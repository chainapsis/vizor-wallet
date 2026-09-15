// Pure-Dart stand-ins for the two seams a scanner-hosting screen needs: the
// `mobile_scanner` platform channel (camera) and the Rust UR decoder.
// Widgetbook and gallery tests have neither.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// ignore: implementation_imports
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';

import '../../src/rust/frb_generated.dart';
import '../../src/rust/wallet/keystone.dart'
    show KeystoneAccountInfo, UrDecodeResult;

/// Marks the placeholder that replaces the camera texture.
const Key kWbFakeCameraViewKey = ValueKey('wb_fake_camera_view');

/// Camera output size the fake reports; 16:9 like a real preview.
const Size kWbFakeScannerPreviewSize = Size(1280, 720);

const MobileScannerCameraInfo kWbFakeBuiltInCamera = MobileScannerCameraInfo(
  id: 'wb-built-in',
  name: 'Built-in camera',
  facing: CameraFacing.front,
  lensType: CameraLensType.normal,
  isDefault: true,
  isExternal: false,
);

const MobileScannerCameraInfo kWbFakeBackCamera = MobileScannerCameraInfo(
  id: 'wb-back',
  name: 'Back camera',
  facing: CameraFacing.back,
  lensType: CameraLensType.normal,
  isDefault: true,
  isExternal: false,
);

const MobileScannerCameraInfo kWbFakeExternalCamera = MobileScannerCameraInfo(
  id: 'wb-external',
  name: 'External webcam',
  facing: CameraFacing.external,
  lensType: CameraLensType.any,
  isDefault: false,
  isExternal: true,
);

/// What `start()` does, which is the whole camera-state axis a scanner screen
/// renders: running feed, permission prompt still open, denied, or broken.
enum WbFakeScannerStart {
  /// Resolves with a running camera.
  running,

  /// Never resolves, so the screen stays in its "requesting access" state.
  requesting,

  /// Fails with [MobileScannerErrorCode.permissionDenied].
  permissionDenied,

  /// Fails with [MobileScannerErrorCode.genericError].
  unavailable,
}

/// A `mobile_scanner` platform that needs no camera.
///
/// `MobileScannerController` delegates every operation to
/// `MobileScannerPlatform.instance`, so replacing that one object is enough to
/// render the real `MobileScanner`, [MobileScannerController] state, and every
/// screen built on them.
///
/// It extends the method-channel implementation, with every channel-touching
/// member overridden, because `MobileScanner.initState` type-tests for that
/// class and awaits its force-stop before starting. Extending the bare
/// interface skips that await, so the controller's first state change lands
/// synchronously during mount and any ancestor listening to the same
/// controller asserts 'setState() called during build'.
class WbFakeMobileScannerPlatform extends MethodChannelMobileScanner {
  WbFakeMobileScannerPlatform({
    List<MobileScannerCameraInfo>? cameras,
    this.startResult = WbFakeScannerStart.running,
    this.previewSize = kWbFakeScannerPreviewSize,
    this.errorMessage,
  }) : cameras = cameras ?? const [kWbFakeBackCamera];

  static WbFakeMobileScannerPlatform? _current;
  static MobileScannerPlatform? _originalInstance;

  /// The installed fake, so a fixture can reconfigure the scenario per knob
  /// without reinstalling (which would drop live subscriptions).
  static WbFakeMobileScannerPlatform? get current => _current;

  /// Installs a fresh fake as the platform instance and returns it.
  static WbFakeMobileScannerPlatform install({
    List<MobileScannerCameraInfo>? cameras,
    WbFakeScannerStart startResult = WbFakeScannerStart.running,
    Size previewSize = kWbFakeScannerPreviewSize,
    String? errorMessage,
  }) {
    _originalInstance ??= MobileScannerPlatform.instance;
    _current?._close();
    final fake = WbFakeMobileScannerPlatform(
      cameras: cameras,
      startResult: startResult,
      previewSize: previewSize,
      errorMessage: errorMessage,
    );
    MobileScannerPlatform.instance = fake;
    _current = fake;
    return fake;
  }

  /// The installed fake, installing a default one first if needed.
  static WbFakeMobileScannerPlatform ensureInstalled() => _current ?? install();

  /// Restores the platform instance that was in place before the first
  /// [install], and closes the fake's streams.
  static void reset() {
    _current?._close();
    _current = null;
    final original = _originalInstance;
    if (original != null) {
      MobileScannerPlatform.instance = original;
    }
  }

  /// Cameras `getAvailableCameras()` reports; drives the camera picker.
  List<MobileScannerCameraInfo> cameras;
  WbFakeScannerStart startResult;
  Size previewSize;

  /// Surfaced as the error detail message for [WbFakeScannerStart.unavailable];
  /// null lets the screen show its own fallback copy.
  String? errorMessage;

