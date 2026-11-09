import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../core/storage/linux_keyring_coordinator.dart';
import '../../../core/storage/linux_secret_operation_guard.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/zcash/transparent_ledger_errors.dart';
import '../../../core/zcash/wallet_error_code.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/pending_activity_evidence_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../core/zcash/broadcast_notice_text.dart';
import '../../../core/zcash/network_upgrade_hold.dart';
import '../../../core/l10n/l10n.dart';

/// Whether the shield transaction was stored for a later broadcast retry.
bool shieldBalanceQueuedForRetry(rust_sync.ShieldTransparentResult result) =>
    result.status != 'broadcasted';

String? shieldBalanceBroadcastStatusMessage(
  AppLocalizations l10n,
  rust_sync.ShieldTransparentResult result,
) => shieldBalanceQueuedForRetry(result) ? l10n.homeShieldQueuedForRetry : null;

/// Why a shield attempt stopped before it reached Rust.
enum ShieldPrecondition { balanceTooSmall, secretUnavailable, noActiveAccount }

/// A shield attempt stopped before it reached Rust. The notice explains it,
/// so it carries no detail of its own.
class ShieldPreconditionException implements Exception {
  const ShieldPreconditionException(this.reason);

  final ShieldPrecondition reason;

  @override
  String toString() => 'ShieldPreconditionException: ${reason.name}'; // l10n-ignore: log text
}

String friendlyShieldBalanceError(AppLocalizations l10n, Object error) {
  if (error is ShieldPreconditionException) {
    return switch (error.reason) {
      ShieldPrecondition.balanceTooSmall => l10n.homeShieldErrorTooSmall,
      ShieldPrecondition.secretUnavailable =>
        l10n.homeShieldErrorSeedUnavailable,
      ShieldPrecondition.noActiveAccount => l10n.commonNoActiveAccountSentence,
    };
  }
  switch (walletErrorCode(error)) {
    case rust_sync.ApiWalletErrorCode.optOutUnfinished:
      return privateQueriesOptOutUnfinishedMessage(l10n);
    case rust_sync.ApiWalletErrorCode.recoveryIncomplete:
      return transparentRecoveryIncompleteMessage(l10n);
    default:
      break;
  }
  final upgradeHold = networkUpgradeHoldMessage(l10n, error);
  if (upgradeHold != null) return upgradeHold;
  final message = error.toString();
  if (isTransparentLedgerNeedsNewerBuildError(message)) {
    return transparentLedgerNeedsNewerBuildMessage(l10n);
  }
  if (isTransparentRecoveryIncompleteError(message)) {
    return transparentRecoveryIncompleteMessage(l10n);
  }
  final lower = message.toLowerCase();
  if (lower.contains('mnemonic')) {
    return l10n.homeShieldErrorSeedUnavailable;
  }
  if (lower.contains('sync')) {
    return l10n.homeShieldErrorWaitForSync;
  }
  if (lower.contains('insufficient') ||
      lower.contains('threshold') ||
      lower.contains('too small') ||
      lower.contains('no transparent funds')) {
    return l10n.homeShieldErrorTooSmall;
  }
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return l10n.homeShieldErrorBroadcastFailed;
  }
  return l10n.homeShieldErrorCouldNotShield;
}

String? shieldBalanceErrorDetails(Object error) {
  if (error is ShieldPreconditionException) return null;
  final message = error.toString().trim();
  final lower = message.toLowerCase();
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return null;
  }
  return message.isEmpty ? null : message;
}

typedef SoftwareTransparentShieldRunner =
    Future<rust_sync.ShieldTransparentResult> Function({
      required WidgetRef ref,
      required String accountUuid,
      String logContext,
    });
final softwareTransparentShieldRunnerProvider =
    Provider<SoftwareTransparentShieldRunner>(
      (_) => shieldTransparentSoftwareBalance,
    );

