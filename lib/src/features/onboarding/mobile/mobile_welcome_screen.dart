import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_welcome_art.dart' show VizorWordmark;
import 'mobile_welcome_backdrop.dart';
import '../shared/welcome_accent_button.dart';
import '../shared/welcome_button_tokens.dart';

/// Figma `Welcome` (8635:103040): native video with create and import entry paths.
class MobileWelcomeScreen extends StatelessWidget {
  const MobileWelcomeScreen({
    this.showBackButton = false,
    this.animateBackground = true,
    super.key,
  });

  /// `/add-account` returns home and omits the walletless Gift Card entry.
  final bool showBackButton;
  final bool animateBackground;

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(50.0, MediaQuery.paddingOf(context).bottom + 16);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xff0f0f0f),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final videoHeight = (constraints.maxWidth + 1) * 700 / 394;
            final fadeEnd = math.min(1.0, videoHeight / constraints.maxHeight);
            return Stack(
              fit: StackFit.expand,
              children: [
                // 394×700 video slot at x=-1 in the 393×852 reference.
                Positioned(
                  top: 0,
                  left: -1,
                  width: constraints.maxWidth + 1,
                  height: videoHeight,
                  child: MobileWelcomeBackdrop(animate: animateBackground),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: const [
                            Color(0x00000000),
                            Color(0x99000000),
                            Color(0xff000000),
                          ],
                          // Keep the artwork visible behind the copy, then
                          // blend its bottom edge into the page background.
                          stops: [fadeEnd * 0.40857, fadeEnd * 0.88, fadeEnd],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, available) => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, bottom),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(
                            0,
                            available.maxHeight - bottom - 24,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 313),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const VizorWordmark(
                                    width: 106,
                                    height: 40,
                                    color: Color(0xffffffff),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    'Shielded\nby default',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.displayLarge.copyWith(
                                      color: const Color(0xffffffff),
                                      fontSize: 56,
                                      height: 1.02,
                                      letterSpacing: -1.68,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  SizedBox(
                                    width: 240,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        WelcomeAccentButton(
                                          semanticKey: const ValueKey(
                                            'mobile_welcome_get_started',
                                          ),
                                          onPressed: () =>
                                              context.push('/onboarding/intro'),
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        Semantics(
                                          key: const ValueKey(
                                            'mobile_welcome_import',
                                          ),
                                          button: true,
                                          child: AppButton(
                                            expand: true,
                                            focusRingColor:
                                                WelcomeButtonTokens.focusRing,
                                            enabledBackgroundColor:
                                                WelcomeButtonTokens
                                                    .secondaryBackground,
                                            pressedBackgroundColor:
                                                WelcomeButtonTokens
                                                    .secondaryHighlightedBackground,
                                            enabledBorderColor:
                                                WelcomeButtonTokens.border,
                                            enabledLabelColor:
                                                WelcomeButtonTokens
                                                    .secondaryLabel,
                                            pressedLabelColor:
                                                WelcomeButtonTokens
                                                    .secondaryLabel,
                                            onPressed: () => context.push(
                                              '/onboarding/method',
                                            ),
                                            leading: const AppIcon(
                                              AppIcons.importWallet,
                                            ),
                                            growWithContent: true,
                                            constrainContent: true,
                                            child: const Text(
                                              'Import wallet',
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                        if (!showBackButton) ...[
                                          const SizedBox(height: AppSpacing.sm),
                                          Semantics(
                                            key: const ValueKey(
                                              'mobile_welcome_redeem_card',
                                            ),
                                            button: true,
                                            enabled: false,
                                            child: AppButton(
                                              expand: true,
                                              focusRingColor:
                                                  WelcomeButtonTokens.focusRing,
                                              variant: AppButtonVariant.ghost,
                                              enabledLabelColor:
                                                  WelcomeButtonTokens
                                                      .ghostLabel,
                                              pressedLabelColor:
                                                  WelcomeButtonTokens
                                                      .ghostLabel,
                                              pressedBackgroundColor:
                                                  WelcomeButtonTokens
                                                      .ghostHighlightedBackground,
                                              // TODO: Connect Gift Card activation once the claim flow is finalized.
                                              onPressed: null,
                                              disabledBackgroundColor:
                                                  const Color(0x00000000),
                                              leading: const AppIcon(
                                                AppIcons.giftCard,
                                                color: WelcomeButtonTokens
                                                    .ghostDisabledLabel,
                                              ),
                                              growWithContent: true,
                                              constrainContent: true,
                                              child: const Text(
                                                'Activate Gift Card',
                                                style: TextStyle(
                                                  color: WelcomeButtonTokens
                                                      .ghostDisabledLabel,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (showBackButton)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
                    left: AppSpacing.s,
                    child: Semantics(
                      label: 'Back',
                      button: true,
                      child: AppButton(
                        variant: AppButtonVariant.ghost,
                        focusRingColor: WelcomeButtonTokens.focusRing,
                        enabledLabelColor: const Color(0xffffffff),
                        onPressed: () => context.go('/home'),
                        child: const AppIcon(
                          AppIcons.chevronBackward,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
