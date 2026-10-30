import '../../../../core/navigation/mobile_sidebar_exit.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/rpc_endpoint_config.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/navigation/external_action_guard_hold.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/keystone.dart' as rust_keystone;
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../../services/camera_permission_settings.dart';
import '../../../../services/qr_scanner.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanCameraErrorOverlay;
import '../../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../../send/services/sapling_params.dart';
import '../../services/transparent_shielding_service.dart';
import '../../services/hardware_shielding_session.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../providers/wallet_provider.dart';
import '../../widgets/mobile/shield/mobile_shield_scene.dart';
import '../../widgets/mobile/shield/keystone_shield_morph.dart';
import '../../widgets/mobile/shield/keystone_shield_footer.dart';
import '../../widgets/mobile/shield/keystone_shield_scanner_surface.dart';
import '../../widgets/mobile/shield/mobile_shield_backdrop.dart';

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
  const MobileKeystoneShieldScreen({this.backdrop, super.key});
  final MobileShieldBackdrop? backdrop;

  @override
  ConsumerState<MobileKeystoneShieldScreen> createState() =>
      _MobileKeystoneShieldScreenState();
}

// Shows the shield PCZT QR and then scans the signed result, so the whole
// screen is a live Keystone session.
class _MobileKeystoneShieldScreenState
    extends ConsumerState<MobileKeystoneShieldScreen>
    with WidgetsBindingObserver, ExternalActionGuardHoldMixin {
  var _stage = _ShieldSignStage.preparing;
  bool _started = false;
  late final HardwareShieldingSession _session;
  bool _qrVisualReady = false;
  bool _closed = false;
  // A failed release can be retried, but signing work from before cancellation
  // must never resume once the exit has been accepted.
  bool _cancellationStarted = false;
  int _scanGeneration = 0;
  bool _done = false;
  late final String _accountUuid;
  late final String _network;
  late final BigInt _amount;
  BigInt? _shieldedAmount;
  String? _error;
  String? _statusMessage;
  List<String> _urParts = const [];
  Uint8List? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;
  bool _needsSaplingParams = false;

  /// The signature of a broadcast that waits for private recovery, kept so
  /// the user can send it again without signing again.
  Uint8List? _retrySignatures;
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
    _accountUuid = activeShieldingAccountUuid(ref);
    _session = HardwareShieldingSession.forRef(ref, _accountUuid);
    _network = ref.read(rpcEndpointFailoverProvider).current.networkName;
    final sync = (ref.read(syncProvider).value ?? SyncState()).scopedToAccount(
      _accountUuid,
    );
    _amount = sync.shieldTransparentAmount > BigInt.zero
        ? sync.shieldTransparentAmount + sync.shieldTransparentFee
        : sync.transparentBalance;
    _shieldedAmount = sync.shieldTransparentAmount;
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
    _closed = true;
    _scanGeneration++;
    unawaited(_session.close());
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_scanController?.dispose());
    super.dispose();
  }

  Future<void> _preparePczt() async {
    try {
      _requireOriginalAccount();
      final dbPath = await getWalletDbPath();
      if (!mounted || _closed || _cancellationStarted) return;
      _requireOriginalAccount();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final shieldPczt = await _session.prepare(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );

      if (!mounted || _closed || _cancellationStarted) return;
      var saplingParams = await loadSaplingParamsStatus();
      if (!mounted || _closed || _cancellationStarted) return;
      if (shieldPczt.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _confirmSaplingParamsDownload();
        if (!confirmed) {
          if (!mounted || _closed || _cancellationStarted) return;
          await _cancel();
          return;
        }
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('MobileKeystoneShield: $message'),
        );
        saplingParams = await loadSaplingParamsStatus();
      }

      if (!mounted || _closed || _cancellationStarted) return;
      final redactedPczt = await rust_sync.redactPcztForSigner(
        pcztBytes: shieldPczt.pcztBytes,
      );
      if (!mounted || _closed || _cancellationStarted) return;
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: redactedPczt,
        maxFragmentLen: BigInt.from(140),
      );

      if (!mounted || _closed || _cancellationStarted) return;
      setState(() {
        _stage = _ShieldSignStage.showQr;
        _saplingParams = saplingParams;
        _needsSaplingParams = shieldPczt.needsSaplingParams;
        _shieldedAmount = shieldPczt.shieldedZatoshi;
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
      if (!mounted || _closed || _cancellationStarted) return;
      setState(() => _pcztWithProofs = pcztWithProofs);
    } catch (e, st) {
      if (!mounted || _closed || _cancellationStarted) return;
      log('MobileKeystoneShield._preparePczt: ERROR: $e\n$st');
      await _session.close();
      if (!mounted || _closed || _cancellationStarted) return;
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
    if (_closed ||
        _cancellationStarted ||
        _stage != _ShieldSignStage.showQr ||
        !_qrVisualReady) {
      return;
    }
    _scanGeneration++;
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
    if (_closed ||
        _cancellationStarted ||
        _decoding ||
        _stage != _ShieldSignStage.scanning) {
      return;
    }
    _scanGeneration++;
    setState(() {
      _stage = _ShieldSignStage.showQr;
      _scanHint = null;
      _scanProgress = 0;
    });
  }

  Future<void> _openCameraSettings() async {
    if (_closed ||
        _cancellationStarted ||
        _stage != _ShieldSignStage.scanning) {
      return;
    }
    _restartCameraOnResume = true;
    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      _restartCameraOnResume = false;
      log('MobileKeystoneShield: failed to open camera permission settings');
    }
  }

  Future<void> _restartCameraAfterSettings() async {
    if (_closed ||
        _cancellationStarted ||
        _stage != _ShieldSignStage.scanning) {
      return;
    }
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

  bool _isActiveScan(int generation) =>
      mounted &&
      !_closed &&
      !_cancellationStarted &&
      _stage == _ShieldSignStage.scanning &&
      generation == _scanGeneration;

  Future<void> _handleScanComplete(ScanResult result, int generation) async {
    if (!_isActiveScan(generation) || _decoding) return;
    setState(() {
      _decoding = true;
      _scanHint = null;
    });
    try {
      final signedPczt = await rust_keystone.decodePcztFromCbor(
        cbor: result.data,
      );
      while (_isActiveScan(generation) &&
          _pcztWithProofs == null &&
          !_proofsFailed) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final pcztWithProofs = _pcztWithProofs;
      final saplingParams = _saplingParams;
      if (!_isActiveScan(generation)) return;
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
      if (!_isActiveScan(generation)) return;
      log('MobileKeystoneShield: signed PCZT decode error: $e\n$st');
      if (!mounted || _closed) return;
      setState(() {
        _decoding = false;
        _scanHint =
            'This QR code could not be decoded as a Keystone signature.';
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _closed || _cancellationStarted || _decoding) return;
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
    if (!mounted || _closed || _cancellationStarted) return;
    _scanGeneration++;
    setState(() {
      _stage = _ShieldSignStage.broadcasting;
      _error = null;
      _statusMessage = null;
      _retrySignatures = null;
    });

    RpcEndpointConfig? attemptedEndpoint;
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      attemptedEndpoint = endpoint;
      _requireOriginalAccount();
      final result = await _session.broadcast(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        proofs: pcztWithProofs,
        signatures: signatures,
        spendParamsPath: _needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: _needsSaplingParams ? saplingParams.outputPath : null,
      );
      if (!mounted || _closed) return;
      log(
        'MobileKeystoneShield: broadcast shield txid=${result.txid} '
        'status=${result.status}',
      );
      observeShieldingBroadcast(
        ref: ref,
        accountUuid: _accountUuid,
        status: result.status,
        txids: [result.txid],
      );

      if (result.status != 'broadcasted' && result.message != null) {
        await _maybeSwitchBroadcastEndpoint(result.message!, attemptedEndpoint);
      }

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('MobileKeystoneShield: refreshAfterSend failed: $e');
      }
      if (!mounted || _closed) return;
      if (result.status != 'broadcasted') {
        setState(() {
          _stage = _ShieldSignStage.broadcastWarning;
          _statusMessage = shieldPcztBroadcastStatusMessage(result);
        });
        return;
      }
      setState(() => _done = true);
    } catch (e, st) {
      log('MobileKeystoneShield._broadcast: ERROR: $e\n$st');
      if (!mounted || _closed) return;
      await _maybeSwitchBroadcastEndpoint(e, attemptedEndpoint);
      if (!mounted || _closed) return;
      final postBroadcastMessage = postBroadcastShieldErrorMessage(e);
      if (postBroadcastMessage != null) {
        setState(() {
          _stage = _ShieldSignStage.broadcastWarning;
          _statusMessage = postBroadcastMessage;
        });
        return;
      }
      if (isHardwareBroadcastRetryable(e)) {
        setState(() {
          _stage = _ShieldSignStage.failed;
          _error = kShieldWaitingForPrivateRecoveryMessage;
          _retrySignatures = signatures;
        });
        return;
      }
      setState(() {
        _stage = _ShieldSignStage.failed;
        _error = _friendlyError(e);
      });
    }
  }

  /// Sends the kept signature again.
  void _retryBroadcast() {
    if (_closed || _cancellationStarted) return;
    final pcztWithProofs = _pcztWithProofs;
    final signatures = _retrySignatures;
    final saplingParams = _saplingParams;
    if (pcztWithProofs == null || signatures == null || saplingParams == null) {
      return;
    }
    unawaited(
      _broadcast(
        pcztWithProofs: pcztWithProofs,
        signatures: signatures,
        saplingParams: saplingParams,
      ),
    );
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

  /// Shared by Cancel and sidebar navigation; the caller owns any route change.
  Future<bool> _prepareExit() async {
    if (_closed || _stage == _ShieldSignStage.broadcasting) return false;
    setState(() {
      _closed = true;
      _cancellationStarted = true;
      _scanGeneration++;
      _restartCameraOnResume = false;
    });
    final released = await _session.close();
    if (!mounted) return false;
    if (!released) _showCancellationResult(released: false);
    return released;
  }

  Future<bool> _prepareSidebarExit() async {
    final released = await _prepareExit();
    // If the sidebar's final route checks reject the pending navigation, leave
    // a usable return action rather than a permanently absorbed signing view.
    if (released && mounted) _showCancellationResult(released: true);
    return released;
  }

  void _showCancellationResult({required bool released}) {
    setState(() {
      _closed = false;
      _started = true;
      _stage = _ShieldSignStage.failed;
      _decoding = false;
      _retrySignatures = null;
      _statusMessage = null;
      _error = released
          ? 'Shielding was cancelled.'
          : 'Could not finish cancelling. Please try again.';
    });
  }

  Future<void> _cancel() async {
    final message = _stage == _ShieldSignStage.broadcastWarning
        ? _statusMessage
        : null;
    if (!await _prepareExit() || !mounted) return;
    context.pop(
      message != null && message.isNotEmpty
          ? MobileKeystoneShieldResult.warning(message)
          : null,
    );
  }

  void _finishWarningOrFailure() => unawaited(_cancel());

  void _requireOriginalAccount() {
    if (_network != ref.read(rpcEndpointFailoverProvider).current.networkName ||
        _accountUuid != ref.read(walletProvider).value?.activeAccountUuid) {
      throw StateError(
        'The selected account or network changed. Return to your wallet.',
      );
    }
  }

  void _start() {
    if (_closed || _cancellationStarted || _started) return;
    setState(() => _started = true);
    unawaited(_preparePczt());
  }

  @override
  Widget build(BuildContext context) {
    final scanning = _stage == _ShieldSignStage.scanning;
    final terminal =
        _stage == _ShieldSignStage.failed ||
        _stage == _ShieldSignStage.broadcastWarning;
    return MobileSidebarExitScope(
      canNavigate: !_closed && _stage != _ShieldSignStage.broadcasting,
      onExit: _prepareSidebarExit,
      child: AbsorbPointer(
        absorbing: _closed,
        child: MobileShieldScene(
          backdrop: widget.backdrop,
          phase: !_started
              ? MobileShieldPhase.review
              : _done
              ? MobileShieldPhase.succeeded
              : terminal
              ? MobileShieldPhase.failed
              : scanning || _stage == _ShieldSignStage.showQr
              ? MobileShieldPhase.hardware
              : MobileShieldPhase.working,
          amount: formatZecAmount(_amount),
          resultAmount: formatZecAmount(_shieldedAmount ?? _amount),
          title: !_started
              ? 'Transparent Balance'
              : _done
              ? 'Shielded successfully'
              : scanning
              ? 'Scan your Keystone signature'
              : _stage == _ShieldSignStage.showQr
              ? 'Approve with Keystone'
              : terminal
              ? 'Shielding needs attention'
              : 'Shielding your balance…',
          body: terminal ? _statusMessage ?? _error : null,
          keystoneFocus: KeystoneShieldFocus(
            stage: _started && !_done && !terminal
                ? scanning
                      ? KeystoneShieldFocusStage.scanner
                      : _stage == _ShieldSignStage.showQr
                      ? KeystoneShieldFocusStage.qr
                      : KeystoneShieldFocusStage.cloud
                : KeystoneShieldFocusStage.cloud,
            urParts: _urParts,
            scannerBuilder: (constraints, morph) =>
                _buildScanner(constraints, morph),
            onQrReadyChanged: (ready) {
              if (mounted && !_cancellationStarted && _qrVisualReady != ready) {
                setState(() => _qrVisualReady = ready);
              }
            },
          ),
          canLeave: !_closed && _stage != _ShieldSignStage.broadcasting,
          onCommit: _start,
          onClose: _done
              ? () => context.pop(const MobileKeystoneShieldResult.succeeded())
              : _cancel,
          onComplete: () =>
              context.pop(const MobileKeystoneShieldResult.succeeded()),
          footer: !_started || _done ? null : _buildBottomBar(),
        ),
      ),
    );
  }

  Widget _buildScanner(BoxConstraints constraints, KeystoneShieldMorph morph) {
    final controller = _scanController;
    if (controller == null) return const SizedBox.shrink();
    final generation = _scanGeneration;
    return KeystoneShieldScannerSurface(
      constraints: constraints,
      morph: morph,
      decoding: _decoding,
      progress: _scanProgress,
      hint: _scanHint,
      onToggleTorch: () {
        if (_isActiveScan(generation)) unawaited(controller.toggleTorch());
      },
      cameraBuilder: (viewSize) => AnimatedUrScannerView(
        controller: controller,
        expectedUrType: 'zcash-pczt',
        scanWindow: Rect.fromLTWH(0, 0, viewSize, viewSize),
        scanSessionResetToken: generation,
        errorBuilder: (context, error) => const SizedBox.shrink(),
        onProgress: (progress) {
          if (_isActiveScan(generation) && _scanProgress != progress) {
            setState(() => _scanProgress = progress);
          }
        },
        onDecodeError: (error) {
          if (_isActiveScan(generation)) _handleDecodeError(error);
        },
        onComplete: (result) =>
            unawaited(_handleScanComplete(result, generation)),
      ),
      cameraErrorBuilder: (viewSize) => MobileScanCameraErrorOverlay(
        controller: controller,
        maxWidth: viewSize,
        permissionDeniedMessage:
            'Allow camera access in Settings to scan Keystone signatures.',
        unavailableMessage: 'The camera is unavailable right now.',
        onOpenSettings: _openCameraSettings,
      ),
    );
  }

  Widget _buildBottomBar() {
    final scanning = _stage == _ShieldSignStage.scanning;
    final terminal =
        _stage == _ShieldSignStage.failed ||
        _stage == _ShieldSignStage.broadcastWarning;
    if (terminal) {
      final canRetry =
          _stage == _ShieldSignStage.failed && _retrySignatures != null;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.s,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: canRetry
            ? Row(
                children: [
                  Expanded(
                    child: AppButton(
                      expand: true,
                      constrainContent: true,
                      growWithContent: true,
                      variant: AppButtonVariant.ghost,
                      onPressed: _finishWarningOrFailure,
                      child: const Text(
                        'Back to wallet',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: AppButton(
                      key: const ValueKey('mobile_keystone_shield_retry'),
                      expand: true,
                      constrainContent: true,
                      growWithContent: true,
                      onPressed: _retryBroadcast,
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              )
            : AppButton(
                expand: true,
                constrainContent: true,
                growWithContent: true,
                onPressed: _finishWarningOrFailure,
                child: const Text('Back to wallet'),
              ),
      );
    }

    return KeystoneShieldFooter(
      showQr: !scanning && _stage != _ShieldSignStage.broadcasting,
      onCancel: _closed || _stage == _ShieldSignStage.broadcasting
          ? null
          : _cancel,
      onNext: _stage == _ShieldSignStage.showQr && _qrVisualReady
          ? _startScanning
          : null,
      onShowQr: scanning && !_decoding ? _backToQr : null,
    );
  }
}
