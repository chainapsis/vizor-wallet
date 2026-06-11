import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart' show appModalShadow;
import '../../../services/camera_permission_settings.dart';
import '../../../services/qr_scanner.dart';
import '../domain/address_scan_payload.dart';

enum AddressQrCameraStatus { requesting, denied, active, loading, unavailable }

class AddressQrScanModal extends StatefulWidget {
  const AddressQrScanModal({
    required this.onAddressScanned,
    required this.onCancel,
    super.key,
  });

  final ValueChanged<String> onAddressScanned;
  final VoidCallback onCancel;

  @override
  State<AddressQrScanModal> createState() => _AddressQrScanModalState();
}

class _AddressQrScanModalState extends State<AddressQrScanModal>
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
      log('AddressQrScanModal: camera list error: $e\n$st');
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
      log('AddressQrScanModal: camera start retry error: $e\n$st');
    }

    if (!mounted || !openSettingsOnDenied) return;
    if (_cameraAccessStatus(_controller.value) !=
        AddressQrCameraStatus.denied) {
      return;
    }

    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      log('AddressQrScanModal: failed to open camera permission settings');
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
      log('AddressQrScanModal: camera switch error: $e\n$st');
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
    final normalized = normalizeAddressScanPayload(value);
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
            status == AddressQrCameraStatus.unavailable
            ? _cameraUnavailableDescription(scannerState)
            : null;
        return AddressQrScanModalContent(
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

class AddressQrScanModalContent extends StatelessWidget {
  const AddressQrScanModalContent({
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
  static const cameraModalHeight = 276.0;
  static const cameraFooterHeight = 40.0;

  final AddressQrCameraStatus status;
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
    // Inline AppModalCard shell: the QR modal needs a fixed 440 height and a
    // size-asserted key, which the shared AppModalCard wrapper cannot expose,
    // so the card decoration (base surface, large radius, appModalShadow) is
    // applied directly here to stay in sync with the shared modal pattern.
    return Container(
      key: const ValueKey('address_scan_modal'),
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appModalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AddressQrScanTitle(),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _AddressQrCameraModal(
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
                      key: const ValueKey('address_scan_error'),
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
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('address_scan_cancel_button'),
            onPressed: onCancel,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.large,
            minWidth: 196,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _AddressQrScanTitle extends StatelessWidget {
  const _AddressQrScanTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Scan the address QR Code',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _AddressQrCameraModal extends StatelessWidget {
  const _AddressQrCameraModal({
    required this.status,
    required this.cameraLabel,
    required this.canChooseCamera,
    required this.onCameraTap,
    required this.onRetry,
    required this.unavailableDescription,
    this.cameraView,
  });

  final AddressQrCameraStatus status;
  final Widget? cameraView;
  final String cameraLabel;
  final bool canChooseCamera;
  final VoidCallback? onCameraTap;
  final VoidCallback? onRetry;
  final String? unavailableDescription;

  bool get _showsCameraFooter =>
      status == AddressQrCameraStatus.active ||
      status == AddressQrCameraStatus.loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('address_scan_camera_modal'),
      width: AddressQrScanModalContent.cameraWidth,
      height: AddressQrScanModalContent.cameraModalHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _AddressQrCameraViewport(
            status: status,
            cameraView: cameraView,
            onRetry: onRetry,
            unavailableDescription: unavailableDescription,
          ),
          if (_showsCameraFooter) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              key: const ValueKey('address_scan_camera_footer_slot'),
              height: AddressQrScanModalContent.cameraFooterHeight,
              child: _AddressQrCameraFooter(
                label: cameraLabel,
                enabled: canChooseCamera,
                onTap: onCameraTap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressQrCameraViewport extends StatelessWidget {
  const _AddressQrCameraViewport({
    required this.status,
    required this.onRetry,
    required this.unavailableDescription,
    this.cameraView,
  });

  final AddressQrCameraStatus status;
  final Widget? cameraView;
  final VoidCallback? onRetry;
  final String? unavailableDescription;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showsCameraSurface =
        status == AddressQrCameraStatus.active ||
        status == AddressQrCameraStatus.loading;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.large),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: SizedBox(
        key: const ValueKey('address_scan_camera_viewport'),
        width: AddressQrScanModalContent.cameraWidth,
        height: AddressQrScanModalContent.cameraHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.background.base),
            ),
            ?cameraView,
            if (status == AddressQrCameraStatus.requesting)
              const _AddressQrCameraMessage(
                iconName: AppIcons.camera,
                title: 'Grant access to your camera',
                description:
                    'Request again, or enable manually\nin the System settings.',
              ),
            if (status == AddressQrCameraStatus.denied)
              _AddressQrCameraMessage(
                iconName: AppIcons.camera,
                title: _cameraDeniedTitle,
                description: _cameraDeniedDescription,
                action: AppButton(
                  key: const ValueKey('address_scan_retry_button'),
                  onPressed: onRetry,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  minWidth: 96,
                  leading: const AppIcon(AppIcons.renew, size: 16),
                  child: const Text('Request again'),
                ),
              ),
            if (status == AddressQrCameraStatus.unavailable)
              _AddressQrCameraMessage(
                iconName: AppIcons.cameraDenied,
                title: 'Camera unavailable',
                description:
                    unavailableDescription ??
                    'Address QR scanning requires a camera on this device.',
                action: onRetry == null
                    ? null
                    : AppButton(
                        key: const ValueKey('address_scan_retry_button'),
                        onPressed: onRetry,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.medium,
                        minWidth: 96,
                        leading: const AppIcon(AppIcons.renew, size: 16),
                        child: const Text('Try again'),
                      ),
              ),
            if (status == AddressQrCameraStatus.loading)
              const _AddressQrLoadingOverlay(),
            if (showsCameraSurface)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('address_scan_camera_border'),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.large),
                      border: Border.all(
                        color: colors.border.inverseOpacity,
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

class _AddressQrCameraMessage extends StatelessWidget {
  const _AddressQrCameraMessage({
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
    // Figma 'Modal Camera Utility': the message sits directly on the modal
    // card surface — no filled box behind the permission/error states.
    return ColoredBox(
      key: const ValueKey('address_scan_camera_message'),
      color: colors.background.base,
      child: Center(
        child: Padding(
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
                  child: AppIcon(
                    iconName,
                    size: 24,
                    color: colors.icon.inverse,
                  ),
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
              _AddressQrCameraDescription(
                description: description,
                color: colors.text.secondary,
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.md),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressQrCameraDescription extends StatelessWidget {
  const _AddressQrCameraDescription({
    required this.description,
    required this.color,
  });

  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final lines = description.split('\n');
    final style = AppTypography.bodyMedium.copyWith(color: color);

    if (lines.length <= 1) {
      return Text(
        description,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          Text(
            line,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
      ],
    );
  }
}

class _AddressQrLoadingOverlay extends StatelessWidget {
  const _AddressQrLoadingOverlay();

  // Figma 'Camera Loading': a theme-invariant black 30% tint with white
  // foreground — the overlay sits on live camera video, not on a themed
  // surface, so it does not follow the light/dark tokens.
  static const _scrimColor = Color(0x4D000000);
  static const _foregroundColor = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      key: const ValueKey('address_scan_loading_overlay'),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 37, sigmaY: 37),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: _scrimColor),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(
                  AppIcons.loader,
                  size: 20,
                  color: _foregroundColor,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Loading',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: _foregroundColor,
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

class _AddressQrCameraFooter extends StatelessWidget {
  const _AddressQrCameraFooter({
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
            key: const ValueKey('address_scan_camera_footer'),
            height: 36,
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
