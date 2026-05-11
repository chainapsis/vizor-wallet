import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart';
import 'keystone_onboarding_flow.dart';

class KeystoneScanQrScreen extends ConsumerStatefulWidget {
  const KeystoneScanQrScreen({super.key});

  @override
  ConsumerState<KeystoneScanQrScreen> createState() =>
      _KeystoneScanQrScreenState();
}

class _KeystoneScanQrScreenState extends ConsumerState<KeystoneScanQrScreen> {
  bool _decoding = false;
  String? _error;

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
    });

    try {
      final accounts = await rust_keystone.decodeAccountsFromCbor(
        cbor: result.data,
      );
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _decoding = false;
          _error = 'No Zcash accounts were found on this Keystone QR.';
        });
        return;
      }

      ref.read(keystoneOnboardingProvider.notifier).setAccounts(accounts);
      context.go(KeystoneOnboardingStep.selectAccount.routePath);
    } catch (e, st) {
      log('KeystoneScanQrScreen: account decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _error =
            'This QR code could not be decoded as a Keystone Zcash account.';
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the Zcash account QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return KeystoneOnboardingTrailingPane(
      child: Column(
        children: [
          KeystoneBackRow(
            routePath: KeystoneOnboardingStep.howToConnect.routePath,
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scan QR Code',
                      style: AppTypography.displayMedium.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: 340,
                      child: Text(
                        'Grant access to your camera and then place the QR code in front of your screen.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _ScannerCard(
                      decoding: _decoding,
                      error: _error,
                      onProgress: (progress) {
                        if (!mounted) return;
                        setState(() {
                          if (progress > 0) _error = null;
                        });
                      },
                      onDecodeError: _handleDecodeError,
                      onComplete: _handleScanComplete,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerCard extends StatefulWidget {
  const _ScannerCard({
    required this.decoding,
    required this.error,
    required this.onProgress,
    required this.onDecodeError,
    required this.onComplete,
  });

  final bool decoding;
  final String? error;
  final ValueChanged<int> onProgress;
  final ValueChanged<Object> onDecodeError;
  final ValueChanged<ScanResult> onComplete;

  @override
  State<_ScannerCard> createState() => _ScannerCardState();
}

class _ScannerCardState extends State<_ScannerCard> {
  late MobileScannerController _controller;
  StreamSubscription<List<MobileScannerCameraInfo>>? _camerasSubscription;
  List<MobileScannerCameraInfo> _cameras = const [];
  String? _selectedCameraId;
  bool _loadingCameras = false;
  bool _cameraPickerOpen = false;

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
      log('KeystoneScanQrScreen: camera list error: $e\n$st');
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
    });

    try {
      rust_keystone.resetUrSession();
      await _controller.switchCamera(SelectCamera(cameraId: camera.id));
    } catch (e, st) {
      log('KeystoneScanQrScreen: camera switch error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _selectedCameraId = _controller.value.camera?.id;
      });
    }
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
      width: 456,
      child: Column(
        children: [
          Container(
            height: 316,
            decoration: BoxDecoration(
              color: colors.background.overlay.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (QrScanner.isAvailable)
                  AnimatedUrScannerView(
                    controller: _controller,
                    expectedUrType: 'zcash-accounts',
                    onProgress: widget.onProgress,
                    onDecodeError: widget.onDecodeError,
                    onComplete: widget.onComplete,
                  )
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        'Keystone import uses camera QR scanning only. Connect a camera and try again.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const _ScanFrame(),
                if (widget.decoding)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background.ground.withValues(alpha: 0.72),
                    ),
                    child: Center(
                      child: Text(
                        'Reading accounts...',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
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
              return Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canChooseCamera ? _toggleCameraPicker : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Camera',
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              _cameraLabel(scannerState),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                  ),
                  if (_cameraPickerOpen)
                    _CameraPicker(
                      cameras: _cameras,
                      selectedCameraId:
                          _selectedCameraId ?? scannerState.camera?.id,
                      onSelect: _selectCamera,
                    ),
                ],
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

class _CameraPicker extends StatelessWidget {
  const _CameraPicker({
    required this.cameras,
    required this.selectedCameraId,
    required this.onSelect,
  });

  final List<MobileScannerCameraInfo> cameras;
  final String? selectedCameraId;
  final ValueChanged<MobileScannerCameraInfo> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: colors.background.overlay.withValues(alpha: 0.72),
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 176),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          itemCount: cameras.length,
          separatorBuilder: (_, _) =>
              Container(height: 1, color: colors.border.subtle),
          itemBuilder: (context, index) {
            final camera = cameras[index];
            final selected = camera.id == selectedCameraId;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(camera),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        camera.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: selected
                              ? colors.text.accent
                              : colors.text.secondary,
                        ),
                      ),
                    ),
                    if (selected)
                      AppIcon(
                        AppIcons.check,
                        size: AppIconSize.medium,
                        color: colors.icon.accent,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
