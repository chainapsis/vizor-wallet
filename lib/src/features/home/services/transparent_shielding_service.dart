import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

const shieldBalancePendingBroadcastMessage =
    'Shielding queued for retry. Check Activity.';

String? shieldBalanceBroadcastStatusMessage(
  rust_sync.ShieldTransparentResult result,
) {
  if (result.status == 'broadcasted') return null;
  return shieldBalancePendingBroadcastMessage;
}

String friendlyShieldBalanceError(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('mnemonic')) {
    return "Secret Passphrase isn't available for this account.";
  }
  if (lower.contains('sync')) {
    return 'Wait for sync to finish, then shield.';
  }
  if (lower.contains('insufficient') ||
      lower.contains('threshold') ||
      lower.contains('too small') ||
      lower.contains('no transparent funds')) {
    return 'Transparent balance is too small to shield after fees.';
  }
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return "Couldn't broadcast your shielding transaction. Try again.";
  }
  return "Couldn't shield your balance. Try again.";
}

String? shieldBalanceErrorDetails(Object error) {
  final message = error.toString().trim();
  final lower = message.toLowerCase();
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return null;
  }
  return message.isEmpty ? null : message;
}

Future<rust_sync.ShieldTransparentResult> shieldTransparentSoftwareBalance({
  required WidgetRef ref,
  required String accountUuid,
  String logContext = 'TransparentShielding',
}) async {
  RpcEndpointConfig? attemptedEndpoint;
  try {
    final sync = (ref.read(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    if (!sync.canShieldTransparentBalance) {
      throw Exception('Transparent balance is too small to shield after fees.');
    }

    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    attemptedEndpoint = endpoint;

    late final rust_sync.ShieldTransparentResult result;
    late final Future<rust_sync.ShieldTransparentResult> resultFuture;

    if (Platform.isMacOS) {
      final password = ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      resultFuture = rust_sync.shieldTransparentBalanceWithMacosStoredMnemonic(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.walletNetworkName,
        accountUuid: accountUuid,
        password: password,
      );
    } else {
      final accountNotifier = ref.read(accountProvider.notifier);
      final mnemonicBytes = await accountNotifier.getMnemonicBytesForAccount(
        accountUuid,
      );
      if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
        throw Exception('Mnemonic not found for the active account.');
      }

      try {
        resultFuture = rust_sync.shieldTransparentBalance(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.walletNetworkName,
          accountUuid: accountUuid,
          mnemonicBytes: mnemonicBytes,
        );
      } finally {
        mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
      }
    }

    result = await resultFuture;
    log(
      '$logContext: shielded transparent balance txids=${result.txids} '
      'status=${result.status} '
      'broadcasted=${result.broadcastedCount}/${result.totalCount} '
      'fee=${result.feeZatoshi} shielded=${result.shieldedZatoshi}',
    );

    final broadcastStatusMessage = shieldBalanceBroadcastStatusMessage(result);
    final broadcastDetailMessage = result.message?.trim();
    if (broadcastStatusMessage != null &&
        broadcastDetailMessage != null &&
        broadcastDetailMessage.isNotEmpty) {
      final switched = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .switchToFallbackFor(
            broadcastDetailMessage,
            endpoint: attemptedEndpoint,
            operation: 'shield transparent balance broadcast',
          );
      if (switched) {
        unawaited(ref.read(syncProvider.notifier).restartSync());
      }
    }

    try {
      await ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (e) {
      log('$logContext: refreshAfterSend after shielding failed: $e');
    }

    return result;
  } catch (e, st) {
    log('$logContext: shield transparent balance failed: $e\n$st');
    final switched = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          e,
          endpoint: attemptedEndpoint,
          operation: 'shield transparent balance',
        );
    if (switched) {
      unawaited(ref.read(syncProvider.notifier).restartSync());
    }
    rethrow;
  }
}

String shieldPcztBroadcastStatusMessage(
  rust_sync.ExtractAndBroadcastPcztResult result,
) {
  if (result.status == 'broadcast_unknown') {
    return result.message ??
        'The shield transaction may have reached the network, but confirmation timed out. Check activity before trying again.';
  }
  if (result.status == 'broadcasted_storage_failed') {
    return result.message ??
        'The shield transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';
  }
  return result.message ??
      'The shield transaction status is uncertain. Check activity before trying again.';
}

String? postBroadcastShieldErrorMessage(Object error) {
  final raw = error.toString();
  if (!raw.toLowerCase().contains('broadcast succeeded')) return null;
  return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
}

String activeShieldingAccountUuid(WidgetRef ref) {
  final wallet = ref.read(walletProvider).value;
  final accountUuid = wallet?.activeAccountUuid;
  if (accountUuid == null) {
    throw Exception('No active account.');
  }
  return accountUuid;
}
