import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  const IntroZcashScreen({super.key});

  @override
  ConsumerState<IntroZcashScreen> createState() => _IntroZcashScreenState();
}

class _IntroZcashScreenState extends ConsumerState<IntroZcashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      clearCreateOnboardingSecretState(ref.read);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const OnboardingTrailingPane(
      backTarget: OnboardingBackTarget.route(
        label: 'Welcome',
        routePath: '/welcome',
      ),
      bodyPadding: EdgeInsets.zero,
      child: _HeroLayout(),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout();

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  @override
  Widget build(BuildContext context) {
    return const Column(
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
                    Expanded(child: _OnPageContent()),
                    _ButtonStack(),
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
  const _OnPageContent();

  static const double _sectionGap = 32;

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TitleBlock(),
        SizedBox(height: _sectionGap),
        _ShieldedInfoCard(),
        SizedBox(height: _sectionGap),
        _SetupIntroText(),
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
            'The Shielded World',
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 226,
          child: Text(
            'Zcash (ZEC) built around financial privacy & self-custody.',
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
        ? 'assets/illustrations/home_balance_card_pattern_dark.png'
        : 'assets/illustrations/home_balance_card_pattern_light.png';

    return Container(
      height: _height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: _radius,
      ),
      child: Stack(
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
                      'Unlike Bitcoin or Ethereum, shielded Zcash '
                      'transactions hide the sender, recipient, and amount '
                      '— verified by cryptography, not trust.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.homeCard,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
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
  const _SetupIntroText();

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
          "You're a few steps away from your first private wallet.\n"
          "Let's get you set up.",
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ButtonStack extends StatelessWidget {
  const _ButtonStack();

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
                onPressed: () =>
                    context.go(OnboardingStep.addressTypes.routePath),
                variant: AppButtonVariant.primary,
                minWidth: _buttonMinWidth,
                trailing: const AppIcon(AppIcons.chevronForward),
                child: const Text('Tell me how Zcash works'),
              ),
              const SizedBox(height: AppSpacing.s),
              AppButton(
                onPressed: () =>
                    context.go(OnboardingStep.secretPassphrase.routePath),
                variant: AppButtonVariant.ghost,
                minWidth: _buttonMinWidth,
                trailing: const AppIcon(AppIcons.skip),
                child: const Text('I know how to use Zcash'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
