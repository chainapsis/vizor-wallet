import 'dart:async';

import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_ledger_funding_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';

final ledgerGiftLink = VizorPaymentLink(
  label: 'Gift card',
  network: 'main',
  address: 'u1gift',
  amountZatoshi: BigInt.from(10000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  createdAt: DateTime.utc(2026, 8, 6),
);

class LedgerGiftHarness {
  LedgerGiftHarness() {
    recovery = PaymentLinkRecoveryStore(storage);
    hardware = LedgerGiftHardware(recovery);
    service = PaymentLinkLedgerFundingService(
      hardware: hardware,
      operations: operations,
      recovery: recovery,
      lifecycle: lifecycle,
      accountExists: (_) => accountExists,
      settleProposal: (_, status) async {
        settlements.add(status);
        if (status != null &&
            status != "broadcast_unknown" &&
            status != "broadcasted_storage_failed") {
          releases++;
        }
      },
      refresh: () async {},
    );
  }
  final storage = LedgerGiftStorage();
  final operations = LedgerGiftOperations();
  final lifecycle = LedgerOperationLifecycle();
  late final PaymentLinkRecoveryStore recovery;
  late final LedgerGiftHardware hardware;
  late final PaymentLinkLedgerFundingService service;
  bool accountExists = true;
  int releases = 0;
  final settlements = <String?>[];
  Future<PaymentLinkHardwarePcztDraft> prepare() async {
    final draft = await service.prepare(
      accountUuid: 'account-1',
      amountZatoshi: ledgerGiftLink.amountZatoshi,
    );
    await service.prove(accountUuid: 'account-1', draft: draft);
    return draft;
  }

  Future<PaymentLinkHardwareFundingResult> submit(
    PaymentLinkHardwarePcztDraft draft,
  ) => service.submit(
    accountUuid: 'account-1',
    draft: draft,
    proofs: [2],
    signatures: [3],
    onCheckpointed: () {},
  );
}

class LedgerGiftStorage implements PaymentLinkRecoveryStorage {
  String? data;
  bool failWrites = false;
  Completer<void>? writeGate;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String value) async {
    await writeGate?.future;
    if (failWrites) throw StateError('storage unavailable');
    data = value;
  }

  @override
  Future<void> delete() async => data = null;
}

class LedgerGiftHardware implements PaymentLinkHardwareSigningService {
  LedgerGiftHardware(this.store);
  final PaymentLinkRecoveryStore store;
  int discards = 0;
  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    await store.saveDraft(
      link: ledgerGiftLink,
      sourceAccountUuid: sourceAccountUuid,
      claimFeeReserveZatoshi: BigInt.from(10000),
    );
    return PaymentLinkHardwarePcztDraft(
      link: ledgerGiftLink,
      pcztBytes: [1],
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
      proposalId: BigInt.one,
      sendFlowId: 'gift',
    );
  }

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    await store.markPrepared(
      address: draft.link.address,
      fundingTxid: 'gift-txid',
      expiryHeight: 3000040,
    );
    return [2];
  }

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
    discards++;
    await store.removeUnbroadcastDraft(address: draft.link.address);
  }

  // Keystone-only methods must never be used by the Ledger path.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected Keystone operation: ${invocation.memberName}',
  );
}

class LedgerGiftOperations implements LedgerSignedOperationService {
  LedgerSignedOperationMetadata? entry;
  int broadcasts = 0;
  int checkpoints = 0;
  int acks = 0;
  Completer<void>? broadcastGate;
  String status = 'broadcasted';
  bool terminalRejection = false;
  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    checkpoints++;
    entry = LedgerSignedOperationMetadata(
      operationId: operationId,
      accountUuid: accountUuid,
      kind: kind,
      externalRef: externalRef,
      state: 'signed_pending_broadcast',
    );
  }

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => [?entry];
  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts++;
    await broadcastGate?.future;
    if (terminalRejection) {
      entry = null;
      throw StateError(
        'Ledger signed operation cannot be retried: broadcast rejected',
      );
    }
    final old = entry!;
    entry = LedgerSignedOperationMetadata(
      operationId: old.operationId,
      accountUuid: old.accountUuid,
      kind: old.kind,
      externalRef: old.externalRef,
      state: 'result_pending_ack',
      txid: 'gift-txid',
      status: status,
    );
    return LedgerSignedOperationBroadcastResult(
      operationId: operationId,
      txid: 'gift-txid',
      status: status,
      requiresAck: true,
    );
  }

  @override
  Future<void> acknowledge(String operationId) async {
    acks++;
    entry = null;
  }
}
