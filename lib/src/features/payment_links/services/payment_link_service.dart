import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../send/services/sapling_params.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_recovery_store.dart';

final paymentLinkServiceProvider = Provider<PaymentLinkService>((ref) {
  return PaymentLinkService(ref, ref.read(paymentLinkRecoveryStoreProvider));
});

const kPaymentLinkMaxClaimLookbackBlocks = 100000;
const kPaymentLinkShareConfirmationTarget = 10;

/// The ZIP-317 fee for the payment link's expected one-input, one-output
/// shielded claim transaction.
const kPaymentLinkClaimFeeReserveZatoshi = 10000;

BigInt paymentLinkFundingAmountZatoshi(BigInt recipientAmountZatoshi) {
  if (recipientAmountZatoshi <= BigInt.zero) {
    throw ArgumentError.value(
      recipientAmountZatoshi,
      'recipientAmountZatoshi',
      'Payment link amount must be positive.',
    );
  }
  return recipientAmountZatoshi +
      BigInt.from(kPaymentLinkClaimFeeReserveZatoshi);
}

@visibleForTesting
int paymentLinkConfirmationCount({
  required BigInt minedHeight,
  required BigInt chainTipHeight,
}) {
  if (minedHeight <= BigInt.zero || chainTipHeight < minedHeight) return 0;
  return (chainTipHeight - minedHeight + BigInt.one).toInt();
}

/// Rust's broadcast result formats a transaction ID for display, while the
/// transaction-history API currently exposes the same SQLite txid bytes in
/// storage order. Accept both byte orders at this boundary so a mined funding
/// transaction can advance its persisted payment link.
@visibleForTesting
bool paymentLinkTxidsMatch(String first, String second) {
  final normalizedFirst = _normalizeTxid(first);
  final normalizedSecond = _normalizeTxid(second);
  if (normalizedFirst == normalizedSecond) return true;
  if (!_isTransactionIdHex(normalizedFirst) ||
      !_isTransactionIdHex(normalizedSecond)) {
    return false;
  }
  return _reverseHexBytes(normalizedFirst) == normalizedSecond;
}

class PaymentLinkFundingQuote {
  const PaymentLinkFundingQuote({
    required this.recipientAmountZatoshi,
    required this.fundingFeeZatoshi,
    required this.claimFeeReserveZatoshi,
  });

  final BigInt recipientAmountZatoshi;
  final BigInt fundingFeeZatoshi;
  final BigInt claimFeeReserveZatoshi;

  BigInt get cardFeeZatoshi => fundingFeeZatoshi + claimFeeReserveZatoshi;

  BigInt get totalDeductedZatoshi => recipientAmountZatoshi + cardFeeZatoshi;
}

class PaymentLinkFundingProgress {
  const PaymentLinkFundingProgress({
    required this.confirmationCount,
    this.confirmationTarget = kPaymentLinkShareConfirmationTarget,
  });

  final int confirmationCount;
  final int confirmationTarget;

  bool get isReady => confirmationCount >= confirmationTarget;
}

@visibleForTesting
BigInt paymentLinkClaimableAmountZatoshi({
  required BigInt recipientAmountZatoshi,
  required BigInt maxSpendableZatoshi,
}) {
  return maxSpendableZatoshi >= recipientAmountZatoshi
      ? recipientAmountZatoshi
      : BigInt.zero;
}

/// UI-facing boundary for the persisted Payment Link lifecycle.
///
/// Keeping the screen on this small surface makes transaction behavior
/// replaceable in widget tests without weakening the production service.
abstract interface class PaymentLinkOperations {
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  });

  Future<VizorPaymentLink> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  });

  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries();

  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  );

  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  );

  Future<PaymentLinkClaimSession> prepareClaim(VizorPaymentLink link);

  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  );

  Future<void> discardClaimSession(PaymentLinkClaimSession session);

  Future<PaymentLinkClaimResult> claimLink(VizorPaymentLink link);
}

final paymentLinkOperationsProvider = Provider<PaymentLinkOperations>((ref) {
  return ref.watch(paymentLinkServiceProvider);
});

class PaymentLinkClaimSession {
  const PaymentLinkClaimSession({
    required this.link,
    required this.destinationAddress,
    required this.directory,
    required this.dbPath,
    required this.accountUuid,
    required this.totalZatoshi,
    required this.claimableZatoshi,
    required this.feeZatoshi,
  });

