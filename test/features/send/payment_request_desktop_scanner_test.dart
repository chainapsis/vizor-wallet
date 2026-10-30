import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/payment_request_scan_screen.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import '../../fakes/fake_gift_link_rust_api.dart';
import '../../support/payment_links_screen_support.dart';

class _ScanApi extends FakeGiftLinkRustApi {
  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) async => const AddressValidationResult(
    isValid: true,
    addressType: 'unified',
    wrongNetwork: false,
  );
}

void main() {
  setUpAll(() async {
    await loadPaymentLinksTestFonts();
    RustLib.initMock(api: _ScanApi());
  });
  tearDownAll(RustLib.dispose);
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const camera = {
      'id': 'desktop-camera',
      'name': 'Desktop camera',
      'facing': 2,
      'isDefault': true,
    };
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
      (call) async => switch (call.method) {
        'state' => 1,
        'request' => true,
        'getAvailableCameras' => [camera],
        'start' => {
          'textureId': 1,
          'camera': camera,
          'cameraDirection': 2,
          'numberOfCameras': 1,
          'size': {'width': 640.0, 'height': 480.0},
        },
        _ => null,
      },
    );
    for (final suffix in ['event', 'deviceOrientation']) {
      messenger.setMockMethodCallHandler(
        MethodChannel('dev.steenbakker.mobile_scanner/scanner/$suffix'),
        (_) async => null,
      );
    }
  });

  testWidgets(
    'desktop re-scan uses the full camera page and returns all new terms',
    (tester) async {
      await pumpPaymentLinksScreen(tester);
      final router = GoRouter.of(
        tester.element(
          find.byKey(const ValueKey('payment_links_desktop_screen')),
        ),
      );
      final result = router.push<SendPrefillArgs>(
        '/send/request-scan?network=main',
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentRequestScanScreen), findsOneWidget);
      expect(find.byType(MobileQrScanCard), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Scan original QR'), findsOneWidget);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('keystone_qr_scanner_camera_viewport')),
        ),
        const Size(388, 310),
      );
      tester
          .widget<PlainQrScannerView>(find.byType(PlainQrScannerView))
          .onComplete('zcash:u1valid?amount=bad');
      await tester.pumpAndSettle();
      expect(
        find.text("This QR code doesn't contain a valid payment request."),
        findsOneWidget,
      );
      tester
          .widget<PlainQrScannerView>(find.byType(PlainQrScannerView))
          .onComplete('zcash:u1valid?amount=0.75&memo=TmV3&label=Shop');
      await tester.pumpAndSettle();
      final scanned = await result;
      expect(scanned?.amountText, '0.75');
      expect(scanned?.memoText, 'New');
      expect(scanned?.label, 'Shop');
      expect(scanned?.requestSource, PaymentRequestSource.qrCode);
      expect(find.byType(PaymentRequestScanScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Back rejects a QR callback during scanner dismissal', (
    tester,
  ) async {
    await pumpPaymentLinksScreen(tester);
    final router = GoRouter.of(
      tester.element(
        find.byKey(const ValueKey('payment_links_desktop_screen')),
      ),
    );
    final result = router.push<SendPrefillArgs>(
      '/send/request-scan?network=main',
    );
    await tester.pumpAndSettle();
    final detect = tester
        .widget<PlainQrScannerView>(find.byType(PlainQrScannerView))
        .onComplete;
    await tester.tap(find.byType(AppBackLink));
    detect('zcash:u1valid?amount=1');
    await tester.pumpAndSettle();
    detect('zcash:u1valid?amount=1');
    expect(await result, isNull);
    expect(router.state.matchedLocation, '/payment-links');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
