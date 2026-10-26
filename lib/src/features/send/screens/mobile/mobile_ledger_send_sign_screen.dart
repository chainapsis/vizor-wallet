import 'dart:async';

import '../../../ledger/services/ledger_failure_guidance.dart';
import '../../../../providers/sync_provider.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../ledger/ledger_capability.dart';
import '../../../ledger/services/ledger_signed_operation_service.dart';
import '../../../ledger/services/ledger_signing_service.dart';
import '../../../ledger/services/ledger_device_selection.dart';
import '../../../ledger/widgets/ledger_device_app_prompt.dart';
import '../../../ledger/widgets/ledger_signing_modal.dart';
import '../../../ledger/widgets/mobile_ledger_signing_surface.dart';
import '../../services/sapling_params.dart';
import '../../services/send_flow.dart';
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;
import '../../../../core/zcash/network_upgrade_hold.dart';

enum _LedgerSendRecoveryAction {
  retrySigning,
  createNewTransaction,
  retryCheckpoint,
}

typedef MobileLedgerSendPcztCreator =
    Future<List<int>> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required BigInt proposalId,
      required String sendFlowId,
    });
typedef MobileLedgerSendTexPcztsCreator =
    Future<rust_sync.TexPcztPairResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required BigInt proposalId,
      required String sendFlowId,
    });
typedef MobileLedgerSendPcztRedactor =
    Future<List<int>> Function({required List<int> pcztBytes});
typedef MobileLedgerSendProofAdder =
    Future<List<int>> Function({
      required List<int> pcztBytes,
      String? spendParamsPath,
      String? outputParamsPath,
    });

class _LedgerProofFailure {
  const _LedgerProofFailure(this.cause);
  final Object cause;
  @override
  String toString() => cause.toString();
}

/// Mobile-native Ledger signing surface for a standard Send proposal.
///
/// The proof-bearing PCZT and signer-redacted PCZT deliberately remain
/// separate until the signed operation has been durably checkpointed.
class MobileLedgerSendSignScreen extends ConsumerStatefulWidget {
  const MobileLedgerSendSignScreen({
    required this.args,
    this.loadWalletDbPath,
    this.loadSaplingParams,
    this.createPczt,
    this.createTexPczts,
    this.redactPczt,
    this.addProofs,
    this.discardProposal,
    super.key,
  });

  final SendReviewArgs args;

  @visibleForTesting
  final Future<String> Function()? loadWalletDbPath;

  @visibleForTesting
  final Future<SaplingParamsStatus> Function()? loadSaplingParams;

  @visibleForTesting
  final MobileLedgerSendPcztCreator? createPczt;

  @visibleForTesting
  final MobileLedgerSendTexPcztsCreator? createTexPczts;

  @visibleForTesting
  final MobileLedgerSendPcztRedactor? redactPczt;

  @visibleForTesting
  final MobileLedgerSendProofAdder? addProofs;

  @visibleForTesting
  final Future<bool> Function()? discardProposal;

  @override
  ConsumerState<MobileLedgerSendSignScreen> createState() =>
      _MobileLedgerSendSignScreenState();
}

