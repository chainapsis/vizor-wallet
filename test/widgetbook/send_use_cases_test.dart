import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_compose_view.dart';
import 'package:zcash_wallet/widgetbook/send_use_cases.dart';

void main() {
  testWidgets('send empty use case renders desktop compose shell', (
    tester,
  ) async {
    await _pumpSendUseCase(tester, buildSendEmptyUseCase);

    expect(tester.takeException(), isNull);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppThemeData.light.colors.macosUtility.window,
    );
    expect(find.byType(SendComposeView), findsOneWidget);
    expect(find.text('Send ZEC'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Add a memo'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('send_add_memo_card'))),
      const Size(396, 128),
    );
    final backLabelFinder = find.descendant(
      of: find.byKey(const ValueKey('send_preview_pane_back_button')),
      matching: find.text('Home'),
    );
    final backLabelStyle = tester.widget<Text>(backLabelFinder).style;
    expect(backLabelStyle?.fontSize, 14);
    expect(backLabelStyle?.height, 16 / 14);
    expect(backLabelStyle?.color, AppThemeData.light.colors.button.ghost.label);
    expect(
      tester.getTopLeft(backLabelFinder).dx,
      moreOrLessEquals(316, epsilon: 0.1),
    );
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('send filled use cases keep the contacts picker label stable', (
    tester,
  ) async {
    await _pumpSendUseCase(tester, buildSendShieldedFilledUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(find.text('125.12'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('send_amount_field')),
        matching: find.text('ZEC'),
      ),
      findsOneWidget,
    );

    await _pumpSendUseCase(tester, buildSendTransparentUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Shielded → Shielded'), findsNothing);
    expect(find.text('Shielded → Transparent'), findsNothing);
    expect(find.text('Add a memo'), findsNothing);
    expect(find.text('Encrypted, for shielded addresses only.'), findsNothing);

    await _pumpSendUseCase(tester, buildSendContactSelectedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Mike'), findsNothing);
    expect(find.text('Contacts'), findsOneWidget);
  });
}

Future<void> _pumpSendUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: 1080,
            height: 720,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
