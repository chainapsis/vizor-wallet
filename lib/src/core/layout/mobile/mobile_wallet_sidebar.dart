import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import '../../formatting/sync_status_label.dart';
import '../../navigation/mobile_destinations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_icon.dart';
import 'mobile_sync_status.dart';
import 'mobile_sidebar_surface.dart';

/// A mobile component, intentionally independent of the desktop sidebar.
/// Data is injected so window/typography/accessibility states can be captured
/// without a wallet database, secure storage, network, or Rust.
class MobileWalletSidebar extends StatelessWidget {
  const MobileWalletSidebar({
    required this.accountName,
    required this.avatar,
    required this.status,
    required this.currentPath,
    required this.swapEnabled,
    required this.onSelect,
    required this.onAccountTap,
    this.inputBlocked = false,
    super.key,
  });
  final String accountName;
  final Widget avatar;
  final SyncStatusLabel status;
  final String currentPath;
  final bool swapEnabled;
  final ValueChanged<String>? onSelect;
  final VoidCallback? onAccountTap;

  /// A temporary navigation lock preserves paint while blocking pointer,
  /// keyboard focus, and pointer-related accessibility actions. Null callbacks
  /// still represent actual route restrictions. A full lock uses a panel veil;
  /// a profile-only restriction retains the individual disabled style.
  final bool inputBlocked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fullyDisabled = onSelect == null && onAccountTap == null;
    final veilColor = colors.background.window.withValues(alpha: 0.6);
    final items = [
      for (final item in mobileDestinations)
        if (swapEnabled || item.path != '/swap') item,
    ];
    final controls = Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AppButton(
              variant: AppButtonVariant.ghost,
              onPressed: onAccountTap,
              disabledBackgroundColor: fullyDisabled
                  ? colors.background.ground.withValues(alpha: 0)
                  : null,
              height: 72,
              growWithContent: true,
              constrainContent: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Text(
                      accountName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: fullyDisabled ? colors.button.ghost.label : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final destination in items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Semantics(
                selected: _selected(destination.path),
                child: AppButton(
                  variant: AppButtonVariant.ghost,
                  height: 52,
                  growWithContent: true,
                  expand: true,
                  constrainContent: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  disabledBackgroundColor: fullyDisabled
                      ? (_selected(destination.path)
                            ? colors.navPanel.activeBg
                            : colors.background.ground.withValues(alpha: 0))
                      : null,
                  enabledBackgroundColor: _selected(destination.path)
                      ? colors.navPanel.activeBg
                      : null,
                  enabledLabelColor: _selected(destination.path)
                      ? colors.navPanel.activeIcon
                      : null,
                  onPressed: onSelect == null
                      ? null
                      : () => onSelect!(destination.path),
                  child: Row(
                    children: [
                      AppIcon(
                        destination.item.iconName,
                        size: 24,
                        color: _selected(destination.path)
                            ? colors.navPanel.activeIcon
                            : colors.icon.muted,
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          destination.item.label,
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: fullyDisabled
                                ? (_selected(destination.path)
                                      ? colors.navPanel.activeIcon
                                      : colors.button.ghost.label)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const Spacer(),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
    final panel = MobileSidebarSurface.builder(
      builder: (context, corners) {
        final bottomClearance = MediaQuery.paddingOf(
          context,
        ).bottom.clamp(corners.bottomLeft.y + AppSpacing.sm, double.infinity);
        return LayoutBuilder(
          builder: (context, constraints) {
            // Both regions share one scroll layout. Their contiguous veils
            // cover the entire panel, while the single sync widget paints last
            // (including its glow). No duplicate footer or deferred measurement.
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          fit: StackFit.passthrough,
                          children: [
                            Semantics(
                              enabled: fullyDisabled ? false : null,
                              child: controls,
                            ),
                            if (fullyDisabled)
                              Positioned.fill(
                                child: _SidebarVeil(
                                  key: const ValueKey(
                                    'mobile_sidebar_controls_veil',
                                  ),
                                  color: veilColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (fullyDisabled)
                            Positioned.fill(
                              child: _SidebarVeil(
                                key: const ValueKey(
                                  'mobile_sidebar_footer_veil',
                                ),
                                color: veilColor,
                              ),
                            ),
                          Padding(
                            key: const ValueKey(
                              'mobile_sidebar_sync_foreground',
                            ),
                            // Keep the bar and its glow above the same native
                            // bottom corner used to paint and clip the panel.
                            padding: EdgeInsets.only(
                              right: 16,
                              bottom: bottomClearance,
                            ),
                            child: MobileSyncStatus.fromStatus(
                              context: context,
                              status: status,
                              leading: true,
                              wrapLabel: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    // Establish text defaults independently of surrounding route Material widgets.
    // Establish a complete mobile text style instead of inheriting the
    // MaterialApp fallback's yellow double underline.
    return ExcludeFocus(
      excluding: inputBlocked,
      child: AbsorbPointer(
        absorbing: inputBlocked,
        child: Material(
          type: MaterialType.transparency,
          textStyle: AppTypography.bodyMedium.copyWith(
            color: colors.text.accent,
            decoration: TextDecoration.none,
          ),
          child: panel,
        ),
      ),
    );
  }

  bool _selected(String path) =>
      currentPath == path ||
      currentPath.startsWith('$path/') ||
      (path == '/home' &&
          (currentPath == '/accounts' ||
              currentPath.startsWith('/send') ||
              currentPath.startsWith('/receive') ||
              currentPath.startsWith('/migration')));
}

/// Visual treatment only: actual callbacks remain null, so pointer, keyboard,
/// and accessibility activation stay disabled while read-only scrolling works.
class _SidebarVeil extends StatelessWidget {
  const _SidebarVeil({required this.color, super.key});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: ColoredBox(color: color));
}
