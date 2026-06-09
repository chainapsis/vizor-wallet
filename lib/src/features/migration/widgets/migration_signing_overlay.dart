import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../migration_copy.dart';
import '../models/migration_batch.dart';
import '../providers/migration_expected_transfer_count_provider.dart';

enum _MigrationPhase { preparing, broadcasting, failed }

class MigrationSigningCompletion {
  const MigrationSigningCompletion({
    required this.accountUuid,
    required this.result,
  });

  final String accountUuid;
  final rust_sync.IronwoodMigrationResult result;
}

class MigrationSigningOverlay extends ConsumerStatefulWidget {
  const MigrationSigningOverlay({
    required this.onCancel,
    required this.onComplete,
    super.key,
  });

  final VoidCallback onCancel;
  final ValueChanged<MigrationSigningCompletion> onComplete;

  @override
  ConsumerState<MigrationSigningOverlay> createState() =>
      _MigrationSigningOverlayState();
}

class _MigrationSigningOverlayState
    extends ConsumerState<MigrationSigningOverlay> {
  _MigrationPhase _phase = _MigrationPhase.preparing;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_startMigration());
    });
  }

  Future<void> _startMigration() async {
    setState(() {
      _phase = _MigrationPhase.broadcasting;
      _error = null;
    });
    final providerContainer = ProviderScope.containerOf(context, listen: false);

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
      late final rust_sync.IronwoodMigrationResult result;

      if (Platform.isMacOS) {
        final password = ref
            .read(appSecurityProvider.notifier)
            .requireSessionPasswordForNativeSecretUse();
        try {
          result = await rust_sync
              .migrateOrchardToIronwoodWithMacosStoredMnemonic(
                dbPath: dbPath,
                lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
                network: migrationNetworkName,
                accountUuid: accountUuid,
                password: password,
              );
        } catch (e) {
          final message = e.toString().toLowerCase();
          if (!message.contains('secure storage salt not found') &&
              !message.contains('mnemonic not found for account')) {
            rethrow;
          }
          log(
            'MigrationSigningOverlay: native macOS mnemonic unavailable, '
            'falling back to Dart mnemonic storage: $e',
          );
          result = await _migrateWithMnemonicBytes(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: migrationNetworkName,
            accountUuid: accountUuid,
          );
        }
      } else {
        result = await _migrateWithMnemonicBytes(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: migrationNetworkName,
          accountUuid: accountUuid,
        );
      }

      log(
        'MigrationSigningOverlay: migration txids=${result.txids} '
        'status=${result.status} '
        'broadcasted=${result.broadcastedCount}/${result.totalCount} '
        'fee=${result.feeZatoshi} migrated=${result.migratedZatoshi}',
      );

      final migrationStarted = _migrationStarted(result);
      if (migrationStarted && result.totalCount > 0) {
        providerContainer
            .read(migrationExpectedTransferCountProvider.notifier)
            .setCount(accountUuid, result.totalCount);
      }

      if (!migrationStarted) {
        try {
          await providerContainer
              .read(syncProvider.notifier)
              .refreshAfterSend();
        } catch (e) {
          log('MigrationSigningOverlay: refreshAfterSend failed: $e');
        }
        if (!mounted) return;
        setState(() {
          _phase = _MigrationPhase.failed;
          _error =
              result.message ??
              'Migration transactions were created locally but not fully broadcast. Keep Vizor open and do not start another migration.';
        });
        return;
      }

      try {
        await providerContainer.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('MigrationSigningOverlay: refreshAfterSend failed: $e');
      }

      if (!mounted) return;
      widget.onComplete(
        MigrationSigningCompletion(accountUuid: accountUuid, result: result),
      );
    } catch (e, st) {
      log('MigrationSigningOverlay._startMigration: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _MigrationPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  bool _migrationStarted(rust_sync.IronwoodMigrationResult result) {
    if (result.status == 'broadcasted') return true;
    return result.status == 'partial_broadcast' &&
        result.broadcastedCount > 0 &&
        result.message == null;
  }

  Future<rust_sync.IronwoodMigrationResult> _migrateWithMnemonicBytes({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
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
      );
    } finally {
      mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
    }
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

  void _cancel() {
    if (_phase == _MigrationPhase.broadcasting) return;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final isFailed = _phase == _MigrationPhase.failed;
    return AppPaneModalOverlay(
      onDismiss: _cancel,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
          border: Border.all(color: context.colors.border.subtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFailed ? MigrationCopy.genericError : MigrationCopy.signTitle,
              style: AppTypography.headlineLarge.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              isFailed ? (_error ?? MigrationCopy.genericError) : _subtitle,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (!isFailed) ...[
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.icon.success,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      MigrationCopy.broadcastingInstruction,
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    onPressed: _cancel,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                    child: const Text(MigrationCopy.signBack),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _subtitle => switch (_phase) {
    _MigrationPhase.preparing => MigrationCopy.signSubtitle,
    _MigrationPhase.broadcasting => MigrationCopy.broadcastingSubtitle,
    _MigrationPhase.failed => MigrationCopy.genericError,
  };
}
