import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/services/keystone_batch_signing.dart';
import '../models/swap_models.dart';

final swapHardwareSigningServiceProvider = Provider<SwapHardwareSigningService>(
  (ref) => RustSwapHardwareSigningService(ref),
);

abstract interface class SwapHardwareSigningService {
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  });

  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  });

  Future<List<int>> decodeSigningResponse({
    required SwapHardwarePcztDraft draft,
    required List<int> responseCbor,
  });

  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  });

  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft});

  /// Takes ownership of [draft]'s proposal lock on entry. The implementation
  /// must release it for definite completion/failure or retain it through its
  /// height expiry when broadcast acceptance is ambiguous.
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  });
}

class SwapHardwarePcztDraft {
  const SwapHardwarePcztDraft({
    required this.pcztBytes,
    required this.needsSaplingParams,
    required this.feeZatoshi,
    required this.proposalId,
    required this.sendFlowId,
  });

  final List<int> pcztBytes;
  final bool needsSaplingParams;
  final BigInt feeZatoshi;
  final BigInt proposalId;
  final String sendFlowId;
}

class RustSwapHardwareSigningService implements SwapHardwareSigningService {
  RustSwapHardwareSigningService(this._ref);

  final Ref _ref;

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    if (intent.direction != SwapDirection.zecToExternal) {
      throw StateError('Only ZEC deposit swaps can create a deposit PCZT');
    }
    final depositAddress = intent.depositAddress?.trim();
    if (depositAddress == null || depositAddress.isEmpty) {
      throw StateError('Swap deposit address is missing');
    }
    await _rejectTexDepositForKeystone(
      depositAddress,
      networkName: _ref.read(rpcEndpointProvider).networkName,
    );
    final amountZatoshi = zecDepositAmountZatoshiForIntent(intent);
    final sendFlowId = _newSwapHardwareFlowId('deposit');
    return _ref
        .read(syncProvider.notifier)
        .runWithAuthoritativeSpendable(
          accountUuid: accountUuid,
          operation: () async {
            final dbPath = await getWalletDbPath();
            final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
            BigInt? proposalId;
            var proposalConsumed = false;

            try {
              log(
                'SwapHardwareSigning: deposit propose begin flow=$sendFlowId '
                'intent=${_shortSwapValue(intent.id)} '
                'deposit=${_shortSwapValue(depositAddress)} '
                'zatoshi=$amountZatoshi',
              );
              final proposal = await rust_sync.proposeSend(
                dbPath: dbPath,
                network: endpoint.networkName,
                accountUuid: accountUuid,
                sendFlowId: sendFlowId,
                toAddress: depositAddress,
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
              log(
                'SwapHardwareSigning: deposit pczt ready flow=$sendFlowId '
                'proposal=${proposal.proposalId} '
                'needsSapling=${proposal.needsSaplingParams}',
              );
              return SwapHardwarePcztDraft(
                pcztBytes: pcztBytes,
                needsSaplingParams: proposal.needsSaplingParams,
                feeZatoshi: proposal.feeZatoshi,
                proposalId: proposal.proposalId,
                sendFlowId: sendFlowId,
              );
            } catch (e) {
              log(
                'SwapHardwareSigning: deposit pczt failed '
                'flow=$sendFlowId error=$e',
              );
              rethrow;
            } finally {
              if (proposalId != null && !proposalConsumed) {
                try {
                  await rust_sync.discardProposal(
                    proposalId: proposalId,
                    sendFlowId: sendFlowId,
                  );
                } catch (e) {
                  log(
                    'SwapHardwareSigning: discard deposit proposal failed '
                    'flow=$sendFlowId proposal=$proposalId error=$e',
                  );
                }
              }
            }
          },
        );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async {
    final request = await buildKeystoneBatchSigningRequest(
      requestId: _swapKeystoneRequestId(draft),
      pczts: [
        KeystoneBatchPcztSource(
          id: _swapKeystoneMessageId,
          pcztBytes: draft.pcztBytes,
        ),
      ],
    );
    return request.urParts;
  }

  @override
  Future<List<int>> decodeSigningResponse({
    required SwapHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async {
    final prepared = await rust_sync.preparePcztForKeystoneBatch(
      pcztBytes: draft.pcztBytes,
    );
    final request = KeystoneBatchSigningRequest(
      requestId: _swapKeystoneRequestId(draft),
      messageIds: const [_swapKeystoneMessageId],
      expectedSignatureCounts: [prepared.expectedSignatureCount],
      urParts: const [],
    );
    final signatureBlobs = await request.decodeResponse(responseCbor);
    if (signatureBlobs.length != 1) {
      throw StateError('Keystone returned an invalid swap signature count.');
    }
    return signatureBlobs.single;
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return rust_sync.addProofsToPczt(
      pcztBytes: draft.pcztBytes,
      spendParamsPath: draft.needsSaplingParams ? spendParamsPath : null,
      outputParamsPath: draft.needsSaplingParams ? outputParamsPath : null,
    );
  }

  @override
  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await rust_sync.discardProposal(
          proposalId: draft.proposalId,
          sendFlowId: draft.sendFlowId,
        );
        log(
          'SwapHardwareSigning: released deposit proposal '
          'flow=${draft.sendFlowId} proposal=${draft.proposalId}',
        );
        return;
      } catch (e) {
        lastError = e;
        log(
          'SwapHardwareSigning: discard deposit proposal attempt $attempt '
          'failed flow=${draft.sendFlowId} proposal=${draft.proposalId} '
          'error=$e',
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: attempt * 100));
        }
      }
    }
    log(
      'SwapHardwareSigning: deposit proposal cleanup remains pending '
      'flow=${draft.sendFlowId} proposal=${draft.proposalId} error=$lastError',
    );
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
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
    try {
      await _ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (e) {
      log('SwapHardwareSigning: refreshAfterSend failed: $e');
    }
    return result;
  }
}

const _swapKeystoneMessageId = 'swap-deposit';

String _swapKeystoneRequestId(SwapHardwarePcztDraft draft) =>
    'vizor-${draft.sendFlowId}';

Future<void> _rejectTexDepositForKeystone(
  String address, {
  required String networkName,
}) async {
  final validation = await rust_sync.validateAddress(
    address: address,
    network: networkName,
  );
  if (validation.isValid && validation.addressType == 'tex') {
    throw UnsupportedError('Keystone does not support TEX sends yet.');
  }
}

BigInt zecDepositAmountZatoshiForIntent(SwapIntent intent) {
  if (intent.direction != SwapDirection.zecToExternal) {
    throw StateError('Only ZEC deposit swaps can create a deposit PCZT');
  }
  final zatoshi = intent.sellAmountBaseUnits;
  if (zatoshi == null || zatoshi <= BigInt.zero) {
    throw StateError('Swap intent is missing executable ZEC amount');
  }
  return zatoshi;
}

String _newSwapHardwareFlowId(String label) {
  return 'swap-hw-$label-${DateTime.now().microsecondsSinceEpoch}';
}

String _shortSwapValue(String? value) {
  if (value == null) return 'null';
  if (value.length <= 16) return value;
  return '${value.substring(0, 7)}...${value.substring(value.length - 6)}';
}
