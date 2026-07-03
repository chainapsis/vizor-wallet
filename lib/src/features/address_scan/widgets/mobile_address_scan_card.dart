import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart'
    show kMobileTopNavHeight;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../services/camera_permission_settings.dart';
import '../../../services/qr_scanner.dart';
import 'address_qr_scan_modal.dart' show AddressQrCameraStatus;
import 'mobile_address_scan_view.dart'
    show MobileScanResolver, MobileScanViewfinderCorners;

typedef MobileQrCameraViewBuilder =
    Widget Function(BuildContext context, MobileScannerController controller);

typedef MobileQrPermissionBuilder =
    Widget Function(
      BuildContext context,
      AddressQrCameraStatus status,
      String? unavailableDescription,
      VoidCallback onRetry,
      VoidCallback onClose,
    );

/// Generic live mobile QR scanner card. It owns the shared mobile camera
/// lifecycle, permission/retry handling, and Figma scan-card visuals while the
/// caller supplies the concrete scanner view (plain QR, animated UR, etc.).
class MobileQrScanCard extends StatefulWidget {
  const MobileQrScanCard({
    required this.cameraViewBuilder,
    required this.onClose,
    this.controller,
    this.closeEnabled = true,
    this.forceActiveForTesting = false,
    this.caption,
    this.permissionTitle,
    this.error,
    this.unavailableDescription,
    this.permissionBuilder,
    this.cameraHeight,
    super.key,
  });

  /// Optional externally-owned controller (tests inject one with
  /// `autoStart: false` to drive camera/permission states). When null the card
  /// creates and owns its own back-camera controller.
  final MobileScannerController? controller;

  /// Builds the scanner view mounted behind the shared scan chrome.
  final MobileQrCameraViewBuilder cameraViewBuilder;

  /// Called when the user taps close / Cancel.
  final VoidCallback onClose;

  /// Whether the camera close control is interactive. Permission states keep
  /// their existing Cancel action; this is for in-flight scan finalization
  /// where leaving the route would drop a result.
  final bool closeEnabled;

  final bool forceActiveForTesting;

  /// Idle caption beneath the viewfinder.
  final String? caption;

  /// Title shown in the permission/requesting card state.
  final String? permissionTitle;

  /// Message shown beneath the viewfinder in active camera states.
  final String? error;

  /// Fallback description for no-camera / camera-open failures.
  /// Defaults to the localized generic scan copy when null.
  final String? unavailableDescription;

  /// Optional override for permission/requesting/denied states. The active and
  /// loading scan chrome stays shared.
  final MobileQrPermissionBuilder? permissionBuilder;

  /// Optional height override for in-page scanner placements. The default
  /// keeps the send/swap bottom-sheet geometry.
  final double? cameraHeight;

  @override
  State<MobileQrScanCard> createState() => _MobileQrScanCardState();
}

