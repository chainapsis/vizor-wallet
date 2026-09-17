import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ledger/services/ledger_failure_guidance.dart';
import '../../../../main.dart' show log;
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../ledger/ledger_capability.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/widgets/ledger_signing_modal.dart';
import '../../ledger/widgets/mobile_ledger_signing_surface.dart';
import '../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';
import '../models/vizor_payment_link.dart';
import '../services/payment_link_hardware_signing_service.dart';
import '../services/payment_link_ledger_funding_service.dart';

class PaymentLinkLedgerSigningOverlay extends ConsumerStatefulWidget {
  const PaymentLinkLedgerSigningOverlay({
    required this.amountZatoshi,
    required this.sourceAccountUuid,
    required this.onCancel,
    required this.onFundingBroadcast,
    this.presentation,
    super.key,
  });
  final BigInt amountZatoshi;
  final String sourceAccountUuid;
  final PaymentLinkPresentation? presentation;
  final Future<void> Function() onCancel;
  final Future<void> Function(
    VizorPaymentLink,
    PaymentLinkHardwareFundingResult,
  )
  onFundingBroadcast;

  @override
  ConsumerState<PaymentLinkLedgerSigningOverlay> createState() =>
      _PaymentLinkLedgerSigningOverlayState();
}

class _PaymentLinkLedgerSigningOverlayState
    extends ConsumerState<PaymentLinkLedgerSigningOverlay> {
  late final PaymentLinkLedgerFundingService _service;
  late final LedgerPcztSigner _sign;
  late final LedgerOperationCanceller _cancelDevice;
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.preparing;
  PaymentLinkHardwarePcztDraft? _draft;
  List<int>? _proofs;
  SaplingParamsStatus? _params;
  Future<void>? _work;
  Future<void>? _cleanup;
  Completer<bool>? _paramsPrompt;
  bool _cancelled = false;
  bool _checkpointed = false;
  bool _terminal = false;
  String? _error;
  LedgerFailureGuidance? _deviceGuidance;

  bool get _active => mounted && !_cancelled;
  bool get _durableBusy =>
      _phase == LedgerSigningModalPhase.saving ||
      _phase == LedgerSigningModalPhase.broadcasting;

  @override
  void initState() {
    super.initState();
    _service = ref.read(paymentLinkLedgerFundingServiceProvider);
    _sign = ref.read(ledgerPcztSignerProvider);
    _cancelDevice = ref.read(ledgerOperationCancellerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) _start();
    });
  }

  void _start() {
    _work = _run();
  }

  Future<void> _run() async {
    try {
      if (_checkpointed) {
        setState(() {
          _phase = LedgerSigningModalPhase.broadcasting;
          _error = null;
          _deviceGuidance = null;
        });
        final result = await _service.resume(
          accountUuid: widget.sourceAccountUuid,
          address: _draft!.link.address,
          draft: _draft,
          spendParamsPath: _params?.spendPath,
          outputParamsPath: _params?.outputPath,
        );
        await _present(result);
        return;
      }
      setState(() {
        _phase = LedgerSigningModalPhase.preparing;
        _error = null;
        _deviceGuidance = null;
      });
      _draft ??= await _service.prepare(
        accountUuid: widget.sourceAccountUuid,
        amountZatoshi: widget.amountZatoshi,
        presentation: widget.presentation,
      );
      if (!_active) return;
      final draft = _draft!;
      if (draft.needsSaplingParams && _params == null) {
        var params = await loadSaplingParamsStatus();
        if (!_active) return;
        if (!params.complete) {
          if (!await _showParamsPrompt()) {
            unawaited(_cancel());
            return;
          }
          if (!_active) return;
          await downloadMissingSaplingParams(
            params,
            log: (message) => log('GiftCardLedger: $message'),
          );
          params = await loadSaplingParamsStatus();
        }
        _params = params;
      }
      if (!_active) return;
      _proofs ??= await _service.prove(
        accountUuid: widget.sourceAccountUuid,
        draft: draft,
        spendParamsPath: _params?.spendPath,
        outputParamsPath: _params?.outputPath,
      );
      if (!_active) return;
      setState(() => _phase = LedgerSigningModalPhase.awaitingDevice);
      final signatures = await _sign(widget.sourceAccountUuid, draft.pcztBytes);
      if (!_active) return;
      setState(() => _phase = LedgerSigningModalPhase.saving);
      final result = await _service.submit(
        accountUuid: widget.sourceAccountUuid,
        draft: draft,
        proofs: _proofs!,
        signatures: signatures,
        onCheckpointed: () {
          _checkpointed = true;
          if (mounted) {
            setState(() => _phase = LedgerSigningModalPhase.broadcasting);
          }
        },
        spendParamsPath: _params?.spendPath,
        outputParamsPath: _params?.outputPath,
      );
      await _present(result);
    } catch (error, stack) {
      log('GiftCardLedger: $error\n$stack');
      if (!_active && !_checkpointed) {
        unawaited(
          _discardAfterWork().catchError(
            (Object cleanupError) =>
                log('GiftCardLedger cleanup: $cleanupError'),
          ),
        );
      }
      if (_active) {
        setState(() {
          _phase = LedgerSigningModalPhase.failed;
          _terminal = error is LedgerGiftFundingTerminalException;
          _deviceGuidance = ledgerFailureGuidance(error);
          _error = _terminal
              ? LedgerGiftFundingTerminalException.message
              : isLedgerLegacyOrchardRecoveryUnsupported(error)
              ? kLedgerLegacyOrchardRecoveryUnavailableMessage
              : _checkpointed
              ? 'Gift card funding is saved for recovery. Try again to check its status and finish saving.'
              : _deviceGuidance?.message ??
                    'Ledger signing could not be completed. Check your device and try again.';
        });
      }
    }
  }

  Future<void> _present(PaymentLinkHardwareFundingResult result) async {
    if (!_active) return;
    try {
      await widget.onFundingBroadcast(_draft!.link, result);
    } catch (error) {
      log('GiftCardLedger: result presentation failed: $error');
    }
  }

  Future<bool> _showParamsPrompt() {
    if (kAppFormFactor == AppFormFactor.mobile) {
      return showAppMobileSheet<bool>(
        context: context,
        isDismissible: false,
        builder: (_) => const MobileSaplingParamsSheet(),
      ).then((value) => value == true);
    }
    final prompt = Completer<bool>();
    setState(() => _paramsPrompt = prompt);
    return prompt.future;
  }

  void _resolveParams(bool value) {
    final prompt = _paramsPrompt;
    if (prompt == null) return;
    setState(() => _paramsPrompt = null);
    if (!prompt.isCompleted) prompt.complete(value);
  }

  Future<void> _discardAfterWork() => _cleanup ??= (() async {
    try {
      await _cancelDevice();
    } catch (_) {
      /* Keep cleaning up the draft. */
    }
    await _work;
    final draft = _draft;
    if (draft != null && !_checkpointed) {
      await _service.discard(widget.sourceAccountUuid, draft);
      _draft = null;
    }
  })();

  Future<void> _cancel() async {
    if (_durableBusy || _cancelled) return;
    setState(() => _cancelled = true);
    try {
      await _discardAfterWork();
      if (mounted) await widget.onCancel();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancelled = false;
        _cleanup = null;
        _phase = LedgerSigningModalPhase.failed;
        _deviceGuidance = null;
        _error = 'Could not finish cancelling. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    final prompt = _paramsPrompt;
    if (prompt != null && !prompt.isCompleted) prompt.complete(false);
    if (!_durableBusy) {
      unawaited(
        _discardAfterWork().catchError(
          (Object error) => log('GiftCardLedger cleanup: $error'),
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unavailable =
        _error == kLedgerLegacyOrchardRecoveryUnavailableMessage;
    final canLeave = !_durableBusy && !_cancelled;
    final modal = LedgerSigningModal(
      accountUuid: widget.sourceAccountUuid,
      phase: _phase,
      failure: _phase == LedgerSigningModalPhase.failed
          ? LedgerSigningFailurePresentation(
              title: unavailable
                  ? 'Ledger app update required'
                  : 'Gift card funding needs attention',
              statusLabel: 'Action needed',
              message: _error!,
              showDeviceAppPrompt:
                  !_checkpointed &&
                  !unavailable &&
                  (_deviceGuidance?.showDeviceAppPrompt ?? false),
              actionLabel: unavailable || _terminal ? null : 'Try again',
            )
          : null,
      onCancel: canLeave ? () => unawaited(_cancel()) : null,
      cancelLabel: 'Back to gift card',
      onFailureAction:
          _phase == LedgerSigningModalPhase.failed &&
              !_cancelled &&
              !unavailable &&
              !_terminal
          ? _start
          : null,
    );
    final content = kAppFormFactor == AppFormFactor.mobile
        ? MobileLedgerSigningSurface(
            title: 'Confirm Gift Card',
            canLeave: canLeave,
            onBack: () => unawaited(_cancel()),
            child: modal,
          )
        : AppPaneModalOverlay(
            onDismiss: canLeave ? () => unawaited(_cancel()) : () {},
            child: modal,
          );
    return Stack(
      key: const ValueKey('payment_link_ledger_signing_overlay_surface'),
      fit: StackFit.expand,
      children: [
        content,
        if (_paramsPrompt != null)
          Positioned.fill(
            child: SaplingParamsPrompt(
              onDownload: () => _resolveParams(true),
              onCancel: () => _resolveParams(false),
            ),
          ),
      ],
    );
  }
}
