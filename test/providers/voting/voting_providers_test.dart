import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_tree_sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_api;
import 'package:zcash_wallet/src/rust/api/voting_config.dart' as rust_config_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/delegate.dart'
    as rust_delegate;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/round.dart'
    as rust_round;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/share_policy.dart'
    as rust_share_policy;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/types.dart'
    as rust_types;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/vote.dart'
    as rust_vote;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_frb_types;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';
import 'package:zcash_wallet/src/services/voting/resolved_voting_config_extensions.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import '../../features/voting/round_plan_test_utils.dart';
import '../../features/voting/tx_event_json_test_utils.dart';
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

  test('config provider retries transient static fetch failures', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json':
            SequentialVotingHttpResponses([timeoutResponse(), staticConfigJson()]),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final config = await container.read(votingConfigProvider.future);
    expect(config.apiBaseUrl, Uri.parse('https://voting.example'));
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

  test('config provider fails closed when refresh fails', () async {
    final responses = <String, Object>{
      'https://voting.example/static-voting-config.json': staticConfigJson(),
      'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
    };
    final http = FakeVotingHttpClient(responses: responses);
    final container = _container(http: http);
    addTearDown(container.dispose);

    await container.read(votingConfigProvider.future);
    responses['https://voting.example/static-voting-config.json'] = StateError(
      'network down',
    );

    await container.read(votingConfigProvider.notifier).refresh();

    final state = container.read(votingConfigProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StateError>());
  });

  test('config provider ignores stale refresh after source changes', () async {
    const firstSource = 'https://voting-a.example/static-voting-config.json';
    const secondSource = 'https://voting-b.example/static-voting-config.json';
    final store = FakeVotingConfigSourceStore(sourceUrl: firstSource);
    final loads = _GatedVotingConfigLoads({
      firstSource: _configForVoteServer('https://voting-a.example'),
      secondSource: _configForVoteServer('https://voting-b.example'),
    });
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(store),
        votingConfigLoaderProvider.overrideWith((ref) {
          final source =
              ref.watch(votingConfigSourceProvider).value?.sourceUrl ??
              kDefaultStaticVotingConfigSource;
          return _GatedVotingConfigLoader(loads, source);
        }),
        votingActiveAccountUuidProvider.overrideWithValue(() async => null),
      ],
    );
    addTearDown(container.dispose);

    final first = await container.read(votingConfigProvider.future);
    expect(first.apiBaseUrl, Uri.parse('https://voting-a.example'));

    final staleGate = loads.gateNext(firstSource);
    final staleRefresh = container.read(votingConfigProvider.notifier).refresh();
    await loads.waitForLoadCount(firstSource, 2);

    await container
        .read(votingConfigSourceProvider.notifier)
        .setCustom(secondSource);
    await container.read(votingConfigProvider.notifier).refresh();
    expect(
      container.read(votingConfigProvider).value?.apiBaseUrl,
      Uri.parse('https://voting-b.example'),
    );

    staleGate.complete();
    await staleRefresh;
    expect(
      container.read(votingConfigProvider).value?.apiBaseUrl,
      Uri.parse('https://voting-b.example'),
    );
  });

  test(
    'config provider ignores stale load failure after source changes',
    () async {
      const firstSource = 'https://voting-a.example/static-voting-config.json';
      const secondSource = 'https://voting-b.example/static-voting-config.json';
      final store = FakeVotingConfigSourceStore(sourceUrl: firstSource);
      final loads = _GatedVotingConfigLoads({
        secondSource: _configForVoteServer('https://voting-b.example'),
      });
      final container = ProviderContainer(
        overrides: [
          votingConfigSourceStoreProvider.overrideWithValue(store),
          votingConfigLoaderProvider.overrideWith((ref) {
            final source =
                ref.watch(votingConfigSourceProvider).value?.sourceUrl ??
                kDefaultStaticVotingConfigSource;
            return _GatedVotingConfigLoader(loads, source);
          }),
          votingActiveAccountUuidProvider.overrideWithValue(() async => null),
        ],
      );
      addTearDown(container.dispose);

      final staleGate = loads.gateNext(firstSource);
      loads.failNext(firstSource, StateError('stale source failed'));
      final staleLoad = container.read(votingConfigProvider.future);
      await loads.waitForLoadCount(firstSource, 1);

      await container
          .read(votingConfigSourceProvider.notifier)
          .setCustom(secondSource);
      await container.read(votingConfigProvider.notifier).refresh();
      expect(
        container.read(votingConfigProvider).value?.apiBaseUrl,
        Uri.parse('https://voting-b.example'),
      );

      staleGate.complete();
      final staleResult = await staleLoad;
      expect(staleResult.apiBaseUrl, Uri.parse('https://voting-b.example'));
      expect(
        container.read(votingConfigProvider).value?.apiBaseUrl,
        Uri.parse('https://voting-b.example'),
      );
    },
  );

  test(
    'config provider keeps failed refresh over stale load success',
    () async {
      const firstSource = 'https://voting-a.example/static-voting-config.json';
      const secondSource = 'https://voting-b.example/static-voting-config.json';
      final store = FakeVotingConfigSourceStore(sourceUrl: firstSource);
      final newerFailure = StateError('replacement source failed');
      final loads = _GatedVotingConfigLoads({
        firstSource: _configForVoteServer('https://voting-a.example'),
      });
      final container = ProviderContainer(
        overrides: [
          votingConfigSourceStoreProvider.overrideWithValue(store),
          votingConfigLoaderProvider.overrideWith((ref) {
            final source =
                ref.watch(votingConfigSourceProvider).value?.sourceUrl ??
                kDefaultStaticVotingConfigSource;
            return _GatedVotingConfigLoader(loads, source);
          }),
          votingActiveAccountUuidProvider.overrideWithValue(() async => null),
        ],
      );
      addTearDown(container.dispose);

      final staleGate = loads.gateNext(firstSource);
      final staleLoad = container.read(votingConfigProvider.future);
      await loads.waitForLoadCount(firstSource, 1);

      loads.failNext(secondSource, newerFailure);
      await container
          .read(votingConfigSourceProvider.notifier)
          .setCustom(secondSource);
      await container.read(votingConfigProvider.notifier).refresh();
      expect(container.read(votingConfigProvider).hasError, isTrue);
      expect(container.read(votingConfigProvider).error, newerFailure);

      staleGate.complete();
      await expectLater(staleLoad, throwsA(same(newerFailure)));
      expect(container.read(votingConfigProvider).hasError, isTrue);
      expect(container.read(votingConfigProvider).error, newerFailure);
    },
  );

  test(
    'stale config resolution does not invalidate rounds cache',
    () async {
      var resolveCount = 0;
      final staleLoadStarted = Completer<void>();
      final staleLoadGate = Completer<void>();
      final http = FakeVotingHttpClient(
        responses: {
          'https://voting.example/static-voting-config.json': staticConfigJson(),
          'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
          '/shielded-vote/v1/rounds': {
            'rounds': [
              {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
            ],
          },
          '/shielded-vote/v1/endorsed-rounds/zodl': {
            'vote_round_ids': [kRoundId],
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          votingConfigSourceStoreProvider.overrideWithValue(
            FakeVotingConfigSourceStore(),
          ),
          votingHttpClientProvider.overrideWithValue(http),
          votingConfigLoaderProvider.overrideWithValue(
            VotingConfigLoader(
              httpClient: http,
              sourceUrl: 'https://voting.example/static-voting-config.json',
              resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
              resolveVotingConfig: ({
                required source,
                required staticBytes,
                required dynamicBytes,
                previous,
              }) async {
                resolveCount++;
                if (resolveCount == 2) {
                  staleLoadStarted.complete();
                  await staleLoadGate.future;
                  return fakeResolveVotingConfig(
                    dynamicBytes: dynamicBytes,
                    previous: previous,
                    switchKind: rust_config.ConfigSwitchKind.newChainOrRound,
                    authenticatedRoundIds: const [kRoundId],
                  );
                }
                return fakeResolveVotingConfig(
                  dynamicBytes: dynamicBytes,
                  previous: previous,
                  switchKind: previous == null
                      ? rust_config.ConfigSwitchKind.initialLoad
                      : rust_config.ConfigSwitchKind.unchanged,
                  authenticatedRoundIds: const [kRoundId],
                );
              },
            ),
          ),
          votingActiveAccountUuidProvider.overrideWithValue(() async => null),
        ],
      );
      addTearDown(container.dispose);

      await container.read(votingRoundsProvider.future);
      final roundsCallsBefore = http.requests
          .where((request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'))
          .length;

      final staleRefresh = container.read(votingConfigProvider.notifier).refresh();
      await staleLoadStarted.future;

      await container.read(votingConfigProvider.notifier).refresh();
      await container.read(votingRoundsProvider.future);
      final roundsCallsBeforeStaleCompletion = http.requests
          .where((request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'))
          .length;

      staleLoadGate.complete();
      await staleRefresh;
      await container.read(votingRoundsProvider.future);
      final roundsCallsAfterStaleCompletion = http.requests
          .where((request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'))
          .length;

      expect(roundsCallsBeforeStaleCompletion, roundsCallsBefore);
      expect(roundsCallsAfterStaleCompletion, roundsCallsBeforeStaleCompletion);
    },
  );

  test('config switch newChainOrRound invalidates rounds provider', () async {
    var refreshCount = 0;
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
        },
        '/shielded-vote/v1/endorsed-rounds/zodl': {
          'vote_round_ids': [kRoundId],
        },
      },
    );
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(
          FakeVotingConfigSourceStore(),
        ),
        votingHttpClientProvider.overrideWithValue(http),
        votingConfigLoaderProvider.overrideWithValue(
          VotingConfigLoader(
            httpClient: http,
            sourceUrl: 'https://voting.example/static-voting-config.json',
            resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
            resolveVotingConfig: ({
              required source,
              required staticBytes,
              required dynamicBytes,
              previous,
            }) => fakeResolveVotingConfig(
              dynamicBytes: dynamicBytes,
              previous: previous,
              switchKind: refreshCount++ == 0
                  ? rust_config.ConfigSwitchKind.initialLoad
                  : rust_config.ConfigSwitchKind.newChainOrRound,
              authenticatedRoundIds: const [kRoundId],
            ),
          ),
        ),
        votingActiveAccountUuidProvider.overrideWithValue(() async => null),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingRoundsProvider.future);
    final roundsCallsBefore = http.requests
        .where((request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'))
        .length;

    await container.read(votingConfigProvider.notifier).refresh();
    await container.read(votingRoundsProvider.future);
    final roundsCallsAfter = http.requests
        .where((request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'))
        .length;

    expect(roundsCallsAfter, greaterThan(roundsCallsBefore));
  });

  test('config switch unchanged keeps rounds provider cache', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
        },
        '/shielded-vote/v1/endorsed-rounds/zodl': {
          'vote_round_ids': [kRoundId],
        },
      },
    );
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(
          FakeVotingConfigSourceStore(),
        ),
        votingHttpClientProvider.overrideWithValue(http),
        votingConfigLoaderProvider.overrideWithValue(
          VotingConfigLoader(
            httpClient: http,
            sourceUrl: 'https://voting.example/static-voting-config.json',
            resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
            resolveVotingConfig: ({
              required source,
              required staticBytes,
              required dynamicBytes,
              previous,
            }) => fakeResolveVotingConfig(
              dynamicBytes: dynamicBytes,
              previous: previous,
              switchKind: previous == null
                  ? rust_config.ConfigSwitchKind.initialLoad
                  : rust_config.ConfigSwitchKind.unchanged,
              authenticatedRoundIds: const [kRoundId],
            ),
          ),
        ),
        votingActiveAccountUuidProvider.overrideWithValue(() async => null),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingRoundsProvider.future);
    final roundsCallsBefore = http.requests
        .where((request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'))
        .length;

    await container.read(votingConfigProvider.notifier).refresh();
    await container.read(votingRoundsProvider.future);
    final roundsCallsAfter = http.requests
        .where((request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'))
        .length;

    expect(roundsCallsAfter, roundsCallsBefore);
  });

  test('config source provider persists named saved sources', () async {
    final store = FakeVotingConfigSourceStore();
    final container = _container(
      http: FakeVotingHttpClient(responses: votingHttpResponses()),
      sourceStore: store,
    );
    addTearDown(container.dispose);

    await container.read(votingConfigSourceProvider.future);
    await container
        .read(votingConfigSourceProvider.notifier)
        .saveSource(
          name: 'Stage',
          sourceUrl: 'https://voting.example/static-voting-config.json',
        );

    final selected = container.read(votingConfigSourceProvider).value!;
    expect(selected.isDefault, isFalse);
    expect(
      selected.sourceUrl,
      'https://voting.example/static-voting-config.json',
    );
    expect(selected.savedSources, hasLength(1));
    expect(selected.savedSources.single.name, 'Stage');
    expect(store.savedSourcesJson, isNotNull);

    final restored = _container(
      http: FakeVotingHttpClient(responses: votingHttpResponses()),
      sourceStore: store,
    );
    addTearDown(restored.dispose);

    final restoredState = await restored.read(
      votingConfigSourceProvider.future,
    );
    expect(restoredState.savedSources, hasLength(1));
    expect(restoredState.savedSources.single.name, 'Stage');
    expect(restoredState.sourceUrl, selected.sourceUrl);
  });

  test('deleting active saved config source falls back to default', () async {
    final store = FakeVotingConfigSourceStore();
    final container = _container(
      http: FakeVotingHttpClient(responses: votingHttpResponses()),
      sourceStore: store,
    );
    addTearDown(container.dispose);

    await container.read(votingConfigSourceProvider.future);
    await container
        .read(votingConfigSourceProvider.notifier)
        .saveSource(
          name: 'Stage',
          sourceUrl: 'https://voting.example/static-voting-config.json',
        );
    final saved = container
        .read(votingConfigSourceProvider)
        .value!
        .savedSources
        .single;

    await container
        .read(votingConfigSourceProvider.notifier)
        .deleteSavedSource(saved.id);

    final next = container.read(votingConfigSourceProvider).value!;
    expect(next.isDefault, isTrue);
    expect(next.sourceUrl, kDefaultStaticVotingConfigSource);
    expect(next.savedSources, isEmpty);
    expect(store.sourceUrl, isNull);
  });

  test('rounds provider merges endorsed and unverified rows', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
            {
              'vote_round_id': kOtherRoundId,
              'title': 'Other',
              'status': 'active',
            },
          ],
        },
        '/shielded-vote/v1/endorsed-rounds/zodl': {
          'vote_round_ids': [kRoundId],
        },
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final rounds = await container.read(votingRoundsProvider.future);

    expect(rounds, hasLength(2));
    expect(rounds.first.endorsed, isTrue);
    expect(rounds.first.unverified, isFalse);
    expect(rounds.first.roundId, kRoundId);
    expect(rounds.last.endorsed, isFalse);
    expect(rounds.last.unverified, isTrue);
    expect(rounds.last.roundId, kOtherRoundId);
  });

  test('rounds provider filters to authenticated round IDs', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
            {
              'vote_round_id': kOtherRoundId,
              'title': 'Other',
              'status': 'active',
            },
          ],
        },
        '/shielded-vote/v1/endorsed-rounds/zodl': {
          'vote_round_ids': [kRoundId],
        },
      },
    );
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(
          FakeVotingConfigSourceStore(),
        ),
        votingHttpClientProvider.overrideWithValue(http),
        votingConfigLoaderProvider.overrideWithValue(
          VotingConfigLoader(
            httpClient: http,
            sourceUrl: 'https://voting.example/static-voting-config.json',
            resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
            resolveVotingConfig: ({
              required source,
              required staticBytes,
              required dynamicBytes,
              previous,
            }) => fakeResolveVotingConfig(
              dynamicBytes: dynamicBytes,
              previous: previous,
              authenticatedRoundIds: const [kRoundId],
            ),
          ),
        ),
        votingActiveAccountUuidProvider.overrideWithValue(() async => null),
      ],
    );
    addTearDown(container.dispose);

    final rounds = await container.read(votingRoundsProvider.future);
    expect(rounds.map((round) => round.roundId), [kRoundId]);
  });

  test('rounds provider does not filter by endorsements set', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
            {
              'vote_round_id': kOtherRoundId,
              'title': 'Finalized',
              'status': 'finalized',
            },
          ],
        },
        '/shielded-vote/v1/endorsed-rounds/zodl': {
          'vote_round_ids': [kRoundId],
        },
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final rounds = await container.read(votingRoundsProvider.future);
    expect(rounds.map((round) => round.roundId), [kRoundId, kOtherRoundId]);
  });

  test(
    'rounds provider marks locally completed active rounds as voted',
    () async {
      final http = FakeVotingHttpClient(
        responses: {
          'https://voting.example/static-voting-config.json':
              staticConfigJson(),
          'https://voting.example/dynamic-voting-config.json':
              dynamicConfigJson(),
          '/shielded-vote/v1/rounds': {
            'rounds': [
              {
                'vote_round_id': kRoundId,
                'title': 'Poll',
                'status': 'active',
                'proposals': [
                  {
                    'id': 7,
                    'title': 'Question',
                    'options': [
                      {'index': 0, 'label': 'Yes'},
                      {'index': 1, 'label': 'No'},
                    ],
                  },
                ],
              },
            ],
          },
          '/shielded-vote/v1/endorsed-rounds/zodl': {
            'vote_round_ids': [kRoundId],
          },
        },
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
          ],
          shareDelegations: [
            rust_frb_types.ShareDelegationRecordView(
              roundId: kRoundId,
              bundleIndex: 0,
              proposalId: 7,
              shareIndex: 0,
              sentToUrls: const ['https://voting.example'],
              nullifier: Uint8List.fromList(List.filled(32, 1)),
              phase: VotingWorkflowPhase.submittedShare,
              confirmed: false,
              submitAt: BigInt.zero,
              createdAt: BigInt.zero,
            ),
          ],
          unconfirmedShareDelegations: [
            rust_frb_types.ShareDelegationRecordView(
              roundId: kRoundId,
              bundleIndex: 0,
              proposalId: 7,
              shareIndex: 0,
              sentToUrls: const ['https://voting.example'],
              nullifier: Uint8List.fromList(List.filled(32, 1)),
              phase: VotingWorkflowPhase.submittedShare,
              confirmed: false,
              submitAt: BigInt.zero,
              createdAt: BigInt.zero,
            ),
          ],
        ),
        roundPlan: apiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          blockingRecovery: false,
          completedVoteArtifact: true,
          completedForDisplay: true,
          completedVoteDisplay: rust_wire.CompletedVoteDisplayView(
            choices: const [
              rust_wire.CompletedVoteChoiceView(proposalId: 7, choice: null),
            ],
          ),
          nextSteps: const [
            rust_wire.NextStepView(
              kind: 'confirm_share',
              bundleIndex: 0,
              proposalId: 7,
              choice: 0,
              shareIndex: 0,
            ),
          ],
          openProposals: Uint32List(0),
          allDecided: true,
        ),
      );
      final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
      addTearDown(container.dispose);

      final rounds = await container.read(votingRoundsProvider.future);

      expect(rounds.single.voted, isTrue);
    },
  );

  test('session provider rejects explicitly skipped round IDs', () async {
    final http = FakeVotingHttpClient(responses: votingHttpResponses());
    final container = _sessionContainer(
      http: http,
      authenticatedRoundIds: const [kOtherRoundId],
      authenticatedRoundEaPks: {
        kOtherRoundId: Uint8List.fromList(List.filled(32, 7)),
      },
      skippedRoundIds: const [kRoundId],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(votingSessionProvider(kRoundId).future),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('not authenticated by voting config'),
            contains('failed dynamic-config authentication'),
          ),
        ),
      ),
    );
    expect(
      http.requests.any(
        (request) => request.uri.path == '/shielded-vote/v1/round/$kRoundId',
      ),
      isFalse,
    );
  });

  test('session provider rejects rounds absent from the authenticated set', () async {
    final http = FakeVotingHttpClient(responses: votingHttpResponses());
    final container = _sessionContainer(
      http: http,
      authenticatedRoundIds: const [kOtherRoundId],
      authenticatedRoundEaPks: {
        kOtherRoundId: Uint8List.fromList(List.filled(32, 7)),
      },
      skippedRoundIds: const [],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(votingSessionProvider(kRoundId).future),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('not authenticated by voting config'),
            contains('absent from the authenticated round set'),
          ),
        ),
      ),
    );
    expect(
      http.requests.any(
        (request) => request.uri.path == '/shielded-vote/v1/round/$kRoundId',
      ),
      isFalse,
    );
  });

  test('session provider uses Rust-assembled trusted round params', () async {
    final rust = FakeVotingRustApi();
    final serverRoundStatus = roundStatusJson(roundId: kRoundId)
      ..['ea_pk'] = _bytes1x32Base64;
    final container = _sessionContainer(
      http: FakeVotingHttpClient(
        responses: votingHttpResponses(roundStatus: serverRoundStatus),
      ),
      rust: rust,
      authenticatedRoundIds: const [kRoundId],
      authenticatedRoundEaPks: {
        kRoundId: Uint8List.fromList(List.filled(32, 7)),
      },
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);

    expect(rust.trustedRoundParamsCalls, 1);
    expect(
      rust.lastTrustedRoundParams?.eaPk,
      orderedEquals(List.filled(32, 7)),
    );
  });

  test(
    'rounds provider loads planner state when summaries omit proposals',
    () async {
      final roundStatusWithProposals = roundStatusJson(roundId: kRoundId)
        ..['proposals'] = [
          {
            'id': 7,
            'title': 'Question',
            'options': [
              {'index': 0, 'label': 'Yes'},
              {'index': 1, 'label': 'No'},
            ],
          },
        ];
      final http = FakeVotingHttpClient(
        responses: {
          ...votingHttpResponses(roundStatus: roundStatusWithProposals),
          '/shielded-vote/v1/rounds': {
            'rounds': [
              {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
            ],
          },
          '/shielded-vote/v1/endorsed-rounds/zodl': {
            'vote_round_ids': [kRoundId],
          },
        },
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(),
        roundPlan: apiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          nextSteps: const [
            rust_wire.NextStepView(
              kind: 'vote',
              bundleIndex: 0,
              proposalId: 7,
              choice: 1,
              shareIndex: 0,
            ),
          ],
          openProposals: Uint32List(0),
          allDecided: false,
        ),
      );
      final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
      addTearDown(container.dispose);

      final rounds = await container.read(votingRoundsProvider.future);

      expect(rounds.single.inProgress, isTrue);
      expect(recoveryApi.roundPlanProposalIds, [
        [7],
      ]);
      expect(
        http.requests.any(
          (request) =>
              request.method == 'GET' &&
              request.uri.path == '/shielded-vote/v1/round/$kRoundId',
        ),
        isTrue,
      );
    },
  );

  test('rounds reload fails closed when refresh fails', () async {
    final responses = <String, Object>{
      'https://voting.example/static-voting-config.json': staticConfigJson(),
      'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
      '/shielded-vote/v1/rounds': {
        'rounds': [
          {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
        ],
      },
      '/shielded-vote/v1/endorsed-rounds/zodl': {
        'vote_round_ids': [kRoundId],
      },
    };
    final http = FakeVotingHttpClient(responses: responses);
    final container = _sessionContainer(http: http);
    addTearDown(container.dispose);

    await container.read(votingRoundsProvider.future);
    responses['/shielded-vote/v1/rounds'] = StateError('network down');
    await container.read(votingRoundsProvider.notifier).reload();

    final reloaded = container.read(votingRoundsProvider);
    expect(reloaded.hasError, isTrue);
    expect(reloaded.error, isA<StateError>());
  });

  test('round details normalize base64 vote_round_id to hex', () {
    final details = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(roundId: kEncodedRoundId)..remove('round_id'),
      ),
    );

    expect(details.roundId, kEncodedRoundIdHex);
  });

  test('round details use the validated status round id', () {
    final json = roundStatusJson(roundId: kEncodedRoundId)
      ..['round_id'] = kOtherRoundId
      ..['id'] = kOtherRoundId;

    final details = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(json),
    );

    expect(details.roundId, kEncodedRoundIdHex);
  });

  test('round details expose last-moment scheduling window', () {
    final details = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(roundId: kRoundId, ceremonyStart: 1000, voteEnd: 1600),
      ),
    );

    expect(
      details.ceremonyStart,
      DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
    );
    expect(
      details.voteEndTime,
      DateTime.fromMillisecondsSinceEpoch(1600000, isUtc: true),
    );
    expect(details.lastMomentBuffer, const Duration(seconds: 240));
    expect(
      details.isLastMoment(
        DateTime.fromMillisecondsSinceEpoch(1359000, isUtc: true),
      ),
      isFalse,
    );
    expect(
      details.isLastMoment(
        DateTime.fromMillisecondsSinceEpoch(1360000, isUtc: true),
      ),
      isTrue,
    );
  });

  test('round details cap last-moment buffer and reject invalid timing', () {
    final capped = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(
          roundId: kRoundId,
          ceremonyStart: 1000,
          voteEnd: 100000,
        ),
      ),
    );
    final invalid = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(roundId: kRoundId, ceremonyStart: 2000, voteEnd: 1000),
      ),
    );

    expect(capped.lastMomentBuffer, const Duration(hours: 6));
    expect(invalid.lastMomentBuffer, isNull);
    expect(
      invalid.isLastMoment(
        DateTime.fromMillisecondsSinceEpoch(1500000, isUtc: true),
      ),
      isFalse,
    );
  });

  test('empty all-decided plan is not a completed submission', () async {
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(bundleCount: 0),
      roundPlan: apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        allDecided: true,
      ),
    );
    final container = _sessionContainer(recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    final state = await container.read(votingSessionProvider(kRoundId).future);

    expect(state.phase, VotingSessionPhase.idle);
    expect(state.roundPlan?.completedVoteArtifact, isFalse);
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
    expect(state.error?.message, contains('Voting PIR data is not ready'));
    expect(state.error?.message, contains('123'));
    expect(state.error?.message, contains('122'));
    expect(state.error?.pirDiagnostics, hasLength(1));
    expect(rust.setupCalls, 0);
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test('wallet sync guard waits before delegation setup', () async {
    final rust = FakeVotingRustApi();
    final readiness = FakeVotingWalletSyncReadinessChecker(
      responses: const [
        VotingWalletSyncReadiness(
          scannedHeight: 122,
          snapshotHeight: 123,
          chainTipHeight: 130,
        ),
        VotingWalletSyncReadiness(
          scannedHeight: 123,
          snapshotHeight: 123,
          chainTipHeight: 130,
        ),
      ],
    );
    var syncStartCalls = 0;
    final container = _sessionContainer(
      rust: rust,
      walletSyncReadinessChecker: readiness,
      walletSyncStarter: () {
        syncStartCalls++;
      },
      walletSyncPollInterval: Duration.zero,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareDelegation();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(readiness.calls, 2);
    expect(syncStartCalls, 1);
    expect(rust.setupCalls, 1);
    expect(state.phase, VotingSessionPhase.readyToDelegate);
  });

  test('wallet sync wait aborts stale account before queued action', () async {
    final rust = FakeVotingRustApi();
    final readiness = FakeVotingWalletSyncReadinessChecker(
      responses: const [
        VotingWalletSyncReadiness(
          scannedHeight: 122,
          snapshotHeight: 123,
          chainTipHeight: 130,
        ),
        VotingWalletSyncReadiness(
          scannedHeight: 123,
          snapshotHeight: 123,
          chainTipHeight: 130,
        ),
      ],
    );
    var syncStartCalls = 0;
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final container = _sessionContainer(
      rust: rust,
      activeAccountUuidListenable: activeAccountProvider,
      walletSyncReadinessChecker: readiness,
      walletSyncStarter: () {
        syncStartCalls++;
      },
      walletSyncPollInterval: const Duration(milliseconds: 100),
    );
    final subscription = container.listen(
      votingSessionProvider(kRoundId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    final stalePrepare = notifier.prepareDelegation();
    while (readiness.calls < 1) {
      await Future<void>.delayed(Duration.zero);
    }

    container.read(activeAccountProvider.notifier).set('account-2');
    await Future<void>.delayed(Duration.zero);
    final reloaded = await container.read(
      votingSessionProvider(kRoundId).future,
    );
    expect(reloaded.accountUuid, 'account-2');

    final currentPrepare = container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareDelegation();
    await Future.wait([
      stalePrepare,
      currentPrepare,
    ]).timeout(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 110));
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(readiness.calls, 2);
    expect(syncStartCalls, 1);
    expect(rust.setupCalls, 1);
    expect(rust.accountUuids, ['account-2']);
    expect(state.accountUuid, 'account-2');
    expect(state.phase, VotingSessionPhase.readyToDelegate);
  });

  test(
    'PIR endpoint without identity is accepted when root height matches',
    () async {
      final rust = FakeVotingRustApi();
      final pir = PirSnapshotResolver(
        httpClient: FakeVotingHttpClient(
          responses: {
            'https://pir.example/root': {'height': 123},
          },
        ),
      );
      final container = _sessionContainer(rust: rust, pirResolver: pir);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareDelegation();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.pirEndpoint, Uri.parse('https://pir.example'));
      expect(
        state.pirDiagnostics.single.status,
        PirSnapshotEndpointStatus.matched,
      );
      expect(rust.setupCalls, 1);
    },
  );

  test('resume after delegated does not rebuild delegation bundle', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-tx',
            vanLeafPosition: null,
          ),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.setupCalls, 1);
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test('submitted delegation timeout surfaces resumable tx context', () async {
    final httpResponses = votingHttpResponses()
      ..['/shielded-vote/v1/tx/submitted-delegation-tx'] = jsonResponse({
        'error': 'not found',
      }, statusCode: 404);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationWorkflows: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'submitted-delegation-tx',
            vanLeafPosition: null,
          ),
        ],
      ),
    );
    final container = _sessionContainer(
      http: FakeVotingHttpClient(responses: httpResponses),
      recoveryApi: recoveryApi,
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('submitted-delegation-tx'));
    expect(state.error?.message, contains('bundle 0'));
    expect(state.error?.message, contains('Retry to resume confirmation'));
  });

  test('delegation submits chain payload and stores recovery state', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.delegationBundleCalls, [0]);
    expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
    expect(rust.storedVanPositions, ['0:0']);
  });

  test('delegation stream errors surface the Rust failure', () async {
    final rust = FakeVotingRustApi(
      delegationStreamError: StateError(
        'network: gRPC connect failed: transport error',
      ),
    );
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('gRPC connect failed'));
    expect(
      state.error?.message,
      isNot(contains('Delegation proof completed without submission payload')),
    );
    expect(rust.delegationBundleCalls, [0]);
    expect(rust.storedDelegationTxHashes, isEmpty);
  });

  test('hardware voting prepares Keystone signing request', () async {
    final rust = FakeVotingRustApi();
    final hotkeyStore = FakeVotingHotkeyStore(null);
    final container = _sessionContainer(
      rust: rust,
      accountIsHardware: true,
      hotkeyStore: hotkeyStore,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.keystoneSigning);
    expect(state.isHardwareAccount, isTrue);
    expect(state.keystoneSigningRequest?.bundleIndex, 0);
    expect(hotkeyStore.hotkey, [42, 43, 44]);
    expect(rust.generateVotingHotkeyCalls, 1);
    expect(rust.keystoneDelegationRequestCalls, [0, 0]);
  });

  test(
    'hardware voting permits prepared-only recovery without stored hotkey',
    () async {
      final rust = FakeVotingRustApi();
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          delegationWorkflows: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.prepared,
              txHash: null,
              vanLeafPosition: null,
            ),
          ],
        ),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
        hotkeyStore: hotkeyStore,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneSigningRequest?.bundleIndex, 0);
      expect(hotkeyStore.hotkey, [42, 43, 44]);
      expect(rust.setupCalls, 1);
      expect(rust.generateVotingHotkeyCalls, 1);
      expect(rust.keystoneDelegationRequestCalls, [0]);
    },
  );

  test('software delegation entry point rejects hardware sessions', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust, accountIsHardware: true);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('Keystone'));
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test(
    'hardware voting rejects wrong Keystone signature without storing',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([99, 0]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneScanError, contains('different voting bundle'));
      expect(rust.storedKeystoneSignatures, isEmpty);
      expect(rust.parseSignedVotingPcztCalls, 1);
    },
  );

  test(
    'hardware voting rejects duplicate Keystone signature without storing',
    () async {
      final rust = FakeVotingRustApi();
      rust.storedKeystoneSignatures[1] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 1,
        sig: Uint8List.fromList(const [7]),
        sighash: Uint8List.fromList(const [99, 0]),
        rk: Uint8List.fromList(const [8]),
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([99, 0]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneScanError, contains('already scanned'));
      expect(rust.parseSignedVotingPcztCalls, 1);
    },
  );

  test(
    'hardware voting stores valid Keystone signature and becomes ready',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([10, 0]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.keystoneSigningRequest, isNull);
      expect(state.keystoneSignatures.keys, [0]);
      expect(rust.storedKeystoneSignatures[0]?.sig, [3, 0]);
    },
  );

  test('hardware voting advances signing across multiple bundles', () async {
    final rust = FakeVotingRustApi(bundleCount: 2);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(bundleCount: 2),
    );
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: recoveryApi,
      accountIsHardware: true,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .handleKeystoneSignedPczt([10, 0]);
    var state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.keystoneSigning);
    expect(state.keystoneSigningRequest?.bundleIndex, 1);
    expect(state.keystoneSignatures.keys, [0]);
    expect(rust.keystoneDelegationRequestCalls, [0, 1]);

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .handleKeystoneSignedPczt([10, 1]);
    state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.readyToDelegate);
    expect(state.keystoneSigningRequest, isNull);
    expect(state.keystoneSignatures.keys, [0, 1]);

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundlesWithKeystoneSignatures();
    state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.keystoneProofBundleCalls, [0, 1]);
    expect(rust.storedDelegationTxHashes, [
      '0:delegation-tx',
      '1:delegation-tx',
    ]);
  });

  test(
    'hardware voting can skip unsigned Keystone bundles after prefix signed',
    () async {
      late FakeVotingRecoveryApi recoveryApi;
      final rust = FakeVotingRustApi(
        bundleCount: 2,
        onDeleteSkippedBundles: (keepCount) {
          recoveryApi.state = recoveryState(bundleCount: keepCount);
        },
      );
      recoveryApi = FakeVotingRecoveryApi(state: recoveryState(bundleCount: 2));
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([10, 0]);
      var state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneSigningRequest?.bundleIndex, 1);
      expect(state.canSkipRemainingKeystoneBundles, isTrue);

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .skipRemainingKeystoneBundles();
      state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.resumePlan?.bundleCount, 1);
      expect(state.keystoneSigningRequest, isNull);
      expect(rust.deleteSkippedBundleKeepCounts, [1]);
      expect(rust.storedKeystoneSignatures.keys, [0]);

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.delegated);
      expect(rust.keystoneProofBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
    },
  );

  test(
    'hardware voting cannot skip across missing Keystone bundle prefix',
    () async {
      final rust = FakeVotingRustApi(bundleCount: 2);
      rust.storedKeystoneSignatures[1] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 1,
        sig: Uint8List.fromList(const [3, 1]),
        sighash: Uint8List.fromList(const [10, 1]),
        rk: Uint8List.fromList(const [2, 1]),
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(bundleCount: 2),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      var state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.keystoneSigningRequest?.bundleIndex, 0);
      expect(state.canSkipRemainingKeystoneBundles, isFalse);

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .skipRemainingKeystoneBundles();
      state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('Sign at least one'));
      expect(rust.deleteSkippedBundleKeepCounts, isEmpty);
    },
  );

  test(
    'hardware voting does not regenerate hotkey after stored signature',
    () async {
      final rust = FakeVotingRustApi(bundleCount: 2);
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(bundleCount: 2),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
        hotkeyStore: FakeVotingHotkeyStore(null),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('missing stored Keystone'));
      expect(rust.generateVotingHotkeyCalls, 0);
      expect(rust.keystoneDelegationRequestCalls, isEmpty);
    },
  );

  test(
    'hardware voting submits delegation with stored Keystone signature',
    () async {
      final rust = FakeVotingRustApi();
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.delegated);
      expect(rust.keystoneProofBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
      expect(rust.storedVanPositions, ['0:0']);
    },
  );

  test(
    'hardware voting does not regenerate hotkey while submitting signatures',
    () async {
      final rust = FakeVotingRustApi();
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final container = _sessionContainer(
        rust: rust,
        accountIsHardware: true,
        hotkeyStore: FakeVotingHotkeyStore(null),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('missing stored Keystone'));
      expect(rust.generateVotingHotkeyCalls, 0);
      expect(rust.keystoneProofBundleCalls, isEmpty);
      expect(rust.storedDelegationTxHashes, isEmpty);
    },
  );

  test(
    'hardware voting rejects mismatched Keystone submission payload',
    () async {
      final rust = FakeVotingRustApi(mismatchKeystoneSubmission: true);
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('did not match'));
      expect(rust.keystoneProofBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, isEmpty);
    },
  );

  test('session keeps using account from initial round load', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(state: recoveryState());
    final activeAccount = _MutableActiveAccount('account-1');
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: recoveryApi,
      activeAccountUuid: activeAccount.call,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    activeAccount.value = 'account-2';
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);

    expect(rust.accountUuids.toSet(), {'account-1'});
    expect(recoveryApi.walletIds.toSet(), {'account-1'});
  });

  test('session reloads same round when active account changes', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(state: recoveryState());
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: recoveryApi,
      activeAccountUuidListenable: activeAccountProvider,
      hardwareAccountUuids: {'account-2'},
    );
    final subscription = container.listen(
      votingSessionProvider(kRoundId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final first = await container.read(votingSessionProvider(kRoundId).future);
    expect(first.accountUuid, 'account-1');
    expect(first.isHardwareAccount, isFalse);

    container.read(activeAccountProvider.notifier).set('account-2');
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(votingSessionProvider(kRoundId)).value?.accountUuid,
      isNot('account-1'),
    );
    final second = await container.read(votingSessionProvider(kRoundId).future);

    expect(second.accountUuid, 'account-2');
    expect(second.isHardwareAccount, isTrue);
    expect(
      recoveryApi.walletIds,
      containsAllInOrder(['account-1', 'account-2']),
    );
    expect(rust.resetVotingSessionStateCalls, contains('account-1:$kRoundId'));
  });

  test('submission job stays pinned after active account changes', () async {
    final readiness = _GatedVotingWalletSyncReadinessChecker();
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final container = _sessionContainer(
      activeAccountUuidListenable: activeAccountProvider,
      walletSyncReadinessChecker: readiness,
      walletSyncPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(container.dispose);

    final key = await container
        .read(votingSubmissionJobsProvider.notifier)
        .start(kRoundId);
    expect(key, isNotNull);
    await readiness.firstCheck.future;
    await _waitForJobSessionPhase(
      container,
      key!,
      VotingSessionPhase.waitingForWalletSync,
    );

    expect(key.accountUuid, 'account-1');
    expect(
      container.read(votingSubmissionJobProvider(key)).status,
      VotingSubmissionJobStatus.running,
    );
    expect(
      container
          .read(votingSubmissionGuardProvider.notifier)
          .guardForAccount('account-1')
          ?.accountUuid,
      'account-1',
    );
    expect(
      container.read(votingSubmissionJobSessionProvider(key)).value?.phase,
      VotingSessionPhase.waitingForWalletSync,
    );

    container.read(activeAccountProvider.notifier).set('account-2');
    await Future<void>.delayed(Duration.zero);

    expect(container.read(votingSubmissionJobProvider(key)).key, key);
    expect(
      container
          .read(votingSubmissionJobSessionProvider(key))
          .value
          ?.accountUuid,
      'account-1',
    );

    readiness.allowReady();
    final failed = await _waitForJobStatus(
      container,
      key,
      VotingSubmissionJobStatus.error,
    );

    expect(failed.key, key);
    expect(failed.errorMessage, 'Choose at least one vote before submitting.');
    expect(
      container
          .read(votingSubmissionGuardProvider.notifier)
          .guardForAccount('account-1'),
      isNull,
    );
  });

  test('submission jobs run independently for multiple accounts', () async {
    final readiness = _GatedVotingWalletSyncReadinessChecker();
    final container = _sessionContainer(
      walletSyncReadinessChecker: readiness,
      walletSyncPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(container.dispose);

    final manager = container.read(votingSubmissionJobsProvider.notifier);
    final firstKey = await manager.start(kRoundId, accountUuid: 'account-1');
    final secondKey = await manager.start(kRoundId, accountUuid: 'account-2');
    expect(firstKey, isNotNull);
    expect(secondKey, isNotNull);

    await _waitForJobSessionPhase(
      container,
      firstKey!,
      VotingSessionPhase.waitingForWalletSync,
    );
    await _waitForJobSessionPhase(
      container,
      secondKey!,
      VotingSessionPhase.waitingForWalletSync,
    );

    expect(container.read(votingSubmissionJobsProvider).jobKeys, [
      firstKey,
      secondKey,
    ]);
    expect(
      container
          .read(votingSubmissionGuardProvider.notifier)
          .guardForAccount('account-1')
          ?.roundId,
      kRoundId,
    );
    expect(
      container
          .read(votingSubmissionGuardProvider.notifier)
          .guardForAccount('account-2')
          ?.roundId,
      kRoundId,
    );

    readiness.allowReady();
    final firstFailed = await _waitForJobStatus(
      container,
      firstKey,
      VotingSubmissionJobStatus.error,
    );
    final secondFailed = await _waitForJobStatus(
      container,
      secondKey,
      VotingSubmissionJobStatus.error,
    );

    expect(firstFailed.key, firstKey);
    expect(secondFailed.key, secondKey);
    expect(
      firstFailed.errorMessage,
      'Choose at least one vote before submitting.',
    );
    expect(
      secondFailed.errorMessage,
      'Choose at least one vote before submitting.',
    );
  });

  test(
    'software vote-only submission seeds hotkey without delegation',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true);
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final roundStatus = roundStatusJson(roundId: kRoundId)
        ..['proposals'] = [
          {
            'id': 7,
            'title': 'Question',
            'options': [
              {'index': 0, 'label': 'No'},
              {'index': 1, 'label': 'Yes'},
            ],
          },
        ];
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(roundStatus: roundStatus),
      );
      final draftPersistence = FakeVotingDraftPersistence();
      const key = VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1');
      await draftPersistence.save(key, const VotingDraftState(choices: {7: 1}));
      const castStep = rust_wire.NextStepView(
        kind: 'cast_vote',
        bundleIndex: 0,
        proposalId: 7,
        choice: 1,
        shareIndex: 0,
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(bundleCount: 1),
        roundPlan: apiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          nextSteps: const [castStep],
          openProposals: Uint32List.fromList(const [7]),
          allDecided: false,
          needsDraftSetup: false,
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
        draftPersistence: draftPersistence,
        hotkeyStore: hotkeyStore,
      );
      addTearDown(container.dispose);

      final startedKey = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      expect(startedKey, key);
      await _waitForVoteCommitmentKey(rust, '0:7');

      expect(rust.setupCalls, 0);
      expect(rust.delegationBundleCalls, isEmpty);
      expect(rust.deriveHotkeyCalls, 1);
      expect(hotkeyStore.hotkey, isNotNull);
      expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 1);
    },
  );

  test(
    'software submission prepares draft setup before ballot intent',
    () async {
      final setupGate = Completer<void>();
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        setupGate: setupGate,
      );
      final roundStatus = roundStatusJson(roundId: kRoundId)
        ..['proposals'] = [
          {
            'id': 7,
            'title': 'Question',
            'options': [
              {'index': 0, 'label': 'No'},
              {'index': 1, 'label': 'Yes'},
            ],
          },
        ];
      final draftPersistence = FakeVotingDraftPersistence();
      const key = VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1');
      await draftPersistence.save(key, const VotingDraftState(choices: {7: 1}));
      final needsSetupPlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List.fromList(const [7]),
        allDecided: false,
        needsDraftSetup: true,
      );
      const delegateStep = rust_wire.NextStepView(
        kind: 'delegate',
        bundleIndex: 0,
        proposalId: 0,
        choice: 0,
        shareIndex: 0,
      );
      final delegatePlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [delegateStep],
        openProposals: Uint32List.fromList(const [7]),
        allDecided: false,
        needsDraftSetup: false,
      );
      const castStep = rust_wire.NextStepView(
        kind: 'cast_vote',
        bundleIndex: 0,
        proposalId: 7,
        choice: 1,
        shareIndex: 0,
      );
      final votePlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [castStep],
        openProposals: Uint32List.fromList(const [7]),
        allDecided: false,
        needsDraftSetup: false,
      );
      final completedPlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        allDecided: true,
        completedVoteArtifact: true,
        completedForDisplay: true,
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(bundleCount: 1),
        roundPlanSequence: [
          needsSetupPlan,
          needsSetupPlan,
          needsSetupPlan,
          delegatePlan,
          delegatePlan,
          votePlan,
          votePlan,
          completedPlan,
          completedPlan,
          completedPlan,
        ],
      );
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(roundStatus: roundStatus),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
        draftPersistence: draftPersistence,
      );
      addTearDown(container.dispose);

      final startedKey = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      expect(startedKey, key);
      await rust.setupStarted.future;

      expect(recoveryApi.ballotIntents, isEmpty);
      expect(rust.voteCommitmentKeys, isEmpty);

      setupGate.complete();
      final completed = await _waitForJobStatus(
        container,
        key,
        VotingSubmissionJobStatus.complete,
      );

      expect(completed.errorMessage, isNull);
      expect(rust.setupCalls, 1);
      expect(rust.delegationBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
      expect(recoveryApi.ballotIntents, ['7:2:false:1']);
      expect(rust.voteCommitmentKeys, ['0:7']);
    },
  );

  test(
    'software submission resumes submitted delegation without draft',
    () async {
      final rust = FakeVotingRustApi();
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: _submittedDelegationOnlyRecoveryApi(),
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      final startedKey = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      expect(
        startedKey,
        const VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1'),
      );
      await _waitForStoredVanPosition(rust, '0:0');
      final completed = await _waitForJobStatus(
        container,
        startedKey!,
        VotingSubmissionJobStatus.complete,
      );

      expect(completed.errorMessage, isNull);
      expect(rust.delegationBundleCalls, isEmpty);
      expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/shares'), 0);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
      expect(rust.storedVanPositions, ['0:0']);
      expect(rust.voteCommitmentKeys, isEmpty);
      expect(rust.recordedShares, isEmpty);
    },
  );

  test(
    'hardware submission resumes submitted delegation without draft',
    () async {
      final rust = FakeVotingRustApi();
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: _submittedDelegationOnlyRecoveryApi(),
        accountIsHardware: true,
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      final startedKey = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      expect(
        startedKey,
        const VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1'),
      );
      await _waitForStoredVanPosition(rust, '0:0');
      final completed = await _waitForJobStatus(
        container,
        startedKey!,
        VotingSubmissionJobStatus.complete,
      );

      expect(completed.errorMessage, isNull);
      expect(rust.keystoneDelegationRequestCalls, isEmpty);
      expect(rust.keystoneProofBundleCalls, isEmpty);
      expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/shares'), 0);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
      expect(rust.storedVanPositions, ['0:0']);
      expect(rust.voteCommitmentKeys, isEmpty);
      expect(rust.recordedShares, isEmpty);
    },
  );

  test(
    'submitted delegation recovery continues pending share recovery',
    () async {
      final shareNullifier = Uint8List.fromList(List.filled(32, 1));
      final shareId = _hexFromBytes(shareNullifier);
      final acceptedShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        nullifier: shareNullifier,
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.zero,
        createdAt: BigInt.one,
      );
      final rust = FakeVotingRustApi();
      final http = FakeVotingHttpClient(
        responses:
            votingHttpResponses(
              dynamicConfig: dynamicConfigJson(
                voteServers: const [
                  {'url': 'https://helper-a.example', 'label': 'helper-a'},
                ],
              ),
            )..addAll({
              'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  {'status': 'confirmed'},
            }),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: _submittedDelegationWithShareRecoveryApi(acceptedShare),
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      final startedKey = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      expect(
        startedKey,
        const VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1'),
      );
      await _waitForStoredVanPosition(rust, '0:0');
      await _waitForConfirmedShare(rust, '0:7:0');

      expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/shares'), 0);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
      expect(rust.confirmedShares, ['0:7:0']);
      expect(rust.voteCommitmentKeys, isEmpty);
    },
  );

  test(
    'accepted share tracking does not keep submission job running',
    () async {
      final shareNullifier = Uint8List.fromList(List.filled(32, 1));
      final acceptedShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        nullifier: shareNullifier,
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.zero,
        createdAt: BigInt.one,
      );
      final rust = FakeVotingRustApi();
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          dynamicConfig: dynamicConfigJson(
            voteServers: const [
              {'url': 'https://helper-a.example', 'label': 'helper-a'},
            ],
          ),
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: _submittedDelegationWithShareRecoveryApi(acceptedShare),
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      final startedKey = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      expect(
        startedKey,
        const VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1'),
      );
      await _waitForStoredVanPosition(rust, '0:0');
      final completed = await _waitForJobStatus(
        container,
        startedKey!,
        VotingSubmissionJobStatus.complete,
      );

      expect(completed.errorMessage, isNull);
      expect(
        container
            .read(votingSubmissionGuardProvider.notifier)
            .guardForAccount('account-1'),
        isNull,
      );
      expect(rust.confirmedShares, isEmpty);
    },
  );

  test('Keystone signing starts after active account reload', () async {
    final rust = FakeVotingRustApi();
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final container = _sessionContainer(
      rust: rust,
      activeAccountUuidListenable: activeAccountProvider,
      hardwareAccountUuids: {'account-2'},
    );
    final subscription = container.listen(
      votingSessionProvider(kRoundId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final first = await container.read(votingSessionProvider(kRoundId).future);
    expect(first.accountUuid, 'account-1');
    expect(first.isHardwareAccount, isFalse);

    container.read(activeAccountProvider.notifier).set('account-2');
    final second = await container.read(votingSessionProvider(kRoundId).future);
    expect(second.accountUuid, 'account-2');
    expect(second.isHardwareAccount, isTrue);

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.keystoneSigning);
    expect(state.keystoneSigningRequest?.bundleIndex, 0);
    expect(rust.keystoneDelegationRequestCalls, [0]);
    expect(rust.accountUuids, contains('account-2'));
  });

  test(
    'ignores stale session UI updates after active account changes',
    () async {
      final setupGate = Completer<void>();
      final rust = FakeVotingRustApi(setupGate: setupGate);
      final activeAccountProvider =
          NotifierProvider<_ActiveVotingAccountNotifier, String?>(
            _ActiveVotingAccountNotifier.new,
          );
      final container = _sessionContainer(
        rust: rust,
        activeAccountUuidListenable: activeAccountProvider,
      );
      final subscription = container.listen(
        votingSessionProvider(kRoundId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final prepare = container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareDelegation();
      await rust.setupStarted.future;

      container.read(activeAccountProvider.notifier).set('account-2');
      await Future<void>.delayed(Duration.zero);
      setupGate.complete();
      await prepare;
      await Future<void>.delayed(Duration.zero);
      await container.read(votingSessionProvider(kRoundId).future);

      final state = container.read(votingSessionProvider(kRoundId)).value!;
      expect(state.accountUuid, 'account-2');
      expect(state.eligibleWeightZatoshi, isNull);
    },
  );

  test(
    'does not surface stale action errors while reloading switched account',
    () async {
      final setupGate = Completer<void>();
      final rust = FakeVotingRustApi(setupGate: setupGate);
      final activeAccountProvider =
          NotifierProvider<_ActiveVotingAccountNotifier, String?>(
            _ActiveVotingAccountNotifier.new,
          );
      final container = _sessionContainer(
        rust: rust,
        activeAccountUuidListenable: activeAccountProvider,
      );
      final subscription = container.listen(
        votingSessionProvider(kRoundId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final prepare = container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareDelegation();
      await rust.setupStarted.future;

      container.read(activeAccountProvider.notifier).set('account-2');
      await Future<void>.delayed(Duration.zero);

      final reloaded = await container.read(
        votingSessionProvider(kRoundId).future,
      );
      expect(reloaded.accountUuid, 'account-2');
      expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);

      setupGate.complete();
      await prepare;
    },
  );

  test(
    'delegation does not submit after active account changes during proof',
    () async {
      final proofGate = Completer<void>();
      final rust = FakeVotingRustApi(delegationProofGate: proofGate);
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final activeAccountProvider =
          NotifierProvider<_ActiveVotingAccountNotifier, String?>(
            _ActiveVotingAccountNotifier.new,
          );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        activeAccountUuidListenable: activeAccountProvider,
      );
      final subscription = container.listen(
        votingSessionProvider(kRoundId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final delegation = container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundles(mnemonic: kTestMnemonic);
      await rust.delegationProofStarted.future;

      container.read(activeAccountProvider.notifier).set('account-2');
      final switched = await container.read(
        votingSessionProvider(kRoundId).future,
      );
      expect(switched.accountUuid, 'account-2');

      proofGate.complete();
      await delegation;

      expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 0);
      expect(rust.storedDelegationTxHashes, isEmpty);
      expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);
    },
  );

  test(
    'vote commitments do not submit after active account changes during proof',
    () async {
      final proofGate = Completer<void>();
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        voteCommitmentGate: proofGate,
      );
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
          ],
        ),
      );
      final activeAccountProvider =
          NotifierProvider<_ActiveVotingAccountNotifier, String?>(
            _ActiveVotingAccountNotifier.new,
          );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
        activeAccountUuidListenable: activeAccountProvider,
      );
      final subscription = container.listen(
        votingSessionProvider(kRoundId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final voting = container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_wire.DraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );
      await rust.voteCommitmentStarted.future;

      container.read(activeAccountProvider.notifier).set('account-2');
      final switched = await container.read(
        votingSessionProvider(kRoundId).future,
      );
      expect(switched.accountUuid, 'account-2');

      proofGate.complete();
      await voting;

      expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 0);
      expect(_postRequestCount(http, '/shielded-vote/v1/shares'), 0);
      expect(rust.storedVoteTxHashes, isEmpty);
      expect(rust.recordedShares, isEmpty);
      expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);
    },
  );

  test('draft choices are isolated by pinned voting account', () async {
    final activeAccount = _MutableActiveAccount('account-1');
    final container = _sessionContainer(activeAccountUuid: activeAccount.call);
    addTearDown(container.dispose);

    final session = await container.read(
      votingSessionProvider(kRoundId).future,
    );
    final pinnedDraftKey = VotingSessionKey(
      roundId: kRoundId,
      accountUuid: session.accountUuid!,
    );
    container
        .read(votingDraftProvider(pinnedDraftKey).notifier)
        .setChoice(7, 1);
    activeAccount.value = 'account-2';

    const switchedDraftKey = VotingSessionKey(
      roundId: kRoundId,
      accountUuid: 'account-2',
    );
    expect(
      container.read(votingSessionProvider(kRoundId)).value?.accountUuid,
      'account-1',
    );
    expect(container.read(votingDraftProvider(pinnedDraftKey)).choices, {7: 1});
    expect(container.read(votingDraftProvider(switchedDraftKey)).isEmpty, true);
  });

  test(
    'delegation submission matches Swift SDK snake case wire shape',
    () async {
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final container = _sessionContainer(http: http);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundles(mnemonic: kTestMnemonic);

      expect(
        _postBodyJson(http, '/shielded-vote/v1/delegate-vote'),
        _delegationSubmissionWireGolden,
      );
    },
  );

  test('vote progress is isolated by bundle index', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 1,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-1',
            vanLeafPosition: null,
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
            rust_wire.DraftVote(
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

  test(
    'vote submission progress displays questions while bundle work advances',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 2,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 1,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-1',
              vanLeafPosition: null,
            ),
          ],
        ),
      );
      final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
      addTearDown(container.dispose);
      final observed = <VotingSessionState>[];
      final subscription = container.listen<AsyncValue<VotingSessionState>>(
        votingSessionProvider(kRoundId),
        (_, next) {
          final value = next.asData?.value;
          if (value != null) observed.add(value);
        },
      );
      addTearDown(subscription.close);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_wire.DraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
              rust_wire.DraftVote(
                proposalId: 8,
                choice: 0,
                numOptions: 2,
                vcTreePosition: BigInt.one,
                singleShare: false,
              ),
            ],
          );
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.submittingShares);
      expect(state.voteSubmissionCompletedCount, 2);
      expect(state.voteSubmissionTotalCount, 2);
      expect(state.voteSubmissionProgress, 1);
      expect(rust.voteCommitBundleCalls, [0, 1, 0, 1]);

      final activeProgressCounts = observed
          .where((state) => state.voteSubmissionTotalCount == 2)
          .map((state) => state.voteSubmissionCompletedCount)
          .toSet();
      expect(activeProgressCounts, containsAll(<int>{0, 1, 2}));
      expect(
        observed
            .where((state) => state.voteSubmissionTotalCount == 2)
            .map((state) => state.voteSubmissionProgress)
            .whereType<double>(),
        containsAll(<double>[0, 0.25, 0.5, 0.75, 1]),
      );

      final submittingShareStates = observed
          .where((state) => state.phase == VotingSessionPhase.submittingShares)
          .toList(growable: false);
      expect(submittingShareStates, hasLength(1));
      expect(submittingShareStates.single.voteSubmissionCompletedCount, 2);
    },
  );

  test('draft votes persist and can be cleared proposal by proposal', () async {
    final persistence = FakeVotingDraftPersistence();
    final key = const VotingSessionKey(
      roundId: kRoundId,
      accountUuid: 'account-1',
    );
    await persistence.save(key, const VotingDraftState(choices: {7: 1, 8: 0}));
    final container = ProviderContainer(
      overrides: [
        votingDraftPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(votingDraftProvider(key).notifier);
    final loaded = await notifier.ensureLoaded();
    expect(loaded.choices, {7: 1, 8: 0});

    notifier.clearChoice(7);
    await Future<void>.delayed(Duration.zero);

    expect((await persistence.load(key)).choices, {8: 0});
  });

  test(
    'partial vote resume submits persisted drafts not already on chain',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 2,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 1,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-1',
              vanLeafPosition: null,
            ),
          ],
          votes: [
            vote(bundleIndex: 0, proposalId: 7),
            vote(bundleIndex: 1, proposalId: 7),
          ],
          voteTxHashes: [
            rust_frb_types.VoteRecoveryView(
              bundleIndex: 0,
              proposalId: 7,
              choice: 0,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'vote-tx-0-7',
              vcTreePosition: null,
              hasCommitmentBundle: false,
            ),
            rust_frb_types.VoteRecoveryView(
              bundleIndex: 1,
              proposalId: 7,
              choice: 0,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'vote-tx-1-7',
              vcTreePosition: null,
              hasCommitmentBundle: false,
            ),
          ],
          commitmentBundles: [
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(2),
            ),
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 1,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(3),
            ),
          ],
        ),
      );
      final persistence = FakeVotingDraftPersistence();
      const draftKey = VotingSessionKey(
        roundId: kRoundId,
        accountUuid: 'account-1',
      );
      await persistence.save(
        draftKey,
        const VotingDraftState(choices: {7: 1, 8: 0, 9: 1}),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        draftPersistence: persistence,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final loadedDraft = await container
          .read(votingDraftProvider(draftKey).notifier)
          .ensureLoaded();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: loadedDraft.toDraftVotes([
              VotingProposalView(
                id: 7,
                title: 'One',
                description: '',
                options: [
                  VotingOptionView(index: 0, label: 'No'),
                  VotingOptionView(index: 1, label: 'Yes'),
                ],
              ),
              VotingProposalView(
                id: 8,
                title: 'Two',
                description: '',
                options: [
                  VotingOptionView(index: 0, label: 'No'),
                  VotingOptionView(index: 1, label: 'Yes'),
                ],
              ),
              VotingProposalView(
                id: 9,
                title: 'Three',
                description: '',
                options: [
                  VotingOptionView(index: 0, label: 'No'),
                  VotingOptionView(index: 1, label: 'Yes'),
                ],
              ),
            ]),
          );

      expect(rust.voteCommitmentKeys, ['0:8', '1:8', '0:9', '1:9']);
      expect((await persistence.load(draftKey)).choices, {7: 1, 8: 0, 9: 1});
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .submitPendingShares();
      expect((await persistence.load(draftKey)).choices, isEmpty);
    },
  );

  test(
    'resume submits interrupted earlier bundle before later proposal casts',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
      final recoveryApi = FakeVotingRecoveryApi(
        roundPlan: apiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          nextSteps: const [
            rust_wire.NextStepView(
              kind: 'submit_vote',
              bundleIndex: 1,
              proposalId: 7,
              shareIndex: 0,
              choice: 0,
            ),
            rust_wire.NextStepView(
              kind: 'cast_vote',
              bundleIndex: 0,
              proposalId: 8,
              shareIndex: 0,
              choice: 1,
            ),
            rust_wire.NextStepView(
              kind: 'cast_vote',
              bundleIndex: 1,
              proposalId: 8,
              shareIndex: 0,
              choice: 1,
            ),
          ],
          openProposals: Uint32List.fromList(const [9]),
          allDecided: false,
        ),
        state: recoveryState(
          bundleCount: 2,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 1,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-1',
              vanLeafPosition: null,
            ),
          ],
          votes: [
            vote(bundleIndex: 0, proposalId: 7),
            vote(bundleIndex: 1, proposalId: 7),
          ],
          voteTxHashes: [
            rust_frb_types.VoteRecoveryView(
              bundleIndex: 0,
              proposalId: 7,
              choice: 0,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'vote-tx-0-7',
              vcTreePosition: null,
              hasCommitmentBundle: false,
            ),
          ],
          commitmentBundles: [
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(2),
            ),
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 1,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(3),
            ),
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
              rust_wire.DraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
              rust_wire.DraftVote(
                proposalId: 8,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(rust.recoveredVoteCommitmentKeys, ['1:7']);
      expect(rust.voteCommitmentKeys, ['0:8', '1:8']);
      expect(rust.operationLog.take(5).toList(), [
        'recover_vote:1:7',
        'mark_vote_submitted:1:7',
        'mark_vote_confirmed:1:7',
        'record_share:1:7:0',
        'build_vote:0:8',
      ]);
    },
  );

  test('resume submits missing shares before later proposal casts', () async {
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      bundleCount: 2,
      commitmentShareCount: 2,
    );
    final existingShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 1,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://voting.example'],
      nullifier: Uint8List.fromList(List.filled(32, 1)),
      phase: VotingWorkflowPhase.confirmed,
      confirmed: true,
      submitAt: BigInt.zero,
      createdAt: BigInt.zero,
    );
    final recoveryApi = FakeVotingRecoveryApi(
      roundPlan: apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'submit_shares',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 1,
            choice: 0,
          ),
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 1,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
        ],
        openProposals: Uint32List.fromList(const [9]),
        allDecided: false,
      ),
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 1,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-1',
            vanLeafPosition: null,
          ),
        ],
        votes: [vote(bundleIndex: 1, proposalId: 7)],
        voteTxHashes: [
          rust_frb_types.VoteRecoveryView(
            bundleIndex: 1,
            proposalId: 7,
            choice: 0,
            phase: VotingWorkflowPhase.submittedVote,
            txHash: 'vote-tx-1-7',
            vcTreePosition: null,
            hasCommitmentBundle: false,
          ),
        ],
        commitmentBundles: [
          rust_frb_types.RecoverableCommitmentBundle(
            bundleIndex: 1,
            proposalId: 7,
            commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
            vcTreePosition: BigInt.from(55),
          ),
        ],
        shareDelegations: [existingShare],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_wire.DraftVote(
              proposalId: 8,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );

    expect(rust.recoveredVoteCommitmentKeys, ['1:7']);
    expect(
      rust.recordedShares
          .where((share) => share.bundleIndex == 1 && share.proposalId == 7)
          .map((share) => share.shareIndex)
          .toList(),
      [1],
    );
    expect(rust.storedVoteTxHashes, isNot(contains('1:7:vote-tx')));
    expect(rust.voteCommitmentKeys, ['0:8', '1:8']);
    expect(rust.operationLog.take(3).toList(), [
      'recover_vote:1:7',
      'record_share:1:7:1',
      'build_vote:0:8',
    ]);
  });

  test(
    'resume refreshes planner after vote confirmation before later proposal casts',
    () async {
      final httpResponses = votingHttpResponses()
        ..['/shielded-vote/v1/tx/submitted-vote-tx'] = {
          'height': 11,
          'code': 0,
          'log': '',
          'events': [
            {
              'type': 'cast_vote',
              'attributes': [
                {'key': 'leaf_index', 'value': '1,55'},
                {'key': 'vote_round_id', 'value': kRoundId},
              ],
            },
          ],
        };
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        bundleCount: 2,
        commitmentShareCount: 2,
      );
      final beforeConfirmation = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'poll_vote',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 0,
            choice: 0,
          ),
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 1,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
      final afterConfirmation = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'submit_shares',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 0,
            choice: 0,
          ),
          rust_wire.NextStepView(
            kind: 'submit_shares',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 1,
            choice: 0,
          ),
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 1,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
      final recoveryApi = FakeVotingRecoveryApi(
        roundPlanSequence: [
          beforeConfirmation,
          beforeConfirmation,
          afterConfirmation,
        ],
        state: recoveryState(
          bundleCount: 2,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 1,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-1',
              vanLeafPosition: null,
            ),
          ],
          votes: [vote(bundleIndex: 1, proposalId: 7)],
          voteWorkflows: [
            rust_frb_types.VoteRecoveryView(
              bundleIndex: 1,
              proposalId: 7,
              choice: 0,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'submitted-vote-tx',
              vcTreePosition: null,
              hasCommitmentBundle: true,
            ),
          ],
          voteTxHashes: [
            rust_frb_types.VoteRecoveryView(
              bundleIndex: 1,
              proposalId: 7,
              choice: 0,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'submitted-vote-tx',
              vcTreePosition: null,
              hasCommitmentBundle: false,
            ),
          ],
          commitmentBundles: [
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 1,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(55),
            ),
          ],
        ),
      );
      final container = _sessionContainer(
        http: FakeVotingHttpClient(responses: httpResponses),
        rust: rust,
        recoveryApi: recoveryApi,
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_wire.DraftVote(
                proposalId: 8,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(rust.recoveredVoteCommitmentKeys, ['1:7']);
      expect(
        rust.recordedShares
            .where((share) => share.bundleIndex == 1 && share.proposalId == 7)
            .map((share) => share.shareIndex)
            .toList(),
        [0, 1],
      );
      expect(rust.voteCommitmentKeys, ['0:8', '1:8']);
      expect(rust.operationLog.take(5).toList(), [
        'mark_vote_confirmed:1:7',
        'recover_vote:1:7',
        'record_share:1:7:0',
        'record_share:1:7:1',
        'build_vote:0:8',
      ]);
    },
  );

  test('submitted vote timeout surfaces resumable tx context', () async {
    final httpResponses = votingHttpResponses()
      ..['/shielded-vote/v1/tx/submitted-vote-tx'] = jsonResponse({
        'error': 'not found',
      }, statusCode: 404);
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        votes: [vote(bundleIndex: 0, proposalId: 7)],
        voteWorkflows: [
          rust_frb_types.VoteRecoveryView(
            bundleIndex: 0,
            proposalId: 7,
            choice: 0,
            phase: VotingWorkflowPhase.submittedVote,
            txHash: 'submitted-vote-tx',
            vcTreePosition: null,
            hasCommitmentBundle: true,
          ),
        ],
        voteTxHashes: [
          rust_frb_types.VoteRecoveryView(
            bundleIndex: 0,
            proposalId: 7,
            choice: 0,
            phase: VotingWorkflowPhase.submittedVote,
            txHash: 'submitted-vote-tx',
            vcTreePosition: null,
            hasCommitmentBundle: false,
          ),
        ],
        commitmentBundles: [
          rust_frb_types.RecoverableCommitmentBundle(
            bundleIndex: 0,
            proposalId: 7,
            commitmentBundleJson: '{"proposal_id":7}',
            vcTreePosition: BigInt.zero,
          ),
        ],
      ),
    );
    final container = _sessionContainer(
      http: FakeVotingHttpClient(responses: httpResponses),
      rust: rust,
      recoveryApi: recoveryApi,
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: const []);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('submitted-vote-tx'));
    expect(state.error?.message, contains('bundle 0, proposal 7'));
    expect(state.error?.message, contains('Retry to resume confirmation'));
    expect(rust.voteCommitBundleCalls, isEmpty);
  });

  test(
    'recovery-only vote confirmation does not rewrite ballot intents',
    () async {
      final httpResponses = votingHttpResponses()
        ..['/shielded-vote/v1/tx/submitted-vote-tx'] = {
          'height': 11,
          'code': 0,
          'log': '',
          'events': [
            {
              'type': 'cast_vote',
              'attributes': [
                {'key': 'leaf_index', 'value': '1,2'},
                {'key': 'vote_round_id', 'value': kRoundId},
              ],
            },
          ],
        };
      final rust = FakeVotingRustApi();
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          votes: [vote(bundleIndex: 0, proposalId: 7)],
          voteWorkflows: [
            rust_frb_types.VoteRecoveryView(
              bundleIndex: 0,
              proposalId: 7,
              choice: 0,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'submitted-vote-tx',
              vcTreePosition: null,
              hasCommitmentBundle: true,
            ),
          ],
          voteTxHashes: [
            rust_frb_types.VoteRecoveryView(
              bundleIndex: 0,
              proposalId: 7,
              choice: 0,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'submitted-vote-tx',
              vcTreePosition: null,
              hasCommitmentBundle: false,
            ),
          ],
          commitmentBundles: [
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: '{"proposal_id":7}',
              vcTreePosition: BigInt.zero,
            ),
          ],
        ),
      );
      final container = _sessionContainer(
        http: FakeVotingHttpClient(responses: httpResponses),
        rust: rust,
        recoveryApi: recoveryApi,
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(draftVotes: const [], allProposalIds: const [7, 8]);

      expect(recoveryApi.ballotIntents, isEmpty);
      expect(rust.voteCommitBundleCalls, isEmpty);
      expect(rust.storedCommitmentBundles, ['0:7:2']);
    },
  );

  test('vote tree pre-sync dedupes warmup for the same round', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    final service = container.read(votingTreePreSyncProvider);
    await Future.wait([
      service.preSyncRound(kRoundId),
      service.preSyncRound(kRoundId),
    ]);
    await service.preSyncRound(kRoundId);

    expect(rust.syncedVoteTrees, [kRoundId]);
  });

  test('vote tree sync runs before each proposal', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_wire.DraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
            rust_wire.DraftVote(
              proposalId: 8,
              choice: 0,
              numOptions: 2,
              vcTreePosition: BigInt.one,
              singleShare: false,
            ),
          ],
        );

    expect(rust.syncedVoteTrees, [kRoundId, kRoundId]);
    expect(rust.voteCommitBundleCalls, [0, 0]);
  });

  test('vote commitments submit shares and record recovery rows', () async {
    final rust = FakeVotingRustApi(emitCommitments: true);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
        ],
        votes: [vote(bundleIndex: 0, proposalId: 7)],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_wire.DraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
          allProposalIds: const [7, 8],
          proposalOptionCounts: const {8: 4},
        );

    expect(recoveryApi.ballotIntents, ['7:2:false:1', '8:4:true:null']);
    expect(rust.recordedShares, hasLength(1));
    expect(rust.recordedShares.single.bundleIndex, 0);
    expect(rust.recordedShares.single.proposalId, 7);
    expect(rust.recordedShares.single.submitAt, BigInt.zero);
    expect(rust.storedVoteTxHashes, ['0:7:vote-tx']);
    expect(rust.storedCommitmentBundles, ['0:7:2']);
  });

  test('ballot intent write failure aborts before vote submission', () async {
    final rust = FakeVotingRustApi(emitCommitments: true);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
        ],
        votes: [vote(bundleIndex: 0, proposalId: 7)],
      ),
      setBallotIntentError: StateError('intent write failed'),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_wire.DraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
          allProposalIds: const [7, 8],
          proposalOptionCounts: const {8: 4},
        );

    final state = container.read(votingSessionProvider(kRoundId)).value!;
    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('intent write failed'));
    expect(recoveryApi.ballotIntents, isEmpty);
    expect(rust.voteCommitBundleCalls, isEmpty);
    expect(rust.storedVoteTxHashes, isEmpty);
    expect(rust.recordedShares, isEmpty);
  });

  test('initial share submission uses planned helper targets', () async {
    final helperUrls = [
      for (var i = 1; i <= 6; i++)
        {'url': 'https://helper-$i.example', 'label': 'helper-$i'},
    ];
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(
        dynamicConfig: dynamicConfigJson(voteServers: helperUrls),
      ),
    );
    final rust = FakeVotingRustApi(emitCommitments: true);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
        ],
        votes: [vote(bundleIndex: 0, proposalId: 7)],
      ),
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_wire.DraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );

    final sharePosts = http.requests.where(
      (request) =>
          request.method == 'POST' &&
          request.uri.path == '/shielded-vote/v1/shares',
    );
    expect(sharePosts.map((request) => request.uri.host), [
      'helper-1.example',
      'helper-2.example',
      'helper-3.example',
    ]);
    expect(rust.recordedShares.single.sentToUrls, [
      'https://helper-1.example',
      'https://helper-2.example',
      'https://helper-3.example',
    ]);
  });

  test(
    'share submission schedules submit_at before last-moment buffer',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final voteEnd = nowSeconds + 1000;
      final ceremonyStart = nowSeconds - 100;
      final deadline = voteEnd - ((voteEnd - ceremonyStart) * 0.4).round();
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            ceremonyStart: ceremonyStart,
            voteEnd: voteEnd,
          ),
        ),
      );
      final rust = FakeVotingRustApi(emitCommitments: true);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_wire.DraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      final submitAt = _postBody(http, '/shielded-vote/v1/shares')['submit_at'];
      expect(submitAt, isA<int>());
      expect(submitAt as int, greaterThanOrEqualTo(nowSeconds));
      expect(submitAt, lessThan(deadline));
      expect(rust.recordedShares.single.submitAt, BigInt.from(submitAt));
    },
  );

  test(
    'last-moment vote uses single-share mode and immediate submit_at',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            ceremonyStart: nowSeconds - 1000,
            voteEnd: nowSeconds + 100,
          ),
        ),
      );
      final rust = FakeVotingRustApi(emitCommitments: true);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_wire.DraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(rust.draftSingleShareValues, [true]);
      expect(_postBody(http, '/shielded-vote/v1/shares')['submit_at'], 0);
      expect(rust.recordedShares.single.submitAt, BigInt.zero);
    },
  );

  test(
    'vote and share submissions match Swift SDK snake case wire shapes',
    () async {
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final rust = FakeVotingRustApi(emitCommitments: true);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_wire.DraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(
        _postBodyJson(http, '/shielded-vote/v1/cast-vote'),
        _voteCommitmentWireGolden,
      );
      expect(
        _postBodyJson(http, '/shielded-vote/v1/shares'),
        _voteShareWireGolden,
      );
    },
  );

  test('accepted unconfirmed shares confirm from any accepted helper', () async {
    final shareNullifier = Uint8List.fromList(List.filled(32, 1));
    final shareId = _hexFromBytes(shareNullifier);
    final acceptedShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const [
        'https://helper-a.example',
        'https://helper-b.example',
      ],
      nullifier: shareNullifier,
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.one,
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
        ],
        shareDelegations: [acceptedShare],
        unconfirmedShareDelegations: [acceptedShare],
      ),
    );
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(
      http: FakeVotingHttpClient(
        responses:
            votingHttpResponses(
              dynamicConfig: dynamicConfigJson(
                voteServers: const [
                  {'url': 'https://helper-a.example', 'label': 'helper-a'},
                  {'url': 'https://helper-b.example', 'label': 'helper-b'},
                ],
              ),
            )..addAll({
              'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  {'status': 'pending'},
              'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  {'status': 'confirmed'},
            }),
      ),
      rust: rust,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .submitPendingShares();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.done);
    expect(state.resumePlan?.unconfirmedShareDelegations, [acceptedShare]);
    expect(rust.confirmedShares, ['0:7:0']);
  });

  test(
    'share recovery waits until submit_at plus grace before polling',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final shareNullifier = Uint8List.fromList(List.filled(32, 3));
      final futureShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        nullifier: shareNullifier,
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.from(nowSeconds + 100),
        createdAt: BigInt.from(nowSeconds),
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          commitmentBundles: [
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(),
              vcTreePosition: BigInt.from(42),
            ),
          ],
          shareDelegations: [futureShare],
          unconfirmedShareDelegations: [futureShare],
        ),
      );
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          dynamicConfig: dynamicConfigJson(
            voteServers: const [
              {'url': 'https://helper-a.example', 'label': 'helper-a'},
              {'url': 'https://helper-b.example', 'label': 'helper-b'},
            ],
          ),
        ),
      );
      final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .submitPendingShares();

      expect(
        http.requests.where(
          (request) => request.uri.path.contains('/share-status/'),
        ),
        isEmpty,
      );
      expect(
        http.requests.where(
          (request) =>
              request.method == 'POST' &&
              request.uri.host == 'helper-b.example',
        ),
        isEmpty,
      );
      expect(recoveryApi.addedSentServers, isEmpty);
    },
  );

  test('pending share recovery resubmits helpers missed initially', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shareNullifier = Uint8List.fromList(List.filled(32, 2));
    final shareId = _hexFromBytes(shareNullifier);
    final pendingShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://helper-a.example'],
      nullifier: shareNullifier,
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.from(123),
      createdAt: BigInt.one,
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
        ],
        commitmentBundles: [
          rust_frb_types.RecoverableCommitmentBundle(
            bundleIndex: 0,
            proposalId: 7,
            commitmentBundleJson: commitmentBundleRecoveryJson(),
            vcTreePosition: BigInt.from(42),
          ),
        ],
        shareDelegations: [pendingShare],
        unconfirmedShareDelegations: [pendingShare],
      ),
    );
    final http = FakeVotingHttpClient(
      responses:
          votingHttpResponses(
            roundStatus: roundStatusJson(
              roundId: kRoundId,
              ceremonyStart: 0,
              voteEnd: nowSeconds + 1000,
            ),
            dynamicConfig: dynamicConfigJson(
              voteServers: const [
                {'url': 'https://helper-a.example', 'label': 'helper-a'},
                {'url': 'https://helper-b.example', 'label': 'helper-b'},
              ],
            ),
          )..addAll({
            'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'pending'},
            'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'pending'},
          }),
    );
    final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .submitPendingShares();

    final helperBPost = http.requests.singleWhere(
      (request) =>
          request.method == 'POST' && request.uri.host == 'helper-b.example',
    );
    expect(helperBPost.uri.path, '/shielded-vote/v1/shares');
    expect(helperBPost.body?['vote_round_id'], kRoundId);
    expect(helperBPost.body?['tree_position'], 42);
    expect(helperBPost.body?['submit_at'], 0);
    expect(helperBPost.body?['enc_share'], {
      'c1': base64Encode([8]),
      'c2': base64Encode([9]),
      'share_index': 0,
    });
    expect(recoveryApi.addedSentServers, [
      _AddedSentServers(0, 7, 0, const ['https://helper-b.example']),
    ]);
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

  test('delegation PIR warmup passes the account mnemonic to Rust', () async {
    final precomputeGate = Completer<void>();
    final rust = FakeVotingRustApi(precomputeGate: precomputeGate);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .precomputeDelegationPir(
          accountUuid: 'account-1',
          mnemonic: kTestMnemonic,
        );
    await rust.precomputeStarted.future;

    expect(rust.precomputeMnemonics.single, kTestMnemonic);

    precomputeGate.complete();
    await rust.precomputeFinished.future;
    await Future<void>.delayed(Duration.zero);
  });

  test('delegation PIR warmup skips after account switch', () async {
    final rust = FakeVotingRustApi();
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final container = _sessionContainer(
      rust: rust,
      activeAccountUuidListenable: activeAccountProvider,
    );
    final subscription = container.listen(
      votingSessionProvider(kRoundId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    final first = await container.read(votingSessionProvider(kRoundId).future);
    expect(first.accountUuid, 'account-1');

    container.read(activeAccountProvider.notifier).set('account-2');
    final second = await container.read(votingSessionProvider(kRoundId).future);
    expect(second.accountUuid, 'account-2');

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .precomputeDelegationPir(
          accountUuid: 'account-1',
          mnemonic: kTestMnemonic,
        );

    expect(rust.precomputedDelegationPir, isEmpty);
  });

  test('delegation phase activates while waiting for PIR warmup', () async {
    final precomputeGate = Completer<void>();
    final rust = FakeVotingRustApi(precomputeGate: precomputeGate);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.precomputeDelegationPir(
      accountUuid: 'account-1',
      mnemonic: kTestMnemonic,
    );
    await rust.precomputeStarted.future;

    final delegationFuture = notifier.delegatePendingBundles(
      mnemonic: kTestMnemonic,
    );

    VotingSessionState? activeState;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
      final state = container.read(votingSessionProvider(kRoundId)).value;
      if (state?.phase == VotingSessionPhase.delegating) {
        activeState = state;
        break;
      }
    }

    expect(activeState?.currentBundleIndex, 0);
    expect(rust.delegationBundleCalls, isEmpty);

    precomputeGate.complete();
    await delegationFuture;

    final finalState = container.read(votingSessionProvider(kRoundId)).value!;
    expect(finalState.phase, VotingSessionPhase.delegated);
    expect(rust.delegationBundleCalls, [0]);
  });

  test('delegation PIR warmup failure is a non-fatal cache miss', () async {
    final rust = FakeVotingRustApi(failPrecompute: true);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.precomputeDelegationPir(
      accountUuid: 'account-1',
      mnemonic: kTestMnemonic,
    );
    await notifier.delegatePendingBundles(mnemonic: kTestMnemonic);

    expect(rust.precomputedDelegationPir, [0]);
    expect(rust.delegationBundleCalls, [0]);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
  });

  test('session dispose clears round-scoped process state', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);

    await container.read(votingSessionProvider(kRoundId).future);
    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(rust.resetVotingSessionStateCalls, ['account-1:$kRoundId']);
  });

  test('hotkey failure moves session into error phase', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(
      rust: rust,
      hotkeyStore: const FailingVotingHotkeyStore(),
      recoveryApi: FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-0',
              vanLeafPosition: null,
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_wire.DraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.cause, isA<VotingHotkeyUnavailable>());
    expect(rust.resetVotingSessionStateCalls, contains('account-1:$kRoundId'));
  });
}

