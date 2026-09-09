import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/ledger_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final height in [692.0, 500.0]) {
    testWidgets('Bluetooth picker stays in its pane at height $height', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(1080, height);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('ble_capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: AppTheme(
              data: AppThemeData.dark,
              child: buildLedgerFlowPreview(
                screen: 'Connect Ledger',
                mobile: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paneRect = tester.getRect(find.byType(AppDesktopPane));
      final launch = find.byKey(
        const ValueKey('ledger_desktop_ble_connect_button'),
      );
      await tester.ensureVisible(launch);
      await tester.tap(launch);
      await tester.pumpAndSettle();
      final overlay = find.byKey(
        const ValueKey('ledger_desktop_ble_modal_pane'),
      );
      final card = find.byKey(
        const ValueKey('ledger_desktop_ble_connect_dialog'),
      );
      expect(tester.getRect(overlay), paneRect);
      expect(tester.getRect(card).center.dx, paneRect.center.dx);
      expect(
        tester.getRect(card).height,
        lessThanOrEqualTo(paneRect.height - AppSpacing.sm * 2),
      );
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      final device = find.byKey(
        const ValueKey('ledger_desktop_ble_device_preview-flex'),
      );
      final cancel = find.byKey(const ValueKey('ledger_desktop_ble_close'));
      final deviceWidth = tester.getSize(device).width;
      expect(tester.getSize(cancel).width, deviceWidth);
      expect(tester.getRect(cancel).left, tester.getRect(device).left);
      const dir = String.fromEnvironment('LEDGER_PREVIEW_CAPTURE_DIR');
      if (dir.isNotEmpty) {
        await expectLater(
          find.byKey(const ValueKey('ble_capture')),
          matchesGoldenFile(Uri.file('$dir/bluetooth-${height.toInt()}.png')),
        );
      }
      await tester.ensureVisible(device);
      await tester.tap(device);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final continueButton = find.byKey(
        const ValueKey('ledger_desktop_ble_continue'),
      );
      expect(continueButton, findsOneWidget);
      expect(tester.getSize(continueButton).width, deviceWidth);
      expect(tester.getSize(cancel).width, deviceWidth);
      if (dir.isNotEmpty) {
        await expectLater(
          find.byKey(const ValueKey('ble_capture')),
          matchesGoldenFile(
            Uri.file('$dir/bluetooth-ready-${height.toInt()}.png'),
          ),
        );
      }
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);
      expect(launch, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
