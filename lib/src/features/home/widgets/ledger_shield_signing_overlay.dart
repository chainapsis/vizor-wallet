import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../../ledger/widgets/ledger_signing_modal.dart';
import '../../ledger/widgets/mobile_ledger_signing_surface.dart';
import '../../send/services/sapling_params.dart';
import '../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../send/widgets/sapling_params_prompt.dart';

class LedgerShieldSigningOverlay extends ConsumerStatefulWidget {
  const LedgerShieldSigningOverlay({
    required this.onCancel,
    required this.onComplete,
    this.mobile = false,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onComplete;
  final bool mobile;

  @override
  ConsumerState<LedgerShieldSigningOverlay> createState() =>
      _LedgerShieldSigningOverlayState();
}

class _LedgerShieldSigningOverlayState
    extends ConsumerState<LedgerShieldSigningOverlay> {
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.preparing;
  bool _showSaplingParamsPrompt = false;
  bool _cancelled = false;
  bool _canRetry = false;
  bool _needsSaplingParams = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  List<int>? _pcztBytes;
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;
  String? _accountUuid;
  String? _operationId;
  bool _operationCheckpointed = false;
  late final LedgerOperationCanceller _cancelLedgerOperation;

  bool get _isBroadcasting => _phase == LedgerSigningModalPhase.broadcasting;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.mobile) {
        ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      }
      unawaited(_prepareAndSign());
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
    super.dispose();
  }

