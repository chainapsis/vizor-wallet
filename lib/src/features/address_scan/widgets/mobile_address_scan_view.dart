import 'dart:async';

import 'package:flutter/material.dart' show Colors, Icons, Material;
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../services/qr_scanner.dart' show QrScanner;

/// Result of resolving a scanned QR payload — either an accepted address
/// string or a rejection message to surface under the viewfinder.
class MobileScanOutcome {
  const MobileScanOutcome.accepted(this.address) : error = null;
  const MobileScanOutcome.rejected(this.error) : address = null;

  final String? address;
  final String? error;

  bool get isAccepted => address != null;
}

/// Resolves a raw scanned payload into a [MobileScanOutcome]. Callers
/// own the validation semantics — the send flow checks the string is a
/// Zcash address, the swap flow accepts any destination address.
typedef MobileScanResolver = Future<MobileScanOutcome> Function(String raw);

/// Full-bleed mobile QR scanner — Figma `Mobile Scanner` (4484:58700 /
/// 4484:61584 / 4697:106096): a full-screen back-camera feed under a dark
/// scrim, torch toggle top-left, close top-right, a corner-bracket
/// viewfinder and a caption beneath it. Mobile always uses the back
/// camera, so there is no camera picker.
///
/// Shared by the send recipient scan, the swap address scan, and (via
/// [MobileScanViewfinderCorners]) the Keystone signing scan, so the
/// camera chrome stays identical across every mobile scan surface.
class MobileAddressScanView extends StatefulWidget {
  const MobileAddressScanView({
    required this.resolve,
    required this.onScanned,
    required this.onClose,
    this.caption = 'Scan a Zcash QR code to continue',
    this.steadyHint = 'Keep the QR code steady and fully visible.',
    super.key,
  });

  /// Validates a scanned payload; see [MobileScanResolver].
  final MobileScanResolver resolve;

  /// Called with the accepted address once [resolve] succeeds.
  final ValueChanged<String> onScanned;

  /// Called when the user taps the close control.
  final VoidCallback onClose;

  /// Idle caption beneath the viewfinder.
  final String caption;

  /// Fallback message when resolution throws.
  final String steadyHint;

  @override
  State<MobileAddressScanView> createState() => _MobileAddressScanViewState();
}

class _MobileAddressScanViewState extends State<MobileAddressScanView> {
  // No `facing` argument: mobile_scanner defaults to the back camera,
  // which is the only camera the mobile scan flows ever use.
  final _controller = MobileScannerController(
    formats: QrScanner.formats,
    detectionSpeed: QrScanner.detectionSpeed,
  );
  bool _validating = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
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
      final outcome = await widget.resolve(raw);
      if (!mounted) return;
      if (outcome.isAccepted) {
        widget.onScanned(outcome.address!);
        return;
      }
      setState(() {
        _validating = false;
        _error = outcome.error ?? widget.steadyHint;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _error = widget.steadyHint;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const viewfinderSize = 260.0;
    // Material (not a bare ColoredBox) so the scan chrome always has a
    // Material ancestor for its text/ink even when hosted in a raw dialog
    // (the swap scanner surface) rather than a Scaffold (the send route).
    return Material(
      color: Colors.black,
      child: Stack(
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
                      ? 'Camera access is off. Allow it in Settings to scan '
                            'addresses.'
                      : 'The camera is unavailable right now.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white),
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
          const Center(
            child: SizedBox(
              width: viewfinderSize,
              height: viewfinderSize,
              child: MobileScanViewfinderCorners(),
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
                          onTap: widget.onClose,
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
                    _error ?? widget.caption,
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

/// Corner-bracket viewfinder overlay shared by every mobile scan flow.
class MobileScanViewfinderCorners extends StatelessWidget {
  const MobileScanViewfinderCorners({super.key});

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
