import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../services/camera_permission_settings.dart';
import '../../../services/qr_scanner.dart';
import '../domain/swap_address_scan_payload.dart';

enum SwapAddressQrCameraStatus {
  requesting,
  denied,
  active,
  loading,
  unavailable,
}

class SwapAddressQrScanModal extends StatefulWidget {
  const SwapAddressQrScanModal({
    required this.onAddressScanned,
    required this.onCancel,
    super.key,
  });

  final ValueChanged<String> onAddressScanned;
  final VoidCallback onCancel;

  @override
  State<SwapAddressQrScanModal> createState() => _SwapAddressQrScanModalState();
}

class _SwapAddressQrScanModalState extends State<SwapAddressQrScanModal>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  StreamSubscription<List<MobileScannerCameraInfo>>? _camerasSubscription;
  List<MobileScannerCameraInfo> _cameras = const [];
  String? _selectedCameraId;
  bool _loadingCameras = false;
  bool _switchingCamera = false;
  bool _completed = false;
  int _scanResetToken = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      facing: defaultQrScannerFacing,
      formats: QrScanner.formats,
      detectionSpeed: QrScanner.detectionSpeed,
    );
    _camerasSubscription = _controller.camerasStream.listen(_applyCameras);
    unawaited(_loadCameras());
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

  Future<void> _loadCameras() async {
    if (!QrScanner.isAvailable) return;
    setState(() => _loadingCameras = true);

    try {
      final cameras = await _controller.getAvailableCameras();
      if (!mounted) return;
      _applyCameras(cameras);
    } catch (e, st) {
      log('SwapAddressQrScanModal: camera list error: $e\n$st');
      if (!mounted) return;
      setState(() => _loadingCameras = false);
    }
  }

  void _applyCameras(List<MobileScannerCameraInfo> cameras) {
    if (!mounted) return;
    final selectedStillAvailable =
        _selectedCameraId == null ||
        cameras.any((camera) => camera.id == _selectedCameraId);
    setState(() {
      _cameras = cameras;
      _loadingCameras = false;
      if (!selectedStillAvailable) {
        _selectedCameraId = null;
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

  SwapAddressQrCameraStatus _cameraAccessStatus(MobileScannerState state) {
    if (!QrScanner.isAvailable) return SwapAddressQrCameraStatus.unavailable;
    if (state.error?.errorCode == MobileScannerErrorCode.permissionDenied) {
      return SwapAddressQrCameraStatus.denied;
    }
    if (state.error != null && !state.isRunning) {
      return SwapAddressQrCameraStatus.unavailable;
    }
    if (state.hasCameraPermission && state.isRunning) {
      return SwapAddressQrCameraStatus.active;
    }
    if (state.hasCameraPermission || state.isStarting || state.isInitialized) {
      return SwapAddressQrCameraStatus.loading;
    }
    return SwapAddressQrCameraStatus.requesting;
  }

  String _cameraUnavailableDescription(MobileScannerState state) {
    final message = state.error?.errorDetails?.message;
    if (message != null && message.isNotEmpty) return message;
    return 'No camera could be opened. Check that a camera is connected and not in use by another app.';
  }

  Future<void> _retryCameraStart({required bool openSettingsOnDenied}) async {
    if (!QrScanner.isAvailable || _controller.value.isStarting) return;

    try {
      await _controller.start();
    } catch (e, st) {
      log('SwapAddressQrScanModal: camera start retry error: $e\n$st');
    }

    if (!mounted || !openSettingsOnDenied) return;
    if (_cameraAccessStatus(_controller.value) !=
        SwapAddressQrCameraStatus.denied) {
      return;
    }

    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      log('SwapAddressQrScanModal: failed to open camera permission settings');
    }
  }

  Future<void> _selectNextCamera() async {
    if (_cameras.length < 2 ||
        _switchingCamera ||
        _controller.value.isStarting ||
        !_controller.value.isRunning) {
      return;
    }
    final currentId =
        _selectedCameraId ?? _controller.value.camera?.id ?? _defaultCamera?.id;
    final currentIndex = _cameras.indexWhere(
      (camera) => camera.id == currentId,
    );
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + 1) % _cameras.length;
    final nextCamera = _cameras[nextIndex];

    setState(() {
      _switchingCamera = true;
      _selectedCameraId = nextCamera.id;
      _error = null;
    });

    try {
      await _controller.switchCamera(SelectCamera(cameraId: nextCamera.id));
    } catch (e, st) {
      log('SwapAddressQrScanModal: camera switch error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _selectedCameraId = _controller.value.camera?.id;
      });
    } finally {
      if (mounted) {
        setState(() => _switchingCamera = false);
      }
    }
  }

  void _handleScanComplete(String value) {
    if (_completed) return;
    final normalized = normalizeSwapAddressScanPayload(value);
    if (normalized == null || normalized.isEmpty) {
      setState(() {
        _error = 'QR code did not include an address.';
        _scanResetToken++;
      });
      return;
    }
    _completed = true;
    widget.onAddressScanned(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, scannerState, _) {
        final status = _cameraAccessStatus(scannerState);
        final unavailableDescription =
            status == SwapAddressQrCameraStatus.unavailable
            ? _cameraUnavailableDescription(scannerState)
            : null;
        return SwapAddressQrScanModalContent(
          status: status,
          cameraView: QrScanner.isAvailable
              ? PlainQrScannerView(
                  controller: _controller,
                  scanSessionResetToken: _scanResetToken,
                  onComplete: _handleScanComplete,
                )
              : null,
          cameraLabel: _cameraLabel(scannerState),
          canChooseCamera:
              _cameras.length > 1 &&
              scannerState.isInitialized &&
              scannerState.isRunning &&
              !scannerState.isStarting &&
              !_switchingCamera &&
              !_completed,
          onCameraTap: () => unawaited(_selectNextCamera()),
          onRetry: () =>
              unawaited(_retryCameraStart(openSettingsOnDenied: true)),
          onCancel: widget.onCancel,
          unavailableDescription: unavailableDescription,
          error: _error,
        );
      },
    );
  }
}

