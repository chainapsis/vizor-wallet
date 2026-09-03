import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/services/keystone_batch_signing.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_recovery_store.dart';
import 'payment_link_service.dart';

final paymentLinkHardwareSigningServiceProvider =
    Provider<PaymentLinkHardwareSigningService>((ref) {
      return RustPaymentLinkHardwareSigningService(
        ref,
        ref.read(paymentLinkServiceProvider),
        ref.read(paymentLinkRecoveryStoreProvider),
      );
    });

abstract interface class PaymentLinkHardwareSigningService {
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  });

  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  });

  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  });

  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  });

  Future<void> discardPcztDraft({required PaymentLinkHardwarePcztDraft draft});

  /// Applies [pcztWithSignaturesBytes] and broadcasts the funding transaction.
  ///
  /// [onSubmissionStarted] fires immediately before the transaction is handed
  /// to the network, mirroring the software path's
  /// `runPaymentLinkFundingSubmission` marker. Once it has fired the caller
  /// must keep the recovery draft on failure: the network may already hold
  /// the transaction, and the draft carries the `markPrepared` txid the
  /// reconciler needs to settle it.
  Future<PaymentLinkHardwareFundingResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
    void Function()? onSubmissionStarted,
  });
}

class PaymentLinkHardwarePcztDraft {
  const PaymentLinkHardwarePcztDraft({
    required this.link,
    required this.pcztBytes,
    required this.needsSaplingParams,
    required this.feeZatoshi,
    required this.proposalId,
    required this.sendFlowId,
  });

  final VizorPaymentLink link;
  final List<int> pcztBytes;
  final bool needsSaplingParams;
  final BigInt feeZatoshi;
  final BigInt proposalId;
  final String sendFlowId;
}

class PaymentLinkHardwareFundingResult {
  const PaymentLinkHardwareFundingResult({
    required this.txids,
    required this.status,
    required this.fundingMetadataSaved,
    this.message,
  });

  final String txids;
  final String status;
  final String? message;
  final bool fundingMetadataSaved;
}

