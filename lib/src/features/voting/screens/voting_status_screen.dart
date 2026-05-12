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

class VotingStatusScreen extends ConsumerStatefulWidget {
  const VotingStatusScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingStatusScreen> createState() => _VotingStatusScreenState();
}

class _VotingStatusScreenState extends ConsumerState<VotingStatusScreen> {
  bool _started = false;
  bool _completedInThisRun = false;

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
    _started = true;
    final roundId = widget.roundId;
    final sessionNotifier = ref.read(votingSessionProvider(roundId).notifier);
    final session = await ref.read(votingSessionProvider(roundId).future);
    final round = session.round;
    if (round == null) return;
    final proposals = proposalsFromRound(round);
    final draftVotes = ref
        .read(votingDraftProvider(roundId))
        .toDraftVotes(proposals);
    if (draftVotes.isEmpty) return;

    final mnemonic = await ref
        .read(accountProvider.notifier)
        .getActiveMnemonic();
    if (mnemonic == null || mnemonic.isEmpty) {
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
                errorMessage: '$error',
                onRetry: _retry,
              ),
              data: (state) {
                final phase = _displayPhase(state.phase);
                return _StatusContent(
                  phase: phase,
                  errorMessage: state.error?.message,
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

  void _retry() {
    _started = false;
    _completedInThisRun = false;
    unawaited(_run());
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.phase, this.errorMessage, this.onRetry});

  final VotingSessionPhase phase;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
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
