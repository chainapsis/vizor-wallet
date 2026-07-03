import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';
import '../models/swap_deposit_broadcast_result.dart';
import '../models/swap_keystone_broadcast_result.dart';
import '../models/swap_models.dart';
import '../providers/swap_hardware_signing_service.dart';
import '../../../../l10n/app_localizations.dart';

class SwapKeystoneSigningOverlay extends ConsumerStatefulWidget {
  const SwapKeystoneSigningOverlay({
    required this.intent,
    required this.onCancel,
    required this.onDepositBroadcast,
    super.key,
  });

  final SwapIntent intent;
  final VoidCallback onCancel;
  final ValueChanged<SwapKeystoneBroadcastResult> onDepositBroadcast;

  @override
  ConsumerState<SwapKeystoneSigningOverlay> createState() =>
      _SwapKeystoneSigningOverlayState();
}

enum _SwapKeystonePhase { preparing, ready, broadcasting, failed }

class _SwapKeystoneSigningOverlayState
    extends ConsumerState<SwapKeystoneSigningOverlay> {
  _SwapKeystonePhase _phase = _SwapKeystonePhase.preparing;
  bool _showSaplingParamsPrompt = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  SwapHardwarePcztDraft? _draft;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_preparePczt());
    });
  }

  @override
  void dispose() {
    final completer = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    super.dispose();
  }

  Future<void> _preparePczt() async {
    try {
      final accountUuid = widget.intent.accountUuid;
      if (accountUuid == null || accountUuid.trim().isEmpty) {
        throw StateError('Swap account is missing.');
      }

      final service = ref.read(swapHardwareSigningServiceProvider);
      final draft = await service.createZecDepositPczt(
        accountUuid: accountUuid,
        intent: widget.intent,
      );

      SaplingParamsStatus? saplingParams;
      if (draft.needsSaplingParams) {
        saplingParams = await loadSaplingParamsStatus();
        if (!saplingParams.complete) {
          final confirmed = await _showDownloadPrompt();
          if (!confirmed) {
            if (!mounted) return;
            setState(() {
              _phase = _SwapKeystonePhase.failed;
              _error = AppLocalizations.of(context).swapSigningCancelledBeforeParams;
            });
            return;
          }
          await downloadMissingSaplingParams(
            saplingParams,
            log: (message) => log('SwapKeystoneSigning: $message'),
          );
          saplingParams = await loadSaplingParamsStatus();
        }
      }

      final urParts = await service.encodeSigningUrParts(draft: draft);
      final pcztWithProofs = await service.addProofsForSigning(
        draft: draft,
        spendParamsPath: draft.needsSaplingParams
            ? saplingParams!.spendPath
            : null,
        outputParamsPath: draft.needsSaplingParams
            ? saplingParams!.outputPath
            : null,
      );
      if (!mounted) return;
      setState(() {
        _phase = _SwapKeystonePhase.ready;
        _draft = draft;
        _urParts = urParts;
        _saplingParams = saplingParams;
        _pcztWithProofs = pcztWithProofs;
      });
    } catch (e, st) {
      log('SwapKeystoneSigning._preparePczt: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _SwapKeystonePhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<bool> _showDownloadPrompt() {
    if (!mounted) return Future.value(false);
    final existing = _saplingParamsPromptCompleter;
    if (existing != null && !existing.isCompleted) return existing.future;

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

  Future<void> _getSignature() async {
    if (_phase != _SwapKeystonePhase.ready || _pcztWithProofs == null) return;
    final signatures = await context.push<List<int>>('/send/keystone/scan');
    if (signatures == null || !mounted) return;
    await _broadcast(signatures);
  }

  Future<void> _broadcast(List<int> signatures) async {
    final draft = _draft;
    final pcztWithProofs = _pcztWithProofs;
    final saplingParams = _saplingParams;
    if (draft == null ||
        pcztWithProofs == null ||
        (draft.needsSaplingParams && saplingParams == null)) {
      return;
    }

    setState(() {
      _phase = _SwapKeystonePhase.broadcasting;
      _error = null;
    });

    try {
      final result = await ref
          .read(swapHardwareSigningServiceProvider)
          .broadcastSignedPczt(
            pcztWithProofsBytes: pcztWithProofs,
            pcztWithSignaturesBytes: signatures,
            spendParamsPath: draft.needsSaplingParams
                ? saplingParams!.spendPath
                : null,
            outputParamsPath: draft.needsSaplingParams
                ? saplingParams!.outputPath
                : null,
          );
      log(
        'SwapKeystoneSigning: broadcast complete kind=zecDeposit '
        'tx=${_shortSwapValue(result.txid)} status=${result.status}',
      );
      if (!_hasBroadcastTxid(result)) {
        if (!mounted) return;
        setState(() {
          _phase = _SwapKeystonePhase.failed;
          _error =
              result.message ?? AppLocalizations.of(context).swapTxStatusUncertain;
        });
        return;
      }
      if (result.status != SwapDepositBroadcastStatus.broadcasted) {
        log(
          'SwapKeystoneSigning: broadcast returned ${result.status} '
          'with tx=${_shortSwapValue(result.txid)}; recording txid for swap tracking',
        );
      }
      final broadcast = SwapKeystoneBroadcastResult(
        txHash: result.txid,
        status: result.status,
        message: result.message,
      );
      widget.onDepositBroadcast(broadcast);
    } catch (e, st) {
      log('SwapKeystoneSigning._broadcast: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _SwapKeystonePhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  bool _hasBroadcastTxid(rust_sync.ExtractAndBroadcastPcztResult result) {
    return switch (result.status) {
      SwapDepositBroadcastStatus.broadcasted ||
      SwapDepositBroadcastStatus.broadcastUnknown ||
      SwapDepositBroadcastStatus.broadcastedStorageFailed =>
        result.txid.trim().isNotEmpty,
      _ => false,
    };
  }

  void _cancel() {
    if (_phase == _SwapKeystonePhase.broadcasting) return;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final modalPhase = switch (_phase) {
      _SwapKeystonePhase.ready => KeystoneSigningModalPhase.ready,
      _SwapKeystonePhase.failed => KeystoneSigningModalPhase.failed,
      _SwapKeystonePhase.preparing ||
      _SwapKeystonePhase.broadcasting => KeystoneSigningModalPhase.preparing,
    };
    final isBroadcasting = _phase == _SwapKeystonePhase.broadcasting;
    final l10n = AppLocalizations.of(context);
    final action = l10n.swapZecDepositAction;

    return Stack(
      key: const ValueKey('swap_keystone_signing_overlay_surface'),
      fit: StackFit.expand,
      children: [
        AppPaneModalOverlay(
          onDismiss: _cancel,
          child: KeystoneSigningModal(
            phase: modalPhase,
            urParts: _urParts,
            error: _error,
            title: isBroadcasting
                ? l10n.swapBroadcastingAction(action)
                : l10n.swapSignActionOnKeystone(action),
            subtitle: isBroadcasting
                ? l10n.swapSubmittingTransaction
                : l10n.swapScanToSign,
            instruction: isBroadcasting
                ? l10n.keystoneShieldKeepOpen
                : _phase == _SwapKeystonePhase.failed
                ? null
                : l10n.swapAfterScannedClickGetSignature,
            primaryLabel: _phase == _SwapKeystonePhase.failed || isBroadcasting
                ? null
                : l10n.swapGetSignature,
            onPrimary:
                _phase == _SwapKeystonePhase.ready && _pcztWithProofs != null
                ? () => unawaited(_getSignature())
                : null,
            secondaryLabel: isBroadcasting
                ? null
                : _phase == _SwapKeystonePhase.failed
                ? l10n.swapBackToActivity
                : l10n.commonCancel,
            onSecondary: _cancel,
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

  String _friendlyError(Object error) {
    final l10n = AppLocalizations.of(context);
    final lower = error.toString().toLowerCase();
    if (lower.contains('does not support tex')) {
      return l10n.sendKeystoneNoTex;
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return l10n.keystoneShieldParamsError;
    }
    if (lower.contains('proposal not found')) {
      return l10n.sendTxExpired;
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return l10n.swapTxCouldNotBroadcast;
    }
    if (lower.contains('grpc') ||
        lower.contains('transport error') ||
        lower.contains('network')) {
      return l10n.swapNetworkErrorRetry;
    }
    if (lower.contains('pczt') || lower.contains('signature')) {
      return l10n.keystoneShieldSignatureError;
    }
    return l10n.swapZecDepositSigningFailed;
  }
}

String _shortSwapValue(String? value) {
  if (value == null) return 'null';
  if (value.length <= 16) return value;
  return '${value.substring(0, 7)}...${value.substring(value.length - 6)}';
}
