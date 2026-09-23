import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;

import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/services/voting/voting_rust_exception.dart';
import 'fake_rust_api_shapes.dart' as rust_api;
import 'package:zcash_wallet/src/rust/api/voting_session.dart' as rust_session;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/delegate.dart'
    as rust_delegate;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/vote.dart'
    as rust_vote;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import 'round_plan_test_utils.dart';

/// State a scripted `VotingRustApi` fake exposes so [FakeVotingRoundSession]
/// can mirror the SDK executor on top of it.
/// Cancellable handle for one scripted chain episode.
abstract interface class FakeChainSubmissionPassHandle {
  String get accountUuid;

  String get roundId;

  bool get isCancelled;

  bool get isDisposed;

  void cancel();

  void dispose();

  void setOperationEpoch(BigInt operationEpoch);
}

/// The per-step operations a scripted fake still exposes so
/// [FakeVotingRoundSession] can mirror the SDK executor. Production Dart no
/// longer sees these; the SDK runs them inside a round session step.
/// The account-and-round scope a session keeps for helper work.
///
/// Production has no separate type for this any more — one session owns the
/// scope, its helper health, and its sidecar handle. The fake keeps it as a
/// value so its step decomposition can pass it around the way the SDK passes
/// its own state internally.
class FakeHelperDeliveryScope {
  const FakeHelperDeliveryScope({
    required this.dbPath,
    required this.accountUuid,
    required this.roundId,
  });

  final String dbPath;
  final String accountUuid;
  final String roundId;
}

abstract interface class FakeRoundStepApi {
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required String mnemonic,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  });

  Stream<rust_api.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
  });

  FakeChainSubmissionPassHandle beginChainSubmissionPass({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String network,
    required List<String> endpoints,
    required BigInt operationEpoch,
  });

  Future<rust_api.ApiChainSubmissionCallResult> advanceChainDelegation({
    required FakeChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required rust_wire.SignedDelegationPayloadView submission,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  });

  Future<rust_api.ApiChainSubmissionCallResult> advanceChainVote({
    required FakeChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  });

  Future<rust_api.ApiChainSubmissionCallResult> advanceChainVoteBatch({
    required FakeChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  });

  Future<rust_vote.VanWitness> generateVanWitness({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  });

  Stream<rust_api.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> storedHotkeySecret,
    required rust_vote.VanWitness vanWitness,
    required List<VotingDraftVote> draftVotes,
    required bool singleShare,
    required int maxProofConcurrency,
  });

  Future<rust_api.ApiSignedVoteCommitments> recoverVoteCommitment({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
  });

  Future<rust_api.ApiVotingHelperPreflight> preflightVotingHelpers({
    required FakeHelperDeliveryScope scope,
    required List<String> configuredHelperUrls,
  });

  Future<void> prepareCommittedShareDelivery({
    required FakeHelperDeliveryScope scope,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiVotingHelperPreflight preflight,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    required List<int> proposalIds,
    BigInt? lastMomentBufferSeconds,
  });

  Future<rust_api.ApiShareBatchDeliveryReport> submitPreparedSharesToHelpers({
    required FakeHelperDeliveryScope scope,
    required int bundleIndex,
    required int proposalId,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
  });

  /// One confirm-or-retry pass over the round's unconfirmed shares.
  ///
  /// The SDK's tracking driver calls this repeatedly; the fake session drives
  /// the same loop so tests exercise the pass behaviour they always did.
  Future<rust_wire.ShareTrackingPassReportView> trackPendingSharesPass({
    required FakeHelperDeliveryScope scope,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
    required bool Function() isCancelled,
  });

  /// Quorum confirmation for exactly one share, without walking the round.
  Future<bool> confirmOneShareWithHelpers({
    required FakeHelperDeliveryScope scope,
    required List<String> configuredHelperUrls,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required BigInt nowSeconds,
    required bool Function() isCancelled,
  });
}

abstract interface class FakeRoundSessionDriver {
  VotingRustApi get api;

  FakeRoundStepApi get stepApi;

  /// Bundle count the planner sees, from recovery state when present.
  int get planBundleCount;

  /// Bundles whose delegation is already durable, so a synthesised plan does
  /// not ask for one again. Mirrors the SDK, whose planner reads the bundle's
  /// delegation phase rather than guessing from the steps it lists.
  Set<int> get confirmedDelegationBundles;

  Map<int, rust_wire.KeystoneSignatureRecord> get storedKeystoneSignatures;

  /// Proposal ids proven together per bundle, recorded by the fake's
  /// `buildVoteCommitmentsWithProgress`.
  Map<int, List<int>> get batchProposalIdsByBundle;

  /// `bundle:proposal` keys proven in-process.
  Set<String> get provenVoteKeys;

  /// `bundle:proposal` keys whose shares were delivered.
  Set<String> get handledVoteKeys;

  /// `bundle:proposal` keys whose recovery state shows a vote past the
  /// prepared phase or already on the wire, so the session never re-casts
  /// them.
  Set<String> get recordedVoteKeys;

  /// The recovery plan the host most recently loaded, without consuming a
  /// scripted plan sequence.
  Future<rust_wire.RoundPlanView?> peekRoundPlan({
    required String roundId,
    required List<int> proposalIds,
  });

  /// Loads a fresh recovery plan the way the SDK re-plans after ballot
  /// intents are written; this consumes one scripted plan.
  Future<rust_wire.RoundPlanView?> loadRoundPlan({
    required String roundId,
    required List<int> proposalIds,
  });

  /// Bridge failures to raise before a step reaches the SDK, keyed
  /// `'<stepKind>:<bundleIndex>'` and consumed on first use.
  ///
  /// These are delivered as the step's result event, not thrown into the
  /// stream, because that is the only channel production has: the bridge
  /// drops a streaming function's `Result`, so `advance_*` reports every
  /// failure — including one raised before the step runs — as an event.
  Map<String, VotingRustException> get roundStepBridgeErrors;

  /// Event sequences to emit from `runRound`, one per call, instead of
  /// driving the scripted plan.
  ///
  /// The SDK owns the loop now, and its conformance tests own whether a given
  /// sequence is realistic. A provider test that cares how Dart maps events
  /// onto session state scripts the sequence here and asserts the state,
  /// rather than making this fake re-derive a plan the real planner owns.
  List<List<rust_session.ApiRoundRunEvent>> get scriptedRoundRuns;

  /// Called when a session carrying helper work is cancelled.
  ///
  /// Mirrors the SDK observing cancellation inside its work, not only between
  /// passes: gated fake helper work — a tracking pass or a focused
  /// confirmation — must unblock rather than hold a drain open.
  void onShareTrackingCancelled();

  /// Sessions on which a focused immediate-share confirmation was run.
  ///
  /// The focused check runs on its own short-lived session, so this is how a
  /// test sees the destructive drain cancel it.
  List<FakeVotingRoundSession> get focusedConfirmationSessions;

  /// The policy each tracking run was started with, in order.
  ///
  /// Pacing is the SDK's, but which pacing this app asks for is its own
  /// decision and a silent one to get wrong: a wrong cap costs empty passes
  /// rather than an error.
  List<rust_session.ApiShareTrackingDrivePolicy?> get shareTrackingPolicies;

  /// Sessions on which a tracking run was started, in order.
  ///
  /// Background tracking runs on its own session, so this is what a test
  /// watches to see the run started, cancelled, and closed.
  List<FakeVotingRoundSession> get shareTrackingSessions;

  /// Verbatim event sequences for `runShareTracking`, one per run.
  ///
  /// Scripting a run says what the SDK's tracking driver did without this fake
  /// re-deriving a cadence the driver owns.
  List<List<rust_session.ApiShareTrackingRunEvent>>
  get scriptedShareTrackingRuns;

  List<String> get roundSessionSteps;

  List<String> get sessionBallotIntents;

  /// Failure the session raises from `setBallotIntents`, if any.
  ///
  /// The SDK write is the ballot's durable write, so this is the seam for
  /// proving a failed intent write aborts before any vote work runs.
  Object? get sessionBallotIntentsError => null;

  /// Proposal ids the session was asked to clear as unrostered intents.
  List<int> get sessionClearedBallotIntents;
}

/// One event from the fake's scripted step machinery.
///
/// The bridge no longer exposes a per-step stream: production drives a round
/// with `runRound`. This keeps the same shape internally so the scripted
/// scenarios below still read as "what one step did", without holding a
/// retired API alive.
class _ScriptedStepEvent {
  const _ScriptedStepEvent({
    required this.kind,
    this.progress,
    this.outcome,
    this.failure,
    this.error,
  });