class _MobileQrScanCardState extends State<MobileQrScanCard>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  late final bool _ownsController;
  bool _restartCameraOnResume = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        MobileScannerController(
          formats: QrScanner.formats,
          detectionSpeed: QrScanner.detectionSpeed,
        );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_restartCameraOnResume) return;
    _restartCameraOnResume = false;
    unawaited(_retryCameraStart(openSettingsOnDenied: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) unawaited(_controller.dispose());
    super.dispose();
  }

  AddressQrCameraStatus _cameraAccessStatus(MobileScannerState state) {
    if (!QrScanner.isAvailable) return AddressQrCameraStatus.unavailable;
    if (state.error?.errorCode == MobileScannerErrorCode.permissionDenied) {
      return AddressQrCameraStatus.denied;
    }
    if (state.error != null && !state.isRunning) {
      return AddressQrCameraStatus.unavailable;
    }
    if (state.hasCameraPermission && state.isRunning) {
      return AddressQrCameraStatus.active;
    }
    if (state.hasCameraPermission || state.isStarting || state.isInitialized) {
      return AddressQrCameraStatus.loading;
    }
    return AddressQrCameraStatus.requesting;
  }

  Future<void> _retryCameraStart({required bool openSettingsOnDenied}) async {
    if (!QrScanner.isAvailable ||
        _controller.value.isStarting ||
        _controller.value.isRunning) {
      return;
    }
    try {
      await _controller.start();
    } catch (e, st) {
      log('MobileQrScanCard: camera start retry error: $e\n$st');
    }
    if (!mounted || !openSettingsOnDenied) return;
    if (_cameraAccessStatus(_controller.value) !=
        AddressQrCameraStatus.denied) {
      return;
    }
    await _openCameraSettings();
  }

  Future<void> _openCameraSettings() async {
    _restartCameraOnResume = true;
    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      _restartCameraOnResume = false;
      log('MobileQrScanCard: failed to open camera permission settings');
    }
  }

  String _cameraUnavailableDescription(MobileScannerState state) {
    final message = state.error?.errorDetails?.message;
    if (message != null && message.isNotEmpty) return message;
    return widget.unavailableDescription ??
        AppLocalizations.of(context).scanNeedsCamera;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final status = widget.forceActiveForTesting
            ? AddressQrCameraStatus.active
            : _cameraAccessStatus(state);
        return MobileAddressScanCardContent(
          status: status,
          // The camera preview is mounted in every state (offstage until
          // access is granted) so the controller keeps running and reporting
          // permission changes.
          cameraView: QrScanner.isAvailable
              ? widget.cameraViewBuilder(context, _controller)
              : null,
          caption: widget.caption ?? AppLocalizations.of(context).scanZcashQrCaption,
          permissionTitle: widget.permissionTitle ?? AppLocalizations.of(context).scanAddressQrTitle,
          error: widget.error,
          unavailableDescription: status == AddressQrCameraStatus.unavailable
              ? _cameraUnavailableDescription(state)
              : null,
          permissionBuilder: widget.permissionBuilder,
          cameraHeight: widget.cameraHeight,
          closeEnabled: widget.closeEnabled,
          onTorch: () => unawaited(_controller.toggleTorch()),
          onClose: widget.onClose,
          onRetry: () =>
              unawaited(_retryCameraStart(openSettingsOnDenied: true)),
        );
      },
    );
  }
}

/// Card-contained mobile QR scanner — Figma `Address QR` (4697:106096 active /
/// 4697:111341 loading / 4697:106414 requesting / 4697:111063 denied) and send
/// `QR Scan` (4484:61584). This is the bottom-sheet/card camera surface used
/// by send and swap: it lives inside the shared [MobileModalCard] surface and
/// morphs between two layouts —
///
/// - **camera** (active / loading): a tall card whose camera fills the rounded
///   surface, with a dashed 256px viewfinder, a caption, a torch toggle
///   top-left and a close top-right (plus a blurred "Loading…" veil while the
///   camera spins up);
/// - **permission** (requesting / denied / unavailable): a short card with the
///   `_Modal Type` title, a camera-icon message and a Cancel button — and, when
///   denied/unavailable, a "Request again" action.
///
/// The camera preview is mounted in every state (kept offstage until access is
/// granted) so the single [MobileScannerController] keeps running and the
/// requesting → active transition is seamless.
class MobileAddressScanCard extends StatefulWidget {
  const MobileAddressScanCard({
    required this.resolve,
    required this.onScanned,
    required this.onClose,
    this.controller,
    this.caption,
    this.permissionTitle,
    this.steadyHint,
    super.key,
  });

  /// Optional externally-owned controller (tests inject one with
  /// `autoStart: false` to drive camera/permission states). When null the card
  /// creates and owns its own back-camera controller.
  final MobileScannerController? controller;

  /// Validates a scanned payload; see [MobileScanResolver].
  final MobileScanResolver resolve;

