import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import '../figma_compare/figma_compare_font_loader.dart';

const _screenshotPath = String.fromEnvironment(
  'VIZOR_WIDGETBOOK_PLAYGROUND_SCREENSHOT',
);

void main() {
  setUpAll(() async {
    await loadFigmaCompareFonts();
    final poppins = FontLoader('Poppins')
      ..addFont(
        rootBundle.load(
          'packages/widgetbook/assets/fonts/Poppins/Poppins-Regular.ttf',
        ),
      )
      ..addFont(
        rootBundle.load(
          'packages/widgetbook/assets/fonts/Poppins/Poppins-Medium.ttf',
        ),
      )
      ..addFont(
        rootBundle.load(
          'packages/widgetbook/assets/fonts/Poppins/Poppins-SemiBold.ttf',
        ),
      )
      ..addFont(
        rootBundle.load(
          'packages/widgetbook/assets/fonts/Poppins/Poppins-Bold.ttf',
        ),
      );
    await poppins.load();
  });

  testWidgets('Widgetbook addons do not offer the removed workflow controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(
        key: ValueKey('widgetbook_app_capture'),
        child: WidgetbookApp(
          initialRoute:
              '/?path=screens/pay/pay-screen/screen&panels=navigation,addons,knobs',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Addons'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Playground workflow'), findsNothing);
    expect(find.text('Reset preview'), findsNothing);
    expect(find.text('Copy state'), findsNothing);
    expect(find.text('Load state'), findsNothing);
    expect(find.text('Save state'), findsNothing);
    expect(tester.takeException(), isNull);

    if (_screenshotPath.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('widgetbook_app_capture')),
      );
      final png = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return await image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          image.dispose();
        }
      });
      File(_screenshotPath).writeAsBytesSync(png!.buffer.asUint8List());
    }
  });
}
