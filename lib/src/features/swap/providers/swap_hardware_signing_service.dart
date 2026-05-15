import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/swap_prototype_models.dart';

final swapHardwareSigningServiceProvider = Provider<SwapHardwareSigningService>(
  (ref) => RustSwapHardwareSigningService(ref),
);

abstract interface class SwapHardwareSigningService {
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapPrototypeIntent intent,
  });

  Future<SwapHardwarePcztDraft> createShieldPczt({
    required String accountUuid,
    required String transparentAddress,
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
    this.shieldedZatoshi,
  });

  final List<int> pcztBytes;
  final bool needsSaplingParams;
  final BigInt feeZatoshi;
  final BigInt? shieldedZatoshi;
}

class RustSwapHardwareSigningService implements SwapHardwareSigningService {
  RustSwapHardwareSigningService(this._ref);

  final Ref _ref;

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapPrototypeIntent intent,
  }) async {
    if (intent.direction != SwapDirection.zecToExternal) {
      throw StateError('Only ZEC deposit swaps can create a deposit PCZT');
    }
    final depositAddress = intent.depositAddress?.trim();
    if (depositAddress == null || depositAddress.isEmpty) {
      throw StateError('Swap deposit address is missing');
    }

    final amountZatoshi = _zecAmountFromIntent(intent);
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointProvider);
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
  Future<SwapHardwarePcztDraft> createShieldPczt({
    required String accountUuid,
    required String transparentAddress,
  }) async {
    final staging = transparentAddress.trim();
    if (staging.isEmpty) {
      throw StateError('Transparent staging address is missing');
    }

    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointProvider);
    log(
      'SwapHardwareSigning: shield pczt begin staging=${_shortSwapValue(staging)}',
    );
    final result = await rust_sync.createShieldTransparentAddressPczt(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      transparentAddress: staging,
    );
    log(
      'SwapHardwareSigning: shield pczt ready staging=${_shortSwapValue(staging)} '
      'shielded=${result.shieldedZatoshi} fee=${result.feeZatoshi} '
      'needsSapling=${result.needsSaplingParams}',
    );
    return SwapHardwarePcztDraft(
      pcztBytes: result.pcztBytes,
      needsSaplingParams: result.needsSaplingParams,
      feeZatoshi: result.feeZatoshi,
      shieldedZatoshi: result.shieldedZatoshi,
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
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointProvider);
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

BigInt _zecAmountFromIntent(SwapPrototypeIntent intent) {
  final amountText = intent.sellAmount.split(' ').first.trim();
  final zatoshi = parseZecAmount(amountText);
  if (zatoshi == null || zatoshi <= BigInt.zero) {
    throw FormatException('Invalid ZEC swap amount: $amountText');
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