  /// Called with the accepted address once [resolve] succeeds.
  final ValueChanged<String> onScanned;

  /// Called when the user taps close / Cancel.
  final VoidCallback onClose;

  /// Idle caption beneath the viewfinder.
  final String? caption;

  /// Title shown in the permission/requesting card state.
  final String? permissionTitle;

  /// Fallback message when resolution throws.
  final String? steadyHint;

  @override
  State<MobileAddressScanCard> createState() => _MobileAddressScanCardState();
}

class _MobileAddressScanCardState extends State<MobileAddressScanCard> {
  bool _validating = false;
  int _scanResetToken = 0;
  String? _error;

  Future<void> _handleScan(String raw) async {
    if (_validating || !mounted) return;
    if (raw.trim().isEmpty) return;
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
        // Let PlainQrScannerView fire again for the next frame.
        _scanResetToken++;
        _error =
            outcome.error ??
            widget.steadyHint ??
            AppLocalizations.of(context).keystoneScanHoldSteady;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _scanResetToken++;
        _error =
            widget.steadyHint ??
            AppLocalizations.of(context).keystoneScanHoldSteady;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileQrScanCard(
      controller: widget.controller,
      caption: widget.caption,
      permissionTitle: widget.permissionTitle,
      error: _error,
      unavailableDescription: AppLocalizations.of(context).scanAddressNeedsCamera,
      onClose: widget.onClose,
      cameraViewBuilder: (context, controller) => PlainQrScannerView(
        key: const ValueKey('mobile_address_scan_card_camera'),
        controller: controller,
        scanSessionResetToken: _scanResetToken,
        onComplete: (value) => unawaited(_handleScan(value)),
      ),
    );
  }
}

/// The stateless visual layout of the scan card (camera ⇆ permission morph),
/// split out so widgetbook can preview every [AddressQrCameraStatus] with a
/// stub [cameraView]. The live [MobileAddressScanCard] wires the real camera
/// preview and controller into it; the camera fills the rounded card in the
/// active/loading states and is covered by the opaque permission card
/// otherwise.
class MobileAddressScanCardContent extends StatelessWidget {
  const MobileAddressScanCardContent({
    required this.status,
    required this.onTorch,
    required this.onClose,
    required this.onRetry,
    this.cameraView,
    this.caption,
    this.permissionTitle,
    this.error,
    this.unavailableDescription,
    this.permissionBuilder,
    this.cameraHeight,
    this.closeEnabled = true,
    super.key,
  });

  final AddressQrCameraStatus status;