class RustPaymentLinkHardwareSigningService
    implements PaymentLinkHardwareSigningService {
  RustPaymentLinkHardwareSigningService(
    this._ref,
    this._paymentLinkService,
    this._recoveryStore,
  );

  final Ref _ref;
  final PaymentLinkService _paymentLinkService;
  final PaymentLinkRecoveryStore _recoveryStore;

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    final link = await _paymentLinkService.createFundingDraft(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
      presentation: presentation,
    );
    final sendFlowId =
        'payment-link-hw-${DateTime.now().microsecondsSinceEpoch}';

    try {
      return await _ref
          .read(syncProvider.notifier)
          .runWithAuthoritativeSpendable(
            accountUuid: sourceAccountUuid,
            operation: () async {
              final dbPath = await getWalletDbPath();
              final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
              BigInt? proposalId;
              var proposalConsumed = false;

              try {
                final proposal = await rust_sync.proposeSend(
                  dbPath: dbPath,
                  network: endpoint.networkName,
                  accountUuid: sourceAccountUuid,
                  sendFlowId: sendFlowId,
                  toAddress: link.address,
                  amountZatoshi: paymentLinkFundingAmountZatoshi(amountZatoshi),
                );
                proposalId = proposal.proposalId;
                final pcztBytes = await rust_sync.createPcztFromProposal(
                  dbPath: dbPath,
                  lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
                  network: endpoint.networkName,
                  proposalId: proposal.proposalId,
                  sendFlowId: sendFlowId,
                );
                proposalConsumed = true;
                return PaymentLinkHardwarePcztDraft(
                  link: link,
                  pcztBytes: pcztBytes,
                  needsSaplingParams: proposal.needsSaplingParams,
                  feeZatoshi: proposal.feeZatoshi,
                  proposalId: proposal.proposalId,
                  sendFlowId: sendFlowId,
                );
              } finally {
                if (proposalId != null && !proposalConsumed) {
                  try {
                    await rust_sync.discardProposal(
                      proposalId: proposalId,
                      sendFlowId: sendFlowId,
                    );
                  } catch (error) {
                    log(
                      'PaymentLinkHardwareSigning: proposal cleanup failed '
                      'flow=$sendFlowId proposal=$proposalId error=$error',
                    );
                  }
                }
              }
            },
          );
    } catch (error, stackTrace) {
      try {
        await _recoveryStore.removeUnsubmittedDraft(address: link.address);
      } catch (cleanupError) {
        log(
          'PaymentLinkHardwareSigning: failed PCZT draft cleanup '
          'address=${link.address} error=$cleanupError',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
    final request = await buildKeystoneBatchSigningRequest(
      requestId: _paymentLinkKeystoneRequestId(draft),
      pczts: [
        KeystoneBatchPcztSource(
          id: _paymentLinkKeystoneMessageId,
          pcztBytes: draft.pcztBytes,
        ),
      ],
    );
    return request.urParts;
  }

  @override
  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async {
    final prepared = await rust_sync.preparePcztForKeystoneBatch(
      pcztBytes: draft.pcztBytes,
    );
    final request = KeystoneBatchSigningRequest(
      requestId: _paymentLinkKeystoneRequestId(draft),
      messageIds: const [_paymentLinkKeystoneMessageId],
      expectedSignatureCounts: [prepared.expectedSignatureCount],
      urParts: const [],
    );
    final signatureBlobs = await request.decodeResponse(responseCbor);
    if (signatureBlobs.length != 1) {
      throw StateError(
        'Keystone returned an invalid Gift Card signature count.',
      );
    }
    return signatureBlobs.single;
  }

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    final pcztWithProofs = await rust_sync.addProofsToPczt(
      pcztBytes: draft.pcztBytes,
      spendParamsPath: draft.needsSaplingParams ? spendParamsPath : null,
      outputParamsPath: draft.needsSaplingParams ? outputParamsPath : null,
    );
    final preparedTxid = rust_sync.getPcztTxid(pcztBytes: pcztWithProofs);
    final preparedExpiryHeight = rust_sync.getPcztExpiryHeight(
      pcztBytes: pcztWithProofs,
    );
    await _recoveryStore.markPrepared(
      address: draft.link.address,
      fundingTxid: preparedTxid,
      expiryHeight: preparedExpiryHeight,
    );
    return pcztWithProofs;
  }

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
    await _discardProposal(draft);
    try {
      await _recoveryStore.removeUnbroadcastDraft(address: draft.link.address);
    } catch (error) {
      log(
        'PaymentLinkHardwareSigning: canceled funding cleanup failed '
        'address=${draft.link.address} error=$error',
      );
    }
  }

  Future<void> _discardProposal(PaymentLinkHardwarePcztDraft draft) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await rust_sync.discardProposal(
          proposalId: draft.proposalId,
          sendFlowId: draft.sendFlowId,
        );
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: attempt * 100));
        }
      }
    }
    log(
      'PaymentLinkHardwareSigning: proposal cleanup remains pending '
      'flow=${draft.sendFlowId} proposal=${draft.proposalId} error=$lastError',
    );
  }

  @override
  Future<PaymentLinkHardwareFundingResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
    void Function()? onSubmissionStarted,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    // Rust broadcasts before it stores, so from here on a throw can no longer
    // prove the network did not accept the transaction.
    onSubmissionStarted?.call();
    final stored = await rust_sync
        .storeAndBroadcastPcztsWithKeystoneSignaturesForProposal(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          proposalId: draft.proposalId,
          sendFlowId: draft.sendFlowId,
          pcztWithProofs: [Uint8List.fromList(pcztWithProofsBytes)],
          signatureBlobs: [Uint8List.fromList(pcztWithSignaturesBytes)],
          spendParamsPath: spendParamsPath,
          outputParamsPath: outputParamsPath,
        );
    final result = rust_sync.ExtractAndBroadcastPcztResult(
      txid: stored.txids
          .split(',')
          .map((txid) => txid.trim())
          .firstWhere((txid) => txid.isNotEmpty, orElse: () => ''),
      status: stored.status,
      message: stored.message,
    );

    final fundingAccepted = isPaymentLinkFundingSubmitted(
      status: result.status,
      txids: result.txid,
    );
    var fundingMetadataSaved = false;
    if (fundingAccepted) {
      final funding = await PaymentLinkFundingRecovery(_recoveryStore).complete(
        transaction: result,
        address: draft.link.address,
        fundingTxids: (broadcast) => broadcast.txid,
      );
      if (!funding.fundingMetadataSaved) {
        log(
          'PaymentLinkHardwareSigning: funding was submitted but recovery '
          'metadata could not be saved after retry: '
          '${funding.recoveryError}\n${funding.recoveryStackTrace}',
        );
      }
      fundingMetadataSaved = funding.fundingMetadataSaved;
    }
    try {
      await _ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (error) {
      log('PaymentLinkHardwareSigning: refreshAfterSend failed: $error');
    }
    return PaymentLinkHardwareFundingResult(
      txids: result.txid,
      status: result.status,
      message: result.message,
      fundingMetadataSaved: fundingMetadataSaved,
    );
  }
}

const _paymentLinkKeystoneMessageId = 'gift-card-funding';

String _paymentLinkKeystoneRequestId(PaymentLinkHardwarePcztDraft draft) =>
    'vizor-${draft.sendFlowId}';