  final VizorPaymentLink link;
  final String destinationAddress;
  final Directory directory;
  final String dbPath;
  final String accountUuid;
  final BigInt totalZatoshi;
  final BigInt claimableZatoshi;
  final BigInt feeZatoshi;

  bool get canClaim => claimableZatoshi > BigInt.zero;
}

enum PaymentLinkClaimBroadcastStatus {
  broadcasted,
  pendingBroadcast,
  partialBroadcast,
}

@visibleForTesting
PaymentLinkClaimBroadcastStatus paymentLinkClaimBroadcastStatusFromWire(
  String status,
) {
  return switch (status) {
    'broadcasted' => PaymentLinkClaimBroadcastStatus.broadcasted,
    'pending_broadcast' => PaymentLinkClaimBroadcastStatus.pendingBroadcast,
    'partial_broadcast' => PaymentLinkClaimBroadcastStatus.partialBroadcast,
    _ => throw StateError('Unknown payment link broadcast status: $status'),
  };
}

@visibleForTesting
bool shouldRetainPaymentLinkClaimWallet(
  PaymentLinkClaimBroadcastStatus status,
) {
  return status != PaymentLinkClaimBroadcastStatus.broadcasted;
}

@visibleForTesting
bool shouldRecreatePaymentLinkClaimWallet({
  required List<String> accountAddresses,
  required String expectedAddress,
}) {
  return accountAddresses.length != 1 ||
      accountAddresses.single != expectedAddress;
}

@visibleForTesting
void requireUnlockedPaymentLinkWallet({required bool requiresUnlock}) {
  if (requiresUnlock) {
    throw StateError('Wallet is locked.');
  }
}

@visibleForTesting
int validatePaymentLinkClaimBirthday({
  required int advertisedBirthdayHeight,
  required int currentTipHeight,
}) {
  if (currentTipHeight <= 0) {
    throw StateError('Current chain tip is unavailable.');
  }
  if (advertisedBirthdayHeight > currentTipHeight) {
    throw const FormatException(
      'Payment link birthday is ahead of the current chain tip.',
    );
  }
  final earliestSupportedHeight = max(
    1,
    currentTipHeight - kPaymentLinkMaxClaimLookbackBlocks,
  );
  if (advertisedBirthdayHeight < earliestSupportedHeight) {
    throw const FormatException(
      'Payment link birthday is outside the supported claim window.',
    );
  }
  return advertisedBirthdayHeight;
}

@visibleForTesting
String paymentLinkClaimWalletDirectoryName(VizorPaymentLink link) {
  final identity = sha256
      .convert(utf8.encode('${link.network}:${link.address}:${link.mnemonic}'))
      .toString();
  return '$kPaymentLinkClaimWalletDirectoryPrefix$identity';
}

class PaymentLinkClaimResult {
  const PaymentLinkClaimResult({required this.txids, required this.status});

  final String txids;
  final PaymentLinkClaimBroadcastStatus status;

  bool get isBroadcasted =>
      status == PaymentLinkClaimBroadcastStatus.broadcasted;
}

class PaymentLinkBroadcastPendingException implements Exception {
  const PaymentLinkBroadcastPendingException({
    required this.txids,
    required this.status,
    required this.message,
  });

  final String txids;
  final String status;
  final String message;

  @override
  String toString() => message;
}

class PaymentLinkService implements PaymentLinkOperations {
  PaymentLinkService(this._ref, this._recoveryStore);

