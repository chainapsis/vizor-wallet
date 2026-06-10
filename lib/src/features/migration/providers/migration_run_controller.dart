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
import '../models/migration_step_state.dart';
import 'migration_expected_transfer_count_provider.dart';
import 'orchard_migration_status_provider.dart';

class MigrationRunState {
  const MigrationRunState({
    this.intent = MigrationRunIntent.none,
    this.inFlight = false,
    this.error,
    this.errorIntent,
  });

  final MigrationRunIntent intent;
  final bool inFlight;
  final String? error;

  /// Which step card shows [error]. Null when there is no error.
  final MigrationRunIntent? errorIntent;
}

/// True when the Rust call advanced the run. Successful stage outcomes
/// report run-phase strings, not 'broadcasted': stage 1 returns
/// waiting_denom_confirmations, stage 2 returns
/// waiting_migration_confirmations (and its benign "notes not spendable
/// yet" no-op also returns waiting_denom_confirmations).
bool migrationRunAdvanced(rust_sync.IronwoodMigrationResult result) {
  return switch (result.status) {
    'broadcasted' ||
    'waiting_denom_confirmations' ||
    'waiting_migration_confirmations' => true,
    'partial_broadcast' =>
      result.broadcastedCount > 0 && result.message == null,
    _ => false,
  };
}

class MigrationRunController extends Notifier<MigrationRunState> {
  Timer? _progressTimer;

  @override
  MigrationRunState build() {
    ref.onDispose(() {
      _progressTimer?.cancel();
      _progressTimer = null;
    });
    return const MigrationRunState();
  }

  /// Advances the migration run one stage. The Rust entry point is
  /// stage-aware: with no active run it splits notes into denominations;
  /// with an active run it signs and submits the migration transactions
  /// over the broadcast window.
  Future<void> advance(MigrationRunIntent intent) async {
    if (state.inFlight) return;
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
      if (endpoint.network != ZcashNetwork.testnet) {
        throw MigrationBatchError(
          'Select a testnet endpoint before migrating.',
        );
      }

      final dbPath = await getWalletDbPath();
      final migrationNetworkName = endpoint.walletNetworkName;
      final security = ref.read(appSecurityProvider.notifier);
      final password = security.requireSessionPasswordForNativeSecretUse();
      final saltBase64 = await security
          .requireSecretPayloadSaltForNativeSecretUse();
      late final rust_sync.IronwoodMigrationResult result;

      if (Platform.isMacOS && !kDebugMode) {
        try {
          result = await rust_sync
              .migrateOrchardToIronwoodWithMacosStoredMnemonic(
                dbPath: dbPath,
                lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
                network: migrationNetworkName,
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
          result = await _migrateWithMnemonicBytes(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: migrationNetworkName,
            accountUuid: accountUuid,
            password: password,
            saltBase64: saltBase64,
          );
        }
      } else {
        result = await _migrateWithMnemonicBytes(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: migrationNetworkName,
          accountUuid: accountUuid,
          password: password,
          saltBase64: saltBase64,
        );
      }

      log(
        'MigrationRunController: intent=${intent.name} '
        'txids=${result.txids} status=${result.status} '
        'broadcasted=${result.broadcastedCount}/${result.totalCount} '
        'fee=${result.feeZatoshi} migrated=${result.migratedZatoshi}',
      );

      final firstTxid = _firstTxid(result.txids);
      if (result.broadcastedCount > 0 &&
          result.totalCount > 0 &&
          firstTxid != null) {
        ref
            .read(migrationExpectedTransferCountProvider.notifier)
            .setCount(accountUuid, result.totalCount, firstTxid: firstTxid);
      }

      if (migrationRunAdvanced(result)) {
        state = const MigrationRunState();
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
    } catch (e, st) {
      if (_isActiveMigrationError(e)) {
        log(
          'MigrationRunController.advance: migration already active; '
          'reconciling from status',
        );
        state = const MigrationRunState();
      } else {
        log('MigrationRunController.advance: ERROR: $e\n$st');
        state = MigrationRunState(
          intent: intent,
          error: _friendlyError(e),
          errorIntent: intent,
        );
      }
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
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

  String? _firstTxid(String txids) {
    for (final txid in txids.split(',')) {
      final trimmed = txid.trim();
      if (trimmed.isNotEmpty) return trimmed.toLowerCase();
    }
    return null;
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
}

final migrationRunControllerProvider =
    NotifierProvider<MigrationRunController, MigrationRunState>(
      MigrationRunController.new,
    );