ProviderContainer _container({
  required VotingHttpClient http,
  VotingConfigSourceStore? sourceStore,
}) {
  return ProviderContainer(
    overrides: [
      votingConfigSourceStoreProvider.overrideWithValue(
        sourceStore ?? FakeVotingConfigSourceStore(),
      ),
      votingHttpClientProvider.overrideWithValue(http),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: http,
          sourceUrl: 'https://voting.example/static-voting-config.json',
          resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
          resolveVotingConfig: ({
            required source,
            required staticBytes,
            required dynamicBytes,
            previous,
          }) => fakeResolveVotingConfig(
            dynamicBytes: dynamicBytes,
            previous: previous,
            authenticatedRoundIds: const [kRoundId, kOtherRoundId],
          ),
        ),
      ),
      votingActiveAccountUuidProvider.overrideWithValue(() async => null),
    ],
  );
}

ProviderContainer _sessionContainer({
  FakeVotingHttpClient? http,
  FakeVotingRustApi? rust,
  FakeVotingRecoveryApi? recoveryApi,
  VotingDraftPersistence? draftPersistence,
  PirSnapshotResolver? pirResolver,
  VotingHotkeyStore? hotkeyStore,
  Future<String?> Function()? activeAccountUuid,
  ProviderListenable<String?>? activeAccountUuidListenable,
  bool accountIsHardware = false,
  Set<String>? hardwareAccountUuids,
  VotingTxConfirmationPolling? txConfirmationPolling,
  VotingWalletSyncReadinessChecker? walletSyncReadinessChecker,
  void Function()? walletSyncStarter,
  Duration? walletSyncPollInterval,
  List<String> authenticatedRoundIds = const [kRoundId, kOtherRoundId],
  Map<String, Uint8List>? authenticatedRoundEaPks,
  List<String> skippedRoundIds = const [],
}) {
  final effectiveHttp =
      http ?? FakeVotingHttpClient(responses: votingHttpResponses());
  final effectiveHardwareAccountUuids =
      hardwareAccountUuids ?? (accountIsHardware ? {'account-1'} : <String>{});
  return ProviderContainer(
    overrides: [
      votingConfigSourceStoreProvider.overrideWithValue(
        FakeVotingConfigSourceStore(),
      ),
      votingHttpClientProvider.overrideWithValue(effectiveHttp),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: effectiveHttp,
          sourceUrl: 'https://voting.example/static-voting-config.json',
          resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
          resolveVotingConfig: ({
            required source,
            required staticBytes,
            required dynamicBytes,
            previous,
          }) => fakeResolveVotingConfig(
            dynamicBytes: dynamicBytes,
            previous: previous,
            authenticatedRoundIds: authenticatedRoundIds,
            authenticatedRoundEaPks: authenticatedRoundEaPks,
            skippedRoundIds: skippedRoundIds,
          ),
        ),
      ),
      votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
      votingActiveAccountUuidProvider.overrideWith((ref) {
        final activeAccountUuidFromProvider =
            activeAccountUuidListenable == null
            ? null
            : ref.watch(activeAccountUuidListenable);
        if (activeAccountUuidListenable != null) {
          return () async => activeAccountUuidFromProvider;
        }
        return activeAccountUuid ?? () async => 'account-1';
      }),
      votingAccountIsHardwareProvider.overrideWithValue(
        (uuid) async => effectiveHardwareAccountUuids.contains(uuid),
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
      accountProvider.overrideWith(
        () => _FakeVotingAccountNotifier(mnemonic: kTestMnemonic),
      ),
      votingDraftPersistenceProvider.overrideWithValue(
        draftPersistence ?? FakeVotingDraftPersistence(),
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
      votingHotkeyStoreProvider.overrideWithValue(
        hotkeyStore ?? FakeVotingHotkeyStore([9, 9, 9]),
      ),
      votingWalletSyncReadinessCheckerProvider.overrideWithValue(
        walletSyncReadinessChecker ?? FakeVotingWalletSyncReadinessChecker(),
      ),
      votingWalletSyncStarterProvider.overrideWithValue(
        walletSyncStarter ?? () {},
      ),
      votingWalletSyncPollIntervalProvider.overrideWithValue(
        walletSyncPollInterval ?? Duration.zero,
      ),
      if (txConfirmationPolling != null)
        votingTxConfirmationPollingProvider.overrideWithValue(
          txConfirmationPolling,
        ),
    ],
  );
}

