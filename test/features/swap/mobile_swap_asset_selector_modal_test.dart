@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_asset_selector_modal.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    builder: (_, navigator) =>
        AppTheme(data: AppThemeData.dark, child: navigator!),
    home: Material(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(393, 852)),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('asset selector scrollbar reaches the exact bottom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _harness(
        MobileSwapAssetSelectorModal(
          assets: SwapAsset.values,
          selected: SwapAsset.usdc,
          onSelected: (_) {},
          onClose: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scrollbarRect = tester.getRect(
      find.byKey(const ValueKey('swap_asset_selector_scrollbar')),
    );
    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('swap_asset_selector_scrollbar')),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    final controller = list.controller!;

    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.thickness, 6);
    expect(scrollbar.mainAxisMargin, 0);
    expect(scrollbar.padding, EdgeInsets.zero);
    expect(scrollbar.crossAxisMargin, 5);
    expect(list.physics, isA<ClampingScrollPhysics>());

    await tester.dragFrom(
      Offset(scrollbarRect.right - 8, scrollbarRect.center.dy),
      const Offset(0, 1000),
    );
    await tester.pump();

    expect(
      controller.position.pixels,
      moreOrLessEquals(controller.position.maxScrollExtent, epsilon: 0.1),
    );
  });
}
