/// Part of `payment_link_service.dart`: the temporary wallet a Gift Card claim
/// is scanned in.
///
/// A claim imports the link's mnemonic into a throwaway wallet DB under its own
/// directory, scans it, and deletes it again. That directory lifecycle plus the
/// per-claim scan de-duplication is the whole concern here, so it is kept out of
/// the service file, which only orchestrates funding and claiming over this
/// small surface. It stays a `part` rather than its own library because it needs
/// the `@visibleForTesting` claim math and the service's own claim types.
part of 'payment_link_service.dart';

/// Claim databases are cached by the fields that determine the recovered
/// account and its scan range. Share-payload fields such as amount, label,
/// address, timestamp, and presentation deliberately do not participate, so a
/// corrected payload can reuse already-scanned state.
///
/// The network is also kept outside the hash, as a readable name segment, so a
/// cleanup sweep can scope itself to one network.
String paymentLinkClaimWalletDirectoryName(VizorPaymentLink link) {
  final identity = sha256
      .convert(
        utf8.encode('${link.network}:${link.mnemonic}:${link.birthdayHeight}'),
      )
      .toString();
  return paymentLinkClaimWalletDirectoryNameFor(
    network: link.network.trim(),
    identityHash: identity,
  );
}

/// Owns every filesystem and scan operation on a claim's temporary wallet.
class PaymentLinkClaimWallet {
  PaymentLinkClaimWallet(this._ref);

  final Ref _ref;
  final Map<String, Future<void>> _claimSyncs = {};
  int _checkCancellationEpoch = 0;
  final Map<String, Future<rust_sync.ApiGiftCardCheckProgress>> _claimChecks =
      {};

  Future<rust_sync.ApiGiftCardCheckProgress> runClaimCheck({
    required VizorPaymentLink link,
    required String dbPath,
    bool allowResubmit = false,
  }) {
    final claimId = paymentLinkClaimWalletDirectoryName(link);
    final existing = _claimChecks[claimId];
    if (existing != null) return existing;
    final unregister = _ref
        .read(paymentLinkClaimCoordinatorProvider)
        .registerCheckCancellation(() => cancelAllChecks());
    late final Future<rust_sync.ApiGiftCardCheckProgress> tracked;
    tracked =
        _runClaimCheckOnce(
          link: link,
          dbPath: dbPath,
          allowResubmit: allowResubmit,
        ).whenComplete(() {
          unregister();
          if (identical(_claimChecks[claimId], tracked)) {
            _claimChecks.remove(claimId);
            _ref.read(giftCardCheckProgressProvider.notifier).clear(link);
          }
        });
    _claimChecks[claimId] = tracked;
    return tracked;
  }

