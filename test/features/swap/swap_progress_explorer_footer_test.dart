import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_progress_explorer_footer.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _boundary = ValueKey('footer_capture');
const _link = ValueKey('swap_progress_explorer_link');
final _uri = Uri.parse('https://explorer.near-intents.org/transactions/t1test');

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    final name = theme == AppThemeData.light ? 'light' : 'dark';
    testWidgets(
      '$name footer hover is visually inert but pressing still works',
      (tester) async {
        final launched = <String>[];
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
            }
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await _pump(tester, theme, SwapProgressExplorerFooter(uri: _uri));
        final initial = await _pixels(tester);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        final center = tester.getCenter(find.byKey(_link));
        await mouse.moveTo(center);
        await tester.pumpAndSettle();
        expect(
          listEquals(initial, await _pixels(tester)),
          isTrue,
          reason: 'hover must not change the background, label or icon',
        );
        expect(
          tester
              .widgetList<MouseRegion>(
                find.descendant(
                  of: find.byKey(_link),
                  matching: find.byType(MouseRegion),
                ),
              )
              .any((region) => region.cursor == SystemMouseCursors.click),
          isTrue,
        );

        await mouse.down(center);
        await tester.pumpAndSettle();
        expect(
          listEquals(initial, await _pixels(tester)),
          isFalse,
          reason: 'pressed feedback must remain visible',
        );
        await mouse.up();
        await tester.pumpAndSettle();
        expect(launched, [_uri.toString()]);
        expect(listEquals(initial, await _pixels(tester)), isTrue);

        await mouse.moveTo(Offset.zero);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          listEquals(initial, await _pixels(tester)),
          isFalse,
          reason: 'keyboard focus must retain its visible ring',
        );
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }
        expect(launched, List.filled(3, _uri.toString()));
      },
    );

    testWidgets('$name ordinary ghost buttons retain their hover palette', (
      tester,
    ) async {
      var activations = 0;
      await _pump(
        tester,
        theme,
        AppButton(
          onPressed: () => activations++,
          variant: AppButtonVariant.ghost,
          pressedBackgroundColor: theme.colors.state.focusRing,
          child: const Text('Ordinary action'),
        ),
      );
      final initial = await _pixels(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final center = tester.getCenter(find.byType(AppButton));
      await mouse.moveTo(center);
      await tester.pumpAndSettle();
      final hover = await _pixels(tester);
      expect(listEquals(initial, hover), isFalse);
      await mouse.down(center);
      await tester.pumpAndSettle();
      expect(
        listEquals(hover, await _pixels(tester)),
        isTrue,
        reason: 'legacy pressed-background overrides still apply to hover',
      );
      await mouse.up();
      await tester.pumpAndSettle();
      expect(activations, 1);
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  AppThemeData theme,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      home: AppTheme(
        data: theme,
        child: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _boundary,
              child: ColoredBox(
                color: theme.colors.background.ground,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SizedBox(width: 400, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  for (final view in tester.binding.renderViews) {
    view.reassemble();
  }
  await tester.pump();
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundary),
    );
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}
