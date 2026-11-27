import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_message.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_proxy_job_restorer_provider.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegator.dart'
    as rust_delegator;
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/delegate.dart'
    as rust_delegate;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/share_policy.dart'
    as rust_share_policy;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import '../../features/voting/round_plan_test_utils.dart';
import '../../features/voting/proxy/support/proxy_values.dart';

const _roundId =
    'abababababababababababababababababababababababababababababababab';
const _key = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');

/// The round's vote end, in unix seconds.
const _voteEndSeconds = 1792000000;
final _voteEnd = DateTime.fromMillisecondsSinceEpoch(_voteEndSeconds * 1000);

/// A plan owing proxy work on bundle 0: [steps], with bundle 0's
/// registration confirmed so no proof of it is due.
rust_wire.RoundPlanView _proxyPlan(
  List<rust_wire.NextStepView> steps, {
  Set<int> signing = const {},
}) => apiRoundPlan(
  roundId: _roundId,
  pendingRecovery: false,
  nextSteps: steps,
  openProposals: Uint32List(0),
  allDecided: true,
  hasUnconfirmedShares: false,
  recoveredVoteWork: const [],
  delegationStatuses: const [
    rust_wire.DelegationStatusView(
      bundleIndex: 0,
      phase: rust_wire.WorkflowPhaseView.confirmed,
      terminal: false,
    ),
  ],
  proxySigningBundles: signing,
);

/// A DC share delivery step for slot 0 of bundle 0.
const _dcShare = rust_wire.NextStepView(
  kind: rust_wire.NextStepKind.submitShares,
  bundleIndex: 0,
  proposalId: 0,
  choice: 0,
  shareIndex: 3,
  dcSlot: 0,
);

/// Bundle 0's batch submission.
const _advanceBatch = rust_wire.NextStepView(
  kind: rust_wire.NextStepKind.advanceProxyBatch,
  bundleIndex: 0,
  proposalId: 0,
  choice: 0,
  shareIndex: 0,
);

/// Bundle 1's delegation, which a hardware account still has to sign.
const _delegateBundle1 = rust_wire.NextStepView(
  kind: rust_wire.NextStepKind.delegate,
  bundleIndex: 1,
  proposalId: 0,
  choice: 0,
  shareIndex: 0,
);

/// The Ledger request a hardware account is shown for [bundle].
rust_delegate.KeystoneSigningRequest _ledgerRequest(int bundle) =>
    rust_delegate.KeystoneSigningRequest(
      pcztBytes: Uint8List(1),
      redactedPcztBytes: Uint8List(1),
      pcztSighash: Uint8List(32),
      rk: Uint8List(32),
      actionIndex: 0,
      displayMemo: 'Proxy round',
      eligibleWeightZatoshi: BigInt.from(100000000),
      delegatedWeightZatoshi: BigInt.from(50000000),
      bundleCount: 2,
      bundleIndex: bundle,
    );

/// The session state of a one-question round ending at [_voteEnd], with
/// [plan], signed by [signer] (a software account when null).
VotingSessionState _sessionState(
  rust_wire.RoundPlanView plan, {
  HardwareSignerKind? signer,
  bool eligible = true,
  List<rust_delegate.KeystoneSigningRequest> ledgerRequests = const [],
}) => VotingSessionState(
  roundId: _roundId,
  accountUuid: _key.accountUuid,
  roundPlan: plan,
  isHardwareAccount: signer != null,
  hardwareSignerKind: signer,
  ledgerSigningRequests: ledgerRequests,
  eligibleWeightZatoshi: eligible ? BigInt.from(100000000) : null,
  round: VotingRoundDetails(
    roundId: _roundId,
    title: 'Proxy round',
    status: 'SESSION_STATUS_ACTIVE',
    snapshotHeight: 100,
    eaPk: Uint8List(32),
    ncRoot: Uint8List(32),
    nullifierImtRoot: Uint8List(32),
    rawJson: const {
      'vote_end_time': _voteEndSeconds,
      'proposals': [
        {
          'id': 1,
          'title': 'Question 1',
          'options': [
            {'index': 0, 'label': 'Yes'},
            {'index': 1, 'label': 'No'},
          ],
        },
      ],
    },
  ),
);

/// What every fake session shares: [build] over [currentPlan], [publish],
/// and wallet checks and share tracking that do nothing.
abstract class _FakeSession extends VotingSubmissionSessionNotifier {
  _FakeSession(super.key);

  /// The plan the fake SDK reports now.
  rust_wire.RoundPlanView currentPlan();

  /// The account's hardware signer; null for a software account.
  HardwareSignerKind? get signer;

  @override
  Future<VotingSessionState> build() async =>
      _sessionState(currentPlan(), signer: signer);

