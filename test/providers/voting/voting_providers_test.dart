import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_voting;
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

import '../../services/voting/fake_voting_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('config provider loads and refreshes dynamic voting config', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final first = await container.read(votingConfigProvider.future);
    await container.read(votingConfigProvider.notifier).refresh();
    final second = container.read(votingConfigProvider).value;

    expect(first.apiBaseUrl, Uri.parse('https://voting.example'));
    expect(second?.apiBaseUrl, first.apiBaseUrl);
    expect(
      http.requests
          .where(
            (request) =>
                request.uri.toString() ==
                'https://voting.example/static-voting-config.json',
          )
          .length,
      2,
    );
  });

  test('rounds provider merges endorsed and unverified rows', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': [
          {'round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          {'round_id': kOtherRoundId, 'title': 'Other', 'status': 'active'},
        ],
        '/shielded-vote/v1/endorsed-rounds/zodl': {
          'endorsed_round_ids': [kRoundId],
        },
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final rounds = await container.read(votingRoundsProvider.future);

    expect(rounds, hasLength(2));
    expect(rounds.first.endorsed, isTrue);
    expect(rounds.first.unverified, isFalse);
    expect(rounds.last.endorsed, isFalse);
    expect(rounds.last.unverified, isTrue);
  });

  test('PIR mismatch fails before Rust delegation work is called', () async {
    final rust = FakeVotingRustApi();
    final pir = FakePirResolver(
      error: PirSnapshotNoMatchingEndpoint(
        expectedSnapshotHeight: 123,
        diagnostics: [
          PirSnapshotEndpointDiagnostic(
            endpoint: Uri.parse('https://pir.example'),
            status: PirSnapshotEndpointStatus.behind,
            reportedHeight: 122,
          ),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, pirResolver: pir);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareDelegation();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.pirDiagnostics, hasLength(1));
    expect(rust.setupCalls, 0);
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test('resume after delegated does not rebuild delegation bundle', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 0,
            txHash: 'delegation-tx',
          ),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(seedBytes: [1, 2, 3]);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.setupCalls, 1);
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test('vote progress is isolated by bundle index', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 0,
            txHash: 'delegation-0',
          ),
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 1,
            txHash: 'delegation-1',
          ),
        ],
        votes: [
          vote(bundleIndex: 0, proposalId: 7),
          vote(bundleIndex: 1, proposalId: 7),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_voting.ApiDraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.submittingShares);
    expect(state.voteProgress.keys.toSet(), {
      const VotingVoteKey(bundleIndex: 0, proposalId: 7),
      const VotingVoteKey(bundleIndex: 1, proposalId: 7),
    });
    expect(rust.voteCommitBundleCalls, [0, 1]);
  });

  test('session actions are serialized', () async {
    final rust = FakeVotingRustApi(
      setupDelay: const Duration(milliseconds: 10),
    );
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await Future.wait([
      notifier.prepareDelegation(),
      notifier.prepareDelegation(),
    ]);

    expect(rust.setupCalls, 2);
    expect(rust.maxConcurrentSetups, 1);
  });

  test('hotkey failure moves session into error phase', () async {
    final container = _sessionContainer(
      hotkeyStore: const FailingVotingHotkeyStore(),
      recoveryApi: FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_voting.ApiDelegationTxRecovery(
              bundleIndex: 0,
              txHash: 'delegation-0',
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await expectLater(
      container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_voting.ApiDraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          ),
      throwsA(isA<VotingHotkeyUnavailable>()),
    );
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.cause, isA<VotingHotkeyUnavailable>());
  });
}

ProviderContainer _container({required VotingHttpClient http}) {
  return ProviderContainer(
    overrides: [
      votingHttpClientProvider.overrideWithValue(http),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: http,
          staticConfigSource: StaticVotingConfigSource.parse(
            'https://voting.example/static-voting-config.json',
          ),
        ),
      ),
    ],
  );
}

