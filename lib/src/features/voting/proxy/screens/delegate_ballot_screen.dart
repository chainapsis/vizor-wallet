import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_desktop_shell.dart';
import '../../../../core/layout/app_main_sidebar.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../voting_flow_models.dart';
import '../../widgets/voting_metadata_widgets.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../../widgets/voting_step_row.dart';
import '../delegate_mode_models.dart';
import '../delegate_mode_presentation.dart';
import '../delegate_mode_providers.dart';
import '../delegate_mode_repository.dart';
import '../proxy_delegation_copy.dart';
import '../proxy_delegation_models.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/delegate_mode_widgets.dart';
import '../widgets/delegate_reauth_gate.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// DG-9 on desktop.
class DelegateBallotScreen extends StatelessWidget {
  /// Creates the screen for [roundId].
  const DelegateBallotScreen({required this.roundId, super.key});

  /// Round to vote in.
  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: DelegateRoundBallotView(
          roundId: roundId,
          showDesktopToolbar: true,
        ),
      ),
    );
  }
}

/// Where DG-9's processing view is after the delegate confirmed DG-10.
enum DelegateBallotSubmitStage {
  /// The entry's key signs the ballot, after the re-auth.
  signing,

  /// The signed ballot is stored and posted to the vote servers.
  submitting,

  /// The ballot is posted; the round's ballot list does not show it yet.
  confirming,

  /// The round's ballot list shows the ballot.
  confirmed,
}

/// DG-9: every question of the round with its options. Submit enables only
/// when every question has an answer; there is no per-question abstain. A
/// preflight shows a ballot already on chain and never submits a different
/// one, and Submit is blocked with an explanation while the entry is
/// suspended, retired or not registered.
///
/// A ballot is submitted once. Confirming DG-10 opens a processing view, as
/// a vote's progress screen, that stays until the round's ballot list shows
/// the ballot or [kDelegateBallotConfirmTimeout] passes, and then offers
/// Done. A later visit shows where the ballot stands (see
/// [delegateBallotPending]) and never offers to submit again.
class DelegateRoundBallotView extends ConsumerStatefulWidget {
  /// Creates the view for [roundId].
  const DelegateRoundBallotView({
    required this.roundId,
    required this.showDesktopToolbar,
    super.key,
  });

  /// Round to vote in.
  final String roundId;

  /// Whether the desktop toolbar and title show.
  final bool showDesktopToolbar;

  @override
  ConsumerState<DelegateRoundBallotView> createState() =>
      _DelegateRoundBallotViewState();
}

