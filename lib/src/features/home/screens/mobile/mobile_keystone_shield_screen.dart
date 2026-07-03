import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Colors, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/rpc_endpoint_config.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/keystone.dart' as rust_keystone;
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../../services/camera_permission_settings.dart';
import '../../../../services/qr_scanner.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanCameraErrorOverlay, MobileScanViewfinderCorners;
import '../../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../../send/services/sapling_params.dart';
import '../../services/transparent_shielding_service.dart';

enum _ShieldSignStage {
  preparing,
  showQr,
  scanning,
  broadcasting,
  failed,
  broadcastWarning,
}

class MobileKeystoneShieldResult {
  const MobileKeystoneShieldResult._({required this.succeeded, this.message});

  const MobileKeystoneShieldResult.succeeded() : this._(succeeded: true);

  const MobileKeystoneShieldResult.warning(String message)
    : this._(succeeded: false, message: message);

  final bool succeeded;
  final String? message;
}

class MobileKeystoneShieldScreen extends ConsumerStatefulWidget {
  const MobileKeystoneShieldScreen({super.key});

  @override
  ConsumerState<MobileKeystoneShieldScreen> createState() =>
      _MobileKeystoneShieldScreenState();
}

class _MobileKeystoneShieldScreenState
    extends ConsumerState<MobileKeystoneShieldScreen>
    with WidgetsBindingObserver {
  var _stage = _ShieldSignStage.preparing;
  String? _error;
  String? _statusMessage;
  List<String> _urParts = const [];
  Uint8List? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;
  bool _needsSaplingParams = false;
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
      final accountUuid = activeShieldingAccountUuid(ref);
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final shieldPczt = await rust_sync.createShieldTransparentPczt(
        dbPath: dbPath,
        network: endpoint.walletNetworkName,
        accountUuid: accountUuid,
      );

      var saplingParams = await loadSaplingParamsStatus();
      if (shieldPczt.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _confirmSaplingParamsDownload();
        if (!confirmed) {
          if (!mounted) return;
          context.pop();
          return;
        }
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('MobileKeystoneShield: $message'),
        );
        saplingParams = await loadSaplingParamsStatus();
      }

      final redactedPczt = await rust_sync.redactPcztForSigner(
        pcztBytes: shieldPczt.pcztBytes,
      );
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: redactedPczt,
        maxFragmentLen: BigInt.from(140),
      );

      if (!mounted) return;
      setState(() {
        _stage = _ShieldSignStage.showQr;
        _saplingParams = saplingParams;
        _needsSaplingParams = shieldPczt.needsSaplingParams;
        _urParts = urParts;
      });

      final pcztWithProofs = await rust_sync.addProofsToPczt(
        pcztBytes: shieldPczt.pcztBytes,
        spendParamsPath: shieldPczt.needsSaplingParams
            ? saplingParams.spendPath
            : null,
        outputParamsPath: shieldPczt.needsSaplingParams
            ? saplingParams.outputPath
            : null,
      );
      if (!mounted) return;
      setState(() => _pcztWithProofs = pcztWithProofs);
    } catch (e, st) {
      log('MobileKeystoneShield._preparePczt: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        if (_stage == _ShieldSignStage.showQr) {
          _proofsFailed = true;
        }
        _stage = _ShieldSignStage.failed;
        _error = _friendlyError(e);
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

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    if (lower.contains('pczt') || lower.contains('signature')) {
      return 'Keystone signature could not be applied.';
    }
    if (lower.contains('extract')) {
      return 'Shield transaction could not be finalized.';
    }
    return friendlyShieldBalanceError(error);
  }

  void _startScanning() {
    _scanController ??= MobileScannerController(
      facing: CameraFacing.back,
      formats: QrScanner.formats,
      detectionSpeed: QrScanner.detectionSpeed,
    );
    setState(() {
      _stage = _ShieldSignStage.scanning;
      _scanHint = null;
      _scanProgress = 0;
    });
  }

  void _backToQr() {
    setState(() {
      _stage = _ShieldSignStage.showQr;
      _scanHint = null;
      _scanProgress = 0;
    });
  }

  Future<void> _openCameraSettings() async {
    _restartCameraOnResume = true;
    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      _restartCameraOnResume = false;
      log('MobileKeystoneShield: failed to open camera permission settings');
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
      log('MobileKeystoneShield: camera settings return retry error: $e\n$st');
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
      while (mounted && _pcztWithProofs == null && !_proofsFailed) {
        if (_stage == _ShieldSignStage.failed) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final pcztWithProofs = _pcztWithProofs;
      final saplingParams = _saplingParams;
      if (!mounted) return;
      if (pcztWithProofs == null || saplingParams == null) {
        setState(() {
          _decoding = false;
          _stage = _ShieldSignStage.failed;
          _error ??= 'Keystone signing could not be prepared.';
        });
        return;
      }
      await _broadcast(
        pcztWithProofs: pcztWithProofs,
        signatures: Uint8List.fromList(signedPczt),
        saplingParams: saplingParams,
      );
    } catch (e, st) {
      log('MobileKeystoneShield: signed PCZT decode error: $e\n$st');
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
        ? 'Open the signed shield QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_scanHint == message) return;
    setState(() => _scanHint = message);
  }

  Future<void> _broadcast({
    required Uint8List pcztWithProofs,
    required Uint8List signatures,
    required SaplingParamsStatus saplingParams,
  }) async {
    setState(() {
      _stage = _ShieldSignStage.broadcasting;
      _error = null;
      _statusMessage = null;
    });

    RpcEndpointConfig? attemptedEndpoint;
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      attemptedEndpoint = endpoint;
      final result = await rust_sync.extractAndBroadcastPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.walletNetworkName,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signatures,
        spendParamsPath: _needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: _needsSaplingParams ? saplingParams.outputPath : null,
      );
      log(
        'MobileKeystoneShield: broadcast shield txid=${result.txid} '
        'status=${result.status}',
      );

      if (result.status != 'broadcasted' && result.message != null) {
        await _maybeSwitchBroadcastEndpoint(result.message!, attemptedEndpoint);
      }

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('MobileKeystoneShield: refreshAfterSend failed: $e');
      }
      if (!mounted) return;
      if (result.status != 'broadcasted') {
        setState(() {
          _stage = _ShieldSignStage.broadcastWarning;
          _statusMessage = shieldPcztBroadcastStatusMessage(result);
        });
        return;
      }
      context.pop(const MobileKeystoneShieldResult.succeeded());
    } catch (e, st) {
      log('MobileKeystoneShield._broadcast: ERROR: $e\n$st');
      await _maybeSwitchBroadcastEndpoint(e, attemptedEndpoint);
      if (!mounted) return;
      final postBroadcastMessage = postBroadcastShieldErrorMessage(e);
      if (postBroadcastMessage != null) {
        setState(() {
          _stage = _ShieldSignStage.broadcastWarning;
          _statusMessage = postBroadcastMessage;
        });
        return;
      }
      setState(() {
        _stage = _ShieldSignStage.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _maybeSwitchBroadcastEndpoint(
    Object error,
    RpcEndpointConfig? attemptedEndpoint,
  ) async {
    final switched = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          error,
          endpoint: attemptedEndpoint,
          operation: 'mobile keystone shield broadcast',
        );
    if (switched) {
      unawaited(ref.read(syncProvider.notifier).restartSync());
    }
  }

  void _cancel() {
    if (_stage == _ShieldSignStage.broadcasting) return;
    context.pop();
  }

  void _finishWarningOrFailure() {
    final message = _statusMessage;
    if (_stage == _ShieldSignStage.broadcastWarning &&
        message != null &&
        message.isNotEmpty) {
      context.pop(MobileKeystoneShieldResult.warning(message));
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scanning = _stage == _ShieldSignStage.scanning;
    return PopScope<void>(
      canPop: _stage != _ShieldSignStage.broadcasting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
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
      ),
    );
  }

  Widget _buildQrStage() {
    final colors = context.colors;
    final error = _stage == _ShieldSignStage.broadcastWarning
        ? _statusMessage ??
              'The shield transaction status is uncertain. Check activity before trying again.'
        : _error;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          children: [
            const SizedBox(height: 72),
            Text(
              _stage == _ShieldSignStage.broadcasting
                  ? 'Broadcasting shield tx'
                  : 'Shield transparent balance',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              _stage == _ShieldSignStage.broadcasting
                  ? 'Keep Vizor open while the transaction is sent.'
                  : 'Use your Keystone wallet to scan this shielding QR code. Follow the steps on your device.',
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
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.background.ground,
                    borderRadius: BorderRadius.circular(AppRadii.large),
                  ),
                  child: KeystonePcztQrStage(
                    phase: switch (_stage) {
                      _ShieldSignStage.showQr => KeystonePcztQrStagePhase.ready,
                      _ShieldSignStage.failed ||
                      _ShieldSignStage.broadcastWarning =>
                        KeystonePcztQrStagePhase.failed,
                      _ => KeystonePcztQrStagePhase.preparing,
                    },
                    urParts: _urParts,
                    error: error,
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
    final scanning = _stage == _ShieldSignStage.scanning;
    final terminal =
        _stage == _ShieldSignStage.failed ||
        _stage == _ShieldSignStage.broadcastWarning;
    if (terminal) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.s,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: AppButton(
          expand: true,
          onPressed: _finishWarningOrFailure,
          child: const Text('Back to wallet'),
        ),
      );
    }

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
              expand: true,
              variant: AppButtonVariant.ghost,
              onPressed: _stage == _ShieldSignStage.broadcasting
                  ? null
                  : _cancel,
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
                    expand: true,
                    variant: AppButtonVariant.secondary,
                    onPressed: _decoding ? null : _backToQr,
                    child: const Text('Show QR'),
                  )
                : AppButton(
                    expand: true,
                    onPressed: _stage == _ShieldSignStage.showQr
                        ? _startScanning
                        : null,
                    trailing: _stage == _ShieldSignStage.broadcasting
                        ? const AppIcon(AppIcons.loader)
                        : const AppIcon(AppIcons.chevronForward),
                    child: Text(
                      _stage == _ShieldSignStage.broadcasting
                          ? 'Broadcasting...'
                          : 'Next step',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
