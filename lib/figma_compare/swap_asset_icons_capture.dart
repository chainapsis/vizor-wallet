import 'package:flutter/widgets.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/swap/domain/swap_asset.dart';
import '../src/features/swap/widgets/swap_asset_icon.dart';

/// The missing-logo combinations from the October 2026 provider catalog.
/// Kept independent of the live API so both form factors can be inspected.
List<SwapAsset> swapAssetIconCaptureAssets() => [
  for (final (symbol, chain, decimals) in const [
    ('QTC', 'qtc', 12),
    ('QTC', 'near', 12),
    ('FOGO', 'fogo', 9),
    ('USDG', 'hood', 6),
    ('PONS', 'hood', 18),
    ('CASHCAT', 'hood', 18),
    ('USDe', 'hood', 18),
    ('ETH', 'hood', 18),
    ('WETH', 'hood', 18),
    ('GRAM', 'ton', 9),
    ('TLO', 'eth', 8),
    ('laUSDC', 'base', 6),
    ('wNEARKAT', 'sol', 6),
    ('COCA', 'pol', 18),
    ('COCA', 'base', 18),
  ])
    SwapAsset.live(
      assetId: 'capture:$chain:$symbol',
      symbol: symbol,
      blockchain: chain,
      decimals: decimals,
    ),
];

Widget buildSwapAssetIconsCapture(BuildContext context) {
  final mobile = kAppFormFactor == AppFormFactor.mobile;
  return ColoredBox(
    color: context.colors.background.ground,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            for (final asset in swapAssetIconCaptureAssets())
              SizedBox(
                width: mobile ? constraints.maxWidth : 260,
                height: 48,
                child: Row(
                  children: [
                    SwapAssetIcon(
                      asset: asset,
                      size: mobile ? 40 : 32,
                      badgeScale: mobile ? 0.5 : 0.625,
                      overhangScale: mobile ? 0.1 : 0.125,
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '${asset.symbol} · ${asset.chainLabel}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.primary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
