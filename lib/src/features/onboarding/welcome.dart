import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';

/// Welcome-specific button minimum width. Matches the 196 dp the Figma
/// component uses for the two CTAs (node 215:2829 / 215:2830). Modeled
/// as a minimum, not a fixed width, because "fixed width" is a
/// designer-side convenience: the real requirement is that both
/// buttons share a visually consistent size, and `minWidth` lets
/// Column pick whichever of the two wants more room without
/// short-circuiting hit-test behavior on smaller locales.
const double _welcomeButtonMinWidth = 196;

/// Onboarding entry point — the Figma "Split View" at node 215:2688
/// (light) / 215:2888 (dark).
///
/// The outer 8 dp gap around the content pane is deliberately transparent
/// so the native macOS acrylic / Windows blur shows through; only the
/// inner "Trailing Pane" is opaque (`background.ground` with an 8 dp
/// corner radius). The transparent-first rule is documented in CLAUDE.md
/// under "Window Transparency".
///
/// The screen targets the large (landscape) desktop layout by design.
/// On entry it asks [AppLayoutNotifier] to switch to
/// [AppLayoutMode.large] so a user who had previously toggled the window
/// into small can still come back through onboarding.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame so the provider mutation doesn't clash with the current
    // build (Riverpod forbids state writes during build). `setMode` is
    // idempotent when the mode already matches.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent so the flutter_acrylic window effect on the native
      // surface shows through the outer gap below.
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          // Only the 8 dp gap around the pane is transparent — this is
          // the strip where the native acrylic is visible.
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: _Pane(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // "Bottom-anchor content, scroll when it doesn't fit"
                // pattern — the Figma layout justifies the content
                // column to the bottom of the pane so the backdrop
                // illustration has room to breathe in the upper area.
                // The configured minimum window height (≈ 400 dp) is
                // smaller than the natural content height, so content
                // still scrolls at the layout floor.
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [_Content()],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Opaque card that wraps the onboarding content. Fills the padded
/// area. Renders the Figma-composited backdrop illustration behind the
/// content — two variants (light / dark) pre-composed from the Figma
/// "Welcome Bg" nodes (261:6662 / 303:1477). Picking at render time via
/// [AppTheme] keeps the Dart side trivial: each PNG already bakes in
/// the three-layer mask / opacity composition the Figma spec describes.
///
/// No ambient pane shadow — the Figma dark variant ships one, but the
/// team decided it adds no depth in the transparent-window + acrylic
/// context the app actually runs in.
class _Pane extends StatelessWidget {
  const _Pane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final bgAsset = isDark
        ? 'assets/illustrations/welcome_bg_dark.png'
        : 'assets/illustrations/welcome_bg_light.png';
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Backdrop illustration. `BoxFit.cover` + top-center anchor
          // keeps the knight figure in the upper portion of the pane;
          // the Figma asset's bottom third fades to transparent so the
          // opaque pane color shows through behind the content column.
          Positioned.fill(
            child: Image.asset(
              bgAsset,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Vizor logo + title block + buttons + legal footer, bottom-anchored.
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _VizorLogo(),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Private Money.\nFor the New Internet',
          style: AppTypography.displayMedium.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        const _ButtonsStack(),
        const SizedBox(height: AppSpacing.md),
        const _LegalFooter(),
      ],
    );
  }
}

/// Brand wordmark rendered above the title.
///
/// The SVG ships with a static `#E1E1E1` fill — a snapshot of the
/// dark-mode accent tone at export time. `BlendMode.srcIn` swaps that
/// for whatever `text.accent` resolves to at paint, so the logo flips
/// to near-black in light mode and near-white in dark mode without
/// maintaining two asset variants.
///
/// The Figma Logo component (node 238:3869) is a 74×37 frame with the
/// wordmark inset to roughly 62 × 20.7 dp; the SizedBox + centered
/// SvgPicture mirrors that padding so the logo sits with the same
/// breathing room the spec calls for.
class _VizorLogo extends StatelessWidget {
  const _VizorLogo();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 74,
      height: 37,
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/vizor_logo.svg',
          width: 62,
          colorFilter: ColorFilter.mode(colors.text.accent, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _ButtonsStack extends StatelessWidget {
  const _ButtonsStack();

  @override
  Widget build(BuildContext context) {
    // Both buttons carry the same minWidth so they render identical
    // widths even when their labels differ in length; Column picks up
    // the larger child's intrinsic width and applies it to both.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          onPressed: () => context.go('/onboarding/intro'),
          variant: AppButtonVariant.primary,
          minWidth: _welcomeButtonMinWidth,
          leading: const AppIcon(AppIcons.addNew),
          child: const Text('Create new wallet'),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          onPressed: () => context.go('/import'),
          variant: AppButtonVariant.secondary,
          minWidth: _welcomeButtonMinWidth,
          leading: const AppIcon(AppIcons.importWallet),
          child: const Text('Import existing wallet'),
        ),
      ],
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Body uses `text.muted` per Figma. Link emphasis uses
    // `text.secondary` as the closest semantic token to Figma's
    // hardcoded `#4D5252` — in light mode the token resolves to
    // `#626767`, one step lighter than the literal, but this preserves
    // legibility in dark mode where the literal would disappear into
    // the background. Navigation handlers are intentionally stubbed
    // until the Terms / Privacy destinations exist.
    final bodyStyle = AppTypography.bodySmall.copyWith(
      color: colors.text.muted,
    );
    final linkStyle = AppTypography.bodySmall.copyWith(
      color: colors.text.secondary,
      decoration: TextDecoration.underline,
      decorationColor: colors.text.secondary,
    );

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'By using Zeplr you agree to our '),
          TextSpan(text: 'Terms', style: linkStyle),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy', style: linkStyle),
        ],
        style: bodyStyle,
      ),
      textAlign: TextAlign.center,
    );
  }
}