  final rust_session.ApiRoundStepEventKind kind;
  final rust_wire.RoundStepProgressView? progress;
  final _ScriptedStepOutcome? outcome;
  final rust_wire.RoundStepFailureView? failure;
  final rust_session.ApiRoundStepError? error;
}

/// What one scripted step accomplished.
class _ScriptedStepOutcome {
  const _ScriptedStepOutcome({
    required this.disposition,
    required this.plan,
    this.chainOutcome,
    this.shareDeliveries = const [],
    this.delegation,
  });

  final rust_wire.RoundStepDispositionView disposition;
  final rust_wire.RoundPlanView plan;
  final rust_wire.ChainSubmissionOutcomeView? chainOutcome;
  final List<rust_wire.ShareBatchDeliveryReportView> shareDeliveries;
  final rust_wire.SignedDelegationPayloadView? delegation;
}

/// Test double for the SDK round session.
///
/// Mirrors the executor's step semantics on top of the scripted fake API:
/// a `castVote` step proves the bundle's pending intents, plans helper
/// delivery, runs one chain episode, and delivers shares; `advanceVote*` and
/// `submitShares` resume that pipeline for persisted work; delegation steps
/// prove, sign, and run one chain episode. Every outcome carries the plan
/// with the completed work removed, the way the SDK re-plans after a step.
class FakeVotingRoundSession implements VotingRoundSession {
  FakeVotingRoundSession({
    required this.driver,
    required this.ctx,
    required this.binding,
    required this.storedHotkeySecret,
    required this.operationEpoch,
  });

  final FakeRoundSessionDriver driver;
  final rust_api.ApiVotingRoundContext ctx;

  /// The endpoints, roster and timing this session is bound to for its life.
  final rust_session.ApiRoundSessionBinding binding;
  final List<int>? storedHotkeySecret;
  BigInt operationEpoch;
  final Map<int, rust_session.ApiBallotIntent> _intents = {};
  final Set<int> _clearedUnrosteredIntents = {};
  final Set<String> _recoveredKeys = {};
  final Set<FakeChainSubmissionPassHandle> _passHandles = {};
  final Completer<void> _cancelled = Completer<void>();
  bool isCancelled = false;
  @override
  bool isDisposed = false;

  VotingRustApi get _api => driver.api;

  /// The clock the bridge stamps per dispatch. Production reads it inside
  /// Rust; the fake reads the same wall clock so timing-sensitive steps see a
  /// consistent value.
  BigInt get _fakeNowSeconds =>
      BigInt.from(DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);

  FakeRoundStepApi get _steps => driver.stepApi;

  @override
  String get accountUuid => ctx.accountUuid;

  @override
  String get roundId => ctx.roundParams.voteRoundId;

  List<String> get chainEndpoints => binding.chainEndpoints;

  List<String> get pirServerUrls => binding.pirServerUrls;

  List<rust_session.ApiProposalRosterEntry> get proposals => binding.proposals;

  List<int> get _rosterIds => [
    for (final proposal in proposals) proposal.proposalId,
  ];

  @override
  void setOperationEpoch(BigInt operationEpoch) {
    this.operationEpoch = operationEpoch;
    for (final handle in _passHandles) {
      handle.setOperationEpoch(operationEpoch);
    }
  }

