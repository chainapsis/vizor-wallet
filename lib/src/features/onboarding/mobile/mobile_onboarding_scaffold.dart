import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';

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
    this.scrollable = true,
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

  /// Overrides the Headline XL title style — the passcode frames use
  /// the smaller Headline M serif.
  final TextStyle? titleStyle;

  /// Keeps the default onboarding behavior scrollable. Screens with a
  /// live camera viewport can opt out so the viewport resizes instead of
  /// being partially scrolled off-screen on shorter phones.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contentPadding = const EdgeInsets.fromLTRB(
      AppSpacing.xs,
      AppSpacing.md,
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
      const SizedBox(height: AppSpacing.md),
    ];
    final childPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.xs);
    return Scaffold(
      backgroundColor: colors.background.window,
      resizeToAvoidBottomInset: true,
      body: AppToastHost(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTopNav.steps(progress: progress, onBack: onBack),
              Expanded(
                child: scrollable
                    ? SingleChildScrollView(
                        // The title gets the near-full screen width (long
                        // serif titles like "Zcash Address Types" stay on one
                        // line per the Figma frames); the content keeps the
                        // standard sm inset via the inner padding below.
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
                              child: Padding(
                                padding: childPadding,
                                child: child,
                              ),
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
                        AppSpacing.sm,
                        AppSpacing.s,
                        AppSpacing.sm,
                        AppSpacing.s,
                      ),
                  child: bottomArea!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