  Future<rust_sync.ApiGiftCardCheckProgress> _runClaimCheckOnce({
    required VizorPaymentLink link,
    required String dbPath,
    required bool allowResubmit,
  }) async {
    final coordinator = _ref.read(paymentLinkClaimCoordinatorProvider);
    final generation = coordinator.beginPreparation();
    final epoch = _checkCancellationEpoch;
    return _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .runWithEndpointFallback<rust_sync.ApiGiftCardCheckProgress>(
          operation: 'Gift Card check',
          action: (endpoint) async {
            coordinator.requirePreparation(generation);
            if (epoch != _checkCancellationEpoch ||
                !_ref
                    .read(paymentLinkClaimCoordinatorProvider)
                    .acceptsPreparation ||
                _ref.read(appSecurityProvider).requiresUnlock) {
              throw StateError('Gift Card preparation is paused.');
            }
            if (endpoint.networkName != link.network) {
              throw StateError('Gift Card network changed.');
            }
            try {
              final failover = _ref.read(rpcEndpointFailoverProvider);
              rust_sync.ApiGiftCardCheckProgress? last;
              var paused = false;
              await for (final event in rust_sync.runPaymentLinkClaimCheck(
                claimId: paymentLinkClaimWalletDirectoryName(link),
                dbPath: dbPath,
                lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
                // Capability fallback also works for custom endpoints. Preserve
                // configured transport routing; these are public chain queries.
                fallbackUrls:
                    {
                          ...failover.fallbackCandidates
                              .where((e) => e.networkName == link.network)
                              .map((e) => e.normalizedLightwalletdUrl),
                          ...rpcEndpointPresetsForNetwork(link.network).map(
                            (e) => RpcEndpointConfig(
                              networkName: link.network,
                              lightwalletdUrl: e.url,
                            ).normalizedLightwalletdUrl,
                          ),
                        }
                        .where(
                          (url) => url != endpoint.normalizedLightwalletdUrl,
                        )
                        .toList(),
                network: link.network,
                allowResubmit: allowResubmit,
              )) {
                if (epoch != _checkCancellationEpoch ||
                    _ref.read(appSecurityProvider).requiresUnlock ||
                    !_ref
                        .read(paymentLinkClaimCoordinatorProvider)
                        .acceptsPreparation) {
                  rust_sync.cancelPaymentLinkClaimSync(
                    claimId: paymentLinkClaimWalletDirectoryName(link),
                  );
                  paused = true;
                }
                if (paused) continue;
                last = event;
                _ref
                    .read(giftCardCheckProgressProvider.notifier)
                    .update(link, event);
              }
              coordinator.requirePreparation(generation);
              if (paused || epoch != _checkCancellationEpoch) {
                throw StateError('Gift Card preparation is paused.');
              }
              if (last == null || !last.complete) {
                throw StateError('Gift Card check did not complete.');
              }
              return last;
            } catch (_) {
              // A late transport error after pause must not start endpoint
              // health probes or a fallback scan, even after a quick resume.
              coordinator.requirePreparation(generation);
              rethrow;
            }
          },
        );
  }