  /// How many times a controller asked to start, and with what — enough for a
  /// test to assert a retry actually reached the platform.
  int startCount = 0;
  StartOptions? lastStartOptions;
  Rect? lastScanWindow;

  final StreamController<BarcodeCapture?> _barcodes =
      StreamController<BarcodeCapture?>.broadcast();
  final StreamController<TorchState> _torch =
      StreamController<TorchState>.broadcast();
  final StreamController<double> _zoom = StreamController<double>.broadcast();
  final StreamController<List<MobileScannerCameraInfo>> _cameras =
      StreamController<List<MobileScannerCameraInfo>>.broadcast();

  // Held so `requesting` never resolves; completing it is not part of the API.
  Completer<MobileScannerViewAttributes>? _pendingStart;
  TorchState _torchState = TorchState.off;

  /// The controller a fixture or test pushes barcode captures into.
  StreamController<BarcodeCapture?> get barcodeController => _barcodes;

  /// Emits one QR capture carrying [rawValue].
  void pushBarcode(String rawValue) {
    pushCapture(
      BarcodeCapture(
        barcodes: [Barcode(rawValue: rawValue, format: BarcodeFormat.qrCode)],
        size: previewSize,
      ),
    );
  }

  /// Emits [capture] to every listening controller.
  void pushCapture(BarcodeCapture capture) {
    if (_barcodes.isClosed) return;
    _barcodes.add(capture);
  }

  /// Replaces [cameras] and notifies `camerasStream` listeners.
  void pushCameras(List<MobileScannerCameraInfo> cameras) {
    this.cameras = cameras;
    if (_cameras.isClosed) return;
    _cameras.add(cameras);
  }

  /// Applies a new scenario in place. Only the named fields change, so a knob
  /// dispatcher can flip one axis and leave the rest alone.
  void configure({
    List<MobileScannerCameraInfo>? cameras,
    WbFakeScannerStart? startResult,
    Size? previewSize,
    String? errorMessage,
  }) {
    if (cameras != null) this.cameras = cameras;
    if (startResult != null) this.startResult = startResult;
    if (previewSize != null) this.previewSize = previewSize;
    if (errorMessage != null) this.errorMessage = errorMessage;
  }

  void _close() {
    unawaited(_barcodes.close());
    unawaited(_torch.close());
    unawaited(_zoom.close());
    unawaited(_cameras.close());
  }

  MobileScannerCameraInfo? _resolveCamera(String? cameraId) {
    if (cameras.isEmpty) return null;
    for (final camera in cameras) {
      if (camera.id == cameraId) return camera;
    }
    for (final camera in cameras) {
      if (camera.isDefault) return camera;
    }
    return cameras.first;
  }

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => _torch.stream;

  @override
  Stream<double> get zoomScaleStateStream => _zoom.stream;

  @override
  Stream<List<MobileScannerCameraInfo>> get camerasStream => _cameras.stream;

  // Inherited channel streams, replaced so no EventChannel is ever subscribed.
  @override
  Stream<DeviceOrientation> get deviceOrientationChangedStream =>
      const Stream<DeviceOrientation>.empty();

  @override
  Stream<Map<Object?, Object?>> get eventsStream =>
      const Stream<Map<Object?, Object?>>.empty();

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async => null;

  @override
  Widget buildCameraView() => const _WbFakeCameraView();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) {
    startCount++;
    lastStartOptions = startOptions;

    switch (startResult) {
      case WbFakeScannerStart.requesting:
        _pendingStart ??= Completer<MobileScannerViewAttributes>();
        return _pendingStart!.future;
      case WbFakeScannerStart.permissionDenied:
        return Future<MobileScannerViewAttributes>.error(
          const MobileScannerException(
            errorCode: MobileScannerErrorCode.permissionDenied,
          ),
        );
      case WbFakeScannerStart.unavailable:
        return Future<MobileScannerViewAttributes>.error(
          MobileScannerException(
            errorCode: MobileScannerErrorCode.genericError,
            errorDetails: MobileScannerErrorDetails(message: errorMessage),
          ),
        );
      case WbFakeScannerStart.running:
        final camera = _resolveCamera(startOptions.cameraId);
        _torchState = startOptions.torchEnabled
            ? TorchState.on
            : TorchState.off;
        return Future<MobileScannerViewAttributes>.value(
          MobileScannerViewAttributes(
            cameraDirection: camera?.facing ?? startOptions.cameraDirection,
            currentTorchMode: _torchState,
            size: previewSize,
            camera: camera,
            numberOfCameras: cameras.length,
            initialDeviceOrientation: DeviceOrientation.portraitUp,
          ),
        );
    }
  }

  @override
  Future<Set<CameraLensType>> getSupportedLenses() async {
    if (cameras.isEmpty) return const <CameraLensType>{};
    return {CameraLensType.any, for (final c in cameras) c.lensType};
  }

  @override
  Future<List<MobileScannerCameraInfo>> getAvailableCameras() async => cameras;

  @override
  Future<void> toggleTorch() async {
    _torchState = _torchState == TorchState.on ? TorchState.off : TorchState.on;
    if (_torch.isClosed) return;
    _torch.add(_torchState);
  }

  @override
  Future<void> updateScanWindow(Rect? window) async => lastScanWindow = window;

  @override
  Future<void> setZoomScale(double zoomScale) async {}

  @override
  Future<void> resetZoomScale() async {}

  @override
  Future<void> setFocusPoint(Offset position) async {}

  @override
  Future<void> stop({bool force = false}) async {}

  @override
  Future<void> pause({bool force = false}) async {}

  // No-op: a controller disposes the platform, but the fake outlives every
  // controller so the next scanner mount still has working streams.
  @override
  Future<void> dispose() async {}
}