class _DelegateRoundBallotViewState
    extends ConsumerState<DelegateRoundBallotView>
    with DelegateDeadlineTicker {
  final Map<int, int> _choices = {};
  bool _busy = false;

  /// The ballot this visit submits; the processing view shows while set.
  List<int>? _submitting;
  DelegateBallotSubmitStage _stage = DelegateBallotSubmitStage.signing;

  /// The confirm timeout passed before the list showed the ballot.
  bool _timedOut = false;
  Timer? _confirmTimer;
  String? _notice;
  ProxyNoticeTone _noticeTone = ProxyNoticeTone.info;

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  /// Drops the cached round so the screen shows the chain's state.
  void _refresh() {
    ref.invalidate(delegateRoundProvider(widget.roundId));
    ref.invalidate(delegateRoundsProvider);
  }

  /// Shows [message] above the questions.
  void _show(String message, ProxyNoticeTone tone) {
    setState(() {
      _notice = message;
      _noticeTone = tone;
    });
  }

  /// Runs the final-minute confirm, the preflight, DG-10, then the
  /// submission.
  Future<void> _review(DelegateRound round, List<int> options) async {
    final now = ref.read(proxyClockProvider)();
    final urgency = delegateBallotUrgency(
      now: now,
      voteEnd: round.voteEndTime,
      ballotOnChain: false,
    );
    if (urgency == DelegateBallotUrgency.finalSeconds) {
      final go = await showDelegateModal<bool>(
        context: context,
        title: context.l10n.delegateFinalMinuteTitle,
        builder: (context) => const DelegateFinalMinuteContent(),
      );
      if (go != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final ApiBallotPreflight preflight;
    try {
      preflight = await ref
          .read(delegateModeRepositoryProvider)
          .preflight(round.view.roundId, options);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _show(delegateModeErrorCopy(context.l10n, error), ProxyNoticeTone.error);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (preflight.alreadySubmitted) {
      final identical = preflight.sameOptions;
      _refresh();
      _show(
        identical
            ? context.l10n.delegateAlreadySubmitted
            : context.l10n.delegateDifferentBallotOnChain,
        identical ? ProxyNoticeTone.info : ProxyNoticeTone.error,
      );
      return;
    }
    final confirmed = await showDelegateModal<bool>(
      context: context,
      title: context.l10n.delegateBallotConfirmTitle,
      dismissible: false,
      builder: (context) =>
          DelegateBallotConfirmSheet(round: round, options: options),
    );
    if (confirmed != true || !mounted) return;
    await _submit(round, options);
  }

  /// Signs and submits [options] once on the processing view, after the
  /// app's re-auth. A dismissed re-auth, or a failure before the ballot is
  /// stored, goes back to the questions.
  Future<void> _submit(DelegateRound round, List<int> options) async {
    setState(() {
      _submitting = options;
      _stage = DelegateBallotSubmitStage.signing;
      _timedOut = false;
      _notice = null;
    });
    try {
      final result = await ref
          .read(delegateModeRepositoryProvider)
          .submitBallot(
            round.view.roundId,
            options,
            reauth: delegateSigningReauth(
              context,
              ref,
              DelegateReauthPurpose.signBallot,
            ),
            onSigned: () {
              if (!mounted) return;
              setState(() => _stage = DelegateBallotSubmitStage.submitting);
            },
          );
      if (!mounted) return;
      if (result.rejected) {
        // The stored ballot stays the round's only one, so DG-9 shows this
        // rejection. Only a suspension, which can be lifted, is checked
        // again in the background.
        final resender = ref.read(
          delegateBallotResenderProvider(round.view.roundId).notifier,
        );
        if (result.blocksForNow) resender.keepSending();
        resender.rejected(result);
      }
      _awaitConfirmation();
    } catch (error) {
      if (!mounted) return;
      if (error is DelegateBallotStoredException) {
        _awaitConfirmation();
        return;
      }
      setState(() => _submitting = null);
      if (!delegateSigningCancelled(error)) {
        _show(
          delegateModeErrorCopy(
            context.l10n,
            error,
            fallback: context.l10n.delegateBallotFailed,
          ),
          ProxyNoticeTone.error,
        );
      }
    } finally {
      if (mounted) _refresh();
    }
  }

  /// Moves the processing view on to waiting for the round's ballot list,
  /// and arms the timeout after which the delegate may leave.
  void _awaitConfirmation() {
    _confirmTimer?.cancel();
    _confirmTimer = Timer(kDelegateBallotConfirmTimeout, () {
      if (mounted) setState(() => _timedOut = true);
    });
    setState(() => _stage = DelegateBallotSubmitStage.confirming);
  }

  @override
  Widget build(BuildContext context) {
    final round = ref.watch(delegateRoundProvider(widget.roundId));
    final now = ref.watch(proxyClockProvider)();
    final value = round.value;
    final rejection = ref.watch(delegateBallotResenderProvider(widget.roundId));
    final submitting = _submitting;
    Widget? action;
    final Widget body;
    if (round.hasError && value == null) {
      body = ProxyNotice(
        message: delegateModeErrorCopy(context.l10n, round.error!),
        tone: ProxyNoticeTone.error,
        actionLabel: context.l10n.commonTryAgain,
        onAction: _refresh,
      );
    } else if (value == null) {
      body = const VotingPaneLoading();
    } else {
      armDeadlineTicker(now, [value.voteEndTime]);
      final onChain = value.onChainOptions;
      final blocked = delegateBallotBlockCopy(
        context.l10n,
        value.view.ballotBlock,
      );
      final urgency = delegateBallotUrgency(
        now: now,
        voteEnd: value.voteEndTime,
        ballotOnChain: onChain != null,
      );
      final closed = urgency == DelegateBallotUrgency.closed;
      final submitted =
          onChain == null &&
          (value.view.storedBallot != null || submitting != null);
      // A different listed ballot, from another device, is this one's
      // conflict, not its landing.
      final conflict = rejection?.codespace == 'vote' && rejection?.code == 57;
      final rejected = submitted || conflict ? rejection : null;
      final pending =
          submitted &&
          rejected == null &&
          !closed &&
          value.view.ballotBlock != DelegateBallotBlock.retired;
      if (pending && value.view.storedBallot != null) {
        ref
            .read(delegateBallotResenderProvider(widget.roundId).notifier)
            .keepSending();
      }
      if (submitting != null) {
        final stage = onChain != null && listEquals(onChain, submitting)
            ? DelegateBallotSubmitStage.confirmed
            : _stage;
        final waiting = stage == DelegateBallotSubmitStage.confirming;
        final ended = waiting && closed && rejected == null;
        body = DelegateBallotProgressContent(
          round: value,
          options: onChain ?? submitting,
          stage: stage,
          stillConfirming: waiting && _timedOut,
          votingEnded: ended,
          rejection: waiting && rejected != null
              ? delegateBallotRejectionCopy(
                  context.l10n,
                  rejected.codespace,
                  rejected.code,
                )
              : null,
        );
        final finished =
            stage == DelegateBallotSubmitStage.confirmed ||
            (waiting && (_timedOut || ended || rejected != null));
        if (finished) {
          action = AppButton(
            key: const ValueKey('delegate_ballot_done'),
            onPressed: () => context.go(kDelegateModePath),
            expand: true,
            growWithContent: true,
            constrainContent: true,
            child: Text(context.l10n.commonDone),
          );
        }
      } else {
        final fixed = onChain ?? value.view.storedBallot;
        final choices = fixed == null ? _choices : delegateBallotChoices(fixed);
        final options = delegateBallotOptions(value.proposals, choices);
        final editable = fixed == null && blocked == null && !closed && !_busy;
        body = DelegateBallotContent(
          round: value,
          now: now,
          choices: choices,
          editable: editable,
          pending: pending,
          rejection: rejected == null
              ? null
              : delegateBallotRejectionCopy(
                  context.l10n,
                  rejected.codespace,
                  rejected.code,
                ),
          notice: _notice,
          noticeTone: _noticeTone,
          onChoice: (proposalId, choice) => setState(() {
            _notice = null;
            if (choice == null) {
              _choices.remove(proposalId);
            } else {
              _choices[proposalId] = choice;
            }
          }),
        );
        if (fixed == null) {
          final answered = value.proposals
              .where((proposal) => choices[proposal.id] != null)
              .length;
          action = DelegateBallotFooter(
            answered: answered,
            total: value.proposals.length,
            onSubmit: options != null && editable
                ? () => _review(value, options)
                : null,
          );
        }
      }
    }
    return ProxyPaneLayout(
      showDesktopToolbar: widget.showDesktopToolbar,
      title: context.l10n.delegateBallotTitle,
      action: action,
      child: body,
    );
  }
}

/// DG-9's processing view, laid out as a vote's progress screen: signing,
/// submitting and confirming rows, then "Ballot submitted" with the chosen
/// answers once the round's ballot list shows the ballot. A chain
/// rejection, the end of voting, or the confirm timeout shows under the
/// rows.
class DelegateBallotProgressContent extends StatelessWidget {
  /// Creates the view.
  const DelegateBallotProgressContent({
    required this.round,
    required this.options,
    required this.stage,
    this.stillConfirming = false,
    this.votingEnded = false,
    this.rejection,
    super.key,
  });

  /// The round.
  final DelegateRound round;

  /// The ballot, `options[i]` answering proposal `i + 1`.
  final List<int> options;

  /// How far the submission is.
  final DelegateBallotSubmitStage stage;

  /// The confirm timeout passed; background resends go on.
  final bool stillConfirming;

  /// Voting ended before the round's ballot list showed the ballot.
  final bool votingEnded;

  /// The chain's rejection of the ballot.
  final String? rejection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rejection = this.rejection;
    final confirmed = stage == DelegateBallotSubmitStage.confirmed;
    final moving = rejection == null && !votingEnded;
    final title = Text(
      confirmed
          ? context.l10n.delegateBallotSubmittedTitle
          : context.l10n.delegateBallotProgressTitle,
      key: const ValueKey('delegate_ballot_progress_title'),
      textAlign: TextAlign.center,
      style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
    );
    final subtitle = Text(
      confirmed
          ? context.l10n.delegateBallotOnChain
          : context.l10n.delegateBallotProgress,
      textAlign: TextAlign.center,
      style: AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
    );

    /// The row for [step], titled [label].
    Widget row(DelegateBallotSubmitStage step, String label) => VotingStepRow(
      key: ValueKey('delegate_ballot_step_${step.name}'),
      label: label,
      active: moving && stage == step,
      complete: stage.index > step.index,
    );
    return Column(
      key: ValueKey(
        confirmed ? 'delegate_ballot_success' : 'delegate_ballot_progress',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        title,
        const SizedBox(height: AppSpacing.sm),
        subtitle,
        const SizedBox(height: AppSpacing.md),
        if (confirmed)
          DelegateBallotChoiceList(
            proposals: round.proposals,
            options: options,
            keyPrefix: 'delegate_success_choice',
          )
        else ...[
          row(
            DelegateBallotSubmitStage.signing,
            context.l10n.delegateStepSigning,
          ),
          row(
            DelegateBallotSubmitStage.submitting,
            context.l10n.delegateStepSubmitting,
          ),
          row(
            DelegateBallotSubmitStage.confirming,
            context.l10n.delegateStepConfirming,
          ),
          if (rejection != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ProxyNotice(
              key: const ValueKey('delegate_ballot_rejected'),
              message: rejection,
              tone: ProxyNoticeTone.error,
            ),
          ] else if (votingEnded) ...[
            const SizedBox(height: AppSpacing.sm),
            ProxyNotice(
              key: const ValueKey('delegate_ballot_closed'),
              message: context.l10n.delegateVotingEnded,
              tone: ProxyNoticeTone.error,
            ),
          ] else if (stillConfirming) ...[
            const SizedBox(height: AppSpacing.sm),
            ProxyNotice(
              key: const ValueKey('delegate_ballot_still_confirming'),
              message: context.l10n.delegateBallotStillConfirming,
            ),
          ],
        ],
      ],
    );
  }
}

/// Each question of a ballot with the option [options] picks, as DG-10 and
/// the processing view's success list them.
class DelegateBallotChoiceList extends StatelessWidget {
  /// Creates the list.
  const DelegateBallotChoiceList({
    required this.proposals,
    required this.options,
    required this.keyPrefix,
    super.key,
  });

  /// The round's questions.
  final List<VotingProposalView> proposals;

  /// The ballot, `options[i]` answering proposal `i + 1`.
  final List<int> options;

  /// Prefix of each row's key, followed by its index.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final choices = delegateBallotChoiceLabels(
      context.l10n,
      proposals,
      options,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, choice) in choices.indexed)
          Padding(
            key: ValueKey('${keyPrefix}_$i'),
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ProxyBodyText(choice.proposal)),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    choice.option,
                    textAlign: TextAlign.end,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// DG-9's pinned footer: how many questions are answered, and Submit.
class DelegateBallotFooter extends StatelessWidget {
  /// Creates the footer.
  const DelegateBallotFooter({
    required this.answered,
    required this.total,
    this.onSubmit,
    super.key,
  });

  /// Questions with an answer.
  final int answered;

  /// Questions in the round.
  final int total;

  /// Opens the confirm step; null until the ballot is complete.
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.delegateAnswered(answered, total),
          key: const ValueKey('delegate_ballot_answered'),
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('delegate_ballot_submit'),
          onPressed: onSubmit,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.delegateSubmitBallotLabel),
        ),
      ],
    );
  }
}

