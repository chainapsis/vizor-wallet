import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../main.dart' show log;
import '../rust/api/keystone.dart' as rust_keystone;
import '../rust/wallet/keystone.dart' show UrDecodeResult;

const _qrUnavailableMessage =
    'Keystone QR scanning requires a camera on this device.';

/// Default camera facing per platform.
/// Mobile: back camera for QR scanning.
/// Desktop: external webcam if available (handled by patched mobile_scanner).
CameraFacing get _defaultFacing =>
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
    ? CameraFacing.external
    : CameraFacing.back;

CameraFacing get defaultQrScannerFacing => _defaultFacing;

/// QR scanner abstraction. Uses mobile_scanner on macOS/iOS/Android.
class QrScanner {
  QrScanner._();

  static bool get isAvailable =>
      Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  static Future<String?> scan(BuildContext context) async {
    if (!isAvailable) {
      throw UnsupportedError(_qrUnavailableMessage);
    }
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _SingleScanScreen()),
    );
  }

  /// Scan an animated UR QR. [expectedUrType] pins the scan to a single UR
  /// registry type (e.g. `"zcash-pczt"` or `"zcash-accounts"`); frames of any
  /// other type are rejected so the caller never sees mismatched CBOR later.
  static Future<ScanResult?> scanAnimatedUr(
    BuildContext context, {
    required String expectedUrType,
    void Function(int progress)? onProgress,
  }) async {
    if (!isAvailable) {
      throw UnsupportedError(_qrUnavailableMessage);
    }
    return Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _AnimatedUrScanScreen(
          expectedUrType: expectedUrType,
          onProgress: onProgress,
        ),
      ),
    );
  }
}

class ScanResult {
  final String urType;
  final List<int> data;
  const ScanResult({required this.urType, required this.data});
}

/// Inline animated UR scanner that can be embedded in product screens.
///
/// The standalone [QrScanner.scanAnimatedUr] route uses the same widget, so
/// QR decoding behaviour stays identical between onboarding and send signing.
class AnimatedUrScannerView extends StatefulWidget {
  const AnimatedUrScannerView({
    required this.expectedUrType,
    required this.onComplete,
    this.onProgress,
    this.onDecodeError,
    this.controller,
    this.facing,
    super.key,
  });

  final String expectedUrType;
  final ValueChanged<ScanResult> onComplete;
  final ValueChanged<int>? onProgress;
  final ValueChanged<Object>? onDecodeError;
  final MobileScannerController? controller;
  final CameraFacing? facing;

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
        MobileScannerController(facing: widget.facing ?? _defaultFacing);
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
    } else if (oldWidget.expectedUrType != widget.expectedUrType) {
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

  @override
  Widget build(BuildContext context) {
    return MobileScanner(controller: _controller, onDetect: _onDetect);
  }
}

// ==================== Single QR Scan Screen ====================

class _SingleScanScreen extends StatefulWidget {
  const _SingleScanScreen();

  @override
  State<_SingleScanScreen> createState() => _SingleScanScreenState();
}

class _SingleScanScreenState extends State<_SingleScanScreen> {
  late final MobileScannerController _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(facing: _defaultFacing);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_scanned) return;
          final barcode = capture.barcodes.firstOrNull;
          if (barcode?.rawValue != null) {
            _scanned = true;
            Navigator.pop(context, barcode!.rawValue);
          }
        },
      ),
    );
  }
}

// ==================== Animated UR Scan Screen ====================

class _AnimatedUrScanScreen extends StatefulWidget {
  final String expectedUrType;
  final void Function(int progress)? onProgress;

  const _AnimatedUrScanScreen({required this.expectedUrType, this.onProgress});

  @override
  State<_AnimatedUrScanScreen> createState() => _AnimatedUrScanScreenState();
}

class _AnimatedUrScanScreenState extends State<_AnimatedUrScanScreen> {
  int _progress = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Keystone QR'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          AnimatedUrScannerView(
            expectedUrType: widget.expectedUrType,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _progress = progress;
              });
              widget.onProgress?.call(progress);
            },
            onComplete: (result) => Navigator.pop(context, result),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _progress > 0
                        ? 'Scanning... $_progress%'
                        : 'Point camera at Keystone QR',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  if (_progress == 0) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Use good light and keep enough distance for the camera to focus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress / 100.0,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