  /// The live camera preview (or a stub in widgetbook). Null when no camera is
  /// available — the card then only ever shows the permission states.
  final Widget? cameraView;
  final String? caption;
  final String? permissionTitle;
  final String? error;
  final String? unavailableDescription;
  final MobileQrPermissionBuilder? permissionBuilder;
  final double? cameraHeight;
  final bool closeEnabled;
  final VoidCallback onTorch;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  /// The camera card nearly fills the screen, leaving the dimmed app behind
  /// visible under the top nav. `viewPadding` (not `padding`) so the status-bar
  /// inset survives the dialog's `SafeArea(top)`.
  static double modalCameraHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    // Figma `QR Scan` (4484:61584) on the 393x852 mobile artboard places the
    // modal at y=126 and h=694, with a 32px bottom gap. The scanner overlays
    // the lower edge of the top nav by 1px, hence the correction below.
    final targetTop = media.viewPadding.top + kMobileTopNavHeight - 1;
    final reserved = targetTop + AppSpacing.base;
    return (media.size.height - reserved).clamp(420.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final showsCamera =
        status == AddressQrCameraStatus.active ||
        status == AddressQrCameraStatus.loading;
    final hasFixedHeight = showsCamera || permissionBuilder != null;
    return SizedBox(
      height: hasFixedHeight
          ? (cameraHeight ?? modalCameraHeight(context))
          : null,
      child: Stack(
        fit: hasFixedHeight ? StackFit.expand : StackFit.loose,
        children: [
          if (cameraView != null)
            Positioned.fill(
              child: Offstage(offstage: !showsCamera, child: cameraView!),
            ),
          if (status == AddressQrCameraStatus.active) ...[
            const Positioned.fill(child: _ScanViewfinder()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 110,
              child: _ScanCaption(
                text:
                    error ??
                    caption ??
                    AppLocalizations.of(context).scanZcashQrCaption,
              ),
            ),
            Positioned(
              top: AppSpacing.base,
              left: AppSpacing.base,
              child: _CameraGlyphButton(
                semanticLabel: AppLocalizations.of(context).keystoneToggleFlashlight,
                icon: const Icon(
                  Icons.flashlight_on_outlined,
                  color: Color(0xFFFFFFFF),
                  size: 30,
                ),
                onTap: onTorch,
              ),
            ),
          ],
          if (status == AddressQrCameraStatus.loading)
            const Positioned.fill(child: _ScanLoadingVeil()),
          // Close (top-right) sits over the camera in both camera states; the
          // permission card carries its own pinned close.
          if (showsCamera)
            Positioned(
              top: AppSpacing.base,
              right: AppSpacing.base,
              child: _CameraGlyphButton(
                semanticLabel: AppLocalizations.of(context).scanCloseScanner,
                enabled: closeEnabled,
                icon: AppIcon(
                  AppIcons.cross,
                  size: 30,
                  color: closeEnabled
                      ? const Color(0xFFFFFFFF)
                      : const Color(0x61FFFFFF),
                ),
                onTap: onClose,
              ),
            ),
          if (!showsCamera)
            permissionBuilder?.call(
                  context,
                  status,
                  unavailableDescription,
                  onRetry,
                  onClose,
                ) ??
                _ScanPermissionCard(
                  status: status,
                  title:
                      permissionTitle ??
                      AppLocalizations.of(context).scanAddressQrTitle,
                  unavailableDescription: unavailableDescription,
                  onRetry: onRetry,
                  onClose: onClose,
                ),
        ],
      ),
    );
  }
}

/// A 40×40 transparent tap target for the torch / close glyphs floating over
/// the camera (Figma `Modal Close`, size-40).
class _CameraGlyphButton extends StatelessWidget {
  const _CameraGlyphButton({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String semanticLabel;
  final Widget icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(width: 40, height: 40, child: Center(child: icon)),
      ),
    );
  }
}

