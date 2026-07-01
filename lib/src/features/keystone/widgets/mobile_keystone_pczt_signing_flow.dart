import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Colors, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/camera_permission_settings.dart';
import '../../../services/qr_scanner.dart';
import '../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanCameraErrorOverlay, MobileScanViewfinderCorners;
import 'keystone_pczt_qr_stage.dart';

class MobileKeystonePcztSigningAborted implements Exception {
  const MobileKeystonePcztSigningAborted();
}

class MobileKeystonePcztSigningPayload {
  const MobileKeystonePcztSigningPayload({
    required this.urParts,
    required this.pcztWithProofs,
  });

  final List<String> urParts;
  final Future<List<int>> pcztWithProofs;
}

typedef MobileKeystonePcztPrepare =
    Future<MobileKeystonePcztSigningPayload> Function(
      BuildContext context,
      WidgetRef ref,
    );

typedef MobileKeystonePcztSigned =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref,
      List<int> pcztWithProofs,
      Uint8List signedPczt,
    );

typedef MobileKeystonePcztFriendlyError = String Function(Object error);

enum _SignStage { preparing, showQr, scanning, failed }

/// Shared mobile Keystone PCZT round trip.
///
/// Callers own domain-specific PCZT creation and broadcast; this widget owns the
/// common mobile UX: animated transaction QR, camera scan for the signed PCZT,
/// decode, and waiting for the locally-proved PCZT clone.
class MobileKeystonePcztSigningFlow extends ConsumerStatefulWidget {
  const MobileKeystonePcztSigningFlow({
    required this.title,
    required this.description,
    required this.preparePczt,
    required this.onSigned,
    required this.friendlyError,
    this.failedTitle,
    this.keyPrefix = 'mobile_keystone_sign',
    this.readingSignatureLabel = 'Reading signature...',
    this.finalizingSignatureLabel,
    this.logTag = 'MobileKeystonePcztSigningFlow',
    super.key,
  });

  final String title;
  final String? failedTitle;
  final String description;
  final String keyPrefix;
  final String readingSignatureLabel;
  final String? finalizingSignatureLabel;
  final String logTag;
  final MobileKeystonePcztPrepare preparePczt;
  final MobileKeystonePcztSigned onSigned;
  final MobileKeystonePcztFriendlyError friendlyError;

  @override
  ConsumerState<MobileKeystonePcztSigningFlow> createState() =>
      _MobileKeystonePcztSigningFlowState();
}

