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
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_scan_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

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

  group('the sheet\'s default resolver', () {
    late _RustApiFake rustApi;

    setUpAll(() {
      rustApi = _RustApiFake();
      RustLib.initMock(api: rustApi);
    });
    tearDownAll(RustLib.dispose);

    test('accepts an address this wallet can pay', () async {
      final outcome = await resolveScannedZcashAddress(
        _mainnetAddress,
        networkName: kZcashDefaultNetworkName,
      );

      expect(outcome.isAccepted, isTrue);
      expect(rustApi.lastNetwork, kZcashDefaultNetworkName);
    });

    test('refuses an address for another network, and says which', () async {
      final outcome = await resolveScannedZcashAddress(
        _otherNetworkAddress,
        networkName: kZcashDefaultNetworkName,
      );

      expect(outcome.isAccepted, isFalse);
      expect(
        outcome.error,
        '$kWrongNetworkAddressMessage.',
        reason:
            'the code scanned fine and holds a real address; "not a Zcash '
            'address" would read as a broken scanner',
      );
    });

    test('refuses anything that is not an address at all', () async {
      final outcome = await resolveScannedZcashAddress(
        'not-an-address',
        networkName: kZcashDefaultNetworkName,
      );

      expect(outcome.isAccepted, isFalse);
      expect(outcome.error, "This QR code isn't a Zcash address.");
    });
  });
}
