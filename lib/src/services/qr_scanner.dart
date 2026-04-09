import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../main.dart' show log;
import '../rust/api/keystone.dart' as rust_keystone;

/// QR scanner abstraction. Uses mobile_scanner on macOS/iOS/Android.
/// Windows/Linux implementations can be added later.
class QrScanner {
  QrScanner._();

  /// Whether QR scanning is available on this platform.
  static bool get isAvailable =>
      Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  /// Scan a single QR code. Returns the decoded string, or null if cancelled.
  static Future<String?> scan(BuildContext context) async {
    if (!isAvailable) {
      throw UnsupportedError('QR scanning not available on this platform');
    }
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _SingleScanScreen()),
    );
  }

  /// Scan animated QR codes (multi-part UR from Keystone).
  /// Accumulates UR parts until complete. Returns the full decoded data bytes,
  /// or null if cancelled. [onProgress] reports 0-100.
  static Future<ScanResult?> scanAnimatedUr(
    BuildContext context, {
    void Function(int progress)? onProgress,
  }) async {
    if (!isAvailable) {
      throw UnsupportedError('QR scanning not available on this platform');
    }
    return Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _AnimatedUrScanScreen(onProgress: onProgress),
      ),
    );
  }
}

/// Result from animated UR scan.
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
  final _controller = MobileScannerController();
  bool _scanned = false;

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
  final void Function(int progress)? onProgress;

  const _AnimatedUrScanScreen({this.onProgress});

  @override
  State<_AnimatedUrScanScreen> createState() => _AnimatedUrScanScreenState();
}

class _AnimatedUrScanScreenState extends State<_AnimatedUrScanScreen> {
  final _controller = MobileScannerController();
  int _progress = 0;
  bool _complete = false;
  final Set<String> _seenParts = {};

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

    // Skip duplicate parts (case-insensitive since UR encoding varies)
    final normalized = value.toLowerCase();
    if (_seenParts.contains(normalized)) return;
    _seenParts.add(normalized);

    try {
      log('QrScanner: scanned part (${value.length} chars): ${value.substring(0, value.length.clamp(0, 80))}...');
      final result = await rust_keystone.decodeUrPart(part_: value);
      setState(() { _progress = result.progress; });
      widget.onProgress?.call(result.progress);

      if (result.complete && result.data != null) {
        _complete = true;
        if (!mounted) return;
        Navigator.pop(context, ScanResult(
          urType: result.urType ?? '',
          data: result.data!,
        ));
      }
    } catch (e) {
      log('QrScanner: UR part decode error: $e');
      // Continue scanning — might be a non-UR QR or corrupted frame
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
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Progress indicator at bottom
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _progress > 0 ? 'Scanning... $_progress%' : 'Point camera at Keystone QR',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
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
