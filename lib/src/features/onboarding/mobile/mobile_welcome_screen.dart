import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_welcome_art.dart' show VizorWordmark;

/// Mobile welcome screen — Figma `Welcome` (node 4394:77936): full-bleed
/// hero with the Vizor wordmark and "Private money. By default" tagline,
/// then the create / import / Keystone entry points and the legal
/// footer.
class MobileWelcomeScreen extends StatelessWidget {
  const MobileWelcomeScreen({this.showBackButton = false, super.key});

  /// True on `/add-account`, where welcome is re-entered from a wallet
  /// that already exists and back returns home.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: Column(
        children: [
          Expanded(child: _WelcomeHero(showBackButton: showBackButton)),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.s,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: const ValueKey('mobile_welcome_create'),
                  expand: true,
                  onPressed: () => context.push('/onboarding/intro'),
                  child: const _ButtonLabel(
                    iconName: AppIcons.addNew,
                    label: 'Create a wallet',
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('mobile_welcome_import'),
                  expand: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.push('/import'),
                  child: const _ButtonLabel(
                    iconName: AppIcons.importWallet,
                    label: 'Import a wallet',
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                const _OrDivider(),
                const SizedBox(height: AppSpacing.base),
                AppButton(
                  key: const ValueKey('mobile_welcome_keystone'),
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => context.push('/onboarding/keystone'),
                  child: const _ButtonLabel(
                    iconName: AppIcons.qr,
                    label: 'Connect Keystone',
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                // Constrained so the legal text wraps onto two centered
                // lines as in the Figma frame.
                const Center(
                  child: SizedBox(width: 240, child: _LegalFooter()),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.showBackButton});

  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadii.xLarge),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/illustrations/welcome_hero_dark.png',
            fit: BoxFit.cover,
          ),
          // Darkens the lower half so the wordmark and tagline stay
          // legible over the artwork.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.47, 0.97],
                colors: [const Color(0x00000000), const Color(0xFF1E1E1E)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.lg,
            child: Column(
              children: [
                VizorWordmark(width: 90, height: 34, color: colors.text.homeCard),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Private money.\nBy default',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.homeCard,
                  ),
                ),
              ],
            ),
          ),
          if (showBackButton)
            Positioned(
              top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
              left: AppSpacing.s,
              child: Semantics(
                label: 'Back',
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.go('/home'),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AppIcon(
                        AppIcons.chevronBackward,
                        size: 24,
                        color: colors.text.homeCard,
                      ),
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

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.iconName, required this.label});

  final String iconName;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          iconName,
          size: 20,
          color: DefaultTextStyle.of(context).style.color,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final line = Expanded(
      child: Container(
        height: 2,
        decoration: BoxDecoration(
          color: colors.border.regular,
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: Text(
            'OR',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = AppTypography.bodySmall.copyWith(color: colors.text.muted);
    final link = AppTypography.bodySmall.copyWith(
      color: colors.text.secondary,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By using Vizor you agree to our '),
          TextSpan(
            text: 'Terms',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push('/terms'),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push('/privacy'),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