class _MobileLedgerSendSignScreenState
    extends ConsumerState<MobileLedgerSendSignScreen> {
  final LedgerConnectionScope _connectionScope = LedgerConnectionScope();
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.preparing;
  LedgerSigningFailurePresentation? _failure;
  _LedgerSendRecoveryAction? _recoveryAction;
  List<List<int>>? _basePczts;
  Future<List<List<int>>>? _basePcztsFuture;
  List<List<int>>? _redactedPczts;
  List<List<int>>? _pcztsWithProofs;
  Future<void>? _proofsFuture;
  final List<List<int>> _signedPczts = [];
  var _round = 0;
  var _attemptGeneration = 0;
  var _ownershipTransferred = false;
  var _checkpointStarted = false;
  Future<bool>? _discardFuture;
  var _releasing = false;
  var _cancelled = false;
  var _drainingFailure = false;
  var _resumingApproval = false;
  late final SyncNotifier? _syncNotifier;
  late final String _operationId;
  late final LedgerOperationCanceller _cancelOperation;

  @override
  void initState() {
    super.initState();
    _syncNotifier = widget.discardProposal == null
        ? ref.read(syncProvider.notifier)
        : null;
    _cancelOperation = ref.read(ledgerOperationCancellerProvider);
    _operationId =
        'send:${widget.args.proposalAccountUuid}:${widget.args.sendFlowId}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startSigning();
    });
  }

  @override
  void dispose() {
    _attemptGeneration++;
    if (!_ownershipTransferred) {
      if (!_signingComplete && !_cancelled) {
        unawaited(_cancelOperationSafely());
      }
      // Approval alone does not transfer the proposal. Preserve inputs only
      // once saving starts, because its native commit can outlive this screen.
      if (!_checkpointStarted) {
        unawaited(_releaseProposal('MobileLedgerSendSign(dispose)'));
      }
    }
    super.dispose();
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _attemptGeneration;

  bool get _signingComplete =>
      _basePczts != null &&
      _basePczts!.isNotEmpty &&
      _signedPczts.length == _basePczts!.length;

  void _startSigning() {
    if ((_signingComplete && _pcztsWithProofs != null) ||
        _cancelled ||
        _drainingFailure) {
      return;
    }
    final generation = ++_attemptGeneration;
    setState(() {
      _resumingApproval = _redactedPczts != null;
      _phase = _signingComplete
          ? LedgerSigningModalPhase.finishing
          : LedgerSigningModalPhase.preparing;
      _failure = null;
      _recoveryAction = null;
    });
    unawaited(_prepareAndSign(generation));
  }

  Future<void> _prepareAndSign(int generation) async {
    Future<void>? signing;
    try {
      final dbPath = await (widget.loadWalletDbPath ?? getWalletDbPath)();
      if (!_isCurrent(generation)) return;
      var saplingParams =
          await (widget.loadSaplingParams ?? loadSaplingParamsStatus)();
      if (!_isCurrent(generation)) return;

      if (widget.args.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _confirmSaplingParamsDownload();
        if (!_isCurrent(generation)) return;
        if (!confirmed) {
          await _cancelAndPop();
          return;
        }
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('MobileLedgerSendSign: $message'),
        );
        if (!_isCurrent(generation)) return;
        saplingParams =
            await (widget.loadSaplingParams ?? loadSaplingParamsStatus)();
        if (!_isCurrent(generation)) return;
      }

      // PCZT creation consumes the proposal; select the live route once and
      // never retry the consumed proposal through a generic failover runner.
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final basePczts = await _getOrCreateBasePczts(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );
      if (!_isCurrent(generation)) return;

      var redactedPczts = _redactedPczts;
      if (redactedPczts == null) {
        final redacted = <List<int>>[];
        for (final pczt in basePczts) {
          redacted.add(
            List<int>.unmodifiable(
              await (widget.redactPczt ?? rust_sync.redactPcztForSigner)(
                pcztBytes: pczt,
              ),
            ),
          );
          if (!_isCurrent(generation)) return;
        }
        redactedPczts = List<List<int>>.unmodifiable(redacted);
        _redactedPczts = redactedPczts;
      }

      // These branches consume separate copies of the same fixed transaction.
      // Observe both immediately, but keep Ledger approval rounds sequential.
      final proving = _prepareProofs(basePczts, saplingParams).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            Error.throwWithStackTrace(_LedgerProofFailure(error), stack),
      );
      signing = _signPendingPczts(generation, redactedPczts);
      await Future.wait([proving, signing], eagerError: true);
      if (!_isCurrent(generation)) return;
      setState(() {
        _phase = LedgerSigningModalPhase.saving;
        _failure = null;
        _recoveryAction = null;
      });
    } catch (error, stackTrace) {
      log('MobileLedgerSendSign._prepareAndSign: ERROR: $error\n$stackTrace');
      if (!_isCurrent(generation)) return;
      if (error is _LedgerProofFailure) {
        // A proof failure must end the active device request before retry.
        // Invalidate its late result without discarding earlier signed rounds.
        final recoveryGeneration = ++_attemptGeneration;
        setState(() => _drainingFailure = true);
        if (!_signingComplete) {
          await _cancelOperationSafely();
          try {
            await signing;
          } catch (_) {
            // Keep the original proof failure as the recovery reason.
          }
          // Cancellation also invalidates a cached connection's guard. A
          // request cancelled before transport entry cannot clear it itself.
          _connectionScope.changeConnection();
        }
        if (!_isCurrent(recoveryGeneration)) return;
        setState(() {
          _drainingFailure = false;
          _phase = LedgerSigningModalPhase.failed;
          _failure = LedgerSigningFailurePresentation(
            title: 'Could not finish transaction',
            statusLabel: 'Action needed',
            message: _signingComplete
                ? 'Keep Vizor open and try again. No new Ledger approval needed.'
                : 'Vizor could not prepare the transaction. Try again.',
            showDeviceAppPrompt: false,
            actionLabel: 'Try again',
          );
          _recoveryAction = _LedgerSendRecoveryAction.retrySigning;
        });
        return;
      }
      _setPreSignatureFailure(error);
      return;
    }

    await _checkpoint(generation);
  }

  Future<void> _prepareProofs(
    List<List<int>> basePczts,
    SaplingParamsStatus params,
  ) {
    if (_pcztsWithProofs != null) return Future<void>.value();
    if (_proofsFuture case final existing?) return existing;
    final addProofs = widget.addProofs ?? rust_sync.addProofsToPczt;
    final needsSaplingParams = widget.args.needsSaplingParams;
    final work = () async {
      final proved = <List<int>>[];
      for (final pczt in basePczts) {
        proved.add(
          List<int>.unmodifiable(
            await addProofs(
              pcztBytes: pczt,
              spendParamsPath: needsSaplingParams ? params.spendPath : null,
              outputParamsPath: needsSaplingParams ? params.outputPath : null,
            ),
          ),
        );
        // A proof already running in Rust owns its bytes and may finish after
        // cancellation. Do not start another round or publish its result then.
        if (!mounted || _cancelled) return;
      }
      _pcztsWithProofs = List<List<int>>.unmodifiable(proved);
    }();
    _proofsFuture = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_proofsFuture, work)) _proofsFuture = null;
        },
      ),
    );
    return work;
  }

  Future<void> _signPendingPczts(
    int generation,
    List<List<int>> signerPczts,
  ) async {
    for (var index = _signedPczts.length; index < signerPczts.length; index++) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _round = index;
        _phase = LedgerSigningModalPhase.awaitingDevice;
      });
      final signedPczt = await _connectionScope.run(
        () => ref.read(ledgerPcztSignerProvider)(
          widget.args.proposalAccountUuid,
          signerPczts[index],
        ),
      );
      if (!_isCurrent(generation)) return;
      _signedPczts.add(List<int>.unmodifiable(signedPczt));
    }
    if (_isCurrent(generation) && _pcztsWithProofs == null) {
      setState(() => _phase = LedgerSigningModalPhase.finishing);
    }
  }

  Future<List<List<int>>> _getOrCreateBasePczts({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
  }) async {
    if (_basePczts case final cached?) return cached;
    if (_basePcztsFuture case final existing?) return existing;

    final future =
        (widget.args.addressType == 'tex'
                ? (widget.createTexPczts ??
                          rust_sync.createTexPcztsFromProposal)(
                        dbPath: dbPath,
                        lightwalletdUrl: lightwalletdUrl,
                        network: network,
                        proposalId: widget.args.proposalId,
                        sendFlowId: widget.args.sendFlowId,
                      )
                      .then((result) => result.pczts)
                : (widget.createPczt ?? rust_sync.createPcztFromProposal)(
                    dbPath: dbPath,
                    lightwalletdUrl: lightwalletdUrl,
                    network: network,
                    proposalId: widget.args.proposalId,
                    sendFlowId: widget.args.sendFlowId,
                  ).then((pczt) => <List<int>>[pczt]))
            .then<List<List<int>>>((value) {
              _basePczts ??= List<List<int>>.unmodifiable(
                value.map(List<int>.unmodifiable),
              );
              return _basePczts!;
            });
    _basePcztsFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_basePcztsFuture, future)) _basePcztsFuture = null;
    }
  }

  Future<bool> _confirmSaplingParamsDownload() async {
    if (!mounted) return false;
    return await showAppMobileSheet<bool>(
          context: context,
          isDismissible: false,
          builder: (_) => const MobileSaplingParamsSheet(),
        ) ==
        true;
  }

  void _setPreSignatureFailure(Object error) {
    final lower = error.toString().toLowerCase();
    final guidance = ledgerFailureGuidance(error);
    final appInstruction = ledgerZcashAppOpenErrorInstruction(
      ref.read(rpcEndpointProvider).networkName,
    );
    late final LedgerSigningFailurePresentation presentation;
    late final _LedgerSendRecoveryAction? action;

    final upgradeHold = networkUpgradeHoldMessage(error);
    if (upgradeHold != null) {
      // Nothing to do here until the upgrade; the sheet only closes.
      presentation = LedgerSigningFailurePresentation(
        title: kNetworkUpgradeHoldActionLabel,
        statusLabel: 'Action needed',
        message: upgradeHold,
        showDeviceAppPrompt: false,
      );
      action = null;
    } else if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      presentation = const LedgerSigningFailurePresentation(
        title: 'Transaction expired',
        statusLabel: 'New transaction required',
        message:
            'This transaction can no longer be signed. Create and review a new transaction.',
        showDeviceAppPrompt: false,
        actionLabel: 'Create new transaction',
      );
      action = _LedgerSendRecoveryAction.createNewTransaction;
    } else if (isLedgerLegacyOrchardRecoveryUnsupported(error)) {
      presentation = const LedgerSigningFailurePresentation(
        title: 'Ledger app update required',
        statusLabel: 'Recovery unavailable',
        message: kLedgerLegacyOrchardRecoveryUnavailableMessage,
        showDeviceAppPrompt: false,
      );
      action = null;
    } else if (lower.contains('sapling')) {
      presentation = const LedgerSigningFailurePresentation(
        title: 'Ledger signing unavailable',
        statusLabel: 'Unsupported transaction',
        message: kLedgerSaplingRecipientMessage,
        showDeviceAppPrompt: false,
      );
      action = null;
    } else if (guidance != null && !guidance.retryable) {
      // Retrying the same request fails the same way on the device.
      presentation = LedgerSigningFailurePresentation(
        title: LedgerRequestFailure.fromError(error).title,
        statusLabel: 'New transaction required',
        message: guidance.message,
        showDeviceAppPrompt: false,
        actionLabel: 'Create new transaction',
      );
      action = _LedgerSendRecoveryAction.createNewTransaction;
    } else if (guidance != null) {
      presentation = LedgerSigningFailurePresentation(
        title: 'Ledger needs attention',
        requestFailure: LedgerRequestFailure.fromError(error),
        statusLabel: 'Action needed',
        message: guidance.message,
        showDeviceAppPrompt: guidance.showDeviceAppPrompt,
        bluetoothRecovery: guidance.bluetoothRecovery,
        pairingRecovery: guidance.pairingRecovery,
        pairingInvalid: guidance.pairingInvalid,
        actionLabel: 'Try again',
      );
      action = _LedgerSendRecoveryAction.retrySigning;
    } else {
      final message = switch (LedgerRequestFailure.fromError(error)) {
        LedgerRequestFailure.declined =>
          'The transaction was rejected on your Ledger.',
        LedgerRequestFailure.transportLost =>
          ledgerUsbErrorMessage(error, appInstruction: appInstruction) ??
              'Connect and unlock your Ledger. $appInstruction',
        _ =>
          'Ledger signing could not be completed. Check your device and try again.',
      };
      presentation = LedgerSigningFailurePresentation(
        title: 'Ledger signing failed',
        requestFailure: LedgerRequestFailure.fromError(error),
        statusLabel: 'Action needed',
        message: message,
        showDeviceAppPrompt: false,
        actionLabel: 'Try again',
      );
      action = _LedgerSendRecoveryAction.retrySigning;
    }

    setState(() {
      _phase = LedgerSigningModalPhase.failed;
      _failure = presentation;
      _recoveryAction = action;
    });
  }

  Future<void> _checkpoint(int generation) async {
    final proofs = _pcztsWithProofs;
    if (proofs == null || !_signingComplete) return;
    try {
      final operationService = ref.read(ledgerSignedOperationServiceProvider);
      if (proofs.length == 1) {
        _checkpointStarted = true;
        await operationService.checkpoint(
          operationId: _operationId,
          accountUuid: widget.args.proposalAccountUuid,
          kind: LedgerSignedOperationKind.send,
          pcztWithProofsBytes: proofs.single,
          pcztWithSignaturesBytes: _signedPczts.single,
        );
      } else if (operationService
          case final LedgerSignedOperationBatchCheckpointService batchService) {
        _checkpointStarted = true;
        await batchService.checkpointBatch(
          operationId: _operationId,
          accountUuid: widget.args.proposalAccountUuid,
          kind: LedgerSignedOperationKind.send,
          pcztsWithProofs: proofs,
          pcztsWithSignatures: _signedPczts,
        );
      } else {
        throw StateError(
          'Ledger operation service does not support PCZT batches',
        );
      }
    } catch (error, stackTrace) {
      log('MobileLedgerSendSign._checkpoint: ERROR: $error\n$stackTrace');
      if (!_isCurrent(generation)) return;
      final terminal = isTerminalLedgerSignedOperationError(error);
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _failure = LedgerSigningFailurePresentation(
          title: terminal
              ? 'Signed transaction needs attention'
              : 'Could not save signed transaction',
          statusLabel: terminal ? 'Recovery required' : 'Action needed',
          message: terminal
              ? 'Vizor could not verify the saved transaction. Do not sign or send it again.'
              : 'Keep Vizor open and retry saving. No new Ledger approval needed.',
          showDeviceAppPrompt: false,
          actionLabel: terminal ? null : 'Retry saving',
        );
        _recoveryAction = terminal
            ? null
            : _LedgerSendRecoveryAction.retryCheckpoint;
      });
      return;
    }

    if (!_isCurrent(generation)) return;
    _ownershipTransferred = true;
    if (!mounted) return;
    context.pop(
      LedgerBroadcastArgs(reviewArgs: widget.args, operationId: _operationId),
    );
  }

  void _handleFailureAction() {
    if (_cancelled) return;
    switch (_recoveryAction) {
      case _LedgerSendRecoveryAction.retrySigning:
        _startSigning();
      case _LedgerSendRecoveryAction.retryCheckpoint:
        final generation = ++_attemptGeneration;
        setState(() {
          _phase = LedgerSigningModalPhase.saving;
          _failure = null;
          _recoveryAction = null;
        });
        unawaited(_checkpoint(generation));
      case _LedgerSendRecoveryAction.createNewTransaction:
        unawaited(_createNewTransaction());
      case null:
        return;
    }
  }

  // The replacement send must not read balances while this proposal's inputs
  // are still locked, so release and refresh finish before navigating.
  Future<void> _createNewTransaction() async {
    if (_releasing) return;
    _attemptGeneration++;
    setState(() => _releasing = true);
    final released = await _releaseProposal('MobileLedgerSendSign(expired)');
    if (!mounted) return;
    if (released) {
      ref.read(sendStatusRoutePayloadProvider.notifier).clear();
      context.go('/send');
      return;
    }
    final failure = _failure;
    setState(() {
      _releasing = false;
      if (failure != null) {
        _failure = LedgerSigningFailurePresentation(
          title: failure.title,
          requestFailure: failure.requestFailure,
          statusLabel: failure.statusLabel,
          message: 'Could not finish cancelling. Please try again.',
          showDeviceAppPrompt: false,
          actionLabel: failure.actionLabel,
        );
      }
    });
  }

  Future<void> _cancelAndPop() async {
    if (_signingComplete || _cancelled || _releasing || _drainingFailure) {
      return;
    }
    setState(() => _cancelled = true);
    _attemptGeneration++;
    await _cancelOperationSafely();
    // Creation may still reserve inputs after the device cancellation returns.
    // Drain it before handing release and fee refresh back to the review.
    try {
      await _basePcztsFuture;
    } catch (_) {
      // Failed creators still require the review's idempotent cleanup.
    }
    if (!mounted) return;
    final discard = widget.discardProposal;
    if (discard != null) await discard();
    if (!mounted) return;
    _ownershipTransferred = true;
    context.pop();
  }

  Future<void> _cancelOperationSafely() async {
    try {
      await _cancelOperation();
    } catch (error, stackTrace) {
      log('MobileLedgerSendSign.cancel: ERROR: $error\n$stackTrace');
    }
  }

  Future<bool> _releaseProposal(String logContext) {
    final creation = _basePcztsFuture;
    final discard = widget.discardProposal;
    final args = widget.args;
    final syncNotifier = _syncNotifier;
    return _discardFuture ??=
        () async {
          try {
            await creation;
          } catch (_) {
            // A failed creator still needs idempotent proposal cleanup.
          }
          if (discard != null) return discard();
          return discardSendProposal(
            proposalId: args.proposalId,
            sendFlowId: args.sendFlowId,
            logContext: logContext,
            syncNotifier: syncNotifier!,
            accountUuid: args.proposalAccountUuid,
          );
        }().then((released) {
          if (!released) _discardFuture = null;
          return released;
        });
  }

  @override
  Widget build(BuildContext context) {
    final canLeave =
        !_signingComplete && !_cancelled && !_releasing && !_drainingFailure;
    return MobileLedgerSigningSurface(
      key: const ValueKey('mobile_ledger_signing_surface'),
      title: 'Confirm transaction',
      canLeave: canLeave,
      onBack: () => unawaited(_cancelAndPop()),
      child: LedgerSigningModal(
        cancelling: _cancelled || _releasing || _drainingFailure,
        resumingApproval: _resumingApproval,
        accountUuid: widget.args.proposalAccountUuid,
        phase: _phase,
        failure: _failure,
        roundNumber: _round + 1,
        roundCount: _basePczts?.length ?? 1,
        onCancel: canLeave ? () => unawaited(_cancelAndPop()) : null,
        onFailureAction:
            !_cancelled &&
                !_releasing &&
                _phase == LedgerSigningModalPhase.failed &&
                _recoveryAction != null
            ? _handleFailureAction
            : null,
      ),
    );
  }
}
