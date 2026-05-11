import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart';
import 'keystone_transaction_progress_panel.dart';

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

  @override
  State<KeystoneQrScannerCard> createState() => _KeystoneQrScannerCardState();
}

class _KeystoneQrScannerCardState extends State<KeystoneQrScannerCard> {
  static const _scannerWidth = 456.0;
  static const _scannerHeight = 316.0;
  static const _scannerRadius = 20.0;

  late MobileScannerController _controller;
  StreamSubscription<List<MobileScannerCameraInfo>>? _camerasSubscription;
  List<MobileScannerCameraInfo> _cameras = const [];
  String? _selectedCameraId;
  bool _loadingCameras = false;
  bool _cameraPickerOpen = false;
  int _scanProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _camerasSubscription = _controller.camerasStream.listen(_applyCameras);
    _loadCameras();
  }

  MobileScannerController _createController({String? cameraId}) {
    return MobileScannerController(
      cameraId: cameraId,
      facing: defaultQrScannerFacing,
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
      _cameraPickerOpen = !_cameraPickerOpen;
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
    });

    try {
      rust_keystone.resetUrSession();
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
    return selectedCamera?.name ??
        state.camera?.name ??
        _defaultCamera?.name ??
        'Default camera';
  }

  @override
  void dispose() {
    _camerasSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: _scannerWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: _scannerHeight,
            decoration: BoxDecoration(
              color: colors.background.overlay.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(_scannerRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (QrScanner.isAvailable)
                  AnimatedUrScannerView(
                    controller: _controller,
                    expectedUrType: widget.expectedUrType,
                    onProgress: _handleScanProgress,
                    onDecodeError: widget.onDecodeError,
                    onComplete: _handleScanComplete,
                  )
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        widget.unavailableMessage,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const _ScanFrame(),
                if (_scanProgress > 0 &&
                    _scanProgress < 100 &&
                    !widget.decoding)
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: _QrScanProgressBar(progress: _scanProgress / 100),
                  ),
                if (widget.decoding)
                  KeystoneTransactionProgressOverlay(
                    label: widget.decodingLabel,
                    borderRadius: BorderRadius.circular(_scannerRadius),
                  ),
                if (_cameraPickerOpen)
                  AppPaneModalOverlay(
                    onDismiss: _toggleCameraPicker,
                    borderRadius: BorderRadius.circular(_scannerRadius),
                    child: _CameraPickerModal(
                      cameras: _cameras,
                      selectedCameraId:
                          _selectedCameraId ?? _controller.value.camera?.id,
                      onSelect: _selectCamera,
                      onCancel: _toggleCameraPicker,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, scannerState, _) {
              final canChooseCamera =
                  _cameras.length > 1 &&
                  !widget.decoding &&
                  scannerState.isInitialized;
              return _CameraControlRow(
                label: _cameraLabel(scannerState),
                canChooseCamera: canChooseCamera,
                onTap: _toggleCameraPicker,
              );
            },
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

class _CameraControlRow extends StatelessWidget {
  const _CameraControlRow({
    required this.label,
    required this.canChooseCamera,
    required this.onTap,
  });

  static const _height = 24.0;
  static const _trailingMaxWidth = 320.0;

  final String label;
  final bool canChooseCamera;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: canChooseCamera
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canChooseCamera ? onTap : null,
        child: SizedBox(
          height: _height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Camera',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _trailingMaxWidth,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    if (canChooseCamera) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      AppIcon(
                        AppIcons.chevronForward,
                        size: AppIconSize.medium,
                        color: colors.icon.accent,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrScanProgressBar extends StatelessWidget {
  const _QrScanProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final normalized = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.full),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground.withValues(alpha: 0.42),
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: normalized,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.text.accent.withValues(alpha: 0.92),
                ),
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

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  static const _width = 263.0;
  static const _height = 262.0;
  static const _segmentLength = 58.0;
  static const _strokeWidth = 5.0;
  static const _radius = 17.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          children: [
            _ScanCorner(
              alignment: Alignment.topLeft,
              color: colors.text.accent,
            ),
            _ScanCorner(
              alignment: Alignment.topRight,
              color: colors.text.accent,
            ),
            _ScanCorner(
              alignment: Alignment.bottomLeft,
              color: colors.text.accent,
            ),
            _ScanCorner(
              alignment: Alignment.bottomRight,
              color: colors.text.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCorner extends StatelessWidget {
  const _ScanCorner({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment.x < 0;
    final isTop = alignment.y < 0;
    final border = BorderSide(
      color: color,
      width: _ScanFrame._strokeWidth,
      strokeAlign: BorderSide.strokeAlignInside,
    );
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: _ScanFrame._segmentLength,
        height: _ScanFrame._segmentLength,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: isLeft ? border : BorderSide.none,
              right: isLeft ? BorderSide.none : border,
              top: isTop ? border : BorderSide.none,
              bottom: isTop ? BorderSide.none : border,
            ),
            borderRadius: BorderRadius.only(
              topLeft: isLeft && isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
              topRight: !isLeft && isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
              bottomLeft: isLeft && !isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
              bottomRight: !isLeft && !isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
            ),
          ),
        ),
      ),
    );
  }
}
