import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../services/camera_permission_settings.dart';
import '../../../services/qr_scanner.dart';
import 'keystone_transaction_progress_panel.dart';

enum _CameraAccessStatus { active, requesting, denied, unavailable }

// The mobile Keystone Scan frames diverge from the desktop pane in the
// permission states: Body L titles, the slashed camera glyph on a dark
// square for both requesting and denied, a "Request again" retry label,
// and no footer until the camera feed is live.
const _mobileFormFactor = kAppFormFactor == AppFormFactor.mobile;

class KeystoneQrScannerCard extends StatefulWidget {
  const KeystoneQrScannerCard({
    required this.expectedUrType,
    required this.decoding,
    required this.error,
    required this.onProgress,
    required this.onDecodeError,
    required this.onComplete,
    required this.unavailableMessage,
    this.decodingLabel = 'Reading QR...',
    this.cardWidth,
    this.cameraHeight,
    super.key,
  });

  final String expectedUrType;
  final bool decoding;
  final String? error;
  final ValueChanged<int> onProgress;
  final ValueChanged<Object> onDecodeError;
  final ValueChanged<ScanResult> onComplete;
  final String unavailableMessage;
  final String decodingLabel;

  /// Layout overrides for the mobile single-pane flow; the defaults keep
  /// the desktop pane dimensions.
  final double? cardWidth;
  final double? cameraHeight;

  @override
  State<KeystoneQrScannerCard> createState() => _KeystoneQrScannerCardState();
}