class _MobileKeystonePcztSigningFlowState
    extends ConsumerState<MobileKeystonePcztSigningFlow>
    with WidgetsBindingObserver {
  var _stage = _SignStage.preparing;
  String? _error;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  bool _proofsFailed = false;
  bool _decoding = false;
  bool _restartCameraOnResume = false;
  int _scanProgress = 0;
  String? _scanHint;

  MobileScannerController? _scanController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_preparePczt());
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
    unawaited(_scanController?.dispose());
    super.dispose();
  }

  Future<void> _preparePczt() async {
    try {
      final payload = await widget.preparePczt(context, ref);
      if (!mounted) return;
      setState(() {
        _stage = _SignStage.showQr;
        _urParts = payload.urParts;
        _error = null;
      });
      unawaited(_waitForProofs(payload.pcztWithProofs));
    } on MobileKeystonePcztSigningAborted {
      if (!mounted) return;
      context.pop();
    } catch (e, st) {
      log('${widget.logTag}._preparePczt: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _stage = _SignStage.failed;
        _error = widget.friendlyError(e);
      });
    }
  }

  Future<void> _waitForProofs(Future<List<int>> pcztWithProofs) async {
    try {
      final proofs = await pcztWithProofs;
      if (!mounted) return;
      setState(() => _pcztWithProofs = proofs);
    } catch (e, st) {
      log('${widget.logTag}._waitForProofs: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _proofsFailed = true;
        _stage = _SignStage.failed;
        _error = widget.friendlyError(e);
      });
    }
  }

  void _startScanning() {
    _scanController ??= MobileScannerController(
      facing: CameraFacing.back,
      formats: QrScanner.formats,
      detectionSpeed: QrScanner.detectionSpeed,
    );
    setState(() {
      _stage = _SignStage.scanning;
      _scanHint = null;
      _scanProgress = 0;
    });
  }

  void _backToQr() {
    setState(() {
      _stage = _SignStage.showQr;
      _scanHint = null;
      _scanProgress = 0;
    });
  }

  Future<void> _openCameraSettings() async {
    _restartCameraOnResume = true;
    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      _restartCameraOnResume = false;
      log('${widget.logTag}: failed to open camera permission settings');
    }
  }

  Future<void> _restartCameraAfterSettings() async {
    final scanController = _scanController;
    if (scanController == null ||
        scanController.value.isStarting ||
        scanController.value.isRunning) {
      return;
    }

    try {
      await scanController.start();
    } catch (e, st) {
      log('${widget.logTag}: camera settings return retry error: $e\n$st');
    }
  }

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _scanHint = widget.readingSignatureLabel;
    });

    late final Uint8List signedPczt;
    try {
      final signedPcztBytes = await rust_keystone.decodePcztFromCbor(
        cbor: result.data,
      );
      signedPczt = Uint8List.fromList(signedPcztBytes);
    } catch (e, st) {
      log('${widget.logTag}: signed PCZT decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _scanHint =
            'This QR code could not be decoded as a Keystone signature.';
      });
      return;
    }

    while (mounted && _pcztWithProofs == null && !_proofsFailed) {
      if (_stage == _SignStage.failed) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final pcztWithProofs = _pcztWithProofs;
    if (!mounted) return;
    if (pcztWithProofs == null) {
      setState(() {
        _decoding = false;
        _stage = _SignStage.failed;
        _error ??= 'Keystone signing could not be prepared.';
      });
      return;
    }

    final finalizingLabel = widget.finalizingSignatureLabel;
    if (finalizingLabel != null) {
      setState(() => _scanHint = finalizingLabel);
    }

    try {
      await widget.onSigned(context, ref, pcztWithProofs, signedPczt);
    } catch (e, st) {
      log('${widget.logTag}._onSigned: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _stage = _SignStage.failed;
        _error = widget.friendlyError(e);
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the signed transaction QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_scanHint == message) return;
    setState(() => _scanHint = message);
  }

  void _cancel() {
    if (_decoding) return;
    context.pop();
  }

  ValueKey<String> _key(String suffix) {
    return ValueKey('${widget.keyPrefix}_$suffix');
  }

  @override
  Widget build(BuildContext context) {
    final scanning = _stage == _SignStage.scanning;
    return PopScope<void>(
      canPop: !_decoding,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          key: _key('screen'),
          fit: StackFit.expand,
          children: [
            if (scanning) _buildScanner() else _buildQrStage(),
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
                        if (scanning)
                          Semantics(
                            button: true,
                            label: 'Toggle flashlight',
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  unawaited(_scanController?.toggleTorch()),
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
                          enabled: !_decoding,
                          label: 'Cancel signing',
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _decoding ? null : _cancel,
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
                  _buildBottomBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrStage() {
    final colors = context.colors;
    final title = _stage == _SignStage.failed
        ? widget.failedTitle ?? widget.title
        : widget.title;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          children: [
            const SizedBox(height: 72),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              widget.description,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: const Color(0xCCFFFFFF),
              ),
            ),
            const Spacer(),
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 312.0;
                final qrSize = (availableWidth - AppSpacing.sm * 2)
                    .clamp(220.0, 280.0)
                    .toDouble();
                return Container(
                  key: _key('qr_stage'),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.background.ground,
                    borderRadius: BorderRadius.circular(AppRadii.large),
                  ),
                  child: KeystonePcztQrStage(
                    phase: switch (_stage) {
                      _SignStage.showQr => KeystonePcztQrStagePhase.ready,
                      _SignStage.failed => KeystonePcztQrStagePhase.failed,
                      _ => KeystonePcztQrStagePhase.preparing,
                    },
                    urParts: _urParts,
                    error: _error,
                    size: qrSize,
                    scanOptimized: true,
                    frameInterval: const Duration(milliseconds: 100),
                  ),
                );
              },
            ),
            const Spacer(),
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    const viewfinderSize = 260.0;
    final scanController = _scanController;
    if (scanController == null) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedUrScannerView(
          controller: scanController,
          expectedUrType: 'zcash-pczt',
          scanSessionResetToken: _stage,
          errorBuilder: (context, error) => const SizedBox.shrink(),
          onProgress: (progress) {
            if (!mounted || _scanProgress == progress) return;
            setState(() => _scanProgress = progress);
          },
          onDecodeError: _handleDecodeError,
          onComplete: (result) => unawaited(_handleScanComplete(result)),
        ),
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
            child: const MobileScanViewfinderCorners(),
          ),
        ),
        MobileScanCameraErrorOverlay(
          controller: scanController,
          maxWidth: viewfinderSize,
          permissionDeniedMessage:
              'Camera access is off. Allow it in Settings to scan Keystone signatures.',
          unavailableMessage: 'The camera is unavailable right now.',
          onOpenSettings: _openCameraSettings,
        ),
        Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.only(top: viewfinderSize + 96),
            child: Text(
              _decoding
                  ? _scanHint ?? widget.readingSignatureLabel
                  : _scanHint ??
                        (_scanProgress > 0
                            ? 'Scanning... $_scanProgress%'
                            : 'Scan the signed QR on your Keystone'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final scanning = _stage == _SignStage.scanning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.s,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: AppButton(
              key: _key('cancel'),
              expand: true,
              variant: AppButtonVariant.ghost,
              onPressed: _decoding ? null : _cancel,
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: scanning
                ? AppButton(
                    key: _key('show_qr'),
                    expand: true,
                    variant: AppButtonVariant.secondary,
                    onPressed: _decoding ? null : _backToQr,
                    child: const Text('Show QR'),
                  )
                : AppButton(
                    key: _key('next'),
                    expand: true,
                    onPressed: _stage == _SignStage.showQr
                        ? _startScanning
                        : null,
                    trailing: const AppIcon(AppIcons.chevronForward),
                    child: const Text('Next step'),
                  ),
          ),
        ],
      ),
    );
  }
}