/// Session-free DG-9 body shared by the live view and tests.
class DelegateBallotContent extends StatelessWidget {
  /// Creates the body.
  const DelegateBallotContent({
    required this.round,
    required this.now,
    required this.choices,
    required this.editable,
    this.pending = false,
    this.rejection,
    this.notice,
    this.noticeTone = ProxyNoticeTone.info,
    this.onChoice,
    super.key,
  });

  /// The round.
  final DelegateRound round;

  /// Current time.
  final DateTime now;

  /// Choices by proposal id: the draft, or the fixed ballot.
  final Map<int, int> choices;

  /// The delegate may still change choices.
  final bool editable;

  /// The ballot is submitted and confirming on chain, see
  /// [delegateBallotPending].
  final bool pending;

  /// The chain's rejection of the submitted ballot.
  final String? rejection;

  /// A preflight or submission message.
  final String? notice;

  /// Tone of [notice].
  final ProxyNoticeTone noticeTone;

  /// A choice changed; null clears the question.
  final void Function(int proposalId, int? choice)? onChoice;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.s);
    final onChain = round.onChainOptions != null;
    final rejection = this.rejection;
    final blocked = delegateBallotBlockCopy(
      context.l10n,
      round.view.ballotBlock,
    );
    final urgency = delegateBallotUrgency(
      now: now,
      voteEnd: round.voteEndTime,
      ballotOnChain: onChain || pending,
    );
    final notice = this.notice;
    final proposals = [...round.proposals]
      ..sort((a, b) => a.id.compareTo(b.id));
    return Column(
      key: const ValueKey('delegate_ballot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          round.title,
          style: AppTypography.headlineSmall.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        ProxyBodyText(
          context.l10n.delegateVotingEnds(
            formatProxyVoteEnd(context.l10n, round.voteEndTime),
          ),
        ),
        gap,
        ProxyNotice(
          key: const ValueKey('delegate_ballot_rules'),
          message: context.l10n.proxyBallotRules,
        ),
        if (onChain) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_ballot_on_chain'),
            // Its weight is counted at close, not when it lands.
            message: round.view.ballot.kind == ApiDelegateBallotKind.counted
                ? context.l10n.delegateBallotCounted
                : context.l10n.delegateBallotOnChain,
          ),
        ] else if (rejection != null) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_ballot_rejected'),
            message: rejection,
            tone: ProxyNoticeTone.error,
          ),
        ] else if (pending) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_ballot_pending'),
            message: context.l10n.delegateBallotPendingLabel,
          ),
        ],
        if (blocked != null && !onChain && rejection == null) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_ballot_blocked'),
            message: blocked,
            tone: ProxyNoticeTone.error,
          ),
        ],
        if (urgency == DelegateBallotUrgency.closed) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_ballot_closed'),
            message: context.l10n.delegateVotingEnded,
            tone: ProxyNoticeTone.error,
          ),
        ] else if (urgency == DelegateBallotUrgency.finalMinutes ||
            urgency == DelegateBallotUrgency.finalSeconds) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_ballot_final_minutes'),
            message: context.l10n.delegateFinalMinutes(
              delegateMinutesLeft(now: now, voteEnd: round.voteEndTime),
            ),
            tone: ProxyNoticeTone.warning,
          ),
        ],
        if (notice != null) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('delegate_ballot_notice'),
            message: notice,
            tone: noticeTone,
          ),
        ],
        for (final proposal in proposals) ...[
          gap,
          VotingProposalCard(
            key: ValueKey('delegate_ballot_question_${proposal.id}'),
            proposal: proposal,
            selectedChoice: choices[proposal.id],
            enabled: editable,
            readOnly: !editable,
            onChoice: editable && onChoice != null
                ? (choice) => onChoice!(proposal.id, choice)
                : null,
          ),
        ],
      ],
    );
  }
}

