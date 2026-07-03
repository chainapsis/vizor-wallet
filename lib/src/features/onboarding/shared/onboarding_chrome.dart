import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/desktop_sidebar_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_icon.dart';

class OnboardingBackTarget {
  const OnboardingBackTarget.route({
    required this.label,
    required String routePath,
    Object? routeExtra,
  }) : _routePath = routePath,
       _routeExtra = routeExtra,
       _onTap = null;

  const OnboardingBackTarget.callback({
    required this.label,
    required VoidCallback onTap,
  }) : _routePath = null,
       _routeExtra = null,
       _onTap = onTap;

  final String label;
  final String? _routePath;
  final Object? _routeExtra;
  final VoidCallback? _onTap;

  void navigate(BuildContext context) {
    final onTap = _onTap;
    if (onTap != null) {
      onTap();
      return;
    }

    context.go(_routePath!, extra: _routeExtra);
  }
}

class OnboardingPaneChrome extends StatelessWidget {
  const OnboardingPaneChrome({
    required this.child,
    this.backTarget,
    this.overlay,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 16, 12, 16),
    super.key,
  });

  final Widget child;
  final OnboardingBackTarget? backTarget;
  final Widget? overlay;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) {
    return AppDesktopPane(
      padding: EdgeInsets.zero,
      paintBackground: false,
      child: OnboardingPaneScaffold(
        backTarget: backTarget,
        overlay: overlay,
        bodyPadding: bodyPadding,
        child: child,
      ),
    );
  }
}

class OnboardingPaneScaffold extends StatelessWidget {
  const OnboardingPaneScaffold({
    required this.child,
    this.backTarget,
    this.overlay,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 16, 12, 16),
    super.key,
  });

  final Widget child;
  final OnboardingBackTarget? backTarget;
  final Widget? overlay;
  final EdgeInsetsGeometry bodyPadding;

  static const double toolbarHeight = 48;

  @override
  Widget build(BuildContext context) {
    final overlay = this.overlay;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            OnboardingPaneToolbar(backTarget: backTarget),
            Expanded(
              child: Padding(padding: bodyPadding, child: child),
            ),
          ],
        ),
        ?overlay,
      ],
    );
  }
}

class OnboardingPaneToolbar extends StatelessWidget {
  const OnboardingPaneToolbar({this.backTarget, super.key});

  final OnboardingBackTarget? backTarget;

  @override
  Widget build(BuildContext context) {
    final backTarget = this.backTarget;
    return SizedBox(
      height: OnboardingPaneScaffold.toolbarHeight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: backTarget == null
              ? const SizedBox.shrink()
              : AppBackLink(
                  label: backTarget.label,
                  onTap: () => backTarget.navigate(context),
                ),
        ),
      ),
    );
  }
}

class OnboardingSidebarStepData {
  const OnboardingSidebarStepData({
    required this.label,
    required this.iconName,
    required this.active,
    this.onTap,
  });

  final String label;
  final String iconName;
  final bool active;
  final VoidCallback? onTap;
}

class OnboardingSidebarChrome extends StatelessWidget {
  const OnboardingSidebarChrome({
    required this.steps,
    required this.illustration,
    super.key,
  });

  final List<OnboardingSidebarStepData> steps;
  final Widget illustration;

  @override
  Widget build(BuildContext context) {
    final isDark = context.appTheme == AppThemeData.dark;
    final navPanelMaterial = isDark
        ? const Color(0xFF1A1A1A).withValues(alpha: 0.3)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.3);
    final navPanelFill = Color.alphaBlend(
      navPanelMaterial,
      context.colors.background.window,
    );

    return AppDesktopSidebarSurface(
      glass: true,
      backgroundColor: navPanelFill,
      child: Stack(
        children: [
          Positioned.fill(child: illustration),
          Positioned.fill(
            top: onboardingSidebarTopOffset(),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: OnboardingSidebarNav(steps: steps),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingSidebarNav extends StatelessWidget {
  const OnboardingSidebarNav({required this.steps, super.key});

  final List<OnboardingSidebarStepData> steps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            OnboardingSidebarItem(step: steps[i]),
            if (i != steps.length - 1) const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class OnboardingSidebarItem extends StatelessWidget {
  const OnboardingSidebarItem({required this.step, super.key});

  final OnboardingSidebarStepData step;

  static const _labelStyle = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 16 / 14,
    letterSpacing: -0.06,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = step.active
        ? colors.navPanel.activeIcon
        : colors.icon.regular;
    final textColor = step.active
        ? colors.navPanel.activeLabel
        : colors.text.accent;

    final item = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 40,
      padding: const EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: step.active ? colors.navPanel.activeBg : null,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        children: [
          AppIcon(step.iconName, size: 20, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              step.label,
              overflow: TextOverflow.ellipsis,
              style: _labelStyle.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );

    final onTap = step.onTap;
    if (onTap == null) return item;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: item,
      ),
    );
  }
}
