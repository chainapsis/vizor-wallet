import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatting/duration_format.dart';
import '../../core/formatting/hex_codec.dart';
import '../../features/voting/voting_error_messages.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_formatters.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../features/voting/voting_share_timing.dart';
import '../../rust/api/voting.dart' as rust_voting;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_helper_health_tracker.dart';
import '../../services/voting/voting_models.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';
import 'voting_submission_guard_provider.dart';

/// Orchestrates one round's voting lifecycle for the UI.
///
/// The notifier is intentionally recovery-first: every public action reloads
/// persisted Rust recovery state before deciding which bundle/proposal/share
/// work is still safe to run. Network/proof actions are serialized through
/// [_enqueue] so repeated button taps cannot overlap Rust wallet mutations.
class VotingSessionNotifier extends AsyncNotifier<VotingSessionState> {
  VotingSessionNotifier(this._roundId);

  Future<void> _operation = Future.value();
  final String _roundId;
  final Map<String, Future<void>> _delegationPirPrecomputes = {};
  Timer? _shareTrackingTimer;
  String? _sessionAccountUuid;
  bool? _sessionIsHardwareAccount;
  _VotingSessionContext? _currentContext;
  bool _disposeHandlerRegistered = false;
  bool _activeAccountListenerRegistered = false;
  bool _submissionGuardListenerRegistered = false;
  List<VotingSubmissionGuard> _activeSubmissionGuards = const [];
  int _sessionGeneration = 0;
  Completer<void> _sessionInvalidated = Completer<void>();
  int? _runningActionGeneration;
  bool _isDisposed = false;

  @override
  Future<VotingSessionState> build() async {
    _reactivateForBuild();
    _registerSubmissionGuardListener();
    _registerDisposeHandler();
    _registerActiveAccountListener();
    await _refreshSessionAccountFromActiveAccount();
    final context = await _loadContext(_roundId, checkStaleAction: false);
    _currentContext = context;
    final initialState = VotingSessionState(
      roundId: _roundId,
      accountUuid: context.accountUuid,
      isHardwareAccount: context.isHardwareAccount,
      config: context.config,
      round: context.round,
      resumePlan: context.resumePlan,
      roundPlan: context.roundPlan,
      phase: _phaseForPlans(context.roundPlan),
    );
    _shareTrackingTimer?.cancel();
    unawaited(_scheduleShareTracking(context, context.resumePlan));
    return initialState;
  }

  void _reactivateForBuild() {
    // Riverpod runs ref.onDispose before every notifier rebuild, not only on
    // permanent provider teardown. Re-arm this reused notifier so account
    // reloads can still accept queued actions after a dependency changes.
    _isDisposed = false;
  }

  void _registerDisposeHandler() {
    if (_disposeHandlerRegistered) return;
    _disposeHandlerRegistered = true;
    final rust = ref.read(votingRustApiProvider);
    ref.onDispose(() {
      _disposeHandlerRegistered = false;
      _activeAccountListenerRegistered = false;
      _submissionGuardListenerRegistered = false;
      // Provider disposal is round-scoped: clear abandoned prepared PCZTs but
      // keep account-wide vote-tree sync state reusable across rounds.
      final context = _currentContext;
      _isDisposed = true;
      _advanceSessionGeneration();
      _delegationPirPrecomputes.clear();
      _shareTrackingTimer?.cancel();
      if (context == null) return;
      if (_activeSubmissionOwnsContext(context)) {
        debugPrint(
          '[zcash] Voting: process-local state reset skipped '
          'round=${context.round.roundId} account=${context.accountUuid} '
          'reason=provider-dispose activeSubmission=true',
        );
        return;
      }
      unawaited(
        _resetVotingSessionState(
          rust: rust,
          context: context,
          reason: 'provider-dispose',
        ),
      );
    });
  }

  void _registerSubmissionGuardListener() {
    if (_submissionGuardListenerRegistered) return;
    _submissionGuardListenerRegistered = true;
    ref.listen<List<VotingSubmissionGuard>>(votingSubmissionGuardProvider, (
      _,
      guards,
    ) {
      _activeSubmissionGuards = guards;
    }, fireImmediately: true);
  }

  void _registerActiveAccountListener() {
    if (_activeAccountListenerRegistered) return;
    _activeAccountListenerRegistered = true;
    ref.listen<Future<String?> Function()>(votingActiveAccountUuidProvider, (
      _,
      accountUuidLoader,
    ) {
      unawaited(
        _refreshSessionAccountFromLoader(
          accountUuidLoader,
          throwIfMissing: false,
        ),
      );
    });
  }

  Future<void> _refreshSessionAccountFromActiveAccount() async {
    final accountUuidLoader = ref.watch(votingActiveAccountUuidProvider);
    await _refreshSessionAccountFromLoader(accountUuidLoader);
  }

