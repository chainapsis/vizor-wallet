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
/// timestamp, and presentation deliberately do not participate, so a corrected
/// payload can reuse already-scanned state.
String paymentLinkClaimWalletDirectoryName(VizorPaymentLink link) {
  final identity = sha256
      .convert(
        utf8.encode(
          '${link.network}:${link.address}:${link.mnemonic}:'
          '${link.birthdayHeight}',
        ),
      )
      .toString();
  return '$kPaymentLinkClaimWalletDirectoryPrefix$identity';
}

/// Owns every filesystem and scan operation on a claim's temporary wallet.
class PaymentLinkClaimWallet {
  PaymentLinkClaimWallet(this._ref);

  final Ref _ref;
  final Map<String, Future<void>> _claimSyncs = {};

  Future<void> runClaimSync({
    required VizorPaymentLink link,
    required String dbPath,
  }) {
    final claimId = paymentLinkClaimWalletDirectoryName(link);
    final existing = _claimSyncs[claimId];
    if (existing != null) return existing;
    final future = _runClaimSyncOnce(
      claimId: claimId,
      dbPath: dbPath,
      network: link.network,
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
            );
          },
        );
  }

  Future<bool> syncRetained({
    required PaymentLinkReceivedRecord record,
    required String network,
  }) async {
    final link = record.claimLink;
    final claimTxids = record.claimTxids;
    if (link == null || claimTxids == null || claimTxids.trim().isEmpty) {
      return false;
    }

    final tempWallet = await locate(link);
    if (!await File(tempWallet.dbPath).exists()) return false;

    await runClaimSync(link: link, dbPath: tempWallet.dbPath);
    final accounts = await rust_wallet.listAccounts(
      dbPath: tempWallet.dbPath,
      network: network,
    );
    if (shouldRecreatePaymentLinkClaimWallet(
      accountAddresses: [
        for (final account in accounts) account.unifiedAddress,
      ],
      expectedAddress: link.address,
    )) {
      log(
        'PaymentLinkService: retained claim wallet no longer matches its '
        'Gift Card identity; leaving it recoverable from the stored link',
      );
      return false;
    }
    final transactions = await rust_sync.getTransactionHistory(
      dbPath: tempWallet.dbPath,
      network: network,
      accountUuid: accounts.single.uuid,
      limit: null,
    );
    return paymentLinkClaimTransactionsExpired(
      claimTxids: claimTxids,
      transactions: transactions,
    );
  }

  Future<bool> deleteRetained(PaymentLinkReceivedRecord record) async {
    final link = record.claimLink;
    if (link == null) return true;

    final tempWallet = await locate(link);
    if (!await tempWallet.directory.exists()) return true;
    try {
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
      await _claimSyncs[claimId];
    } catch (_) {
      // A failed scan does not prevent the user-requested preview cleanup.
    }
  }
}

void _zeroize(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