ProviderContainer _sessionContainer({
  FakeVotingRustApi? rust,
  FakeVotingRecoveryApi? recoveryApi,
  PirSnapshotResolver? pirResolver,
  VotingHotkeyStore hotkeyStore = const FakeVotingHotkeyStore([9, 9, 9]),
}) {
  final http = FakeVotingHttpClient(
    responses: {
      'https://voting.example/static-voting-config.json': staticConfigJson(),
      'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
      '/shielded-vote/v1/round/$kRoundId': {
        'round': roundStatusJson(roundId: kRoundId),
      },
      '/shielded-vote/v1/share-status/$kRoundId/0102': {'status': 'confirmed'},
    },
  );
  return ProviderContainer(
    overrides: [
      votingHttpClientProvider.overrideWithValue(http),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: http,
          staticConfigSource: StaticVotingConfigSource.parse(
            'https://voting.example/static-voting-config.json',
          ),
        ),
      ),
      votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
      votingActiveAccountUuidProvider.overrideWithValue(
        () async => 'account-1',
      ),
      votingRpcEndpointConfigProvider.overrideWithValue(
        const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: 'https://lightwalletd.example:443',
        ),
      ),
      votingRecoveryServiceProvider.overrideWithValue(
        VotingRecoveryService(
          api: recoveryApi ?? FakeVotingRecoveryApi(state: recoveryState()),
        ),
      ),
      votingPirResolverProvider.overrideWithValue(
        pirResolver ??
            FakePirResolver(
              resolution: PirSnapshotResolution(
                endpoint: Uri.parse('https://pir.example'),
                diagnostics: [
                  PirSnapshotEndpointDiagnostic(
                    endpoint: Uri.parse('https://pir.example'),
                    status: PirSnapshotEndpointStatus.matched,
                    reportedHeight: 123,
                  ),
                ],
              ),
            ),
      ),
      votingRustApiProvider.overrideWithValue(rust ?? FakeVotingRustApi()),
      votingHotkeyStoreProvider.overrideWithValue(hotkeyStore),
    ],
  );
}

const kRoundId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const kOtherRoundId =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _hex32 =
    '0101010101010101010101010101010101010101010101010101010101010101';

Map<String, dynamic> staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _hex32},
  ],
};

Map<String, dynamic> dynamicConfigJson() => {
  'config_version': 1,
  'vote_servers': [
    {'url': 'https://voting.example', 'label': 'primary'},
  ],
  'pir_endpoints': [
    {'url': 'https://pir.example', 'label': 'pir'},
  ],
  'supported_versions': {
    'pir': ['v0'],
    'vote_protocol': 'v0',
    'tally': 'v0',
    'vote_server': 'v1',
  },
  'rounds': {
    kRoundId: {
      'auth_version': 1,
      'ea_pk': _hex32,
      'signatures': [
        {'key_id': 'demo', 'alg': 'ed25519', 'sig': _hex32},
      ],
    },
  },
};

Map<String, dynamic> roundStatusJson({required String roundId}) => {
  'vote_round_id': roundId,
  'round_id': roundId,
  'title': 'Poll',
  'status': 'active',
  'snapshot_height': 123,
  'ea_pk': _hex32,
  'nc_root': _hex32,
  'nullifier_imt_root': _hex32,
};

rust_voting.ApiRoundRecoveryState recoveryState({
  int bundleCount = 1,
  List<rust_voting.ApiDelegationTxRecovery> delegationTxHashes = const [],
  List<rust_voting.ApiVoteRecord> votes = const [],
  List<rust_voting.ApiVoteTxRecovery> voteTxHashes = const [],
  List<rust_voting.ApiCommitmentBundleRecovery> commitmentBundles = const [],
  List<rust_voting.ApiShareDelegationRecord> shareDelegations = const [],
  List<rust_voting.ApiShareDelegationRecord> unconfirmedShareDelegations =
      const [],
}) {
  return rust_voting.ApiRoundRecoveryState(
    roundId: kRoundId,
    bundleCount: bundleCount,
    delegationTxHashes: delegationTxHashes,
    votes: votes,
    voteTxHashes: voteTxHashes,
    commitmentBundles: commitmentBundles,
    shareDelegations: shareDelegations,
    unconfirmedShareDelegations: unconfirmedShareDelegations,
  );
}

