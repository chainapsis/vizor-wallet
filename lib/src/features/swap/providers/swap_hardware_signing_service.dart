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

  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
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
  });

  final List<int> pcztBytes;
  final bool needsSaplingParams;
  final BigInt feeZatoshi;
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
    await _ref
        .read(syncProvider.notifier)
        .waitForAuthoritativeSpendable(accountUuid: accountUuid);

    final amountZatoshi = zecDepositAmountZatoshiForIntent(intent);
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final sendFlowId = _newSwapHardwareFlowId('deposit');
    BigInt? proposalId;
    var proposalConsumed = false;

    try {
      log(
        'SwapHardwareSigning: deposit propose begin flow=$sendFlowId '
        'intent=${_shortSwapValue(intent.id)} '
        'deposit=${_shortSwapValue(depositAddress)} zatoshi=$amountZatoshi',
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
        network: endpoint.networkName,
        proposalId: proposal.proposalId,
        sendFlowId: sendFlowId,
      );
      proposalConsumed = true;
      log(
        'SwapHardwareSigning: deposit pczt ready flow=$sendFlowId '
        'proposal=${proposal.proposalId} needsSapling=${proposal.needsSaplingParams}',
      );
      return SwapHardwarePcztDraft(
        pcztBytes: pcztBytes,
        needsSaplingParams: proposal.needsSaplingParams,
        feeZatoshi: proposal.feeZatoshi,
      );
    } catch (e) {
      log('SwapHardwareSigning: deposit pczt failed flow=$sendFlowId error=$e');
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
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final result = await rust_sync.extractAndBroadcastPczt(
      dbPath: dbPath,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      network: endpoint.networkName,
      pcztWithProofsBytes: pcztWithProofsBytes,
      pcztWithSignaturesBytes: pcztWithSignaturesBytes,
      spendParamsPath: spendParamsPath,
      outputParamsPath: outputParamsPath,
    );
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
