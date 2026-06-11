import 'dart:async';

import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show log;
import '../../features/migration/migration_copy.dart';
import '../../features/migration/models/migration_view_state.dart';
import '../../features/migration/providers/migration_expected_transfer_count_provider.dart';
import '../../features/migration/providers/migration_run_controller.dart';
import '../../features/migration/providers/orchard_migration_status_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_toast.dart';

class AppDesktopShell extends StatelessWidget {
  const AppDesktopShell({
    required this.sidebar,
    required this.pane,
    this.sidebarWidth = 256,
    super.key,
  });

  final Widget sidebar;
  final Widget pane;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: sidebarWidth, child: sidebar),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _GlobalMigrationWarningBanner(),
                    Expanded(child: pane),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlobalMigrationWarningBanner extends ConsumerStatefulWidget {
  const _GlobalMigrationWarningBanner();

  @override
  ConsumerState<_GlobalMigrationWarningBanner> createState() =>
      _GlobalMigrationWarningBannerState();
}

class _GlobalMigrationWarningBannerState
    extends ConsumerState<_GlobalMigrationWarningBanner> {
  Timer? _migrationTickTimer;

  @override
  void dispose() {
    _migrationTickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(activeOrchardMigrationStatusProvider).value;
    final visible = _showsMigrationWarning(status);
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
    try {
      final status = ref.read(activeOrchardMigrationStatusProvider).value;
      if (!_showsMigrationWarning(status)) return;

      final hasScheduledPendingBroadcasts =
          migrationHasScheduledPendingBroadcasts(status);
      final signedChildrenMayFinalize = migrationSignedChildrenMayFinalize(
        status,
      );
      final hasSignedChildren = migrationHasSignedChildPczts(status);
      final hadDueScheduledBroadcast = migrationHasDueScheduledBroadcast(
        status,
        DateTime.now(),
      );
      final hasBroadcastedUnconfirmed =
          migrationHasBroadcastedUnconfirmedTransactions(status);

      if (hasScheduledPendingBroadcasts ||
          signedChildrenMayFinalize ||
          hasSignedChildren) {
        await ref
            .read(migrationRunControllerProvider.notifier)
            .broadcastDueScheduled();
      }

      if (hadDueScheduledBroadcast ||
          hasBroadcastedUnconfirmed ||
          hasSignedChildren) {
        await ref.read(syncProvider.notifier).startSyncAnyway();
        ref.invalidate(activeOrchardMigrationStatusProvider);
        return;
      }

      if (!hasScheduledPendingBroadcasts &&
          !signedChildrenMayFinalize &&
          !hasSignedChildren) {
        await ref
            .read(syncProvider.notifier)
            .refreshAfterSend(
              transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
            );
        ref.invalidate(activeOrchardMigrationStatusProvider);
      }
    } catch (e) {
      log('GlobalMigrationWarningBanner: migration activity tick failed: $e');
    }
  }

  bool _showsMigrationWarning(rust_sync.MigrationStatus? status) {
    return migrationShouldWarnBeforeClose(status) ||
        switch (status?.phase) {
          'building_signing_batch' ||
          'signing_batch' ||
          'broadcast_scheduled' ||
          'broadcasting' ||
          'waiting_migration_confirmations' => true,
          _ => false,
        };
  }
}

class AppDesktopSidebarSurface extends StatelessWidget {
  const AppDesktopSidebarSurface({
    required this.child,
    this.backgroundColor,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final Widget child;
  final Color? backgroundColor;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

class AppDesktopPane extends StatelessWidget {
  const AppDesktopPane({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppToastHost(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AppSidebarItem extends StatelessWidget {
  const AppSidebarItem({
    required this.label,
    this.iconName,
    this.leading,
    this.active = false,
    this.onTap,
    this.leadingGap = AppSpacing.s,
    super.key,
  }) : assert(iconName != null || leading != null);

  final String label;
  final String? iconName;
  final Widget? leading;
  final bool active;
  final VoidCallback? onTap;
  final double leadingGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = onTap == null && !active;
    final iconColor = disabled ? colors.icon.disabled : colors.icon.accent;
    final textColor = disabled ? colors.text.disabled : colors.text.accent;
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: active ? colors.state.selectedOpacity : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          leading ?? AppIcon(iconName!, size: 20, color: iconColor),
          SizedBox(width: leadingGap),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );

    return onTap == null
        ? row
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            ),
          );
  }
}
