import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/widgets/verify_address_modal.dart';
import 'package:zcash_wallet/widgetbook/address_verify_use_cases.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  testWidgets('verify unknown-address use case renders', (tester) async {
    await _pumpUseCase(tester, buildVerifyAddressUnknownUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsOneWidget);
    expect(find.text('Add to contacts'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('verify known-contact use case renders', (tester) async {
    await _pumpUseCase(tester, buildVerifyAddressKnownContactUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('12 previous transactions'), findsOneWidget);
    expect(find.text('Add to contacts'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('verify transparent unknown-address use case renders', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildVerifyAddressUnknownTransparentUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown transparent address'), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppTheme(
        data: AppThemeData.light,
        // Scaffold stands in for Widgetbook's own Material chrome (the
        // add-to-contacts use cases host a TextField).
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1080,
              height: 720,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