class _KeystoneQrScannerCardState extends State<KeystoneQrScannerCard>
    with WidgetsBindingObserver {
  static const _cardWidth = 464.0;
  static const _cameraHeight = 310.0;
  static const _outerRadius = 28.0;
  static const _cameraRadius = 24.0;

  late MobileScannerController _controller;
  StreamSubscription<List<MobileScannerCameraInfo>>? _camerasSubscription;
  List<MobileScannerCameraInfo> _cameras = const [];
  String? _selectedCameraId;
  bool _loadingCameras = false;
  bool _cameraPickerOpen = false;
  bool _troubleScanningPopoverOpen = false;
  int _scanProgress = 0;
  int _scanSessionResetToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = _createController();
    _camerasSubscription = _controller.camerasStream.listen(_applyCameras);
    _loadCameras();
  }

  MobileScannerController _createController({String? cameraId}) {
    return MobileScannerController(
      cameraId: cameraId,
      facing: defaultQrScannerFacing,
      formats: QrScanner.formats,
      detectionSpeed: QrScanner.detectionSpeed,
    );
  }

  Future<void> _loadCameras() async {
    if (!QrScanner.isAvailable) return;

    setState(() {
      _loadingCameras = true;
    });

    try {
      final cameras = await _controller.getAvailableCameras();
      if (!mounted) return;
      _applyCameras(cameras);
    } catch (e, st) {
      log('KeystoneQrScannerCard: camera list error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadingCameras = false;
      });
    }
  }

  void _applyCameras(List<MobileScannerCameraInfo> cameras) {
    if (!mounted) return;

    final selectedCameraStillAvailable =
        _selectedCameraId == null ||
        cameras.any((camera) => camera.id == _selectedCameraId);

    setState(() {
      _cameras = cameras;
      _loadingCameras = false;
      if (!selectedCameraStillAvailable) {
        _selectedCameraId = null;
        _cameraPickerOpen = false;
      } else if (cameras.length < 2) {
        _cameraPickerOpen = false;
      }
    });
  }

  MobileScannerCameraInfo? _cameraById(String? id) {
    if (id == null) return null;
    for (final camera in _cameras) {
      if (camera.id == id) return camera;
    }
    return null;
  }

  MobileScannerCameraInfo? get _defaultCamera {
    for (final camera in _cameras) {
      if (camera.isDefault) return camera;
    }
    return _cameras.isEmpty ? null : _cameras.first;
  }

  void _toggleCameraPicker() {
    if (_cameras.length < 2 || widget.decoding) return;
    setState(() {
      _troubleScanningPopoverOpen = false;
      _cameraPickerOpen = !_cameraPickerOpen;
    });
  }

  void _toggleTroubleScanning() {
    setState(() {
      _cameraPickerOpen = false;
      _troubleScanningPopoverOpen = !_troubleScanningPopoverOpen;
    });
  }

  void _dismissTroubleScanning() {
    setState(() {
      _troubleScanningPopoverOpen = false;
    });
  }

  Future<void> _selectCamera(MobileScannerCameraInfo camera) async {
    if (_selectedCameraId == camera.id) {
      setState(() {
        _cameraPickerOpen = false;
      });
      return;
    }

    setState(() {
      _selectedCameraId = camera.id;
      _cameraPickerOpen = false;
      _scanProgress = 0;
      _scanSessionResetToken++;
    });

    try {
      await _controller.switchCamera(SelectCamera(cameraId: camera.id));
    } catch (e, st) {
      log('KeystoneQrScannerCard: camera switch error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _selectedCameraId = _controller.value.camera?.id;
        _scanProgress = 0;
      });
    }
  }

  void _handleScanProgress(int progress) {
    final clamped = progress.clamp(0, 100);
    widget.onProgress(clamped);
    if (!mounted || _scanProgress == clamped) return;
    setState(() {
      _scanProgress = clamped;
    });
  }

  void _handleScanComplete(ScanResult result) {
    if (mounted && _scanProgress != 100) {
      setState(() {
        _scanProgress = 100;
      });
    }
    widget.onComplete(result);
  }

  String _cameraLabel(MobileScannerState state) {
    if (!QrScanner.isAvailable) return 'No camera found';
    if (_loadingCameras && _cameras.isEmpty) return 'Loading camera...';

    final selectedCamera = _cameraById(_selectedCameraId);
    final camera = selectedCamera ?? state.camera ?? _defaultCamera;
    final name = camera?.name ?? 'Default camera';
    if (camera?.isDefault == true && !name.contains('(Default)')) {
      return '$name (Default)';
    }
    return name;
  }

  _CameraAccessStatus _cameraAccessStatus(MobileScannerState state) {
    if (!QrScanner.isAvailable) return _CameraAccessStatus.unavailable;
    if (state.error?.errorCode == MobileScannerErrorCode.permissionDenied) {
      return _CameraAccessStatus.denied;
    }
    if (state.error != null && !state.isRunning) {
      return _CameraAccessStatus.unavailable;
    }
    if (state.hasCameraPermission && state.isRunning) {
      return _CameraAccessStatus.active;
    }
    return _CameraAccessStatus.requesting;
  }

  String _cameraUnavailableDescription(MobileScannerState state) {
    final message = state.error?.errorDetails?.message;
    if (message != null && message.isNotEmpty) return message;
    return 'No camera could be opened. Check that a camera is connected and not in use by another app.';
  }

  String get _cameraDeniedTitle => Platform.isWindows
      ? 'Enable Windows camera access'
      : "You've denied the Camera access";

  String get _cameraDeniedDescription => Platform.isWindows
      ? 'Turn on Camera access and Let desktop apps access your camera in Windows Settings.'
      : 'Request again, or enable manually\nin the System settings.';

  Future<void> _retryCameraStart({required bool openSettingsOnDenied}) async {
    if (!QrScanner.isAvailable || _controller.value.isStarting) return;

    try {
      await _controller.start();
    } catch (e, st) {
      log('KeystoneQrScannerCard: camera start retry error: $e\n$st');
    }

    if (!mounted || !openSettingsOnDenied) return;
    if (_cameraAccessStatus(_controller.value) != _CameraAccessStatus.denied) {
      return;
    }

    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      log('KeystoneQrScannerCard: failed to open camera permission settings');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_retryCameraStart(openSettingsOnDenied: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camerasSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The mobile Keystone Scan frames draw the viewfinder as a white
    // (ground) card on the page background; the desktop pane keeps the
    // base surface.
    final surfaceColor = _mobileFormFactor
        ? colors.background.ground
        : colors.background.base;
    // Mobile draws a single full-bleed rounded camera card (Figma
    // `Keystone Scan`, radius 32, no inner frame and no camera-picker
    // footer — the back camera is the only camera). Desktop keeps the
    // 4 px inset frame around the feed and the camera controls.
    final outerPadding = _mobileFormFactor
        ? EdgeInsets.zero
        : const EdgeInsets.all(AppSpacing.xxs);
    final outerRadius = _mobileFormFactor ? AppRadii.xLarge : _outerRadius;
    final cameraRadius = _mobileFormFactor ? AppRadii.xLarge : _cameraRadius;
    final cameraAreaWidth = _mobileFormFactor
        ? double.infinity
        : (widget.cardWidth ?? _cardWidth) - AppSpacing.xxs * 2;
    return SizedBox(
      width: widget.cardWidth ?? _cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: outerPadding,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(outerRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      key: const ValueKey(
                        'keystone_qr_scanner_camera_viewport',
                      ),
                      width: cameraAreaWidth,
                      height: widget.cameraHeight ?? _cameraHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(cameraRadius),
                            clipBehavior: Clip.antiAliasWithSaveLayer,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: surfaceColor),
                              child: ValueListenableBuilder<MobileScannerState>(
                                valueListenable: _controller,
                                builder: (context, scannerState, _) {
                                  final accessStatus = _cameraAccessStatus(
                                    scannerState,
                                  );
                                  final canScan =
                                      accessStatus ==
                                      _CameraAccessStatus.active;

                                  return Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: [
                                      if (QrScanner.isAvailable)
                                        AnimatedUrScannerView(
                                          controller: _controller,
                                          expectedUrType: widget.expectedUrType,
                                          scanSessionResetToken:
                                              _scanSessionResetToken,
                                          onProgress: _handleScanProgress,
                                          onDecodeError: widget.onDecodeError,
                                          onComplete: _handleScanComplete,
                                        )
                                      else
                                        Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(
                                              AppSpacing.md,
                                            ),
                                            child: Text(
                                              widget.unavailableMessage,
                                              style: AppTypography
                                                  .bodyMediumStrong
                                                  .copyWith(
                                                    color: colors.text.accent,
                                                  ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      if (canScan) const _ScanOverlay(),
                                      if (canScan &&
                                          _scanProgress > 0 &&
                                          _scanProgress < 100 &&
                                          !widget.decoding)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 20,
                                          child: Center(
                                            child: _QrScanProgressBar(
                                              progress: _scanProgress / 100,
                                            ),
                                          ),
                                        ),
                                      if (canScan && widget.decoding)
                                        Positioned(
                                          left: -2,
                                          top: -2,
                                          right: -2,
                                          bottom: -2,
                                          child:
                                              KeystoneTransactionProgressOverlay(
                                                label: widget.decodingLabel,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      cameraRadius,
                                                    ),
                                              ),
                                        ),
                                      if (canScan &&
                                          _cameraPickerOpen &&
                                          !_mobileFormFactor)
                                        AppPaneModalOverlay(
                                          onDismiss: _toggleCameraPicker,
                                          borderRadius: BorderRadius.circular(
                                            _cameraRadius,
                                          ),
                                          child: _CameraPickerModal(
                                            cameras: _cameras,
                                            selectedCameraId:
                                                _selectedCameraId ??
                                                _controller.value.camera?.id,
                                            onSelect: _selectCamera,
                                            onCancel: _toggleCameraPicker,
                                          ),
                                        ),
                                      if (accessStatus ==
                                          _CameraAccessStatus.requesting)
                                        _CameraPermissionPrompt(
                                          icon: _mobileFormFactor
                                              ? AppIcons.cameraDenied
                                              : AppIcons.camera,
                                          title: 'Enable camera access',
                                          description:
                                              'A camera is required to connect Keystone.\n'
                                              'You can revert this in settings anytime later.',
                                          iconStyle: _CameraPermissionIconStyle
                                              .inverse,
                                        ),
                                      if (accessStatus ==
                                          _CameraAccessStatus.unavailable)
                                        _CameraPermissionPrompt(
                                          icon: AppIcons.cameraDenied,
                                          title: 'Camera unavailable',
                                          description:
                                              _cameraUnavailableDescription(
                                                scannerState,
                                              ),
                                          iconStyle:
                                              _CameraPermissionIconStyle.raised,
                                          action: AppButton(
                                            onPressed: () => unawaited(
                                              _retryCameraStart(
                                                openSettingsOnDenied: false,
                                              ),
                                            ),
                                            variant: AppButtonVariant.secondary,
                                            size: AppButtonSize.medium,
                                            minWidth: 96,
                                            leading: const AppIcon(
                                              AppIcons.renew,
                                            ),
                                            child: const Text('Try again'),
                                          ),
                                        ),
                                      if (accessStatus ==
                                          _CameraAccessStatus.denied)
                                        _CameraPermissionPrompt(
                                          icon: AppIcons.cameraDenied,
                                          title: _cameraDeniedTitle,
                                          description: _cameraDeniedDescription,
                                          // Denied draws the slashed glyph on a
                                          // raised (grey) square on both
                                          // platforms — Figma `Keystone Scan`
                                          // denied state.
                                          iconStyle:
                                              _CameraPermissionIconStyle.raised,
                                          action: AppButton(
                                            onPressed: () => unawaited(
                                              _retryCameraStart(
                                                openSettingsOnDenied: true,
                                              ),
                                            ),
                                            variant: AppButtonVariant.secondary,
                                            size: AppButtonSize.medium,
                                            minWidth: 96,
                                            leading: const AppIcon(
                                              AppIcons.renew,
                                            ),
                                            child: Text(
                                              _mobileFormFactor
                                                  ? 'Request again'
                                                  : 'Allow camera',
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          // The viewfinder edge ring outlines the live
                          // camera feed; the mobile permission states are
                          // a plain white card without it.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ValueListenableBuilder<MobileScannerState>(
                                valueListenable: _controller,
                                builder: (context, scannerState, _) {
                                  final active =
                                      _cameraAccessStatus(scannerState) ==
                                      _CameraAccessStatus.active;
                                  if (_mobileFormFactor && !active) {
                                    return const SizedBox.shrink();
                                  }
                                  return DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        cameraRadius,
                                      ),
                                      border: Border.all(
                                        color: colors.border.subtleOpacity,
                                        width: 2,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, scannerState, _) {
                        final active =
                            _cameraAccessStatus(scannerState) ==
                            _CameraAccessStatus.active;
                        // Mobile has no footer at all — the back camera is
                        // the only camera, so there is no picker, and the
                        // trouble-scanning link is dropped in favour of the
                        // page's "Tell me how Zcash works" button. Desktop
                        // keeps the link + camera controls in every state.
                        if (_mobileFormFactor) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          children: [
                            const SizedBox(height: AppSpacing.xs),
                            _TroubleScanningDisclosure(
                              onToggle: _toggleTroubleScanning,
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 56),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s,
                                  vertical: AppSpacing.sm,
                                ),
                                child: !active
                                    ? const SizedBox.shrink()
                                    : _CameraControlRow(
                                        label: _cameraLabel(scannerState),
                                        canChooseCamera:
                                            _cameras.length > 1 &&
                                            !widget.decoding &&
                                            scannerState.isInitialized,
                                        disabled: widget.decoding,
                                        onTap: _toggleCameraPicker,
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                if (_troubleScanningPopoverOpen)
                  AppPaneModalOverlay(
                    onDismiss: _dismissTroubleScanning,
                    borderRadius: BorderRadius.circular(_cameraRadius),
                    child: _TroubleScanningPopover(
                      onDismiss: _dismissTroubleScanning,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              widget.error!,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.destructive,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (!QrScanner.isAvailable) ...[
            const SizedBox(height: AppSpacing.s),
            AppButton(
              onPressed: null,
              variant: AppButtonVariant.primary,
              minWidth: 256,
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}

const _troubleScanningTips = [
  'Tap the QR code on your Keystone to show it full screen. This is the '
      'easiest fix.',
  'Move your Keystone a few inches further from the camera so it can focus.',
  "Make sure the room is well-lit and the QR code isn't reflecting glare.",
  'On a Mac, you can use Continuity Camera to scan with your iPhone instead.',
];

class _TroubleScanningDisclosure extends StatelessWidget {
  const _TroubleScanningDisclosure({required this.onToggle});

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor = colors.button.ghost.label;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.center,
            child: Semantics(
              button: true,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Trouble scanning?',
                          style: AppTypography.labelLarge.copyWith(
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        AppIcon(
                          AppIcons.expand,
                          size: AppIconSize.medium,
                          color: labelColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TroubleScanningPopover extends StatelessWidget {
  const _TroubleScanningPopover({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 360,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Trouble scanning?',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: AppIcon(
                      AppIcons.cross,
                      size: AppIconSize.medium,
                      color: colors.icon.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final tip in _troubleScanningTips)
            _TroubleScanningTip(text: tip),
        ],
      ),
    );
  }
}

class _TroubleScanningTip extends StatelessWidget {
  const _TroubleScanningTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: style),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

enum _CameraPermissionIconStyle { inverse, raised }

class _CameraPermissionPrompt extends StatelessWidget {
  const _CameraPermissionPrompt({
    required this.icon,
    required this.title,
    required this.description,
    required this.iconStyle,
    this.action,
  });

  final String icon;
  final String title;
  final String description;
  final _CameraPermissionIconStyle iconStyle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconBackground = switch (iconStyle) {
      _CameraPermissionIconStyle.inverse => colors.background.inverse,
      _CameraPermissionIconStyle.raised => colors.background.raised,
    };
    final iconColor = switch (iconStyle) {
      _CameraPermissionIconStyle.inverse => colors.icon.inverse,
      _CameraPermissionIconStyle.raised => colors.icon.regular,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _mobileFormFactor
            ? colors.background.ground
            : colors.background.base,
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Center(
          child: Padding(
            // The narrower mobile card keeps the prompt copy on the
            // designed two lines.
            padding: const EdgeInsets.symmetric(
              horizontal: _mobileFormFactor ? AppSpacing.sm : AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: Center(
                    child: AppIcon(icon, size: 24, color: iconColor),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      // Mobile prompt titles are Body L SemiBold in the
                      // Keystone Scan frames; desktop keeps Body M Strong.
                      style: _mobileFormFactor
                          ? AppTypography.bodyLarge.copyWith(
                              color: colors.text.accent,
                              fontWeight: FontWeight.w600,
                            )
                          : AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraControlRow extends StatelessWidget {
  const _CameraControlRow({
    required this.label,
    required this.canChooseCamera,
    required this.disabled,
    required this.onTap,
  });

  static const _labelMaxWidth = 304.0;

  final String label;
  final bool canChooseCamera;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cameraLabelColor = disabled
        ? colors.text.disabled
        : colors.text.primary;
    final cameraIconColor = disabled ? colors.text.disabled : colors.icon.muted;
    final controlLabelColor = disabled
        ? colors.button.disabled.label
        : colors.button.ghost.label;
    return Row(
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minWidth: 80),
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Row(
              children: [
                AppIcon(AppIcons.camera, size: 20, color: cameraIconColor),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Camera',
                  style: AppTypography.labelLarge.copyWith(
                    color: cameraLabelColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        MouseRegion(
          cursor: canChooseCamera
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canChooseCamera ? onTap : null,
            child: Container(
              height: 32,
              constraints: const BoxConstraints(minWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _labelMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: controlLabelColor,
                        ),
                      ),
                    ),
                  ),
                  AppIcon(
                    AppIcons.expand,
                    size: AppIconSize.medium,
                    color: controlLabelColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QrScanProgressBar extends StatelessWidget {
  const _QrScanProgressBar({required this.progress});

  static const _width = 128.0;
  static const _height = 6.0;

  final double progress;

  @override
  Widget build(BuildContext context) {
    final normalized = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.full),
      child: SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.4),
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: normalized,
              child: DecoratedBox(
                decoration: BoxDecoration(color: const Color(0xFFFFFFFF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraPickerModal extends StatelessWidget {
  const _CameraPickerModal({
    required this.cameras,
    required this.selectedCameraId,
    required this.onSelect,
    required this.onCancel,
  });

  static const _cardWidth = 344.0;
  static const _buttonWidth = 280.0;

  final List<MobileScannerCameraInfo> cameras;
  final String? selectedCameraId;
  final ValueChanged<MobileScannerCameraInfo> onSelect;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: _cardWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CameraPickerHeader(),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 152),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: cameras.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final camera = cameras[index];
                return _CameraOptionCard(
                  camera: camera,
                  selected: camera.id == selectedCameraId,
                  onTap: () => onSelect(camera),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: _buttonWidth,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _CameraPickerHeader extends StatelessWidget {
  const _CameraPickerHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(
              AppIcons.monitor,
              size: AppIconSize.medium,
              color: colors.icon.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Select Camera',
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraOptionCard extends StatelessWidget {
  const _CameraOptionCard({
    required this.camera,
    required this.selected,
    required this.onTap,
  });

  final MobileScannerCameraInfo camera;
  final bool selected;
  final VoidCallback onTap;

  String get _detailLabel {
    final parts = <String>[];
    if (camera.isDefault) parts.add('Default');
    if (camera.isExternal) parts.add('External');
    switch (camera.facing) {
      case CameraFacing.front:
        parts.add('Front');
      case CameraFacing.back:
        parts.add('Back');
      case CameraFacing.external:
        if (!parts.contains('External')) parts.add('External');
      case CameraFacing.unknown:
        break;
    }
    switch (camera.lensType) {
      case CameraLensType.normal:
        parts.add('Normal');
      case CameraLensType.wide:
        parts.add('Wide');
      case CameraLensType.zoom:
        parts.add('Zoom');
      case CameraLensType.any:
        break;
    }
    return parts.isEmpty ? 'Camera' : parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.background.neutralSubtleOpacity
                : colors.background.ground.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.regular,
              width: selected ? 2 : 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AppIcon(
                    AppIcons.monitor,
                    size: 18,
                    color: colors.icon.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      camera.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detailLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _CameraOptionIndicator(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraOptionIndicator extends StatelessWidget {
  const _CameraOptionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: selected
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: colors.background.ground,
              ),
            )
          : null,
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  static const _inset = -2.0;

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: _inset,
      top: _inset,
      right: _inset,
      bottom: _inset,
      child: IgnorePointer(child: CustomPaint(painter: _ScanOverlayPainter())),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  const _ScanOverlayPainter();

  static const _cutoutSize = 250.0;
  static const _cutoutRadius = 32.0;
  static const _strokeWidth = 5.0;
  static const _cornerArmLength = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: _cutoutSize,
      height: _cutoutSize,
    );
    final cutoutRRect = RRect.fromRectAndRadius(
      cutout,
      const Radius.circular(_cutoutRadius),
    );

    final dimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(cutoutRRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, Paint()..color = const Color(0xB3000000));

    final borderPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawCornerMarkers(canvas, cutout, borderPaint);
  }

  void _drawCornerMarkers(Canvas canvas, Rect cutout, Paint paint) {
    final rect = cutout.deflate(_strokeWidth / 2);
    final radius = _cutoutRadius - _strokeWidth / 2;
    final diameter = radius * 2;

    canvas
      ..drawPath(_topLeftCorner(rect, radius, diameter), paint)
      ..drawPath(_topRightCorner(rect, radius, diameter), paint)
      ..drawPath(_bottomRightCorner(rect, radius, diameter), paint)
      ..drawPath(_bottomLeftCorner(rect, radius, diameter), paint);
  }

  Path _topLeftCorner(Rect rect, double radius, double diameter) {
    return Path()
      ..moveTo(rect.left + radius + _cornerArmLength, rect.top)
      ..lineTo(rect.left + radius, rect.top)
      ..arcTo(
        Rect.fromLTWH(rect.left, rect.top, diameter, diameter),
        -math.pi / 2,
        -math.pi / 2,
        false,
      )
      ..lineTo(rect.left, rect.top + radius + _cornerArmLength);
  }

  Path _topRightCorner(Rect rect, double radius, double diameter) {
    return Path()
      ..moveTo(rect.right - radius - _cornerArmLength, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..arcTo(
        Rect.fromLTWH(rect.right - diameter, rect.top, diameter, diameter),
        -math.pi / 2,
        math.pi / 2,
        false,
      )
      ..lineTo(rect.right, rect.top + radius + _cornerArmLength);
  }

  Path _bottomRightCorner(Rect rect, double radius, double diameter) {
    return Path()
      ..moveTo(rect.right, rect.bottom - radius - _cornerArmLength)
      ..lineTo(rect.right, rect.bottom - radius)
      ..arcTo(
        Rect.fromLTWH(
          rect.right - diameter,
          rect.bottom - diameter,
          diameter,
          diameter,
        ),
        0,
        math.pi / 2,
        false,
      )
      ..lineTo(rect.right - radius - _cornerArmLength, rect.bottom);
  }

  Path _bottomLeftCorner(Rect rect, double radius, double diameter) {
    return Path()
      ..moveTo(rect.left + radius + _cornerArmLength, rect.bottom)
      ..lineTo(rect.left + radius, rect.bottom)
      ..arcTo(
        Rect.fromLTWH(rect.left, rect.bottom - diameter, diameter, diameter),
        math.pi / 2,
        math.pi / 2,
        false,
      )
      ..lineTo(rect.left, rect.bottom - radius - _cornerArmLength);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) => false;
}
