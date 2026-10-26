import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/navigation/external_action_guard_hold.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/zcash/network_upgrade_hold.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';
import '../services/hardware_shielding_session.dart';
import '../services/transparent_shielding_service.dart'
    show
        isHardwareBroadcastRetryable,
        kShieldWaitingForPrivateRecoveryMessage,
        observeShieldingBroadcast;

enum _KeystoneShieldPhase {
  preparing,
  ready,
  broadcasting,
  broadcastWarning,
  failed,
}

class KeystoneShieldSigningOverlay extends ConsumerStatefulWidget {
  const KeystoneShieldSigningOverlay({
    required this.onCancel,
    required this.onComplete,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onComplete;

  @override
  ConsumerState<KeystoneShieldSigningOverlay> createState() =>
      _KeystoneShieldSigningOverlayState();
}

// An inbound `zcash:` link must not scrim a prepared PCZT and a device
// approval the user already gave. This overlay lives on `/home`, so the
// location-based rules in `payment_uri_drain_policy.dart` cannot see it; the
// hold is what makes the drain treat it as busy, for every phase until
// dispose.
class _KeystoneShieldSigningOverlayState
    extends ConsumerState<KeystoneShieldSigningOverlay>
    with ExternalActionGuardHoldMixin {
  _KeystoneShieldPhase _phase = _KeystoneShieldPhase.preparing;
  bool _showSaplingParamsPrompt = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  String? _statusMessage;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  String? _accountUuid;
  HardwareShieldingSession? _session;
  bool _closed = false;
  SaplingParamsStatus? _saplingParams;
  bool _needsSaplingParams = false;

  /// The signature of a broadcast that waits for private recovery, kept so
  /// the user can send it again without signing again.
  List<int>? _retrySignatures;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_preparePczt());
    });
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_session?.close());
    final promptCompleter = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (promptCompleter != null && !promptCompleter.isCompleted) {
      promptCompleter.complete(false);
    }
    super.dispose();
  }

  Future<bool> _showDownloadPrompt() {
    if (!mounted) return Future.value(false);

    final existingCompleter = _saplingParamsPromptCompleter;
    if (existingCompleter != null && !existingCompleter.isCompleted) {
      return existingCompleter.future;
    }

    final completer = Completer<bool>();
    setState(() {
      _saplingParamsPromptCompleter = completer;
      _showSaplingParamsPrompt = true;
    });
    return completer.future;
  }

  void _resolveSaplingParamsDialog(bool confirmed) {
    final completer = _saplingParamsPromptCompleter;
    if (completer == null || completer.isCompleted) return;

    setState(() {
      _showSaplingParamsPrompt = false;
      _saplingParamsPromptCompleter = null;
    });
    completer.complete(confirmed);
  }

  Future<void> _preparePczt() async {
    try {
      final accountUuid = ref.read(walletProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        throw Exception('No active account.');
      }
      _accountUuid = accountUuid;
      final session = _session ??= HardwareShieldingSession.forRef(
        ref,
        accountUuid,
      );

      final dbPath = await getWalletDbPath();
      if (!mounted || _closed) return;
      _requireOriginalAccount();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final shieldPczt = await session.prepare(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );

      if (!mounted || _closed) return;
      var saplingParams = await loadSaplingParamsStatus();
      if (shieldPczt.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!confirmed) {
          if (!mounted || _closed) return;
          setState(() {
            _phase = _KeystoneShieldPhase.failed;
            _error =
                'Shielding was cancelled before proving parameters were downloaded.';
          });
          return;
        }

        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('KeystoneShieldConfirm: $message'),
        );
        saplingParams = await loadSaplingParamsStatus();
      }

      final pcztWithProofs = await rust_sync.addProofsToPczt(
        pcztBytes: shieldPczt.pcztBytes,
        spendParamsPath: shieldPczt.needsSaplingParams
            ? saplingParams.spendPath
            : null,
        outputParamsPath: shieldPczt.needsSaplingParams
            ? saplingParams.outputPath
            : null,
      );
      final redactedPczt = await rust_sync.redactPcztForSigner(
        pcztBytes: shieldPczt.pcztBytes,
      );
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: redactedPczt,
        maxFragmentLen: BigInt.from(140),
      );

      if (!mounted || _closed) return;
      setState(() {
        _phase = _KeystoneShieldPhase.ready;
        _pcztWithProofs = pcztWithProofs;
        _saplingParams = saplingParams;
        _needsSaplingParams = shieldPczt.needsSaplingParams;
        _urParts = urParts;
      });
    } catch (e, st) {
      log('KeystoneShieldConfirm._preparePczt: ERROR: $e\n$st');
      await _session?.close();
      if (!mounted || _closed) return;
      setState(() {
        _phase = _KeystoneShieldPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  void _requireOriginalAccount() {
    if (_accountUuid == null ||
        _accountUuid != ref.read(walletProvider).value?.activeAccountUuid) {
      throw StateError('The selected account changed. Return to your wallet.');
    }
  }

  Future<void> _getSignature() async {
    final pcztWithProofs = _pcztWithProofs;
    final saplingParams = _saplingParams;
    if (_phase != _KeystoneShieldPhase.ready ||
        pcztWithProofs == null ||
        saplingParams == null) {
      return;
    }

    final signatures = await context.push<List<int>>('/send/keystone/scan');
    if (signatures == null || !mounted || _closed) return;
    await _broadcast(pcztWithProofs, signatures, saplingParams);
  }

  Future<void> _broadcast(
    List<int> pcztWithProofs,
    List<int> signatures,
    SaplingParamsStatus saplingParams,
  ) async {
    setState(() {
      _phase = _KeystoneShieldPhase.broadcasting;
      _error = null;
      _statusMessage = null;
      _retrySignatures = null;
    });

    RpcEndpointConfig? attemptedEndpoint;
    try {
      final dbPath = await getWalletDbPath();
      if (!mounted || _closed) return;
      _requireOriginalAccount();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      attemptedEndpoint = endpoint;
      final result = await _session!.broadcast(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        proofs: pcztWithProofs,
        signatures: signatures,
        spendParamsPath: _needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: _needsSaplingParams ? saplingParams.outputPath : null,
      );
      log(
        'KeystoneShieldConfirm: broadcast shield txid=${result.txid} '
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
        log('KeystoneShieldConfirm: refreshAfterSend failed: $e');
      }
      if (!mounted || _closed) return;
      if (result.status != 'broadcasted') {
        setState(() {
          _phase = _KeystoneShieldPhase.broadcastWarning;
          _statusMessage = _pcztBroadcastStatusMessage(result);
        });
        return;
      }
      widget.onComplete();
    } catch (e, st) {
      log('KeystoneShieldConfirm._broadcast: ERROR: $e\n$st');
      await _maybeSwitchBroadcastEndpoint(e, attemptedEndpoint);
      if (!mounted || _closed) return;
      final postBroadcastMessage = _postBroadcastErrorMessage(e);
      if (postBroadcastMessage != null) {
        setState(() {
          _phase = _KeystoneShieldPhase.broadcastWarning;
          _statusMessage = postBroadcastMessage;
        });
        return;
      }
      if (isHardwareBroadcastRetryable(e)) {
        setState(() {
          _phase = _KeystoneShieldPhase.failed;
          _error = kShieldWaitingForPrivateRecoveryMessage;
          _retrySignatures = signatures;
        });
        return;
      }
      setState(() {
        _phase = _KeystoneShieldPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  /// Sends the kept signature again.
  void _retryBroadcast() {
    final pcztWithProofs = _pcztWithProofs;
    final signatures = _retrySignatures;
    final saplingParams = _saplingParams;
    if (pcztWithProofs == null || signatures == null || saplingParams == null) {
      return;
    }
    unawaited(_broadcast(pcztWithProofs, signatures, saplingParams));
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
          operation: 'keystone shield broadcast',
        );
    if (switched) {
      unawaited(ref.read(syncProvider.notifier).restartSync());
    }
  }

  String _pcztBroadcastStatusMessage(
    rust_sync.ExtractAndBroadcastPcztResult result,
  ) {
    final upgradeHold = networkUpgradeHoldMessage(result.message ?? '');
    if (upgradeHold != null) return upgradeHold;
    if (result.status == 'broadcast_unknown') {
      return result.message ??
          'The shield transaction may have reached the network, but confirmation timed out. Check activity before trying again.';
    }
    if (result.status == 'broadcasted_storage_failed') {
      return result.message ??
          'The shield transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';
    }
    return result.message ??
        'The shield transaction status is uncertain. Check activity before trying again.';
  }

  String? _postBroadcastErrorMessage(Object error) {
    final raw = error.toString();
    if (!raw.toLowerCase().contains('broadcast succeeded')) return null;
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  String _friendlyError(Object error) {
    final upgradeHold = networkUpgradeHoldMessage(error);
    if (upgradeHold != null) return upgradeHold;
    final lower = error.toString().toLowerCase();
    if (lower.contains('sync')) {
      return 'Sync the wallet before shielding transparent balance.';
    }
    if (lower.contains('threshold') ||
        lower.contains('too small') ||
        lower.contains('no transparent funds')) {
      return 'Transparent balance is too small to shield after fees.';
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return 'Shield transaction could not be broadcast.';
    }
    if (lower.contains('extract') || lower.contains('pczt')) {
      return 'Keystone signature could not be applied.';
    }
    return 'Shield balance failed. Please try again.';
  }

  Future<void> _cancelToHome() async {
    if (_closed || _phase == _KeystoneShieldPhase.broadcasting) return;
    setState(() => _closed = true);
    _resolveSaplingParamsDialog(false);
    final released = await _session?.close() ?? true;
    if (!mounted) return;
    if (!released) {
      setState(() {
        _closed = false;
        _phase = _KeystoneShieldPhase.failed;
        _error = 'Could not finish cancelling. Please try again.';
      });
      return;
    }
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final isBroadcasting = _phase == _KeystoneShieldPhase.broadcasting;
    final isBroadcastWarning = _phase == _KeystoneShieldPhase.broadcastWarning;
    final isFailed = _phase == _KeystoneShieldPhase.failed;
    final canRetry = isFailed && _retrySignatures != null;
    final modalPhase = switch (_phase) {
      _KeystoneShieldPhase.ready => KeystoneSigningModalPhase.ready,
      _KeystoneShieldPhase.failed ||
      _KeystoneShieldPhase.broadcastWarning => KeystoneSigningModalPhase.failed,
      _KeystoneShieldPhase.preparing ||
      _KeystoneShieldPhase.broadcasting => KeystoneSigningModalPhase.preparing,
    };
    final error = isBroadcastWarning
        ? _statusMessage ??
              'The shield transaction status is uncertain. Check activity before trying again.'
        : _error;

    return AbsorbPointer(
      absorbing: _closed,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppPaneModalOverlay(
            onDismiss: _cancelToHome,
            child: KeystoneSigningModal(
              phase: modalPhase,
              urParts: _urParts,
              error: error,
              title: isBroadcasting
                  ? 'Broadcasting shield tx'
                  : 'Sign tx on your Keystone',
              subtitle: isBroadcasting
                  ? 'Submitting transaction'
                  : 'Scan the QR code to sign',
              instruction: isBroadcasting
                  ? 'Keep Vizor open while the transaction is sent.'
                  : isFailed || isBroadcastWarning
                  ? null
                  : 'After you scanned, click Get Signature.',
              primaryLabel: canRetry
                  ? 'Try again'
                  : isFailed || isBroadcastWarning || isBroadcasting
                  ? null
                  : 'Get Signature',
              onPrimary: canRetry
                  ? _retryBroadcast
                  : _phase == _KeystoneShieldPhase.ready
                  ? () => unawaited(_getSignature())
                  : null,
              secondaryLabel: isBroadcasting
                  ? null
                  : isFailed || isBroadcastWarning
                  ? 'Back to Wallet'
                  : 'Reject',
              onSecondary: _cancelToHome,
            ),
          ),
          if (_showSaplingParamsPrompt)
            Positioned.fill(
              child: SaplingParamsPrompt(
                onDownload: () => _resolveSaplingParamsDialog(true),
                onCancel: () => _resolveSaplingParamsDialog(false),
              ),
            ),
        ],
      ),
    );
  }
}
