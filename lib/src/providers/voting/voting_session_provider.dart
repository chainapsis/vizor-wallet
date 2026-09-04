import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatting/duration_format.dart';
import '../../features/voting/voting_error_messages.dart';
import '../../services/voting/voting_rust_exception.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_formatters.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/voting.dart' as rust_api;
import '../../rust/api/voting_session.dart' as rust_session;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../app_security_provider.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_share_tracking_registry_provider.dart';
import 'voting_state.dart';
import 'voting_submission_guard_provider.dart';

/// The PCZT value-pool tag for Ironwood actions.
///
/// Ironwood spend authorization uses a RedPallas key derived from the
/// account's Orchard key, but the action remains in the PCZT's Ironwood bundle.
const _ironwoodPcztPool = 1;

/// Cap for independent voting work pools: delegation proofs, vote proofs,
/// share submission, and recovery polling.
const _votingWorkConcurrency = 3;
const _votingBatchProofConcurrency = 3;

/// Wait between passes while the SDK reports a chain step as pending.
const _chainSubmissionRepollDelay = Duration(seconds: 2);

/// How often a running share-tracking pass re-checks Dart-owned stop
/// conditions.
///
/// The pass itself runs in Rust, so this is the granularity at which app lock,
/// round expiry, or disposal reach it. Short enough that a lock screen stops
/// helper traffic promptly, long enough not to spin.
const _shareTrackingCancellationPollInterval = Duration(milliseconds: 250);

/// Whether an authenticated round is still safe for automatic share recovery.
bool shouldTrackPendingVotingShares(VotingRoundDetails round, {DateTime? now}) {
  final status = round.status.trim().toLowerCase();
  if (!const {
    'active',
    'open',
    '1',
    'session_status_active',
  }.contains(status)) {
    return false;
  }
  final voteEnd = round.voteEndTime;
  return voteEnd != null && (now ?? DateTime.now()).isBefore(voteEnd);
}

/// Orchestrates one round's voting lifecycle for the UI.
///
/// The notifier is intentionally recovery-first: every public action reloads
/// persisted Rust recovery state before deciding which bundle/proposal/share
/// work is still safe to run. Network/proof actions are serialized through
/// [_enqueue] so repeated button taps cannot overlap Rust wallet mutations.
class VotingSessionNotifier extends AsyncNotifier<VotingSessionState> {
  VotingSessionNotifier(this._roundId);

  bool get _ownsAutomaticShareTracking => false;

  bool _retainAutomaticShareTracking() => true;

  void _releaseAutomaticShareTracking() {
    _disposeHelperDeliveryContext();
  }

  /// Pins automatic helper-share tracking before a submission job can drop its
  /// destructive-operation guard.
  ///
  /// Returns false when the registry is quiesced and new tracking must not
  /// start. Account delete/reset drain through the registry, so the job must
  /// register first when accepted shares still need confirmation.
  bool pinAutomaticShareTracking() => _retainAutomaticShareTracking();

  Future<void> _operation = Future.value();
  final String _roundId;
  // Foreground delegation may await only this snapshot/PIR-plan stage. Proof
  // warm-up has a separate lifecycle so one slow sibling cannot gate bundles
  // whose SDK-coordinated proofs are already ready.
  final Map<String, Future<void>> _snapshotBundlePrecomputes = {};
  final Map<String, Future<void>> _backgroundDelegationProofPrecomputes = {};
  final Set<String> _completedSnapshotBundlePrecomputes = {};
  final Map<String, Future<List<int>>> _hotkeyEnsures = {};
  Timer? _shareTrackingTimer;
  Future<void>? _activeAutomaticShareTrackingPass;
  final Set<Future<void>> _activeShareTrackingPasses = {};
  VotingHelperDeliveryContext? _helperDeliveryContext;
  final Set<VotingShareTrackingPassHandle> _activeShareTrackingPassHandles = {};
  final Set<VotingRoundSession> _activeRoundSessions = {};
  bool _automaticShareTrackingStopped = false;
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

  VotingHelperDeliveryContext _helperDeliveryContextFor(
    VotingRustApi rust,
    _VotingSessionContext context,
  ) {
    final current = _helperDeliveryContext;
    if (current != null &&
        !current.isDisposed &&
        current.dbPath == context.dbPath &&
        current.accountUuid == context.accountUuid &&
        current.roundId == context.round.roundId) {
      return current;
    }
    if (_activeShareTrackingPassHandles.isNotEmpty) {
      throw StateError(
        'Cannot replace a helper delivery context while tracking is active.',
      );
    }
    current?.dispose();
    final created = rust.createVotingHelperDeliveryContext(
      dbPath: context.dbPath,
      accountUuid: context.accountUuid,
      roundId: context.round.roundId,
    );
    _helperDeliveryContext = created;
    return created;
  }

  void _disposeHelperDeliveryContext() {
    final context = _helperDeliveryContext;
    _helperDeliveryContext = null;
    context?.dispose();
  }