/// DG-10: every choice, the "Ballot confirm" copy, and Submit, which
/// closes the sheet with true so DG-9 signs and submits the ballot once on
/// its processing view. Cancel closes it with false.
class DelegateBallotConfirmSheet extends StatefulWidget {
  /// Creates the sheet for [options] in [round].
  const DelegateBallotConfirmSheet({
    required this.round,
    required this.options,
    super.key,
  });

  /// The round.
  final DelegateRound round;

  /// The complete ballot, `options[i]` answering proposal `i + 1`.
  final List<int> options;

  @override
  State<DelegateBallotConfirmSheet> createState() =>
      _DelegateBallotConfirmSheetState();
}

class _DelegateBallotConfirmSheetState
    extends State<DelegateBallotConfirmSheet> {
  bool _closed = false;

  /// Closes the sheet with [submit], once: a second press while it closes
  /// would pop DG-9 too.
  void _close(bool submit) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(submit);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('delegate_ballot_confirm'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(
          context.l10n.proxyBallotConfirm(widget.round.proposals.length),
        ),
        const SizedBox(height: AppSpacing.s),
        DelegateBallotChoiceList(
          proposals: widget.round.proposals,
          options: widget.options,
          keyPrefix: 'delegate_confirm_choice',
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          key: const ValueKey('delegate_confirm_submit'),
          onPressed: () => _close(true),
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.delegateSubmitBallotLabel),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('delegate_confirm_cancel'),
          onPressed: () => _close(false),
          variant: AppButtonVariant.ghost,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.commonCancel),
        ),
      ],
    );
  }
}

/// The blocking confirm in the final 60 seconds before `vote_end`.
class DelegateFinalMinuteContent extends StatelessWidget {
  /// Creates the content.
  const DelegateFinalMinuteContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('delegate_final_minute'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProxyBodyText(context.l10n.delegateFinalMinute),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('delegate_final_minute_submit'),
          onPressed: () => Navigator.of(context).pop(true),
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.delegateSubmitAnywayLabel),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('delegate_final_minute_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          variant: AppButtonVariant.ghost,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          child: Text(context.l10n.commonCancel),
        ),
      ],
    );
  }
}
