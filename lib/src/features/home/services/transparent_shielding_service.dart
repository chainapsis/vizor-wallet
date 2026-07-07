import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

String? shieldBalanceBroadcastStatusMessage(
  rust_sync.ShieldTransparentResult result,
  AppLocalizations l10n,
) {
  if (result.status == 'broadcasted') return null;
  return l10n.shieldQueuedRetry;
}

String friendlyShieldBalanceError(Object error, AppLocalizations l10n) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('mnemonic')) {
    return l10n.shieldErrorNoPassphrase;
  }
  if (lower.contains('sync')) {
    return l10n.shieldErrorWaitForSync;
  }
  if (lower.contains('insufficient') ||
      lower.contains('threshold') ||
      lower.contains('too small') ||
      lower.contains('no transparent funds')) {
    return l10n.shieldErrorTooSmall;
  }
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return l10n.shieldErrorBroadcast;
  }
  return l10n.shieldErrorGeneric;
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
        network: endpoint.networkName,
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
          network: endpoint.networkName,
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

    final pendingBroadcastRetry = result.status != 'broadcasted';
    final broadcastDetailMessage = result.message?.trim();
    if (pendingBroadcastRetry &&
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
  AppLocalizations l10n,
) {
  if (result.status == 'broadcast_unknown') {
    return result.message ?? l10n.shieldTxBroadcastUnknown;
  }
  if (result.status == 'broadcasted_storage_failed') {
    return result.message ?? l10n.shieldTxStorageFailed;
  }
  return result.message ?? l10n.shieldTxUncertain;
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
