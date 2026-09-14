// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_scan/widgets/address_qr_scan_modal.dart';
import '../src/features/address_scan/widgets/mobile_address_scan_card.dart';
import '../src/features/address_scan/widgets/mobile_address_scan_view.dart';
import '../src/features/onboarding/mobile/mobile_keystone_scan_card.dart';
import 'support/wb_layout.dart';

// Not covered yet: MobileAddressScanView and _TroubleScanningPopover build a
// live MobileScannerController in their own State. That is now previewable —
// `support/wb_fake_scanner_platform.dart` stands in for the camera — so they
// are a follow-up, not a production-change blocker.

// --- Address QR scan modal --------------------------------------------------

/// Camera states [AddressQrScanModalContent] renders, plus the variant where
/// the platform hands us its own "why the camera failed" message.
enum AddressScanModalCamera {
  requesting,
  denied,
  active,
  loading,
  unavailable,
  unavailableDetail,
}

/// Whether a scanned code was rejected; the modal shows it under the viewport.
enum AddressScanModalError { none, noAddress }

/// Whether the camera-picker footer can cycle cameras. The footer itself only
/// exists in the ready / starting states — that axis is [AddressScanModalCamera].
enum AddressScanModalPicker { canSwitch, singleCamera }

/// `_handleScanComplete`'s rejection message.
const String kAddressScanNoAddressError = 'QR code did not include an address.';

/// A `MobileScannerErrorDetails.message` the desktop modal passes through
/// verbatim instead of its generic no-camera copy.
const String kAddressScanDeviceMessage = 'Camera is in use by another app.';

/// The production scan modal on a plain frame, with the camera stubbed.
///
/// No Layout knob: the content branches on `kAppFormFactor` itself, so the
/// mobile hug-content geometry only exists in the mobile lane.
Widget addressQrScanModalFixture({
  AddressScanModalCamera camera = AddressScanModalCamera.active,
  AddressScanModalError error = AddressScanModalError.none,
  AddressScanModalPicker picker = AddressScanModalPicker.canSwitch,
}) {
  final status = _addressScanModalStatus(camera);
  final showsCamera =
      status == AddressQrCameraStatus.active ||
      status == AddressQrCameraStatus.loading;
  return _AddressScanModalFrame(
    child: AddressQrScanModalContent(
      status: status,
      cameraView: showsCamera ? const _WbScanCameraStub() : null,
      canChooseCamera: picker == AddressScanModalPicker.canSwitch,
      onCameraTap: _noop,
      onRetry: _noop,
      onCancel: _noop,
      unavailableDescription: camera == AddressScanModalCamera.unavailableDetail
          ? kAddressScanDeviceMessage
          : null,
      error: error == AddressScanModalError.none
          ? null
          : kAddressScanNoAddressError,
    ),
  );
}

AddressQrCameraStatus _addressScanModalStatus(AddressScanModalCamera camera) {
  return switch (camera) {
    AddressScanModalCamera.requesting => AddressQrCameraStatus.requesting,
    AddressScanModalCamera.denied => AddressQrCameraStatus.denied,
    AddressScanModalCamera.active => AddressQrCameraStatus.active,
    AddressScanModalCamera.loading => AddressQrCameraStatus.loading,
    AddressScanModalCamera.unavailable ||
    AddressScanModalCamera.unavailableDetail =>
      AddressQrCameraStatus.unavailable,
  };
}

/// Plain modal frame: the desktop content pins itself to 312×440, the mobile
/// one stretches, so the box hands it the 361 sheet width either way.
class _AddressScanModalFrame extends StatelessWidget {
  const _AddressScanModalFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Center(child: SizedBox(width: 361, child: child)),
    );
  }
}

// --- Mobile scan card -------------------------------------------------------

/// Camera states [MobileQrScanCard] derives from its controller.
enum AddressScanCardCamera { requesting, denied, active, loading, unavailable }

/// The caption ladder: the idle caption, a rejected code, and the
/// "hold it still" fallback a resolver throw falls back to.
enum AddressScanCardError { none, wrongCode, keepSteady }

/// Which flow's copy the card is carrying.
enum AddressScanCardCopy { sendAndSwap, contacts, pay, giftCard }

/// Whether the permission states use the shared card or a caller's own.
enum AddressScanCardChrome { permissionCard, keystoneCard }

/// Sheet height versus the in-page placement onboarding clamps to.
enum AddressScanCardHeight { modal, inPage }

/// `mobile_send_scan_screen.dart`'s rejection message.
const String kAddressScanWrongCodeError = "This QR code isn't a Zcash address.";

/// [MobileAddressScanCard.steadyHint] — shown when resolution throws.
const String kAddressScanSteadyHint =
    'Keep the QR code steady and fully visible.';

/// The onboarding in-page clamp floor (`cameraHeight.clamp(420, 560)`).
const double kAddressScanInPageCameraHeight = 420;

