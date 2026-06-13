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
              _error =
                  'Signing was cancelled before proving parameters were downloaded.';
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
              result.message ??
              'The transaction status is uncertain. Refresh activity before trying again.';
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
    const action = 'ZEC deposit';

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
                ? 'Broadcasting $action'
                : 'Sign $action on Keystone',
            subtitle: isBroadcasting
                ? 'Submitting transaction'
                : 'Scan to sign',
            instruction: isBroadcasting
                ? 'Keep Vizor open while the transaction is sent.'
                : _phase == _SwapKeystonePhase.failed
                ? null
                : 'After you scanned, click Get signature.',
            primaryLabel: _phase == _SwapKeystonePhase.failed || isBroadcasting
                ? null
                : 'Get signature',
            onPrimary:
                _phase == _SwapKeystonePhase.ready && _pcztWithProofs != null
                ? () => unawaited(_getSignature())
                : null,
            secondaryLabel: isBroadcasting
                ? null
                : _phase == _SwapKeystonePhase.failed
                ? 'Back to activity'
                : 'Cancel',
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
    final lower = error.toString().toLowerCase();
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    if (lower.contains('proposal not found')) {
      return 'Transaction expired before it could be signed.';
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return 'Transaction could not be broadcast.';
    }
    if (lower.contains('pczt') || lower.contains('signature')) {
      return 'Keystone signature could not be applied.';
    }
    return 'ZEC deposit signing could not be completed.';
  }
}

String _shortSwapValue(String? value) {
  if (value == null) return 'null';
  if (value.length <= 16) return value;
  return '${value.substring(0, 7)}...${value.substring(value.length - 6)}';
}