class SwapAddressQrScanModalContent extends StatelessWidget {
  const SwapAddressQrScanModalContent({
    required this.status,
    required this.onCancel,
    this.cameraView,
    this.cameraLabel = 'Face Time HD Camera (Default)',
    this.canChooseCamera = false,
    this.onCameraTap,
    this.onRetry,
    this.unavailableDescription,
    this.error,
    super.key,
  });

  static const width = 312.0;
  static const height = 440.0;
  static const cameraWidth = 272.0;
  static const cameraHeight = 220.0;

  final SwapAddressQrCameraStatus status;
  final Widget? cameraView;
  final String cameraLabel;
  final bool canChooseCamera;
  final VoidCallback? onCameraTap;
  final VoidCallback? onRetry;
  final VoidCallback onCancel;
  final String? unavailableDescription;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_address_scan_modal'),
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SwapAddressQrScanTitle(),
          const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _SwapAddressQrCameraModal(
                        status: status,
                        cameraView: cameraView,
                        cameraLabel: cameraLabel,
                        canChooseCamera: canChooseCamera,
                        onCameraTap: onCameraTap,
                        onRetry: onRetry,
                        unavailableDescription: unavailableDescription,
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      error!,
                      key: const ValueKey('swap_address_scan_error'),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.destructive,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            key: const ValueKey('swap_address_scan_cancel_button'),
            onPressed: onCancel,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.large,
            minWidth: 280,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _SwapAddressQrScanTitle extends StatelessWidget {
  const _SwapAddressQrScanTitle();

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
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Center(
            child: AppIcon(AppIcons.qr, size: 16, color: colors.icon.regular),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Scan the address QR Code',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _SwapAddressQrCameraModal extends StatelessWidget {
  const _SwapAddressQrCameraModal({
    required this.status,
    required this.cameraLabel,
    required this.canChooseCamera,
    required this.onCameraTap,
    required this.onRetry,
    required this.unavailableDescription,
    this.cameraView,
  });

  final SwapAddressQrCameraStatus status;
  final Widget? cameraView;
  final String cameraLabel;
  final bool canChooseCamera;
  final VoidCallback? onCameraTap;
  final VoidCallback? onRetry;
  final String? unavailableDescription;

  bool get _showsCameraFooter =>
      status == SwapAddressQrCameraStatus.active ||
      status == SwapAddressQrCameraStatus.loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('swap_address_scan_camera_modal'),
      width: SwapAddressQrScanModalContent.cameraWidth,
      height: 276,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SwapAddressQrCameraViewport(
            status: status,
            cameraView: cameraView,
            onRetry: onRetry,
            unavailableDescription: unavailableDescription,
          ),
          if (_showsCameraFooter) ...[
            const SizedBox(height: 16),
            _SwapAddressQrCameraFooter(
              label: cameraLabel,
              enabled: canChooseCamera,
              onTap: onCameraTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _SwapAddressQrCameraViewport extends StatelessWidget {
  const _SwapAddressQrCameraViewport({
    required this.status,
    required this.onRetry,
    required this.unavailableDescription,
    this.cameraView,
  });

  final SwapAddressQrCameraStatus status;
  final Widget? cameraView;
  final VoidCallback? onRetry;
  final String? unavailableDescription;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.large),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: SizedBox(
        key: const ValueKey('swap_address_scan_camera_viewport'),
        width: SwapAddressQrScanModalContent.cameraWidth,
        height: SwapAddressQrScanModalContent.cameraHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.background.base),
            ),
            ?cameraView,
            if (status == SwapAddressQrCameraStatus.requesting)
              const _SwapAddressQrCameraMessage(
                iconName: AppIcons.camera,
                title: 'Grant access to your Camera',
                description:
                    'Request again, or enable manually\nin the System settings.',
              ),
            if (status == SwapAddressQrCameraStatus.denied)
              _SwapAddressQrCameraMessage(
                iconName: AppIcons.camera,
                title: _cameraDeniedTitle,
                description: _cameraDeniedDescription,
                action: AppButton(
                  onPressed: onRetry,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  minWidth: 96,
                  leading: const AppIcon(AppIcons.renew),
                  child: const Text('Request again'),
                ),
              ),
            if (status == SwapAddressQrCameraStatus.unavailable)
              _SwapAddressQrCameraMessage(
                iconName: AppIcons.cameraDenied,
                title: 'Camera unavailable',
                description:
                    unavailableDescription ??
                    'Address QR scanning requires a camera on this device.',
                action: onRetry == null
                    ? null
                    : AppButton(
                        onPressed: onRetry,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.medium,
                        minWidth: 96,
                        leading: const AppIcon(AppIcons.renew),
                        child: const Text('Try again'),
                      ),
              ),
            if (status == SwapAddressQrCameraStatus.loading)
              const _SwapAddressQrLoadingOverlay(),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.large),
                    border: Border.all(
                      color: colors.border.subtleOpacity,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _cameraDeniedTitle => Platform.isWindows
      ? 'Enable Windows camera access'
      : "You've denied Camera access";

  String get _cameraDeniedDescription => Platform.isWindows
      ? 'Turn on Camera access and Let desktop apps access your camera in Windows Settings.'
      : 'Request again, or enable manually\nin the System settings.';
}

class _SwapAddressQrCameraMessage extends StatelessWidget {
  const _SwapAddressQrCameraMessage({
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
    return ColoredBox(
      color: colors.background.base,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                  child: AppIcon(
                    iconName,
                    size: 24,
                    color: colors.icon.inverse,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _SwapAddressQrLoadingOverlay extends StatelessWidget {
  const _SwapAddressQrLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.inverse.withValues(alpha: 0.3),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.loader, size: 20, color: colors.icon.inverse),
            const SizedBox(width: 4),
            Text(
              'Loading...',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.inverse,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapAddressQrCameraFooter extends StatelessWidget {
  const _SwapAddressQrCameraFooter({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor = enabled
        ? colors.button.ghost.label
        : colors.text.primary;
    return Center(
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Container(
            key: const ValueKey('swap_address_scan_camera_footer'),
            height: 32,
            constraints: const BoxConstraints(minWidth: 96, maxWidth: 248),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: labelColor,
                      ),
                    ),
                  ),
                ),
                AppIcon(AppIcons.expand, size: 16, color: labelColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
