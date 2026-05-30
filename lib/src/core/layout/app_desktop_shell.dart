import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_toast.dart';
import '../../features/voting/widgets/voting_submission_progress_banner.dart';

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
                    const VotingSubmissionProgressBanner(),
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
