import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_connection_guide.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  Widget harness({bool enabled = true, double textScale = 1}) => MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Center(
          child: SizedBox(
            width: 288,
            child: LedgerConnectionGuide(
              networkName: 'main',
              awaitingAccountApproval: !enabled,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('explains the app minimum using the actual gate constant', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    expect(
      find.text(
        'Use Zcash app $kMinimumLedgerZcashAppVersion or newer on your Ledger.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('firmware'), findsOneWidget);
    expect(find.text('1. Check the Zcash app version'), findsOneWidget);
    expect(find.text('2. Prepare to connect'), findsOneWidget);
    expect(find.text('App update guide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a narrow card keeps the update link reachable with larger text',
    (tester) async {
      await tester.pumpWidget(harness(textScale: 1.3));
      expect(
        find.byKey(const ValueKey('ledger_app_update_guide')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the update guide opens the official Ledger support article', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(harness());
    await tester.tap(find.text('App update guide'));
    await tester.pump();
    expect(launched, [LedgerConnectionGuide.updateGuideUrl]);
    expect(Uri.parse(launched.single).host, 'support.ledger.com');
  });

  testWidgets('the guide cannot interrupt an active connection request', (
    tester,
  ) async {
    await tester.pumpWidget(harness(enabled: false));
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('ledger_app_update_guide')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining(kMinimumLedgerZcashAppVersion), findsOneWidget);
  });
}
