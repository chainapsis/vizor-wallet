import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../migration_copy.dart';
import '../models/migration_batch.dart';
import '../models/migration_timeline_model.dart';
import 'orchard_migration_status_provider.dart';

class MigrationRunState {
  const MigrationRunState({
    this.intent = MigrationRunIntent.none,
    this.inFlight = false,
    this.settling = false,
    this.error,
    this.errorIntent,
  });

  final MigrationRunIntent intent;
  final bool inFlight;
  final bool settling;
  final String? error;

  /// Which step card shows [error]. Null when there is no error.
  final MigrationRunIntent? errorIntent;

  /// True while the UI should keep showing the stage progress view even if the
  /// status provider has not caught up yet.
  bool get keepsProgressVisible => inFlight || settling;
}

/// True when the Rust call advanced the run. Successful stage outcomes
/// report run-phase strings, not 'broadcasted': stage 1 returns
/// waiting_denom_confirmations, stage 2 returns
/// broadcast_scheduled once transactions are signed and scheduled, then
/// waiting_migration_confirmations after the last scheduled broadcast
/// submission. A retry can also return ready_to_migrate if sync already made
/// denomination outputs spendable before the retry recorded local state.
bool migrationRunAdvanced(rust_sync.IronwoodMigrationResult result) {
  return switch (result.status) {
    'broadcasted' ||
    'broadcast_scheduled' ||
    'waiting_denom_confirmations' ||
    'ready_to_migrate' ||
    'waiting_migration_confirmations' => true,
    'partial_broadcast' =>
      result.broadcastedCount > 0 && result.message == null,
    _ => false,
  };
}

class MigrationRunController extends Notifier<MigrationRunState> {
  Timer? _progressTimer;
  Timer? _settleTimer;
  bool _dueBroadcastInFlight = false;

  @override
  MigrationRunState build() {
    ref.onDispose(() {
      _progressTimer?.cancel();
      _progressTimer = null;
      _settleTimer?.cancel();
      _settleTimer = null;
    });
    return const MigrationRunState();
  }