/// Stands in for the camera texture: a dark frame with a viewfinder hint, no
/// text and no theme dependency, so it never reads as product UI.
class _WbFakeCameraView extends StatelessWidget {
  const _WbFakeCameraView();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: kWbFakeCameraViewKey,
      color: Color(0xFF14181B),
      child: Center(
        child: SizedBox.square(
          dimension: 180,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x33FFFFFF), width: 2),
              ),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A `RustLibApi` that answers only the UR-scan calls.
///
/// `AnimatedUrScannerView` calls `resetUrSession()` from `initState` and
/// `decodeUrPart()` per frame; without an initialized bridge those throw a
/// `StateError` and the screen cannot mount at all. Every other Rust call still
/// fails loudly through `noSuchMethod`.
class WbFakeUrScanRustApi implements RustLibApi {
  WbFakeUrScanRustApi({Uint8List? completedData})
    : completedData =
          completedData ?? Uint8List.fromList(List<int>.generate(32, (i) => i));

  /// Payload handed to `onComplete` once a UR finishes.
  final Uint8List completedData;

  /// Installs this fake as the Rust bridge, unless one is already installed.
  ///
  /// Returns whether it took the slot: `RustLib` accepts exactly one mock per
  /// process, so a caller that already installed a broader fake wins.
  static bool install({WbFakeUrScanRustApi? api}) {
    try {
      RustLib.initMock(api: api ?? WbFakeUrScanRustApi());
      return true;
    } on StateError {
      return false;
    }
  }

  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  Future<UrDecodeResult> crateApiKeystoneDecodeUrPart({
    required String part_,
    required String expectedUrType,
  }) async {
    final parts = part_.toLowerCase().split('/');
    if (parts.length < 2 || !parts.first.startsWith('ur:')) {
      throw Exception('Invalid UR: missing type prefix');
    }
    final urType = parts.first.substring(3);
    if (urType != expectedUrType.toLowerCase()) {
      // Byte-for-byte the shape of the Rust error (`keystone.rs:314`): six
      // screens pick their actionable copy by matching 'Unexpected UR type'.
      throw Exception(
        'Unexpected UR type: got "$urType", expected "$expectedUrType"',
      );
    }

    // An empty fragment stands in for one the `ur` decoder cannot read. The
    // scan screens treat this as a session reset rather than a wrong code.
    if (parts.last.isEmpty) {
      throw Exception('UR session reset: UR receive: invalid fragment');
    }

    // `ur:<type>/<seq>-<total>/<payload>` for multi-part, `ur:<type>/<payload>`
    // for single-part.
    final sequence = parts.length > 2 ? parts[1].split('-') : const <String>[];
    final index = sequence.length == 2 ? int.tryParse(sequence[0]) : null;
    final total = sequence.length == 2 ? int.tryParse(sequence[1]) : null;
    if (index == null || total == null || total <= 0) {
      return UrDecodeResult(
        complete: true,
        progress: 100,
        data: completedData,
        urType: urType,
      );
    }

    final complete = index >= total;
    return UrDecodeResult(
      complete: complete,
      progress: (index * 100 / total).round().clamp(0, 100),
      data: complete ? completedData : null,
      urType: urType,
    );
  }

  // The two CBOR decodes a completed scan runs. The fake's UR payload is not
  // real CBOR, so they fail the way a garbled QR does — not as a missing
  // method, which would reach the same copy through a crash and bury real
  // failures in `noSuchMethod` stacks.
  @override
  Future<Uint8List> crateApiKeystoneDecodePcztFromCbor({
    required List<int> cbor,
  }) async => throw Exception('Invalid CBOR payload');

  @override
  Future<List<KeystoneAccountInfo>> crateApiKeystoneDecodeAccountsFromCbor({
    required List<int> cbor,
  }) async => throw Exception('Invalid CBOR payload');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
