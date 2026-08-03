import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_scan_help_overlay.dart';

Widget _app({required bool visible}) {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: Center(
      child: KeystoneScanHelpOverlay(
        visible: visible,
        child: const SizedBox(key: ValueKey('qr'), width: 200, height: 200),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    final regular = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'));
    final medium = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
    await Future.wait([regular.load(), medium.load()]);
  });

  testWidgets('anchors the Figma scan-help tooltip beside the QR', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(visible: true));
    await tester.pump();

    final qrRect = tester.getRect(find.byKey(const ValueKey('qr')));
    final tooltip = find.byKey(const ValueKey('keystone_scan_help_tooltip'));
    final tooltipRect = tester.getRect(tooltip);
    final tooltipContainer = tester.widget<Container>(tooltip);
    final tooltipDecoration = tooltipContainer.decoration! as BoxDecoration;

    expect(tooltipRect.width, 224);
    if (kAppFormFactor == AppFormFactor.desktop) {
      // The referenced Figma tooltip uses desktop typography and is 98px tall.
      expect(tooltipRect.height, 98);
    } else {
      expect(tooltipRect.height, greaterThanOrEqualTo(72));
    }
    // Figma: 11px QR-to-pointer gap plus the 8px pointer asset.
    expect(tooltipRect.left - qrRect.right, 19);
    expect(tooltipRect.center.dy, qrRect.center.dy);
    expect(tooltipContainer.padding, const EdgeInsets.all(AppSpacing.s));
    expect(
      tooltipDecoration.color,
      AppThemeData.dark.colors.background.inverse,
    );
    expect(
      tooltipDecoration.borderRadius,
      BorderRadius.circular(AppRadii.medium),
    );
    expect(find.text('Scanning issues?'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Scanning issues?'));
    expect(
      title.style,
      AppTypography.bodyMediumStrong.copyWith(
        color: AppThemeData.dark.colors.text.inverse,
      ),
    );
    expect(
      DefaultTextStyle.of(
        tester.element(find.text('Scanning issues?')),
      ).style.decoration,
      TextDecoration.none,
    );
    expect(
      find.textContaining(
        'Update to the latest Keystone firmware at',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Check Keystone firmware version at',
        findRichText: true,
      ),
      findsNothing,
    );
    expect(
      find.textContaining('keyst.one/firmware', findRichText: true),
      findsOneWidget,
    );
    final firmwareLink = tester.widget<Text>(find.text('keyst.one/firmware'));
    expect(
      firmwareLink.style,
      AppTypography.bodyMediumStrong.copyWith(
        color: AppThemeData.dark.colors.text.inverse.withValues(alpha: 0.6),
      ),
    );
  });

  testWidgets('dismisses for the current visible session', (tester) async {
    await tester.pumpWidget(_app(visible: true));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('keystone_scan_help_close')));
    await tester.pump();
    expect(find.text('Scanning issues?'), findsNothing);

    await tester.pumpWidget(_app(visible: true));
    await tester.pump();
    expect(find.text('Scanning issues?'), findsNothing);

    await tester.pumpWidget(_app(visible: false));
    await tester.pump();
    await tester.pumpWidget(_app(visible: true));
    await tester.pump();
    expect(find.text('Scanning issues?'), findsOneWidget);
  });

  testWidgets('close action supports keyboard focus and activation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(visible: true));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final closeAction = find.byKey(const ValueKey('keystone_scan_help_close'));
    final focusedBox = tester.widget<DecoratedBox>(
      find.descendant(of: closeAction, matching: find.byType(DecoratedBox)),
    );
    final focusedDecoration = focusedBox.decoration as BoxDecoration;
    final focusRingColor = focusedDecoration.border!.top.color;
    expect(focusRingColor, AppThemeData.dark.colors.text.inverse);
    expect(focusRingColor, isNot(AppThemeData.dark.colors.background.inverse));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Scanning issues?'), findsNothing);
  });

  testWidgets('stays hidden while the QR is not ready', (tester) async {
    await tester.pumpWidget(_app(visible: false));
    await tester.pump();

    expect(find.text('Scanning issues?'), findsNothing);
  });

  testWidgets('opens the Keystone firmware page in the default browser', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launchedUrls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launch') {
        launchedUrls.add(
          (call.arguments as Map<Object?, Object?>)['url']! as String,
        );
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(_app(visible: true));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keystone_firmware_link')));
    await tester.pump();

    expect(launchedUrls, ['https://keyst.one/firmware']);
  });

  testWidgets('firmware link supports keyboard focus and activation', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launchedUrls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launch') {
        launchedUrls.add(
          (call.arguments as Map<Object?, Object?>)['url']! as String,
        );
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(_app(visible: true));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(launchedUrls, ['https://keyst.one/firmware']);
  });
}
