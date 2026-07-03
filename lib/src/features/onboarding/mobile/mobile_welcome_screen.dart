import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_welcome_art.dart' show VizorWordmark;
import '../../../../l10n/app_localizations.dart';

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
        // The only non-positioned child is the min-height content Column, so
        // without `expand` the Stack collapses to it (~300px) and the
        // Positioned.fill hero shrinks into a band at the top. `expand`
        // pins the Stack to the full screen so the hero truly fills it.
        fit: StackFit.expand,
        children: [
          // Full-screen hero — Figma `Welcome BG` (4750:24095). The asset
          // is a 393×852 knight that fades to transparent at the top, so
          // the same image bottom-aligns and blends into the window colour
          // in both light and dark mode (no hard seam).
          Positioned.fill(
            child: Image.asset(
              'assets/illustrations/mobile_welcome_hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              // Figma logo top is 35 below the system status area.
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
                  // Figma rhythm: logo→tagline 38, tagline→button 29,
                  // placing the button over the faded part of the hero
                  // rather than down on the opaque treasure.
                  const SizedBox(height: 38),
                  Text(
                    AppLocalizations.of(context).onbPrivateMoneyMobile,
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
                  const SizedBox(height: 29),
                  // Figma `Buttons Stack` (4750:24094): a 200-wide primary
                  // pill with Label M text and a trailing chevron —
                  // the standard large AppButton. `minWidth` (not a tight
                  // box) pins it to 200 with centred content while letting it
                  // grow if a wide test font would otherwise overflow.
                  AppButton(
                    key: const ValueKey('mobile_welcome_get_started'),
                    onPressed: () => context.push('/onboarding/method'),
                    minWidth: 200,
                    trailing: const AppIcon(AppIcons.chevronForward),
                    child: Text(AppLocalizations.of(context).onbGetStartedShort),
                  ),
                ],
              ),
            ),
          ),
          if (showBackButton)
            Positioned(
              top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
              left: AppSpacing.s,
              child: Semantics(
                label: AppLocalizations.of(context).commonBack,
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
