import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/desktop_payment_link_scan_screen.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_scanner_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_qr_scanner_card.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart';

import '../../support/payment_links_screen_support.dart';
import '../../fakes/fake_gift_link_rust_api.dart';

const _camera = {
  'id': 'desktop-camera',
  'name': 'Desktop camera',
  'facing': 2,
  'isDefault': true,
};

void main() {
  late _UrApi api;
  setUpAll(() async {
    await loadPaymentLinksTestFonts();
    api = _UrApi();
    RustLib.initMock(api: api);
  });
  tearDownAll(RustLib.dispose);
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
      (call) async => switch (call.method) {
        'state' => 1,
        'request' => true,
        'getAvailableCameras' => [
          _camera,
          {..._camera, 'id': 'external-camera', 'name': 'External camera'},
        ],
        'start' => {
          'textureId': 1,
          'camera': _camera,
          'cameraDirection': 2,
          'numberOfCameras': 2,
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
    'desktop provider opens the existing scanner with camera choice',
    (tester) async {
      VizorPaymentLink? result;
      await _openScanner(tester, onResult: (link) => result = link);
      expect(find.byType(MobileQrScanCard), findsNothing);
      expect(find.byType(DesktopPaymentLinkScanScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Open scanner'), findsNothing);
      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.text('Desktop camera (Default)'), findsOneWidget);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('keystone_qr_scanner_camera_viewport')),
        ),
        const Size(388, 310),
      );
      final guard = ProviderScope.containerOf(
        tester.element(find.byType(DesktopPaymentLinkScanScreen)),
      );
      expect(
        guard
            .read(externalActionGuardProvider)
            .blocks(ExternalAction.paymentRequest),
        isTrue,
      );
      await tester.tap(find.byType(AppBackLink));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(DesktopPaymentLinkScanScreen), findsNothing);
      expect(guard.read(externalActionGuardProvider).activeHoldCount, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('invalid QR can be retried and a valid card completes once', (
    tester,
  ) async {
    final results = <VizorPaymentLink?>[];
    await _openScanner(tester, onResult: results.add);
    final onScan = tester
        .widget<PlainQrScannerView>(find.byType(PlainQrScannerView))
        .onComplete;
    onScan('zcash:u1address?amount=1');
    await tester.pump();
    expect(find.text("This isn't a gift card QR code."), findsOneWidget);
    expect(results, isEmpty);
    onScan(incomingLink.toUri().toString());
    onScan(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    expect(results, hasLength(1));
    expect(results.single!.hasSameCanonicalPayload(incomingLink), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('another network is rejected without closing the scanner', (
    tester,
  ) async {
    final results = <VizorPaymentLink?>[];
    await _openScanner(tester, network: 'regtest', onResult: results.add);
    tester
        .widget<PlainQrScannerView>(find.byType(PlainQrScannerView))
        .onComplete(incomingLink.toUri().toString());
    await tester.pump();
    expect(
      find.text('This gift card is for a different network.'),
      findsOneWidget,
    );
    expect(results, isEmpty);
    await tester.tap(find.byType(AppBackLink));
    await tester.pumpAndSettle();
    expect(results, [null]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Back rejects detections during page dismissal', (tester) async {
    final results = <VizorPaymentLink?>[];
    await _openScanner(tester, onResult: results.add);
    final onScan = tester
        .widget<PlainQrScannerView>(find.byType(PlainQrScannerView))
        .onComplete;
    await tester.tap(find.byType(AppBackLink));
    onScan(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    onScan(incomingLink.toUri().toString());
    expect(results, [null]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('invalid QR resets the real single-frame detector for a retry', (
    tester,
  ) async {
    final results = <VizorPaymentLink?>[];
    await _openScanner(tester, onResult: results.add);
    void detect(String raw) => tester
        .widget<MobileScanner>(find.byType(MobileScanner))
        .onDetect!(BarcodeCapture(barcodes: [Barcode(rawValue: raw)]));
    detect('not-a-gift-card');
    await tester.pump();
    detect(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    expect(results, hasLength(1));
    expect(results.single!.hasSameCanonicalPayload(incomingLink), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets(
    'Settings Gift Card uses the desktop page and returns to Redeem',
    (tester) async {
      final operations = FakePaymentLinkOperations();
      await pumpPaymentLinksScreen(tester, operations: operations);
      await tester.tap(find.text('Redeem a card'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_desktop_scan_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesktopPaymentLinkScanScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Scan QR Code'), findsOneWidget);
      await tester.tap(find.byType(AppBackLink));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopPaymentLinkScanScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('payment_link_desktop_scan_button')),
        findsOneWidget,
      );
      expect(operations.preparedLinks, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  for (final completeScan in [false, true]) {
    testWidgets(
      'Settings scanner queues an incoming Gift Card until ${completeScan ? 'the scanned preview is left' : 'Back'}',
      (tester) async {
        final operations = FakePaymentLinkOperations();
        await pumpPaymentLinksScreen(tester, operations: operations);
        await tester.tap(find.text('Redeem a card'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('payment_link_desktop_scan_button')),
        );
        await tester.pumpAndSettle();

        final scanner = find.byType(DesktopPaymentLinkScanScreen);
        final scannerState = tester.state(scanner);
        final context = tester.element(scanner);
        final router = GoRouter.of(context);
        final container = ProviderScope.containerOf(context);
        container
            .read(paymentLinkIntakeProvider.notifier)
            .receive(secondIncomingLink.toUri().toString());
        await tester.pumpAndSettle();

        expect(router.state.matchedLocation, '/payment-links/scan');
        expect(tester.state(scanner), same(scannerState));
        expect(find.byType(MobileScanner), findsOneWidget);
        expect(operations.preparedLinks, isEmpty);
        expect(
          container
              .read(paymentLinkIntakeProvider)
              .pendingLink!
              .hasSameCanonicalPayload(secondIncomingLink),
          isTrue,
        );

        if (completeScan) {
          tester
              .widget<PlainQrScannerView>(find.byType(PlainQrScannerView))
              .onComplete(incomingLink.toUri().toString());
          await tester.pumpAndSettle();
          expect(find.text('You’ve received\na gift card!'), findsOneWidget);
          expect(operations.preparedLinks.map((link) => link.address), [
            incomingLink.address,
          ]);
          expect(
            container.read(paymentLinkIntakeProvider).pendingLink,
            isNotNull,
          );
          await tester.tap(find.text('Cards'));
        } else {
          await tester.tap(find.byType(AppBackLink));
        }
        await tester.pumpAndSettle();

        expect(router.state.matchedLocation, '/payment-links');
        expect(scanner, findsNothing);
        expect(container.read(externalActionGuardProvider).activeHoldCount, 0);
        expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
        expect(operations.preparedLinks.map((link) => link.address), [
          if (completeScan) incomingLink.address,
          secondIncomingLink.address,
        ]);
        expect(find.text('You’ve received\na gift card!'), findsOneWidget);
        expect(operations.claimedSessions, isEmpty);
        expect(operations.receivedRecords, isEmpty);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
  testWidgets('Keystone keeps its animated UR decoding with the shared card', (
    tester,
  ) async {
    final results = <ScanResult>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Center(
            child: KeystoneQrScannerCard(
              expectedUrType: 'zcash-accounts',
              decoding: false,
              error: null,
              onProgress: (_) {},
              onDecodeError: (_) {},
              onComplete: results.add,
              unavailableMessage: 'Connect a camera.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedUrScannerView), findsOneWidget);
    expect(find.byType(PlainQrScannerView), findsNothing);
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
      BarcodeCapture(
        barcodes: [Barcode(rawValue: 'ur:zcash-accounts/example')],
      ),
    );
    await tester.pumpAndSettle();
    expect(api.resetCalls, 1);
    expect(api.expectedType, 'zcash-accounts');
    expect(results.single.data, [1, 2, 3]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

Future<void> _openScanner(
  WidgetTester tester, {
  required ValueChanged<VizorPaymentLink?> onResult,
  String network = 'main',
}) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/gift',
    routes: [
      GoRoute(
        path: '/gift',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async => onResult(
              await ref.read(paymentLinkScannerProvider)(
                context,
                networkName: network,
              ),
            ),
            child: const Text('Open scanner'),
          ),
        ),
      ),
      GoRoute(
        path: '/gift/scan',
        builder: (_, state) => DesktopPaymentLinkScanScreen(
          networkName: state.uri.queryParameters['network']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.tap(find.text('Open scanner'));
  await tester.pumpAndSettle();
}

class _UrApi extends FakeGiftLinkRustApi {
  int resetCalls = 0;
  String? expectedType;
  @override
  void crateApiKeystoneResetUrSession() => resetCalls++;
  @override
  Future<UrDecodeResult> crateApiKeystoneDecodeUrPart({
    required String part_,
    required String expectedUrType,
  }) async {
    expectedType = expectedUrType;
    return UrDecodeResult(
      complete: true,
      progress: 100,
      urType: expectedUrType,
      data: Uint8List.fromList([1, 2, 3]),
    );
  }
}
