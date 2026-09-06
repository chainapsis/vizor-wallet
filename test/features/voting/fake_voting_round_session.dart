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
    required VotingHelperDeliveryContext context,
    required List<String> configuredHelperUrls,
  });

  Future<void> prepareCommittedShareDelivery({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiVotingHelperPreflight preflight,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    required List<int> proposalIds,
    BigInt? lastMomentBufferSeconds,
  });

  Future<rust_api.ApiShareBatchDeliveryReport> submitPreparedSharesToHelpers({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
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
    required this.chainEndpoints,
    required this.pirServerUrls,
    required this.proposals,
    required this.storedHotkeySecret,
    required this.operationEpoch,
  });

  final FakeRoundSessionDriver driver;
  final rust_api.ApiVotingRoundContext ctx;
  final List<String> chainEndpoints;
  final List<String> pirServerUrls;
  final List<rust_session.ApiProposalRosterEntry> proposals;
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

  FakeRoundStepApi get _steps => driver.stepApi;

  @override
  String get accountUuid => ctx.accountUuid;

  @override
  String get roundId => ctx.roundParams.voteRoundId;

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
            _delegatedBundles.contains(step.bundleIndex)) {
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
      delegationStatuses: base?.delegationStatuses ?? const [],
      immediateShareKey: base?.immediateShareKey,
      immediateShareConfirmed: base?.immediateShareConfirmed ?? false,
    );
  }

  /// Runs one scripted step. Private: production drives rounds through
  /// `runRound`, and the bridge no longer exposes a per-step entry point.
  Stream<_ScriptedStepEvent> _advanceScriptedStep({
    required rust_wire.NextStepView step,
    required rust_session.ApiRoundHostContext host,
    rust_session.ApiDelegationSignerInput? signer,
  }) async* {
    final stepKey = '${step.kind.name}:${step.bundleIndex}';
    driver.roundSessionSteps.add(stepKey);
    final bridgeError = driver.roundStepBridgeErrors.remove(stepKey);
    if (bridgeError != null) {
      yield _bridgeError(bridgeError);
      return;
    }
    try {
      switch (step.kind) {
        case rust_wire.NextStepKind.delegate:
        case rust_wire.NextStepKind.advanceDelegation:
          yield* _advanceDelegation(step, host, signer);
        case rust_wire.NextStepKind.castVote:
        case rust_wire.NextStepKind.advanceVote:
        case rust_wire.NextStepKind.advanceVoteBatch:
        case rust_wire.NextStepKind.submitShares:
          yield* _advanceVote(step, host);
        case rust_wire.NextStepKind.advanceImportedDelegation:
        case rust_wire.NextStepKind.confirmShare:
          yield await _result(step, rust_wire.RoundStepDispositionView.noWork);
      }
    } on _FakeChainSubmissionFailure catch (failure) {
      yield await _failure(
        step,
        kind: rust_wire.RoundStepFailureKindView.protocol,
        message: failure.toString(),
        strongestChainState: _chainStateView(failure.failure.strongestState),
      );
    }
  }

  /// Bundles whose delegation this session already ran, so a synthesised
  /// plan stops listing them once they are done.
  final _delegatedBundles = <int>{};

  Stream<_ScriptedStepEvent> _advanceDelegation(
    rust_wire.NextStepView step,
    rust_session.ApiRoundHostContext host,
    rust_session.ApiDelegationSignerInput? signer,
  ) async* {
    final bundleIndex = step.bundleIndex;
    final hotkey = storedHotkeySecret;
    if (signer == null) {
      throw StateError('delegation step requires a signer');
    }
    if (hotkey == null) {
      throw StateError('delegation step requires a stored hotkey');
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
          throw StateError(
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
      throw StateError('delegation proof stream ended without a payload');
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
    yield await _result(
      step,
      disposition,
      chainOutcome: outcome,
      delegation: submission,
    );
  }

  Stream<_ScriptedStepEvent> _advanceVote(
    rust_wire.NextStepView step,
    rust_session.ApiRoundHostContext host,
  ) async* {
    final bundleIndex = step.bundleIndex;
    final ceremonyStart = host.ceremonyStartSeconds;
    final voteEnd = host.voteEndTimeSeconds;
    if (step.kind == rust_wire.NextStepKind.castVote) {
      final hotkey = storedHotkeySecret;
      if (hotkey == null) {
        throw StateError('cast-vote step requires a stored hotkey');
      }
      final singleShare =
          ceremonyStart != null &&
          voteEnd != null &&
          _api.isLastMoment(
            nowSeconds: host.nowSeconds,
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
        final anchorHeight = await _syncVoteTree(host.voteTreeNodeUrls);
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
          maxProofConcurrency: host.maxProofConcurrency,
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

    final context = _api.createVotingHelperDeliveryContext(
      dbPath: ctx.dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );
    try {
      final lastMomentBuffer = ceremonyStart == null || voteEnd == null
          ? null
          : _api.lastMomentBufferSeconds(
              ceremonyStartSeconds: ceremonyStart,
              voteEndTimeSeconds: voteEnd,
            );
      final preflight = await _steps.preflightVotingHelpers(
        context: context,
        configuredHelperUrls: host.configuredHelperUrls,
      );
      for (final proposalId in proposalIds) {
        await _steps.prepareCommittedShareDelivery(
          context: context,
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          preflight: preflight,
          nowSeconds: host.nowSeconds,
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
          context: context,
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          configuredHelperUrls: host.configuredHelperUrls,
          nowSeconds: host.nowSeconds,
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
    } finally {
      context.dispose();
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
      throw StateError('cast vote requires at least one vote-tree node URL');
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

  _ScriptedStepEvent _progress(
    rust_wire.RoundStepProgressView progress,
  ) {
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
    required rust_session.ApiRoundHostContext host,
    rust_session.ApiDelegationSignerInput? signer,
    rust_session.ApiRoundDrivePolicy? policy,
  }) async* {
    if (driver.scriptedRoundRuns.isNotEmpty) {
      for (final event in driver.scriptedRoundRuns.removeAt(0)) {
        yield event;
      }
      return;
    }
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
          signer?.kind ==
              rust_session.ApiDelegationSignerKind.keystoneStored) {
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
        host: host,
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
            await _plan(),
            failures,
            skipped,
            chainOutcomes,
            shareDeliveries,
          );
          return;
        case rust_wire.RoundStepDispositionView.cancelled:
          yield _runReport(
            _quiescence(rust_wire.RoundQuiescenceKind.cancelled),
            await _plan(),
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
            await _plan(),
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
        return _quiescence(rust_wire.RoundQuiescenceKind.persistedChainTerminal);
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

  rust_wire.RoundWorkTallyView _tally(rust_wire.RoundPlanView plan) {
    final proposals = <int>{
      for (final step in plan.nextSteps)
        if (step.kind != rust_wire.NextStepKind.delegate &&
            step.kind != rust_wire.NextStepKind.advanceDelegation)
          step.proposalId,
    };
    return rust_wire.RoundWorkTallyView(
      completedProposals: 0,
      totalProposals: proposals.length,
      remainingObligations: plan.nextSteps.length,
    );
  }

  rust_session.ApiRoundRunEvent _runEvent(rust_wire.RoundDriveEventView event) =>
      rust_session.ApiRoundRunEvent(
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

  @override
  VotingShareTrackingPassHandle beginShareTrackingPass() {
    return _api.beginShareTrackingPass(
      context: _api.createVotingHelperDeliveryContext(
        dbPath: ctx.dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
      ),
    );
  }
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
