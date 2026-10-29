@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/mobile_receive_capture.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/features/receive/widgets/mobile/receive_request_sheet.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';
import 'package:zcash_wallet/src/services/native_mobile_navigation_geometry.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _duoNative = MobileNavigationGeometry(
  edge: MobileNavigationEdge.right,
  viewSize: Size(951, 669),
  safeRect: Rect.fromLTWH(0, 0, 867, 635),
  occlusions: [],
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _app({
  MobileNavigationGeometry? native,
  bool keystone = false,
  double textScale = 1,
  bool dark = false,
}) => MaterialApp(
  builder: (context, child) => AppTheme(
    data: dark ? AppThemeData.dark : AppThemeData.light,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  ),
  home: MobileReceiveCapture(native: native, keystone: keystone),
);

Future<void> _view(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  for (final pool in ['shielded', 'transparent']) {
    testWidgets(
      'Duo $pool actions fit one line and retain their accessible pool',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _view(tester, const Size(951, 669));
          await tester.pumpWidget(_app(native: _duoNative));
          await _settle(tester);
          if (pool == 'transparent') {
            await tester.tap(find.text('Transparent'));
            await _settle(tester);
          }
          for (final action in ['Copy', 'Share']) {
            final label = find.text('$action address');
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: label, matching: find.byType(RichText)),
            );
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: '$action address'.length,
              ),
            );
            expect(boxes.map((box) => box.top).toSet(), hasLength(1));
            expect(
              find.bySemanticsLabel('$action $pool address'),
              findsOneWidget,
            );
            expect(
              tester
                  .getSize(
                    find.byKey(
                      ValueKey('mobile_receive_${action.toLowerCase()}'),
                    ),
                  )
                  .height,
              50,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
  final cases =
      <String, ({Size size, MobileNavigationGeometry? native, bool split})>{
        'duo': (size: const Size(951, 669), native: _duoNative, split: true),
        'below-split-boundary': (
          size: const Size(863, 500),
          native: null,
          split: false,
        ),
        'at-split-boundary': (
          size: const Size(864, 500),
          native: null,
          split: true,
        ),
        'short-wide': (size: const Size(951, 320), native: null, split: true),
        'narrow-wide': (size: const Size(568, 320), native: null, split: false),
        'hinge': (
          size: const Size(900, 700),
          native: const MobileNavigationGeometry(
            edge: MobileNavigationEdge.none,
            viewSize: Size(900, 700),
            safeRect: Rect.fromLTWH(0, 0, 900, 700),
            occlusions: [],
            divisions: [Rect.fromLTWH(350, 0, 24, 700)],
          ),
          split: false,
        ),
        'horizontal-hinge': (
          size: const Size(951, 669),
          native: const MobileNavigationGeometry(
            edge: MobileNavigationEdge.none,
            viewSize: Size(951, 669),
            safeRect: Rect.fromLTWH(0, 0, 951, 669),
            occlusions: [],
            divisions: [Rect.fromLTWH(0, 320, 951, 20)],
          ),
          split: true,
        ),
      };
  for (final entry in cases.entries) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final keystone in [false, true]) {
        testWidgets(
          '${entry.key} scale $scale keystone $keystone exposes every receive action',
          (tester) async {
            await _view(tester, entry.value.size);
            await tester.pumpWidget(
              _app(
                native: entry.value.native,
                textScale: scale,
                keystone: keystone,
              ),
            );
            await _settle(tester);
            expect(
              find.byKey(
                ValueKey(
                  entry.value.split
                      ? 'mobile_receive_split'
                      : 'mobile_receive_stacked',
                ),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            final surface = tester.widget<ReceiveQrSurface>(
              find.byType(ReceiveQrSurface),
            );
            expect(surface.size, 260);
            expect(surface.paddingX, 16);
            expect(surface.paddingY, 24);
            expect(surface.scanOptimized, keystone);
            for (final name in ['copy', 'share', 'request']) {
              final action = find.byKey(ValueKey('mobile_receive_$name'));
              await tester.ensureVisible(action);
              await _settle(tester);
              final scroll = tester.getRect(
                find.byKey(const ValueKey('mobile_receive_wide_scroll')),
              );
              final bounds = tester.getRect(action);
              expect(bounds.top, greaterThanOrEqualTo(scroll.top - 1));
              expect(bounds.bottom, lessThanOrEqualTo(scroll.bottom + 1));
              expect(tester.widget<AppButton>(action).onPressed, isNotNull);
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }

  testWidgets(
    'resize preserves selected pool, renewed address and QR pager state',
    (tester) async {
      await _view(tester, const Size(951, 669));
      await tester.pumpWidget(_app());
      await _settle(tester);
      final screenState = tester.state(find.byType(MobileReceiveScreen));
      await tester.tap(find.bySemanticsLabel('Generate new shielded address'));
      await _settle(tester);
      final renewed = tester
          .widget<ReceiveQrSurface>(find.byType(ReceiveQrSurface))
          .address;
      expect(renewed.endsWith('new'), isTrue);
      await tester.tap(find.text('Transparent'));
      await _settle(tester);
      final pagerState = tester.state(find.byType(PageView));
      for (final size in [
        const Size(568, 320),
        const Size(393, 852),
        const Size(951, 669),
      ]) {
        tester.view.physicalSize = size;
        await _settle(tester);
        expect(
          tester.state(find.byType(MobileReceiveScreen)),
          same(screenState),
        );
        expect(tester.state(find.byType(PageView)), same(pagerState));
        expect(
          find.text(
            size.width > size.height
                ? 'Copy address'
                : 'Copy transparent address',
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<ReceiveQrSurface>(find.byType(ReceiveQrSurface)).type,
          ReceiveAddressType.transparent,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Shielded'));
      await _settle(tester);
      expect(
        tester.widget<ReceiveQrSurface>(find.byType(ReceiveQrSurface)).address,
        renewed,
      );
    },
  );

  testWidgets('narrow wide copy and request work after scrolling', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _view(tester, const Size(568, 320));
    await tester.pumpWidget(_app());
    await _settle(tester);
    final copy = find.byKey(const ValueKey('mobile_receive_copy'));
    await tester.ensureVisible(copy);
    await _settle(tester);
    await tester.tap(copy);
    await _settle(tester);
    expect(copied.single, startsWith('u1'));
    final request = find.byKey(const ValueKey('mobile_receive_request'));
    await tester.ensureVisible(request);
    await _settle(tester);
    await tester.tap(request);
    await _settle(tester);
    expect(find.byType(ReceiveRequestSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
