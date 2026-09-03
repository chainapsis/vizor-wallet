import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;

import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_api;
import 'package:zcash_wallet/src/rust/api/voting_session.dart' as rust_session;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/delegate.dart'
    as rust_delegate;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import 'round_plan_test_utils.dart';

/// State a scripted `VotingRustApi` fake exposes so [FakeVotingRoundSession]
/// can mirror the SDK executor on top of it.
abstract interface class FakeRoundSessionDriver {
  VotingRustApi get api;

  /// Bundle count the planner sees, from recovery state when present.
  int get planBundleCount;

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

  List<String> get roundSessionSteps;

  List<String> get sessionBallotIntents;
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
  final Set<String> _recoveredKeys = {};
  final Set<VotingChainSubmissionPassHandle> _passHandles = {};
  final Completer<void> _cancelled = Completer<void>();
  bool isCancelled = false;
  @override
  bool isDisposed = false;

  VotingRustApi get _api => driver.api;

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
  Future<rust_wire.RoundPlanView> setBallotIntents(
    List<rust_session.ApiBallotIntent> intents,
  ) async {
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

  Future<rust_wire.RoundPlanView> _plan() async {
    final base = await driver.peekRoundPlan(
      roundId: roundId,
      proposalIds: _rosterIds,
    );
    final steps = <rust_wire.NextStepView>[];
    final seen = <String>{};
    for (final step in base?.nextSteps ?? const <rust_wire.NextStepView>[]) {
      if (!_isVoteStep(step)) {
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
      allDecided: base?.allDecided ?? false,
      hotkeyBound: base?.hotkeyBound ?? false,
      completedVoteArtifact: base?.completedVoteArtifact ?? false,
      needsDraftSetup: base?.needsDraftSetup,
      delegationStatuses: base?.delegationStatuses ?? const [],
      immediateShareKey: base?.immediateShareKey,
      immediateShareConfirmed: base?.immediateShareConfirmed ?? false,
    );
  }

  @override
  Stream<rust_session.ApiRoundStepEvent> advanceStep({
    required rust_wire.NextStepView step,
    required rust_session.ApiRoundHostContext host,
    rust_session.ApiDelegationSignerInput? signer,
  }) async* {
    driver.roundSessionSteps.add('${step.kind.name}:${step.bundleIndex}');
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

  Stream<rust_session.ApiRoundStepEvent> _advanceDelegation(
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
        events = _api.buildProveAndSignDelegationPayloadWithProgress(
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
        events = _api
            .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
              ctx: ctx,
              pirServerUrls: pirServerUrls,
              storedHotkeySecret: hotkey,
              bundleIndex: bundleIndex,
              keystoneSig: record.sig,
              keystoneSighash: record.sighash,
            );
      case rust_session.ApiDelegationSignerKind.keystoneProvided:
        events = _api
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
      (passHandle, recoveryMode) => _api.advanceChainDelegation(
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
    yield await _result(
      step,
      _dispositionFor(outcome),
      chainOutcome: outcome,
      delegation: submission,
    );
  }

  Stream<rust_session.ApiRoundStepEvent> _advanceVote(
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
      final drafts = <rust_wire.DraftVote>[
        for (final planned in plan.nextSteps)
          if (planned.kind == rust_wire.NextStepKind.castVote &&
              planned.bundleIndex == bundleIndex)
            rust_wire.DraftVote(
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
              vcTreePosition: BigInt.zero,
              singleShare: singleShare,
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
        final witness = await _api.generateVanWitness(
          dbPath: ctx.dbPath,
          accountUuid: accountUuid,
          roundId: roundId,
          bundleIndex: bundleIndex,
          anchorHeight: anchorHeight,
        );
        await for (final event in _api.buildVoteCommitmentsWithProgress(
          dbPath: ctx.dbPath,
          accountUuid: accountUuid,
          network: ctx.network,
          roundId: roundId,
          bundleIndex: bundleIndex,
          storedHotkeySecret: hotkey,
          vanWitness: witness,
          draftVotes: drafts,
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
      await _api.recoverVoteCommitment(
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
      final preflight = await _api.preflightVotingHelpers(
        context: context,
        configuredHelperUrls: host.configuredHelperUrls,
      );
      for (final proposalId in proposalIds) {
        await _api.prepareCommittedShareDelivery(
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
              ? _api.advanceChainVoteBatch(
                  passHandle: passHandle,
                  bundleIndex: bundleIndex,
                  proposalId: proposalIds.first,
                  recoveryMode: recoveryMode,
                )
              : _api.advanceChainVote(
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
        final delivery = await _api.submitPreparedSharesToHelpers(
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
      VotingChainSubmissionPassHandle passHandle,
      rust_api.ApiChainRecoveryMode recoveryMode,
    )
    advance,
  ) async {
    final passHandle = _api.beginChainSubmissionPass(
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

  rust_session.ApiRoundStepEvent _progress(
    rust_wire.RoundStepProgressView progress,
  ) {
    return rust_session.ApiRoundStepEvent(
      kind: rust_session.ApiRoundStepEventKind.progress,
      progress: progress,
      outcome: null,
      failure: null,
    );
  }

  Future<rust_session.ApiRoundStepEvent> _result(
    rust_wire.NextStepView step,
    rust_wire.RoundStepDispositionView disposition, {
    rust_api.ApiChainSubmissionOutcome? chainOutcome,
    List<rust_wire.ShareBatchDeliveryReportView> shareDeliveries = const [],
    rust_wire.SignedDelegationPayloadView? delegation,
  }) async {
    return rust_session.ApiRoundStepEvent(
      kind: rust_session.ApiRoundStepEventKind.result,
      progress: null,
      outcome: rust_wire.RoundStepOutcomeView(
        step: step,
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

  Future<rust_session.ApiRoundStepEvent> _failure(
    rust_wire.NextStepView step, {
    required rust_wire.RoundStepFailureKindView kind,
    required String message,
    rust_wire.ChainSubmissionFailureStateView? strongestChainState,
  }) async {
    return rust_session.ApiRoundStepEvent(
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
      ),
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