  Future<void> cancelAllChecks() async {
    _checkCancellationEpoch++;
    final pending = _claimChecks.entries.toList();
    if (pending.isEmpty) return;
    void cancel() {
      for (final entry in pending) {
        rust_sync.cancelPaymentLinkClaimSync(claimId: entry.key);
      }
    }

    cancel();
    // Dispatch to Rust can race the first cancellation. Keep signalling until
    // accepted native work has actually unwound, before any file deletion.
    final timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => cancel(),
    );
    try {
      await Future.wait(
        pending.map((entry) async {
          try {
            await entry.value;
          } catch (_) {}
        }),
      );
    } finally {
      timer.cancel();
    }
  }

  /// Verifies the cached wallet and advertised address against the recovery
  /// phrase, accepting current and legacy default-address representations.
  Future<bool> matchesLink({
    required VizorPaymentLink link,
    required List<rust_wallet.AccountInfo> accounts,
  }) async {
    if (accounts.length != 1) return false;
    try {
      await rust_wallet.validateGiftAddress(
        mnemonic: link.mnemonic,
        network: link.network,
        address: accounts.single.unifiedAddress,
      );
      final advertisedAddress = link.knownAddress;
      if (advertisedAddress != null) {
        await rust_wallet.validateGiftAddress(
          mnemonic: link.mnemonic,
          network: link.network,
          address: advertisedAddress,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> runClaimSync({
    required VizorPaymentLink link,
    required String dbPath,
    bool allowResubmit = false,
  }) {
    final claimId = paymentLinkClaimWalletDirectoryName(link);
    final existing = _claimSyncs[claimId];
    if (existing != null) return existing;
    final future = _runClaimSyncOnce(
      claimId: claimId,
      dbPath: dbPath,
      network: link.network,
      allowResubmit: allowResubmit,
    );
    _claimSyncs[claimId] = future;
    return future.whenComplete(() {
      if (identical(_claimSyncs[claimId], future)) {
        _claimSyncs.remove(claimId);
      }
    });
  }

  Future<void> _runClaimSyncOnce({
    required String claimId,
    required String dbPath,
    required String network,
    required bool allowResubmit,
  }) {
    return _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .runWithEndpointFallback<void>(
          operation: 'Gift Card claim sync',
          action: (endpoint) {
            if (endpoint.networkName != network) {
              throw StateError(
                'Payment link is for $network, but this wallet is using '
                '${endpoint.networkName}.',
              );
            }
            return rust_sync.runPaymentLinkClaimSync(
              claimId: claimId,
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: network,
              allowResubmit: allowResubmit,
            );
          },
        );
  }

  Future<PaymentLinkAvailability?> syncRetained({
    required PaymentLinkReceivedRecord record,
    required String network,
    required bool allowResubmit,
  }) async {
    final link = record.claimLink;
    final claimTxids = record.claimTxids;
    if (link == null || claimTxids == null || claimTxids.trim().isEmpty) {
      return null;
    }

    final tempWallet = await locate(link);
    if (!await File(tempWallet.dbPath).exists()) return null;

    final fastConfirmations = await rust_sync.getPaymentLinkClaimConfirmations(
      dbPath: tempWallet.dbPath,
      claimTxids: claimTxids,
    );
    if (fastConfirmations != null) {
      await runClaimCheck(
        link: link,
        dbPath: tempWallet.dbPath,
        allowResubmit: allowResubmit,
      );
    } else {
      await runClaimSync(
        link: link,
        dbPath: tempWallet.dbPath,
        allowResubmit: allowResubmit,
      );
    }
    final accounts = await rust_wallet.listAccounts(
      dbPath: tempWallet.dbPath,
      network: network,
    );
    if (!await matchesLink(link: link, accounts: accounts)) {
      log(
        'PaymentLinkService: retained claim wallet no longer matches its '
        'Gift Card identity; leaving it recoverable from the stored link',
      );
      return null;
    }
    final transactions = await rust_sync.getTransactionHistory(
      dbPath: tempWallet.dbPath,
      network: network,
      accountUuid: accounts.single.uuid,
      limit: null,
    );
    final fundingTime = paymentLinkFundingCreatedAt(
      recipientAmountZatoshi: link.amountZatoshi,
      transactions: transactions,
    );
    if (record.isCreatedAtProvisional && fundingTime != null) {
      await _ref
          .read(paymentLinkReceivedStoreProvider)
          .resolveProvisionalCreatedAt(
            address: record.address,
            createdAt: fundingTime,
          );
    }
    final evidence = await rust_sync.getPaymentLinkSpendEvidence(
      dbPath: tempWallet.dbPath,
      accountUuid: accounts.single.uuid,
      claimTxids: claimTxids,
    );
    final settled = paymentLinkClaimFailureSettled(
      claimTxids: claimTxids,
      transactions: transactions,
      conflictedTxids: evidence.conflictedTxids,
      verifiedHeight: evidence.verifiedHeight,
    );
    if (!settled) return null;
    return evidence.allFundsSpentElsewhere
        ? PaymentLinkAvailability.claimedElsewhere
        : PaymentLinkAvailability.failed;
  }

  /// Reads the link's own wallet history so a funding broadcast whose result
  /// was lost can be matched against the chain.
  ///
  /// The funding transaction is invisible from the source account's history —
  /// nothing there records which address it paid — but it is a plain receive
  /// in the Gift Card's own wallet. That wallet normally exists only once
  /// somebody claims the Card, so this creates and imports it if needed, and
  /// leaves it in place for the claim that may still follow.
  Future<List<rust_sync.TransactionInfo>> loadFundingHistory(
    VizorPaymentLink link,
  ) async {
    final tempWallet = await createOrOpen(link);
    String? accountUuid;
    if (tempWallet.existed) {
      List<rust_wallet.AccountInfo>? accounts;
      try {
        accounts = await rust_wallet.listAccounts(
          dbPath: tempWallet.dbPath,
          network: link.network,
        );
      } catch (e) {
        log('PaymentLinkClaimWallet: reopening the claim wallet failed: $e');
      }
      if (accounts != null &&
          await matchesLink(link: link, accounts: accounts)) {
        accountUuid = accounts.single.uuid;
      } else {
        // An import that died between creating the file and the account, or a
        // wallet for another identity: recreate, as the claim path does.
        await resetDb(tempWallet.directory);
        await tempWallet.directory.create(recursive: true);
      }
    }
    if (accountUuid == null) {
      final imported = await importClaimAccount(
        link: link,
        birthdayHeight: link.birthdayHeight,
        dbPath: tempWallet.dbPath,
        network: link.network,
      );
      accountUuid = imported.accountUuid;
    }
    await runClaimSync(link: link, dbPath: tempWallet.dbPath);
    return rust_sync.getTransactionHistory(
      dbPath: tempWallet.dbPath,
      network: link.network,
      accountUuid: accountUuid,
      limit: null,
    );
  }

  Future<bool> deleteRetained(PaymentLinkReceivedRecord record) async {
    final link = record.claimLink;
    if (link == null) return true;

    final tempWallet = await locate(link);
    if (!await tempWallet.directory.exists()) return true;
    try {
      await cancelClaimSync(link);
      await tempWallet.directory.delete(recursive: true);
      return true;
    } catch (error, stackTrace) {
      log(
        'PaymentLinkService: failed to delete confirmed claim wallet: '
        '$error\n$stackTrace',
      );
      return false;
    }
  }

  Future<({Directory directory, String dbPath})> locate(
    VizorPaymentLink link,
  ) async {
    final supportDir = await getWalletSupportDirectory();
    final separator = Platform.pathSeparator;
    // Pre-v2 wallets included the address in their identity. Keep using their
    // DB (including local submission metadata and SQLite sidecars) in place.
    // Prefer it even if a newer cache also exists: a rescan of that cache cannot
    // replace the original attempt's locally recorded transaction evidence.
    final legacyAddress = link.knownAddress;
    if (legacyAddress != null) {
      final legacyIdentity = sha256.convert(
        utf8.encode(
          '${link.network}:$legacyAddress:${link.mnemonic}:'
          '${link.birthdayHeight}',
        ),
      );
      final legacyName = paymentLinkClaimWalletDirectoryNameFor(
        network: link.network.trim(),
        identityHash: legacyIdentity.toString(),
      );
      final legacyDirectory = Directory(
        '${supportDir.path}$separator$legacyName',
      );
      final legacyDbPath = '${legacyDirectory.path}${separator}zcash_wallet.db';
      if (await File(legacyDbPath).exists()) {
        return (directory: legacyDirectory, dbPath: legacyDbPath);
      }
    }
    final directory = Directory(
      '${supportDir.path}$separator${paymentLinkClaimWalletDirectoryName(link)}',
    );
    return (
      directory: directory,
      dbPath: '${directory.path}${separator}zcash_wallet.db',
    );
  }

  Future<({Directory directory, String dbPath, bool existed})> createOrOpen(
    VizorPaymentLink link,
  ) async {
    final location = await locate(link);
    final existed = await File(location.dbPath).exists();
    await location.directory.create(recursive: true);
    return (
      directory: location.directory,
      dbPath: location.dbPath,
      existed: existed,
    );
  }

  Future<({String address, String accountUuid})> importClaimAccount({
    required VizorPaymentLink link,
    required int birthdayHeight,
    required String dbPath,
    required String network,
  }) async {
    final imported = await rust_wallet.importWallet(
      mnemonic: link.mnemonic,
      bip39Passphrase: '',
      birthdayHeight: BigInt.from(birthdayHeight),
      network: network,
      dbPath: dbPath,
      accountName: 'Payment link claim',
    );
    return (
      address: imported.unifiedAddress,
      accountUuid: imported.accountUuid,
    );
  }

  Future<void> resetDb(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  }

  Future<void> deleteDb(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e, st) {
      log(
        'PaymentLinkService: failed to delete temporary payment-link DB '
        '${directory.path}: $e\n$st',
      );
    }
  }

  /// Stops a running claim scan for [link] and waits for it to unwind, so a
  /// caller can delete the wallet directory underneath it.
  Future<void> cancelClaimSync(VizorPaymentLink link) async {
    final claimId = paymentLinkClaimWalletDirectoryName(link);
    rust_sync.cancelPaymentLinkClaimSync(claimId: claimId);
    try {
      await _claimChecks[claimId];
      await _claimSyncs[claimId];
    } catch (_) {
      // A failed scan does not prevent the user-requested preview cleanup.
    }
  }
}

void _zeroize(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
