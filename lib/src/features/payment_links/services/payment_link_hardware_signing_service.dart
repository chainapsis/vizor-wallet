import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
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
  });

  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  });

  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  });

  Future<void> discardPcztDraft({required PaymentLinkHardwarePcztDraft draft});

  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
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
  }) async {
    final link = await _paymentLinkService.createFundingDraft(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
    );
    final sendFlowId =
        'payment-link-hw-${DateTime.now().microsecondsSinceEpoch}';

    return _ref
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
                amountZatoshi: amountZatoshi,
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
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
    final redactedPczt = await rust_sync.redactPcztForSigner(
      pcztBytes: draft.pcztBytes,
    );
    return rust_keystone.encodePcztUrParts(
      pcztBytes: redactedPczt,
      maxFragmentLen: BigInt.from(140),
    );
  }

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    return rust_sync.addProofsToPczt(
      pcztBytes: draft.pcztBytes,
      spendParamsPath: draft.needsSaplingParams ? spendParamsPath : null,
      outputParamsPath: draft.needsSaplingParams ? outputParamsPath : null,
    );
  }

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
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

  Future<void> _retainPcztDraftLockUntilExpiry(
    PaymentLinkHardwarePcztDraft draft,
  ) async {
    try {
      await rust_sync.retainProposalLockUntilExpiry(
        proposalId: draft.proposalId,
        sendFlowId: draft.sendFlowId,
      );
    } catch (error) {
      log(
        'PaymentLinkHardwareSigning: retain proposal lock failed '
        'flow=${draft.sendFlowId} proposal=${draft.proposalId} error=$error',
      );
    }
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    late final rust_sync.ExtractAndBroadcastPcztResult result;
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
      result = await rust_sync.extractAndBroadcastPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        pcztWithProofsBytes: pcztWithProofsBytes,
        pcztWithSignaturesBytes: pcztWithSignaturesBytes,
        spendParamsPath: spendParamsPath,
        outputParamsPath: outputParamsPath,
      );
    } catch (_) {
      await discardPcztDraft(draft: draft);
      rethrow;
    }

    final hasTxid = result.txid.trim().isNotEmpty;
    final fundingAccepted =
        hasTxid &&
        (result.status == 'broadcasted' ||
            result.status == 'broadcasted_storage_failed');
    if (result.status == 'broadcast_unknown' ||
        result.status == 'broadcasted_storage_failed') {
      await _retainPcztDraftLockUntilExpiry(draft);
    } else {
      await discardPcztDraft(draft: draft);
    }

    if (fundingAccepted) {
      await _recoveryStore.markFunded(
        address: draft.link.address,
        fundingTxids: result.txid,
      );
    }
    try {
      await _ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (error) {
      log('PaymentLinkHardwareSigning: refreshAfterSend failed: $error');
    }
    return result;
  }
}