/// The live [MobileQrScanCard] with a stubbed camera view, driven to a fixed
/// camera state through a real controller.
Widget mobileAddressScanCardFixture({
  AddressScanCardCamera camera = AddressScanCardCamera.active,
  AddressScanCardError error = AddressScanCardError.none,
  AddressScanCardCopy copy = AddressScanCardCopy.sendAndSwap,
  AddressScanCardChrome chrome = AddressScanCardChrome.permissionCard,
  AddressScanCardHeight height = AddressScanCardHeight.modal,
  bool closeEnabled = true,
}) {
  final cameraHeight = height == AddressScanCardHeight.inPage
      ? kAddressScanInPageCameraHeight
      : null;
  return _WbMobileScanCardFrame(
    child: _WbScannerControllerHost(
      // A fresh controller per camera state, so the state is seeded in
      // `initState` and never notified mid-build.
      key: ValueKey('wb_scan_card_${camera.name}'),
      state: _addressScanCardState(camera),
      builder: (context, controller) => MobileQrScanCard(
        controller: controller,
        caption: addressScanCardCaption(copy),
        permissionTitle: addressScanCardPermissionTitle(copy),
        error: addressScanCardErrorMessage(error),
        closeEnabled: closeEnabled,
        cameraHeight: cameraHeight,
        permissionBuilder: chrome == AddressScanCardChrome.keystoneCard
            ? (context, status, unavailableDescription, onRetry, onClose) =>
                  MobileKeystoneScanPermissionCard(
                    status: status,
                    unavailableDescription: unavailableDescription,
                    onRetry: onRetry,
                    cameraHeight:
                        cameraHeight ??
                        MobileAddressScanCardContent.modalCameraHeight(context),
                  )
            : null,
        onClose: _noop,
        cameraViewBuilder: (context, controller) => const _WbScanCameraStub(),
      ),
    ),
  );
}

/// Idle caption, quoted from the flow that passes it.
String addressScanCardCaption(AddressScanCardCopy copy) {
  return switch (copy) {
    AddressScanCardCopy.sendAndSwap => 'Scan a Zcash QR code to continue',
    AddressScanCardCopy.contacts => addressBookQrScanTitle(
      AddressBookNetwork.zcash,
    ),
    AddressScanCardCopy.pay => 'Scan the recipient address QR code',
    AddressScanCardCopy.giftCard => 'Scan the gift card QR code',
  };
}

/// Permission-card title, quoted from the flow that passes it.
String addressScanCardPermissionTitle(AddressScanCardCopy copy) {
  return switch (copy) {
    AddressScanCardCopy.sendAndSwap => 'Scan the address QR code',
    AddressScanCardCopy.contacts => addressBookQrScanTitle(
      AddressBookNetwork.zcash,
    ),
    AddressScanCardCopy.pay => 'Scan the recipient address',
    AddressScanCardCopy.giftCard => 'Scan gift card QR',
  };
}

String? addressScanCardErrorMessage(AddressScanCardError error) {
  return switch (error) {
    AddressScanCardError.none => null,
    AddressScanCardError.wrongCode => kAddressScanWrongCodeError,
    AddressScanCardError.keepSteady => kAddressScanSteadyHint,
  };
}

MobileScannerState _addressScanCardState(AddressScanCardCamera camera) {
  return switch (camera) {
    AddressScanCardCamera.requesting => _wbScannerState(),
    AddressScanCardCamera.loading => _wbScannerState(isInitialized: true),
    AddressScanCardCamera.active => _wbScannerState(
      isInitialized: true,
      isRunning: true,
    ),
    AddressScanCardCamera.denied => _wbScannerState(
      isInitialized: true,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      ),
    ),
    AddressScanCardCamera.unavailable => _wbScannerState(
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerUninitialized,
      ),
    ),
  };
}

/// Phone frame bottom-anchoring the card in the shared [MobileModalCard], the
/// way every scan sheet presents it.
class _WbMobileScanCardFrame extends StatelessWidget {
  const _WbMobileScanCardFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WbFrame(
      layout: WbLayout.mobile,
      child: ColoredBox(
        color: context.colors.background.neutralScrim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            MobileModalCard(child: child),
          ],
        ),
      ),
    );
  }
}

// --- Camera error overlay ---------------------------------------------------

/// What the full-bleed scanner's controller is reporting.
enum MobileScanOverlayError { none, permissionDenied, unavailable }

/// Copy `mobile_address_scan_view.dart` passes the overlay.
const String kMobileScanPermissionDeniedMessage =
    'Camera access is off. Allow it in Settings to scan addresses.';
const String kMobileScanUnavailableMessage =
    'The camera is unavailable right now.';