  /// Advances the migration run one stage. The Rust entry point is
  /// stage-aware: with no active run it splits notes into denominations;
  /// with an active run it signs and schedules the migration transactions.
  Future<bool> advance(MigrationRunIntent intent) async {
    if (state.inFlight) return false;
    _settleTimer?.cancel();
    _settleTimer = null;
    state = MigrationRunState(intent: intent, inFlight: true);
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ref.invalidate(activeOrchardMigrationStatusProvider);
    });

    try {
      final accountState = ref.read(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      if (account == null || accountUuid == null) {
        throw MigrationBatchError('No active account.');
      }
      if (account.isHardware) {
        throw MigrationBatchError(
          'Switch to a software account before migrating.',
        );
      }

      final endpoint = ref.read(rpcEndpointProvider);
      final dbPath = await getWalletDbPath();
      final migrationNetworkName = endpoint.walletNetworkName;
      final security = ref.read(appSecurityProvider.notifier);
      final password = security.requireSessionPasswordForNativeSecretUse();
      final saltBase64 = await security
          .requireSecretPayloadSaltForNativeSecretUse();
      final result = await _runMigrationWithPrepareRetry(
        intent: intent,
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: migrationNetworkName,
        accountUuid: accountUuid,
        password: password,
        saltBase64: saltBase64,
      );

      log(
        'MigrationRunController: intent=${intent.name} '
        'txids=${result.txids} status=${result.status} '
        'broadcasted=${result.broadcastedCount}/${result.totalCount} '
        'fee=${result.feeZatoshi} migrated=${result.migratedZatoshi}',
      );

      final advanced = migrationRunAdvanced(result);
      if (advanced) {
        _showSettlingState(intent);
      } else {
        state = MigrationRunState(
          intent: intent,
          error: result.message ?? MigrationCopy.partialBroadcastError,
          errorIntent: intent,
        );
      }

      unawaited(
        _refreshIfAccountStillActive(accountUuid).catchError((Object e) {
          log('MigrationRunController: refreshAfterSend failed: $e');
        }),
      );
      return advanced;
    } catch (e, st) {
      if (_isActiveMigrationError(e)) {
        log(
          'MigrationRunController.advance: migration already active; '
          'reconciling from status',
        );
        state = const MigrationRunState();
        return true;
      } else {
        log('MigrationRunController.advance: ERROR: $e\n$st');
        state = MigrationRunState(
          intent: intent,
          error: _friendlyError(e),
          errorIntent: intent,
        );
        return false;
      }
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
      ref.invalidate(activeOrchardMigrationStatusProvider);
    }
  }

  void settleAfterExternalAdvance(MigrationRunIntent intent) {
    if (state.inFlight) return;
    _showSettlingState(intent);
  }

  void _showSettlingState(MigrationRunIntent intent) {
    _settleTimer?.cancel();
    state = MigrationRunState(intent: intent, settling: true);
    _settleTimer = Timer(const Duration(seconds: 5), () {
      final current = state;
      if (current.settling && current.intent == intent) {
        state = const MigrationRunState();
        ref.invalidate(activeOrchardMigrationStatusProvider);
      }
    });
  }

  Future<rust_sync.IronwoodMigrationResult> _runMigrationWithPrepareRetry({
    required MigrationRunIntent intent,
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String password,
    required String saltBase64,
  }) async {
    try {
      return await _runMigrationNative(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        password: password,
        saltBase64: saltBase64,
      );
    } catch (e) {
      if (intent != MigrationRunIntent.preparing ||
          !_isTransientPrepareSpendabilityError(e)) {
        rethrow;
      }

      log(
        'MigrationRunController: prepare saw transient spendability error; '
        'refreshing wallet state and retrying once: $e',
      );
      await _refreshIfAccountStillActive(accountUuid);
      ref.invalidate(activeOrchardMigrationStatusProvider);

      return _runMigrationNative(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        password: password,
        saltBase64: saltBase64,
      );
    }
  }

  Future<rust_sync.IronwoodMigrationResult> _runMigrationNative({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String password,
    required String saltBase64,
  }) async {
    final syncNotifier = ref.read(syncProvider.notifier);
    final syncPause = await syncNotifier.pauseForWalletMutation(
      onStoppingSync: () {
        log(
          'MigrationRunController: pausing sync before migration wallet '
          'mutation',
        );
      },
    );

    try {
      if (Platform.isMacOS && !kDebugMode) {
        try {
          return await rust_sync
              .migrateOrchardToIronwoodWithMacosStoredMnemonic(
                dbPath: dbPath,
                lightwalletdUrl: lightwalletdUrl,
                network: network,
                accountUuid: accountUuid,
                password: password,
                saltBase64: saltBase64,
              );
        } catch (e) {
          final message = e.toString().toLowerCase();
          if (!message.contains('secure storage salt not found') &&
              !message.contains('mnemonic not found for account')) {
            rethrow;
          }
          log(
            'MigrationRunController: native macOS mnemonic unavailable, '
            'falling back to Dart mnemonic storage: $e',
          );
          return await _migrateWithMnemonicBytes(
            dbPath: dbPath,
            lightwalletdUrl: lightwalletdUrl,
            network: network,
            accountUuid: accountUuid,
            password: password,
            saltBase64: saltBase64,
          );
        }
      }

      return await _migrateWithMnemonicBytes(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        password: password,
        saltBase64: saltBase64,
      );
    } finally {
      syncNotifier.resumeAfterWalletMutation(syncPause);
    }
  }

  /// Submits any already signed migration transactions whose scheduled time
  /// has arrived. This keeps the migration page responsive after stage 2 has
  /// signed and scheduled the batch.
  Future<void> broadcastDueScheduled() async {
    if (_dueBroadcastInFlight || state.inFlight) return;
    _dueBroadcastInFlight = true;

    String? accountUuid;
    try {
      final accountState = ref.read(accountProvider).value;
      final account = accountState?.activeAccount;
      accountUuid = accountState?.activeAccountUuid;
      if (account == null || accountUuid == null) return;

      final endpoint = ref.read(rpcEndpointProvider);
      final dbPath = await getWalletDbPath();
      final security = ref.read(appSecurityProvider.notifier);
      final password = security.requireSessionPasswordForNativeSecretUse();
      final saltBase64 = await security
          .requireSecretPayloadSaltForNativeSecretUse();
      final syncNotifier = ref.read(syncProvider.notifier);
      final syncPause = await syncNotifier.pauseForWalletMutation(
        onStoppingSync: () {
          log(
            'MigrationRunController: pausing sync before due migration '
            'broadcast',
          );
        },
      );

      late final rust_sync.IronwoodMigrationResult result;
      try {
        result = await rust_sync.broadcastDueOrchardMigrationTransactions(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.walletNetworkName,
          accountUuid: accountUuid,
          password: password,
          saltBase64: saltBase64,
        );
      } finally {
        syncNotifier.resumeAfterWalletMutation(syncPause);
      }

      log(
        'MigrationRunController: due broadcast status=${result.status} '
        'broadcasted=${result.broadcastedCount}/${result.totalCount}',
      );

      await _refreshIfAccountStillActive(accountUuid);
    } catch (e, st) {
      if (_isActiveMigrationError(e)) {
        log(
          'MigrationRunController.broadcastDueScheduled: migration already '
          'active; skipping this tick',
        );
      } else {
        log('MigrationRunController.broadcastDueScheduled: ERROR: $e\n$st');
      }
    } finally {
      _dueBroadcastInFlight = false;
      ref.invalidate(activeOrchardMigrationStatusProvider);
    }
  }

  Future<rust_sync.IronwoodMigrationResult> _migrateWithMnemonicBytes({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String password,
    required String saltBase64,
  }) async {
    final mnemonicBytes = await ref
        .read(accountProvider.notifier)
        .getMnemonicBytesForAccount(accountUuid);
    if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
      throw MigrationBatchError('Mnemonic not found for the active account.');
    }

    try {
      return await rust_sync.migrateOrchardToIronwood(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        mnemonicBytes: mnemonicBytes,
        password: password,
        saltBase64: saltBase64,
      );
    } finally {
      mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
    }
  }

  Future<void> _refreshIfAccountStillActive(String accountUuid) async {
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    if (activeAccountUuid != accountUuid) return;
    await ref
        .read(syncProvider.notifier)
        .refreshAfterSend(
          transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
        );
  }

  String _friendlyError(Object error) {
    if (error is MigrationBatchError) return error.message;
    final lower = error.toString().toLowerCase();
    if (lower.contains('insufficient') || lower.contains('spendable')) {
      return 'Receive enough Orchard funds, let Vizor sync, then try again.';
    }
    if (lower.contains('sync') || lower.contains('scan required')) {
      return 'Sync the wallet before migrating.';
    }
    return '${error.runtimeType}: $error';
  }

  bool _isActiveMigrationError(Object error) {
    return error.toString().toLowerCase().contains(
      'ironwood migration is already running',
    );
  }

  bool _isTransientPrepareSpendabilityError(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('insufficient spendable orchard funds') ||
        (lower.contains('insufficient') && lower.contains('orchard')) ||
        lower.contains('spendable');
  }
}

final migrationRunControllerProvider =
    NotifierProvider<MigrationRunController, MigrationRunState>(
      MigrationRunController.new,
    );
