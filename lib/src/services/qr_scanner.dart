import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../main.dart' show log;
import '../rust/api/keystone.dart' as rust_keystone;
import '../rust/wallet/keystone.dart' show UrDecodeResult;

/// Default camera facing per platform.
/// Mobile: back camera for QR scanning.
/// Desktop: external webcam if available (handled by patched mobile_scanner).
CameraFacing get _defaultFacing =>
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
    ? CameraFacing.external
    : CameraFacing.back;

CameraFacing get defaultQrScannerFacing => _defaultFacing;

/// QR scanner abstraction. Uses mobile_scanner on mobile and desktop.
class QrScanner {
  QrScanner._();

  static const formats = <BarcodeFormat>[BarcodeFormat.qrCode];
  static const detectionSpeed = DetectionSpeed.noDuplicates;
  static const scanWindowUpdateThreshold = 8.0;

  static bool get isAvailable =>
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isLinux ||
      Platform.isMacOS;

  static Rect? scanWindowFor(Size layoutSize) {
    if (!layoutSize.width.isFinite ||
        !layoutSize.height.isFinite ||
        layoutSize.width <= 0 ||
        layoutSize.height <= 0) {
      return null;
    }

    final shortestSide = math.min(layoutSize.width, layoutSize.height);
    final side = math.min(shortestSide * 0.9, 280.0);
    return Rect.fromCenter(
      center: layoutSize.center(Offset.zero),
      width: side,
      height: side,
    );
  }
}

class ScanResult {
  final String urType;
  final List<int> data;
  const ScanResult({required this.urType, required this.data});
}

/// Inline animated UR scanner that can be embedded in product screens.
class AnimatedUrScannerView extends StatefulWidget {
  const AnimatedUrScannerView({
    required this.expectedUrType,
    required this.onComplete,
    this.onProgress,
    this.onDecodeError,
    this.controller,
    this.facing,
    this.scanSessionResetToken,
    super.key,
  });

  final String expectedUrType;
  final ValueChanged<ScanResult> onComplete;
  final ValueChanged<int>? onProgress;
  final ValueChanged<Object>? onDecodeError;
  final MobileScannerController? controller;
  final CameraFacing? facing;
  final Object? scanSessionResetToken;

  @override
  State<AnimatedUrScannerView> createState() => _AnimatedUrScannerViewState();
}

class _AnimatedUrScannerViewState extends State<AnimatedUrScannerView> {
  late MobileScannerController _controller;
  late bool _ownsController;
  bool _complete = false;
  final Set<String> _seenParts = {};

  @override
  void initState() {
    super.initState();
    _setController();
    // Ensure Rust's UR decoder starts clean. The previous scan may have
    // left behind a partial multi-part session (cancel / back / mid-stream
    // error), which would otherwise corrupt this fresh scan with stale
    // fountain-code state.
    rust_keystone.resetUrSession();
  }

  void _setController() {
    final controller = widget.controller;
    _ownsController = controller == null;
    _controller =
        controller ??
        MobileScannerController(
          facing: widget.facing ?? _defaultFacing,
          formats: QrScanner.formats,
          detectionSpeed: QrScanner.detectionSpeed,
        );
  }

  void _resetScanSession() {
    _complete = false;
    _seenParts.clear();
    rust_keystone.resetUrSession();
  }

  @override
  void didUpdateWidget(covariant AnimatedUrScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    final ownedFacingChanged =
        widget.controller == null && oldWidget.facing != widget.facing;
    if (controllerChanged || ownedFacingChanged) {
      if (_ownsController) {
        _controller.dispose();
      }
      _setController();
      _resetScanSession();
    } else if (oldWidget.expectedUrType != widget.expectedUrType ||
        oldWidget.scanSessionResetToken != widget.scanSessionResetToken) {
      _resetScanSession();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_complete) return;
    final barcode = capture.barcodes.firstOrNull;
    final value = barcode?.rawValue;
    if (value == null || value.isEmpty) return;

    final normalized = value.toLowerCase();
    if (_seenParts.contains(normalized)) return;

    final UrDecodeResult result;
    try {
      result = await rust_keystone.decodeUrPart(
        part_: value,
        expectedUrType: widget.expectedUrType,
      );
    } catch (e) {
      if (!mounted) return;
      if (_shouldIgnoreDecodeError(e)) {
        return;
      }
      if (_shouldResetScanSessionAfterError(e)) {
        _resetScanSession();
      }
      widget.onDecodeError?.call(e);
      log('QrScanner: UR part decode error: $e');
      return;
    }

    if (!mounted || _complete) return;

    _seenParts.add(normalized);
    widget.onProgress?.call(result.progress);

    if (result.complete && result.data != null) {
      _complete = true;
      widget.onComplete(
        ScanResult(urType: result.urType ?? '', data: result.data!),
      );
    }
  }

  bool _shouldResetScanSessionAfterError(Object error) {
    return error.toString().contains('UR session reset:');
  }

  bool _shouldIgnoreDecodeError(Object error) {
    final message = error.toString();
    return message.contains('Invalid UR: missing type prefix');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          scanWindow: QrScanner.scanWindowFor(constraints.biggest),
          scanWindowUpdateThreshold: QrScanner.scanWindowUpdateThreshold,
        );
      },
    );
  }
}
