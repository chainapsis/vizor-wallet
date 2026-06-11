import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/widgets/received_receipt_view.dart';
import 'package:zcash_wallet/widgetbook/received_receipt_use_cases.dart';

void main() {
  testWidgets('transparent-to-transparent use case renders the full frame', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildReceivedReceiptTransparentToTransparentUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Received successfully'), findsOneWidget);
    expect(find.text('t1PV7ny ... GVSpEX'), findsOneWidget);
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('120 ZEC'), findsOneWidget);
    expect(find.text('t1Z9N3o ... DgHXyo'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Zcash is a privacy-focused ...'), findsOneWidget);
    expect(find.text('Network fee'), findsOneWidget);
  });

  testWidgets('transparent-to-shielded use case renders both pools', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildReceivedReceiptTransparentToShieldedUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('u1j9g9d ... 190592'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('shielded-to-shielded use case drops the memo row', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildReceivedReceiptShieldedToShieldedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Unknown sender'), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('known-sender use case renders the contact row', (tester) async {
    await _pumpUseCase(tester, buildReceivedReceiptKnownSenderUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('t1PV7ny ... GVSpEX'), findsOneWidget);
  });

  testWidgets('in-progress use case shows the pending receive shape', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildReceivedReceiptInProgressUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Receive in progress...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    // No fee row on a live inbound transaction.
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Unknown sender'), findsOneWidget);
    expect(find.text('Network fee'), findsNothing);
  });
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view.physicalSize = const Size(1080, 900);
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
            height: 900,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
