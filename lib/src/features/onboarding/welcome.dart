import 'package:flutter/material.dart' show Colors, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';

/// Welcome-specific button width. Matches the 256 px buttons column on
/// the Figma split-view layout (node 215:2828). Kept inside this file —
/// it's a screen-level layout choice, not a design-system token.
const double _welcomeButtonMinWidth = 256;

/// Onboarding entry point — the Figma "Split View" at node 215:2688.
///
/// The outer 8 dp gap around the content pane is deliberately transparent
/// so the native macOS acrylic / Windows blur shows through; only the
/// inner "Trailing Pane" is opaque (`background.ground` with an 8 dp
/// corner radius and a soft ambient shadow). The transparent-first rule
/// is documented in CLAUDE.md under "Window Transparency".
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
                // "Center when content fits, scroll when it doesn't"
                // pattern — the configured minimum window height (≈ 400
                // dp) is smaller than the natural content height, so the
                // content needs to scroll when the user shrinks the
                // window to the floor.
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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

/// The opaque card that wraps the onboarding content. Fills the entire
/// padded area. The pane edge reads against the acrylic on its own —
/// no shadow needed (the Figma spec carries one, but in a transparent-
/// window + acrylic context it would only blur into an already-blurred
/// material, adding no depth).
class _Pane extends StatelessWidget {
  const _Pane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

/// Shield illustration + title block + buttons + legal footer, centered.
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/illustrations/shield_light.png',
          width: 160,
          height: 137,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'Zeplr Wallet',
          // Kicker / brand identifier above the hero — same 14 px as
          // bodyMedium, but labelLarge's Medium weight + tighter line
          // height reads as a UI label rather than prose.
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Private Money.\nFor the New Internet',
          style: AppTypography.displayMedium.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        const _ButtonsStack(),
        const SizedBox(height: AppSpacing.base),
        const _LegalFooter(),
      ],
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
          leading: const Icon(Icons.add),
          child: const Text('Create new wallet'),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          onPressed: () => context.go('/import'),
          variant: AppButtonVariant.secondary,
          minWidth: _welcomeButtonMinWidth,
          leading: const Icon(Icons.download),
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
    final bodyStyle =
        AppTypography.bodySmall.copyWith(color: colors.text.muted);
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
