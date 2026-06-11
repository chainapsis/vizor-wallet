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
    super.key,
  });

  /// Progress through the flow (0.0–1.0) shown in the top nav track.
  final double progress;
  final VoidCallback? onBack;

  final String title;
  final String? subtitle;

  /// Step content below the title block; wrapped in a scroll view so
  /// small phones and the software keyboard never clip it.
  final Widget child;

  /// Pinned actions (primary button, secondary link) at the bottom.
  final Widget? bottomArea;

  /// Override for the inset around [bottomArea] — pass
  /// [EdgeInsets.zero] for full-bleed panels like the numeric keypad.
  final EdgeInsets? bottomAreaPadding;

  /// Optional hero content rendered above the title — the biometrics
  /// frame puts its illustration first.
  final Widget? aboveTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                child: SingleChildScrollView(
                  // The title gets the near-full screen width (long serif
                  // titles like "Zcash Address Types" stay on one line per
                  // the Figma frames); the content keeps the standard sm
                  // inset via the inner padding below.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (aboveTitle != null) ...[
                        aboveTitle!,
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTypography.displayLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: child,
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
