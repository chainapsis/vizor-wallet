@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';
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

class _MutableRpcEndpoint extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
  void changeNetwork() => state = defaultRpcEndpointConfig('test');
}

void main() {
  testWidgets('scan sheet overlays the current page instead of replacing it', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        ],
        child: MaterialApp(
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
      ),
    );

    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();

    expect(find.text('Send page behind scanner'), findsOneWidget);
    expect(find.byType(MobileAddressScanCard), findsOneWidget);
    expect(find.text('Scan the address QR code'), findsOneWidget);
  });

  testWidgets(
    'network change closes the Send scanner and discards pending result',
    (tester) async {
      final endpoint = _MutableRpcEndpoint();
      final pending = Completer<MobileScanOutcome>();
      final results = <Object?>[];
      final controller = MobileScannerController(autoStart: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            rpcEndpointProvider.overrideWith(() => endpoint),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      results.add(
                        await showMobileSendScanSheet(
                          context,
                          networkName: 'main',
                          controller: controller,
                          resolve: (_) => pending.future,
                        ),
                      );
                    },
                    child: const Text('Open scanner'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open scanner'));
      await tester.pumpAndSettle();
      tester
          .widget<PlainQrScannerView>(
            find.byType(PlainQrScannerView, skipOffstage: false),
          )
          .onComplete('zcash:request');
      await tester.pump();
      endpoint.changeNetwork();
      await tester.pumpAndSettle();
      expect(find.byType(MobileAddressScanCard), findsNothing);
      expect(results, [null]);
      pending.complete(const MobileScanOutcome.accepted(_mainnetAddress));
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(tester.takeException(), isNull);
    },
  );

  group('the sheet\'s default resolver', () {
    late _RustApiFake rustApi;

    setUpAll(() {
      rustApi = _RustApiFake();
      RustLib.initMock(api: rustApi);
    });
    tearDownAll(RustLib.dispose);

    test(
      'rejects cross-chain payment requests without calling the Zcash validator',
      () async {
        rustApi.lastNetwork = null;
        for (final raw in [
          'bitcoin:bc1qinvoice?amount=0.01&label=Coffee%20shop',
          'litecoin:ltc1qinvoice?amount=1.5',
          'ethereum:0xToken@8453/transfer?address=0xPayee&uint256=25000000',
          'solana:Payee?amount=25&spl-token=Mint&reference=Order',
        ]) {
          final outcome = await resolveScannedZcashAddress(
            raw,
            networkName: kZcashDefaultNetworkName,
          );
          expect(outcome.isAccepted, isFalse);
          expect(
            outcome.error,
            'Only Zcash addresses and payment requests can be scanned here.',
          );
        }
        expect(rustApi.lastNetwork, isNull);
      },
    );

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
      expect(
        outcome.error,
        'Only Zcash addresses and payment requests can be scanned here.',
      );
    });
  });
}