FakeVotingRecoveryApi _submittedDelegationOnlyRecoveryApi() {
  final beforeConfirmation = apiRoundPlan(
    roundId: kRoundId,
    pendingRecovery: false,
    nextSteps: const [],
    openProposals: Uint32List(0),
    allDecided: false,
    recoveredDelegationWork: const [],
  );
  final afterConfirmation = apiRoundPlan(
    roundId: kRoundId,
    pendingRecovery: false,
    nextSteps: const [],
    openProposals: Uint32List(0),
    allDecided: true,
    completedVoteArtifact: true,
    completedForDisplay: true,
    recoveredDelegationWork: const [],
  );
  return FakeVotingRecoveryApi(
    state: recoveryState(
      bundleCount: 1,
      delegationWorkflows: [
        rust_frb_types.DelegationRecoveryView(
          bundleIndex: 0,
          phase: VotingWorkflowPhase.submittedDelegation,
          txHash: 'delegation-tx',
          vanLeafPosition: null,
        ),
      ],
    ),
    roundPlanSequence: [
      beforeConfirmation,
      beforeConfirmation,
      afterConfirmation,
    ],
  );
}

FakeVotingRecoveryApi _submittedDelegationWithShareRecoveryApi(
  rust_frb_types.ShareDelegationRecordView share,
) {
  final beforeConfirmation = apiRoundPlan(
    roundId: kRoundId,
    pendingRecovery: false,
    nextSteps: const [],
    openProposals: Uint32List(0),
    allDecided: false,
    recoveredDelegationWork: const [],
  );
  final afterConfirmation = apiRoundPlan(
    roundId: kRoundId,
    pendingRecovery: true,
    blockingRecovery: false,
    completedVoteArtifact: true,
    completedForDisplay: true,
    completedVoteDisplay: const rust_wire.CompletedVoteDisplayView(
      choices: [rust_wire.CompletedVoteChoiceView(proposalId: 7, choice: null)],
      votedAt: null,
    ),
    nextSteps: const [
      rust_wire.NextStepView(
        kind: 'confirm_share',
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        choice: 0,
      ),
    ],
    openProposals: Uint32List(0),
    allDecided: true,
    recoveredDelegationWork: const [],
  );
  return FakeVotingRecoveryApi(
    state: recoveryState(
      bundleCount: 1,
      delegationWorkflows: [
        rust_frb_types.DelegationRecoveryView(
          bundleIndex: 0,
          phase: VotingWorkflowPhase.submittedDelegation,
          txHash: 'delegation-tx',
          vanLeafPosition: null,
        ),
      ],
      shareDelegations: [share],
      unconfirmedShareDelegations: [share],
    ),
    roundPlanSequence: [
      beforeConfirmation,
      beforeConfirmation,
      afterConfirmation,
    ],
  );
}

