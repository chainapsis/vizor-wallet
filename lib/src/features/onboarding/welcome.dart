import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import 'shared/onboarding_welcome_art.dart';

/// Welcome-specific button width. The redesigned Figma CTA stack is 256 dp
/// wide (node 1136:17519).
const double _welcomeActionWidth = 256;

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
  const WelcomeScreen({super.key, this.showBackButton = false});

  final bool showBackButton;

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
            showBackButton: widget.showBackButton,
            child: const _Content(),
          ),
        ),
      ),
    );
  }
}

/// Opaque card that wraps the onboarding content.
///
/// The backdrop illustration fills the whole pane, while the bottom-anchored
/// UI column is treated as a fixed-size 1064 × 672 dp design block — the
/// dimensions of Figma's welcome pane inside the 1080 × 720 window
/// (node 215:2665). At the default window size, the backdrop and foreground
/// design block both land on the Figma pixels. When the user grows the window,
/// the backdrop scales to avoid empty pane bands and the foreground block stays
/// centered so CTA positions remain stable.
///
/// Alignment is height-adaptive:
///   * pane height >= 672 dp → `Alignment.center`. The canvas fits
///     with symmetric `bg.ground` strips top and bottom, which
///     reads as intentional letterboxing when the user drags the
///     window taller than Figma's pane.
///   * pane height <  672 dp → `Alignment.bottomCenter`. The canvas
///     overflows the pane; bottom-anchoring keeps the UI CTAs
///     visible and lets the backdrop's soft top fade clip off,
///     which is far less load-bearing than the interactive footer.
///
/// Horizontal overflow always clips symmetrically (center component of both
/// alignments), and the rounded-rect clip on the surrounding Container swallows
/// the overflow evenly. Rationale: CTA positions are more load-bearing than
/// the backdrop's exact pixel scale, so the content remains rigid while the
/// background scales independently to cover larger panes.
///
/// Two theme variants of the backdrop (261:6662 light / 303:1477 dark)
/// pre-compose the masked layering on the Figma side; the Dart side
/// just picks the right PNG per [AppTheme] without reproducing the
/// masking math.
///
/// No ambient pane shadow — the Figma dark variant ships one, but the
/// team decided it adds no depth in the transparent-window + acrylic
/// context the app actually runs in.
class _Pane extends StatelessWidget {
  const _Pane({required this.child, required this.showBackButton});

  final Widget child;
  final bool showBackButton;

  /// Fixed foreground design-canvas dimensions pulled from Figma's Welcome BG
  /// frame (node 1300:34883). The 1080 × 720 desktop window leaves a
  /// 1064 × 672 pane after the outer 8 dp gap and native titlebar safe area.
  static const double _canvasWidth = 1064;
  static const double _canvasHeight = 672;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: OnboardingWelcomeBackdrop(
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
            ),
          ),
          // OverflowBox with tight canvas-sized constraints parks the
          // foreground design block at its native 1064 × 672 regardless of the
          // pane's actual dimensions. The more obvious
          // `Container.alignment: Alignment.center` can't carry this:
          // internally it wraps in an `Align`, which loosens the child's min
          // constraints but keeps `max` capped to the parent's incoming bounds.
          //
          // Alignment is chosen per-frame by pane height:
          //   * pane height >= _canvasHeight (672) → `Alignment.center`.
          //   * pane height <  _canvasHeight       → `Alignment.bottomCenter`,
          //     protecting the interactive CTA column when space is tight.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final alignment = constraints.maxHeight < _canvasHeight
                    ? Alignment.bottomCenter
                    : Alignment.center;
                return OverflowBox(
                  alignment: alignment,
                  minWidth: _canvasWidth,
                  maxWidth: _canvasWidth,
                  minHeight: _canvasHeight,
                  maxHeight: _canvasHeight,
                  child: SizedBox(
                    width: _canvasWidth,
                    height: _canvasHeight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [child],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (showBackButton)
            const Positioned(
              left: AppSpacing.md,
              top: AppSpacing.md,
              child: _BackRow(),
            ),
        ],
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.canPop() ? context.pop() : context.go('/home'),
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: AppIconSize.medium,
                color: colors.icon.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vizor logo + title block + buttons + legal footer, bottom-anchored.
///
/// Figma's Container contributes 32 dp vertical padding and `_Welcome Content`
/// contributes another 24 dp. Combined with the pane's outer 24 dp content
/// padding above, the legal footer sits 80 dp above the pane edge.
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _TitleBlock(),
            const SizedBox(height: AppSpacing.lg),
            const _ButtonsStack(),
            const SizedBox(height: AppSpacing.lg),
            const _LegalFooter(),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _VizorLogo(),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Behind the Vizor.\nYour money, hidden.',
          style: AppTypography.displayLarge.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Brand wordmark rendered above the title.
///
/// `VizorWordmark` owns the Figma logo frame metrics so the welcome and
/// unlock screens stay visually consistent.
class _VizorLogo extends StatelessWidget {
  const _VizorLogo();

  @override
  Widget build(BuildContext context) => const VizorWordmark();
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
          key: const ValueKey('welcome_create_wallet_button'),
          onPressed: () => context.go('/onboarding/intro'),
          variant: AppButtonVariant.primary,
          minWidth: _welcomeActionWidth,
          leading: const AppIcon(AppIcons.addNew),
          child: const Text('Create a new wallet'),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          key: const ValueKey('welcome_import_wallet_button'),
          onPressed: () => context.go('/import'),
          variant: AppButtonVariant.secondary,
          minWidth: _welcomeActionWidth,
          leading: const AppIcon(AppIcons.importWallet),
          child: const Text('Import a wallet'),
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
    // the background.
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
          const TextSpan(text: 'By using Vizor you agree to our '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _LegalFooterLink(
              label: 'Terms',
              style: linkStyle,
              onTap: () => context.push('/terms'),
            ),
          ),
          const TextSpan(text: ' and '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _LegalFooterLink(
              label: 'Privacy',
              style: linkStyle,
              onTap: () => context.push('/privacy'),
            ),
          ),
        ],
        style: bodyStyle,
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _LegalFooterLink extends StatelessWidget {
  const _LegalFooterLink({
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(label, style: style),
        ),
      ),
    );
  }
}
