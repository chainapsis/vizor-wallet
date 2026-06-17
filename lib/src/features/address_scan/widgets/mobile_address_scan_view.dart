import 'dart:async';

import 'package:flutter/material.dart' show Colors, Icons, Material;
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../services/camera_permission_settings.dart';
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
/// The send and swap flows use the card-contained scanner in
/// `mobile_address_scan_card.dart`; this file keeps the reusable full-screen
/// primitives and shared viewfinder/error overlays used by mobile scan
/// surfaces such as Keystone signing.
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

class _MobileAddressScanViewState extends State<MobileAddressScanView>
    with WidgetsBindingObserver {
  // No `facing` argument: mobile_scanner defaults to the back camera,
  // which is the only camera the mobile scan flows ever use.
  final _controller = MobileScannerController(
    formats: QrScanner.formats,
    detectionSpeed: QrScanner.detectionSpeed,
  );
  bool _validating = false;
  bool _restartCameraOnResume = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_restartCameraOnResume) return;
    _restartCameraOnResume = false;
    unawaited(_restartCameraAfterSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _openCameraSettings() async {
    _restartCameraOnResume = true;
    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      _restartCameraOnResume = false;
      log('MobileAddressScanView: failed to open camera permission settings');
    }
  }

  Future<void> _restartCameraAfterSettings() async {
    if (!QrScanner.isAvailable ||
        _controller.value.isStarting ||
        _controller.value.isRunning) {
      return;
    }

    try {
      await _controller.start();
    } catch (e, st) {
      log('MobileAddressScanView: camera settings return retry error: $e\n$st');
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
            // Camera errors are rendered above the scrim below. If the scanner
            // paints them here, text outside the clear viewfinder is tinted by
            // the BlendMode overlay.
            errorBuilder: (context, error) => const SizedBox.shrink(),
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
          MobileScanCameraErrorOverlay(
            controller: _controller,
            maxWidth: viewfinderSize,
            permissionDeniedMessage:
                'Camera access is off. Allow it in Settings to scan addresses.',
            unavailableMessage: 'The camera is unavailable right now.',
            onOpenSettings: _openCameraSettings,
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

/// Camera error text for full-bleed mobile scan surfaces.
///
/// Render this above the dark scrim, not inside [MobileScanner.errorBuilder].
/// Otherwise text that extends outside the transparent viewfinder hole is
/// composited through the scrim and appears to change color at the edges.
class MobileScanCameraErrorOverlay extends StatelessWidget {
  const MobileScanCameraErrorOverlay({
    required this.controller,
    required this.permissionDeniedMessage,
    required this.unavailableMessage,
    this.maxWidth = 260,
    this.onOpenSettings,
    this.openSettingsLabel = 'Open settings',
    super.key,
  });

  final MobileScannerController controller;
  final String permissionDeniedMessage;
  final String unavailableMessage;
  final double maxWidth;
  final Future<void> Function()? onOpenSettings;
  final String openSettingsLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final message = _messageFor(state);
        if (message == null) return const SizedBox.shrink();
        final showSettingsButton =
            state.error?.errorCode == MobileScannerErrorCode.permissionDenied &&
            onOpenSettings != null;

        final content = Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  if (showSettingsButton) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      key: const ValueKey('mobile_scan_open_settings_button'),
                      onPressed: () => unawaited(onOpenSettings!()),
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      minWidth: 128,
                      leading: const AppIcon(AppIcons.cog),
                      child: Text(openSettingsLabel),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

        if (showSettingsButton) return content;
        return IgnorePointer(child: content);
      },
    );
  }

  String? _messageFor(MobileScannerState state) {
    final error = state.error;
    if (error == null) return null;
    return error.errorCode == MobileScannerErrorCode.permissionDenied
        ? permissionDeniedMessage
        : unavailableMessage;
  }
}

/// Corner-bracket viewfinder overlay shared by every mobile scan flow. The
/// bracket geometry is tunable — the full-bleed send scanner keeps the compact
/// default, the swap card passes longer arms / a larger radius to match its
/// Figma `Camera Pointer`.
class MobileScanViewfinderCorners extends StatelessWidget {
  const MobileScanViewfinderCorners({
    this.cornerLength = 28,
    this.cornerRadius = 24,
    this.strokeWidth = 3,
    super.key,
  });

  /// Extent of each bracket along the window edge (from the corner).
  final double cornerLength;

  /// Radius of the rounded bend — match the viewfinder window's corner radius.
  final double cornerRadius;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ViewfinderCornersPainter(
        cornerLength: cornerLength,
        cornerRadius: cornerRadius,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _ViewfinderCornersPainter extends CustomPainter {
  _ViewfinderCornersPainter({
    required this.cornerLength,
    required this.cornerRadius,
    required this.strokeWidth,
  });

  final double cornerLength;
  final double cornerRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    Path corner(double rotationQuarter) {
      final path = Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, cornerRadius)
        ..arcToPoint(
          Offset(cornerRadius, 0),
          radius: Radius.circular(cornerRadius),
        )
        ..lineTo(cornerLength, 0);
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
  bool shouldRepaint(covariant _ViewfinderCornersPainter oldDelegate) =>
      oldDelegate.cornerLength != cornerLength ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.strokeWidth != strokeWidth;
}
