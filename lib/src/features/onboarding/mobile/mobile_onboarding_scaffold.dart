import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/mobile_scroll_edge_fades.dart';
import '../../../core/layout/mobile/mobile_sticky_bottom_action.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';
import 'mobile_unlock_screen.dart' show mobileBiometricSignInBackgroundAsset;

/// Single-pane scaffold for mobile onboarding steps: the Steps top nav
/// (back chevron + progress track), a centered serif title with an
/// optional subtitle, scrollable content, and a pinned bottom action
/// area — the shared shape of every step frame in the Figma `WELCOME`
/// and `ONBOARDING IMPORT` sections.
class MobileOnboardingStepScaffold extends StatelessWidget {
  const MobileOnboardingStepScaffold({
    required this.progress,
    required this.title,
    required this.child,
    this.subtitle,
    this.onBack,
    this.bottomArea,
    this.bottomAreaPadding,
    this.aboveTitle,
    this.titleStyle,
    this.contentGap = AppSpacing.md,
    this.topNavHeight = kMobileTopNavHeight,
    this.topNavProgressOffset = Offset.zero,
    this.topNavProgressTrackColor,
    this.showBackButton = true,
    this.showProgress = true,
    this.scrollable = true,
    this.background,
    super.key,
  });

  /// Progress through the flow (0.0–1.0) shown in the top nav track.
  final double progress;
  final VoidCallback? onBack;

  final String title;
  final String? subtitle;

  /// Step content below the title block. The scaffold wraps this in a scroll
  /// view by default so small phones and the software keyboard never clip it.
  final Widget child;

  /// Pinned actions (primary button, secondary link) at the bottom.
  final Widget? bottomArea;

  /// Override for the inset around [bottomArea] — pass
  /// [EdgeInsets.zero] for full-bleed panels like the numeric keypad.
  final EdgeInsets? bottomAreaPadding;

  /// Optional hero content rendered above the title — the biometrics
  /// frame puts its illustration first.
  final Widget? aboveTitle;

  /// Overrides the default Headline XL title style for compact step titles.
  final TextStyle? titleStyle;

  /// Space between the heading group and the step content.
  final double contentGap;

  /// Screen-specific steps-nav geometry; defaults match the shared component.
  final double topNavHeight;
  final Offset topNavProgressOffset;
  final Color? topNavProgressTrackColor;

  /// The steps nav normally reserves the leading back affordance; terminal
  /// opt-in steps can hide it when there is no valid previous action.
  final bool showBackButton;
  final bool showProgress;

  /// Keeps the default onboarding behavior scrollable. Screens with a
  /// live camera viewport can opt out so the viewport resizes instead of
  /// being partially scrolled off-screen on shorter phones.
  final bool scrollable;

  /// Full-page art behind the step, from the top of the screen, such as
  /// [MobileOnboardingCitadelBackground].
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contentPadding = EdgeInsets.fromLTRB(
      AppSpacing.xs,
      showProgress ? AppSpacing.md : AppSpacing.s,
      AppSpacing.xs,
      AppSpacing.md,
    );
    final contentChildren = <Widget>[
      if (aboveTitle != null) ...[
        aboveTitle!,
        const SizedBox(height: AppSpacing.md),
      ],
      Text(
        title,
        textAlign: TextAlign.center,
        style: (titleStyle ?? AppTypography.displayLarge).copyWith(
          color: colors.text.accent,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: AppSpacing.sm),
        // Body M Medium on text/primary, wrapped to the narrow centered
        // measure of the step frames (subtitle nodes are 259–277 wide in
        // Figma).
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ),
      ],
      SizedBox(height: contentGap),
    ];
    final childPadding = const EdgeInsets.symmetric(
      horizontal: kMobilePageMargin - AppSpacing.xs,
    );
    final page = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!showProgress)
            MobileTopNav.back(
              title: '',
              height: kMobileTopNavHeight,
              onBack: showBackButton ? onBack : null,
            )
          else
            MobileTopNav.steps(
              progress: progress,
              height: topNavHeight,
              progressOffset: topNavProgressOffset,
              progressTrackColor: topNavProgressTrackColor,
              onBack: onBack,
              showBackButton: showBackButton,
            ),
          Expanded(
            child: scrollable
                ? SingleChildScrollView(
                    // The title gets the near-full screen width (long
                    // serif titles like "Zcash Address Types" stay on one
                    // line per the Figma frames); the content keeps the
                    // page margin via the inner padding below.
                    padding: contentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...contentChildren,
                        Padding(padding: childPadding, child: child),
                      ],
                    ),
                  )
                : Padding(
                    padding: contentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...contentChildren,
                        Expanded(
                          child: Padding(padding: childPadding, child: child),
                        ),
                      ],
                    ),
                  ),
          ),
          if (bottomArea != null)
            Padding(
              padding:
                  bottomAreaPadding ??
                  const EdgeInsets.fromLTRB(
                    kMobilePageMargin,
                    AppSpacing.s,
                    kMobilePageMargin,
                    kMobileFooterGap,
                  ),
              child: bottomArea!,
            ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: colors.background.window,
      resizeToAvoidBottomInset: true,
      body: AppToastHost(
        child: background == null
            // Onboarding steps sit outside the page viewport, so they
            // install the standard scroll edges themselves.
            ? MobileScrollEdgeFades(
                color: colors.background.window,
                bottomHeight: AppSpacing.xl,
                child: page,
              )
            // The fades paint the window color, which would band across the
            // art; the step scrolls without them, as transaction records do.
            : Stack(
                fit: StackFit.expand,
                children: [
                  background!,
                  MobileScrollEdgeFades.off(child: page),
                ],
              ),
      ),
    );
  }
}

/// The citadel engraving from the top of an onboarding step, the unlock
/// screen's art (Figma `Full Page Background`). The asset is already faded
/// and translucent, so it reads on both themes.
class MobileOnboardingCitadelBackground extends StatelessWidget {
  const MobileOnboardingCitadelBackground({super.key});

  static const _figmaFrameWidth = 393.0;
  static const _width = 392.0;
  static const _height = 720.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / _figmaFrameWidth;
        return Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: _width * scale,
            height: _height * scale,
            child: const Image(
              key: ValueKey('mobile_onboarding_citadel_background'),
              image: AssetImage(mobileBiometricSignInBackgroundAsset),
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
        );
      },
    );
  }
}
