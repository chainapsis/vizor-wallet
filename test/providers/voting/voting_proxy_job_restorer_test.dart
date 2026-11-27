import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_proxy_job_restorer_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegator.dart'
    as rust_delegator;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import '../../features/voting/round_plan_test_utils.dart';
import '../../features/voting/proxy/support/proxy_values.dart';

const _roundId =
    'abababababababababababababababababababababababababababababababab';
const _key = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');

/// The round's vote end, in unix seconds.
const _voteEndSeconds = 1792000000;

/// The round's one unfinished allocation, as zcash_voting lists it.
const _pending = rust_delegator.ApiPendingProxyRound(
  accountUuid: 'account-1',
  roundId: _roundId,
);

/// A plan owing one DC share on bundle 0, its registration confirmed.
final _plan = apiRoundPlan(
  roundId: _roundId,
  pendingRecovery: false,
  nextSteps: const [
    rust_wire.NextStepView(
      kind: rust_wire.NextStepKind.submitShares,
      bundleIndex: 0,
      proposalId: 0,
      choice: 0,
      shareIndex: 3,
      dcSlot: 0,
    ),
  ],
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
);

/// Delegate 3's delegation, included and still owing its shares.
final _included = proxyProgress(
  delegations: [
    proxyView(
      delegateIndex: 3,
      handle: 'delegate3',
      ballots: BigInt.from(75),
      stage: ProxyDelegationStage.included,
      ballot: proxyBallot(ApiDelegateBallotKind.noBallotYet),
    ),
  ],
);

/// A session whose proxy drives are counted.
class _Session extends VotingSubmissionSessionNotifier {
  _Session(super.key, this.drives, this.plan);

  /// Every drive's signer.
  final List<({String? mnemonic, HardwareSignerKind? hardwareSigner})> drives;

  /// The round plan it reports.
  final rust_wire.RoundPlanView plan;

  @override
  Future<VotingSessionState> build() async => VotingSessionState(
    roundId: _roundId,
    accountUuid: _key.accountUuid,
    roundPlan: plan,
    round: VotingRoundDetails(
      roundId: _roundId,
      title: 'Proxy round',
      status: 'SESSION_STATUS_ACTIVE',
      snapshotHeight: 100,
      eaPk: Uint8List(32),
      ncRoot: Uint8List(32),
      nullifierImtRoot: Uint8List(32),
      rawJson: const {'vote_end_time': _voteEndSeconds},
    ),
  );

  @override
  Future<VotingProxyDriveOutcome> driveProxyDelegation({
    String? mnemonic,
    HardwareSignerKind? hardwareSigner,
    void Function()? onStepFinished,
  }) async {
    drives.add((mnemonic: mnemonic, hardwareSigner: hardwareSigner));
    return const VotingProxyDriveOutcome();
  }
}

/// A ballot job already running for the round.
class _RunningBallotJob extends VotingSubmissionJobNotifier {
  _RunningBallotJob(super.key);

  @override
  VotingSubmissionJobState build() => const VotingSubmissionJobState(
    key: _key,
    status: VotingSubmissionJobStatus.running,
  );
}

/// The wallet's lock, which tests flip.
class _Security extends AppSecurityNotifier {
  _Security({required this.locked});

  /// Whether the wallet starts locked.
  final bool locked;

  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: true, isUnlocked: !locked);

  /// Unlocks the wallet.
  void setUnlocked() => state = state.copyWith(isUnlocked: true);
}

/// An empty ballot draft store.
class _EmptyDrafts implements VotingDraftPersistence {
  @override
  Future<VotingDraftState> load(VotingSessionKey key) async =>
      const VotingDraftState();

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {}

  @override
  Future<void> deleteForAccount(String accountUuid) async {}
}

/// What one restorer container read and did.
class _Restore {
  /// Rounds zcash_voting lists; a thrown error fails the listing.
  List<Object> listings = [
    [_pending],
  ];

  /// Whether each round is still open.
  bool open = true;

  /// How often the listing and the open check ran.
  int listed = 0;
  int openChecks = 0;

