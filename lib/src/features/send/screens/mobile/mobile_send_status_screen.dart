import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../../services/send_flow.dart';
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

enum _MobileSendStatusPhase { sending, pendingBroadcast, succeeded, failed }

const _statusSubtitleWidth = 223.0;

typedef MobileSendBroadcastRunner =
    Future<SendBroadcastOutcome> Function({
      required WidgetRef ref,
      required SendReviewArgs args,
      KeystoneBroadcastArgs? keystone,
      required Future<bool> Function() confirmSaplingParamsDownload,
      Future<bool> Function()? shouldAbort,
    });

class MobileSendStatusScreen extends ConsumerStatefulWidget {
  const MobileSendStatusScreen({
    required this.args,
    this.keystone,
    this.broadcastRunner,
    super.key,
  });

  final SendReviewArgs args;
  final KeystoneBroadcastArgs? keystone;

  @visibleForTesting
  final MobileSendBroadcastRunner? broadcastRunner;

  @override
  ConsumerState<MobileSendStatusScreen> createState() =>
      _MobileSendStatusScreenState();
}

class _MobileSendStatusScreenState
    extends ConsumerState<MobileSendStatusScreen> {
  var _phase = _MobileSendStatusPhase.sending;
  var _proposalConsumed = false;
  var _discardScheduled = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _proposalConsumed = widget.keystone != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startBroadcast());
    });
  }

  @override
  void dispose() {
    if (_phase != _MobileSendStatusPhase.sending) {
      _scheduleDiscardIfNeeded();
    }
    super.dispose();
  }

  void _scheduleDiscardIfNeeded() {
    if (_proposalConsumed || _discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      discardSendProposal(
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        logContext: 'MobileSendStatus(dispose)',
      ),
    );
  }

  Future<bool> _confirmSaplingParamsDownload() async {
    if (!mounted) return false;
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (_) => const MobileSaplingParamsSheet(),
    );
    return confirmed == true;
  }

  Future<void> _startBroadcast() async {
    final runner = widget.broadcastRunner ?? runSendBroadcast;
    final outcome = await runner(
      ref: ref,
      args: widget.args,
      keystone: widget.keystone,
      confirmSaplingParamsDownload: _confirmSaplingParamsDownload,
      shouldAbort: () async => !mounted,
    );
    _proposalConsumed = outcome.proposalConsumed;
    if (outcome.phase == SendBroadcastPhase.aborted || !mounted) return;

    setState(() {
      _phase = switch (outcome.phase) {
        SendBroadcastPhase.succeeded => _MobileSendStatusPhase.succeeded,
        SendBroadcastPhase.pendingBroadcast =>
          _MobileSendStatusPhase.pendingBroadcast,
        SendBroadcastPhase.failed => _MobileSendStatusPhase.failed,
        SendBroadcastPhase.aborted => _MobileSendStatusPhase.failed,
      };
      _statusMessage = outcome.statusMessage;
    });
    // Success and failure use custom native haptic patterns without system
    // notification sounds.
    switch (_phase) {
      case _MobileSendStatusPhase.succeeded:
        unawaited(AppHaptics.sendSuccess());
      case _MobileSendStatusPhase.failed:
        unawaited(AppHaptics.sendFailure());
      case _MobileSendStatusPhase.sending:
      case _MobileSendStatusPhase.pendingBroadcast:
        break;
    }
  }

  void _handleBack() {
    if (_phase == _MobileSendStatusPhase.sending) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  bool get _routePopAllowed => _phase != _MobileSendStatusPhase.sending;

  MobileTransactionProgressPhase get _presentationPhase {
    return switch (_phase) {
      _MobileSendStatusPhase.sending =>
        MobileTransactionProgressPhase.inProgress,
      _MobileSendStatusPhase.pendingBroadcast =>
        MobileTransactionProgressPhase.pending,
      _MobileSendStatusPhase.succeeded =>
        MobileTransactionProgressPhase.succeeded,
      _MobileSendStatusPhase.failed => MobileTransactionProgressPhase.failed,
    };
  }

  String get _title {
    return switch (_phase) {
      _MobileSendStatusPhase.sending => 'Sending...',
      _MobileSendStatusPhase.pendingBroadcast => 'Queued to send',
      _MobileSendStatusPhase.succeeded => 'Sent!',
      _MobileSendStatusPhase.failed => 'Send failed',
    };
  }

  String get _subtitle {
    final statusMessage = _statusMessage?.trim();
    return switch (_phase) {
      _MobileSendStatusPhase.sending =>
        'Submitting your transaction to the network...',
      _MobileSendStatusPhase.pendingBroadcast =>
        statusMessage == null || statusMessage.isEmpty
            ? 'Your transaction was created and will be submitted '
                  'automatically. Check the Activity page before sending '
                  'again.'
            : statusMessage,
      _MobileSendStatusPhase.succeeded =>
        'It will confirm on-chain shortly. Track it in Activity.',
      _MobileSendStatusPhase.failed =>
        "Nothing was sent, your funds haven't moved. Try again.",
    };
  }

  String? get _buttonLabel {
    return switch (_phase) {
      _MobileSendStatusPhase.sending => null,
      _MobileSendStatusPhase.pendingBroadcast ||
      _MobileSendStatusPhase.succeeded => 'Done',
      _MobileSendStatusPhase.failed => 'Return home',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MobileTransactionProgressScreen(
      phase: _presentationPhase,
      title: _title,
      body: _subtitle,
      bodyMaxWidth: _phase == _MobileSendStatusPhase.pendingBroadcast
          ? null
          : _statusSubtitleWidth,
      canPop: _routePopAllowed,
      onPopBlocked: _handleBack,
      titleKey: ValueKey('mobile_send_status_${_phase.name}'),
      progressIconKey: const ValueKey('mobile_send_status_icon_loader'),
      successIconKey: const ValueKey('mobile_send_status_icon_success'),
      failureIconKey: const ValueKey('mobile_send_status_icon_failed'),
      successRippleKey: const ValueKey('mobile_send_status_success_ripple'),
      primaryActionKey: const ValueKey('mobile_send_status_button'),
      primaryActionLabel: _buttonLabel,
      onPrimaryAction: _buttonLabel == null ? null : _handleBack,
    );
  }
}
