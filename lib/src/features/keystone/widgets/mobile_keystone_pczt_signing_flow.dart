import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Colors, Icons, TextDecoration;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/mobile_top_nav.dart'
    show kMobileTopNavHeight;
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

typedef MobileKeystonePcztDecoder = Future<Uint8List> Function(List<int> cbor);

typedef MobileKeystonePcztScannerBuilder =
    Widget Function(
      BuildContext context,
      ValueChanged<ScanResult> onComplete,
      Object? scanSessionResetToken,
    );

enum _SignStage { preparing, showQr, scanning, failed }

const _mobileKeystoneQrFrameSize = 320.0;
const _mobileKeystoneDesignWidth = 393.0;
const _mobileKeystoneDesignHeight = 852.0;
const _mobileKeystoneScanWindowSize = 285.0;
const _mobileKeystoneScanWindowTop = 293.0;
const _mobileKeystoneScanWindowCenterXOffset = 1.0;
const _mobileKeystoneScanCaptionTop = 628.0;
const _mobileKeystoneScanCaptionWidth = 263.0;
const _mobileKeystoneScanActionTop = 762.0;
const _mobileKeystoneScanActionInset = AppSpacing.base;
const _mobileKeystoneScanActionSize = 40.0;
const _mobileKeystoneFlashlightIconSize = 30.0;
const _mobileKeystoneQrActionIconSize = 26.0;
const _mobileKeystoneProgressTrackWidth = 196.0;
const _mobileKeystoneStepOneProgress = 0.5;
const _mobileKeystoneStepTwoProgress = 1.0;
const _mobileKeystoneScanCaption =
    'Scan the QR code on your Keystone to confirm';
