import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatting/duration_format.dart';
import '../../features/voting/voting_error_messages.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_formatters.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/voting.dart' as rust_api;
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

final _minimumVotingBundleWeightZatoshi = BigInt.from(12500000);

/// The PCZT value-pool tag for Ironwood actions.
///
/// Ironwood spend authorization uses a RedPallas key derived from the
/// account's Orchard key, but the action remains in the PCZT's Ironwood bundle.
const _ironwoodPcztPool = 1;

/// Cap for independent voting work pools: delegation proofs, vote proofs,
/// share submission, and recovery polling.
const _votingWorkConcurrency = 3;

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
  final Map<String, Future<void>> _snapshotBundlePrecomputes = {};
  final Set<String> _completedSnapshotBundlePrecomputes = {};
  final Map<String, Future<List<int>>> _hotkeyEnsures = {};
  Timer? _shareTrackingTimer;
  Future<void>? _activeAutomaticShareTrackingPass;
  final Set<Future<void>> _activeShareTrackingPasses = {};
  VotingHelperDeliveryContext? _helperDeliveryContext;
  final Set<VotingShareTrackingPassHandle> _activeShareTrackingPassHandles = {};
  final Set<VotingChainSubmissionPassHandle> _activeChainSubmissionPassHandles =
      {};
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
      resumePlan: context.resumePlan,
      roundPlan: context.roundPlan,
      phase: _phaseForPlans(context.roundPlan),
    );
    _shareTrackingTimer?.cancel();
    await _scheduleShareTracking(context, context.resumePlan);
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
      _completedSnapshotBundlePrecomputes.clear();
      _hotkeyEnsures.clear();
      _shareTrackingTimer?.cancel();
      for (final passHandle in _activeShareTrackingPassHandles.toList()) {
        passHandle.cancel();
        passHandle.dispose();
      }
      _activeShareTrackingPassHandles.clear();
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

  Future<BigInt?> refreshEligibleWeight() {
    return _enqueue(_refreshEligibleWeightUnlocked).then((_) {
      final current = state.value;
      final error = current?.error;
      if (error != null && !isVotingEligibilityErrorText(error.message)) {
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
    final completed = await _runSnapshotBundlePrecompute(
      context: context,
      pirEndpoint: pirEndpoint,
    );
    if (completed && _isCurrentPrecomputeContext(context, accountUuid)) {
      _completedSnapshotBundlePrecomputes.add(precomputeKey);
    }
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
      var plan = context.resumePlan;
      var roundPlan = context.roundPlan;
      if (_needsFreshDelegationWork(plan, roundPlan) &&
          _needsDelegationPreparation(current)) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
        context = await _loadContext(_roundId);
        plan = context.resumePlan;
        roundPlan = context.roundPlan;
      }

      final delegationBundleIndexes = _chainDelegationBundleIndexes(
        plan,
        roundPlan,
      );
      final hasPendingBundles = delegationBundleIndexes.isNotEmpty;
      var pirEndpoint = current.pirEndpoint;
      if (hasPendingBundles && pirEndpoint == null) {
        pirEndpoint = await _resolvePirEndpoint(context);
        _throwIfContextStale(context, 'delegation-pir-resolution');
        if (pirEndpoint != null) {
          current = (state.value ?? current).copyWith(pirEndpoint: pirEndpoint);
          _setStateForContext(context, current);
        }
      }
      if (hasPendingBundles) {
        if (pirEndpoint == null) {
          _setError('PIR endpoint has not been resolved.', context: context);
          return;
        }
        // Software delegation proving still needs the account mnemonic in the
        // current Rust API. Keystone signing uses a separate flow
        // (`delegatePendingBundlesWithKeystoneSignatures`) and never reaches
        // this branch.
        if (mnemonic == null || mnemonic.isEmpty) {
          _setError(
            'Software delegation requires this account mnemonic. Unlock this account or switch to one with mnemonic access.',
            context: context,
          );
          return;
        }
        final nextState = (state.value ?? current).copyWith(
          phase: VotingSessionPhase.delegating,
          resumePlan: plan,
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
      try {
        completedBundleIndexes.addAll(
          await _runDelegationBundleBatch(
            context: context,
            fallbackState: current,
            bundleIndexes: delegationBundleIndexes,
            progress: progress,
            logLabel: 'software',
            prove: (bundleIndex, publishProgress) async {
              await _awaitSnapshotBundlePrecomputeIfRunning(context);
              _throwIfContextStale(context, 'delegation-proof');
              rust_wire.SignedDelegationPayloadView? signedPayload;
              await for (final event
                  in rust.buildProveAndSignDelegationPayloadWithProgress(
                    ctx: _apiRoundContext(context),
                    pirServerUrls: _delegationPirTransportUrls(
                      state.value ?? current,
                    ),
                    mnemonic: mnemonic!,
                    storedHotkeySecret: storedHotkeySecret!,
                    bundleIndex: bundleIndex,
                  )) {
                _throwIfContextStale(context, 'delegation-proof-progress');
                signedPayload = event.signedDelegationPayload ?? signedPayload;
                publishProgress(
                  VotingSessionProgress(
                    phase: event.phase,
                    bundleIndex: bundleIndex,
                    proofProgress: _monotonicProofProgress(
                      progress[bundleIndex]?.proofProgress,
                      event.proofProgress,
                    ),
                  ),
                );
              }
              return signedPayload ??
                  (throw StateError(
                    'Delegation proof completed without submission payload.',
                  ));
            },
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
      }

      final resumeTimer = Stopwatch()..start();
      debugPrint(
        '[zcash] Voting: loading resume plan after delegation '
        'round=${context.round.roundId}',
      );
      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
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
        final result = await rust.storeKeystoneSignaturesBatch(
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
        if (result.conflictingBundleIndex != null) {
          reject(
            'This Keystone result conflicts with a signature already saved for this voting request. Restart Keystone signing and scan the newly generated result.',
          );
          return;
        }
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
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
            keepCount: signedPrefixCount,
          );
      final bundleSetup = await ref
          .read(votingRustApiProvider)
          .setupDelegationBundles(ctx: _apiRoundContext(context));
      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
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
      var plan = context.resumePlan;
      var roundPlan = context.roundPlan;
      if (_needsFreshDelegationWork(plan, roundPlan) &&
          _needsDelegationPreparation(current)) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
        context = await _loadContext(_roundId);
        plan = context.resumePlan;
        roundPlan = context.roundPlan;
      }
      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final completedBundleIndexes = <int>{};
      final delegationBundleIndexes = _chainDelegationBundleIndexes(
        plan,
        roundPlan,
      );
      final hasPendingBundles = delegationBundleIndexes.isNotEmpty;
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
      if (hasPendingBundles && pirEndpoint == null) {
        pirEndpoint = await _resolvePirEndpoint(context);
        _throwIfContextStale(context, 'keystone-delegation-pir-resolution');
        if (pirEndpoint != null) {
          current = (state.value ?? current).copyWith(pirEndpoint: pirEndpoint);
          _setStateForContext(context, current);
        }
      }
      if (hasPendingBundles && pirEndpoint == null) {
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
      try {
        completedBundleIndexes.addAll(
          await _runDelegationBundleBatch(
            context: context,
            fallbackState: current,
            bundleIndexes: delegationBundleIndexes,
            progress: progress,
            logLabel: 'Keystone',
            prove: (bundleIndex, publishProgress) async {
              final signature = signatures[bundleIndex]!;
              rust_wire.SignedDelegationPayloadView? signedPayload;
              await for (final event
                  in rust
                      .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
                        ctx: _apiRoundContext(context),
                        pirServerUrls: _delegationPirTransportUrls(
                          state.value ?? current,
                        ),
                        storedHotkeySecret: storedHotkeySecret!,
                        bundleIndex: bundleIndex,
                        keystoneSig: signature.sig,
                        keystoneSighash: signature.sighash,
                      )) {
                _throwIfContextStale(
                  context,
                  'keystone-delegation-proof-progress',
                );
                signedPayload = event.signedDelegationPayload ?? signedPayload;
                publishProgress(
                  VotingSessionProgress(
                    phase: event.phase,
                    bundleIndex: bundleIndex,
                    proofProgress: _monotonicProofProgress(
                      progress[bundleIndex]?.proofProgress,
                      event.proofProgress,
                    ),
                  ),
                );
              }
              final submission =
                  signedPayload ??
                  (throw StateError(
                    'Delegation proof completed without submission payload.',
                  ));
              _verifyKeystoneDelegationSignature(
                submission: submission,
                signature: signature,
                bundleIndex: bundleIndex,
              );
              return submission;
            },
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
      }

      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
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
    }, cleanupProcessStateOnError: false);
  }

  Future<void> castVotes({
    required List<rust_wire.DraftVote> draftVotes,
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
      var plan = context.resumePlan;
      var roundPlan = context.roundPlan;
      final rust = ref.read(votingRustApiProvider);
      final effectiveDraftVotes = draftVotes;
      final draftVotesByProposal = {
        for (final draftVote in effectiveDraftVotes)
          draftVote.proposalId: draftVote,
      };
      final intentProposalIds = {
        ...?allProposalIds,
        ...draftVotesByProposal.keys,
      }.toList()..sort();
      Future<bool> writeBallotIntents() async {
        if (effectiveDraftVotes.isEmpty) return true;
        // Write durable ballot intent before the cast loop so recovery can
        // resume from the correct choice if the user quits mid-vote.
        for (final proposalId in intentProposalIds) {
          final draftVote = draftVotesByProposal[proposalId];
          final numOptions =
              draftVote?.numOptions ?? proposalOptionCounts?[proposalId];
          if (numOptions == null) {
            _setError(
              'Voting proposal details are missing. Retry after the round reloads.',
              cause: StateError(
                'missing numOptions for proposal_id $proposalId',
              ),
            );
            return false;
          }
          await ref
              .read(votingRecoveryServiceProvider)
              .setBallotIntent(
                dbPath: context.dbPath,
                accountUuid: context.accountUuid,
                roundId: context.round.roundId,
                proposalId: proposalId,
                numOptions: numOptions,
                skipped: draftVote == null,
                choice: draftVote?.choice,
              );
        }
        return true;
      }

      final pendingVotePolling = _pendingVotePollingWork(roundPlan);
      final pollingOutcomes = await _runBoundedBundleWork(
        List<int>.generate(pendingVotePolling.length, (index) => index),
        concurrency: _votingWorkConcurrency,
        work: (index) async {
          final work = pendingVotePolling[index];
          final key = VotingVoteKey(
            bundleIndex: work.bundleIndex,
            proposalId: work.proposalId,
          );
          final commitments = await rust.recoverVoteCommitment(
            dbPath: context.dbPath,
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
            bundleIndex: key.bundleIndex,
            proposalId: key.proposalId,
          );
          await _submitVoteCommitments(context, commitments);
          return key;
        },
      );
      final voteRecoveryFailures = <_VoteWaveFailure>[];
      for (var index = 0; index < pendingVotePolling.length; index++) {
        final outcome = pollingOutcomes[index]!;
        final error = outcome.error;
        if (error != null) {
          final work = pendingVotePolling[index];
          voteRecoveryFailures.add(
            _VoteWaveFailure(
              bundleIndex: work.bundleIndex,
              proposalId: work.proposalId,
              stage: 'recovery confirmation polling',
              error: error,
            ),
          );
          continue;
        }
        final key = outcome.value!;
        progress[key] = VotingSessionProgress(
          phase: 'confirmed',
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
        );
      }
      if (pendingVotePolling.isNotEmpty && voteRecoveryFailures.isEmpty) {
        plan = await _loadResumePlan(context);
        roundPlan = await _loadRoundPlan(context);
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            resumePlan: plan,
            roundPlan: roundPlan,
            voteProgress: progress,
          ),
        );
      }
      for (final failure in voteRecoveryFailures) {
        if (failure.error is _StaleVotingSessionAction) throw failure.error;
      }
      if (voteRecoveryFailures.isNotEmpty) {
        throw _VoteWaveBatchException(voteRecoveryFailures);
      }
      final recoveredVoteWork = _pendingRecoveredVoteWork(roundPlan);
      final recoveredVoteKeys = {
        for (final work in recoveredVoteWork) work.key,
      };
      final bundleIndexesByProposal = <int, List<int>>{
        for (final draftVote in effectiveDraftVotes)
          draftVote.proposalId:
              _pendingVoteBundleIndexesForProposal(plan, draftVote.proposalId)
                  .where(
                    (bundleIndex) => !recoveredVoteKeys.contains(
                      VotingVoteKey(
                        bundleIndex: bundleIndex,
                        proposalId: draftVote.proposalId,
                      ),
                    ),
                  )
                  .toList()
                ..sort(),
      };
      final voteWork = [
        for (final draftVote in effectiveDraftVotes)
          _DraftVoteWork(
            draftVote: draftVote,
            bundleIndexes: bundleIndexesByProposal[draftVote.proposalId]!,
          ),
      ].where((work) => work.bundleIndexes.isNotEmpty).toList();
      final List<int>? storedHotkeySecret;
      if (voteWork.isEmpty) {
        storedHotkeySecret = null;
      } else {
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
      if (!await writeBallotIntents()) {
        return;
      }
      if (effectiveDraftVotes.isNotEmpty) {
        // The immediate-share key is derived from durable ballot intents.
        // Reload after writing them so a fresh cast uses the same stable key
        // that recovery will derive after a restart.
        roundPlan = await _loadRoundPlan(context);
      }
      final totalQuestions = recoveredVoteWork.length + voteWork.length;
      final totalBundleTasks =
          recoveredVoteWork.length +
          voteWork.fold<int>(
            0,
            (total, work) => total + work.bundleIndexes.length,
          );
      final configuredHelperUrls = _configuredHelperTransportUrls(context);
      final helperPreflight = totalBundleTasks == 0
          ? rust_api.ApiVotingHelperPreflight(
              configuredHelperUrls: configuredHelperUrls,
              readyHelperUrls: const [],
            )
          : await rust.preflightVotingHelpers(
              context: _helperDeliveryContextFor(rust, context),
              configuredHelperUrls: configuredHelperUrls,
            );
      _throwIfContextStale(context, 'helper-preflight-finished');
      var completedBundleTasks = 0;
      var completedQuestions = 0;
      final startTiming = _roundShareTiming(context, _nowSeconds());
      _logVoteTiming(
        'cast votes start '
        'round=${context.round.roundId} bundleTasks=$totalBundleTasks '
        'proposals=$totalQuestions '
        'lastMoment=${startTiming.isLastMoment}',
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
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
        );
        await _prepareCommitmentShares(
          context,
          commitments,
          preflight: helperPreflight,
        );
        if (recoveredWork.kind == _RecoveredVoteWorkKind.submitVote) {
          await _submitVoteCommitments(context, commitments);
        } else {
          final vcTreePosition = recoveredWork.vcTreePosition;
          if (vcTreePosition == null) {
            throw StateError(
              'Missing vote tree position for submitted shares '
              'bundle=${key.bundleIndex} proposal=${key.proposalId}.',
            );
          }
        }
        await _submitCommitmentShares(
          context,
          commitments,
          configuredHelperUrls: helperPreflight.configuredHelperUrls,
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
      if (voteWork.isNotEmpty) {
        late final int chainCompleted;
        try {
          chainCompleted = await _runVoteRoundChains(
            context: context,
            fallbackState: current,
            voteWork: voteWork,
            storedHotkeySecret: storedHotkeySecret!,
            progress: progress,
            completedBundleTasks: completedBundleTasks,
            totalBundleTasks: totalBundleTasks,
            completedQuestions: completedQuestions,
            totalQuestions: totalQuestions,
            helperPreflight: helperPreflight,
          );
        } catch (_) {
          plan = await _loadResumePlan(context);
          roundPlan = await _loadRoundPlan(context);
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              resumePlan: plan,
              roundPlan: roundPlan,
              voteProgress: progress,
            ),
          );
          await _scheduleShareTracking(context, plan);
          rethrow;
        }
        completedBundleTasks += chainCompleted;
        completedQuestions += voteWork.length;
        plan = await _loadResumePlan(context);
        roundPlan = await _loadRoundPlan(context);
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.castingVotes,
            resumePlan: plan,
            roundPlan: roundPlan,
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
      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
      final hasBlockingWork = hasBlockingRoundRecoveryWork(refreshedRoundPlan);
      if (!hasBlockingWork) {
        await _clearPersistedDraftChoices(context);
      }
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
          phase: _phaseForPlans(refreshedRoundPlan),
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
    }, cleanupProcessStateOnError: false);
    return operation;
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
    final plan = context.resumePlan;
    return plan.submittedDelegationBundleIndexes.isNotEmpty ||
        plan.pendingVoteSubmissionKeys.isNotEmpty ||
        plan.submittedVoteConfirmationKeys.isNotEmpty ||
        plan.commitmentBundlesByKey.isNotEmpty ||
        plan.shareDelegations.isNotEmpty;
  }

  Future<void> _prepareCommitmentShares(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments, {
    required rust_api.ApiVotingHelperPreflight preflight,
  }) async {
    if (preflight.configuredHelperUrls.isEmpty) {
      throw StateError('No helpers configured for share submission.');
    }
    final rust = ref.read(votingRustApiProvider);
    final timing = _roundShareTiming(context, _nowSeconds());
    final proposalIds = proposalsFromRound(
      context.round,
    ).map((proposal) => proposal.id).toList(growable: false);
    for (final commitment in commitments.commitments) {
      await rust.prepareCommittedShareDelivery(
        context: _helperDeliveryContextFor(rust, context),
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        preflight: preflight,
        nowSeconds: BigInt.from(timing.nowSeconds),
        voteEndTimeSeconds: BigInt.from(timing.voteEndSeconds),
        proposalIds: proposalIds,
        lastMomentBufferSeconds: timing.lastMomentBufferSeconds,
      );
      _throwIfContextStale(context, 'helper-share-planning-finished');
    }
  }

  Future<void> _submitCommitmentShares(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments, {
    required List<String> configuredHelperUrls,
    void Function(VotingSessionProgress progress)? publishProgress,
    required int completedQuestions,
    required int totalQuestions,
    required double? voteSubmissionProgress,
  }) async {
    final rust = ref.read(votingRustApiProvider);
    if (configuredHelperUrls.isEmpty) {
      throw StateError("No helpers configured for share submission.");
    }
    final bundleProgressMessage = _bundleProgressMessage(
      bundleIndex: commitments.bundleIndex,
      bundleCount: context.resumePlan.bundleCount,
    );

    for (final commitment in commitments.commitments) {
      if (publishProgress == null) {
        _setShareSubmissionProgress(
          context: context,
          bundleIndex: commitments.bundleIndex,
          proposalId: commitment.proposalId,
          message: bundleProgressMessage,
          completedQuestions: completedQuestions,
          totalQuestions: totalQuestions,
          voteSubmissionProgress: voteSubmissionProgress,
        );
      } else {
        publishProgress(
          VotingSessionProgress(
            phase: "submitting_shares",
            bundleIndex: commitments.bundleIndex,
            proposalId: commitment.proposalId,
            message: bundleProgressMessage,
          ),
        );
      }

      final report = await rust.submitPreparedSharesToHelpers(
        context: _helperDeliveryContextFor(rust, context),
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        configuredHelperUrls: configuredHelperUrls,
        nowSeconds: BigInt.from(_nowSeconds()),
      );
      _throwIfContextStale(context, "helper-share-delivery-finished");
      if (report.legacyBestEffort) {
        debugPrint(
          "[zcash] Voting: resumed legacy helper delivery without an original complete plan "
          "round=${context.round.roundId} bundle=${commitments.bundleIndex} "
          "proposal=${commitment.proposalId}",
        );
      }
      if (report.cancelled || report.pendingShareIndices.isNotEmpty) {
        throw StateError(
          "Helper-share delivery stopped with pending shares "
          "${report.pendingShareIndices.join(", ")} for proposal "
          "${commitment.proposalId}.",
        );
      }
      final failedDeliveries = report.deliveries.where(
        (delivery) =>
            delivery.submission.acceptedUrls.isEmpty &&
            delivery.submission.ambiguousUrls.isEmpty,
      );
      if (failedDeliveries.isNotEmpty) {
        final failed = failedDeliveries.first;
        throw StateError(
          "No helper accepted share ${failed.shareIndex} for proposal "
          "${commitment.proposalId}.",
        );
      }
      for (final delivery in report.deliveries) {
        final submission = delivery.submission;
        if (submission.acceptedUrls.length < submission.targetCount) {
          debugPrint(
            "[zcash] Voting: share accepted by fewer helpers than planned "
            "proposal=${commitment.proposalId} share=${delivery.shareIndex} "
            "accepted=${submission.acceptedUrls.length}/${submission.targetCount} "
            "ambiguous=${submission.ambiguousUrls.length}",
          );
        }
      }
    }
  }

  /// Syncs the round's vote tree, failing over across configured API servers.
  ///
  /// Failover resets round-global process state, so callers must never run two
  /// of these concurrently — go through [_VoteTreeSyncCoalescer].
  Future<int> _syncVoteTreeWithFailover({
    required _VotingSessionContext context,
    required String label,
  }) async {
    final nodeUrls = context.config.apiServers.all;
    final rust = ref.read(votingRustApiProvider);
    Object? lastError;
    for (var attempt = 0; attempt < nodeUrls.length; attempt++) {
      final nodeUrl = nodeUrls[attempt];
      try {
        return await rust.syncVoteTree(
          dbPath: context.dbPath,
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          nodeUrl: _transportUrl(nodeUrl),
        );
      } catch (error) {
        lastError = error;
        if (attempt == nodeUrls.length - 1) {
          rethrow;
        }
        await rust.resetVoteTree(
          dbPath: context.dbPath,
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
        );
        debugPrint(
          '[zcash] Voting: vote tree sync retrying failover '
          '$label from=$nodeUrl error=$error',
        );
      }
    }
    throw StateError('vote tree sync failover exited unexpectedly: $lastError');
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

  void _logVoteTiming(String message) {
    debugPrint('[zcash] Voting: $message');
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
    final previousProgress = current.voteSubmissionProgress ?? 0;
    final requestedProgress = voteSubmissionProgress ?? previousProgress;
    final monotonicProgress = requestedProgress < previousProgress
        ? previousProgress
        : requestedProgress;
    _setStateForContext(
      context,
      current.copyWith(
        phase: VotingSessionPhase.castingVotes,
        voteProgress: progress,
        voteSubmissionCompletedCount: completedQuestions,
        voteSubmissionTotalCount: totalQuestions,
        voteSubmissionProgress: monotonicProgress,
        clearCurrentBundleIndex: true,
        clearCurrentVoteKey: true,
      ),
    );
  }

  /// Casts every pending vote for the round, running one serial chain per
  /// delegation bundle with all bundles in flight at once.
  ///
  /// The serialization inside a bundle is a protocol requirement, not a
  /// throttle. A cast vote spends the bundle's vote authority note: the proof
  /// binds the current VAN leaf position and the current proposal-authority
  /// mask, submission clears that proposal's bit, and confirmation appends the
  /// replacement VAN leaf and advances the stored position. Proving two
  /// proposals of one bundle against the same state yields the same
  /// `van_nullifier`, so the second cast-vote transaction is a double spend.
  /// Each step therefore waits for `submit -> confirm -> tree re-sync` before
  /// the next proposal of the same bundle is proved.
  ///
  /// Different bundles own independent VAN chains, so they never wait on each
  /// other. Witness materialization stays inside the serialized tree handoff;
  /// only the CPU-heavy proof step is capped ([_votingWorkConcurrency]). A
  /// bundle parked on a block confirmation holds no proof permit. Share
  /// submission is dispatched off the chain because the VAN advance is already
  /// durable by then.
  ///
  /// Returns the number of bundle tasks that completed through share
  /// submission. Throws [_VoteWaveBatchException] if any task failed.
  Future<int> _runVoteRoundChains({
    required _VotingSessionContext context,
    required VotingSessionState fallbackState,
    required List<_DraftVoteWork> voteWork,
    required List<int> storedHotkeySecret,
    required Map<VotingVoteKey, VotingSessionProgress> progress,
    required int completedBundleTasks,
    required int totalBundleTasks,
    required int completedQuestions,
    required int totalQuestions,
    required rust_api.ApiVotingHelperPreflight helperPreflight,
  }) async {
    // Transpose proposal -> bundles into bundle -> proposals. Proposal order
    // within a bundle follows the draft order so a restart resumes the same
    // chain it left off.
    final draftsByBundle = <int, List<rust_wire.DraftVote>>{};
    final voteKeys = <VotingVoteKey>[];
    for (final work in voteWork) {
      for (final bundleIndex in work.bundleIndexes) {
        draftsByBundle
            .putIfAbsent(bundleIndex, () => <rust_wire.DraftVote>[])
            .add(work.draftVote);
        voteKeys.add(
          VotingVoteKey(
            bundleIndex: bundleIndex,
            proposalId: work.draftVote.proposalId,
          ),
        );
      }
    }
    if (voteKeys.isEmpty) return 0;

    final rust = ref.read(votingRustApiProvider);
    // Idempotent and non-blocking: kicked off before the first tree sync so
    // Halo2 keygen overlaps the network round trip instead of landing cold on
    // the first proof.
    rust.warmVotingProvingCaches();
    final roundTimer = Stopwatch()..start();
    final proofWallTimer = Stopwatch()..start();
    final proofElapsed = <VotingVoteKey, Duration>{};
    final failures = <_VoteWaveFailure>[];
    final proofPool = _AsyncPermitPool(_votingWorkConcurrency);
    // Each SDK call owns its full reservation, POST, tracking, and recovery
    // episode. Keep only the app's ordinary work bound here; the SDK's
    // coordinator is the sole authority for chain-submission concurrency.
    final broadcastPool = _AsyncPermitPool(_votingWorkConcurrency);
    final sharePool = _AsyncPermitPool(_votingWorkConcurrency);
    final shareOutcomeFutures =
        <VotingVoteKey, Future<_BundleWorkOutcome<void>>>{};
    var syncCount = 0;
    final treeSync = _VoteTreeSyncCoalescer(() {
      syncCount++;
      return _syncVoteTreeWithFailover(
        context: context,
        label:
            'round=${context.round.roundId} bundles=${draftsByBundle.length}',
      );
    });
    var lastAggregateProgress =
        _voteSubmissionProgress(
          completedBundleTasks: completedBundleTasks,
          totalBundleTasks: totalBundleTasks,
        ) ??
        0;

    double? aggregateProgress() => _aggregateVotePipelineProgress(
      progress: progress,
      voteKeys: voteKeys,
      completedBundleTasks: completedBundleTasks,
      totalBundleTasks: totalBundleTasks,
    );

    void publish(VotingSessionProgress update) {
      final bundleIndex = update.bundleIndex;
      final proposalId = update.proposalId;
      if (bundleIndex == null || proposalId == null) return;
      final key = VotingVoteKey(
        bundleIndex: bundleIndex,
        proposalId: proposalId,
      );
      progress[key] = update;
      final updatedProgress = aggregateProgress() ?? lastAggregateProgress;
      if (updatedProgress > lastAggregateProgress) {
        lastAggregateProgress = updatedProgress;
      }
      // A question counts as done only once every bundle finished it, because
      // bundles now advance through the proposal list independently.
      final completedChainQuestions = voteWork.where((work) {
        return work.bundleIndexes.every(
          (bundleIndex) =>
              progress[VotingVoteKey(
                    bundleIndex: bundleIndex,
                    proposalId: work.draftVote.proposalId,
                  )]
                  ?.phase ==
              'completed',
        );
      }).length;
      _setStateForContext(
        context,
        (state.value ?? fallbackState).copyWith(
          phase: VotingSessionPhase.castingVotes,
          voteProgress: Map<VotingVoteKey, VotingSessionProgress>.of(progress),
          voteSubmissionCompletedCount:
              completedQuestions + completedChainQuestions,
          voteSubmissionTotalCount: totalQuestions,
          voteSubmissionProgress: lastAggregateProgress,
          clearCurrentBundleIndex: true,
          clearCurrentVoteKey: true,
        ),
      );
    }

    void recordFailure({
      required VotingVoteKey key,
      required String stage,
      required Object error,
    }) {
      failures.add(
        _VoteWaveFailure(
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          stage: stage,
          error: error,
        ),
      );
      publish(
        VotingSessionProgress(
          phase: 'failed',
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          proofProgress: progress[key]?.proofProgress,
          message: error.toString(),
        ),
      );
    }

    /// Runs one bundle's proposals in order. A failed step aborts the rest of
    /// this bundle — the next proposal cannot be proved without the VAN
    /// advance the failed step was supposed to produce — but leaves every other
    /// bundle running.
    Future<void> runBundleChain(
      int bundleIndex,
      List<rust_wire.DraftVote> drafts,
    ) async {
      // Attribute anything that escapes the per-stage handlers below.
      // A swallowed error would leave `failures` empty and let the caller
      // report a fully successful round.
      VotingVoteKey? currentKey;
      try {
        for (final draft in drafts) {
          final key = VotingVoteKey(
            bundleIndex: bundleIndex,
            proposalId: draft.proposalId,
          );
          currentKey = key;

          final rust_wire.SignedVoteCommitmentsView commitments;
          try {
            _throwIfContextStale(context, 'vote-chain-sync');
            // A sync that started before this call could predate this bundle's
            // own previous confirmation, so the coalescer only hands back one
            // that started after it.
            final syncTimer = Stopwatch()..start();
            final witness = await treeSync.freshAndUse((anchorHeight) async {
              _logVoteTiming(
                'bundle=$bundleIndex proposal=${draft.proposalId} '
                'tree-sync elapsed=${formatElapsedSeconds(syncTimer.elapsed)} '
                'anchorHeight=$anchorHeight',
              );
              return rust.generateVanWitness(
                dbPath: context.dbPath,
                accountUuid: context.accountUuid,
                roundId: context.round.roundId,
                bundleIndex: bundleIndex,
                anchorHeight: anchorHeight,
              );
            });
            // Re-evaluated per step: a long round can cross into the last-moment
            // buffer part way through a bundle's chain.
            final timedDraft = _draftVoteForCurrentShareMode(context, draft);
            commitments = await proofPool.run(() async {
              _throwIfContextStale(context, 'vote-chain-proof-start');
              final timer = Stopwatch()..start();
              try {
                rust_wire.SignedVoteCommitmentsView? built;
                await for (final event in rust.buildVoteCommitmentsWithProgress(
                  dbPath: context.dbPath,
                  accountUuid: context.accountUuid,
                  network: context.network,
                  roundId: context.round.roundId,
                  bundleIndex: bundleIndex,
                  storedHotkeySecret: storedHotkeySecret,
                  vanWitness: witness,
                  draftVotes: [timedDraft],
                )) {
                  _throwIfContextStale(context, 'vote-chain-proof-progress');
                  final eventKey = VotingVoteKey(
                    bundleIndex: event.bundleIndex ?? bundleIndex,
                    proposalId: event.proposalId ?? draft.proposalId,
                  );
                  publish(
                    VotingSessionProgress(
                      phase: event.phase,
                      bundleIndex: eventKey.bundleIndex,
                      proposalId: eventKey.proposalId,
                      proofProgress: _monotonicProofProgress(
                        progress[eventKey]?.proofProgress,
                        event.proofProgress,
                      ),
                    ),
                  );
                  built = event.commitments ?? built;
                }
                return built ??
                    (throw StateError(
                      'Vote proof completed without commitment payload.',
                    ));
              } finally {
                proofElapsed[key] = timer.elapsed;
                _logVoteTiming(
                  'bundle=$bundleIndex proposal=${draft.proposalId} '
                  'prove elapsed=${formatElapsedSeconds(timer.elapsed)}',
                );
              }
            });
          } catch (error) {
            recordFailure(key: key, stage: 'proof', error: error);
            return;
          }

          try {
            await _prepareCommitmentShares(
              context,
              commitments,
              preflight: helperPreflight,
            );
          } catch (error) {
            recordFailure(
              key: key,
              stage: 'helper-share planning',
              error: error,
            );
            return;
          }

          try {
            _throwIfContextStale(context, 'vote-chain-submit');
            final submitTimer = Stopwatch()..start();
            await broadcastPool.run(() async {
              // The context can become stale while this bundle waits for a
              // work permit. Revalidate after acquiring it so a queued bundle
              // cannot start an SDK episode for an inactive session.
              _throwIfContextStale(context, 'vote-chain-submit-acquired');
              await _submitVoteCommitments(context, commitments);
            });
            _logVoteTiming(
              'bundle=$bundleIndex proposal=${key.proposalId} '
              'submit-confirm elapsed=${formatElapsedSeconds(submitTimer.elapsed)}',
            );
            publish(
              VotingSessionProgress(
                phase: 'confirmed',
                bundleIndex: bundleIndex,
                proposalId: key.proposalId,
                proofProgress: 1,
              ),
            );
          } catch (error) {
            recordFailure(key: key, stage: 'submission', error: error);
            return;
          }

          // Shares are off the chain: the VAN advance is durable, so the next
          // proposal does not wait on helper-server delivery.
          shareOutcomeFutures[key] = _captureBundleWork(
            () => sharePool.run(() async {
              final shareTimer = Stopwatch()..start();
              await _submitCommitmentShares(
                context,
                commitments,
                configuredHelperUrls: helperPreflight.configuredHelperUrls,
                publishProgress: publish,
                completedQuestions: completedQuestions,
                totalQuestions: totalQuestions,
                voteSubmissionProgress: aggregateProgress(),
              );
              _logVoteTiming(
                'bundle=$bundleIndex proposal=${key.proposalId} '
                'shares elapsed=${formatElapsedSeconds(shareTimer.elapsed)}',
              );
              publish(
                VotingSessionProgress(
                  phase: 'completed',
                  bundleIndex: bundleIndex,
                  proposalId: key.proposalId,
                  proofProgress: 1,
                ),
              );
            }),
          );
        }
      } catch (error) {
        failures.add(
          _VoteWaveFailure(
            bundleIndex: bundleIndex,
            proposalId: currentKey?.proposalId ?? drafts.first.proposalId,
            stage: 'chain',
            error: error,
          ),
        );
      }
    }

    await Future.wait([
      for (final entry in draftsByBundle.entries)
        _captureBundleWork(() => runBundleChain(entry.key, entry.value)),
    ]);

    final serialProofDuration = proofElapsed.values.fold<Duration>(
      Duration.zero,
      (total, elapsed) => total + elapsed,
    );
    _logVoteTiming(
      'vote chains proof time '
      'round=${context.round.roundId} proposals=${voteWork.length} '
      'bundles=${draftsByBundle.length} tasks=${voteKeys.length} '
      'treeSyncs=$syncCount concurrency=$_votingWorkConcurrency '
      'wall=${formatElapsedSeconds(proofWallTimer.elapsed)} '
      'serialEquivalent=${formatElapsedSeconds(serialProofDuration)}',
    );

    final shareOutcomes = <VotingVoteKey, _BundleWorkOutcome<void>>{};
    await Future.wait(
      shareOutcomeFutures.entries.map((entry) async {
        shareOutcomes[entry.key] = await entry.value;
      }),
    );

    var completed = 0;
    for (final entry in shareOutcomes.entries) {
      final outcome = entry.value;
      if (outcome.error != null) {
        recordFailure(key: entry.key, stage: 'shares', error: outcome.error!);
        continue;
      }
      completed++;
    }

    if (failures.isNotEmpty) {
      // A stale session is a control-flow signal, not a per-task failure; let
      // it unwind on its own so the caller can drop the abandoned round.
      for (final failure in failures) {
        if (failure.error is _StaleVotingSessionAction) throw failure.error;
      }
      throw _VoteWaveBatchException(failures);
    }
    _logVoteTiming(
      'vote chains completed '
      'round=${context.round.roundId} proposals=${voteWork.length} '
      'bundles=${draftsByBundle.length} tasks=$completed '
      'elapsed=${formatElapsedSeconds(roundTimer.elapsed)}',
    );
    return completed;
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

  Future<Map<int, BigInt>> _submitVoteCommitments(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments,
  ) async {
    final rust = ref.read(votingRustApiProvider);
    final vcTreePositions = <int, BigInt>{};
    for (final commitment in commitments.commitments) {
      debugPrint(
        '[zcash] Voting: submitting cast-vote '
        'round=${context.round.roundId} bundle=${commitments.bundleIndex} '
        'proposal=${commitment.proposalId}',
      );
      final outcome = await _runChainSubmissionEpisode(
        context,
        (passHandle, recoveryMode) => rust.advanceChainVote(
          passHandle: passHandle,
          bundleIndex: commitments.bundleIndex,
          proposalId: commitment.proposalId,
          recoveryMode: recoveryMode,
        ),
      );
      final vcTreePosition = outcome.voteCommitmentPositions.singleOrNull;
      if (vcTreePosition == null) {
        throw StateError(
          'Confirmed vote submission did not include one commitment position.',
        );
      }
      debugPrint(
        '[zcash] Voting: cast-vote confirmed '
        'proposal=${commitment.proposalId} '
        'txHash=${outcome.transactionHash} '
        'vanPosition=${outcome.finalVanPosition} '
        'vcTreePosition=$vcTreePosition',
      );
      vcTreePositions[commitment.proposalId] = vcTreePosition;
    }
    return vcTreePositions;
  }

  Future<rust_api.ApiChainSubmissionOutcome> _runChainSubmissionEpisode(
    _VotingSessionContext context,
    Future<rust_api.ApiChainSubmissionCallResult> Function(
      VotingChainSubmissionPassHandle passHandle,
      rust_api.ApiChainRecoveryMode recoveryMode,
    )
    advance,
  ) async {
    final rust = ref.read(votingRustApiProvider);
    final passHandle = rust.beginChainSubmissionPass(
      dbPath: context.dbPath,
      accountUuid: context.accountUuid,
      roundId: context.round.roundId,
      network: context.network,
      endpoints: context.config.apiServers.all
          .map(_transportUrl)
          .toList(growable: false),
      operationEpoch: BigInt.from(context.sessionGeneration),
    );
    _activeChainSubmissionPassHandles.add(passHandle);
    var exactRecoveryAttempted = false;
    try {
      while (true) {
        _throwIfContextStale(context, 'chain-submission-advance');
        final recoveryMode = exactRecoveryAttempted
            ? rust_api.ApiChainRecoveryMode.exactTree
            : rust_api.ApiChainRecoveryMode.statusOnly;
        final result = await advance(passHandle, recoveryMode);
        final failure = result.failure;
        if (failure != null) throw _ChainSubmissionFailure(failure);
        final outcome = result.outcome;
        if (outcome == null) {
          throw StateError(
            'Chain submission returned neither an outcome nor a failure.',
          );
        }
        switch (outcome.kind) {
          case rust_api.ApiChainSubmissionOutcomeKind.confirmed:
            return outcome;
          case rust_api.ApiChainSubmissionOutcomeKind.tracking:
            await Future.any<void>([
              Future<void>.delayed(const Duration(seconds: 2)),
              _sessionInvalidated.future,
            ]);
            continue;
          case rust_api.ApiChainSubmissionOutcomeKind.recovering:
            if (outcome.diagnostic?.kind ==
                rust_api.ApiChainDiagnosticKind.recoveryUnavailable) {
              throw _ChainSubmissionPending(outcome);
            }
            if (exactRecoveryAttempted) {
              throw _ChainSubmissionPending(outcome);
            }
            exactRecoveryAttempted = true;
            continue;
          case rust_api.ApiChainSubmissionOutcomeKind.rejected:
            throw _ChainSubmissionRejected(outcome);
          case rust_api.ApiChainSubmissionOutcomeKind.cancelled:
            _throwIfContextStale(context, 'chain-submission-cancelled');
            throw const _ChainSubmissionCancelled();
        }
      }
    } finally {
      _activeChainSubmissionPassHandles.remove(passHandle);
      passHandle.dispose();
    }
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
      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
      _throwIfContextStale(context, 'delegation-batch-failure-refresh');
      _setStateForContext(
        context,
        (state.value ?? fallbackState).copyWith(
          resumePlan: refreshedPlan,
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

  Future<Set<int>> _runDelegationBundleBatch({
    required _VotingSessionContext context,
    required VotingSessionState fallbackState,
    required List<int> bundleIndexes,
    required Map<int, VotingSessionProgress> progress,
    required Future<rust_wire.SignedDelegationPayloadView> Function(
      int bundleIndex,
      void Function(VotingSessionProgress progress) publishProgress,
    )
    prove,
    required String logLabel,
  }) async {
    final batchTimer = Stopwatch()..start();
    final proofWallTimer = Stopwatch()..start();
    final timers = <int, Stopwatch>{};
    final proofElapsed = <int, Duration>{};

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

    final proofOutcomes = await _runBoundedBundleWork(
      bundleIndexes,
      concurrency: _votingWorkConcurrency,
      work: (bundleIndex) async {
        _throwIfContextStale(context, '$logLabel-proof-start');
        final timer = Stopwatch()..start();
        timers[bundleIndex] = timer;
        debugPrint(
          '[zcash] Voting: $logLabel delegation bundle start '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        try {
          final submission = await prove(bundleIndex, publishProgress);
          debugPrint(
            '[zcash] Voting: $logLabel delegation proof stream completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'elapsed=${formatElapsedSeconds(timer.elapsed)}',
          );
          return submission;
        } finally {
          proofElapsed[bundleIndex] = timer.elapsed;
        }
      },
    );
    final serialProofDuration = proofElapsed.values.fold<Duration>(
      Duration.zero,
      (total, elapsed) => total + elapsed,
    );
    debugPrint(
      '[zcash] Voting: $logLabel delegation proof fan-in '
      'round=${context.round.roundId} bundles=${bundleIndexes.length} '
      'concurrency=$_votingWorkConcurrency '
      'wall=${formatElapsedSeconds(proofWallTimer.elapsed)} '
      'serialEquivalent=${formatElapsedSeconds(serialProofDuration)}',
    );

    _throwIfContextStale(context, '$logLabel-proof-fan-in');
    final failures = <_DelegationBundleFailure>[];
    final completed = <int>{};

    // Advance each semantic generation serially. The SDK owns reservation,
    // dispatch classification, status polling, recovery, and confirmation.
    for (final bundleIndex in bundleIndexes) {
      final proof = proofOutcomes[bundleIndex]!;
      if (proof.error != null) {
        publishProgress(
          VotingSessionProgress(
            phase: 'failed',
            bundleIndex: bundleIndex,
            message: proof.error.toString(),
          ),
        );
        failures.add(
          _DelegationBundleFailure(
            bundleIndex: bundleIndex,
            stage: 'proof',
            error: proof.error!,
          ),
        );
        continue;
      }
      try {
        _throwIfContextStale(context, '$logLabel-delegation-submit');
        final outcome = await _submitDelegation(
          context: context,
          bundleIndex: bundleIndex,
          submission: proof.value!,
        );
        completed.add(bundleIndex);
        publishProgress(
          VotingSessionProgress(
            phase: 'confirmed',
            bundleIndex: bundleIndex,
            message: outcome.transactionHash,
          ),
        );
        debugPrint(
          '[zcash] Voting: $logLabel delegation bundle completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'leafIndex=${outcome.finalVanPosition} '
          'total=${formatElapsedSeconds(timers[bundleIndex]!.elapsed)}',
        );
      } catch (error) {
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
            stage: 'submission',
            error: error,
          ),
        );
        if (error is _StaleVotingSessionAction) {
          break;
        }
      }
    }

    for (final failure in failures) {
      if (failure.error is _StaleVotingSessionAction) {
        throw failure.error;
      }
    }
    if (failures.isNotEmpty) {
      throw _DelegationBundleBatchException(failures);
    }
    debugPrint(
      '[zcash] Voting: $logLabel delegation batch completed '
      'round=${context.round.roundId} bundles=${bundleIndexes.length} '
      'elapsed=${formatElapsedSeconds(batchTimer.elapsed)}',
    );
    return completed;
  }

  Future<rust_api.ApiChainSubmissionOutcome> _submitDelegation({
    required _VotingSessionContext context,
    required int bundleIndex,
    required rust_wire.SignedDelegationPayloadView submission,
  }) async {
    final rust = ref.read(votingRustApiProvider);
    final submitTimer = Stopwatch()..start();
    debugPrint(
      '[zcash] Voting: submitting delegation '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    final outcome = await _runChainSubmissionEpisode(
      context,
      (passHandle, recoveryMode) => rust.advanceChainDelegation(
        passHandle: passHandle,
        bundleIndex: bundleIndex,
        submission: submission,
        recoveryMode: recoveryMode,
      ),
    );
    debugPrint(
      '[zcash] Voting: delegation confirmed '
      'round=${context.round.roundId} bundle=$bundleIndex '
      'txHash=${outcome.transactionHash} '
      'elapsed=${formatElapsedSeconds(submitTimer.elapsed)}',
    );
    return outcome;
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
        var plan = await _loadResumePlan(context);
        var roundPlan = await _loadRoundPlan(context);
        if (hasConfirmedImmediateShare(roundPlan, plan)) {
          confirmed = true;
          return;
        }

        final immediateKey = roundPlan.immediateShareKey;
        if (immediateKey == null) return;
        rust_wire.ShareDelegationRecordView? immediateShare;
        for (final share in plan.shareDelegations) {
          if (share.bundleIndex == immediateKey.bundleIndex &&
              share.proposalId == immediateKey.proposalId &&
              share.shareIndex == immediateKey.shareIndex) {
            immediateShare = share;
            break;
          }
        }
        if (immediateShare == null || immediateShare.confirmed) return;
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
          plan = await _loadResumePlan(context);
          roundPlan = await _loadRoundPlan(context);
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              phase: _phaseForPlans(roundPlan),
              resumePlan: plan,
              roundPlan: roundPlan,
            ),
          );
          if (plan.unconfirmedShareDelegations.isEmpty) {
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
      var plan = await _loadResumePlan(context);
      var roundPlan = await _loadRoundPlan(context);
      if (ref.read(appSecurityProvider).requiresUnlock ||
          !shouldTrackPendingVotingShares(context.round)) {
        _setStateForContext(
          context,
          current.copyWith(
            phase: _phaseForPlans(roundPlan),
            resumePlan: plan,
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
          resumePlan: plan,
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
      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
      final hasBlockingWork = hasBlockingRoundRecoveryWork(refreshedRoundPlan);
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
    VotingResumePlan plan,
  ) async {
    if (!_ownsAutomaticShareTracking) {
      _shareTrackingTimer?.cancel();
      _shareTrackingTimer = null;
      _releaseAutomaticShareTracking();
      return;
    }
    if (_automaticShareTrackingStopped ||
        plan.unconfirmedShareDelegations.isEmpty ||
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
          shares: plan.unconfirmedShareDelegations,
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

  Future<bool> _runSnapshotBundlePrecompute({
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
      return await _runBackgroundDelegationProofPrecompute(
        context: context,
        pirEndpoint: pirEndpoint,
        bundleCount: result.bundleCount,
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: snapshot bundle precompute failed '
        'round=${context.round.roundId} '
        'elapsed=${formatElapsedSeconds(timer.elapsed)} error=$e '
        'reason=cache-miss',
      );
      return false;
    }
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

    var allProofsReady = true;
    for (var bundleIndex = 0; bundleIndex < bundleCount; bundleIndex++) {
      if (!_isCurrentPrecomputeContext(context, context.accountUuid)) {
        return false;
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
        allProofsReady = false;
      }
    }
    return allProofsReady;
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
        if (publishError) _setError(_actionErrorMessage(e), cause: e);
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

  static bool _needsFreshDelegationWork(
    VotingResumePlan plan,
    rust_wire.RoundPlanView? roundPlan,
  ) {
    if (plan.pendingDelegationBundleIndexes.isNotEmpty) return true;
    if (roundPlan == null) return false;
    return roundPlan.needsDelegationSigning ||
        roundPlanNeedsDraftSetup(roundPlan);
  }

  static List<int> _chainDelegationBundleIndexes(
    VotingResumePlan plan,
    rust_wire.RoundPlanView? roundPlan,
  ) {
    final indexes = <int>{...plan.pendingDelegationBundleIndexes};
    for (final record in plan.recoveryState.delegation) {
      if (record.phase == VotingWorkflowPhase.submittedDelegation) {
        indexes.add(record.bundleIndex);
      }
    }
    for (final work
        in roundPlan?.recoveredDelegationWork ??
            const <rust_wire.DelegationRecoveryWorkView>[]) {
      indexes.add(work.bundleIndex);
    }
    return indexes.toList()..sort();
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

    var plan = current.resumePlan ?? context.resumePlan;
    var roundPlan = current.roundPlan ?? context.roundPlan;
    var signatures = await _loadKeystoneSignatures(context);
    var unsignedBundleIndexes = plan.pendingDelegationBundleIndexes
        .where((bundleIndex) => !signatures.containsKey(bundleIndex))
        .toList();
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

    final storedHotkeySecret =
        existingHotkey ??
        await _ensureHotkey(context, alreadyBound: signatures.isNotEmpty);

    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.keystoneSigning,
        isHardwareAccount: true,
        resumePlan: plan,
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
      plan = await _loadResumePlan(context);
      roundPlan = await _loadRoundPlan(context);
      signatures = await _loadKeystoneSignatures(context);
      final maxBundleIndex = plan.bundleCount;
      if (maxBundleIndex >= 0) {
        signatures = {
          for (final entry in signatures.entries)
            if (entry.key >= 0 && entry.key < maxBundleIndex)
              entry.key: entry.value,
        };
      }
      unsignedBundleIndexes = plan.pendingDelegationBundleIndexes
          .where((bundleIndex) => !signatures.containsKey(bundleIndex))
          .toList();
      if (unsignedBundleIndexes.isEmpty) {
        _setStateForContext(
          context,
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.readyToDelegate,
            isHardwareAccount: true,
            resumePlan: plan,
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
          resumePlan: plan,
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
        resumePlan: plan,
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

    await _awaitSnapshotBundlePrecomputeIfRunning(context);
    _throwIfContextStale(context, 'snapshot-bundle-precompute');
    final bundleSetup = await ref
        .read(votingRustApiProvider)
        .setupDelegationBundles(ctx: _apiRoundContext(context));
    final refreshedPlan = await _loadResumePlan(context);
    final refreshedRoundPlan = await _loadRoundPlan(context);
    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.readyToDelegate,
        resumePlan: refreshedPlan,
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
      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
      final successPhase = current.phase == VotingSessionPhase.error
          ? VotingSessionPhase.idle
          : current.phase;
      final base = (state.value ?? current).copyWith(
        phase: eligibility.isEligible ? successPhase : VotingSessionPhase.error,
        config: context.config,
        round: context.round,
        resumePlan: refreshedPlan,
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
                  message: _minimumVotingEligibilityErrorMessage(
                    eligibility: eligibility,
                    snapshotHeight: context.round.snapshotHeight,
                  ),
                ),
              ),
      );
    } catch (error) {
      final message = friendlyVotingErrorMessage(error);
      final eligibilityError = isVotingEligibilityErrorText(message);
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.error,
          config: context.config,
          round: context.round,
          resumePlan: context.resumePlan,
          roundPlan: context.roundPlan,
          eligibleWeightZatoshi: eligibilityError ? BigInt.zero : null,
          privacyTrimDroppedValueZatoshi: eligibilityError ? BigInt.zero : null,
          isHardwareAccount: context.isHardwareAccount,
          error: VotingSessionError(message: message, cause: error),
        ),
      );
    }
  }

  String _minimumVotingEligibilityErrorMessage({
    required rust_api.ApiVotingEligibility eligibility,
    required int snapshotHeight,
  }) {
    return 'minimum voting eligibility requires at least one eligible voting '
        'bundle with $_minimumVotingBundleWeightZatoshi zatoshi voting weight; '
        'selected '
        '${eligibility.distinctNoteCount} distinct notes across eligible '
        'bundles with ${eligibility.eligibleWeightZatoshi} zatoshi eligible '
        'bundle weight at '
        'snapshot height $snapshotHeight';
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
    final resumePlan = await ref
        .read(votingRecoveryServiceProvider)
        .loadResumePlan(
          dbPath: dbPath,
          accountUuid: accountUuid,
          roundId: round.roundId,
        );
    // Build a temporary context without roundPlan to derive proposalIds.
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

  Future<VotingResumePlan> _loadResumePlan(_VotingSessionContext context) {
    return ref
        .read(votingRecoveryServiceProvider)
        .loadResumePlan(
          dbPath: context.dbPath,
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
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

  /// Preserves resolved PIR diagnostics unless the error supplies replacements.
  void _setError(
    String message, {
    Object? cause,
    List<PirSnapshotEndpointDiagnostic>? pirDiagnostics,
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
          pirDiagnostics: pirDiagnostics ?? const [],
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
    for (final passHandle in _activeChainSubmissionPassHandles.toList()) {
      passHandle.setOperationEpoch(operationEpoch);
      passHandle.cancel();
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
    switch (roundPlan?.primaryAction) {
      case 'done':
        return VotingSessionPhase.done;
      case 'delegate':
        return VotingSessionPhase.readyToDelegate;
      case 'vote':
        return VotingSessionPhase.readyToVote;
      case 'submit_shares':
        return VotingSessionPhase.submittingShares;
    }
    return VotingSessionPhase.idle;
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

  static Set<int> _pendingVoteBundleIndexesForProposal(
    VotingResumePlan plan,
    int proposalId,
  ) {
    final bundleCount = plan.bundleCount;
    if (bundleCount == 0) return const {};
    return {
      for (var bundleIndex = 0; bundleIndex < bundleCount; bundleIndex++)
        if (_shouldSubmitVoteBundle(
          plan,
          VotingVoteKey(bundleIndex: bundleIndex, proposalId: proposalId),
        ))
          bundleIndex,
    };
  }

  /// Vote work whose chain transaction has already been dispatched.
  ///
  /// The SDK reports one `advance_vote` kind for a vote's whole chain
  /// lifecycle, because reserving, submitting, and reconciling are a single
  /// bounded call. A recorded `txHash` is what distinguishes a generation that
  /// is already on the wire from one that has not been dispatched yet.
  static List<rust_wire.VoteRecoveryWorkView> _pendingVotePollingWork(
    rust_wire.RoundPlanView? roundPlan,
  ) {
    return [
      for (final work
          in roundPlan?.recoveredVoteWork ??
              const <rust_wire.VoteRecoveryWorkView>[])
        if (work.kind == 'advance_vote' && work.txHash != null) work,
    ];
  }

  static List<_RecoveredVoteWork> _pendingRecoveredVoteWork(
    rust_wire.RoundPlanView? roundPlan,
  ) {
    if (roundPlan == null) return const [];
    return [
      for (final work in roundPlan.recoveredVoteWork)
        if ((work.kind == 'advance_vote' && work.txHash == null) ||
            work.kind == 'submit_shares')
          _RecoveredVoteWork(
            kind: work.kind == 'advance_vote'
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

  rust_wire.DraftVote _draftVoteForCurrentShareMode(
    _VotingSessionContext context,
    rust_wire.DraftVote draftVote,
  ) {
    if (draftVote.singleShare) return draftVote;
    final timing = _roundShareTiming(context, _nowSeconds());
    if (!timing.isLastMoment) return draftVote;
    return rust_wire.DraftVote(
      proposalId: draftVote.proposalId,
      choice: draftVote.choice,
      numOptions: draftVote.numOptions,
      vcTreePosition: draftVote.vcTreePosition,
      singleShare: true,
    );
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

  static bool _shouldSubmitVoteBundle(
    VotingResumePlan plan,
    VotingVoteKey key,
  ) {
    final phase = plan.votePhasesByKey[key];
    if (phase == VotingWorkflowPhase.confirmed ||
        phase == VotingWorkflowPhase.submittedVote) {
      return false;
    }
    return !plan.voteTxHashesByKey.containsKey(key);
  }

  static void _verifyKeystoneDelegationSignature({
    required rust_wire.SignedDelegationPayloadView submission,
    required rust_wire.KeystoneSignatureRecord signature,
    required int bundleIndex,
  }) {
    final wire = submission.submission;
    if (!_bytesEqual(_decodeBase64(wire.rk), signature.rk) ||
        !_bytesEqual(_decodeBase64(wire.spendAuthSig), signature.sig)) {
      throw StateError(
        'Keystone signature did not match delegation bundle $bundleIndex.',
      );
    }
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

  static bool _isKeystoneSetupOverwriteError(Object error) {
    final normalized = error
        .toString()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');
    return normalized.contains('refusing to overwrite pczt sighash') ||
        normalized.contains('refusing to overwrite pczt hash') ||
        normalized.contains('refusing to overwrite padded note secrets');
  }
}

class _DraftVoteWork {
  const _DraftVoteWork({required this.draftVote, required this.bundleIndexes});

  final rust_wire.DraftVote draftVote;
  final List<int> bundleIndexes;
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

Future<_BundleWorkOutcome<T>> _captureBundleWork<T>(
  Future<T> Function() work,
) async {
  try {
    return _BundleWorkOutcome.success(await work());
  } catch (error, stackTrace) {
    return _BundleWorkOutcome.failure(error, stackTrace);
  }
}

/// Serializes vote-tree syncs and batches concurrent requesters onto one call.
///
/// Two guarantees matter to callers:
///
/// * **Protected handoff.** `_syncVoteTreeWithFailover` resets round-global
///   process state when it fails over to another node, so the next sync cannot
///   start until every caller served by the previous sync has materialized its
///   witness.
/// * **Never stale.** `freshAndUse()` only uses the result of a sync that
///   *started after* the call. A bundle that just recorded a vote confirmation
///   therefore cannot be handed an anchor height from a sync that predates its
///   new VAN leaf. Requests arriving while a sync runs are batched into the
///   next one, so N bundles finishing a proposal together cost one round trip.
class _VoteTreeSyncCoalescer {
  _VoteTreeSyncCoalescer(this._sync);

  final Future<int> Function() _sync;
  final Queue<_VoteTreeSyncRequestBase> _waiting =
      Queue<_VoteTreeSyncRequestBase>();
  bool _running = false;

  Future<T> freshAndUse<T>(Future<T> Function(int anchorHeight) useTree) {
    final request = _VoteTreeSyncRequest<T>(useTree);
    _waiting.addLast(request);
    // Deferred so every requester in this turn joins the same sync — bundles
    // that finish a proposal together should cost one round trip, not N.
    // Delaying the start can only add requesters ahead of it, so the
    // "started after my call" guarantee still holds.
    scheduleMicrotask(_pump);
    return request.future;
  }

  void _pump() {
    if (_running || _waiting.isEmpty) return;
    _running = true;
    // Everyone registered *before* this sync starts is served by it; anyone who
    // registers after this point waits for the following run.
    final batch = _waiting.toList(growable: false);
    _waiting.clear();
    Future<int> attempt;
    try {
      attempt = _sync();
    } catch (error, stackTrace) {
      // A synchronous throw would otherwise leave `_running` latched and hang
      // every later requester instead of failing them.
      attempt = Future<int>.error(error, stackTrace);
    }
    attempt
        .then(
          (anchorHeight) async {
            await Future.wait([
              for (final request in batch) request.completeWith(anchorHeight),
            ]);
          },
          onError: (Object error, StackTrace stackTrace) {
            for (final request in batch) {
              request.completeError(error, stackTrace);
            }
          },
        )
        .whenComplete(() {
          _running = false;
          scheduleMicrotask(_pump);
        });
  }
}

abstract interface class _VoteTreeSyncRequestBase {
  Future<void> completeWith(int anchorHeight);

  void completeError(Object error, StackTrace stackTrace);
}

class _VoteTreeSyncRequest<T> implements _VoteTreeSyncRequestBase {
  _VoteTreeSyncRequest(this._useTree);

  final Future<T> Function(int anchorHeight) _useTree;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  @override
  Future<void> completeWith(int anchorHeight) async {
    try {
      _completer.complete(await _useTree(anchorHeight));
    } catch (error, stackTrace) {
      _completer.completeError(error, stackTrace);
    }
  }

  @override
  void completeError(Object error, StackTrace stackTrace) {
    _completer.completeError(error, stackTrace);
  }
}

class _AsyncPermitPool {
  _AsyncPermitPool(int concurrency)
    : assert(concurrency > 0),
      _availablePermits = concurrency;

  int _availablePermits;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() work) async {
    await _acquire();
    try {
      return await work();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_availablePermits > 0) {
      _availablePermits--;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _availablePermits++;
    }
  }
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

class _DelegationBundleBatchException implements Exception {
  const _DelegationBundleBatchException(this.failures);

  final List<_DelegationBundleFailure> failures;

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

class _VoteWaveFailure {
  const _VoteWaveFailure({
    required this.bundleIndex,
    required this.proposalId,
    required this.stage,
    required this.error,
  });

  final int bundleIndex;
  final int proposalId;
  final String stage;
  final Object error;
}

class _VoteWaveBatchException implements Exception {
  const _VoteWaveBatchException(this.failures);

  final List<_VoteWaveFailure> failures;

  @override
  String toString() {
    final details = failures
        .map(
          (failure) =>
              'bundle ${failure.bundleIndex + 1} '
              'proposal ${failure.proposalId} ${failure.stage}: '
              '${failure.error}',
        )
        .join('; ');
    return 'Vote casting failed: $details';
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
  final VotingResumePlan resumePlan;
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
    required this.resumePlan,
    this.roundPlan,
  });
}

class _StaleVotingSessionAction implements Exception {
  const _StaleVotingSessionAction();
}

class _ChainSubmissionFailure implements Exception {
  const _ChainSubmissionFailure(this.failure);

  final rust_api.ApiChainSubmissionFailure failure;

  @override
  String toString() {
    final strongest = failure.strongestState;
    final state = strongest == null
        ? ''
        : ' (state=${strongest.state.name}, evidence=${strongest.evidence.name})';
    return '${failure.message}$state';
  }
}

class _ChainSubmissionPending implements Exception {
  const _ChainSubmissionPending(this.outcome);

  final rust_api.ApiChainSubmissionOutcome outcome;

  @override
  String toString() =>
      outcome.diagnostic?.message ??
      'Chain submission recovery is still pending.';
}

class _ChainSubmissionRejected implements Exception {
  const _ChainSubmissionRejected(this.outcome);

  final rust_api.ApiChainSubmissionOutcome outcome;

  @override
  String toString() =>
      outcome.diagnostic?.message ?? 'Chain submission was rejected.';
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
        final refreshedPlan = await _loadResumePlan(context);
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
            resumePlan: refreshedPlan,
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
