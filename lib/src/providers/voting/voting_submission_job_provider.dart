import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_error_messages.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/keystone.dart' as rust_keystone;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../account_provider.dart';
import 'voting_session_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';
import 'voting_submission_guard_provider.dart';

enum VotingSubmissionJobStatus {
  idle,
  running,
  waitingForKeystone,
  complete,
  error,
}

@immutable
class VotingSubmissionJobState {
  const VotingSubmissionJobState({
    this.key,
    this.status = VotingSubmissionJobStatus.idle,
    this.generation = 0,
    this.errorMessage,
    this.softwareAccountRequired = false,
    this.keystoneUrParts = const [],
    this.keystoneQrError,
    this.pendingDraftVotes,
    this.pendingProposalIds = const [],
    this.pendingProposalOptionCounts = const {},
    this.pendingRecoveryWithoutDraft = false,
  });

  final VotingSessionKey? key;
  final VotingSubmissionJobStatus status;
  final int generation;
  final String? errorMessage;
  final bool softwareAccountRequired;
  final List<String> keystoneUrParts;
  final String? keystoneQrError;
  final List<rust_wire.DraftVote>? pendingDraftVotes;
  final List<int> pendingProposalIds;
  final Map<int, int> pendingProposalOptionCounts;
  final bool pendingRecoveryWithoutDraft;

  bool get hasVisibleJob =>
      key != null && status != VotingSubmissionJobStatus.idle;

  bool get isInFlight =>
      status == VotingSubmissionJobStatus.running ||
      status == VotingSubmissionJobStatus.waitingForKeystone;

  VotingSubmissionJobState copyWith({
    VotingSessionKey? key,
    VotingSubmissionJobStatus? status,
    int? generation,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? softwareAccountRequired,
    List<String>? keystoneUrParts,
    String? keystoneQrError,
    bool clearKeystoneQrError = false,
    List<rust_wire.DraftVote>? pendingDraftVotes,
    bool clearPendingDraftVotes = false,
    List<int>? pendingProposalIds,
    Map<int, int>? pendingProposalOptionCounts,
    bool? pendingRecoveryWithoutDraft,
  }) {
    return VotingSubmissionJobState(
      key: key ?? this.key,
      status: status ?? this.status,
      generation: generation ?? this.generation,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      softwareAccountRequired:
          softwareAccountRequired ?? this.softwareAccountRequired,
      keystoneUrParts: keystoneUrParts ?? this.keystoneUrParts,
      keystoneQrError: clearKeystoneQrError
          ? null
          : keystoneQrError ?? this.keystoneQrError,
      pendingDraftVotes: clearPendingDraftVotes
          ? null
          : pendingDraftVotes ?? this.pendingDraftVotes,
      pendingProposalIds: pendingProposalIds ?? this.pendingProposalIds,
      pendingProposalOptionCounts:
          pendingProposalOptionCounts ?? this.pendingProposalOptionCounts,
      pendingRecoveryWithoutDraft:
          pendingRecoveryWithoutDraft ?? this.pendingRecoveryWithoutDraft,
    );
  }
}

@immutable
class VotingSubmissionJobsState {
  const VotingSubmissionJobsState({
    this.jobKeys = const [],
    this.startErrorsByRoundId = const {},
  });

  final List<VotingSessionKey> jobKeys;
  final Map<String, String> startErrorsByRoundId;

  bool get hasJobs => jobKeys.isNotEmpty;

  String? startErrorForRound(String roundId) => startErrorsByRoundId[roundId];

  VotingSubmissionJobsState copyWith({
    List<VotingSessionKey>? jobKeys,
    Map<String, String>? startErrorsByRoundId,
  }) {
    return VotingSubmissionJobsState(
      jobKeys: jobKeys ?? this.jobKeys,
      startErrorsByRoundId: startErrorsByRoundId ?? this.startErrorsByRoundId,
    );
  }

  VotingSubmissionJobsState addJobKey(VotingSessionKey key) {
    if (jobKeys.contains(key)) {
      return clearStartError(key.roundId);
    }
    return copyWith(
      jobKeys: [...jobKeys, key],
      startErrorsByRoundId: _withoutStartError(key.roundId),
    );
  }

