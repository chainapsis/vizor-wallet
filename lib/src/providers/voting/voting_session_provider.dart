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
import '../../rust/api/voting.dart' as rust_api;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_helper_health_tracker.dart';
import '../../services/voting/voting_models.dart';
import '../app_security_provider.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_share_tracking_registry_provider.dart';
import 'voting_state.dart';
import 'voting_submission_guard_provider.dart';

final _minimumVotingBundleWeightZatoshi = BigInt.from(12500000);

const _votingAlreadyStartedMessage =
    "Voting has already started for these funds, but Vizor couldn't recover "
    'the submission status. If you used another wallet, return to it to see '
    'the status.';

final _nullifierAlreadySpentPattern = RegExp(
  r'nullifier already spent:\s*\S+',
  caseSensitive: false,
);
const _spentNullifierRecoveryMaxAttempts = 3;
const _spentNullifierRecoveryMaxDelay = Duration(seconds: 1);

/// The PCZT value-pool tag for Ironwood actions.
///
/// Ironwood spend authorization uses a RedPallas key derived from the
/// account's Orchard key, but the action remains in the PCZT's Ironwood bundle.
const _ironwoodPcztPool = 1;

/// Cap for independent voting work pools: delegation proofs, vote proofs,
/// share submission, and recovery polling.
const _votingWorkConcurrency = 3;

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
  final Map<String, Future<void>> _delegationPirPrecomputes = {};
  final Map<String, Future<List<int>>> _hotkeyEnsures = {};
  Timer? _shareTrackingTimer;
  Future<void>? _shareTrackingPass;
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
      _delegationPirPrecomputes.clear();
      _hotkeyEnsures.clear();
      _shareTrackingTimer?.cancel();
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
    _delegationPirPrecomputes.clear();
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

  Future<void> precomputeDelegationPir({required String accountUuid}) async {
    final context = await _loadContext(_roundId);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    try {
      await _waitUntilWalletReadyForVoting(context);
    } on _StaleVotingSessionAction {
      return;
    } on _VotingWalletSyncTimeout catch (e) {
      _setWalletSyncReadinessState(
        context: context,
        readiness: e.readiness,
        waiting: false,
      );
      debugPrint(
        '[zcash] Voting: delegation PIR precompute skipped '
        'round=${context.round.roundId} reason=wallet-sync-timeout error=$e',
      );
      return;
    }
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final plan = await _loadResumePlan(context);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final pendingBundles = plan.pendingDelegationBundleIndexes;
    if (pendingBundles.isEmpty) {
      // Fresh rounds (no durable bundles yet) land here by design: the
      // bundle-independent background warm-up (votingPirWarmupProvider) has
      // already cached the real-note PIR proofs, so the prove-time precompute
      // only fetches the per-bundle padded-slot nullifiers.
      debugPrint(
        '[zcash] Voting: delegation PIR precompute skipped '
        'round=${context.round.roundId} reason=no-pending-bundles '
        '(real-note proofs come from the background PIR cache warmup)',
      );
      return;
    }
    final pirEndpoint = await _resolvePirEndpoint(context);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    if (pirEndpoint == null) return;
    final signatures = context.isHardwareAccount
        ? await _loadKeystoneSignatures(context)
        : const <int, rust_wire.KeystoneSignatureRecord>{};
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final List<int> storedHotkeySecret;
    try {
      storedHotkeySecret = await _ensureHotkey(
        context,
        alreadyBound: signatures.isNotEmpty,
      );
    } on VotingHotkeyUnavailable catch (e) {
      debugPrint(
        '[zcash] Voting: delegation PIR precompute skipped '
        'round=${context.round.roundId} reason=missing-hotkey error=$e',
      );
      return;
    }
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;

    for (final bundleIndex in pendingBundles) {
      final key = _delegationPirPrecomputeKey(context, bundleIndex);
      _delegationPirPrecomputes[key] ??= _runDelegationPirPrecompute(
        context: context,
        pirEndpoint: pirEndpoint,
        storedHotkeySecret: storedHotkeySecret,
        bundleIndex: bundleIndex,
      );
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

      final hasPendingBundles = plan.pendingDelegationBundleIndexes.isNotEmpty;
      final pirEndpoint = current.pirEndpoint;
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
      final completedBundleIndexes = await _confirmSubmittedDelegations(
        context: context,
        plan: plan,
        roundPlan: roundPlan,
        progress: progress,
      );
      if (completedBundleIndexes == null) return;
      try {
        completedBundleIndexes.addAll(
          await _runDelegationBundleBatch(
            context: context,
            fallbackState: current,
            bundleIndexes: plan.pendingDelegationBundleIndexes,
            progress: progress,
            logLabel: 'software',
            prove: (bundleIndex, publishProgress) async {
              await _awaitDelegationPirPrecomputeIfRunning(
                context,
                bundleIndex,
              );
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
      } catch (error) {
        final isConflict = error.toString().contains(
          'Keystone signature conflict',
        );
        reject(
          isConflict
              ? 'This Keystone result conflicts with a signature already saved for this voting request. Restart Keystone signing and scan the newly generated result.'
              : 'Could not save the Keystone signatures. Scan the same Keystone result again.',
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
      final completedBundleIndexes = await _confirmSubmittedDelegations(
        context: context,
        plan: plan,
        roundPlan: roundPlan,
        progress: progress,
      );
      if (completedBundleIndexes == null) return;

      final hasPendingBundles = plan.pendingDelegationBundleIndexes.isNotEmpty;
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
      final pirEndpoint = current.pirEndpoint;
      if (hasPendingBundles && pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.', context: context);
        return;
      }

      final rust = ref.read(votingRustApiProvider);
      for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
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
            bundleIndexes: plan.pendingDelegationBundleIndexes,
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
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);

      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      var plan = context.resumePlan;
      var roundPlan = context.roundPlan;
      final api = ref.read(votingApiClientProvider(context.config.apiServers));
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

      var confirmedSubmittedVotes = false;
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
          final txHash = work.txHash;
          if (txHash == null) {
            throw StateError(
              'Missing submitted vote transaction hash for '
              'bundle ${key.bundleIndex}, proposal ${key.proposalId}.',
            );
          }
          final confirmation = await _awaitTxConfirmation(
            api,
            txHash,
            context: context,
          );
          if (confirmation == null) {
            throw _VoteConfirmationTimeout(key: key, txHash: txHash);
          }
          return _PolledVoteRecovery(
            key: key,
            txHash: txHash,
            confirmation: confirmation,
          );
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
        final polled = outcome.value!;
        final key = polled.key;
        final txHash = polled.txHash;
        final confirmation = polled.confirmation;
        if (confirmation.code != 0) {
          voteRecoveryFailures.add(
            _VoteWaveFailure(
              bundleIndex: key.bundleIndex,
              proposalId: key.proposalId,
              stage: 'recovery confirmation',
              error: StateError(
                confirmation.log.isEmpty
                    ? 'Vote commitment transaction failed.'
                    : confirmation.log,
              ),
            ),
          );
          continue;
        }
        try {
          await rust.confirmVoteSubmission(
            dbPath: context.dbPath,
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
            bundleIndex: key.bundleIndex,
            proposalId: key.proposalId,
            txHash: txHash,
            eventsJson: confirmation.eventsJson,
          );
        } catch (error) {
          voteRecoveryFailures.add(
            _VoteWaveFailure(
              bundleIndex: key.bundleIndex,
              proposalId: key.proposalId,
              stage: 'recovery confirmation persistence',
              error: error,
            ),
          );
          continue;
        }
        progress[key] = VotingSessionProgress(
          phase: 'confirmed',
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          message: txHash,
        );
        confirmedSubmittedVotes = true;
      }
      if (confirmedSubmittedVotes) {
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
        final error = failure.error;
        if (error is _VoteConfirmationTimeout) {
          _setError(
            'Vote commitment transaction ${error.txHash} for bundle '
            '${error.key.bundleIndex}, proposal ${error.key.proposalId} is still '
            'unconfirmed after repeated checks. Retry to resume confirmation '
            'before continuing.',
            context: context,
          );
          return;
        }
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
      final totalQuestions = recoveredVoteWork.length + voteWork.length;
      final totalBundleTasks =
          recoveredVoteWork.length +
          voteWork.fold<int>(
            0,
            (total, work) => total + work.bundleIndexes.length,
          );
      final helperAvailability = totalBundleTasks == 0
          ? Future.value(const <String, bool>{})
          : ref
                .read(votingApiClientProvider(context.config.apiServers))
                .preflightHelpers(context.config.apiServers.all);
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
          helperAvailability: helperAvailability,
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
            helperAvailability: helperAvailability,
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

  Future<void> _submitCommitmentShares(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments, {
    required Future<Map<String, bool>> helperAvailability,
    Map<int, BigInt> vcTreePositions = const {},
    Set<int>? shareIndexFilter,
    void Function(VotingSessionProgress progress)? publishProgress,
    required bool singleShare,
    required int completedQuestions,
    required int totalQuestions,
    required double? voteSubmissionProgress,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiServers));
    final rust = ref.read(votingRustApiProvider);
    final helperHealth = ref.read(votingHelperHealthTrackerProvider);
    final serverUrls = context.config.apiServers.all
        .map((endpoint) => endpoint.toString())
        .toList(growable: false);
    if (serverUrls.isEmpty) {
      throw StateError('No vote servers configured for share submission.');
    }
    final availableHelpers = await helperAvailability;
    _throwIfContextStale(context, 'helper-preflight-finished');

    final timing = _roundShareTiming(context, _nowSeconds());
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
        nowSeconds: BigInt.from(timing.nowSeconds),
        voteEndTimeSeconds: BigInt.from(timing.voteEndSeconds),
        lastMomentBufferSeconds: timing.lastMomentBufferSeconds,
        singleShare: singleShare,
      );
      if (plans.length != shares.length) {
        throw StateError(
          'Share submission policy returned ${plans.length} plan(s) for '
          '${shares.length} payload(s).',
        );
      }
      // Validate every body before starting helper requests. Otherwise a later
      // serialization failure could abandon already accepted submissions.
      final preparedSubmissions = <_PreparedInitialShareSubmission>[];
      for (var payloadIndex = 0; payloadIndex < shares.length; payloadIndex++) {
        final share = shares[payloadIndex];
        final plan = plans[payloadIndex];
        final targetCount = plan.targetCount
            .clamp(1, serverUrls.length)
            .toInt();
        final candidateServers = _plannedShareServers(
          plannedServers: plan.targetServers,
          fallbackServers: helperHealth.candidateServers(serverUrls),
          helperAvailability: availableHelpers,
        );
        final body = await _wireJsonMap(
          rust.voteShareWireJson(
            share: share,
            vcTreePosition: vcTreePosition,
            submitAt: plan.submitAt,
          ),
        );
        if (publishProgress == null) {
          _setShareSubmissionProgress(
            context: context,
            bundleIndex: commitments.bundleIndex,
            proposalId: share.proposalId,
            message: bundleProgressMessage,
            completedQuestions: completedQuestions,
            totalQuestions: totalQuestions,
            voteSubmissionProgress: voteSubmissionProgress,
          );
        } else {
          publishProgress(
            VotingSessionProgress(
              phase: 'submitting_shares',
              bundleIndex: commitments.bundleIndex,
              proposalId: share.proposalId,
              message: bundleProgressMessage,
            ),
          );
        }
        preparedSubmissions.add(
          _PreparedInitialShareSubmission(
            share: share,
            body: body,
            candidateServers: candidateServers,
            targetCount: targetCount,
            submitAt: plan.submitAt,
          ),
        );
      }

      final submissions = [
        for (final prepared in preparedSubmissions)
          _submitInitialShareToHelpers(
            api: api,
            helperHealth: helperHealth,
            share: prepared.share,
            body: prepared.body,
            candidateServers: prepared.candidateServers,
            targetCount: prepared.targetCount,
            submitAt: prepared.submitAt,
          ),
      ];
      _InitialShareSubmissionResult? failedResult;
      Object? persistenceError;
      StackTrace? persistenceStackTrace;
      // Persist in completion order so accepted shares become durable promptly
      // while Rust DB writes remain sequential.
      await for (final result in Stream.fromFutures(submissions)) {
        if (result.acceptedServers.isEmpty) {
          failedResult ??= result;
          continue;
        }
        try {
          await rust.recordShareDelegation(
            dbPath: context.dbPath,
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
            bundleIndex: commitments.bundleIndex,
            proposalId: result.share.proposalId,
            shareIndex: result.share.shareIndex,
            sentToUrls: result.acceptedServers,
            submitAt: result.submitAt,
          );
        } catch (error, stackTrace) {
          persistenceError ??= error;
          persistenceStackTrace ??= stackTrace;
        }
      }
      if (persistenceError != null) {
        Error.throwWithStackTrace(persistenceError, persistenceStackTrace!);
      }
      if (failedResult != null) {
        throw StateError(
          'No vote server accepted share ${failedResult.share.shareIndex} '
          'for proposal ${failedResult.share.proposalId}.',
        );
      }
    }
  }

  Future<_InitialShareSubmissionResult> _submitInitialShareToHelpers({
    required VotingApiClient api,
    required VotingHelperHealthTracker helperHealth,
    required rust_wire.VoteShareWire share,
    required Map<String, dynamic> body,
    required List<String> candidateServers,
    required int targetCount,
    required BigInt submitAt,
  }) async {
    final acceptedServers = <String>[];
    final remainingServers = LinkedHashSet<String>.of(candidateServers);
    while (remainingServers.isNotEmpty &&
        acceptedServers.length < targetCount) {
      // Re-evaluate health before every attempt so failures observed by
      // concurrent submissions can move a degraded helper behind healthy
      // alternatives. The tracker still returns every helper when all are
      // degraded, preserving the liveness fallback.
      final serverUrl = helperHealth.candidateServers(remainingServers).first;
      remainingServers.remove(serverUrl);
      try {
        debugPrint(
          '[zcash] Voting: submitting share '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl treePosition=${body['tree_position']} '
          'submitAt=$submitAt target=$targetCount',
        );
        await api.submitShare(serverUrl: Uri.parse(serverUrl), share: body);
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
    if (acceptedServers.length < targetCount && acceptedServers.isNotEmpty) {
      debugPrint(
        '[zcash] Voting: share accepted by fewer helpers than planned '
        'proposal=${share.proposalId} share=${share.shareIndex} '
        'accepted=${acceptedServers.length}/$targetCount',
      );
    }
    return _InitialShareSubmissionResult(
      share: share,
      submitAt: submitAt,
      acceptedServers: acceptedServers,
    );
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

  List<String> _plannedShareServers({
    required List<String> plannedServers,
    required Iterable<String> fallbackServers,
    Map<String, bool> helperAvailability = const {},
  }) {
    final ordered = <String>{};
    for (final server in plannedServers) {
      if (server.trim().isNotEmpty) ordered.add(server);
    }
    for (final server in fallbackServers) {
      if (server.trim().isNotEmpty) ordered.add(server);
    }
    return [
      for (final readiness in const <bool?>[true, null, false])
        for (final server in ordered)
          if (helperAvailability[server] == readiness) server,
    ];
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
    required Future<Map<String, bool>> helperAvailability,
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
    // Cast-vote broadcasts stay one-at-a-time across all bundles; only the
    // confirmation wait that follows them overlaps.
    final broadcastPool = _AsyncPermitPool(1);
    _VotingAlreadyStarted? votingAlreadyStartedAbort;
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
          final bool singleShare;
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
            singleShare = timedDraft.singleShare;
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

          final Map<int, String> txHashes;
          try {
            _throwIfContextStale(context, 'vote-chain-submit');
            final submitTimer = Stopwatch()..start();
            txHashes = await broadcastPool.run(() async {
              final abort = votingAlreadyStartedAbort;
              if (abort != null) throw abort;
              try {
                return await _submitVoteCommitmentsWithoutConfirmation(
                  context,
                  commitments,
                );
              } on _VotingAlreadyStarted catch (error) {
                // Set the shared abort before releasing the single broadcast
                // permit, so already queued bundle chains cannot submit after
                // one of the round's voting nullifiers has already been spent.
                votingAlreadyStartedAbort ??= error;
                rethrow;
              }
            });
            _logVoteTiming(
              'bundle=$bundleIndex proposal=${key.proposalId} '
              'submit elapsed=${formatElapsedSeconds(submitTimer.elapsed)}',
            );
            publish(
              VotingSessionProgress(
                phase: 'submitted',
                bundleIndex: bundleIndex,
                proposalId: key.proposalId,
                proofProgress: 1,
                message: txHashes[key.proposalId],
              ),
            );
          } catch (error) {
            recordFailure(key: key, stage: 'submission', error: error);
            return;
          }

          final confirmations = <int, VotingTxConfirmation>{};
          try {
            final confirmTimer = Stopwatch()..start();
            final api = ref.read(
              votingApiClientProvider(context.config.apiServers),
            );
            for (final entry in txHashes.entries) {
              final confirmation = await _awaitTxConfirmation(
                api,
                entry.value,
                context: context,
              );
              if (confirmation == null) {
                throw StateError(
                  'Transaction ${entry.value} was not confirmed in time.',
                );
              }
              if (confirmation.code != 0) {
                throw StateError(
                  confirmation.log.isEmpty
                      ? 'Vote commitment transaction failed.'
                      : confirmation.log,
                );
              }
              confirmations[entry.key] = confirmation;
            }
            _logVoteTiming(
              'bundle=$bundleIndex proposal=${key.proposalId} '
              'confirm-wait elapsed=${formatElapsedSeconds(confirmTimer.elapsed)}',
            );
          } catch (error) {
            recordFailure(key: key, stage: 'confirmation', error: error);
            return;
          }

          final Map<int, BigInt> vcTreePositions;
          try {
            // Advances this bundle's stored VAN position, which is what unblocks
            // the next proposal in this chain.
            final persistTimer = Stopwatch()..start();
            vcTreePositions = await _persistVoteConfirmations(
              context,
              bundleIndex: bundleIndex,
              txHashes: txHashes,
              confirmations: confirmations,
            );
            _logVoteTiming(
              'bundle=$bundleIndex proposal=${key.proposalId} '
              'confirm-persist elapsed=${formatElapsedSeconds(persistTimer.elapsed)}',
            );
            publish(
              VotingSessionProgress(
                phase: 'confirmed',
                bundleIndex: bundleIndex,
                proposalId: key.proposalId,
                proofProgress: 1,
                message: txHashes[key.proposalId],
              ),
            );
          } catch (error) {
            recordFailure(
              key: key,
              stage: 'confirmation persistence',
              error: error,
            );
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
                helperAvailability: helperAvailability,
                vcTreePositions: vcTreePositions,
                publishProgress: publish,
                singleShare: singleShare,
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
        if (failure.error is _VotingAlreadyStarted) {
          throw failure.error;
        }
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

  Future<Map<int, String>> _submitVoteCommitmentsWithoutConfirmation(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments,
  ) async {
    final api = ref.read(votingApiClientProvider(context.config.apiServers));
    final rust = ref.read(votingRustApiProvider);
    final txHashes = <int, String>{};
    for (final commitment in commitments.commitments) {
      final result = await api.submitVoteCommitment(
        commitment: await _wireJsonMap(
          rust.voteCommitmentWireJson(commitment: commitment.wire),
        ),
      );
      await _requireAcceptedVotingTransaction(
        result,
        waitForConfirmation: (txHash) => _awaitTxConfirmation(
          api,
          txHash,
          context: context,
          spentNullifierRecovery: true,
        ),
        rejectionMessage: 'Vote commitment transaction was rejected.',
      );
      if (result.txHash.isEmpty) {
        throw StateError('Vote commitment response did not include tx_hash.');
      }
      await rust.markVoteSubmitted(
        dbPath: context.dbPath,
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
      );
      txHashes[commitment.proposalId] = result.txHash;
    }
    return txHashes;
  }

  Future<Map<int, BigInt>> _persistVoteConfirmations(
    _VotingSessionContext context, {
    required int bundleIndex,
    required Map<int, String> txHashes,
    required Map<int, VotingTxConfirmation> confirmations,
  }) async {
    final rust = ref.read(votingRustApiProvider);
    final vcTreePositions = <int, BigInt>{};
    for (final entry in txHashes.entries) {
      final confirmation = confirmations[entry.key]!;
      final result = await rust.confirmVoteSubmission(
        dbPath: context.dbPath,
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: bundleIndex,
        proposalId: entry.key,
        txHash: entry.value,
        eventsJson: confirmation.eventsJson,
      );
      vcTreePositions[entry.key] = result.vcTreePosition;
    }
    return vcTreePositions;
  }

  Future<Map<int, BigInt>> _submitVoteCommitments(
    _VotingSessionContext context,
    rust_wire.SignedVoteCommitmentsView commitments,
  ) async {
    final api = ref.read(votingApiClientProvider(context.config.apiServers));
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
      await _requireAcceptedVotingTransaction(
        result,
        waitForConfirmation: (txHash) => _awaitTxConfirmation(
          api,
          txHash,
          context: context,
          spentNullifierRecovery: true,
        ),
        rejectionMessage: 'Vote commitment transaction was rejected.',
      );
      if (result.txHash.isEmpty) {
        throw StateError('Vote commitment response did not include tx_hash.');
      }
      await rust.markVoteSubmitted(
        dbPath: context.dbPath,
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
      );

      final confirmation = await _awaitTxConfirmation(
        api,
        result.txHash,
        context: context,
      );
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
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
        eventsJson: confirmation.eventsJson,
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
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
        );
    return {for (final record in records) record.bundleIndex: record};
  }

  Future<Set<int>?> _confirmSubmittedDelegations({
    required _VotingSessionContext context,
    required VotingResumePlan plan,
    required rust_wire.RoundPlanView? roundPlan,
    required Map<int, VotingSessionProgress> progress,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiServers));
    final rust = ref.read(votingRustApiProvider);
    final completedBundleIndexes = <int>{};
    final submittedDelegationsByBundle = <int, String>{};
    for (final work
        in roundPlan?.recoveredDelegationWork ??
            const <rust_wire.DelegationRecoveryWorkView>[]) {
      if (work.kind == 'poll_delegation' && work.txHash != null) {
        submittedDelegationsByBundle[work.bundleIndex] = work.txHash!;
      }
    }
    for (final record in plan.recoveryState.delegation) {
      if (record.phase == VotingWorkflowPhase.submittedDelegation &&
          record.txHash != null) {
        submittedDelegationsByBundle.putIfAbsent(
          record.bundleIndex,
          () => record.txHash!,
        );
      }
    }
    for (final entry in submittedDelegationsByBundle.entries) {
      final bundleIndex = entry.key;
      final txHash = entry.value;
      final confirmation = await _awaitTxConfirmation(
        api,
        txHash,
        context: context,
      );
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
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: bundleIndex,
        txHash: txHash,
        eventsJson: confirmation.eventsJson,
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
    final submittedTxHashes = <int, String>{};

    // Broadcasts remain serial because the vote server API does not expose an
    // idempotency key. Persist each returned hash before starting the next one.
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
        final txHash = await _submitDelegation(
          context: context,
          bundleIndex: bundleIndex,
          submission: proof.value!,
        );
        submittedTxHashes[bundleIndex] = txHash;
        publishProgress(
          VotingSessionProgress(
            phase: 'submitted',
            bundleIndex: bundleIndex,
            message: txHash,
          ),
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
        if (error is _StaleVotingSessionAction ||
            error is _VotingAlreadyStarted) {
          break;
        }
      }
    }

    final confirmationOutcomes = await _runBoundedBundleWork(
      submittedTxHashes.keys.toList(growable: false),
      concurrency: _votingWorkConcurrency,
      work: (bundleIndex) => _confirmDelegation(
        context: context,
        bundleIndex: bundleIndex,
        txHash: submittedTxHashes[bundleIndex]!,
      ),
    );
    final completed = <int>{};
    for (final bundleIndex in submittedTxHashes.keys) {
      final confirmation = confirmationOutcomes[bundleIndex]!;
      if (confirmation.error != null) {
        publishProgress(
          VotingSessionProgress(
            phase: 'failed',
            bundleIndex: bundleIndex,
            message: confirmation.error.toString(),
          ),
        );
        failures.add(
          _DelegationBundleFailure(
            bundleIndex: bundleIndex,
            stage: 'confirmation',
            error: confirmation.error!,
          ),
        );
        continue;
      }
      final result = confirmation.value!;
      completed.add(bundleIndex);
      publishProgress(
        VotingSessionProgress(
          phase: 'confirmed',
          bundleIndex: bundleIndex,
          message: result.txHash,
        ),
      );
      debugPrint(
        '[zcash] Voting: $logLabel delegation bundle completed '
        'round=${context.round.roundId} bundle=$bundleIndex '
        'leafIndex=${result.leafIndex} '
        'total=${formatElapsedSeconds(timers[bundleIndex]!.elapsed)}',
      );
    }

    for (final failure in failures) {
      if (failure.error is _StaleVotingSessionAction ||
          failure.error is _VotingAlreadyStarted) {
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

  Future<String> _submitDelegation({
    required _VotingSessionContext context,
    required int bundleIndex,
    required rust_wire.SignedDelegationPayloadView submission,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiServers));
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
    await _requireAcceptedVotingTransaction(
      result,
      waitForConfirmation: (txHash) => _awaitTxConfirmation(
        api,
        txHash,
        context: context,
        spentNullifierRecovery: true,
      ),
      rejectionMessage: 'Delegation transaction was rejected.',
    );
    await rust.markDelegationSubmitted(
      dbPath: context.dbPath,
      accountUuid: context.accountUuid,
      roundId: context.round.roundId,
      bundleIndex: bundleIndex,
      txHash: result.txHash,
    );
    debugPrint(
      '[zcash] Voting: delegation tx hash stored '
      'round=${context.round.roundId} bundle=$bundleIndex '
      'txHash=${result.txHash}',
    );
    return result.txHash;
  }

  Future<({String txHash, int leafIndex})> _confirmDelegation({
    required _VotingSessionContext context,
    required int bundleIndex,
    required String txHash,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiServers));
    final rust = ref.read(votingRustApiProvider);
    final confirmation = await _awaitTxConfirmation(
      api,
      txHash,
      context: context,
    );
    if (confirmation == null) {
      throw StateError('Transaction $txHash was not confirmed in time.');
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
      accountUuid: context.accountUuid,
      roundId: context.round.roundId,
      bundleIndex: bundleIndex,
      txHash: txHash,
      eventsJson: confirmation.eventsJson,
    );
    return (txHash: txHash, leafIndex: delegationConfirmation.vanLeafPosition);
  }

  Future<VotingTxConfirmation?> _awaitTxConfirmation(
    VotingApiClient api,
    String txHash, {
    required _VotingSessionContext context,
    bool spentNullifierRecovery = false,
  }) async {
    final settings = ref.read(votingTxConfirmationPollingProvider);
    final attempts =
        spentNullifierRecovery &&
            settings.attempts > _spentNullifierRecoveryMaxAttempts
        ? _spentNullifierRecoveryMaxAttempts
        : settings.attempts;
    final delay =
        spentNullifierRecovery &&
            settings.delay > _spentNullifierRecoveryMaxDelay
        ? _spentNullifierRecoveryMaxDelay
        : settings.delay;
    final timer = Stopwatch()..start();
    _logVoteTiming('tx confirmation wait start txHash=$txHash');
    for (var attempt = 0; attempt < attempts; attempt++) {
      _throwIfContextStale(context, 'tx-confirmation');
      final confirmation = await api.getTxConfirmation(txHash);
      _throwIfContextStale(context, 'tx-confirmation-response');
      if (confirmation != null) {
        _logVoteTiming(
          'tx confirmation found txHash=$txHash '
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
        _throwIfContextStale(context, 'tx-confirmation-delay');
      }
    }
    _logVoteTiming(
      'tx confirmation wait timed out txHash=$txHash '
      'elapsed=${formatElapsedSeconds(timer.elapsed)}',
    );
    return null;
  }

  Future<void> submitPendingShares() {
    if (_automaticShareTrackingStopped) return Future.value();
    final inFlight = _shareTrackingPass;
    if (inFlight != null) return inFlight;
    if (_ownsAutomaticShareTracking && !_retainAutomaticShareTracking()) {
      return Future.value();
    }

    late final Future<void> pass;
    pass = _startPendingSharePass().whenComplete(() {
      if (identical(_shareTrackingPass, pass)) _shareTrackingPass = null;
    });
    _shareTrackingPass = pass;
    return pass;
  }

  Future<void> _startPendingSharePass() {
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

      final api = ref.read(votingApiClientProvider(context.config.apiServers));
      final rust = ref.read(votingRustApiProvider);
      final helperHealth = ref.read(votingHelperHealthTrackerProvider);
      final configuredServerUrls = context.config.apiServers.all
          .map((endpoint) => endpoint.toString())
          .toList(growable: false);
      final configuredServerUrlSet = configuredServerUrls.toSet();
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final voteEnd = context.round.voteEndTime;
      final voteEndSeconds = voteEnd == null
          ? null
          : voteEnd.millisecondsSinceEpoch ~/ 1000;
      for (final share in plan.unconfirmedShareDelegations) {
        final acceptedUrls = LinkedHashSet<String>.of(
          share.sentToUrls.where(configuredServerUrlSet.contains),
        );
        final trackingFlags = await rust.shareTrackingFlags(
          share: share,
          nowSeconds: BigInt.from(nowSeconds),
          voteEndTimeSeconds: voteEndSeconds == null
              ? null
              : BigInt.from(voteEndSeconds),
        );
        if (_shareTrackingCancelled(context)) {
          _releaseAutomaticShareTrackingIfRoundExpired(context);
          return;
        }
        final readyForStatusCheck = (trackingFlags & 1) != 0;
        final overdueForRetry = (trackingFlags & 2) != 0;

        if (!readyForStatusCheck && !overdueForRetry) continue;

        if (acceptedUrls.isNotEmpty && readyForStatusCheck) {
          // Helpers can reveal at slightly different times. Confirmation by any
          // helper is enough to advance the local workflow for this share.
          final confirmed = await _shareConfirmedByAnyHelper(
            api: api,
            context: context,
            helperHealth: helperHealth,
            share: share,
            serverUrls: acceptedUrls,
          );
          if (confirmed) {
            await rust.markShareConfirmed(
              dbPath: context.dbPath,
              accountUuid: context.accountUuid,
              roundId: share.roundId,
              bundleIndex: share.bundleIndex,
              proposalId: share.proposalId,
              shareIndex: share.shareIndex,
            );
            continue;
          }
        }

        if (overdueForRetry) {
          final retryServer = await _resubmitShare(
            api: api,
            context: context,
            plan: plan,
            share: share,
            configuredServerUrls: configuredServerUrls,
            sentToUrls: acceptedUrls,
          );
          if (retryServer != null && acceptedUrls.add(retryServer)) {
            await ref
                .read(votingRecoveryServiceProvider)
                .addSentServersForShare(
                  dbPath: context.dbPath,
                  accountUuid: context.accountUuid,
                  share: share,
                  newUrls: [retryServer],
                );
          }
        }
      }

      if (_shareTrackingCancelled(context)) {
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
    final pass = _shareTrackingPass;
    try {
      if (pass != null) await pass;
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

  Future<String?> _resubmitShare({
    required VotingApiClient api,
    required _VotingSessionContext context,
    required VotingResumePlan plan,
    required rust_wire.ShareDelegationRecordView share,
    required List<String> configuredServerUrls,
    required Set<String> sentToUrls,
  }) async {
    if (!ref.mounted || !_isCurrentContext(context)) return null;
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
      return null;
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
      return null;
    }

    final retryOrder = await rust.shareResubmissionServerOrder(
      configuredServerUrls: configuredServerUrls,
      sentToUrls: sentToUrls.toList(growable: false),
    );
    final shareId = bytesToHex(share.nullifier);
    final helperHealth = ref.read(votingHelperHealthTrackerProvider);
    for (final serverUrl in retryOrder) {
      if (_automaticShareTrackingStopped ||
          !_isCurrentContext(context) ||
          ref.read(appSecurityProvider).requiresUnlock ||
          !shouldTrackPendingVotingShares(context.round)) {
        return null;
      }
      try {
        await api.resubmitShare(
          serverUrl: Uri.parse(serverUrl),
          shareId: shareId,
          share: body,
        );
        // Preserve a known acceptance even if a stop arrived during the POST;
        // forgetting it could resend the same share after unlock.
        helperHealth.recordSuccess(serverUrl);
        debugPrint(
          '[zcash] Voting: share resubmitted '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl',
        );
        return serverUrl;
      } catch (e) {
        debugPrint(
          '[zcash] Voting: share resubmit failed '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl error=$e',
        );
        // Overdue recovery deliberately favors liveness. An ambiguous error
        // may follow acceptance, but it may also mean the request never
        // arrived, so keep this helper eligible and continue until one
        // acknowledges or the round ends. This accepts possible duplicates.
        helperHealth.recordFailure(serverUrl);
      }
    }
    return null;
  }

  Future<void> _scheduleShareTracking(
    _VotingSessionContext context,
    VotingResumePlan plan,
  ) async {
    if (!_ownsAutomaticShareTracking) {
      _shareTrackingTimer?.cancel();
      _shareTrackingTimer = null;
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
      unawaited(_submitPendingSharesInBackground());
    });
  }

  Future<void> _submitPendingSharesInBackground() async {
    try {
      await submitPendingShares();
    } catch (_) {
      // The pass already logged the failure and scheduled its next retry.
    }
  }

  Future<bool> _shareConfirmedByAnyHelper({
    required VotingApiClient api,
    required _VotingSessionContext context,
    required VotingHelperHealthTracker helperHealth,
    required rust_wire.ShareDelegationRecordView share,
    required Iterable<String> serverUrls,
  }) async {
    final shareId = bytesToHex(share.nullifier);
    for (final serverUrl in helperHealth.candidateServers(serverUrls)) {
      if (_shareTrackingCancelled(context)) return false;
      try {
        final status = await api.getShareStatus(
          roundId: share.roundId,
          serverUrl: Uri.parse(serverUrl),
          shareId: shareId,
          isCancelled: () => _shareTrackingCancelled(context),
        );
        if (_automaticShareTrackingStopped || !_isCurrentContext(context)) {
          return false;
        }
        helperHealth.recordSuccess(serverUrl);
        if (status.status == 'confirmed') return true;
      } catch (e) {
        if (_shareTrackingCancelled(context)) return false;
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
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) async {
    final key = _delegationPirPrecomputeKey(context, bundleIndex);
    final timer = Stopwatch()..start();
    debugPrint(
      '[zcash] Voting: delegation PIR precompute start '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    try {
      final rust = ref.read(votingRustApiProvider);
      rust.warmVotingProvingCaches();
      final result = await rust.precomputeDelegationPir(
        ctx: _apiRoundContext(context),
        pirServerUrl: _transportUrl(pirEndpoint),
        storedHotkeySecret: storedHotkeySecret,
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
    return roundPlan.nextSteps.any((step) => step.kind == 'delegate') ||
        roundPlanNeedsDraftSetup(roundPlan);
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
    _VotingSessionContext context,
  ) async {
    var loggedWait = false;
    final maxWait = ref.read(votingWalletSyncMaxWaitProvider);
    final waitTimer = Stopwatch()..start();
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

  static Future<Map<String, dynamic>> _wireJsonMap(
    Future<String> wireJson,
  ) async {
    final decoded = jsonDecode(await wireJson);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Rust voting wire JSON is not an object.');
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

/// Stops queued broadcasts once a voting nullifier is already spent.
class _VotingAlreadyStarted implements Exception {
  const _VotingAlreadyStarted();

  @override
  String toString() => _votingAlreadyStartedMessage;
}

/// Requires a voting transaction to be accepted or already present on-chain.
///
/// A spent-nullifier rejection means voting has started, but it does not prove
/// which wallet submitted the accepted transaction. If the rejected response's
/// hash resolves to a successful transaction, normal recovery continues.
Future<void> _requireAcceptedVotingTransaction(
  VotingTxResult result, {
  required Future<VotingTxConfirmation?> Function(String txHash)
  waitForConfirmation,
  required String rejectionMessage,
}) async {
  if (result.code == 0) return;
  if (_nullifierAlreadySpentPattern.hasMatch(result.log) &&
      result.txHash.isNotEmpty) {
    final confirmation = await waitForConfirmation(result.txHash);
    if (confirmation?.code == 0) return;
    throw const _VotingAlreadyStarted();
  }
  throw StateError(result.log.isEmpty ? rejectionMessage : result.log);
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

class _PolledVoteRecovery {
  const _PolledVoteRecovery({
    required this.key,
    required this.txHash,
    required this.confirmation,
  });

  final VotingVoteKey key;
  final String txHash;
  final VotingTxConfirmation confirmation;
}

class _VoteConfirmationTimeout implements Exception {
  const _VoteConfirmationTimeout({required this.key, required this.txHash});

  final VotingVoteKey key;
  final String txHash;
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

class _PreparedInitialShareSubmission {
  const _PreparedInitialShareSubmission({
    required this.share,
    required this.body,
    required this.candidateServers,
    required this.targetCount,
    required this.submitAt,
  });

  final rust_wire.VoteShareWire share;
  final Map<String, dynamic> body;
  final List<String> candidateServers;
  final int targetCount;
  final BigInt submitAt;
}

class _InitialShareSubmissionResult {
  const _InitialShareSubmissionResult({
    required this.share,
    required this.submitAt,
    required this.acceptedServers,
  });

  final rust_wire.VoteShareWire share;
  final BigInt submitAt;
  final List<String> acceptedServers;
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