Future<rust_sync.ShieldTransparentResult> shieldTransparentSoftwareBalance({
  required WidgetRef ref,
  required String accountUuid,
  String logContext = 'TransparentShielding',
}) async {
  RpcEndpointConfig? attemptedEndpoint;
  LinuxSecretOperationGuard? secretGuard;
  try {
    secretGuard = LinuxSecretOperationGuard(
      store: ref.read(linuxSecretOperationStoreProvider),
      coordinator: ref.read(linuxKeyringCoordinatorProvider),
      isRequestCurrent: () => ref.context.mounted,
      readAccounts: () => ref.read(accountProvider).value,
      accountUuid: accountUuid,
    );
    final sync = (ref.read(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    if (!sync.canShieldTransparentBalance) {
      throw const ShieldPreconditionException(
        ShieldPrecondition.balanceTooSmall,
      );
    }

    final dbPath = await getWalletDbPath();
    secretGuard.check();
    final endpoint = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .ensureReady();
    secretGuard.check();
    attemptedEndpoint = endpoint;

    late final rust_sync.ShieldTransparentResult result;
    late final Future<rust_sync.ShieldTransparentResult> resultFuture;

    if (Platform.isMacOS && !secretGuard.enabled) {
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
      try {
        secretGuard.check();
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw const ShieldPreconditionException(
            ShieldPrecondition.secretUnavailable,
          );
        }
        resultFuture = rust_sync.shieldTransparentBalance(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          accountUuid: accountUuid,
          mnemonicBytes: mnemonicBytes,
        );
      } finally {
        mnemonicBytes?.fillRange(0, mnemonicBytes.length, 0);
      }
    }

    result = await resultFuture;
    if (secretGuard.enabled && !ref.context.mounted) return result;
    log(
      '$logContext: shielded transparent balance txids=${result.txids} '
      'status=${result.status} '
      'broadcasted=${result.broadcastedCount}/${result.totalCount} '
      'fee=${result.feeZatoshi} shielded=${result.shieldedZatoshi}',
    );
    observeShieldingBroadcast(
      ref: ref,
      accountUuid: accountUuid,
      status: result.status,
      txids: result.txids.split(','),
    );

    final broadcastDetailMessage = result.message?.trim();
    if (shieldBalanceQueuedForRetry(result) &&
        broadcastDetailMessage != null &&
        broadcastDetailMessage.isNotEmpty) {
      final switched = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .switchToFallbackFor(
            broadcastDetailMessage,
            endpoint: attemptedEndpoint,
            operation:
                'shield transparent balance broadcast', // l10n-ignore: log label
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
    if (e is SecureStorageSessionChangedException ||
        (secretGuard?.enabled == true && !ref.context.mounted)) {
      rethrow;
    }
    final switched = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          e,
          endpoint: attemptedEndpoint,
          operation: 'shield transparent balance', // l10n-ignore: log label
        );
    if (switched) {
      unawaited(ref.read(syncProvider.notifier).restartSync());
    }
    rethrow;
  }
}

/// Seed the existing activity ETA only from a confirmed successful broadcast.
/// Keep the proposal's account identity even if the user switches accounts.
/// Partial/unknown batches cannot identify which txids propagated, so they
/// wait for independent mempool evidence instead.
void observeShieldingBroadcast({
  required WidgetRef ref,
  required String? accountUuid,
  required String status,
  required Iterable<String> txids,
}) {
  if (status != 'broadcasted' ||
      accountUuid == null ||
      !ref.context.mounted ||
      ref.read(appSecurityProvider).requiresUnlock ||
      !(ref
              .read(accountProvider)
              .value
              ?.accounts
              .any((account) => account.uuid == accountUuid) ??
          false)) {
    return;
  }
  ref
      .read(pendingActivityEvidenceProvider.notifier)
      .observe(accountUuid: accountUuid, txids: txids);
}

String shieldPcztBroadcastStatusMessage(
  AppLocalizations l10n,
  rust_sync.ExtractAndBroadcastPcztResult result,
) {
  final upgradeHold = networkUpgradeHoldMessage(l10n, result.message ?? '');
  if (upgradeHold != null) return upgradeHold;
  final detail = broadcastResultText(
    l10n,
    notices: result.notices,
    message: result.message,
  );
  if (result.status == 'broadcast_unknown') {
    return detail ?? l10n.homeShieldBroadcastUnknown;
  }
  if (result.status == 'broadcasted_storage_failed') {
    return detail ?? l10n.homeShieldBroadcastNotStored;
  }
  return detail ?? l10n.homeShieldStatusUncertain;
}

/// Whether a hardware broadcast failed only because private recovery has not
/// yet covered the wallet's latest block, so the same signature can be sent
/// again once it has. Only Rust can say so, with its retry code.
bool isHardwareBroadcastRetryable(Object error) =>
    walletErrorCode(error) == rust_sync.ApiWalletErrorCode.retryAfterRecovery;

/// The warning for a shield transaction that reached the network but was not
/// stored locally, or null for any other error.
String? postBroadcastShieldErrorMessage(AppLocalizations l10n, Object error) {
  final raw = error.toString();
  if (!raw.toLowerCase().contains('broadcast succeeded')) return null;
  return l10n.homeShieldBroadcastNotStored;
}

String activeShieldingAccountUuid(WidgetRef ref) {
  final wallet = ref.read(walletProvider).value;
  final accountUuid = wallet?.activeAccountUuid;
  if (accountUuid == null) {
    throw const ShieldPreconditionException(ShieldPrecondition.noActiveAccount);
  }
  return accountUuid;
}
