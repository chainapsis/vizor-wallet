import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../../ledger/widgets/ledger_signing_modal.dart';
import '../../ledger/widgets/mobile_ledger_signing_surface.dart';
import '../../send/services/sapling_params.dart';
import '../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../send/widgets/sapling_params_prompt.dart';
import '../models/swap_deposit_broadcast_result.dart';
import '../models/swap_hardware_broadcast_result.dart';
import '../models/swap_models.dart';
import '../providers/swap_hardware_signing_service.dart';

class SwapLedgerSigningOverlay extends ConsumerStatefulWidget {
  const SwapLedgerSigningOverlay({
    required this.intent,
    required this.onCancel,
    required this.onDepositBroadcast,
    this.mobile = false,
    super.key,
  });

  final SwapIntent intent;
  final VoidCallback onCancel;
  final Future<void> Function(SwapHardwareBroadcastResult) onDepositBroadcast;
  final bool mobile;

  @override
  ConsumerState<SwapLedgerSigningOverlay> createState() =>
      _SwapLedgerSigningOverlayState();
}

class _SwapLedgerSigningOverlayState
    extends ConsumerState<SwapLedgerSigningOverlay> {
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.preparing;
  bool _showSaplingParamsPrompt = false;
  bool _cancelled = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  SwapHardwareSigningService? _signingService;
  SwapHardwarePcztDraft? _draft;
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;
  String? _operationId;
  bool _operationCheckpointed = false;
  LedgerSignedOperationBroadcastResult? _pendingBroadcastResult;
  late final LedgerOperationCanceller _cancelLedgerOperation;

  bool get _isBroadcasting => _phase == LedgerSigningModalPhase.broadcasting;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepareAndSign());
    });
  }

  @override
  void dispose() {
    final shouldCancelDevice = !_cancelled && !_isBroadcasting;
    _cancelled = true;
    if (shouldCancelDevice) {
      unawaited(_cancelLedgerOperationSafely());
    }
    final completer = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    unawaited(_discardDraft());
    super.dispose();
  }

  Future<void> _prepareAndSign() async {
    try {
      final accountUuid = widget.intent.accountUuid;
      if (accountUuid == null || accountUuid.trim().isEmpty) {
        throw StateError('Swap account is missing.');
      }
      final operationKind = widget.intent.payMode
          ? LedgerSignedOperationKind.payDeposit
          : LedgerSignedOperationKind.swapDeposit;
      final operationId = _operationId ??= newLedgerSignedOperationId(
        kind: operationKind,
        accountUuid: accountUuid,
        externalRef: widget.intent.id,
      );
      final existingOperation = await _findExistingOperation(operationId);
      if (existingOperation != null) {
        _operationCheckpointed = true;
        if (existingOperation.state == 'result_pending_ack') {
          final txid = existingOperation.txid?.trim() ?? '';
          final status = existingOperation.status?.trim() ?? '';
          if (txid.isEmpty || status.isEmpty) {
            throw StateError('Ledger deposit result is incomplete.');
          }
          _pendingBroadcastResult = LedgerSignedOperationBroadcastResult(
            operationId: operationId,
            txid: txid,
            status: status,
            message: existingOperation.message,
            requiresAck: true,
          );
          await _completeProviderCheckpoint(_pendingBroadcastResult!);
          return;
        }
        await _broadcastCheckpointed();
        return;
      }

      final service = ref.read(swapHardwareSigningServiceProvider);
      _signingService = service;
      final draft = await service.createZecDepositPczt(
        accountUuid: accountUuid,
        intent: widget.intent,
      );
      _draft = draft;

      SaplingParamsStatus? saplingParams;
      if (draft.needsSaplingParams) {
        saplingParams = await loadSaplingParamsStatus();
        if (!saplingParams.complete) {
          final confirmed = await _showDownloadPrompt();
          if (!confirmed) {
            throw StateError(
              'Signing was cancelled before proving parameters were downloaded.',
            );
          }
          await downloadMissingSaplingParams(
            saplingParams,
            log: (message) => log('SwapLedgerSigning: $message'),
          );
          saplingParams = await loadSaplingParamsStatus();
        }
      }

      final pcztWithProofs = await service.addProofsForSigning(
        draft: draft,
        spendParamsPath: draft.needsSaplingParams
            ? saplingParams!.spendPath
            : null,
        outputParamsPath: draft.needsSaplingParams
            ? saplingParams!.outputPath
            : null,
      );
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.awaitingDevice;
        _saplingParams = saplingParams;
        _pcztWithProofs = pcztWithProofs;
      });

      final signedPczt = await ref.read(ledgerPcztSignerProvider)(
        accountUuid,
        draft.pcztBytes,
      );
      if (!mounted || _cancelled) return;
      await ref
          .read(ledgerSignedOperationServiceProvider)
          .checkpoint(
            operationId: operationId,
            accountUuid: accountUuid,
            kind: operationKind,
            externalRef: widget.intent.id,
            pcztWithProofsBytes: pcztWithProofs,
            pcztWithSignaturesBytes: signedPczt,
          );
      _operationCheckpointed = true;
      await _broadcastCheckpointed();
    } catch (e, st) {
      log('SwapLedgerSigning._prepareAndSign: ERROR: $e\n$st');
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _retry() async {
    if (_phase != LedgerSigningModalPhase.failed || _isBroadcasting) return;
    if (_operationCheckpointed) {
      setState(() {
        _error = null;
      });
      try {
        final pendingResult = _pendingBroadcastResult;
        if (pendingResult != null) {
          await _completeProviderCheckpoint(pendingResult);
        } else {
          await _broadcastCheckpointed();
        }
      } catch (e, st) {
        log('SwapLedgerSigning._retryCheckpoint: ERROR: $e\n$st');
        if (!mounted || _cancelled) return;
        setState(() {
          _phase = LedgerSigningModalPhase.failed;
          _error = _friendlyError(e);
        });
      }
      return;
    }
    final draft = _draft;
    final proofs = _pcztWithProofs;
    if (draft == null || proofs == null) {
      setState(() {
        _phase = LedgerSigningModalPhase.preparing;
        _error = null;
      });
      await _prepareAndSign();
      return;
    }

    setState(() {
      _phase = LedgerSigningModalPhase.awaitingDevice;
      _error = null;
    });
    try {
      final accountUuid = widget.intent.accountUuid!;
      final signedPczt = await ref.read(ledgerPcztSignerProvider)(
        accountUuid,
        draft.pcztBytes,
      );
      if (!mounted || _cancelled) return;
      final operationKind = widget.intent.payMode
          ? LedgerSignedOperationKind.payDeposit
          : LedgerSignedOperationKind.swapDeposit;
      final operationId = _operationId!;
      await ref
          .read(ledgerSignedOperationServiceProvider)
          .checkpoint(
            operationId: operationId,
            accountUuid: accountUuid,
            kind: operationKind,
            externalRef: widget.intent.id,
            pcztWithProofsBytes: proofs,
            pcztWithSignaturesBytes: signedPczt,
          );
      _operationCheckpointed = true;
      await _broadcastCheckpointed();
    } catch (e, st) {
      log('SwapLedgerSigning._retry: ERROR: $e\n$st');
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _broadcastCheckpointed() async {
    final operationId = _operationId;
    if (operationId == null || !_operationCheckpointed) {
      throw StateError('Ledger deposit transaction is not checkpointed.');
    }
    if (!mounted || _cancelled) return;
    setState(() {
      _phase = LedgerSigningModalPhase.broadcasting;
      _error = null;
    });
    LedgerSignedOperationBroadcastResult result;
    try {
      final draft = _draft;
      final saplingParams = _saplingParams;
      result = await ref
          .read(ledgerSignedOperationServiceProvider)
          .broadcast(
            operationId: operationId,
            spendParamsPath: draft?.needsSaplingParams == true
                ? saplingParams?.spendPath
                : null,
            outputParamsPath: draft?.needsSaplingParams == true
                ? saplingParams?.outputPath
                : null,
          );
      if (draft != null) {
        await _signingService?.settlePcztDraftAfterLedgerBroadcast(
          draft: draft,
          status: result.status,
        );
        _draft = null;
      }
    } catch (error) {
      final terminal = isTerminalLedgerSignedOperationError(error);
      final draft = _draft;
      if (draft != null) {
        await _signingService?.settlePcztDraftAfterLedgerBroadcast(
          draft: draft,
          status: terminal ? 'terminal_failure' : null,
        );
        _draft = null;
      }
      if (terminal) {
        _operationCheckpointed = false;
        _operationId = null;
        _pendingBroadcastResult = null;
      }
      rethrow;
    }
    if (!_hasBroadcastTxid(result)) {
      throw StateError(
        result.message ?? 'The ZEC deposit could not be broadcast.',
      );
    }
    _pendingBroadcastResult = result;
    try {
      await ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (e) {
      log('SwapLedgerSigning: refreshAfterSend failed: $e');
    }
    await _completeProviderCheckpoint(result);
  }

  Future<void> _completeProviderCheckpoint(
    LedgerSignedOperationBroadcastResult result,
  ) async {
    final operationService = ref.read(ledgerSignedOperationServiceProvider);
    if (mounted) {
      setState(() {
        _phase = LedgerSigningModalPhase.broadcasting;
        _error = null;
      });
    }
    await widget.onDepositBroadcast(
      SwapHardwareBroadcastResult(
        txHash: result.txid,
        status: result.status,
        message: result.message,
      ),
    );
    if (result.requiresAck) {
      await operationService.acknowledge(result.operationId);
    }
    _pendingBroadcastResult = null;
  }

  bool _hasBroadcastTxid(LedgerSignedOperationBroadcastResult result) {
    return switch (result.status) {
      SwapDepositBroadcastStatus.broadcasted ||
      SwapDepositBroadcastStatus.broadcastUnknown ||
      SwapDepositBroadcastStatus.broadcastedStorageFailed =>
        result.txid.trim().isNotEmpty,
      _ => false,
    };
  }

  Future<LedgerSignedOperationMetadata?> _findExistingOperation(
    String operationId,
  ) async {
    final operations = await ref
        .read(ledgerSignedOperationServiceProvider)
        .list();
    for (final operation in operations) {
      if (operation.operationId == operationId) return operation;
    }
    return null;
  }

  Future<bool> _showDownloadPrompt() {
    if (!mounted) return Future.value(false);
    if (widget.mobile) {
      return showAppMobileSheet<bool>(
        context: context,
        isDismissible: false,
        builder: (_) => const MobileSaplingParamsSheet(),
      ).then((confirmed) => confirmed == true);
    }
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

  Future<void> _cancel() async {
    if (_isBroadcasting) return;
    _cancelled = true;
    await _cancelLedgerOperationSafely();
    unawaited(_discardDraft());
    widget.onCancel();
  }

  Future<void> _cancelLedgerOperationSafely() async {
    try {
      await _cancelLedgerOperation();
    } catch (e, st) {
      log('SwapLedgerSigning.cancel: ERROR: $e\n$st');
    }
  }

  Future<void> _discardDraft() async {
    final draft = _draft;
    _draft = null;
    if (draft == null) return;
    if (_operationCheckpointed) {
      await _signingService?.settlePcztDraftAfterLedgerBroadcast(
        draft: draft,
        status: null,
      );
      return;
    }
    await _signingService?.discardPcztDraft(draft: draft);
  }

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    final appInstruction = ledgerZcashAppOpenErrorInstruction(
      ref.read(rpcEndpointProvider).networkName,
    );
    if (lower.contains('rejected') || lower.contains('6985')) {
      return 'The ZEC deposit was rejected on your Ledger.';
    }
    if (lower.contains('no ledger') || lower.contains('hid')) {
      return 'Connect and unlock your Ledger. $appInstruction';
    }
    if (lower.contains('sapling')) {
      return 'This Ledger preview does not support Sapling inputs or outputs.';
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return 'The ZEC deposit could not be broadcast.';
    }
    return 'Ledger signing could not be completed.';
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = !_isBroadcasting;
    final modal = LedgerSigningModal(
      accountUuid: widget.intent.accountUuid,
      phase: _phase,
      failure: _phase == LedgerSigningModalPhase.failed
          ? LedgerSigningFailurePresentation(
              title: 'Ledger signing failed',
              statusLabel: 'Action needed',
              message: _error ?? 'Ledger signing could not be completed.',
              showDeviceAppPrompt: true,
              actionLabel: 'Try again',
            )
          : null,
      onCancel: canLeave ? () => unawaited(_cancel()) : null,
      cancelLabel: 'Back to activity',
      onFailureAction: _phase == LedgerSigningModalPhase.failed
          ? () => unawaited(_retry())
          : null,
    );
    if (widget.mobile) {
      return Stack(
        key: const ValueKey('mobile_swap_ledger_signing_surface'),
        fit: StackFit.expand,
        children: [
          MobileLedgerSigningSurface(
            title: widget.intent.payMode ? 'Sign payment' : 'Sign ZEC deposit',
            canLeave: canLeave,
            onBack: () => unawaited(_cancel()),
            child: modal,
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
    return Stack(
      key: const ValueKey('swap_ledger_signing_overlay_surface'),
      fit: StackFit.expand,
      children: [
        AppPaneModalOverlay(
          onDismiss: _isBroadcasting ? () {} : () => unawaited(_cancel()),
          child: modal,
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
