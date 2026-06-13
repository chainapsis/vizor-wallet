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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, AppSpacing.s, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        if (showBackButton)
                          Semantics(
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
                        Expanded(
                          child: Center(
                            child: VizorWordmark(
                              width: 96,
                              height: 36,
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                        // Balances the back button so the wordmark stays
                        // centered.
                        if (showBackButton) const SizedBox(width: 44),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Private Money.\nBy default',
                    style: AppTypography.displayLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: const ValueKey('mobile_welcome_get_started'),
                      onPressed: () => context.push('/onboarding/method'),
                      trailing: const AppIcon(AppIcons.chevronForward),
                      child: const Text('Get started'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Image.asset(
              'assets/illustrations/welcome_hero_dark.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}
