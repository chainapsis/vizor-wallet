import 'dart:async';

import 'package:flutter/material.dart' show Colors, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../../main.dart' show log;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../rust/api/sync.dart' as rust_sync;

/// Address scanner for the mobile send flow — Figma `Mobile Scanner`
/// (4484:58700): full-bleed camera under a dark scrim, torch toggle
/// top-left, close top-right, corner-bracket viewfinder with the
/// caption beneath. Pops the scanned address string on success.
class MobileSendScanScreen extends StatefulWidget {
  const MobileSendScanScreen({super.key});

  @override
  State<MobileSendScanScreen> createState() => _MobileSendScanScreenState();
}

class _MobileSendScanScreenState extends State<MobileSendScanScreen> {
  final _controller = MobileScannerController();
  bool _validating = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// Accepts a bare address or a ZIP-321 style `zcash:` URI; only the
  /// address part is taken — amount prefill can come later.
  String _extractAddress(String raw) {
    var value = raw.trim();
    if (value.toLowerCase().startsWith('zcash:')) {
      value = value.substring('zcash:'.length);
      final queryStart = value.indexOf('?');
      if (queryStart >= 0) value = value.substring(0, queryStart);
    }
    return value.trim();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_validating || !mounted) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() {
      _validating = true;
      _error = null;
    });
    try {
      final address = _extractAddress(raw);
      final result = await rust_sync.validateAddress(address: address);
      if (!mounted) return;
      if (result.isValid) {
        context.pop(address);
        return;
      }
      setState(() {
        _validating = false;
        _error = "This QR code isn't a Zcash address.";
      });
    } catch (e) {
      log('MobileSendScan: validation error: $e');
      if (!mounted) return;
      setState(() {
        _validating = false;
        _error = 'Keep the QR code steady and fully visible.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const viewfinderSize = 260.0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) => unawaited(_handleDetect(capture)),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Allow it in iOS Settings to '
                            'scan addresses.'
                      : 'The camera is unavailable right now.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // Dark scrim with a clear viewfinder window.
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0x99000000),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    width: viewfinderSize,
                    height: viewfinderSize,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(AppRadii.large),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: SizedBox(
              width: viewfinderSize,
              height: viewfinderSize,
              child: const _ViewfinderCorners(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.s,
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Toggle flashlight',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => unawaited(_controller.toggleTorch()),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.flashlight_on_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Semantics(
                        button: true,
                        label: 'Close scanner',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.pop(),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: AppIcon(
                                AppIcons.cross,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.only(
                    // Caption sits right under the centered viewfinder.
                    bottom:
                        (MediaQuery.sizeOf(context).height - viewfinderSize) /
                            2 -
                        64,
                  ),
                  child: Text(
                    _error ?? 'Scan a Zcash QR code to continue',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderCorners extends StatelessWidget {
  const _ViewfinderCorners();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ViewfinderCornersPainter());
  }
}

class _ViewfinderCornersPainter extends CustomPainter {
  static const _cornerLength = 28.0;
  static const _cornerRadius = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    Path corner(double rotationQuarter) {
      final path = Path()
        ..moveTo(0, _cornerLength)
        ..lineTo(0, _cornerRadius)
        ..arcToPoint(
          const Offset(_cornerRadius, 0),
          radius: const Radius.circular(_cornerRadius),
        )
        ..lineTo(_cornerLength, 0);
      final matrix = Matrix4.identity()
        ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
        ..rotateZ(rotationQuarter * 3.1415926535 / 2)
        ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
      return path.transform(matrix.storage);
    }

    for (var quarter = 0; quarter < 4; quarter++) {
      canvas.drawPath(corner(quarter.toDouble()), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
