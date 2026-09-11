@Tags(['mobile'])
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';

void main() {
  for (final width in [320.0, 375.0]) {
    testWidgets(
      'scrolled artwork stays out of 16px edge gutters at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = Size(width * 3, 240 * 3);
        addTearDown(tester.view.reset);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: PaymentLinkCardSelectorRail(
                      artworks: PaymentLinkCardArtwork.values,
                      selected: PaymentLinkCardArtwork.chestLava,
                      width: 393,
                      itemWidth: 80,
                      itemHeight: 60,
                      artworkWidth: 76,
                      artworkHeight: 56,
                      edgeMaskInset: 16,
                      edgeFadeFraction: 0.3,
                      inactiveOpacity: 1,
                      onSelected: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          for (final artwork in PaymentLinkCardArtwork.values) {
            await precacheImage(
              AssetImage(artwork.assetPath),
              boundaryKey.currentContext!,
            );
          }
        });
        await tester.pumpAndSettle();
        final list = tester.widget<ListView>(find.byType(ListView));
        list.controller!.jumpTo(list.controller!.offset + 37.25);
        await tester.pumpAndSettle();
        final result = await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 3);
          final rgba = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var outerAlpha = 0;
          var innerAlpha = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final alpha = rgba.getUint8((y * image.width + x) * 4 + 3);
              // Check all 16 logical pixels of each gutter at DPR 3.
              if (x < 48 || x >= image.width - 48) {
                outerAlpha += alpha;
              } else {
                innerAlpha += alpha;
              }
            }
          }
          image.dispose();
          return (outerAlpha: outerAlpha, innerAlpha: innerAlpha);
        });
        expect(result!.innerAlpha, greaterThan(0));
        expect(result.outerAlpha, 0);
      },
    );
  }
}
