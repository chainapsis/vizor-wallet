import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/swap_contract.dart';

class SwapAssetIcon extends StatelessWidget {
  const SwapAssetIcon({
    required this.asset,
    this.size = 32,
    this.selected = false,
    this.showChainBadge = true,
    super.key,
  });

  final SwapAsset asset;
  final double size;
  final bool selected;
  final bool showChainBadge;

  @override
  Widget build(BuildContext context) {
    final badgeSize = (size * 0.62).clamp(17.0, 24.0);
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
            ),
          ),
          if (showChainBadge)
            Positioned(
              right: -4,
              bottom: -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: context.colors.background.base,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  border: Border.all(color: context.colors.border.regular),
                ),
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

class _RoundAssetImage extends StatelessWidget {
  const _RoundAssetImage({
    required this.assetPath,
    required this.fallbackText,
    required this.selected,
    this.small = false,
  });

  final String assetPath;
  final String fallbackText;
  final bool selected;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => _AssetImageFallback(
          label: fallbackText,
          selected: selected,
          small: small,
        ),
      ),
    );
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
