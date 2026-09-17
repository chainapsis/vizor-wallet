import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../core/navigation/payment_uri_busy_surface_hold.dart';
import '../../../core/navigation/payment_uri_busy_surface_provider.dart';
import '../../../core/navigation/app_back_resolver.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../keystone/services/keystone_batch_signing.dart';
import '../../donation/widgets/donation_views.dart';
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../../ledger/ledger_capability.dart';
import '../../ledger/ledger_error_codes.dart';
import '../../ledger/ledger_error_messages.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../../ledger/widgets/ledger_signing_modal.dart';
import '../services/sapling_params.dart';
import '../services/send_flow.dart';
import 'keystone_send_scan_screen.dart';
import '../widgets/sapling_params_prompt.dart';
import '../widgets/send_recipient_resolver.dart';
import '../widgets/send_review_content_view.dart';
import '../widgets/send_verify_address_overlay.dart';

export '../services/send_flow.dart'
    show KeystoneBroadcastArgs, LedgerBroadcastArgs, SendReviewArgs;

enum _LedgerSendRecoveryAction {
  retrySigning,
  createNewTransaction,
  retryCheckpoint,
}

typedef LedgerSendBasePcztCreator =
    Future<List<int>> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required BigInt proposalId,
      required String sendFlowId,
    });

typedef LedgerSendTexPcztsCreator =
    Future<rust_sync.TexPcztPairResult> Function({
      required String dbPath,
      required String lightwalletdUrl,
      required String network,
      required BigInt proposalId,
      required String sendFlowId,
    });

final ledgerSendBasePcztCreatorProvider = Provider<LedgerSendBasePcztCreator>(
  (_) => rust_sync.createPcztFromProposal,
);

final ledgerSendTexPcztsCreatorProvider = Provider<LedgerSendTexPcztsCreator>(
  (_) => rust_sync.createTexPcztsFromProposal,
);

class SendReviewScreen extends ConsumerStatefulWidget {
  const SendReviewScreen({super.key, required this.args});

  final SendReviewArgs args;

  @override
  ConsumerState<SendReviewScreen> createState() => _SendReviewScreenState();
}

class _SendReviewScreenState extends ConsumerState<SendReviewScreen> {
  late final PaymentUriBusySurfaceNotifier _paymentUriBusySurface;
  bool _holdsPaymentUriBusySurface = false;
  late final SyncNotifier _syncNotifier;
  Future<bool>? _discardFuture;
  bool _cancelling = false;
  bool _proposalAbandoned = false;
  late SendReviewArgs _reviewArgs;
  int _signingGeneration = 0;
  Future<Object?>? _proposalConsumption;
  bool _reviewRecoveryFailed = false;
  bool _handoffToHardware = false;
  bool _showSaplingParamsPrompt = false;
  bool _messageExpanded = false;
  bool _showVerifyAddress = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  KeystoneSigningModalPhase? _keystonePhase;
  String? _keystoneError;
  List<String> _keystoneUrParts = const [];
  List<List<String>> _keystoneUrPartsByRound = const [];
  List<KeystoneBatchSigningRequest?> _keystoneBatchRequestsByRound = const [];
  List<List<int>> _keystonePcztsWithProofs = const [];
  final List<List<int>> _keystoneSignatures = [];
  int _keystoneRound = 0;
  SaplingParamsStatus? _keystoneSaplingParams;
  LedgerSigningModalPhase? _ledgerPhase;
  LedgerSigningFailurePresentation? _ledgerFailure;
  _LedgerSendRecoveryAction? _ledgerRecoveryAction;
  int _ledgerAttemptGeneration = 0;
  List<List<int>>? _ledgerBasePczts;
  Future<List<List<int>>>? _ledgerBasePcztsFuture;
  List<List<int>>? _ledgerSignerPczts;
  List<List<int>>? _ledgerPcztsWithProofs;
  final List<List<int>> _ledgerSignedPczts = [];
  int _ledgerRound = 0;
  late final String _ledgerOperationId;
  late final LedgerOperationCanceller _cancelLedgerOperation;

  @override
  void initState() {
    super.initState();
    _reviewArgs = widget.args;
    _paymentUriBusySurface = ref.read(paymentUriBusySurfaceProvider.notifier);
    _syncNotifier = ref.read(syncProvider.notifier);
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    _ledgerOperationId =
        'send:${widget.args.proposalAccountUuid}:${widget.args.sendFlowId}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_holdsPaymentUriBusySurface) {
        _paymentUriBusySurface.acquire();
        _holdsPaymentUriBusySurface = true;
      }
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  void dispose() {
    final promptCompleter = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (promptCompleter != null && !promptCompleter.isCompleted) {
      promptCompleter.complete(false);
    }
    final hasUncheckpointedLedgerSignature =
        _ledgerSigningComplete && !_handoffToHardware;
    _ledgerAttemptGeneration++;
    if (_ledgerPhase != null &&
        !_handoffToHardware &&
        !hasUncheckpointedLedgerSignature) {
      unawaited(_cancelLedgerOperation());
    }
    final discard = _handoffToHardware || hasUncheckpointedLedgerSignature
        ? null
        : _scheduleDiscard();
    _releasePaymentUriBusySurface(after: discard);
    super.dispose();
  }

