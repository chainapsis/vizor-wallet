import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/swap_contract.dart';

class SwapAssetIcon extends StatelessWidget {
  const SwapAssetIcon({
    required this.asset,
    this.size = 32,
    this.selected = false,
    this.showChainBadge = true,
    this.badgeScale = 0.625,
    this.overhangScale = 0.125,
    super.key,
  });

  final SwapAsset asset;
  final double size;
  final bool selected;
  final bool showChainBadge;

  /// Chain-badge diameter as a fraction of [size]. Desktop renders a 5/8
  /// badge (0.625) on its 32px asset = a 20px chain circle. The mobile
  /// composer draws a larger 40px asset but keeps the chain circle at the
  /// same absolute 20px, so it passes 0.5.
  final double badgeScale;

  /// How far the badge overhangs the asset's bottom-right corner, as a
  /// fraction of [size]. Desktop 1/8 (0.125); the mobile 40px asset uses 0.1
  /// so the 20px badge sits flush with a 4px overhang per Figma.
  final double overhangScale;

  @override
  Widget build(BuildContext context) {
    // Figma Asset Image: the chain icon is a circle ringed by a 2px OUTSIDE
    // stroke in the backdrop surface color (no gray border, no inner
    // padding). On desktop's 32px asset it is a 20px circle at (16,16) — 5/8
    // of the asset, overhanging by 1/8; the mobile composer keeps the 20px
    // circle on a 40px asset (0.5 / 0.1).
    final badgeSize = size * badgeScale;
    final overhang = size * overhangScale;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: _RoundAssetImage(
              assetPath: asset.tokenIconAsset,
              fallbackText: asset.symbol,
              selected: selected,
              notch: showChainBadge
                  ? _ChainBadgeNotch(badgeSize: badgeSize, overhang: overhang)
                  : null,
            ),
          ),
          if (showChainBadge)
            Positioned(
              right: -overhang,
              bottom: -overhang,
              child: SizedBox(
                key: ValueKey('swap_asset_chain_badge_${asset.identityKey}'),
                width: badgeSize,
                height: badgeSize,
                child: _RoundAssetImage(
                  assetPath: asset.chainIconAsset,
                  fallbackText: asset.chainTicker,
                  selected: selected,
                  small: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cuts the badge ring out of the token logo so the backdrop shows through.
/// A painted ring would mismatch non-ground surfaces, and its inner edge
/// would meet the badge's edge and leak the logo underneath.
class _ChainBadgeNotch extends CustomClipper<Path> {
  const _ChainBadgeNotch({required this.badgeSize, required this.overhang});

  static const _ringWidth = 2.0;

  final double badgeSize;
  final double overhang;

  @override
  Path getClip(Size size) {
    final center = Offset(
      size.width + overhang - badgeSize / 2,
      size.height + overhang - badgeSize / 2,
    );
    return Path.combine(
      PathOperation.difference,
      Path()..addOval(Offset.zero & size),
      Path()..addOval(
        Rect.fromCircle(center: center, radius: badgeSize / 2 + _ringWidth),
      ),
    );
  }

  @override
  bool shouldReclip(_ChainBadgeNotch oldClipper) =>
      oldClipper.badgeSize != badgeSize || oldClipper.overhang != overhang;
}

class _RoundAssetImage extends StatelessWidget {
  const _RoundAssetImage({
    required this.assetPath,
    required this.fallbackText,
    required this.selected,
    this.small = false,
    this.notch,
  });

  final String assetPath;
  final String fallbackText;
  final bool selected;
  final bool small;
  final CustomClipper<Path>? notch;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      assetPath,
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) => _AssetImageFallback(
        label: fallbackText,
        selected: selected,
        small: small,
      ),
    );
    final notch = this.notch;
    return notch == null
        ? ClipOval(child: image)
        : ClipPath(clipper: notch, child: image);
  }
}

class _AssetImageFallback extends StatelessWidget {
  const _AssetImageFallback({
    required this.label,
    required this.selected,
    required this.small,
  });

  final String label;
  final bool selected;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final normalized = label.trim().isEmpty ? '?' : label.trim();
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.brandCrimsonAlpha
            : colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        normalized.substring(0, 1).toUpperCase(),
        style: (small ? AppTypography.labelSmall : AppTypography.labelMedium)
            .copyWith(
              color: selected ? colors.text.brandCrimson : colors.text.muted,
            ),
      ),
    );
  }
}
