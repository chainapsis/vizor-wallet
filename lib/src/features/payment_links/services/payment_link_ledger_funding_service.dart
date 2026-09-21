import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_service.dart';
import 'payment_link_hardware_signing_service.dart';
import 'payment_link_recovery_store.dart';

final paymentLinkLedgerFundingServiceProvider =
    Provider<PaymentLinkLedgerFundingService>((ref) {
      return PaymentLinkLedgerFundingService(
        hardware: ref.watch(paymentLinkHardwareSigningServiceProvider),
        operations: ref.watch(ledgerSignedOperationServiceProvider),
        recovery: ref.watch(paymentLinkRecoveryStoreProvider),
        lifecycle: ref.watch(ledgerOperationLifecycleProvider),
        accountExists: (uuid) =>
            ref
                .read(accountProvider)
                .value
                ?.accounts
                .any((account) => account.uuid == uuid && account.isLedger) ??
            false,
        settleProposal: (draft, status) {
          if (status == null ||
              status == 'broadcast_unknown' ||
              status == 'broadcasted_storage_failed') {
            return rust_sync.retainProposalLockUntilExpiry(
              proposalId: draft.proposalId,
              sendFlowId: draft.sendFlowId,
            );
          }
          return rust_sync.discardProposal(
            proposalId: draft.proposalId,
            sendFlowId: draft.sendFlowId,
          );
        },
        refresh: () => ref.read(syncProvider.notifier).refreshAfterSend(),
        currentChainHeight: () =>
            ref.read(syncProvider).value?.chainTipHeight ?? 0,
      );
    });

int _unknownChainHeight() => 0;

class LedgerGiftFundingTerminalException implements Exception {
  const LedgerGiftFundingTerminalException();

  static const message =
      'This gift card transaction expired or was rejected. Go back to create a new gift card.';

  @override
  String toString() => message;
}

/// Reuses Gift Card draft/proof storage but uses the Ledger signed outbox.
/// No UI callback owns persistence or acknowledgement.
class PaymentLinkLedgerFundingService {
  const PaymentLinkLedgerFundingService({
    required this.hardware,
    required this.operations,
    required this.recovery,
    required this.lifecycle,
    required this.accountExists,
    required this.settleProposal,
    required this.refresh,
    this.currentChainHeight = _unknownChainHeight,
  });
  final PaymentLinkHardwareSigningService hardware;
  final LedgerSignedOperationService operations;
  final PaymentLinkRecoveryStore recovery;
  final LedgerOperationLifecycle lifecycle;
  final bool Function(String uuid) accountExists;
  final Future<void> Function(PaymentLinkHardwarePcztDraft, String? status)
  settleProposal;
  final Future<void> Function() refresh;

  /// The in-memory sync tip used to date a submission; `0` when unknown.
  final int Function() currentChainHeight;

  void _requireAccount(String accountUuid) {
    if (!accountExists(accountUuid)) {
      throw StateError('The Ledger account is no longer available.');
    }
  }

  String operationId(String accountUuid, String address) =>
      newLedgerSignedOperationId(
        kind: LedgerSignedOperationKind.giftCard,
        accountUuid: accountUuid,
        externalRef: address,
      );

  Future<PaymentLinkHardwarePcztDraft> prepare({
    required String accountUuid,
    required BigInt amountZatoshi,
    PaymentLinkPresentation? presentation,
  }) => lifecycle.run(() {
    _requireAccount(accountUuid);
    return hardware.createFundingPczt(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: accountUuid,
      presentation: presentation,
    );
  });

