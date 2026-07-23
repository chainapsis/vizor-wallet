part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationStepScaffold extends StatelessWidget {
  const _MobileMigrationStepScaffold({
    required this.onBack,
    required this.stepLabel,
    required this.title,
    required this.child,
    required this.bottom,
    this.subtitle,
    this.topGap = 31,
    this.childGap = 28,
  });

  final VoidCallback onBack;
  final String stepLabel;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget bottom;
  final double topGap;
  final double childGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Transform.translate(
              offset: const Offset(0, 20),
              child: MobileTopNav.back(
                title: stepLabel,
                titleStyle: AppTypography.headlineSmall,
                onBack: onBack,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  topGap,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.start,
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                    SizedBox(height: childGap),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: bottom,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobilePrivateReviewScaffold extends StatelessWidget {
  const _MobilePrivateReviewScaffold({
    required this.onBack,
    required this.child,
    required this.bottom,
  });

  final VoidCallback onBack;
  final Widget child;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < _mobileMigrationReviewCompactHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Transform.translate(
                  offset: const Offset(0, 20),
                  child: MobileTopNav.back(
                    title: 'Step 3/3',
                    titleStyle: AppTypography.headlineSmall,
                    onBack: onBack,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Text(
                    'Review Migration Plan',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 24 : 42),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: child,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.s,
                  ),
                  child: bottom,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MobileMigrationReviewScaffold extends StatelessWidget {
  const _MobileMigrationReviewScaffold({
    required this.onBack,
    required this.child,
    required this.bottom,
  });

  final VoidCallback onBack;
  final Widget child;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The approved dark review frame places the plan 9px higher than the
    // light frame while keeping the bottom actions fixed to the safe area.
    final topPadding =
        colors.background.window == AppThemeData.dark.colors.background.window
        ? 30.0
        : 39.0;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Transform.translate(
              offset: const Offset(0, 20),
              child: MobileTopNav.back(
                title: 'Step 3/3',
                titleStyle: AppTypography.headlineSmall,
                onBack: onBack,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  topPadding,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Text(
                      'Review Migration Plan',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: bottom,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationPrimaryButton extends StatelessWidget {
  const _MobileMigrationPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      expand: true,
      constrainContent: true,
      height: 50,
      onPressed: onPressed,
      trailing: const AppIcon(AppIcons.chevronForward, size: 20),
      child: Text(label),
    );
  }
}

class _MobileMigrationProgressTrack extends StatelessWidget {
  const _MobileMigrationProgressTrack({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clampedValue = value.clamp(0.0, 1.0);
    return Semantics(
      label: 'Migration plan analysis',
      value: '${(clampedValue * 100).round()}%',
      child: SizedBox(
        width: 196,
        height: 12,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
          child: ColoredBox(
            color: colors.background.neutralSubtleOpacity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: clampedValue,
                heightFactor: 1,
                child: ColoredBox(
                  key: const ValueKey(
                    'mobile_ironwood_migration_analysis_progress_fill',
                  ),
                  color: colors.background.inverse,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