  final Ref _ref;
  final PaymentLinkRecoveryStore _recoveryStore;

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    if (sourceAccountUuid.isEmpty) {
      throw StateError('No active account.');
    }
    final fundingAmount = paymentLinkFundingAmountZatoshi(amountZatoshi);
    return _ref
        .read(syncProvider.notifier)
        .runWithAuthoritativeSpendable(
          accountUuid: sourceAccountUuid,
          operation: () async {
            final dbPath = await getWalletDbPath();
            final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
            final estimateAddress = await rust_wallet.getUnifiedAddress(
              dbPath: dbPath,
              network: endpoint.networkName,
              accountUuid: sourceAccountUuid,
            );
            final fundingFee = await rust_sync.estimateFee(
              dbPath: dbPath,
              network: endpoint.networkName,
              accountUuid: sourceAccountUuid,
              toAddress: estimateAddress,
              amountZatoshi: fundingAmount,
              memo: null,
            );
            return PaymentLinkFundingQuote(
              recipientAmountZatoshi: amountZatoshi,
              fundingFeeZatoshi: fundingFee,
              claimFeeReserveZatoshi: BigInt.from(
                kPaymentLinkClaimFeeReserveZatoshi,
              ),
            );
          },
        );
  }

  @override
  Future<VizorPaymentLink> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    if (_ref
        .read(accountProvider.notifier)
        .isHardwareAccount(sourceAccountUuid)) {
      throw StateError(
        'Keystone payment links require the hardware signing flow.',
      );
    }
    final link = await createFundingDraft(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
      presentation: presentation,
    );
    final fundingResult = await _sendShielded(
      fromAccountUuid: sourceAccountUuid,
      toAddress: link.address,
      amountZatoshi: paymentLinkFundingAmountZatoshi(amountZatoshi),
      memo: null,
    );
    await _recoveryStore.markFunded(
      address: link.address,
      fundingTxids: fundingResult.txids,
    );

    unawaited(_ref.read(syncProvider.notifier).refreshAfterSend());
    _requireFullyBroadcasted(fundingResult);
    return link;
  }

  /// Creates the bearer-secret account and persists its recovery record before
  /// any funding proposal can be signed or broadcast.
  Future<VizorPaymentLink> createFundingDraft({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    if (sourceAccountUuid.isEmpty) {
      throw StateError('No active account.');
    }
    if (amountZatoshi <= BigInt.zero) {
      throw ArgumentError.value(
        amountZatoshi,
        'amountZatoshi',
        'Payment link amount must be positive.',
      );
    }
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final paymentAccount = await rust_wallet.previewNewSoftwareAccount(
      network: endpoint.networkName,
    );
    final ephemeralAddress = paymentAccount.unifiedAddress;
    if (ephemeralAddress.isEmpty) {
      throw StateError('Payment link account was created without an address.');
    }

    final birthdayHeight = await _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .getLatestBlockHeight();
    final link = VizorPaymentLink(
      network: endpoint.networkName,
      address: ephemeralAddress,
      amountZatoshi: amountZatoshi,
      mnemonic: paymentAccount.mnemonic,
      birthdayHeight: birthdayHeight.toInt(),
      label: 'Payment link',
      createdAt: DateTime.now(),
      presentation: presentation,
    );
    await _recoveryStore.saveDraft(
      link: link,
      sourceAccountUuid: sourceAccountUuid,
    );
    return link;
  }

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() {
    return _recoveryStore.load();
  }

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) {
    return _recoveryStore.markShared(address: link.address);
  }

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    final needsHistory = records
        .where((record) => record.state == PaymentLinkRecoveryState.funded)
        .toList();
    if (needsHistory.isEmpty) {
      return {
        for (final record in records)
          record.link.address: PaymentLinkFundingProgress(
            confirmationCount: record.state == PaymentLinkRecoveryState.shared
                ? kPaymentLinkShareConfirmationTarget
                : 0,
          ),
      };
    }
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final dbPath = await getWalletDbPath();
    final transactionsByAccount = <String, List<rust_sync.TransactionInfo>>{};
    for (final accountUuid
        in needsHistory.map((record) => record.sourceAccountUuid).toSet()) {
      transactionsByAccount[accountUuid] = await rust_sync
          .getTransactionHistory(
            dbPath: dbPath,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            limit: null,
          );
    }
    final cachedTip = _ref.read(syncProvider).value?.chainTipHeight ?? 0;
    final chainTipHeight = cachedTip > 0
        ? BigInt.from(cachedTip)
        : await _ref
              .read(rpcEndpointFailoverProvider.notifier)
              .getLatestBlockHeight();
    return {
      for (final record in records)
        record.link.address: record.state == PaymentLinkRecoveryState.shared
            ? const PaymentLinkFundingProgress(
                confirmationCount: kPaymentLinkShareConfirmationTarget,
              )
            : _fundingProgressForRecord(
                record: record,
                transactions:
                    transactionsByAccount[record.sourceAccountUuid] ?? const [],
                chainTipHeight: chainTipHeight,
              ),
    };
  }

  PaymentLinkFundingProgress _fundingProgressForRecord({
    required PaymentLinkRecoveryRecord record,
    required List<rust_sync.TransactionInfo> transactions,
    required BigInt chainTipHeight,
  }) {
    final rawTxids = record.fundingTxids;
    if (record.state == PaymentLinkRecoveryState.draft ||
        rawTxids == null ||
        rawTxids.trim().isEmpty) {
      return const PaymentLinkFundingProgress(confirmationCount: 0);
    }
    final fundingTxids = rawTxids
        .split(',')
        .map(_normalizeTxid)
        .where((txid) => txid.isNotEmpty)
        .toSet();
    if (fundingTxids.isEmpty) {
      return const PaymentLinkFundingProgress(confirmationCount: 0);
    }
    final minedHeights = <String, BigInt>{};
    for (final transaction in transactions) {
      final txid = _normalizeTxid(transaction.txidHex);
      if (transaction.minedHeight <= BigInt.zero) continue;
      for (final fundingTxid in fundingTxids) {
        if (paymentLinkTxidsMatch(fundingTxid, txid)) {
          minedHeights[fundingTxid] = transaction.minedHeight;
        }
      }
    }
    final allFundingTransactionsMined = minedHeights.keys.toSet().containsAll(
      fundingTxids,
    );
    final minedHeight = allFundingTransactionsMined
        ? minedHeights.values.reduce(
            (latest, height) => height > latest ? height : latest,
          )
        : BigInt.zero;
    return PaymentLinkFundingProgress(
      confirmationCount: paymentLinkConfirmationCount(
        minedHeight: minedHeight,
        chainTipHeight: chainTipHeight,
      ),
    );
  }

  Future<PaymentLinkRecoveryRecord> setCreatedLinkArchived(
    VizorPaymentLink link, {
    required bool archived,
  }) {
    return _recoveryStore.setArchived(
      address: link.address,
      archived: archived,
    );
  }

  @override
  Future<PaymentLinkClaimSession> prepareClaim(VizorPaymentLink link) async {
    final receiverState = _ref.read(accountProvider).value;
    final receiverAddress = receiverState?.activeAddress;
    if (receiverState?.activeAccountUuid == null ||
        receiverAddress == null ||
        receiverAddress.isEmpty) {
      throw StateError('No active receive account.');
    }
    return _prepareSpend(link: link, destinationAddress: receiverAddress);
  }

  Future<PaymentLinkClaimSession> _prepareSpend({
    required VizorPaymentLink link,
    required String destinationAddress,
  }) async {
    await _requireShieldedAddress(destinationAddress);
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    if (link.network != endpoint.networkName) {
      throw StateError(
        'Payment link is for ${link.network}, but this wallet is using '
        '${endpoint.networkName}.',
      );
    }

    final currentTipHeight = await _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .getLatestBlockHeight();
    final claimBirthdayHeight = validatePaymentLinkClaimBirthday(
      advertisedBirthdayHeight: link.birthdayHeight,
      currentTipHeight: currentTipHeight.toInt(),
    );

    final tempWallet = await _createOrOpenTemporaryWalletDb(link);
    var deleteOnError = !tempWallet.existed;
    try {
      final String importedAddress;
      final String importedAccountUuid;
      if (tempWallet.existed) {
        List<rust_wallet.AccountInfo>? accounts;
        try {
          accounts = await rust_wallet.listAccounts(
            dbPath: tempWallet.dbPath,
            network: endpoint.networkName,
          );
        } catch (e, st) {
          log(
            'PaymentLinkService: reopening payment-link claim wallet failed; '
            'recreating it: $e\n$st',
          );
        }
        if (accounts == null ||
            shouldRecreatePaymentLinkClaimWallet(
              accountAddresses: [
                for (final account in accounts) account.unifiedAddress,
              ],
              expectedAddress: link.address,
            )) {
          if (accounts != null) {
            log(
              'PaymentLinkService: recreating incomplete payment-link claim '
              'wallet with ${accounts.length} account(s)',
            );
          }
          deleteOnError = true;
          await _resetTemporaryWalletDb(tempWallet.directory);
          final imported = await _importPaymentLinkClaimAccount(
            link: link,
            birthdayHeight: claimBirthdayHeight,
            dbPath: tempWallet.dbPath,
            network: endpoint.networkName,
          );
          importedAddress = imported.address;
          importedAccountUuid = imported.accountUuid;
        } else {
          importedAddress = accounts.single.unifiedAddress;
          importedAccountUuid = accounts.single.uuid;
        }
      } else {
        final imported = await _importPaymentLinkClaimAccount(
          link: link,
          birthdayHeight: claimBirthdayHeight,
          dbPath: tempWallet.dbPath,
          network: endpoint.networkName,
        );
        importedAddress = imported.address;
        importedAccountUuid = imported.accountUuid;
      }
      if (importedAddress != link.address) {
        throw const FormatException(
          'Payment link address does not match its recovery phrase.',
        );
      }

      await _runBlockingSync(dbPath: tempWallet.dbPath);
      final balance = await rust_sync.getBalance(
        dbPath: tempWallet.dbPath,
        network: endpoint.networkName,
        accountUuid: importedAccountUuid,
      );
      var claimableZatoshi = BigInt.zero;
      var feeZatoshi = BigInt.zero;
      try {
        final estimate = await rust_sync.estimateSendMaxMinConfirmations(
          dbPath: tempWallet.dbPath,
          network: endpoint.networkName,
          accountUuid: importedAccountUuid,
          toAddress: destinationAddress,
        );
        claimableZatoshi = paymentLinkClaimableAmountZatoshi(
          recipientAmountZatoshi: link.amountZatoshi,
          maxSpendableZatoshi: estimate.amountZatoshi,
        );
        feeZatoshi = estimate.feeZatoshi;
      } catch (e) {
        final message = e.toString().toLowerCase();
        if (!message.contains('insufficient balance')) {
          rethrow;
        }
      }

      return PaymentLinkClaimSession(
        link: link,
        destinationAddress: destinationAddress,
        directory: tempWallet.directory,
        dbPath: tempWallet.dbPath,
        accountUuid: importedAccountUuid,
        totalZatoshi: balance.total,
        claimableZatoshi: claimableZatoshi,
        feeZatoshi: feeZatoshi,
      );
    } catch (_) {
      if (deleteOnError) {
        await _deleteTemporaryWalletDb(tempWallet.directory);
      }
      rethrow;
    }
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    return _broadcastPreparedSpend(session);
  }

  Future<PaymentLinkClaimResult> _broadcastPreparedSpend(
    PaymentLinkClaimSession session,
  ) async {
    if (!session.canClaim) {
      throw StateError('Payment link has no spendable shielded balance yet.');
    }
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    if (session.link.network != endpoint.networkName) {
      throw StateError(
        'Payment link is for ${session.link.network}, but this wallet is '
        'using ${endpoint.networkName}.',
      );
    }
    final estimate = await rust_sync.estimateSendMaxMinConfirmations(
      dbPath: session.dbPath,
      network: endpoint.networkName,
      accountUuid: session.accountUuid,
      toAddress: session.destinationAddress,
    );
    if (estimate.amountZatoshi < session.link.amountZatoshi) {
      throw StateError(
        'Payment link does not yet have enough spendable shielded balance.',
      );
    }

    _requireWalletUnlocked();
    final sendResult = await _sendShielded(
      dbPath: session.dbPath,
      fromAccountUuid: session.accountUuid,
      toAddress: session.destinationAddress,
      amountZatoshi: session.link.amountZatoshi,
      memo: null,
      mnemonic: session.link.mnemonic,
      useMinConfirmations: true,
    );
    final claimResult = PaymentLinkClaimResult(
      txids: sendResult.txids,
      status: paymentLinkClaimBroadcastStatusFromWire(sendResult.status),
    );
    if (!shouldRetainPaymentLinkClaimWallet(claimResult.status)) {
      await discardClaimSession(session);
    }
    unawaited(_ref.read(syncProvider.notifier).refreshAfterSend());
    return claimResult;
  }

  @override
  Future<PaymentLinkClaimResult> claimLink(VizorPaymentLink link) async {
    final session = await prepareClaim(link);
    return claimPreparedLink(session);
  }

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) =>
      _deleteTemporaryWalletDb(session.directory);

  Future<rust_sync.ExecuteProposalResult> _sendShielded({
    String? dbPath,
    required String fromAccountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
    String? mnemonic,
    bool useMinConfirmations = false,
  }) async {
    await _requireShieldedAddress(toAddress);
    final walletDbPath = dbPath ?? await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final sendFlowId = _newSendFlowId();
    final proposal = useMinConfirmations
        ? await rust_sync.proposeSendMinConfirmations(
            dbPath: walletDbPath,
            network: endpoint.networkName,
            accountUuid: fromAccountUuid,
            sendFlowId: sendFlowId,
            toAddress: toAddress,
            amountZatoshi: amountZatoshi,
            memo: memo,
          )
        : await rust_sync.proposeSend(
            dbPath: walletDbPath,
            network: endpoint.networkName,
            accountUuid: fromAccountUuid,
            sendFlowId: sendFlowId,
            toAddress: toAddress,
            amountZatoshi: amountZatoshi,
            memo: memo,
          );

    try {
      final result = await _executeProposal(
        dbPath: walletDbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        accountUuid: fromAccountUuid,
        proposalId: proposal.proposalId,
        sendFlowId: sendFlowId,
        needsSaplingParams: proposal.needsSaplingParams,
        mnemonic: mnemonic,
      );
      paymentLinkClaimBroadcastStatusFromWire(result.status);
      return result;
    } catch (e) {
      try {
        await rust_sync.discardProposal(
          proposalId: proposal.proposalId,
          sendFlowId: sendFlowId,
        );
      } catch (discardError) {
        log('PaymentLinkService: discardProposal failed: $discardError');
      }
      rethrow;
    }
  }

  Future<rust_sync.ExecuteProposalResult> _executeProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String accountUuid,
    required BigInt proposalId,
    required String sendFlowId,
    required bool needsSaplingParams,
    String? mnemonic,
  }) async {
    var saplingParams = await loadSaplingParamsStatus();
    if (needsSaplingParams && !saplingParams.complete) {
      await downloadMissingSaplingParams(
        saplingParams,
        log: (message) => log('PaymentLinkService: $message'),
      );
      saplingParams = await loadSaplingParamsStatus();
    }

    _requireWalletUnlocked();

    if (Platform.isMacOS && mnemonic == null) {
      final password = _ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      return rust_sync.executeProposalWithMacosStoredMnemonic(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
        password: password,
        spendParamsPath: needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: needsSaplingParams ? saplingParams.outputPath : null,
      );
    }

    final mnemonicBytes = mnemonic == null
        ? await _ref
              .read(accountProvider.notifier)
              .getMnemonicBytesForAccount(accountUuid)
        : Uint8List.fromList(utf8.encode(mnemonic));
    if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
      throw StateError('Mnemonic not found for payment link account.');
    }
    late final Future<rust_sync.ExecuteProposalResult> result;
    try {
      result = rust_sync.executeProposal(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
        mnemonicBytes: mnemonicBytes,
        spendParamsPath: needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: needsSaplingParams ? saplingParams.outputPath : null,
      );
    } finally {
      _zeroize(mnemonicBytes);
    }
    return result;
  }

  Future<void> _runBlockingSync({required String dbPath}) async {
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    await _ref
        .read(syncProvider.notifier)
        .runWithExclusiveRustSync(
          () => rust_sync.runFullSyncBlocking(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            mode: 1,
          ),
        );
  }

  Future<({Directory directory, String dbPath, bool existed})>
  _createOrOpenTemporaryWalletDb(VizorPaymentLink link) async {
    final supportDir = await getWalletSupportDirectory();
    final separator = Platform.pathSeparator;
    final directory = Directory(
      '${supportDir.path}$separator${paymentLinkClaimWalletDirectoryName(link)}',
    );
    final dbPath = '${directory.path}${separator}zcash_wallet.db';
    final existed = await File(dbPath).exists();
    await directory.create(recursive: true);
    return (directory: directory, dbPath: dbPath, existed: existed);
  }

  Future<({String address, String accountUuid})>
  _importPaymentLinkClaimAccount({
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

  Future<void> _resetTemporaryWalletDb(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  }

  void _requireFullyBroadcasted(rust_sync.ExecuteProposalResult result) {
    if (paymentLinkClaimBroadcastStatusFromWire(result.status) ==
        PaymentLinkClaimBroadcastStatus.broadcasted) {
      return;
    }
    throw PaymentLinkBroadcastPendingException(
      txids: result.txids,
      status: result.status,
      message:
          result.message ??
          'Payment link funding transaction is waiting to be broadcast.',
    );
  }

  Future<void> _deleteTemporaryWalletDb(Directory directory) async {
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

  Future<void> _requireShieldedAddress(String address) async {
    final validation = await rust_sync.validateAddress(address: address);
    if (!validation.isValid ||
        (validation.addressType != 'unified' &&
            validation.addressType != 'sapling')) {
      throw StateError('Payment links only support shielded addresses.');
    }
  }

  void _requireWalletUnlocked() {
    requireUnlockedPaymentLinkWallet(
      requiresUnlock: _ref.read(appSecurityProvider).requiresUnlock,
    );
  }

  String _newSendFlowId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  void _zeroize(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }
}

String _normalizeTxid(String txid) {
  final normalized = txid.trim().toLowerCase();
  return normalized.startsWith('0x') ? normalized.substring(2) : normalized;
}

bool _isTransactionIdHex(String value) {
  return value.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(value);
}

String _reverseHexBytes(String value) {
  final reversed = StringBuffer();
  for (var index = value.length; index > 0; index -= 2) {
    reversed.write(value.substring(index - 2, index));
  }
  return reversed.toString();
}