Future<VotingSubmissionJobState> _waitForJobStatus(
  ProviderContainer container,
  VotingSessionKey key,
  VotingSubmissionJobStatus status,
) async {
  for (var i = 0; i < 100; i++) {
    final state = container.read(votingSubmissionJobProvider(key));
    if (state.status == status) return state;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for voting submission job status $status. '
    'Last state: ${container.read(votingSubmissionJobProvider(key)).status}',
  );
}

Future<VotingSessionState> _waitForJobSessionPhase(
  ProviderContainer container,
  VotingSessionKey key,
  VotingSessionPhase phase,
) async {
  for (var i = 0; i < 100; i++) {
    final state = container.read(votingSubmissionJobSessionProvider(key)).value;
    if (state?.phase == phase) return state!;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for voting submission job session phase $phase. '
    'Last phase: '
    '${container.read(votingSubmissionJobSessionProvider(key)).value?.phase}',
  );
}

Future<void> _waitForVoteCommitmentKey(
  FakeVotingRustApi rust,
  String expectedKey,
) async {
  for (var i = 0; i < 100; i++) {
    if (rust.voteCommitmentKeys.contains(expectedKey)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for vote commitment $expectedKey. '
    'Saw ${rust.voteCommitmentKeys}.',
  );
}

Future<void> _waitForStoredVanPosition(
  FakeVotingRustApi rust,
  String expectedPosition,
) async {
  for (var i = 0; i < 100; i++) {
    if (rust.storedVanPositions.contains(expectedPosition)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for stored VAN position $expectedPosition. '
    'Saw ${rust.storedVanPositions}.',
  );
}

Future<void> _waitForConfirmedShare(
  FakeVotingRustApi rust,
  String expectedShare,
) async {
  for (var i = 0; i < 100; i++) {
    if (rust.confirmedShares.contains(expectedShare)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for confirmed share $expectedShare. '
    'Saw ${rust.confirmedShares}.',
  );
}

class _GatedVotingConfigLoads {
  _GatedVotingConfigLoads(this._configs);

  final Map<String, rust_config_api.VotingConfigResolution> _configs;
  final Map<String, List<Object>> _failures = {};
  final Map<String, int> _loadCounts = {};
  final Map<String, List<Completer<void>>> _gates = {};

  Completer<void> gateNext(String sourceUrl) {
    final gate = Completer<void>();
    (_gates[sourceUrl] ??= []).add(gate);
    return gate;
  }

  void failNext(String sourceUrl, Object error) {
    (_failures[sourceUrl] ??= []).add(error);
  }

  Future<rust_config_api.VotingConfigResolution> load(String sourceUrl) async {
    _loadCounts[sourceUrl] = (_loadCounts[sourceUrl] ?? 0) + 1;
    final gates = _gates[sourceUrl];
    if (gates != null && gates.isNotEmpty) {
      await gates.removeAt(0).future;
    }
    final failures = _failures[sourceUrl];
    if (failures != null && failures.isNotEmpty) {
      throw failures.removeAt(0);
    }
    final config = _configs[sourceUrl];
    if (config == null) {
      throw StateError('No fake voting config for $sourceUrl');
    }
    return config;
  }

  Future<void> waitForLoadCount(String sourceUrl, int expected) async {
    for (var i = 0; i < 100; i++) {
      if ((_loadCounts[sourceUrl] ?? 0) >= expected) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail(
      'Timed out waiting for config load $sourceUrl count $expected. '
      'Saw ${_loadCounts[sourceUrl] ?? 0}.',
    );
  }
}

class _GatedVotingConfigLoader extends VotingConfigLoader {
  _GatedVotingConfigLoader(this._loads, this._sourceUrl)
    : super(httpClient: FakeVotingHttpClient());

  final _GatedVotingConfigLoads _loads;
  final String _sourceUrl;

  @override
  Future<rust_config_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
  }) {
    return _loads.load(_sourceUrl);
  }
}

rust_config_api.VotingConfigResolution _configForVoteServer(String url) {
  final defaultEaPk = Uint8List.fromList(List.filled(32, 1));
  final config = rust_config.ResolvedVotingConfig(
    sourceFingerprint: 'test-source-fingerprint',
    trustedKeyFingerprint: 'test-trusted-key-fingerprint',
    dynamicConfigFingerprint: 'test-dynamic-config-fingerprint',
    voteServers: [rust_config.ServiceEndpoint(url: url, label: 'primary')],
    pirEndpoints: const [
      rust_config.ServiceEndpoint(url: 'https://pir.example', label: 'pir'),
    ],
    supportedVersions: const rust_config.SupportedVersions(
      pir: ['v0'],
      voteProtocol: 'v0',
      tally: 'v0',
      voteServer: 'v1',
    ),
    authenticatedRounds: [
      rust_config.AuthenticatedRound(
        roundId: kRoundId,
        eaPk: defaultEaPk,
      ),
      rust_config.AuthenticatedRound(
        roundId: kOtherRoundId,
        eaPk: defaultEaPk,
      ),
    ],
    skippedRoundIds: const [],
    conditions: const [],
  );
  return rust_config_api.VotingConfigResolution(
    config: config,
    switchKind: rust_config.ConfigSwitchKind.unchanged,
  );
}

Map<String, dynamic> _postBody(FakeVotingHttpClient http, String path) {
  final request = http.requests.singleWhere(
    (request) => request.method == 'POST' && request.uri.path == path,
  );
  return request.body!;
}

int _postRequestCount(FakeVotingHttpClient http, String path) {
  return http.requests
      .where((request) => request.method == 'POST' && request.uri.path == path)
      .length;
}

String _postBodyJson(FakeVotingHttpClient http, String path) =>
    jsonEncode(_postBody(http, path));

Map<String, Object> votingHttpResponses({
  Map<String, dynamic>? roundStatus,
  Map<String, dynamic>? dynamicConfig,
}) => {
  'https://voting.example/static-voting-config.json': staticConfigJson(),
  'https://voting.example/dynamic-voting-config.json':
      dynamicConfig ?? dynamicConfigJson(),
  '/shielded-vote/v1/round/$kRoundId': {
    'round': roundStatus ?? roundStatusJson(roundId: kRoundId),
  },
  '/shielded-vote/v1/delegate-vote': {
    'tx_hash': 'delegation-tx',
    'code': 0,
    'log': '',
  },
  '/shielded-vote/v1/tx/delegation-tx': {
    'height': 10,
    'code': 0,
    'log': '',
    'events': [
      {
        'type': 'delegate_vote',
        'attributes': [
          {'key': 'leaf_index', 'value': '0'},
          {'key': 'vote_round_id', 'value': kRoundId},
        ],
      },
    ],
  },
  '/shielded-vote/v1/cast-vote': {'tx_hash': 'vote-tx', 'code': 0, 'log': ''},
  '/shielded-vote/v1/shares': {'status': 'queued'},
  '/shielded-vote/v1/tx/vote-tx': {
    'height': 11,
    'code': 0,
    'log': '',
    'events': [
      {
        'type': 'cast_vote',
        'attributes': [
          {'key': 'leaf_index', 'value': '1,2'},
          {'key': 'vote_round_id', 'value': kRoundId},
        ],
      },
    ],
  },
  '/shielded-vote/v1/share-status/$kRoundId/0102': {'status': 'confirmed'},
};

const kRoundId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const kOtherRoundId =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const kTestMnemonic = 'abandon abandon abandon';
const kEncodedRoundId = 'El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv/3RE=';
const kEncodedRoundIdHex =
    '125e5475f653b074d5f4c36730852695f356416c2b6c3042516a912e5bffdd11';
const _roundIdBase64 = 'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo=';
const _bytes1x32Base64 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _bytes2x32Base64 = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';
const _bytes3x32Base64 = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=';
const _bytes7x32Base64 = 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=';
const _bytes10x32Base64 = 'CgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo=';
const _bytes11x32Base64 = 'CwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws=';
const _bytes12x64Base64 =
    'DAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA==';
const _bytes13x32Base64 = 'DQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0=';
const _delegationSubmissionWireGolden =
    '{"rk":"Ag==","spend_auth_sig":"Aw==","sighash":"BA==","signed_note_nullifier":"BQ==","cmx_new":"Bg==","van_cmx":"Bw==","gov_nullifiers":["CA=="],"proof":"AQ==","vote_round_id":"$_roundIdBase64"}';
const _voteCommitmentWireGolden =
    '{"van_nullifier":"$_bytes1x32Base64","vote_authority_note_new":"$_bytes2x32Base64","vote_commitment":"$_bytes3x32Base64","proposal_id":7,"proof":"BA==","vote_round_id":"$_roundIdBase64","vote_comm_tree_anchor_height":10,"r_vpk":"$_bytes13x32Base64","vote_auth_sig":"$_bytes12x64Base64"}';
const _voteShareWireGolden =
    '{"shares_hash":"$_bytes7x32Base64","proposal_id":7,"vote_decision":1,"enc_share":{"c1":"CA==","c2":"CQ==","share_index":0},"share_index":0,"tree_position":2,"all_enc_shares":[{"c1":"CA==","c2":"CQ==","share_index":0}],"share_comms":["$_bytes10x32Base64"],"primary_blind":"$_bytes11x32Base64","submit_at":0,"vote_round_id":"$kRoundId"}';
const _fastTxConfirmationPolling = VotingTxConfirmationPolling(
  attempts: 1,
  delay: Duration.zero,
);

Future<String> fakeResolveStaticVotingConfig({
  required String source,
  required List<int> staticBytes,
}) async {
  final staticJson = decodeVotingJsonObject(utf8.decode(staticBytes));
  final dynamicConfigUrl = staticJson['dynamic_config_url']?.toString();
  if (dynamicConfigUrl == null || dynamicConfigUrl.isEmpty) {
    throw const FormatException('Missing required string: dynamic_config_url');
  }
  return dynamicConfigUrl;
}

Future<rust_config_api.VotingConfigResolution> fakeResolveVotingConfig({
  required List<int> dynamicBytes,
  rust_config.ResolvedVotingConfig? previous,
  List<String>? authenticatedRoundIds,
  Map<String, Uint8List>? authenticatedRoundEaPks,
  List<String> skippedRoundIds = const [],
  rust_config.ConfigSwitchKind? switchKind,
}) async {
  final dynamicJson = decodeVotingJsonObject(utf8.decode(dynamicBytes));

  final voteServers = (dynamicJson['vote_servers'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(
        (endpoint) => rust_config.ServiceEndpoint(
          url: endpoint['url'].toString(),
          label: endpoint['label']?.toString() ?? '',
        ),
      )
      .toList(growable: false);
  final pirEndpoints = (dynamicJson['pir_endpoints'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(
        (endpoint) => rust_config.ServiceEndpoint(
          url: endpoint['url'].toString(),
          label: endpoint['label']?.toString() ?? '',
        ),
      )
      .toList(growable: false);
  final versions = dynamicJson['supported_versions'] as Map<String, dynamic>;
  final dynamicRounds = dynamicJson['rounds'] as Map<String, dynamic>;
  final effectiveAuthenticatedRoundIds =
      authenticatedRoundIds ?? dynamicRounds.keys.toList(growable: false);
  final authenticatedRounds = effectiveAuthenticatedRoundIds.map((roundId) {
    final configuredEaPk = authenticatedRoundEaPks?[roundId];
    if (configuredEaPk != null) {
      return rust_config.AuthenticatedRound(roundId: roundId, eaPk: configuredEaPk);
    }
    final dynamicRound = dynamicRounds[roundId] as Map<String, dynamic>?;
    final eaPkB64 = dynamicRound?['ea_pk']?.toString();
    if (eaPkB64 == null || eaPkB64.isEmpty) {
      throw FormatException('Missing required string: rounds.$roundId.ea_pk');
    }
    return rust_config.AuthenticatedRound(
      roundId: roundId,
      eaPk: base64Decode(eaPkB64),
    );
  }).toList(growable: false);
  final resolved = rust_config.ResolvedVotingConfig(
    sourceFingerprint: 'test-source-fingerprint',
    trustedKeyFingerprint: 'test-trusted-key-fingerprint',
    dynamicConfigFingerprint: 'test-dynamic-config-fingerprint',
    voteServers: voteServers,
    pirEndpoints: pirEndpoints,
    supportedVersions: rust_config.SupportedVersions(
      pir: (versions['pir'] as List<dynamic>)
          .map((value) => value.toString())
          .toList(growable: false),
      voteProtocol: versions['vote_protocol'].toString(),
      tally: versions['tally'].toString(),
      voteServer: versions['vote_server'].toString(),
    ),
    authenticatedRounds: authenticatedRounds,
    skippedRoundIds: skippedRoundIds,
    conditions: const [],
  );

  return rust_config_api.VotingConfigResolution(
    config: resolved,
    switchKind:
        switchKind ??
        (previous == null
            ? rust_config.ConfigSwitchKind.initialLoad
            : rust_config.ConfigSwitchKind.unchanged),
  );
}

Map<String, dynamic> staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _bytes1x32Base64},
  ],
};

Map<String, dynamic> dynamicConfigJson({
  List<Map<String, String>> voteServers = const [
    {'url': 'https://voting.example', 'label': 'primary'},
  ],
}) => {
  'config_version': 1,
  'vote_servers': voteServers,
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
      'ea_pk': _bytes1x32Base64,
      'signatures': [
        {'key_id': 'demo', 'alg': 'ed25519', 'sig': _bytes12x64Base64},
      ],
    },
    kOtherRoundId: {
      'auth_version': 1,
      'ea_pk': _bytes1x32Base64,
      'signatures': [
        {'key_id': 'demo', 'alg': 'ed25519', 'sig': _bytes12x64Base64},
      ],
    },
  },
};

Map<String, dynamic> roundStatusJson({
  required String roundId,
  int? ceremonyStart,
  int? voteEnd,
}) {
  final json = <String, dynamic>{
    'vote_round_id': roundId,
    'round_id': roundId,
    'title': 'Poll',
    'status': 'active',
    'snapshot_height': 123,
    'ea_pk': _bytes1x32Base64,
    'nc_root': _bytes2x32Base64,
    'nullifier_imt_root': _bytes3x32Base64,
  };
  if (ceremonyStart != null) {
    json['ceremony_phase_start'] = ceremonyStart;
  }
  if (voteEnd != null) {
    json['vote_end_time'] = voteEnd;
  }
  return json;
}

rust_frb_types.RoundRecoveryStateView recoveryState({
  int bundleCount = 1,
  List<rust_frb_types.DelegationRecoveryView> delegationWorkflows = const [],
  List<rust_frb_types.DelegationRecoveryView> delegationTxHashes = const [],
  List<rust_frb_types.VoteRecoveryView> votes = const [],
  List<rust_frb_types.VoteRecoveryView> voteWorkflows = const [],
  List<rust_frb_types.VoteRecoveryView> voteTxHashes = const [],
  List<rust_frb_types.RecoverableCommitmentBundle> commitmentBundles = const [],
  List<rust_frb_types.ShareWorkflowRecoveryView> shareWorkflows = const [],
  List<rust_frb_types.ShareDelegationRecordView> shareDelegations = const [],
  List<rust_frb_types.ShareDelegationRecordView> unconfirmedShareDelegations =
      const [],
}) {
  final delegationByBundle = <int, rust_frb_types.DelegationRecoveryView>{
    for (final record in delegationWorkflows)
      record.bundleIndex: rust_frb_types.DelegationRecoveryView(
        bundleIndex: record.bundleIndex,
        phase: record.phase,
        txHash: record.txHash,
        vanLeafPosition: record.vanLeafPosition,
      ),
  };
  for (final record in delegationTxHashes) {
    delegationByBundle[record.bundleIndex] =
        rust_frb_types.DelegationRecoveryView(
          bundleIndex: record.bundleIndex,
          phase: VotingWorkflowPhase.submittedDelegation,
          txHash: record.txHash,
          vanLeafPosition: null,
        );
  }

  final votesByKey = <String, rust_frb_types.VoteRecoveryView>{
    for (final record in votes)
      '${record.bundleIndex}:${record.proposalId}': record,
    for (final record in voteWorkflows)
      '${record.bundleIndex}:${record.proposalId}':
          rust_frb_types.VoteRecoveryView(
            bundleIndex: record.bundleIndex,
            proposalId: record.proposalId,
            choice: 0,
            phase: record.phase,
            txHash: record.txHash,
            vcTreePosition: record.vcTreePosition,
            hasCommitmentBundle: record.hasCommitmentBundle,
          ),
  };
  for (final record in voteTxHashes) {
    final key = '${record.bundleIndex}:${record.proposalId}';
    final current = votesByKey[key];
    votesByKey[key] = rust_frb_types.VoteRecoveryView(
      bundleIndex: record.bundleIndex,
      proposalId: record.proposalId,
      choice: current?.choice ?? 0,
      phase: current?.phase ?? VotingWorkflowPhase.submittedVote,
      txHash: record.txHash,
      vcTreePosition: current?.vcTreePosition,
      hasCommitmentBundle: current?.hasCommitmentBundle ?? false,
    );
  }

  return rust_frb_types.RoundRecoveryStateView(
    roundId: kRoundId,
    bundleCount: bundleCount,
    delegation: delegationByBundle.values.toList(),
    votes: votesByKey.values.toList(),
    commitmentBundles: commitmentBundles,
    shares: shareWorkflows,
    shareDelegations: shareDelegations,
    unconfirmedShareDelegations: unconfirmedShareDelegations,
  );
}

rust_frb_types.VoteRecoveryView vote({
  required int bundleIndex,
  required int proposalId,
}) {
  return rust_frb_types.VoteRecoveryView(
    bundleIndex: bundleIndex,
    proposalId: proposalId,
    choice: 1,
    phase: VotingWorkflowPhase.prepared,
    hasCommitmentBundle: false,
  );
}

String commitmentBundleRecoveryJson({int proposalId = 7, int shareIndex = 0}) {
  return jsonEncode({
    'format': 'vizor_vote_commitment_bundle_recovery_v1',
    'share_payloads': [
      {
        'shares_hash': _hexFromBytes(List.filled(32, 7)),
        'proposal_id': proposalId,
        'vote_decision': 1,
        'enc_share': {
          'c1': _hexFromBytes([8]),
          'c2': _hexFromBytes([9]),
          'share_index': shareIndex,
        },
        'tree_position': 2,
        'all_enc_shares': [
          {
            'c1': _hexFromBytes([8]),
            'c2': _hexFromBytes([9]),
            'share_index': shareIndex,
          },
        ],
        'share_comms': [_hexFromBytes(List.filled(32, 10))],
        'primary_blind': _hexFromBytes(List.filled(32, 11)),
      },
    ],
  });
}

String _hexFromBytes(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

List<int> _bytesFromHex(String hex) {
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

class FakeVotingRecoveryApi implements VotingRecoveryApi {
  rust_frb_types.RoundRecoveryStateView state;
  rust_wire.RoundPlanView? roundPlan;
  final List<rust_wire.RoundPlanView>? roundPlanSequence;
  final walletIds = <String>[];
  final addedSentServers = <_AddedSentServers>[];
  final ballotIntents = <String>[];
  final roundPlanProposalIds = <List<int>>[];
  final Object? setBallotIntentError;
  var _roundPlanCallCount = 0;

  FakeVotingRecoveryApi({
    required this.state,
    this.roundPlan,
    this.roundPlanSequence,
    this.setBallotIntentError,
  });

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) async {
    addedSentServers.add(
      _AddedSentServers(bundleIndex, proposalId, shareIndex, newUrls),
    );
  }

  @override
  Future<void> clearRecoveryState({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) async {}

  @override
  Future<rust_frb_types.RoundRecoveryStateView> getRoundRecoveryState({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) async {
    walletIds.add(accountUuid);
    return state;
  }

  @override
  Future<rust_wire.RoundPlanView> getRoundPlan({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<int> proposalIds,
  }) async {
    roundPlanProposalIds.add(List<int>.from(proposalIds));
    final sequence = roundPlanSequence;
    if (sequence != null && sequence.isNotEmpty) {
      var index = _roundPlanCallCount;
      _roundPlanCallCount++;
      if (index >= sequence.length) index = sequence.length - 1;
      return sequence[index];
    }
    return roundPlan ??
        apiRoundPlanFromRecoveryState(
          state: state,
          roundId: roundId,
          proposalIds: proposalIds,
        );
  }

  @override
  Future<void> setBallotIntent({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  }) async {
    final error = setBallotIntentError;
    if (error != null) {
      throw error;
    }
    ballotIntents.add('$proposalId:$numOptions:$skipped:${choice ?? 'null'}');
  }
}

class FakeVotingDraftPersistence implements VotingDraftPersistence {
  final _stored = <VotingSessionKey, VotingDraftState>{};

  @override
  Future<VotingDraftState> load(VotingSessionKey key) async {
    return _stored[key] ?? const VotingDraftState();
  }

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {
    if (draft.choices.isEmpty) {
      _stored.remove(key);
    } else {
      _stored[key] = VotingDraftState(choices: Map.of(draft.choices));
    }
  }
}

class _AddedSentServers {
  const _AddedSentServers(
    this.bundleIndex,
    this.proposalId,
    this.shareIndex,
    this.newUrls,
  );

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final List<String> newUrls;

  @override
  bool operator ==(Object other) =>
      other is _AddedSentServers &&
      other.bundleIndex == bundleIndex &&
      other.proposalId == proposalId &&
      other.shareIndex == shareIndex &&
      _listEquals(other.newUrls, newUrls);

  @override
  int get hashCode => Object.hash(bundleIndex, proposalId, shareIndex, newUrls);

  @override
  String toString() =>
      '_AddedSentServers($bundleIndex, $proposalId, $shareIndex, $newUrls)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _MutableActiveAccount {
  _MutableActiveAccount(this.value);

  String? value;

  Future<String?> call() async => value;
}

class _ActiveVotingAccountNotifier extends Notifier<String?> {
  @override
  String? build() => 'account-1';

  void set(String? accountUuid) {
    state = accountUuid;
  }
}

class _FakeVotingAccountNotifier extends AccountNotifier {
  _FakeVotingAccountNotifier({required this.mnemonic});

  final String? mnemonic;

  @override
  FutureOr<AccountState> build() {
    return const AccountState(
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
  }

  @override
  Future<String?> getMnemonicForAccount(String uuid) async {
    return mnemonic;
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
  List<int>? hotkey;

  FakeVotingHotkeyStore(this.hotkey);

  @override
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) async {
    return hotkey;
  }

  @override
  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) async {
    this.hotkey = List<int>.from(hotkey);
  }

  @override
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) async {}
}

class FailingVotingHotkeyStore implements VotingHotkeyStore {
  const FailingVotingHotkeyStore();

  @override
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) {
    throw const VotingHotkeyUnavailable('missing test hotkey');
  }

  @override
  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) async {}

  @override
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) async {}
}

