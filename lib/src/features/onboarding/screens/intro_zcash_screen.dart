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

/// Two-layer illustration anchored to the bottom of the sidebar, matching
/// Figma node 258:5229. The backdrop layer (`book1.png`) carries the full
/// greyscale scene — sky, mountains, valley, castles, trees — and fades
/// into the acrylic via a top-transparent → bottom-opaque gradient. The
/// focus layer (`knight_light.png`) sits on top, positioned so only the
/// knight figure lines up over the corresponding shape in the backdrop,
/// providing a sharper silhouette right where the eye lands.
///
/// `IgnorePointer` keeps the whole composition out of the hit-test path
/// so the sidebar nav (and future nav interactions) never lose clicks to
/// the illustration.
class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration();

  // Frame size Figma gives for both layers (node 258:5232 book / 258:5233
  // knight-light). Matches the sidebar width exactly, so no responsive
  // scaling is needed at this level.
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
          // Default `Clip.hardEdge` on Stack clips positioned children
          // that overflow the frame — mirrors the Figma frame behavior,
          // where both layers are larger than their containers and only
          // the windowed region is visible.
          child: Stack(
            children: const [
              _BackdropLayer(),
              _KnightLayer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-scene backdrop — book1.png — with a top-clear → bottom-opaque
/// gradient mask applied via `ShaderMask` (`BlendMode.dstIn` against a
/// linear gradient in the alpha channel). Keeping the gradient in code
/// rather than baking it into the asset lets light/dark mode or a future
/// background tweak change how the fade lands without re-exporting.
class _BackdropLayer extends StatelessWidget {
  const _BackdropLayer();

  @override
  Widget build(BuildContext context) {
    // Figma inner image: w:105.18% h:106.6% at left:-2.57% / top:-0.99%
    // (node 258:5232). Literals preserved to avoid drift from rounding.
    return Positioned(
      left: _SidebarIllustration._frameWidth * -0.0257,
      top: _SidebarIllustration._frameHeight * -0.0099,
      width: _SidebarIllustration._frameWidth * 1.0518,
      height: _SidebarIllustration._frameHeight * 1.066,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
          // Figma mask SVG: linearGradient from y=39 to y=445 on a 445-
          // unit viewBox — the top ~8.8% stays fully clear before the
          // ramp begins.
          stops: [0.088, 1.0],
        ).createShader(bounds),
        child: Image.asset(
          'assets/illustrations/book1.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// Focused foreground layer — knight_light.png — scaled up and offset so
/// only the knight figure of the source image sits on top of the
/// corresponding region in the backdrop. The source PNG is colored, but
/// Figma renders the whole illustration greyscale, so a luminance matrix
/// strips the color at paint time. Keep this in sync with the backdrop —
/// if the design ever re-introduces color to the knight, drop the filter
/// here (`book1.png` is already greyscale and does not need one).
class _KnightLayer extends StatelessWidget {
  const _KnightLayer();

  // ITU-R BT.709 luminance coefficients applied to each RGB channel. Keeps
  // the ink detail of the illustration but flattens hue so the knight
  // blends with the already-greyscale backdrop.
  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    // Figma inner image: w:136.13% h:79.92% at left:-26.87% / top:32.65%
    // (node 258:5233). Matches the crop the designer used to isolate the
    // knight silhouette from the rest of the source asset.
    return Positioned(
      left: _SidebarIllustration._frameWidth * -0.2687,
      top: _SidebarIllustration._frameHeight * 0.3265,
      width: _SidebarIllustration._frameWidth * 1.3613,
      height: _SidebarIllustration._frameHeight * 0.7992,
      child: ColorFiltered(
        colorFilter: _greyscale,
        child: Image.asset(
          'assets/illustrations/knight_light.png',
          fit: BoxFit.cover,
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
