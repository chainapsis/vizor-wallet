import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

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
    // The enclosing `CustomTransitionPage` uses an identity page
    // transition on purpose so each pane can drive its own entrance
    // from the same route animation: the sidebar slides in from the
    // left, the trailing pane fades in. Sharing the curved animation
    // locks the two halves to one clock, so they settle together.
    // Falls back to a completed animation for static test harnesses /
    // previews where there is no route.
    final routeAnimation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1.0);
    final entrance = CurvedAnimation(
      parent: routeAnimation,
      curve: kOnboardingForwardCurve,
      reverseCurve: kOnboardingReverseCurve,
    );
    final sidebarOffset = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(entrance);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SlideTransition(
                position: sidebarOffset,
                child: const SizedBox(width: 240, child: _Sidebar()),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: FadeTransition(
                  opacity: entrance,
                  child: const _TrailingPane(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Left column. Transparent background so the acrylic shows through, with
/// the nav list at the top and the knight illustration anchored to the
/// bottom (the illustration's own alpha carries the fade into the
/// acrylic — see `_SidebarIllustration`).
///
/// Figma node 258:5214 "Sidebar" carries `rounded-[radii/s] (8 dp)` +
/// `overflow-clip`, so wrap the whole column in a `ClipRRect` to match.
/// Without the clip, the bottom of the knight PNG bleeds past the pane
/// corners because `Image.asset` paints to the raw rectangle.
class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: const Stack(
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
      ),
    );
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `p-[xs]` on the Figma "Navigtaion" container — 8 dp on all sides.
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _NavItem(
            label: 'Intro to Zcash',
            iconName: AppIcons.zcash,
            active: true,
          ),
          SizedBox(height: AppSpacing.xxs),
          _NavItem(
            label: 'Address types',
            iconName: AppIcons.shieldKeyhole,
          ),
          SizedBox(height: AppSpacing.xxs),
          _NavItem(
            label: 'Things to know',
            iconName: AppIcons.book,
          ),
          SizedBox(height: AppSpacing.xxs),
          _NavItem(
            label: 'Secret Passphrase',
            iconName: AppIcons.key,
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
    required this.iconName,
    this.active = false,
  });

  final String label;
  final String iconName;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: active ? 1.0 : 0.5,
      child: Padding(
        // `pl-[xs] py-[xxs]` on Figma NavigtaionItem — 8 dp leading and
        // 4 dp vertical, NO trailing padding. The trailing icon sits
        // flush against the row's right edge, which lands 24 dp from
        // the sidebar's right edge (outer Side p-xs + Navigtaion p-xs).
        padding: const EdgeInsets.only(
          left: AppSpacing.xs,
          top: AppSpacing.xxs,
          bottom: AppSpacing.xxs,
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
            AppIcon(iconName, size: 20, color: colors.icon.accent),
          ],
        ),
      ),
    );
  }
}

/// Sidebar illustration anchored to the bottom of the column, matching
/// the Figma "Illustration" frame inside the Split View Sidebar (nodes
/// 303:1678 light / 303:1680 dark). The Figma design ships two variants
/// of the composited knight scene — the light variant renders with
/// higher contrast / richer tonal range, the dark variant with a
/// softer, more muted palette so the illustration recedes behind the
/// text content. The PNGs are cropped out of the theme-specific Split
/// View exports at 2x; see `onboarding_intro_sidebar_{light,dark}.png`
/// under `assets/illustrations/`.
///
/// Each asset is a Figma composited image — backdrop scene, knight
/// focus layer, and the top-transparent → bottom-opaque gradient fade
/// are already merged. No Dart-side layering, positioning, greyscale
/// filter, or `ShaderMask` is needed; stacking another mask on top of
/// the baked-in fade would double-apply it.
///
/// The PNGs are Figma exports, not source assets (see CLAUDE.md →
/// `scripts/figma-export.js`). To refresh, re-export the Split View
/// frame at 2x for each theme and crop the sidebar column.
///
/// `IgnorePointer` keeps the composition out of the hit-test path so
/// the sidebar nav never loses clicks to the illustration.
class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration();

  // Matches the Figma illustration frame size (240 × 411). The asset
  // was exported/cropped at 2x from this same frame, so `BoxFit.cover`
  // inside this box renders a crisp downscale on 1x/2x/3x displays
  // without needing per-DPR asset variants.
  static const _frameWidth = 240.0;
  static const _frameHeight = 411.0;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/onboarding_intro_sidebar_dark.png'
        : 'assets/illustrations/onboarding_intro_sidebar_light.png';
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: _frameWidth,
          height: _frameHeight,
          child: Image.asset(asset, fit: BoxFit.cover),
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
          // Figma pins "Start Onboarding" at `w-[196px]` — same treatment
          // as the Welcome screen CTAs (see `_welcomeButtonMinWidth`).
          // Expressed as a minimum rather than a fixed width to let the
          // button breathe in longer locales instead of clipping.
          minWidth: 196,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: const Text('Start Onboarding'),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(
          onPressed: () => context.go('/create'),
          variant: AppButtonVariant.ghost,
          trailing: const AppIcon(AppIcons.skip),
          child: const Text('Skip'),
        ),
      ],
    );
  }
}
