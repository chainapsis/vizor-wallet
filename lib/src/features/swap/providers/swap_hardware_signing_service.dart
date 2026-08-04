import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
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
    await _rejectTexDepositForKeystone(depositAddress);
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

  Future<void> _retainPcztDraftLockUntilExpiry({
    required SwapHardwarePcztDraft draft,
  }) async {
    try {
      await rust_sync.retainProposalLockUntilExpiry(
        proposalId: draft.proposalId,
        sendFlowId: draft.sendFlowId,
      );
      log(
        'SwapHardwareSigning: retained deposit input lock until expiry '
        'flow=${draft.sendFlowId} proposal=${draft.proposalId}',
      );
    } catch (e) {
      log(
        'SwapHardwareSigning: retain deposit proposal lock failed '
        'flow=${draft.sendFlowId} proposal=${draft.proposalId} error=$e',
      );
    }
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    late final rust_sync.ExtractAndBroadcastPcztResult result;
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
      final managedSubmissionRouting = endpoint.usesManagedSubmissionRouting;
      result = await rust_sync.extractAndBroadcastPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        managedSubmissionRouting: managedSubmissionRouting,
        pcztWithProofsBytes: pcztWithProofsBytes,
        pcztWithSignaturesBytes: pcztWithSignaturesBytes,
        spendParamsPath: spendParamsPath,
        outputParamsPath: outputParamsPath,
      );
    } catch (_) {
      await discardPcztDraft(draft: draft);
      rethrow;
    }
    if (result.status == 'broadcast_unknown' ||
        result.status == 'broadcasted_storage_failed') {
      await _retainPcztDraftLockUntilExpiry(draft: draft);
    } else {
      await discardPcztDraft(draft: draft);
    }
    try {
      await _ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (e) {
      log('SwapHardwareSigning: refreshAfterSend failed: $e');
    }
    return result;
  }
}

Future<void> _rejectTexDepositForKeystone(String address) async {
  final validation = await rust_sync.validateAddress(address: address);
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
