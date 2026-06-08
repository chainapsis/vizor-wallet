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
import '../providers/migration_demo_provider.dart';

enum _MigrationPhase { preparing, broadcasting, failed }

class MigrationSigningOverlay extends ConsumerStatefulWidget {
  const MigrationSigningOverlay({
    required this.onCancel,
    required this.onComplete,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onComplete;

  @override
  ConsumerState<MigrationSigningOverlay> createState() =>
      _MigrationSigningOverlayState();
}

class _MigrationSigningOverlayState
    extends ConsumerState<MigrationSigningOverlay> {
  static const int _transferCount = 3;
  static const int _amountPerTransferZatoshi = 10000; // 0.0001 ZEC

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
      if (endpoint.networkName != ZcashNetwork.testnet.name ||
          endpoint.effectivePresetId !=
              kLocalIronwoodTestnetRpcEndpointPresetId) {
        throw MigrationBatchError(
          'Select the Local Ironwood testnet endpoint before migrating.',
        );
      }

      final dbPath = await getWalletDbPath();
      late final rust_sync.IronwoodMigrationResult result;

      if (Platform.isMacOS) {
        final password = ref
            .read(appSecurityProvider.notifier)
            .requireSessionPasswordForNativeSecretUse();
        result = await rust_sync
            .migrateOrchardToIronwoodWithMacosStoredMnemonic(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              accountUuid: accountUuid,
              password: password,
              amountZatoshi: BigInt.from(_amountPerTransferZatoshi),
              transferCount: _transferCount,
            );
      } else {
        final mnemonicBytes = await ref
            .read(accountProvider.notifier)
            .getMnemonicBytesForAccount(accountUuid);
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw MigrationBatchError(
            'Mnemonic not found for the active account.',
          );
        }

        late final Future<rust_sync.IronwoodMigrationResult> resultFuture;
        try {
          resultFuture = rust_sync.migrateOrchardToIronwood(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            mnemonicBytes: mnemonicBytes,
            amountZatoshi: BigInt.from(_amountPerTransferZatoshi),
            transferCount: _transferCount,
          );
        } finally {
          mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
        }
        result = await resultFuture;
      }

      log(
        'MigrationSigningOverlay: migration txids=${result.txids} '
        'status=${result.status} '
        'broadcasted=${result.broadcastedCount}/${result.totalCount} '
        'fee=${result.feeZatoshi} migrated=${result.migratedZatoshi}',
      );

      if (result.status != 'broadcasted') {
        try {
          await ref.read(syncProvider.notifier).refreshAfterSend();
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

      final txids = result.txids
          .split(',')
          .map((txid) => txid.trim())
          .where((txid) => txid.isNotEmpty)
          .toList(growable: false);
      await ref
          .read(migrationDemoProvider.notifier)
          .startDemoForAccount(
            accountUuid: accountUuid,
            displayAmountZatoshi: result.migratedZatoshi,
            txids: txids,
          );

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('MigrationSigningOverlay: refreshAfterSend failed: $e');
      }

      if (!mounted) return;
      widget.onComplete();
    } catch (e, st) {
      log('MigrationSigningOverlay._startMigration: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _MigrationPhase.failed;
        _error = _friendlyError(e);
      });
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
    return MigrationCopy.genericError;
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