  VotingSubmissionJobsState setStartError(String roundId, String message) {
    return copyWith(
      startErrorsByRoundId: {...startErrorsByRoundId, roundId: message},
    );
  }

  VotingSubmissionJobsState clearStartError(String roundId) {
    if (!startErrorsByRoundId.containsKey(roundId)) return this;
    return copyWith(startErrorsByRoundId: _withoutStartError(roundId));
  }

  VotingSubmissionJobsState removeJobKey(VotingSessionKey key) {
    if (!jobKeys.contains(key)) return this;
    return copyWith(
      jobKeys: [
        for (final jobKey in jobKeys)
          if (jobKey != key) jobKey,
      ],
    );
  }

  Map<String, String> _withoutStartError(String roundId) {
    return {
      for (final entry in startErrorsByRoundId.entries)
        if (entry.key != roundId) entry.key: entry.value,
    };
  }
}

class VotingSubmissionJobsNotifier extends Notifier<VotingSubmissionJobsState> {
  @override
  VotingSubmissionJobsState build() => const VotingSubmissionJobsState();

  Future<VotingSessionKey?> start(String roundId, {String? accountUuid}) async {
    final String? resolvedAccountUuid;
    try {
      resolvedAccountUuid = accountUuid ?? await _activeAccountUuid();
    } catch (error) {
      state = state.setStartError(roundId, friendlyVotingErrorMessage(error));
      return null;
    }
    if (resolvedAccountUuid == null) {
      state = state.setStartError(
        roundId,
        'No active account for voting session.',
      );
      return null;
    }

    final key = VotingSessionKey(
      roundId: roundId,
      accountUuid: resolvedAccountUuid,
    );
    state = state.addJobKey(key);
    await ref.read(votingSubmissionJobProvider(key).notifier).start();
    return key;
  }

  Future<void> retry(VotingSessionKey key) async {
    state = state.addJobKey(key);
    await ref.read(votingSubmissionJobProvider(key).notifier).retry();
  }

  void dismiss(VotingSessionKey key) {
    ref.read(votingSubmissionJobProvider(key).notifier).dismiss();
    state = state.removeJobKey(key);
  }

  Future<void> handleKeystoneSignedPczt(
    VotingSessionKey key,
    List<int> signedPczt,
  ) {
    return ref
        .read(votingSubmissionJobProvider(key).notifier)
        .handleKeystoneSignedPczt(signedPczt);
  }

  Future<void> skipRemainingKeystoneBundles(VotingSessionKey key) {
    return ref
        .read(votingSubmissionJobProvider(key).notifier)
        .skipRemainingKeystoneBundles();
  }

  Future<String?> _activeAccountUuid() async {
    final votingAccountUuid = await ref
        .read(votingActiveAccountUuidProvider)
        .call();
    if (votingAccountUuid != null) return votingAccountUuid;
    final immediate = ref.read(accountProvider).value?.activeAccountUuid;
    if (immediate != null) return immediate;
    return (await ref.read(accountProvider.future)).activeAccountUuid;
  }
}

class VotingSubmissionJobNotifier extends Notifier<VotingSubmissionJobState> {
  VotingSubmissionJobNotifier(this._key);

  final VotingSessionKey _key;
  VotingSubmissionGuard? _guard;
  ProviderSubscription<AsyncValue<VotingSessionState>>? _sessionSubscription;
  VotingSessionKey? _retainedSessionKey;
  Timer? _completionPollTimer;
  int _nextGeneration = 0;

  @override
  VotingSubmissionJobState build() {
    ref.onDispose(() {
      _completionPollTimer?.cancel();
      _completionPollTimer = null;
      _releaseSessionSubscription();
    });
    return VotingSubmissionJobState(key: _key);
  }

  Future<void> start() async {
    final current = state;
    if (current.hasVisibleJob) return;
    _startJob(_key);
  }