  Future<void> _prepareAndSign() async {
    try {
      final accountUuid = ref.read(walletProvider).value?.activeAccountUuid;
      if (accountUuid == null) throw StateError('No active account.');
      _accountUuid = accountUuid;

      final existingOperation = await _findExistingShieldOperation(accountUuid);
      if (existingOperation != null) {
        _operationId = existingOperation.operationId;
        _operationCheckpointed = true;
        if (existingOperation.state == 'result_pending_ack') {
          if (!mounted || _cancelled) return;
          setState(() {
            _phase = LedgerSigningModalPhase.failed;
            _canRetry = false;
            _error =
                existingOperation.message ??
                'The shield transaction status is uncertain. Check activity before trying again.';
          });
          return;
        }
        await _broadcastCheckpointed();
        return;
      }

      final dbPath = await ref.read(ledgerWalletDbPathProvider)();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final shieldPczt = await rust_sync.createShieldTransparentPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      );

      var saplingParams = await loadSaplingParamsStatus();
      if (shieldPczt.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!confirmed) {
          throw StateError(
            'Shielding was cancelled before proving parameters were downloaded.',
          );
        }
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('LedgerShieldConfirm: $message'),
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
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.awaitingDevice;
        _canRetry = true;
        _pcztBytes = shieldPczt.pcztBytes;
        _pcztWithProofs = pcztWithProofs;
        _saplingParams = saplingParams;
        _needsSaplingParams = shieldPczt.needsSaplingParams;
      });

      final signedPczt = await ref.read(ledgerPcztSignerProvider)(
        accountUuid,
        shieldPczt.pcztBytes,
      );
      if (!mounted || _cancelled) return;
      final operationId = newLedgerSignedOperationId(
        kind: LedgerSignedOperationKind.shield,
        accountUuid: accountUuid,
      );
      await ref
          .read(ledgerSignedOperationServiceProvider)
          .checkpoint(
            operationId: operationId,
            accountUuid: accountUuid,
            kind: LedgerSignedOperationKind.shield,
            pcztWithProofsBytes: pcztWithProofs,
            pcztWithSignaturesBytes: signedPczt,
          );
      _operationId = operationId;
      _operationCheckpointed = true;
      await _broadcastCheckpointed();
    } catch (e, st) {
      log('LedgerShieldConfirm._prepareAndSign: ERROR: $e\n$st');
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _canRetry = true;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _retry() async {
    if (_phase != LedgerSigningModalPhase.failed || !_canRetry) return;
    if (_operationCheckpointed) {
      setState(() {
        _phase = LedgerSigningModalPhase.broadcasting;
        _canRetry = false;
        _error = null;
      });
      try {
        await _broadcastCheckpointed();
      } catch (e, st) {
        log('LedgerShieldConfirm._retryCheckpoint: ERROR: $e\n$st');
        if (!mounted || _cancelled) return;
        setState(() {
          _phase = LedgerSigningModalPhase.failed;
          _canRetry = true;
          _error = _friendlyError(e);
        });
      }
      return;
    }
    final pcztBytes = _pcztBytes;
    if (pcztBytes == null) {
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
      final accountUuid = _accountUuid;
      final proofs = _pcztWithProofs;
      if (accountUuid == null || proofs == null) {
        throw StateError('Ledger shield transaction is incomplete.');
      }
      final signedPczt = await ref.read(ledgerPcztSignerProvider)(
        accountUuid,
        pcztBytes,
      );
      if (!mounted || _cancelled) return;
      final operationId = newLedgerSignedOperationId(
        kind: LedgerSignedOperationKind.shield,
        accountUuid: accountUuid,
      );
      await ref
          .read(ledgerSignedOperationServiceProvider)
          .checkpoint(
            operationId: operationId,
            accountUuid: accountUuid,
            kind: LedgerSignedOperationKind.shield,
            pcztWithProofsBytes: proofs,
            pcztWithSignaturesBytes: signedPczt,
          );
      _operationId = operationId;
      _operationCheckpointed = true;
      await _broadcastCheckpointed();
    } catch (e, st) {
      log('LedgerShieldConfirm._retry: ERROR: $e\n$st');
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _broadcastCheckpointed() async {
    final operationId = _operationId;
    final saplingParams = _saplingParams;
    if (operationId == null || !_operationCheckpointed) {
      throw StateError('Ledger shield transaction is not checkpointed.');
    }
    if (!mounted || _cancelled) return;

    setState(() {
      _phase = LedgerSigningModalPhase.broadcasting;
      _canRetry = false;
      _error = null;
    });

    RpcEndpointConfig? attemptedEndpoint;
    try {
      attemptedEndpoint = ref.read(rpcEndpointFailoverProvider).current;
      final result = await ref
          .read(ledgerSignedOperationServiceProvider)
          .broadcast(
            operationId: operationId,
            spendParamsPath: _needsSaplingParams
                ? saplingParams?.spendPath
                : null,
            outputParamsPath: _needsSaplingParams
                ? saplingParams?.outputPath
                : null,
          );
      if (result.status != 'broadcasted' && result.message != null) {
        await _maybeSwitchBroadcastEndpoint(result.message!, attemptedEndpoint);
      }
      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('LedgerShieldConfirm: refreshAfterSend failed: $e');
      }
      if (!mounted) return;
      if (result.status != 'broadcasted') {
        setState(() {
          _phase = LedgerSigningModalPhase.failed;
          _canRetry = false;
          _error = _broadcastStatusMessage(
            status: result.status,
            message: result.message,
          );
        });
        return;
      }
      widget.onComplete();
    } catch (e, st) {
      log('LedgerShieldConfirm._broadcast: ERROR: $e\n$st');
      await _maybeSwitchBroadcastEndpoint(e, attemptedEndpoint);
      if (isTerminalLedgerSignedOperationError(e)) {
        _operationCheckpointed = false;
        _operationId = null;
      }
      if (!mounted) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _canRetry = true;
        _error = _friendlyError(e);
      });
    }
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

  Future<void> _maybeSwitchBroadcastEndpoint(
    Object error,
    RpcEndpointConfig? attemptedEndpoint,
  ) async {
    final switched = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          error,
          endpoint: attemptedEndpoint,
          operation: 'ledger shield broadcast',
        );
    if (switched) {
      unawaited(ref.read(syncProvider.notifier).restartSync());
    }
  }

  String _broadcastStatusMessage({
    required String status,
    required String? message,
  }) {
    if (status == 'broadcast_unknown') {
      return message ??
          'The shield transaction may have reached the network. Check activity before trying again.';
    }
    if (status == 'broadcasted_storage_failed') {
      return message ??
          'The shield transaction reached the network but was not stored locally. Do not try again until sync confirms it.';
    }
    return message ??
        'The shield transaction status is uncertain. Check activity before trying again.';
  }

  Future<LedgerSignedOperationMetadata?> _findExistingShieldOperation(
    String accountUuid,
  ) async {
    final operations = await ref
        .read(ledgerSignedOperationServiceProvider)
        .list();
    for (final operation in operations) {
      if (operation.accountUuid == accountUuid &&
          operation.kind == LedgerSignedOperationKind.shield) {
        return operation;
      }
    }
    return null;
  }

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    final appInstruction = ledgerZcashAppOpenErrorInstruction(
      ref.read(rpcEndpointProvider).networkName,
    );
    if (lower.contains('rejected') || lower.contains('6985')) {
      return 'The shield transaction was rejected on your Ledger.';
    }
    if (lower.contains('no ledger') || lower.contains('hid')) {
      return 'Connect and unlock your Ledger. $appInstruction';
    }
    if (lower.contains('sync')) {
      return 'Sync the wallet before shielding transparent balance.';
    }
    if (lower.contains('threshold') ||
        lower.contains('too small') ||
        lower.contains('no transparent funds')) {
      return 'Transparent balance is too small to shield after fees.';
    }
    if (lower.contains('sapling')) {
      return 'This Ledger preview does not support Sapling inputs or outputs.';
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return 'Shield transaction could not be broadcast.';
    }
    return 'Ledger shielding could not be completed.';
  }

  Future<void> _cancelToHome() async {
    if (_isBroadcasting) return;
    _cancelled = true;
    await _cancelLedgerOperationSafely();
    widget.onCancel();
  }

  Future<void> _cancelLedgerOperationSafely() async {
    try {
      await _cancelLedgerOperation();
    } catch (e, st) {
      log('LedgerShieldConfirm.cancel: ERROR: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = !_isBroadcasting;
    final modal = LedgerSigningModal(
      accountUuid: _accountUuid,
      phase: _phase,
      failure: _phase == LedgerSigningModalPhase.failed
          ? LedgerSigningFailurePresentation(
              title: 'Ledger signing failed',
              statusLabel: 'Action needed',
              message: _error ?? 'Ledger shielding could not be completed.',
              showDeviceAppPrompt: true,
              actionLabel: _canRetry ? 'Try again' : null,
            )
          : null,
      onCancel: canLeave ? () => unawaited(_cancelToHome()) : null,
      cancelLabel: 'Back to wallet',
      onFailureAction: _phase == LedgerSigningModalPhase.failed && _canRetry
          ? () => unawaited(_retry())
          : null,
    );
    if (widget.mobile) {
      return Stack(
        key: const ValueKey('mobile_ledger_shield_signing_surface'),
        fit: StackFit.expand,
        children: [
          MobileLedgerSigningSurface(
            title: 'Shield with Ledger',
            canLeave: canLeave,
            onBack: () => unawaited(_cancelToHome()),
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
      key: const ValueKey('ledger_shield_signing_overlay_surface'),
      fit: StackFit.expand,
      children: [
        AppPaneModalOverlay(
          onDismiss: _isBroadcasting ? () {} : () => unawaited(_cancelToHome()),
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