  /// Publishes [currentPlan], as the real session does after each run.
  void publish() {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(roundPlan: currentPlan()));
    }
  }

  @override
  Future<void> ensureWalletReadyForVoting() async {}

  @override
  Future<void> ensureVotingEligibility() async {}

  @override
  Future<void> recordBallotIntents({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {}

  @override
  Future<void> startShareTracking() async {}
}

/// Delegate 3's delegation at [stage].
ApiProxyDelegationView _view(ProxyDelegationStage stage) => proxyView(
  delegateIndex: 3,
  handle: 'delegate3',
  ballots: BigInt.from(75),
  stage: stage,
  ballot: proxyBallot(ApiDelegateBallotKind.noBallotYet),
);

/// A progress snapshot with delegate 3 at [stage].
ApiProxyDelegationProgress _progress(
  ProxyDelegationStage stage, {
  bool plannedImmediate = false,
  bool immediateRevealConfirmed = false,
  bool refusedByChain = false,
}) => proxyProgress(
  delegations: [_view(stage)],
  plannedImmediate: plannedImmediate,
  immediateRevealConfirmed: immediateRevealConfirmed,
  refusedByChain: refusedByChain,
);

/// What the fake session and progress reader do, and what they saw.
class _Script {
  _Script({
    required this.plan,
    List<ApiProxyDelegationProgress?> progress = const [],
    this.hardware = false,
    this.ledger = false,
    this.eligible = false,
  }) : progress = [...progress];

  /// The round plan the session reports.
  rust_wire.RoundPlanView plan;

  /// Progress answers, in order; the last repeats.
  final List<ApiProxyDelegationProgress?> progress;

  /// Whether the account signs with a Keystone.
  final bool hardware;

  /// Whether the account signs with a Ledger, which then has one bundle's
  /// delegation to sign.
  final bool ledger;

  /// Whether the session starts with confirmed voting eligibility.
  final bool eligible;

  /// Thrown by the next casts, when set.
  Object? castError;

  /// The plan recording the ballot's intents publishes, when set.
  rust_wire.RoundPlanView? planAfterIntents;

  /// The stored ballot choices, by proposal.
  Map<int, int> draft = const {};

  /// How far each clock read moves [now]; zero keeps it still.
  Duration clockStep = Duration.zero;

  /// Reads [now], then moves it by [clockStep].
  DateTime readClock() {
    final read = now;
    now = now.add(clockStep);
    return read;
  }

  /// How often the vote flow cast or recorded a ballot.
  int ballotCalls = 0;

  /// Outcomes of successive drives; an empty list drives cleanly.
  final outcomes = <VotingProxyDriveOutcome>[];

  /// The signer each drive was given.
  final drives = <({String? mnemonic, HardwareSignerKind? hardwareSigner})>[];

  /// How often hardware signing was prepared.
  int signingPrepared = 0;

  /// Steps each drive reports finished.
  int stepsPerDrive = 0;

  /// How often the job read progress.
  int progressReads = 0;

  /// Errors successive drives throw before driving, in order.
  final driveErrors = <Object>[];

  /// How many progress reads fail before one answers.
  int failedProgressReads = 0;

  /// How often the job ran its final DC share 0 check after `vote_end`.
  int finalChecks = 0;

  /// The progress every read answers once the final check ran, when set.
  ApiProxyDelegationProgress? progressAfterFinalCheck;

  /// The clock the job reads.
  DateTime now = _voteEnd.subtract(const Duration(days: 1));

  /// The next progress answer.
  ApiProxyDelegationProgress? nextProgress() {
    progressReads++;
    if (failedProgressReads > 0) {
      failedProgressReads--;
      throw const SocketException('vote server down');
    }
    return progress.isEmpty
        ? null
        : progress.length == 1
        ? progress.single
        : progress.removeAt(0);
  }
}

/// A submission session that drives proxy work by the script.
class _ProxySession extends _FakeSession {
  _ProxySession(super.key, this.script);

  final _Script script;

  @override
  rust_wire.RoundPlanView currentPlan() => script.plan;

  @override
  HardwareSignerKind? get signer => script.ledger
      ? HardwareSignerKind.ledger
      : script.hardware
      ? HardwareSignerKind.keystone
      : null;

  @override
  Future<VotingSessionState> build() async => _sessionState(
    script.plan,
    signer: signer,
    eligible: script.eligible,
    ledgerRequests: script.ledger ? [_ledgerRequest(1)] : const [],
  );

  @override
  Future<VotingProxyDriveOutcome> driveProxyDelegation({
    String? mnemonic,
    HardwareSignerKind? hardwareSigner,
    void Function()? onStepFinished,
  }) async {
    script.drives.add((mnemonic: mnemonic, hardwareSigner: hardwareSigner));
    if (script.driveErrors.isNotEmpty) throw script.driveErrors.removeAt(0);
    for (var i = 0; i < script.stepsPerDrive; i++) {
      onStepFinished?.call();
      await Future<void>.delayed(Duration.zero);
    }
    publish();
    return script.outcomes.isEmpty
        ? const VotingProxyDriveOutcome()
        : script.outcomes.removeAt(0);
  }

  @override
  Future<void> prepareKeystoneSigning({
    Iterable<int> alsoSign = const [],
  }) async => script.signingPrepared++;

  @override
  Future<void> castVotes({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {
    script.ballotCalls++;
    if (script.castError case final error?) throw error;
  }

  @override
  Future<void> prepareLedgerSigning({
    Iterable<int> alsoSign = const [],
  }) async {}

  @override
  Future<void> recordBallotIntents({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {
    script.ballotCalls++;
    final plan = script.planAfterIntents;
    final current = state.value;
    if (plan != null && current != null) {
      state = AsyncData(current.copyWith(roundPlan: plan));
    }
  }

  @override
  Future<bool> refreshImmediateShareConfirmation() async => false;

  @override
  Future<void> refreshDcShareZeroConfirmations() async {
    script.finalChecks++;
    if (script.progressAfterFinalCheck case final confirmed?) {
      script.progress
        ..clear()
        ..add(confirmed);
    }
  }
}

/// A proxy job waiting for a Keystone signature.
class _SigningProxyJob extends VotingSubmissionJobNotifier {
  _SigningProxyJob(super.key);

  @override
  VotingSubmissionJobState build() => const VotingSubmissionJobState(
    key: _key,
    status: VotingSubmissionJobStatus.waitingForKeystone,
    kind: VotingSubmissionJobKind.proxy,
    proxyStage: ProxyJobStage.signing,
  );
}

/// A ballot draft store holding [choices].
class _Drafts implements VotingDraftPersistence {
  _Drafts([this.choices = const {}]);

  /// The stored choices, by proposal.
  final Map<int, int> choices;

  @override
  Future<VotingDraftState> load(VotingSessionKey key) async =>
      VotingDraftState(choices: choices);

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {}

  @override
  Future<void> deleteForAccount(String accountUuid) async {}
}

/// An unlocked wallet.
class _Unlocked extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

/// Where the held-cast SDK's one proxy batch stands.
enum _Batch { planned, proved, dispatched, landed }

/// The SDK as a delegation meets it: bundle 0 carries one proxy batch whose
/// first attempt signs the registration, and, with [keptShare], the kept
/// share's casts for proposal 1, held until the batch lands.
/// Every round run is whole-round, like the SDK's: it proves the batch,
/// sends it only with a signer, tracks it, then casts once intents are
/// durable.
class _HeldCastSdk {
  _HeldCastSdk({this.pendingPasses = 1, this.keptShare = true});

  /// Passes over a dispatched batch that report it still pending.
  int pendingPasses;

  /// Whether the wallet kept a share to answer; without one the delegates
  /// took the whole bundle.
  final bool keptShare;

  _Batch batch = _Batch.planned;

  /// Whether the chain refuses a dispatched batch.
  bool refused = false;

  /// Whether the ballot's intents are durable.
  bool intents = false;

  /// Whether the kept share's vote and its shares exist.
  bool cast = false;

  /// Whether the designated immediate share is confirmed.
  bool confirmed = false;

  /// Whether a Keystone signature for the registration is stored.
  bool signatureStored = false;

  /// What happened, in order.
  final log = <String>[];

  /// One round run, with or without the account's signer, and why it
  /// stopped short.
  rust_wire.RoundQuiescenceKind? run({required bool signer}) {
    if (batch == _Batch.planned) {
      batch = _Batch.proved;
      log.add('prove');
    }
    if (batch == _Batch.proved) {
      if (!signer) {
        return rust_wire.RoundQuiescenceKind.needsDelegationSignatures;
      }
      batch = _Batch.dispatched;
      log.add('broadcast');
    }
    if (batch == _Batch.dispatched) {
      if (refused) return null;
      if (pendingPasses > 0) {
        pendingPasses--;
        return null;
      }
      batch = _Batch.landed;
      log.add('land');
    }
    if (keptShare && intents && !cast) {
      cast = true;
      log.add('cast');
    }
    return null;
  }

  /// Confirms the immediate share, which the SDK refuses as invalid input
  /// while no such share exists.
  bool confirmImmediateShare() {
    if (!cast) {
      log.add('confirm unknown share');
      throw StateError(
        'Invalid input: helper share not found: round=$_roundId, bundle=0, '
        'proposal=1, share=0',
      );
    }
    confirmed = true;
    log.add('confirm');
    return true;
  }

  /// The plan the SDK reports now.
  rust_wire.RoundPlanView plan() {
    final resolved = batch == _Batch.landed;
    final steps = [
      if (batch == _Batch.planned)
        const rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.proxyDelegate,
          bundleIndex: 0,
          proposalId: 0,
          choice: 0,
          shareIndex: 0,
        ),
      if (batch == _Batch.proved || batch == _Batch.dispatched) _advanceBatch,
      if (keptShare && resolved && intents && !cast)
        const rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.castVote,
          bundleIndex: 0,
          proposalId: 1,
          choice: 0,
          shareIndex: 0,
        ),
      if (cast && !confirmed)
        const rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.confirmShare,
          bundleIndex: 0,
          proposalId: 1,
          choice: 0,
          shareIndex: 0,
        ),
    ];
    return apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: steps.isNotEmpty,
      nextSteps: steps,
      openProposals: intents || !keptShare
          ? Uint32List(0)
          : Uint32List.fromList(const [1]),
      allDecided: cast,
      needsDraftSetup: false,
      hasUnconfirmedShares: cast && !confirmed,
      completedVoteArtifact: cast,
      // The SDK derives the designation from the choices before any cast.
      immediateShareKey: keptShare
          ? const rust_share_policy.ImmediateShareKey(
              bundleIndex: 0,
              proposalId: 1,
              shareIndex: 0,
            )
          : null,
      immediateShareConfirmed: confirmed,
      delegationStatuses: [
        rust_wire.DelegationStatusView(
          bundleIndex: 0,
          phase: resolved
              ? rust_wire.WorkflowPhaseView.confirmed
              : rust_wire.WorkflowPhaseView.prepared,
          terminal: false,
        ),
      ],
      proxySigningBundles: batch == _Batch.proved ? const {0} : const {},
      fullyDelegatedBundles: keptShare ? const [] : const [0],
      nothingLeftToVote: !keptShare,
    );
  }

  /// The delegation's progress as zcash_voting reports it.
  ApiProxyDelegationProgress progress() => _progress(switch (batch) {
    _Batch.planned || _Batch.proved => ProxyDelegationStage.preparing,
    _Batch.dispatched => ProxyDelegationStage.submitting,
    _Batch.landed => ProxyDelegationStage.handedOff,
  }, refusedByChain: batch == _Batch.dispatched && refused);
}

/// A submission session over [_HeldCastSdk].
class _HeldCastSession extends _FakeSession {
  _HeldCastSession(super.key, this.sdk, {required this.keystone});

  final _HeldCastSdk sdk;

  /// Whether the account signs with a Keystone.
  final bool keystone;

  /// The signer each proxy drive was given.
  final drives = <({String? mnemonic, HardwareSignerKind? hardwareSigner})>[];

  @override
  rust_wire.RoundPlanView currentPlan() => sdk.plan();

  @override
  HardwareSignerKind? get signer =>
      keystone ? HardwareSignerKind.keystone : null;

  /// Whether a run given [mnemonic] or [hardware] can sign.
  bool _signs({String? mnemonic, bool hardware = false}) =>
      mnemonic != null || (hardware && sdk.signatureStored);

  @override
  Future<VotingProxyDriveOutcome> driveProxyDelegation({
    String? mnemonic,
    HardwareSignerKind? hardwareSigner,
    void Function()? onStepFinished,
  }) async {
    drives.add((mnemonic: mnemonic, hardwareSigner: hardwareSigner));
    final stopped = sdk.run(
      signer: _signs(mnemonic: mnemonic, hardware: hardwareSigner != null),
    );
    publish();
    return VotingProxyDriveOutcome(
      quiescence: stopped,
      chainPending: sdk.batch == _Batch.dispatched,
    );
  }

  @override
  Future<void> delegatePendingBundles({String? mnemonic}) async {
    sdk.run(signer: _signs(mnemonic: mnemonic));
    publish();
  }

  @override
  Future<void> delegatePendingBundlesWithKeystoneSignatures() async {
    sdk.run(signer: _signs(hardware: true));
    publish();
  }

  @override
  Future<void> prepareKeystoneSigning({
    Iterable<int> alsoSign = const [],
  }) async {
    sdk.signatureStored = true;
    sdk.log.add('keystone signature');
  }

  @override
  Future<void> recordBallotIntents({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {
    sdk.intents = true;
    publish();
  }

  /// Records the intents and runs the round without a signer, as the real
  /// casts do.
  @override
  Future<void> castVotes({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {
    sdk.intents = true;
    sdk.run(signer: false);
    publish();
  }

  @override
  Future<bool> refreshImmediateShareConfirmation() async {
    final confirmed = sdk.confirmImmediateShare();
    publish();
    return confirmed;
  }
}

/// The SDK for a two-bundle wallet whose delegation took bundle 0 whole and
/// kept bundle 1 for its own answer. Bundle 0's proxy batch signs the
/// registration; bundle 1's first cast, planned once the ballot's intents
/// are durable, signs bundle 1's delegation. A run with the device's signer
/// uses only the signatures stored for each bundle.
class _KeptBundleSdk {
  _Batch batch = _Batch.planned;

  /// Whether the ballot's intents are durable.
  bool intents = false;

  /// Whether bundle 1's vote is cast.
  bool cast = false;

  /// Whether the designated immediate share is confirmed.
  bool confirmed = false;

  /// Bundles whose device signature is stored.
  final signed = <int>{};

  /// What happened, in order.
  final log = <String>[];

  /// Bundles the plan lists as needing a signature now.
  Set<int> get planSigning => {
    if (batch == _Batch.proved) 0,
    if (intents && !cast) 1,
  };

  /// One whole-round run; [hardware] signs only with stored signatures.
  /// Returns why it stopped short.
  rust_wire.RoundQuiescenceKind? run({
    required bool signer,
    bool hardware = false,
  }) {
    bool signs(int bundle) => signer && (!hardware || signed.contains(bundle));
    if (batch == _Batch.planned) {
      batch = _Batch.proved;
      log.add('prove');
    }
    if (batch == _Batch.proved) {
      if (!signs(0)) {
        return rust_wire.RoundQuiescenceKind.needsDelegationSignatures;
      }
      batch = _Batch.dispatched;
      log.add('broadcast');
    }
    if (batch == _Batch.dispatched) {
      batch = _Batch.landed;
      log.add('land');
    }
    if (intents && !cast) {
      if (!signs(1)) {
        return rust_wire.RoundQuiescenceKind.needsDelegationSignatures;
      }
      cast = true;
      log.add('cast');
    }
    return null;
  }

  /// The plan the SDK reports now.
  rust_wire.RoundPlanView plan() {
    final steps = [
      if (batch == _Batch.planned)
        const rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.proxyDelegate,
          bundleIndex: 0,
          proposalId: 0,
          choice: 0,
          shareIndex: 0,
        ),
      if (batch == _Batch.proved || batch == _Batch.dispatched) _advanceBatch,
      if (intents && !cast)
        const rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.castVote,
          bundleIndex: 1,
          proposalId: 1,
          choice: 0,
          shareIndex: 0,
        ),
    ];
    rust_wire.DelegationStatusView status(int bundle, bool done) =>
        rust_wire.DelegationStatusView(
          bundleIndex: bundle,
          phase: done
              ? rust_wire.WorkflowPhaseView.confirmed
              : rust_wire.WorkflowPhaseView.prepared,
          terminal: false,
        );
    return apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: steps.isNotEmpty,
      nextSteps: steps,
      openProposals: intents || cast
          ? Uint32List(0)
          : Uint32List.fromList(const [1]),
      allDecided: intents || cast,
      hasUnconfirmedShares: cast && !confirmed,
      completedVoteArtifact: cast,
      immediateShareKey: const rust_share_policy.ImmediateShareKey(
        bundleIndex: 1,
        proposalId: 1,
        shareIndex: 0,
      ),
      immediateShareConfirmed: confirmed,
      delegationStatuses: [status(0, batch == _Batch.landed), status(1, cast)],
      proxySigningBundles: batch == _Batch.proved ? const {0} : const {},
      castSigningBundles: intents && !cast ? const {1} : const {},
      fullyDelegatedBundles: const [0],
    );
  }

  /// The delegation's progress as zcash_voting reports it.
  ApiProxyDelegationProgress progress() => _progress(switch (batch) {
    _Batch.landed => ProxyDelegationStage.handedOff,
    _Batch.dispatched => ProxyDelegationStage.submitting,
    _ => ProxyDelegationStage.preparing,
  });
}

/// A hardware account's session over [_KeptBundleSdk]: a Keystone signs
/// every requested bundle in one scan, a Ledger approves one bundle at a
/// time.
class _KeptBundleSession extends _FakeSession {
  _KeptBundleSession(super.key, this.sdk, {required this.ledger});

  final _KeptBundleSdk sdk;

  /// Whether the account signs with a Ledger rather than a Keystone.
  final bool ledger;

  @override
  rust_wire.RoundPlanView currentPlan() => sdk.plan();

  @override
  HardwareSignerKind? get signer =>
      ledger ? HardwareSignerKind.ledger : HardwareSignerKind.keystone;

  /// Publishes the SDK's current plan with Ledger requests for [bundles].
  void _publishLedgerRequests(List<int> bundles) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        roundPlan: sdk.plan(),
        ledgerSigningRequests: [
          for (final bundle in bundles) _ledgerRequest(bundle),
        ],
      ),
    );
  }

  /// The bundles a signing round asks for: the plan's and [alsoSign], less
  /// those already signed.
  List<int> _unsigned(Iterable<int> alsoSign) =>
      ({...sdk.planSigning, ...alsoSign}..removeAll(sdk.signed)).toList()
        ..sort();

  @override
  Future<VotingProxyDriveOutcome> driveProxyDelegation({
    String? mnemonic,
    HardwareSignerKind? hardwareSigner,
    void Function()? onStepFinished,
  }) async {
    final stopped = sdk.run(signer: hardwareSigner != null, hardware: true);
    publish();
    return VotingProxyDriveOutcome(quiescence: stopped);
  }

  @override
  Future<void> prepareKeystoneSigning({
    Iterable<int> alsoSign = const [],
  }) async {
    final bundles = _unsigned(alsoSign);
    if (bundles.isEmpty) return;
    sdk.signed.addAll(bundles);
    sdk.log.add('keystone scan $bundles');
  }

  @override
  Future<void> prepareLedgerSigning({Iterable<int> alsoSign = const []}) async {
    _publishLedgerRequests(_unsigned(alsoSign));
  }

  @override
  Future<void> handleLedgerSignatures(
    List<LedgerVotingSignature> signatures,
  ) async {
    final requests = state.value!.ledgerSigningRequests;
    final bundle = requests.first.bundleIndex;
    sdk.signed.add(bundle);
    sdk.log.add('ledger approval $bundle');
    _publishLedgerRequests([
      for (final request in requests.skip(1)) request.bundleIndex,
    ]);
  }

  @override
  Future<void> delegatePendingBundlesWithKeystoneSignatures() async {
    sdk.run(signer: true, hardware: true);
    publish();
  }

  @override
  Future<void> delegatePendingBundlesWithLedgerSignatures() async {
    sdk.run(signer: true, hardware: true);
    publish();
  }

  @override
  Future<void> recordBallotIntents({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {
    sdk.intents = true;
    publish();
  }

  bool _awaiting = false;

  @override
  bool get castsAwaitSignatures => _awaiting;

  @override
  Future<void> castVotes({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {
    sdk.intents = true;
    _awaiting = sdk.run(signer: false) != null;
    publish();
  }

  @override
  Future<bool> refreshImmediateShareConfirmation() async {
    if (!sdk.cast) return false;
    sdk.confirmed = true;
    sdk.log.add('confirm');
    publish();
    return true;
  }
}

/// A session whose kept share's cast signs its bundle's delegation, as a
/// bundle with no proxy batch does: a signerless cast stops for the
/// signature, and a run with the signer casts unless [signerCasts] is
/// false. The plan reports the signature only once a cast stopped for it.
class _SigningCastSession extends _FakeSession {
  _SigningCastSession(
    super.key, {
    required this.keystone,
    this.signerCasts = true,
  });

  /// Whether the account signs with a Keystone.
  final bool keystone;

  /// Whether a run with the signer casts.
  final bool signerCasts;

  /// Whether the plan reports the cast's signature yet.
  bool signingKnown = false;

  /// Whether a Keystone signature for the bundle is stored.
  bool signatureStored = false;

  /// Whether the kept share is cast.
  bool cast = false;

  bool _awaiting = false;

  /// What happened, in order.
  final log = <String>[];

  @override
  bool get castsAwaitSignatures => _awaiting;

  @override
  HardwareSignerKind? get signer =>
      keystone ? HardwareSignerKind.keystone : null;

  @override
  rust_wire.RoundPlanView currentPlan() => apiRoundPlan(
    roundId: _roundId,
    pendingRecovery: !cast,
    nextSteps: [
      if (!cast)
        const rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.castVote,
          bundleIndex: 0,
          proposalId: 1,
          choice: 0,
          shareIndex: 0,
        ),
    ],
    openProposals: Uint32List(0),
    allDecided: true,
    hasUnconfirmedShares: false,
    completedVoteArtifact: cast,
    delegationStatuses: [
      rust_wire.DelegationStatusView(
        bundleIndex: 0,
        phase: cast
            ? rust_wire.WorkflowPhaseView.confirmed
            : rust_wire.WorkflowPhaseView.prepared,
        terminal: false,
      ),
    ],
    castSigningBundles: signingKnown && !cast ? const {0} : const {},
  );

  /// A run with a signer casts, when it can.
  void _castWithSigner(String entry) {
    if (signerCasts) {
      cast = true;
      log.add(entry);
    }
    publish();
  }

  @override
  Future<void> castVotes({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async {
    _awaiting = !cast;
    if (_awaiting) {
      signingKnown = true;
      log.add('cast stopped for signature');
    }
    publish();
  }

  @override
  Future<void> delegatePendingBundles({String? mnemonic}) async {
    if (mnemonic != null) _castWithSigner('cast with seed');
  }

  @override
  Future<void> prepareKeystoneSigning({
    Iterable<int> alsoSign = const [],
  }) async {
    signatureStored = true;
    log.add('keystone signature');
  }

  @override
  Future<void> delegatePendingBundlesWithKeystoneSignatures() async {
    if (signatureStored) _castWithSigner('cast with keystone signature');
  }

  @override
  Future<bool> refreshImmediateShareConfirmation() async => true;
}

/// An account list whose one software account holds a mnemonic.
class _SoftwareAccount extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: 'account-1',
  );

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async => const SoftwareWalletSecret(mnemonic: 'test mnemonic');
}

/// A container whose job for [_key] submits [draft] through [session],
/// pacing proxy cycles by [delays].
ProviderContainer _heldCastContainer(
  _HeldCastSession session, {
  Map<int, int> draft = const {1: 0},
  ProxyJobCycleDelays delays = _sessionDelays,
}) => _sessionContainer(
  session,
  draft: draft,
  progress: (_) async => session.sdk.progress(),
  delays: delays,
);

/// The pacing [_sessionContainer] uses unless told otherwise.
const _sessionDelays = ProxyJobCycleDelays(
  working: Duration(milliseconds: 1),
  waiting: Duration(hours: 1),
  retry: Duration(milliseconds: 1),
);

/// A container whose job for [_key] submits [draft] through [session],
/// reading delegation progress from [progress] and pacing proxy cycles by
/// [delays].
ProviderContainer _sessionContainer(
  VotingSubmissionSessionNotifier session, {
  Map<int, int> draft = const {1: 0},
  ProxyJobProgressReader? progress,
  ProxyJobCycleDelays delays = _sessionDelays,
  List<Override> extra = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      votingActiveAccountUuidProvider.overrideWithValue(
        () async => _key.accountUuid,
      ),
      accountProvider.overrideWith(_SoftwareAccount.new),
      votingSubmissionSessionProvider(_key).overrideWith(() => session),
      proxyJobProgressReaderProvider.overrideWithValue(
        progress ?? (_) async => null,
      ),
      proxyJobCycleDelaysProvider.overrideWithValue(delays),
      votingSubmissionJobClockProvider.overrideWithValue(
        () => _voteEnd.subtract(const Duration(days: 1)),
      ),
      votingDraftPersistenceProvider.overrideWithValue(_Drafts(draft)),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A container whose job for [_key] runs on [script], pacing cycles by
/// [delays].
ProviderContainer _container(
  _Script script, {
  ProxyJobCycleDelays delays = const ProxyJobCycleDelays(
    working: Duration(milliseconds: 1),
    waiting: Duration(hours: 1),
    retry: Duration(milliseconds: 1),
  ),
}) {
  final container = ProviderContainer(
    overrides: [
      votingActiveAccountUuidProvider.overrideWithValue(
        () async => _key.accountUuid,
      ),
      votingSubmissionSessionProvider(
        _key,
      ).overrideWith(() => _ProxySession(_key, script)),
      proxyJobProgressReaderProvider.overrideWithValue(
        (_) async => script.nextProgress(),
      ),
      proxyJobCycleDelaysProvider.overrideWithValue(delays),
      votingSubmissionJobClockProvider.overrideWithValue(script.readClock),
      ledgerVotingPcztSignerProvider.overrideWithValue(
        (_, _) => Completer<List<LedgerVotingSignature>>().future,
      ),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      votingDraftPersistenceProvider.overrideWithValue(_Drafts(script.draft)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Starts the proxy job for [_key].
Future<void> _startProxy(ProviderContainer container) => container
    .read(votingSubmissionJobsProvider.notifier)
    .startProxy(_roundId, accountUuid: _key.accountUuid);

/// Waits until the job state satisfies [done], polling [attempts] times.
Future<VotingSubmissionJobState> _waitFor(
  ProviderContainer container,
  bool Function(VotingSubmissionJobState state) done, {
  int attempts = 200,
}) async {
  for (var i = 0; i < attempts; i++) {
    final state = container.read(votingSubmissionJobProvider(_key));
    if (done(state)) return state;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final last = container.read(votingSubmissionJobProvider(_key));
  fail(
    'Timed out: status ${last.status}, stage ${last.proxyStage}, '
    'error ${last.errorMessage}',
  );
}

/// Waits until [done] holds, polling [attempts] times.
Future<void> _eventually(
  bool Function() done, {
  int attempts = 400,
  String reason = 'condition',
}) async {
  for (var i = 0; i < attempts; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for $reason');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a proxy job completes once every delegation is handed off', () async {
    final script = _Script(
      plan: _proxyPlan([_dcShare]),
      progress: [
        _progress(ProxyDelegationStage.included),
        _progress(ProxyDelegationStage.handedOff),
      ],
    );
    final container = _container(script);

    await _startProxy(container);
    final done = await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );

    expect(done.kind, VotingSubmissionJobKind.proxy);
    expect(done.proxyStage, ProxyJobStage.complete);
    expect(done.terminalReason, isNull);
    expect(
      done.proxyProgress!.delegations.single.stage,
      ProxyDelegationStage.handedOff,
    );
    expect(script.drives, hasLength(greaterThanOrEqualTo(2)));
    expect(
      script.drives.every(
        (drive) => drive.mnemonic == null && drive.hardwareSigner == null,
      ),
      isTrue,
      reason: 'share delivery needs only the round hotkey',
    );
  });

  test('the job reads progress after every finished round step', () async {
    final script = _Script(
      plan: _proxyPlan([_dcShare]),
      progress: [_progress(ProxyDelegationStage.handedOff)],
    )..stepsPerDrive = 3;
    final container = _container(script);

    await _startProxy(container);
    await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );
    expect(script.drives, hasLength(1));
    expect(script.progressReads, 4, reason: 'three steps, then the drive');
  });

  test('completion waits for the confirmed reveal of an in-window DC\'s '
      'share 0', () async {
    final script = _Script(
      plan: _proxyPlan([_dcShare]),
      progress: [
        _progress(ProxyDelegationStage.handedOff, plannedImmediate: true),
        _progress(
          ProxyDelegationStage.handedOff,
          plannedImmediate: true,
          immediateRevealConfirmed: true,
        ),
      ],
    );
    final container = _container(
      script,
      delays: const ProxyJobCycleDelays(
        working: Duration(milliseconds: 100),
        waiting: Duration(hours: 1),
        retry: Duration(hours: 1),
      ),
    );

    await _startProxy(container);
    final waiting = await _waitFor(
      container,
      (state) => state.proxyStage == ProxyJobStage.handingOff,
    );
    expect(waiting.status, VotingSubmissionJobStatus.running);

    final done = await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );
    expect(done.proxyProgress!.immediateRevealConfirmed, isTrue);
  });

  test('a refused batch keeps the job running and resending it at the '
      'waiting cadence until it lands', () async {
    final script = _Script(
      plan: _proxyPlan([_advanceBatch]),
      progress: [
        _progress(ProxyDelegationStage.submitting, refusedByChain: true),
      ],
    );
    final container = _container(
      script,
      delays: const ProxyJobCycleDelays(
        working: Duration(hours: 1),
        waiting: Duration(milliseconds: 20),
        retry: Duration(hours: 1),
      ),
    );

    await _startProxy(container);
    final refused = await _waitFor(
      container,
      (state) => state.proxyStage == ProxyJobStage.refused,
    );
    expect(refused.status, VotingSubmissionJobStatus.running);
    expect(refused.isInFlight, isTrue);
    expect(refused.errorMessage, isNull);
    await _eventually(() => script.drives.length >= 2, reason: 'a resend');

    script.progress
      ..clear()
      ..add(_progress(ProxyDelegationStage.handedOff));
    script.plan = _proxyPlan([_dcShare]);
    await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );
  });

  test('a pass no vote-chain replica can answer yet keeps the job submitting '
      'and retrying, without an error', () async {
    final script = _Script(
      plan: _proxyPlan([_advanceBatch]),
      progress: [_progress(ProxyDelegationStage.submitting)],
    );
    script.outcomes.addAll(const [
      VotingProxyDriveOutcome(chainPending: true),
      VotingProxyDriveOutcome(chainPending: true),
    ]);
    final container = _container(
      script,
      delays: const ProxyJobCycleDelays(
        working: Duration(hours: 1),
        waiting: Duration(hours: 1),
        retry: Duration(milliseconds: 1),
      ),
    );

    await _startProxy(container);
    // Each pending drive is retried at once; the clean third one waits for
    // the next working cycle.
    await _eventually(() => script.drives.length == 3, reason: 'two retries');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(script.drives, hasLength(3));
    final running = container.read(votingSubmissionJobProvider(_key));
    expect(running.status, VotingSubmissionJobStatus.running);
    expect(running.proxyStage, ProxyJobStage.submitting);
    expect(running.errorMessage, isNull);
  });

  test(
    'a round that closed before hand-off ends the job as not counted',
    () async {
      final script = _Script(
        plan: _proxyPlan([_dcShare]),
        progress: [_progress(ProxyDelegationStage.notCounted)],
      );
      final container = _container(script);

      await _startProxy(container);
      final ended = await _waitFor(
        container,
        (state) => state.status == VotingSubmissionJobStatus.error,
      );
      expect(ended.terminalReason, ProxyJobTerminalReason.notCounted);
      expect(ended.proxyStage, ProxyJobStage.notCounted);
      expect(
        ended.errorMessage,
        const VotingNotice(VotingNoticeKind.proxyNotCounted),
      );
      expect(ended.retryable, isFalse);
    },
  );

  test('vote_end fails an unfinished job like an unconfirmed immediate share, '
      'after one last drive', () async {
    final script = _Script(
      plan: _proxyPlan([_dcShare]),
      progress: [_progress(ProxyDelegationStage.included)],
    )..now = _voteEnd.add(const Duration(seconds: 1));
    final container = _container(script);

    await _startProxy(container);
    final ended = await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.error,
    );
    expect(ended.terminalReason, ProxyJobTerminalReason.expired);
    expect(
      ended.errorMessage,
      const VotingNotice(VotingNoticeKind.immediateShareExpired),
    );
    expect(script.drives, hasLength(2));
  });

  test('the final check after vote_end confirms an at-once share 0 tracking '
      'left unconfirmed, and the job completes', () async {
    final unconfirmed = _progress(
      ProxyDelegationStage.handedOff,
      plannedImmediate: true,
    );
    final script =
        _Script(plan: _proxyPlan([_dcShare]), progress: [unconfirmed])
          ..now = _voteEnd.add(const Duration(seconds: 1))
          ..progressAfterFinalCheck = _progress(
            ProxyDelegationStage.handedOff,
            plannedImmediate: true,
            immediateRevealConfirmed: true,
          );
    final container = _container(script);

    await _startProxy(container);
    final done = await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );
    expect(done.proxyStage, ProxyJobStage.complete);
    expect(done.terminalReason, isNull);
    expect(script.finalChecks, 1);
  });

  group('a failed step', () {
    VotingRoundStepFailure failure(rust_wire.RoundStepFailureKindView kind) =>
        VotingRoundStepFailure(
          _dcShare,
          rust_wire.RoundStepFailureView(
            kind: kind,
            message: 'step failed: ${kind.name}',
            shareDeliveries: const [],
          ),
        );

    test('that a later cycle cannot overcome fails the job', () async {
      final script = _Script(
        plan: _proxyPlan([_dcShare]),
        progress: [_progress(ProxyDelegationStage.included)],
      );
      script.outcomes.add(
        VotingProxyDriveOutcome(
          failures: [failure(rust_wire.RoundStepFailureKindView.proofFailed)],
        ),
      );
      final container = _container(script);

      await _startProxy(container);
      final failed = await _waitFor(
        container,
        (state) => state.status == VotingSubmissionJobStatus.error,
      );
      expect(failed.terminalReason, isNull);
      expect(failed.retryable, isTrue);
    });

    test('in transport is retried', () async {
      final script = _Script(
        plan: _proxyPlan([_dcShare]),
        progress: [
          _progress(ProxyDelegationStage.included),
          _progress(ProxyDelegationStage.handedOff),
        ],
      );
      script.outcomes.add(
        VotingProxyDriveOutcome(
          failures: [failure(rust_wire.RoundStepFailureKindView.transport)],
        ),
      );
      final container = _container(script);

      await _startProxy(container);
      await _waitFor(
        container,
        (state) => state.status == VotingSubmissionJobStatus.complete,
      );
      expect(script.drives, hasLength(greaterThanOrEqualTo(2)));
    });

    test('that got no answer, or a progress read that failed, is retried on '
        'the cycle cadence', () async {
      final script = _Script(
        plan: _proxyPlan([_dcShare]),
        progress: [_progress(ProxyDelegationStage.handedOff)],
      );
      script.driveErrors.add(
        TimeoutException('Network HTTP request timed out'),
      );
      script.failedProgressReads = 1;
      final container = _container(script);

      await _startProxy(container);
      await _waitFor(
        container,
        (state) => state.status == VotingSubmissionJobStatus.complete,
      );
      expect(script.drives, hasLength(3));
    });

    test('classification keeps only what no later cycle overcomes', () {
      for (final kind in rust_wire.RoundStepFailureKindView.values) {
        final blocking = proxyJobBlockingFailure([failure(kind)]);
        final retried = {
          rust_wire.RoundStepFailureKindView.transport,
          rust_wire.RoundStepFailureKindView.busy,
          rust_wire.RoundStepFailureKindView.helperDeliveryIncomplete,
          rust_wire.RoundStepFailureKindView.voteEnded,
        }.contains(kind);
        expect(blocking == null, retried, reason: kind.name);
      }
    });
  });

  test('a Keystone account signs through the vote flow\'s signing, then '
      'drives with its stored signatures', () async {
    final script = _Script(
      plan: _proxyPlan([_advanceBatch], signing: {0}),
      progress: [_progress(ProxyDelegationStage.handedOff)],
      hardware: true,
    );
    final container = _container(script);

    await _startProxy(container);
    await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );
    expect(script.signingPrepared, 1);
    expect(script.drives.first.hardwareSigner, HardwareSignerKind.keystone);
    expect(script.drives.first.mnemonic, isNull);
  });

  test('startProxy keeps a finished job and restarts a failed one', () async {
    final script = _Script(
      plan: _proxyPlan([_dcShare]),
      progress: [_progress(ProxyDelegationStage.handedOff)],
    );
    final container = _container(script);
    await _startProxy(container);
    await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );
    final drives = script.drives.length;

    await _startProxy(container);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(script.drives, hasLength(drives));
    expect(
      container.read(votingSubmissionJobProvider(_key)).status,
      VotingSubmissionJobStatus.complete,
    );

    final failing = _Script(
      plan: _proxyPlan([_dcShare]),
      progress: [_progress(ProxyDelegationStage.included)],
    );
    failing.outcomes.add(
      VotingProxyDriveOutcome(
        failures: [
          VotingRoundStepFailure(
            _dcShare,
            const rust_wire.RoundStepFailureView(
              kind: rust_wire.RoundStepFailureKindView.invalidInput,
              message: 'bad input',
              shareDeliveries: [],
            ),
          ),
        ],
      ),
    );
    final other = _container(failing);
    await _startProxy(other);
    await _waitFor(
      other,
      (state) => state.status == VotingSubmissionJobStatus.error,
    );
    failing.progress
      ..clear()
      ..add(_progress(ProxyDelegationStage.handedOff));
    await _startProxy(other);
    await _waitFor(
      other,
      (state) => state.status == VotingSubmissionJobStatus.complete,
    );
  });

  test('the vote flow takes the round over from a running proxy job', () async {
    final script = _Script(
      plan: _proxyPlan([_advanceBatch]),
      progress: [_progress(ProxyDelegationStage.submitting)],
    )..draft = const {1: 0};
    final container = _container(
      script,
      delays: const ProxyJobCycleDelays(
        working: Duration(hours: 1),
        waiting: Duration(hours: 1),
        retry: Duration(hours: 1),
      ),
    );
    await _startProxy(container);
    await _waitFor(
      container,
      (state) => state.proxyStage == ProxyJobStage.submitting,
    );

    await container.read(votingSubmissionJobProvider(_key).notifier).start();

    final ballot = container.read(votingSubmissionJobProvider(_key));
    expect(ballot.kind, VotingSubmissionJobKind.ballot);
    expect(ballot.status, VotingSubmissionJobStatus.running);
    expect(
      ballot.proxyProgress,
      isNotNull,
      reason: 'the delegation\'s last progress stays readable',
    );
  });

  test('the vote flow leaves a proxy job whose account has no ballot to '
      'add', () async {
    final script = _Script(
      plan: _proxyPlan([_advanceBatch]),
      progress: [_progress(ProxyDelegationStage.submitting)],
    );
    final container = _container(
      script,
      delays: const ProxyJobCycleDelays(
        working: Duration(hours: 1),
        waiting: Duration(hours: 1),
        retry: Duration(hours: 1),
      ),
    );
    await _startProxy(container);
    await _waitFor(
      container,
      (state) => state.proxyStage == ProxyJobStage.submitting,
    );
    final generation = container
        .read(votingSubmissionJobProvider(_key))
        .generation;

    await container.read(votingSubmissionJobProvider(_key).notifier).start();

    final state = container.read(votingSubmissionJobProvider(_key));
    expect(state.kind, VotingSubmissionJobKind.proxy);
    expect(state.status, VotingSubmissionJobStatus.running);
    expect(state.generation, generation, reason: 'the same job keeps going');
    expect(script.ballotCalls, 0);
  });

  test('the vote flow leaves a proxy job that waits for a hardware '
      'signature', () async {
    final container = ProviderContainer(
      overrides: [
        votingSubmissionJobProvider(
          _key,
        ).overrideWith(() => _SigningProxyJob(_key)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingSubmissionJobProvider(_key).notifier).start();

    final state = container.read(votingSubmissionJobProvider(_key));
    expect(state.kind, VotingSubmissionJobKind.proxy);
    expect(state.status, VotingSubmissionJobStatus.waitingForKeystone);
  });

  group('a vote job that took the round over', () {
    /// A proxy job delivering [script]'s DC share, handed to the vote job.
    Future<ProviderContainer> takeOver(
      _Script script, {
      FutureOr<void> Function()? beforeVote,
    }) async {
      final container = _container(script);
      await _startProxy(container);
      await _waitFor(
        container,
        (state) => state.proxyStage == ProxyJobStage.handingOff,
      );
      await beforeVote?.call();
      await container.read(votingSubmissionJobProvider(_key).notifier).start();
      return container;
    }

    /// Waits for [script] to drive [count] more times.
    Future<void> moreDrives(_Script script, int count) {
      final target = script.drives.length + count;
      return _eventually(
        () => script.drives.length >= target,
        reason: '$count more drives',
      );
    }

    test('and then failed keeps delivering DC shares under the vote\'s '
        'error, and hands them back to a proxy job when dismissed', () async {
      final script =
          _Script(
              plan: _proxyPlan([_dcShare]),
              progress: [_progress(ProxyDelegationStage.included)],
            )
            ..clockStep = const Duration(seconds: 1)
            ..draft = const {1: 0};
      final container = await takeOver(
        script,
        beforeVote: () => script.castError = StateError('cast failed'),
      );
      final failed = await _waitFor(
        container,
        (state) => state.status == VotingSubmissionJobStatus.error,
      );
      expect(failed.kind, VotingSubmissionJobKind.ballot);

      await moreDrives(script, 3);
      final still = container.read(votingSubmissionJobProvider(_key));
      expect(still.kind, VotingSubmissionJobKind.ballot);
      expect(still.status, VotingSubmissionJobStatus.error);
      expect(still.errorMessage, failed.errorMessage);

      container.read(votingSubmissionJobProvider(_key).notifier).dismiss();
      final handedBack = container.read(votingSubmissionJobProvider(_key));
      expect(handedBack.kind, VotingSubmissionJobKind.proxy);
      expect(handedBack.status, VotingSubmissionJobStatus.running);

      script.progress
        ..clear()
        ..add(_progress(ProxyDelegationStage.handedOff));
      await _waitFor(
        container,
        (state) => state.status == VotingSubmissionJobStatus.complete,
      );
    });

    test('and then waits for a Ledger signature keeps delivering DC '
        'shares, also once the signing is cancelled', () async {
      // The kept remainder's ballot: its delegation is a Ledger signature
      // the vote job asks for once it recorded the ballot.
      final ballot = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [_dcShare],
        openProposals: Uint32List.fromList(const [1]),
        allDecided: false,
        needsDraftSetup: true,
        delegationStatuses: const [
          rust_wire.DelegationStatusView(
            bundleIndex: 0,
            phase: rust_wire.WorkflowPhaseView.confirmed,
            terminal: false,
          ),
        ],
      );
      final script =
          _Script(
              plan: ballot,
              progress: [_progress(ProxyDelegationStage.included)],
              ledger: true,
            )
            ..clockStep = const Duration(seconds: 1)
            ..draft = const {1: 0}
            ..planAfterIntents = _proxyPlan([_dcShare, _delegateBundle1]);
      final container = await takeOver(script);
      // The proxy job stopped at the hand-over; only the vote job runs now.
      final waiting = await _waitFor(
        container,
        (state) => state.status == VotingSubmissionJobStatus.waitingForLedger,
      );
      expect(waiting.kind, VotingSubmissionJobKind.ballot);

      await moreDrives(script, 3);
      expect(script.drives.last.hardwareSigner, HardwareSignerKind.ledger);
      expect(
        container.read(votingSubmissionJobProvider(_key)).status,
        VotingSubmissionJobStatus.waitingForLedger,
      );

      await container
          .read(votingSubmissionJobProvider(_key).notifier)
          .cancelLedgerSigning();
      expect(
        container.read(votingSubmissionJobProvider(_key)).status,
        VotingSubmissionJobStatus.error,
      );
      await moreDrives(script, 3);

      script.plan = _proxyPlan(const []);
      await moreDrives(script, 1);
      final settled = script.drives.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        script.drives,
        hasLength(settled),
        reason: 'no drive follows once no proxy work is owed',
      );
    });
  });

  group('a round with nothing left to vote', () {
    /// A plan whose only bundle the proxy DCs took whole, owing [steps].
    rust_wire.RoundPlanView nothingLeft(List<rust_wire.NextStepView> steps) =>
        apiRoundPlan(
          roundId: _roundId,
          pendingRecovery: steps.isNotEmpty,
          nextSteps: steps,
          openProposals: Uint32List(0),
          allDecided: false,
          delegationStatuses: const [
            rust_wire.DelegationStatusView(
              bundleIndex: 0,
              phase: rust_wire.WorkflowPhaseView.confirmed,
              terminal: false,
            ),
          ],
          fullyDelegatedBundles: const [0],
          nothingLeftToVote: true,
        );

    test('completes the vote job without asking for a ballot', () async {
      final script = _Script(plan: nothingLeft(const []), eligible: true);
      final container = _container(script);

      await container.read(votingSubmissionJobProvider(_key).notifier).start();
      final done = await _waitFor(
        container,
        (state) => state.status != VotingSubmissionJobStatus.running,
      );

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(script.ballotCalls, 0);
    });

    test('keeps the vote job delivering DC shares without casting, then '
        'completes once they settle', () async {
      final script = _Script(
        plan: nothingLeft(const [_dcShare]),
        progress: [_progress(ProxyDelegationStage.included)],
        eligible: true,
      );
      final container = _container(script);

      await container.read(votingSubmissionJobProvider(_key).notifier).start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(votingSubmissionJobProvider(_key)).status,
        VotingSubmissionJobStatus.running,
        reason: 'no ballot is asked for while the DC shares are owed',
      );

      script.plan = nothingLeft(const []);
      final done = await _waitFor(
        container,
        (state) => state.status != VotingSubmissionJobStatus.running,
        attempts: 1000,
      );

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(script.drives, isNotEmpty);
      expect(script.ballotCalls, 0);
    });
  });

  test('a ballot job for a round without an allocation never reads proxy '
      'progress', () async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        votingSubmissionSessionProvider(_key).overrideWith(
          () => _ProxySession(_key, _Script(plan: _proxyPlan([]))),
        ),
        proxyJobProgressReaderProvider.overrideWithValue((_) async {
          reads++;
          return null;
        }),
        votingDraftPersistenceProvider.overrideWithValue(_Drafts()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingSubmissionJobProvider(_key).notifier).start();
    final ended = await _waitFor(
      container,
      (state) => state.status == VotingSubmissionJobStatus.error,
    );

    expect(ended.kind, VotingSubmissionJobKind.ballot);
    expect(
      ended.errorMessage,
      const VotingNotice(VotingNoticeKind.noVoteChosen),
    );
    expect(reads, 0);
    expect(ended.proxyProgress, isNull);
  });

  group('a ballot whose delegation has not landed yet', () {
    /// Starts the vote job for [draft] through [session], recording every
    /// error it shows into [errors].
    Future<ProviderContainer> start(
      _HeldCastSession session,
      List<VotingMessage?> errors, {
      Map<int, int> draft = const {1: 0},
      ProxyJobCycleDelays delays = _sessionDelays,
    }) async {
      final container = _heldCastContainer(
        session,
        draft: draft,
        delays: delays,
      );
      container.listen<VotingSubmissionJobState>(
        votingSubmissionJobProvider(_key),
        (_, next) {
          if (next.status == VotingSubmissionJobStatus.error) {
            errors.add(next.errorMessage);
          }
        },
      );
      await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(_roundId, accountUuid: _key.accountUuid);
      return container;
    }

    /// Waits for [container]'s job to settle, failing on any error it
    /// showed on the way.
    Future<VotingSubmissionJobState> settled(
      ProviderContainer container,
      List<VotingMessage?> errors,
    ) async {
      final settled = await _waitFor(
        container,
        (state) =>
            state.status == VotingSubmissionJobStatus.complete ||
            state.status == VotingSubmissionJobStatus.error,
        attempts: 400,
      );
      expect(errors, isEmpty, reason: 'a held cast is not a failure');
      expect(settled.kind, VotingSubmissionJobKind.ballot);
      return settled;
    }

    /// Submits [draft] through [session] and waits for the job to settle.
    Future<VotingSubmissionJobState> submit(
      _HeldCastSession session, {
      Map<int, int> draft = const {1: 0},
    }) async {
      final errors = <VotingMessage?>[];
      return settled(await start(session, errors, draft: draft), errors);
    }

    test('sends the batch with the signer, waits for it to land, then casts '
        'and confirms the kept share', () async {
      final sdk = _HeldCastSdk(pendingPasses: 2);
      final session = _HeldCastSession(_key, sdk, keystone: false);

      final done = await submit(session);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(sdk.log, ['prove', 'broadcast', 'land', 'cast', 'confirm']);
      expect(
        session.drives.first.mnemonic,
        isNotNull,
        reason: 'the batch signs its registration with the account seed',
      );
    });

    test('collects the Keystone signature for the batch, sends it, then '
        'casts and confirms the kept share', () async {
      final sdk = _HeldCastSdk();
      final session = _HeldCastSession(_key, sdk, keystone: true);

      final done = await submit(session);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(sdk.log, [
        'prove',
        'keystone signature',
        'broadcast',
        'land',
        'cast',
        'confirm',
      ]);
      expect(
        session.drives.map((drive) => drive.hardwareSigner),
        everyElement(HardwareSignerKind.keystone),
      );
    });

    test('that took everything sends the batch with the signer before the '
        'vote job completes', () async {
      final sdk = _HeldCastSdk(keptShare: false);
      final session = _HeldCastSession(_key, sdk, keystone: false);

      final done = await submit(session, draft: const {});

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(sdk.log, ['prove', 'broadcast', 'land']);
      expect(session.drives.first.mnemonic, isNotNull);
    });

    test('taken over from the proxy job a restart restored, casts once the '
        'batch lands', () async {
      // The restorer's proxy job sent the batch; the chain refuses it.
      final sdk = _HeldCastSdk()..refused = true;
      final session = _HeldCastSession(_key, sdk, keystone: false);
      final errors = <VotingMessage?>[];
      final container = _heldCastContainer(session);
      container.listen<VotingSubmissionJobState>(
        votingSubmissionJobProvider(_key),
        (_, next) {
          if (next.status == VotingSubmissionJobStatus.error) {
            errors.add(next.errorMessage);
          }
        },
      );
      await _startProxy(container);
      await _waitFor(
        container,
        (state) => state.proxyStage == ProxyJobStage.refused,
      );

      // The progress screen opens and starts the vote job.
      sdk.refused = false;
      await container.read(votingSubmissionJobProvider(_key).notifier).start();
      final done = await settled(container, errors);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(sdk.log, ['prove', 'broadcast', 'land', 'cast', 'confirm']);
    });

    test('and is refused waits in place, resending it, and casts the kept '
        'share once it lands', () async {
      final sdk = _HeldCastSdk()..refused = true;
      final session = _HeldCastSession(_key, sdk, keystone: false);
      final errors = <VotingMessage?>[];
      final container = await start(
        session,
        errors,
        delays: const ProxyJobCycleDelays(
          working: Duration(milliseconds: 1),
          waiting: Duration(milliseconds: 20),
          retry: Duration(milliseconds: 1),
        ),
      );
      final held = await _waitFor(
        container,
        (state) => state.proxyStage == ProxyJobStage.refused,
      );
      expect(held.status, VotingSubmissionJobStatus.running);
      expect(sdk.cast, isFalse);
      final drives = session.drives.length;
      await _eventually(
        () => session.drives.length > drives,
        reason: 'a resend',
      );

      sdk.refused = false;
      final done = await settled(container, errors);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(sdk.log, ['prove', 'broadcast', 'land', 'cast', 'confirm']);
    });
  });

  group('casts that stop for a signature', () {
    /// Submits the kept share through [session] and waits for the job to
    /// settle.
    Future<VotingSubmissionJobState> submit(_SigningCastSession session) async {
      final container = _sessionContainer(session);
      await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(_roundId, accountUuid: _key.accountUuid);
      return _waitFor(
        container,
        (state) =>
            state.status == VotingSubmissionJobStatus.complete ||
            state.status == VotingSubmissionJobStatus.error,
      );
    }

    test('go back through the seed and are cast', () async {
      final session = _SigningCastSession(_key, keystone: false);

      final done = await submit(session);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(session.log, ['cast stopped for signature', 'cast with seed']);
    });

    test('go back through the Keystone signing and are cast', () async {
      final session = _SigningCastSession(_key, keystone: true);

      final done = await submit(session);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(session.log, [
        'cast stopped for signature',
        'keystone signature',
        'cast with keystone signature',
      ]);
    });

    test('again after signing fail the job with a clear message', () async {
      final session = _SigningCastSession(
        _key,
        keystone: false,
        signerCasts: false,
      );

      final done = await submit(session);

      expect(done.status, VotingSubmissionJobStatus.error);
      expect(
        done.errorMessage,
        const VotingNotice(VotingNoticeKind.castsNeedSignature),
      );
      expect(session.log, [
        'cast stopped for signature',
        'cast stopped for signature',
      ]);
    });
  });

  group('a hardware Submit whose kept bundle signs at its first cast', () {
    /// Submits the kept answer through [session] and waits for the job to
    /// settle.
    Future<VotingSubmissionJobState> submit(_KeptBundleSession session) async {
      final container = _sessionContainer(
        session,
        progress: (_) async => session.sdk.progress(),
        extra: [
          ledgerVotingPcztSignerProvider.overrideWithValue(
            (_, _) async => const [
              LedgerVotingSignature(pool: 1, actionIndex: 0, signature: [0]),
            ],
          ),
        ],
      );
      await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(_roundId, accountUuid: _key.accountUuid);
      return _waitFor(
        container,
        (state) =>
            state.status == VotingSubmissionJobStatus.complete ||
            state.status == VotingSubmissionJobStatus.error,
        attempts: 400,
      );
    }

    test('signs it in the Keystone scan for the batch', () async {
      final sdk = _KeptBundleSdk();
      final session = _KeptBundleSession(_key, sdk, ledger: false);

      final done = await submit(session);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(sdk.log, [
        'prove',
        'keystone scan [0, 1]',
        'broadcast',
        'land',
        'cast',
        'confirm',
      ]);
    });

    test('approves it on the Ledger before the batch is sent', () async {
      final sdk = _KeptBundleSdk();
      final session = _KeptBundleSession(_key, sdk, ledger: true);

      final done = await submit(session);

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(sdk.log, [
        'prove',
        'ledger approval 0',
        'ledger approval 1',
        'broadcast',
        'land',
        'cast',
        'confirm',
      ]);
    });
  });

  group('a restart while the delegation is still on its way', () {
    test('the restorer casts the kept answers once the batch lands, without '
        'the round being opened', () async {
      // The batch went out before the restart. The submit recorded the
      // kept share's answers in the voting database, and the draft is gone.
      final sdk = _HeldCastSdk()
        ..batch = _Batch.dispatched
        ..intents = true;
      final session = _HeldCastSession(_key, sdk, keystone: false);
      final container = _sessionContainer(
        session,
        draft: const {},
        progress: (_) async => sdk.progress(),
        extra: [
          proxyDelegationFeatureEnabledProvider.overrideWithValue(true),
          appSecurityProvider.overrideWith(_Unlocked.new),
          votingProxyJobRestoreAccountsProvider.overrideWithValue(
            () async => [_key.accountUuid],
          ),
          votingWalletDbPathProvider.overrideWithValue(() async => 'db'),
          votingPendingProxyRoundLoaderProvider.overrideWithValue(
            ({required dbPath, required accountUuids}) async => const [
              rust_delegator.ApiPendingProxyRound(
                accountUuid: 'account-1',
                roundId: _roundId,
              ),
            ],
          ),
          votingProxyRoundOpenProvider.overrideWithValue((_) async => true),
        ],
      );

      await container.read(votingProxyJobRestorerProvider).restore();
      final done = await _waitFor(
        container,
        (state) =>
            state.status == VotingSubmissionJobStatus.complete ||
            state.status == VotingSubmissionJobStatus.error,
      );

      expect(done.status, VotingSubmissionJobStatus.complete);
      expect(done.kind, VotingSubmissionJobKind.ballot);
      expect(sdk.log, ['land', 'cast', 'confirm']);
    });
  });
}