  Future<List<int>> prove({
    required String accountUuid,
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => lifecycle.run(() {
    _requireAccount(accountUuid);
    return hardware.addProofsForSigning(
      draft: draft,
      spendParamsPath: spendParamsPath,
      outputParamsPath: outputParamsPath,
    );
  });

  Future<void> discard(
    String accountUuid,
    PaymentLinkHardwarePcztDraft draft,
  ) => lifecycle.run(() async {
    if (!accountExists(accountUuid)) return;
    await hardware.discardPcztDraft(draft: draft);
    await refresh();
  });

  Future<PaymentLinkHardwareFundingResult> submit({
    required String accountUuid,
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> proofs,
    required List<int> signatures,
    required void Function() onCheckpointed,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => lifecycle.run(() async {
    _requireAccount(accountUuid);
    await operations.checkpoint(
      operationId: operationId(accountUuid, draft.link.address),
      accountUuid: accountUuid,
      kind: LedgerSignedOperationKind.giftCard,
      externalRef: draft.link.address,
      pcztWithProofsBytes: proofs,
      pcztWithSignaturesBytes: signatures,
    );
    onCheckpointed();
    // The signed outbox owns recovery; retain both the secret and the input
    // reservation until the broadcast result determines safe settlement.
    return resume(
      accountUuid: accountUuid,
      address: draft.link.address,
      draft: draft,
      spendParamsPath: spendParamsPath,
      outputParamsPath: outputParamsPath,
    );
  });

  Future<PaymentLinkHardwareFundingResult> resume({
    required String accountUuid,
    required String address,
    PaymentLinkHardwarePcztDraft? draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => lifecycle.run(() async {
    _requireAccount(accountUuid);
    String? settlementStatus;
    try {
      final id = operationId(accountUuid, address);
      final entries = await operations.list();
      final entry = entries
          .where((entry) => entry.operationId == id)
          .firstOrNull;
      if (entry == null) {
        // Startup recovery may already have completed this same operation.
        final record = (await recovery.load())
            .where(
              (record) =>
                  record.link.address == address &&
                  record.sourceAccountUuid == accountUuid,
            )
            .firstOrNull;
        if (record != null &&
            record.state != PaymentLinkRecoveryState.draft &&
            (record.fundingTxids?.isNotEmpty ?? false)) {
          return PaymentLinkHardwareFundingResult(
            txids: record.fundingTxids!,
            status: 'pending_broadcast',
            fundingMetadataSaved: true,
          );
        }
        throw StateError(
          'The saved Ledger gift card transaction is unavailable.',
        );
      }
      final LedgerSignedOperationBroadcastResult result;
      if (entry.state == 'result_pending_ack') {
        result = LedgerSignedOperationBroadcastResult(
          operationId: id,
          txid: entry.txid ?? '',
          status: entry.status ?? '',
          message: entry.message,
          requiresAck: true,
        );
      } else {
        final broadcast = await broadcastCheckpoint(
          operationId: id,
          address: address,
          spendParamsPath: spendParamsPath,
          outputParamsPath: outputParamsPath,
        );
        if (broadcast == null) {
          settlementStatus = 'terminal_failure';
          throw const LedgerGiftFundingTerminalException();
        }
        result = broadcast;
      }
      settlementStatus = result.status;
      await complete(entry, result);
      try {
        await refresh();
      } catch (_) {
        /* A sync refresh cannot undo funding. */
      }
      if (result.status == 'expired') {
        throw const LedgerGiftFundingTerminalException();
      }
      return PaymentLinkHardwareFundingResult(
        txids: result.txid,
        status: result.status,
        message: result.message,
        fundingMetadataSaved: true,
      );
    } finally {
      if (draft != null) await settleProposal(draft, settlementStatus);
    }
  });

  /// Broadcasts a checkpointed funding for the signing surface and startup
  /// recovery alike. Returns null when Rust rejected it definitively.
  Future<LedgerSignedOperationBroadcastResult?> broadcastCheckpoint({
    required String operationId,
    required String address,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    // Past this marker the draft may hold funds and blocks deleting its
    // account. A failed write aborts before the network sees anything.
    await recovery.markSubmissionStartedIfPresent(
      address: address,
      chainHeight: currentChainHeight(),
    );
    try {
      return await operations.broadcast(
        operationId: operationId,
        spendParamsPath: spendParamsPath,
        outputParamsPath: outputParamsPath,
      );
    } catch (error) {
      if (!isTerminalLedgerSignedOperationError(error)) rethrow;
      // Rust has rejected this transaction definitively and removed its outbox
      // entry. The prepared secret is safe to remove; never offer rebroadcast.
      await recovery.removeUnbroadcastDraft(address: address);
      return null;
    }
  }

  Future<void> complete(
    LedgerSignedOperationMetadata operation,
    LedgerSignedOperationBroadcastResult result,
  ) => lifecycle.run(() async {
    _requireAccount(operation.accountUuid);
    final address = operation.externalRef;
    if (operation.kind != LedgerSignedOperationKind.giftCard ||
        address == null ||
        address.isEmpty) {
      throw StateError('The Ledger gift card recovery reference is missing.');
    }
    if (result.operationId != operation.operationId ||
        operation.operationId != operationId(operation.accountUuid, address)) {
      throw StateError(
        'The Ledger gift card operation does not match its result.',
      );
    }
    final record = (await recovery.load())
        .where((record) => record.link.address == address)
        .firstOrNull;
    if (record != null && record.sourceAccountUuid != operation.accountUuid) {
      throw StateError('The gift card belongs to a different account.');
    }
    if (result.status == 'expired') {
      if (record?.state == PaymentLinkRecoveryState.draft) {
        await recovery.removeUnbroadcastDraft(address: address);
      }
    } else {
      if (record == null) {
        throw StateError('The gift card recovery draft is missing.');
      }
      if (record.state == PaymentLinkRecoveryState.draft) {
        // Rust attempted this broadcast, so the boundary was crossed even if
        // the marker was never written.
        await recovery.markSubmissionStarted(
          address: address,
          chainHeight: currentChainHeight(),
        );
      }
      if (!isPaymentLinkFundingSubmitted(
        status: result.status,
        txids: result.txid,
      )) {
        throw StateError(
          result.message ?? 'The gift card funding result is incomplete.',
        );
      }
      if (record.state != PaymentLinkRecoveryState.draft) {
        if (record.fundingTxids?.trim().toLowerCase() !=
            result.txid.trim().toLowerCase()) {
          throw StateError(
            'The gift card transaction does not match its saved funding.',
          );
        }
      } else {
        await recovery.markFunded(address: address, fundingTxids: result.txid);
      }
    }
    if (result.requiresAck) await operations.acknowledge(result.operationId);
  });
}
