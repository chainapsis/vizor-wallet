import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ledger/services/ledger_failure_guidance.dart';
import '../../../../main.dart' show log;
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/zcash/network_upgrade_hold.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../ledger/ledger_error_codes.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/services/ledger_device_selection.dart';
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../../ledger/widgets/ledger_signing_modal.dart';
import '../../ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import '../../../core/navigation/external_action_guard_hold.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../providers/account_provider.dart';
import 'mobile/shield/mobile_shield_scene.dart';
import 'mobile/shield/mobile_shield_backdrop.dart';
import '../../send/services/sapling_params.dart';
import '../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../send/widgets/sapling_params_prompt.dart';
import '../services/hardware_shielding_session.dart';
import '../services/transparent_shielding_service.dart'
    show observeShieldingBroadcast;

typedef LedgerShieldingProgressReader =
    Future<rust_sync.LedgerShieldingProgress> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });

final ledgerShieldingProgressReaderProvider =
    Provider<LedgerShieldingProgressReader>(
      (_) => rust_sync.getLedgerShieldingProgress,
    );

class LedgerShieldSigningOverlay extends ConsumerStatefulWidget {
  const LedgerShieldSigningOverlay({
    required this.onCancel,
    required this.onComplete,
    this.mobile = false,
    this.mobileBackdrop,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onComplete;
  final bool mobile;
  final MobileShieldBackdrop? mobileBackdrop;

  @override
  ConsumerState<LedgerShieldSigningOverlay> createState() =>
      _LedgerShieldSigningOverlayState();
}

class _LedgerShieldSigningOverlayState
    extends ConsumerState<LedgerShieldSigningOverlay> {
  final LedgerConnectionScope _connectionScope = LedgerConnectionScope();
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.preparing;
  bool _showSaplingParamsPrompt = false;
  bool _cancelled = false;
  bool _resumingApproval = false;
  bool _canRetry = false;
  bool _needsSaplingParams = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  LedgerFailureGuidance? _deviceGuidance;
  LedgerRequestFailure? _requestFailure;
  List<int>? _pcztBytes;
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;
  String? _accountUuid;
  String? _operationId;
  bool _operationCheckpointed = false;
  bool _momentStarted = false;
  bool _momentComplete = false;
  late final BigInt _initialAmount;
  BigInt _shieldedTotal = BigInt.zero;
  bool _shieldedTotalKnown = true;
  int _sentRounds = 0;
  BigInt? _roundShielded;
  HardwareShieldingSession? _shieldSession;
  int _round = 1;
  int _roundCount = 1;
  int? _pendingInputs;
  bool _pausedEarly = false;
  String? _network;
  List<int>? _signedPczt;

  late final LedgerOperationCanceller _cancelLedgerOperation;

  bool get _isBroadcasting =>
      _phase == LedgerSigningModalPhase.broadcasting ||
      _phase == LedgerSigningModalPhase.saving;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    final uuid = ref.read(accountProvider).value?.activeAccountUuid;
    final sync = (ref.read(syncProvider).value ?? SyncState()).scopedToAccount(
      uuid,
    );
    _initialAmount = sync.shieldTransparentAmount > BigInt.zero
        ? sync.shieldTransparentAmount + sync.shieldTransparentFee
        : sync.transparentBalance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.mobile) {
        ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      }
      if (!widget.mobile) unawaited(_prepareAndSign());
    });
  }

  @override
  void dispose() {
    final shouldCancelDevice = !_cancelled && !_isBroadcasting;
    _cancelled = true;
    unawaited(_shieldSession?.close());
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
      if (ref.read(ledgerOperationLifecycleProvider).isPaused) {
        throw StateError('Ledger operations are paused for wallet changes.');
      }
      final accountUuid = ref.read(walletProvider).value?.activeAccountUuid;
      if (accountUuid == null) throw StateError('No active account.');
      if (_accountUuid != null && _accountUuid != accountUuid) {
        throw StateError(
          'The selected account changed. Return to your wallet.',
        );
      }
      _accountUuid = accountUuid;
      _network ??= ref.read(rpcEndpointProvider).networkName;
      if (_network != ref.read(rpcEndpointProvider).networkName) {
        throw StateError('The network changed. Return to your wallet.');
      }

      final existingOperation = await _findExistingShieldOperation(accountUuid);
      if (existingOperation != null) {
        _operationId = existingOperation.operationId;
        _operationCheckpointed = true;
        if (existingOperation.state == 'result_pending_ack') {
          if (!mounted || _cancelled) return;
          setState(() {
            _phase = LedgerSigningModalPhase.failed;
            _canRetry = false;
            _error = _broadcastStatusMessage(
              status: existingOperation.status ?? '',
              message: existingOperation.message,
            );
          });
          return;
        }
        _roundShielded = existingOperation.shieldedZatoshi;
        await _broadcastCheckpointed();
        return;
      }

      if (!await (_shieldSession?.close() ?? Future.value(true))) {
        throw StateError('Could not finish cancelling. Please try again.');
      }
      if (!mounted || _cancelled) return;
      final session = _shieldSession = HardwareShieldingSession.forRef(
        ref,
        accountUuid,
      );
      final work = await _readProgress();
      if (!mounted || _cancelled) return;
      if (work.inputCount == 0) {
        _completeShielding();
        return;
      }
      if (work.belowThreshold) {
        _pauseEarly('The remaining funds are below the shielding threshold.');
        return;
      }
      _pendingInputs = work.inputCount;
      setState(() => _roundCount = _round - 1 + _roundsFor(work));

      final dbPath = await ref.read(ledgerWalletDbPathProvider)();
      _requireOriginalContext();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final shieldPczt = await session.prepare(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );
      if (!mounted || _cancelled) return;

      _roundShielded = shieldPczt.shieldedZatoshi;
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
      _requireOriginalContext();
      setState(() {
        _phase = LedgerSigningModalPhase.awaitingDevice;
        _canRetry = true;
        _pcztBytes = shieldPczt.pcztBytes;
        _pcztWithProofs = pcztWithProofs;
        _saplingParams = saplingParams;
        _needsSaplingParams = shieldPczt.needsSaplingParams;
      });

      final signedPczt =
          _signedPczt ??
          await _connectionScope.run<List<int>>(
            () => ref.read(ledgerPcztSignerProvider)(
              accountUuid,
              shieldPczt.pcztBytes,
            ),
          );
      if (!mounted || _cancelled) return;
      _requireOriginalContext();
      _signedPczt = signedPczt;
      setState(() => _phase = LedgerSigningModalPhase.saving);
      final operationId =
          _operationId ??
          newLedgerSignedOperationId(
            kind: LedgerSignedOperationKind.shield,
            accountUuid: accountUuid,
          );
      _operationId = operationId;
      await _shieldSession!.checkpoint(
        () => ref
            .read(ledgerSignedOperationServiceProvider)
            .checkpoint(
              operationId: operationId,
              accountUuid: accountUuid,
              kind: LedgerSignedOperationKind.shield,
              pcztWithProofsBytes: pcztWithProofs,
              pcztWithSignaturesBytes: signedPczt,
            ),
      );
      _operationId = operationId;
      _operationCheckpointed = true;
      await _broadcastCheckpointed();
    } catch (e, st) {
      log('LedgerShieldConfirm._prepareAndSign: ERROR: $e\n$st');
      if (_pcztBytes == null) await _shieldSession?.close();
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _canRetry = true;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _retry() async {
    if (_cancelled || _phase != LedgerSigningModalPhase.failed || !_canRetry) {
      return;
    }
    if (_network != ref.read(rpcEndpointProvider).networkName ||
        _accountUuid != ref.read(walletProvider).value?.activeAccountUuid) {
      _pauseEarly(
        'The selected account or network changed. Return to your wallet.',
      );
      return;
    }
    if (_operationCheckpointed) {
      setState(() {
        _phase = LedgerSigningModalPhase.broadcasting;
        _canRetry = false;
        _error = null;
        _deviceGuidance = null;
        _requestFailure = null;
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
        _deviceGuidance = null;
        _requestFailure = null;
      });
      await _prepareAndSign();
      return;
    }

    setState(() {
      _phase = LedgerSigningModalPhase.awaitingDevice;
      _resumingApproval = true;
      _error = null;
      _deviceGuidance = null;
      _requestFailure = null;
    });
    try {
      final accountUuid = _accountUuid;
      final proofs = _pcztWithProofs;
      if (accountUuid == null || proofs == null) {
        throw StateError('Ledger shield transaction is incomplete.');
      }
      final signedPczt =
          _signedPczt ??
          await _connectionScope.run<List<int>>(
            () => ref.read(ledgerPcztSignerProvider)(accountUuid, pcztBytes),
          );
      if (!mounted || _cancelled) return;
      _requireOriginalContext();
      _signedPczt = signedPczt;
      setState(() => _phase = LedgerSigningModalPhase.saving);
      final operationId =
          _operationId ??
          newLedgerSignedOperationId(
            kind: LedgerSignedOperationKind.shield,
            accountUuid: accountUuid,
          );
      _operationId = operationId;
      await _shieldSession!.checkpoint(
        () => ref
            .read(ledgerSignedOperationServiceProvider)
            .checkpoint(
              operationId: operationId,
              accountUuid: accountUuid,
              kind: LedgerSignedOperationKind.shield,
              pcztWithProofsBytes: proofs,
              pcztWithSignaturesBytes: signedPczt,
            ),
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
    if (!mounted || _cancelled) return;
    final sent = await ref
        .read(ledgerOperationLifecycleProvider)
        .run(_broadcastCheckpointedWithLease);
    // The signed result is durable before the lease ends. Device approval for
    // the next round must remain outside that lease so wallet mutations drain.
    if (sent && mounted && !_cancelled) await _continueOrComplete();
  }

  Future<bool> _broadcastCheckpointedWithLease() async {
    final operationId = _operationId;
    final saplingParams = _saplingParams;
    if (operationId == null || !_operationCheckpointed) {
      throw StateError('Ledger shield transaction is not checkpointed.');
    }
    if (!mounted || _cancelled) return false;

    setState(() {
      _phase = LedgerSigningModalPhase.broadcasting;
      _canRetry = false;
      _error = null;
      _deviceGuidance = null;
      _requestFailure = null;
    });

    try {
      _requireOriginalContext();
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
      observeShieldingBroadcast(
        ref: ref,
        accountUuid: _accountUuid,
        status: result.status,
        txids: [result.txid],
      );
      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('LedgerShieldConfirm: refreshAfterSend failed: $e');
      }
      if (!mounted) return false;
      if (result.status != 'broadcasted') {
        setState(() {
          _phase = LedgerSigningModalPhase.failed;
          _canRetry = false;
          _error = _broadcastStatusMessage(
            status: result.status,
            message: result.message,
          );
        });
        return false;
      }
      _sentRounds++;
      final amount = _roundShielded;
      if (amount != null && amount > BigInt.zero) {
        _shieldedTotal += amount;
      } else {
        _shieldedTotalKnown = false;
      }
      _roundShielded = null;
      return true;
    } catch (e, st) {
      log('LedgerShieldConfirm._broadcast: ERROR: $e\n$st');
      if (isTerminalLedgerSignedOperationError(e)) {
        _operationCheckpointed = false;
        _operationId = null;
      }
      if (!mounted) return false;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _canRetry = true;
        _error = _friendlyError(e);
      });
      return false;
    }
  }

  void _requireOriginalContext() {
    if (_accountUuid == null ||
        _network != ref.read(rpcEndpointProvider).networkName ||
        _accountUuid != ref.read(walletProvider).value?.activeAccountUuid) {
      throw StateError(
        'The selected account or network changed. Return to your wallet.',
      );
    }
  }

  Future<rust_sync.LedgerShieldingProgress> _readProgress() async {
    final uuid = _accountUuid;
    if (uuid == null ||
        _network != ref.read(rpcEndpointProvider).networkName ||
        uuid != ref.read(walletProvider).value?.activeAccountUuid) {
      throw StateError('The selected account or network changed.');
    }
    final dbPath = await ref.read(ledgerWalletDbPathProvider)();
    _requireOriginalContext();
    return ref.read(ledgerShieldingProgressReaderProvider)(
      dbPath: dbPath,
      network: _network!,
      accountUuid: uuid,
    );
  }

  int _roundsFor(rust_sync.LedgerShieldingProgress work) {
    if (work.inputLimit <= 0) throw StateError('Invalid Ledger input limit');
    return (work.inputCount + work.inputLimit - 1) ~/ work.inputLimit;
  }

  void _completeShielding() {
    if (widget.mobile && mounted) {
      if (_sentRounds == 0) {
        _pauseEarly(
          'No spendable transparent funds remain. Return to your wallet.',
        );
        return;
      }
      setState(() => _momentComplete = true);
    } else {
      widget.onComplete();
    }
  }

  Future<void> _continueOrComplete() async {
    if (ref.read(ledgerOperationLifecycleProvider).isPaused) {
      _pauseEarly(
        'Shielding paused while wallet changes finish. Return to your wallet.',
      );
      return;
    }
    final rust_sync.LedgerShieldingProgress work;
    try {
      work = await _readProgress();
    } catch (error) {
      if (!mounted || _cancelled) return;
      _pauseEarly(
        'Round $_round was sent, but the remaining funds could not be checked. Return to your wallet and try again after sync.',
      );
      return;
    }
    if (!mounted || _cancelled) return;
    if (work.inputCount == 0) {
      _completeShielding();
      return;
    }
    if (work.belowThreshold) {
      _pauseEarly(
        'Round $_round was sent. The remaining funds are below the shielding threshold.',
      );
      return;
    }
    if (_pendingInputs == null || work.inputCount >= _pendingInputs!) {
      _pauseEarly(
        'Round $_round was sent, but no reduction in spendable inputs could be confirmed. Wait for sync before shielding again.',
      );
      return;
    }
    setState(() {
      _round++;
      _roundCount = _round - 1 + _roundsFor(work);
      _phase = LedgerSigningModalPhase.preparing;
      _resumingApproval = false;
      _canRetry = false;
      _error = null;
      _deviceGuidance = null;
      _requestFailure = null;
      _pcztBytes = null;
      _pcztWithProofs = null;
      _signedPczt = null;
      _operationId = null;
      _operationCheckpointed = false;
    });
    await _prepareAndSign();
  }

  void _pauseEarly(String message) {
    setState(() {
      _phase = LedgerSigningModalPhase.failed;
      _pausedEarly = true;
      _canRetry = false;
      _error = message;
    });
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

  String _broadcastStatusMessage({
    required String status,
    required String? message,
  }) {
    final upgradeHold = networkUpgradeHoldMessage(message ?? '');
    if (upgradeHold != null) return upgradeHold;
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
    _requestFailure = LedgerRequestFailure.fromError(error);
    final guidance = ledgerFailureGuidance(
      error,
      requestKind: LedgerRequestKind.shield,
    );
    _deviceGuidance = guidance;
    final upgradeHold = networkUpgradeHoldMessage(error);
    if (upgradeHold != null) return upgradeHold;
    // Retrying the same request fails the same way on the device.
    if (guidance?.retryable == false) _canRetry = false;
    final failure = LedgerRequestFailure.fromError(error);
    if (failure == LedgerRequestFailure.requestRejected &&
        classifyLedgerError(error) == LedgerFailureKind.hostRequestRejected &&
        _round > 1) {
      return 'Your Ledger couldn’t accept this approval. Earlier approvals were already sent.';
    }
    if (guidance != null) return guidance.message;
    final lower = error.toString().toLowerCase();
    final appInstruction = ledgerZcashAppOpenErrorInstruction(
      ref.read(rpcEndpointProvider).networkName,
    );
    if (failure == LedgerRequestFailure.declined) {
      return 'The shield transaction was rejected on your Ledger.';
    }
    final usb = ledgerUsbErrorMessage(error, appInstruction: appInstruction);
    if (usb != null) return usb;
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
    if (!mounted || _isBroadcasting || _cancelled) return;
    setState(() => _cancelled = true);
    await _cancelLedgerOperationSafely();
    final released = await _shieldSession?.close() ?? true;
    if (!mounted) return;
    if (!released) {
      setState(() {
        _cancelled = false;
        _canRetry = false;
        _phase = LedgerSigningModalPhase.failed;
        _error = 'Could not finish cancelling. Please try again.';
      });
      return;
    }
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
    final canLeave = !_cancelled && (_momentComplete || !_isBroadcasting);
    final broadcasting = _phase == LedgerSigningModalPhase.broadcasting;
    final upgradeHold = _error == kNetworkUpgradeHoldMessage;
    final modal = LedgerSigningModal(
      cancelling: _cancelled,
      resumingApproval: _resumingApproval,
      connectionScope: _connectionScope,
      accountUuid: _accountUuid,
      roundNumber: _round,
      roundCount: _roundCount,
      roundFeeNotice: !widget.mobile && _roundCount > 1
          ? 'Each approval creates a separate transaction with its own network fee.'
          : null,
      phase: _phase,
      failure: _phase == LedgerSigningModalPhase.failed
          ? LedgerSigningFailurePresentation(
              requestFailure: _requestFailure,
              pairingInvalid: _deviceGuidance?.pairingInvalid ?? false,
              bluetoothRecovery: _deviceGuidance?.bluetoothRecovery ?? false,
              pairingRecovery: _deviceGuidance?.pairingRecovery ?? false,
              isError: !_pausedEarly,
              title: _pausedEarly
                  ? 'Shielding paused'
                  : upgradeHold
                  ? kNetworkUpgradeHoldActionLabel
                  : 'Ledger signing failed',
              statusLabel: _pausedEarly ? 'Inputs remaining' : 'Action needed',
              message: _error ?? 'Ledger shielding could not be completed.',
              showDeviceAppPrompt:
                  !_pausedEarly &&
                  (_deviceGuidance?.showDeviceAppPrompt ?? false),
              showConnectionPicker: !upgradeHold,
              actionLabel: _canRetry ? 'Try again' : null,
            )
          : null,
      onCancel: canLeave ? () => unawaited(_cancelToHome()) : null,
      cancelLabel: 'Back to wallet',
      onFailureAction:
          !_cancelled && _phase == LedgerSigningModalPhase.failed && _canRetry
          ? () => unawaited(_retry())
          : null,
    );
    if (widget.mobile) {
      return ExternalActionGuardHold(
        child: Stack(
          key: const ValueKey('mobile_ledger_shield_signing_surface'),
          fit: StackFit.expand,
          children: [
            MobileShieldScene(
              backdrop: widget.mobileBackdrop,
              animateHardware: true,
              phase: !_momentStarted
                  ? MobileShieldPhase.review
                  : _momentComplete
                  ? MobileShieldPhase.succeeded
                  : _phase == LedgerSigningModalPhase.failed
                  ? MobileShieldPhase.failed
                  : broadcasting
                  ? MobileShieldPhase.working
                  : MobileShieldPhase.hardware,
              amount: formatZecAmount(_initialAmount),
              resultAmount: _shieldedTotal > BigInt.zero
                  ? formatZecAmount(_shieldedTotal)
                  : null,
              showResultAmount: _shieldedTotalKnown,
              title: !_momentStarted
                  ? 'Transparent Balance'
                  : _momentComplete
                  ? 'Shielded successfully'
                  : broadcasting
                  ? 'Shielding your balance…'
                  : 'Shield with Ledger',
              focusChild: _momentStarted && !_momentComplete && !broadcasting
                  ? LedgerInlinePresentation(
                      closeLabel: _phase == LedgerSigningModalPhase.failed
                          ? 'Close'
                          : 'Cancel shielding',
                      child: modal,
                    )
                  : null,
              canLeave: canLeave,
              onCommit: () {
                if (_momentStarted) return;
                setState(() => _momentStarted = true);
                unawaited(_prepareAndSign());
              },
              onClose: _momentComplete
                  ? widget.onComplete
                  : () => unawaited(_cancelToHome()),
              onComplete: widget.onComplete,
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
