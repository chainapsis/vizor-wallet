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
      Platform.isMacOS ||
      Platform.isWindows;

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

/// Inline QR scanner for single-frame QR payloads such as plain addresses or
/// payment URIs. Animated UR payloads should continue to use
/// [AnimatedUrScannerView] so fountain-code state stays isolated.
class PlainQrScannerView extends StatefulWidget {
  const PlainQrScannerView({
    required this.onComplete,
    this.controller,
    this.facing,
    this.scanSessionResetToken,
    super.key,
  });

  final ValueChanged<String> onComplete;
  final MobileScannerController? controller;
  final CameraFacing? facing;
  final Object? scanSessionResetToken;

  @override
  State<PlainQrScannerView> createState() => _PlainQrScannerViewState();
}

class _PlainQrScannerViewState extends State<PlainQrScannerView> {
  late MobileScannerController _controller;
  late bool _ownsController;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _setController();
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

  @override
  void didUpdateWidget(covariant PlainQrScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    final ownedFacingChanged =
        widget.controller == null && oldWidget.facing != widget.facing;
    if (!controllerChanged && !ownedFacingChanged) {
      if (oldWidget.scanSessionResetToken != widget.scanSessionResetToken) {
        _complete = false;
      }
      return;
    }
    if (_ownsController) {
      _controller.dispose();
    }
    _setController();
    _complete = false;
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_complete) return;
    final value = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _complete = true;
    widget.onComplete(value);
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

/// Inline animated UR scanner that can be embedded in product screens.
class AnimatedUrScannerView extends StatefulWidget {
  const AnimatedUrScannerView({
    required this.expectedUrType,
    required this.onComplete,
    this.additionalExpectedUrTypes = const [],
    this.onProgress,
    this.onDecodeError,
    this.controller,
    this.facing,
    this.scanSessionResetToken,
    super.key,
  });

  final String expectedUrType;
  final List<String> additionalExpectedUrTypes;
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

  List<String> get _acceptedUrTypes => <String>{
    widget.expectedUrType.toLowerCase(),
    ...widget.additionalExpectedUrTypes.map((type) => type.toLowerCase()),
  }.toList(growable: false);

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
        !_sameStringList(
          oldWidget.additionalExpectedUrTypes,
          widget.additionalExpectedUrTypes,
        ) ||
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

    final partUrType = _urTypeFromPart(value);
    final acceptedUrTypes = _acceptedUrTypes;
    if (partUrType != null && !acceptedUrTypes.contains(partUrType)) {
      widget.onDecodeError?.call(
        'Unexpected UR type $partUrType, expected ${acceptedUrTypes.join(', ')}',
      );
      return;
    }

    final UrDecodeResult result;
    try {
      result = await rust_keystone.decodeUrPart(
        part_: value,
        expectedUrType: partUrType ?? widget.expectedUrType,
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
        ScanResult(
          urType: result.urType ?? partUrType ?? widget.expectedUrType,
          data: result.data!,
        ),
      );
    }
  }

  /// Extract the UR type (e.g. `zcash-sig-result`) from a UR part string, or
  /// null when the string is not a UR. Lets the scanner route a part to the
  /// right expected type when more than one UR type is accepted.
  String? _urTypeFromPart(String value) {
    final normalized = value.trim().toLowerCase();
    const prefix = 'ur:';
    if (!normalized.startsWith(prefix)) {
      return null;
    }
    final typeStart = prefix.length;
    final typeEnd = normalized.indexOf('/', typeStart);
    if (typeEnd <= typeStart) {
      return null;
    }
    return normalized.substring(typeStart, typeEnd);
  }

  /// Order-sensitive string list equality, used to detect a changed
  /// `additionalExpectedUrTypes` across widget updates.
  bool _sameStringList(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