class FakeVotingConfigSourceStore implements VotingConfigSourceStore {
  FakeVotingConfigSourceStore({this.sourceUrl, this.savedSourcesJson});

  String? sourceUrl;
  String? savedSourcesJson;

  @override
  Future<String?> readSourceUrl() async => sourceUrl;

  @override
  Future<void> writeSourceUrl(String sourceUrl) async {
    this.sourceUrl = sourceUrl;
  }

  @override
  Future<void> resetSourceUrl() async {
    sourceUrl = null;
  }

  @override
  Future<String?> readSavedSourcesJson() async => savedSourcesJson;

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) async {
    this.savedSourcesJson = savedSourcesJson;
  }
}

class FakeVotingWalletSyncReadinessChecker
    implements VotingWalletSyncReadinessChecker {
  FakeVotingWalletSyncReadinessChecker({this.responses = const []});

  final List<VotingWalletSyncReadiness> responses;
  int calls = 0;

  @override
  Future<VotingWalletSyncReadiness> check({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  }) async {
    final index = calls;
    calls++;
    if (responses.isNotEmpty) {
      return responses[index < responses.length ? index : responses.length - 1];
    }
    return VotingWalletSyncReadiness(
      scannedHeight: snapshotHeight,
      snapshotHeight: snapshotHeight,
      chainTipHeight: snapshotHeight,
    );
  }
}