/// White caption under the viewfinder (Figma 4697:106404).
class _ScanCaption extends StatelessWidget {
  const _ScanCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 152,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

/// Dark scrim with a clear, centered 256px viewfinder window framed by the
/// shared corner brackets — Figma `Camera Pointer` (4755:85734) is corner
/// brackets, NOT a full border; the CSS export's `border-dashed` mis-renders
/// the bracket overlay. Reuses [MobileScanViewfinderCorners] so the swap card
/// and the full-bleed send scanner share the exact same viewfinder.
class _ScanViewfinder extends StatelessWidget {
  const _ScanViewfinder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _ScanScrimPainter()),
          const Center(
            child: SizedBox(
              width: _ScanScrimPainter.windowSize,
              height: _ScanScrimPainter.windowSize,
              // Longer arms + a radius matching the 32px window (Figma
              // `Camera Pointer` brackets reach ~1/4 along each edge).
              child: MobileScanViewfinderCorners(
                cornerLength: 56,
                cornerRadius: 32,
                strokeWidth: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims the camera everywhere outside the centered 256px viewfinder window
/// (Figma `Camera Pointer` 0.7 black scrim).
class _ScanScrimPainter extends CustomPainter {
  static const windowSize = 256.0;
  static const _radius = 32.0;

  @override
  void paint(Canvas canvas, Size size) {
    final window = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: windowSize,
      height: windowSize,
    );
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(
        RRect.fromRectAndRadius(window, const Radius.circular(_radius)),
      ),
    );
    canvas.drawPath(scrim, Paint()..color = const Color(0xB3000000));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Blurred veil shown while the camera spins up (Figma `Camera Loading`).
class _ScanLoadingVeil extends StatelessWidget {
  const _ScanLoadingVeil();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 37, sigmaY: 37),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0x4D000000)),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(
                  AppIcons.loader,
                  size: 20,
                  color: Color(0xFFFFFFFF),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  AppLocalizations.of(context).scanLoadingEllipsis,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The opaque permission card shown over the (still-running) camera while
/// access is requesting / denied / unavailable (Figma 4697:106414 / 111063):
/// the `_Modal Type` title + close, a camera-icon message, an optional
/// "Request again" action, and a Cancel button.
class _ScanPermissionCard extends StatelessWidget {
  const _ScanPermissionCard({
    required this.status,
    required this.title,
    required this.unavailableDescription,
    required this.onRetry,
    required this.onClose,
  });

  final AddressQrCameraStatus status;
  final String title;
  final String? unavailableDescription;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      // Opaque so the live camera behind it stays hidden until access lands.
      color: colors.background.base,
      child: MobileModalScaffold(
        key: const ValueKey('mobile_address_scan_permission_card'),
        title: title,
        onClose: onClose,
        bottomPadding: AppSpacing.sm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Figma `Camera Modal` height (4697:106416) — centers the message
            // so the card lands at the ~440 permission height.
            SizedBox(height: 276, child: Center(child: _message(context, colors))),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const ValueKey('mobile_address_scan_cancel_button'),
              variant: AppButtonVariant.ghost,
              expand: true,
              onPressed: onClose,
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(BuildContext context, AppColors colors) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case AddressQrCameraStatus.denied:
        return _ScanCameraMessage(
          iconName: AppIcons.camera,
          title: l10n.scanCameraDeniedTitle,
          description: l10n.cameraDeniedDesc,
          action: AppButton(
            key: const ValueKey('mobile_address_scan_retry_button'),
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.medium,
            minWidth: 96,
            leading: const AppIcon(AppIcons.renew),
            onPressed: onRetry,
            child: Text(l10n.cameraRequestAgain),
          ),
        );
      case AddressQrCameraStatus.unavailable:
        return _ScanCameraMessage(
          iconName: AppIcons.cameraDenied,
          title: l10n.cameraUnavailableTitle,
          description: unavailableDescription ?? l10n.scanAddressNeedsCamera,
          // A runtime open failure (camera busy / in use by another app) is
          // recoverable, so surface the same retry the desktop modal offers
          // instead of forcing a full close + reopen.
          action: AppButton(
            key: const ValueKey('mobile_address_scan_retry_button'),
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.medium,
            minWidth: 96,
            leading: const AppIcon(AppIcons.renew),
            onPressed: onRetry,
            child: Text(l10n.settingsUpdateActionTryAgain),
          ),
        );
      case AddressQrCameraStatus.requesting:
      case AddressQrCameraStatus.active:
      case AddressQrCameraStatus.loading:
        return _ScanCameraMessage(
          iconName: AppIcons.camera,
          title: l10n.scanGrantCameraAccess,
          description: l10n.cameraDeniedDesc,
        );
    }
  }
}

/// The camera-icon message block (Figma `Utility Message Container`): a 40px
/// inverse icon tile, a strong title, a two-line secondary description and an
/// optional action.
class _ScanCameraMessage extends StatelessWidget {
  const _ScanCameraMessage({
    required this.iconName,
    required this.title,
    required this.description,
    this.action,
  });

  final String iconName;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.background.inverse,
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Center(
              child: AppIcon(iconName, size: 24, color: colors.icon.inverse),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final line in description.split('\n'))
            Text(
              line,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
