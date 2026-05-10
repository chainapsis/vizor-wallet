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
  late final MobileScannerController _controller;
  int _progress = 0;
  bool _complete = false;
  final Set<String> _seenParts = {};

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(facing: _defaultFacing);
    // Ensure Rust's UR decoder starts clean. The previous scan may have
    // left behind a partial multi-part session (cancel / back / mid-stream
    // error), which would otherwise corrupt this fresh scan with stale
    // fountain-code state.
    rust_keystone.resetUrSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_complete) return;
    final barcode = capture.barcodes.firstOrNull;
    final value = barcode?.rawValue;
    if (value == null || value.isEmpty) return;

    final normalized = value.toLowerCase();
    if (_seenParts.contains(normalized)) return;

    // Scope the try to just the await. Any post-await state mutation must
    // happen outside, gated by the mounted/_complete check below, so the
    // control flow is obvious and a thrown exception can't accidentally
    // land in the middle of a state update.
    final UrDecodeResult result;
    try {
      result = await rust_keystone.decodeUrPart(
        part_: value,
        expectedUrType: widget.expectedUrType,
      );
    } catch (e) {
      // Deliberately do NOT add to _seenParts here — the same fragment will
      // come back on the next animation cycle and get another chance.
      log('QrScanner: UR part decode error: $e');
      return;
    }

    // Post-await lifecycle guard. Discard any late arrival if:
    //   - the widget was disposed while we were awaiting (user hit back,
    //     or another concurrent _onDetect already popped after reaching
    //     complete), or
    //   - another detection has already marked the scan complete (fountain
    //     codes plus concurrent frames mean two awaits can complete
    //     out-of-order, and we don't want a late-resolving earlier
    //     fragment to overwrite `_progress` or re-pop).
    // Without this guard the old code would `setState()` on a disposed
    // widget (Flutter warns / asserts) or briefly regress the progress bar.
    if (!mounted || _complete) return;

    // Only mark as seen after the decoder actually accepted this fragment.
    // Animated URs cycle through fragments repeatedly; if we marked on
    // entry, any transient failure (wrong-type frame, corrupted capture,
    // stale session right after init) would permanently dedupe the
    // fragment and stall the scan below 100%.
    _seenParts.add(normalized);
    setState(() {
      _progress = result.progress;
    });
    widget.onProgress?.call(result.progress);

    if (result.complete && result.data != null) {
      _complete = true;
      Navigator.pop(
        context,
        ScanResult(urType: result.urType ?? '', data: result.data!),
      );
    }
  }

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
          MobileScanner(controller: _controller, onDetect: _onDetect),
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
