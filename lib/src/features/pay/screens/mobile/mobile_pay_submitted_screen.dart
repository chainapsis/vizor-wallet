import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/models/swap_deposit_broadcast_result.dart';
import '../../../swap/models/swap_models.dart';
import '../../../swap/providers/swap_state_provider.dart';

const kMobilePayIntentRestoreGrace = Duration(seconds: 2);

class MobilePayDepositProgress {
  const MobilePayDepositProgress({required this.phase, this.notice});

  final MobileTransactionProgressPhase phase;
  final String? notice;
}

/// Maps the Pay deposit broadcast lifecycle without treating an intent being
/// created as proof that its transaction reached the network.
MobilePayDepositProgress mobilePayDepositProgressFor({
  required SwapState state,
  required String intentId,
}) {
  final intent = state.intents.swapIntentById(intentId);
  final txHash = _nonEmpty(intent?.depositTxHash);
  final broadcastStatus = _nonEmpty(intent?.broadcastStatus);

  if (intent?.hasProviderObservedDepositEvidence ?? false) {
    return const MobilePayDepositProgress(
      phase: MobileTransactionProgressPhase.succeeded,
    );
  }

  if (txHash != null) {
    if (broadcastStatus == null ||
        broadcastStatus == SwapDepositBroadcastStatus.broadcasted) {
      return const MobilePayDepositProgress(
        phase: MobileTransactionProgressPhase.succeeded,
      );
    }
    return MobilePayDepositProgress(
      phase: MobileTransactionProgressPhase.pending,
      notice:
          _nonEmpty(intent?.broadcastNotice) ??
          'The payment status is uncertain. Check Activity before trying again.',
    );
  }

  final isRelevantIntent = state.selectedIntentId == intentId;
  if (isRelevantIntent && state.depositSubmitting) {
    return const MobilePayDepositProgress(
      phase: MobileTransactionProgressPhase.inProgress,
    );
  }

  final error =
      _nonEmpty(intent?.statusError) ??
      (isRelevantIntent ? _nonEmpty(state.statusError) : null);
  if (error != null) {
    return MobilePayDepositProgress(
      phase: MobileTransactionProgressPhase.failed,
      notice: error,
    );
  }

  // The route can restore before persisted intents finish hydrating. Keep the
  // non-terminal presentation until there is positive success/failure evidence.
  return const MobilePayDepositProgress(
    phase: MobileTransactionProgressPhase.inProgress,
  );
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Mobile Pay handoff while its ZEC deposit is being submitted.
///
/// Figma success: light `6268:85812`, dark `6268:86061`.
class MobilePaySubmittedScreen extends ConsumerStatefulWidget {
  const MobilePaySubmittedScreen({required this.intentId, super.key});

  final String intentId;

  @override
  ConsumerState<MobilePaySubmittedScreen> createState() =>
      _MobilePaySubmittedScreenState();
}

class _MobilePaySubmittedScreenState
    extends ConsumerState<MobilePaySubmittedScreen> {
  Timer? _restoreGraceTimer;
  var _restoreGraceElapsed = false;

  @override
  void initState() {
    super.initState();
    _startRestoreGraceTimer();
  }

  @override
  void didUpdateWidget(covariant MobilePaySubmittedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentId != widget.intentId) _startRestoreGraceTimer();
  }

  void _startRestoreGraceTimer() {
    _restoreGraceTimer?.cancel();
    _restoreGraceElapsed = false;
    _restoreGraceTimer = Timer(kMobilePayIntentRestoreGrace, () {
      if (mounted) setState(() => _restoreGraceElapsed = true);
    });
  }

  @override
  void dispose() {
    _restoreGraceTimer?.cancel();
    super.dispose();
  }

  void _openActivity(BuildContext context) {
    context.go(
      swapActivityDetailUri(
        intentId: widget.intentId,
        returnTarget: SwapActivityReturnTarget.pay,
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapStateProvider);
    final baseProgress = mobilePayDepositProgressFor(
      state: swapState,
      intentId: widget.intentId,
    );
    final intentMissing =
        swapState.intents.swapIntentById(widget.intentId) == null;
    // A persisted intent can outlive its unawaited deposit sender. Only a
    // route-scoped submitting flag proves that this screen should stay locked.
    final hasActiveSubmission =
        swapState.selectedIntentId == widget.intentId &&
        swapState.depositSubmitting;
    final paymentUnavailable =
        intentMissing &&
        _restoreGraceElapsed &&
        baseProgress.phase == MobileTransactionProgressPhase.inProgress;
    final submissionInterrupted =
        !intentMissing &&
        !hasActiveSubmission &&
        _restoreGraceElapsed &&
        baseProgress.phase == MobileTransactionProgressPhase.inProgress;
    final progress = paymentUnavailable
        ? const MobilePayDepositProgress(
            phase: MobileTransactionProgressPhase.failed,
            notice:
                "We couldn't load this payment. Check Activity for its latest status.",
          )
        : submissionInterrupted
        ? const MobilePayDepositProgress(
            phase: MobileTransactionProgressPhase.pending,
          )
        : baseProgress;
    final terminal =
        progress.phase != MobileTransactionProgressPhase.inProgress;
    final title = paymentUnavailable
        ? 'Payment unavailable'
        : switch (progress.phase) {
            MobileTransactionProgressPhase.inProgress =>
              'Submitting payment...',
            MobileTransactionProgressPhase.pending =>
              'Payment status\nuncertain',
            MobileTransactionProgressPhase.succeeded => 'Payment\nSubmitted',
            MobileTransactionProgressPhase.failed => 'Payment failed',
          };
    final body = switch (progress.phase) {
      MobileTransactionProgressPhase.inProgress =>
        'Submitting your payment to the network...',
      MobileTransactionProgressPhase.pending =>
        progress.notice ??
            'The payment status is uncertain. Check Activity before trying again.',
      MobileTransactionProgressPhase.succeeded =>
        'It will confirm on-chain shortly.\nTrack it in Activity.',
      MobileTransactionProgressPhase.failed =>
        progress.notice ?? 'The payment could not be submitted. Try again.',
    };

    return MobileTransactionProgressScreen(
      phase: progress.phase,
      title: title,
      body: body,
      bodyMaxWidth:
          progress.phase == MobileTransactionProgressPhase.pending ||
              progress.phase == MobileTransactionProgressPhase.failed
          ? null
          : 245,
      canPop: terminal,
      statusBadgeKey: const ValueKey('pay_submitted_status'),
      titleKey: const ValueKey('pay_submitted_title'),
      progressIconKey: const ValueKey('pay_submitted_status_loader'),
      successIconKey: const ValueKey('pay_submitted_status_success'),
      failureIconKey: const ValueKey('pay_submitted_status_failed'),
      successRippleKey: const ValueKey('pay_submitted_status_ripple'),
      primaryActionKey: const ValueKey('pay_submitted_done'),
      primaryActionLabel: terminal
          ? progress.phase == MobileTransactionProgressPhase.failed
                ? 'Return home'
                : 'Done'
          : null,
      onPrimaryAction: terminal ? () => context.go('/home') : null,
      secondaryActionKey: const ValueKey('pay_submitted_activity'),
      secondaryActionLabel: terminal ? 'Go to activity' : null,
      onSecondaryAction: terminal
          ? () => paymentUnavailable
                ? context.go('/activity')
                : _openActivity(context)
          : null,
    );
  }
}
