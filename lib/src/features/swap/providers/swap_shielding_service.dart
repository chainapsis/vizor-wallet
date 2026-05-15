import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;

final swapShieldingServiceProvider = Provider<SwapShieldingService>((ref) {
  return RustSwapShieldingService(ref);
});

abstract interface class SwapShieldingService {
  Future<SwapShieldingResult> shieldStagingAddress({
    required String accountUuid,
    required String transparentAddress,
  });

  Future<SwapShieldTxState> trackShieldTransaction({
    required String accountUuid,
    required String txHash,
  });
}

enum SwapShieldTxStatus { unknown, pending, mined, expired }

class SwapShieldTxState {
  const SwapShieldTxState({required this.status});

  final SwapShieldTxStatus status;
}

final _txidHexPattern = RegExp(r'^[0-9a-f]{64}$');

SwapShieldTxState classifySwapShieldTransaction({
  required Iterable<rust_sync.TransactionInfo> transactions,
  required String txHash,
}) {
  final candidates = _txidCandidates(txHash);
  if (candidates.isEmpty) {
    return const SwapShieldTxState(status: SwapShieldTxStatus.unknown);
  }

  for (final transaction in transactions) {
    if (!candidates.contains(transaction.txidHex.trim().toLowerCase())) {
      continue;
    }
    if (transaction.expiredUnmined) {
      return const SwapShieldTxState(status: SwapShieldTxStatus.expired);
    }
    if (transaction.minedHeight > BigInt.zero) {
      return const SwapShieldTxState(status: SwapShieldTxStatus.mined);
    }
    return const SwapShieldTxState(status: SwapShieldTxStatus.pending);
  }
  return const SwapShieldTxState(status: SwapShieldTxStatus.unknown);
}

Set<String> _txidCandidates(String txHash) {
  final normalized = txHash.trim().toLowerCase();
  if (normalized.isEmpty) return const {};
  if (!_txidHexPattern.hasMatch(normalized)) return {normalized};

  final bytes = <String>[];
  for (var i = 0; i < normalized.length; i += 2) {
    bytes.add(normalized.substring(i, i + 2));
  }
  return {normalized, bytes.reversed.join()};
}

class SwapShieldingResult {
  const SwapShieldingResult({
    required this.txids,
    required this.feeZatoshi,
    required this.shieldedZatoshi,
  });

  final String txids;
  final BigInt feeZatoshi;
  final BigInt shieldedZatoshi;

  String? get firstTxid {
    for (final part in txids.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

class SwapShieldingNotReadyException implements Exception {
  const SwapShieldingNotReadyException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

class RustSwapShieldingService implements SwapShieldingService {
  RustSwapShieldingService(this._ref);

  final Ref _ref;

  @override
  Future<SwapShieldingResult> shieldStagingAddress({
    required String accountUuid,
    required String transparentAddress,
  }) async {
    if (transparentAddress.trim().isEmpty) {
      throw const SwapShieldingNotReadyException(
        'Transparent staging address is missing',
      );
    }

    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointProvider);
    final status = await rust_sync.getShieldTransparentAddressStatus(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      transparentAddress: transparentAddress,
    );
    if (!status.canShield) {
      throw SwapShieldingNotReadyException(
        status.reason.isEmpty
            ? 'Staging address has no shieldable transparent funds yet'
            : status.reason,
      );
    }

    final mnemonic = await _ref
        .read(accountProvider.notifier)
        .getMnemonicForAccount(accountUuid);
    if (mnemonic == null) {
      throw StateError('Mnemonic not found for the active account');
    }

    final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
    final result = await rust_sync.shieldTransparentAddress(
      dbPath: dbPath,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      transparentAddress: transparentAddress,
      seed: seedBytes,
    );

    try {
      await _ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (_) {}

    return SwapShieldingResult(
      txids: result.txids,
      feeZatoshi: result.feeZatoshi,
      shieldedZatoshi: result.shieldedZatoshi,
    );
  }

  @override
  Future<SwapShieldTxState> trackShieldTransaction({
    required String accountUuid,
    required String txHash,
  }) async {
    final normalizedTxHash = txHash.trim().toLowerCase();
    if (normalizedTxHash.isEmpty) {
      return const SwapShieldTxState(status: SwapShieldTxStatus.unknown);
    }

    try {
      await _ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (_) {}

    final syncState = _ref
        .read(syncProvider)
        .value
        ?.scopedToAccount(accountUuid);
    return classifySwapShieldTransaction(
      transactions: syncState?.recentTransactions ?? const [],
      txHash: normalizedTxHash,
    );
  }
}
