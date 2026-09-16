import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../ledger/ledger_capability.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/services/ledger_operation_lifecycle.dart';
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
import '../providers/swap_ledger_completion_service.dart';

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
  late final SwapLedgerCompletionService _completionService;
  late final LedgerOperationLifecycle _lifecycle;
  late final LedgerSignedOperationService _operations;

  bool get _isBroadcasting =>
      _phase == LedgerSigningModalPhase.broadcasting ||
      _phase == LedgerSigningModalPhase.saving;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    _completionService = ref.read(swapLedgerCompletionServiceProvider);
    _lifecycle = ref.read(ledgerOperationLifecycleProvider);
    _operations = ref.read(ledgerSignedOperationServiceProvider);
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
    if (!_isBroadcasting) unawaited(_discardDraft());
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
          await _resumeRecoveredResult(
            _broadcastResultFromMetadata(existingOperation),
          );
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
      await _checkpointAndBroadcast(
        operationId: operationId,
        accountUuid: accountUuid,
        operationKind: operationKind,
        proofs: pcztWithProofs,
        signatures: signedPczt,
      );
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
        _phase = LedgerSigningModalPhase.saving;
        _error = null;
      });
      try {
        var pendingResult = _pendingBroadcastResult;
        if (pendingResult == null) {
          final existingOperation = await _findExistingOperation(_operationId!);
          if (existingOperation != null &&
              existingOperation.state == 'result_pending_ack') {
            pendingResult = _broadcastResultFromMetadata(existingOperation);
          }
        }
        if (pendingResult != null) {
          await _resumeRecoveredResult(pendingResult);
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
      await _checkpointAndBroadcast(
        operationId: operationId,
        accountUuid: accountUuid,
        operationKind: operationKind,
        proofs: proofs,
        signatures: signedPczt,
      );
    } catch (e, st) {
      log('SwapLedgerSigning._retry: ERROR: $e\n$st');
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _checkpointAndBroadcast({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind operationKind,
    required List<int> proofs,
    required List<int> signatures,
  }) => _lifecycle.run(() async {
    setState(() => _phase = LedgerSigningModalPhase.saving);
    try {
      await _operations.checkpoint(
        operationId: operationId,
        accountUuid: accountUuid,
        kind: operationKind,
        externalRef: widget.intent.id,
        pcztWithProofsBytes: proofs,
        pcztWithSignaturesBytes: signatures,
      );
    } catch (_) {
      if (!mounted) await _discardDraft();
      rethrow;
    }
    _operationCheckpointed = true;
    // A reset/delete must drain this entire approved transaction, including
    // provider persistence and acknowledgement, without a gap after checkpoint.
    await _broadcastCheckpointedWithLease();
  });

  Future<void> _broadcastCheckpointed() =>
      _lifecycle.run(_broadcastCheckpointedWithLease);

  Future<void> _broadcastCheckpointedWithLease() async {
    final operationId = _operationId;
    if (operationId == null || !_operationCheckpointed) {
      throw StateError('Ledger deposit transaction is not checkpointed.');
    }
    if (mounted) {
      setState(() {
        _phase = LedgerSigningModalPhase.broadcasting;
        _error = null;
      });
    }
    late final LedgerSignedOperationBroadcastResult result;
    try {
      final draft = _draft;
      final saplingParams = _saplingParams;
      result = await _operations.broadcast(
        operationId: operationId,
        spendParamsPath: draft?.needsSaplingParams == true
            ? saplingParams?.spendPath
            : null,
        outputParamsPath: draft?.needsSaplingParams == true
            ? saplingParams?.outputPath
            : null,
      );
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
    final disposition = classifyLedgerDepositBroadcastResult(result);
    if (disposition == LedgerDepositBroadcastDisposition.expired) {
      await _finishExpiredResult(result);
      return;
    }
    if (disposition != LedgerDepositBroadcastDisposition.accepted) {
      final draft = _draft;
      _draft = null;
      if (draft != null) {
        await _signingService?.settlePcztDraftAfterLedgerBroadcast(
          draft: draft,
          status: result.status,
        );
      }
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

  Future<void> _resumeRecoveredResult(
    LedgerSignedOperationBroadcastResult result,
  ) async {
    switch (classifyLedgerDepositBroadcastResult(result)) {
      case LedgerDepositBroadcastDisposition.accepted:
        _pendingBroadcastResult = result;
        await _completeProviderCheckpoint(result);
      case LedgerDepositBroadcastDisposition.expired:
        await _finishExpiredResult(result);
      case LedgerDepositBroadcastDisposition.invalid:
        throw StateError(
          'Ledger deposit result was not accepted for broadcast.',
        );
    }
  }

  Future<void> _finishExpiredResult(
    LedgerSignedOperationBroadcastResult result,
  ) => _lifecycle.run(() async {
    final draft = _draft;
    _draft = null;
    if (draft != null) {
      try {
        await _signingService?.settlePcztDraftAfterLedgerBroadcast(
          draft: draft,
          status: result.status,
        );
      } catch (error, stackTrace) {
        log(
          'SwapLedgerSigning: expired draft cleanup failed: '
          '$error\n$stackTrace',
        );
        try {
          await _signingService?.settlePcztDraftAfterLedgerBroadcast(
            draft: draft,
            status: null,
          );
        } catch (fallbackError, fallbackStackTrace) {
          log(
            'SwapLedgerSigning: retaining expired draft failed: '
            '$fallbackError\n$fallbackStackTrace',
          );
        }
      }
    }
    if (result.requiresAck) {
      try {
        await _operations.acknowledge(result.operationId);
      } catch (error, stackTrace) {
        log(
          'SwapLedgerSigning: expired result acknowledgement failed: '
          '$error\n$stackTrace',
        );
      }
    }
    _operationCheckpointed = false;
    _operationId = null;
    _pendingBroadcastResult = null;
    if (!mounted) return;
    _cancelled = true;
    widget.onCancel();
  });

  Future<void> _completeProviderCheckpoint(
    LedgerSignedOperationBroadcastResult result,
  ) => _lifecycle.run(() async {
    if (mounted) {
      setState(() {
        _phase = LedgerSigningModalPhase.saving;
        _error = null;
      });
    }
    final draft = _draft;
    if (draft != null) {
      await _signingService?.settlePcztDraftAfterLedgerBroadcast(
        draft: draft,
        status: result.status,
      );
      _draft = null;
    }
    await _completionService.complete(widget.intent, result);
    _pendingBroadcastResult = null;
    if (!mounted) return;
    try {
      await widget.onDepositBroadcast(
        SwapHardwareBroadcastResult(
          txHash: result.txid,
          status: result.status,
          message: result.message,
        ),
      );
    } catch (error) {
      // A navigation/toast failure must not repeat a durably completed deposit.
      log('SwapLedgerSigning: result presentation failed: $error');
    }
  });

  LedgerSignedOperationBroadcastResult _broadcastResultFromMetadata(
    LedgerSignedOperationMetadata operation,
  ) {
    final txid = operation.txid?.trim() ?? '';
    final status = operation.status?.trim() ?? '';
    if (txid.isEmpty || status.isEmpty) {
      throw StateError('Ledger deposit result is incomplete.');
    }
    return LedgerSignedOperationBroadcastResult(
      operationId: operation.operationId,
      txid: txid,
      status: status,
      message: operation.message,
      requiresAck: true,
    );
  }

  Future<LedgerSignedOperationMetadata?> _findExistingOperation(
    String operationId,
  ) async {
    final operations = await _operations.list();
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
      try {
        await _signingService?.settlePcztDraftAfterLedgerBroadcast(
          draft: draft,
          status: _pendingBroadcastResult?.status,
        );
      } catch (error, stackTrace) {
        log(
          'SwapLedgerSigning: checkpointed draft cleanup failed: '
          '$error\n$stackTrace',
        );
        if (_pendingBroadcastResult != null) {
          try {
            await _signingService?.settlePcztDraftAfterLedgerBroadcast(
              draft: draft,
              status: null,
            );
          } catch (fallbackError, fallbackStackTrace) {
            log(
              'SwapLedgerSigning: retaining checkpointed draft failed: '
              '$fallbackError\n$fallbackStackTrace',
            );
          }
        }
      }
      return;
    }
    await _signingService?.discardPcztDraft(draft: draft);
  }

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    final appInstruction = ledgerZcashAppOpenErrorInstruction(
      ref.read(rpcEndpointProvider).networkName,
    );
    if (isLedgerLegacyOrchardRecoveryUnsupported(error)) {
      return kLedgerLegacyOrchardRecoveryUnavailableMessage;
    }
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
    final legacyOrchardRecoveryUnavailable =
        _error == kLedgerLegacyOrchardRecoveryUnavailableMessage;
    final pendingBroadcastResult = _pendingBroadcastResult;
    final postBroadcastRecovery = pendingBroadcastResult != null;
    final broadcastConfirmed =
        pendingBroadcastResult?.status ==
            SwapDepositBroadcastStatus.broadcasted ||
        pendingBroadcastResult?.status ==
            SwapDepositBroadcastStatus.broadcastedStorageFailed;
    final modal = LedgerSigningModal(
      accountUuid: widget.intent.accountUuid,
      phase: _phase,
      failure: _phase == LedgerSigningModalPhase.failed
          ? LedgerSigningFailurePresentation(
              title: postBroadcastRecovery
                  ? broadcastConfirmed
                        ? 'Transaction sent'
                        : 'Transaction status pending'
                  : legacyOrchardRecoveryUnavailable
                  ? 'Ledger app update required'
                  : 'Ledger signing failed',
              statusLabel: postBroadcastRecovery
                  ? 'Saving transaction'
                  : legacyOrchardRecoveryUnavailable
                  ? 'Recovery unavailable'
                  : 'Action needed',
              message: postBroadcastRecovery
                  ? broadcastConfirmed
                        ? 'The transaction was sent, but Vizor could not finish saving it.'
                        : 'Vizor could not confirm whether the transaction was sent, and still needs to save its status.'
                  : _error ?? 'Ledger signing could not be completed.',
              showDeviceAppPrompt:
                  !postBroadcastRecovery && !legacyOrchardRecoveryUnavailable,
              showConnectionPicker: !postBroadcastRecovery,
              actionLabel: legacyOrchardRecoveryUnavailable
                  ? null
                  : postBroadcastRecovery
                  ? 'Retry saving'
                  : 'Try again',
            )
          : null,
      onCancel: canLeave ? () => unawaited(_cancel()) : null,
      cancelLabel: 'Back to activity',
      onFailureAction:
          _phase == LedgerSigningModalPhase.failed &&
              !legacyOrchardRecoveryUnavailable
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
