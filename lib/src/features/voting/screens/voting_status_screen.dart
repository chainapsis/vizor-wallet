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
import '../../../providers/voting/voting_submission_guard_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../rust/api/voting.dart' as rust_voting;
import '../../../services/voting/pir_snapshot_resolver.dart';
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../voting_flow_models.dart';
import '../voting_error_messages.dart';
import '../voting_formatters.dart';
import '../voting_resume_plan.dart';
import '../voting_routes.dart';

class VotingStatusScreen extends ConsumerStatefulWidget {
  const VotingStatusScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingStatusScreen> createState() => _VotingStatusScreenState();
}

class _VotingStatusScreenState extends ConsumerState<VotingStatusScreen> {
  bool _started = false;
  bool _softwareAccountRequired = false;
  String? _runErrorMessage;
  List<String> _keystoneUrParts = const [];
  String? _keystoneQrError;
  List<rust_voting.ApiDraftVote>? _pendingDraftVotes;
  List<int> _pendingProposalIds = const [];
  Map<int, int> _pendingProposalOptionCounts = const {};
  bool _pendingRecoveryWithoutDraft = false;
  int _runGeneration = 0;
  String? _runAccountUuid;
  late final VotingSubmissionGuardNotifier _submissionGuardNotifier;
  VotingSubmissionGuard? _submissionGuard;

