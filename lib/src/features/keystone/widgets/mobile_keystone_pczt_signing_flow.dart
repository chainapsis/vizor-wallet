import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart';
import '../../address_scan/widgets/mobile_address_scan_card.dart'
    show MobileQrScanCard;
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

const _mobileKeystoneQrSize = 321.0;
const _mobileKeystoneMinQrSize = 200.0;
const _mobileKeystoneModalMaxWidth = 393.0;
const _mobileKeystoneModalBottomPadding = AppSpacing.base;
const _mobileKeystoneQrInset = AppSpacing.xxs;
const _mobileKeystoneScanCaption = 'Scan a Zcash QR code to continue';

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
    @visibleForTesting this.signedPcztDecoder,
    @visibleForTesting this.scannerBuilder,
    @visibleForTesting this.forceScannerActiveForTesting = false,
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
  final MobileKeystonePcztDecoder? signedPcztDecoder;
  final MobileKeystonePcztScannerBuilder? scannerBuilder;
  final bool forceScannerActiveForTesting;

  @override
  ConsumerState<MobileKeystonePcztSigningFlow> createState() =>
      _MobileKeystonePcztSigningFlowState();
}

class _MobileKeystonePcztSigningFlowState
    extends ConsumerState<MobileKeystonePcztSigningFlow> {
  var _stage = _SignStage.preparing;
  String? _error;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  bool _proofsFailed = false;
  bool _decoding = false;
  int _scanProgress = 0;
  int _scanSessionResetToken = 0;
  String? _scanHint;

  MobileScannerController? _scanController;

  @override
  void initState() {
    super.initState();
    unawaited(_preparePczt());
  }

  @override
  void dispose() {
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
    context.pop();
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

  @override
  Widget build(BuildContext context) {
    final scanning = _stage == _SignStage.scanning;
    final modal = scanning ? _buildScannerModal() : _buildQrModal();
    return PopScope<void>(
      canPop: !_decoding,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: SizedBox.expand(
        key: _key('screen'),
        child: Align(alignment: Alignment.bottomCenter, child: modal),
      ),
    );
  }

  Widget _buildQrModal() {
    final colors = context.colors;
    final title = _stage == _SignStage.failed
        ? widget.failedTitle ?? widget.title
        : 'Confirm with Keystone';
    final actionEnabled = _stage == _SignStage.showQr;
    final isPreparing = _stage == _SignStage.preparing;
    final isFailed = _stage == _SignStage.failed;
    final instruction = isPreparing
        ? 'Loading the QR code ...'
        : isFailed
        ? _error ?? widget.friendlyError(StateError('Keystone signing failed.'))
        : 'After you scanned, click Get signature.';

    final surface = Stack(
      key: _key('modal_surface'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            _mobileKeystoneModalBottomPadding,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final qrSize = _qrSizeFor(constraints);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Scan with your Keystone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 44),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _mobileKeystoneQrInset,
                    ),
                    child: _buildQrContent(size: qrSize),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    instruction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isFailed
                          ? colors.text.destructive
                          : colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  AppButton(
                    key: _key('get_signature'),
                    expand: true,
                    onPressed: actionEnabled ? _startScanning : null,
                    child: const Text('Get signature'),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    key: _key('cancel'),
                    expand: true,
                    variant: AppButtonVariant.ghost,
                    onPressed: _cancel,
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          ),
        ),
        Positioned(
          top: 15.5,
          right: AppSpacing.sm,
          child: _KeystoneModalCloseButton(onTap: _cancel),
        ),
      ],
    );
    return _buildModalFrame(surface);
  }

  Widget _buildModalFrame(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _mobileKeystoneModalMaxWidth),
      child: Stack(
        key: _key('modal'),
        children: [MobileModalCard(child: child)],
      ),
    );
  }

  double _qrSizeFor(BoxConstraints constraints) {
    const titleBlockHeight = 26.0 + AppSpacing.xxs + 25.0;
    const instructionBlockHeight = 25.0;
    const fixedContentHeight =
        titleBlockHeight +
        44.0 +
        AppSpacing.sm +
        instructionBlockHeight +
        AppSpacing.base +
        AppButtonSizing.largeHeight +
        AppSpacing.s +
        AppButtonSizing.largeHeight;
    final available = constraints.maxHeight - fixedContentHeight;
    return available
        .clamp(_mobileKeystoneMinQrSize, _mobileKeystoneQrSize)
        .toDouble();
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
      frameInterval: const Duration(milliseconds: 100),
    );
  }

  Widget _buildScannerModal() {
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
                  : _mobileKeystoneScanCaption);

    return _buildModalFrame(
      MobileQrScanCard(
        key: _key('scanner_card'),
        controller: scanController,
        closeEnabled: !_decoding,
        forceActiveForTesting: widget.forceScannerActiveForTesting,
        caption: caption,
        permissionTitle: 'Scan the signed Keystone QR',
        unavailableDescription:
            'Keystone signing needs a camera on this device.',
        onClose: _cancel,
        cameraViewBuilder: (_, _) => scannerView,
      ),
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
    final colors = context.colors;
    final base = colors.background.raised;
    final highlight = colors.background.overlay.withValues(alpha: 0.72);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final bandHeight = widget.size * 0.72;
        final travel = widget.size + bandHeight * 2;
        final top = -bandHeight + travel * _controller.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.large),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(decoration: BoxDecoration(color: base)),
                Positioned(
                  left: 0,
                  right: 0,
                  top: top,
                  height: bandHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          base.withValues(alpha: 0),
                          highlight,
                          base.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.5, 1],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KeystoneModalCloseButton extends StatelessWidget {
  const _KeystoneModalCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Close Keystone signing',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.button.secondary.bg,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(AppIcons.cross, size: 20, color: colors.icon.accent),
          ),
        ),
      ),
    );
  }
}

Future<Uint8List> _decodeSignedPcztFromCbor(List<int> cbor) async {
  final signedPcztBytes = await rust_keystone.decodePcztFromCbor(cbor: cbor);
  return Uint8List.fromList(signedPcztBytes);
}