class _GatedVotingWalletSyncReadinessChecker
    implements VotingWalletSyncReadinessChecker {
  final firstCheck = Completer<void>();
  var _ready = false;

  void allowReady() {
    _ready = true;
  }

  @override
  Future<VotingWalletSyncReadiness> check({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  }) async {
    if (!firstCheck.isCompleted) firstCheck.complete();
    return VotingWalletSyncReadiness(
      scannedHeight: _ready ? snapshotHeight : snapshotHeight - 1,
      snapshotHeight: snapshotHeight,
      chainTipHeight: snapshotHeight,
    );
  }
}

class FakeVotingRustApi implements VotingRustApi {
  FakeVotingRustApi({
    this.setupDelay = Duration.zero,
    this.setupGate,
    this.emitCommitments = false,
    this.precomputeGate,
    this.failPrecompute = false,
    this.bundleCount = 1,
    this.commitmentShareCount = 1,
    this.mismatchKeystoneSubmission = false,
    this.delegationStreamError,
    this.delegationProofGate,
    this.keystoneDelegationProofGate,
    this.voteCommitmentGate,
    this.onDeleteSkippedBundles,
  });

  final Duration setupDelay;
  final Completer<void>? setupGate;
  final bool emitCommitments;
  final Completer<void>? precomputeGate;
  final bool failPrecompute;
  final int bundleCount;
  final int commitmentShareCount;
  final bool mismatchKeystoneSubmission;
  final Object? delegationStreamError;
  final Completer<void>? delegationProofGate;
  final Completer<void>? keystoneDelegationProofGate;
  final Completer<void>? voteCommitmentGate;
  final void Function(int keepCount)? onDeleteSkippedBundles;
  int setupCalls = 0;
  int _activeSetups = 0;
  int maxConcurrentSetups = 0;
  final delegationBundleCalls = <int>[];
  final voteCommitBundleCalls = <int>[];
  final voteCommitmentKeys = <String>[];
  final recoveredVoteCommitmentKeys = <String>[];
  final storedDelegationTxHashes = <String>[];
  final storedVoteTxHashes = <String>[];
  final storedCommitmentBundles = <String>[];
  final storedVanPositions = <String>[];
  final operationLog = <String>[];
  final recordedShares = <_RecordedShare>[];
  final syncedVoteTrees = <String>[];
  final precomputedDelegationPir = <int>[];
  final precomputeMnemonics = <String>[];
  final setupStarted = Completer<void>();
  final delegationProofStarted = Completer<void>();
  final keystoneDelegationProofStarted = Completer<void>();
  final voteCommitmentStarted = Completer<void>();
  final precomputeStarted = Completer<void>();
  final precomputeFinished = Completer<void>();
  final resetVotingSessionStateCalls = <String>[];
  final draftSingleShareValues = <bool>[];
  final accountUuids = <String>[];
  final confirmedShares = <String>[];
  final keystoneDelegationRequestCalls = <int>[];
  final keystoneProofBundleCalls = <int>[];
  final deleteSkippedBundleKeepCounts = <int>[];
  final storedKeystoneSignatures = <int, rust_wire.KeystoneSignatureRecord>{};
  rust_wire.VotingRoundParams? lastTrustedRoundParams;
  rust_wire.VotingRoundParams? lastSetupRoundParams;
  int trustedRoundParamsCalls = 0;
  int generateVotingHotkeyCalls = 0;
  int parseSignedVotingPcztCalls = 0;
  int deriveHotkeyCalls = 0;
  int extractSpendAuthSignatureCalls = 0;

