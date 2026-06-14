import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Colors, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../rust/api/keystone.dart' as rust_keystone;
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../../services/camera_permission_settings.dart';
import '../../../../services/qr_scanner.dart';
import '../../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../../services/sapling_params.dart';
import '../../services/send_flow.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanCameraErrorOverlay, MobileScanViewfinderCorners;
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

enum _SignStage { preparing, showQr, scanning, failed }

/// Mobile Keystone signing — Figma `Keystone Scan Windget` / `Keystone
/// Scan Error` (4654:73731 / 4654:73823): the redacted PCZT plays as an
/// animated QR for the device to scan ("Next step"), then the camera
/// reads the signed PCZT back. Pops [KeystoneBroadcastArgs] on success
/// and `null` on cancel; the caller owns broadcast and proposal
/// cleanup (the proposal is consumed here once the PCZT is created —
/// the caller's discard is idempotent either way).
class MobileKeystoneSignScreen extends ConsumerStatefulWidget {
  const MobileKeystoneSignScreen({required this.args, super.key});

  final SendReviewArgs args;

  @override
  ConsumerState<MobileKeystoneSignScreen> createState() =>
      _MobileKeystoneSignScreenState();
}

class _MobileKeystoneSignScreenState
    extends ConsumerState<MobileKeystoneSignScreen>
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

  /// Same pipeline as the desktop review screen: params → create →
  /// redact + encode (QR up fast) → proofs in the background.
  Future<void> _preparePczt() async {
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final saplingParams = await loadSaplingParamsStatus();

      if (widget.args.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _confirmSaplingParamsDownload();
        if (!confirmed) {
          if (!mounted) return;
          context.pop();
          return;
        }
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('MobileKeystoneSign: $message'),
        );
      }

      if (!mounted) return;
      final currentParams = await loadSaplingParamsStatus();

      final pcztBytes = await rust_sync.createPcztFromProposal(
        dbPath: dbPath,
        network: endpoint.networkName,
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
      );

      final redactedPczt = await rust_sync.redactPcztForSigner(
        pcztBytes: pcztBytes,
      );
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: redactedPczt,
        maxFragmentLen: BigInt.from(140),
      );

      if (!mounted) return;
      setState(() {
        _stage = _SignStage.showQr;
        _urParts = urParts;
      });

      final pcztWithProofs = await rust_sync.addProofsToPczt(
        pcztBytes: pcztBytes,
        spendParamsPath: widget.args.needsSaplingParams
            ? currentParams.spendPath
            : null,
        outputParamsPath: widget.args.needsSaplingParams
            ? currentParams.outputPath
            : null,
      );
      if (!mounted) return;
      setState(() => _pcztWithProofs = pcztWithProofs);
    } catch (e, st) {
      log('MobileKeystoneSign._preparePczt: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        if (_stage == _SignStage.showQr) {
          // The QR is already on screen, so only proving failed.
          _proofsFailed = true;
        }
        _stage = _SignStage.failed;
        _error = _friendlyError(e.toString());
      });
    }
  }

  Future<bool> _confirmSaplingParamsDownload() async {
    if (!mounted) return false;
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (_) => const MobileSaplingParamsSheet(),
    );
    return confirmed == true;
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be signed.';
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    return 'Keystone signing could not be prepared. Go back and try again.';
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
      log('MobileKeystoneSign: failed to open camera permission settings');
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
      log('MobileKeystoneSign: camera settings return retry error: $e\n$st');
    }
  }

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _scanHint = null;
    });
    try {
      final signedPczt = await rust_keystone.decodePcztFromCbor(
        cbor: result.data,
      );
      // The signed half is useless without the proofs half — wait for
      // the background proving to land before handing both back.
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
      context.pop(
        KeystoneBroadcastArgs(
          reviewArgs: widget.args,
          pcztWithProofsBytes: pcztWithProofs,
          pcztWithSignaturesBytes: Uint8List.fromList(signedPczt),
        ),
      );
    } catch (e, st) {
      log('MobileKeystoneSign: signed PCZT decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _scanHint =
            'This QR code could not be decoded as a Keystone signature.';
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

  void _cancel() => context.pop();

  @override
  Widget build(BuildContext context) {
    final scanning = _stage == _SignStage.scanning;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
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
                        label: 'Cancel signing',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _cancel,
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
    );
  }

  Widget _buildQrStage() {
    final colors = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          children: [
            const SizedBox(height: 72),
            Text(
              'Confirm transaction',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Use your Keystone wallet to scan this transaction QR code. '
              'Follow the steps on your device.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: const Color(0xCCFFFFFF),
              ),
            ),
            const Spacer(),
            Container(
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
              ),
            ),
            const Spacer(),
            // Space for the bottom bar in the outer stack.
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
        // Dark scrim with a clear viewfinder window, same treatment as
        // the address scanner.
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
                  ? 'Reading signature...'
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
              key: const ValueKey('mobile_keystone_sign_cancel'),
              expand: true,
              variant: AppButtonVariant.ghost,
              onPressed: _cancel,
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
                    key: const ValueKey('mobile_keystone_sign_show_qr'),
                    expand: true,
                    variant: AppButtonVariant.secondary,
                    onPressed: _decoding ? null : _backToQr,
                    child: const Text('Show QR'),
                  )
                : AppButton(
                    key: const ValueKey('mobile_keystone_sign_next'),
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
