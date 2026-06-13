import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_welcome_art.dart' show VizorWordmark;

/// Mobile welcome screen — Figma `Welcome` (4750:24077): the Vizor
/// wordmark and "Private money. By default" tagline over a single
/// "Get started" call to action, with the hero illustration filling the
/// lower half. "Get started" leads to the `Method Selection` step where
/// the create / import / Keystone entry points now live.
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
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 35),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Figma `Logo` 106×40, centered near the top.
                      VizorWordmark(
                        width: 106,
                        height: 40,
                        color: colors.text.accent,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Private Money.\nBy default',
                        textAlign: TextAlign.center,
                        // Figma `Welcome` tagline — Young Serif 48 / 1.1,
                        // larger than the standard Headline XL token.
                        style: AppTypography.displayLarge.copyWith(
                          color: colors.text.accent,
                          fontSize: 48,
                          height: 1.1,
                          letterSpacing: -1.35,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Centered primary pill (Figma `Buttons Stack`,
                      // 4750:24094 — ~200 wide; sized to its content so the
                      // label + chevron never clip).
                      AppButton(
                        key: const ValueKey('mobile_welcome_get_started'),
                        onPressed: () => context.push('/onboarding/method'),
                        trailing: const AppIcon(AppIcons.chevronForward),
                        child: const Text('Get started'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Image.asset(
                  'assets/illustrations/welcome_hero_dark.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  width: double.infinity,
                ),
              ),
            ],
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
                        color: colors.text.accent,
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
