import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_error_messages.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/keystone.dart' as rust_keystone;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../rust/wallet/keystone.dart' as rust_keystone_wallet;
import '../account_provider.dart';
import '../app_security_provider.dart';
import 'voting_session_provider.dart';
import 'voting_service_providers.dart';
import 'voting_share_tracking_registry_provider.dart';
import 'voting_state.dart';
import 'voting_submission_guard_provider.dart';

enum VotingSubmissionJobStatus {
  idle,
  running,
  waitingForKeystone,
  complete,
  error,
}

/// Display metadata for requests included in the currently shown Keystone QR.
@immutable
class VotingKeystoneBatchMemo {
  const VotingKeystoneBatchMemo({
    required this.bundleIndex,
    required this.bundleCount,
    required this.displayMemo,
  });

  final int bundleIndex;
  final int bundleCount;
  final String displayMemo;
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
    this.keystoneBatchMemos = const [],
    this.keystoneBatchMessageCount = 0,
    this.keystoneBatchTotalCount = 0,
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
  final List<VotingKeystoneBatchMemo> keystoneBatchMemos;
  final int keystoneBatchMessageCount;
  final int keystoneBatchTotalCount;
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
    List<VotingKeystoneBatchMemo>? keystoneBatchMemos,
    int? keystoneBatchMessageCount,
    int? keystoneBatchTotalCount,
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
      keystoneBatchMemos: keystoneBatchMemos ?? this.keystoneBatchMemos,
      keystoneBatchMessageCount:
          keystoneBatchMessageCount ?? this.keystoneBatchMessageCount,
      keystoneBatchTotalCount:
          keystoneBatchTotalCount ?? this.keystoneBatchTotalCount,
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
    final jobProvider = votingSubmissionJobProvider(key);
    if (ref.read(jobProvider).isInFlight) return;
    ref.read(jobProvider.notifier).dismiss();
    ref.invalidate(votingSessionProvider(key.roundId));
    state = state.removeJobKey(key);
  }

  void forgetCancelledRecovery(VotingSessionKey key) {
    state = state.removeJobKey(key);
  }

  Future<void> handleKeystoneBatchSignResponse(
    VotingSessionKey key,
    List<int> responseCbor,
  ) {
    return ref
        .read(votingSubmissionJobProvider(key).notifier)
        .handleKeystoneBatchSignResponse(responseCbor);
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

class _VotingKeystoneSigningRound {
  const _VotingKeystoneSigningRound({
    required this.requestId,
    required this.requests,
  });

  final String requestId;
  final List<rust_delegate.KeystoneSigningRequest> requests;

  List<String> get messageIds => [
    for (final request in requests)
      _votingKeystoneMessageId(request.bundleIndex),
  ];
}

class _ConfirmedVoteIntent {
  _ConfirmedVoteIntent({
    required List<rust_wire.DraftVote> draftVotes,
    required List<int> proposalIds,
    required Map<int, int> proposalOptionCounts,
  }) : draftVotes = List.unmodifiable(draftVotes),
       proposalIds = List.unmodifiable(proposalIds),
       proposalOptionCounts = Map.unmodifiable(proposalOptionCounts);

  final List<rust_wire.DraftVote> draftVotes;
  final List<int> proposalIds;
  final Map<int, int> proposalOptionCounts;
}

class VotingSubmissionJobNotifier extends Notifier<VotingSubmissionJobState> {
  VotingSubmissionJobNotifier(this._key);

  final VotingSessionKey _key;
  VotingSubmissionGuard? _guard;
  ProviderSubscription<AsyncValue<VotingSessionState>>? _sessionSubscription;
  VotingSessionKey? _retainedSessionKey;
  Timer? _completionPollTimer;
  _VotingKeystoneSigningRound? _keystoneSigningRound;
  int? _walletSyncRecoveryGeneration;
  int? _walletSyncRecoverySnapshotHeight;
  Timer? _walletSyncRecoveryTimer;
  bool _walletSyncRecoveryInFlight = false;
  Completer<void>? _walletSyncRecoveryPollCompletion;
  bool _walletSyncRecoveryRegistered = false;
  bool _walletSyncRecoveryPausedForMutation = false;
  int _walletSyncRecoveryFailureStreak = 0;
  bool _walletSyncRecoveryRetryOnUnlock = false;
  VoidCallback? _walletSyncRecoveryRestoreListener;
  late VotingShareTrackingRegistry _shareTrackingRegistry;
  int _nextGeneration = 0;

  @override
  VotingSubmissionJobState build() {
    _shareTrackingRegistry = ref.read(votingShareTrackingRegistryProvider);
    _walletSyncRecoveryRestoreListener ??= () {
      unawaited(_restoreWalletSyncRecoveryAfterMutation());
    };
    ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
      if (_walletSyncRecoveryRetryOnUnlock &&
          previous?.requiresUnlock == true &&
          !next.requiresUnlock) {
        unawaited(_retryWalletSyncRecoveryAfterUnlock());
      }
    });
    ref.onDispose(() {
      _shareTrackingRegistry.removeRestoreRequestListener(
        _walletSyncRecoveryRestoreListener!,
      );
      _completionPollTimer?.cancel();
      _completionPollTimer = null;
      _cancelWalletSyncRecovery();
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
    await _restartJob();
  }

  Future<void> _restartJob({_ConfirmedVoteIntent? confirmedIntent}) async {
    _cancelWalletSyncRecovery();
    _releaseGuard();
    _keystoneSigningRound = null;
    state = VotingSubmissionJobState(key: _key);
    _startJob(_key, confirmedIntent: confirmedIntent);
  }

  void dismiss() {
    if (state.isInFlight) return;
    _cancelWalletSyncRecovery();
    _cancelCompletionPoll();
    _releaseGuard();
    _releaseSessionSubscription();
    _keystoneSigningRound = null;
    state = VotingSubmissionJobState(key: _key, generation: ++_nextGeneration);
  }

  void _startJob(
    VotingSessionKey key, {
    _ConfirmedVoteIntent? confirmedIntent,
  }) {
    _cancelWalletSyncRecovery();
    _cancelCompletionPoll();
    _replaceGuard(accountUuid: key.accountUuid, roundId: key.roundId);
    _retainSession(key);
    _keystoneSigningRound = null;
    final sessionNotifier = ref.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    sessionNotifier.clearVoteSubmissionProgressForJobStart();
    final generation = ++_nextGeneration;
    state = VotingSubmissionJobState(
      key: key,
      status: VotingSubmissionJobStatus.running,
      generation: generation,
      pendingDraftVotes: confirmedIntent?.draftVotes,
      pendingProposalIds: confirmedIntent?.proposalIds ?? const [],
      pendingProposalOptionCounts:
          confirmedIntent?.proposalOptionCounts ?? const {},
    );
    unawaited(
      _run(key: key, generation: generation, confirmedIntent: confirmedIntent),
    );
  }

  Future<void> handleKeystoneBatchSignResponse(List<int> responseCbor) async {
    final job = state;
    final key = job.key;
    final signingRound = _keystoneSigningRound;
    if (key == null ||
        !job.isInFlight ||
        responseCbor.isEmpty ||
        signingRound == null) {
      return;
    }
    final generation = job.generation;
    final sessionNotifier = ref.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    late final List<VotingKeystoneBatchSignature> batchSignatures;
    try {
      final decoded = await rust_keystone.decodeZcashBatchSignResponse(
        cbor: responseCbor,
        expectedRequestId: signingRound.requestId,
        messageIds: signingRound.messageIds,
      );
      if (!_isCurrentJob(key: key, generation: generation)) return;
      if (decoded.results.length != signingRound.requests.length) {
        throw StateError(
          'Keystone returned a different number of voting signatures than requested.',
        );
      }

      batchSignatures = <VotingKeystoneBatchSignature>[];
      for (var index = 0; index < signingRound.requests.length; index++) {
        final request = signingRound.requests[index];
        final result = decoded.results[index];
        // Compact responses carry ordered signature lists without message IDs.
        // Rust checks the request ID and count before restoring request order.
        if (result.sigs.length != 1) {
          throw StateError(
            'Keystone returned signatures that do not match this voting request.',
          );
        }
        final signature = result.sigs.single;
        batchSignatures.add(
          VotingKeystoneBatchSignature(
            bundleIndex: request.bundleIndex,
            pool: signature.pool,
            actionIndex: signature.actionIndex,
            signature: signature.sig,
          ),
        );
      }
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      await sessionNotifier.reportKeystoneScanError(
        'This Keystone result does not match the voting QR shown here. Scan the matching result and try again.',
      );
      return;
    }

    try {
      await sessionNotifier.handleKeystoneBatchSignatures(batchSignatures);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final session = _sessionForJob(key);
      if (session == null) return;
      if (session.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session);
        return;
      }
      final requests = session.keystoneSigningRequests;
      if (requests.isNotEmpty) {
        // Validation and persistence failures are recoverable scan errors. Keep
        // the current request ID and QR so the same Keystone response can be
        // scanned again instead of replacing the active signing round.
        if (session.keystoneScanError != null) return;
        await _updateKeystoneQr(
          key: key,
          generation: generation,
          requests: requests,
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
    _ConfirmedVoteIntent? confirmedIntent,
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
      final currentProposalOptionCounts = {
        for (final proposal in proposals) proposal.id: proposal.options.length,
      };
      late List<rust_wire.DraftVote> draftVotes;
      late List<int> intentProposalIds;
      late Map<int, int> proposalOptionCounts;
      if (confirmedIntent != null) {
        // Keep the reviewed choices immutable, but drop work that a fresh
        // recovery plan now reports as complete while sync was catching up.
        draftVotes = _draftVotesForSession(
          confirmedIntent.draftVotes,
          loadedSession,
        );
        intentProposalIds = _proposalIdsForSession(
          confirmedIntent.proposalIds,
          loadedSession,
        );
        proposalOptionCounts = confirmedIntent.proposalOptionCounts;
      } else {
        final VotingDraftState draft;
        try {
          draft = await ref
              .read(votingDraftProvider(key).notifier)
              .ensureLoaded();
        } catch (_) {
          if (!_isCurrentJob(key: key, generation: generation)) return;
          final activeSession = await _ensureEligibilityForCompletedSession(
            key: key,
            generation: generation,
            sessionNotifier: sessionNotifier,
            session: loadedSession,
          );
          if (activeSession == null) return;
          if (_canCompleteSessionAfterDraftLoadFailure(activeSession)) {
            _completeJob(key: key, generation: generation);
            return;
          }
          rethrow;
        }
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final confirmedDraft = _draftForSession(draft, loadedSession);
        draftVotes = confirmedDraft.toDraftVotes(proposals);
        intentProposalIds = draftVotes.isNotEmpty
            ? _proposalIdsForDraftIntents(loadedSession, proposals)
            : const [];
        proposalOptionCounts = currentProposalOptionCounts;
      }
      if (_canCompleteSessionWithoutDraftVotes(loadedSession, draftVotes)) {
        _completeJob(key: key, generation: generation);
        return;
      }
      state = state.copyWith(
        pendingDraftVotes: draftVotes,
        pendingProposalIds: intentProposalIds,
        pendingProposalOptionCounts: proposalOptionCounts,
      );
      if (round.voteEndTime == null) {
        _failJob(
          key: key,
          generation: generation,
          message: 'Voting round end time is unavailable. Retry in a moment.',
        );
        return;
      }

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

      var activeSession = afterWalletSync ?? loadedSession;
      final completedEligibilitySession =
          await _ensureEligibilityForCompletedSession(
            key: key,
            generation: generation,
            sessionNotifier: sessionNotifier,
            session: activeSession,
          );
      if (completedEligibilitySession == null) return;
      activeSession = completedEligibilitySession;
      if (draftVotes.isNotEmpty &&
          !activeSession.hasConfirmedVotingEligibility) {
        await sessionNotifier.ensureVotingEligibility();
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterEligibilityCheck = _sessionForJob(key);
        if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterEligibilityCheck!,
          );
          return;
        }
        activeSession = afterEligibilityCheck ?? activeSession;
      }
      if (_canCompleteSessionWithoutDraftVotes(activeSession, draftVotes)) {
        _completeJob(key: key, generation: generation);
        return;
      }
      final recoveredDraftVotes =
          draftVotes.isEmpty && _roundPlanHasNoOpenProposals(activeSession)
          ? _draftVotesFromRoundPlan(activeSession.roundPlan, proposals)
          : const <rust_wire.DraftVote>[];
      if (draftVotes.isEmpty) draftVotes = recoveredDraftVotes;
      final canRecoverWithoutDraft = _canRecoverWithoutDraft(activeSession);
      final canPollDelegationWithoutDraft = _canPollDelegationWithoutDraft(
        activeSession,
      );
      if ((draftVotes.isNotEmpty ||
              _hasRemainingVoteOrShareWork(activeSession) ||
              canPollDelegationWithoutDraft) &&
          !activeSession.hasConfirmedVotingEligibility) {
        await sessionNotifier.ensureVotingEligibility();
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterEligibilityCheck = _sessionForJob(key);
        if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterEligibilityCheck!,
          );
          return;
        }
        activeSession = afterEligibilityCheck ?? activeSession;
      }
      final needsDelegation = _sessionNeedsDelegation(activeSession);
      final needsDelegationSigning = _sessionNeedsDelegationSigning(
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

      if (activeSession.isHardwareAccount && needsDelegationSigning) {
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
      if (!activeSession.isHardwareAccount && needsDelegationSigning) {
        final softwareSecret = await ref
            .read(accountProvider.notifier)
            .getSoftwareWalletSecretForAccount(key.accountUuid);
        if (!_isCurrentJob(key: key, generation: generation)) return;
        softwareMnemonic = softwareSecret?.encodeForStorage();
        if (softwareMnemonic == null || softwareMnemonic.isEmpty) {
          _failJob(
            key: key,
            generation: generation,
            message:
                'Token holder voting requires a software account. Switch to a software account to vote in this round.',
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
    final requests = session.keystoneSigningRequests;
    if (requests.isNotEmpty) {
      await _updateKeystoneQr(
        key: key,
        generation: generation,
        requests: requests,
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
    required List<rust_delegate.KeystoneSigningRequest> requests,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    if (requests.isEmpty) {
      throw StateError('No Keystone voting requests are ready to encode.');
    }
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.waitingForKeystone,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: requests.length,
      clearKeystoneQrError: true,
    );
    try {
      final baseRequestId = _votingKeystoneRequestId(key, requests);
      final allMessages = _votingKeystoneBatchMessages(requests);
      final roundCounts = await rust_keystone.zcashSignBatchRoundMessageCounts(
        requestId: baseRequestId,
        messages: allMessages,
        maxMessages: _votingKeystoneBatchMaxMessages,
      );
      if (roundCounts.isEmpty || roundCounts.first <= 0) {
        throw StateError('Keystone returned an invalid voting batch plan.');
      }
      final messageCount = roundCounts.first;
      if (messageCount > requests.length) {
        throw StateError('Keystone voting batch plan exceeds the request.');
      }
      final roundRequests = requests.sublist(0, messageCount);
      final urParts = await rust_keystone.encodeZcashSignBatchUrParts(
        requestId: baseRequestId,
        messages: _votingKeystoneBatchMessages(roundRequests),
        maxFragmentLen: BigInt.from(200),
      );
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _keystoneSigningRound = _VotingKeystoneSigningRound(
        requestId: baseRequestId,
        requests: roundRequests,
      );
      state = state.copyWith(
        status: VotingSubmissionJobStatus.waitingForKeystone,
        keystoneUrParts: urParts,
        keystoneBatchMemos: [
          for (final request in roundRequests)
            VotingKeystoneBatchMemo(
              bundleIndex: request.bundleIndex,
              bundleCount: request.bundleCount,
              displayMemo: request.displayMemo,
            ),
        ],
        keystoneBatchMessageCount: roundRequests.length,
        keystoneBatchTotalCount: requests.length,
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
    var votePollingSession = _sessionForJob(key) ?? initialSession;
    final canContinueWithoutDraft =
        votePollingSession != null &&
        (_canRecoverWithoutDraft(votePollingSession) ||
            _canPollDelegationWithoutDraft(votePollingSession) ||
            _hasCompletedSubmissionArtifacts(votePollingSession));
    if (draftVotes.isEmpty &&
        (votePollingSession == null || !canContinueWithoutDraft)) {
      _failJob(
        key: key,
        generation: generation,
        message: 'Choose at least one vote before submitting.',
      );
      return;
    }
    final hasVoteOrShareWork =
        draftVotes.isNotEmpty ||
        (votePollingSession != null &&
            _hasRemainingVoteOrShareWork(votePollingSession));
    if (hasVoteOrShareWork &&
        !(votePollingSession?.hasConfirmedVotingEligibility ?? false)) {
      await sessionNotifier.ensureVotingEligibility();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterEligibilityCheck = _sessionForJob(key);
      if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
        _failFromSession(
          key: key,
          generation: generation,
          session: afterEligibilityCheck!,
        );
        return;
      }
      votePollingSession = afterEligibilityCheck ?? votePollingSession;
    }
    if (draftVotes.isNotEmpty || _sessionNeedsVotePolling(votePollingSession)) {
      await sessionNotifier.castVotes(
        draftVotes: draftVotes,
        allProposalIds: intentProposalIds,
        proposalOptionCounts: proposalOptionCounts,
      );
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    var done = _sessionForJob(key);
    if (done?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: done!);
      return;
    }
    if (done != null) {
      final completedEligibilitySession =
          await _ensureEligibilityForCompletedSession(
            key: key,
            generation: generation,
            sessionNotifier: sessionNotifier,
            session: done,
          );
      if (completedEligibilitySession == null) return;
      done = completedEligibilitySession;
    }
    if (_canCompleteSubmission(done)) {
      _completeJob(key: key, generation: generation);
      return;
    }
    await sessionNotifier.submitPendingShares();
    if (!_isCurrentJob(key: key, generation: generation)) return;
    done = _sessionForJob(key);
    if (done?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: done!);
      return;
    }
    if (done != null) {
      final completedEligibilitySession =
          await _ensureEligibilityForCompletedSession(
            key: key,
            generation: generation,
            sessionNotifier: sessionNotifier,
            session: done,
          );
      if (completedEligibilitySession == null) return;
      done = completedEligibilitySession;
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
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.running,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: 0,
      clearKeystoneQrError: true,
      clearErrorMessage: true,
    );
  }

  void _completeJob({required VotingSessionKey key, required int generation}) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    // Register live helper-share tracking before releasing the submission
    // guard. Account delete/reset drain through the registry; they must not
    // observe an unguarded in-flight pass.
    _pinLiveShareTracking(key);
    _releaseGuard();
    _releaseSessionSubscription();
    ref.invalidate(votingSessionProvider(key.roundId));
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.complete,
      clearErrorMessage: true,
      softwareAccountRequired: false,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: 0,
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
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final shouldAutoRecover = isVotingWalletSyncStalled(session.error?.cause);
    final snapshotHeight = session.walletSnapshotHeight;
    final preserveConfirmedIntent = shouldAutoRecover && snapshotHeight != null;
    _failJob(
      key: key,
      generation: generation,
      message: _statusErrorMessage(session) ?? _genericVotingStatusErrorMessage,
      preservePendingSubmission: preserveConfirmedIntent,
    );
    if (shouldAutoRecover && snapshotHeight != null) {
      _walletSyncRecoveryGeneration = generation;
      _walletSyncRecoverySnapshotHeight = snapshotHeight;
      _startWalletSyncRecoveryPolling();
    }
  }

  void _failJob({
    required VotingSessionKey key,
    required int generation,
    required String message,
    bool softwareAccountRequired = false,
    bool preservePendingSubmission = false,
  }) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelWalletSyncRecovery();
    _cancelCompletionPoll();
    _releaseGuard();
    _releaseSessionSubscription();
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.error,
      errorMessage: message,
      softwareAccountRequired: softwareAccountRequired,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: 0,
      clearKeystoneQrError: true,
      clearPendingDraftVotes: !preservePendingSubmission,
      pendingProposalIds: preservePendingSubmission
          ? state.pendingProposalIds
          : const [],
      pendingProposalOptionCounts: preservePendingSubmission
          ? state.pendingProposalOptionCounts
          : const {},
      pendingRecoveryWithoutDraft: preservePendingSubmission
          ? state.pendingRecoveryWithoutDraft
          : false,
    );
  }

  Future<void> _pollWalletSyncRecovery() async {
    final generation = _walletSyncRecoveryGeneration;
    final snapshotHeight = _walletSyncRecoverySnapshotHeight;
    if (generation == null ||
        snapshotHeight == null ||
        state.status != VotingSubmissionJobStatus.error ||
        state.generation != generation ||
        _walletSyncRecoveryPausedForMutation ||
        _walletSyncRecoveryInFlight) {
      return;
    }
    if (ref.read(appSecurityProvider).requiresUnlock) {
      // Sync cannot advance while locked, so polling readiness would spin
      // for the whole lock. Wait for unlock instead — the retry itself also
      // needs the unlocked spending secret.
      _armWalletSyncRecoveryRetryOnUnlock();
      return;
    }
    _walletSyncRecoveryInFlight = true;
    final pollCompletion = Completer<void>();
    _walletSyncRecoveryPollCompletion = pollCompletion;
    try {
      // votingWalletDbPathProvider memoizes the resolve, so the 2s poll
      // does not repeat a support-directory lookup plus keychain read.
      final dbPath = await ref.read(votingWalletDbPathProvider).call();
      final endpoint = ref.read(votingRpcEndpointConfigProvider);
      final readiness = await ref
          .read(votingWalletSyncReadinessCheckerProvider)
          .check(
            dbPath: dbPath,
            network: endpoint.networkName,
            snapshotHeight: snapshotHeight,
          );
      if (_walletSyncRecoveryGeneration != generation ||
          _walletSyncRecoveryPausedForMutation ||
          state.status != VotingSubmissionJobStatus.error) {
        return;
      }
      _walletSyncRecoveryFailureStreak = 0;
      if (readiness.walletBirthdayAfterSnapshot) {
        // The shared scanner cannot reach a snapshot before the wallet's
        // earliest birthday. Replace the now-false automatic-retry promise
        // in both owners before stopping recovery; a manual retry after
        // restoring an earlier account re-runs this gate.
        ref
            .read(votingSubmissionSessionProvider(_key).notifier)
            .markWalletBirthdayAfterSnapshot(readiness);
        state = state.copyWith(
          errorMessage: votingWalletBirthdayAfterSnapshotMessage(readiness),
        );
        _cancelWalletSyncRecovery();
        return;
      }
      if (readiness.isReady) {
        // The wallet can lock while the readiness check is in flight; the
        // retry needs the unlocked spending secret.
        if (ref.read(appSecurityProvider).requiresUnlock) {
          _armWalletSyncRecoveryRetryOnUnlock();
          return;
        }
        final confirmedIntent = _confirmedVoteIntentFromState();
        if (confirmedIntent == null) {
          ref
              .read(votingSubmissionSessionProvider(_key).notifier)
              .markWalletSyncRecoveryStopped(_walletSyncRecoveryStoppedMessage);
          state = state.copyWith(
            errorMessage: _walletSyncRecoveryStoppedMessage,
          );
          _cancelWalletSyncRecovery();
          return;
        }
        _walletSyncRecoveryGeneration = null;
        _walletSyncRecoverySnapshotHeight = null;
        _walletSyncRecoveryTimer?.cancel();
        _walletSyncRecoveryTimer = null;
        await _restartJob(confirmedIntent: confirmedIntent);
      } else {
        ref.read(votingWalletSyncStarterProvider).call();
      }
    } catch (e) {
      // A poll can also throw after the notifier is disposed (the timer is
      // cancelled on dispose, but an in-flight poll keeps running); treating
      // that as one more failed attempt is fine because the cancelled timer
      // never polls again. Transient readiness failures keep the timer alive;
      // a persistent failure (e.g. the wallet DB was reset) stops recovery so
      // it does not log unhandled errors forever. The job stays in its error
      // state and manual retry remains available.
      if (_walletSyncRecoveryGeneration != generation ||
          _walletSyncRecoveryPausedForMutation ||
          state.status != VotingSubmissionJobStatus.error) {
        return;
      }
      _walletSyncRecoveryFailureStreak++;
      debugPrint(
        '[zcash] Voting: wallet sync recovery poll failed '
        '($_walletSyncRecoveryFailureStreak/'
        '$_kWalletSyncRecoveryMaxFailureStreak): $e',
      );
      if (_walletSyncRecoveryFailureStreak >=
          _kWalletSyncRecoveryMaxFailureStreak) {
        ref
            .read(votingSubmissionSessionProvider(_key).notifier)
            .markWalletSyncRecoveryStopped(_walletSyncRecoveryStoppedMessage);
        state = state.copyWith(errorMessage: _walletSyncRecoveryStoppedMessage);
        _cancelWalletSyncRecovery();
      }
    } finally {
      _walletSyncRecoveryInFlight = false;
      if (identical(_walletSyncRecoveryPollCompletion, pollCompletion)) {
        _walletSyncRecoveryPollCompletion = null;
      }
      if (!pollCompletion.isCompleted) pollCompletion.complete();
    }
  }

  void _startWalletSyncRecoveryPolling() {
    _walletSyncRecoveryPausedForMutation = false;
    if (!_registerWalletSyncRecovery()) {
      state = state.copyWith(errorMessage: _walletSyncRecoveryStoppedMessage);
      _cancelWalletSyncRecovery();
      return;
    }
    final configuredInterval = ref.read(votingWalletSyncPollIntervalProvider);
    final interval = configuredInterval > Duration.zero
        ? configuredInterval
        : const Duration(milliseconds: 10);
    _walletSyncRecoveryTimer?.cancel();
    _walletSyncRecoveryTimer = Timer.periodic(interval, (_) {
      unawaited(_pollWalletSyncRecovery());
    });
    unawaited(_pollWalletSyncRecovery());
  }

  /// Parks recovery on the unlock signal. Sync cannot advance and the retry
  /// needs the unlocked spending secret, so polling stops entirely until
  /// [_retryWalletSyncRecoveryAfterUnlock] resumes it.
  void _armWalletSyncRecoveryRetryOnUnlock() {
    _walletSyncRecoveryRetryOnUnlock = true;
    _walletSyncRecoveryTimer?.cancel();
    _walletSyncRecoveryTimer = null;
    _walletSyncRecoveryFailureStreak = 0;
  }

  Future<void> _retryWalletSyncRecoveryAfterUnlock() async {
    if (!ref.mounted || !_walletSyncRecoveryRetryOnUnlock) return;
    if (ref.read(appSecurityProvider).requiresUnlock) return;
    final generation = _walletSyncRecoveryGeneration;
    if (generation == null ||
        state.status != VotingSubmissionJobStatus.error ||
        state.generation != generation) {
      _cancelWalletSyncRecovery();
      return;
    }
    _walletSyncRecoveryRetryOnUnlock = false;
    // Resume polling rather than retrying outright: the wallet may have been
    // locked while still short of the snapshot, and the poll is what decides
    // readiness. When sync is already past it, the immediate first tick
    // retries straight away.
    _startWalletSyncRecoveryPolling();
  }

  void _cancelWalletSyncRecovery() {
    _walletSyncRecoveryTimer?.cancel();
    _walletSyncRecoveryTimer = null;
    _walletSyncRecoveryGeneration = null;
    _walletSyncRecoverySnapshotHeight = null;
    _walletSyncRecoveryFailureStreak = 0;
    _walletSyncRecoveryRetryOnUnlock = false;
    _walletSyncRecoveryPausedForMutation = false;
    final restoreListener = _walletSyncRecoveryRestoreListener;
    if (restoreListener != null) {
      _shareTrackingRegistry.removeRestoreRequestListener(restoreListener);
    }
    if (_walletSyncRecoveryRegistered) {
      _shareTrackingRegistry.unregisterSyncRecovery(key: _key, owner: this);
      _walletSyncRecoveryRegistered = false;
    }
  }

  bool _registerWalletSyncRecovery() {
    if (_walletSyncRecoveryRegistered) return true;
    final registered = _shareTrackingRegistry.registerSyncRecovery(
      key: _key,
      owner: this,
      stopAndDrain: _stopAndDrainWalletSyncRecovery,
    );
    _walletSyncRecoveryRegistered = registered;
    return registered;
  }

  Future<void> _stopAndDrainWalletSyncRecovery() async {
    final pollCompletion = _walletSyncRecoveryPollCompletion?.future;
    _walletSyncRecoveryPausedForMutation = true;
    _walletSyncRecoveryTimer?.cancel();
    _walletSyncRecoveryTimer = null;
    _walletSyncRecoveryRetryOnUnlock = false;
    _shareTrackingRegistry.addRestoreRequestListener(
      _walletSyncRecoveryRestoreListener!,
    );
    if (_walletSyncRecoveryRegistered) {
      _shareTrackingRegistry.unregisterSyncRecovery(key: _key, owner: this);
      _walletSyncRecoveryRegistered = false;
    }
    if (pollCompletion != null) await pollCompletion;
  }

  Future<void> _restoreWalletSyncRecoveryAfterMutation() async {
    if (!ref.mounted || !_walletSyncRecoveryPausedForMutation) return;

    final AccountState accountState;
    try {
      accountState =
          ref.read(accountProvider).value ??
          await ref.read(accountProvider.future);
    } catch (error) {
      debugPrint(
        '[zcash] Voting: could not restore wallet sync recovery after '
        'account mutation: $error',
      );
      return;
    }
    if (!ref.mounted || !_walletSyncRecoveryPausedForMutation) return;

    _shareTrackingRegistry.removeRestoreRequestListener(
      _walletSyncRecoveryRestoreListener!,
    );

    final accountStillExists = accountState.accounts.any(
      (account) => account.uuid == _key.accountUuid,
    );
    if (!accountStillExists) {
      dismiss();
      ref
          .read(votingSubmissionJobsProvider.notifier)
          .forgetCancelledRecovery(_key);
      return;
    }

    final generation = _walletSyncRecoveryGeneration;
    final snapshotHeight = _walletSyncRecoverySnapshotHeight;
    if (generation == null ||
        snapshotHeight == null ||
        state.status != VotingSubmissionJobStatus.error ||
        state.generation != generation) {
      _cancelWalletSyncRecovery();
      return;
    }
    _walletSyncRecoveryPausedForMutation = false;
    _startWalletSyncRecoveryPolling();
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

  void _pinLiveShareTracking(VotingSessionKey key) {
    final hasUnconfirmedShares =
        _sessionForJob(
          key,
        )?.resumePlan?.unconfirmedShareDelegations.isNotEmpty ??
        false;
    if (!hasUnconfirmedShares) return;
    final sessionNotifier = ref.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    sessionNotifier.pinAutomaticShareTracking();
    // Helper reveal is background work. Awaiting it in the job keeps the
    // status screen on "Finalizing submission" for accepted-but-unrevealed
    // shares. The registry, not the job guard, is the drain barrier.
    unawaited(
      sessionNotifier.submitPendingShares().catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint(
          '[zcash] Voting: background share tracking failed: $error\n$stack',
        );
      }),
    );
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
    return session.hasConfirmedVotingEligibility &&
        _hasCompletedSubmissionArtifacts(session);
  }

  Future<VotingSessionState?> _ensureEligibilityForCompletedSession({
    required VotingSessionKey key,
    required int generation,
    required VotingSessionNotifier sessionNotifier,
    required VotingSessionState session,
  }) async {
    if (session.hasConfirmedVotingEligibility ||
        !_hasCompletedSubmissionArtifacts(session)) {
      return session;
    }
    await sessionNotifier.ensureVotingEligibility();
    if (!_isCurrentJob(key: key, generation: generation)) return null;
    final afterEligibilityCheck = _sessionForJob(key);
    if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
      _failFromSession(
        key: key,
        generation: generation,
        session: afterEligibilityCheck!,
      );
      return null;
    }
    return afterEligibilityCheck ?? session;
  }

  bool _hasCompletedSubmissionArtifacts(VotingSessionState? session) {
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

  bool _canCompleteSessionWithoutDraftVotes(
    VotingSessionState session,
    List<rust_wire.DraftVote> draftVotes,
  ) {
    if (!_canCompleteSubmission(session)) return false;
    if (draftVotes.isEmpty) return true;
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return false;
    final openProposalIds = roundPlan.openProposals.toSet();
    return draftVotes.every(
      (draftVote) => !openProposalIds.contains(draftVote.proposalId),
    );
  }

  _ConfirmedVoteIntent? _confirmedVoteIntentFromState() {
    final draftVotes = state.pendingDraftVotes;
    if (draftVotes == null) return null;
    return _ConfirmedVoteIntent(
      draftVotes: draftVotes,
      proposalIds: state.pendingProposalIds,
      proposalOptionCounts: state.pendingProposalOptionCounts,
    );
  }

  bool _canCompleteSessionAfterDraftLoadFailure(VotingSessionState session) {
    return _canCompleteSubmission(session) &&
        _roundPlanHasNoOpenProposals(session);
  }

  VotingDraftState _draftForSession(
    VotingDraftState draft,
    VotingSessionState session,
  ) {
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return draft;
    final openProposalIds = roundPlan.openProposals.toSet();
    return VotingDraftState(
      choices: {
        for (final entry in draft.choices.entries)
          if (openProposalIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  List<rust_wire.DraftVote> _draftVotesForSession(
    List<rust_wire.DraftVote> draftVotes,
    VotingSessionState session,
  ) {
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return draftVotes;
    final openProposalIds = roundPlan.openProposals.toSet();
    return [
      for (final draftVote in draftVotes)
        if (openProposalIds.contains(draftVote.proposalId)) draftVote,
    ];
  }

  List<int> _proposalIdsForSession(
    List<int> proposalIds,
    VotingSessionState session,
  ) {
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return proposalIds;
    final openProposalIds = roundPlan.openProposals.toSet();
    return [
      for (final proposalId in proposalIds)
        if (openProposalIds.contains(proposalId)) proposalId,
    ];
  }

  List<int> _proposalIdsForDraftIntents(
    VotingSessionState session,
    List<VotingProposalView> proposals,
  ) {
    final proposalIds = proposals.map((proposal) => proposal.id).toList();
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return proposalIds;
    final openProposalIds = roundPlan.openProposals.toSet();
    return [
      for (final proposalId in proposalIds)
        if (openProposalIds.contains(proposalId)) proposalId,
    ];
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
      'eligible account if this account cannot vote in this voting round.';

  static const _walletSyncRecoveryStoppedMessage =
      'Automatic recovery could not continue. Retry to check wallet sync '
      'again.';

  /// Consecutive readiness-check failures tolerated before auto-recovery
  /// stops polling. At the default 2s interval this rides out ~1 minute of
  /// transient errors while still halting on persistent ones.
  static const _kWalletSyncRecoveryMaxFailureStreak = 30;

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
    return step.kind == 'cast_vote' ||
        step.kind == 'submit_vote' ||
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

  bool _sessionNeedsDelegationSigning(VotingSessionState session) {
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
              step.kind == 'cast_vote' ||
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

const _votingKeystoneBatchMaxMessages = 40;

String _votingKeystoneMessageId(int bundleIndex) =>
    'voting-bundle-$bundleIndex';

String _votingKeystoneRequestId(
  VotingSessionKey key,
  List<rust_delegate.KeystoneSigningRequest> requests,
) {
  final material = <int>[
    ...utf8.encode('vizor-voting-batch-v1'),
    0,
    ...utf8.encode(key.accountUuid),
    0,
    ...utf8.encode(key.roundId),
  ];
  for (final request in requests) {
    material
      ..add(0)
      ..addAll(utf8.encode(request.bundleIndex.toString()))
      ..add(0)
      ..addAll(request.pcztSighash);
  }
  return 'vizor-vote-${sha256.convert(material)}';
}

List<rust_keystone_wallet.ZcashBatchMessageInput> _votingKeystoneBatchMessages(
  List<rust_delegate.KeystoneSigningRequest> requests,
) => [
  for (final request in requests)
    rust_keystone_wallet.ZcashBatchMessageInput(
      id: _votingKeystoneMessageId(request.bundleIndex),
      pcztBytes: request.redactedPcztBytes,
      expectedSignatureCount: 1,
    ),
];

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

final votingSubmissionJobSessionProvider = Provider.autoDispose
    .family<AsyncValue<VotingSessionState>, VotingSessionKey>((ref, key) {
      return ref.watch(votingSubmissionSessionProvider(key));
    });