  Future<void> retry() async {
    _releaseGuard();
    state = VotingSubmissionJobState(key: _key);
    _startJob(_key);
  }

  void dismiss() {
    if (state.isInFlight) return;
    _cancelCompletionPoll();
    _releaseGuard();
    _releaseSessionSubscription();
    state = VotingSubmissionJobState(key: _key, generation: ++_nextGeneration);
  }

  void _startJob(VotingSessionKey key) {
    _cancelCompletionPoll();
    _replaceGuard(accountUuid: key.accountUuid, roundId: key.roundId);
    _retainSession(key);
    final generation = ++_nextGeneration;
    state = VotingSubmissionJobState(
      key: key,
      status: VotingSubmissionJobStatus.running,
      generation: generation,
    );
    unawaited(_run(key: key, generation: generation));
  }

  Future<void> handleKeystoneSignedPczt(List<int> signedPczt) async {
    final job = state;
    final key = job.key;
    if (key == null || !job.isInFlight || signedPczt.isEmpty) return;
    final generation = job.generation;
    try {
      final sessionNotifier = ref.read(
        votingSubmissionSessionProvider(key).notifier,
      );
      await sessionNotifier.handleKeystoneSignedPczt(signedPczt);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final session = _sessionForJob(key);
      if (session == null) return;
      if (session.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session);
        return;
      }
      final request = session.keystoneSigningRequest;
      if (request != null) {
        await _updateKeystoneQr(
          key: key,
          generation: generation,
          request: request,
        );
        return;
      }
      await _submitAfterKeystoneSignatures(
        sessionNotifier,
        key: key,
        generation: generation,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> skipRemainingKeystoneBundles() async {
    final job = state;
    final key = job.key;
    if (key == null || !job.isInFlight) return;
    final generation = job.generation;
    try {
      _setRunning(key: key, generation: generation);
      final sessionNotifier = ref.read(
        votingSubmissionSessionProvider(key).notifier,
      );
      await sessionNotifier.skipRemainingKeystoneBundles();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final session = _sessionForJob(key);
      if (session?.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session!);
        return;
      }
      await _submitAfterKeystoneSignatures(
        sessionNotifier,
        key: key,
        generation: generation,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> _run({
    required VotingSessionKey key,
    required int generation,
  }) async {
    try {
      final sessionProvider = votingSubmissionSessionProvider(key);
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final loadedSession = await ref.read(sessionProvider.future);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final round = loadedSession.round;
      if (round == null) {
        _failJob(
          key: key,
          generation: generation,
          message:
              'Voting round details are not available yet. Retry in a moment.',
        );
        return;
      }

      final proposals = proposalsFromRound(round);
      final proposalOptionCounts = {
        for (final proposal in proposals) proposal.id: proposal.options.length,
      };
      final draft = await ref
          .read(votingDraftProvider(key).notifier)
          .ensureLoaded();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final userDraftVotes = draft.toDraftVotes(proposals);
      final proposalIds = proposals.map((proposal) => proposal.id).toList();

      await sessionNotifier.ensureWalletReadyForVoting();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterWalletSync = _sessionForJob(key);
      if (afterWalletSync?.phase == VotingSessionPhase.error ||
          afterWalletSync?.phase == VotingSessionPhase.waitingForWalletSync) {
        if (afterWalletSync?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterWalletSync!,
          );
        }
        return;
      }

      final activeSession = afterWalletSync ?? loadedSession;
      final recoveredDraftVotes =
          userDraftVotes.isEmpty && _roundPlanHasNoOpenProposals(activeSession)
          ? _draftVotesFromRoundPlan(activeSession.roundPlan, proposals)
          : const <rust_wire.DraftVote>[];
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
      final needsDelegationSubmission = _sessionNeedsDelegationSubmission(
        activeSession,
      );
      if (draftVotes.isEmpty &&
          !canRecoverWithoutDraft &&
          !canPollDelegationWithoutDraft) {
        _failJob(
          key: key,
          generation: generation,
          message: 'Choose at least one vote before submitting.',
        );
        return;
      }

      if (activeSession.isHardwareAccount &&
          _sessionNeedsKeystoneSigning(activeSession)) {
        _storePendingKeystoneState(
          key: key,
          generation: generation,
          draftVotes: draftVotes,
          intentProposalIds: intentProposalIds,
          proposalOptionCounts: proposalOptionCounts,
          pendingRecoveryWithoutDraft:
              canRecoverWithoutDraft || canPollDelegationWithoutDraft,
        );
        await _prepareKeystoneSigning(
          sessionNotifier,
          key: key,
          generation: generation,
        );
        return;
      }

      if (activeSession.isHardwareAccount &&
          (draftVotes.isNotEmpty || needsDelegation)) {
        if (needsDelegation) {
          _storePendingKeystoneState(
            key: key,
            generation: generation,
            draftVotes: draftVotes,
            intentProposalIds: intentProposalIds,
            proposalOptionCounts: proposalOptionCounts,
            pendingRecoveryWithoutDraft:
                canRecoverWithoutDraft || canPollDelegationWithoutDraft,
          );
          await _submitAfterKeystoneSignatures(
            sessionNotifier,
            key: key,
            generation: generation,
          );
        } else {
          await _submitVotesAndShares(
            sessionNotifier,
            key: key,
            generation: generation,
            draftVotes: draftVotes,
            intentProposalIds: intentProposalIds,
            proposalOptionCounts: proposalOptionCounts,
            initialSession: activeSession,
          );
        }
        return;
      }
      String? softwareMnemonic;
      if (!activeSession.isHardwareAccount && needsDelegationSubmission) {
        softwareMnemonic = await ref
            .read(accountProvider.notifier)
            .getMnemonicForAccount(key.accountUuid);
        if (!_isCurrentJob(key: key, generation: generation)) return;
        if (softwareMnemonic == null || softwareMnemonic.isEmpty) {
          _failJob(
            key: key,
            generation: generation,
            message:
                'Coinholder voting requires a software account. Switch to a software account to vote in this round.',
            softwareAccountRequired: true,
          );
          return;
        }
      }
      if (needsDelegation) {
        if (!_isCurrentJob(key: key, generation: generation)) return;
        await sessionNotifier.delegatePendingBundles(
          mnemonic: softwareMnemonic,
        );
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterDelegation = _sessionForJob(key);
        if (afterDelegation?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterDelegation!,
          );
          return;
        }
        if (_completeJobIfSubmissionDone(
          key: key,
          generation: generation,
          session: afterDelegation,
          requireNoUnconfirmedShares: true,
        )) {
          return;
        }
      }
      final afterDelegation = _sessionForJob(key);
      await _submitVotesAndShares(
        sessionNotifier,
        key: key,
        generation: generation,
        draftVotes: draftVotes,
        intentProposalIds: intentProposalIds,
        proposalOptionCounts: proposalOptionCounts,
        initialSession: afterDelegation ?? activeSession,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> _prepareKeystoneSigning(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
  }) async {
    await sessionNotifier.prepareKeystoneSigning();
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final session = _sessionForJob(key);
    if (session == null) return;
    if (session.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: session);
      return;
    }
    final request = session.keystoneSigningRequest;
    if (request != null) {
      await _updateKeystoneQr(
        key: key,
        generation: generation,
        request: request,
      );
      return;
    }
    await _submitAfterKeystoneSignatures(
      sessionNotifier,
      key: key,
      generation: generation,
    );
  }

  Future<void> _updateKeystoneQr({
    required VotingSessionKey key,
    required int generation,
    required rust_delegate.KeystoneSigningRequest request,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.waitingForKeystone,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
    );
    try {
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: request.redactedPcztBytes,
        maxFragmentLen: BigInt.from(200),
      );
      if (!_isCurrentJob(key: key, generation: generation)) return;
      state = state.copyWith(
        status: VotingSubmissionJobStatus.waitingForKeystone,
        keystoneUrParts: urParts,
        clearKeystoneQrError: true,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message:
            'Failed to prepare Keystone voting QR: ${_messageFromError(error)}',
      );
    }
  }

  Future<void> _submitAfterKeystoneSignatures(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final draftVotes = state.pendingDraftVotes;
    if (draftVotes == null ||
        (draftVotes.isEmpty && !state.pendingRecoveryWithoutDraft)) {
      _failJob(
        key: key,
        generation: generation,
        message: 'Choose at least one vote before submitting.',
      );
      return;
    }
    _setRunning(key: key, generation: generation);
    final beforeDelegation = _sessionForJob(key);
    if (_sessionNeedsDelegationSubmission(beforeDelegation)) {
      await sessionNotifier.delegatePendingBundlesWithKeystoneSignatures();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterDelegation = _sessionForJob(key);
      if (afterDelegation?.phase == VotingSessionPhase.error) {
        _failFromSession(
          key: key,
          generation: generation,
          session: afterDelegation!,
        );
        return;
      }
      if (_completeJobIfSubmissionDone(
        key: key,
        generation: generation,
        session: afterDelegation,
        requireNoUnconfirmedShares: true,
      )) {
        return;
      }
      await _submitVotesAndShares(
        sessionNotifier,
        key: key,
        generation: generation,
        draftVotes: draftVotes,
        intentProposalIds: state.pendingProposalIds,
        proposalOptionCounts: state.pendingProposalOptionCounts,
        initialSession: afterDelegation ?? beforeDelegation,
      );
      return;
    }
    await _submitVotesAndShares(
      sessionNotifier,
      key: key,
      generation: generation,
      draftVotes: draftVotes,
      intentProposalIds: state.pendingProposalIds,
      proposalOptionCounts: state.pendingProposalOptionCounts,
      initialSession: beforeDelegation,
    );
  }

  Future<void> _submitVotesAndShares(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
    required List<rust_wire.DraftVote> draftVotes,
    required List<int> intentProposalIds,
    required Map<int, int> proposalOptionCounts,
    VotingSessionState? initialSession,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final votePollingSession = _sessionForJob(key) ?? initialSession;
    if (draftVotes.isEmpty &&
        (votePollingSession == null ||
            !_canRecoverWithoutDraft(votePollingSession))) {
      _failJob(
        key: key,
        generation: generation,
        message: 'Choose at least one vote before submitting.',
      );
      return;
    }
    if (draftVotes.isNotEmpty || _sessionNeedsVotePolling(votePollingSession)) {
      await sessionNotifier.castVotes(
        draftVotes: draftVotes,
        allProposalIds: intentProposalIds,
        proposalOptionCounts: proposalOptionCounts,
      );
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final afterVotes = _sessionForJob(key);
    if (afterVotes?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: afterVotes!);
      return;
    }
    await sessionNotifier.submitPendingShares();
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final done = _sessionForJob(key);
    if (done?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: done!);
      return;
    }
    if (!_canCompleteSubmission(done)) {
      _scheduleCompletionPoll(key: key, generation: generation);
      return;
    }
    _completeJob(key: key, generation: generation);
  }

  void _storePendingKeystoneState({
    required VotingSessionKey key,
    required int generation,
    required List<rust_wire.DraftVote> draftVotes,
    required List<int> intentProposalIds,
    required Map<int, int> proposalOptionCounts,
    required bool pendingRecoveryWithoutDraft,
  }) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    state = state.copyWith(
      pendingDraftVotes: draftVotes,
      pendingProposalIds: intentProposalIds,
      pendingProposalOptionCounts: proposalOptionCounts,
      pendingRecoveryWithoutDraft: pendingRecoveryWithoutDraft,
    );
  }

