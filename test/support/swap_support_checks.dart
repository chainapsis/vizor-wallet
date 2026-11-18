import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/swap_activity_capture.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_support_notice.dart';

import '../figma_compare/figma_compare_font_loader.dart';

Widget _app(
  WidgetBuilder builder, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: appSupportedLocales(),
  locale: locale,
  builder: (context, child) => AppTheme(
    data: AppThemeData.light,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
  ),
  home: Scaffold(
    body: AppToastHost(child: Builder(builder: builder)),
  ),
);

void runSwapSupportChecks() {
  setUpAll(loadFigmaCompareFonts);
  for (final scenario in [
    ('failed swap', buildSwapActivityFailedCapture, true),
    (
      'failed swap without a deposit',
      (BuildContext context) =>
          buildSwapActivityFailedCapture(context, hasDeposit: false),
      false,
    ),
    ('failed payment', buildPayActivityFailedCapture, true),
    ('expired swap', buildSwapActivityExpiredCapture, true),
    ('processing swap', buildSwapActivityProcessingCapture, false),
    ('refunded swap', buildSwapActivityRefundedCapture, false),
  ]) {
    testWidgets('${scenario.$1} production Activity support visibility', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(scenario.$2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('swap_support_prompt')),
        scenario.$3 ? findsOneWidget : findsNothing,
      );
      if (scenario.$3) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('swap_support_prompt')),
        );
        await tester.tap(find.byKey(const ValueKey('swap_support_prompt')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('swap_support_notice')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('support address and transaction details are copied separately', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final launched = <MethodCall>[];
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
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      launched.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      _app(
        (_) => SingleChildScrollView(
          child: SwapSupportNotice(
            intent: SwapIntent(
              id: 'failed',
              pair: 'USDC -> ZEC',
              sellAmount: '99 USDC',
              receiveEstimate: '1 ZEC',
              provider: 'NEAR Intents',
              status: SwapIntentStatus.failed,
              nextAction: 'Failed',
              depositAddress: '0xdeposit',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    for (final key in ['swap_support_copy_address', 'swap_support_copy']) {
      expect(
        tester.getSemantics(find.byKey(ValueKey(key))).flagsCollection.isButton,
        isTrue,
      );
    }
    expect(copied, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(copied.single, 'support@vizor.cash');
    await tester.tap(find.byKey(const ValueKey('swap_support_copy')));
    await tester.pumpAndSettle();
    expect(copied, hasLength(2));
    expect(copied.last, contains('Deposit address: 0xdeposit'));
    expect(copied.last, isNot(contains('99 USDC')));
    expect(launched, isEmpty);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final locale in ['en', 'ko', 'zh']) {
    testWidgets('$locale support controls remain reachable at 200% text', (
      tester,
    ) async {
      const mobile = kAppFormFactor == AppFormFactor.mobile;
      tester.view.physicalSize = mobile
          ? const Size(320, 852)
          : const Size(320, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final notice = SwapSupportNotice(
        intent: SwapIntent(
          id: 'failed',
          pair: 'USDC -> ZEC',
          sellAmount: '99 USDC',
          receiveEstimate: '1 ZEC',
          provider: 'NEAR Intents',
          status: SwapIntentStatus.failed,
          nextAction: 'Failed',
        ),
      );
      await tester.pumpWidget(
        _app(
          (_) => mobile
              ? SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: notice,
                  ),
                )
              : Center(child: notice),
          locale: Locale(locale),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('support@vizor.cash'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap_support_copy')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('swap_support_copy')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
