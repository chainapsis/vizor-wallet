import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/widgets/received_receipt_view.dart';
import 'package:zcash_wallet/widgetbook/received_receipt_use_cases.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

// The fixture's addresses (lib/widgetbook/received_receipt_use_cases.dart).
const _transparentFromAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';
const _transparentReceivingAddress = 't1Z9N3oVYrYDpnbqDcXJpuLrGpcSLDgHXyo';
const _shieldedReceivingAddress =
    'u1j9g9dnk7f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190592';

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
    expect(
      find.text(truncatedAddress(_transparentFromAddress)),
      findsOneWidget,
    );
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('120 ZEC'), findsOneWidget);
    expect(
      find.text(truncatedAddress(_transparentReceivingAddress)),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Zcash is a privacy-focused ...'), findsOneWidget);
    // The sender paid the fee, so a receive shows none.
    expect(find.text('Network fee'), findsNothing);
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
    expect(
      find.text(truncatedAddress(_shieldedReceivingAddress)),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('shielded-to-shielded use case drops the memo row', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildReceivedReceiptShieldedToShieldedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Shielded sender'), findsOneWidget);
    expect(find.text('Unknown sender'), findsNothing);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('known-sender use case renders the contact row', (tester) async {
    await _pumpUseCase(tester, buildReceivedReceiptKnownSenderUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(
      find.text(truncatedAddress(_transparentFromAddress)),
      findsOneWidget,
    );
  });

  testWidgets('in-progress use case shows the pending receive shape', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildReceivedReceiptInProgressUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Receive in progress...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
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
      localizationsDelegates: appLocalizationsDelegates,
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