  rust_api.ApiVotingRoundContext _apiRoundContext(
    _VotingSessionContext context,
  ) {
    return rust_api.ApiVotingRoundContext(
      dbPath: context.dbPath,
      lightwalletdUrl: context.lightwalletdUrl,
      network: context.network,
      roundParams: context.roundParams,
      roundName: context.round.title,
      sessionJson: context.round.sessionJson,
      accountUuid: context.accountUuid,
      maxRealNotesPerBundle: null,
      pirLayout: context.config.pirLayout,
    );
  }

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
      roundPlan: context.roundPlan,
      phase: _phaseForPlans(context.roundPlan),
    );
    _shareTrackingTimer?.cancel();
    await _scheduleShareTracking(context, context.roundPlan);
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
    final guardNotifier = ref.read(votingSubmissionGuardProvider.notifier);
    ref.onDispose(() {
      // Snapshot guards before listener teardown. Do not ref.read here:
      // Riverpod forbids using this provider's Ref inside onDispose.
      final context = _currentContext;
      final ownsSubmission =
          context != null &&
          (_guardsOwnContext(_activeSubmissionGuards, context) ||
              _guardsOwnContext(_guardNotifierState(guardNotifier), context));
      _disposeHandlerRegistered = false;
      _activeAccountListenerRegistered = false;
      _submissionGuardListenerRegistered = false;
      // Provider disposal is round-scoped: clear abandoned prepared PCZTs but
      // keep account-wide vote-tree sync state reusable across rounds.
      _isDisposed = true;
      _advanceSessionGeneration();
      _snapshotBundlePrecomputes.clear();
      _backgroundDelegationProofPrecomputes.clear();
      _completedSnapshotBundlePrecomputes.clear();
      _hotkeyEnsures.clear();
      _shareTrackingTimer?.cancel();
      for (final passHandle in _activeShareTrackingPassHandles.toList()) {
        passHandle.cancel();
        passHandle.dispose();
      }
      _activeShareTrackingPassHandles.clear();
      for (final session in _activeRoundSessions.toList()) {
        session.cancel();
        session.dispose();
      }
      _activeRoundSessions.clear();
      _releaseAutomaticShareTracking();
      if (context == null) return;
      if (ownsSubmission) {
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
    _snapshotBundlePrecomputes.clear();
    _backgroundDelegationProofPrecomputes.clear();
    _completedSnapshotBundlePrecomputes.clear();
    _hotkeyEnsures.clear();
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
          roundPlan: context.roundPlan,
          phase: _phaseForPlans(context.roundPlan),
        ),
      );
      unawaited(_scheduleShareTracking(context, context.roundPlan));
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

  Future<BigInt?> refreshEligibleWeight() {
    return _enqueue(_refreshEligibleWeightUnlocked).then((_) {
      final current = state.value;
      final error = current?.error;
      if (error != null && !error.isEligibilityFailure) {
        throw error.cause ?? StateError(error.message);
      }
      return current?.eligibleWeightZatoshi;
    });
  }

  Future<void> ensureWalletReadyForVoting() {
    return _enqueue(() async {
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);
    });
  }

  Future<void> ensureVotingEligibility() {
    return _enqueue(_ensureVotingEligibilityUnlocked);
  }

  void clearVoteSubmissionProgressForJobStart() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        clearVoteSubmissionProgress: true,
        clearCurrentVoteKey: true,
        clearError: true,
      ),
    );
  }

  Future<void> precomputeSnapshotBundles({required String accountUuid}) {
    final key = _snapshotBundlePrecomputeKey(accountUuid);
    final existing = _snapshotBundlePrecomputes[key];
    if (existing != null) return existing;
    final existingProofs = _backgroundDelegationProofPrecomputes[key];
    if (existingProofs != null) return existingProofs;
    if (_completedSnapshotBundlePrecomputes.contains(key)) {
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute skipped '
        'round=$_roundId reason=already-completed',
      );
      return Future<void>.value();
    }

    final precompute = _runSnapshotBundlePrecomputeForAccount(
      accountUuid,
      precomputeKey: key,
    );
    _snapshotBundlePrecomputes[key] = precompute;
    void removeIfCurrent() {
      if (identical(_snapshotBundlePrecomputes[key], precompute)) {
        _snapshotBundlePrecomputes.remove(key);
      }
    }

    unawaited(
      precompute.then<void>(
        (_) => removeIfCurrent(),
        onError: (Object _, StackTrace _) => removeIfCurrent(),
      ),
    );
    return precompute;
  }

  Future<void> _runSnapshotBundlePrecomputeForAccount(
    String accountUuid, {
    required String precomputeKey,
  }) async {
    final releaseBackgroundWork = ref
        .read(votingShareTrackingRegistryProvider)
        .beginBackgroundWork(accountUuid: accountUuid);
    if (releaseBackgroundWork == null) {
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute skipped '
        'round=$_roundId reason=wallet-mutation-in-progress',
      );
      return;
    }
    try {
      await _runRegisteredSnapshotBundlePrecomputeForAccount(
        accountUuid,
        precomputeKey: precomputeKey,
      );
    } finally {
      releaseBackgroundWork();
    }
  }

  Future<void> _runRegisteredSnapshotBundlePrecomputeForAccount(
    String accountUuid, {
    required String precomputeKey,
  }) async {
    final context = await _loadContext(_roundId);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final current = state.value;
    if (current == null || !current.hasConfirmedVotingEligibility) {
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute skipped '
        'round=${context.round.roundId} reason=eligibility-not-confirmed',
      );
      return;
    }
    try {
      await _waitUntilWalletReadyForVoting(
        context,
        stopIfVotingBackgroundWorkQuiesced: true,
      );
    } on _StaleVotingSessionAction {
      return;
    } on _VotingBackgroundWorkQuiesced catch (e) {
      final readiness = e.readiness;
      if (readiness != null) {
        _setWalletSyncReadinessState(
          context: context,
          readiness: readiness,
          waiting: false,
        );
      }
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute skipped '
        'round=${context.round.roundId} reason=wallet-mutation-in-progress',
      );
      return;
    } on _VotingWalletSyncTimeout catch (e) {
      _setWalletSyncReadinessState(
        context: context,
        readiness: e.readiness,
        waiting: false,
      );
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute skipped '
        'round=${context.round.roundId} reason=wallet-sync-timeout error=$e',
      );
      return;
    }
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final pirEndpoint = await _resolvePirEndpoint(context);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    if (pirEndpoint == null) return;
    final bundleCount = await _runSnapshotBundlePrecompute(
      context: context,
      pirEndpoint: pirEndpoint,
    );
    if (bundleCount == null ||
        !_isCurrentPrecomputeContext(context, accountUuid)) {
      return;
    }
    if (context.isHardwareAccount || bundleCount == 0) {
      _completedSnapshotBundlePrecomputes.add(precomputeKey);
      return;
    }
    _startBackgroundDelegationProofPrecompute(
      context: context,
      pirEndpoint: pirEndpoint,
      bundleCount: bundleCount,
      precomputeKey: precomputeKey,
    );
  }

  Future<void> delegatePendingBundles({String? mnemonic}) {
    return _enqueue(() async {
      var current = await future;
      var context = await _loadContext(_roundId);
      if (context.isHardwareAccount) {
        _setError(
          'Sign delegation bundles with Keystone before submitting.',
          context: context,
        );
        return;
      }
      var roundPlan = context.roundPlan;
      if (_needsFreshDelegationPreparation(roundPlan) &&
          _needsDelegationPreparation(current)) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
        context = await _loadContext(_roundId);
        roundPlan = context.roundPlan;
      }

      final delegationBundleIndexes = delegationBundleIndexesNeedingWork(
        roundPlan,
      );
      final hasPendingBundles = delegationBundleIndexes.isNotEmpty;
      final needsPir = _needsFreshDelegationPreparation(roundPlan);
      var pirEndpoint = current.pirEndpoint;
      if (needsPir && pirEndpoint == null) {
        pirEndpoint = await _resolvePirEndpoint(context);
        _throwIfContextStale(context, 'delegation-pir-resolution');
        if (pirEndpoint != null) {
          current = (state.value ?? current).copyWith(pirEndpoint: pirEndpoint);
          _setStateForContext(context, current);
        }
      }
      if (hasPendingBundles) {
        if (needsPir && pirEndpoint == null) {
          _setError('PIR endpoint has not been resolved.', context: context);
          return;
        }
        // Software delegation signs with the account seed at the wallet
        // boundary; the SDK receives only the SpendAuth signature. Keystone
        // signing uses `delegatePendingBundlesWithKeystoneSignatures`.
        if (mnemonic == null || mnemonic.isEmpty) {
          _setError(
            'Software delegation requires this account mnemonic. Unlock this account or switch to one with mnemonic access.',
            context: context,
          );
          return;
        }
        final nextState = (state.value ?? current).copyWith(
          phase: VotingSessionPhase.delegating,
          clearCurrentBundleIndex: true,
          clearError: true,
        );
        _setStateForContext(context, nextState);
        current = nextState;
      }
      final storedHotkeySecret = hasPendingBundles
          ? await _ensureHotkey(context)
          : null;

      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final rust = ref.read(votingRustApiProvider);
      final completedBundleIndexes = <int>{};
      if (hasPendingBundles) {
        await _awaitSnapshotBundlePrecomputeIfRunning(context);
        _throwIfContextStale(context, 'delegation-proof');
        final session = _openRoundSession(
          rust,
          context,
          storedHotkeySecret: storedHotkeySecret,
          pirServerUrls: _delegationPirTransportUrls(state.value ?? current),
        );
        try {
          completedBundleIndexes.addAll(
            await _runDelegationSteps(
              session: session,
              context: context,
              fallbackState: current,
              steps: _delegationStepsFor(roundPlan, delegationBundleIndexes),
              signer: rust_session.ApiDelegationSignerInput(
                kind: rust_session.ApiDelegationSignerKind.mnemonic,
                mnemonic: mnemonic,
                keystoneSig: null,
                keystoneSighash: null,
              ),
              progress: progress,
              logLabel: 'software',
            ),
          );
        } on _StaleVotingSessionAction {
          rethrow;
        } catch (error, stackTrace) {
          await _refreshDelegationPlansAfterBatchFailure(
            context: context,
            fallbackState: current,
            progress: progress,
          );
          Error.throwWithStackTrace(error, stackTrace);
        } finally {
          _closeRoundSession(session);
        }
      }

      final resumeTimer = Stopwatch()..start();
      debugPrint(
        '[zcash] Voting: loading resume plan after delegation '
        'round=${context.round.roundId}',
      );
      final refreshedRoundPlan = await _loadRoundPlan(context);
      debugPrint(
        '[zcash] Voting: resume plan after delegation loaded '
        'round=${context.round.roundId} '
        'pendingDelegations='
        '${delegationBundleIndexesNeedingWork(refreshedRoundPlan).length} '
        'needsVotePolling=${refreshedRoundPlan.needsVotePolling} '
        'pendingRecovery=${refreshedRoundPlan.pendingRecovery} '
        'elapsed=${formatElapsedSeconds(resumeTimer.elapsed)}',
      );
      final nextPhase =
          delegationBundleIndexesNeedingSigning(
            refreshedRoundPlan,
          ).where((index) => !completedBundleIndexes.contains(index)).isEmpty
          ? VotingSessionPhase.delegated
          : VotingSessionPhase.readyToDelegate;
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: nextPhase,
          roundPlan: refreshedRoundPlan,
          delegationProgress: progress,
          clearCurrentBundleIndex: true,
        ),
      );
    }, cleanupProcessStateOnError: false);
  }

  Future<void> prepareKeystoneSigning() {
    return _enqueue(_prepareKeystoneSigningUnlocked);
  }

  Future<void> handleKeystoneBatchSignatures(
    List<VotingKeystoneBatchSignature> batchSignatures,
  ) {
    return _enqueue(() async {
      final current = await future;
      final requests = current.keystoneSigningRequests;
      if (requests.isEmpty) {
        _setError('No Keystone signing request is waiting for a signature.');
        return;
      }

      final context = await _loadContext(_roundId);
      final rust = ref.read(votingRustApiProvider);
      // Always refresh this snapshot. Another attempt may have committed the
      // batch even if Dart did not receive its successful return value.
      final storedSignatures = await _loadKeystoneSignatures(context);

      void reject(String message) {
        _setStateForContext(
          context,
          current.copyWith(
            phase: VotingSessionPhase.keystoneSigning,
            keystoneSignatures: storedSignatures,
            keystoneScanError: message,
          ),
        );
      }

      if (batchSignatures.isEmpty) {
        reject(
          'Keystone returned no voting signatures. Scan the result again.',
        );
        return;
      }

      final requestsByBundle = {
        for (final request in requests) request.bundleIndex: request,
      };
      final seenBundleIndexes = <int>{};
      for (final batchSignature in batchSignatures) {
        final bundleIndex = batchSignature.bundleIndex;
        final request = requestsByBundle[bundleIndex];
        if (request == null || !seenBundleIndexes.add(bundleIndex)) {
          reject(
            'Keystone returned signatures that do not match this voting request. Scan the result for the QR shown here.',
          );
          return;
        }
        if (batchSignature.pool != _ironwoodPcztPool ||
            batchSignature.actionIndex != request.actionIndex ||
            batchSignature.signature.length != 64) {
          reject(
            'Keystone returned an invalid voting signature. Scan the result for the QR shown here.',
          );
          return;
        }
      }

      try {
        // A conflicting tuple fails the whole batch with a typed error; a
        // successful write needs no inspection.
        await rust.storeKeystoneSignaturesBatch(
          dbPath: context.dbPath,
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          signatures: [
            for (final batchSignature in batchSignatures)
              rust_api.ApiKeystoneSignatureInput(
                bundleIndex: batchSignature.bundleIndex,
                sig: Uint8List.fromList(batchSignature.signature),
                sighash: Uint8List.fromList(
                  requestsByBundle[batchSignature.bundleIndex]!.pcztSighash,
                ),
                rk: Uint8List.fromList(
                  requestsByBundle[batchSignature.bundleIndex]!.rk,
                ),
              ),
          ],
        );
      } on VotingRustException catch (error) {
        if (error.kind ==
            rust_wire.VotingErrorKindView.keystoneSignatureConflict) {
          reject(
            'This Keystone result conflicts with a signature already saved for this voting request. Restart Keystone signing and scan the newly generated result.',
          );
          return;
        }
        reject(
          'Could not save the Keystone signatures. Scan the same Keystone result again.',
        );
        return;
      } catch (error) {
        reject(
          'Could not save the Keystone signatures. Scan the same Keystone result again.',
        );
        return;
      }

      final signedBundleIndexes = batchSignatures
          .map((batchSignature) => batchSignature.bundleIndex)
          .toSet();
      final remainingRequests = requests
          .where(
            (request) => !signedBundleIndexes.contains(request.bundleIndex),
          )
          .toList();
      if (remainingRequests.isNotEmpty) {
        final refreshedSignatures = await _loadKeystoneSignatures(context);
        _setStateForContext(
          context,
          current.copyWith(
            phase: VotingSessionPhase.keystoneSigning,
            keystoneSigningRequests: remainingRequests,
            keystoneSignatures: refreshedSignatures,
            currentBundleIndex: remainingRequests.first.bundleIndex,
            clearKeystoneScanError: true,
            clearError: true,
          ),
        );
        return;
      }
      await _prepareKeystoneSigningUnlocked();
    });
  }

  Future<void> reportKeystoneScanError(String message) {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      _setStateForContext(
        context,
        current.copyWith(
          phase: VotingSessionPhase.keystoneSigning,
          keystoneScanError: message,
        ),
      );
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

      final roundPlan = current.roundPlan ?? context.roundPlan;
      final signatures = await _loadKeystoneSignatures(context);
      final signedPrefixCount = resolvedKeystoneBundlePrefixCount(
        roundPlan: roundPlan,
        signatures: signatures,
      );
      if (signedPrefixCount <= 0) {
        _setError(
          'Sign at least one Keystone bundle before skipping the rest.',
          context: context,
        );
        return;
      }
      if (signedPrefixCount >= roundPlanBundleCount(roundPlan)) {
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.readyToDelegate,
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
        'bundleCount=${roundPlanBundleCount(roundPlan)}',
      );
      await ref
          .read(votingRustApiProvider)
          .deleteSkippedBundles(
            dbPath: context.dbPath,
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
            keepCount: signedPrefixCount,
          );
      final bundleSetup = await ref
          .read(votingRustApiProvider)
          .setupDelegationBundles(ctx: _apiRoundContext(context));
      final refreshedRoundPlan = await _loadRoundPlan(context);
      final retainedSignatures = {
        for (final entry in signatures.entries)
          if (entry.key < signedPrefixCount) entry.key: entry.value,
      };
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.readyToDelegate,
          roundPlan: refreshedRoundPlan,
          eligibleWeightZatoshi: bundleSetup.eligibleWeight,
          privacyTrimDroppedValueZatoshi:
              bundleSetup.privacyTrimDroppedValueZatoshi,
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
      if (!context.isHardwareAccount) {
        _setError(
          'Keystone voting is only available for hardware accounts.',
          context: context,
        );
        return;
      }
      var roundPlan = context.roundPlan;
      if (_needsFreshDelegationPreparation(roundPlan) &&
          _needsDelegationPreparation(current)) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
        context = await _loadContext(_roundId);
        roundPlan = context.roundPlan;
      }
      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final completedBundleIndexes = <int>{};
      final delegationBundleIndexes = delegationBundleIndexesNeedingWork(
        roundPlan,
      );
      final hasPendingBundles = delegationBundleIndexes.isNotEmpty;
      final needsPir = _needsFreshDelegationPreparation(roundPlan);
      final signatures = hasPendingBundles
          ? await _loadKeystoneSignatures(context)
          : current.keystoneSignatures;
      final List<int>? storedHotkeySecret;
      if (hasPendingBundles) {
        storedHotkeySecret = await _ensureHotkey(
          context,
          alreadyBound: signatures.isNotEmpty,
        );
      } else {
        storedHotkeySecret = null;
      }
      var pirEndpoint = current.pirEndpoint;
      if (needsPir && pirEndpoint == null) {
        pirEndpoint = await _resolvePirEndpoint(context);
        _throwIfContextStale(context, 'keystone-delegation-pir-resolution');
        if (pirEndpoint != null) {
          current = (state.value ?? current).copyWith(pirEndpoint: pirEndpoint);
          _setStateForContext(context, current);
        }
      }
      if (needsPir && pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.', context: context);
        return;
      }

      final rust = ref.read(votingRustApiProvider);
      for (final bundleIndex in delegationBundleIndexes) {
        if (!signatures.containsKey(bundleIndex)) {
          _setError(
            'Sign delegation bundle ${bundleIndex + 1} with Keystone before submitting.',
            context: context,
          );
          return;
        }
      }
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.delegating,
          keystoneSignatures: signatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
        ),
      );
      if (hasPendingBundles) {
        final session = _openRoundSession(
          rust,
          context,
          storedHotkeySecret: storedHotkeySecret,
          pirServerUrls: _delegationPirTransportUrls(state.value ?? current),
        );
        try {
          completedBundleIndexes.addAll(
            await _runDelegationSteps(
              session: session,
              context: context,
              fallbackState: current,
              steps: _delegationStepsFor(roundPlan, delegationBundleIndexes),
              // The device signatures are durable in the sidecar; the SDK
              // loads the record for each bundle and verifies it against the
              // stored PCZT sighash.
              signer: const rust_session.ApiDelegationSignerInput(
                kind: rust_session.ApiDelegationSignerKind.keystoneStored,
                mnemonic: null,
                keystoneSig: null,
                keystoneSighash: null,
              ),
              progress: progress,
              logLabel: 'Keystone',
            ),
          );
        } on _StaleVotingSessionAction {
          rethrow;
        } catch (error, stackTrace) {
          await _refreshDelegationPlansAfterBatchFailure(
            context: context,
            fallbackState: current,
            progress: progress,
          );
          Error.throwWithStackTrace(error, stackTrace);
        } finally {
          _closeRoundSession(session);
        }
      }

      final refreshedRoundPlan = await _loadRoundPlan(context);
      final nextPhase =
          delegationBundleIndexesNeedingSigning(
            refreshedRoundPlan,
          ).where((index) => !completedBundleIndexes.contains(index)).isEmpty
          ? VotingSessionPhase.delegated
          : VotingSessionPhase.readyToDelegate;
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: nextPhase,
          roundPlan: refreshedRoundPlan,
          delegationProgress: progress,
          keystoneSignatures: signatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
        ),
      );
    }, cleanupProcessStateOnError: false);
  }

  Future<void> castVotes({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
    Map<int, int>? proposalOptionCounts,
  }) {
    final operation = _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);

      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      final rust = ref.read(votingRustApiProvider);
      final draftVotesByProposal = {
        for (final draftVote in draftVotes) draftVote.proposalId: draftVote,
      };
      final intentProposalIds = {
        ...?allProposalIds,
        ...draftVotesByProposal.keys,
      }.toList()..sort();
      final rosterOptionCounts = {
        for (final proposal in proposalsFromRound(context.round))
          proposal.id: proposal.options.length,
      };
      final intents = <rust_session.ApiBallotIntent>[];
      for (final proposalId in intentProposalIds) {
        final draftVote = draftVotesByProposal[proposalId];
        intents.add(
          rust_session.ApiBallotIntent(
            proposalId: proposalId,
            skipped: draftVote == null,
            choice: draftVote?.choice,
          ),
        );
      }

      List<int>? storedHotkeySecret;
      if (draftVotes.isNotEmpty) {
        storedHotkeySecret = await _hotkeyForVoteCasting(context);
        if (storedHotkeySecret == null) {
          _setError(
            'Voting hotkey is missing. Delegate this round before casting votes.',
            cause: const VotingHotkeyUnavailable('missing stored hotkey'),
            context: context,
          );
          return;
        }
      }

      // Write durable ballot intent before any cast work so recovery resumes
      // from the correct choice if the user quits mid-vote. The session
      // re-applies the same intents when it plans, so the two stay equal.
      if (draftVotes.isNotEmpty) {
        for (final intent in intents) {
          final proposalId = intent.proposalId;
          final numOptions =
              draftVotesByProposal[proposalId]?.numOptions ??
              proposalOptionCounts?[proposalId] ??
              rosterOptionCounts[proposalId];
          if (numOptions == null) {
            _setError(
              'Voting proposal details are missing. Retry after the round reloads.',
              cause: StateError(
                'missing numOptions for proposal_id $proposalId',
              ),
            );
            return;
          }
          await ref
              .read(votingRecoveryServiceProvider)
              .setBallotIntent(
                dbPath: context.dbPath,
                accountUuid: context.accountUuid,
                roundId: context.round.roundId,
                proposalId: proposalId,
                numOptions: numOptions,
                skipped: intent.skipped,
                choice: intent.choice,
              );
        }
      }

      var roundPlan = context.roundPlan ?? await _loadRoundPlan(context);
      var totalBundleTasks = 0;
      var totalQuestions = 0;
      var completedBundleTasks = 0;
      var completedQuestions = 0;
      final allVoteKeys = <VotingVoteKey>{};

      void publishState({
        int? currentBundleIndex,
        VotingVoteKey? currentVoteKey,
        List<VotingVoteKey> inFlightKeys = const [],
      }) {
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.castingVotes,
            roundPlan: roundPlan,
            voteProgress: Map<VotingVoteKey, VotingSessionProgress>.of(
              progress,
            ),
            currentBundleIndex: currentBundleIndex,
            currentVoteKey: currentVoteKey,
            clearCurrentBundleIndex: currentBundleIndex == null,
            clearCurrentVoteKey: currentVoteKey == null,
            voteSubmissionCompletedCount: completedQuestions,
            voteSubmissionTotalCount: totalQuestions,
            voteSubmissionProgress: _aggregateVotePipelineProgress(
              progress: progress,
              voteKeys: inFlightKeys,
              completedBundleTasks: completedBundleTasks,
              totalBundleTasks: totalBundleTasks,
            ),
          ),
        );
      }

      // The SDK owns proving, atomic persistence, helper planning, chain
      // episodes, confirmation, and share delivery for every step. Dart
      // drives the plan, projects progress, and keeps cancellation.
      if (draftVotes.isNotEmpty) rust.warmVotingProvingCaches();
      final session = _openRoundSession(
        rust,
        context,
        storedHotkeySecret: storedHotkeySecret,
      );
      try {
        roundPlan = intents.isEmpty
            ? await session.plan()
            : await session.setBallotIntents(intents);
        _throwIfContextStale(context, 'vote-plan');
        final initialSteps = roundPlan.nextSteps.where(_isVoteStep).toList();
        totalBundleTasks = initialSteps.length;
        allVoteKeys.addAll(initialSteps.map(_voteKeyForStep));
        totalQuestions = {
          for (final step in initialSteps) step.proposalId,
        }.length;
        final startTiming = _roundShareTiming(context, _nowSeconds());
        _logVoteTiming(
          'cast votes start '
          'round=${context.round.roundId} bundleTasks=$totalBundleTasks '
          'proposals=$totalQuestions '
          'lastMoment=${startTiming.isLastMoment}',
        );
        if (initialSteps.isNotEmpty) {
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.castingVotes,
              roundPlan: roundPlan,
              voteProgress: progress,
              voteSubmissionCompletedCount: 0,
              voteSubmissionTotalCount: totalQuestions,
              clearCurrentBundleIndex: true,
              clearCurrentVoteKey: true,
            ),
          );
        }
        // A failing bundle does not stop the others: its remaining steps are
        // skipped, the rest of the plan runs, and every failure surfaces at
        // the end so successful bundles keep their durable progress.
        final failures = <_VoteBundleFailure>[];
        final failedBundles = <int>{};
        while (true) {
          _throwIfContextStale(context, 'vote-plan');
          final step = roundPlan.nextSteps
              .where(
                (step) =>
                    _isVoteStep(step) &&
                    !failedBundles.contains(step.bundleIndex),
              )
              .firstOrNull;
          if (step == null) break;
          final stepKeys = <VotingVoteKey>{_voteKeyForStep(step)};
          final stepTimer = Stopwatch()..start();
          publishState(
            currentBundleIndex: step.bundleIndex,
            currentVoteKey: _voteKeyForStep(step),
            inFlightKeys: stepKeys.toList(),
          );
          final rust_wire.RoundStepOutcomeView outcome;
          try {
            outcome = await _advanceStep(
              session,
              context,
              step,
              label: 'vote',
              onProgress: (update) {
                _applyVoteProgress(update, step, stepKeys, progress);
                publishState(
                  currentBundleIndex: step.bundleIndex,
                  currentVoteKey: _voteKeyForStep(step),
                  inFlightKeys: stepKeys.toList(),
                );
              },
            );
          } on _StaleVotingSessionAction {
            rethrow;
          } on _ChainSubmissionCancelled {
            rethrow;
          } catch (error) {
            failedBundles.add(step.bundleIndex);
            failures.add(
              _VoteBundleFailure(
                bundleIndex: step.bundleIndex,
                proposalId: step.proposalId,
                error: error,
              ),
            );
            for (final key in stepKeys) {
              final item = progress[key];
              progress[key] = VotingSessionProgress(
                phase: 'failed',
                bundleIndex: key.bundleIndex,
                proposalId: key.proposalId,
                proofProgress: item?.proofProgress,
                message: error.toString(),
              );
            }
            roundPlan =
                (error is VotingRoundStepFailure ? error.failure.plan : null) ??
                await session.plan();
            _logVoteTiming(
              'step ${step.kind.name} bundle=${step.bundleIndex} '
              'proposal=${step.proposalId} failed '
              'elapsed=${formatElapsedSeconds(stepTimer.elapsed)}: $error',
            );
            publishState(inFlightKeys: allVoteKeys.toList());
            continue;
          }
          roundPlan = outcome.plan;
          final remaining = roundPlan.nextSteps.where(_isVoteStep).toList();
          completedBundleTasks = totalBundleTasks - remaining.length;
          final remainingProposals = {
            for (final remainingStep in remaining) remainingStep.proposalId,
          };
          completedQuestions = totalQuestions - remainingProposals.length;
          if (outcome.disposition ==
              rust_wire.RoundStepDispositionView.advanced) {
            for (final key in stepKeys) {
              if (progress[key]?.phase != 'completed') {
                progress[key] = VotingSessionProgress(
                  phase: 'completed',
                  bundleIndex: key.bundleIndex,
                  proposalId: key.proposalId,
                  proofProgress: 1,
                );
              }
            }
          } else if (remaining.contains(step)) {
            throw StateError(
              'The SDK reported no work for a step its plan still lists: '
              '${step.kind} bundle=${step.bundleIndex} '
              'proposal=${step.proposalId}.',
            );
          }
          _logVoteTiming(
            'step ${step.kind.name} bundle=${step.bundleIndex} '
            'proposal=${step.proposalId} '
            'disposition=${outcome.disposition.name} '
            'elapsed=${formatElapsedSeconds(stepTimer.elapsed)}',
          );
          // Completed steps are already counted in `completedBundleTasks`;
          // listing them again as in-flight would double count.
          publishState();
        }
        if (failures.isNotEmpty) throw _VoteBundleBatchException(failures);
      } on _StaleVotingSessionAction {
        rethrow;
      } catch (_) {
        for (final key in allVoteKeys) {
          final item = progress[key];
          if (item != null && item.phase != 'completed') {
            progress[key] = VotingSessionProgress(
              phase: 'failed',
              bundleIndex: key.bundleIndex,
              proposalId: key.proposalId,
              proofProgress: item.proofProgress,
              message: item.message,
            );
          }
        }
        roundPlan = await _loadRoundPlan(context);
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            roundPlan: roundPlan,
            voteProgress: progress,
          ),
        );
        await _scheduleShareTracking(context, roundPlan);
        rethrow;
      } finally {
        _closeRoundSession(session);
      }

      final resumeTimer = Stopwatch()..start();
      debugPrint(
        '[zcash] Voting: loading resume plan after vote flow '
        'round=${context.round.roundId}',
      );
      final refreshedRoundPlan = await _loadRoundPlan(context);
      final hasBlockingWork = hasBlockingRoundRecoveryWork(refreshedRoundPlan);
      if (!hasBlockingWork) {
        await _clearPersistedDraftChoices(context);
      }
      debugPrint(
        '[zcash] Voting: resume plan after vote flow loaded '
        'round=${context.round.roundId} '
        'needsVotePolling=${refreshedRoundPlan.needsVotePolling} '
        'unconfirmedShares=${refreshedRoundPlan.hasUnconfirmedShares} '
        'pendingRecovery=${refreshedRoundPlan.pendingRecovery} '
        'elapsed=${formatElapsedSeconds(resumeTimer.elapsed)}',
      );
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: _phaseForPlans(refreshedRoundPlan),
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
      await _scheduleShareTracking(context, refreshedRoundPlan);
    }, cleanupProcessStateOnError: false);
    return operation;
  }

  static bool _isVoteStep(rust_wire.NextStepView step) {
    return switch (step.kind) {
      rust_wire.NextStepKind.castVote ||
      rust_wire.NextStepKind.advanceVote ||
      rust_wire.NextStepKind.advanceVoteBatch ||
      rust_wire.NextStepKind.submitShares => true,
      rust_wire.NextStepKind.delegate ||
      rust_wire.NextStepKind.advanceDelegation ||
      rust_wire.NextStepKind.advanceImportedDelegation ||
      rust_wire.NextStepKind.confirmShare => false,
    };
  }

  static bool _isDelegationStep(rust_wire.NextStepView step) {
    return switch (step.kind) {
      rust_wire.NextStepKind.delegate ||
      rust_wire.NextStepKind.advanceDelegation ||
      rust_wire.NextStepKind.advanceImportedDelegation => true,
      _ => false,
    };
  }

  static VotingVoteKey _voteKeyForStep(rust_wire.NextStepView step) {
    return VotingVoteKey(
      bundleIndex: step.bundleIndex,
      proposalId: step.proposalId,
    );
  }

  /// Projects one SDK step progress event into the per-vote progress map.
  ///
  /// Phase labels stay the ones the UI already reads: proof stages while
  /// proving, `submitting` once helper plans are durable, `submitted` or
  /// `confirmed` after the chain episode, and `completed` after delivery.
  void _applyVoteProgress(
    rust_wire.RoundStepProgressView update,
    rust_wire.NextStepView step,
    Set<VotingVoteKey> stepKeys,
    Map<VotingVoteKey, VotingSessionProgress> progress,
  ) {
    switch (update.kind) {
      case rust_wire.RoundStepProgressKind.voteCommit:
        final bundleIndex = update.bundleIndex;
        final proposalId = update.proposalId;
        final stage = update.voteCommitStage;
        if (bundleIndex == null || proposalId == null || stage == null) return;
        final key = VotingVoteKey(
          bundleIndex: bundleIndex,
          proposalId: proposalId,
        );
        stepKeys.add(key);
        progress[key] = VotingSessionProgress(
          phase: _voteStageLabel(stage),
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          proofProgress: _monotonicProofProgress(
            progress[key]?.proofProgress,
            update.proofProgress ??
                switch (stage) {
                  rust_wire.VoteCommitStageKind.proofStarting => 0.0,
                  rust_wire.VoteCommitStageKind.sharePayloadsBuilding ||
                  rust_wire.VoteCommitStageKind.signing => 1.0,
                  rust_wire.VoteCommitStageKind.proofProgress => null,
                },
          ),
        );
      case rust_wire.RoundStepProgressKind.helperPlansPrepared:
        for (final voteKey in update.voteKeys) {
          final key = VotingVoteKey(
            bundleIndex: voteKey.bundleIndex,
            proposalId: voteKey.proposalId,
          );
          stepKeys.add(key);
          progress[key] = VotingSessionProgress(
            phase: 'submitting',
            bundleIndex: key.bundleIndex,
            proposalId: key.proposalId,
            proofProgress: 1,
          );
        }
      case rust_wire.RoundStepProgressKind.chainOutcome:
        final chainOutcome = update.chainOutcome;
        if (chainOutcome == null) return;
        final confirmed =
            chainOutcome.kind == rust_wire.ChainSubmissionOutcomeKind.confirmed;
        for (final key in stepKeys.where(
          (key) => key.bundleIndex == step.bundleIndex,
        )) {
          progress[key] = VotingSessionProgress(
            phase: confirmed ? 'confirmed' : 'submitted',
            bundleIndex: key.bundleIndex,
            proposalId: key.proposalId,
            proofProgress: 1,
            message:
                chainOutcome.transactionHash ??
                chainOutcome.candidateTransactionHash,
          );
        }
      case rust_wire.RoundStepProgressKind.shareOutcome:
        final delivery = update.shareDelivery;
        if (delivery == null) return;
        final key = VotingVoteKey(
          bundleIndex: delivery.vote.bundleIndex,
          proposalId: delivery.vote.proposalId,
        );
        stepKeys.add(key);
        progress[key] = VotingSessionProgress(
          phase: 'completed',
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          proofProgress: 1,
        );
      case rust_wire.RoundStepProgressKind.selected ||
          rust_wire.RoundStepProgressKind.delegation ||
          rust_wire.RoundStepProgressKind.treeSynced ||
          rust_wire.RoundStepProgressKind.shareConfirmed:
        break;
    }
  }

  static String _voteStageLabel(rust_wire.VoteCommitStageKind stage) {
    return switch (stage) {
      rust_wire.VoteCommitStageKind.proofStarting => 'building_proof',
      rust_wire.VoteCommitStageKind.proofProgress => 'proof_progress',
      rust_wire.VoteCommitStageKind.sharePayloadsBuilding =>
        'building_share_payloads',
      rust_wire.VoteCommitStageKind.signing => 'signing',
    };
  }

  static String _delegationPhaseLabel(rust_wire.DelegationProgressKind kind) {
    return switch (kind) {
      rust_wire.DelegationProgressKind.selectingNotes => 'selecting_notes',
      rust_wire.DelegationProgressKind.pcztBuilding ||
      rust_wire.DelegationProgressKind.pcztBuilt => 'building_pczt',
      rust_wire.DelegationProgressKind.proofStarting => 'building_proof',
      rust_wire.DelegationProgressKind.waitingForExistingProof =>
        'waiting_for_existing_proof',
      rust_wire.DelegationProgressKind.proofProgress ||
      rust_wire.DelegationProgressKind.proofComplete => 'proof_progress',
      rust_wire.DelegationProgressKind.signingPayload => 'signing_payload',
      rust_wire.DelegationProgressKind.payloadReady => 'payload_ready',
    };
  }

  static double? _delegationPhaseProgress(
    rust_wire.DelegationProgressKind kind,
    double? proofProgress,
  ) {
    return switch (kind) {
      rust_wire.DelegationProgressKind.proofStarting => 0.0,
      rust_wire.DelegationProgressKind.proofProgress => proofProgress,
      rust_wire.DelegationProgressKind.proofComplete ||
      rust_wire.DelegationProgressKind.signingPayload => 1.0,
      _ => null,
    };
  }

  /// Opens an SDK round session for this account and round.
  ///
  /// Chain and helper traffic follow the wallet's network route inside Rust;
  /// PIR and vote-tree traffic use the SDK's direct transport.
  VotingRoundSession _openRoundSession(
    VotingRustApi rust,
    _VotingSessionContext context, {
    List<int>? storedHotkeySecret,
    List<String> pirServerUrls = const [],
  }) {
    final proposals = proposalsFromRound(context.round);
    final session = rust.openRoundSession(
      ctx: _apiRoundContext(context),
      chainEndpoints: context.config.apiServers.all
          .map(_transportUrl)
          .toList(growable: false),
      pirServerUrls: pirServerUrls,
      proposals: [
        for (final proposal in proposals)
          rust_session.ApiProposalRosterEntry(
            proposalId: proposal.id,
            numOptions: proposal.options.length,
          ),
      ],
      storedHotkeySecret: storedHotkeySecret,
      operationEpoch: BigInt.from(context.sessionGeneration),
    );
    _activeRoundSessions.add(session);
    return session;
  }

  void _closeRoundSession(VotingRoundSession session) {
    _activeRoundSessions.remove(session);
    session.dispose();
  }

  rust_session.ApiRoundHostContext _hostContext(_VotingSessionContext context) {
    final start = context.round.ceremonyStart;
    final end = context.round.voteEndTime;
    return rust_session.ApiRoundHostContext(
      configuredHelperUrls: _configuredHelperTransportUrls(context),
      nowSeconds: BigInt.from(_nowSeconds()),
      ceremonyStartSeconds: start == null
          ? null
          : BigInt.from(_unixSeconds(start)),
      voteEndTimeSeconds: end == null ? null : BigInt.from(_unixSeconds(end)),
      voteTreeNodeUrls: context.config.apiServers.all
          .map(_transportUrl)
          .toList(growable: false),
      maxProofConcurrency: _votingBatchProofConcurrency,
    );
  }

  /// Runs one planned step through the SDK, re-invoking it while the chain
  /// or helper work is pending. Returns the outcome that ended the step.
  ///
  /// A `pending` disposition waits the re-poll delay or until the session is
  /// invalidated; `cancelled` and `chainTerminal` become exceptions so the
  /// caller's failure path runs.
  Future<rust_wire.RoundStepOutcomeView> _advanceStep(
    VotingRoundSession session,
    _VotingSessionContext context,
    rust_wire.NextStepView step, {
    required String label,
    required void Function(rust_wire.RoundStepProgressView progress) onProgress,
    rust_session.ApiDelegationSignerInput? signer,
  }) async {
    while (true) {
      _throwIfContextStale(context, '$label-advance');
      rust_session.ApiRoundStepEvent? terminal;
      await for (final event in session.advanceStep(
        step: step,
        host: _hostContext(context),
        signer: signer,
      )) {
        _throwIfContextStale(context, '$label-progress');
        final progress = event.progress;
        if (progress != null) onProgress(progress);
        if (event.kind == rust_session.ApiRoundStepEventKind.result) {
          terminal = event;
        }
      }
      if (terminal == null) {
        throw StateError('Round step completed without a result.');
      }
      final failure = terminal.failure;
      if (failure != null) throw VotingRoundStepFailure(step, failure);
      final outcome = terminal.outcome;
      if (outcome == null) {
        throw StateError('Round step returned neither outcome nor failure.');
      }
      switch (outcome.disposition) {
        case rust_wire.RoundStepDispositionView.pending:
          // The SDK already re-polled a tracking submission and escalated to
          // exact-tree recovery once. Keep waiting only while the chain is
          // still tracking; a submission stuck in recovery surfaces so the
          // user can retry later.
          if (outcome.chainOutcome?.kind !=
              rust_wire.ChainSubmissionOutcomeKind.tracking) {
            throw VotingChainPendingOutcome(step, outcome);
          }
          await Future.any<void>([
            Future<void>.delayed(_chainSubmissionRepollDelay),
            _sessionInvalidated.future,
          ]);
          continue;
        case rust_wire.RoundStepDispositionView.cancelled:
          _throwIfContextStale(context, '$label-cancelled');
          throw const _ChainSubmissionCancelled();
        case rust_wire.RoundStepDispositionView.chainTerminal:
          throw VotingChainTerminalOutcome(step, outcome);
        case rust_wire.RoundStepDispositionView.advanced ||
            rust_wire.RoundStepDispositionView.noWork:
          return outcome;
      }
    }
  }

  /// Advances every delegation step in `steps` through the SDK, bundles
  /// concurrently, publishing per-bundle progress.
  Future<Set<int>> _runDelegationSteps({
    required VotingRoundSession session,
    required _VotingSessionContext context,
    required VotingSessionState fallbackState,
    required List<rust_wire.NextStepView> steps,
    required rust_session.ApiDelegationSignerInput signer,
    required Map<int, VotingSessionProgress> progress,
    required String logLabel,
  }) async {
    final batchTimer = Stopwatch()..start();
    final stepsByBundle = {for (final step in steps) step.bundleIndex: step};
    final bundleIndexes = stepsByBundle.keys.toList()..sort();

    void publishProgress(VotingSessionProgress update) {
      final bundleIndex = update.bundleIndex;
      if (bundleIndex == null) return;
      progress[bundleIndex] = update;
      _setStateForContext(
        context,
        (state.value ?? fallbackState).copyWith(
          phase: VotingSessionPhase.delegating,
          delegationProgress: Map<int, VotingSessionProgress>.of(progress),
          clearCurrentBundleIndex: true,
        ),
      );
    }

    final outcomes = await _runBoundedBundleWork(
      bundleIndexes,
      concurrency: _votingWorkConcurrency,
      work: (bundleIndex) async {
        final step = stepsByBundle[bundleIndex]!;
        final pipelineTimer = Stopwatch()..start();
        debugPrint(
          '[zcash] Voting: $logLabel delegation bundle start '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        final outcome = await _advanceStep(
          session,
          context,
          step,
          label: '$logLabel-delegation',
          signer: signer,
          onProgress: (update) {
            switch (update.kind) {
              case rust_wire.RoundStepProgressKind.delegation:
                final kind = update.delegationProgress;
                if (kind == null) return;
                publishProgress(
                  VotingSessionProgress(
                    phase: _delegationPhaseLabel(kind),
                    bundleIndex: bundleIndex,
                    proofProgress: _monotonicProofProgress(
                      progress[bundleIndex]?.proofProgress,
                      _delegationPhaseProgress(kind, update.proofProgress),
                    ),
                  ),
                );
              case rust_wire.RoundStepProgressKind.chainOutcome:
                final chainOutcome = update.chainOutcome;
                if (chainOutcome?.kind ==
                    rust_wire.ChainSubmissionOutcomeKind.confirmed) {
                  publishProgress(
                    VotingSessionProgress(
                      phase: 'confirmed',
                      bundleIndex: bundleIndex,
                      message: chainOutcome!.transactionHash,
                    ),
                  );
                }
              default:
                break;
            }
          },
        );
        if (outcome.disposition == rust_wire.RoundStepDispositionView.noWork) {
          throw StateError(
            'Delegation bundle $bundleIndex is no longer in the round plan.',
          );
        }
        debugPrint(
          '[zcash] Voting: $logLabel delegation bundle completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'txHash=${outcome.chainOutcome?.transactionHash} '
          'leafIndex=${outcome.chainOutcome?.finalVanPosition} '
          'total=${formatElapsedSeconds(pipelineTimer.elapsed)}',
        );
        return bundleIndex;
      },
    );

    final failures = <_DelegationBundleFailure>[];
    final completed = <int>{};
    for (final bundleIndex in bundleIndexes) {
      final outcome = outcomes[bundleIndex]!;
      final error = outcome.error;
      if (error != null) {
        publishProgress(
          VotingSessionProgress(
            phase: 'failed',
            bundleIndex: bundleIndex,
            message: error.toString(),
          ),
        );
        failures.add(
          _DelegationBundleFailure(
            bundleIndex: bundleIndex,
            stage: 'step',
            error: error,
          ),
        );
      } else {
        completed.add(outcome.value!);
      }
    }
    for (final failure in failures) {
      if (failure.error is _StaleVotingSessionAction) throw failure.error;
    }
    if (failures.isNotEmpty) throw _DelegationBundleBatchException(failures);
    debugPrint(
      '[zcash] Voting: $logLabel delegation batch completed '
      'round=${context.round.roundId} bundles=${bundleIndexes.length} '
      'elapsed=${formatElapsedSeconds(batchTimer.elapsed)}',
    );
    return completed;
  }

  /// Delegation steps the plan lists for the given bundles. A plan that
  /// predates the SDK planner yields synthetic `Delegate` steps, which the
  /// SDK validates against its own fresh plan.
  static List<rust_wire.NextStepView> _delegationStepsFor(
    rust_wire.RoundPlanView? roundPlan,
    List<int> bundleIndexes,
  ) {
    final wanted = bundleIndexes.toSet();
    final planned = [
      for (final step
          in roundPlan?.nextSteps ?? const <rust_wire.NextStepView>[])
        if (_isDelegationStep(step) && wanted.contains(step.bundleIndex)) step,
    ];
    final covered = {for (final step in planned) step.bundleIndex};
    return [
      ...planned,
      for (final bundleIndex in bundleIndexes)
        if (!covered.contains(bundleIndex))
          rust_wire.NextStepView(
            kind: rust_wire.NextStepKind.delegate,
            bundleIndex: bundleIndex,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
    ];
  }

  Future<List<int>?> _hotkeyForVoteCasting(
    _VotingSessionContext context,
  ) async {
    final existing = await _readStoredHotkey(context);
    if (existing != null) return existing;
    try {
      return await _ensureHotkey(context);
    } on VotingHotkeyUnavailable {
      return null;
    }
  }

  Future<List<int>> _ensureHotkey(
    _VotingSessionContext context, {
    bool alreadyBound = false,
  }) {
    final key = _hotkeyEnsureKey(context);
    final inFlight = _hotkeyEnsures[key];
    if (inFlight != null) return inFlight;

    late final Future<List<int>> ensureFuture;
    ensureFuture = _ensureHotkeyUncached(context, alreadyBound: alreadyBound)
        .whenComplete(() {
          if (identical(_hotkeyEnsures[key], ensureFuture)) {
            _hotkeyEnsures.remove(key);
          }
        });
    _hotkeyEnsures[key] = ensureFuture;
    return ensureFuture;
  }

  Future<List<int>> _ensureHotkeyUncached(
    _VotingSessionContext context, {
    required bool alreadyBound,
  }) async {
    final existing = await _readStoredHotkey(context);
    if (existing != null && existing.isNotEmpty) return existing;
    if (alreadyBound || _hotkeyAlreadyBound(context)) {
      throw const VotingHotkeyUnavailable('missing stored voting hotkey');
    }

    final rust = ref.read(votingRustApiProvider);
    final hotkey = await rust.generateVotingHotkey(network: context.network);
    final storedAfterGeneration = await _readStoredHotkey(context);
    if (storedAfterGeneration != null && storedAfterGeneration.isNotEmpty) {
      return storedAfterGeneration;
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

  static String _hotkeyEnsureKey(_VotingSessionContext context) {
    return '${context.accountUuid}:${context.round.roundId}';
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

  bool _hotkeyAlreadyBound(_VotingSessionContext context) {
    if (context.roundPlan?.hotkeyBound ?? false) return true;
    return context.roundPlan?.hotkeyBound ?? false;
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

  void _logVoteTiming(String message) {
    debugPrint('[zcash] Voting: $message');
  }

  double? _aggregateVotePipelineProgress({
    required Map<VotingVoteKey, VotingSessionProgress> progress,
    required List<VotingVoteKey> voteKeys,
    required int completedBundleTasks,
    required int totalBundleTasks,
  }) {
    if (totalBundleTasks <= 0) return null;
    var pipelineProgress = 0.0;
    for (final key in voteKeys) {
      final item = progress[key];
      pipelineProgress += switch (item?.phase) {
        'completed' => 1,
        'submitting_shares' => 0.95,
        'confirmed' => 0.95,
        'submitted' => 0.85,
        'failed' => 0,
        _ => (item?.proofProgress ?? 0).clamp(0.0, 1.0) * 0.8,
      };
    }
    return ((completedBundleTasks + pipelineProgress) / totalBundleTasks)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Future<Map<int, rust_wire.KeystoneSignatureRecord>> _loadKeystoneSignatures(
    _VotingSessionContext context,
  ) async {
    final records = await ref
        .read(votingRustApiProvider)
        .getKeystoneSignatures(
          dbPath: context.dbPath,
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
        );
    return {for (final record in records) record.bundleIndex: record};
  }

  Future<void> _refreshDelegationPlansAfterBatchFailure({
    required _VotingSessionContext context,
    required VotingSessionState fallbackState,
    required Map<int, VotingSessionProgress> progress,
  }) async {
    try {
      final refreshedRoundPlan = await _loadRoundPlan(context);
      _throwIfContextStale(context, 'delegation-batch-failure-refresh');
      _setStateForContext(
        context,
        (state.value ?? fallbackState).copyWith(
          roundPlan: refreshedRoundPlan,
          delegationProgress: Map<int, VotingSessionProgress>.of(progress),
          clearCurrentBundleIndex: true,
        ),
      );
    } on _StaleVotingSessionAction {
      rethrow;
    } catch (error, stackTrace) {
      // Preserve the original bundle failure for the user. A later retry still
      // reloads context from durable recovery state before doing any work.
      debugPrint(
        '[zcash] Voting: delegation recovery refresh failed '
        'round=${context.round.roundId} error=$error\n$stackTrace',
      );
    }
  }

  Future<void> runShareTrackingPass() {
    if (_automaticShareTrackingStopped) return Future.value();
    final inFlight = _activeAutomaticShareTrackingPass;
    if (inFlight != null) return inFlight;
    if (_ownsAutomaticShareTracking && !_retainAutomaticShareTracking()) {
      return Future.value();
    }

    late final Future<void> pass;
    pass = _runShareTrackingPass().whenComplete(() {
      _activeShareTrackingPasses.remove(pass);
      if (identical(_activeAutomaticShareTrackingPass, pass)) {
        _activeAutomaticShareTrackingPass = null;
      }
    });
    _activeAutomaticShareTrackingPass = pass;
    _activeShareTrackingPasses.add(pass);
    return pass;
  }

  /// Reconciles the designated immediate share without reopening recovery.
  ///
  /// This is the one confirmation-only exception to the vote-end boundary:
  /// the helper may have confirmed the share before the deadline while the
  /// last local tracking pass missed that transition. The crate polls the
  /// configured helper quorum for the round and may persist other observed
  /// confirmations along the way; success here depends only on the designated
  /// immediate share. Because the round has ended, the pass never resubmits a
  /// share or selects a new helper.
  Future<bool> refreshImmediateShareConfirmation() async {
    var confirmed = false;
    await _enqueue(
      () async {
        if (_automaticShareTrackingStopped ||
            ref.read(appSecurityProvider).requiresUnlock) {
          return;
        }
        final current = await future;
        if (_isDisposed || !ref.mounted) return;
        final context = await _loadContext(_roundId);
        _currentContext = context;
        var roundPlan = await _loadRoundPlan(context);
        if (hasConfirmedImmediateShare(roundPlan)) {
          confirmed = true;
          return;
        }

        final immediateShare = roundPlan.immediateShareKey;
        if (immediateShare == null) return;
        if (_finalConfirmationCheckCancelled(context)) return;

        final configuredHelperUrls = _configuredHelperTransportUrls(context);

        final rust = ref.read(votingRustApiProvider);
        final helperContext = _helperDeliveryContextFor(rust, context);
        final passHandle = rust.beginShareTrackingPass(context: helperContext);
        _activeShareTrackingPassHandles.add(passHandle);
        final cancellationWatchdog = Timer.periodic(
          _shareTrackingCancellationPollInterval,
          (timer) {
            if (!_finalConfirmationCheckCancelled(context)) return;
            timer.cancel();
            passHandle.cancel();
          },
        );
        final bool helperConfirmed;
        final focusedConfirmationDone = Completer<void>();
        final focusedConfirmation = focusedConfirmationDone.future;
        _activeShareTrackingPasses.add(focusedConfirmation);
        try {
          final nowSeconds =
              DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
          helperConfirmed = await rust.confirmShareWithHelpers(
            passHandle: passHandle,
            configuredHelperUrls: configuredHelperUrls,
            bundleIndex: immediateShare.bundleIndex,
            proposalId: immediateShare.proposalId,
            shareIndex: immediateShare.shareIndex,
            nowSeconds: BigInt.from(nowSeconds),
          );
        } finally {
          cancellationWatchdog.cancel();
          _activeShareTrackingPassHandles.remove(passHandle);
          passHandle.dispose();
          if (!focusedConfirmationDone.isCompleted) {
            focusedConfirmationDone.complete();
          }
          _activeShareTrackingPasses.remove(focusedConfirmation);
        }
        if (!helperConfirmed || _finalConfirmationCheckCancelled(context)) {
          return;
        }
        // Persistence is the success boundary. A best-effort state reload
        // keeps this notifier current, but must not turn a durable helper
        // confirmation back into an expiry error if a follow-up read fails.
        confirmed = true;
        try {
          roundPlan = await _loadRoundPlan(context);
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              phase: _phaseForPlans(roundPlan),
              roundPlan: roundPlan,
            ),
          );
          if (!roundPlan.hasUnconfirmedShares) {
            _releaseAutomaticShareTracking();
          }
        } catch (error) {
          debugPrint(
            '[zcash] Voting: final immediate-share state reload skipped: '
            '$error',
          );
        }
      },
      cleanupProcessStateOnError: false,
      publishError: false,
      propagateError: true,
    );
    return confirmed;
  }

  Future<void> _runShareTrackingPass() {
    return _enqueueShareTracking(() async {
      _shareTrackingTimer?.cancel();
      _shareTrackingTimer = null;
      if (_automaticShareTrackingStopped) return;
      final current = await future;
      if (_isDisposed || !ref.mounted) return;
      final context = await _loadContext(_roundId);
      if (_shareTrackingCancelled(context)) {
        _releaseAutomaticShareTrackingIfRoundExpired(context);
        return;
      }
      _currentContext = context;
      var roundPlan = await _loadRoundPlan(context);
      if (ref.read(appSecurityProvider).requiresUnlock ||
          !shouldTrackPendingVotingShares(context.round)) {
        _setStateForContext(
          context,
          current.copyWith(
            phase: _phaseForPlans(roundPlan),
            roundPlan: roundPlan,
          ),
        );
        _releaseAutomaticShareTracking();
        return;
      }
      _setStateForContext(
        context,
        current.copyWith(
          phase: VotingSessionPhase.submittingShares,
          roundPlan: roundPlan,
        ),
      );

      final rust = ref.read(votingRustApiProvider);
      final configuredHelperUrls = _configuredHelperTransportUrls(context);
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final voteEnd = context.round.voteEndTime;
      final voteEndSeconds = voteEnd == null
          ? null
          : voteEnd.millisecondsSinceEpoch ~/ 1000;

      // One crate call performs the whole pass: helper status polling, the
      // two-distinct-helper confirmation quorum, overdue resubmission, and all
      // durable writes. Dart no longer sees individual helper requests, so its
      // stop conditions are pushed in by the watchdog below instead of being
      // polled between them.
      final helperContext = _helperDeliveryContextFor(rust, context);
      final passHandle = rust.beginShareTrackingPass(context: helperContext);
      _activeShareTrackingPassHandles.add(passHandle);
      Timer? cancellationWatchdog;
      final rust_api.ApiShareTrackingReport report;
      try {
        cancellationWatchdog = _watchShareTrackingCancellation(
          context,
          passHandle,
        );
        report = await rust.trackPendingShares(
          passHandle: passHandle,
          configuredHelperUrls: configuredHelperUrls,
          nowSeconds: BigInt.from(nowSeconds),
          voteEndTimeSeconds: voteEndSeconds == null
              ? null
              : BigInt.from(voteEndSeconds),
        );
      } finally {
        cancellationWatchdog?.cancel();
        _activeShareTrackingPassHandles.remove(passHandle);
        passHandle.dispose();
      }

      if (report.unrecoverable.isNotEmpty) {
        // These cannot be repaired by retrying; log once per pass rather than
        // spinning on them silently.
        debugPrint(
          '[zcash] Voting: ${report.unrecoverable.length} share(s) missing '
          'recovery material round=${context.round.roundId}',
        );
      }

      if (report.cancelled || _shareTrackingCancelled(context)) {
        _releaseAutomaticShareTrackingIfRoundExpired(context);
        return;
      }
      final refreshedRoundPlan = await _loadRoundPlan(context);
      final hasBlockingWork = hasBlockingRoundRecoveryWork(refreshedRoundPlan);
      if (!hasBlockingWork) {
        await _clearPersistedDraftChoices(context);
      }
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: _phaseForPlans(refreshedRoundPlan),
          roundPlan: refreshedRoundPlan,
        ),
      );
      await _scheduleShareTracking(context, refreshedRoundPlan);
    });
  }

  Future<void> stopAndDrainShareTracking() async {
    _automaticShareTrackingStopped = true;
    _shareTrackingTimer?.cancel();
    _shareTrackingTimer = null;
    _advanceSessionGeneration();
    // Stop the in-flight Rust pass now rather than waiting for the watchdog's
    // next tick: destructive wallet operations block on this draining.
    for (final passHandle in _activeShareTrackingPassHandles.toList()) {
      passHandle.cancel();
    }
    try {
      while (_activeShareTrackingPasses.isNotEmpty) {
        await Future.wait(
          _activeShareTrackingPasses.map(
            (pass) => pass.then<void>((_) {}, onError: (_, _) {}),
          ),
        );
      }
    } catch (_) {
      // The tracking action already logged its business error. Destructive
      // wallet operations require the pass to finish, not to succeed.
    } finally {
      _releaseAutomaticShareTracking();
    }
  }

  void resumeShareTracking() {
    _automaticShareTrackingStopped = false;
  }

  Future<void> _scheduleShareTracking(
    _VotingSessionContext context,
    rust_wire.RoundPlanView? roundPlan,
  ) async {
    if (!_ownsAutomaticShareTracking) {
      _shareTrackingTimer?.cancel();
      _shareTrackingTimer = null;
      _releaseAutomaticShareTracking();
      return;
    }
    if (_automaticShareTrackingStopped ||
        !(roundPlan?.hasUnconfirmedShares ?? false) ||
        !shouldTrackPendingVotingShares(context.round) ||
        ref.read(appSecurityProvider).requiresUnlock) {
      _shareTrackingTimer?.cancel();
      _shareTrackingTimer = null;
      _releaseAutomaticShareTracking();
      return;
    }
    if (!_isCurrentContext(context)) return;
    if (!_retainAutomaticShareTracking()) return;
    _shareTrackingTimer?.cancel();
    _shareTrackingTimer = null;

    final delaySeconds = await ref
        .read(votingRustApiProvider)
        .nextShareTrackingDelaySeconds(
          dbPath: context.dbPath,
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          nowSeconds: BigInt.from(
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          ),
        );
    if (delaySeconds == null) {
      _releaseAutomaticShareTracking();
      return;
    }
    if (!_isCurrentContext(context)) return;
    final delay = Duration(seconds: delaySeconds.toInt());
    _armShareTrackingTimer(context, _delayCappedAtVoteEnd(context, delay));
  }

  void _scheduleShareTrackingFailureRetry() {
    if (_isDisposed ||
        !_ownsAutomaticShareTracking ||
        _automaticShareTrackingStopped ||
        ref.read(appSecurityProvider).requiresUnlock) {
      _releaseAutomaticShareTracking();
      return;
    }
    final config = ref.read(votingConfigProvider).value;
    if (config != null && !config.isRoundAuthenticated(_roundId)) {
      _releaseAutomaticShareTracking();
      return;
    }
    final context = _currentContext;
    if (context == null ||
        !_isCurrentContext(context) ||
        !shouldTrackPendingVotingShares(context.round) ||
        !_retainAutomaticShareTracking()) {
      _releaseAutomaticShareTracking();
      return;
    }
    final configuredDelay = ref.read(
      votingShareTrackingFailureRetryDelayProvider,
    );
    final delay = configuredDelay.isNegative ? Duration.zero : configuredDelay;
    _armShareTrackingTimer(context, _delayCappedAtVoteEnd(context, delay));
  }

  Duration _delayCappedAtVoteEnd(
    _VotingSessionContext context,
    Duration delay,
  ) {
    final remaining = context.round.voteEndTime!.difference(DateTime.now());
    if (remaining.isNegative) return Duration.zero;
    return delay < remaining ? delay : remaining;
  }

  void _armShareTrackingTimer(_VotingSessionContext context, Duration delay) {
    _shareTrackingTimer?.cancel();
    _shareTrackingTimer = Timer(delay, () {
      _shareTrackingTimer = null;
      if (!_isCurrentContext(context)) return;
      if (!shouldTrackPendingVotingShares(context.round)) {
        _releaseAutomaticShareTracking();
        return;
      }
      unawaited(_runShareTrackingPassInBackground());
    });
  }

  Future<void> _runShareTrackingPassInBackground() async {
    try {
      await runShareTrackingPass();
    } catch (_) {
      // The pass already logged the failure and scheduled its next retry.
    }
  }

  /// Pushes Dart-owned stop conditions into the in-flight Rust pass.
  ///
  /// The pass runs to completion inside the crate, so app lock, round expiry,
  /// session disposal, and context change can no longer be checked between
  /// helper requests the way the old Dart loop did. This polls them for the
  /// duration of the pass and cancels once, which keeps the stop conditions
  /// and their ownership exactly where they were.
  ///
  /// Callers must cancel the returned timer when the pass settles.
  Timer _watchShareTrackingCancellation(
    _VotingSessionContext context,
    VotingShareTrackingPassHandle passHandle,
  ) {
    return Timer.periodic(_shareTrackingCancellationPollInterval, (timer) {
      if (!_shareTrackingCancelled(context)) return;
      timer.cancel();
      passHandle.cancel();
    });
  }

  bool _finalConfirmationCheckCancelled(_VotingSessionContext context) {
    return _automaticShareTrackingStopped ||
        _isDisposed ||
        !ref.mounted ||
        !_isCurrentContext(context) ||
        ref.read(appSecurityProvider).requiresUnlock;
  }

  bool _shareTrackingCancelled(_VotingSessionContext context) {
    if (_automaticShareTrackingStopped || _isDisposed || !ref.mounted) {
      return true;
    }
    return !_isCurrentContext(context) ||
        ref.read(appSecurityProvider).requiresUnlock ||
        !shouldTrackPendingVotingShares(context.round);
  }

  void _releaseAutomaticShareTrackingIfRoundExpired(
    _VotingSessionContext context,
  ) {
    if (!shouldTrackPendingVotingShares(context.round)) {
      _releaseAutomaticShareTracking();
    }
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
        '[zcash] Voting: snapshot bundle precompute skipped '
        'round=${context.round.roundId} reason=pir-resolution-failed '
        'error=$e',
      );
      return null;
    } catch (e) {
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute skipped '
        'round=${context.round.roundId} reason=pir-resolution-failed '
        'error=$e',
      );
      return null;
    }
  }

  Future<int?> _runSnapshotBundlePrecompute({
    required _VotingSessionContext context,
    required Uri pirEndpoint,
  }) async {
    final timer = Stopwatch()..start();
    debugPrint(
      '[zcash] Voting: snapshot bundle precompute start '
      'round=${context.round.roundId}',
    );
    try {
      final rust = ref.read(votingRustApiProvider);
      rust.warmVotingProvingCaches();
      final result = await rust.precomputeSnapshotBundles(
        ctx: _apiRoundContext(context),
        pirServerUrl: _transportUrl(pirEndpoint),
      );
      final cached = result.bundles.fold<int>(
        0,
        (total, bundle) => total + bundle.cachedCount,
      );
      final fetched = result.bundles.fold<int>(
        0,
        (total, bundle) => total + bundle.fetchedCount,
      );
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute completed '
        'round=${context.round.roundId} bundles=${result.bundleCount} '
        'cached=$cached fetched=$fetched '
        'elapsed=${formatElapsedSeconds(timer.elapsed)}',
      );
      return result.bundleCount;
    } catch (e) {
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute failed '
        'round=${context.round.roundId} '
        'elapsed=${formatElapsedSeconds(timer.elapsed)} error=$e '
        'reason=cache-miss',
      );
      return null;
    }
  }

  /// Starts drainable, best-effort proof warm-up without extending the
  /// foreground snapshot-readiness barrier.
  void _startBackgroundDelegationProofPrecompute({
    required _VotingSessionContext context,
    required Uri pirEndpoint,
    required int bundleCount,
    required String precomputeKey,
  }) {
    if (_backgroundDelegationProofPrecomputes.containsKey(precomputeKey)) {
      return;
    }
    final releaseBackgroundWork = ref
        .read(votingShareTrackingRegistryProvider)
        .beginBackgroundWork(accountUuid: context.accountUuid);
    if (releaseBackgroundWork == null) {
      debugPrint(
        '[zcash] Voting: background delegation proof skipped '
        'round=${context.round.roundId} reason=wallet-mutation-in-progress',
      );
      return;
    }

    late final Future<void> proofPrecompute;
    proofPrecompute = () async {
      try {
        final completed = await _runBackgroundDelegationProofPrecompute(
          context: context,
          pirEndpoint: pirEndpoint,
          bundleCount: bundleCount,
        );
        if (completed &&
            _isCurrentPrecomputeContext(context, context.accountUuid)) {
          _completedSnapshotBundlePrecomputes.add(precomputeKey);
        }
      } catch (error) {
        debugPrint(
          '[zcash] Voting: background delegation proof pass failed '
          'round=${context.round.roundId} error=$error '
          'reason=foreground-fallback',
        );
      } finally {
        if (identical(
          _backgroundDelegationProofPrecomputes[precomputeKey],
          proofPrecompute,
        )) {
          _backgroundDelegationProofPrecomputes.remove(precomputeKey);
        }
        releaseBackgroundWork();
      }
    }();
    _backgroundDelegationProofPrecomputes[precomputeKey] = proofPrecompute;
    unawaited(proofPrecompute);
  }

  Future<bool> _runBackgroundDelegationProofPrecompute({
    required _VotingSessionContext context,
    required Uri pirEndpoint,
    required int bundleCount,
  }) async {
    // Keystone must retain the original PCZT bytes for its QR signing request.
    // The software path can persist ZKP1 now and reconstruct its signed payload
    // from the stored setup fields later without retaining those bytes in Dart.
    if (context.isHardwareAccount || bundleCount == 0) return true;
    if (!_isCurrentPrecomputeContext(context, context.accountUuid)) {
      return false;
    }

    final rust = ref.read(votingRustApiProvider);
    late final List<int> storedHotkeySecret;
    try {
      storedHotkeySecret = await _ensureHotkey(context);
    } catch (e) {
      debugPrint(
        '[zcash] Voting: background delegation proof skipped '
        'round=${context.round.roundId} reason=hotkey-unavailable error=$e',
      );
      return false;
    }
    if (!_isCurrentPrecomputeContext(context, context.accountUuid)) {
      return false;
    }

    final current = state.value;
    if (current == null) return false;
    final pirServerUrls = List<String>.from(
      _delegationPirTransportUrls(current),
    );
    if (pirServerUrls.isEmpty) {
      pirServerUrls.add(_transportUrl(pirEndpoint));
    }

    final outcomes = await _runBoundedBundleWork(
      List<int>.generate(bundleCount, (bundleIndex) => bundleIndex),
      concurrency: _votingWorkConcurrency,
      work: (bundleIndex) async {
        if (!_isCurrentPrecomputeContext(context, context.accountUuid)) {
          throw const _StaleVotingSessionAction();
        }
        final timer = Stopwatch()..start();
        debugPrint(
          '[zcash] Voting: background delegation proof start '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        try {
          final generated = await rust.precomputeDelegationProof(
            ctx: _apiRoundContext(context),
            pirServerUrls: pirServerUrls,
            storedHotkeySecret: storedHotkeySecret,
            bundleIndex: bundleIndex,
          );
          debugPrint(
            '[zcash] Voting: background delegation proof completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'result=${generated ? 'generated' : 'reused'} '
            'elapsed=${formatElapsedSeconds(timer.elapsed)}',
          );
        } catch (e) {
          debugPrint(
            '[zcash] Voting: background delegation proof failed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'elapsed=${formatElapsedSeconds(timer.elapsed)} error=$e '
            'reason=foreground-fallback',
          );
          rethrow;
        }
      },
    );
    return outcomes.values.every((outcome) => outcome.error == null);
  }

  Future<void> _awaitSnapshotBundlePrecomputeIfRunning(
    _VotingSessionContext context,
  ) async {
    final precompute =
        _snapshotBundlePrecomputes[_snapshotBundlePrecomputeKey(
          context.accountUuid,
        )];
    if (precompute == null) return;

    debugPrint(
      '[zcash] Voting: waiting for in-flight snapshot bundle precompute '
      'round=${context.round.roundId}',
    );
    await precompute;
  }

  String _transportUrl(Uri logicalUrl) {
    return ref.read(votingEndpointMapperProvider).map(logicalUrl).toString();
  }

  List<String> _configuredHelperTransportUrls(_VotingSessionContext context) {
    return context.config.apiServers.all
        .map(_transportUrl)
        .toList(growable: false);
  }

  List<String> _delegationPirTransportUrls(VotingSessionState session) {
    final selected = session.pirEndpoint;
    if (selected == null) return const [];

    final candidates = <String>[_transportUrl(selected)];
    final seen = <String>{selected.toString()};
    for (final diagnostic in session.pirDiagnostics) {
      if (diagnostic.matched && seen.add(diagnostic.endpoint.toString())) {
        candidates.add(_transportUrl(diagnostic.endpoint));
      }
    }
    return candidates;
  }

  String _snapshotBundlePrecomputeKey(String accountUuid) {
    return '$_roundId|$accountUuid|$_sessionGeneration';
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
      return 'Voting PIR data is not ready for this voting round yet. Expected '
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
      return 'Configured PIR endpoints are ahead of this voting round snapshot. '
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

    return 'No PIR endpoint matched this voting round snapshot. Expected snapshot '
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

  Future<void> _enqueue(
    Future<void> Function() action, {
    void Function()? onError,
    bool cleanupProcessStateOnError = true,
    bool publishError = true,
    bool propagateError = false,
  }) {
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
        if (cleanupProcessStateOnError) {
          await _cleanupCurrentSessionState(reason: 'action-failed');
        }
        if (publishError) {
          _setError(
            _actionErrorMessage(e),
            cause: e,
            isEligibilityFailure:
                votingRustExceptionOf(e)?.isEligibilityFailure ?? false,
          );
        }
        onError?.call();
        if (propagateError) rethrow;
      } finally {
        _runningActionGeneration = previousActionGeneration;
      }
    });
    _operation = next.catchError((_) {});
    return next;
  }

  Future<void> _enqueueShareTracking(Future<void> Function() action) {
    return _enqueue(
      action,
      onError: _scheduleShareTrackingFailureRetry,
      cleanupProcessStateOnError: false,
      publishError: false,
      propagateError: true,
    );
  }

  static String _actionErrorMessage(Object error) {
    return friendlyVotingErrorMessage(error);
  }

  static bool _needsDelegationPreparation(VotingSessionState state) {
    return state.pirEndpoint == null || state.eligibleWeightZatoshi == null;
  }

  static bool _needsFreshDelegationPreparation(
    rust_wire.RoundPlanView? roundPlan,
  ) {
    if (delegationBundleIndexesNeedingSigning(roundPlan).isNotEmpty)
      return true;
    if (roundPlan == null) return false;
    return roundPlanNeedsDraftSetup(roundPlan) ||
        roundPlan.recoveredDelegationWork.any(
          (work) =>
              work.kind == rust_wire.DelegationRecoveryWorkKindView.delegate,
        );
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

    var roundPlan = current.roundPlan ?? context.roundPlan;
    var signatures = await _loadKeystoneSignatures(context);
    var unsignedBundleIndexes = delegationBundleIndexesNeedingSigning(
      roundPlan,
    ).where((bundleIndex) => !signatures.containsKey(bundleIndex)).toList();
    final existingHotkey = await _readStoredHotkey(context);
    if (existingHotkey == null &&
        (signatures.isNotEmpty || (roundPlan?.hotkeyBound ?? false))) {
      throw const VotingHotkeyUnavailable('missing stored voting hotkey');
    }

    if (unsignedBundleIndexes.isEmpty) {
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.readyToDelegate,
          isHardwareAccount: true,
          keystoneSignatures: signatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
          clearError: true,
        ),
      );
      return;
    }

    final storedHotkeySecret =
        existingHotkey ??
        await _ensureHotkey(context, alreadyBound: signatures.isNotEmpty);

    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.keystoneSigning,
        isHardwareAccount: true,
        keystoneSignatures: signatures,
        currentBundleIndex: unsignedBundleIndexes.first,
        clearKeystoneSigningRequest: true,
        clearKeystoneScanError: true,
        clearError: true,
      ),
    );

    final rust = ref.read(votingRustApiProvider);
    late final List<rust_delegate.KeystoneSigningRequest> requests;
    try {
      requests = await rust.buildKeystoneDelegationRequests(
        ctx: _apiRoundContext(context),
        storedHotkeySecret: storedHotkeySecret,
        bundleIndices: unsignedBundleIndexes,
      );
    } catch (error) {
      if (!_isKeystoneSetupOverwriteError(error)) rethrow;
      debugPrint(
        '[zcash] Voting: Keystone request detected stale bundle setup '
        'round=${context.round.roundId} bundles=$unsignedBundleIndexes',
      );
      await _resetVotingSessionState(
        rust: rust,
        context: context,
        reason: 'keystone-stale-setup',
      );
      await rust.setupDelegationBundles(ctx: _apiRoundContext(context));
      roundPlan = await _loadRoundPlan(context);
      signatures = await _loadKeystoneSignatures(context);
      final maxBundleIndex = roundPlanBundleCount(roundPlan);
      if (maxBundleIndex >= 0) {
        signatures = {
          for (final entry in signatures.entries)
            if (entry.key >= 0 && entry.key < maxBundleIndex)
              entry.key: entry.value,
        };
      }
      unsignedBundleIndexes = delegationBundleIndexesNeedingSigning(
        roundPlan,
      ).where((bundleIndex) => !signatures.containsKey(bundleIndex)).toList();
      if (unsignedBundleIndexes.isEmpty) {
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.readyToDelegate,
            isHardwareAccount: true,
            roundPlan: roundPlan,
            keystoneSignatures: signatures,
            clearKeystoneSigningRequest: true,
            clearKeystoneScanError: true,
            clearCurrentBundleIndex: true,
            clearError: true,
          ),
        );
        return;
      }
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.keystoneSigning,
          isHardwareAccount: true,
          roundPlan: roundPlan,
          keystoneSignatures: signatures,
          currentBundleIndex: unsignedBundleIndexes.first,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearError: true,
        ),
      );
      requests = await rust.buildKeystoneDelegationRequests(
        ctx: _apiRoundContext(context),
        storedHotkeySecret: storedHotkeySecret,
        bundleIndices: unsignedBundleIndexes,
      );
    }

    if (requests.length != unsignedBundleIndexes.length ||
        !List.generate(
          requests.length,
          (index) =>
              requests[index].bundleIndex == unsignedBundleIndexes[index],
        ).every((matches) => matches)) {
      throw StateError(
        'Keystone voting requests do not match the pending bundles.',
      );
    }

    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.keystoneSigning,
        isHardwareAccount: true,
        roundPlan: roundPlan,
        eligibleWeightZatoshi: requests.first.eligibleWeightZatoshi,
        keystoneSigningRequests: requests,
        keystoneSignatures: signatures,
        currentBundleIndex: unsignedBundleIndexes.first,
        clearKeystoneScanError: true,
        clearError: true,
      ),
    );
  }

  Future<void> _prepareDelegationUnlocked() async {
    final current = await future;
    final context = await _loadContext(_roundId);
    ref.read(votingRustApiProvider).warmVotingProvingCaches();
    await _waitUntilWalletReadyForVoting(context);
    _setStateForContext(
      context,
      current.copyWith(
        phase: VotingSessionPhase.resolvingPir,
        config: context.config,
        round: context.round,
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
        roundPlan: context.roundPlan,
        isHardwareAccount: context.isHardwareAccount,
      ),
    );

    await _awaitSnapshotBundlePrecomputeIfRunning(context);
    _throwIfContextStale(context, 'snapshot-bundle-precompute');
    final bundleSetup = await ref
        .read(votingRustApiProvider)
        .setupDelegationBundles(ctx: _apiRoundContext(context));
    final refreshedRoundPlan = await _loadRoundPlan(context);
    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.readyToDelegate,
        roundPlan: refreshedRoundPlan,
        eligibleWeightZatoshi: bundleSetup.eligibleWeight,
        privacyTrimDroppedValueZatoshi:
            bundleSetup.privacyTrimDroppedValueZatoshi,
        isHardwareAccount: context.isHardwareAccount,
      ),
    );
  }

  Future<void> _refreshEligibleWeightUnlocked() async {
    final current = await future;
    final context = await _loadContext(_roundId);
    await _waitUntilWalletReadyForVoting(context);
    await _refreshVotingEligibilityState(current: current, context: context);
  }

  Future<void> _ensureVotingEligibilityUnlocked() async {
    final current = await future;
    if (current.hasConfirmedVotingEligibility) return;
    final context = await _loadContext(_roundId);
    await _waitUntilWalletReadyForVoting(context);
    await _refreshVotingEligibilityState(current: current, context: context);
  }

  Future<void> _refreshVotingEligibilityState({
    required VotingSessionState current,
    required _VotingSessionContext context,
  }) async {
    try {
      final eligibility = await ref
          .read(votingRustApiProvider)
          .checkVotingEligibility(ctx: _apiRoundContext(context));
      final refreshedRoundPlan = await _loadRoundPlan(context);
      final successPhase = current.phase == VotingSessionPhase.error
          ? VotingSessionPhase.idle
          : current.phase;
      final base = (state.value ?? current).copyWith(
        phase: eligibility.isEligible ? successPhase : VotingSessionPhase.error,
        config: context.config,
        round: context.round,
        roundPlan: refreshedRoundPlan,
        eligibleWeightZatoshi: eligibility.eligibleWeightZatoshi,
        privacyTrimDroppedValueZatoshi:
            eligibility.privacyTrimDroppedValueZatoshi,
        isHardwareAccount: context.isHardwareAccount,
        clearError: eligibility.isEligible,
      );
      _setStateForContext(
        context,
        eligibility.isEligible
            ? base
            : base.copyWith(
                error: VotingSessionError(
                  message: minimumVotingEligibilityMessage(
                    snapshotHeight: context.round.snapshotHeight,
                  ),
                  isEligibilityFailure: true,
                ),
              ),
      );
    } catch (error) {
      final message = friendlyVotingErrorMessage(error);
      final eligibilityError =
          votingRustExceptionOf(error)?.isEligibilityFailure ?? false;
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.error,
          config: context.config,
          round: context.round,
          roundPlan: context.roundPlan,
          eligibleWeightZatoshi: eligibilityError ? BigInt.zero : null,
          privacyTrimDroppedValueZatoshi: eligibilityError ? BigInt.zero : null,
          isHardwareAccount: context.isHardwareAccount,
          error: VotingSessionError(
            message: message,
            cause: error,
            isEligibilityFailure: eligibilityError,
          ),
        ),
      );
    }
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
    config.assertRoundAuthenticated(roundId);
    final api = ref.read(votingApiClientProvider(config.apiServers));
    final round = VotingRoundDetails.fromStatus(
      await api.getRoundStatus(roundId),
    );
    final roundParams = await ref
        .read(votingRustApiProvider)
        .trustedVotingRoundParamsFromConfig(
          config: config,
          roundId: round.roundId,
          snapshotHeight: BigInt.from(round.snapshotHeight),
          ncRoot: round.ncRoot,
          nullifierImtRoot: round.nullifierImtRoot,
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
          accountUuid: accountUuid,
          roundId: round.roundId,
          proposalIds: proposalIds,
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
      roundParams: roundParams,
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

  /// Loads the crate planner's round plan.
  Future<rust_wire.RoundPlanView> _loadRoundPlan(
    _VotingSessionContext context,
  ) {
    final proposals = proposalsFromRound(context.round);
    return ref
        .read(votingRecoveryServiceProvider)
        .loadRoundPlan(
          dbPath: context.dbPath,
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          proposalIds: proposals.map((p) => p.id).toList(),
        );
  }

  Future<void> _waitUntilWalletReadyForVoting(
    _VotingSessionContext context, {
    bool stopIfVotingBackgroundWorkQuiesced = false,
  }) async {
    VotingWalletSyncReadiness? lastReadiness;
    void throwIfBackgroundWorkQuiesced() {
      if (stopIfVotingBackgroundWorkQuiesced &&
          ref
              .read(votingShareTrackingRegistryProvider)
              .isQuiesced(context.accountUuid)) {
        throw _VotingBackgroundWorkQuiesced(readiness: lastReadiness);
      }
    }

    var loggedWait = false;
    final maxWait = ref.read(votingWalletSyncMaxWaitProvider);
    final waitTimer = Stopwatch()..start();
    final sessionInvalidated = _sessionInvalidated.future;
    while (true) {
      throwIfBackgroundWorkQuiesced();
      _throwIfContextStale(context, 'wallet-sync-wait');
      final readiness = await ref
          .read(votingWalletSyncReadinessCheckerProvider)
          .check(
            dbPath: context.dbPath,
            network: context.network,
            snapshotHeight: context.round.snapshotHeight,
          );
      lastReadiness = readiness;
      throwIfBackgroundWorkQuiesced();
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
      final remainingWait = maxWait - waitTimer.elapsed;
      if (remainingWait.compareTo(Duration.zero) <= 0) {
        throw _VotingWalletSyncTimeout(readiness: readiness, maxWait: maxWait);
      }
      final pollInterval = ref.read(votingWalletSyncPollIntervalProvider);
      final delay = remainingWait.compareTo(pollInterval) < 0
          ? remainingWait
          : pollInterval;
      await Future.any<void>([Future<void>.delayed(delay), sessionInvalidated]);
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

  /// Preserves resolved PIR diagnostics unless the error supplies replacements.
  void _setError(
    String message, {
    Object? cause,
    List<PirSnapshotEndpointDiagnostic>? pirDiagnostics,
    _VotingSessionContext? context,
    bool isEligibilityFailure = false,
  }) {
    if (!_canUpdateSessionUi(context)) return;
    final current = state.value ?? VotingSessionState(roundId: _roundId);
    state = AsyncData(
      current.copyWith(
        phase: VotingSessionPhase.error,
        error: VotingSessionError(
          message: message,
          cause: cause,
          pirDiagnostics: pirDiagnostics ?? const [],
          isEligibilityFailure: isEligibilityFailure,
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
    return _guardsOwnContext(_activeSubmissionGuards, context) ||
        _guardsOwnContext(
          _guardNotifierState(ref.read(votingSubmissionGuardProvider.notifier)),
          context,
        );
  }

  static List<VotingSubmissionGuard> _guardNotifierState(
    VotingSubmissionGuardNotifier notifier,
  ) {
    try {
      return notifier.state;
    } catch (_) {
      return const [];
    }
  }

  static bool _guardsOwnContext(
    List<VotingSubmissionGuard> guards,
    _VotingSessionContext context,
  ) {
    for (final guard in guards) {
      if (guard.accountUuid == context.accountUuid &&
          guard.roundId == context.round.roundId) {
        return true;
      }
    }
    return false;
  }

  void _advanceSessionGeneration() {
    _sessionGeneration++;
    final operationEpoch = BigInt.from(_sessionGeneration);
    for (final session in _activeRoundSessions.toList()) {
      session.setOperationEpoch(operationEpoch);
      session.cancel();
    }
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
    } finally {
      if (_shareTrackingTimer == null && _activeShareTrackingPasses.isEmpty) {
        _releaseAutomaticShareTracking();
      }
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
        accountUuid: context.accountUuid,
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

  static VotingSessionPhase _phaseForPlans(rust_wire.RoundPlanView? roundPlan) {
    return switch (roundPlan?.primaryAction) {
      rust_wire.RoundPlanActionKind.done => VotingSessionPhase.done,
      rust_wire.RoundPlanActionKind.delegate =>
        VotingSessionPhase.readyToDelegate,
      rust_wire.RoundPlanActionKind.vote => VotingSessionPhase.readyToVote,
      rust_wire.RoundPlanActionKind.submitShares =>
        VotingSessionPhase.submittingShares,
      rust_wire.RoundPlanActionKind.idle || null => VotingSessionPhase.idle,
    };
  }

  Future<void> _clearPersistedDraftChoices(
    _VotingSessionContext context,
  ) async {
    final draftKey = VotingSessionKey(
      roundId: context.round.roundId,
      accountUuid: context.accountUuid,
    );
    final notifier = ref.read(votingDraftProvider(draftKey).notifier);
    try {
      final draft = await notifier.ensureLoaded();
      if (draft.isEmpty) return;
      await notifier.clearAll();
    } catch (error) {
      debugPrint(
        '[zcash] Voting: draft cleanup skipped '
        'round=${context.round.roundId} account=${context.accountUuid} '
        'error=$error',
      );
    }
  }

  _RoundShareTiming _roundShareTiming(
    _VotingSessionContext context,
    int nowSeconds,
  ) {
    final start = context.round.ceremonyStart;
    final end = context.round.voteEndTime;
    if (start == null || end == null) {
      return _RoundShareTiming(
        nowSeconds: nowSeconds,
        voteEndSeconds: nowSeconds,
        lastMomentBufferSeconds: null,
        isLastMoment: false,
      );
    }

    final startSeconds = _unixSeconds(start);
    final voteEndSeconds = _unixSeconds(end);
    final rust = ref.read(votingRustApiProvider);
    return _RoundShareTiming(
      nowSeconds: nowSeconds,
      voteEndSeconds: voteEndSeconds,
      lastMomentBufferSeconds: rust.lastMomentBufferSeconds(
        ceremonyStartSeconds: BigInt.from(startSeconds),
        voteEndTimeSeconds: BigInt.from(voteEndSeconds),
      ),
      isLastMoment: rust.isLastMoment(
        nowSeconds: BigInt.from(nowSeconds),
        ceremonyStartSeconds: BigInt.from(startSeconds),
        voteEndTimeSeconds: BigInt.from(voteEndSeconds),
      ),
    );
  }

  static int _nowSeconds() {
    return DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  static int _unixSeconds(DateTime value) {
    return value.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  static bool _isKeystoneSetupOverwriteError(Object error) {
    return error is VotingRustException &&
        error.kind == rust_wire.VotingErrorKindView.setupAlreadyPersisted;
  }
}

class _RoundShareTiming {
  const _RoundShareTiming({
    required this.nowSeconds,
    required this.voteEndSeconds,
    required this.lastMomentBufferSeconds,
    required this.isLastMoment,
  });

  final int nowSeconds;
  final int voteEndSeconds;
  final BigInt? lastMomentBufferSeconds;
  final bool isLastMoment;
}

/// Serializes vote-tree syncs and batches concurrent requesters onto one call.
///
/// Two guarantees matter to callers:
///

Future<Map<int, _BundleWorkOutcome<T>>> _runBoundedBundleWork<T>(
  List<int> bundleIndexes, {
  required int concurrency,
  required Future<T> Function(int bundleIndex) work,
}) async {
  if (bundleIndexes.isEmpty) return {};
  final outcomes = <int, _BundleWorkOutcome<T>>{};
  var nextIndex = 0;
  final workerCount = concurrency < bundleIndexes.length
      ? concurrency
      : bundleIndexes.length;

  Future<void> worker() async {
    while (nextIndex < bundleIndexes.length) {
      final bundleIndex = bundleIndexes[nextIndex++];
      try {
        outcomes[bundleIndex] = _BundleWorkOutcome.success(
          await work(bundleIndex),
        );
      } catch (error, stackTrace) {
        outcomes[bundleIndex] = _BundleWorkOutcome.failure(error, stackTrace);
      }
    }
  }

  await Future.wait(List.generate(workerCount, (_) => worker()));
  return outcomes;
}

class _BundleWorkOutcome<T> {
  const _BundleWorkOutcome.success(this.value)
    : error = null,
      stackTrace = null;

  const _BundleWorkOutcome.failure(this.error, this.stackTrace) : value = null;

  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
}

/// The bridge failure that best describes a batch of per-bundle failures.
///
/// An eligibility failure wins because it is round-wide rather than specific
/// to the bundle that reported it first.
VotingRustException? _representativeVotingRustException(
  Iterable<Object> errors,
) {
  VotingRustException? first;
  for (final error in errors) {
    final rustError = votingRustExceptionOf(error);
    if (rustError == null) continue;
    if (rustError.isEligibilityFailure) return rustError;
    first ??= rustError;
  }
  return first;
}

class _VoteBundleFailure {
  const _VoteBundleFailure({
    required this.bundleIndex,
    required this.proposalId,
    required this.error,
  });

  final int bundleIndex;
  final int proposalId;
  final Object error;
}

class _VoteBundleBatchException
    implements Exception, VotingRustExceptionSource {
  const _VoteBundleBatchException(this.failures);

  final List<_VoteBundleFailure> failures;

  @override
  VotingRustException? get votingRustException =>
      _representativeVotingRustException(
        failures.map((failure) => failure.error),
      );

  @override
  String toString() {
    final details = failures
        .map(
          (failure) =>
              'bundle ${failure.bundleIndex + 1} '
              'proposal ${failure.proposalId}: ${failure.error}',
        )
        .join('; ');
    return 'Vote casting failed: $details';
  }
}

class _DelegationBundleFailure {
  const _DelegationBundleFailure({
    required this.bundleIndex,
    required this.stage,
    required this.error,
  });

  final int bundleIndex;
  final String stage;
  final Object error;
}

class _DelegationBundleBatchException
    implements Exception, VotingRustExceptionSource {
  const _DelegationBundleBatchException(this.failures);

  final List<_DelegationBundleFailure> failures;

  @override
  VotingRustException? get votingRustException =>
      _representativeVotingRustException(
        failures.map((failure) => failure.error),
      );

  @override
  String toString() {
    final details = failures
        .map(
          (failure) =>
              'bundle ${failure.bundleIndex + 1} ${failure.stage}: '
              '${failure.error}',
        )
        .join('; ');
    return 'Delegation bundle processing failed: $details';
  }
}

class _VotingSessionContext {
  final int sessionGeneration;
  final String dbPath;
  final String accountUuid;
  final bool isHardwareAccount;
  final String network;
  final String lightwalletdUrl;
  final rust_config.ResolvedVotingConfig config;
  final VotingRoundDetails round;
  final rust_wire.VotingRoundParams roundParams;
  final rust_wire.RoundPlanView? roundPlan;

  const _VotingSessionContext({
    required this.sessionGeneration,
    required this.dbPath,
    required this.accountUuid,
    required this.isHardwareAccount,
    required this.network,
    required this.lightwalletdUrl,
    required this.config,
    required this.round,
    required this.roundParams,
    this.roundPlan,
  });
}

class _StaleVotingSessionAction implements Exception {
  const _StaleVotingSessionAction();
}

/// An SDK round step ended in a typed failure.
class VotingRoundStepFailure implements Exception {
  const VotingRoundStepFailure(this.step, this.failure);

  final rust_wire.NextStepView step;
  final rust_wire.RoundStepFailureView failure;

  @override
  String toString() => failure.message;
}

/// The chain reported a terminal outcome for a step.
class VotingChainTerminalOutcome implements Exception {
  const VotingChainTerminalOutcome(this.step, this.outcome);

  final rust_wire.NextStepView step;
  final rust_wire.RoundStepOutcomeView outcome;

  @override
  String toString() {
    final chainOutcome = outcome.chainOutcome;
    final diagnostic = chainOutcome?.diagnostic?.message;
    if (diagnostic != null) return diagnostic;
    return switch (chainOutcome?.kind) {
      rust_wire.ChainSubmissionOutcomeKind.rejected =>
        'Chain submission was rejected.',
      rust_wire.ChainSubmissionOutcomeKind.submittedWithoutHash =>
        'Submission may have reached the chain, but no transaction hash was returned. Do not retry it.',
      _ => 'Chain submission ended without a usable transaction.',
    };
  }
}

/// The chain step is still reconciling after the SDK's recovery pass.
class VotingChainPendingOutcome implements Exception {
  const VotingChainPendingOutcome(this.step, this.outcome);

  final rust_wire.NextStepView step;
  final rust_wire.RoundStepOutcomeView outcome;

  @override
  String toString() =>
      outcome.chainOutcome?.diagnostic?.message ??
      'Chain submission recovery is still pending.';
}

class _ChainSubmissionCancelled implements Exception {
  const _ChainSubmissionCancelled();

  @override
  String toString() => 'Chain submission was cancelled.';
}

class _VotingBackgroundWorkQuiesced implements Exception {
  const _VotingBackgroundWorkQuiesced({this.readiness});

  final VotingWalletSyncReadiness? readiness;
}

class _VotingWalletSyncTimeout implements Exception {
  const _VotingWalletSyncTimeout({
    required this.readiness,
    required this.maxWait,
  });

  final VotingWalletSyncReadiness readiness;
  final Duration maxWait;

  @override
  String toString() {
    return 'Wallet sync did not reach this voting round snapshot within '
        '${formatElapsedSeconds(maxWait)}. Scanned block '
        '${formatBlockHeight(readiness.scannedHeight)} of '
        '${formatBlockHeight(readiness.snapshotHeight)}. Let wallet sync '
        'catch up and retry.';
  }
}

class VotingSubmissionSessionNotifier extends VotingSessionNotifier {
  VotingSubmissionSessionNotifier(this._key) : super(_key.roundId);

  final VotingSessionKey _key;
  VotingShareTrackingRegistry? _shareTrackingRegistry;
  void Function()? _closeShareTrackingKeepAlive;

  @override
  bool get _ownsAutomaticShareTracking => true;

  @override
  bool _retainAutomaticShareTracking() {
    if (_closeShareTrackingKeepAlive != null) return true;
    final registry = ref.read(votingShareTrackingRegistryProvider);
    final keepAlive = ref.keepAlive();
    // Register before the submission job drops its guard so account
    // delete/reset can drain this pass through the registry.
    if (!registry.register(
      key: _key,
      owner: this,
      stopAndDrain: stopAndDrainShareTracking,
    )) {
      keepAlive.close();
      return false;
    }
    _shareTrackingRegistry = registry;
    _closeShareTrackingKeepAlive = keepAlive.close;
    return true;
  }

  @override
  void _releaseAutomaticShareTracking() {
    super._releaseAutomaticShareTracking();
    _shareTrackingRegistry?.unregister(key: _key, owner: this);
    _shareTrackingRegistry = null;
    final close = _closeShareTrackingKeepAlive;
    _closeShareTrackingKeepAlive = null;
    close?.call();
  }

  // This subclass must remain in this library because it overrides private
  // hooks to pin background submissions to their original account.
  @override
  void _registerActiveAccountListener() {}

  @override
  Future<void> _refreshSessionAccountFromActiveAccount() async {
    _sessionAccountUuid = _key.accountUuid;
  }

  @override
  Future<void> _refreshEligibleWeightUnlocked() async {
    final current = await future;
    final context = await _loadContext(_roundId);
    await _waitUntilWalletReadyForVoting(context);
    if (context.isHardwareAccount) {
      final signatures = await _loadKeystoneSignatures(context);
      if (signatures.isNotEmpty) {
        final bundleSetup = await ref
            .read(votingRustApiProvider)
            .setupDelegationBundles(ctx: _apiRoundContext(context));
        final refreshedRoundPlan = await _loadRoundPlan(context);
        final successPhase = current.phase == VotingSessionPhase.error
            ? VotingSessionPhase.idle
            : current.phase;
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: successPhase,
            config: context.config,
            round: context.round,
            roundPlan: refreshedRoundPlan,
            eligibleWeightZatoshi: bundleSetup.eligibleWeight,
            privacyTrimDroppedValueZatoshi:
                bundleSetup.privacyTrimDroppedValueZatoshi,
            isHardwareAccount: context.isHardwareAccount,
            clearError: true,
          ),
        );
        return;
      }
    }
    await _refreshVotingEligibilityState(current: current, context: context);
  }
}

final votingSessionProvider =
    AsyncNotifierProvider.family<
      VotingSessionNotifier,
      VotingSessionState,
      String
    >(VotingSessionNotifier.new);

final votingSubmissionSessionProvider = AsyncNotifierProvider.autoDispose
    .family<
      VotingSubmissionSessionNotifier,
      VotingSessionState,
      VotingSessionKey
    >(VotingSubmissionSessionNotifier.new);
