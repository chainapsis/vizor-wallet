import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
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
  return _txidCandidateList(txHash).toSet();
}

List<String> _txidCandidateList(String txHash) {
  final normalized = txHash.trim().toLowerCase();
  if (normalized.isEmpty) return const [];
  if (!_txidHexPattern.hasMatch(normalized)) return [normalized];

  final bytes = <String>[];
  for (var i = 0; i < normalized.length; i += 2) {
    bytes.add(normalized.substring(i, i + 2));
  }
  final reversed = bytes.reversed.join();
  return reversed == normalized ? [normalized] : [normalized, reversed];
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
    log(
      'SwapShielding: status begin staging=${_shortSwapValue(transparentAddress)}',
    );
    final status = await rust_sync.getShieldTransparentAddressStatus(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      transparentAddress: transparentAddress,
    );
    if (!status.canShield) {
      log(
        'SwapShielding: not ready staging=${_shortSwapValue(transparentAddress)} '
        'reason=${status.reason}',
      );
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
    log(
      'SwapShielding: shield begin staging=${_shortSwapValue(transparentAddress)}',
    );
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
    } catch (e) {
      log('SwapShielding: refreshAfterSend failed: $e');
    }

    final firstTxid = _firstTxid(result.txids);
    log(
      'SwapShielding: shield complete tx=${_shortSwapValue(firstTxid)} '
      'shielded=${result.shieldedZatoshi} fee=${result.feeZatoshi}',
    );
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
    } catch (e) {
      log('SwapShielding: track refreshAfterSend failed: $e');
    }

    final syncState = _ref
        .read(syncProvider)
        .value
        ?.scopedToAccount(accountUuid);
    final state = classifySwapShieldTransaction(
      transactions: syncState?.recentTransactions ?? const [],
      txHash: normalizedTxHash,
    );
    if (state.status == SwapShieldTxStatus.pending ||
        state.status == SwapShieldTxStatus.unknown) {
      final networkState = await _trackShieldTransactionOnNetwork(
        accountUuid: accountUuid,
        txHash: normalizedTxHash,
      );
      if (networkState.status != SwapShieldTxStatus.unknown) {
        if (networkState.status == SwapShieldTxStatus.mined) {
          log(
            'SwapShielding: track mined '
            'tx=${_shortSwapValue(normalizedTxHash)} source=network',
          );
        }
        return networkState;
      }
    }
    if (state.status == SwapShieldTxStatus.mined ||
        state.status == SwapShieldTxStatus.expired) {
      log(
        'SwapShielding: track ${state.status.name} '
        'tx=${_shortSwapValue(normalizedTxHash)}',
      );
    }
    return state;
  }

  Future<SwapShieldTxState> _trackShieldTransactionOnNetwork({
    required String accountUuid,
    required String txHash,
  }) async {
    if (!_txidHexPattern.hasMatch(txHash)) {
      return const SwapShieldTxState(status: SwapShieldTxStatus.unknown);
    }
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = _ref.read(rpcEndpointProvider);
      for (final candidate in _txidCandidateList(txHash)) {
        final height = await rust_sync.checkTransactionMined(
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          txidHex: candidate,
        );
        if (height > 0) {
          try {
            await rust_sync.setTransactionStatus(
              dbPath: dbPath,
              network: endpoint.networkName,
              txidHex: candidate,
              status: height,
            );
          } catch (e) {
            log(
              'SwapShielding: set mined status failed '
              'tx=${_shortSwapValue(candidate)} height=$height error=$e',
            );
          }
          try {
            await _ref.read(syncProvider.notifier).refreshAfterSend();
          } catch (e) {
            log('SwapShielding: post-mined refreshAfterSend failed: $e');
          }
          return const SwapShieldTxState(status: SwapShieldTxStatus.mined);
        }
        if (height == 0) {
          return const SwapShieldTxState(status: SwapShieldTxStatus.pending);
        }
      }
    } catch (e) {
      log(
        'SwapShielding: network track failed '
        'account=${_shortSwapValue(accountUuid)} tx=${_shortSwapValue(txHash)} '
        'error=$e',
      );
    }
    return const SwapShieldTxState(status: SwapShieldTxStatus.unknown);
  }
}

String? _firstTxid(String txids) {
  for (final part in txids.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String _shortSwapValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '-';
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 7)}...${trimmed.substring(trimmed.length - 6)}';
}