rust_voting.ApiVoteRecord vote({
  required int bundleIndex,
  required int proposalId,
}) {
  return rust_voting.ApiVoteRecord(
    proposalId: proposalId,
    bundleIndex: bundleIndex,
    choice: 1,
    submitted: false,
  );
}

class FakeVotingRecoveryApi implements VotingRecoveryApi {
  rust_voting.ApiRoundRecoveryState state;

  FakeVotingRecoveryApi({required this.state});

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) async {}

  @override
  Future<void> clearRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {}

  @override
  Future<rust_voting.ApiRoundRecoveryState> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    return state;
  }
}

class FakePirResolver implements PirSnapshotResolver {
  final PirSnapshotResolution? resolution;
  final Object? error;

  const FakePirResolver({this.resolution, this.error});

  @override
  Future<PirSnapshotResolution> resolve({
    required List<Uri> endpoints,
    required int expectedSnapshotHeight,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    return resolution!;
  }
}

class FakeVotingHotkeyStore implements VotingHotkeyStore {
  final List<int> hotkey;

  const FakeVotingHotkeyStore(this.hotkey);

  @override
  Future<List<int>> readHotkey({
    required String accountUuid,
    required String roundId,
  }) async {
    return hotkey;
  }
}

class FailingVotingHotkeyStore implements VotingHotkeyStore {
  const FailingVotingHotkeyStore();

  @override
  Future<List<int>> readHotkey({
    required String accountUuid,
    required String roundId,
  }) {
    throw const VotingHotkeyUnavailable('missing test hotkey');
  }
}

class FakeVotingRustApi implements VotingRustApi {
  FakeVotingRustApi({this.setupDelay = Duration.zero});

  final Duration setupDelay;
  int setupCalls = 0;
  int _activeSetups = 0;
  int maxConcurrentSetups = 0;
  final delegationBundleCalls = <int>[];
  final voteCommitBundleCalls = <int>[];

  @override
  Future<rust_voting.ApiVotingBundleSetupResult> setupDelegationBundles({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
  }) async {
    _activeSetups++;
    if (_activeSetups > maxConcurrentSetups) {
      maxConcurrentSetups = _activeSetups;
    }
    if (setupDelay > Duration.zero) {
      await Future<void>.delayed(setupDelay);
    }
    setupCalls++;
    _activeSetups--;
    return rust_voting.ApiVotingBundleSetupResult(
      bundleCount: 1,
      eligibleWeightZatoshi: BigInt.from(100),
    );
  }

  @override
  Stream<rust_voting.ApiDelegationProofEvent>
  buildAndProveDelegationBundleWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
  }) async* {
    delegationBundleCalls.add(bundleIndex);
    yield rust_voting.ApiDelegationProofEvent(
      phase: 'result',
      txidHex: 'delegation-$bundleIndex',
    );
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String walletId,
    required String roundId,
    required String nodeUrl,
  }) async {
    return 10;
  }

  @override
  Future<rust_voting.ApiVanWitness> generateVanWitness({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  }) async {
    return rust_voting.ApiVanWitness(
      authPath: const [],
      position: bundleIndex,
      anchorHeight: anchorHeight,
    );
  }

  @override
  Stream<rust_voting.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String walletId,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> hotkeySeed,
    required rust_voting.ApiVanWitness vanWitness,
    required List<rust_voting.ApiDraftVote> draftVotes,
  }) async* {
    voteCommitBundleCalls.add(bundleIndex);
    for (final draft in draftVotes) {
      yield rust_voting.ApiVoteCommitEvent(
        phase: 'result',
        proposalId: draft.proposalId,
        bundleIndex: bundleIndex,
      );
    }
  }

  @override
  Future<void> storeVoteTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) async {}

  @override
  Future<void> recordShareDelegation({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> sentToUrls,
    required List<int> nullifier,
    required BigInt submitAt,
  }) async {}

  @override
  Future<void> markShareConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) async {}
}