  void _setRunning({required VotingSessionKey key, required int generation}) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.running,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
      clearErrorMessage: true,
    );
  }

  void _completeJob({required VotingSessionKey key, required int generation}) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    _releaseGuard();
    _releaseSessionSubscription();
    state = state.copyWith(
      status: VotingSubmissionJobStatus.complete,
      clearErrorMessage: true,
      softwareAccountRequired: false,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
      clearPendingDraftVotes: true,
      pendingProposalIds: const [],
      pendingProposalOptionCounts: const {},
      pendingRecoveryWithoutDraft: false,
    );
  }

  void _failFromSession({
    required VotingSessionKey key,
    required int generation,
    required VotingSessionState session,
  }) {
    _failJob(
      key: key,
      generation: generation,
      message: _statusErrorMessage(session) ?? _genericVotingStatusErrorMessage,
    );
  }

  void _failJob({
    required VotingSessionKey key,
    required int generation,
    required String message,
    bool softwareAccountRequired = false,
  }) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    _releaseGuard();
    _releaseSessionSubscription();
    state = state.copyWith(
      status: VotingSubmissionJobStatus.error,
      errorMessage: message,
      softwareAccountRequired: softwareAccountRequired,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
      clearPendingDraftVotes: true,
      pendingProposalIds: const [],
      pendingProposalOptionCounts: const {},
      pendingRecoveryWithoutDraft: false,
    );
  }

  VotingSessionState? _sessionForJob(VotingSessionKey key) {
    final session = ref.read(votingSubmissionSessionProvider(key)).value;
    if (session?.accountUuid != key.accountUuid) return null;
    return session;
  }

  bool _isCurrentJob({required VotingSessionKey key, required int generation}) {
    if (!ref.mounted) return false;
    final current = state;
    return current.generation == generation && current.key == key;
  }

  void _replaceGuard({required String accountUuid, required String roundId}) {
    _releaseGuard();
    _guard = ref
        .read(votingSubmissionGuardProvider.notifier)
        .acquire(accountUuid: accountUuid, roundId: roundId);
  }

  void _retainSession(VotingSessionKey key) {
    if (_retainedSessionKey == key && _sessionSubscription != null) return;
    _releaseSessionSubscription();
    _retainedSessionKey = key;
    // Keep the session provider alive while the background job owns submission.
    _sessionSubscription = ref.listen<AsyncValue<VotingSessionState>>(
      votingSubmissionSessionProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
  }

  void _releaseSessionSubscription() {
    _sessionSubscription?.close();
    _sessionSubscription = null;
    _retainedSessionKey = null;
  }

  void _releaseGuard() {
    final guard = _guard;
    if (guard == null) return;
    _guard = null;
    ref.read(votingSubmissionGuardProvider.notifier).release(guard);
  }

  void _scheduleCompletionPoll({
    required VotingSessionKey key,
    required int generation,
  }) {
    _completionPollTimer?.cancel();
    _completionPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isCurrentJob(key: key, generation: generation) ||
          !state.isInFlight) {
        timer.cancel();
        if (identical(_completionPollTimer, timer)) _completionPollTimer = null;
        return;
      }
      final session = _sessionForJob(key);
      if (session?.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session!);
        return;
      }
      if (_canCompleteSubmission(session)) {
        _completeJob(key: key, generation: generation);
      }
    });
  }

  void _cancelCompletionPoll() {
    _completionPollTimer?.cancel();
    _completionPollTimer = null;
  }

  bool _canCompleteSubmission(VotingSessionState? session) {
    if (session == null) return false;
    return hasCompletedVoteForDisplay(session.roundPlan) &&
        !_hasRemainingVoteOrShareWork(session);
  }

  bool _completeJobIfSubmissionDone({
    required VotingSessionKey key,
    required int generation,
    required VotingSessionState? session,
    bool requireNoUnconfirmedShares = false,
  }) {
    if (requireNoUnconfirmedShares &&
        (session?.resumePlan?.unconfirmedShareDelegations.isNotEmpty ??
            false)) {
      return false;
    }
    if (!_canCompleteSubmission(session)) return false;
    _completeJob(key: key, generation: generation);
    return true;
  }

  String _messageFromError(Object error) => friendlyVotingErrorMessage(error);

  String? _statusErrorMessage(VotingSessionState state) {
    final error = state.error;
    if (error != null) return friendlyVotingErrorText(error.message);
    if (state.phase != VotingSessionPhase.error) return null;
    return _genericVotingStatusErrorMessage;
  }

  static const _genericVotingStatusErrorMessage =
      'Voting could not continue for this account. Retry, or switch to an '
      'eligible account if this account cannot vote in this poll.';

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

  bool _hasRemainingVoteOrShareWork(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      for (final step in roundPlan.nextSteps) {
        if (step.kind == 'confirm_share') {
          if (session.resumePlan?.hasBlockingShareWork ?? true) return true;
          continue;
        }
        if (_stepCanRecoverWithoutDraft(step)) return true;
      }
    }
    final resumePlan = session.resumePlan;
    return resumePlan != null &&
        (resumePlan.pendingVoteSubmissionKeys.isNotEmpty ||
            resumePlan.submittedVoteConfirmationKeys.isNotEmpty ||
            resumePlan.hasBlockingShareWork);
  }

  bool _canPollDelegationWithoutDraft(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      var hasSubmittedDelegation = false;
      for (final step in roundPlan.nextSteps) {
        if (step.kind == 'delegate') return false;
        if (step.kind == 'poll_delegation') hasSubmittedDelegation = true;
      }
      if (hasSubmittedDelegation) return true;
    }
    final resumePlan = session.resumePlan;
    return resumePlan != null &&
        resumePlan.submittedDelegationBundleIndexes.isNotEmpty &&
        resumePlan.pendingDelegationBundleIndexes.isEmpty;
  }

  bool _stepCanRecoverWithoutDraft(rust_wire.NextStepView step) {
    return step.kind == 'submit_vote' ||
        step.kind == 'submit_shares' ||
        step.kind == 'poll_vote' ||
        step.kind == 'confirm_share';
  }

  bool _sessionNeedsDelegation(VotingSessionState? session) {
    if (session == null) return false;
    final roundPlan = session.roundPlan;
    if (_planNeedsDelegation(roundPlan)) return true;
    if (roundPlan != null && roundPlanNeedsDraftSetup(roundPlan)) return true;
    if (roundPlan != null) {
      return _canPollDelegationWithoutDraft(session);
    }
    return session.resumePlan?.submittedDelegationBundleIndexes.isNotEmpty ??
        false;
  }

  bool _sessionNeedsDelegationSubmission(VotingSessionState? session) {
    if (session == null) return false;
    final roundPlan = session.roundPlan;
    if (_planNeedsDelegation(roundPlan)) return true;
    if (_canPollDelegationWithoutDraft(session)) return true;
    return roundPlan != null && roundPlanNeedsDraftSetup(roundPlan);
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

  bool _planNeedsDelegation(rust_wire.RoundPlanView? roundPlan) {
    return roundPlan?.nextSteps.any(
          (step) => step.kind == 'delegate' || step.kind == 'poll_delegation',
        ) ??
        false;
  }

  bool _planNeedsVotePolling(rust_wire.RoundPlanView? roundPlan) {
    return roundPlan?.nextSteps.any(
          (step) =>
              step.kind == 'submit_vote' ||
              step.kind == 'submit_shares' ||
              step.kind == 'poll_vote',
        ) ??
        false;
  }

  List<rust_wire.DraftVote> _draftVotesFromRoundPlan(
    rust_wire.RoundPlanView? roundPlan,
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
          rust_wire.DraftVote(
            proposalId: proposal.id,
            choice: choicesByProposal[proposal.id]!,
            numOptions: proposal.options.length,
            vcTreePosition: BigInt.zero,
            singleShare: false,
          ),
    ];
  }
}

final votingSubmissionJobsProvider =
    NotifierProvider<VotingSubmissionJobsNotifier, VotingSubmissionJobsState>(
      VotingSubmissionJobsNotifier.new,
    );

final votingSubmissionJobProvider =
    NotifierProvider.family<
      VotingSubmissionJobNotifier,
      VotingSubmissionJobState,
      VotingSessionKey
    >(VotingSubmissionJobNotifier.new);

final votingSubmissionJobSessionProvider =
    Provider.family<AsyncValue<VotingSessionState>, VotingSessionKey>((
      ref,
      key,
    ) {
      return ref.watch(votingSubmissionSessionProvider(key));
    });
