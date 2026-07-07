@Tags(['mobile'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;

const _cameraKey = ValueKey('mobile_address_scan_card_camera');

Widget _host(Widget child) {
  return AppTheme(
    data: AppThemeData.dark,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(393, 852)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(width: 361, child: child),
        ),
      ),
    ),
  );
}

/// Reproduces the swap dialog geometry — a bottom-anchored [MobileModalCard]
/// in a stretch Column[Spacer, card]. The MediaQuery comes from the test view
/// (set to 393×852 by [_useSwapViewport]) so the camera-card height clamp is
/// measured against the same surface it's laid out in — an overflow would throw.
Widget _swapHost(Widget child) {
  return AppTheme(
    data: AppThemeData.dark,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            MobileModalCard(child: child),
          ],
        ),
      ),
    ),
  );
}

/// Sizes the render surface (and thus MediaQuery) to a phone so the camera
/// card's MediaQuery-derived height matches the laid-out height.
void _useSwapViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MobileAddressScanCard _card(
  MobileScannerController controller, {
  String? caption,
  String? permissionTitle,
  VoidCallback? onClose,
  ValueChanged<String>? onScanned,
}) {
  return MobileAddressScanCard(
    controller: controller,
    caption: caption ?? 'Scan a Zcash QR code to continue',
    permissionTitle: permissionTitle ?? 'Scan the address QR code',
    resolve: (raw) async => MobileScanOutcome.accepted(raw),
    onScanned: onScanned ?? (_) {},
    onClose: onClose ?? () {},
  );
}

bool _hasRoundedCameraClip(WidgetTester tester) {
  final cameraClips = tester.widgetList<ClipRRect>(
    find.ancestor(of: find.byKey(_cameraKey), matching: find.byType(ClipRRect)),
  );
  return cameraClips.any(
    (clip) =>
        clip.borderRadius == BorderRadius.circular(AppRadii.xLarge) &&
        clip.clipBehavior == Clip.antiAliasWithSaveLayer,
  );
}

void main() {
  testWidgets('requesting access shows the permission card and Cancel', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);
    var closed = 0;

    await tester.pumpWidget(_host(_card(controller, onClose: () => closed++)));
    await tester.pump();

    // The permission card (not the camera chrome) is shown while access is
    // still being requested.
    expect(find.text('Scan the address QR code'), findsOneWidget);
    expect(find.text('Grant access to your camera'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_address_scan_cancel_button')),
      findsOneWidget,
    );
    // No retry button until access is actually denied.
    expect(
      find.byKey(const ValueKey('mobile_address_scan_retry_button')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_address_scan_cancel_button')),
    );
    expect(closed, 1);
  });

  testWidgets('custom copy replaces the default Zcash scan copy', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        _card(
          controller,
          caption: 'Scan Ethereum QR code',
          permissionTitle: 'Scan Ethereum QR code',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Scan Ethereum QR code'), findsOneWidget);
    expect(find.text('Scan a Zcash QR code to continue'), findsNothing);
    expect(find.text('Scan the address QR code'), findsNothing);

    controller.value = controller.value.copyWith(
      isInitialized: true,
      isRunning: true,
    );
    await tester.pump();

    expect(find.text('Scan Ethereum QR code'), findsOneWidget);
    expect(find.text('Scan a Zcash QR code to continue'), findsNothing);
  });

  testWidgets('denied access swaps in the retry copy and action', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(_card(controller)));
    await tester.pump();

    controller.value = controller.value.copyWith(
      isInitialized: true,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      ),
    );
    await tester.pump();

    expect(find.text("You've denied camera access"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_address_scan_retry_button')),
      findsOneWidget,
    );
    expect(find.text('Request again'), findsOneWidget);
  });

  testWidgets('unavailable camera keeps a Try again recovery action', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(_card(controller)));
    await tester.pump();

    controller.value = controller.value.copyWith(
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerUninitialized,
      ),
    );
    await tester.pump();

    expect(find.text('Camera unavailable'), findsOneWidget);
    // A recoverable open failure must stay actionable in-card.
    expect(
      find.byKey(const ValueKey('mobile_address_scan_retry_button')),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('camera-state morph preserves the single camera element', (
    tester,
  ) async {
    _useSwapViewport(tester);
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    // Real swap geometry so the camera-card height clamp is exercised under the
    // Column[Spacer, MobileModalCard] flex layout; an overflow would throw.
    await tester.pumpWidget(_swapHost(_card(controller)));
    await tester.pump();

    // Permission card first; the camera preview is already mounted behind it.
    expect(find.text('Scan the address QR code'), findsOneWidget);
    expect(find.byKey(_cameraKey), findsNothing);
    final cameraElement = tester.element(
      find.byKey(_cameraKey, skipOffstage: false),
    );

    // Granted-but-spinning-up → the camera card takes over (loading veil).
    controller.value = controller.value.copyWith(isInitialized: true);
    await tester.pump();
    expect(find.text('Loading...'), findsOneWidget);
    expect(find.text('Scan the address QR code'), findsNothing);
    // The single controller's preview element survives the morph (same Element
    // at the same keyed position), so the camera never restarts.
    expect(
      identical(tester.element(find.byKey(_cameraKey)), cameraElement),
      isTrue,
    );
    expect(_hasRoundedCameraClip(tester), isTrue);

    // Running camera preview keeps the same rounded surface.
    controller.value = controller.value.copyWith(isRunning: true);
    await tester.pump();
    expect(find.text('Scan a Zcash QR code to continue'), findsOneWidget);
    expect(
      identical(tester.element(find.byKey(_cameraKey)), cameraElement),
      isTrue,
    );
    expect(_hasRoundedCameraClip(tester), isTrue);

    // Morph back; the permission card returns over the still-mounted camera.
    controller.value = controller.value.copyWith(isInitialized: false);
    await tester.pump();
    expect(find.text('Scan the address QR code'), findsOneWidget);
    expect(find.byKey(_cameraKey), findsNothing);
    expect(
      identical(
        tester.element(find.byKey(_cameraKey, skipOffstage: false)),
        cameraElement,
      ),
      isTrue,
    );
  });
}
