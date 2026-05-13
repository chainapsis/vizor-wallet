import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../voting_flow_models.dart';
import '../voting_routes.dart';
import '../voting_share_timing.dart';

class VotingStatusScreen extends ConsumerStatefulWidget {
  const VotingStatusScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingStatusScreen> createState() => _VotingStatusScreenState();
}

class _VotingStatusScreenState extends ConsumerState<VotingStatusScreen> {
  bool _started = false;
  bool _completedInThisRun = false;
  bool _softwareAccountRequired = false;
  String? _runErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_started) return;
    try {
      _started = true;
      if (mounted) {
        setState(() {
          _runErrorMessage = null;
          _softwareAccountRequired = false;
        });
      }

      final roundId = widget.roundId;
      final sessionNotifier = ref.read(votingSessionProvider(roundId).notifier);
      final session = await ref.read(votingSessionProvider(roundId).future);
      final round = session.round;
      if (round == null) {
        _setRunError(
          'Voting round details are not available yet. Retry in a moment.',
        );
        return;
      }
      final proposals = proposalsFromRound(round);
      final accountUuid = session.accountUuid;
      if (accountUuid == null) {
        _setRunError('No active account for voting session.');
        return;
      }
      final draftVotes = ref
          .read(
            votingDraftProvider(
              VotingSessionKey(roundId: roundId, accountUuid: accountUuid),
            ),
          )
          .toDraftVotes(proposals);
      if (draftVotes.isEmpty) {
        _setRunError('Choose at least one vote before submitting.');
        return;
      }

      final mnemonic = await ref
          .read(accountProvider.notifier)
          .getMnemonicForAccount(accountUuid);
      if (mnemonic == null || mnemonic.isEmpty) {
        if (!mounted) return;
        setState(() {
          _softwareAccountRequired = true;
        });
        return;
      }
      final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
      try {
        await sessionNotifier.delegatePendingBundles(seedBytes: seedBytes);
      } finally {
        seedBytes.fillRange(0, seedBytes.length, 0);
      }
      final afterDelegation = ref.read(votingSessionProvider(roundId)).value;
      if (afterDelegation?.phase == VotingSessionPhase.error) return;
      await sessionNotifier.castVotes(draftVotes: draftVotes);
      final afterVotes = ref.read(votingSessionProvider(roundId)).value;
      if (afterVotes?.phase == VotingSessionPhase.error) return;
      await sessionNotifier.submitPendingShares();
      final done = ref.read(votingSessionProvider(roundId)).value;
      if (!mounted || done?.phase != VotingSessionPhase.done) return;
      setState(() {
        _completedInThisRun = true;
      });
      context.go(votingSubmissionConfirmedRoute(roundId));
    } catch (error) {
      _setRunError(_messageFromError(error));
    }
  }

  void _setRunError(String message) {
    if (!mounted) return;
    setState(() {
      _runErrorMessage = message;
      _softwareAccountRequired = false;
    });
  }

  String _messageFromError(Object error) {
    final text = error.toString().trim();
    for (final prefix in const ['Exception: ', 'StateError: ', 'Bad state: ']) {
      if (text.startsWith(prefix)) {
        return text.substring(prefix.length);
      }
    }
    return text.isEmpty ? 'Voting session action failed.' : text;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(votingSessionProvider(widget.roundId));
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: SensitivePrivacyOverlay(
          sensitiveContentVisible: true,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: session.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _StatusContent(
                phase: VotingSessionPhase.error,
                errorMessage: _runErrorMessage ?? _messageFromError(error),
                onRetry: _retry,
              ),
              data: (state) {
                final localError = _runErrorMessage;
                final phase = localError == null
                    ? _displayPhase(state.phase)
                    : VotingSessionPhase.error;
                return _StatusContent(
                  phase: phase,
                  shareSummary: _shareSummary(state),
                  softwareAccountRequired: _softwareAccountRequired,
                  errorMessage: localError ?? state.error?.message,
                  onRetry: _retry,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  VotingSessionPhase _displayPhase(VotingSessionPhase phase) {
    if (phase == VotingSessionPhase.done && !_completedInThisRun) {
      return VotingSessionPhase.loadingWitnesses;
    }
    return phase;
  }

  VotingShareTrackingSummary? _shareSummary(VotingSessionState state) {
    final plan = state.resumePlan;
    final round = state.round;
    if (plan == null || round == null || plan.shareDelegations.isEmpty) {
      return null;
    }
    return VotingShareTrackingSummary.fromShares(plan.shareDelegations, round);
  }

  void _retry() {
    _started = false;
    _completedInThisRun = false;
    _softwareAccountRequired = false;
    _runErrorMessage = null;
    unawaited(_run());
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.phase,
    this.shareSummary,
    this.softwareAccountRequired = false,
    this.errorMessage,
    this.onRetry,
  });

  final VotingSessionPhase phase;
  final VotingShareTrackingSummary? shareSummary;
  final bool softwareAccountRequired;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (softwareAccountRequired) {
      return const _SoftwareAccountRequiredContent();
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              phase == VotingSessionPhase.done
                  ? 'Votes Submitted'
                  : 'Submitting Votes',
              textAlign: TextAlign.center,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Don't close the window. Generating zero-knowledge proofs can take a while; closing now may lose in-flight proof work.",
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _StepRow(
              label: 'Selecting notes',
              complete: _after(VotingSessionPhase.loadingWitnesses),
            ),
            _StepRow(
              label: 'Delegating voting authority',
              active: phase == VotingSessionPhase.delegating,
              complete: _after(VotingSessionPhase.delegating),
            ),
            _StepRow(
              label: 'Submitting delegation',
              complete: _after(VotingSessionPhase.delegated),
            ),
            _StepRow(
              label: 'Casting votes',
              active:
                  phase == VotingSessionPhase.castingVotes ||
                  phase == VotingSessionPhase.syncingVoteTree,
              complete: _after(VotingSessionPhase.castingVotes),
            ),
            _StepRow(
              label: 'Submitting shares',
              active: phase == VotingSessionPhase.submittingShares,
              complete: phase == VotingSessionPhase.done,
            ),
            if (shareSummary case final summary? when summary.hasShares) ...[
              const SizedBox(height: AppSpacing.xs),
              _ShareTrackingRows(summary: summary),
            ],
            if (phase == VotingSessionPhase.error) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                errorMessage ?? 'Voting failed.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: onRetry,
                variant: AppButtonVariant.primary,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _after(VotingSessionPhase target) {
    return phase.index > target.index && phase != VotingSessionPhase.error;
  }
}

class _ShareTrackingRows extends StatelessWidget {
  const _ShareTrackingRows({required this.summary});

  final VotingShareTrackingSummary summary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            _ShareStatusLine(
              label: 'Accepted, waiting for reveal',
              count: summary.waiting,
            ),
            _ShareStatusLine(
              label: 'Ready for helper confirmation',
              count: summary.ready,
            ),
            _ShareStatusLine(
              label: 'Overdue, retrying helpers',
              count: summary.overdue,
            ),
            _ShareStatusLine(
              label: 'Confirmed by helper',
              count: summary.confirmed,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareStatusLine extends StatelessWidget {
  const _ShareStatusLine({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Text(
            count.toString(),
            style: AppTypography.bodySmall.copyWith(color: colors.text.accent),
          ),
        ],
      ),
    );
  }
}

class _SoftwareAccountRequiredContent extends StatelessWidget {
  const _SoftwareAccountRequiredContent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Software Account Required',
              textAlign: TextAlign.center,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Coinholder voting requires a software account. Switch to a software account to vote in this round.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    this.active = false,
    this.complete = false,
  });

  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: active
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(
                    complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: complete
                        ? colors.text.success
                        : colors.text.secondary,
                  ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: active || complete
                    ? colors.text.accent
                    : colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