  Future<void> _refreshSessionAccountFromLoader(
    Future<String?> Function() accountUuidLoader, {
    bool throwIfMissing = true,
  }) async {
    final accountUuid = await accountUuidLoader.call();
    if (accountUuid == null) {
      if (!throwIfMissing) return;
      throw StateError('No active account for voting session.');
    }
    if (_sessionAccountUuid == accountUuid) return;

    final hadSessionAccount = _sessionAccountUuid != null;
    final previousContext = _currentContext;
    if (previousContext != null) {
      if (!_activeSubmissionOwnsContext(previousContext)) {
        unawaited(
          _resetVotingSessionState(
            rust: ref.read(votingRustApiProvider),
            context: previousContext,
            reason: 'active-account-switch',
          ),
        );
      }
    }
    if (hadSessionAccount) {
      _advanceSessionGeneration();
    }
    _sessionAccountUuid = accountUuid;
    _sessionIsHardwareAccount = null;
    _currentContext = null;
    _delegationPirPrecomputes.clear();
    _shareTrackingTimer?.cancel();
    if (!hadSessionAccount || _isDisposed) return;

    final generation = _sessionGeneration;
    state = const AsyncLoading();
    try {
      final context = await _loadContext(_roundId, checkStaleAction: false);
      if (!_isCurrentGeneration(generation) ||
          _sessionAccountUuid != accountUuid) {
        _logStaleSessionUpdate('account-reload', generation, context);
        return;
      }
      _currentContext = context;
      state = AsyncData(
        VotingSessionState(
          roundId: _roundId,
          accountUuid: context.accountUuid,
          isHardwareAccount: context.isHardwareAccount,
          config: context.config,
          round: context.round,
          resumePlan: context.resumePlan,
          roundPlan: context.roundPlan,
          phase: _phaseForPlans(context.roundPlan),
        ),
      );
      unawaited(_scheduleShareTracking(context, context.resumePlan));
    } catch (error, stackTrace) {
      if (!_isCurrentGeneration(generation) ||
          _sessionAccountUuid != accountUuid) {
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> prepareDelegation() {
    return _enqueue(_prepareDelegationUnlocked);
  }

  Future<void> ensureWalletReadyForVoting() {
    return _enqueue(() async {
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);
    });
  }

  Future<void> recordDraftVoteIntents({
    required List<rust_wire.DraftVote> draftVotes,
    List<int>? allProposalIds,
    Map<int, int>? proposalOptionCounts,
  }) {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);
      final effectiveDraftVotes = VotingShareTimingPolicy.applyLastMomentMode(
        draftVotes,
        context.round,
      );
      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      await _recordBallotIntentsAndReloadPlans(
        context: context,
        current: current,
        effectiveDraftVotes: effectiveDraftVotes,
        allProposalIds: allProposalIds,
        proposalOptionCounts: proposalOptionCounts,
        progress: progress,
      );
    });
  }

  Future<void> precomputeDelegationPir({
    required String accountUuid,
    required String mnemonic,
  }) async {
    final context = await _loadContext(_roundId);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    try {
      await _waitUntilWalletReadyForVoting(context);
    } on _StaleVotingSessionAction {
      return;
    }
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final pirEndpoint = await _resolvePirEndpoint(context);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    if (pirEndpoint == null) return;

    final rust = ref.read(votingRustApiProvider);
    await rust.setupDelegationBundles(
      dbPath: context.dbPath,
      lightwalletdUrl: context.lightwalletdUrl,
      network: context.network,
      roundParams: context.round.toRoundParams(),
      roundName: context.round.title,
      sessionJson: context.round.sessionJson,
      accountUuid: context.accountUuid,
    );
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final plans = await _loadPlans(context);
    final plan = plans.resumePlan;
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final pendingBundles = plan.pendingDelegationBundleIndexes;

    for (final bundleIndex in pendingBundles) {
      final key = _delegationPirPrecomputeKey(context, bundleIndex);
      _delegationPirPrecomputes[key] ??= _runDelegationPirPrecompute(
        context: context,
        pirEndpoint: pirEndpoint,
        mnemonic: mnemonic,
        bundleIndex: bundleIndex,
      );
    }
  }

  Future<void> delegatePendingBundles({
    required String mnemonic,
    bool forceFreshSetup = false,
  }) {
    return _enqueue(() async {
      var current = await future;
      var context = await _loadContext(_roundId);
      var plan = current.resumePlan ?? context.resumePlan;
      var roundPlan = current.roundPlan ?? context.roundPlan;
      var hasFreshDelegationWork =
          plan.pendingDelegationBundleIndexes.isNotEmpty;
      if (forceFreshSetup ||
          (hasFreshDelegationWork && _needsDelegationPreparation(current))) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
        context = await _loadContext(_roundId);
        plan = current.resumePlan ?? context.resumePlan;
        roundPlan = current.roundPlan ?? context.roundPlan;
        hasFreshDelegationWork = plan.pendingDelegationBundleIndexes.isNotEmpty;
      }

      if (context.isHardwareAccount) {
        _setError(
          'Sign delegation bundles with Keystone before submitting.',
          context: context,
        );
        return;
      }
      final pirEndpoint = current.pirEndpoint;
      if (hasFreshDelegationWork && pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.', context: context);
        return;
      }
      if (hasFreshDelegationWork) {
        final nextState = (state.value ?? current).copyWith(
          phase: VotingSessionPhase.delegating,
          resumePlan: plan,
          currentBundleIndex: plan.pendingDelegationBundleIndexes.first,
          clearError: true,
        );
        _setStateForContext(context, nextState);
        current = nextState;
      }
      if (hasFreshDelegationWork) {
        await _ensureHotkey(context, mnemonic: mnemonic);
      }

      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final rust = ref.read(votingRustApiProvider);
      final completedBundleIndexes = await _confirmSubmittedDelegations(
        context: context,
        roundPlan: roundPlan,
        progress: progress,
      );
      if (completedBundleIndexes == null) return;
      if (!hasFreshDelegationWork) {
        final refreshedPlans = await _loadPlans(context);
        final refreshedPlan = refreshedPlans.resumePlan;
        final refreshedRoundPlan = refreshedPlans.roundPlan;
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: refreshedPlan.pendingDelegationBundleIndexes.isEmpty
                ? VotingSessionPhase.delegated
                : _phaseForPlans(refreshedRoundPlan),
            resumePlan: refreshedPlan,
            roundPlan: refreshedRoundPlan,
            delegationProgress: progress,
            clearCurrentBundleIndex: true,
          ),
        );
        return;
      }
      for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
        await _awaitDelegationPirPrecomputeIfRunning(context, bundleIndex);
        final bundleTimer = Stopwatch()..start();
        debugPrint(
          '[zcash] Voting: delegation bundle start '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.delegating,
            currentBundleIndex: bundleIndex,
          ),
        );
        rust_wire.SignedDelegationPayloadView? signedDelegationPayload;
        await for (final event
            in rust.buildProveAndSignDelegationPayloadWithProgress(
              dbPath: context.dbPath,
              lightwalletdUrl: context.lightwalletdUrl,
              pirServerUrl: pirEndpoint!.toString(),
              network: context.network,
              roundParams: context.round.toRoundParams(),
              roundName: context.round.title,
              sessionJson: context.round.sessionJson,
              accountUuid: context.accountUuid,
              mnemonic: mnemonic,
              bundleIndex: bundleIndex,
            )) {
          signedDelegationPayload =
              event.signedDelegationPayload ?? signedDelegationPayload;
          final proofProgress = _monotonicProofProgress(
            progress[bundleIndex]?.proofProgress,
            event.proofProgress,
          );
          progress[bundleIndex] = VotingSessionProgress(
            phase: event.phase,
            bundleIndex: bundleIndex,
            proofProgress: proofProgress,
            message: null,
          );
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(delegationProgress: progress),
          );
        }
        debugPrint(
          '[zcash] Voting: delegation proof stream completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'elapsed=${formatElapsedSeconds(bundleTimer.elapsed)}',
        );
        final submission = signedDelegationPayload;
        if (submission == null) {
          throw StateError(
            'Delegation proof completed without submission payload.',
          );
        }
        final result = await _submitAndConfirmDelegation(
          context: context,
          bundleIndex: bundleIndex,
          submission: submission,
        );
        debugPrint(
          '[zcash] Voting: delegation bundle completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'leafIndex=${result.leafIndex} total=${formatElapsedSeconds(bundleTimer.elapsed)}',
        );
        completedBundleIndexes.add(bundleIndex);
        progress[bundleIndex] = VotingSessionProgress(
          phase: 'submitted',
          bundleIndex: bundleIndex,
          message: result.txHash,
        );
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(delegationProgress: progress),
        );
      }

      final resumeTimer = Stopwatch()..start();
      debugPrint(
        '[zcash] Voting: loading resume plan after delegation '
        'round=${context.round.roundId}',
      );
      final refreshedPlans = await _loadPlans(context);
      final refreshedPlan = refreshedPlans.resumePlan;
      final refreshedRoundPlan = refreshedPlans.roundPlan;
      debugPrint(
        '[zcash] Voting: resume plan after delegation loaded '
        'round=${context.round.roundId} '
        'pendingDelegations=${refreshedPlan.pendingDelegationBundleIndexes.length} '
        'pendingVotes=${refreshedPlan.pendingVoteSubmissionKeys.length} '
        'pendingRecovery=${refreshedRoundPlan.pendingRecovery} '
        'elapsed=${formatElapsedSeconds(resumeTimer.elapsed)}',
      );
      final nextPhase =
          refreshedPlan.pendingDelegationBundleIndexes
              .where((index) => !completedBundleIndexes.contains(index))
              .isEmpty
          ? VotingSessionPhase.delegated
          : VotingSessionPhase.readyToDelegate;
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: nextPhase,
          resumePlan: refreshedPlan,
          roundPlan: refreshedRoundPlan,
          delegationProgress: progress,
          clearCurrentBundleIndex: true,
        ),
      );
    });
  }

  Future<void> prepareKeystoneSigning() {
    return _enqueue(_prepareKeystoneSigningUnlocked);
  }

  Future<void> handleKeystoneSignedPczt(List<int> signedPcztBytes) {
    return _enqueue(() async {
      final current = await future;
      final request = current.keystoneSigningRequest;
      if (request == null) {
        _setError('No Keystone signing request is waiting for a signature.');
        return;
      }

      final context = await _loadContext(_roundId);
      final rust = ref.read(votingRustApiProvider);
      final signatures = Map<int, rust_wire.KeystoneSignatureRecord>.from(
        current.keystoneSignatures,
      );
      if (signatures.isEmpty) {
        signatures.addAll(await _loadKeystoneSignatures(context));
      }

      rust_wire.KeystoneSignatureRecord signature;
      try {
        signature = await rust.acceptKeystoneSignature(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          request: request,
          signedPcztBytes: signedPcztBytes,
        );
      } catch (error) {
        _setStateForContext(
          context,
          current.copyWith(
            phase: VotingSessionPhase.keystoneSigning,
            keystoneSignatures: signatures,
            keystoneScanError: _keystoneSignatureScanError(error, request),
          ),
        );
        return;
      }
      signatures[signature.bundleIndex] = signature;
      await _prepareKeystoneSigningUnlocked();
    });
  }

  Future<void> skipRemainingKeystoneBundles() {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      if (!context.isHardwareAccount) {
        _setError(
          'Keystone voting is only available for hardware accounts.',
          context: context,
        );
        return;
      }

      final plan = current.resumePlan ?? context.resumePlan;
      final signatures = await _loadKeystoneSignatures(context);
      final signedPrefixCount = resolvedKeystoneBundlePrefixCount(
        plan: plan,
        signatures: signatures,
      );
      if (signedPrefixCount <= 0) {
        _setError(
          'Sign at least one Keystone bundle before skipping the rest.',
          context: context,
        );
        return;
      }
      if (signedPrefixCount >= plan.bundleCount) {
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.readyToDelegate,
            resumePlan: plan,
            keystoneSignatures: signatures,
            clearKeystoneSigningRequest: true,
            clearKeystoneScanError: true,
            clearCurrentBundleIndex: true,
            clearError: true,
          ),
        );
        return;
      }

      debugPrint(
        '[zcash] Voting: Keystone skipping remaining bundles '
        'round=${context.round.roundId} keepCount=$signedPrefixCount '
        'bundleCount=${plan.bundleCount}',
      );
      await ref
          .read(votingRustApiProvider)
          .deleteSkippedBundles(
            dbPath: context.dbPath,
            walletId: context.accountUuid,
            roundId: context.round.roundId,
            keepCount: signedPrefixCount,
          );
      final refreshedPlans = await _loadPlans(context);
      final refreshedPlan = refreshedPlans.resumePlan;
      final refreshedRoundPlan = refreshedPlans.roundPlan;
      final retainedSignatures = {
        for (final entry in signatures.entries)
          if (entry.key < signedPrefixCount) entry.key: entry.value,
      };
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.readyToDelegate,
          resumePlan: refreshedPlan,
          roundPlan: refreshedRoundPlan,
          keystoneSignatures: retainedSignatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
          clearError: true,
        ),
      );
    });
  }

  Future<void> delegatePendingBundlesWithKeystoneSignatures() {
    return _enqueue(() async {
      var current = await future;
      var context = await _loadContext(_roundId);
      var plan = current.resumePlan ?? context.resumePlan;
      var roundPlan = current.roundPlan ?? context.roundPlan;
      var hasFreshDelegationWork =
          plan.pendingDelegationBundleIndexes.isNotEmpty;
      if (hasFreshDelegationWork && _needsDelegationPreparation(current)) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
        context = await _loadContext(_roundId);
        plan = current.resumePlan ?? context.resumePlan;
        roundPlan = current.roundPlan ?? context.roundPlan;
        hasFreshDelegationWork = plan.pendingDelegationBundleIndexes.isNotEmpty;
      }

      if (!context.isHardwareAccount) {
        _setError(
          'Keystone voting is only available for hardware accounts.',
          context: context,
        );
        return;
      }
      final pirEndpoint = current.pirEndpoint;
      if (hasFreshDelegationWork && pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.', context: context);
        return;
      }

      final signatures = await _loadKeystoneSignatures(context);
      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final completedBundleIndexes = await _confirmSubmittedDelegations(
        context: context,
        roundPlan: roundPlan,
        progress: progress,
      );
      if (completedBundleIndexes == null) return;
      if (!hasFreshDelegationWork) {
        final refreshedPlans = await _loadPlans(context);
        final refreshedPlan = refreshedPlans.resumePlan;
        final refreshedRoundPlan = refreshedPlans.roundPlan;
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: refreshedPlan.pendingDelegationBundleIndexes.isEmpty
                ? VotingSessionPhase.delegated
                : _phaseForPlans(refreshedRoundPlan),
            resumePlan: refreshedPlan,
            roundPlan: refreshedRoundPlan,
            delegationProgress: progress,
            keystoneSignatures: signatures,
            clearKeystoneSigningRequest: true,
            clearKeystoneScanError: true,
            clearCurrentBundleIndex: true,
          ),
        );
        return;
      }

      final rust = ref.read(votingRustApiProvider);
      final hotkeySeed = await _ensureHotkey(context);
      for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
        final signature = signatures[bundleIndex];
        if (signature == null) {
          _setError(
            'Sign delegation bundle ${bundleIndex + 1} with Keystone before submitting.',
            context: context,
          );
          return;
        }

        final bundleTimer = Stopwatch()..start();
        debugPrint(
          '[zcash] Voting: Keystone delegation bundle start '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.delegating,
            keystoneSignatures: signatures,
            clearKeystoneSigningRequest: true,
            clearKeystoneScanError: true,
            currentBundleIndex: bundleIndex,
          ),
        );

        rust_wire.SignedDelegationPayloadView? signedDelegationPayload;
        await for (final event
            in rust
                .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
                  dbPath: context.dbPath,
                  lightwalletdUrl: context.lightwalletdUrl,
                  pirServerUrl: pirEndpoint!.toString(),
                  network: context.network,
                  roundParams: context.round.toRoundParams(),
                  roundName: context.round.title,
                  sessionJson: context.round.sessionJson,
                  accountUuid: context.accountUuid,
                  hotkeySeed: hotkeySeed,
                  bundleIndex: bundleIndex,
                  keystoneSig: signature.sig,
                  keystoneSighash: signature.sighash,
                )) {
          signedDelegationPayload =
              event.signedDelegationPayload ?? signedDelegationPayload;
          final proofProgress = _monotonicProofProgress(
            progress[bundleIndex]?.proofProgress,
            event.proofProgress,
          );
          progress[bundleIndex] = VotingSessionProgress(
            phase: event.phase,
            bundleIndex: bundleIndex,
            proofProgress: proofProgress,
            message: null,
          );
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(delegationProgress: progress),
          );
        }
        debugPrint(
          '[zcash] Voting: Keystone delegation proof stream completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'elapsed=${formatElapsedSeconds(bundleTimer.elapsed)}',
        );
        final submission = signedDelegationPayload;
        if (submission == null) {
          throw StateError(
            'Delegation proof completed without submission payload.',
          );
        }
        _verifyKeystoneDelegationSignature(
          submission: submission,
          signature: signature,
          bundleIndex: bundleIndex,
        );
        final result = await _submitAndConfirmDelegation(
          context: context,
          bundleIndex: bundleIndex,
          submission: submission,
        );
        debugPrint(
          '[zcash] Voting: Keystone delegation bundle completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'leafIndex=${result.leafIndex} total=${formatElapsedSeconds(bundleTimer.elapsed)}',
        );
        completedBundleIndexes.add(bundleIndex);
        progress[bundleIndex] = VotingSessionProgress(
          phase: 'submitted',
          bundleIndex: bundleIndex,
          message: result.txHash,
        );
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(delegationProgress: progress),
        );
      }

      final refreshedPlans = await _loadPlans(context);
      final refreshedPlan = refreshedPlans.resumePlan;
      final refreshedRoundPlan = refreshedPlans.roundPlan;
      final nextPhase =
          refreshedPlan.pendingDelegationBundleIndexes
              .where((index) => !completedBundleIndexes.contains(index))
              .isEmpty
          ? VotingSessionPhase.delegated
          : VotingSessionPhase.readyToDelegate;
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: nextPhase,
          resumePlan: refreshedPlan,
          roundPlan: refreshedRoundPlan,
          delegationProgress: progress,
          keystoneSignatures: signatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
        ),
      );
    });
  }

  Future<_VotingPlans?> _recordBallotIntentsAndReloadPlans({
    required _VotingSessionContext context,
    required VotingSessionState current,
    required List<rust_wire.DraftVote> effectiveDraftVotes,
    required List<int>? allProposalIds,
    required Map<int, int>? proposalOptionCounts,
    required Map<VotingVoteKey, VotingSessionProgress> progress,
  }) async {
    if (effectiveDraftVotes.isEmpty) {
      return _VotingPlans(
        resumePlan: context.resumePlan,
        roundPlan: context.roundPlan,
      );
    }

    // Write durable ballot intent before the cast loop so recovery can resume
    // from the correct choice if the user quits mid-vote.
    final draftVotesByProposal = {
      for (final draftVote in effectiveDraftVotes)
        draftVote.proposalId: draftVote,
    };
    final intentProposalIds = {
      ...?allProposalIds,
      ...draftVotesByProposal.keys,
    }.toList()..sort();
    for (final proposalId in intentProposalIds) {
      final draftVote = draftVotesByProposal[proposalId];
      final numOptions =
          draftVote?.numOptions ?? proposalOptionCounts?[proposalId];
      if (numOptions == null) {
        _setError(
          'Voting proposal details are missing. Retry after the round reloads.',
          cause: StateError('missing numOptions for proposal_id $proposalId'),
          context: context,
        );
        return null;
      }
      await ref
          .read(votingRecoveryServiceProvider)
          .setBallotIntent(
            dbPath: context.dbPath,
            walletId: context.accountUuid,
            roundId: context.round.roundId,
            proposalId: proposalId,
            numOptions: numOptions,
            skipped: draftVote == null,
            choice: draftVote?.choice,
          );
    }
    final refreshedPlans = await _loadPlans(context);
    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        resumePlan: refreshedPlans.resumePlan,
        roundPlan: refreshedPlans.roundPlan,
        voteProgress: progress,
      ),
    );
    return refreshedPlans;
  }

  Future<void> castVotes({
    required List<rust_wire.DraftVote> draftVotes,
    List<int>? allProposalIds,
    Map<int, int>? proposalOptionCounts,
    bool recordBallotIntent = true,
  }) {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);

      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      var plan = context.resumePlan;
      var roundPlan = context.roundPlan;
      final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
      final rust = ref.read(votingRustApiProvider);
      final effectiveDraftVotes = VotingShareTimingPolicy.applyLastMomentMode(
        draftVotes,
        context.round,
      );
      if (recordBallotIntent && effectiveDraftVotes.isNotEmpty) {
        final refreshedPlans = await _recordBallotIntentsAndReloadPlans(
          context: context,
          current: current,
          effectiveDraftVotes: effectiveDraftVotes,
          allProposalIds: allProposalIds,
          proposalOptionCounts: proposalOptionCounts,
          progress: progress,
        );
        if (refreshedPlans == null) return;
        plan = refreshedPlans.resumePlan;
        roundPlan = refreshedPlans.roundPlan;
      }
      var confirmedSubmittedVotes = false;
      for (final work in _pendingVotePollingWork(roundPlan)) {
        final key = VotingVoteKey(
          bundleIndex: work.bundleIndex,
          proposalId: work.proposalId,
        );
        final txHash = work.txHash;
        if (txHash == null) continue;
        final confirmation = await _awaitTxConfirmation(api, txHash);
        if (confirmation == null) {
          _setError(
            'Vote commitment transaction $txHash for bundle '
            '${key.bundleIndex}, proposal ${key.proposalId} is still '
            'unconfirmed after repeated checks. Retry to resume confirmation '
            'before continuing.',
            context: context,
          );
          return;
        }
        if (confirmation.code != 0) {
          throw StateError(
            confirmation.log.isEmpty
                ? 'Vote commitment transaction failed.'
                : confirmation.log,
          );
        }
        await rust.confirmVoteSubmission(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          txHash: txHash,
          events: _txEvents(confirmation),
        );
        progress[key] = VotingSessionProgress(
          phase: 'confirmed',
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          message: txHash,
        );
        confirmedSubmittedVotes = true;
      }
      if (confirmedSubmittedVotes) {
        final refreshedPlans = await _loadPlans(context);
        plan = refreshedPlans.resumePlan;
        roundPlan = refreshedPlans.roundPlan;
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            resumePlan: plan,
            roundPlan: roundPlan,
            voteProgress: progress,
          ),
        );
      }
      final recoveredVoteWork = _pendingRecoveredVoteWork(roundPlan);
      final recoveredVoteKeys = {
        for (final work in recoveredVoteWork) work.key,
      };
      final bundleIndexesByProposal = _plannedCastVoteBundleIndexesByProposal(
        roundPlan,
        effectiveDraftVotes,
      );
      final voteWork = [
        for (final draftVote in effectiveDraftVotes)
          _DraftVoteWork(
            draftVote: draftVote,
            bundleIndexes:
                (bundleIndexesByProposal[draftVote.proposalId] ?? const [])
                    .where(
                      (bundleIndex) => !recoveredVoteKeys.contains(
                        VotingVoteKey(
                          bundleIndex: bundleIndex,
                          proposalId: draftVote.proposalId,
                        ),
                      ),
                    )
                    .toList(),
          ),
      ].where((work) => work.bundleIndexes.isNotEmpty).toList();
      final totalQuestions = recoveredVoteWork.length + voteWork.length;
      final totalBundleTasks =
          recoveredVoteWork.length +
          voteWork.fold<int>(
            0,
            (total, work) => total + work.bundleIndexes.length,
          );
      var completedBundleTasks = 0;
      var completedQuestions = 0;
      debugPrint(
        '[zcash] Voting: cast votes start '
        'round=${context.round.roundId} bundleTasks=$totalBundleTasks '
        'proposals=$totalQuestions '
        'lastMoment=${context.round.isLastMoment()}',
      );
      for (final recoveredWork in recoveredVoteWork) {
        final key = recoveredWork.key;
        final voteTimer = Stopwatch()..start();
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.castingVotes,
            currentBundleIndex: key.bundleIndex,
            currentVoteKey: key,
            voteSubmissionCompletedCount: completedQuestions,
            voteSubmissionTotalCount: totalQuestions,
            voteSubmissionProgress: _voteSubmissionProgress(
              completedBundleTasks: completedBundleTasks,
              totalBundleTasks: totalBundleTasks,
            ),
          ),
        );
        debugPrint(
          '[zcash] Voting: recovering ${recoveredWork.logLabel} '
          'round=${context.round.roundId} bundle=${key.bundleIndex} '
          'proposal=${key.proposalId}',
        );
        final commitments = await rust.recoverVoteCommitment(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
        );
        final Map<int, BigInt> vcTreePositions;
        Set<int>? shareIndexFilter;
        if (recoveredWork.kind == _RecoveredVoteWorkKind.submitVote) {
          vcTreePositions = await _submitVoteCommitments(context, commitments);
        } else {
          final vcTreePosition = recoveredWork.vcTreePosition;
          if (vcTreePosition == null) {
            throw StateError(
              'Missing vote tree position for submitted shares '
              'bundle=${key.bundleIndex} proposal=${key.proposalId}.',
            );
          }
          final shareIndexes = recoveredWork.shareIndexes;
          if (shareIndexes == null || shareIndexes.isEmpty) {
            throw StateError(
              'Missing planned share indexes for submitted shares '
              'bundle=${key.bundleIndex} proposal=${key.proposalId}.',
            );
          }
          final recoveredShareIndexes = {
            for (final commitment in commitments.commitments)
              if (commitment.proposalId == key.proposalId)
                for (final share in commitment.shares) share.shareIndex,
          };
          final missingRecoveredShares = shareIndexes
              .where(
                (shareIndex) => !recoveredShareIndexes.contains(shareIndex),
              )
              .toList(growable: false);
          if (missingRecoveredShares.isNotEmpty) {
            throw StateError(
              'Recovered commitment did not contain planned share(s) '
              '${missingRecoveredShares.join(', ')} '
              'for bundle=${key.bundleIndex} proposal=${key.proposalId}.',
            );
          }
          vcTreePositions = {key.proposalId: vcTreePosition};
          shareIndexFilter = Set<int>.unmodifiable(shareIndexes);
        }
        await _submitCommitmentShares(
          context,
          commitments,
          vcTreePositions: vcTreePositions,
          singleShare: _commitmentsUseSingleShare(commitments),
          shareIndexFilter: shareIndexFilter,
          completedQuestions: completedQuestions,
          totalQuestions: totalQuestions,
          voteSubmissionProgress: _voteSubmissionProgress(
            completedBundleTasks: completedBundleTasks,
            totalBundleTasks: totalBundleTasks,
            currentBundleProgress: 0.95,
          ),
        );
        completedBundleTasks++;
        completedQuestions++;
        progress[key] = VotingSessionProgress(
          phase: 'completed',
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
        );
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.castingVotes,
            voteProgress: progress,
            currentVoteKey: key,
            voteSubmissionCompletedCount: completedQuestions,
            voteSubmissionTotalCount: totalQuestions,
            voteSubmissionProgress: _voteSubmissionProgress(
              completedBundleTasks: completedBundleTasks,
              totalBundleTasks: totalBundleTasks,
            ),
          ),
        );
        debugPrint(
          '[zcash] Voting: recovered ${recoveredWork.logLabel} completed '
          'round=${context.round.roundId} bundle=${key.bundleIndex} '
          'proposal=${key.proposalId} '
          'total=${formatElapsedSeconds(voteTimer.elapsed)}',
        );
      }
      List<int>? hotkeySeed;
      if (voteWork.isNotEmpty) {
        hotkeySeed = await ref
            .read(votingHotkeyStoreProvider)
            .readHotkey(
              accountUuid: context.accountUuid,
              roundId: context.round.roundId,
            );
        if (hotkeySeed == null) {
          _setError(
            'Voting hotkey is missing. Delegate this round before casting votes.',
            cause: const VotingHotkeyUnavailable('missing stored hotkey'),
            context: context,
          );
          return;
        }
      }
      for (final work in voteWork) {
        final draftVote = work.draftVote;
        for (final bundleIndex in work.bundleIndexes) {
          final voteTimer = Stopwatch()..start();
          final key = VotingVoteKey(
            bundleIndex: bundleIndex,
            proposalId: draftVote.proposalId,
          );
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.syncingVoteTree,
              currentBundleIndex: bundleIndex,
              currentVoteKey: key,
              voteSubmissionCompletedCount: completedQuestions,
              voteSubmissionTotalCount: totalQuestions,
              voteSubmissionProgress: _voteSubmissionProgress(
                completedBundleTasks: completedBundleTasks,
                totalBundleTasks: totalBundleTasks,
              ),
            ),
          );
          debugPrint(
            '[zcash] Voting: vote tree sync start '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId}',
          );
          final syncTimer = Stopwatch()..start();
          final anchorHeight = await ref
              .read(votingRustApiProvider)
              .syncVoteTree(
                dbPath: context.dbPath,
                walletId: context.accountUuid,
                roundId: context.round.roundId,
                nodeUrl: context.config.apiBaseUrl.toString(),
              );
          debugPrint(
            '[zcash] Voting: vote tree sync completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} anchorHeight=$anchorHeight '
            'elapsed=${formatElapsedSeconds(syncTimer.elapsed)}',
          );

          final witnessTimer = Stopwatch()..start();
          debugPrint(
            '[zcash] Voting: VAN witness generation start '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} anchorHeight=$anchorHeight',
          );
          final witness = await ref
              .read(votingRustApiProvider)
              .generateVanWitness(
                dbPath: context.dbPath,
                walletId: context.accountUuid,
                roundId: context.round.roundId,
                bundleIndex: bundleIndex,
                anchorHeight: anchorHeight,
              );
          debugPrint(
            '[zcash] Voting: VAN witness generation completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} position=${witness.position} '
            'elapsed=${formatElapsedSeconds(witnessTimer.elapsed)}',
          );
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.castingVotes,
              currentBundleIndex: bundleIndex,
              currentVoteKey: key,
              voteSubmissionCompletedCount: completedQuestions,
              voteSubmissionTotalCount: totalQuestions,
              voteSubmissionProgress: _voteSubmissionProgress(
                completedBundleTasks: completedBundleTasks,
                totalBundleTasks: totalBundleTasks,
              ),
            ),
          );
          debugPrint(
            '[zcash] Voting: ZKP2 commitment stream start '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId}',
          );
          await for (final event
              in ref
                  .read(votingRustApiProvider)
                  .buildVoteCommitmentsWithProgress(
                    dbPath: context.dbPath,
                    walletId: context.accountUuid,
                    network: context.network,
                    roundId: context.round.roundId,
                    bundleIndex: bundleIndex,
                    hotkeySeed: hotkeySeed!,
                    vanWitness: witness,
                    draftVotes: [draftVote],
                  )) {
            final proposalId = event.proposalId;
            if (proposalId != null) {
              final eventKey = VotingVoteKey(
                bundleIndex: event.bundleIndex ?? bundleIndex,
                proposalId: proposalId,
              );
              final proofProgress = _monotonicProofProgress(
                progress[eventKey]?.proofProgress,
                event.proofProgress,
              );
              progress[eventKey] = VotingSessionProgress(
                phase: event.phase,
                bundleIndex: eventKey.bundleIndex,
                proposalId: proposalId,
                proofProgress: proofProgress,
              );
              _setStateForContext(
                context,
                (state.value ?? current).copyWith(
                  phase: VotingSessionPhase.castingVotes,
                  voteProgress: progress,
                  currentVoteKey: eventKey,
                  voteSubmissionCompletedCount: completedQuestions,
                  voteSubmissionTotalCount: totalQuestions,
                  voteSubmissionProgress: _voteSubmissionProgress(
                    completedBundleTasks: completedBundleTasks,
                    totalBundleTasks: totalBundleTasks,
                    currentBundleProgress: proofProgress,
                  ),
                ),
              );
            }
            final commitments = event.commitments;
            if (commitments != null) {
              final vcTreePositions = await _submitVoteCommitments(
                context,
                commitments,
              );
              await _submitCommitmentShares(
                context,
                commitments,
                vcTreePositions: vcTreePositions,
                singleShare: draftVote.singleShare,
                completedQuestions: completedQuestions,
                totalQuestions: totalQuestions,
                voteSubmissionProgress: _voteSubmissionProgress(
                  completedBundleTasks: completedBundleTasks,
                  totalBundleTasks: totalBundleTasks,
                  currentBundleProgress: _monotonicProofProgress(
                    progress[key]?.proofProgress,
                    0.95,
                  ),
                ),
              );
            }
          }
          completedBundleTasks++;
          progress[key] = VotingSessionProgress(
            phase: 'completed',
            bundleIndex: key.bundleIndex,
            proposalId: key.proposalId,
          );
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.castingVotes,
              voteProgress: progress,
              currentVoteKey: key,
              voteSubmissionCompletedCount: completedQuestions,
              voteSubmissionTotalCount: totalQuestions,
              voteSubmissionProgress: _voteSubmissionProgress(
                completedBundleTasks: completedBundleTasks,
                totalBundleTasks: totalBundleTasks,
              ),
            ),
          );
          debugPrint(
            '[zcash] Voting: vote flow completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} '
            'total=${formatElapsedSeconds(voteTimer.elapsed)}',
          );
        }
        completedQuestions++;
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.castingVotes,
            voteProgress: progress,
            voteSubmissionCompletedCount: completedQuestions,
            voteSubmissionTotalCount: totalQuestions,
            voteSubmissionProgress: _voteSubmissionProgress(
              completedBundleTasks: completedBundleTasks,
              totalBundleTasks: totalBundleTasks,
            ),
          ),
        );
      }

      final resumeTimer = Stopwatch()..start();
      debugPrint(
        '[zcash] Voting: loading resume plan after vote flow '
        'round=${context.round.roundId}',
      );
      final refreshedPlans = await _loadPlans(context);
      final refreshedPlan = refreshedPlans.resumePlan;
      final refreshedRoundPlan = refreshedPlans.roundPlan;
      debugPrint(
        '[zcash] Voting: resume plan after vote flow loaded '
        'round=${context.round.roundId} '
        'pendingVotes=${refreshedPlan.pendingVoteSubmissionKeys.length} '
        'unconfirmedShares=${refreshedPlan.unconfirmedShareDelegations.length} '
        'pendingRecovery=${refreshedRoundPlan.pendingRecovery} '
        'elapsed=${formatElapsedSeconds(resumeTimer.elapsed)}',
      );
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.submittingShares,
          resumePlan: refreshedPlan,
          roundPlan: refreshedRoundPlan,
          voteProgress: progress,
          voteSubmissionCompletedCount: completedQuestions,
          voteSubmissionTotalCount: totalQuestions,
          voteSubmissionProgress: _voteSubmissionProgress(
            completedBundleTasks: completedBundleTasks,
            totalBundleTasks: totalBundleTasks,
          ),
          clearCurrentBundleIndex: true,
          clearCurrentVoteKey: true,
        ),
      );
      await _scheduleShareTracking(context, refreshedPlan);
    });
  }

  Future<List<int>> _ensureHotkey(
    _VotingSessionContext context, {
    String? mnemonic,
    bool allowHardwareGeneration = false,
  }) async {
    final existing = await _readStoredHotkey(context);
    if (existing != null && existing.isNotEmpty) return existing;

    final rust = ref.read(votingRustApiProvider);
    late final List<int> hotkey;
    if (context.isHardwareAccount) {
      if (!allowHardwareGeneration) {
        throw const VotingHotkeyUnavailable(
          'missing stored Keystone voting hotkey',
        );
      }
      hotkey = await rust.generateVotingHotkey(network: context.network);
    } else {
      hotkey = await rust.deriveHotkey(
        mnemonic: mnemonic ?? (throw StateError('Missing wallet mnemonic.')),
        roundId: context.round.roundId,
        accountUuid: context.accountUuid,
        network: context.network,
      );
    }
    await ref
        .read(votingHotkeyStoreProvider)
        .writeHotkey(
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          hotkey: hotkey,
        );
    return hotkey;
  }

  Future<List<int>?> _readStoredHotkey(_VotingSessionContext context) async {
    final existing = await ref
        .read(votingHotkeyStoreProvider)
        .readHotkey(
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
        );
    if (existing == null || existing.isEmpty) return null;
    return existing;
  }

  Future<void> _submitCommitmentShares(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments, {
    Map<int, BigInt> vcTreePositions = const {},
    Set<int>? shareIndexFilter,
    required bool singleShare,
    required int completedQuestions,
    required int totalQuestions,
    required double? voteSubmissionProgress,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final helperHealth = ref.read(votingHelperHealthTrackerProvider);
    final serverUrls = context.config.voteServers
        .map((endpoint) => endpoint.url.toString())
        .toList(growable: false);
    if (serverUrls.isEmpty) {
      throw StateError('No vote servers configured for share submission.');
    }

    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final voteEnd = context.round.voteEndTime;
    final voteEndSeconds = voteEnd == null
        ? nowSeconds
        : voteEnd.toUtc().millisecondsSinceEpoch ~/ 1000;
    final lastMomentBufferSeconds = context.round.lastMomentBuffer == null
        ? null
        : BigInt.from(context.round.lastMomentBuffer!.inSeconds);
    final bundleProgressMessage = _bundleProgressMessage(
      bundleIndex: commitments.bundleIndex,
      bundleCount: context.resumePlan.bundleCount,
    );

    for (final commitment in commitments.commitments) {
      final shares = shareIndexFilter == null
          ? commitment.shares
          : commitment.shares
                .where((share) => shareIndexFilter.contains(share.shareIndex))
                .toList(growable: false);
      if (shares.isEmpty) continue;
      final vcTreePosition = vcTreePositions[commitment.proposalId];
      final plans = await rust.planShareSubmissions(
        shareCount: shares.length,
        serverUrls: serverUrls,
        nowSeconds: BigInt.from(nowSeconds),
        voteEndTimeSeconds: BigInt.from(voteEndSeconds),
        lastMomentBufferSeconds: lastMomentBufferSeconds,
        singleShare: singleShare,
      );
      if (plans.length != shares.length) {
        throw StateError(
          'Share submission policy returned ${plans.length} plan(s) for '
          '${shares.length} payload(s).',
        );
      }

      for (var payloadIndex = 0; payloadIndex < shares.length; payloadIndex++) {
        final share = shares[payloadIndex];
        final plan = plans[payloadIndex];
        final acceptedServers = <String>[];
        final targetCount = plan.targetCount
            .clamp(1, serverUrls.length)
            .toInt();
        final candidateServers = _plannedShareServers(
          plannedServers: plan.targetServers,
          fallbackServers: helperHealth.candidateServers(serverUrls),
        );
        final body = await _wireJsonMap(
          rust.voteShareWireJson(
            share: share,
            vcTreePosition: vcTreePosition,
            submitAt: plan.submitAt,
          ),
        );
        _setShareSubmissionProgress(
          context: context,
          bundleIndex: commitments.bundleIndex,
          proposalId: share.proposalId,
          message: bundleProgressMessage,
          completedQuestions: completedQuestions,
          totalQuestions: totalQuestions,
          voteSubmissionProgress: voteSubmissionProgress,
        );
        for (final serverUrl in candidateServers) {
          if (acceptedServers.length >= targetCount) break;
          try {
            debugPrint(
              '[zcash] Voting: submitting share '
              'proposal=${share.proposalId} share=${share.shareIndex} '
              'server=$serverUrl treePosition=${body['tree_position']} '
              'submitAt=${plan.submitAt} target=$targetCount',
            );
            await api.submitShare(
              roundId: context.round.roundId,
              serverUrl: Uri.parse(serverUrl),
              share: body,
            );
            helperHealth.recordSuccess(serverUrl);
            acceptedServers.add(serverUrl);
            debugPrint(
              '[zcash] Voting: share accepted '
              'proposal=${share.proposalId} share=${share.shareIndex} '
              'server=$serverUrl accepted=${acceptedServers.length}/$targetCount',
            );
          } catch (e) {
            debugPrint(
              '[zcash] Voting: share rejected '
              'proposal=${share.proposalId} share=${share.shareIndex} '
              'server=$serverUrl error=$e',
            );
            helperHealth.recordFailure(serverUrl);
            // Recovery retries helpers that did not accept this share.
          }
        }
        if (acceptedServers.isEmpty) {
          throw StateError(
            'No vote server accepted share ${share.shareIndex} '
            'for proposal ${share.proposalId}.',
          );
        }
        if (acceptedServers.length < targetCount) {
          debugPrint(
            '[zcash] Voting: share accepted by fewer helpers than planned '
            'proposal=${share.proposalId} '
            'share=${share.shareIndex} '
            'accepted=${acceptedServers.length}/$targetCount',
          );
        }

        await rust.recordShareDelegation(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: commitments.bundleIndex,
          proposalId: share.proposalId,
          shareIndex: share.shareIndex,
          sentToUrls: acceptedServers,
          submitAt: plan.submitAt,
        );
      }
    }
  }

  String? _bundleProgressMessage({
    required int bundleIndex,
    required int bundleCount,
  }) {
    if (bundleCount <= 1) return null;
    return '${bundleIndex + 1}/$bundleCount';
  }

  double? _voteSubmissionProgress({
    required int completedBundleTasks,
    required int totalBundleTasks,
    double? currentBundleProgress,
  }) {
    if (totalBundleTasks <= 0) return null;
    final currentProgress = (currentBundleProgress ?? 0).clamp(0.0, 1.0);
    return ((completedBundleTasks + currentProgress) / totalBundleTasks)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double? _monotonicProofProgress(double? previous, double? next) {
    final previousValue = previous?.clamp(0.0, 1.0).toDouble();
    final nextValue = next?.clamp(0.0, 1.0).toDouble();
    if (nextValue == null) return previousValue;
    if (previousValue == null) return nextValue;
    return nextValue < previousValue ? previousValue : nextValue;
  }

  List<String> _plannedShareServers({
    required List<String> plannedServers,
    required Iterable<String> fallbackServers,
  }) {
    final ordered = <String>{};
    for (final server in plannedServers) {
      if (server.trim().isNotEmpty) ordered.add(server);
    }
    for (final server in fallbackServers) {
      if (server.trim().isNotEmpty) ordered.add(server);
    }
    return ordered.toList(growable: false);
  }

  void _setShareSubmissionProgress({
    required _VotingSessionContext context,
    required int bundleIndex,
    required int proposalId,
    required String? message,
    required int completedQuestions,
    required int totalQuestions,
    required double? voteSubmissionProgress,
  }) {
    final current = state.value;
    if (current == null) return;
    final key = VotingVoteKey(bundleIndex: bundleIndex, proposalId: proposalId);
    final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
      current.voteProgress,
    );
    progress[key] = VotingSessionProgress(
      phase: 'submitting_shares',
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      message: message,
    );
    _setStateForContext(
      context,
      current.copyWith(
        phase: VotingSessionPhase.castingVotes,
        voteProgress: progress,
        currentVoteKey: key,
        voteSubmissionCompletedCount: completedQuestions,
        voteSubmissionTotalCount: totalQuestions,
        voteSubmissionProgress: voteSubmissionProgress,
      ),
    );
  }

  Future<Map<int, BigInt>> _submitVoteCommitments(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments,
  ) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final vcTreePositions = <int, BigInt>{};
    for (final commitment in commitments.commitments) {
      debugPrint(
        '[zcash] Voting: submitting cast-vote '
        'round=${context.round.roundId} bundle=${commitments.bundleIndex} '
        'proposal=${commitment.proposalId}',
      );
      final result = await api.submitVoteCommitment(
        commitment: await _wireJsonMap(
          rust.voteCommitmentWireJson(commitment: commitment.wire),
        ),
      );
      debugPrint(
        '[zcash] Voting: cast-vote response '
        'proposal=${commitment.proposalId} txHash=${result.txHash} '
        'code=${result.code} log=${result.log}',
      );
      if (result.code != 0) {
        throw StateError(
          result.log.isEmpty
              ? 'Vote commitment transaction was rejected.'
              : result.log,
        );
      }
      if (result.txHash.isEmpty) {
        throw StateError('Vote commitment response did not include tx_hash.');
      }
      await rust.markVoteSubmitted(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
      );

      final confirmation = await _awaitTxConfirmation(api, result.txHash);
      if (confirmation == null) {
        throw StateError(
          'Transaction ${result.txHash} was not confirmed in time.',
        );
      }
      if (confirmation.code != 0) {
        throw StateError(
          confirmation.log.isEmpty
              ? 'Vote commitment transaction failed.'
              : confirmation.log,
        );
      }

      final voteConfirmation = await rust.confirmVoteSubmission(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
        events: _txEvents(confirmation),
      );
      debugPrint(
        '[zcash] Voting: cast-vote confirmed '
        'proposal=${commitment.proposalId} vanPosition=${voteConfirmation.vanLeafPosition} '
        'vcTreePosition=${voteConfirmation.vcTreePosition}',
      );
      vcTreePositions[commitment.proposalId] = voteConfirmation.vcTreePosition;
    }
    return vcTreePositions;
  }

  Future<Map<int, rust_wire.KeystoneSignatureRecord>> _loadKeystoneSignatures(
    _VotingSessionContext context,
  ) async {
    final records = await ref
        .read(votingRustApiProvider)
        .getKeystoneSignatures(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
        );
    return {for (final record in records) record.bundleIndex: record};
  }

  Future<Set<int>?> _confirmSubmittedDelegations({
    required _VotingSessionContext context,
    required rust_wire.RoundPlanView? roundPlan,
    required Map<int, VotingSessionProgress> progress,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final completedBundleIndexes = <int>{};
    final submittedDelegationsByBundle = {
      for (final work
          in roundPlan?.recoveredDelegationWork ??
              const <rust_wire.DelegationRecoveryWorkView>[])
        if (work.kind == 'poll_delegation' && work.txHash != null)
          work.bundleIndex: work.txHash!,
    };
    for (final entry in submittedDelegationsByBundle.entries) {
      final bundleIndex = entry.key;
      final txHash = entry.value;
      final confirmation = await _awaitTxConfirmation(api, txHash);
      if (confirmation == null) {
        _setError(
          'Delegation transaction $txHash for bundle $bundleIndex is still '
          'unconfirmed after repeated checks. Retry to resume confirmation '
          'before continuing.',
          context: context,
        );
        return null;
      }
      if (confirmation.code != 0) {
        throw StateError(
          confirmation.log.isEmpty
              ? 'Delegation transaction failed.'
              : confirmation.log,
        );
      }
      await rust.confirmDelegationSubmission(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: bundleIndex,
        txHash: txHash,
        events: _txEvents(confirmation),
      );
      completedBundleIndexes.add(bundleIndex);
      progress[bundleIndex] = VotingSessionProgress(
        phase: 'confirmed',
        bundleIndex: bundleIndex,
        message: txHash,
      );
    }
    return completedBundleIndexes;
  }

  Future<({String txHash, int leafIndex})> _submitAndConfirmDelegation({
    required _VotingSessionContext context,
    required int bundleIndex,
    required rust_wire.SignedDelegationPayloadView submission,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final submitTimer = Stopwatch()..start();
    debugPrint(
      '[zcash] Voting: submitting delegation '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    final result = await api.submitDelegation(
      submission: await _wireJsonMap(
        rust.delegationSubmissionWireJson(submission: submission),
      ),
    );
    debugPrint(
      '[zcash] Voting: delegation submit response '
      'round=${context.round.roundId} bundle=$bundleIndex '
      'txHash=${result.txHash} code=${result.code} '
      'elapsed=${formatElapsedSeconds(submitTimer.elapsed)}',
    );
    if (result.code != 0) {
      throw StateError(
        result.log.isEmpty
            ? 'Delegation transaction was rejected.'
            : result.log,
      );
    }
    if (result.txHash.isEmpty) {
      throw StateError('Delegation response did not include tx_hash.');
    }
    await rust.markDelegationSubmitted(
      dbPath: context.dbPath,
      walletId: context.accountUuid,
      roundId: context.round.roundId,
      bundleIndex: bundleIndex,
      txHash: result.txHash,
    );
    debugPrint(
      '[zcash] Voting: delegation tx hash stored '
      'round=${context.round.roundId} bundle=$bundleIndex '
      'txHash=${result.txHash}',
    );

    final confirmation = await _awaitTxConfirmation(api, result.txHash);
    if (confirmation == null) {
      throw StateError(
        'Transaction ${result.txHash} was not confirmed in time.',
      );
    }
    if (confirmation.code != 0) {
      throw StateError(
        confirmation.log.isEmpty
            ? 'Delegation transaction failed.'
            : confirmation.log,
      );
    }
    final delegationConfirmation = await rust.confirmDelegationSubmission(
      dbPath: context.dbPath,
      walletId: context.accountUuid,
      roundId: context.round.roundId,
      bundleIndex: bundleIndex,
      txHash: result.txHash,
      events: _txEvents(confirmation),
    );
    return (
      txHash: result.txHash,
      leafIndex: delegationConfirmation.vanLeafPosition,
    );
  }

  Future<VotingTxConfirmation?> _awaitTxConfirmation(
    VotingApiClient api,
    String txHash,
  ) async {
    final polling = ref.read(votingTxConfirmationPollingProvider);
    final attempts = polling.attempts;
    final delay = polling.delay;
    final timer = Stopwatch()..start();
    debugPrint('[zcash] Voting: tx confirmation wait start txHash=$txHash');
    for (var attempt = 0; attempt < attempts; attempt++) {
      final confirmation = await api.getTxConfirmation(txHash);
      if (confirmation != null) {
        debugPrint(
          '[zcash] Voting: tx confirmation found txHash=$txHash '
          'attempt=${attempt + 1} code=${confirmation.code} '
          'elapsed=${formatElapsedSeconds(timer.elapsed)}',
        );
        return confirmation;
      }
      if (attempt + 1 < attempts) {
        if (attempt == 0 || (attempt + 1) % 5 == 0) {
          debugPrint(
            '[zcash] Voting: waiting for tx confirmation '
            'txHash=$txHash attempt=${attempt + 1}/$attempts',
          );
        }
        await Future<void>.delayed(delay);
      }
    }
    debugPrint(
      '[zcash] Voting: tx confirmation wait timed out txHash=$txHash '
      'elapsed=${formatElapsedSeconds(timer.elapsed)}',
    );
    return null;
  }

  Future<void> submitPendingShares() {
    return _enqueue(() async {
      _shareTrackingTimer?.cancel();
      _shareTrackingTimer = null;
      final current = await future;
      final context = await _loadContext(_roundId);
      final plans = await _loadPlans(context);
      final plan = plans.resumePlan;
      final roundPlan = plans.roundPlan;
      _setStateForContext(
        context,
        current.copyWith(
          phase: VotingSessionPhase.submittingShares,
          resumePlan: plan,
          roundPlan: roundPlan,
        ),
      );

      final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
      final rust = ref.read(votingRustApiProvider);
      final helperHealth = ref.read(votingHelperHealthTrackerProvider);
      final configuredServerUrls = context.config.voteServers
          .map((endpoint) => endpoint.url.toString())
          .toList(growable: false);
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final voteEnd = context.round.voteEndTime;
      final voteEndSeconds = voteEnd == null
          ? null
          : voteEnd.millisecondsSinceEpoch ~/ 1000;
      for (final share in plan.unconfirmedShareDelegations) {
        // A share is recoverable once any helper accepted it, but every
        // configured helper should eventually receive it for redundancy.
        final acceptedUrls = LinkedHashSet<String>.of(share.sentToUrls);
        final trackingFlags = await rust.shareTrackingFlags(
          share: share,
          nowSeconds: BigInt.from(nowSeconds),
          voteEndTimeSeconds: voteEndSeconds == null
              ? null
              : BigInt.from(voteEndSeconds),
        );
        final readyForStatusCheck = (trackingFlags & 1) != 0;
        final overdueForRetry = (trackingFlags & 2) != 0;

        if (!readyForStatusCheck && !overdueForRetry) continue;

        if (acceptedUrls.isNotEmpty && readyForStatusCheck) {
          // Helpers can reveal at slightly different times. Confirmation by any
          // helper is enough to advance the local workflow for this share.
          final confirmed = await _shareConfirmedByAnyHelper(
            api: api,
            helperHealth: helperHealth,
            share: share,
            serverUrls: acceptedUrls,
          );
          if (confirmed) {
            await rust.markShareConfirmed(
              dbPath: context.dbPath,
              walletId: context.accountUuid,
              roundId: share.roundId,
              bundleIndex: share.bundleIndex,
              proposalId: share.proposalId,
              shareIndex: share.shareIndex,
            );
            continue;
          }
        }

        if (overdueForRetry && configuredServerUrls.isNotEmpty) {
          final retryUrls = await rust.shareResubmissionServerOrder(
            configuredServerUrls: configuredServerUrls,
            sentToUrls: share.sentToUrls,
          );
          final acceptedRetryUrls = await _resubmitShareToHelpers(
            api: api,
            context: context,
            plan: plan,
            share: share,
            serverUrls: retryUrls,
          );
          final newUrls = acceptedRetryUrls
              .where((url) => !acceptedUrls.contains(url))
              .toList(growable: false);
          if (newUrls.isNotEmpty) {
            await ref
                .read(votingRecoveryServiceProvider)
                .addSentServersForShare(
                  dbPath: context.dbPath,
                  walletId: context.accountUuid,
                  share: share,
                  newUrls: newUrls,
                );
          }
          acceptedUrls.addAll(acceptedRetryUrls);
        }
      }

      final refreshedPlans = await _loadPlans(context);
      final refreshedPlan = refreshedPlans.resumePlan;
      final refreshedRoundPlan = refreshedPlans.roundPlan;
      final hasBlockingWork = hasBlockingRoundRecoveryWork(
        roundPlan: refreshedRoundPlan,
      );
      if (!hasBlockingWork) {
        await _clearPersistedDraftChoices(context);
      }
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: _phaseForPlans(refreshedRoundPlan),
          resumePlan: refreshedPlan,
          roundPlan: refreshedRoundPlan,
        ),
      );
      await _scheduleShareTracking(context, refreshedPlan);
    });
  }

  /// Retries an already-generated share against ordered helpers and returns
  /// only the helpers that accepted the retry.
  Future<List<String>> _resubmitShareToHelpers({
    required VotingApiClient api,
    required _VotingSessionContext context,
    required VotingResumePlan plan,
    required rust_wire.ShareDelegationRecordView share,
    required List<String> serverUrls,
  }) async {
    final rust = ref.read(votingRustApiProvider);
    final key = VotingVoteKey(
      bundleIndex: share.bundleIndex,
      proposalId: share.proposalId,
    );
    final commitmentBundle = plan.commitmentBundleFor(key);
    if (commitmentBundle == null) {
      debugPrint(
        '[zcash] Voting: share resubmit skipped; missing commitment bundle '
        'round=${share.roundId} bundle=${share.bundleIndex} '
        'proposal=${share.proposalId} share=${share.shareIndex}',
      );
      return const [];
    }
    final Map<String, dynamic> body;
    try {
      body = await _wireJsonMap(
        rust.recoveredVoteShareWireJson(
          commitmentBundleJson: commitmentBundle.commitmentBundleJson,
          proposalId: share.proposalId,
          shareIndex: share.shareIndex,
          vcTreePosition: commitmentBundle.vcTreePosition,
          submitAt: BigInt.zero,
        ),
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: share resubmit skipped; invalid recovery payload '
        'round=${share.roundId} bundle=${share.bundleIndex} '
        'proposal=${share.proposalId} share=${share.shareIndex} error=$e',
      );
      return const [];
    }
    final shareId = bytesToHex(share.nullifier);
    final acceptedUrls = <String>[];
    final helperHealth = ref.read(votingHelperHealthTrackerProvider);
    for (final serverUrl in serverUrls) {
      try {
        await api.resubmitShare(
          roundId: context.round.roundId,
          serverUrl: Uri.parse(serverUrl),
          shareId: shareId,
          share: body,
        );
        helperHealth.recordSuccess(serverUrl);
        acceptedUrls.add(serverUrl);
        debugPrint(
          '[zcash] Voting: share resubmitted '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl',
        );
      } catch (e) {
        debugPrint(
          '[zcash] Voting: share resubmit failed '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl error=$e',
        );
        helperHealth.recordFailure(serverUrl);
      }
    }
    return acceptedUrls;
  }

  Future<void> _scheduleShareTracking(
    _VotingSessionContext context,
    VotingResumePlan plan,
  ) async {
    if (!_isCurrentContext(context)) return;
    _shareTrackingTimer?.cancel();
    _shareTrackingTimer = null;
    if (plan.unconfirmedShareDelegations.isEmpty) return;

    final delaySeconds = await ref
        .read(votingRustApiProvider)
        .nextShareTrackingDelaySeconds(
          shares: plan.unconfirmedShareDelegations,
          nowSeconds: BigInt.from(
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ),
        );
    if (delaySeconds == null) return;
    if (!_isCurrentContext(context)) return;
    final delay = Duration(seconds: delaySeconds.toInt());

    // Keep the timer asynchronous so build/state updates settle before
    // recovery polling re-enters the serialized operation queue.
    final scheduledDelay = delay;
    _shareTrackingTimer = Timer(scheduledDelay, () {
      _shareTrackingTimer = null;
      if (!_isCurrentContext(context)) return;
      unawaited(submitPendingShares());
    });
  }

  Future<bool> _shareConfirmedByAnyHelper({
    required VotingApiClient api,
    required VotingHelperHealthTracker helperHealth,
    required rust_wire.ShareDelegationRecordView share,
    required Iterable<String> serverUrls,
  }) async {
    final shareId = bytesToHex(share.nullifier);
    for (final serverUrl in helperHealth.candidateServers(serverUrls)) {
      try {
        final status = await api.getShareStatus(
          roundId: share.roundId,
          serverUrl: Uri.parse(serverUrl),
          shareId: shareId,
        );
        helperHealth.recordSuccess(serverUrl);
        if (status.status == 'confirmed') return true;
      } catch (e) {
        debugPrint(
          '[zcash] Voting: share status check failed '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl error=$e',
        );
        helperHealth.recordFailure(serverUrl);
      }
    }
    return false;
  }

  Future<Uri?> _resolvePirEndpoint(_VotingSessionContext context) async {
    final currentEndpoint = state.value?.pirEndpoint;
    if (currentEndpoint != null) return currentEndpoint;

    try {
      final resolution = await ref
          .read(votingPirResolverProvider)
          .resolve(
            endpoints: context.config.pirEndpointUrls,
            expectedSnapshotHeight: context.round.snapshotHeight,
          );
      return resolution.endpoint;
    } on PirSnapshotNoMatchingEndpoint catch (e) {
      _logPirSnapshotMismatch(context: context, error: e);
      debugPrint(
        '[zcash] Voting: delegation PIR precompute skipped '
        'round=${context.round.roundId} reason=pir-resolution-failed '
        'error=$e',
      );
      return null;
    } catch (e) {
      debugPrint(
        '[zcash] Voting: delegation PIR precompute skipped '
        'round=${context.round.roundId} reason=pir-resolution-failed '
        'error=$e',
      );
      return null;
    }
  }

  Future<void> _runDelegationPirPrecompute({
    required _VotingSessionContext context,
    required Uri pirEndpoint,
    required String mnemonic,
    required int bundleIndex,
  }) async {
    final key = _delegationPirPrecomputeKey(context, bundleIndex);
    final timer = Stopwatch()..start();
    debugPrint(
      '[zcash] Voting: delegation PIR precompute start '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    try {
      final result = await ref
          .read(votingRustApiProvider)
          .precomputeDelegationPir(
            dbPath: context.dbPath,
            lightwalletdUrl: context.lightwalletdUrl,
            pirServerUrl: pirEndpoint.toString(),
            network: context.network,
            roundParams: context.round.toRoundParams(),
            roundName: context.round.title,
            sessionJson: context.round.sessionJson,
            accountUuid: context.accountUuid,
            mnemonic: mnemonic,
            bundleIndex: bundleIndex,
          );
      debugPrint(
        '[zcash] Voting: delegation PIR precompute completed '
        'round=${context.round.roundId} bundle=$bundleIndex '
        'cached=${result.cachedCount} fetched=${result.fetchedCount} '
        'elapsed=${formatElapsedSeconds(timer.elapsed)}',
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: delegation PIR precompute failed '
        'round=${context.round.roundId} bundle=$bundleIndex '
        'elapsed=${formatElapsedSeconds(timer.elapsed)} error=$e '
        'reason=cache-miss',
      );
    } finally {
      _delegationPirPrecomputes.remove(key);
    }
  }

  Future<void> _awaitDelegationPirPrecomputeIfRunning(
    _VotingSessionContext context,
    int bundleIndex,
  ) async {
    final precompute =
        _delegationPirPrecomputes[_delegationPirPrecomputeKey(
          context,
          bundleIndex,
        )];
    if (precompute == null) return;

    debugPrint(
      '[zcash] Voting: waiting for in-flight delegation PIR precompute '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    await precompute;
  }

  static String _delegationPirPrecomputeKey(
    _VotingSessionContext context,
    int bundleIndex,
  ) {
    return '${context.dbPath}|${context.accountUuid}|${context.round.roundId}|$bundleIndex';
  }

  static void _logPirSnapshotMismatch({
    required _VotingSessionContext context,
    required PirSnapshotNoMatchingEndpoint error,
  }) {
    debugPrint(
      '[zcash] Voting: PIR endpoint mismatch '
      'round=${context.round.roundId} '
      'expected=${error.expectedSnapshotHeight} '
      'diagnostics=${_pirDiagnosticsLog(error.diagnostics)}',
    );
  }

  static String _pirSnapshotMismatchMessage(
    PirSnapshotNoMatchingEndpoint error,
  ) {
    final diagnostics = error.diagnostics;
    final expected = formatBlockHeight(error.expectedSnapshotHeight);
    final reportedHeights = diagnostics
        .map((diagnostic) => diagnostic.reportedHeight)
        .nonNulls
        .toSet();

    if (diagnostics.isNotEmpty &&
        diagnostics.every(
          (diagnostic) => diagnostic.status == PirSnapshotEndpointStatus.behind,
        ) &&
        reportedHeights.isNotEmpty) {
      final highest = formatBlockHeight(
        reportedHeights.reduce((left, right) => left > right ? left : right),
      );
      return 'Voting PIR data is not ready for this poll yet. Expected '
          'snapshot block $expected; PIR endpoints report $highest. Retry '
          'once the PIR service catches up.';
    }

    if (diagnostics.isNotEmpty &&
        diagnostics.every(
          (diagnostic) => diagnostic.status == PirSnapshotEndpointStatus.ahead,
        ) &&
        reportedHeights.isNotEmpty) {
      final lowest = formatBlockHeight(
        reportedHeights.reduce((left, right) => left < right ? left : right),
      );
      return 'Configured PIR endpoints are ahead of this poll snapshot. '
          'Expected snapshot block $expected; endpoints report $lowest.';
    }

    if (diagnostics.isNotEmpty &&
        diagnostics.every(
          (diagnostic) =>
              diagnostic.status ==
              PirSnapshotEndpointStatus.timeoutOrNetworkError,
        )) {
      return "Couldn't reach any configured PIR endpoint. Check your network "
          'connection and retry.';
    }

    return 'No PIR endpoint matched this poll snapshot. Expected snapshot '
        'block $expected. Diagnostics: ${_pirDiagnosticsLog(diagnostics)}.';
  }

  static String _pirDiagnosticsLog(
    List<PirSnapshotEndpointDiagnostic> diagnostics,
  ) {
    if (diagnostics.isEmpty) return 'none';
    return diagnostics.map(_pirDiagnosticLog).join('; ');
  }

  static String _pirDiagnosticLog(PirSnapshotEndpointDiagnostic diagnostic) {
    final height = diagnostic.reportedHeight == null
        ? ''
        : ' height=${diagnostic.reportedHeight}';
    final statusCode = diagnostic.httpStatusCode == null
        ? ''
        : ' http=${diagnostic.httpStatusCode}';
    final message = diagnostic.message == null || diagnostic.message!.isEmpty
        ? ''
        : ' message=${diagnostic.message}';
    return '${diagnostic.endpoint} status=${diagnostic.status.name}'
        '$height$statusCode$message';
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final actionGeneration = _sessionGeneration;
    final next = _operation.then((_) async {
      if (!_isCurrentGeneration(actionGeneration)) {
        _logStaleSessionUpdate('queued-action', actionGeneration);
        return;
      }
      final previousActionGeneration = _runningActionGeneration;
      _runningActionGeneration = actionGeneration;
      try {
        await action();
      } on _StaleVotingSessionAction {
        _logStaleSessionUpdate('action');
      } catch (e, st) {
        debugPrint('[zcash] Voting: session action failed: $e\n$st');
        await _cleanupCurrentSessionState(reason: 'action-failed');
        _setError(_actionErrorMessage(e), cause: e);
      } finally {
        _runningActionGeneration = previousActionGeneration;
      }
    });
    _operation = next.catchError((_) {});
    return next;
  }

  static String _actionErrorMessage(Object error) {
    return friendlyVotingErrorMessage(error);
  }

  static bool _needsDelegationPreparation(VotingSessionState state) {
    return state.pirEndpoint == null || state.eligibleWeightZatoshi == null;
  }

  Future<void> _prepareKeystoneSigningUnlocked() async {
    var current = await future;
    var context = await _loadContext(_roundId);
    if (!context.isHardwareAccount) {
      _setError(
        'Keystone voting is only available for hardware accounts.',
        context: context,
      );
      return;
    }
    await _waitUntilWalletReadyForVoting(context);

    if (_needsDelegationPreparation(current)) {
      await _prepareDelegationUnlocked();
      current = await future;
      if (current.phase == VotingSessionPhase.error) return;
      context = await _loadContext(_roundId);
    }

    final plan = current.resumePlan ?? context.resumePlan;
    final roundPlan = current.roundPlan ?? context.roundPlan;
    final signatures = await _loadKeystoneSignatures(context);
    int? nextUnsignedBundle;
    for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
      if (!signatures.containsKey(bundleIndex)) {
        nextUnsignedBundle = bundleIndex;
        break;
      }
    }
    final existingHotkey = await _readStoredHotkey(context);
    if (existingHotkey == null &&
        (signatures.isNotEmpty || roundPlan.hotkeyBound)) {
      throw const VotingHotkeyUnavailable(
        'missing stored Keystone voting hotkey',
      );
    }

    if (nextUnsignedBundle == null) {
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.readyToDelegate,
          isHardwareAccount: true,
          resumePlan: plan,
          keystoneSignatures: signatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
          clearError: true,
        ),
      );
      return;
    }

    final hotkeySeed =
        existingHotkey ??
        await _ensureHotkey(context, allowHardwareGeneration: true);

    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.keystoneSigning,
        isHardwareAccount: true,
        resumePlan: plan,
        keystoneSignatures: signatures,
        currentBundleIndex: nextUnsignedBundle,
        clearKeystoneSigningRequest: true,
        clearKeystoneScanError: true,
        clearError: true,
      ),
    );

    final request = await ref
        .read(votingRustApiProvider)
        .buildKeystoneDelegationRequest(
          dbPath: context.dbPath,
          lightwalletdUrl: context.lightwalletdUrl,
          network: context.network,
          roundParams: context.round.toRoundParams(),
          roundName: context.round.title,
          sessionJson: context.round.sessionJson,
          accountUuid: context.accountUuid,
          hotkeySeed: hotkeySeed,
          bundleIndex: nextUnsignedBundle,
        );

    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.keystoneSigning,
        isHardwareAccount: true,
        eligibleWeightZatoshi: request.eligibleWeightZatoshi,
        keystoneSigningRequest: request,
        keystoneSignatures: signatures,
        currentBundleIndex: nextUnsignedBundle,
        clearKeystoneScanError: true,
        clearError: true,
      ),
    );
  }

  Future<void> _prepareDelegationUnlocked() async {
    final current = await future;
    final context = await _loadContext(_roundId);
    await _waitUntilWalletReadyForVoting(context);
    _setStateForContext(
      context,
      current.copyWith(
        phase: VotingSessionPhase.resolvingPir,
        config: context.config,
        round: context.round,
        resumePlan: context.resumePlan,
        roundPlan: context.roundPlan,
        isHardwareAccount: context.isHardwareAccount,
        clearError: true,
      ),
    );

    final resolver = ref.read(votingPirResolverProvider);
    late final PirSnapshotResolution resolution;
    try {
      resolution = await resolver.resolve(
        endpoints: context.config.pirEndpointUrls,
        expectedSnapshotHeight: context.round.snapshotHeight,
      );
    } on PirSnapshotNoMatchingEndpoint catch (e) {
      _logPirSnapshotMismatch(context: context, error: e);
      _setError(
        _pirSnapshotMismatchMessage(e),
        cause: e,
        pirDiagnostics: e.diagnostics,
        context: context,
      );
      return;
    } catch (e) {
      _setError('Failed to resolve PIR endpoint.', cause: e, context: context);
      return;
    }

    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.loadingWitnesses,
        pirEndpoint: resolution.endpoint,
        pirDiagnostics: resolution.diagnostics,
        config: context.config,
        round: context.round,
        resumePlan: context.resumePlan,
        roundPlan: context.roundPlan,
        isHardwareAccount: context.isHardwareAccount,
      ),
    );

    final bundleSetup = await ref
        .read(votingRustApiProvider)
        .setupDelegationBundles(
          dbPath: context.dbPath,
          lightwalletdUrl: context.lightwalletdUrl,
          network: context.network,
          roundParams: context.round.toRoundParams(),
          roundName: context.round.title,
          sessionJson: context.round.sessionJson,
          accountUuid: context.accountUuid,
        );
    final refreshedPlans = await _loadPlans(context);
    final refreshedPlan = refreshedPlans.resumePlan;
    final refreshedRoundPlan = refreshedPlans.roundPlan;
    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.readyToDelegate,
        resumePlan: refreshedPlan,
        roundPlan: refreshedRoundPlan,
        eligibleWeightZatoshi: bundleSetup.eligibleWeight,
        isHardwareAccount: context.isHardwareAccount,
      ),
    );
  }

  Future<_VotingSessionContext> _loadContext(
    String roundId, {
    bool checkStaleAction = true,
  }) async {
    void checkAction() {
      if (checkStaleAction) _throwIfActionStale();
    }

    checkAction();
    final config = await ref.read(votingConfigProvider.future);
    final api = ref.read(votingApiClientProvider(config.apiBaseUrl));
    final round = VotingRoundDetails.fromStatus(
      await api.getRoundStatus(roundId),
    );
    checkAction();
    final accountUuid = await _accountUuidForSession();
    final isHardwareAccount = await _isHardwareAccountForSession();
    final endpoint = ref.read(votingRpcEndpointConfigProvider);
    final dbPath = await ref.read(votingWalletDbPathProvider).call();
    checkAction();
    final proposals = proposalsFromRound(round);
    final proposalIds = proposals.map((p) => p.id).toList();
    final roundPlan = await ref
        .read(votingRecoveryServiceProvider)
        .loadRoundPlan(
          dbPath: dbPath,
          walletId: accountUuid,
          roundId: round.roundId,
          proposalIds: proposalIds,
        );
    final resumePlan = await ref
        .read(votingRecoveryServiceProvider)
        .loadResumePlan(
          dbPath: dbPath,
          walletId: accountUuid,
          roundId: round.roundId,
          roundPlan: roundPlan,
        );
    checkAction();
    final context = _VotingSessionContext(
      sessionGeneration: _sessionGeneration,
      dbPath: dbPath,
      accountUuid: accountUuid,
      isHardwareAccount: isHardwareAccount,
      network: endpoint.networkName,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      config: config,
      round: round,
      resumePlan: resumePlan,
      roundPlan: roundPlan,
    );
    return context;
  }

  Future<String> _accountUuidForSession() async {
    final existing = _sessionAccountUuid;
    if (existing != null) return existing;

    final accountUuid = await ref.read(votingActiveAccountUuidProvider).call();
    if (accountUuid == null) {
      throw StateError('No active account for voting session.');
    }
    _sessionAccountUuid = accountUuid;
    return accountUuid;
  }

  Future<bool> _isHardwareAccountForSession() async {
    final existing = _sessionIsHardwareAccount;
    if (existing != null) return existing;

    final accountUuid = await _accountUuidForSession();
    final isHardware = await ref
        .read(votingAccountIsHardwareProvider)
        .call(accountUuid);
    _sessionIsHardwareAccount = isHardware;
    return isHardware;
  }

  Future<VotingResumePlan> _loadResumePlan(
    _VotingSessionContext context, {
    rust_wire.RoundPlanView? roundPlan,
  }) {
    return ref
        .read(votingRecoveryServiceProvider)
        .loadResumePlan(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          roundPlan: roundPlan,
        );
  }

  /// Loads the crate planner's round plan.
  Future<rust_wire.RoundPlanView> _loadRoundPlan(
    _VotingSessionContext context,
  ) {
    final proposals = proposalsFromRound(context.round);
    return ref
        .read(votingRecoveryServiceProvider)
        .loadRoundPlan(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          proposalIds: proposals.map((p) => p.id).toList(),
        );
  }

  Future<_VotingPlans> _loadPlans(_VotingSessionContext context) async {
    final roundPlan = await _loadRoundPlan(context);
    final resumePlan = await _loadResumePlan(context, roundPlan: roundPlan);
    return _VotingPlans(resumePlan: resumePlan, roundPlan: roundPlan);
  }

  Future<void> _waitUntilWalletReadyForVoting(
    _VotingSessionContext context,
  ) async {
    var loggedWait = false;
    final sessionInvalidated = _sessionInvalidated.future;
    while (true) {
      _throwIfContextStale(context, 'wallet-sync-wait');
      final readiness = await ref
          .read(votingWalletSyncReadinessCheckerProvider)
          .check(
            dbPath: context.dbPath,
            network: context.network,
            snapshotHeight: context.round.snapshotHeight,
          );
      _throwIfContextStale(context, 'wallet-sync-readiness');
      if (readiness.isReady) {
        _setWalletSyncReadinessState(
          context: context,
          readiness: readiness,
          waiting: false,
        );
        _throwIfContextStale(context, 'wallet-sync-ready');
        return;
      }

      if (!loggedWait) {
        loggedWait = true;
        debugPrint(
          '[zcash] Voting: waiting for wallet scan before voting '
          'round=${context.round.roundId} '
          'scanned=${readiness.scannedHeight} '
          'snapshot=${readiness.snapshotHeight}',
        );
      }
      _setWalletSyncReadinessState(
        context: context,
        readiness: readiness,
        waiting: true,
      );
      _throwIfContextStale(context, 'wallet-sync-start');
      try {
        ref.read(votingWalletSyncStarterProvider).call();
      } catch (e) {
        debugPrint('[zcash] Voting: wallet sync start skipped: $e');
      }
      await Future.any<void>([
        Future<void>.delayed(ref.read(votingWalletSyncPollIntervalProvider)),
        sessionInvalidated,
      ]);
    }
  }

  void _setWalletSyncReadinessState({
    required _VotingSessionContext context,
    required VotingWalletSyncReadiness readiness,
    required bool waiting,
  }) {
    final current = state.value ?? VotingSessionState(roundId: _roundId);
    final phase = waiting
        ? VotingSessionPhase.waitingForWalletSync
        : current.phase == VotingSessionPhase.waitingForWalletSync ||
              current.phase == VotingSessionPhase.error
        ? VotingSessionPhase.idle
        : current.phase;
    _setStateForContext(
      context,
      current.copyWith(
        phase: phase,
        config: context.config,
        round: context.round,
        resumePlan: context.resumePlan,
        roundPlan: context.roundPlan,
        isHardwareAccount: context.isHardwareAccount,
        walletScannedHeight: readiness.scannedHeight,
        walletSnapshotHeight: readiness.snapshotHeight,
        walletChainTipHeight: readiness.chainTipHeight,
        clearWalletSyncReadiness: !waiting,
        clearError: true,
      ),
    );
  }

  void _setError(
    String message, {
    Object? cause,
    List<PirSnapshotEndpointDiagnostic> pirDiagnostics = const [],
    _VotingSessionContext? context,
  }) {
    if (!_canUpdateSessionUi(context)) return;
    final current = state.value ?? VotingSessionState(roundId: _roundId);
    state = AsyncData(
      current.copyWith(
        phase: VotingSessionPhase.error,
        error: VotingSessionError(
          message: message,
          cause: cause,
          pirDiagnostics: pirDiagnostics,
        ),
        pirDiagnostics: pirDiagnostics,
      ),
    );
  }

  bool _setStateForContext(
    _VotingSessionContext context,
    VotingSessionState nextState,
  ) {
    if (!_canUpdateSessionUi(context)) return false;
    state = AsyncData(nextState);
    return true;
  }

  bool _canUpdateSessionUi([_VotingSessionContext? context]) {
    if (_isDisposed) return false;
    final actionGeneration = _runningActionGeneration;
    if (actionGeneration != null && actionGeneration != _sessionGeneration) {
      _logStaleSessionUpdate('ui-action', actionGeneration);
      return false;
    }
    if (context == null) return true;
    if (!_isCurrentContext(context)) {
      _logStaleSessionUpdate('ui-context', context.sessionGeneration, context);
      return false;
    }
    return true;
  }

  bool _isCurrentContext(_VotingSessionContext context) {
    return _isCurrentGeneration(context.sessionGeneration) &&
        _sessionAccountUuid == context.accountUuid;
  }

  bool _isCurrentPrecomputeContext(
    _VotingSessionContext context,
    String expectedAccountUuid,
  ) {
    if (context.accountUuid != expectedAccountUuid) {
      _logStaleSessionUpdate('pir-account', context.sessionGeneration, context);
      return false;
    }
    if (!_isCurrentContext(context)) {
      _logStaleSessionUpdate('pir-context', context.sessionGeneration, context);
      return false;
    }
    return true;
  }

  bool _isCurrentGeneration(int generation) {
    return !_isDisposed && generation == _sessionGeneration;
  }

  bool _activeSubmissionOwnsContext(_VotingSessionContext context) {
    for (final guard in _activeSubmissionGuards) {
      if (guard.accountUuid == context.accountUuid &&
          guard.roundId == context.round.roundId) {
        return true;
      }
    }
    return false;
  }

  void _advanceSessionGeneration() {
    _sessionGeneration++;
    if (!_sessionInvalidated.isCompleted) {
      _sessionInvalidated.complete();
    }
    _sessionInvalidated = Completer<void>();
  }

  void _throwIfActionStale() {
    final actionGeneration = _runningActionGeneration;
    if (actionGeneration != null && actionGeneration != _sessionGeneration) {
      throw const _StaleVotingSessionAction();
    }
  }

  void _throwIfContextStale(_VotingSessionContext context, String reason) {
    if (_isCurrentContext(context)) return;
    _logStaleSessionUpdate(reason, context.sessionGeneration, context);
    throw const _StaleVotingSessionAction();
  }

  void _logStaleSessionUpdate(
    String reason, [
    int? generation,
    _VotingSessionContext? context,
  ]) {
    debugPrint(
      '[zcash] Voting: ignored stale session update '
      'round=$_roundId reason=$reason '
      'generation=${generation ?? _runningActionGeneration} '
      'currentGeneration=$_sessionGeneration '
      'account=${context?.accountUuid} currentAccount=$_sessionAccountUuid',
    );
  }

  /// Clear process-local state for the current round after an action failure.
  ///
  /// The context is reloaded so cleanup follows the session account and DB path.
  /// If that lookup fails, cleanup is skipped because there is no safe key to
  /// clear.
  Future<void> _cleanupCurrentSessionState({required String reason}) async {
    try {
      final context = await _loadContext(_roundId);
      await _resetVotingSessionState(
        rust: ref.read(votingRustApiProvider),
        context: context,
        reason: reason,
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: process-local cleanup skipped '
        'round=$_roundId reason=$reason error=$e',
      );
    }
  }

  /// Clear round-scoped Rust voting caches for this session.
  ///
  /// Passing the round ID intentionally preserves the account-wide vote-tree
  /// sync client while discarding prepared delegation PCZTs for abandoned work.
  /// This cache reset does not abort in-flight proof or vote jobs.
  static Future<void> _resetVotingSessionState({
    required VotingRustApi rust,
    required _VotingSessionContext context,
    required String reason,
  }) async {
    try {
      await rust.resetVotingSessionState(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
      );
      debugPrint(
        '[zcash] Voting: process-local state reset '
        'round=${context.round.roundId} account=${context.accountUuid} '
        'reason=$reason',
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: process-local state reset failed '
        'round=${context.round.roundId} account=${context.accountUuid} '
        'reason=$reason error=$e',
      );
    }
  }

  static VotingSessionPhase _phaseForPlans(rust_wire.RoundPlanView roundPlan) {
    switch (roundPlan.primaryAction) {
      case 'done':
        return VotingSessionPhase.done;
      case 'delegate':
        return VotingSessionPhase.readyToDelegate;
      case 'vote':
        return VotingSessionPhase.readyToVote;
      case 'submit_shares':
        return VotingSessionPhase.submittingShares;
      case 'idle':
      default:
        return VotingSessionPhase.idle;
    }
  }

  Future<void> _clearPersistedDraftChoices(
    _VotingSessionContext context,
  ) async {
    final draftKey = VotingSessionKey(
      roundId: context.round.roundId,
      accountUuid: context.accountUuid,
    );
    final notifier = ref.read(votingDraftProvider(draftKey).notifier);
    final draft = await notifier.ensureLoaded();
    for (final proposalId in draft.choices.keys.toList(growable: false)) {
      notifier.clearChoice(proposalId);
    }
  }

  static Map<int, List<int>> _plannedCastVoteBundleIndexesByProposal(
    rust_wire.RoundPlanView? roundPlan,
    List<rust_wire.DraftVote> draftVotes,
  ) {
    final draftVotesByProposal = {
      for (final draftVote in draftVotes) draftVote.proposalId: draftVote,
    };
    final bundleIndexesByProposal = {
      for (final draftVote in draftVotes) draftVote.proposalId: <int>{},
    };
    for (final step
        in roundPlan?.nextSteps ?? const <rust_wire.NextStepView>[]) {
      if (step.kind != 'cast_vote') continue;
      final draftVote = draftVotesByProposal[step.proposalId];
      if (draftVote == null) continue;
      if (step.choice != draftVote.choice) {
        throw StateError(
          'Round plan choice mismatch for proposal ${step.proposalId}: '
          'planned ${step.choice}, draft ${draftVote.choice}.',
        );
      }
      bundleIndexesByProposal[step.proposalId]?.add(step.bundleIndex);
    }
    return {
      for (final entry in bundleIndexesByProposal.entries)
        entry.key: entry.value.toList()..sort(),
    };
  }

  static List<rust_wire.VoteRecoveryWorkView> _pendingVotePollingWork(
    rust_wire.RoundPlanView? roundPlan,
  ) {
    return [
      for (final work
          in roundPlan?.recoveredVoteWork ??
              const <rust_wire.VoteRecoveryWorkView>[])
        if (work.kind == 'poll_vote') work,
    ];
  }

  static List<_RecoveredVoteWork> _pendingRecoveredVoteWork(
    rust_wire.RoundPlanView? roundPlan,
  ) {
    if (roundPlan == null) return const [];
    return [
      for (final work in roundPlan.recoveredVoteWork)
        if (work.kind == 'submit_vote' || work.kind == 'submit_shares')
          _RecoveredVoteWork(
            kind: work.kind == 'submit_vote'
                ? _RecoveredVoteWorkKind.submitVote
                : _RecoveredVoteWorkKind.submitShares,
            key: VotingVoteKey(
              bundleIndex: work.bundleIndex,
              proposalId: work.proposalId,
            ),
            vcTreePosition: work.vcTreePosition,
            shareIndexes: work.shareIndexes.toSet(),
          ),
    ];
  }

  static bool _commitmentsUseSingleShare(
    rust_wire.SignedVoteCommitmentsView commitments,
  ) {
    return commitments.commitments.isNotEmpty &&
        commitments.commitments.every(
          (commitment) => commitment.shares.length <= 1,
        );
  }

  static Future<Map<String, dynamic>> _wireJsonMap(
    Future<String> wireJson,
  ) async {
    final decoded = jsonDecode(await wireJson);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Rust voting wire JSON is not an object.');
  }

  static List<rust_voting.ApiTxEvent> _txEvents(
    VotingTxConfirmation confirmation,
  ) {
    return [
      for (final event in confirmation.events)
        rust_voting.ApiTxEvent(
          eventType: event.type,
          attributes: [
            for (final attribute in event.attributes)
              rust_voting.ApiTxEventAttribute(
                key: attribute.key,
                value: attribute.value,
              ),
          ],
        ),
    ];
  }

  static void _verifyKeystoneDelegationSignature({
    required rust_wire.SignedDelegationPayloadView submission,
    required rust_wire.KeystoneSignatureRecord signature,
    required int bundleIndex,
  }) {
    final wire = submission.submission;
    if (!_bytesEqual(_decodeBase64(wire.rk), signature.rk) ||
        !_bytesEqual(_decodeBase64(wire.spendAuthSig), signature.sig) ||
        !_bytesEqual(_decodeBase64(wire.sighash), signature.sighash)) {
      throw StateError(
        'Keystone signature did not match delegation bundle $bundleIndex.',
      );
    }
  }

  static String _keystoneSignatureScanError(
    Object error,
    rust_delegate.KeystoneSigningRequest request,
  ) {
    final message = error.toString().toLowerCase();
    if (message.contains('already accepted') ||
        message.contains('already scanned') ||
        message.contains('overwrite')) {
      return 'This Keystone signature was already scanned. Open the next signature on Keystone and scan again.';
    }
    if (message.contains('sighash') || message.contains('different')) {
      return 'This signature is for a different voting bundle. Scan the signature for bundle ${request.bundleIndex + 1}.';
    }
    return 'Could not read the Keystone voting signature. Scan the signed voting QR from Keystone again.';
  }

  static List<int> _decodeBase64(String value) {
    try {
      return base64.decode(value);
    } on FormatException catch (error) {
      throw StateError(
        'Invalid base64 payload from Rust delegation wire: $error',
      );
    }
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

class _DraftVoteWork {
  const _DraftVoteWork({required this.draftVote, required this.bundleIndexes});

  final rust_wire.DraftVote draftVote;
  final List<int> bundleIndexes;
}

enum _RecoveredVoteWorkKind { submitVote, submitShares }

class _RecoveredVoteWork {
  const _RecoveredVoteWork({
    required this.kind,
    required this.key,
    this.vcTreePosition,
    this.shareIndexes,
  });

  final _RecoveredVoteWorkKind kind;
  final VotingVoteKey key;
  final BigInt? vcTreePosition;
  final Set<int>? shareIndexes;

  String get logLabel {
    switch (kind) {
      case _RecoveredVoteWorkKind.submitVote:
        return 'committed cast-vote';
      case _RecoveredVoteWorkKind.submitShares:
        return 'confirmed vote shares';
    }
  }
}

class _VotingSessionContext {
  final int sessionGeneration;
  final String dbPath;
  final String accountUuid;
  final bool isHardwareAccount;
  final String network;
  final String lightwalletdUrl;
  final VotingConfig config;
  final VotingRoundDetails round;
  final VotingResumePlan resumePlan;
  final rust_wire.RoundPlanView roundPlan;

  const _VotingSessionContext({
    required this.sessionGeneration,
    required this.dbPath,
    required this.accountUuid,
    required this.isHardwareAccount,
    required this.network,
    required this.lightwalletdUrl,
    required this.config,
    required this.round,
    required this.resumePlan,
    required this.roundPlan,
  });
}

class _VotingPlans {
  final VotingResumePlan resumePlan;
  final rust_wire.RoundPlanView roundPlan;

  const _VotingPlans({required this.resumePlan, required this.roundPlan});
}

class _StaleVotingSessionAction implements Exception {
  const _StaleVotingSessionAction();
}

class VotingSubmissionSessionNotifier extends VotingSessionNotifier {
  VotingSubmissionSessionNotifier(this._key) : super(_key.roundId);

  final VotingSessionKey _key;

  // This subclass must remain in this library because it overrides private
  // hooks to pin background submissions to their original account.
  @override
  void _registerActiveAccountListener() {}

  @override
  Future<void> _refreshSessionAccountFromActiveAccount() async {
    _sessionAccountUuid = _key.accountUuid;
  }
}

final votingSessionProvider =
    AsyncNotifierProvider.family<
      VotingSessionNotifier,
      VotingSessionState,
      String
    >(VotingSessionNotifier.new);

final votingSubmissionSessionProvider =
    AsyncNotifierProvider.family<
      VotingSubmissionSessionNotifier,
      VotingSessionState,
      VotingSessionKey
    >(VotingSubmissionSessionNotifier.new);

@visibleForTesting
final votingTxConfirmationPollingProvider =
    Provider<VotingTxConfirmationPolling>((ref) {
      return const VotingTxConfirmationPolling(
        attempts: 45,
        delay: Duration(seconds: 2),
      );
    });

@visibleForTesting
class VotingTxConfirmationPolling {
  final int attempts;
  final Duration delay;

  const VotingTxConfirmationPolling({
    required this.attempts,
    required this.delay,
  }) : assert(attempts > 0);
}