/// The production overlay over a dark box, the way it sits on live camera
/// video. It renders nothing while the controller reports no error.
Widget mobileScanCameraErrorOverlayFixture({
  MobileScanOverlayError error = MobileScanOverlayError.permissionDenied,
}) {
  return _WbScannerControllerHost(
    key: ValueKey('wb_scan_overlay_${error.name}'),
    state: _mobileScanOverlayState(error),
    builder: (context, controller) => Center(
      child: SizedBox(
        width: 393,
        height: 400,
        child: ColoredBox(
          color: const Color(0xFF17191A),
          child: MobileScanCameraErrorOverlay(
            controller: controller,
            maxWidth: 260,
            permissionDeniedMessage: kMobileScanPermissionDeniedMessage,
            unavailableMessage: kMobileScanUnavailableMessage,
            onOpenSettings: () async {},
          ),
        ),
      ),
    ),
  );
}

MobileScannerState _mobileScanOverlayState(MobileScanOverlayError error) {
  return switch (error) {
    MobileScanOverlayError.none => _wbScannerState(
      isInitialized: true,
      isRunning: true,
    ),
    MobileScanOverlayError.permissionDenied => _wbScannerState(
      isInitialized: true,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      ),
    ),
    MobileScanOverlayError.unavailable => _wbScannerState(
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerUninitialized,
      ),
    ),
  };
}

// --- Viewfinder corners -----------------------------------------------------

/// The three bracket geometries the production scan surfaces use.
enum MobileScanViewfinderVariant { fullScreen, card, keystone, allThree }

/// Bracket arm length, bend radius and stroke width per variant.
const Map<MobileScanViewfinderVariant, (double, double, double)>
kMobileScanViewfinderGeometry = {
  MobileScanViewfinderVariant.fullScreen: (28, 24, 3),
  MobileScanViewfinderVariant.card: (56, 32, 4),
  MobileScanViewfinderVariant.keystone: (60, 32, 6),
};

/// The production brackets on a dark box, at the 256 window the scan card
/// draws them in.
Widget mobileScanViewfinderCornersFixture({
  MobileScanViewfinderVariant variant = MobileScanViewfinderVariant.card,
}) {
  if (variant != MobileScanViewfinderVariant.allThree) {
    return _WbViewfinderBox(variant: variant, size: 256);
  }
  return ColoredBox(
    color: const Color(0xFF17191A),
    child: Center(
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        alignment: WrapAlignment.center,
        children: [
          for (final entry in kMobileScanViewfinderGeometry.keys)
            _WbViewfinderBox(variant: entry, size: 180, labelled: true),
        ],
      ),
    ),
  );
}

class _WbViewfinderBox extends StatelessWidget {
  const _WbViewfinderBox({
    required this.variant,
    required this.size,
    this.labelled = false,
  });

  final MobileScanViewfinderVariant variant;
  final double size;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    final (cornerLength, cornerRadius, strokeWidth) =
        kMobileScanViewfinderGeometry[variant]!;
    final brackets = SizedBox(
      width: size,
      height: size,
      child: MobileScanViewfinderCorners(
        cornerLength: cornerLength,
        cornerRadius: cornerRadius,
        strokeWidth: strokeWidth,
      ),
    );
    if (!labelled) {
      return ColoredBox(
        color: const Color(0xFF17191A),
        child: Center(child: brackets),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        brackets,
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '$cornerLength / $cornerRadius / $strokeWidth',
          style: AppTypography.labelSmall.copyWith(
            color: const Color(0xFFFFFFFF),
          ),
        ),
      ],
    );
  }
}

// --- Shared -----------------------------------------------------------------

/// Stands in for the live camera preview, so no platform channel is mounted.
class _WbScanCameraStub extends StatelessWidget {
  const _WbScanCameraStub();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF343A3D));
  }
}

MobileScannerState _wbScannerState({
  bool isInitialized = false,
  bool isRunning = false,
  MobileScannerException? error,
}) {
  return const MobileScannerState.uninitialized().copyWith(
    isInitialized: isInitialized,
    isRunning: isRunning,
    error: error,
  );
}

/// Holds a real [MobileScannerController] parked at [state], so the production
/// scan widgets derive their camera status the way they do in the app.
///
/// `autoStart: false` keeps the camera closed; the state is seeded once in
/// `initState`, so callers key the host by the state they want.
class _WbScannerControllerHost extends StatefulWidget {
  const _WbScannerControllerHost({
    required this.state,
    required this.builder,
    super.key,
  });

  final MobileScannerState state;
  final Widget Function(
    BuildContext context,
    MobileScannerController controller,
  )
  builder;

  @override
  State<_WbScannerControllerHost> createState() =>
      _WbScannerControllerHostState();
}

class _WbScannerControllerHostState extends State<_WbScannerControllerHost> {
  late final MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(autoStart: false);
    _controller.value = widget.state;
  }

  @override
  void dispose() {
    // `dispose()` reaches the camera platform channel, which the widgetbook
    // host and the test binding do not provide.
    unawaited(_controller.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

void _noop() {}