  @override
  Future<rust_wire.VotingRoundParams> trustedVotingRoundParamsFromConfig({
    required rust_config.ResolvedVotingConfig config,
    required String roundId,
    required BigInt snapshotHeight,
    required List<int> ncRoot,
    required List<int> nullifierImtRoot,
  }) async {
    trustedRoundParamsCalls++;
    final trustedRound = config.authenticatedRounds.firstWhere(
      (round) => round.roundId == roundId,
      orElse: () => throw StateError('round $roundId is not authenticated'),
    );
    final params = rust_wire.VotingRoundParams(
      voteRoundId: roundId,
      snapshotHeight: snapshotHeight,
      eaPk: trustedRound.eaPk,
      ncRoot: Uint8List.fromList(ncRoot),
      nullifierImtRoot: Uint8List.fromList(nullifierImtRoot),
    );
    lastTrustedRoundParams = params;
    return params;
  }

  @override
  Future<rust_round.BundleLayout> setupDelegationBundles({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    lastSetupRoundParams = ctx.roundParams;
    accountUuids.add(ctx.accountUuid);
    _activeSetups++;
    if (_activeSetups > maxConcurrentSetups) {
      maxConcurrentSetups = _activeSetups;
    }
    if (!setupStarted.isCompleted) {
      setupStarted.complete();
    }
    await setupGate?.future;
    if (setupDelay > Duration.zero) {
      await Future<void>.delayed(setupDelay);
    }
    setupCalls++;
    _activeSetups--;
    return rust_round.BundleLayout(
      bundleCount: bundleCount,
      eligibleWeight: BigInt.from(100),
      droppedCount: 0,
    );
  }

  @override
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
    required String mnemonic,
    required int bundleIndex,
  }) async* {
    accountUuids.add(ctx.accountUuid);
    delegationBundleCalls.add(bundleIndex);
    final error = delegationStreamError;
    if (error != null) throw error;
    if (!delegationProofStarted.isCompleted) {
      delegationProofStarted.complete();
    }
    await delegationProofGate?.future;
    yield rust_api.ApiDelegationProofEvent(
      phase: 'result',
      proofProgress: null,
      signedDelegationPayload: rust_wire.SignedDelegationPayloadView(
        pcztBytes: Uint8List.fromList(const []),
        status: 'ready_for_submission',
        message: null,
        submission: rust_wire.DelegationSubmissionWire(
          rk: base64Encode(const [2]),
          spendAuthSig: base64Encode(const [3]),
          sighash: base64Encode(const [4]),
          nfSigned: base64Encode(const [5]),
          cmxNew: base64Encode(const [6]),
          govComm: base64Encode(const [7]),
          govNullifiers: [
            base64Encode(const [8]),
          ],
          proof: base64Encode(const [1]),
          voteRoundId: base64Encode(_bytesFromHex(ctx.roundParams.voteRoundId)),
        ),
        eligibleWeightZatoshi: BigInt.from(100),
        delegatedWeightZatoshi: BigInt.from(100),
        bundleCount: 1,
        bundleIndex: bundleIndex,
      ),
    );
  }

  @override
  Future<List<int>> generateVotingHotkey({required String network}) async {
    generateVotingHotkeyCalls++;
    return [42, 43, 44];
  }

  @override
  Future<rust_delegate.KeystoneSigningRequest> buildKeystoneDelegationRequest({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> hotkeySeed,
    required int bundleIndex,
  }) async {
    accountUuids.add(ctx.accountUuid);
    keystoneDelegationRequestCalls.add(bundleIndex);
    return rust_delegate.KeystoneSigningRequest(
      pcztBytes: Uint8List.fromList([20, bundleIndex]),
      redactedPcztBytes: Uint8List.fromList([21, bundleIndex]),
      pcztSighash: Uint8List.fromList([10, bundleIndex]),
      rk: Uint8List.fromList([2, bundleIndex]),
      actionIndex: 0,
      displayMemo:
          'I am authorizing this hotkey managed by my wallet to vote on ${ctx.roundName} with 0.00000100 ZEC.',
      eligibleWeightZatoshi: BigInt.from(100),
      delegatedWeightZatoshi: BigInt.from(100),
      bundleCount: bundleCount,
      bundleIndex: bundleIndex,
    );
  }

  @override
  Future<rust_api.ParsedSignedVotingPczt> parseSignedVotingPczt({
    required List<int> signedPcztBytes,
    required int actionIndex,
  }) async {
    parseSignedVotingPcztCalls++;
    return rust_api.ParsedSignedVotingPczt(
      sighash: Uint8List.fromList(signedPcztBytes),
      spendAuthSig: Uint8List.fromList([3, actionIndex]),
    );
  }

  @override
  Future<void> storeKeystoneSignature({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required List<int> sig,
    required List<int> sighash,
    required List<int> rk,
  }) async {
    storedKeystoneSignatures[bundleIndex] = rust_wire.KeystoneSignatureRecord(
      bundleIndex: bundleIndex,
      sig: Uint8List.fromList(sig),
      sighash: Uint8List.fromList(sighash),
      rk: Uint8List.fromList(rk),
    );
  }

  @override
  Future<List<rust_wire.KeystoneSignatureRecord>> getKeystoneSignatures({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) async {
    final records = storedKeystoneSignatures.values.toList()
      ..sort((a, b) => a.bundleIndex.compareTo(b.bundleIndex));
    return records;
  }

  @override
  Future<int> deleteSkippedBundles({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int keepCount,
  }) async {
    deleteSkippedBundleKeepCounts.add(keepCount);
    final removed = storedKeystoneSignatures.keys
        .where((bundleIndex) => bundleIndex >= keepCount)
        .toList();
    for (final bundleIndex in removed) {
      storedKeystoneSignatures.remove(bundleIndex);
    }
    onDeleteSkippedBundles?.call(keepCount);
    return bundleCount - keepCount;
  }

  @override
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
    required List<int> hotkeySeed,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
  }) async* {
    accountUuids.add(ctx.accountUuid);
    keystoneProofBundleCalls.add(bundleIndex);
    if (!keystoneDelegationProofStarted.isCompleted) {
      keystoneDelegationProofStarted.complete();
    }
    await keystoneDelegationProofGate?.future;
    final signature = storedKeystoneSignatures[bundleIndex];
    final rk = mismatchKeystoneSubmission
        ? const [99]
        : signature?.rk ?? const [2];
    yield rust_api.ApiDelegationProofEvent(
      phase: 'result',
      proofProgress: null,
      signedDelegationPayload: rust_wire.SignedDelegationPayloadView(
        pcztBytes: Uint8List.fromList(const []),
        status: 'ready_for_submission',
        message: null,
        submission: rust_wire.DelegationSubmissionWire(
          rk: base64Encode(rk),
          spendAuthSig: base64Encode(keystoneSig),
          sighash: base64Encode(keystoneSighash),
          nfSigned: base64Encode(const [5]),
          cmxNew: base64Encode(const [6]),
          govComm: base64Encode(const [7]),
          govNullifiers: [
            base64Encode(const [8]),
          ],
          proof: base64Encode(const [1]),
          voteRoundId: base64Encode(_bytesFromHex(ctx.roundParams.voteRoundId)),
        ),
        eligibleWeightZatoshi: BigInt.from(100),
        delegatedWeightZatoshi: BigInt.from(100),
        bundleCount: bundleCount,
        bundleIndex: bundleIndex,
      ),
    );
  }

  @override
  Future<String> delegationSubmissionWireJson({
    required rust_wire.SignedDelegationPayloadView submission,
  }) async {
    final wire = submission.submission;
    return jsonEncode({
      'rk': wire.rk,
      'spend_auth_sig': wire.spendAuthSig,
      'sighash': wire.sighash,
      'signed_note_nullifier': wire.nfSigned,
      'cmx_new': wire.cmxNew,
      'van_cmx': wire.govComm,
      'gov_nullifiers': wire.govNullifiers,
      'proof': wire.proof,
      'vote_round_id': wire.voteRoundId,
    });
  }

  @override
  Future<rust_wire.DelegationPirPrecomputeResultView> precomputeDelegationPir({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
    required String mnemonic,
    required int bundleIndex,
  }) async {
    accountUuids.add(ctx.accountUuid);
    precomputedDelegationPir.add(bundleIndex);
    precomputeMnemonics.add(mnemonic);
    if (!precomputeStarted.isCompleted) {
      precomputeStarted.complete();
    }
    try {
      await precomputeGate?.future;
      if (failPrecompute) {
        throw StateError('precompute failed');
      }
    } finally {
      if (!precomputeFinished.isCompleted) {
        precomputeFinished.complete();
      }
    }
    return rust_wire.DelegationPirPrecomputeResultView(
      cachedCount: 0,
      fetchedCount: 1,
      bundleCount: bundleCount,
      bundleIndex: bundleIndex,
    );
  }

  @override
  Future<void> markDelegationSubmitted({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  }) async {
    _addUnique(storedDelegationTxHashes, '$bundleIndex:$txHash');
  }

  void _recordDelegationConfirmed({
    required int bundleIndex,
    required String txHash,
    required int vanLeafPosition,
  }) {
    _addUnique(storedDelegationTxHashes, '$bundleIndex:$txHash');
    storedVanPositions.add('$bundleIndex:$vanLeafPosition');
  }

  @override
  Future<rust_wire.DelegationConfirmation> confirmDelegationSubmission({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required String txHash,
    required String eventsJson,
  }) async {
    final vanLeafPosition = eventIntFromTxEventsJson(
      eventsJson,
      'delegate_vote',
      roundId,
      'leaf_index',
    );
    _recordDelegationConfirmed(
      bundleIndex: bundleIndex,
      txHash: txHash,
      vanLeafPosition: vanLeafPosition,
    );
    return rust_wire.DelegationConfirmation(
      txHash: txHash,
      vanLeafPosition: vanLeafPosition,
    );
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String nodeUrl,
  }) async {
    syncedVoteTrees.add(roundId);
    return 10;
  }

  @override
  Future<rust_vote.VanWitness> generateVanWitness({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  }) async {
    return rust_vote.VanWitness(
      authPath: const [],
      position: bundleIndex,
      anchorHeight: anchorHeight,
    );
  }

  @override
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {
    resetVotingSessionStateCalls.add('$accountUuid:${roundId ?? '*'}');
  }

  @override
  Stream<rust_api.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> hotkeySeed,
    required rust_vote.VanWitness vanWitness,
    required List<rust_wire.DraftVote> draftVotes,
  }) async* {
    voteCommitBundleCalls.add(bundleIndex);
    if (!voteCommitmentStarted.isCompleted) {
      voteCommitmentStarted.complete();
    }
    await voteCommitmentGate?.future;
    for (final draft in draftVotes) {
      voteCommitmentKeys.add('$bundleIndex:${draft.proposalId}');
      operationLog.add('build_vote:$bundleIndex:${draft.proposalId}');
      draftSingleShareValues.add(draft.singleShare);
      yield rust_api.ApiVoteCommitEvent(
        phase: 'result',
        proposalId: draft.proposalId,
        bundleIndex: bundleIndex,
        proofProgress: null,
        commitments: emitCommitments
            ? _commitments(
                roundId: roundId,
                bundleIndex: bundleIndex,
                proposalId: draft.proposalId,
                choice: draft.choice,
                shareCount: commitmentShareCount,
              )
            : null,
      );
    }
  }

  @override
  Future<rust_wire.SignedVoteCommitmentsView> recoverVoteCommitment({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
  }) async {
    recoveredVoteCommitmentKeys.add('$bundleIndex:$proposalId');
    operationLog.add('recover_vote:$bundleIndex:$proposalId');
    return _commitments(
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      choice: 1,
      shareCount: commitmentShareCount,
    );
  }

  @override
  Future<String> voteCommitmentWireJson({
    required rust_wire.VoteCommitmentWire commitment,
  }) async {
    return jsonEncode({
      'van_nullifier': commitment.vanNullifier,
      'vote_authority_note_new': commitment.voteAuthorityNoteNew,
      'vote_commitment': commitment.voteCommitment,
      'proposal_id': commitment.proposalId,
      'proof': commitment.proof,
      'vote_round_id': commitment.voteRoundId,
      'vote_comm_tree_anchor_height': commitment.anchorHeight,
      'r_vpk': commitment.rVpk,
      'vote_auth_sig': commitment.voteAuthSig,
    });
  }

  @override
  Future<String> voteShareWireJson({
    required rust_wire.VoteShareWire share,
    BigInt? vcTreePosition,
    required BigInt submitAt,
  }) async {
    return jsonEncode({
      'shares_hash': share.sharesHash,
      'proposal_id': share.proposalId,
      'vote_decision': share.voteDecision,
      'enc_share': {
        'c1': base64Encode(share.encryptedShare.c1),
        'c2': base64Encode(share.encryptedShare.c2),
        'share_index': share.encryptedShare.shareIndex,
      },
      'share_index': share.shareIndex,
      'tree_position': (vcTreePosition ?? share.vcTreePosition).toInt(),
      'all_enc_shares': share.allEncryptedShares
          .map(
            (share) => {
              'c1': base64Encode(share.c1),
              'c2': base64Encode(share.c2),
              'share_index': share.shareIndex,
            },
          )
          .toList(),
      'share_comms': share.shareComms,
      'primary_blind': share.primaryBlind,
      'submit_at': submitAt.toInt(),
    });
  }

  @override
  Future<List<rust_share_policy.ShareSubmissionPlan>> planShareSubmissions({
    required int shareCount,
    required List<String> serverUrls,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    BigInt? lastMomentBufferSeconds,
    required bool singleShare,
  }) async {
    final targetCount = serverUrls.isEmpty ? 0 : (serverUrls.length / 2).ceil();
    final now = nowSeconds.toInt();
    final voteEnd = voteEndTimeSeconds.toInt();
    final buffer = lastMomentBufferSeconds?.toInt();
    final deadline = buffer == null ? now : voteEnd - buffer;
    final submitAt = singleShare || buffer == null || deadline <= now
        ? BigInt.zero
        : BigInt.from(now + 1);
    return [
      for (var i = 0; i < shareCount; i++)
        rust_share_policy.ShareSubmissionPlan(
          submitAt: submitAt,
          targetCount: targetCount,
          targetServers: serverUrls.take(targetCount).toList(growable: false),
        ),
    ];
  }

  @override
  Future<int> shareTrackingFlags({
    required rust_frb_types.ShareDelegationRecordView share,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  }) async {
    final now = nowSeconds.toInt();
    final base = share.submitAt > BigInt.zero
        ? share.submitAt.toInt()
        : share.createdAt.toInt();
    var flags = 0;
    if (!share.confirmed && now >= base + 10) {
      flags |= 1;
    }
    final voteEnd = voteEndTimeSeconds?.toInt();
    if (!share.confirmed && voteEnd != null) {
      final remaining = (voteEnd - base).clamp(0, 1 << 31).toInt();
      final threshold = (remaining ~/ 4).clamp(30, 3600).toInt();
      if (now >= base + threshold && voteEnd > now + 10) {
        flags |= 2;
      }
    }
    return flags;
  }

  @override
  Future<BigInt?> nextShareTrackingDelaySeconds({
    required List<rust_frb_types.ShareDelegationRecordView> shares,
    required BigInt nowSeconds,
  }) async {
    final now = nowSeconds.toInt();
    int? nextSecond;
    var hasUnconfirmed = false;
    for (final share in shares.where((share) => !share.confirmed)) {
      hasUnconfirmed = true;
      final base = share.submitAt > BigInt.zero
          ? share.submitAt.toInt()
          : share.createdAt.toInt();
      final checkAt = base + 10;
      if (checkAt > now && (nextSecond == null || checkAt < nextSecond)) {
        nextSecond = checkAt;
      }
    }
    if (!hasUnconfirmed) return null;
    final delay = nextSecond == null
        ? 15
        : (nextSecond - now).clamp(0, 30).toInt();
    return BigInt.from(delay < 3 ? 3 : delay);
  }

  @override
  Future<String> recoveredVoteShareWireJson({
    required String commitmentBundleJson,
    required int proposalId,
    required int shareIndex,
    required BigInt vcTreePosition,
    required BigInt submitAt,
  }) async {
    final decoded = jsonDecode(commitmentBundleJson) as Map<String, dynamic>;
    final payloads = decoded['share_payloads'] as List<dynamic>;
    final payload = payloads.cast<Map<String, dynamic>>().singleWhere((
      payload,
    ) {
      final encShare = payload['enc_share'] as Map<String, dynamic>;
      return payload['proposal_id'] == proposalId &&
          encShare['share_index'] == shareIndex;
    });
    final encShare = payload['enc_share'] as Map<String, dynamic>;
    return jsonEncode({
      'shares_hash': base64Encode(
        _bytesFromHex(payload['shares_hash'] as String),
      ),
      'proposal_id': proposalId,
      'vote_decision': payload['vote_decision'],
      'enc_share': {
        'c1': base64Encode(_bytesFromHex(encShare['c1'] as String)),
        'c2': base64Encode(_bytesFromHex(encShare['c2'] as String)),
        'share_index': shareIndex,
      },
      'share_index': shareIndex,
      'tree_position': vcTreePosition.toInt(),
      'all_enc_shares': (payload['all_enc_shares'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (share) => {
              'c1': base64Encode(_bytesFromHex(share['c1'] as String)),
              'c2': base64Encode(_bytesFromHex(share['c2'] as String)),
              'share_index': share['share_index'],
            },
          )
          .toList(),
      'share_comms': (payload['share_comms'] as List<dynamic>)
          .cast<String>()
          .map((hex) => base64Encode(_bytesFromHex(hex)))
          .toList(),
      'primary_blind': base64Encode(
        _bytesFromHex(payload['primary_blind'] as String),
      ),
      'submit_at': submitAt.toInt(),
    });
  }

  @override
  Future<void> markVoteSubmitted({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) async {
    _addUnique(storedVoteTxHashes, '$bundleIndex:$proposalId:$txHash');
    operationLog.add('mark_vote_submitted:$bundleIndex:$proposalId');
  }

  void _recordVoteConfirmed({
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required int vanPosition,
    required BigInt vcTreePosition,
  }) {
    _addUnique(storedVoteTxHashes, '$bundleIndex:$proposalId:$txHash');
    operationLog.add('mark_vote_confirmed:$bundleIndex:$proposalId');
    storedVanPositions.add('$bundleIndex:$vanPosition');
    storedCommitmentBundles.add('$bundleIndex:$proposalId:$vcTreePosition');
  }

  @override
  Future<rust_wire.VoteConfirmation> confirmVoteSubmission({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required String eventsJson,
  }) async {
    final leafPositions = castVoteLeafPositionsFromTxEventsJson(
      eventsJson,
      roundId,
    );
    _recordVoteConfirmed(
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      txHash: txHash,
      vanPosition: leafPositions.vanPosition,
      vcTreePosition: leafPositions.vcTreePosition,
    );
    return rust_wire.VoteConfirmation(
      txHash: txHash,
      vanLeafPosition: leafPositions.vanPosition,
      vcTreePosition: leafPositions.vcTreePosition,
    );
  }

  @override
  Future<void> recordShareDelegation({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> sentToUrls,
    required BigInt submitAt,
  }) async {
    operationLog.add('record_share:$bundleIndex:$proposalId:$shareIndex');
    recordedShares.add(
      _RecordedShare(
        bundleIndex: bundleIndex,
        proposalId: proposalId,
        shareIndex: shareIndex,
        submitAt: submitAt,
        sentToUrls: sentToUrls,
      ),
    );
  }

  @override
  Future<void> markShareConfirmed({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) async {
    confirmedShares.add('$bundleIndex:$proposalId:$shareIndex');
  }

  @override
  Future<List<int>> deriveHotkey({
    required String mnemonic,
    required String roundId,
    required String network,
  }) async {
    deriveHotkeyCalls++;
    return [roundId.length, network.length, ...mnemonic.codeUnits.take(2)];
  }
}

void _addUnique<T>(List<T> values, T value) {
  if (!values.contains(value)) {
    values.add(value);
  }
}

class _RecordedShare {
  const _RecordedShare({
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.submitAt,
    required this.sentToUrls,
  });

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final BigInt submitAt;
  final List<String> sentToUrls;
}

rust_wire.SignedVoteCommitmentsView _commitments({
  required String roundId,
  required int bundleIndex,
  required int proposalId,
  required int choice,
  int shareCount = 1,
}) {
  final wireShares = [
    for (var shareIndex = 0; shareIndex < shareCount; shareIndex++)
      rust_types.WireEncryptedShare(
        c1: Uint8List.fromList(shareCount == 1 ? [8] : [8, shareIndex]),
        c2: Uint8List.fromList(shareCount == 1 ? [9] : [9, shareIndex]),
        shareIndex: shareIndex,
      ),
  ];
  final shares = [
    for (final wireShare in wireShares)
      rust_wire.VoteShareWire(
        sharesHash: base64Encode(Uint8List.fromList(List.filled(32, 7))),
        proposalId: proposalId,
        voteDecision: choice,
        encryptedShare: wireShare,
        shareIndex: wireShare.shareIndex,
        vcTreePosition: BigInt.from(9),
        allEncryptedShares: wireShares,
        shareComms: [
          for (var i = 0; i < shareCount; i++)
            base64Encode(Uint8List.fromList(List.filled(32, 10 + i))),
        ],
        primaryBlind: base64Encode(
          Uint8List.fromList(List.filled(32, 11 + wireShare.shareIndex)),
        ),
        submitAt: BigInt.zero,
      ),
  ];
  return rust_wire.SignedVoteCommitmentsView(
    bundleIndex: bundleIndex,
    commitments: [
      rust_wire.SignedVoteCommitmentView(
        proposalId: proposalId,
        wire: rust_wire.VoteCommitmentWire(
          vanNullifier: base64Encode(Uint8List.fromList(List.filled(32, 1))),
          voteAuthorityNoteNew: base64Encode(
            Uint8List.fromList(List.filled(32, 2)),
          ),
          voteCommitment: base64Encode(Uint8List.fromList(List.filled(32, 3))),
          proposalId: proposalId,
          proof: base64Encode(Uint8List.fromList([4])),
          voteRoundId: base64Encode(_bytesFromHex(roundId)),
          anchorHeight: 10,
          rVpk: base64Encode(Uint8List.fromList(List.filled(32, 13))),
          voteAuthSig: base64Encode(Uint8List.fromList(List.filled(64, 12))),
        ),
        shares: shares,
      ),
    ],
  );
}
