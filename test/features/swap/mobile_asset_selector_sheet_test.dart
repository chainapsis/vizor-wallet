@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_selector_modal.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required List<SwapAsset> assets,
    required SwapAsset selected,
    required ValueChanged<SwapAsset> onSelected,
    bool loading = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        // AppTheme above the Navigator so root-navigator sheets inherit it,
        // mirroring the app's MaterialApp.builder wiring.
        builder: (context, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => showMobileSheet<void>(
                  context: context,
                  builder: (_) => MobileSheetScaffold(
                    title: 'Select asset',
                    expand: true,
                    child: SwapAssetSelectorModal(
                      assets: assets,
                      selected: selected,
                      loading: loading,
                      onSelected: onSelected,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Key rowKey(SwapAsset asset) => ValueKey('swap_asset_row_${asset.identityKey}');

  testWidgets('asset selector opens as a full-screen sheet with chrome', (
    tester,
  ) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc, SwapAsset.eth],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sheet chrome from MobileSheetScaffold.
    expect(find.byKey(const ValueKey('mobile_sheet_grabber')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_sheet_close_button')),
      findsOneWidget,
    );
    expect(find.text('Select asset'), findsOneWidget);

    // Asset selector body.
    expect(
      find.byKey(const ValueKey('swap_asset_search_field')),
      findsOneWidget,
    );
    expect(find.byKey(rowKey(SwapAsset.btc)), findsOneWidget);
  });

  testWidgets('shows skeleton rows while assets are loading', (tester) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
      loading: true,
    );
    await tester.tap(find.text('open'));
    // The skeleton pulses forever, so advance with pump (not pumpAndSettle).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('swap_asset_selector_skeleton')),
      findsOneWidget,
    );
    // Real asset rows are hidden behind the skeleton while loading.
    expect(find.byKey(rowKey(SwapAsset.usdc)), findsNothing);
  });

  testWidgets('search filters the asset list', (tester) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc, SwapAsset.eth],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_asset_search_field')),
      'btc',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(rowKey(SwapAsset.btc)), findsOneWidget);
    expect(find.byKey(rowKey(SwapAsset.eth)), findsNothing);
  });

  testWidgets('tapping an asset returns it', (tester) async {
    SwapAsset? picked;
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc, SwapAsset.eth],
      selected: SwapAsset.usdc,
      onSelected: (asset) => picked = asset,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(rowKey(SwapAsset.btc)));
    await tester.pumpAndSettle();

    expect(picked, SwapAsset.btc);
  });

  testWidgets('tapping the scrim above the sheet dismisses it', (tester) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsOneWidget);

    // The sheet stops short of the top; the gap above it is the barrier.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsNothing);
  });

  testWidgets('over-pulling the grabber rubber-bands up then springs back', (
    tester,
  ) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final grabber = find.byKey(const ValueKey('mobile_sheet_grabber'));
    final restY = tester.getTopLeft(grabber).dy;

    // Pull the grabber up hard.
    final gesture = await tester.startGesture(tester.getCenter(grabber));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();

    final pulledY = tester.getTopLeft(grabber).dy;
    // It follows the finger upward, but the rubber-band caps it (~30px) far
    // short of the 200px pulled.
    expect(pulledY, lessThan(restY));
    expect(restY - pulledY, lessThanOrEqualTo(31));

    await gesture.up();
    await tester.pumpAndSettle();
    // Springs back to the original height.
    expect(tester.getTopLeft(grabber).dy, closeTo(restY, 0.5));
  });

  testWidgets('dragging the grabber down dismisses the sheet', (tester) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('mobile_sheet_grabber')),
      const Offset(0, 260),
    );
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsNothing);
  });

  testWidgets('dragging the header (not just the pill) down dismisses', (
    tester,
  ) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsOneWidget);

    // Drag starting on the title text, not the grabber pill.
    await tester.drag(find.text('Select asset'), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsNothing);
  });

  testWidgets('close button dismisses the sheet', (tester) async {
    await pumpHost(
      tester,
      assets: const [SwapAsset.usdc, SwapAsset.btc],
      selected: SwapAsset.usdc,
      onSelected: (_) {},
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_sheet_close_button')));
    await tester.pumpAndSettle();
    expect(find.text('Select asset'), findsNothing);
  });
}
