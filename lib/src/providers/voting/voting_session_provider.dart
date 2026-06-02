import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatting/duration_format.dart';
import '../../core/formatting/hex_codec.dart';
import '../../features/voting/voting_error_messages.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_formatters.dart';
import '../../features/voting/voting_recovery_service.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../features/voting/voting_share_timing.dart';
import '../../rust/api/voting.dart' as rust_api;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_helper_health_tracker.dart';
import '../../services/voting/voting_models.dart';
import 'voting_debug_print.dart';
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
  final Map<String, Future<List<int>>> _hotkeyEnsures = {};
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
    );
  }

  VotingRustApi get _rustApi => ref.read(votingRustApiProvider);

  VotingApiClient _apiClientForConfig(rust_config.ResolvedVotingConfig config) {
    return ref.read(votingApiClientProvider(config.apiServers));
  }

  VotingApiClient _apiClientForContext(_VotingSessionContext context) {
    return _apiClientForConfig(context.config);
  }

  VotingRecoveryService get _recoveryService {
    return ref.read(votingRecoveryServiceProvider);
  }

  VotingHelperHealthTracker get _helperHealthTracker {
    return ref.read(votingHelperHealthTrackerProvider);
  }

  PirSnapshotResolver get _pirResolver {
    return ref.read(votingPirResolverProvider);
  }

  Future<String> _walletDbPath() {
    return ref.read(votingWalletDbPathProvider).call();
  }

  Future<String?> _activeAccountUuid() {
    return ref.read(votingActiveAccountUuidProvider).call();
  }

  Future<bool> _accountIsHardware(String accountUuid) {
    return ref.read(votingAccountIsHardwareProvider).call(accountUuid);
  }

  VotingTxConfirmationPolling get _txConfirmationPolling {
    return ref.read(votingTxConfirmationPollingProvider);
  }

  VotingWalletSyncReadinessChecker get _walletSyncReadinessChecker {
    return ref.read(votingWalletSyncReadinessCheckerProvider);
  }

  Duration get _walletSyncMaxWait {
    return ref.read(votingWalletSyncMaxWaitProvider);
  }

  Duration get _walletSyncPollInterval {
    return ref.read(votingWalletSyncPollIntervalProvider);
  }

  void _startWalletSync() {
    ref.read(votingWalletSyncStarterProvider).call();
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
    final rust = _rustApi;
    ref.onDispose(() {
      _disposeHandlerRegistered = false;
      _activeAccountListenerRegistered = false;
      _submissionGuardListenerRegistered = false;
      // Provider disposal is round-scoped: clear this round's process-local
      // vote-tree sync cache while leaving other rounds untouched.
      final context = _currentContext;
      _isDisposed = true;
      _advanceSessionGeneration();
      _delegationPirPrecomputes.clear();
      _hotkeyEnsures.clear();
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
            rust: _rustApi,
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

  Future<void> ensureWalletReadyForVoting() {
    return _enqueue(() async {
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);
    });
  }

  Future<void> precomputeDelegationPir({required String accountUuid}) async {
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

    final rust = _rustApi;
    final bundleSetup = await rust.setupDelegationBundles(
      ctx: _apiRoundContext(context),
    );
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final plan = await _loadResumePlan(context);
    if (!_isCurrentPrecomputeContext(context, accountUuid)) return;
    final pendingBundles = plan.pendingDelegationBundleIndexes.isNotEmpty
        ? plan.pendingDelegationBundleIndexes
        : [for (var i = 0; i < bundleSetup.bundleCount; i++) i];

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
      if (_needsDelegationPreparation(current)) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
      }

      final context = await _loadContext(_roundId);
      if (context.isHardwareAccount) {
        _setError(
          'Sign delegation bundles with Keystone before submitting.',
          context: context,
        );
        return;
      }
      final plan = current.resumePlan ?? context.resumePlan;
      final roundPlan = current.roundPlan ?? context.roundPlan;
      final pirEndpoint = current.pirEndpoint;
      if (pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.', context: context);
        return;
      }
      if (plan.pendingDelegationBundleIndexes.isNotEmpty) {
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
          currentBundleIndex: plan.pendingDelegationBundleIndexes.first,
          clearError: true,
        );
        _setStateForContext(context, nextState);
        current = nextState;
      }
      final storedHotkeySecret = await _ensureHotkey(context);

      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final rust = _rustApi;
      final completedBundleIndexes = await _confirmSubmittedDelegations(
        context: context,
        plan: plan,
        roundPlan: roundPlan,
        progress: progress,
      );
      if (completedBundleIndexes == null) return;
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
              ctx: _apiRoundContext(context),
              pirServerUrl: pirEndpoint.toString(),
              mnemonic: mnemonic!,
              storedHotkeySecret: storedHotkeySecret,
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
        _throwIfContextStale(context, 'delegation-submit');
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
      final rust = _rustApi;
      final signatures = Map<int, rust_wire.KeystoneSignatureRecord>.from(
        current.keystoneSignatures,
      );
      if (signatures.isEmpty) {
        signatures.addAll(await _loadKeystoneSignatures(context));
      }

      final parsedPczt = await rust.parseSignedVotingPczt(
        signedPcztBytes: signedPcztBytes,
        actionIndex: request.actionIndex,
      );
      final scannedSighash = parsedPczt.sighash;
      final duplicate = signatures.values.any(
        (record) => _bytesEqual(record.sighash, scannedSighash),
      );
      if (duplicate) {
        _setStateForContext(
          context,
          current.copyWith(
            phase: VotingSessionPhase.keystoneSigning,
            keystoneSignatures: signatures,
            keystoneScanError:
                'This Keystone signature was already scanned. Open the next signature on Keystone and scan again.',
          ),
        );
        return;
      }
      if (!_bytesEqual(request.pcztSighash, scannedSighash)) {
        _setStateForContext(
          context,
          current.copyWith(
            phase: VotingSessionPhase.keystoneSigning,
            keystoneSignatures: signatures,
            keystoneScanError:
                'This signature is for a different voting bundle. Scan the signature for bundle ${request.bundleIndex + 1}.',
          ),
        );
        return;
      }

      await rust.storeKeystoneSignature(
        dbPath: context.dbPath,
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: request.bundleIndex,
        sig: parsedPczt.spendAuthSig,
        sighash: scannedSighash,
        rk: request.rk,
      );
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
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
            keepCount: signedPrefixCount,
          );
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
      if (_needsDelegationPreparation(current)) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
      }

      final context = await _loadContext(_roundId);
      if (!context.isHardwareAccount) {
        _setError(
          'Keystone voting is only available for hardware accounts.',
          context: context,
        );
        return;
      }
      final plan = current.resumePlan ?? context.resumePlan;
      final roundPlan = current.roundPlan ?? context.roundPlan;
      final pirEndpoint = current.pirEndpoint;
      if (pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.', context: context);
        return;
      }

      final signatures = await _loadKeystoneSignatures(context);
      final storedHotkeySecret = await _ensureHotkey(
        context,
        alreadyBound: signatures.isNotEmpty,
      );
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

      final rust = _rustApi;
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
                  ctx: _apiRoundContext(context),
                  pirServerUrl: pirEndpoint.toString(),
                  storedHotkeySecret: storedHotkeySecret,
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
        _throwIfContextStale(context, 'keystone-delegation-submit');
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
    });
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
      final storedHotkeySecret = await _hotkeyForVoteCasting(context);
      if (storedHotkeySecret == null) {
        _setError(
          'Voting hotkey is missing. Delegate this round before casting votes.',
          cause: const VotingHotkeyUnavailable('missing stored hotkey'),
          context: context,
        );
        return;
      }

      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      var plan = context.resumePlan;
      var roundPlan = context.roundPlan;
      final api = _apiClientForContext(context);
      final rust = _rustApi;
      final effectiveDraftVotes = VotingShareTimingPolicy.applyLastMomentMode(
        draftVotes,
        context.round,
      );
      if (effectiveDraftVotes.isNotEmpty) {
        // Write durable ballot intent before the cast loop so recovery can
        // resume from the correct choice if the user quits mid-vote.
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
                skipped: draftVote == null,
                choice: draftVote?.choice,
              );
        }
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
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          txHash: txHash,
          eventsJson: confirmation.eventsJson,
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
          final anchorHeight = await _syncVoteTreeWithFailover(
            context: context,
            bundleIndex: bundleIndex,
            proposalId: draftVote.proposalId,
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
                accountUuid: context.accountUuid,
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
                    accountUuid: context.accountUuid,
                    network: context.network,
                    roundId: context.round.roundId,
                    bundleIndex: bundleIndex,
                    storedHotkeySecret: storedHotkeySecret,
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
              _throwIfContextStale(context, 'vote-commitment-submit');
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
      final refreshedPlan = await _loadResumePlan(context);
      final refreshedRoundPlan = await _loadRoundPlan(context);
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

    final rust = _rustApi;
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
    Map<int, BigInt> vcTreePositions = const {},
    Set<int>? shareIndexFilter,
    required bool singleShare,
    required int completedQuestions,
    required int totalQuestions,
    required double? voteSubmissionProgress,
  }) async {
    final api = _apiClientForContext(context);
    final rust = _rustApi;
    final helperHealth = _helperHealthTracker;
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
          accountUuid: context.accountUuid,
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
    final api = _apiClientForContext(context);
    final rust = _rustApi;
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
        accountUuid: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
      );

      final confirmation = await _awaitTxConfirmation(api, result.txHash);
      if (confirmation == null) {
        throw _VotingTxConfirmationTimeout(
          'Vote commitment transaction ${result.txHash} for bundle '
          '${commitments.bundleIndex}, proposal ${commitment.proposalId} '
          'was submitted but not confirmed in time. Retry to resume '
          'confirmation before continuing.',
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
    final api = _apiClientForContext(context);
    final rust = _rustApi;
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

  Future<({String txHash, int leafIndex})> _submitAndConfirmDelegation({
    required _VotingSessionContext context,
    required int bundleIndex,
    required rust_wire.SignedDelegationPayloadView submission,
  }) async {
    final api = _apiClientForContext(context);
    final rust = _rustApi;
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

    final confirmation = await _awaitTxConfirmation(api, result.txHash);
    if (confirmation == null) {
      throw _VotingTxConfirmationTimeout(
        'Delegation transaction ${result.txHash} for bundle $bundleIndex was '
        'submitted but not confirmed in time. Retry to resume confirmation '
        'before continuing.',
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
      accountUuid: context.accountUuid,
      roundId: context.round.roundId,
      bundleIndex: bundleIndex,
      txHash: result.txHash,
      eventsJson: confirmation.eventsJson,
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
    final polling = _txConfirmationPolling;
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
      final plan = await _loadResumePlan(context);
      final roundPlan = await _loadRoundPlan(context);
      _setStateForContext(
        context,
        current.copyWith(
          phase: VotingSessionPhase.submittingShares,
          resumePlan: plan,
          roundPlan: roundPlan,
        ),
      );

      final api = _apiClientForContext(context);
      final rust = _rustApi;
      final helperHealth = _helperHealthTracker;
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
              accountUuid: context.accountUuid,
              roundId: share.roundId,
              bundleIndex: share.bundleIndex,
              proposalId: share.proposalId,
              shareIndex: share.shareIndex,
            );
            continue;
          }
        }

        final missingUrls = configuredServerUrls
            .where((serverUrl) => !acceptedUrls.contains(serverUrl))
            .toList(growable: false);
        if (overdueForRetry && missingUrls.isNotEmpty) {
          final newUrls = await _resubmitShareToMissingHelpers(
            api: api,
            context: context,
            plan: plan,
            share: share,
            serverUrls: missingUrls,
          );
          if (newUrls.isNotEmpty) {
            await ref
                .read(votingRecoveryServiceProvider)
                .addSentServersForShare(
                  dbPath: context.dbPath,
                  accountUuid: context.accountUuid,
                  share: share,
                  newUrls: newUrls,
                );
            acceptedUrls.addAll(newUrls);
          }
        }
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

  /// Retries an already-generated share against helpers missing from
  /// `sent_to_urls` and returns only the helpers that accepted the retry.
  Future<List<String>> _resubmitShareToMissingHelpers({
    required VotingApiClient api,
    required _VotingSessionContext context,
    required VotingResumePlan plan,
    required rust_wire.ShareDelegationRecordView share,
    required List<String> serverUrls,
  }) async {
    final rust = _rustApi;
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
    final helperHealth = _helperHealthTracker;
    for (final serverUrl in helperHealth.candidateServers(serverUrls)) {
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
      final result = await ref
          .read(votingRustApiProvider)
          .precomputeDelegationPir(
            ctx: _apiRoundContext(context),
            pirServerUrl: pirEndpoint.toString(),
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
        if (_shouldResetSessionStateOnActionError(e)) {
          await _cleanupCurrentSessionState(reason: 'action-failed');
        } else {
          debugPrint(
            '[zcash] Voting: process-local cleanup skipped '
            'round=$_roundId reason=transient-action-failure error=$e',
          );
        }
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

  static bool _shouldResetSessionStateOnActionError(Object error) {
    if (error is _VotingRecoverableActionException) return false;
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException) {
      return false;
    }
    if (error is VotingHttpException) {
      return !_isTransientVotingHttpStatus(error.statusCode);
    }
    return true;
  }

  static bool _isTransientVotingHttpStatus(int statusCode) {
    switch (statusCode) {
      case 408:
      case 425:
      case 429:
      case 500:
      case 502:
      case 503:
      case 504:
        return true;
      default:
        return false;
    }
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
        (signatures.isNotEmpty || (roundPlan?.hotkeyBound ?? false))) {
      throw const VotingHotkeyUnavailable('missing stored voting hotkey');
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
        currentBundleIndex: nextUnsignedBundle,
        clearKeystoneSigningRequest: true,
        clearKeystoneScanError: true,
        clearError: true,
      ),
    );

    final request = await ref
        .read(votingRustApiProvider)
        .buildKeystoneDelegationRequest(
          ctx: _apiRoundContext(context),
          storedHotkeySecret: storedHotkeySecret,
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

    final resolver = _pirResolver;
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
    config.assertRoundAuthenticated(roundId);
    final api = _apiClientForConfig(config);
    final round = VotingRoundDetails.fromStatus(
      await api.getRoundStatus(roundId),
    );
    final roundParams = await _rustApi.trustedVotingRoundParamsFromConfig(
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
    final dbPath = await _walletDbPath();
    checkAction();
    final resumePlan = await _recoveryService.loadResumePlan(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: round.roundId,
    );
    // Build a temporary context without roundPlan to derive proposalIds.
    final proposals = proposalsFromRound(round);
    final proposalIds = proposals.map((p) => p.id).toList();
    final roundPlan = await _recoveryService.loadRoundPlan(
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

    final accountUuid = await _activeAccountUuid();
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
    final isHardware = await _accountIsHardware(accountUuid);
    _sessionIsHardwareAccount = isHardware;
    return isHardware;
  }

  Future<VotingResumePlan> _loadResumePlan(_VotingSessionContext context) {
    return _recoveryService.loadResumePlan(
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
    return _recoveryService.loadRoundPlan(
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
    final sessionInvalidated = _sessionInvalidated.future;
    final maxWait = _walletSyncMaxWait;
    final waitStartedAt = DateTime.now();
    while (true) {
      _throwIfContextStale(context, 'wallet-sync-wait');
      final readiness = await _walletSyncReadinessChecker.check(
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
      final elapsed = DateTime.now().difference(waitStartedAt);
      if (elapsed >= maxWait) {
        throw _VotingWalletSyncWaitTimeout(
          roundId: context.round.roundId,
          scannedHeight: readiness.scannedHeight,
          snapshotHeight: readiness.snapshotHeight,
          waited: elapsed,
        );
      }
      _throwIfContextStale(context, 'wallet-sync-start');
      try {
        _startWalletSync();
      } catch (e) {
        debugPrint('[zcash] Voting: wallet sync start skipped: $e');
      }
      await Future.any<void>([
        Future<void>.delayed(_walletSyncPollInterval),
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
        rust: _rustApi,
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

  /// Clear this round's process-local vote-tree sync cache in Rust.
  ///
  /// Passing the round ID performs round-scoped cleanup and leaves other rounds
  /// under the same account intact. This reset does not abort in-flight proof
  /// or vote jobs.
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
    final draft = await notifier.ensureLoaded();
    for (final proposalId in draft.choices.keys.toList(growable: false)) {
      notifier.clearChoice(proposalId);
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
        !_bytesEqual(_decodeBase64(wire.spendAuthSig), signature.sig) ||
        !_bytesEqual(_decodeBase64(wire.sighash), signature.sighash)) {
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

abstract class _VotingRecoverableActionException implements Exception {
  const _VotingRecoverableActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _VotingTxConfirmationTimeout extends _VotingRecoverableActionException {
  const _VotingTxConfirmationTimeout(super.message);
}

class _VotingWalletSyncWaitTimeout extends _VotingRecoverableActionException {
  _VotingWalletSyncWaitTimeout({
    required String roundId,
    required int scannedHeight,
    required int snapshotHeight,
    required Duration waited,
  }) : super(
         'Wallet sync has not reached the voting snapshot yet '
         '(round=$roundId scanned=${formatBlockHeight(scannedHeight)} '
         'snapshot=${formatBlockHeight(snapshotHeight)} '
         'waited=${formatElapsedSeconds(waited)}). Keep syncing and retry.',
       );
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
    AsyncNotifierProvider.autoDispose.family<
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
