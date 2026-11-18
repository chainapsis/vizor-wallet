@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import 'package:zcash_wallet/src/features/send/models/send_scan_result.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_scan_screen.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import '../../support/test_l10n.dart';

const _mainnetAddress =
    'u1testshieldedaddress000000000000000000000000000000000000000000000000';
const _otherNetworkAddress =
    'utest1testnetshieldedaddress00000000000000000000000000000000000000';

/// Rust stand-in for the one call the default resolver makes.
class _RustApiFake implements RustLibApi {
  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) async {
    lastNetwork = network;
    if (address == _mainnetAddress) {
      return const AddressValidationResult(
        isValid: true,
        addressType: 'unified',
        wrongNetwork: false,
      );
    }
    if (address == _otherNetworkAddress) {
      return const AddressValidationResult(
        isValid: false,
        addressType: 'unified',
        wrongNetwork: true,
      );
    }
    return const AddressValidationResult(
      isValid: false,
      addressType: 'invalid',
      wrongNetwork: false,
    );
  }

  String? lastNetwork;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('scan sheet overlays the current page instead of replacing it', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) => Scaffold(
              body: Stack(
                children: [
                  const Center(child: Text('Send page behind scanner')),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        unawaited(
                          showMobileSendScanSheet(
                            context,
                            networkName: kZcashDefaultNetworkName,
                            controller: controller,
                            resolve: (raw) async =>
                                MobileScanOutcome.accepted(raw),
                          ),
                        );
                      },
                      child: const Text('Open scanner'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();

    expect(find.text('Send page behind scanner'), findsOneWidget);
    expect(find.byType(MobileAddressScanCard), findsOneWidget);
    expect(find.text('Scan the address QR code'), findsOneWidget);
  });

  testWidgets('a result that lands while the sheet closes pops nothing else', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);
    final validation = Completer<MobileScanOutcome>();
    Future<SendScanResult?>? scan;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => scan = showMobileSendScanSheet(
                    context,
                    networkName: kZcashDefaultNetworkName,
                    controller: controller,
                    resolve: (_) => validation.future,
                  ),
                  child: const Text('Open scanner'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();

    tester
        .widget<PlainQrScannerView>(
          find.byType(PlainQrScannerView, skipOffstage: false),
        )
        .onComplete(_mainnetAddress);
    await tester.pump();
    // System back, not the card's own close: the sheet stays mounted while it
    // animates out.
    navigator.pop();
    await tester.pump();
    expect(find.byType(MobileAddressScanCard), findsOneWidget);

    validation.complete(const MobileScanOutcome.accepted(_mainnetAddress));
    await tester.pumpAndSettle();

    expect(await scan, isNull);
    expect(find.text('Open scanner'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('the sheet\'s default resolver', () {
    late _RustApiFake rustApi;

    setUpAll(() {
      rustApi = _RustApiFake();
      RustLib.initMock(api: rustApi);
    });
    tearDownAll(RustLib.dispose);

    test('accepts an address this wallet can pay', () async {
      final outcome = await resolveScannedZcashAddress(
        testL10n,
        _mainnetAddress,
        networkName: kZcashDefaultNetworkName,
      );

      expect(outcome.isAccepted, isTrue);
      expect(rustApi.lastNetwork, kZcashDefaultNetworkName);
    });

    test('refuses an address for another network, and says which', () async {
      final outcome = await resolveScannedZcashAddress(
        testL10n,
        _otherNetworkAddress,
        networkName: kZcashDefaultNetworkName,
      );

      expect(outcome.isAccepted, isFalse);
      expect(
        outcome.error,
        '${testL10n.sendRecipientWrongNetwork}.',
        reason:
            'the code scanned fine and holds a real address; "not a Zcash '
            'address" would read as a broken scanner',
      );
    });

    test('refuses anything that is not an address at all', () async {
      final outcome = await resolveScannedZcashAddress(
        testL10n,
        'not-an-address',
        networkName: kZcashDefaultNetworkName,
      );

      expect(outcome.isAccepted, isFalse);
      expect(outcome.error, "This QR code isn't a Zcash address.");
    });
  });
}
