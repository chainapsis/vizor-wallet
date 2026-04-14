import 'package:flutter/material.dart' show Colors, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';

/// Onboarding step 1 — Figma "Split View" at node 258:5213.
///
/// The Welcome screen's "Create new wallet" button lands here. It is the
/// first of a four-step walkthrough (the sidebar items preview the other
/// three); the remaining steps are not yet implemented, so both
/// `Start Onboarding` and `Skip` currently route to `/create` where the
/// real wallet-creation + mnemonic flow lives.
///
/// Layout mirrors the Figma split:
///
/// ```
/// 8dp transparent gap (acrylic shows through)
/// ├── 240dp Sidebar      — transparent, nav items + fading knight art
/// ├── 8dp gap            — still acrylic
/// └── flex Trailing Pane — opaque `background.ground`, 8dp radius
/// ```
///
/// Only the trailing pane is opaque on purpose — the sidebar background
/// stays clear so the native window effect (see `CLAUDE.md` →
/// "Window Transparency") remains visible on the left column.
class IntroZcashScreen extends StatelessWidget {
  const IntroZcashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              SizedBox(width: 240, child: _Sidebar()),
              SizedBox(width: AppSpacing.xs),
              Expanded(child: _TrailingPane()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Left column. The nav list sits at the top; the knight illustration
/// anchors to the bottom and fades into the acrylic backdrop via a
/// top-to-bottom gradient mask — the Figma composes a greyscale version
/// of the image into a gradient mask, so the Dart side drops the color
/// via a saturation matrix and mirrors that fade with `ShaderMask`.
class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(child: _SidebarIllustration()),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xs),
            child: _SidebarNav(),
          ),
        ),
      ],
    );
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `px-[xxs] py-[xs]` on the Figma "Navigtaion" container — snug
      // inset that lets the row fills still breathe against the pane edge.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _NavItem(
            label: 'Intro to Zcash',
            icon: Icons.currency_exchange,
            active: true,
          ),
          SizedBox(height: AppSpacing.xxs),
          _NavItem(
            label: 'Address types',
            icon: Icons.shield_outlined,
          ),
          SizedBox(height: AppSpacing.xxs),
          _NavItem(
            label: 'Things to know',
            icon: Icons.menu_book_outlined,
          ),
          SizedBox(height: AppSpacing.xxs),
          _NavItem(
            label: 'Secret Passphrase',
            icon: Icons.key_outlined,
          ),
        ],
      ),
    );
  }
}

/// Single row in the sidebar walkthrough list. The current step shows at
/// full opacity; upcoming steps dim to 50% per the Figma spec. No press /
/// hover state yet — the rest of the walkthrough isn't implemented, so the
/// items are presentational for now.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: active ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            Icon(icon, size: 20, color: colors.icon.accent),
          ],
        ),
      ),
    );
  }
}

/// Sidebar illustration anchored to the bottom of the column, matching
/// Figma node 258:5229 "Illustration". The asset
/// (`onboarding_intro_sidebar.png`) is the Figma node exported as a
/// composited image — the backdrop scene and the focus knight layer are
/// already merged together, AND the top-transparent → bottom-opaque
/// gradient fade is baked into the PNG's alpha channel by the Figma
/// export. No Dart-side layering, positioning, greyscale filter, or
/// `ShaderMask` is needed; stacking another mask on top of the baked-in
/// alpha would double-apply the fade.
///
/// The PNG is a Figma export, not a source asset (see CLAUDE.md →
/// `scripts/figma-export.js`). Re-run that script to refresh the image
/// if the designer changes the illustration node — the refreshed PNG
/// will keep carrying the alpha fade, so this widget stays unchanged.
///
/// `IgnorePointer` keeps the composition out of the hit-test path so the
/// sidebar nav never loses clicks to the illustration.
class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration();

  // Matches the Figma illustration frame size (240 × 411). The asset was
  // exported at 2x from this same frame, so `BoxFit.cover` inside this
  // box renders a crisp downscale on 1x/2x/3x displays without needing
  // per-DPR asset variants.
  static const _frameWidth = 240.0;
  static const _frameHeight = 411.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: _frameWidth,
          height: _frameHeight,
          child: Image.asset(
            'assets/illustrations/onboarding_intro_sidebar.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

/// Opaque right column. Holds the step copy and the primary / skip
/// actions; laid out with `MainAxisAlignment.spaceBetween` so the title
/// sticks to the top and the body + buttons drop to the bottom regardless
/// of window height.
class _TrailingPane extends StatelessWidget {
  const _TrailingPane();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [_Title(), _BottomContent()],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome to\nthe Shielded World',
          style: AppTypography.displaySmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Zcash (ZEC) built around financial privacy & self-custody.',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.accent,
          ),
        ),
      ],
    );
  }
}

class _BottomContent extends StatelessWidget {
  const _BottomContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Paragraph column uses the 384dp width from Figma so lines break
    // exactly where the design puts them. A narrower window clips via
    // `softWrap` since Text wraps by default.
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.primary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 384,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unlike Bitcoin or Ethereum, shielded Zcash transactions '
                'hide the sender, recipient, and amount — verified by '
                'cryptography, not trust.',
                style: bodyStyle,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "You're a few steps away from your first private wallet.\n"
                "Let's get you set up.",
                style: bodyStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        const _ActionRow(),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          // TODO(onboarding): route to step 2 ("Address types") once that
          // screen exists. For now, skip straight to mnemonic creation so
          // the flow remains usable.
          onPressed: () => context.go('/create'),
          variant: AppButtonVariant.primary,
          trailing: const Icon(Icons.chevron_right),
          child: const Text('Start Onboarding'),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(
          onPressed: () => context.go('/create'),
          variant: AppButtonVariant.ghost,
          // Material's `skip_next` is the closest stock match for the
          // Figma `skip` glyph (double-chevron → vertical bar).
          trailing: const Icon(Icons.skip_next),
          child: const Text('Skip'),
        ),
      ],
    );
  }
}
