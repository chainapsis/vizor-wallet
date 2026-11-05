import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

/// Onboarding step 1 — "Intro to Zcash".
///
/// This widget now renders only the trailing pane content. The shared
/// split-view shell (sidebar, illustration, acrylic gap) lives in
/// `onboarding_split_view.dart` so subsequent onboarding steps can reuse
/// the same left rail while only the right pane cross-fades.
class IntroZcashScreen extends ConsumerStatefulWidget {
  const IntroZcashScreen({
    this.onContinue,
    this.onSkip,
    this.backTarget,
    this.closingText,
    this.actionsEnabled = true,
    this.resetCreateDraft = true,
    super.key,
  });
  final VoidCallback? onContinue;
  final VoidCallback? onSkip;
  final OnboardingBackTarget? backTarget;
  final String? closingText;
  final bool actionsEnabled;
  final bool resetCreateDraft;

  @override
  ConsumerState<IntroZcashScreen> createState() => _IntroZcashScreenState();
}

class _IntroZcashScreenState extends ConsumerState<IntroZcashScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.resetCreateDraft) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      clearCreateOnboardingSecretState(ref.read);
    });
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingTrailingPane(
      backTarget:
          widget.backTarget ??
          OnboardingBackTarget.route(
            label: context.l10n.onboardingWelcome,
            routePath: '/welcome',
          ),
      bodyPadding: EdgeInsets.zero,
      child: _HeroLayout(
        onContinue: widget.onContinue,
        onSkip: widget.onSkip,
        actionsEnabled: widget.actionsEnabled,
        closingText: widget.closingText,
      ),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout({
    this.onContinue,
    this.onSkip,
    required this.actionsEnabled,
    this.closingText,
  });
  final VoidCallback? onContinue;
  final VoidCallback? onSkip;
  final bool actionsEnabled;
  final String? closingText;

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: _contentAreaWidth,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _contentPaddingX,
                  vertical: _contentPaddingY,
                ),
                child: Column(
                  children: [
                    Expanded(child: _OnPageContent(closingText: closingText)),
                    _ButtonStack(
                      onContinue: onContinue,
                      onSkip: onSkip,
                      actionsEnabled: actionsEnabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnPageContent extends StatelessWidget {
  const _OnPageContent({this.closingText});
  final String? closingText;

  static const double _sectionGap = 32;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _TitleBlock(),
        const SizedBox(height: _sectionGap),
        const _ShieldedInfoCard(),
        const SizedBox(height: _sectionGap),
        _SetupIntroText(closingText: closingText),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            context.l10n.onboardingIntroTitle,
            style: AppTypography.displayLarge.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 226,
          child: Text(
            context.l10n.onboardingIntroSubtitle,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ShieldedInfoCard extends StatelessWidget {
  const _ShieldedInfoCard();

  static const double _cardWidth = 396;
  static const double _height = 163;
  static const double _textWidth = 334;
  static const double _patternWidth = 1086.243;
  static const double _patternHeight = 1220.409;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final patternAsset = isDark
        ? 'assets/illustrations/desktop/home_balance_card_pattern_dark.webp'
        : 'assets/illustrations/desktop/home_balance_card_pattern_light.webp';

    // A minimum, not a fixed height: longer translations grow the card.
    return Container(
      constraints: const BoxConstraints(minHeight: _height),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: _radius,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: (_cardWidth - _patternWidth) / 2,
            top: -566,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.15,
                child: Image.asset(
                  patternAsset,
                  width: _patternWidth,
                  height: _patternHeight,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.shieldKeyhole,
                    size: 24,
                    color: colors.text.homeCard,
                  ),
                  const SizedBox(height: AppSpacing.s),
                  SizedBox(
                    width: _textWidth,
                    child: Text(
                      context.l10n.onboardingIntroCard,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.homeCard,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: _radius,
                  border: Border.all(
                    color: const Color(0xFFFFFFFF).withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupIntroText extends StatelessWidget {
  const _SetupIntroText({this.closingText});
  final String? closingText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 24,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          closingText ?? context.l10n.onboardingIntroClosing,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ButtonStack extends StatelessWidget {
  const _ButtonStack({
    this.onContinue,
    this.onSkip,
    required this.actionsEnabled,
  });
  final VoidCallback? onContinue;
  final VoidCallback? onSkip;
  final bool actionsEnabled;

  static const double _buttonMinWidth = 196;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Column(
            children: [
              AppButton(
                key: const ValueKey('desktop_education_continue'),
                onPressed: actionsEnabled
                    ? onContinue ??
                          () =>
                              context.go(OnboardingStep.addressTypes.routePath)
                    : null,
                variant: AppButtonVariant.primary,
                minWidth: _buttonMinWidth,
                trailing: const AppIcon(AppIcons.chevronForward),
                child: Text(context.l10n.onboardingTellMeHowZcashWorks),
              ),
              const SizedBox(height: AppSpacing.s),
              AppButton(
                key: const ValueKey('desktop_education_skip'),
                onPressed: actionsEnabled
                    ? onSkip ??
                          () => context.go(
                            OnboardingStep.secretPassphrase.routePath,
                          )
                    : null,
                variant: AppButtonVariant.ghost,
                minWidth: _buttonMinWidth,
                trailing: const AppIcon(AppIcons.skip),
                child: Text(context.l10n.onboardingIKnowHowToUseZcash),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