  Future<bool> _scheduleDiscard() {
    _proposalAbandoned = true;
    final args = _reviewArgs;
    return _discardFuture ??=
        () async {
          try {
            await _proposalConsumption;
          } catch (_) {
            // A failed creator still needs idempotent proposal cleanup.
          }
          return discardSendProposal(
            proposalId: args.proposalId,
            sendFlowId: args.sendFlowId,
            logContext: 'SendReview',
            syncNotifier: _syncNotifier,
            accountUuid: args.proposalAccountUuid,
          );
        }().then((released) {
          if (!released) _discardFuture = null;
          return released;
        });
  }

  void _releasePaymentUriBusySurface({Future<void>? after}) {
    if (!_holdsPaymentUriBusySurface) return;
    _holdsPaymentUriBusySurface = false;
    if (after == null) {
      _paymentUriBusySurface.releaseAfterNavigation();
      return;
    }
    // The route is already gone, but Rust may still hold the selected inputs.
    // Do not re-drain the parked request until that release has completed.
    unawaited(after.whenComplete(_paymentUriBusySurface.release));
  }

  String _formatAmount(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).activityDetail.toString();
  }

  String _formatFee(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).fee.toString();
  }

  void _toggleMessageExpanded() {
    setState(() {
      _messageExpanded = !_messageExpanded;
    });
  }

  Future<void> _handleSend() async {
    if (_reviewRecoveryFailed) {
      await _cancelSigningAndRefreshReview();
      return;
    }
    if (_cancelling || _proposalAbandoned) return;
    final signerKind = ref
        .read(accountProvider.notifier)
        .hardwareSignerKindForAccount(_reviewArgs.proposalAccountUuid);
    if (signerKind == HardwareSignerKind.ledger) {
      _showLedgerSigningModal();
      return;
    }
    if (signerKind == HardwareSignerKind.keystone) {
      _showKeystoneSigningModal();
      return;
    }

    ref.read(sendStatusRoutePayloadProvider.notifier).retain(_reviewArgs);
    _releasePaymentUriBusySurface();
    await context.push(
      sendStatusRouteLocation(_reviewArgs.sendFlowId),
      extra: _reviewArgs,
    );
  }

  void _showLedgerSigningModal() {
    if (_ledgerPhase != null) return;
    final generation = ++_ledgerAttemptGeneration;
    setState(() {
      _ledgerPhase = LedgerSigningModalPhase.preparing;
      _ledgerFailure = null;
      _ledgerRecoveryAction = null;
    });
    unawaited(_prepareAndSignWithLedger(generation));
  }

  bool _isCurrentLedgerAttempt(int generation) {
    return mounted && generation == _ledgerAttemptGeneration;
  }

  bool get _ledgerSigningComplete {
    final pczts = _ledgerBasePczts;
    return pczts != null &&
        pczts.isNotEmpty &&
        _ledgerSignedPczts.length == pczts.length;
  }

  Future<void> _prepareAndSignWithLedger(int generation) async {
    try {
      final dbPath = await ref.read(ledgerWalletDbPathProvider)();
      if (!_isCurrentLedgerAttempt(generation)) return;
      var saplingParams = await loadSaplingParamsStatus();
      if (!_isCurrentLedgerAttempt(generation)) return;

      if (_reviewArgs.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!_isCurrentLedgerAttempt(generation)) return;
        if (!confirmed) {
          setState(() {
            _ledgerPhase = null;
            _ledgerFailure = null;
            _ledgerRecoveryAction = null;
          });
          return;
        }
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('SendReview Ledger: $message'),
        );
        if (!_isCurrentLedgerAttempt(generation)) return;
        saplingParams = await loadSaplingParamsStatus();
        if (!_isCurrentLedgerAttempt(generation)) return;
      }

      // PCZT creation consumes the proposal; select the live route once and
      // never retry the consumed proposal through a generic failover runner.
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final pczts = await _getOrCreateLedgerBasePczts(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );
      if (!_isCurrentLedgerAttempt(generation)) return;

      var signerPczts = _ledgerSignerPczts;
      if (signerPczts == null) {
        final redacted = <List<int>>[];
        for (final pczt in pczts) {
          redacted.add(
            List<int>.unmodifiable(
              await rust_sync.redactPcztForSigner(pcztBytes: pczt),
            ),
          );
          if (!_isCurrentLedgerAttempt(generation)) return;
        }
        signerPczts = List<List<int>>.unmodifiable(redacted);
        _ledgerSignerPczts = signerPczts;
      }

      var pcztsWithProofs = _ledgerPcztsWithProofs;
      if (pcztsWithProofs == null) {
        final proved = <List<int>>[];
        for (final pczt in pczts) {
          proved.add(
            List<int>.unmodifiable(
              await rust_sync.addProofsToPczt(
                pcztBytes: pczt,
                spendParamsPath: _reviewArgs.needsSaplingParams
                    ? saplingParams.spendPath
                    : null,
                outputParamsPath: _reviewArgs.needsSaplingParams
                    ? saplingParams.outputPath
                    : null,
              ),
            ),
          );
          if (!_isCurrentLedgerAttempt(generation)) return;
        }
        pcztsWithProofs = List<List<int>>.unmodifiable(proved);
        _ledgerPcztsWithProofs = pcztsWithProofs;
      }

      for (
        var index = _ledgerSignedPczts.length;
        index < pczts.length;
        index++
      ) {
        setState(() {
          _ledgerRound = index;
          _ledgerPhase = LedgerSigningModalPhase.awaitingDevice;
        });
        final signedPczt = await ref.read(ledgerPcztSignerProvider)(
          _reviewArgs.proposalAccountUuid,
          signerPczts[index],
        );
        if (!_isCurrentLedgerAttempt(generation)) return;
        _ledgerSignedPczts.add(List<int>.unmodifiable(signedPczt));
      }
      setState(() {
        _ledgerPhase = LedgerSigningModalPhase.saving;
        _ledgerFailure = null;
        _ledgerRecoveryAction = null;
      });
    } catch (e, st) {
      log('SendReview._prepareAndSignWithLedger: ERROR: $e\n$st');
      if (!_isCurrentLedgerAttempt(generation)) return;
      _setLedgerPreSignatureFailure(e);
      return;
    }

    await _checkpointSignedLedgerOperation(generation);
  }

  Future<List<List<int>>> _getOrCreateLedgerBasePczts({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
  }) async {
    final cachedPczts = _ledgerBasePczts;
    if (cachedPczts != null) return cachedPczts;

    final existingFuture = _ledgerBasePcztsFuture;
    if (existingFuture != null) return existingFuture;

    final creationFuture =
        (_reviewArgs.addressType == 'tex'
                ? ref
                      .read(ledgerSendTexPcztsCreatorProvider)(
                        dbPath: dbPath,
                        lightwalletdUrl: lightwalletdUrl,
                        network: network,
                        proposalId: _reviewArgs.proposalId,
                        sendFlowId: _reviewArgs.sendFlowId,
                      )
                      .then((result) => result.pczts)
                : ref
                      .read(ledgerSendBasePcztCreatorProvider)(
                        dbPath: dbPath,
                        lightwalletdUrl: lightwalletdUrl,
                        network: network,
                        proposalId: _reviewArgs.proposalId,
                        sendFlowId: _reviewArgs.sendFlowId,
                      )
                      .then((pczt) => <List<int>>[pczt]))
            .then<List<List<int>>>((createdPczts) {
              final cached = List<List<int>>.unmodifiable(
                createdPczts.map(List<int>.unmodifiable),
              );
              _ledgerBasePczts ??= cached;
              return _ledgerBasePczts!;
            });
    _ledgerBasePcztsFuture = creationFuture;
    _proposalConsumption = creationFuture;
    try {
      return await creationFuture;
    } finally {
      if (identical(_ledgerBasePcztsFuture, creationFuture)) {
        _ledgerBasePcztsFuture = null;
      }
    }
  }

  void _setLedgerPreSignatureFailure(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final appInstruction = ledgerZcashAppOpenErrorInstruction(
      ref.read(rpcEndpointProvider).networkName,
    );
    late final LedgerSigningFailurePresentation failure;
    late final _LedgerSendRecoveryAction? action;
    final actionable = ledgerActionableErrorMessage(error);

    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      failure = const LedgerSigningFailurePresentation(
        title: 'Transaction expired',
        statusLabel: 'New transaction required',
        message:
            'This transaction can no longer be signed. Create and review a new transaction.',
        showDeviceAppPrompt: false,
        actionLabel: 'Create new transaction',
      );
      action = _LedgerSendRecoveryAction.createNewTransaction;
    } else if (isLedgerLegacyOrchardRecoveryUnsupported(error)) {
      failure = const LedgerSigningFailurePresentation(
        title: 'Ledger app update required',
        statusLabel: 'Recovery unavailable',
        message: kLedgerLegacyOrchardRecoveryUnavailableMessage,
        showDeviceAppPrompt: false,
      );
      action = null;
    } else if (lower.contains('sapling')) {
      failure = const LedgerSigningFailurePresentation(
        title: 'Ledger signing unavailable',
        statusLabel: 'Unsupported transaction',
        message:
            'This Ledger preview does not support Sapling inputs or outputs.',
        showDeviceAppPrompt: false,
      );
      action = null;
    } else if (ledgerRequestNeedsRebuilding(error) && actionable != null) {
      // Retrying the same request fails the same way on the device.
      final updateRequired =
          classifyLedgerError(error) == LedgerFailureKind.unsupportedCommand;
      failure = LedgerSigningFailurePresentation(
        title: updateRequired
            ? 'Ledger app update required'
            : ledgerRequestExceedsCapacity(error)
            ? kLedgerSmallerTransferTitle
            : 'Ledger signing failed',
        statusLabel: updateRequired
            ? 'Update required'
            : 'New transaction required',
        message: actionable,
        showDeviceAppPrompt: false,
        actionLabel: updateRequired ? null : 'Create new transaction',
      );
      action = updateRequired
          ? null
          : _LedgerSendRecoveryAction.createNewTransaction;
    } else {
      final message =
          actionable ??
          switch (classifyLedgerError(error)) {
            LedgerFailureKind.userRejected =>
              'The transaction was rejected on your Ledger.',
            LedgerFailureKind.transportLost ||
            LedgerFailureKind.usbPermission =>
              'Connect and unlock your Ledger. $appInstruction',
            _ => '$appInstruction Then try again.',
          };
      failure = LedgerSigningFailurePresentation(
        title: 'Ledger signing failed',
        statusLabel: 'Action needed',
        message: message,
        showDeviceAppPrompt: true,
        actionLabel: 'Try again',
      );
      action = _LedgerSendRecoveryAction.retrySigning;
    }

    setState(() {
      _ledgerPhase = LedgerSigningModalPhase.failed;
      _ledgerFailure = failure;
      _ledgerRecoveryAction = action;
    });
  }

  Future<void> _checkpointSignedLedgerOperation(int generation) async {
    final pcztsWithProofs = _ledgerPcztsWithProofs;
    if (pcztsWithProofs == null || !_ledgerSigningComplete) return;

    try {
      final operationService = ref.read(ledgerSignedOperationServiceProvider);
      if (pcztsWithProofs.length == 1) {
        await operationService.checkpoint(
          operationId: _ledgerOperationId,
          accountUuid: _reviewArgs.proposalAccountUuid,
          kind: LedgerSignedOperationKind.send,
          pcztWithProofsBytes: pcztsWithProofs.single,
          pcztWithSignaturesBytes: _ledgerSignedPczts.single,
        );
      } else if (operationService
          case final LedgerSignedOperationBatchCheckpointService batchService) {
        await batchService.checkpointBatch(
          operationId: _ledgerOperationId,
          accountUuid: _reviewArgs.proposalAccountUuid,
          kind: LedgerSignedOperationKind.send,
          pcztsWithProofs: pcztsWithProofs,
          pcztsWithSignatures: _ledgerSignedPczts,
        );
      } else {
        throw StateError(
          'Ledger operation service does not support PCZT batches',
        );
      }
    } catch (e, st) {
      log('SendReview._checkpointSignedLedgerOperation: ERROR: $e\n$st');
      if (!_isCurrentLedgerAttempt(generation)) return;
      final terminal = isTerminalLedgerSignedOperationError(e);
      setState(() {
        _ledgerPhase = LedgerSigningModalPhase.failed;
        _ledgerFailure = LedgerSigningFailurePresentation(
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
        _ledgerRecoveryAction = terminal
            ? null
            : _LedgerSendRecoveryAction.retryCheckpoint;
      });
      return;
    }

    if (!_isCurrentLedgerAttempt(generation)) return;
    _handoffToHardware = true;
    setState(() {
      _ledgerPhase = null;
      _ledgerFailure = null;
      _ledgerRecoveryAction = null;
    });
    final statusArgs = LedgerBroadcastArgs(
      reviewArgs: _reviewArgs,
      operationId: _ledgerOperationId,
    );
    ref.read(sendStatusRoutePayloadProvider.notifier).retain(statusArgs);
    if (!mounted) return;
    context.go(
      sendStatusRouteLocation(_reviewArgs.sendFlowId),
      extra: statusArgs,
    );
  }

  Future<void> _dismissLedgerSigningModal() async {
    if (_ledgerPhase == null || _ledgerSigningComplete || _cancelling) return;
    _ledgerAttemptGeneration++;
    _resolveSaplingParamsDialog(false);
    setState(() => _cancelling = true);
    try {
      await _cancelLedgerOperation();
    } catch (e, st) {
      log('SendReview._dismissLedgerSigningModal: ERROR: $e\n$st');
    }
    if (!mounted) return;
    // The shared recovery drains the creator, releases inputs and refreshes
    // balance before constructing a new proposal with the preserved form.
    _cancelling = false;
    await _cancelSigningAndRefreshReview();
  }

  void _retryLedgerSigning() {
    if (_cancelling) return;
    if (_ledgerPhase != LedgerSigningModalPhase.failed ||
        _ledgerRecoveryAction != _LedgerSendRecoveryAction.retrySigning ||
        _ledgerSigningComplete) {
      return;
    }
    final generation = ++_ledgerAttemptGeneration;
    setState(() {
      _ledgerPhase = LedgerSigningModalPhase.preparing;
      _ledgerFailure = null;
      _ledgerRecoveryAction = null;
    });
    unawaited(_prepareAndSignWithLedger(generation));
  }

  void _retryLedgerCheckpoint() {
    if (_ledgerPhase != LedgerSigningModalPhase.failed ||
        _ledgerRecoveryAction != _LedgerSendRecoveryAction.retryCheckpoint ||
        !_ledgerSigningComplete) {
      return;
    }
    final generation = ++_ledgerAttemptGeneration;
    setState(() {
      _ledgerPhase = LedgerSigningModalPhase.saving;
      _ledgerFailure = null;
      _ledgerRecoveryAction = null;
    });
    unawaited(_checkpointSignedLedgerOperation(generation));
  }

  void _createNewLedgerTransaction() {
    if (_ledgerRecoveryAction !=
        _LedgerSendRecoveryAction.createNewTransaction) {
      return;
    }
    _ledgerAttemptGeneration++;
    unawaited(
      _leaveReview(() {
        ref.read(sendStatusRoutePayloadProvider.notifier).clear();
        context.go('/send');
      }),
    );
  }

  void _handleLedgerRecoveryAction() {
    if (_cancelling) return;
    switch (_ledgerRecoveryAction) {
      case _LedgerSendRecoveryAction.retrySigning:
        _retryLedgerSigning();
      case _LedgerSendRecoveryAction.createNewTransaction:
        _createNewLedgerTransaction();
      case _LedgerSendRecoveryAction.retryCheckpoint:
        _retryLedgerCheckpoint();
      case null:
        return;
    }
  }

  Future<void> _leaveReview(VoidCallback navigate) async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    final released = await _scheduleDiscard();
    if (!mounted) return;
    if (released) {
      navigate();
      return;
    }
    const error = 'Could not finish cancelling. Please try again.';
    setState(() {
      _cancelling = false;
      if (_keystonePhase != null) {
        _keystonePhase = KeystoneSigningModalPhase.failed;
        _keystoneError = error;
      }
    });
    showAppToast(
      context,
      error,
      iconName: AppIcons.warningCircle,
      tone: AppToastTone.destructive,
    );
  }

  void _handleCancel() => unawaited(
    _leaveReview(
      () => context.go(
        _reviewArgs.flowKind == SendFlowKind.donation ? '/donation' : '/send',
      ),
    ),
  );

  Future<void> _handleDonationBack() => _ledgerPhase != null
      ? _dismissLedgerSigningModal()
      : _keystonePhase != null
      ? _cancelSigningAndRefreshReview()
      : _leaveReview(() {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/donation');
          }
        });

  void _showKeystoneSigningModal() {
    if (_keystonePhase != null || _proposalAbandoned) return;
    setState(() {
      _keystonePhase = KeystoneSigningModalPhase.preparing;
      _keystoneError = null;
      _keystoneUrParts = const [];
      _keystoneUrPartsByRound = const [];
      _keystoneBatchRequestsByRound = const [];
      _keystonePcztsWithProofs = const [];
      _keystoneSignatures.clear();
      _keystoneRound = 0;
      _keystoneSaplingParams = null;
    });
    unawaited(_prepareKeystonePczt(++_signingGeneration));
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

  Future<void> _prepareKeystonePczt(int generation) async {
    bool isCurrent() =>
        mounted && !_proposalAbandoned && generation == _signingGeneration;
    final args = _reviewArgs;
    try {
      final dbPath = await getWalletDbPath();
      if (!isCurrent()) return;
      final endpoint = ref.read(rpcEndpointProvider);
      final saplingParams = await loadSaplingParamsStatus();
      if (!isCurrent()) return;

      if (args.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!isCurrent()) return;
        if (!confirmed) {
          unawaited(_scheduleDiscard());
          if (!mounted) return;
          setState(() {
            _keystonePhase = KeystoneSigningModalPhase.failed;
            _keystoneError =
                'Signing was cancelled before proving parameters were downloaded.';
          });
          return;
        }

        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('SendReview Keystone: $message'),
        );
      }

      if (!isCurrent()) return;
      final currentSaplingParams = await loadSaplingParamsStatus();
      if (!isCurrent()) return;
      _keystoneSaplingParams = currentSaplingParams;

      final texFuture = args.addressType == 'tex'
          ? rust_sync.createTexPcztsFromProposal(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              proposalId: args.proposalId,
              sendFlowId: args.sendFlowId,
            )
          : null;
      _proposalConsumption = texFuture;
      final texPczts = await texFuture;
      if (!isCurrent()) return;
      final pcztFuture = texPczts == null
          ? rust_sync.createPcztFromProposal(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              proposalId: args.proposalId,
              sendFlowId: args.sendFlowId,
            )
          : null;
      if (pcztFuture != null) _proposalConsumption = pcztFuture;
      final pczts = texPczts?.pczts ?? [await pcztFuture!];
      if (!isCurrent()) return;
      final urPartsByRound = <List<String>>[];
      final batchRequestsByRound = <KeystoneBatchSigningRequest?>[];
      final signerPczts = texPczts?.signerPczts;
      for (var index = 0; index < pczts.length; index++) {
        if (args.addressType == 'tex') {
          final redacted = signerPczts![index];
          urPartsByRound.add(
            await rust_keystone.encodePcztUrParts(
              pcztBytes: redacted,
              maxFragmentLen: BigInt.from(140),
            ),
          );
          batchRequestsByRound.add(null);
        } else {
          final request = await buildKeystoneBatchSigningRequest(
            requestId: 'vizor-send-${args.sendFlowId}-transaction-${index + 1}',
            pczts: [
              KeystoneBatchPcztSource(
                id: 'send-transaction-${index + 1}',
                pcztBytes: pczts[index],
              ),
            ],
          );
          urPartsByRound.add(request.urParts);
          batchRequestsByRound.add(request);
        }
      }

      if (!isCurrent()) return;
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.ready;
        _keystoneUrPartsByRound = urPartsByRound;
        _keystoneBatchRequestsByRound = batchRequestsByRound;
        _keystoneUrParts = urPartsByRound.first;
      });

      final proofs = <List<int>>[];
      for (final pczt in pczts) {
        proofs.add(
          await rust_sync.addProofsToPczt(
            pcztBytes: pczt,
            spendParamsPath: args.needsSaplingParams
                ? currentSaplingParams.spendPath
                : null,
            outputParamsPath: args.needsSaplingParams
                ? currentSaplingParams.outputPath
                : null,
          ),
        );
      }

      if (!isCurrent()) return;
      setState(() {
        _keystonePcztsWithProofs = proofs;
      });
    } catch (e, st) {
      log('SendReview._prepareKeystonePczt: ERROR: $e\n$st');
      if (!isCurrent()) return;
      unawaited(_scheduleDiscard());
      if (!mounted) return;
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.failed;
        _keystoneError = _friendlyKeystoneError(e.toString());
      });
    }
  }

  String _friendlyKeystoneError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be signed.';
    }
    final batchError = keystoneBatchSigningFriendlyError(raw);
    if (batchError != null) return batchError;
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    return 'Keystone signing could not be prepared. Return to Send and try again.';
  }

  Future<void> _cancelSigningAndRefreshReview() async {
    if (_cancelling) return;
    final isLedger = ref
        .read(accountProvider.notifier)
        .isLedgerAccount(_reviewArgs.proposalAccountUuid);
    setState(() {
      _cancelling = true;
      _proposalAbandoned = true;
      _reviewRecoveryFailed = false;
      _signingGeneration++;
    });
    _resolveSaplingParamsDialog(false);
    final released = await _scheduleDiscard();
    if (!mounted) return;
    if (!released) {
      setState(() {
        _cancelling = false;
        if (isLedger) {
          _ledgerPhase = null;
          _reviewRecoveryFailed = true;
        } else {
          _keystonePhase = KeystoneSigningModalPhase.failed;
          _keystoneError = 'Could not finish cancelling. Please try again.';
        }
      });
      return;
    }
    setState(() {
      _keystonePhase = null;
      if (isLedger) {
        _ledgerPhase = null;
        _ledgerBasePczts = null;
        _ledgerBasePcztsFuture = null;
        _ledgerSignerPczts = null;
        _ledgerPcztsWithProofs = null;
        _ledgerSignedPczts.clear();
        _ledgerRound = 0;
        _ledgerFailure = null;
        _ledgerRecoveryAction = null;
      }
    });
    final previous = _reviewArgs;
    try {
      final refreshed = await proposeSendTransfer(
        ref: ref,
        accountUuid: previous.proposalAccountUuid,
        sendFlowId: previous.sendFlowId,
        address: previous.address,
        addressType: previous.addressType,
        amountZatoshi: previous.amountZatoshi,
        memo: previous.memo,
        isPaymentRequest: previous.isPaymentRequest,
        requestedBy: previous.requestedBy,
        requestedAmountZatoshi: previous.requestedAmountZatoshi,
        flowKind: previous.flowKind,
      );
      if (!mounted) {
        await discardSendProposal(
          proposalId: refreshed.proposalId,
          sendFlowId: refreshed.sendFlowId,
          accountUuid: refreshed.proposalAccountUuid,
          syncNotifier: _syncNotifier,
          logContext: 'SendReview(cancelled recovery)',
        );
        return;
      }
      setState(() {
        _reviewArgs = refreshed;
        _discardFuture = null;
        _proposalConsumption = null;
        _proposalAbandoned = false;
        _cancelling = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _reviewRecoveryFailed = true;
      });
      showAppToast(
        context,
        friendlyProposeSendError(error.toString()),
        iconName: AppIcons.warningCircle,
        tone: AppToastTone.destructive,
      );
    }
  }

  Future<void> _getKeystoneSignature() async {
    final generation = _signingGeneration;
    final saplingParams = _keystoneSaplingParams;
    if (_proposalAbandoned ||
        _keystonePhase != KeystoneSigningModalPhase.ready ||
        _keystonePcztsWithProofs.isEmpty ||
        saplingParams == null) {
      return;
    }

    final response = await context.push<List<int>>(
      '/send/keystone/scan',
      extra: _keystoneBatchRequestsByRound[_keystoneRound] == null
          ? KeystoneSendScanArgs(
              suppressSidebarSelection:
                  _reviewArgs.flowKind == SendFlowKind.donation,
            )
          : KeystoneSendScanArgs.batch(
              suppressSidebarSelection:
                  _reviewArgs.flowKind == SendFlowKind.donation,
            ),
    );
    if (response == null ||
        !mounted ||
        _proposalAbandoned ||
        generation != _signingGeneration) {
      return;
    }
    try {
      final batchRequest = _keystoneBatchRequestsByRound[_keystoneRound];
      if (batchRequest == null) {
        _keystoneSignatures.add(response);
      } else {
        _keystoneSignatures.addAll(await batchRequest.decodeResponse(response));
      }
      if (!mounted || _proposalAbandoned || generation != _signingGeneration) {
        return;
      }
      setState(() => _keystoneError = null);
    } catch (e, st) {
      log('SendReview._getKeystoneSignature: ERROR: $e\n$st');
      if (!mounted || generation != _signingGeneration) return;
      setState(() {
        _keystoneError =
            'This QR code does not match the current Keystone signing request.';
      });
      return;
    }
    if (_keystoneRound + 1 < _keystonePcztsWithProofs.length) {
      setState(() {
        _keystoneRound++;
        _keystoneUrParts = _keystoneUrPartsByRound[_keystoneRound];
      });
      return;
    }
    if (!mounted) return;

    _handoffToHardware = true;
    _releasePaymentUriBusySurface();
    final statusArgs = KeystoneBroadcastArgs(
      reviewArgs: _reviewArgs,
      pcztWithProofs: _keystonePcztsWithProofs,
      pcztWithSignatures: List<List<int>>.of(_keystoneSignatures),
    );
    ref.read(sendStatusRoutePayloadProvider.notifier).retain(statusArgs);
    context.go(
      sendStatusRouteLocation(_reviewArgs.sendFlowId),
      extra: statusArgs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final signerKind = ref
        .read(accountProvider.notifier)
        .hardwareSignerKindForAccount(_reviewArgs.proposalAccountUuid);
    final isHardware = signerKind != null;
    final isLedger = signerKind == HardwareSignerKind.ledger;
    final keystonePhase = _keystonePhase;
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final recipient = sendReviewRecipientFor(
      contacts: addressBookContacts,
      address: _reviewArgs.address,
      ownAccounts: ownAccounts,
    );
    final zecUsdUnitPrice = ref.watch(zecHomeUsdUnitPriceProvider);
    final memo = _reviewArgs.memo;
    // Present means non-empty, not non-blank: an edited request whose memo is
    // only whitespace still sends that memo, so the row has to say so rather
    // than omit a memo the transaction carries.
    final hasMemo = memo != null && memo.isNotEmpty;
    final requestedAmountZatoshi = _reviewArgs.differingRequestedAmountZatoshi;
    final backTarget = AppBackResolver.resolve(context);

    return PopScope<Object?>(
      canPop:
          keystonePhase == null &&
          _ledgerPhase == null &&
          !_cancelling &&
          !_proposalAbandoned,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_ledgerPhase != null) {
          unawaited(_dismissLedgerSigningModal());
        } else if (keystonePhase != null) {
          unawaited(_cancelSigningAndRefreshReview());
        } else if (_proposalAbandoned) {
          unawaited(_leaveReview(() => backTarget.navigate(context)));
        }
      },
      child: AppDesktopShell(
        sidebar: AppMainSidebar(
          suppressActiveSelection:
              _reviewArgs.flowKind == SendFlowKind.donation,
        ),
        pane: AppDesktopPane(
          padding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppPaneScrollScaffold(
                toolbar: AppPaneToolbar(
                  leading: _reviewArgs.flowKind == SendFlowKind.donation
                      ? AppBackLink(
                          label: 'Support Vizor',
                          minWidth: 60,
                          onTap: _handleDonationBack,
                        )
                      : AppBackLink(
                          label: backTarget.label,
                          minWidth: 60,
                          onTap: () => _ledgerPhase != null
                              ? _dismissLedgerSigningModal()
                              : keystonePhase != null
                              ? _cancelSigningAndRefreshReview()
                              : _leaveReview(
                                  () => backTarget.navigate(context),
                                ),
                        ),
                  backLinkMinWidth: 60,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: _reviewArgs.flowKind == SendFlowKind.donation
                    ? DonationReviewContentView(
                        amountText: _formatAmount(_reviewArgs.amountZatoshi),
                        fiatText: fiatTextForZatoshi(
                          _reviewArgs.amountZatoshi,
                          zecUsdUnitPrice: zecUsdUnitPrice,
                        ),
                        feeText: _formatFee(_reviewArgs.feeZatoshi),
                        confirmLabel: _reviewRecoveryFailed
                            ? 'Retry'
                            : _cancelling
                            ? 'Cancelling…'
                            : isLedger
                            ? 'Confirm with Ledger'
                            : isHardware
                            ? 'Confirm with Keystone'
                            : 'Confirm donation',
                        confirmIcon: isHardware
                            ? (isLedger ? AppIcons.ledger : AppIcons.qr)
                            : AppIcons.donation,
                        onConfirm:
                            _cancelling ||
                                (_proposalAbandoned && !_reviewRecoveryFailed)
                            ? null
                            : () => unawaited(_handleSend()),
                      )
                    : SendReviewContentView(
                        isPaymentRequest: _reviewArgs.isPaymentRequest,
                        requestedAmountText: requestedAmountZatoshi == null
                            ? null
                            : _formatAmount(requestedAmountZatoshi),
                        amountText: _formatAmount(_reviewArgs.amountZatoshi),
                        fiatText: fiatTextForZatoshi(
                          _reviewArgs.amountZatoshi,
                          zecUsdUnitPrice: zecUsdUnitPrice,
                        ),
                        recipient: recipient,
                        feeText: _formatFee(_reviewArgs.feeZatoshi),
                        isShieldedRecipient: _reviewArgs.isShielded,
                        recipientAddressType: _reviewArgs.addressType,
                        memoText: hasMemo ? memo : null,
                        memoExpanded: _messageExpanded,
                        confirmLabel: _reviewRecoveryFailed
                            ? 'Retry'
                            : _cancelling
                            ? 'Cancelling…'
                            : isLedger
                            ? 'Confirm with Ledger'
                            : isHardware
                            ? 'Confirm with Keystone'
                            : 'Confirm & send',
                        confirmLeadingIconName: isHardware
                            ? (isLedger ? AppIcons.ledger : AppIcons.qr)
                            : AppIcons.plane,
                        onConfirm:
                            _cancelling ||
                                (_proposalAbandoned && !_reviewRecoveryFailed)
                            ? null
                            : () => unawaited(_handleSend()),
                        onCancel: _cancelling ? null : _handleCancel,
                        onShowFullAddress: () =>
                            setState(() => _showVerifyAddress = true),
                        onExpandMemo: _toggleMessageExpanded,
                      ),
              ),
              if (_showVerifyAddress &&
                  keystonePhase == null &&
                  _ledgerPhase == null)
                SendVerifyAddressOverlay(
                  accountUuid: _reviewArgs.proposalAccountUuid,
                  address: _reviewArgs.address.trim(),
                  isShieldedAddress: _reviewArgs.isShielded,
                  onClose: () => setState(() => _showVerifyAddress = false),
                ),
              // The review's outer hold protects its proposal inputs. This
              // nested hold protects the live QR as well, so the latch cannot
              // briefly open while signing subtrees change.
              if (keystonePhase != null)
                PaymentUriBusySurfaceHold(
                  child: AppPaneModalOverlay(
                    onDismiss: () =>
                        unawaited(_cancelSigningAndRefreshReview()),
                    child: KeystoneSigningModal(
                      phase: keystonePhase,
                      urParts: _keystoneUrParts,
                      error: _keystoneError,
                      title: 'Confirm with Keystone',
                      subtitle: _keystoneUrPartsByRound.length == 2
                          ? 'Transaction ${_keystoneRound + 1} of 2'
                          : 'Scan with your Keystone',
                      instruction:
                          _keystoneError ??
                          (_keystonePcztsWithProofs.isEmpty
                              ? 'Scan now. Signature import unlocks after proofs are ready.'
                              : 'After you scanned, click Get signature.'),
                      primaryLabel: _keystonePcztsWithProofs.isEmpty
                          ? 'Preparing'
                          : 'Get signature',
                      onPrimary:
                          !_proposalAbandoned &&
                              keystonePhase ==
                                  KeystoneSigningModalPhase.ready &&
                              _keystonePcztsWithProofs.isNotEmpty
                          ? () => unawaited(_getKeystoneSignature())
                          : null,
                      secondaryLabel: _cancelling ? 'Cancelling…' : 'Cancel',
                      onSecondary: _cancelling
                          ? null
                          : () => unawaited(_cancelSigningAndRefreshReview()),
                    ),
                  ),
                ),
              if (_ledgerPhase case final ledgerPhase?)
                AppPaneModalOverlay(
                  onDismiss: !_ledgerSigningComplete
                      ? () => unawaited(_dismissLedgerSigningModal())
                      : () {},
                  child: LedgerSigningModal(
                    accountUuid: _reviewArgs.proposalAccountUuid,
                    phase: ledgerPhase,
                    failure: _ledgerFailure,
                    onCancel: !_ledgerSigningComplete && !_cancelling
                        ? () => unawaited(_dismissLedgerSigningModal())
                        : null,
                    onFailureAction:
                        !_cancelling &&
                            ledgerPhase == LedgerSigningModalPhase.failed &&
                            _ledgerRecoveryAction != null
                        ? _handleLedgerRecoveryAction
                        : null,
                    roundNumber: _ledgerRound + 1,
                    roundCount: _ledgerBasePczts?.length ?? 1,
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
        ),
      ),
    );
  }
}
