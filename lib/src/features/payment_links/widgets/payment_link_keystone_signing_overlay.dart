import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';
import '../models/vizor_payment_link.dart';
import '../services/payment_link_hardware_signing_service.dart';

class PaymentLinkKeystoneSigningOverlay extends ConsumerStatefulWidget {
  const PaymentLinkKeystoneSigningOverlay({
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
  final VoidCallback onCancel;
  final Future<void> Function(
    VizorPaymentLink link,
    String status,
    String? message,
  )
  onFundingBroadcast;

  @override
  ConsumerState<PaymentLinkKeystoneSigningOverlay> createState() =>
      _PaymentLinkKeystoneSigningOverlayState();
}

enum _PaymentLinkKeystonePhase { preparing, ready, broadcasting, failed }

class _PaymentLinkKeystoneSigningOverlayState
    extends ConsumerState<PaymentLinkKeystoneSigningOverlay> {
  _PaymentLinkKeystonePhase _phase = _PaymentLinkKeystonePhase.preparing;
  bool _showSaplingParamsPrompt = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  PaymentLinkHardwareSigningService? _signingService;
  PaymentLinkHardwarePcztDraft? _draft;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_preparePczt());
    });
  }

  @override
  void dispose() {
    final completer = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    unawaited(_discardDraft());
    super.dispose();
  }

  Future<void> _preparePczt() async {
    try {
      final service = ref.read(paymentLinkHardwareSigningServiceProvider);
      _signingService = service;
      final draft = await service.createFundingPczt(
        amountZatoshi: widget.amountZatoshi,
        sourceAccountUuid: widget.sourceAccountUuid,
        presentation: widget.presentation,
      );
      if (!mounted) {
        await service.discardPcztDraft(draft: draft);
        return;
      }
      _draft = draft;

      SaplingParamsStatus? saplingParams;
      if (draft.needsSaplingParams) {
        saplingParams = await loadSaplingParamsStatus();
        if (!saplingParams.complete) {
          final confirmed = await _showDownloadPrompt();
          if (!confirmed) {
            await _discardDraft();
            if (!mounted) return;
            setState(() {
              _phase = _PaymentLinkKeystonePhase.failed;
              _error =
                  'Signing was cancelled before proving parameters were downloaded.';
            });
            return;
          }
          await downloadMissingSaplingParams(
            saplingParams,
            log: (message) => log('PaymentLinkKeystoneSigning: $message'),
          );
          saplingParams = await loadSaplingParamsStatus();
        }
      }

      final urParts = await service.encodeSigningUrParts(draft: draft);
      final pcztWithProofs = await service.addProofsForSigning(
        draft: draft,
        spendParamsPath:
            draft.needsSaplingParams ? saplingParams!.spendPath : null,
        outputParamsPath:
            draft.needsSaplingParams ? saplingParams!.outputPath : null,
      );
      if (!mounted) return;
      setState(() {
        _phase = _PaymentLinkKeystonePhase.ready;
        _urParts = urParts;
        _saplingParams = saplingParams;
        _pcztWithProofs = pcztWithProofs;
      });
    } catch (error, stackTrace) {
      log('PaymentLinkKeystoneSigning._preparePczt: $error\n$stackTrace');
      await _discardDraft();
      if (!mounted) return;
      setState(() {
        _phase = _PaymentLinkKeystonePhase.failed;
        _error = _friendlyError(error);
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
    if (_phase != _PaymentLinkKeystonePhase.ready || _pcztWithProofs == null) {
      return;
    }
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
      _phase = _PaymentLinkKeystonePhase.broadcasting;
      _error = null;
    });
    try {
      final service = _signingService;
      if (service == null) {
        throw StateError('Keystone signing service is unavailable.');
      }
      _draft = null;
      final result = await service.broadcastSignedPczt(
        draft: draft,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signatures,
        spendParamsPath:
            draft.needsSaplingParams ? saplingParams!.spendPath : null,
        outputParamsPath:
            draft.needsSaplingParams ? saplingParams!.outputPath : null,
      );
      final hasTxid = result.txid.trim().isNotEmpty;
      final fundingAccepted =
          hasTxid &&
          (result.status == 'broadcasted' ||
              result.status == 'broadcasted_storage_failed');
      if (!fundingAccepted) {
        if (!mounted) return;
        setState(() {
          _phase = _PaymentLinkKeystonePhase.failed;
          _error =
              result.message ??
              'The funding status is uncertain. Check activity before trying again.';
        });
        return;
      }
      await widget.onFundingBroadcast(
        draft.link,
        result.status,
        result.message,
      );
    } catch (error, stackTrace) {
      log('PaymentLinkKeystoneSigning._broadcast: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _phase = _PaymentLinkKeystonePhase.failed;
        _error = _friendlyError(error);
      });
    }
  }

  void _cancel() {
    if (_phase == _PaymentLinkKeystonePhase.broadcasting) return;
    unawaited(_discardDraft());
    widget.onCancel();
  }

  Future<void> _discardDraft() async {
    final draft = _draft;
    _draft = null;
    if (draft == null) return;
    await _signingService?.discardPcztDraft(draft: draft);
  }

  @override
  Widget build(BuildContext context) {
    final modalPhase = switch (_phase) {
      _PaymentLinkKeystonePhase.ready => KeystoneSigningModalPhase.ready,
      _PaymentLinkKeystonePhase.failed => KeystoneSigningModalPhase.failed,
      _PaymentLinkKeystonePhase.preparing ||
      _PaymentLinkKeystonePhase
          .broadcasting => KeystoneSigningModalPhase.preparing,
    };
    final isBroadcasting = _phase == _PaymentLinkKeystonePhase.broadcasting;

    return Stack(
      key: const ValueKey('payment_link_keystone_signing_overlay_surface'),
      fit: StackFit.expand,
      children: [
        AppPaneModalOverlay(
          onDismiss: _cancel,
          child: KeystoneSigningModal(
            phase: modalPhase,
            urParts: _urParts,
            error: _error,
            title:
                isBroadcasting
                    ? 'Broadcasting Gift Card funding'
                    : 'Sign Gift Card on Keystone',
            subtitle:
                isBroadcasting ? 'Submitting transaction' : 'Scan to sign',
            instruction:
                isBroadcasting
                    ? 'Keep Vizor open while the transaction is sent.'
                    : _phase == _PaymentLinkKeystonePhase.failed
                    ? null
                    : 'After you scanned, click Get signature.',
            primaryLabel:
                _phase == _PaymentLinkKeystonePhase.failed || isBroadcasting
                    ? null
                    : 'Get signature',
            onPrimary:
                _phase == _PaymentLinkKeystonePhase.ready &&
                        _pcztWithProofs != null
                    ? () => unawaited(_getSignature())
                    : null,
            secondaryLabel:
                isBroadcasting
                    ? null
                    : _phase == _PaymentLinkKeystonePhase.failed
                    ? 'Back to Gift Card'
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
      return 'Gift Card funding could not be broadcast.';
    }
    if (lower.contains('pczt') || lower.contains('signature')) {
      return 'Keystone signature could not be applied.';
    }
    return 'Gift Card signing could not be completed.';
  }
}
