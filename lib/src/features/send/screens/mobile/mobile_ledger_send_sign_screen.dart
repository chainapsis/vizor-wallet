import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../ledger/services/ledger_signed_operation_service.dart';
import '../../../ledger/services/ledger_signing_service.dart';
import '../../../ledger/widgets/ledger_device_app_prompt.dart';
import '../../../ledger/widgets/ledger_signing_modal.dart';
import '../../../ledger/widgets/mobile_ledger_signing_surface.dart';
import '../../services/sapling_params.dart';
import '../../services/send_flow.dart';
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

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
typedef MobileLedgerSendPcztRedactor =
    Future<List<int>> Function({required List<int> pcztBytes});
typedef MobileLedgerSendProofAdder =
    Future<List<int>> Function({
      required List<int> pcztBytes,
      String? spendParamsPath,
      String? outputParamsPath,
    });

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
  final MobileLedgerSendPcztRedactor? redactPczt;

  @visibleForTesting
  final MobileLedgerSendProofAdder? addProofs;

  @visibleForTesting
  final Future<void> Function()? discardProposal;

  @override
  ConsumerState<MobileLedgerSendSignScreen> createState() =>
      _MobileLedgerSendSignScreenState();
}

class _MobileLedgerSendSignScreenState
    extends ConsumerState<MobileLedgerSendSignScreen> {
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.preparing;
  LedgerSigningFailurePresentation? _failure;
  _LedgerSendRecoveryAction? _recoveryAction;
  List<int>? _basePczt;
  Future<List<int>>? _basePcztFuture;
  List<int>? _redactedPczt;
  List<int>? _pcztWithProofs;
  List<int>? _signedPczt;
  var _attemptGeneration = 0;
  var _ownershipTransferred = false;
  var _discardScheduled = false;
  var _cancelled = false;
  late final String _operationId;
  late final LedgerOperationCanceller _cancelOperation;

  @override
  void initState() {
    super.initState();
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
    final hasUncheckpointedSignature =
        _signedPczt != null && !_ownershipTransferred;
    if (!_ownershipTransferred && !_cancelled && !hasUncheckpointedSignature) {
      unawaited(_cancelOperationSafely());
      _scheduleDiscard('MobileLedgerSendSign(dispose)');
    }
    super.dispose();
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _attemptGeneration;

  void _startSigning() {
    if (_signedPczt != null) return;
    final generation = ++_attemptGeneration;
    setState(() {
      _phase = LedgerSigningModalPhase.preparing;
      _failure = null;
      _recoveryAction = null;
    });
    unawaited(_prepareAndSign(generation));
  }

  Future<void> _prepareAndSign(int generation) async {
    try {
      final dbPath = await (widget.loadWalletDbPath ?? getWalletDbPath)();
      if (!_isCurrent(generation)) return;
      final endpoint = ref.read(rpcEndpointProvider);
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

      final basePczt = await _getOrCreateBasePczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );
      if (!_isCurrent(generation)) return;

      var redactedPczt = _redactedPczt;
      if (redactedPczt == null) {
        redactedPczt = List<int>.unmodifiable(
          await (widget.redactPczt ?? rust_sync.redactPcztForSigner)(
            pcztBytes: basePczt,
          ),
        );
        if (!_isCurrent(generation)) return;
        _redactedPczt = redactedPczt;
      }

      var pcztWithProofs = _pcztWithProofs;
      if (pcztWithProofs == null) {
        pcztWithProofs = List<int>.unmodifiable(
          await (widget.addProofs ?? rust_sync.addProofsToPczt)(
            pcztBytes: basePczt,
            spendParamsPath: widget.args.needsSaplingParams
                ? saplingParams.spendPath
                : null,
            outputParamsPath: widget.args.needsSaplingParams
                ? saplingParams.outputPath
                : null,
          ),
        );
        if (!_isCurrent(generation)) return;
        _pcztWithProofs = pcztWithProofs;
      }

      setState(() => _phase = LedgerSigningModalPhase.awaitingDevice);
      final signedPczt = await ref.read(ledgerPcztSignerProvider)(
        widget.args.proposalAccountUuid,
        redactedPczt,
      );
      if (!_isCurrent(generation)) return;
      _signedPczt = List<int>.unmodifiable(signedPczt);
      setState(() {
        _phase = LedgerSigningModalPhase.saving;
        _failure = null;
        _recoveryAction = null;
      });
    } catch (error, stackTrace) {
      log('MobileLedgerSendSign._prepareAndSign: ERROR: $error\n$stackTrace');
      if (!_isCurrent(generation)) return;
      _setPreSignatureFailure(error);
      return;
    }

    await _checkpoint(generation);
  }

  Future<List<int>> _getOrCreateBasePczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
  }) async {
    if (_basePczt case final cached?) return cached;
    if (_basePcztFuture case final existing?) return existing;

    final future =
        (widget.createPczt ?? rust_sync.createPcztFromProposal)(
          dbPath: dbPath,
          lightwalletdUrl: lightwalletdUrl,
          network: network,
          proposalId: widget.args.proposalId,
          sendFlowId: widget.args.sendFlowId,
        ).then<List<int>>((value) {
          _basePczt ??= List<int>.unmodifiable(value);
          return _basePczt!;
        });
    _basePcztFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_basePcztFuture, future)) _basePcztFuture = null;
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
    final appInstruction = ledgerZcashAppOpenErrorInstruction(
      ref.read(rpcEndpointProvider).networkName,
    );
    late final LedgerSigningFailurePresentation presentation;
    late final _LedgerSendRecoveryAction? action;

    if (lower.contains('proposal not found') ||
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
    } else if (lower.contains('sapling')) {
      presentation = const LedgerSigningFailurePresentation(
        title: 'Ledger signing unavailable',
        statusLabel: 'Unsupported transaction',
        message:
            'This Ledger preview does not support Sapling inputs or outputs.',
        showDeviceAppPrompt: false,
      );
      action = null;
    } else {
      final message =
          lower.contains('rejected') ||
              lower.contains('denied') ||
              lower.contains('6985')
          ? 'The transaction was rejected on your Ledger.'
          : lower.contains('not found') ||
                lower.contains('no device') ||
                lower.contains('hid')
          ? 'Connect and unlock your Ledger. $appInstruction'
          : '$appInstruction Then try again.';
      presentation = LedgerSigningFailurePresentation(
        title: 'Ledger signing failed',
        statusLabel: 'Action needed',
        message: message,
        showDeviceAppPrompt: true,
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
    final proofs = _pcztWithProofs;
    final signature = _signedPczt;
    if (proofs == null || signature == null) return;
    try {
      await ref
          .read(ledgerSignedOperationServiceProvider)
          .checkpoint(
            operationId: _operationId,
            accountUuid: widget.args.proposalAccountUuid,
            kind: LedgerSignedOperationKind.send,
            pcztWithProofsBytes: proofs,
            pcztWithSignaturesBytes: signature,
          );
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
          statusLabel: terminal ? 'Recovery required' : 'Signature preserved',
          message: terminal
              ? 'Vizor could not verify the saved transaction. Do not sign or send it again.'
              : 'Your Ledger signature is preserved. Retry saving without approving another transaction.',
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
        _attemptGeneration++;
        _scheduleDiscard('MobileLedgerSendSign(expired)');
        ref.read(sendStatusRoutePayloadProvider.notifier).clear();
        context.go('/send');
      case null:
        return;
    }
  }

  Future<void> _cancelAndPop() async {
    if (_signedPczt != null || _cancelled) return;
    _cancelled = true;
    _attemptGeneration++;
    await _cancelOperationSafely();
    _scheduleDiscard('MobileLedgerSendSign(cancel)');
    if (mounted) context.pop();
  }

  Future<void> _cancelOperationSafely() async {
    try {
      await _cancelOperation();
    } catch (error, stackTrace) {
      log('MobileLedgerSendSign.cancel: ERROR: $error\n$stackTrace');
    }
  }

  void _scheduleDiscard(String logContext) {
    if (_discardScheduled) return;
    _discardScheduled = true;
    final discard = widget.discardProposal;
    if (discard != null) {
      unawaited(discard());
      return;
    }
    unawaited(
      discardSendProposal(
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        logContext: logContext,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = _signedPczt == null;
    return MobileLedgerSigningSurface(
      key: const ValueKey('mobile_ledger_signing_surface'),
      title: 'Confirm transaction',
      canLeave: canLeave,
      onBack: () => unawaited(_cancelAndPop()),
      child: LedgerSigningModal(
        accountUuid: widget.args.proposalAccountUuid,
        phase: _phase,
        failure: _failure,
        onCancel: canLeave ? () => unawaited(_cancelAndPop()) : null,
        onFailureAction:
            _phase == LedgerSigningModalPhase.failed && _recoveryAction != null
            ? _handleFailureAction
            : null,
      ),
    );
  }
}
