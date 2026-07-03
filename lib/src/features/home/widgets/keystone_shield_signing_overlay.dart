import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../../l10n/app_localizations.dart';
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';
import '../services/transparent_shielding_service.dart'
    show shieldPcztBroadcastStatusMessage;

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

class _KeystoneShieldSigningOverlayState
    extends ConsumerState<KeystoneShieldSigningOverlay> {
  _KeystoneShieldPhase _phase = _KeystoneShieldPhase.preparing;
  bool _showSaplingParamsPrompt = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  String? _statusMessage;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;
  bool _needsSaplingParams = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_preparePczt());
    });
  }

  @override
  void dispose() {
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

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final shieldPczt = await rust_sync.createShieldTransparentPczt(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      );

      var saplingParams = await loadSaplingParamsStatus();
      if (shieldPczt.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!confirmed) {
          if (!mounted) return;
          setState(() {
            _phase = _KeystoneShieldPhase.failed;
            _error = AppLocalizations.of(context).shieldCancelledParamsDownload;
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

      if (!mounted) return;
      setState(() {
        _phase = _KeystoneShieldPhase.ready;
        _pcztWithProofs = pcztWithProofs;
        _saplingParams = saplingParams;
        _needsSaplingParams = shieldPczt.needsSaplingParams;
        _urParts = urParts;
      });
    } catch (e, st) {
      log('KeystoneShieldConfirm._preparePczt: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _KeystoneShieldPhase.failed;
        _error = _friendlyError(e);
      });
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
    if (signatures == null || !mounted) return;
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
    });

    RpcEndpointConfig? attemptedEndpoint;
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      attemptedEndpoint = endpoint;
      final result = await rust_sync.extractAndBroadcastPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signatures,
        spendParamsPath: _needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: _needsSaplingParams ? saplingParams.outputPath : null,
      );
      log(
        'KeystoneShieldConfirm: broadcast shield txid=${result.txid} '
        'status=${result.status}',
      );

      if (result.status != 'broadcasted' && result.message != null) {
        await _maybeSwitchBroadcastEndpoint(result.message!, attemptedEndpoint);
      }

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('KeystoneShieldConfirm: refreshAfterSend failed: $e');
      }
      if (!mounted) return;
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
      if (!mounted) return;
      final postBroadcastMessage = _postBroadcastErrorMessage(e);
      if (postBroadcastMessage != null) {
        setState(() {
          _phase = _KeystoneShieldPhase.broadcastWarning;
          _statusMessage = postBroadcastMessage;
        });
        return;
      }
      setState(() {
        _phase = _KeystoneShieldPhase.failed;
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
          operation: 'keystone shield broadcast',
        );
    if (switched) {
      unawaited(ref.read(syncProvider.notifier).restartSync());
    }
  }

  String _pcztBroadcastStatusMessage(
    rust_sync.ExtractAndBroadcastPcztResult result,
  ) {
    return shieldPcztBroadcastStatusMessage(result, AppLocalizations.of(context));
  }

  String? _postBroadcastErrorMessage(Object error) {
    final raw = error.toString();
    if (!raw.toLowerCase().contains('broadcast succeeded')) return null;
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  String _friendlyError(Object error) {
    final l10n = AppLocalizations.of(context);
    final lower = error.toString().toLowerCase();
    if (lower.contains('sync')) {
      return l10n.shieldErrorSyncFirst;
    }
    if (lower.contains('threshold') ||
        lower.contains('too small') ||
        lower.contains('no transparent funds')) {
      return l10n.shieldErrorTooSmall;
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return l10n.keystoneShieldParamsError;
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return l10n.shieldErrorBroadcastFailed;
    }
    if (lower.contains('extract') || lower.contains('pczt')) {
      return l10n.keystoneShieldSignatureError;
    }
    return l10n.shieldErrorRetry;
  }

  void _cancelToHome() {
    if (_phase == _KeystoneShieldPhase.broadcasting) return;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final isBroadcasting = _phase == _KeystoneShieldPhase.broadcasting;
    final isBroadcastWarning = _phase == _KeystoneShieldPhase.broadcastWarning;
    final isFailed = _phase == _KeystoneShieldPhase.failed;
    final modalPhase = switch (_phase) {
      _KeystoneShieldPhase.ready => KeystoneSigningModalPhase.ready,
      _KeystoneShieldPhase.failed ||
      _KeystoneShieldPhase.broadcastWarning => KeystoneSigningModalPhase.failed,
      _KeystoneShieldPhase.preparing ||
      _KeystoneShieldPhase.broadcasting => KeystoneSigningModalPhase.preparing,
    };
    final error = isBroadcastWarning
        ? _statusMessage ?? AppLocalizations.of(context).shieldTxUncertain
        : _error;

    return Stack(
      fit: StackFit.expand,
      children: [
        AppPaneModalOverlay(
          onDismiss: _cancelToHome,
          child: KeystoneSigningModal(
            phase: modalPhase,
            urParts: _urParts,
            error: error,
            title: isBroadcasting
                ? AppLocalizations.of(context).keystoneShieldBroadcasting
                : AppLocalizations.of(context).keystoneShieldSignTitle,
            subtitle: isBroadcasting
                ? AppLocalizations.of(context).keystoneShieldSubmitting
                : AppLocalizations.of(context).keystoneShieldScanToSign,
            instruction: isBroadcasting
                ? AppLocalizations.of(context).keystoneShieldKeepOpen
                : isFailed || isBroadcastWarning
                ? null
                : AppLocalizations.of(context).sendAfterScanGetSignature,
            primaryLabel: isFailed || isBroadcastWarning || isBroadcasting
                ? null
                : AppLocalizations.of(context).sendGetSignature,
            onPrimary: _phase == _KeystoneShieldPhase.ready
                ? () => unawaited(_getSignature())
                : null,
            secondaryLabel: isBroadcasting
                ? null
                : isFailed || isBroadcastWarning
                ? AppLocalizations.of(context).keystoneShieldBackToWallet
                : AppLocalizations.of(context).keystoneShieldReject,
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
    );
  }
}