  @override
  void dispose() {
    _runGeneration++;
    _releaseSubmissionGuard();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _submissionGuardNotifier = ref.read(votingSubmissionGuardProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_started) return;
    final runGeneration = ++_runGeneration;
    try {
      _started = true;
      if (mounted) {
        setState(() {
          _runErrorMessage = null;
          _softwareAccountRequired = false;
        });
      }

      final roundId = widget.roundId;
      final sessionProvider = votingSessionProvider(roundId);
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final loadedSession =
          _sessionForRunAccount(accountUuid: null) ??
          await ref.read(sessionProvider.future);
      if (!_isCurrentRun(runGeneration)) return;
      if (loadedSession == null) {
        _setRunError(
          'Voting round details are not available yet. Retry in a moment.',
        );
        return;
      }
      final session = loadedSession;
      if (!mounted) return;
      final round = session.round;
      if (round == null) {
        _setRunError(
          'Voting round details are not available yet. Retry in a moment.',
        );
        return;
      }
      final proposals = proposalsFromRound(round);
      final proposalOptionCounts = {
        for (final proposal in proposals) proposal.id: proposal.options.length,
      };
      final accountUuid = session.accountUuid;
      if (accountUuid == null) {
        _setRunError('No active account for voting session.');
        return;
      }
      _runAccountUuid = accountUuid;
      _ensureSubmissionGuard(accountUuid);
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) {
        _releaseSubmissionGuard();
        _started = false;
        return;
      }
      final draftKey = VotingSessionKey(
        roundId: roundId,
        accountUuid: accountUuid,
      );
      final draft = await ref
          .read(votingDraftProvider(draftKey).notifier)
          .ensureLoaded();
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      final userDraftVotes = draft.toDraftVotes(proposals);
      final proposalIds = proposals.map((proposal) => proposal.id).toList();
      await sessionNotifier.ensureWalletReadyForVoting();
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      final afterWalletSync = _sessionForRunAccount(accountUuid: accountUuid);
      if (afterWalletSync?.phase == VotingSessionPhase.error ||
          afterWalletSync?.phase == VotingSessionPhase.waitingForWalletSync) {
        if (afterWalletSync?.phase == VotingSessionPhase.error) {
          _setRunError(
            _statusErrorMessage(afterWalletSync!) ??
                _genericVotingStatusErrorMessage,
          );
          _releaseSubmissionGuard();
        }
        return;
      }
      final activeSession = afterWalletSync ?? session;
      final recoveredDraftVotes =
          userDraftVotes.isEmpty && _roundPlanHasNoOpenProposals(activeSession)
          ? _draftVotesFromRoundPlan(activeSession.roundPlan, proposals)
          : const <rust_voting.ApiDraftVote>[];
      final draftVotes = userDraftVotes.isNotEmpty
          ? userDraftVotes
          : recoveredDraftVotes;
      final intentProposalIds = userDraftVotes.isNotEmpty
          ? proposalIds
          : const <int>[];
      final canRecoverWithoutDraft = _canRecoverWithoutDraft(activeSession);
      final canPollDelegationWithoutDraft = _canPollDelegationWithoutDraft(
        activeSession,
      );
      final needsDelegation = _sessionNeedsDelegation(activeSession);
      if (draftVotes.isEmpty &&
          !canRecoverWithoutDraft &&
          !canPollDelegationWithoutDraft) {
        _setRunError('Choose at least one vote before submitting.');
        return;
      }

      if (activeSession.isHardwareAccount &&
          _sessionNeedsKeystoneSigning(activeSession)) {
        _pendingDraftVotes = draftVotes;
        _pendingProposalIds = intentProposalIds;
        _pendingProposalOptionCounts = proposalOptionCounts;
        _pendingRecoveryWithoutDraft =
            canRecoverWithoutDraft || canPollDelegationWithoutDraft;
        await _prepareKeystoneSigning(
          sessionNotifier,
          runGeneration: runGeneration,
          accountUuid: accountUuid,
        );
        return;
      }

      if (draftVotes.isNotEmpty || needsDelegation) {
        if (activeSession.isHardwareAccount) {
          if (needsDelegation) {
            _pendingDraftVotes = draftVotes;
            _pendingProposalIds = intentProposalIds;
            _pendingProposalOptionCounts = proposalOptionCounts;
            _pendingRecoveryWithoutDraft =
                canRecoverWithoutDraft || canPollDelegationWithoutDraft;
            await _submitAfterKeystoneSignatures(
              sessionNotifier,
              runGeneration: runGeneration,
              accountUuid: accountUuid,
            );
          } else {
            await _submitVotesAndShares(
              sessionNotifier,
              runGeneration: runGeneration,
              accountUuid: accountUuid,
              draftVotes: draftVotes,
              intentProposalIds: intentProposalIds,
              proposalOptionCounts: proposalOptionCounts,
              initialSession: activeSession,
            );
          }
          return;
        }
        final mnemonic = await ref
            .read(accountProvider.notifier)
            .getMnemonicForAccount(accountUuid);
        if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
        if (mnemonic == null || mnemonic.isEmpty) {
          _releaseSubmissionGuard();
          setState(() {
            _softwareAccountRequired = true;
          });
          return;
        }
        final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
        try {
          if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
          await sessionNotifier.delegatePendingBundles(seedBytes: seedBytes);
        } finally {
          seedBytes.fillRange(0, seedBytes.length, 0);
        }
        if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
        final afterDelegation = _sessionForRunAccount(accountUuid: accountUuid);
        if (afterDelegation?.phase == VotingSessionPhase.error) {
          _releaseSubmissionGuard();
          return;
        }
      }
      final afterDelegation = _sessionForRunAccount(accountUuid: accountUuid);
      await _submitVotesAndShares(
        sessionNotifier,
        runGeneration: runGeneration,
        accountUuid: accountUuid,
        draftVotes: draftVotes,
        intentProposalIds: intentProposalIds,
        proposalOptionCounts: proposalOptionCounts,
        initialSession: afterDelegation ?? activeSession,
      );
    } catch (error) {
      if (!_isCurrentRunForStoredAccount(runGeneration)) return;
      _setRunError(_messageFromError(error));
    }
  }

  Future<void> _prepareKeystoneSigning(
    VotingSessionNotifier sessionNotifier, {
    required int runGeneration,
    required String accountUuid,
  }) async {
    await sessionNotifier.prepareKeystoneSigning();
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    final state = _sessionForRunAccount(accountUuid: accountUuid);
    if (state == null) return;
    if (state.phase == VotingSessionPhase.error) {
      _releaseSubmissionGuard();
      return;
    }
    final request = state.keystoneSigningRequest;
    if (request != null) {
      await _updateKeystoneQr(
        request,
        runGeneration: runGeneration,
        accountUuid: accountUuid,
      );
      return;
    }
    await _submitAfterKeystoneSignatures(
      sessionNotifier,
      runGeneration: runGeneration,
      accountUuid: accountUuid,
    );
  }

  Future<void> _updateKeystoneQr(
    rust_voting.ApiKeystoneDelegationRequest request, {
    required int runGeneration,
    required String accountUuid,
  }) async {
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    setState(() {
      _keystoneUrParts = const [];
      _keystoneQrError = null;
    });
    try {
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: request.redactedPcztBytes,
        maxFragmentLen: BigInt.from(200),
      );
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      setState(() {
        _keystoneUrParts = urParts;
        _keystoneQrError = null;
      });
    } catch (error) {
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      _setRunError(
        'Failed to prepare Keystone voting QR: ${_messageFromError(error)}',
      );
    }
  }

  Future<void> _scanKeystoneSignature() async {
    final runGeneration = _runGeneration;
    final accountUuid = _runAccountUuid;
    if (accountUuid == null) return;
    final signedPczt = await context.push<List<int>>('/voting/keystone/scan');
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    if (signedPczt == null || signedPczt.isEmpty) return;

    try {
      final sessionNotifier = ref.read(
        votingSessionProvider(widget.roundId).notifier,
      );
      await sessionNotifier.handleKeystoneSignedPczt(signedPczt);
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      final state = _sessionForRunAccount(accountUuid: accountUuid);
      if (state == null) return;
      if (state.phase == VotingSessionPhase.error) {
        _releaseSubmissionGuard();
        return;
      }
      final request = state.keystoneSigningRequest;
      if (request != null) {
        await _updateKeystoneQr(
          request,
          runGeneration: runGeneration,
          accountUuid: accountUuid,
        );
        return;
      }
      await _submitAfterKeystoneSignatures(
        sessionNotifier,
        runGeneration: runGeneration,
        accountUuid: accountUuid,
      );
    } catch (error) {
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      _setRunError(_messageFromError(error));
    }
  }

  Future<void> _skipRemainingKeystoneBundles() async {
    final runGeneration = _runGeneration;
    final accountUuid = _runAccountUuid;
    if (accountUuid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Use signed bundles only?'),
          content: const Text(
            'Vizor will submit with the Keystone bundle signatures already collected and skip the remaining unsigned bundles. This lowers voting power for this poll.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep Signing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use Signed Bundles'),
            ),
          ],
        );
      },
    );
    if (!_isCurrentRunForAccount(runGeneration, accountUuid) ||
        confirmed != true) {
      return;
    }

    try {
      setState(() {
        _keystoneUrParts = const [];
        _keystoneQrError = null;
      });
      final sessionNotifier = ref.read(
        votingSessionProvider(widget.roundId).notifier,
      );
      await sessionNotifier.skipRemainingKeystoneBundles();
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      final afterSkip = _sessionForRunAccount(accountUuid: accountUuid);
      if (afterSkip?.phase == VotingSessionPhase.error) {
        _releaseSubmissionGuard();
        return;
      }
      await _submitAfterKeystoneSignatures(
        sessionNotifier,
        runGeneration: runGeneration,
        accountUuid: accountUuid,
      );
    } catch (error) {
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      _setRunError(_messageFromError(error));
    }
  }

  Future<void> _submitAfterKeystoneSignatures(
    VotingSessionNotifier sessionNotifier, {
    required int runGeneration,
    required String accountUuid,
  }) async {
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    final draftVotes = _pendingDraftVotes;
    if (draftVotes == null ||
        (draftVotes.isEmpty && !_pendingRecoveryWithoutDraft)) {
      _setRunError('Choose at least one vote before submitting.');
      return;
    }
    setState(() {
      _keystoneUrParts = const [];
      _keystoneQrError = null;
    });
    final beforeDelegation = _sessionForRunAccount(accountUuid: accountUuid);
    if (_sessionNeedsDelegationSubmission(beforeDelegation)) {
      await sessionNotifier.delegatePendingBundlesWithKeystoneSignatures();
      if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
      final afterDelegation = _sessionForRunAccount(accountUuid: accountUuid);
      if (afterDelegation?.phase == VotingSessionPhase.error) {
        _releaseSubmissionGuard();
        return;
      }
      await _submitVotesAndShares(
        sessionNotifier,
        runGeneration: runGeneration,
        accountUuid: accountUuid,
        draftVotes: draftVotes,
        intentProposalIds: _pendingProposalIds,
        proposalOptionCounts: _pendingProposalOptionCounts,
        initialSession: afterDelegation ?? beforeDelegation,
      );
      return;
    }
    await _submitVotesAndShares(
      sessionNotifier,
      runGeneration: runGeneration,
      accountUuid: accountUuid,
      draftVotes: draftVotes,
      intentProposalIds: _pendingProposalIds,
      proposalOptionCounts: _pendingProposalOptionCounts,
      initialSession: beforeDelegation,
    );
  }

  Future<void> _submitVotesAndShares(
    VotingSessionNotifier sessionNotifier, {
    required int runGeneration,
    required String accountUuid,
    required List<rust_voting.ApiDraftVote> draftVotes,
    required List<int> intentProposalIds,
    required Map<int, int> proposalOptionCounts,
    VotingSessionState? initialSession,
  }) async {
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    final votePollingSession =
        _sessionForRunAccount(accountUuid: accountUuid) ?? initialSession;
    if (draftVotes.isEmpty &&
        (votePollingSession == null ||
            !_canRecoverWithoutDraft(votePollingSession))) {
      _setRunError('Choose at least one vote before submitting.');
      return;
    }
    if (draftVotes.isNotEmpty || _sessionNeedsVotePolling(votePollingSession)) {
      await sessionNotifier.castVotes(
        draftVotes: draftVotes,
        allProposalIds: intentProposalIds,
        proposalOptionCounts: proposalOptionCounts,
      );
    }
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    final afterVotes = _sessionForRunAccount(accountUuid: accountUuid);
    if (afterVotes?.phase == VotingSessionPhase.error) {
      _releaseSubmissionGuard();
      return;
    }
    await sessionNotifier.submitPendingShares();
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    final done = _sessionForRunAccount(accountUuid: accountUuid);
    if (done?.phase == VotingSessionPhase.error) {
      _releaseSubmissionGuard();
      return;
    }
    if (!_hasCompletedSubmission(done)) return;
    _navigateToConfirmation(
      runGeneration: runGeneration,
      accountUuid: accountUuid,
    );
  }

  void _navigateToConfirmation({
    required int runGeneration,
    required String accountUuid,
  }) {
    if (!_isCurrentRunForAccount(runGeneration, accountUuid)) return;
    _releaseSubmissionGuard();
    context.go(votingSubmissionConfirmedRoute(widget.roundId));
  }

  void _setRunError(String message) {
    if (!mounted) return;
    _releaseSubmissionGuard();
    setState(() {
      _runErrorMessage = message;
      _softwareAccountRequired = false;
      _keystoneUrParts = const [];
      _keystoneQrError = null;
    });
  }

  bool _isCurrentRun(int runGeneration) {
    return mounted && runGeneration == _runGeneration;
  }

  bool _isCurrentRunForStoredAccount(int runGeneration) {
    final accountUuid = _runAccountUuid;
    if (accountUuid == null) return _isCurrentRun(runGeneration);
    return _isCurrentRunForAccount(runGeneration, accountUuid);
  }

  bool _isCurrentRunForAccount(int runGeneration, String accountUuid) {
    if (!_isCurrentRun(runGeneration)) return false;
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    return activeAccountUuid == accountUuid;
  }

  VotingSessionState? _sessionForRunAccount({required String? accountUuid}) {
    final session = ref.read(votingSessionProvider(widget.roundId)).value;
    if (accountUuid != null && session?.accountUuid != accountUuid) {
      return null;
    }
    return session;
  }

  bool _hasCompletedSubmission(VotingSessionState? session) {
    if (session == null) return false;
    return hasCompletedVoteForDisplay(
      roundPlan: session.roundPlan,
      resumePlan: session.resumePlan,
    );
  }

  String _messageFromError(Object error) {
    return friendlyVotingErrorMessage(error);
  }

  bool _canRecoverWithoutDraft(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      return _roundPlanHasNoOpenProposals(session) &&
          roundPlan.nextSteps.any(_stepCanRecoverWithoutDraft);
    }
    final resumePlan = session.resumePlan;
    return resumePlan != null &&
        (resumePlan.pendingVoteSubmissionKeys.isNotEmpty ||
            resumePlan.submittedVoteConfirmationKeys.isNotEmpty ||
            resumePlan.unconfirmedShareDelegations.isNotEmpty);
  }

  bool _roundPlanHasNoOpenProposals(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    return roundPlan != null && roundPlan.openProposals.isEmpty;
  }

  bool _canPollDelegationWithoutDraft(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      var hasSubmittedDelegation = false;
      for (final step in roundPlan.nextSteps) {
        if (step.kind == 'delegate') return false;
        if (step.kind == 'poll_delegation') hasSubmittedDelegation = true;
      }
      return hasSubmittedDelegation;
    }
    final resumePlan = session.resumePlan;
    return resumePlan != null &&
        resumePlan.submittedDelegationBundleIndexes.isNotEmpty &&
        resumePlan.pendingDelegationBundleIndexes.isEmpty;
  }

  bool _stepCanRecoverWithoutDraft(rust_voting.ApiNextStep step) {
    return step.kind == 'submit_vote' ||
        step.kind == 'submit_shares' ||
        step.kind == 'poll_vote' ||
        step.kind == 'confirm_share';
  }

  bool _sessionNeedsDelegation(VotingSessionState? session) {
    if (session == null) return false;
    final roundPlan = session.roundPlan;
    if (_planNeedsDelegation(roundPlan)) return true;
    if (roundPlan != null && !roundPlanNeedsDraftSetup(roundPlan)) {
      return false;
    }
    return session.resumePlan?.submittedDelegationBundleIndexes.isNotEmpty ??
        false;
  }

  bool _sessionNeedsDelegationSubmission(VotingSessionState? session) {
    if (session == null) return false;
    final roundPlan = session.roundPlan;
    if (_planNeedsDelegation(roundPlan)) return true;
    if (roundPlan != null && !roundPlanNeedsDraftSetup(roundPlan)) {
      return false;
    }
    final plan = session.resumePlan;
    return (plan?.pendingDelegationBundleIndexes.isNotEmpty ?? false) ||
        (plan?.submittedDelegationBundleIndexes.isNotEmpty ?? false);
  }

  bool _sessionNeedsKeystoneSigning(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      return roundPlan.nextSteps.any((step) => step.kind == 'delegate') ||
          roundPlanNeedsDraftSetup(roundPlan);
    }
    return session.resumePlan?.pendingDelegationBundleIndexes.isNotEmpty ??
        false;
  }

  bool _sessionNeedsVotePolling(VotingSessionState? session) {
    if (session == null) return false;
    if (_planNeedsVotePolling(session.roundPlan)) return true;
    if (session.roundPlan != null) return false;
    return session.resumePlan?.submittedVoteConfirmationKeys.isNotEmpty ??
        false;
  }

  bool _planNeedsDelegation(rust_voting.ApiRoundPlan? roundPlan) {
    return roundPlan?.nextSteps.any(
          (step) => step.kind == 'delegate' || step.kind == 'poll_delegation',
        ) ??
        false;
  }

  bool _planNeedsVotePolling(rust_voting.ApiRoundPlan? roundPlan) {
    return roundPlan?.nextSteps.any(
          (step) =>
              step.kind == 'submit_vote' ||
              step.kind == 'submit_shares' ||
              step.kind == 'poll_vote',
        ) ??
        false;
  }

  List<rust_voting.ApiDraftVote> _draftVotesFromRoundPlan(
    rust_voting.ApiRoundPlan? roundPlan,
    List<VotingProposalView> proposals,
  ) {
    if (roundPlan == null) return const [];
    final choicesByProposal = <int, int>{};
    for (final step in roundPlan.nextSteps) {
      if (step.kind != 'cast_vote') continue;
      choicesByProposal.putIfAbsent(step.proposalId, () => step.choice);
    }
    if (choicesByProposal.isEmpty) return const [];
    return [
      for (final proposal in proposals)
        if (choicesByProposal[proposal.id] != null)
          rust_voting.ApiDraftVote(
            proposalId: proposal.id,
            choice: choicesByProposal[proposal.id]!,
            numOptions: proposal.options.length,
            vcTreePosition: BigInt.zero,
            singleShare: false,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == null || next == null || previous == next) return;
        _resetLocalRunStateForAccountSwitch();
      },
    );
    final activeAccountUuid = ref.watch(
      accountProvider.select((value) => value.value?.activeAccountUuid),
    );
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
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _StatusContent(
                phase: VotingSessionPhase.error,
                errorMessage: _runErrorMessage ?? _messageFromError(error),
                onRetry: _retry,
              ),
              data: (state) {
                final stateAccountUuid = state.accountUuid;
                if (activeAccountUuid != null &&
                    stateAccountUuid != null &&
                    stateAccountUuid != activeAccountUuid) {
                  return const Center(child: CircularProgressIndicator());
                }
                _scheduleRunIfIdle();
                final localError = _runErrorMessage;
                final completedSubmission = _hasCompletedSubmission(state);
                final phase = localError == null
                    ? _displayPhase(
                        state.phase,
                        completedSubmission: completedSubmission,
                      )
                    : VotingSessionPhase.error;
                return _StatusContent(
                  phase: phase,
                  voteSubmissionDetail: _voteSubmissionDetail(state),
                  voteSubmissionProgress: _voteSubmissionProgress(
                    state,
                    completedSubmission: completedSubmission,
                  ),
                  delegationProgress: _delegationProgress(state),
                  completedSubmission: completedSubmission,
                  softwareAccountRequired: _softwareAccountRequired,
                  isHardwareAccount: state.isHardwareAccount,
                  keystoneSigningRequest: state.keystoneSigningRequest,
                  canSkipRemainingKeystoneBundles:
                      state.canSkipRemainingKeystoneBundles,
                  keystoneUrParts: _keystoneUrParts,
                  keystoneQrError: _keystoneQrError,
                  keystoneScanError: state.keystoneScanError,
                  walletScannedHeight: state.walletScannedHeight,
                  walletSnapshotHeight: state.walletSnapshotHeight,
                  walletChainTipHeight: state.walletChainTipHeight,
                  errorMessage: _sessionErrorMessage(state, localError),
                  onRetry: _retry,
                  onScanKeystone: _scanKeystoneSignature,
                  onSkipKeystoneBundles: _skipRemainingKeystoneBundles,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  VotingSessionPhase _displayPhase(
    VotingSessionPhase phase, {
    required bool completedSubmission,
  }) {
    if (phase == VotingSessionPhase.done && !completedSubmission) {
      return VotingSessionPhase.idle;
    }
    return phase;
  }

  String? _sessionErrorMessage(VotingSessionState state, String? localError) {
    if (localError != null) return localError;
    return _statusErrorMessage(state, fallbackForErrorPhase: false);
  }

  String? _statusErrorMessage(
    VotingSessionState state, {
    bool fallbackForErrorPhase = true,
  }) {
    final error = state.error;
    if (error != null) return friendlyVotingErrorText(error.message);
    final round = state.round;
    if (round != null && state.pirDiagnostics.isNotEmpty) {
      return _pirDiagnosticsErrorMessage(
        expectedSnapshotHeight: round.snapshotHeight,
        diagnostics: state.pirDiagnostics,
      );
    }
    if (!fallbackForErrorPhase || state.phase != VotingSessionPhase.error) {
      return null;
    }
    return _genericVotingStatusErrorMessage;
  }

  static const _genericVotingStatusErrorMessage =
      'Voting could not continue for this account. Retry, or switch to an '
      'eligible account if this account cannot vote in this poll.';

  String _pirDiagnosticsErrorMessage({
    required int expectedSnapshotHeight,
    required List<PirSnapshotEndpointDiagnostic> diagnostics,
  }) {
    final expected = formatBlockHeight(expectedSnapshotHeight);
    final reportedHeights = diagnostics
        .map((diagnostic) => diagnostic.reportedHeight)
        .nonNulls
        .toSet();
    if (diagnostics.every(
          (diagnostic) => diagnostic.status == PirSnapshotEndpointStatus.behind,
        ) &&
        reportedHeights.isNotEmpty) {
      final highest = formatBlockHeight(
        reportedHeights.reduce((left, right) => left > right ? left : right),
      );
      return 'Voting PIR data is not ready for this poll yet. Expected '
          'snapshot block $expected; PIR endpoints report $highest.';
    }
    return 'No PIR endpoint matched this poll snapshot. Expected snapshot '
        'block $expected.';
  }

  String? _shareSubmissionDetail(VotingSessionState state) {
    final key = state.currentVoteKey;
    if (key != null) {
      final message = state.voteProgress[key]?.message;
      if (message != null && message.isNotEmpty) return message;
    }
    final messages = state.voteProgress.values
        .where(
          (progress) =>
              progress.phase == 'submitting_shares' &&
              progress.message != null &&
              progress.message!.isNotEmpty,
        )
        .map((progress) => progress.message!)
        .toList(growable: false);
    return messages.isEmpty ? null : messages.last;
  }

  String? _voteSubmissionDetail(VotingSessionState state) {
    final total = state.voteSubmissionTotalCount;
    if (total > 0) {
      final completed = state.voteSubmissionCompletedCount.clamp(0, total);
      final current = completed >= total ? total : completed + 1;
      return 'Question $current/$total';
    }
    return _shareSubmissionDetail(state);
  }

  double? _voteSubmissionProgress(
    VotingSessionState state, {
    required bool completedSubmission,
  }) {
    if (completedSubmission) return 1;
    final progress = state.voteSubmissionProgress;
    if (progress == null) return null;
    return progress.clamp(0.0, 1.0).toDouble();
  }

  double? _delegationProgress(VotingSessionState state) {
    if (state.phase != VotingSessionPhase.delegating) return null;
    final bundleIndexes = _delegationProgressBundleIndexes(state);
    if (bundleIndexes.isEmpty) return null;

    var completedProgress = 0.0;
    for (final bundleIndex in bundleIndexes) {
      final progress = state.delegationProgress[bundleIndex];
      if (_isDelegationBundleComplete(progress)) {
        completedProgress += 1;
      } else {
        completedProgress +=
            progress?.proofProgress?.clamp(0.0, 1.0).toDouble() ?? 0;
      }
    }
    return (completedProgress / bundleIndexes.length).clamp(0.0, 1.0);
  }

  List<int> _delegationProgressBundleIndexes(VotingSessionState state) {
    final indexes = <int>{
      ...?state.resumePlan?.pendingDelegationBundleIndexes,
      ...state.delegationProgress.keys,
      ?state.currentBundleIndex,
    }.toList()..sort();
    return indexes;
  }

  bool _isDelegationBundleComplete(VotingSessionProgress? progress) {
    return progress?.phase == 'submitted' || progress?.phase == 'confirmed';
  }

  void _retry() {
    _releaseSubmissionGuard();
    _started = false;
    _softwareAccountRequired = false;
    _runErrorMessage = null;
    _keystoneUrParts = const [];
    _keystoneQrError = null;
    _pendingDraftVotes = null;
    _pendingProposalIds = const [];
    _pendingProposalOptionCounts = const {};
    _pendingRecoveryWithoutDraft = false;
    unawaited(_run());
  }

  void _resetLocalRunStateForAccountSwitch() {
    _runGeneration++;
    _releaseSubmissionGuard();
    _started = false;
    _runAccountUuid = null;
    _softwareAccountRequired = false;
    _runErrorMessage = null;
    _keystoneUrParts = const [];
    _keystoneQrError = null;
    _pendingDraftVotes = null;
    _pendingProposalIds = const [];
    _pendingRecoveryWithoutDraft = false;
  }

  void _scheduleRunIfIdle() {
    if (_started) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      unawaited(_run());
    });
  }

  void _ensureSubmissionGuard(String accountUuid) {
    final existing = _submissionGuard;
    if (existing != null &&
        existing.accountUuid == accountUuid &&
        existing.roundId == widget.roundId) {
      return;
    }
    _releaseSubmissionGuard();
    _submissionGuard = _submissionGuardNotifier.acquire(
      accountUuid: accountUuid,
      roundId: widget.roundId,
    );
  }

  void _releaseSubmissionGuard() {
    final guard = _submissionGuard;
    if (guard == null) return;
    _submissionGuard = null;
    _submissionGuardNotifier.release(guard);
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.phase,
    this.voteSubmissionDetail,
    this.voteSubmissionProgress,
    this.delegationProgress,
    this.completedSubmission = false,
    this.softwareAccountRequired = false,
    this.isHardwareAccount = false,
    this.keystoneSigningRequest,
    this.canSkipRemainingKeystoneBundles = false,
    this.keystoneUrParts = const [],
    this.keystoneQrError,
    this.keystoneScanError,
    this.walletScannedHeight,
    this.walletSnapshotHeight,
    this.walletChainTipHeight,
    this.errorMessage,
    this.onRetry,
    this.onScanKeystone,
    this.onSkipKeystoneBundles,
  });

  final VotingSessionPhase phase;
  final String? voteSubmissionDetail;
  final double? voteSubmissionProgress;
  final double? delegationProgress;
  final bool completedSubmission;
  final bool softwareAccountRequired;
  final bool isHardwareAccount;
  final rust_voting.ApiKeystoneDelegationRequest? keystoneSigningRequest;
  final bool canSkipRemainingKeystoneBundles;
  final List<String> keystoneUrParts;
  final String? keystoneQrError;
  final String? keystoneScanError;
  final int? walletScannedHeight;
  final int? walletSnapshotHeight;
  final int? walletChainTipHeight;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onScanKeystone;
  final VoidCallback? onSkipKeystoneBundles;

  @override
  Widget build(BuildContext context) {
    if (softwareAccountRequired) {
      return const _SoftwareAccountRequiredContent();
    }
    final voteStepComplete =
        completedSubmission || (voteSubmissionProgress ?? 0) >= 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return Scrollbar(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Submitting Votes',
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
                        if (phase ==
                            VotingSessionPhase.waitingForWalletSync) ...[
                          _WalletSyncProgressText(
                            scannedHeight: walletScannedHeight,
                            snapshotHeight: walletSnapshotHeight,
                            chainTipHeight: walletChainTipHeight,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        if (isHardwareAccount &&
                            phase == VotingSessionPhase.keystoneSigning &&
                            keystoneSigningRequest != null) ...[
                          _KeystoneSigningPanel(
                            request: keystoneSigningRequest!,
                            urParts: keystoneUrParts,
                            qrError: keystoneQrError,
                            scanError: keystoneScanError,
                            canSkipRemainingBundles:
                                canSkipRemainingKeystoneBundles,
                            onScan: onScanKeystone,
                            onSkipRemainingBundles: onSkipKeystoneBundles,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (isHardwareAccount)
                          _StepRow(
                            label: 'Signing with Keystone',
                            active: phase == VotingSessionPhase.keystoneSigning,
                            complete: _after(
                              VotingSessionPhase.keystoneSigning,
                            ),
                          ),
                        _StepRow(
                          label: 'Delegating voting authority',
                          active: phase == VotingSessionPhase.delegating,
                          complete: _after(VotingSessionPhase.delegating),
                          progressValue: delegationProgress,
                        ),
                        _StepRow(
                          label: 'Casting votes and submitting shares',
                          active:
                              !voteStepComplete &&
                              (phase == VotingSessionPhase.syncingVoteTree ||
                                  phase == VotingSessionPhase.castingVotes ||
                                  phase == VotingSessionPhase.submittingShares),
                          complete: voteStepComplete,
                          detail: voteStepComplete
                              ? null
                              : voteSubmissionDetail,
                          progressValue: voteStepComplete
                              ? null
                              : voteSubmissionProgress,
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
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _after(VotingSessionPhase target) {
    return phase.index > target.index && phase != VotingSessionPhase.error;
  }
}

class _WalletSyncProgressText extends StatelessWidget {
  const _WalletSyncProgressText({
    required this.scannedHeight,
    required this.snapshotHeight,
    required this.chainTipHeight,
  });

  final int? scannedHeight;
  final int? snapshotHeight;
  final int? chainTipHeight;

  @override
  Widget build(BuildContext context) {
    final scanned = scannedHeight;
    final snapshot = snapshotHeight;
    final chainTip = chainTipHeight;
    final rawRemaining = scanned == null || snapshot == null
        ? null
        : snapshot - scanned;
    final remaining = rawRemaining == null
        ? null
        : rawRemaining > 0
        ? rawRemaining
        : 0;
    final detail = [
      if (scanned != null) 'Synced to block $scanned',
      if (snapshot != null) 'snapshot block $snapshot',
      if (chainTip != null) 'chain tip $chainTip',
    ].join(' / ');
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Text(
              'Waiting for wallet sync',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Your wallet is catching up to this poll snapshot. Voting will continue automatically once the wallet has synced through the snapshot block.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            if (remaining != null && remaining > 0) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '$remaining blocks remaining',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeystoneSigningPanel extends StatelessWidget {
  const _KeystoneSigningPanel({
    required this.request,
    required this.urParts,
    this.qrError,
    this.scanError,
    this.canSkipRemainingBundles = false,
    this.onScan,
    this.onSkipRemainingBundles,
  });

  final rust_voting.ApiKeystoneDelegationRequest request;
  final List<String> urParts;
  final String? qrError;
  final String? scanError;
  final bool canSkipRemainingBundles;
  final VoidCallback? onScan;
  final VoidCallback? onSkipRemainingBundles;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final qrPhase = qrError != null
        ? KeystonePcztQrStagePhase.failed
        : urParts.isEmpty
        ? KeystonePcztQrStagePhase.preparing
        : KeystonePcztQrStagePhase.ready;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 64),
                Expanded(
                  child: Text(
                    'Sign Bundle ${request.bundleIndex + 1} of ${request.bundleCount}',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: canSkipRemainingBundles
                        ? AppButton(
                            onPressed: onSkipRemainingBundles,
                            variant: AppButtonVariant.primary,
                            size: AppButtonSize.small,
                            child: const Text('Skip'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Scan this QR with Keystone, then scan the signed voting QR here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            if (request.displayMemo.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _KeystoneSigningMemo(displayMemo: request.displayMemo),
            ],
            const SizedBox(height: AppSpacing.sm),
            KeystonePcztQrStage(
              phase: qrPhase,
              urParts: urParts,
              error: qrError,
            ),
            if (scanError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                scanError!,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              onPressed: urParts.isEmpty ? null : onScan,
              variant: AppButtonVariant.primary,
              minWidth: 220,
              child: const Text('Scan Signature'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeystoneSigningMemo extends StatelessWidget {
  const _KeystoneSigningMemo({required this.displayMemo});

  final String displayMemo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.input,
          border: Border.all(color: colors.border.subtle),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Memo',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              SelectableText(
                displayMemo,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
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
    this.detail,
    this.progressValue,
  });

  final String label;
  final bool active;
  final bool complete;
  final String? detail;
  final double? progressValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = progressValue?.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: active
                ? _ProgressBubble(progress: progress)
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: active || complete
                        ? colors.text.accent
                        : colors.text.secondary,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBubble extends StatelessWidget {
  const _ProgressBubble({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = progress;
    final backgroundColor = colors.text.secondary.withValues(alpha: 0.35);
    const size = 20.0;
    if (value == null) {
      return Center(
        child: SizedBox.square(
          dimension: size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            backgroundColor: backgroundColor,
          ),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return Center(
          child: SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: animatedValue,
              backgroundColor: backgroundColor,
            ),
          ),
        );
      },
    );
  }
}
