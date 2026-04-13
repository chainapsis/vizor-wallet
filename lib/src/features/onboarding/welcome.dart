import 'package:flutter/material.dart' show Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';

/// Welcome-specific button width. Matches the 224 px buttons-stack Figma
/// sets on the instance override in node 115:3283. Kept inside this file
/// because it's a screen-level layout choice, not a design-system token.
const double _welcomeButtonMinWidth = 224;

/// Onboarding entry point.
///
/// Mirrors the Figma frame 115:3275 — the hero Shield illustration, the
/// "Welcome to Zeplr" display title with its subtitle, a stack of two
/// primary / secondary actions ("Create New Wallet" / "Import a wallet"),
/// and the legal footer with inline Terms / Privacy links.
///
/// The screen targets the large (landscape) desktop layout by design. On
/// entry it asks [AppLayoutNotifier] to switch to [AppLayoutMode.large]
/// so a user who had previously toggled the window into small can still
/// come back through onboarding — the switch is a no-op on mobile and in
/// any case where the app is already in large.
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
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Shield illustration. 160×137 is the Figma size; the PNG
                // source is much larger and gets scaled down at paint.
                Image.asset(
                  'assets/illustrations/shield_light.png',
                  width: 160,
                  height: 137,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: AppSpacing.base),
                Text(
                  'Welcome to Zeplr',
                  style: AppTypography.displayMedium.copyWith(
                    color: colors.text.accent,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Private money for the new Internet',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                const _ButtonsStack(),
                const SizedBox(height: AppSpacing.base),
                const _LegalFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonsStack extends StatelessWidget {
  const _ButtonsStack();

  @override
  Widget build(BuildContext context) {
    // Both buttons carry the same minWidth so they render identical widths
    // even when their labels differ in length; Column picks up the larger
    // child's intrinsic width and applies it to both, matching Figma's
    // 224 px buttons-stack.
    return Column(
      children: [
        AppButton(
          onPressed: () => context.go('/create'),
          variant: AppButtonVariant.primary,
          minWidth: _welcomeButtonMinWidth,
          leading: const Icon(Icons.add),
          child: const Text('Create New Wallet'),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          onPressed: () => context.go('/import'),
          variant: AppButtonVariant.secondary,
          minWidth: _welcomeButtonMinWidth,
          leading: const Icon(Icons.download),
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
    // Body uses `text.muted` per Figma. Link emphasis uses `text.secondary`
    // which is the closest semantic token to Figma's hardcoded `#4D5252` —
    // in light mode the token resolves to `#626767`, one step lighter than
    // the literal, but this preserves legibility in dark mode where the
    // literal would disappear into the background. Navigation handlers are
    // intentionally stubbed until the Terms/Privacy destinations exist.
    final bodyStyle = AppTypography.bodySmall.copyWith(color: colors.text.muted);
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