  @override
  void cancel() {
    isCancelled = true;
    for (final handle in _passHandles) {
      handle.cancel();
    }
    driver.onShareTrackingCancelled();
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  void dispose() => isDisposed = true;

  @override
  Future<rust_wire.RoundPlanView> plan() => _plan();

  @override
  Future<rust_wire.RoundPlanView> clearBallotIntents(
    List<int> proposalIds,
  ) async {
    _clearedUnrosteredIntents.addAll(proposalIds);
    for (final proposalId in proposalIds) {
      _intents.remove(proposalId);
    }
    driver.sessionClearedBallotIntents.addAll(proposalIds);
    return _plan();
  }

  @override
  Future<rust_wire.RoundPlanView> setBallotIntents(
    List<rust_session.ApiBallotIntent> intents,
  ) async {
    final error = driver.sessionBallotIntentsError;
    if (error != null) throw error;
    for (final intent in intents) {
      _intents[intent.proposalId] = intent;
    }
    driver.sessionBallotIntents.addAll(
      intents.map(
        (intent) =>
            '${intent.proposalId}:${intent.skipped}:${intent.choice ?? 'null'}',
      ),
    );
    await driver.loadRoundPlan(roundId: roundId, proposalIds: _rosterIds);
    return _plan();
  }

  bool _proven(String key) =>
      driver.provenVoteKeys.contains(key) || _recoveredKeys.contains(key);

  bool _isBatch(int bundleIndex) =>
      (driver.batchProposalIdsByBundle[bundleIndex]?.length ?? 1) > 1;

  static bool _isVoteStep(rust_wire.NextStepView step) => switch (step.kind) {
    rust_wire.NextStepKind.castVote ||
    rust_wire.NextStepKind.advanceVote ||
    rust_wire.NextStepKind.advanceVoteBatch ||
    rust_wire.NextStepKind.submitShares => true,
    _ => false,
  };

  Future<rust_wire.RoundPlanView> _plan({
    bool synthesizeDelegation = false,
  }) async {
    final base = await driver.peekRoundPlan(
      roundId: roundId,
      proposalIds: _rosterIds,
    );
    final steps = <rust_wire.NextStepView>[];
    final seen = <String>{};
    if (base != null && synthesizeDelegation) {
      // The scripted plan may list no delegation step while its own statuses
      // still say a bundle owes one. The SDK planner keeps those in agreement,
      // and the driver runs only what the plan lists, so honour the statuses.
      final covered = {
        for (final step in base.nextSteps)
          if (_isDelegationStep(step)) step.bundleIndex,
      };
      for (final status in base.delegationStatuses) {
        if (covered.contains(status.bundleIndex) ||
            _delegatedBundles.contains(status.bundleIndex) ||
            _terminalDelegationBundles.contains(status.bundleIndex) ||
            status.terminal ||
            status.phase == rust_wire.WorkflowPhaseView.confirmed) {
          continue;
        }
        steps.add(
          rust_wire.NextStepView(
            kind: rust_wire.NextStepKind.delegate,
            bundleIndex: status.bundleIndex,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
        );
      }
    }
    if (base == null && synthesizeDelegation) {
      // No scripted recovery state, and this run holds signing material, so
      // it is a delegation run against a fresh round: every bundle still owes
      // a delegation. The SDK's plan always knows its own bundles, and the
      // driver runs only what the plan lists, so a fake that listed nothing
      // would make delegation unrunnable rather than pending. A cast run
      // carries no signer and assumes delegation is already durable, which is
      // what these fixtures script.
      for (
        var bundleIndex = 0;
        bundleIndex < driver.planBundleCount;
        bundleIndex++
      ) {
        if (_delegatedBundles.contains(bundleIndex) ||
            _terminalDelegationBundles.contains(bundleIndex) ||
            driver.confirmedDelegationBundles.contains(bundleIndex)) {
          continue;
        }
        steps.add(
          rust_wire.NextStepView(
            kind: rust_wire.NextStepKind.delegate,
            bundleIndex: bundleIndex,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
        );
      }
    }
    for (final step in base?.nextSteps ?? const <rust_wire.NextStepView>[]) {
      if (!_isVoteStep(step)) {
        // A delegation this session already advanced leaves the plan, the way
        // the SDK re-plans with completed work removed. Keeping it would make
        // the plan never shrink, and the driver re-plans until it does.
        if (_isDelegationStep(step) &&
            (_delegatedBundles.contains(step.bundleIndex) ||
                _terminalDelegationBundles.contains(step.bundleIndex))) {
          continue;
        }
        steps.add(step);
        continue;
      }
      final key = '${step.bundleIndex}:${step.proposalId}';
      if (driver.handledVoteKeys.contains(key) || !seen.add(key)) continue;
      if (step.kind == rust_wire.NextStepKind.castVote && _proven(key)) {
        steps.add(
          rust_wire.NextStepView(
            kind: _isBatch(step.bundleIndex)
                ? rust_wire.NextStepKind.advanceVoteBatch
                : rust_wire.NextStepKind.advanceVote,
            bundleIndex: step.bundleIndex,
            proposalId: step.proposalId,
            choice: 0,
            shareIndex: 0,
          ),
        );
        continue;
      }
      steps.add(step);
    }
    // Intents the base plan does not mention become cast steps, the way the
    // SDK planner derives `CastVote` from durable ballot intent.
    for (
      var bundleIndex = 0;
      bundleIndex < driver.planBundleCount;
      bundleIndex++
    ) {
      for (final intent in _intents.values) {
        if (intent.skipped) continue;
        final key = '$bundleIndex:${intent.proposalId}';
        if (driver.handledVoteKeys.contains(key) ||
            driver.recordedVoteKeys.contains(key) ||
            !seen.add(key)) {
          continue;
        }
        final proven = _proven(key);
        steps.add(
          rust_wire.NextStepView(
            kind: proven
                ? (_isBatch(bundleIndex)
                      ? rust_wire.NextStepKind.advanceVoteBatch
                      : rust_wire.NextStepKind.advanceVote)
                : rust_wire.NextStepKind.castVote,
            bundleIndex: bundleIndex,
            proposalId: intent.proposalId,
            choice: proven ? 0 : intent.choice ?? 0,
            shareIndex: 0,
          ),
        );
      }
    }
    return apiRoundPlan(
      roundId: roundId,
      pendingRecovery: steps.isNotEmpty,
      nextSteps: steps,
      openProposals: base?.openProposals ?? Uint32List.fromList(_rosterIds),
      unrosteredIntents: Uint32List.fromList([
        for (final proposalId in base?.unrosteredIntents ?? const <int>[])
          if (!_clearedUnrosteredIntents.contains(proposalId)) proposalId,
      ]),
      allDecided: base?.allDecided ?? false,
      hotkeyBound: base?.hotkeyBound ?? false,
      completedVoteArtifact: base?.completedVoteArtifact ?? false,
      needsDraftSetup: base?.needsDraftSetup,
      delegationStatuses: _withTerminalDelegations(
        base?.delegationStatuses ?? const [],
      ),
      immediateShareKey: base?.immediateShareKey,
      immediateShareConfirmed: base?.immediateShareConfirmed ?? false,
    );
  }

  /// The round's delegation statuses with this session's terminal submissions
  /// folded in.
  ///
  /// The SDK reports a terminal submission on the bundle's own status, and that
  /// flag is the only account of it the host gets: a terminal bundle plans no
  /// work, so nothing downstream would ever raise it.
  List<rust_wire.DelegationStatusView> _withTerminalDelegations(
    List<rust_wire.DelegationStatusView> statuses,
  ) {
    if (_terminalDelegationBundles.isEmpty) return statuses;
    final byBundle = {
      for (final status in statuses) status.bundleIndex: status,
    };
    for (final bundleIndex in _terminalDelegationBundles) {
      final diagnostic = _terminalDelegationDiagnostics[bundleIndex];
      byBundle[bundleIndex] = rust_wire.DelegationStatusView(
        bundleIndex: bundleIndex,
        phase: rust_wire.WorkflowPhaseView.submissionRejected,
        terminal: true,
        submissionDiagnostic: diagnostic == null
            ? null
            : rust_wire.SubmissionDiagnosticView(
                kind: diagnostic.kind.name,
                message: diagnostic.message,
              ),
      );
    }
    return (byBundle.values.toList(growable: false)
      ..sort((a, b) => a.bundleIndex.compareTo(b.bundleIndex)));
  }

  /// Runs one scripted step. Private: production drives rounds through
  /// `runRound`, and the bridge no longer exposes a per-step entry point.
  Stream<_ScriptedStepEvent> _advanceScriptedStep({
    required rust_wire.NextStepView step,
    rust_session.ApiDelegationSignerInput? signer,
  }) async* {
    final stepKey = '${step.kind.name}:${step.bundleIndex}';
    driver.roundSessionSteps.add(stepKey);
    final bridgeError = driver.roundStepBridgeErrors.remove(stepKey);
    if (bridgeError != null) {
      yield _bridgeError(bridgeError);
      return;
    }
    final Stream<_ScriptedStepEvent> work;
    switch (step.kind) {
      case rust_wire.NextStepKind.delegate:
      case rust_wire.NextStepKind.advanceDelegation:
        work = _advanceDelegation(step, signer);
      case rust_wire.NextStepKind.castVote:
      case rust_wire.NextStepKind.advanceVote:
      case rust_wire.NextStepKind.advanceVoteBatch:
      case rust_wire.NextStepKind.submitShares:
        work = _advanceVote(step);
      case rust_wire.NextStepKind.advanceImportedDelegation:
      case rust_wire.NextStepKind.confirmShare:
        work = Stream.fromFuture(
          _result(step, rust_wire.RoundStepDispositionView.noWork),
        );
    }
    try {
      // Consumed with `await for` rather than `yield*` on purpose: `yield*`
      // forwards a delegated stream's error straight to our own listener, so
      // it would bypass these handlers and end the whole run. `await for`
      // raises it here, which is what lets one step's failure be isolated the
      // way `RoundExecutor::advance_step` isolates it.
      await for (final event in work) {
        yield event;
      }
    } on _FakeChainSubmissionFailure catch (failure) {
      yield await _failure(
        step,
        kind: rust_wire.RoundStepFailureKindView.protocol,
        message: failure.toString(),
        strongestChainState: _chainStateView(failure.failure.strongestState),
      );
    } on _FakeHarnessError {
      // A misconfigured fake, not something the SDK could report. Let it
      // abort the run loudly rather than reading as an isolated bundle
      // failure a test might then assert around.
      rethrow;
    } on VotingRustException catch (error) {
      // A typed failure ends the run, because the run's single `Result` event
      // is the only channel that carries the kind and the snapshot height the
      // UI keys its specific messages off: `RoundStepFailureView` has neither
      // field, so isolating one here would silently downgrade, say, "this
      // account is not eligible" into generic failure text.
      yield _bridgeError(error);
    } catch (error) {
      // Anything else is work failing inside a step. `advance_step` returns
      // `Result<_, RoundStepFailure>`, so the driver isolates it per its
      // failure policy and the rest of the round still runs.
      yield await _failure(
        step,
        kind: rust_wire.RoundStepFailureKindView.protocol,
        message: error.toString(),
      );
    }
  }

  /// Bundles whose delegation this session already ran, so a synthesised
  /// plan stops listing them once they are done.
  final _delegatedBundles = <int>{};
  final _terminalDelegationBundles = <int>{};
  final _terminalDelegationDiagnostics = <int, rust_api.ApiChainDiagnostic?>{};

  Stream<_ScriptedStepEvent> _advanceDelegation(
    rust_wire.NextStepView step,
    rust_session.ApiDelegationSignerInput? signer,
  ) async* {
    final bundleIndex = step.bundleIndex;
    final hotkey = storedHotkeySecret;
    if (signer == null) {
      throw _FakeHarnessError('delegation step requires a signer');
    }
    if (hotkey == null) {
      throw _FakeHarnessError('delegation step requires a stored hotkey');
    }
    final Stream<rust_api.ApiDelegationProofEvent> events;
    rust_wire.KeystoneSignatureRecord? expectedSignature;
    switch (signer.kind) {
      case rust_session.ApiDelegationSignerKind.mnemonic:
        events = _steps.buildProveAndSignDelegationPayloadWithProgress(
          ctx: ctx,
          pirServerUrls: pirServerUrls,
          mnemonic: signer.mnemonic!,
          storedHotkeySecret: hotkey,
          bundleIndex: bundleIndex,
        );
      case rust_session.ApiDelegationSignerKind.keystoneStored:
        final record = driver.storedKeystoneSignatures[bundleIndex];
        if (record == null) {
          throw _FakeHarnessError(
            'missing Keystone signature for bundle $bundleIndex',
          );
        }
        expectedSignature = record;
        events = _steps
            .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
              ctx: ctx,
              pirServerUrls: pirServerUrls,
              storedHotkeySecret: hotkey,
              bundleIndex: bundleIndex,
              keystoneSig: record.sig,
              keystoneSighash: record.sighash,
            );
      case rust_session.ApiDelegationSignerKind.keystoneProvided:
        events = _steps
            .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
              ctx: ctx,
              pirServerUrls: pirServerUrls,
              storedHotkeySecret: hotkey,
              bundleIndex: bundleIndex,
              keystoneSig: signer.keystoneSig!,
              keystoneSighash: signer.keystoneSighash!,
            );
    }
    rust_wire.SignedDelegationPayloadView? payload;
    await for (final event in events) {
      final signed = event.signedDelegationPayload;
      if (signed != null) {
        payload = signed;
        continue;
      }
      yield _progress(
        _progressView(
          rust_wire.RoundStepProgressKind.delegation,
          step,
          bundleIndex: bundleIndex,
          delegationProgress: rust_wire.DelegationProgressKind.proofProgress,
          proofProgress: event.proofProgress,
        ),
      );
    }
    if (payload == null) {
      throw _FakeHarnessError(
        'delegation proof stream ended without a payload',
      );
    }
    if (expectedSignature != null) {
      // The SDK verifies a stored device signature against the bundle's
      // PCZT before anything reaches the chain.
      final wire = payload.submission;
      if (!_bytesEqual(base64.decode(wire.rk), expectedSignature.rk) ||
          !_bytesEqual(
            base64.decode(wire.spendAuthSig),
            expectedSignature.sig,
          )) {
        yield await _failure(
          step,
          kind: rust_wire.RoundStepFailureKindView.signing,
          message:
              'Keystone signature did not match delegation bundle $bundleIndex.',
        );
        return;
      }
    }
    final submission = payload;
    final outcome = await _chainEpisode(
      (passHandle, recoveryMode) => _steps.advanceChainDelegation(
        passHandle: passHandle,
        bundleIndex: bundleIndex,
        submission: submission,
        recoveryMode: recoveryMode,
      ),
    );
    yield _progress(
      _progressView(
        rust_wire.RoundStepProgressKind.chainOutcome,
        step,
        bundleIndex: bundleIndex,
        chainOutcome: _chainOutcomeView(outcome),
      ),
    );
    final disposition = _dispositionFor(outcome);
    if (disposition == rust_wire.RoundStepDispositionView.advanced) {
      _delegatedBundles.add(bundleIndex);
    }
    // A rejected or hashless submission is durably terminal in the SDK
    // (`DelegationPhase::SubmissionRejected` / `SubmittedWithoutHash`), and the
    // planner schedules nothing further for such a bundle. Recording it keeps
    // the re-plan shrinking the way the real one does, so a round with one dead
    // bundle can still drive its siblings.
    if (disposition == rust_wire.RoundStepDispositionView.chainTerminal) {
      _terminalDelegationBundles.add(bundleIndex);
      _terminalDelegationDiagnostics[bundleIndex] = outcome.diagnostic;
    }
    yield await _result(
      step,
      disposition,
      chainOutcome: outcome,
      delegation: submission,
    );
  }

  Stream<_ScriptedStepEvent> _advanceVote(rust_wire.NextStepView step) async* {
    final bundleIndex = step.bundleIndex;
    final ceremonyStart = binding.ceremonyStartSeconds;
    final voteEnd = binding.voteEndTimeSeconds;
    if (step.kind == rust_wire.NextStepKind.castVote) {
      final hotkey = storedHotkeySecret;
      if (hotkey == null) {
        throw _FakeHarnessError('cast-vote step requires a stored hotkey');
      }
      final singleShare =
          ceremonyStart != null &&
          voteEnd != null &&
          _api.isLastMoment(
            nowSeconds: _fakeNowSeconds,
            ceremonyStartSeconds: ceremonyStart,
            voteEndTimeSeconds: voteEnd,
          );
      // Every planned cast step for this bundle is proven as one batch.
      final plan = await _plan();
      final drafts = <VotingDraftVote>[
        for (final planned in plan.nextSteps)
          if (planned.kind == rust_wire.NextStepKind.castVote &&
              planned.bundleIndex == bundleIndex)
            VotingDraftVote(
              proposalId: planned.proposalId,
              choice: planned.choice,
              numOptions:
                  proposals
                      .where(
                        (proposal) => proposal.proposalId == planned.proposalId,
                      )
                      .firstOrNull
                      ?.numOptions ??
                  0,
            ),
      ];
      if (drafts.isNotEmpty) {
        final anchorHeight = await _syncVoteTree(binding.voteTreeNodeUrls);
        yield _progress(
          _progressView(
            rust_wire.RoundStepProgressKind.treeSynced,
            step,
            treeHeight: anchorHeight,
          ),
        );
        final witness = await _steps.generateVanWitness(
          dbPath: ctx.dbPath,
          accountUuid: accountUuid,
          roundId: roundId,
          bundleIndex: bundleIndex,
          anchorHeight: anchorHeight,
        );
        await for (final event in _steps.buildVoteCommitmentsWithProgress(
          dbPath: ctx.dbPath,
          accountUuid: accountUuid,
          network: ctx.network,
          roundId: roundId,
          bundleIndex: bundleIndex,
          storedHotkeySecret: hotkey,
          vanWitness: witness,
          draftVotes: drafts,
          singleShare: singleShare,
          maxProofConcurrency: binding.maxProofConcurrency,
        )) {
          final proposalId = event.proposalId;
          if (proposalId == null) continue;
          yield _progress(
            _progressView(
              rust_wire.RoundStepProgressKind.voteCommit,
              step,
              bundleIndex: bundleIndex,
              proposalId: proposalId,
              voteCommitStage: event.phase == 'proof_complete'
                  ? rust_wire.VoteCommitStageKind.signing
                  : rust_wire.VoteCommitStageKind.proofProgress,
              proofProgress: event.proofProgress,
            ),
          );
        }
      }
    }

    final proposalIds = [
      for (final proposalId
          in driver.batchProposalIdsByBundle[bundleIndex] ?? [step.proposalId])
        if (!driver.handledVoteKeys.contains('$bundleIndex:$proposalId'))
          proposalId,
    ];
    if (proposalIds.isEmpty) {
      yield await _result(step, rust_wire.RoundStepDispositionView.noWork);
      return;
    }
    for (final proposalId in proposalIds) {
      final key = '$bundleIndex:$proposalId';
      if (_proven(key)) continue;
      await _steps.recoverVoteCommitment(
        dbPath: ctx.dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        bundleIndex: bundleIndex,
        proposalId: proposalId,
      );
      _recoveredKeys.add(key);
    }

    final scope = FakeHelperDeliveryScope(
      dbPath: ctx.dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );
    {
      final lastMomentBuffer = ceremonyStart == null || voteEnd == null
          ? null
          : _api.lastMomentBufferSeconds(
              ceremonyStartSeconds: ceremonyStart,
              voteEndTimeSeconds: voteEnd,
            );
      final preflight = await _steps.preflightVotingHelpers(
        scope: scope,
        configuredHelperUrls: binding.configuredHelperUrls,
      );
      for (final proposalId in proposalIds) {
        await _steps.prepareCommittedShareDelivery(
          scope: scope,
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          preflight: preflight,
          nowSeconds: _fakeNowSeconds,
          voteEndTimeSeconds: voteEnd ?? BigInt.zero,
          proposalIds: _rosterIds,
          lastMomentBufferSeconds: lastMomentBuffer,
        );
      }
      yield _progress(
        _progressView(
          rust_wire.RoundStepProgressKind.helperPlansPrepared,
          step,
          voteKeys: [
            for (final proposalId in proposalIds)
              rust_wire.VoteKeyView(
                bundleIndex: bundleIndex,
                proposalId: proposalId,
              ),
          ],
        ),
      );

      rust_api.ApiChainSubmissionOutcome? chainOutcome;
      if (step.kind != rust_wire.NextStepKind.submitShares) {
        final outcome = await _chainEpisode(
          (passHandle, recoveryMode) => proposalIds.length > 1
              ? _steps.advanceChainVoteBatch(
                  passHandle: passHandle,
                  bundleIndex: bundleIndex,
                  proposalId: proposalIds.first,
                  recoveryMode: recoveryMode,
                )
              : _steps.advanceChainVote(
                  passHandle: passHandle,
                  bundleIndex: bundleIndex,
                  proposalId: proposalIds.single,
                  recoveryMode: recoveryMode,
                ),
        );
        chainOutcome = outcome;
        yield _progress(
          _progressView(
            rust_wire.RoundStepProgressKind.chainOutcome,
            step,
            bundleIndex: bundleIndex,
            chainOutcome: _chainOutcomeView(outcome),
          ),
        );
        final disposition = _dispositionFor(outcome);
        if (disposition != rust_wire.RoundStepDispositionView.advanced) {
          yield await _result(step, disposition, chainOutcome: outcome);
          return;
        }
      }

      final deliveries = <rust_wire.ShareBatchDeliveryReportView>[];
      for (final proposalId in proposalIds) {
        final delivery = await _steps.submitPreparedSharesToHelpers(
          scope: scope,
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          configuredHelperUrls: binding.configuredHelperUrls,
          nowSeconds: _fakeNowSeconds,
        );
        final report = _shareDeliveryView(
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          delivery: delivery,
        );
        deliveries.add(report);
        yield _progress(
          _progressView(
            rust_wire.RoundStepProgressKind.shareOutcome,
            step,
            bundleIndex: bundleIndex,
            proposalId: proposalId,
            shareDelivery: report,
          ),
        );
        final incomplete =
            delivery.pendingShareIndices.isNotEmpty ||
            delivery.deliveries.any(
              (outcome) =>
                  outcome.submission.acceptedUrls.isEmpty &&
                  outcome.submission.ambiguousUrls.isEmpty,
            );
        if (delivery.cancelled) {
          yield await _result(
            step,
            rust_wire.RoundStepDispositionView.cancelled,
            chainOutcome: chainOutcome,
            shareDeliveries: deliveries,
          );
          return;
        }
        if (incomplete) {
          yield await _failure(
            step,
            kind: rust_wire.RoundStepFailureKindView.helperDeliveryIncomplete,
            message: 'helper delivery ended with pending shares',
          );
          return;
        }
        driver.handledVoteKeys.add('$bundleIndex:$proposalId');
      }
      yield await _result(
        step,
        rust_wire.RoundStepDispositionView.advanced,
        chainOutcome: chainOutcome,
        shareDeliveries: deliveries,
      );
    }
  }

  /// Ordered node failover: a failed sync resets the cached tree before the
  /// next node is tried, as the SDK cast-vote step does.
  Future<int> _syncVoteTree(List<String> nodeUrls) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var index = 0; index < nodeUrls.length; index++) {
      if (index > 0) {
        await _api.resetVoteTree(
          dbPath: ctx.dbPath,
          accountUuid: accountUuid,
          roundId: roundId,
        );
      }
      try {
        return await _api.syncVoteTree(
          dbPath: ctx.dbPath,
          accountUuid: accountUuid,
          roundId: roundId,
          nodeUrl: nodeUrls[index],
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    if (lastError == null) {
      throw _FakeHarnessError(
        'cast vote requires at least one vote-tree node URL',
      );
    }
    Error.throwWithStackTrace(lastError, lastStackTrace!);
  }

  Future<rust_api.ApiChainSubmissionOutcome> _chainEpisode(
    Future<rust_api.ApiChainSubmissionCallResult> Function(
      FakeChainSubmissionPassHandle passHandle,
      rust_api.ApiChainRecoveryMode recoveryMode,
    )
    advance,
  ) async {
    final passHandle = _steps.beginChainSubmissionPass(
      dbPath: ctx.dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      network: ctx.network,
      endpoints: chainEndpoints,
      operationEpoch: operationEpoch,
    );
    if (isCancelled) passHandle.cancel();
    _passHandles.add(passHandle);
    var exactRecoveryAttempted = false;
    try {
      while (true) {
        final result = await advance(
          passHandle,
          exactRecoveryAttempted
              ? rust_api.ApiChainRecoveryMode.exactTree
              : rust_api.ApiChainRecoveryMode.statusOnly,
        );
        final failure = result.failure;
        if (failure != null) throw _FakeChainSubmissionFailure(failure);
        final outcome = result.outcome!;
        switch (outcome.kind) {
          case rust_api.ApiChainSubmissionOutcomeKind.tracking:
            await Future.any<void>([
              Future<void>.delayed(const Duration(seconds: 2)),
              _cancelled.future,
            ]);
            if (isCancelled) return _cancelledOutcome();
            continue;
          case rust_api.ApiChainSubmissionOutcomeKind.recovering:
            if (exactRecoveryAttempted ||
                outcome.diagnostic?.kind ==
                    rust_api.ApiChainDiagnosticKind.recoveryUnavailable) {
              return outcome;
            }
            exactRecoveryAttempted = true;
            continue;
          case rust_api.ApiChainSubmissionOutcomeKind.confirmed:
          case rust_api.ApiChainSubmissionOutcomeKind.submittedWithoutHash:
          case rust_api.ApiChainSubmissionOutcomeKind.rejected:
          case rust_api.ApiChainSubmissionOutcomeKind.cancelled:
            return outcome;
        }
      }
    } finally {
      _passHandles.remove(passHandle);
      passHandle.dispose();
    }
  }

  static rust_wire.RoundStepDispositionView _dispositionFor(
    rust_api.ApiChainSubmissionOutcome outcome,
  ) => switch (outcome.kind) {
    rust_api.ApiChainSubmissionOutcomeKind.confirmed =>
      rust_wire.RoundStepDispositionView.advanced,
    rust_api.ApiChainSubmissionOutcomeKind.tracking ||
    rust_api.ApiChainSubmissionOutcomeKind.recovering =>
      rust_wire.RoundStepDispositionView.pending,
    rust_api.ApiChainSubmissionOutcomeKind.cancelled =>
      rust_wire.RoundStepDispositionView.cancelled,
    rust_api.ApiChainSubmissionOutcomeKind.submittedWithoutHash ||
    rust_api.ApiChainSubmissionOutcomeKind.rejected =>
      rust_wire.RoundStepDispositionView.chainTerminal,
  };

  _ScriptedStepEvent _progress(rust_wire.RoundStepProgressView progress) {
    return _ScriptedStepEvent(
      kind: rust_session.ApiRoundStepEventKind.progress,
      progress: progress,
      outcome: null,
      failure: null,
    );
  }

  /// Drives the scripted plan the way the SDK driver does.
  ///
  /// The real loop lives in Rust (`zcash_voting::round_drive`) and its
  /// conformance tests are the source of truth for it. This mirrors only what
  /// provider tests observe — plan-ordered selection, per-bundle failure
  /// isolation, and the quiescence the run stops on — over the same per-step
  /// script the steps use. Keep the two in step; do not add behaviour
  /// here that the Rust driver does not have.
  @override
  Stream<rust_session.ApiRoundRunEvent> runRound({
    rust_session.ApiDelegationSignerInput? signer,
    rust_session.ApiRoundDrivePolicy? policy,
  }) async* {
    if (driver.scriptedRoundRuns.isNotEmpty) {
      for (final event in driver.scriptedRoundRuns.removeAt(0)) {
        yield event;
      }
      return;
    }
    // Like the SDK driver, progress is measured against a baseline captured
    // from the run's first plan, not against whatever the current plan still
    // lists. Reset per run so a second run does not inherit the first's.
    _progressBaseline = null;
    final skipped = <int>[];
    final failures = <rust_wire.RoundStepFailureRecordView>[];
    final chainOutcomes = <rust_wire.RoundChainOutcomeView>[];
    final shareDeliveries = <rust_wire.ShareBatchDeliveryReportView>[];
    var plan = await _plan(synthesizeDelegation: signer != null);
    // The SDK driver bounds itself with `max_dispatches`; without the same
    // guard a scripted plan that never shrinks would spin here forever and
    // hang the test rather than failing it.
    var dispatches = 0;
    const maxDispatches = 64;

    while (true) {
      // The driver re-checks cancellation before every plan read, so a host
      // that cancels mid-run stops at the next boundary instead of running the
      // round out.
      if (isCancelled) {
        yield _runReport(
          _quiescence(rust_wire.RoundQuiescenceKind.cancelled),
          plan,
          failures,
          skipped,
          chainOutcomes,
          shareDeliveries,
        );
        return;
      }
      if (dispatches >= maxDispatches) {
        throw StateError(
          'Fake round run exceeded $maxDispatches dispatches; the scripted '
          'plan is not shrinking.',
        );
      }
      plan = await _plan(synthesizeDelegation: signer != null);
      yield _runEvent(
        rust_wire.RoundDriveEventView(
          kind: rust_wire.RoundDriveEventKind.planRefreshed,
          plan: plan,
          tally: _tally(plan),
        ),
      );

      final quiescence = _quiescenceBeforeDispatch(plan, failures);
      if (quiescence != null) {
        yield _runReport(
          quiescence,
          plan,
          failures,
          skipped,
          chainOutcomes,
          shareDeliveries,
        );
        return;
      }

      final step = plan.nextSteps
          .where((step) => !skipped.contains(step.bundleIndex))
          .firstOrNull;
      if (step == null) {
        yield _runReport(
          _quiescence(rust_wire.RoundQuiescenceKind.failures),
          plan,
          failures,
          skipped,
          chainOutcomes,
          shareDeliveries,
        );
        return;
      }
      if (_needsDelegationSigner(step) &&
          signer?.kind == rust_session.ApiDelegationSignerKind.keystoneStored) {
        // The SDK checks every bundle the round still owes a delegation for
        // against the durable signature rows, and stops before dispatching
        // anything when one is missing, so the voter signs once.
        final stored = await _api.getKeystoneSignatures(
          dbPath: ctx.dbPath,
          accountUuid: ctx.accountUuid,
          roundId: roundId,
        );
        final signed = {for (final record in stored) record.bundleIndex};
        final unsigned = Uint32List.fromList([
          for (final planned in plan.nextSteps)
            if (_needsDelegationSigner(planned) &&
                !skipped.contains(planned.bundleIndex) &&
                !signed.contains(planned.bundleIndex))
              planned.bundleIndex,
        ]);
        if (unsigned.isNotEmpty) {
          yield _runReport(
            _quiescence(
              rust_wire.RoundQuiescenceKind.needsDelegationSignatures,
              bundles: unsigned,
            ),
            plan,
            failures,
            skipped,
            chainOutcomes,
            shareDeliveries,
          );
          return;
        }
      }
      if (_needsDelegationSigner(step) && signer == null) {
        yield _runReport(
          _quiescence(
            rust_wire.RoundQuiescenceKind.needsDelegationSignatures,
            bundles: _delegationBundles(plan, skipped),
          ),
          plan,
          failures,
          skipped,
          chainOutcomes,
          shareDeliveries,
        );
        return;
      }

      yield _runEvent(
        rust_wire.RoundDriveEventView(
          kind: rust_wire.RoundDriveEventKind.stepSelected,
          step: step,
        ),
      );
      dispatches += 1;

      _ScriptedStepEvent? terminal;
      await for (final event in _advanceScriptedStep(
        step: step,
        signer: signer,
      )) {
        final progress = event.progress;
        if (progress != null) {
          yield _runEvent(
            rust_wire.RoundDriveEventView(
              kind: rust_wire.RoundDriveEventKind.stepProgress,
              step: step,
              progress: progress,
            ),
          );
        }
        if (event.kind == rust_session.ApiRoundStepEventKind.result) {
          terminal = event;
        }
      }
      if (terminal == null) {
        throw StateError('Round step completed without a result.');
      }

      final error = terminal.error;
      if (error != null) {
        yield rust_session.ApiRoundRunEvent(
          kind: rust_session.ApiRoundStepEventKind.result,
          error: error,
        );
        return;
      }

      final failure = terminal.failure;
      if (failure != null) {
        yield _runEvent(
          rust_wire.RoundDriveEventView(
            kind: rust_wire.RoundDriveEventKind.stepFailed,
            step: step,
            failureKind: failure.kind,
            message: failure.message,
          ),
        );
        failures.add(
          rust_wire.RoundStepFailureRecordView(
            step: step,
            bundleIndex: step.bundleIndex,
            failure: failure,
          ),
        );
        skipped.add(step.bundleIndex);
        yield _runEvent(
          rust_wire.RoundDriveEventView(
            kind: rust_wire.RoundDriveEventKind.bundleSkipped,
            step: step,
            bundleIndex: step.bundleIndex,
          ),
        );
        continue;
      }

      final outcome = terminal.outcome!;
      yield _runEvent(
        rust_wire.RoundDriveEventView(
          kind: rust_wire.RoundDriveEventKind.stepFinished,
          step: step,
          disposition: outcome.disposition,
        ),
      );
      shareDeliveries.addAll(outcome.shareDeliveries);
      final chainOutcome = outcome.chainOutcome;
      if (chainOutcome != null) {
        chainOutcomes.add(
          rust_wire.RoundChainOutcomeView(step: step, outcome: chainOutcome),
        );
      }
      switch (outcome.disposition) {
        case rust_wire.RoundStepDispositionView.advanced:
        case rust_wire.RoundStepDispositionView.noWork:
          continue;
        case rust_wire.RoundStepDispositionView.pending:
          // The scripted fake never leaves a submission tracking, so a pending
          // result here means the script has nothing further for it.
          yield _runReport(
            _quiescence(
              rust_wire.RoundQuiescenceKind.chainRecoveryStalled,
              step: step,
              chainOutcome: chainOutcome,
            ),
            // The report carries the plan the run was working from, the way
            // the SDK's does; re-planning here would describe a different
            // round than the one the driver drove.
            plan,
            failures,
            skipped,
            chainOutcomes,
            shareDeliveries,
          );
          return;
        case rust_wire.RoundStepDispositionView.cancelled:
          yield _runReport(
            _quiescence(rust_wire.RoundQuiescenceKind.cancelled),
            // The report carries the plan the run was working from, the way
            // the SDK's does; re-planning here would describe a different
            // round than the one the driver drove.
            plan,
            failures,
            skipped,
            chainOutcomes,
            shareDeliveries,
          );
          return;
        case rust_wire.RoundStepDispositionView.chainTerminal:
          yield _runReport(
            _quiescence(
              rust_wire.RoundQuiescenceKind.chainTerminal,
              step: step,
              chainOutcome: chainOutcome,
            ),
            // The report carries the plan the run was working from, the way
            // the SDK's does; re-planning here would describe a different
            // round than the one the driver drove.
            plan,
            failures,
            skipped,
            chainOutcomes,
            shareDeliveries,
          );
          return;
      }
    }
  }

  bool _isDelegationStep(rust_wire.NextStepView step) =>
      step.kind == rust_wire.NextStepKind.delegate ||
      step.kind == rust_wire.NextStepKind.advanceDelegation ||
      step.kind == rust_wire.NextStepKind.advanceImportedDelegation;

  bool _needsDelegationSigner(rust_wire.NextStepView step) =>
      step.kind == rust_wire.NextStepKind.delegate ||
      step.kind == rust_wire.NextStepKind.advanceDelegation;

  Uint32List _delegationBundles(
    rust_wire.RoundPlanView plan,
    List<int> skipped,
  ) => Uint32List.fromList([
    for (final step in plan.nextSteps)
      if (_needsDelegationSigner(step) && !skipped.contains(step.bundleIndex))
        step.bundleIndex,
  ]);

  rust_wire.RoundQuiescenceView? _quiescenceBeforeDispatch(
    rust_wire.RoundPlanView plan,
    List<rust_wire.RoundStepFailureRecordView> failures,
  ) {
    if (plan.nextSteps.isEmpty) {
      if (failures.isNotEmpty) {
        return _quiescence(rust_wire.RoundQuiescenceKind.failures);
      }
      if (plan.blockingRecovery) {
        return _quiescence(
          rust_wire.RoundQuiescenceKind.persistedChainTerminal,
        );
      }
      if (plan.needsBundleSetup) {
        return _quiescence(rust_wire.RoundQuiescenceKind.needsBundleSetup);
      }
      if (plan.openProposals.isNotEmpty || plan.unrosteredIntents.isNotEmpty) {
        return _quiescence(
          rust_wire.RoundQuiescenceKind.needsBallot,
          openProposals: plan.openProposals,
          unrosteredIntents: plan.unrosteredIntents,
        );
      }
      return _quiescence(rust_wire.RoundQuiescenceKind.noWorkLeft);
    }
    if (!plan.blockingRecovery) {
      if (failures.isNotEmpty) {
        return _quiescence(rust_wire.RoundQuiescenceKind.failures);
      }
      return _quiescence(
        rust_wire.RoundQuiescenceKind.backgroundShareWorkOnly,
        shares: [
          for (final step in plan.nextSteps)
            if (step.kind == rust_wire.NextStepKind.confirmShare)
              rust_wire.ShareKeyView(
                bundleIndex: step.bundleIndex,
                proposalId: step.proposalId,
                shareIndex: step.shareIndex,
              ),
        ],
      );
    }
    return null;
  }

  rust_wire.RoundQuiescenceView _quiescence(
    rust_wire.RoundQuiescenceKind kind, {
    Uint32List? openProposals,
    Uint32List? unrosteredIntents,
    Uint32List? bundles,
    List<rust_wire.ShareKeyView> shares = const [],
    rust_wire.NextStepView? step,
    rust_wire.ChainSubmissionOutcomeView? chainOutcome,
  }) => rust_wire.RoundQuiescenceView(
    kind: kind,
    openProposals: openProposals ?? Uint32List(0),
    unrosteredIntents: unrosteredIntents ?? Uint32List(0),
    bundles: bundles ?? Uint32List(0),
    shares: shares,
    step: step,
    chainOutcome: chainOutcome,
    remaining: const [],
  );

  /// Proposals this run measures progress against, captured from its first
  /// plan the way the SDK driver captures a `BallotBaseline`.
  ///
  /// The real driver reads batch membership from the obligation, so its total
  /// is exact where counting steps is not; a scripted plan here names one
  /// proposal per step, which is all these tests need. Batch exactness is
  /// pinned by the SDK's own tally tests.
  Set<int>? _progressBaseline;

  rust_wire.RoundWorkTallyView _tally(rust_wire.RoundPlanView plan) {
    final covered = _voteProposals(plan);
    final baseline = _progressBaseline ??= covered;
    return rust_wire.RoundWorkTallyView(
      completedProposals: baseline
          .where((proposalId) => !covered.contains(proposalId))
          .length,
      totalProposals: baseline.length,
      remainingObligations: plan.nextSteps.length,
    );
  }

  /// Proposals `plan` still owes vote work for.
  Set<int> _voteProposals(rust_wire.RoundPlanView plan) => {
    for (final step in plan.nextSteps)
      if (step.kind != rust_wire.NextStepKind.delegate &&
          step.kind != rust_wire.NextStepKind.advanceDelegation)
        step.proposalId,
  };

  rust_session.ApiRoundRunEvent _runEvent(
    rust_wire.RoundDriveEventView event,
  ) => rust_session.ApiRoundRunEvent(
    kind: rust_session.ApiRoundStepEventKind.progress,
    event: event,
  );

  rust_session.ApiRoundRunEvent _runReport(
    rust_wire.RoundQuiescenceView quiescence,
    rust_wire.RoundPlanView plan,
    List<rust_wire.RoundStepFailureRecordView> failures,
    List<int> skipped,
    List<rust_wire.RoundChainOutcomeView> chainOutcomes,
    List<rust_wire.ShareBatchDeliveryReportView> shareDeliveries,
  ) => rust_session.ApiRoundRunEvent(
    kind: rust_session.ApiRoundStepEventKind.result,
    report: rust_wire.RoundRunReportView(
      quiescence: quiescence,
      plan: plan,
      tally: _tally(plan),
      failures: List.of(failures),
      skippedBundles: Uint32List.fromList(skipped),
      chainOutcomes: List.of(chainOutcomes),
      shareDeliveries: List.of(shareDeliveries),
      delegations: const [],
    ),
  );

  Future<_ScriptedStepEvent> _result(
    rust_wire.NextStepView step,
    rust_wire.RoundStepDispositionView disposition, {
    rust_api.ApiChainSubmissionOutcome? chainOutcome,
    List<rust_wire.ShareBatchDeliveryReportView> shareDeliveries = const [],
    rust_wire.SignedDelegationPayloadView? delegation,
  }) async {
    return _ScriptedStepEvent(
      kind: rust_session.ApiRoundStepEventKind.result,
      progress: null,
      outcome: _ScriptedStepOutcome(
        disposition: disposition,
        chainOutcome: chainOutcome == null
            ? null
            : _chainOutcomeView(chainOutcome),
        shareDeliveries: shareDeliveries,
        delegation: delegation,
        plan: await _plan(),
      ),
      failure: null,
    );
  }

  Future<_ScriptedStepEvent> _failure(
    rust_wire.NextStepView step, {
    required rust_wire.RoundStepFailureKindView kind,
    required String message,
    rust_wire.ChainSubmissionFailureStateView? strongestChainState,
  }) async {
    return _ScriptedStepEvent(
      kind: rust_session.ApiRoundStepEventKind.result,
      progress: null,
      outcome: null,
      failure: rust_wire.RoundStepFailureView(
        kind: kind,
        step: step,
        strongestChainState: strongestChainState,
        chainOutcome: null,
        message: message,
        plan: await _plan(),
        shareDeliveries: const [],
      ),
    );
  }

  /// One result event carrying a typed bridge failure, the way `run_round`
  /// reports a failure raised before the SDK saw the step.
  _ScriptedStepEvent _bridgeError(VotingRustException error) {
    return _ScriptedStepEvent(
      kind: rust_session.ApiRoundStepEventKind.result,
      progress: null,
      outcome: null,
      failure: null,
      error: apiRoundStepError(error.view),
    );
  }

  @override
  Future<List<rust_delegate.KeystoneSigningRequest>> keystoneSigningRequests(
    List<int> bundleIndices,
  ) {
    return _api.buildKeystoneDelegationRequests(
      ctx: ctx,
      storedHotkeySecret: storedHotkeySecret ?? const [],
      bundleIndices: bundleIndices,
    );
  }

  FakeHelperDeliveryScope get _helperScope => FakeHelperDeliveryScope(
    dbPath: ctx.dbPath,
    accountUuid: accountUuid,
    roundId: roundId,
  );

  @override
  Stream<rust_session.ApiShareTrackingRunEvent> runShareTracking({
    rust_session.ApiShareTrackingDrivePolicy? policy,
  }) async* {
    driver.shareTrackingSessions.add(this);
    driver.shareTrackingPolicies.add(policy);
    if (driver.scriptedShareTrackingRuns.isNotEmpty) {
      for (final event in driver.scriptedShareTrackingRuns.removeAt(0)) {
        yield event;
      }
      return;
    }

    final confirmed = <rust_wire.ShareKeyView>[];
    final resubmitted = <rust_wire.ResubmittedShareView>[];
    final ambiguous = <rust_wire.ResubmittedShareView>[];
    var unrecoverable = const <rust_wire.ShareKeyView>[];
    var passes = 0;
    // The real driver bounds itself; without the same guard a pass that never
    // settles would spin here forever and hang the test rather than fail it.
    const maxPasses = 64;

    while (true) {
      final voteEnd = binding.voteEndTimeSeconds;
      if (voteEnd != null && _fakeNowSeconds >= voteEnd) {
        yield _trackingReport(
          rust_wire.ShareTrackingQuiescenceKind.voteEndReached,
          passes,
          confirmed,
          resubmitted,
          ambiguous,
          unrecoverable,
        );
        return;
      }
      if (isCancelled) {
        yield _trackingReport(
          rust_wire.ShareTrackingQuiescenceKind.cancelled,
          passes,
          confirmed,
          resubmitted,
          ambiguous,
          unrecoverable,
        );
        return;
      }
      if (passes >= maxPasses) {
        throw StateError(
          'Fake share tracking exceeded $maxPasses passes; the scripted round '
          'never settles.',
        );
      }

      passes += 1;
      yield _trackingEvent(
        rust_wire.ShareTrackingEventView(
          kind: rust_wire.ShareTrackingEventKind.passStarted,
          pass: passes,
        ),
      );
      final rust_wire.ShareTrackingPassReportView pass;
      try {
        pass = await _steps.trackPendingSharesPass(
          scope: _helperScope,
          configuredHelperUrls: binding.configuredHelperUrls,
          nowSeconds: _fakeNowSeconds,
          voteEndTimeSeconds: binding.voteEndTimeSeconds,
          isCancelled: () => isCancelled,
        );
      } catch (error) {
        // A failing pass is retried by the driver, not surfaced as a bridge
        // error. The fake stops after one so a test asserting on failure does
        // not wait out a retry schedule it cannot see.
        yield _trackingEvent(
          rust_wire.ShareTrackingEventView(
            kind: rust_wire.ShareTrackingEventKind.passFailed,
            pass: passes,
            message: error.toString(),
          ),
        );
        yield rust_session.ApiShareTrackingRunEvent(
          kind: rust_session.ApiRoundStepEventKind.result,
          report: rust_wire.ShareTrackingRunReportView(
            quiescence: rust_wire.ShareTrackingQuiescenceView(
              kind: rust_wire.ShareTrackingQuiescenceKind.failing,
              messages: [error.toString()],
              unrecoverable: const [],
            ),
            passes: passes,
            confirmed: confirmed,
            resubmitted: resubmitted,
            ambiguous: ambiguous,
            unrecoverable: unrecoverable,
            failures: [error.toString()],
          ),
        );
        return;
      }

      confirmed.addAll(pass.confirmed);
      resubmitted.addAll(pass.resubmitted);
      ambiguous.addAll(pass.ambiguous);
      unrecoverable = pass.unrecoverable;
      yield _trackingEvent(
        rust_wire.ShareTrackingEventView(
          kind: rust_wire.ShareTrackingEventKind.passFinished,
          pass: passes,
          report: pass,
        ),
      );

      if (pass.cancelled || isCancelled) {
        yield _trackingReport(
          rust_wire.ShareTrackingQuiescenceKind.cancelled,
          passes,
          confirmed,
          resubmitted,
          ambiguous,
          unrecoverable,
        );
        return;
      }
      if (pass.nextDelaySeconds == null) {
        yield _trackingReport(
          passes == 1 && confirmed.isEmpty && resubmitted.isEmpty
              ? rust_wire.ShareTrackingQuiescenceKind.nothingToTrack
              : rust_wire.ShareTrackingQuiescenceKind.allConfirmed,
          passes,
          confirmed,
          resubmitted,
          ambiguous,
          unrecoverable,
        );
        return;
      }
      // Tests drive wall-clock-free, so the driver's wait cannot be simulated
      // faithfully. A pass that advanced something is followed immediately by
      // the next one, which is what a test asserting on multi-pass recovery
      // needs. A pass that advanced nothing means the driver would now be
      // waiting, and the run ends there rather than spinning: what the wait
      // should have been is pinned by the SDK's own pacing tests.
      yield _trackingEvent(
        rust_wire.ShareTrackingEventView(
          kind: rust_wire.ShareTrackingEventKind.awaitingNextPass,
          // The wait is fractional seconds now; the pass reports whole ones.
          delaySeconds: pass.nextDelaySeconds?.toDouble(),
        ),
      );
      // Only a confirmation earns another immediate pass. A resubmission
      // leaves the share pending, so the driver would wait for the helper to
      // answer before looking again — running straight back would resubmit it
      // forever.
      if (pass.confirmed.isEmpty) {
        yield _trackingReport(
          rust_wire.ShareTrackingQuiescenceKind.passBudgetExhausted,
          passes,
          confirmed,
          resubmitted,
          ambiguous,
          unrecoverable,
        );
        return;
      }
    }
  }

  @override
  Future<bool> confirmImmediateShare({
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) {
    driver.focusedConfirmationSessions.add(this);
    return _steps.confirmOneShareWithHelpers(
      scope: _helperScope,
      configuredHelperUrls: binding.configuredHelperUrls,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      nowSeconds: _fakeNowSeconds,
      isCancelled: () => isCancelled,
    );
  }

  rust_session.ApiShareTrackingRunEvent _trackingEvent(
    rust_wire.ShareTrackingEventView event,
  ) => rust_session.ApiShareTrackingRunEvent(
    kind: rust_session.ApiRoundStepEventKind.progress,
    event: event,
  );

  rust_session.ApiShareTrackingRunEvent _trackingReport(
    rust_wire.ShareTrackingQuiescenceKind quiescence,
    int passes,
    List<rust_wire.ShareKeyView> confirmed,
    List<rust_wire.ResubmittedShareView> resubmitted,
    List<rust_wire.ResubmittedShareView> ambiguous,
    List<rust_wire.ShareKeyView> unrecoverable,
  ) => rust_session.ApiShareTrackingRunEvent(
    kind: rust_session.ApiRoundStepEventKind.result,
    report: rust_wire.ShareTrackingRunReportView(
      quiescence: rust_wire.ShareTrackingQuiescenceView(
        kind: quiescence,
        messages: const [],
        unrecoverable:
            quiescence ==
                rust_wire.ShareTrackingQuiescenceKind.passBudgetExhausted
            ? unrecoverable
            : const [],
      ),
      passes: passes,
      confirmed: List.of(confirmed),
      resubmitted: List.of(resubmitted),
      ambiguous: List.of(ambiguous),
      unrecoverable: List.of(unrecoverable),
      failures: const [],
    ),
  );
}

/// A precondition the fake itself guarantees before it dispatches a step.
///
/// Reaching one means the test is wired wrong — a missing signer the run loop
/// should already have quiesced on, say — so it must abort the run loudly
/// instead of being isolated as a bundle failure a test could assert around.
class _FakeHarnessError extends Error {
  _FakeHarnessError(this.message);

  final String message;

  @override
  String toString() => 'Fake round session misconfigured: $message';
}

class _FakeChainSubmissionFailure implements Exception {
  const _FakeChainSubmissionFailure(this.failure);

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

rust_wire.RoundStepProgressView _progressView(
  rust_wire.RoundStepProgressKind kind,
  rust_wire.NextStepView step, {
  int? bundleIndex,
  int? proposalId,
  rust_wire.DelegationProgressKind? delegationProgress,
  rust_wire.VoteCommitStageKind? voteCommitStage,
  double? proofProgress,
  int? treeHeight,
  List<rust_wire.VoteKeyView> voteKeys = const [],
  rust_wire.ChainSubmissionOutcomeView? chainOutcome,
  rust_wire.ShareBatchDeliveryReportView? shareDelivery,
}) {
  return rust_wire.RoundStepProgressView(
    kind: kind,
    step: step,
    bundleIndex: bundleIndex,
    proposalId: proposalId,
    delegationProgress: delegationProgress,
    voteCommitStage: voteCommitStage,
    proofProgress: proofProgress,
    treeHeight: treeHeight,
    voteKeys: voteKeys,
    chainOutcome: chainOutcome,
    shareDelivery: shareDelivery,
    share: null,
    shareConfirmed: null,
  );
}

rust_api.ApiChainSubmissionOutcome _cancelledOutcome() {
  return rust_api.ApiChainSubmissionOutcome(
    kind: rust_api.ApiChainSubmissionOutcomeKind.cancelled,
    confirmationSource: null,
    transactionHash: null,
    candidateTransactionHash: null,
    finalVanPosition: null,
    voteCommitmentPositions: frb.Uint64List(0),
    diagnostic: null,
  );
}

rust_wire.ChainSubmissionOutcomeView _chainOutcomeView(
  rust_api.ApiChainSubmissionOutcome outcome,
) {
  final diagnostic = outcome.diagnostic;
  final source = outcome.confirmationSource;
  return rust_wire.ChainSubmissionOutcomeView(
    kind: rust_wire.ChainSubmissionOutcomeKind.values.byName(outcome.kind.name),
    confirmationSource: source == null
        ? null
        : rust_wire.ChainConfirmationSourceView.values.byName(source.name),
    transactionHash: outcome.transactionHash,
    candidateTransactionHash: outcome.candidateTransactionHash,
    finalVanPosition: outcome.finalVanPosition,
    voteCommitmentPositions: outcome.voteCommitmentPositions,
    diagnostic: diagnostic == null
        ? null
        : rust_wire.ChainDiagnosticView(
            kind:
                rust_wire.ChainDiagnosticKindView.values
                    .asNameMap()[diagnostic.kind.name] ??
                rust_wire.ChainDiagnosticKindView.reconciliationPending,
            message: diagnostic.message,
          ),
  );
}

rust_wire.ChainSubmissionFailureStateView? _chainStateView(
  rust_api.ApiChainSubmissionFailureState? state,
) {
  if (state == null) return null;
  return rust_wire.ChainSubmissionFailureStateView(
    state: rust_wire.ChainSubmissionStateView.values.byName(state.state.name),
    evidence: rust_wire.ChainSubmissionStateEvidenceView.values.byName(
      state.evidence.name,
    ),
  );
}

rust_wire.ShareBatchDeliveryReportView _shareDeliveryView({
  required int bundleIndex,
  required int proposalId,
  required rust_api.ApiShareBatchDeliveryReport delivery,
}) {
  return rust_wire.ShareBatchDeliveryReportView(
    vote: rust_wire.VoteKeyView(
      bundleIndex: bundleIndex,
      proposalId: proposalId,
    ),
    deliveries: [
      for (final outcome in delivery.deliveries)
        rust_wire.ShareDeliveryOutcomeView(
          shareIndex: outcome.shareIndex,
          acceptedUrls: outcome.submission.acceptedUrls,
          ambiguousUrls: outcome.submission.ambiguousUrls,
          targetCount: outcome.submission.targetCount,
        ),
    ],
    pendingShareIndices: delivery.pendingShareIndices,
    cancelled: delivery.cancelled,
    legacyBestEffort: delivery.legacyBestEffort,
  );
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
