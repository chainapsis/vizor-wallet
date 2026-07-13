import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/sync_provider.dart';
import '../migration_copy.dart';
import '../models/migration_timeline_model.dart';
import '../models/migration_view_state.dart';
import '../providers/migration_run_controller.dart';
import '../providers/orchard_migration_status_provider.dart';

class GlobalMigrationWarningBanner extends ConsumerStatefulWidget {
  const GlobalMigrationWarningBanner({super.key});

  @override
  ConsumerState<GlobalMigrationWarningBanner> createState() =>
      _GlobalMigrationWarningBannerState();
}

class _GlobalMigrationWarningBannerState
    extends ConsumerState<GlobalMigrationWarningBanner> {
  Timer? _migrationTickTimer;
  bool _migrationTickInFlight = false;

  @override
  void dispose() {
    _migrationTickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(activeOrchardMigrationStatusProvider).value;
    final visible = migrationShouldShowGlobalWarning(status);
    _syncMigrationTick(visible);

    if (!visible) return const SizedBox.shrink();

    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
          border: Border.all(color: colors.border.subtle),
        ),
        child: Row(
          children: [
            AppIcon(
              AppIcons.warning,
              size: AppIconSize.medium,
              color: colors.icon.warning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                MigrationCopy.globalKeepOpenWarning,
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _syncMigrationTick(bool enabled) {
    if (enabled && _migrationTickTimer == null) {
      _migrationTickTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_tickMigrationActivity());
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_tickMigrationActivity());
      });
      return;
    }

    if (!enabled && _migrationTickTimer != null) {
      _migrationTickTimer?.cancel();
      _migrationTickTimer = null;
    }
  }

  Future<void> _tickMigrationActivity() async {
    if (!mounted || _migrationTickInFlight) return;
    _migrationTickInFlight = true;
    try {
      final status = ref.read(activeOrchardMigrationStatusProvider).value;
      if (!migrationShouldShowGlobalWarning(status)) return;

      final now = DateTime.now();
      final hasScheduledPendingBroadcasts =
          migrationHasScheduledPendingBroadcasts(status);
      final shouldRunBroadcastTick = migrationShouldRunBroadcastTick(
        status,
        now,
      );
      final hasSignedChildren = migrationHasSignedChildPczts(status);
      final hasPendingSplitStages = migrationHasPendingSplitStages(status);
      final hadDueScheduledBroadcast = migrationHasDueScheduledBroadcast(
        status,
        now,
      );
      final hasBroadcastedUnconfirmed =
          migrationHasBroadcastedUnconfirmedTransactions(status);

      if (shouldRunBroadcastTick) {
        await ref
            .read(migrationRunControllerProvider.notifier)
            .broadcastDueScheduled();
        if (!mounted) return;
      }

      if (hadDueScheduledBroadcast ||
          hasBroadcastedUnconfirmed ||
          hasPendingSplitStages ||
          hasSignedChildren) {
        await ref.read(syncProvider.notifier).startSyncAnyway();
        if (!mounted) return;
        ref.invalidate(activeOrchardMigrationStatusProvider);
        return;
      }

      if (!hasScheduledPendingBroadcasts &&
          !hasPendingSplitStages &&
          !hasSignedChildren) {
        await ref
            .read(syncProvider.notifier)
            .refreshAfterSend(
              transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
            );
        if (!mounted) return;
        ref.invalidate(activeOrchardMigrationStatusProvider);
      }
    } catch (e) {
      log('GlobalMigrationWarningBanner: migration activity tick failed: $e');
    } finally {
      _migrationTickInFlight = false;
    }
  }
}
