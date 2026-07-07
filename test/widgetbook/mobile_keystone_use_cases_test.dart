@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/keystone_use_cases.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  testWidgets('mobile Keystone scan permission use case renders dark card', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneScanRequestingUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('Enable camera access'), findsOneWidget);
    expect(
      find.text('A camera is required to connect Keystone.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_permission_card')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_keystone_scan_widgetbook_card')),
      ),
      const Size(361, 694),
    );
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey('mobile_keystone_scan_widgetbook_card')),
      ),
      const Offset(16, 126),
    );
    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.byType(PrettyQrView, skipOffstage: false), findsOneWidget);
  });

  testWidgets('mobile Keystone scan denied use case exposes retry action', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneScanDeniedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text("You've denied camera access"), findsOneWidget);
    expect(find.text('Request again'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_retry_button')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_keystone_scan_widgetbook_card')),
      ),
      const Size(361, 694),
    );
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey('mobile_keystone_scan_widgetbook_card')),
      ),
      const Offset(16, 126),
    );
    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.byType(PrettyQrView, skipOffstage: false), findsOneWidget);
  });

  testWidgets('mobile Keystone active scan use case renders common scan card', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneScanActiveUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Scan the Keystone account QR'), findsOneWidget);
    expect(find.text('Scan a Zcash QR code to continue'), findsNothing);
    expect(find.text('Enable camera access'), findsNothing);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_keystone_scan_widgetbook_card')),
      ),
      const Size(361, 694),
    );
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey('mobile_keystone_scan_widgetbook_card')),
      ),
      const Offset(16, 126),
    );
    expect(find.byType(PrettyQrView), findsOneWidget);
  });

  testWidgets('mobile Keystone loading scan use case renders loading veil', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneScanLoadingUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Loading...'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_keystone_scan_widgetbook_card')),
      ),
      const Size(361, 694),
    );
  });

  testWidgets('mobile Keystone signing loading use case renders Step 1', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneSigningLoadingUseCase);
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.takeException(), isNull);
    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Scan with Keystone'), findsOneWidget);
    expect(find.text('Loading QR code ...'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_keystone_signing_widgetbook_qr_placeholder'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile Keystone signing ready use case enters scanner step', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneSigningReadyUseCase);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Next step'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey('mobile_keystone_signing_widgetbook_qr_frame'),
        ),
      ),
      const Size(320, 320),
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_keystone_signing_widgetbook_cancel')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Step 1/2'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('mobile_keystone_signing_widgetbook_get_signature'),
      ),
    );
    await tester.pump();

    expect(find.text('Step 2/2'), findsOneWidget);
    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(
      find.text('Scan the QR code on your Keystone to finish sending'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_keystone_signing_widgetbook_camera')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Step 2/2'), findsOneWidget);
  });

  testWidgets('mobile Keystone signing scanner use case renders Step 2', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneSigningScannerUseCase);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(find.text('Step 2/2'), findsOneWidget);
    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(
      find.text('Scan the QR code on your Keystone to finish sending'),
      findsNothing,
    );
    expect(find.text('Scanning... 50%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_keystone_signing_widgetbook_camera')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('mobile_keystone_signing_widgetbook_scan_progress_bar'),
      ),
      findsNothing,
    );
  });

  testWidgets('mobile Keystone select account use case lists seeded accounts', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneSelectAccountUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Select account'), findsWidgets);
    expect(find.text('4 accounts found'), findsOneWidget);
    expect(find.text('Account 1'), findsOneWidget);
    expect(find.text('Account 4'), findsOneWidget);
  });

  testWidgets('mobile Keystone connect use case renders the intro cards', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneConnectUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Connect Keystone'), findsOneWidget);
    expect(find.text('1. Check Keystone firmware'), findsOneWidget);
    expect(find.text('link'), findsOneWidget);
    expect(find.text('Download firmware'), findsNothing);
    expect(find.text('2. Prepare to connect'), findsOneWidget);
    expect(find.text('On your Keystone'), findsOneWidget);
    expect(find.text('Unlock it.'), findsNothing);
    expect(find.text('On Vizor'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('mobile Keystone birthday use case renders the entry row', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildMobileKeystoneBirthdayUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.text('Around when did you create your wallet?'),
      findsOneWidget,
    );
    expect(find.text('Enter the date'), findsOneWidget);
    expect(find.text('Enter the block height'), findsOneWidget);
  });
}

Future<void> _pumpUseCase(WidgetTester tester, WidgetBuilder builder) async {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppTheme(
        data: AppThemeData.dark,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
}