const _mobileKeystoneTitleTopGap = AppSpacing.s;
const _mobileKeystoneQrPromptGap = AppSpacing.base;
const _mobileKeystonePromptBlockHeight = 56.0;
const _mobileKeystonePromptLineGap = 2.0;
const _mobileKeystonePromptInlineGap = 6.0;
const _mobileKeystoneLightText = Color(0xFFFFFFFF);
const _mobileKeystoneOrange = Color(0xFFF98F0E);

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
    this.scanCaption = _mobileKeystoneScanCaption,
    this.stepOneProgress = _mobileKeystoneStepOneProgress,
    this.stepTwoProgress = _mobileKeystoneStepTwoProgress,
    this.logTag = 'MobileKeystonePcztSigningFlow',
    this.onCancel,
    this.signedPcztDecoder,
    this.scannerBuilder,
    this.forceScannerActiveForTesting = false,
    this.startInScannerForTesting = false,
    super.key,
  });

  final String title;
  final String? failedTitle;
  final String description;
  final String keyPrefix;
  final String readingSignatureLabel;
  final String? finalizingSignatureLabel;
  final String scanCaption;
  final double stepOneProgress;
  final double stepTwoProgress;
  final String logTag;
  final VoidCallback? onCancel;
  final MobileKeystonePcztPrepare preparePczt;
  final MobileKeystonePcztSigned onSigned;
  final MobileKeystonePcztFriendlyError friendlyError;
  final MobileKeystonePcztDecoder? signedPcztDecoder;
  final MobileKeystonePcztScannerBuilder? scannerBuilder;
  final bool forceScannerActiveForTesting;
  final bool startInScannerForTesting;

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
  int _scanSessionResetToken = 0;
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
        _stage = widget.startInScannerForTesting
            ? _SignStage.scanning
            : _SignStage.showQr;
        _urParts = payload.urParts;
        _error = null;
        if (widget.startInScannerForTesting) _ensureScanController();
      });
      unawaited(_waitForProofs(payload.pcztWithProofs));
    } on MobileKeystonePcztSigningAborted {
      if (!mounted) return;
      _dismiss();
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
    _ensureScanController();
    setState(() {
      _stage = _SignStage.scanning;
      _scanHint = null;
      _scanProgress = 0;
    });
  }

  void _ensureScanController() {
    _scanController ??= MobileScannerController(
      facing: CameraFacing.back,
      formats: QrScanner.formats,
      detectionSpeed: QrScanner.detectionSpeed,
    );
  }

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding || _stage != _SignStage.scanning) return;
    setState(() {
      _decoding = true;
      _scanHint = widget.readingSignatureLabel;
    });

    late final Uint8List signedPczt;
    try {
      final decoder = widget.signedPcztDecoder ?? _decodeSignedPcztFromCbor;
      signedPczt = await decoder(result.data);
    } catch (e, st) {
      log('${widget.logTag}: signed PCZT decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _scanSessionResetToken++;
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
      _stopScannerIfRunning();
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
    _dismiss();
  }

  void _dismiss() {
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      onCancel();
      return;
    }
    context.pop();
  }

  void _backToQr() {
    if (_decoding) return;
    _stopScannerIfRunning();
    setState(() {
      _stage = _SignStage.showQr;
      _scanHint = null;
      _scanProgress = 0;
      _scanSessionResetToken++;
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
        !QrScanner.isAvailable ||
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

  void _stopScannerIfRunning() {
    final scanController = _scanController;
    if (scanController == null || !scanController.value.isRunning) return;
    unawaited(
      scanController.stop().catchError((Object e, StackTrace st) {
        log(
          '${widget.logTag}: scanner stop error after signing failure: $e\n$st',
        );
      }),
    );
  }

  ValueKey<String> _key(String suffix) {
    return ValueKey('${widget.keyPrefix}_$suffix');
  }

  double get _activeProgress {
    return switch (_stage) {
      _SignStage.scanning => widget.stepTwoProgress,
      _ => widget.stepOneProgress,
    };
  }

  @override
  Widget build(BuildContext context) {
    final child = _stage == _SignStage.scanning
        ? _buildScannerPage()
        : _buildQrPage();
    return PopScope<void>(
      canPop: !_decoding,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: SizedBox.expand(key: _key('screen'), child: child),
      ),
    );
  }

  Widget _buildQrPage() {
    final colors = context.colors;
    final actionEnabled = _stage == _SignStage.showQr;
    final isPreparing = _stage == _SignStage.preparing;
    final isFailed = _stage == _SignStage.failed;
    final title = isFailed ? widget.failedTitle ?? widget.title : 'Step 1/2';
    final subtitle = isFailed ? widget.description : 'Scan with Keystone';
    final message = isPreparing
        ? 'Loading QR code ...'
        : isFailed
        ? _error ?? widget.friendlyError(StateError('Keystone signing failed.'))
        : null;

    return ColoredBox(
      color: colors.background.window,
      child: SafeArea(
        child: Column(
          children: [
            _KeystoneSigningTopNav(
              color: colors.icon.accent,
              trackColor: colors.background.overlay,
              fillColor: colors.background.inverse,
              progress: _activeProgress,
              trackKey: _key('progress_track'),
              fillKey: _key('progress_fill'),
              onBack: _cancel,
            ),
            const SizedBox(height: _mobileKeystoneTitleTopGap),
            _KeystoneSigningTitle(
              title: title,
              subtitle: subtitle,
              titleColor: colors.text.accent,
              subtitleColor: colors.text.accent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableForQr =
                        constraints.maxHeight -
                        _mobileKeystoneQrPromptGap -
                        _mobileKeystonePromptBlockHeight;
                    final frameSize = math
                        .min(
                          _mobileKeystoneQrFrameSize,
                          math.min(constraints.maxWidth, availableForQr),
                        )
                        .clamp(120.0, _mobileKeystoneQrFrameSize)
                        .toDouble();

                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildQrFrame(frameSize: frameSize),
                          const SizedBox(height: _mobileKeystoneQrPromptGap),
                          if (message != null)
                            _KeystoneSigningPromptText(
                              text: message,
                              color: isFailed
                                  ? colors.text.destructive
                                  : colors.text.primary,
                            )
                          else
                            _KeystoneScanPrompt(color: colors.text.primary),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.base,
              ),
              child: Column(
                key: _key('actions'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    key: _key('get_signature'),
                    expand: true,
                    onPressed: actionEnabled ? _startScanning : null,
                    trailing: const AppIcon(AppIcons.chevronForward, size: 20),
                    child: const Text('Next step'),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    key: _key('cancel'),
                    expand: true,
                    variant: AppButtonVariant.ghost,
                    onPressed: _cancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrFrame({required double frameSize}) {
    final showPlaceholder =
        _stage == _SignStage.preparing ||
        (_stage == _SignStage.failed && _urParts.isEmpty);
    if (showPlaceholder) {
      return ClipRRect(
        key: _key('qr_frame'),
        borderRadius: BorderRadius.circular(24),
        child: SizedBox.square(
          dimension: frameSize,
          child: _MobileKeystoneQrPlaceholder(
            key: _key('qr_placeholder'),
            size: frameSize,
          ),
        ),
      );
    }

    return ClipRRect(
      key: _key('qr_frame'),
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox.square(
          dimension: frameSize,
          child: _buildQrContent(size: frameSize),
        ),
      ),
    );
  }

  Widget _buildQrContent({required double size}) {
    if (_stage == _SignStage.preparing ||
        (_stage == _SignStage.failed && _urParts.isEmpty)) {
      return _MobileKeystoneQrPlaceholder(
        key: _key('qr_placeholder'),
        size: size,
      );
    }

    return KeystonePcztQrStage(
      key: _key('qr_stage'),
      phase: switch (_stage) {
        _SignStage.showQr => KeystonePcztQrStagePhase.ready,
        _SignStage.failed => KeystonePcztQrStagePhase.ready,
        _ => KeystonePcztQrStagePhase.preparing,
      },
      urParts: _urParts,
      error: null,
      size: size,
      scanOptimized: true,
      quietZone: const PrettyQrQuietZone.modules(3),
      frameInterval: const Duration(milliseconds: 100),
    );
  }

  Widget _buildScannerPage() {
    final scanController = _scanController;
    if (scanController == null) return const SizedBox.shrink();
    final scanSessionResetToken = (_stage, _scanSessionResetToken);
    final scannerView =
        widget.scannerBuilder?.call(
          context,
          (result) => unawaited(_handleScanComplete(result)),
          scanSessionResetToken,
        ) ??
        AnimatedUrScannerView(
          controller: scanController,
          expectedUrType: 'zcash-pczt',
          scanSessionResetToken: scanSessionResetToken,
          errorBuilder: (context, error) => const SizedBox.shrink(),
          onProgress: (progress) {
            if (!mounted || _scanProgress == progress) return;
            setState(() => _scanProgress = progress);
          },
          onDecodeError: _handleDecodeError,
          onComplete: (result) => unawaited(_handleScanComplete(result)),
        );

    final caption = _decoding
        ? _scanHint ?? widget.readingSignatureLabel
        : _scanHint ??
              (_scanProgress > 0
                  ? 'Scanning... $_scanProgress%'
                  : widget.scanCaption);

    return ColoredBox(
      key: _key('scanner_card'),
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewfinderLeft =
              ((constraints.maxWidth - _mobileKeystoneScanWindowSize) / 2) +
              _mobileKeystoneScanWindowCenterXOffset;
          final captionLeft =
              (constraints.maxWidth - _mobileKeystoneScanCaptionWidth) / 2;
          final actionInset =
              ((constraints.maxWidth - _mobileKeystoneDesignWidth) / 2) +
              _mobileKeystoneScanActionInset;

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: scannerView),
              const _KeystoneScannerScrim(),
              Positioned(
                left: viewfinderLeft.clamp(
                  0.0,
                  math.max(
                    0.0,
                    constraints.maxWidth - _mobileKeystoneScanWindowSize,
                  ),
                ),
                top: _scannerTopFor(
                  constraints,
                  designTop: _mobileKeystoneScanWindowTop,
                  height: _mobileKeystoneScanWindowSize,
                ),
                width: _mobileKeystoneScanWindowSize,
                height: _mobileKeystoneScanWindowSize,
                child: SizedBox(
                  key: _key('scan_viewfinder'),
                  width: _mobileKeystoneScanWindowSize,
                  height: _mobileKeystoneScanWindowSize,
                  child: const MobileScanViewfinderCorners(
                    cornerLength: 60,
                    cornerRadius: 32,
                    strokeWidth: 6,
                  ),
                ),
              ),
              if (!widget.forceScannerActiveForTesting)
                MobileScanCameraErrorOverlay(
                  controller: scanController,
                  maxWidth: _mobileKeystoneScanWindowSize,
                  permissionDeniedMessage:
                      'Camera access is off. Allow it in Settings to scan Keystone signatures.',
                  unavailableMessage: 'The camera is unavailable right now.',
                  onOpenSettings: _openCameraSettings,
                ),
              SafeArea(
                child: Column(
                  children: [
                    _KeystoneSigningTopNav(
                      color: _mobileKeystoneLightText,
                      trackColor: _mobileKeystoneLightText.withValues(
                        alpha: 0.32,
                      ),
                      fillColor: _mobileKeystoneLightText,
                      progress: _activeProgress,
                      trackKey: _key('progress_track'),
                      fillKey: _key('progress_fill'),
                      onBack: _cancel,
                    ),
                    const SizedBox(height: _mobileKeystoneTitleTopGap),
                    const _KeystoneSigningTitle(
                      title: 'Step 2/2',
                      subtitle: 'Confirm with Keystone',
                      titleColor: _mobileKeystoneLightText,
                      subtitleColor: _mobileKeystoneLightText,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: captionLeft.clamp(
                  AppSpacing.sm,
                  math.max(
                    AppSpacing.sm,
                    constraints.maxWidth -
                        _mobileKeystoneScanCaptionWidth -
                        AppSpacing.sm,
                  ),
                ),
                top: _scannerTopFor(
                  constraints,
                  designTop: _mobileKeystoneScanCaptionTop,
                  height: 75,
                ),
                width: _mobileKeystoneScanCaptionWidth,
                child: SizedBox(
                  key: _key('scan_caption'),
                  width: _mobileKeystoneScanCaptionWidth,
                  child: _KeystoneSigningPromptText(
                    text: caption,
                    color: _mobileKeystoneLightText,
                    maxLines: 3,
                  ),
                ),
              ),
              Positioned(
                top: _scannerTopFor(
                  constraints,
                  designTop: _mobileKeystoneScanActionTop,
                  height: _mobileKeystoneScanActionSize,
                ),
                left: actionInset.clamp(
                  AppSpacing.sm,
                  math.max(
                    AppSpacing.sm,
                    constraints.maxWidth -
                        (AppSpacing.sm * 2) -
                        _mobileKeystoneScanActionSize,
                  ),
                ),
                child: _KeystoneScannerIconButton(
                  controlKey: _key('flashlight_action'),
                  semanticLabel: 'Toggle flashlight',
                  onTap: () => unawaited(scanController.toggleTorch()),
                  child: const Icon(
                    Icons.flashlight_on_outlined,
                    color: _mobileKeystoneLightText,
                    size: _mobileKeystoneFlashlightIconSize,
                  ),
                ),
              ),
              Positioned(
                top: _scannerTopFor(
                  constraints,
                  designTop: _mobileKeystoneScanActionTop,
                  height: _mobileKeystoneScanActionSize,
                ),
                right: actionInset.clamp(
                  AppSpacing.sm,
                  math.max(
                    AppSpacing.sm,
                    constraints.maxWidth -
                        (AppSpacing.sm * 2) -
                        _mobileKeystoneScanActionSize,
                  ),
                ),
                child: _KeystoneScannerIconButton(
                  controlKey: _key('qr_action'),
                  semanticLabel: 'Show transaction QR',
                  onTap: _decoding ? null : _backToQr,
                  child: AppIcon(
                    AppIcons.qr,
                    color: _mobileKeystoneLightText.withValues(
                      alpha: _decoding ? 0.4 : 1,
                    ),
                    size: _mobileKeystoneQrActionIconSize,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _scannerTopFor(
    BoxConstraints constraints, {
    required double designTop,
    required double height,
  }) {
    final scaledTop =
        designTop * (constraints.maxHeight / _mobileKeystoneDesignHeight);
    return scaledTop.clamp(
      0.0,
      math.max(0.0, constraints.maxHeight - height - AppSpacing.xxs),
    );
  }
}

class _MobileKeystoneQrPlaceholder extends StatefulWidget {
  const _MobileKeystoneQrPlaceholder({required this.size, super.key});

  final double size;

  @override
  State<_MobileKeystoneQrPlaceholder> createState() =>
      _MobileKeystoneQrPlaceholderState();
}

class _MobileKeystoneQrPlaceholderState
    extends State<_MobileKeystoneQrPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        const base = Color(0x26E1E1E1);
        const highlight = Color(0xFFD4D4D4);
        final bandHeight = widget.size * 0.78;
        final travel = widget.size + bandHeight * 2;
        final top = -bandHeight + travel * _controller.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(color: Color(0x40FFFFFF)),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: top,
                height: bandHeight,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [base, highlight, base],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KeystoneSigningTopNav extends StatelessWidget {
  const _KeystoneSigningTopNav({
    required this.color,
    required this.trackColor,
    required this.fillColor,
    required this.progress,
    required this.onBack,
    this.trackKey,
    this.fillKey,
  });

  final Color color;
  final Color trackColor;
  final Color fillColor;
  final double progress;
  final VoidCallback onBack;
  final Key? trackKey;
  final Key? fillKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMobileTopNavHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: SizedBox(
              key: trackKey,
              width: _mobileKeystoneProgressTrackWidth,
              height: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                    heightFactor: 1,
                    child: DecoratedBox(
                      key: fillKey,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.s,
            child: Semantics(
              label: 'Back',
              button: true,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: AppIcon(
                      AppIcons.chevronBackward,
                      size: 24,
                      color: color,
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

class _KeystoneSigningTitle extends StatelessWidget {
  const _KeystoneSigningTitle({
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final Color titleColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.displayLarge.copyWith(color: titleColor),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              color: subtitleColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeystoneSigningPromptText extends StatelessWidget {
  const _KeystoneSigningPromptText({
    required this.text,
    required this.color,
    this.maxLines = 2,
  });

  final String text;
  final Color color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppTypography.bodyMediumStrong.copyWith(color: color),
    );
  }
}

class _KeystoneScanPrompt extends StatelessWidget {
  const _KeystoneScanPrompt({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTypography.bodyMediumStrong.copyWith(color: color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: _mobileKeystonePromptInlineGap,
          runSpacing: _mobileKeystonePromptLineGap,
          children: [
            Text('Tap', style: textStyle),
            const _KeystoneScanPromptIcon(),
            Text('on your Keystone,', style: textStyle),
          ],
        ),
        const SizedBox(height: _mobileKeystonePromptLineGap),
        Text(
          'then scan this QR code',
          textAlign: TextAlign.center,
          style: textStyle,
        ),
      ],
    );
  }
}

class _KeystoneScanPromptIcon extends StatelessWidget {
  const _KeystoneScanPromptIcon();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _mobileKeystoneOrange,
        borderRadius: BorderRadius.circular(8.615),
      ),
      child: const SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: Center(
              child: AppIcon(
                AppIcons.keystoneScan,
                color: _mobileKeystoneLightText,
                size: 18.3335,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeystoneScannerScrim extends StatelessWidget {
  const _KeystoneScannerScrim();

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Color(0x99000000), BlendMode.srcOut),
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
              width: _mobileKeystoneScanWindowSize,
              height: _mobileKeystoneScanWindowSize,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeystoneScannerIconButton extends StatelessWidget {
  const _KeystoneScannerIconButton({
    required this.semanticLabel,
    required this.child,
    required this.onTap,
    this.controlKey,
  });

  final String semanticLabel;
  final Widget child;
  final VoidCallback? onTap;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          key: controlKey,
          dimension: _mobileKeystoneScanActionSize,
          child: Center(child: child),
        ),
      ),
    );
  }
}

Future<Uint8List> _decodeSignedPcztFromCbor(List<int> cbor) async {
  final signedPcztBytes = await rust_keystone.decodePcztFromCbor(cbor: cbor);
  return Uint8List.fromList(signedPcztBytes);
}
