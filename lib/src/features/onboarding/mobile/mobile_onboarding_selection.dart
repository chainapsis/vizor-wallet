import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

/// The import and hardware selectors share the first visible progress slot.
const kMobileSelectionProgress = 60 / 196;

class MobileOnboardingSelectionPage extends StatelessWidget {
  const MobileOnboardingSelectionPage({
    required this.scrollKey,
    required this.title,
    required this.subtitle,
    required this.cards,
    super.key,
  });

  final Key scrollKey;
  final String title;
  final String subtitle;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileTopNav.steps(
              height: 74,
              progress: kMobileSelectionProgress,
              progressOffset: const Offset(-4.5, 0),
              progressTrackColor: colors.background.inverse.withValues(
                alpha: 0.35,
              ),
              onBack: () => context.pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: scrollKey,
                padding: const EdgeInsets.all(
                  AppSpacing.sm,
                ).copyWith(top: AppSpacing.md, bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.displayLarge.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    // 32 px section gap plus the cards' 16 px top padding.
                    const SizedBox(height: AppSpacing.lg),
                    for (var index = 0; index < cards.length; index++) ...[
                      if (index > 0) const SizedBox(height: AppSpacing.s),
                      cards[index],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileOnboardingSelectionCard extends StatelessWidget {
  const MobileOnboardingSelectionCard({
    required this.iconName,
    required this.title,
    required this.description,
    required this.onPressed,
    super.key,
  });

  final String iconName;
  final String title;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '$title. $description',
      child: AppButton(
        onPressed: onPressed,
        variant: AppButtonVariant.secondary,
        height: 80,
        growWithContent: true,
        expand: true,
        constrainContent: true,
        // AppButton also adds 4 px around its label slot: 12 + 4 = 16.
        contentPadding: const EdgeInsets.all(AppSpacing.s),
        borderRadius: BorderRadius.circular(AppRadii.large),
        enabledBackgroundColor: colors.background.ground,
        pressedBackgroundColor: colors.background.raised,
        enabledBorderColor: const Color(0x00000000),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: AppIcon(iconName, size: 24, color: colors.icon.inverse),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
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