  /// Every proxy drive.
  final drives = <({String? mnemonic, HardwareSignerKind? hardwareSigner})>[];

  /// The round plan the session reports.
  rust_wire.RoundPlanView plan = _plan;
}

/// A container whose restorer runs over [restore], with the flag [enabled]
/// and the wallet [locked] or not.
ProviderContainer _container(
  _Restore restore, {
  bool enabled = true,
  bool locked = false,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      proxyDelegationFeatureEnabledProvider.overrideWithValue(enabled),
      appSecurityProvider.overrideWith(() => _Security(locked: locked)),
      votingProxyJobRestoreAccountsProvider.overrideWithValue(
        () async => ['account-1'],
      ),
      votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
      votingPendingProxyRoundLoaderProvider.overrideWithValue(({
        required dbPath,
        required accountUuids,
      }) async {
        restore.listed++;
        final next = restore.listings.length > 1
            ? restore.listings.removeAt(0)
            : restore.listings.single;
        if (next is List<rust_delegator.ApiPendingProxyRound>) return next;
        throw next;
      }),
      votingProxyRoundOpenProvider.overrideWithValue((_) async {
        restore.openChecks++;
        return restore.open;
      }),
      votingProxyJobRestoreRetryDelayProvider.overrideWithValue(Duration.zero),
      votingSubmissionSessionProvider(
        _key,
      ).overrideWith(() => _Session(_key, restore.drives, restore.plan)),
      proxyJobProgressReaderProvider.overrideWithValue((_) async => _included),
      proxyJobCycleDelaysProvider.overrideWithValue(
        const ProxyJobCycleDelays(
          working: Duration(hours: 1),
          waiting: Duration(hours: 1),
          retry: Duration(hours: 1),
        ),
      ),
      votingSubmissionJobClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(
          (_voteEndSeconds - 86400) * 1000,
        ),
      ),
      votingDraftPersistenceProvider.overrideWithValue(_EmptyDrafts()),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Lets the restorer and the job it started run.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('after a restart an unfinished proxy job resumes with the round '
      'driver and the round hotkey only', () async {
    final restore = _Restore();
    final container = _container(restore);

    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();

    final job = container.read(votingSubmissionJobProvider(_key));
    expect(job.kind, VotingSubmissionJobKind.proxy);
    expect(job.status, VotingSubmissionJobStatus.running);
    expect(job.proxyProgress, _included);
    expect(restore.drives, isNotEmpty);
    expect(
      restore.drives.every(
        (drive) => drive.mnemonic == null && drive.hardwareSigner == null,
      ),
      isTrue,
      reason: 'share delivery needs only the round hotkey',
    );
    expect(container.read(votingSubmissionJobsProvider).jobKeys, [_key]);
  });

  test('with no unfinished allocation it starts nothing and asks no '
      'vote server', () async {
    final restore = _Restore()
      ..listings = [<rust_delegator.ApiPendingProxyRound>[]];
    final container = _container(restore);

    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();

    expect(restore.listed, 1);
    expect(restore.openChecks, 0);
    expect(
      container.read(votingSubmissionJobProvider(_key)).status,
      VotingSubmissionJobStatus.idle,
    );
    expect(restore.drives, isEmpty);
  });

  test('a round that closed is left alone', () async {
    final restore = _Restore()..open = false;
    final container = _container(restore);
    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();
    expect(restore.openChecks, 1);
    expect(restore.drives, isEmpty);
    expect(
      container.read(votingSubmissionJobProvider(_key)).status,
      VotingSubmissionJobStatus.idle,
    );
  });

  test('a running ballot job keeps the round', () async {
    final restore = _Restore();
    final container = _container(
      restore,
      overrides: [
        votingSubmissionJobProvider(
          _key,
        ).overrideWith(() => _RunningBallotJob(_key)),
      ],
    );
    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();
    final job = container.read(votingSubmissionJobProvider(_key));
    expect(job.kind, VotingSubmissionJobKind.ballot);
    expect(job.status, VotingSubmissionJobStatus.running);
    expect(restore.drives, isEmpty);
  });

  test('nothing is restored while the wallet is locked; unlocking '
      'restores', () async {
    final restore = _Restore();
    final container = _container(restore, locked: true);
    container.read(votingProxyJobRestorerProvider);
    await _settle();
    expect(restore.listed, 0);

    (container.read(appSecurityProvider.notifier) as _Security).setUnlocked();
    await _settle();
    expect(restore.listed, 1);
    expect(
      container.read(votingSubmissionJobProvider(_key)).kind,
      VotingSubmissionJobKind.proxy,
    );
  });

  test('an unlock while share tracking still drains restores once the '
      'registry resumes', () async {
    final restore = _Restore();
    final container = _container(restore, locked: true);
    container.read(votingProxyJobRestorerProvider);
    final registry = container.read(votingShareTrackingRegistryProvider);
    // The lock-time drain share tracking holds until its pause finishes.
    await registry.quiesceAndDrain();

    (container.read(appSecurityProvider.notifier) as _Security).setUnlocked();
    await _settle();
    expect(restore.listed, 0, reason: 'the registry refused the lease');

    registry.resume();
    await _settle();
    expect(restore.listed, 1);
    expect(
      container.read(votingSubmissionJobProvider(_key)).kind,
      VotingSubmissionJobKind.proxy,
    );
  });

  test('a restore request from the registry restores, after its resume '
      'when quiesced', () async {
    final restore = _Restore()
      ..listings = [
        <rust_delegator.ApiPendingProxyRound>[],
        [_pending],
      ];
    final container = _container(restore);
    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();
    expect(restore.listed, 1);

    final registry = container.read(votingShareTrackingRegistryProvider);
    await registry.quiesceAndDrain();
    registry.requestRestore();
    await _settle();
    expect(restore.listed, 1);

    registry.resume();
    await _settle();
    expect(restore.listed, 2);
    expect(
      container.read(votingSubmissionJobProvider(_key)).kind,
      VotingSubmissionJobKind.proxy,
    );
  });

  test('an account that deletion holds is skipped', () async {
    final restore = _Restore();
    final container = _container(restore);
    final registry = container.read(votingShareTrackingRegistryProvider);
    final draining = registry.quiesceAndDrain(accountUuid: 'account-1');
    await container.read(votingProxyJobRestorerProvider).restore();
    await draining;
    expect(restore.drives, isEmpty);
    registry.resume(accountUuid: 'account-1');
    await _settle();
    expect(
      restore.drives,
      isNotEmpty,
      reason: 'the refused restore runs once deletion lets go',
    );
  });

  test('a failed discovery is tried again', () async {
    final restore = _Restore()
      ..listings = [
        StateError('sidecar busy'),
        [_pending],
      ];
    final container = _container(restore);
    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();
    expect(restore.listed, 2);
    expect(
      container.read(votingSubmissionJobProvider(_key)).kind,
      VotingSubmissionJobKind.proxy,
    );
  });

  test('with the flag off it reads nothing', () async {
    final restore = _Restore();
    final container = _container(restore, enabled: false);
    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();
    expect(restore.listed, 0);
    expect(restore.drives, isEmpty);
  });

  test('a round whose plan still owes the casts of answers recorded with '
      'the delegation gets the vote job', () async {
    final restore = _Restore()
      ..plan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: rust_wire.NextStepKind.advanceProxyBatch,
            bundleIndex: 0,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
        hasUnconfirmedShares: false,
        recoveredVoteWork: const [],
        delegationStatuses: const [
          rust_wire.DelegationStatusView(
            bundleIndex: 0,
            phase: rust_wire.WorkflowPhaseView.confirmed,
            terminal: false,
          ),
        ],
      );
    final container = _container(restore);

    await container.read(votingProxyJobRestorerProvider).restore();
    await _settle();

    expect(restore.openChecks, 1);
    expect(
      container.read(votingSubmissionJobProvider(_key)).kind,
      VotingSubmissionJobKind.ballot,
    );
    expect(container.read(votingSubmissionJobsProvider).jobKeys, [_key]);
  });
}
