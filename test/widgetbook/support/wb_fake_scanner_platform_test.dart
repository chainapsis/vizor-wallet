// Pins the camera seam every scanner-hosting fixture depends on: the real
// production scanner widgets must mount, show the placeholder, and receive
// pushed barcodes without a camera.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_qr_scanner_card.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';
import 'package:zcash_wallet/widgetbook/support/wb_fake_scanner_platform.dart';

import 'wb_gallery_harness.dart';

void main() {
  setUpAll(WbFakeUrScanRustApi.install);
  tearDown(WbFakeMobileScannerPlatform.reset);

  testWidgets('PlainQrScannerView renders the fake camera view', (
    tester,
  ) async {
    WbFakeMobileScannerPlatform.install();

    await pumpUseCase(
      tester,
      (context) => PlainQrScannerView(onComplete: (_) {}),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);
    expect(WbFakeMobileScannerPlatform.current!.startCount, 1);

    await disposeTree(tester);
  });

  testWidgets('a pushed barcode reaches PlainQrScannerView.onComplete', (
    tester,
  ) async {
    final fake = WbFakeMobileScannerPlatform.install();
    String? scanned;

    await pumpUseCase(
      tester,
      (context) => PlainQrScannerView(onComplete: (value) => scanned = value),
    );
    await tester.pump();

    fake.pushBarcode('u1wbfakescannerplatformtestaddress');
    await tester.pump();

    expect(scanned, 'u1wbfakescannerplatformtestaddress');

    await disposeTree(tester);
  });

  testWidgets('AnimatedUrScannerView reports progress then completes', (
    tester,
  ) async {
    final fake = WbFakeMobileScannerPlatform.install();
    final progress = <int>[];
    ScanResult? result;

    await pumpUseCase(
      tester,
      (context) => AnimatedUrScannerView(
        expectedUrType: 'zcash-pczt',
        onProgress: progress.add,
        onComplete: (value) => result = value,
      ),
    );
    await tester.pump();
    expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);

    fake.pushBarcode('ur:zcash-pczt/1-2/aabb');
    await tester.pump();
    expect(progress, [50]);
    expect(result, isNull);

    fake.pushBarcode('ur:zcash-pczt/2-2/ccdd');
    await tester.pump();
    expect(progress, [50, 100]);
    expect(result?.urType, 'zcash-pczt');
    expect(result?.data, isNotEmpty);

    await disposeTree(tester);
  });

  testWidgets('a UR of the wrong type raises the production error', (
    tester,
  ) async {
    final fake = WbFakeMobileScannerPlatform.install();
    Object? decodeError;

    await pumpUseCase(
      tester,
      (context) => AnimatedUrScannerView(
        expectedUrType: 'zcash-pczt',
        onProgress: (_) {},
        onComplete: (_) {},
        onDecodeError: (error) => decodeError = error,
      ),
    );
    await tester.pump();

    fake.pushBarcode('ur:zcash-address/1-2/aabb');
    await tester.pump();

    // Six screens pick their actionable copy off this substring, so the fake
    // has to raise the message `keystone.rs` does.
    expect(decodeError.toString(), contains('Unexpected UR type'));

    await disposeTree(tester);
  });

  testWidgets('KeystoneQrScannerCard shows the started camera', (tester) async {
    WbFakeMobileScannerPlatform.install(
      cameras: const [kWbFakeBuiltInCamera, kWbFakeExternalCamera],
    );

    await pumpUseCase(tester, (context) => _card());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);
    // The footer label proves the started camera came from the fake's list.
    expect(find.text('Built-in camera (Default)'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the permission-denied scenario reaches the denied state', (
    tester,
  ) async {
    WbFakeMobileScannerPlatform.install(
      startResult: WbFakeScannerStart.permissionDenied,
    );

    await pumpUseCase(tester, (context) => _card());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text("You've denied the Camera access"), findsOneWidget);
    expect(find.text('Allow camera'), findsOneWidget);
    expect(find.byKey(kWbFakeCameraViewKey), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('the requesting scenario leaves the camera starting', (
    tester,
  ) async {
    WbFakeMobileScannerPlatform.install(
      startResult: WbFakeScannerStart.requesting,
    );

    await pumpUseCase(tester, (context) => _card());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(kWbFakeCameraViewKey), findsNothing);
    expect(find.text("You've denied the Camera access"), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('reset restores the platform instance', (tester) async {
    final before = MobileScannerPlatform.instance;
    final fake = WbFakeMobileScannerPlatform.install();

    expect(MobileScannerPlatform.instance, same(fake));
    expect(WbFakeMobileScannerPlatform.current, same(fake));

    WbFakeMobileScannerPlatform.reset();

    expect(MobileScannerPlatform.instance, same(before));
    expect(WbFakeMobileScannerPlatform.current, isNull);
  });
}

Widget _card() {
  return KeystoneQrScannerCard(
    expectedUrType: 'zcash-accounts',
    decoding: false,
    error: null,
    onProgress: (_) {},
    onDecodeError: (_) {},
    onComplete: (_) {},
    unavailableMessage: 'Camera unavailable',
  );
}
