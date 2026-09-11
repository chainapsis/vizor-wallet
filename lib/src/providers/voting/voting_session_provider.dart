import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatting/duration_format.dart';
import '../../core/storage/linux_keyring_coordinator.dart';
import '../../core/storage/linux_secret_operation_guard.dart';
import '../account_provider.dart';
import '../../features/voting/voting_error_messages.dart';
import '../../services/voting/voting_rust_exception.dart';
import '../../services/voting/voting_retry.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_formatters.dart';
import '../../features/voting/voting_progress_presentation.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/voting.dart' as rust_api;
import '../../rust/api/voting_session.dart' as rust_session;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../app_security_provider.dart';
import 'voting_config_provider.dart';
import 'voting_home_cache_provider.dart';
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

// Background setup and QR preparation can briefly contend for the SDK's
// bundle lease. Retrying reuses its persisted transaction and proof work.
final _delegationSetupRetryPolicy = VotingRetryPolicy(
  name: 'delegation setup',
  delays: const [
    Duration(milliseconds: 100),
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ],
  shouldRetry: (error) =>
      votingRustExceptionOf(error)?.kind == rust_wire.VotingErrorKindView.busy,
);

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

  void _releaseAutomaticShareTracking() {}

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

  /// The tracking run in flight, the session it runs on, and the context it
  /// was started for.
  ///
  /// One run per notifier: the SDK drives passes to quiescence itself, so a
  /// second concurrent run would only contend for the same share locks. The
  /// context is what distinguishes that from a superseded run still unwinding
  /// after cancellation, which must not block the next one from starting.
  Future<void>? _shareTrackingRun;
  VotingRoundSession? _shareTrackingSession;
  _VotingSessionContext? _shareTrackingContext;

  /// Pending re-arm of a run that stopped on a condition a later run could
  /// clear, and how many consecutive times that has happened.
  ///
  /// The streak drives the backoff and resets as soon as a run reaches a
  /// quiescence that is not retryable.
  Timer? _shareTrackingRetryTimer;
  int _shareTrackingRetryStreak = 0;

  /// The focused immediate-share check in flight, and its session.
  ///
  /// Drained alongside a tracking run: it touches the same sidecar, so a
  /// destructive wallet operation must wait for it too.
  Future<void>? _focusedConfirmation;
  VotingRoundSession? _focusedConfirmationSession;
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
    // Only the notifier that owns automatic tracking starts a run by itself.
    // A screen-scoped notifier still tracks when something asks it to, but it
    // does not begin polling helpers merely by being watched.
    if (_ownsAutomaticShareTracking) unawaited(_startShareTracking(context));
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
      // Preserve durable setup for background proofs and later signing.
      // Only the round-scoped vote-tree cache is released on disposal.
      _isDisposed = true;
      _advanceSessionGeneration();
      _snapshotBundlePrecomputes.clear();
      _backgroundDelegationProofPrecomputes.clear();
      _completedSnapshotBundlePrecomputes.clear();
      _cancelShareTrackingRetry();
      for (final session in _activeRoundSessions.toList()) {
        session.cancel();
        session.dispose();
      }
      _activeRoundSessions.clear();
      _releaseAutomaticShareTracking();
      if (context == null) return;
      if (ownsSubmission) {
        debugPrint(
          '[zcash] Voting: session cache reset skipped '
          'round=${context.round.roundId} account=${context.accountUuid} '
          'reason=provider-dispose activeSubmission=true',
        );
        return;
      }
      unawaited(
        _resetVotingSessionCaches(
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
          _resetVotingSessionCaches(
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
      if (_ownsAutomaticShareTracking) unawaited(_startShareTracking(context));
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
    if (bundleCount == 0) {
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

  /// Delegates this round's pending bundles with the account mnemonic.
  ///
  /// Software accounts only; Keystone accounts sign on the device and go
  /// through [delegatePendingBundlesWithKeystoneSignatures].
  Future<void> delegatePendingBundles({String? mnemonic}) {
    return _delegatePendingBundles(hardware: false, mnemonic: mnemonic);
  }

  /// Delegates this round's pending bundles with the signatures the Keystone
  /// device already returned.
  ///
  /// The signatures are durable in the sidecar; the SDK loads the record for
  /// each bundle and verifies it against the stored PCZT sighash.
  Future<void> delegatePendingBundlesWithKeystoneSignatures() {
    return _delegatePendingBundles(hardware: true);
  }

  /// Runs the delegation round for whichever signer this account uses.
  ///
  /// The two entry points differ only in how a bundle is signed and in what
  /// has to be true before signing can start: software needs the account
  /// mnemonic, hardware needs a device signature for every pending bundle and
  /// must never mint a fresh hotkey once those signatures exist. Everything
  /// around that — preparation, the terminal check, PIR resolution, the round
  /// itself, and the state it publishes — is one path.
  ///
  /// `hardware` is the entry point the caller used, not the account's kind.
  /// The two are checked against each other so calling the wrong one for the
  /// active account reports that mismatch rather than quietly signing the
  /// other way.
  Future<void> _delegatePendingBundles({
    required bool hardware,
    String? mnemonic,
  }) {
    final secretGuard = mnemonic == null
        ? null
        : LinuxSecretOperationGuard(
            store: ref.read(linuxSecretOperationStoreProvider),
            coordinator: ref.read(linuxKeyringCoordinatorProvider),
            isRequestCurrent: () => !_isDisposed && ref.mounted,
            readAccounts: () => ref.read(accountProvider).value,
            accountUuid: _sessionAccountUuid,
          );
    return _enqueue(() async {
      secretGuard?.check();
      var current = await future;
      var context = await _loadContext(_roundId);
      if (hardware != context.isHardwareAccount) {
        _setError(
          hardware
              ? 'Keystone voting is only available for hardware accounts.'
              : 'Sign delegation bundles with Keystone before submitting.',
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
      if (!hasPendingBundles) {
        final terminal = terminalDelegationMessage(roundPlan);
        if (terminal != null) {
          _setError(terminal, context: context);
          return;
        }
      }
      final needsPir = _needsFreshDelegationPreparation(roundPlan);

      // Hardware signing binds each signature to the hotkey that was current
      // when the device signed, so the signatures have to be known before the
      // hotkey is ensured.
      final Map<int, rust_wire.KeystoneSignatureRecord> signatures = hardware
          ? (hasPendingBundles
                ? await _loadKeystoneSignatures(context)
                : current.keystoneSignatures)
          : const {};

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
        // PIR only matters because a bundle needs a proof built against it, so
        // this is checked where there is a bundle to prove.
        if (needsPir && pirEndpoint == null) {
          _setError('PIR endpoint has not been resolved.', context: context);
          return;
        }
        if (hardware) {
          for (final bundleIndex in delegationBundleIndexes) {
            if (!signatures.containsKey(bundleIndex)) {
              _setError(
                'Sign delegation bundle ${bundleIndex + 1} with Keystone before submitting.',
                context: context,
              );
              return;
            }
          }
        } else if (mnemonic == null || mnemonic.isEmpty) {
          // Software delegation signs with the account seed at the wallet
          // boundary; the SDK receives only the SpendAuth signature.
          _setError(
            'Software delegation requires this account mnemonic. Unlock this account or switch to one with mnemonic access.',
            context: context,
          );
          return;
        }
        final nextState = (state.value ?? current).copyWith(
          phase: VotingSessionPhase.delegating,
          clearCurrentBundleIndex: true,
          // Hardware keeps any standing error until the round reports its own
          // outcome; software clears it as the run starts.
          clearError: !hardware,
          keystoneSignatures: hardware ? signatures : null,
          clearKeystoneSigningRequest: hardware,
          clearKeystoneScanError: hardware,
        );
        _setStateForContext(context, nextState);
        current = nextState;
      }
      final storedHotkeySecret = hasPendingBundles
          ? await _ensureHotkey(
              context,
              // A device signature is bound to the hotkey it was made with, so
              // once signatures exist a missing hotkey is a failure rather than
              // a reason to generate one.
              alreadyBound: hardware && signatures.isNotEmpty,
            )
          : null;

      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final rust = ref.read(votingRustApiProvider);
      final completedBundleIndexes = <int>{};
      if (hasPendingBundles) {
        await _awaitSnapshotBundlePrecomputeIfRunning(context);
        _throwIfContextStale(context, 'delegation-proof');
        // Main checked this immediately before the seed was used to prove and
        // sign. That call site is now inside the SDK round, so the check moves
        // to the last point this side of the boundary still owns.
        secretGuard?.check();
        final session = _openRoundSession(
          rust,
          context,
          storedHotkeySecret: storedHotkeySecret,
          pirServerUrls: _delegationPirTransportUrls(state.value ?? current),
        );
        try {
          completedBundleIndexes.addAll(
            await _runDelegationRound(
              session: session,
              context: context,
              fallbackState: current,
              signer: hardware
                  ? const rust_session.ApiDelegationSignerInput(
                      kind: rust_session.ApiDelegationSignerKind.keystoneStored,
                      mnemonic: null,
                      keystoneSig: null,
                      keystoneSighash: null,
                    )
                  : rust_session.ApiDelegationSignerInput(
                      kind: rust_session.ApiDelegationSignerKind.mnemonic,
                      mnemonic: mnemonic,
                      keystoneSig: null,
                      keystoneSighash: null,
                    ),
              progress: progress,
              logLabel: hardware ? 'Keystone' : 'software',
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
          ? ((state.value?.phase == VotingSessionPhase.castingVotes)
                ? VotingSessionPhase.castingVotes
                : VotingSessionPhase.delegated)
          // Same reason as the guard above, for the other outcome: the run
          // can cast votes while a sibling bundle still owes a signature, and
          // announcing `readyToDelegate` then sent the step list back to the
          // delegation row mid-ballot.
          : _phaseWithoutBallotRegression(VotingSessionPhase.readyToDelegate);
      _setStateForContext(
        context,
        (state.value ?? current).copyWith(
          phase: nextPhase,
          roundPlan: refreshedRoundPlan,
          delegationProgress: progress,
          clearCurrentBundleIndex: true,
          keystoneSignatures: hardware ? signatures : null,
          clearKeystoneSigningRequest: hardware,
          clearKeystoneScanError: hardware,
        ),
      );
      _noteTerminalDelegation(
        context,
        state.value ?? current,
        refreshedRoundPlan,
      );
    }, cleanupProcessStateOnError: false);
  }

  /// Records a delegation the SDK ended, without failing the round.
  ///
  /// A terminal bundle plans no further work, so nothing downstream will ever
  /// raise it, and the user has to be told before they vote with a round that
  /// cannot carry every bundle's weight. It must not become the session's
  /// error, though: the submission job treats an error phase after delegation
  /// as fatal and returns, so a round with one dead bundle and one healthy one
  /// would never reach the ballot at all. That trades a silent bundle for an
  /// unvotable round, which is worse.
  ///
  /// The round-wide case — a terminal bundle and nothing left to run — is
  /// still an error, and is raised before any work is attempted.
  void _noteTerminalDelegation(
    _VotingSessionContext context,
    VotingSessionState current,
    rust_wire.RoundPlanView? roundPlan,
  ) {
    final terminal = terminalDelegationMessage(roundPlan);
    _setStateForContext(
      context,
      current.copyWith(
        terminalDelegationNotice: terminal,
        clearTerminalDelegationNotice: terminal == null,
      ),
    );
  }

  Future<void> prepareKeystoneSigning() {
    return _enqueue(
      _prepareKeystoneSigningUnlocked,
      cleanupProcessStateOnError: false,
    );
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
    }, cleanupProcessStateOnError: false);
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

  /// The ballot intents for `draftVotes`, skipping every other listed proposal.
  static List<rust_session.ApiBallotIntent> _ballotIntentsFor({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) {
    final draftVotesByProposal = {
      for (final draftVote in draftVotes) draftVote.proposalId: draftVote,
    };
    final proposalIds = {
      ...?allProposalIds,
      ...draftVotesByProposal.keys,
    }.toList()..sort();
    return [
      for (final proposalId in proposalIds)
        rust_session.ApiBallotIntent(
          proposalId: proposalId,
          skipped: !draftVotesByProposal.containsKey(proposalId),
          choice: draftVotesByProposal[proposalId]?.choice,
        ),
    ];
  }

  /// Makes the ballot durable before any delegation runs.
  ///
  /// The SDK plans a `Delegate` obligation only for a bundle that still has a
  /// vote to cast, so a round whose intents are not yet durable has no
  /// delegation work at all. Delegating first therefore did nothing, and the
  /// cast that followed — which is what recorded the intents — was then
  /// refused because the delegation it now required had already had its turn.
  /// Recording the ballot first is what makes the two agree.
  ///
  /// Safe to repeat: `set_ballot_intents` replaces the stored decision for
  /// each proposal and re-plans, and `castVotes` records the same intents
  /// again so it stays correct when called on its own.
  Future<void> recordBallotIntents({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) {
    return _enqueue(() async {
      final context = await _loadContext(_roundId);
      // An empty ballot records nothing. `_ballotIntentsFor` marks every listed
      // proposal without a draft vote as skipped, so recording here with no
      // draft would overwrite stored choices rather than leave them alone.
      if (draftVotes.isEmpty) return;
      final intents = _ballotIntentsFor(
        draftVotes: draftVotes,
        allProposalIds: allProposalIds,
      );
      if (intents.isEmpty) return;
      final rust = ref.read(votingRustApiProvider);
      // Bundle rows must exist before a choice intent is recorded. The
      // eligibility check reports voting weight without persisting a bundle
      // plan, so a fresh round reaches here with none whenever nothing has
      // run setup for it yet. The SDK can plan no vote work for a round in
      // that state (it reports `needsBundleSetup`), so persist the plan
      // first; `setupDelegationBundles` ensures the round row too, and is
      // idempotent once the bundles exist.
      if (roundPlanBundleCount(context.roundPlan) == 0) {
        await rust.setupDelegationBundles(ctx: _apiRoundContext(context));
        _throwIfContextStale(context, 'record-ballot-intents-bundle-setup');
      }
      final session = _openRoundSession(rust, context);
      try {
        final plan = await session.setBallotIntents(intents);
        _throwIfContextStale(context, 'record-ballot-intents');
        _setStateForContext(
          context,
          (state.value ?? await future).copyWith(roundPlan: plan),
        );
      } finally {
        _closeRoundSession(session);
      }
    });
  }

  Future<void> castVotes({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) {
    final operation = _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);

      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      final rust = ref.read(votingRustApiProvider);
      // An empty ballot must not reach `set_ballot_intents`: `_ballotIntentsFor`
      // marks every listed proposal without a draft vote as skipped, so a
      // recovery-only run would overwrite the stored choices it exists to
      // resume. Fall through to a plain plan instead.
      final intents = draftVotes.isEmpty
          ? const <rust_session.ApiBallotIntent>[]
          : _ballotIntentsFor(
              draftVotes: draftVotes,
              allProposalIds: allProposalIds,
            );

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

      var roundPlan = context.roundPlan ?? await _loadRoundPlan(context);
      // Bundle tasks drive the smooth progress bar, which moves within a step
      // the tally cannot see inside. The question counters come from the SDK's
      // tally instead.
      var totalBundleTasks = 0;
      var completedBundleTasks = 0;
      // Seeded from what the round already published. The delegation drive is
      // a whole-round run that may have cast votes and reported a real tally
      // before this one started, and restarting from nothing made "N of 37"
      // collapse to nothing and climb again.
      final carried = state.value ?? current;
      rust_wire.RoundWorkTallyView? tally = carried.voteSubmissionTotalCount > 0
          ? rust_wire.RoundWorkTallyView(
              completedProposals: carried.voteSubmissionCompletedCount,
              totalProposals: carried.voteSubmissionTotalCount,
              remainingObligations: 0,
            )
          : null;
      final allVoteKeys = <VotingVoteKey>{};
      // An `advanceVoteBatch` step names only its first member's proposal, so
      // the batch's other members are learned from the progress events it
      // emits. Accumulating them here — the way the delegation run already
      // does — keeps every member of a batch advancing together instead of
      // stalling behind the one the step is named after.
      final stepVoteKeys = <VotingVoteKey, Set<VotingVoteKey>>{};

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
            voteSubmissionCompletedCount: tally?.completedProposals ?? 0,
            voteSubmissionTotalCount: tally?.totalProposals ?? 0,
            voteSubmissionProgress: _aggregateVotePipelineProgress(
              progress: progress,
              voteKeys: inFlightKeys,
              completedBundleTasks: completedBundleTasks,
              totalBundleTasks: totalBundleTasks,
              tally: tally,
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
        // This is the ballot's durable write: the SDK commits every intent in
        // one transaction before it plans, so recovery resumes from the
        // correct choice if the user quits mid-vote.
        roundPlan = intents.isEmpty
            ? await session.plan()
            : await session.setBallotIntents(intents);
        _throwIfContextStale(context, 'vote-plan');
        // A decision recorded before its proposal left the authenticated
        // roster outlives that proposal, and the SDK withholds casting until
        // the host clears it: the round's immediate helper share is derived
        // from the complete set of choices, so a stale intent would make that
        // set disagree with the roster. The plan reports only the ids that
        // are still clearable.
        if (roundPlan.unrosteredIntents.isNotEmpty) {
          roundPlan = await session.clearBallotIntents(
            roundPlan.unrosteredIntents.toList(growable: false),
          );
          _throwIfContextStale(context, 'vote-plan');
          if (roundPlan.unrosteredIntents.isNotEmpty) {
            // The SDK withholds every CastVote while an unrostered intent
            // stands, so carrying on here would read as a cast that quietly
            // did nothing. The planner reports only clearable ids, so this
            // means the clear did not take.
            throw StateError(
              'Ballot intents for proposals outside the round roster could '
              'not be cleared: ${roundPlan.unrosteredIntents.join(', ')}.',
            );
          }
        }
        final initialSteps = roundPlan.nextSteps.where(_isVoteStep).toList();
        totalBundleTasks = initialSteps.length;
        allVoteKeys.addAll(initialSteps.map(_voteKeyForStep));
        final startTiming = _roundShareTiming(context, _nowSeconds());
        _logVoteTiming(
          'cast votes start '
          'round=${context.round.roundId} bundleTasks=$totalBundleTasks '
          'lastMoment=${startTiming.isLastMoment}',
        );
        if (initialSteps.isNotEmpty) {
          _setStateForContext(
            context,
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.castingVotes,
              roundPlan: roundPlan,
              voteProgress: progress,
              // The counters are left alone: whatever the round already
              // published is still true, and this run's first plan refresh
              // merges its own tally into it.
              clearCurrentBundleIndex: true,
              clearCurrentVoteKey: true,
            ),
          );
        }
        // A failing bundle does not stop the others: the SDK skips its
        // remaining obligations, runs the rest of the round, and reports every
        // failure together so successful bundles keep their durable progress.
        final report = await _runRound(
          session,
          context,
          label: 'vote',
          // "Question N of M" counts the choices the voter selected, so it
          // must not renumber when a resume picks up less than all of them.
          policy: const rust_session.ApiRoundDrivePolicy(
            selectedChoiceProgress: true,
          ),
          onEvent: (event) {
            // A refreshed plan carries no step: it is the whole round's
            // remaining work, and it is what the counters read.
            if (event.kind == rust_wire.RoundDriveEventKind.planRefreshed) {
              final plan = event.plan;
              if (plan == null) return;
              // The tally is exact where counting steps is not: an atomic
              // batch projects to one step carrying only its first proposal's
              // id, so six proposals would read as one question here.
              tally = _mergeTally(tally, event.tally);
              final remaining = plan.nextSteps.where(_isVoteStep).toList();
              completedBundleTasks = totalBundleTasks - remaining.length;
              publishState();
              return;
            }
            final step = event.step;
            if (step == null || !_isVoteStep(step)) return;
            final key = _voteKeyForStep(step);
            final keys = stepVoteKeys.putIfAbsent(key, () => {key});
            switch (event.kind) {
              case rust_wire.RoundDriveEventKind.stepSelected:
                publishState(
                  currentBundleIndex: step.bundleIndex,
                  currentVoteKey: key,
                  inFlightKeys: [key],
                );
              case rust_wire.RoundDriveEventKind.stepProgress:
                final update = event.progress;
                if (update == null) return;
                _applyVoteProgress(update, step, keys, progress);
                publishState(
                  currentBundleIndex: step.bundleIndex,
                  currentVoteKey: key,
                  inFlightKeys: keys.toList(growable: false),
                );
              case rust_wire.RoundDriveEventKind.stepFinished:
                if (event.disposition ==
                    rust_wire.RoundStepDispositionView.advanced) {
                  for (final voteKey in keys) {
                    _storeProgress(
                      progress,
                      voteKey,
                      VotingSessionProgress(
                        phase: VotingProgressPhase.completed,
                        bundleIndex: voteKey.bundleIndex,
                        proposalId: voteKey.proposalId,
                        proofProgress: 1,
                      ),
                    );
                  }
                }
                _logVoteTiming(
                  'step ${step.kind.name} bundle=${step.bundleIndex} '
                  'proposal=${step.proposalId} '
                  'disposition=${event.disposition?.name}',
                );
                publishState();
              default:
                break;
            }
          },
        );

        final failures = [
          for (final record in report.failures)
            _VoteBundleFailure(
              bundleIndex: record.bundleIndex ?? 0,
              proposalId: record.step?.proposalId ?? 0,
              error: _failureFromRecord(record),
            ),
        ];
        for (final failure in failures) {
          final key = VotingVoteKey(
            bundleIndex: failure.bundleIndex,
            proposalId: failure.proposalId,
          );
          final item = progress[key];
          _storeProgress(
            progress,
            key,
            VotingSessionProgress(
              phase: VotingProgressPhase.failed,
              bundleIndex: key.bundleIndex,
              proposalId: key.proposalId,
              proofProgress: item?.proofProgress,
              message: failure.error.toString(),
            ),
          );
        }
        roundPlan = report.plan ?? roundPlan;
        // The driver refreshes plan and tally after its final dispatch, so the
        // report's tally is this run's authoritative end state — but it is
        // still only this run's, so it merges rather than replaces.
        tally = _mergeTally(tally, report.tally);
        publishState();
        if (failures.isNotEmpty) throw _VoteBundleBatchException(failures);
      } on _StaleVotingSessionAction {
        rethrow;
      } catch (_) {
        for (final key in allVoteKeys) {
          final item = progress[key];
          if (item != null && item.phase != VotingProgressPhase.completed) {
            _storeProgress(
              progress,
              key,
              VotingSessionProgress(
                phase: VotingProgressPhase.failed,
                bundleIndex: key.bundleIndex,
                proposalId: key.proposalId,
                proofProgress: item.proofProgress,
                message: item.message,
              ),
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
        if (_ownsAutomaticShareTracking) {
          unawaited(_startShareTracking(context));
        }
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
          phase: _phaseWithoutBallotRegression(
            _phaseForPlans(refreshedRoundPlan),
          ),
          roundPlan: refreshedRoundPlan,
          voteProgress: progress,
          voteSubmissionCompletedCount: tally?.completedProposals ?? 0,
          voteSubmissionTotalCount: tally?.totalProposals ?? 0,
          voteSubmissionProgress: _voteSubmissionProgress(
            completedBundleTasks: completedBundleTasks,
            totalBundleTasks: totalBundleTasks,
            tally: tally,
          ),
          clearCurrentBundleIndex: true,
          clearCurrentVoteKey: true,
        ),
      );
      if (_ownsAutomaticShareTracking) unawaited(_startShareTracking(context));
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
        _storeProgress(
          progress,
          key,
          VotingSessionProgress(
            phase: _voteStagePhase(stage),
            bundleIndex: bundleIndex,
            proposalId: proposalId,
            proofProgress:
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
          _storeProgress(
            progress,
            key,
            VotingSessionProgress(
              phase: VotingProgressPhase.submitting,
              bundleIndex: key.bundleIndex,
              proposalId: key.proposalId,
              proofProgress: 1,
            ),
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
          _storeProgress(
            progress,
            key,
            VotingSessionProgress(
              phase: confirmed
                  ? VotingProgressPhase.confirmed
                  : VotingProgressPhase.submitted,
              bundleIndex: key.bundleIndex,
              proposalId: key.proposalId,
              proofProgress: 1,
              message:
                  chainOutcome.transactionHash ??
                  chainOutcome.candidateTransactionHash,
            ),
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
        _storeProgress(
          progress,
          key,
          VotingSessionProgress(
            phase: VotingProgressPhase.completed,
            bundleIndex: key.bundleIndex,
            proposalId: key.proposalId,
            proofProgress: 1,
          ),
        );
      case rust_wire.RoundStepProgressKind.selected ||
          rust_wire.RoundStepProgressKind.delegation ||
          rust_wire.RoundStepProgressKind.delegateAndVoteBatchPersisted ||
          rust_wire.RoundStepProgressKind.treeSynced ||
          rust_wire.RoundStepProgressKind.shareConfirmed:
        break;
    }
  }

  static VotingProgressPhase _voteStagePhase(
    rust_wire.VoteCommitStageKind stage,
  ) {
    return switch (stage) {
      rust_wire.VoteCommitStageKind.proofStarting =>
        VotingProgressPhase.buildingProof,
      rust_wire.VoteCommitStageKind.proofProgress =>
        VotingProgressPhase.proofProgress,
      rust_wire.VoteCommitStageKind.sharePayloadsBuilding =>
        VotingProgressPhase.buildingSharePayloads,
      rust_wire.VoteCommitStageKind.signing => VotingProgressPhase.signing,
    };
  }

  static VotingProgressPhase _delegationPhase(
    rust_wire.DelegationProgressKind kind,
  ) {
    return switch (kind) {
      rust_wire.DelegationProgressKind.selectingNotes =>
        VotingProgressPhase.selectingNotes,
      rust_wire.DelegationProgressKind.pcztBuilding ||
      rust_wire.DelegationProgressKind.pcztBuilt =>
        VotingProgressPhase.buildingPczt,
      rust_wire.DelegationProgressKind.proofStarting =>
        VotingProgressPhase.buildingProof,
      rust_wire.DelegationProgressKind.waitingForExistingProof =>
        VotingProgressPhase.waitingForExistingProof,
      rust_wire.DelegationProgressKind.proofProgress ||
      rust_wire.DelegationProgressKind.proofComplete =>
        VotingProgressPhase.proofProgress,
      rust_wire.DelegationProgressKind.signingPayload =>
        VotingProgressPhase.signingPayload,
      rust_wire.DelegationProgressKind.payloadReady =>
        VotingProgressPhase.payloadReady,
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
    // One mapped fleet for the round. Chain, helper and vote-tree traffic all
    // go to the configured API servers, but they stay separate fields because
    // they are separate roles: sharing a value today is a deployment fact, not
    // something the boundary should assert.
    final servers = context.config.apiServers.all
        .map(_transportUrl)
        .toList(growable: false);
    final start = context.round.ceremonyStart;
    final end = context.round.voteEndTime;
    final session = rust.openRoundSession(
      ctx: _apiRoundContext(context),
      binding: rust_session.ApiRoundSessionBinding(
        chainEndpoints: servers,
        configuredHelperUrls: servers,
        voteTreeNodeUrls: servers,
        pirServerUrls: pirServerUrls,
        proposals: [
          for (final proposal in proposals)
            rust_session.ApiProposalRosterEntry(
              proposalId: proposal.id,
              numOptions: proposal.options.length,
            ),
        ],
        ceremonyStartSeconds: start == null
            ? null
            : BigInt.from(_unixSeconds(start)),
        voteEndTimeSeconds: end == null ? null : BigInt.from(_unixSeconds(end)),
        maxProofConcurrency: _votingBatchProofConcurrency,
      ),
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

  /// Drives the round's delegation work through the SDK, publishing
  /// per-bundle progress.
  ///
  /// The SDK owns the loop: it plans, overlaps bundles, isolates a failure to
  /// its bundle, and stops when only this app can make progress. Dart reads
  /// the event stream and keeps the UI state.
  ///
  /// Returns the bundles that completed. Failures the run isolated are raised
  /// together, as the per-bundle batch the caller already handles, so a
  /// healthy bundle keeps its durable progress.
  Future<Set<int>> _runDelegationRound({
    required VotingRoundSession session,
    required _VotingSessionContext context,
    required VotingSessionState fallbackState,
    required rust_session.ApiDelegationSignerInput signer,
    required Map<int, VotingSessionProgress> progress,
    required String logLabel,
  }) async {
    final batchTimer = Stopwatch()..start();
    final completed = <int>{};
    var castingVotes = false;
    var roundPlan = fallbackState.roundPlan;
    rust_wire.RoundWorkTallyView? tally =
        fallbackState.voteSubmissionTotalCount > 0
        ? rust_wire.RoundWorkTallyView(
            completedProposals: fallbackState.voteSubmissionCompletedCount,
            totalProposals: fallbackState.voteSubmissionTotalCount,
            remainingObligations: 0,
          )
        : null;
    final voteProgress = Map<VotingVoteKey, VotingSessionProgress>.of(
      fallbackState.voteProgress,
    );
    final stepVoteKeys = <VotingVoteKey, Set<VotingVoteKey>>{};

    void publishVotes({VotingVoteKey? currentKey}) {
      final total = tally?.totalProposals ?? 0;
      final finished = tally?.completedProposals ?? 0;
      _setStateForContext(
        context,
        (state.value ?? fallbackState).copyWith(
          phase: VotingSessionPhase.castingVotes,
          roundPlan: roundPlan,
          voteProgress: Map<VotingVoteKey, VotingSessionProgress>.of(
            voteProgress,
          ),
          currentBundleIndex: currentKey?.bundleIndex,
          currentVoteKey: currentKey,
          clearCurrentBundleIndex: currentKey == null,
          clearCurrentVoteKey: currentKey == null,
          voteSubmissionCompletedCount: finished,
          voteSubmissionTotalCount: total,
          // A refresh that reports no baseline has not learned this run's
          // obligations yet. Leaving the counters alone is right; clearing
          // them dropped the ring back to nothing mid-ballot.
          voteSubmissionProgress: total > 0 ? finished / total : null,
        ),
      );
    }

    void publishProgress(VotingSessionProgress update) {
      final bundleIndex = update.bundleIndex;
      if (bundleIndex == null) return;
      _storeProgress(progress, bundleIndex, update);
      _setStateForContext(
        context,
        (state.value ?? fallbackState).copyWith(
          // A sibling delegation can finish after voting has begun. Keep the
          // presentation on voting instead of bouncing between the two steps.
          phase: castingVotes
              ? VotingSessionPhase.castingVotes
              : VotingSessionPhase.delegating,
          delegationProgress: Map<int, VotingSessionProgress>.of(progress),
          clearCurrentBundleIndex: true,
        ),
      );
    }

    final report = await _runRound(
      session,
      context,
      signer: signer,
      label: '$logLabel-delegation',
      policy: const rust_session.ApiRoundDrivePolicy(
        selectedChoiceProgress: true,
      ),
      onEvent: (event) {
        // This is a whole-round drive, even though the caller starts it to
        // delegate. Durable ballot intents let it cast votes and deliver
        // shares in the same run, before castVotes() is ever called.
        if (event.kind == rust_wire.RoundDriveEventKind.planRefreshed) {
          roundPlan = event.plan ?? roundPlan;
          tally = _mergeTally(tally, event.tally);
          if (castingVotes) publishVotes();
          return;
        }
        final step = event.step;
        final bundleIndex = step?.bundleIndex;
        if (bundleIndex == null) return;
        if (_isVoteStep(step!)) {
          castingVotes = true;
          final key = _voteKeyForStep(step);
          final keys = stepVoteKeys.putIfAbsent(key, () => {key});
          switch (event.kind) {
            case rust_wire.RoundDriveEventKind.stepProgress:
              final update = event.progress;
              if (update != null) {
                _applyVoteProgress(update, step, keys, voteProgress);
              }
            case rust_wire.RoundDriveEventKind.stepFinished:
              if (event.disposition ==
                  rust_wire.RoundStepDispositionView.advanced) {
                for (final voteKey in keys) {
                  _storeProgress(
                    voteProgress,
                    voteKey,
                    VotingSessionProgress(
                      phase: VotingProgressPhase.completed,
                      bundleIndex: voteKey.bundleIndex,
                      proposalId: voteKey.proposalId,
                      proofProgress: 1,
                    ),
                  );
                }
              }
            default:
              break;
          }
          publishVotes(currentKey: key);
          return;
        }
        // Chain outcomes are attributed to a step, not just a bundle: a vote
        // confirmation must never overwrite that bundle's delegation state.
        if (!_isDelegationStep(step)) return;
        switch (event.kind) {
          case rust_wire.RoundDriveEventKind.stepProgress:
            final update = event.progress;
            if (update == null) return;
            switch (update.kind) {
              case rust_wire.RoundStepProgressKind.delegation:
                final kind = update.delegationProgress;
                if (kind == null) return;
                publishProgress(
                  VotingSessionProgress(
                    phase: _delegationPhase(kind),
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
                      phase: VotingProgressPhase.confirmed,
                      bundleIndex: bundleIndex,
                      message: chainOutcome!.transactionHash,
                    ),
                  );
                }
              default:
                break;
            }
          case rust_wire.RoundDriveEventKind.stepFinished:
            if (event.disposition ==
                rust_wire.RoundStepDispositionView.advanced) {
              completed.add(bundleIndex);
            }
          default:
            break;
        }
      },
    );

    if (castingVotes) {
      roundPlan = report.plan ?? roundPlan;
      tally = _mergeTally(tally, report.tally);
      publishVotes();
    }

    final failures = [
      for (final record in report.failures)
        if (record.bundleIndex != null)
          _DelegationBundleFailure(
            bundleIndex: record.bundleIndex!,
            stage: 'step',
            error: _failureFromRecord(record),
          ),
    ];
    for (final failure in failures) {
      completed.remove(failure.bundleIndex);
      publishProgress(
        VotingSessionProgress(
          phase: VotingProgressPhase.failed,
          bundleIndex: failure.bundleIndex,
          message: failure.error.toString(),
        ),
      );
    }
    debugPrint(
      '[zcash] Voting: $logLabel delegation run finished '
      'round=${context.round.roundId} completed=${completed.length} '
      'failed=${failures.length} '
      'quiescence=${report.quiescence.kind.name} '
      'elapsed=${formatElapsedSeconds(batchTimer.elapsed)}',
    );
    if (failures.isNotEmpty) throw _DelegationBundleBatchException(failures);
    return completed;
  }

  /// The typed error a host raises for one isolated step failure.
  ///
  /// A record always names a step in practice; the SDK leaves it absent only
  /// for a failure that belonged to no step, such as a plan it could not read.
  static Object _failureFromRecord(
    rust_wire.RoundStepFailureRecordView record,
  ) {
    final step = record.step;
    return step == null
        ? StateError(record.failure.message)
        : VotingRoundStepFailure(step, record.failure);
  }

  /// Streams one SDK round run, forwarding every event and returning its
  /// report.
  ///
  /// The run's own failures ride on the report; only a bridge error or a
  /// stale session throws, so a caller decides what an isolated bundle means
  /// for its flow.
  Future<rust_wire.RoundRunReportView> _runRound(
    VotingRoundSession session,
    _VotingSessionContext context, {
    required String label,
    required void Function(rust_wire.RoundDriveEventView event) onEvent,
    rust_session.ApiDelegationSignerInput? signer,
    rust_session.ApiRoundDrivePolicy? policy,
  }) async {
    _throwIfContextStale(context, '$label-run');
    rust_wire.RoundRunReportView? report;
    await for (final event in session.runRound(
      signer: signer,
      policy: policy,
    )) {
      _throwIfContextStale(context, '$label-run-event');
      final observed = event.event;
      if (observed != null) onEvent(observed);
      final error = event.error;
      if (error != null) throw votingRustExceptionFromStepError(error);
      final finished = event.report;
      if (finished != null) report = finished;
    }
    if (report == null) {
      throw StateError('Round run completed without a report.');
    }
    final quiescence = report.quiescence;
    switch (quiescence.kind) {
      case rust_wire.RoundQuiescenceKind.cancelled:
        _throwIfContextStale(context, '$label-run-cancelled');
        throw const _ChainSubmissionCancelled();
      case rust_wire.RoundQuiescenceKind.chainTerminal:
      case rust_wire.RoundQuiescenceKind.persistedChainTerminal:
        // The SDK plans no retry for a rejected or hashless submission, so
        // this has to surface rather than read as a finished round.
        throw VotingChainTerminalOutcome(
          quiescence.step,
          quiescence.chainOutcome,
        );
      case rust_wire.RoundQuiescenceKind.chainRecoveryStalled:
        throw VotingChainPendingOutcome(
          quiescence.step,
          quiescence.chainOutcome,
        );
      default:
        break;
    }
    return report;
  }

  /// TEMPORARY diagnostic: the network the voting layer binds.
  static String _loggedVotingNetwork(String networkName) {
    debugPrint('[zcash] Voting: context network=$networkName');
    return networkName;
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
    final rust = ref.read(votingRustApiProvider);
    return ref
        .read(votingHotkeyStoreProvider)
        .getOrCreate(
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          generate: () => rust.generateVotingHotkey(network: context.network),
          allowCreation: !(alreadyBound || _hotkeyAlreadyBound(context)),
        );
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
    return context.roundPlan?.hotkeyBound ?? false;
  }

  double? _voteSubmissionProgress({
    required int completedBundleTasks,
    required int totalBundleTasks,
    double? currentBundleProgress,
    rust_wire.RoundWorkTallyView? tally,
  }) {
    return _submissionProgress(
      tally: tally,
      inFlightProgress: currentBundleProgress ?? 0,
      completedBundleTasks: completedBundleTasks,
      totalBundleTasks: totalBundleTasks,
    );
  }

  /// How far through the ballot the bar should sit.
  ///
  /// The tally is the authority whenever the SDK sends one, because it counts
  /// the same proposals the "question N of M" label counts. Counting steps
  /// cannot: an atomic batch is one step carrying every proposal in it, and
  /// the planner may collapse a round's casts into one at any refresh — so
  /// `completedBundleTasks`, which subtracts a refreshed plan's step count
  /// from the count the run started with, compares two different shapes and
  /// lands on a number belonging to neither. A six-question ballot that
  /// started as six casts and refreshed as one batch reported five of six
  /// done and stayed there for the whole submission.
  ///
  /// Step counting survives only as the pre-tally fallback, covering the
  /// window before the run's first plan refresh arrives.
  static double? _submissionProgress({
    required rust_wire.RoundWorkTallyView? tally,
    required double inFlightProgress,
    required int completedBundleTasks,
    required int totalBundleTasks,
  }) {
    final total = tally?.totalProposals ?? 0;
    if (total > 0) {
      final completed = tally!.completedProposals.clamp(0, total);
      // The in-flight step is credited with at most one more question. It may
      // cover several — a batch does — but crediting it for more would
      // overshoot the label, and the next refresh corrects it upward anyway.
      final withinQuestion = inFlightProgress.clamp(0.0, 1.0) / total;
      return ((completed / total) + withinQuestion).clamp(0.0, 1.0).toDouble();
    }
    if (totalBundleTasks <= 0) return null;
    return ((completedBundleTasks + inFlightProgress.clamp(0.0, 1.0)) /
            totalBundleTasks)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Stores an update for [key], holding the furthest point it has reached.
  ///
  /// The round driver re-dispatches a step after a repoll, so a bundle or vote
  /// that already reached `payloadReady` can be told it is selecting notes
  /// again. That is the driver retrying, not the voter losing ground, and
  /// letting it through made the "N of M proved" counters and the progress
  /// rings run backwards.
  ///
  /// `failed` is the one phase allowed to move a key backwards: a failure is
  /// what the UI has to show. A later event still recovers the key, because
  /// `failed` ranks below every working phase.
  void _storeProgress<K>(
    Map<K, VotingSessionProgress> progress,
    K key,
    VotingSessionProgress next,
  ) {
    progress[key] = _monotonicProgress(progress[key], next);
  }

  VotingSessionProgress _monotonicProgress(
    VotingSessionProgress? previous,
    VotingSessionProgress next,
  ) {
    if (previous == null) return next;
    final failed = next.phase == VotingProgressPhase.failed;
    // A key that recovers from a failure must not carry its failure text
    // forward; anything else keeps the last thing it had to say, so a
    // transaction hash survives the events that follow it.
    final recovering = previous.phase == VotingProgressPhase.failed && !failed;
    final message = next.message ?? (recovering ? null : previous.message);
    final advances =
        failed ||
        voteProgressPhaseRank(next.phase) >=
            voteProgressPhaseRank(previous.phase);
    final held = advances ? next : previous;
    return VotingSessionProgress(
      phase: held.phase,
      bundleIndex: next.bundleIndex ?? previous.bundleIndex,
      proposalId: next.proposalId ?? previous.proposalId,
      // A failure reports what it actually got to; everything else holds.
      proofProgress: failed
          ? next.proofProgress
          : _monotonicProofProgress(previous.proofProgress, next.proofProgress),
      message: message,
    );
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
    rust_wire.RoundWorkTallyView? tally,
  }) {
    var pipelineProgress = 0.0;
    for (final key in voteKeys) {
      final item = progress[key];
      pipelineProgress += switch (item?.phase) {
        VotingProgressPhase.completed => 1,
        VotingProgressPhase.confirmed => 0.95,
        VotingProgressPhase.submitting => 0.95,
        VotingProgressPhase.submitted => 0.85,
        VotingProgressPhase.failed => 0,
        _ => (item?.proofProgress ?? 0).clamp(0.0, 1.0) * 0.8,
      };
    }
    return _submissionProgress(
      tally: tally,
      inFlightProgress: pipelineProgress,
      completedBundleTasks: completedBundleTasks,
      totalBundleTasks: totalBundleTasks,
    );
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

  /// The tracking run in flight, if any.
  ///
  /// [startShareTracking] returns once a run is under way, because no product
  /// caller waits for one — the round's shares are tracked for as long as the
  /// round lives. This is how the code that genuinely needs the run's durable
  /// effects waits for them: the destructive drain, and tests.
  Future<void>? get shareTrackingRun => _shareTrackingRun;

  /// Starts background helper-share tracking for this round, if it is not
  /// already running.
  ///
  /// Returns as soon as the run is under way. The SDK drives passes to
  /// quiescence on the cadence each pass computes, so callers observe progress
  /// through session state rather than by awaiting a pass. Idempotent: a
  /// second call while a run is in flight is a no-op.
  Future<void> startShareTracking() => _startShareTracking();

  /// Whether the run in flight is still the one this round wants.
  ///
  /// A run whose context has been superseded — the account switched, the
  /// generation advanced — has already been cancelled and is only unwinding.
  /// Treating that as "tracking is running" is what would drop the next
  /// round's start on the floor, because cancellation is cooperative and the
  /// run is usually still in flight when its replacement is requested.
  bool get _shareTrackingRunIsLive {
    if (_shareTrackingRun == null) return false;
    final running = _shareTrackingContext;
    return running != null && _isCurrentContext(running);
  }

  /// [startShareTracking], reusing a context the caller already loaded.
  Future<void> _startShareTracking([
    _VotingSessionContext? knownContext,
  ]) async {
    if (_shareTrackingRunIsLive) return;
    if (_automaticShareTrackingStopped) return;
    if (_isDisposed || !ref.mounted) return;
    // A superseded run is settled by construction and has already been
    // cancelled by whatever superseded it, so this waits out an unwind rather
    // than an outage — and never has to handle a failure.
    final unwinding = _shareTrackingRun;
    if (unwinding != null) {
      await unwinding;
      if (_isDisposed || !ref.mounted) return;
    }
    // Only the notifier that owns automatic tracking may run it, and only
    // after registering. Registration is what a destructive wallet operation
    // drains through, so a run started anywhere else would be invisible to it
    // — account deletion could clear the state a pass is still reading. This
    // makes "every run is drainable" hold by construction rather than by every
    // caller happening to pick the right provider.
    if (!_ownsAutomaticShareTracking) return;
    if (!_retainAutomaticShareTracking()) return;

    final current = await future;
    if (_isDisposed || !ref.mounted) return;
    // Callers inside this notifier already hold a context. Reloading it would
    // add an await this method is often fired across — from a finished cast,
    // or a rebuild — and the provider can be gone by the time it lands.
    final context = knownContext ?? await _loadContext(_roundId);
    if (_isDisposed || !ref.mounted) return;
    if (_shareTrackingCancelled(context)) {
      _releaseAutomaticShareTrackingIfRoundExpired(context);
      return;
    }
    // Nothing to track: opening a session and driving passes would only ask
    // helpers about shares the round has already confirmed.
    //
    // Read from live state first. A caller that supplies its own context is
    // supplying identity, not a fresh plan: `castVotes` hands over the context
    // it opened with, whose plan predates the votes it just cast and so
    // reports no shares at all. Deciding from that would silently skip
    // tracking exactly when a round has just created shares to track.
    final plan = state.value?.roundPlan ?? context.roundPlan;
    if (plan != null && !plan.hasUnconfirmedShares) {
      _releaseAutomaticShareTracking();
      return;
    }
    // Re-checked after the awaits above: a concurrent caller may have started
    // the run while this one was loading.
    if (_shareTrackingRun != null) return;
    _currentContext = context;
    // A start supersedes any pending re-arm: the run it would have made is the
    // one about to begin.
    _cancelShareTrackingRetry();

    final rust = ref.read(votingRustApiProvider);
    final session = _openRoundSession(rust, context);
    _shareTrackingSession = session;
    _shareTrackingContext = context;
    // The stored future is the settled one: a run's failure is handled here,
    // so waiting for a run to finish — the drain, or a test — never has to
    // handle it again, and a second listener can never turn it into an
    // unhandled asynchronous error.
    late final Future<void> run;
    run = _runShareTracking(session, context, current)
        .catchError((Object error, StackTrace stack) {
          debugPrint(
            '[zcash] Voting: share tracking run failed '
            'round=${context.round.roundId} error=$error\n$stack',
          );
          // Surfaced only while a submission is waiting on it. A job that
          // would otherwise poll forever has to learn that tracking gave up,
          // but once the vote is cast and confirmed the shares deliver in the
          // background: painting that round failed would report a successful
          // vote as a failure over a helper outage the voter cannot act on.
          if (!_activeSubmissionOwnsContext(context)) return;
          _setError(_actionErrorMessage(error), cause: error, context: context);
        })
        .whenComplete(() {
          // All three fields are cleared only by the run that set them, so a
          // successor cannot be erased by its predecessor finishing late.
          if (identical(_shareTrackingSession, session)) {
            _shareTrackingSession = null;
          }
          if (identical(_shareTrackingContext, context)) {
            _shareTrackingContext = null;
          }
          if (identical(_shareTrackingRun, run)) _shareTrackingRun = null;
          _closeRoundSession(session);
        });
    _shareTrackingRun = run;
  }

  /// Consumes one tracking run, projecting its events into session state.
  Future<void> _runShareTracking(
    VotingRoundSession session,
    _VotingSessionContext context,
    VotingSessionState fallback,
  ) async {
    _setStateForContext(
      context,
      (state.value ?? fallback).copyWith(
        phase: VotingSessionPhase.submittingShares,
        // Same reason as the guard above: the live plan is the current one.
        roundPlan: state.value?.roundPlan ?? context.roundPlan,
      ),
    );

    rust_wire.ShareTrackingRunReportView? report;
    await for (final event in session.runShareTracking(
      policy: _shareTrackingPolicy,
    )) {
      // A backstop, not the stop mechanism. Every real stop path cancels the
      // session directly and immediately — the registry drain on app lock,
      // `_advanceSessionGeneration` on an account switch, provider dispose —
      // and vote end is a boundary the SDK holds itself from the binding. This
      // only catches a stop condition that became true with none of those
      // firing, and it can do so no sooner than the next event.
      if (_shareTrackingCancelled(context)) session.cancel();
      final error = event.error;
      if (error != null) throw votingRustExceptionFromStepError(error);
      final observed = event.event;
      if (observed != null) await _applyShareTrackingEvent(observed, context);
      final finished = event.report;
      if (finished != null) report = finished;
    }
    if (report == null) {
      throw StateError('Share tracking run completed without a report.');
    }

    final quiescence = report.quiescence;
    if (quiescence.kind == rust_wire.ShareTrackingQuiescenceKind.failing) {
      // The driver already retried under its policy and gave up, so the fleet
      // has been unreachable for a while. That is still a condition a later
      // run can clear, so re-arm rather than leaving the round pinned but
      // untracked until an app lifecycle event happens to restart it.
      final failure = StateError(
        quiescence.messages.isEmpty
            ? 'Helper share tracking kept failing.'
            : quiescence.messages.last,
      );
      debugPrint(
        '[zcash] Voting: share tracking run failing '
        'round=${context.round.roundId} passes=${report.passes} '
        'error=$failure',
      );
      _armShareTrackingRetry(context);
      // Surfaced only while a submission is waiting on it, for the same reason
      // the run's own failure channel is: a job that would otherwise poll
      // forever has to learn tracking gave up, but once the vote is cast and
      // confirmed the shares deliver in the background, and painting that
      // round red would report a successful vote as a failure over a helper
      // outage the voter cannot act on.
      if (_activeSubmissionOwnsContext(context)) {
        _setError(
          _actionErrorMessage(failure),
          cause: failure,
          context: context,
        );
      }
      return;
    }

    if (quiescence.kind ==
        rust_wire.ShareTrackingQuiescenceKind.alreadyDriving) {
      // Another run holds this round and is still driving it. This one polled
      // nothing, so its report is not evidence about the round: refreshing the
      // plan off it, clearing drafts, or releasing the registration would all
      // act on the holder's work as though this run had finished it. Leave the
      // round to the holder.
      debugPrint(
        '[zcash] Voting: share tracking already driven elsewhere '
        'round=${context.round.roundId}',
      );
      _shareTrackingRetryStreak = 0;
      return;
    }

    if (report.unrecoverable.isNotEmpty) {
      // These cannot be repaired by retrying; log once per run rather than
      // spinning on them silently.
      debugPrint(
        '[zcash] Voting: ${report.unrecoverable.length} share(s) missing '
        'recovery material round=${context.round.roundId}',
      );
    }
    debugPrint(
      '[zcash] Voting: share tracking run finished '
      'round=${context.round.roundId} '
      'quiescence=${report.quiescence.kind.name} passes=${report.passes} '
      'confirmed=${report.confirmed.length}',
    );

    if (!_isCurrentContext(context)) {
      _releaseAutomaticShareTrackingIfRoundExpired(context);
      return;
    }
    final roundPlan = await _loadRoundPlan(context);
    if (!hasBlockingRoundRecoveryWork(roundPlan)) {
      await _clearPersistedDraftChoices(context);
    }
    _setStateForContext(
      context,
      (state.value ?? fallback).copyWith(
        phase: _phaseWithoutBallotRegression(_phaseForPlans(roundPlan)),
        roundPlan: roundPlan,
      ),
    );
    if (!roundPlan.hasUnconfirmedShares ||
        !shouldTrackPendingVotingShares(context.round)) {
      // Nothing left to track, or a boundary no later run can cross — vote end
      // above all. Release rather than pinning a notifier that will never
      // track again.
      _shareTrackingRetryStreak = 0;
      _releaseAutomaticShareTracking();
      return;
    }
    // Shares remain and the round is still live, so the run stopped short of
    // its work. Only a budget a later run can be given again is re-armed here:
    // a cancellation is deliberate and the restorer starts a fresh run on
    // resume, and a clean quiescence means the run reached the end of what it
    // was tracking.
    //
    // Known gap: `AllConfirmed` and `NothingToTrack` describe what the run
    // saw, not what the round owes now, so a cast that writes shares behind a
    // running pass leaves them untracked until the next lifecycle event
    // restarts tracking. Re-arming on those too closes it, but arms a
    // long-lived timer in every round that ends with shares pending — which a
    // `testWidgets` body cannot hold, and which needs wider validation than
    // the race deserves. The targeted fix is at the source: have `castVotes`
    // ensure a follow-up run when it wrote shares behind a live one.
    if (quiescence.kind ==
        rust_wire.ShareTrackingQuiescenceKind.passBudgetExhausted) {
      _armShareTrackingRetry(context);
    } else {
      _shareTrackingRetryStreak = 0;
    }
  }

  /// Re-arms tracking after a run stopped on a condition a later run could
  /// clear.
  ///
  /// The SDK retries within a run, so reaching here means the condition
  /// outlasted that: consecutive re-arms back off exponentially to a ceiling,
  /// and never past the round's vote end, after which no run has anything left
  /// to do.
  void _armShareTrackingRetry(_VotingSessionContext context) {
    _cancelShareTrackingRetry();
    if (_automaticShareTrackingStopped || _isDisposed || !ref.mounted) return;
    if (!_ownsAutomaticShareTracking) return;
    if (_shareTrackingCancelled(context)) {
      _releaseAutomaticShareTrackingIfRoundExpired(context);
      return;
    }

    final ceiling = ref.read(votingShareTrackingMaxRetryDelayProvider);
    // The backoff is multiplicative, so a base of zero would double to zero
    // forever and retry in a tight loop. Floor it: the point of the first
    // delay is that the fleet has already been unreachable for longer than
    // the SDK's own in-run retries, so there is nothing to gain from asking
    // again immediately.
    final configured = ref.read(votingShareTrackingFailureRetryDelayProvider);
    final base = configured < _minShareTrackingRetryDelay
        ? _minShareTrackingRetryDelay
        : configured;
    final streak = _shareTrackingRetryStreak;
    _shareTrackingRetryStreak = streak + 1;
    // The shift is clamped rather than the product checked: 2^16 times any
    // plausible base stays far inside a 64-bit microsecond count, and the
    // ceiling below caps the value long before the clamp is reached.
    final backoff = Duration(
      microseconds: base.inMicroseconds << (streak < 16 ? streak : 16),
    );
    var delay = backoff < ceiling ? backoff : ceiling;
    final voteEnd = context.round.voteEndTime;
    if (voteEnd != null) {
      final remaining = voteEnd.difference(DateTime.now());
      if (remaining.isNegative) {
        _releaseAutomaticShareTracking();
        return;
      }
      if (remaining < delay) delay = remaining;
    }

    debugPrint(
      '[zcash] Voting: re-arming share tracking in ${delay.inSeconds}s '
      'round=${context.round.roundId} attempt=${streak + 1}',
    );
    _shareTrackingRetryTimer = Timer(delay, () {
      _shareTrackingRetryTimer = null;
      if (!_isCurrentContext(context)) return;
      if (!shouldTrackPendingVotingShares(context.round)) {
        _releaseAutomaticShareTracking();
        return;
      }
      unawaited(_startShareTracking());
    });
  }

  void _cancelShareTrackingRetry() {
    _shareTrackingRetryTimer?.cancel();
    _shareTrackingRetryTimer = null;
  }

  /// Floor for the re-arm backoff, applied to the configured base delay.
  ///
  /// Guards the multiplicative backoff against a zero or negative base, which
  /// would otherwise disable it entirely rather than shorten it.
  static const _minShareTrackingRetryDelay = Duration(seconds: 1);

  /// How this app paces a tracking run.
  ///
  /// The SDK caps a wait for a not-yet-due share at 30 seconds so a wallet
  /// using tracking as a general heartbeat re-reads the world regularly. Vizor
  /// has no use for that: a session's helper fleet and round timing are fixed
  /// when it opens, and a configuration change rebuilds the session rather
  /// than mutating it, so waking early can only re-read rows that have not
  /// changed. A share's submit time can be up to 100 hours out, so the cap
  /// would turn one wait into thousands of passes that each find nothing due.
  ///
  /// Waiting that long is safe because the wait is interruptible: the driver
  /// wakes on cancellation or an epoch change rather than polling, so a long
  /// wait costs nothing and ends as soon as Dart cancels the session.
  ///
  /// The pass still shortens any wait that would land past vote end, so this
  /// is bounded by the round, not by this number.
  static final _shareTrackingPolicy = rust_session.ApiShareTrackingDrivePolicy(
    futureCheckMaxDelaySeconds: BigInt.from(
      const Duration(hours: 120).inSeconds,
    ),
  );

  /// Refreshes the plan after a pass so the UI reflects newly confirmed shares.
  Future<void> _applyShareTrackingEvent(
    rust_wire.ShareTrackingEventView event,
    _VotingSessionContext context,
  ) async {
    if (event.kind != rust_wire.ShareTrackingEventKind.passFinished) return;
    final pass = event.report;
    // Only a durable confirmation changes what the UI shows mid-run. A
    // resubmission leaves the share pending and looks identical, so it does
    // not pay for a plan read.
    if (pass == null || pass.confirmed.isEmpty) return;
    if (!_isCurrentContext(context)) return;
    // No state to update yet means a rebuild is in flight and will publish its
    // own. Awaiting it here would stall the run's event stream — and with it
    // the SDK side feeding that stream — on a provider rebuild.
    final current = state.value;
    if (current == null) return;
    final roundPlan = await _loadRoundPlan(context);
    if (!_isCurrentContext(context)) return;
    _setStateForContext(
      context,
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.submittingShares,
        roundPlan: roundPlan,
      ),
    );
  }

  /// Reconciles the designated immediate share without reopening recovery.
  ///
  /// This is the one confirmation-only exception to the vote-end boundary:
  /// the helper may have confirmed the share before the deadline while the
  /// last tracking pass missed that transition. The SDK polls the configured
  /// helper quorum for the round and may persist other observed confirmations
  /// along the way; success here depends only on the designated immediate
  /// share. Because the round has ended, it never resubmits a share or selects
  /// a new helper.
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

        final rust = ref.read(votingRustApiProvider);
        final session = _openRoundSession(rust, context);
        _focusedConfirmationSession = session;
        final check = session.confirmImmediateShare(
          bundleIndex: immediateShare.bundleIndex,
          proposalId: immediateShare.proposalId,
          shareIndex: immediateShare.shareIndex,
        );
        _focusedConfirmation = check.then<void>((_) {}, onError: (_, _) {});
        final bool helperConfirmed;
        try {
          helperConfirmed = await check;
        } finally {
          _focusedConfirmation = null;
          if (identical(_focusedConfirmationSession, session)) {
            _focusedConfirmationSession = null;
          }
          _closeRoundSession(session);
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
              phase: _phaseWithoutBallotRegression(_phaseForPlans(roundPlan)),
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

  /// Stops tracking and waits for the run to finish.
  ///
  /// Destructive wallet operations block on this: the run must be off the
  /// sidecar before the account's state is cleared. Cancelling the session is
  /// observed inside a pass as well as between passes, so this does not wait
  /// out a tracking delay.
  Future<void> stopAndDrainShareTracking() async {
    _automaticShareTrackingStopped = true;
    // Before the drain loop, not after: a pending re-arm that fired mid-drain
    // would start a run the caller has already stopped waiting for.
    _cancelShareTrackingRetry();
    _shareTrackingRetryStreak = 0;
    _advanceSessionGeneration();
    _shareTrackingSession?.cancel();
    _focusedConfirmationSession?.cancel();
    try {
      // Both futures are settled by construction: a run handles its own
      // failure and the focused check swallows its own. A destructive wallet
      // operation needs them finished, not successful, so waiting here can
      // never fail — and must never be able to, or a drain could leave the
      // account's state half cleared.
      while (_shareTrackingRun != null || _focusedConfirmation != null) {
        await _shareTrackingRun;
        await _focusedConfirmation;
      }
    } finally {
      _releaseAutomaticShareTracking();
    }
  }

  void resumeShareTracking() {
    _automaticShareTrackingStopped = false;
    // A resume is new information — the app unlocked, the account came back —
    // so the next attempt starts from the base delay rather than inheriting
    // the backoff of an outage that may already be over.
    _shareTrackingRetryStreak = 0;
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
    // The SDK retains the exact PCZT for the later Keystone signing request.
    if (bundleCount == 0) return true;
    if (!_isCurrentPrecomputeContext(context, context.accountUuid)) {
      return false;
    }

    final rust = ref.read(votingRustApiProvider);
    late final List<int> storedHotkeySecret;
    try {
      final signatures = context.isHardwareAccount
          ? await _loadKeystoneSignatures(context)
          : const <int, rust_wire.KeystoneSignatureRecord>{};
      storedHotkeySecret = await _ensureHotkey(
        context,
        alreadyBound: signatures.isNotEmpty,
      );
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
          final generated = await withVotingRetry(
            policy: _delegationSetupRetryPolicy,
            isCancelled: () =>
                !_isCurrentPrecomputeContext(context, context.accountUuid),
            operation: () => rust.precomputeDelegationProof(
              ctx: _apiRoundContext(context),
              pirServerUrls: pirServerUrls,
              storedHotkeySecret: storedHotkeySecret,
              bundleIndex: bundleIndex,
            ),
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
      'diagnostics=${pirSnapshotDiagnosticsLog(error.diagnostics)}',
    );
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
          await _cleanupCurrentSessionCaches(reason: 'action-failed');
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

  static String _actionErrorMessage(Object error) {
    return friendlyVotingErrorMessage(error);
  }

  static bool _needsDelegationPreparation(VotingSessionState state) {
    return state.pirEndpoint == null || state.eligibleWeightZatoshi == null;
  }

  static bool _needsFreshDelegationPreparation(
    rust_wire.RoundPlanView? roundPlan,
  ) {
    if (delegationBundleIndexesNeedingSigning(roundPlan).isNotEmpty) {
      return true;
    }
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
    final requests = await withVotingRetry(
      policy: _delegationSetupRetryPolicy,
      isCancelled: () =>
          !_isCurrentPrecomputeContext(context, context.accountUuid),
      operation: () => rust.buildKeystoneDelegationRequests(
        ctx: _apiRoundContext(context),
        storedHotkeySecret: storedHotkeySecret,
        bundleIndices: unsignedBundleIndexes,
      ),
    );

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
        pirSnapshotMismatchMessage(
          expectedSnapshotHeight: e.expectedSnapshotHeight,
          diagnostics: e.diagnostics,
          includeDiagnostics: true,
        ),
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
      final eligibility = await observeVotingHomeResult(
        ref,
        operation: () => ref
            .read(votingRustApiProvider)
            .checkVotingEligibility(ctx: _apiRoundContext(context)),
        record: (cache, result) => cache.recordEligibility(
          votingHomeFactKey(
            context.network,
            context.config.sourceFingerprint,
            context.accountUuid,
            context.round.roundId,
          ),
          result.isEligible,
          context.round.snapshotHeight,
        ),
      );
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
    final release = ref
        .read(votingShareTrackingRegistryProvider)
        .beginBackgroundWork();
    if (release == null) {
      throw StateError('Voting work is paused for wallet changes.');
    }
    try {
      return await _loadContextWithCache(
        roundId,
        checkStaleAction: checkStaleAction,
      );
    } finally {
      release();
    }
  }

  Future<_VotingSessionContext> _loadContextWithCache(
    String roundId, {
    required bool checkStaleAction,
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
    final roundPlan = await observeVotingHomeResult(
      ref,
      operation: () => ref
          .read(votingRecoveryServiceProvider)
          .loadRoundPlan(
            dbPath: dbPath,
            accountUuid: accountUuid,
            roundId: round.roundId,
            proposalIds: proposalIds,
          ),
      record: (cache, plan) => cache.recordPlan(
        votingHomeFactKey(
          endpoint.networkName,
          config.sourceFingerprint,
          accountUuid,
          round.roundId,
        ),
        plan,
      ),
    );
    checkAction();
    final context = _VotingSessionContext(
      sessionGeneration: _sessionGeneration,
      dbPath: dbPath,
      accountUuid: accountUuid,
      isHardwareAccount: isHardwareAccount,
      network: _loggedVotingNetwork(endpoint.networkName),
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
    return observeVotingHomeResult(
      ref,
      operation: () => ref
          .read(votingRecoveryServiceProvider)
          .loadRoundPlan(
            dbPath: context.dbPath,
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
            proposalIds: proposals.map((p) => p.id).toList(),
          ),
      record: (cache, plan) => cache.recordPlan(
        votingHomeFactKey(
          context.network,
          context.config.sourceFingerprint,
          context.accountUuid,
          context.round.roundId,
        ),
        plan,
      ),
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
    if (_isRunningActionSuperseded) {
      _logStaleSessionUpdate('ui-action', actionGeneration!);
      return false;
    }
    if (context == null) return true;
    if (!_isCurrentContext(context)) {
      _logStaleSessionUpdate('ui-context', context.sessionGeneration, context);
      return false;
    }
    return true;
  }

  /// Whether the queued action currently running belongs to a superseded
  /// generation.
  ///
  /// This is the one staleness question a context cannot answer, because it
  /// applies before an action has loaded one. Everything else layers on
  /// [_isCurrentGeneration]: [_isCurrentContext] adds the account the context
  /// was loaded for, and [_isCurrentPrecomputeContext] adds the account its
  /// caller expected. They are the same comparison at different points in an
  /// action's life, not independent mechanisms.
  bool get _isRunningActionSuperseded {
    final actionGeneration = _runningActionGeneration;
    return actionGeneration != null && actionGeneration != _sessionGeneration;
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
    if (_isRunningActionSuperseded) throw const _StaleVotingSessionAction();
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

  /// Clear cached vote-tree state for the current round after an action failure.
  ///
  /// The context is reloaded so cleanup follows the session account and DB path.
  /// If that lookup fails, cleanup is skipped because there is no safe key to
  /// clear.
  Future<void> _cleanupCurrentSessionCaches({required String reason}) async {
    try {
      final context = await _loadContext(_roundId);
      await _resetVotingSessionCaches(
        rust: ref.read(votingRustApiProvider),
        context: context,
        reason: reason,
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: session cache cleanup skipped '
        'round=$_roundId reason=$reason error=$e',
      );
    } finally {
      if (_shareTrackingRun == null) _releaseAutomaticShareTracking();
    }
  }

  /// Clear round-scoped Rust voting caches for this session.
  ///
  /// Passing the round ID intentionally preserves the account-wide vote-tree
  /// sync client. Durable delegation setup remains available to in-flight proof
  /// jobs and to the next signing request.
  static Future<void> _resetVotingSessionCaches({
    required VotingRustApi rust,
    required _VotingSessionContext context,
    required String reason,
  }) async {
    try {
      await rust.resetVoteTree(
        dbPath: context.dbPath,
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
      );
      debugPrint(
        '[zcash] Voting: session cache reset '
        'round=${context.round.roundId} account=${context.accountUuid} '
        'reason=$reason',
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: session cache reset failed '
        'round=${context.round.roundId} account=${context.accountUuid} '
        'reason=$reason error=$e',
      );
    }
  }

  /// Whether this phase means the round is at or past the ballot.
  static bool _isBallotPhase(VotingSessionPhase phase) {
    return phase == VotingSessionPhase.castingVotes ||
        phase == VotingSessionPhase.submittingShares;
  }

  /// A phase to publish that cannot drag the submission back before the
  /// ballot.
  ///
  /// The step list the voter watches is derived from this field, and several
  /// writers legitimately report a pre-vote phase while a vote is already in
  /// flight — a sibling bundle that still owes a delegation signature, a plan
  /// refresh whose primary action is `delegate`, background share tracking
  /// finishing. Publishing those moved the active step backwards mid-vote.
  ///
  /// Terminal and interactive phases still get through: an error has to be
  /// shown, `done` is the end of the round, and Keystone signing drives the QR
  /// panel.
  VotingSessionPhase _phaseWithoutBallotRegression(VotingSessionPhase next) {
    final current = state.value?.phase;
    if (current == null || !_isBallotPhase(current)) return next;
    if (_isBallotPhase(next) ||
        next == VotingSessionPhase.done ||
        next == VotingSessionPhase.error ||
        next == VotingSessionPhase.keystoneSigning) {
      return next;
    }
    return current;
  }

  /// Folds a run-scoped tally into what the round has already shown.
  ///
  /// `RoundWorkTallyView` measures one run against what *that run* started
  /// owing. A round is often driven by two runs — the delegation drive casts
  /// votes too — so the second run owes less than the first and would shrink
  /// the denominator the voter is reading. The crate also recomputes the
  /// finished count from scratch on each refresh, so it can fall mid-run.
  /// Neither is progress the voter lost.
  static rust_wire.RoundWorkTallyView _mergeTally(
    rust_wire.RoundWorkTallyView? previous,
    rust_wire.RoundWorkTallyView? next,
  ) {
    if (next == null) {
      return previous ??
          const rust_wire.RoundWorkTallyView(
            completedProposals: 0,
            totalProposals: 0,
            remainingObligations: 0,
          );
    }
    if (previous == null) return next;
    return rust_wire.RoundWorkTallyView(
      completedProposals: next.completedProposals > previous.completedProposals
          ? next.completedProposals
          : previous.completedProposals,
      totalProposals: next.totalProposals > previous.totalProposals
          ? next.totalProposals
          : previous.totalProposals,
      remainingObligations: next.remainingObligations,
    );
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
class VotingRoundStepFailure implements Exception, VotingRustExceptionSource {
  const VotingRoundStepFailure(this.step, this.failure);

  final rust_wire.NextStepView step;
  final rust_wire.RoundStepFailureView failure;

  /// Eligibility is the one step-failure category the app presents as a
  /// state of the account rather than an error of the action: it suppresses
  /// retry and switches the round to its not-eligible copy. The step failure
  /// carries only a kind and a message, so the classified view it exposes
  /// carries no payload and the message builder falls back to naming the
  /// round's snapshot block generically.
  @override
  VotingRustException? get votingRustException {
    final kind = switch (failure.kind) {
      rust_wire.RoundStepFailureKindView.insufficientEligibility =>
        rust_wire.VotingErrorKindView.insufficientEligibility,
      rust_wire.RoundStepFailureKindView.noSpendableNotes =>
        rust_wire.VotingErrorKindView.noSpendableNotes,
      _ => null,
    };
    if (kind == null) return null;
    return VotingRustException(
      rust_wire.VotingErrorView(
        kind: kind,
        retryable: false,
        message: failure.message,
      ),
    );
  }

  @override
  String toString() => failure.message;
}

/// The chain reported a terminal outcome for a step.
///
/// Terminal means the submission ended without a confirmation and the SDK
/// plans no retry for it, so the diagnostic it carries is the only account of
/// what happened.
class VotingChainTerminalOutcome implements Exception {
  const VotingChainTerminalOutcome(this.step, this.chainOutcome);

  final rust_wire.NextStepView? step;
  final rust_wire.ChainSubmissionOutcomeView? chainOutcome;

  @override
  String toString() {
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
///
/// Not terminal: running the round again later may still resolve it, which is
/// why it is reported separately from a rejection.
class VotingChainPendingOutcome implements Exception {
  const VotingChainPendingOutcome(this.step, this.chainOutcome);

  final rust_wire.NextStepView? step;
  final rust_wire.ChainSubmissionOutcomeView? chainOutcome;

  @override
  String toString() =>
      chainOutcome?.diagnostic?.message ??
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
