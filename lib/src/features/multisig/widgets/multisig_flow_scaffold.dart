import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

class MultisigFlowScaffold extends StatelessWidget {
  const MultisigFlowScaffold({
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final String iconName;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AppDesktopPane(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(trailing: trailing),
                    const SizedBox(height: AppSpacing.md),
                    MultisigScreenTitle(
                      title: title,
                      subtitle: subtitle,
                      iconName: iconName,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                context.canPop() ? context.pop() : context.go('/welcome'),
            child: SizedBox(
              height: 32,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.chevronBackward,
                    size: AppIconSize.medium,
                    color: colors.text.accent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Back',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class MultisigScreenTitle extends StatelessWidget {
  const MultisigScreenTitle({
    required this.title,
    required this.subtitle,
    required this.iconName,
    super.key,
  });

  final String title;
  final String subtitle;
  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.state.selectedOpacity,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: AppIcon(iconName, size: 22, color: colors.icon.accent),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: AppTypography.displaySmall.copyWith(
            color: colors.text.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}
