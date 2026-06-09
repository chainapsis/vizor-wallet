import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_desktop_preview.dart';
import 'package:zcash_wallet/widgetbook/receive_use_cases.dart';

void main() {
  testWidgets('receive desktop shielded use case renders Figma shell', (
    tester,
  ) async {
    await _pumpReceiveUseCase(tester, buildReceiveDesktopShieldedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceiveDesktopPreview), findsOneWidget);
    expect(
      tester.getSize(find.byType(ReceiveDesktopPreview)),
      ReceiveDesktopPreview.size,
    );
    expect(find.text('Receive ZEC'), findsOneWidget);
    expect(find.text('Copy shielded address'), findsOneWidget);
    expect(find.text('Copy transparent address'), findsNothing);
    expect(find.text('Shielded Address'), findsNothing);
    final backLabelFinder = find.descendant(
      of: find.byKey(const ValueKey('receive_preview_pane_back_button')),
      matching: find.text('Home'),
    );
    final backLabelStyle = tester.widget<Text>(backLabelFinder).style;
    expect(backLabelStyle?.fontSize, 14);
    expect(backLabelStyle?.height, 18 / 14);
    expect(backLabelStyle?.color, AppThemeData.light.colors.text.accent);
    expect(
      tester.getTopLeft(backLabelFinder).dx,
      moreOrLessEquals(316, epsilon: 0.1),
    );
    expect(
      find.byKey(const ValueKey('receive_preview_qr_block_shielded')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('receive_preview_qr_surface_shielded')),
      findsOneWidget,
    );
  });

  testWidgets(
    'receive desktop transparent use case renders transparent state',
    (tester) async {
      await _pumpReceiveUseCase(tester, buildReceiveDesktopTransparentUseCase);

      expect(tester.takeException(), isNull);
      expect(find.byType(ReceiveDesktopPreview), findsOneWidget);
      expect(find.text('Copy transparent address'), findsOneWidget);
      expect(find.text('Copy shielded address'), findsNothing);
      expect(
        find.byKey(const ValueKey('receive_preview_qr_block_transparent')),
        findsOneWidget,
      );
    },
  );

  testWidgets('receive desktop shielded modal use case renders info modal', (
    tester,
  ) async {
    await _pumpReceiveUseCase(tester, buildReceiveDesktopShieldedModalUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('receive_preview_shielded_info_modal')),
      findsOneWidget,
    );
    expect(find.text('Shielded Address'), findsOneWidget);
    expect(find.text('Strong privacy by default.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('receive_preview_shielded_info_modal')),
      ),
      const Size(312, 382),
    );
  });

  testWidgets('receive desktop transparent modal use case renders info modal', (
    tester,
  ) async {
    await _pumpReceiveUseCase(
      tester,
      buildReceiveDesktopTransparentModalUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('receive_preview_transparent_info_modal')),
      findsOneWidget,
    );
    expect(find.text('Transparent Address'), findsOneWidget);
    expect(find.text('Publicly visible'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('receive_preview_transparent_info_modal')),
      ),
      const Size(312, 403),
    );
  });

  testWidgets(
    'receive desktop transparent modal uses dark QR embedded asset in dark mode',
    (tester) async {
      await _pumpReceiveUseCase(
        tester,
        buildReceiveDesktopTransparentModalUseCase,
        theme: AppThemeData.dark,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('receive_preview_qr_surface_transparent')),
        findsOneWidget,
      );
      expect(find.text('Receive ZEC'), findsOneWidget);
      expect(
        find.text(
          "After receiving ZEC to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won't be able to send it.",
        ),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpReceiveUseCase(
  WidgetTester tester,
  Widget Function(BuildContext context) builder, {
  AppThemeData theme = AppThemeData.light,
}) async {
  tester.view.physicalSize = ReceiveDesktopPreview.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: theme,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
