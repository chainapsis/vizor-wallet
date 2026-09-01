import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_poll_eligibility_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_pir_warmup_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_round_visibility_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_restorer_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_tree_sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/delegate.dart'
    as rust_delegate;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/share_policy.dart'
    as rust_share_policy;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/vote.dart'
    as rust_vote;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_frb_types;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';
import 'package:zcash_wallet/src/services/voting/resolved_voting_config_extensions.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_endpoint_mapper.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import '../../features/voting/round_plan_test_utils.dart';
import '../../features/voting/tx_event_json_test_utils.dart';
import '../../services/voting/fake_voting_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('poll eligibility', () {
    test('lock discards pending results and unlock rechecks', () async {
      final security = _MutableVotingSecurityNotifier(
        const AppSecurityState(isPasswordConfigured: true, isUnlocked: true),
      );
      final rust = _GatedPollEligibilityRustApi();
      final container = _sessionContainer(
        rust: rust,
        securityNotifier: security,
        extraOverrides: [
          votingRoundsProvider.overrideWith(_PollEligibilityRoundsNotifier.new),
          syncProvider.overrideWith(_PollEligibilitySyncNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
      final provider = votingPollEligibilityProvider(kRoundId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await rust.started.future;
      security.setUnlocked(false);
      expect(
        await container.read(provider.future),
        VotingPollEligibility.unknown,
      );
      rust.release.complete();
      await container.pump();
      expect(container.read(provider).value, VotingPollEligibility.unknown);
      security.setUnlocked(true);
      expect(
        await container.read(provider.future),
        VotingPollEligibility.ineligible,
      );
      expect(rust.eligibilityCheckCalls, 2);
    });

    test(
      'sync completion rechecks unknown eligibility without progress-tick queries',
      () async {
        final rust = FakeVotingRustApi();
        final container = _sessionContainer(
          rust: rust,
          walletSyncReadinessChecker: FakeVotingWalletSyncReadinessChecker(
            responses: [
              const VotingWalletSyncReadiness(
                scannedHeight: 1,
                snapshotHeight: 2,
                chainTipHeight: 2,
              ),
              const VotingWalletSyncReadiness(
                scannedHeight: 2,
                snapshotHeight: 2,
                chainTipHeight: 2,
              ),
            ],
          ),
          extraOverrides: [
            votingRoundsProvider.overrideWith(
              _PollEligibilityRoundsNotifier.new,
            ),
            syncProvider.overrideWith(_PollEligibilitySyncNotifier.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(syncProvider.future);
        final provider = votingPollEligibilityProvider(kRoundId);
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        expect(
          await container.read(provider.future),
          VotingPollEligibility.unknown,
        );
        final sync =
            container.read(syncProvider.notifier)
                as _PollEligibilitySyncNotifier;
        sync.progress();
        await container.pump();
        expect(rust.eligibilityCheckCalls, 0);
        sync.complete();
        expect(
          await container.read(provider.future),
          VotingPollEligibility.eligible,
        );
        expect(rust.eligibilityCheckCalls, 1);
      },
    );

    for (final eligible in [true, false]) {
      test(
        'reads snapshot eligibility ($eligible) without preparing votes',
        () async {
          final rust = FakeVotingRustApi(eligibilityEligible: eligible);
          final container = _sessionContainer(
            rust: rust,
            extraOverrides: _pollEligibilityOverrides,
          );
          addTearDown(container.dispose);
          final provider = votingPollEligibilityProvider(kRoundId);
          final subscription = container.listen(provider, (_, _) {});
          addTearDown(subscription.close);
          expect(
            await container.read(provider.future),
            eligible
                ? VotingPollEligibility.eligible
                : VotingPollEligibility.ineligible,
          );
          expect(rust.eligibilityAccountUuids, ['account-1']);
          expect(rust.trustedRoundParamsCalls, 1);
          expect(rust.setupCalls, 0);
          expect(rust.generateVotingHotkeyCalls, 0);
          expect(rust.delegationBundleCalls, isEmpty);
          expect(container.exists(votingSessionProvider(kRoundId)), isFalse);
          await container.read(provider.future);
          expect(rust.eligibilityCheckCalls, 1);
        },
      );
    }

    test(
      'unsynced snapshots stay unknown and recheck after list refresh',
      () async {
        final rust = FakeVotingRustApi(eligibilityEligible: false);
        final readiness = FakeVotingWalletSyncReadinessChecker(
          responses: [
            const VotingWalletSyncReadiness(
              scannedHeight: 1,
              snapshotHeight: 2,
              chainTipHeight: 3,
            ),
            const VotingWalletSyncReadiness(
              scannedHeight: 2,
              snapshotHeight: 2,
              chainTipHeight: 3,
            ),
          ],
        );
        final container = _sessionContainer(
          rust: rust,
          walletSyncReadinessChecker: readiness,
          extraOverrides: _pollEligibilityOverrides,
        );
        addTearDown(container.dispose);
        await container.read(votingRoundsProvider.future);
        final provider = votingPollEligibilityProvider(kRoundId);
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        expect(
          await container.read(provider.future),
          VotingPollEligibility.unknown,
        );
        expect(rust.eligibilityCheckCalls, 0);
        await container.read(votingRoundsProvider.notifier).reload();
        expect(
          await container.read(provider.future),
          VotingPollEligibility.ineligible,
        );
        expect(rust.eligibilityCheckCalls, 1);
      },
    );

    test(
      'rejects unauthenticated rounds before querying their snapshot',
      () async {
        final http = FakeVotingHttpClient(responses: votingHttpResponses());
        final rust = FakeVotingRustApi();
        final container = _sessionContainer(
          http: http,
          rust: rust,
          authenticatedRoundIds: const [kOtherRoundId],
          extraOverrides: _pollEligibilityOverrides,
        );
        addTearDown(container.dispose);
        await expectLater(
          container.read(votingPollEligibilityProvider(kRoundId).future),
          throwsA(isA<StateError>()),
        );
        expect(rust.eligibilityCheckCalls, 0);
        expect(
          http.requests.where(
            (request) => request.uri.path.endsWith('/round/$kRoundId'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'account changes discard late eligibility and check the new account',
      () async {
        final account = NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
        final rust = _GatedPollEligibilityRustApi();
        final container = _sessionContainer(
          rust: rust,
          activeAccountUuidListenable: account,
          extraOverrides: _pollEligibilityOverrides,
        );
        addTearDown(container.dispose);
        final provider = votingPollEligibilityProvider(kRoundId);
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        await rust.started.future;
        container.read(account.notifier).set('account-2');
        expect(container.read(provider).isLoading, isTrue);
        rust.release.complete();
        expect(
          await container.read(provider.future),
          VotingPollEligibility.eligible,
        );
        expect(rust.eligibilityAccountUuids, ['account-1', 'account-2']);
        expect(rust.setupCalls, 0);
      },
    );
  });

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
            SequentialVotingHttpResponses([
              timeoutResponse(),
              staticConfigJson(),
            ]),
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
    final staleRefresh = container
        .read(votingConfigProvider.notifier)
        .refresh();
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

  test('stale config resolution does not invalidate rounds cache', () async {
    var resolveCount = 0;
    final staleLoadStarted = Completer<void>();
    final staleLoadGate = Completer<void>();
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
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
            resolveVotingConfigFromAttempts:
                ({
                  required source,
                  required staticBytes,
                  required attempts,
                  previous,
                }) async {
                  resolveCount++;
                  if (resolveCount == 2) {
                    staleLoadStarted.complete();
                    await staleLoadGate.future;
                    return fakeResolveVotingConfig(
                      dynamicBytes: attempts.last.bytes!,
                      previous: previous,
                      switchKind: rust_config.ConfigSwitchKind.newChainOrRound,
                      authenticatedRoundIds: const [kRoundId],
                    );
                  }
                  return fakeResolveVotingConfig(
                    dynamicBytes: attempts.last.bytes!,
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
        .where(
          (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
        )
        .length;

    final staleRefresh = container
        .read(votingConfigProvider.notifier)
        .refresh();
    await staleLoadStarted.future;

    await container.read(votingConfigProvider.notifier).refresh();
    await container.read(votingRoundsProvider.future);
    final roundsCallsBeforeStaleCompletion = http.requests
        .where(
          (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
        )
        .length;

    staleLoadGate.complete();
    await staleRefresh;
    await container.read(votingRoundsProvider.future);
    final roundsCallsAfterStaleCompletion = http.requests
        .where(
          (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
        )
        .length;

    expect(roundsCallsBeforeStaleCompletion, roundsCallsBefore);
    expect(roundsCallsAfterStaleCompletion, roundsCallsBeforeStaleCompletion);
  });

  test('config switch newChainOrRound invalidates rounds provider', () async {
    var refreshCount = 0;
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
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
            resolveVotingConfigFromAttempts:
                ({
                  required source,
                  required staticBytes,
                  required attempts,
                  previous,
                }) => fakeResolveVotingConfig(
                  dynamicBytes: attempts.last.bytes!,
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
        .where(
          (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
        )
        .length;

    await container.read(votingConfigProvider.notifier).refresh();
    await container.read(votingRoundsProvider.future);
    final roundsCallsAfter = http.requests
        .where(
          (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
        )
        .length;

    expect(roundsCallsAfter, greaterThan(roundsCallsBefore));
  });

  test(
    'poll refresh shows newly authenticated round with same endpoints',
    () async {
      const newRoundId =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      var authenticatedRoundIds = const [kRoundId];
      final responses = <String, Object>{
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {
              'vote_round_id': kRoundId,
              'title': 'Initial poll',
              'status': 'active',
            },
          ],
        },
      };
      final http = FakeVotingHttpClient(responses: responses);
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
              resolveVotingConfigFromAttempts:
                  ({
                    required source,
                    required staticBytes,
                    required attempts,
                    previous,
                  }) => fakeResolveVotingConfig(
                    dynamicBytes: attempts.last.bytes!,
                    previous: previous,
                    authenticatedRoundIds: authenticatedRoundIds,
                    switchKind: previous == null
                        ? rust_config.ConfigSwitchKind.initialLoad
                        : rust_config.ConfigSwitchKind.unchanged,
                  ),
            ),
          ),
          votingActiveAccountUuidProvider.overrideWithValue(() async => null),
        ],
      );
      addTearDown(container.dispose);

      final initial = await container.read(votingRoundsProvider.future);
      expect(initial.map((round) => round.title), ['Initial poll']);

      authenticatedRoundIds = const [kRoundId, newRoundId];
      final dynamicConfig = dynamicConfigJson();
      dynamicConfig['rounds'] = {
        ...dynamicConfig['rounds'] as Map<String, dynamic>,
        newRoundId: {
          'auth_version': 1,
          'ea_pk': _bytes1x32Base64,
          'signatures': [
            {'key_id': 'demo', 'alg': 'ed25519', 'sig': _bytes12x64Base64},
          ],
        },
      };
      responses['https://voting.example/dynamic-voting-config.json'] =
          dynamicConfig;
      responses['/shielded-vote/v1/rounds'] = {
        'rounds': [
          {
            'vote_round_id': kRoundId,
            'title': 'Initial poll',
            'status': 'active',
          },
          {
            'vote_round_id': newRoundId,
            'title': 'New poll',
            'status': 'active',
          },
        ],
      };

      await refreshVotingPollList(
        config: container.read(votingConfigProvider.notifier),
        readRounds: () => container.read(votingRoundsProvider.notifier),
      );
      final refreshed = container.read(votingRoundsProvider).requireValue;

      expect(refreshed.map((round) => round.title), [
        'Initial poll',
        'New poll',
      ]);
    },
  );

  test(
    'config source change invalidates rounds provider on initial load',
    () async {
      const firstSource = 'https://voting-a.example/static-voting-config.json';
      const secondSource = 'https://voting-b.example/static-voting-config.json';
      final http = FakeVotingHttpClient(
        responses: {
          firstSource: staticConfigJson(),
          secondSource: staticConfigJson(),
          'https://voting.example/dynamic-voting-config.json':
              dynamicConfigJson(),
          '/shielded-vote/v1/rounds': {
            'rounds': [
              {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
            ],
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          votingConfigSourceStoreProvider.overrideWithValue(
            FakeVotingConfigSourceStore(sourceUrl: firstSource),
          ),
          votingHttpClientProvider.overrideWithValue(http),
          votingConfigLoaderProvider.overrideWith((ref) {
            final source =
                ref.watch(votingConfigSourceProvider).value?.sourceUrl ??
                kDefaultStaticVotingConfigSource;
            return VotingConfigLoader(
              httpClient: http,
              sourceUrl: source,
              resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
              resolveVotingConfigFromAttempts:
                  ({
                    required source,
                    required staticBytes,
                    required attempts,
                    previous,
                  }) => fakeResolveVotingConfig(
                    dynamicBytes: attempts.last.bytes!,
                    previous: previous,
                    authenticatedRoundIds: const [kRoundId],
                  ),
            );
          }),
          votingActiveAccountUuidProvider.overrideWithValue(() async => null),
        ],
      );
      addTearDown(container.dispose);

      await container.read(votingRoundsProvider.future);
      final roundsCallsBefore = http.requests
          .where(
            (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
          )
          .length;

      await container
          .read(votingConfigSourceProvider.notifier)
          .setCustom(secondSource);
      await container.read(votingConfigProvider.notifier).refresh();
      await container.read(votingRoundsProvider.future);
      final roundsCallsAfter = http.requests
          .where(
            (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
          )
          .length;

      expect(roundsCallsAfter, greaterThan(roundsCallsBefore));
    },
  );

  test(
    'config switch defers interactive session invalidation during submission',
    () async {
      var refreshCount = 0;
      final roundProvider = votingSessionProvider(kRoundId);
      const submissionKey = VotingSessionKey(
        roundId: kRoundId,
        accountUuid: 'account-1',
      );
      final submissionProvider = votingSubmissionSessionProvider(submissionKey);
      final roundObserver = _ProviderDisposalObserver(roundProvider);
      final submissionObserver = _ProviderDisposalObserver(submissionProvider);
      final container = _sessionContainer(
        observers: [roundObserver, submissionObserver],
        configSwitchKind: (previous) => refreshCount++ == 0
            ? rust_config.ConfigSwitchKind.initialLoad
            : rust_config.ConfigSwitchKind.newChainOrRound,
      );
      addTearDown(container.dispose);

      final guard = container
          .read(votingSubmissionGuardProvider.notifier)
          .acquire(accountUuid: 'account-1', roundId: kRoundId);
      addTearDown(() {
        container.read(votingSubmissionGuardProvider.notifier).release(guard);
      });
      final roundSubscription = container
          .listen<AsyncValue<VotingSessionState>>(
            roundProvider,
            (_, _) {},
            fireImmediately: true,
          );
      addTearDown(roundSubscription.close);
      final submissionSubscription = container
          .listen<AsyncValue<VotingSessionState>>(
            submissionProvider,
            (_, _) {},
            fireImmediately: true,
          );
      addTearDown(submissionSubscription.close);
      await container.read(roundProvider.future);
      await container.read(submissionProvider.future);

      await container.read(votingConfigProvider.notifier).refresh();
      await container.pump();

      expect(roundObserver.disposed, isFalse);
      expect(submissionObserver.disposed, isFalse);

      container.read(votingSubmissionGuardProvider.notifier).release(guard);
      await container.pump();

      expect(roundObserver.disposed, isTrue);
      expect(submissionObserver.disposed, isFalse);
    },
  );

  test('config switch unchanged keeps rounds provider cache', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
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
            resolveVotingConfigFromAttempts:
                ({
                  required source,
                  required staticBytes,
                  required attempts,
                  previous,
                }) => fakeResolveVotingConfig(
                  dynamicBytes: attempts.last.bytes!,
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
        .where(
          (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
        )
        .length;

    await container.read(votingConfigProvider.notifier).refresh();
    await container.read(votingRoundsProvider.future);
    final roundsCallsAfter = http.requests
        .where(
          (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
        )
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

  test('rounds provider filters to authenticated round IDs', () async {
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
            resolveVotingConfigFromAttempts:
                ({
                  required source,
                  required staticBytes,
                  required attempts,
                  previous,
                }) => fakeResolveVotingConfig(
                  dynamicBytes: attempts.last.bytes!,
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

  test('rounds provider includes all authenticated rows', () async {
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
              'title': 'Finalized',
              'status': 'finalized',
            },
          ],
        },
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final rounds = await container.read(votingRoundsProvider.future);
    expect(rounds.map((round) => round.roundId), [kRoundId, kOtherRoundId]);
  });

  test('rounds provider hides authenticated [TEST] title prefixes', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {
              'vote_round_id': kRoundId,
              'title': '[TEST] Hidden poll',
              'status': 'active',
            },
            {
              'vote_round_id': kOtherRoundId,
              'title': 'Visible poll [TEST]',
              'status': 'active',
            },
          ],
        },
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final rounds = await container.read(votingRoundsProvider.future);
    expect(rounds.map((round) => round.roundId), [kOtherRoundId]);
  });

  test('rounds provider refreshes when test rounds are enabled', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {
              'vote_round_id': kRoundId,
              'title': '[TEST] Opt-in poll',
              'status': 'active',
            },
            {
              'vote_round_id': kOtherRoundId,
              'title': 'Visible poll',
              'status': 'active',
            },
          ],
        },
      },
    );
    final visibilityStore = FakeVotingRoundVisibilityStore();
    final container = _container(http: http, visibilityStore: visibilityStore);
    addTearDown(container.dispose);

    final hiddenRounds = await container.read(votingRoundsProvider.future);
    expect(hiddenRounds.map((round) => round.roundId), [kOtherRoundId]);

    await container
        .read(showTestVotingRoundsProvider.notifier)
        .setShowTestRounds(true);

    final visibleRounds = await container.read(votingRoundsProvider.future);
    expect(visibleRounds.map((round) => round.roundId), [
      kRoundId,
      kOtherRoundId,
    ]);
    expect(visibilityStore.showTestRounds, isTrue);
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
              ambiguousUrls: const [],
              targetCount: 1,
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
              ambiguousUrls: const [],
              targetCount: 1,
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

  test(
    'session provider rejects rounds absent from the authenticated set',
    () async {
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
    },
  );

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
    'submission session provider disposes after last listener closes',
    () async {
      const key = VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1');
      final provider = votingSubmissionSessionProvider(key);
      final observer = _ProviderDisposalObserver(provider);
      final container = _sessionContainer(observers: [observer]);
      addTearDown(container.dispose);

      final subscription = container.listen<AsyncValue<VotingSessionState>>(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(provider.future);

      expect(observer.disposed, isFalse);

      subscription.close();
      await container.pump();

      expect(observer.disposed, isTrue);
    },
  );

  test('submission job session wrapper releases submission session', () async {
    const key = VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1');
    final sessionProvider = votingSubmissionSessionProvider(key);
    final observer = _ProviderDisposalObserver(sessionProvider);
    final container = _sessionContainer(observers: [observer]);
    addTearDown(container.dispose);

    final subscription = container.listen<AsyncValue<VotingSessionState>>(
      votingSubmissionJobSessionProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    await container.read(sessionProvider.future);

    expect(observer.disposed, isFalse);

    subscription.close();
    await container.pump();

    expect(observer.disposed, isTrue);
  });

  test('submission job dismiss invalidates round session', () async {
    final provider = votingSessionProvider(kRoundId);
    final observer = _ProviderDisposalObserver(provider);
    final container = _sessionContainer(observers: [observer]);
    addTearDown(container.dispose);

    final subscription = container.listen<AsyncValue<VotingSessionState>>(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(provider.future);

    container
        .read(votingSubmissionJobsProvider.notifier)
        .dismiss(
          const VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1'),
        );
    await container.pump();

    expect(observer.disposed, isTrue);
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

  test(
    'rounds reload keeps previous rows visible while refresh is pending',
    () async {
      final responses = <String, Object>{
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
        },
      };
      final http = _GatedVotingHttpClient(responses: responses);
      final container = _sessionContainer(http: http);
      addTearDown(container.dispose);

      final initial = await container.read(votingRoundsProvider.future);
      expect(initial.single.title, 'Poll');

      final roundsGate = http.gateNextGet('/shielded-vote/v1/rounds');
      final reload = container.read(votingRoundsProvider.notifier).reload();
      await http.waitForGetCount('/shielded-vote/v1/rounds', 2);
      final refreshing = container.read(votingRoundsProvider);

      expect(refreshing.isLoading, isTrue);
      expect(refreshing.hasValue, isTrue);
      expect(refreshing.requireValue.single.title, 'Poll');

      roundsGate.complete();
      await reload;
    },
  );

  test('poll refresh skips rounds reload when guard cancels', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);
    await container.read(votingConfigProvider.future);

    final roundsNotifier = _CountingVotingRoundsNotifier();
    var readRoundsCalled = false;
    await refreshVotingPollList(
      config: container.read(votingConfigProvider.notifier),
      shouldReload: () => false,
      readRounds: () {
        readRoundsCalled = true;
        return roundsNotifier;
      },
    );

    expect(readRoundsCalled, isFalse);
    expect(roundsNotifier.reloadCount, 0);
  });

  test('rounds reload fails closed when refresh fails', () async {
    final responses = <String, Object>{
      'https://voting.example/static-voting-config.json': staticConfigJson(),
      'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
      '/shielded-vote/v1/rounds': {
        'rounds': [
          {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
        ],
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

  test('round details expose voting timestamps', () {
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

  test(
    'wallet sync guard waits and forwards the resolved PIR layout',
    () async {
      final rust = FakeVotingRustApi();
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          dynamicConfig: dynamicConfigJson(
            pirLayout: const {
              'pir_depth': 18,
              'tier0_layers': 11,
              'tier1_layers': 7,
              'poly_len': 2048,
            },
          ),
        ),
      );
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
        http: http,
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
      expect(
        rust.lastPirLayout,
        const rust_config.PirLayout(
          pirDepth: 18,
          tier0Layers: 11,
          tier1Layers: 7,
          polyLen: 2048,
        ),
      );
      expect(state.phase, VotingSessionPhase.readyToDelegate);
    },
  );

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
        selectEndpoint:
            ({
              required diagnostics,
              required expectedSnapshotHeight,
              required matchIndex,
            }) {
              final matches = diagnostics
                  .where(
                    (diagnostic) =>
                        diagnostic.status ==
                            PirSnapshotEndpointStatus.matched &&
                        diagnostic.reportedHeight == expectedSnapshotHeight,
                  )
                  .map((diagnostic) => diagnostic.endpoint)
                  .toList(growable: false);
              return matches.isEmpty
                  ? null
                  : matches[matchIndex % matches.length];
            },
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
    expect(rust.setupCalls, 0);
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
    expect(rust.delegationRecoveryCalls, 0);
  });

  test(
    'account switch during delegation serialization stops dispatch',
    () async {
      final delegationWireJsonGate = Completer<void>();
      final rust = FakeVotingRustApi(
        delegationWireJsonGate: delegationWireJsonGate,
      );
      final activeAccountProvider =
          NotifierProvider<_ActiveVotingAccountNotifier, String?>(
            _ActiveVotingAccountNotifier.new,
          );
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
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
      final delegate = container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundles(mnemonic: kTestMnemonic);
      await rust.delegationWireJsonStarted.future;

      container.read(activeAccountProvider.notifier).set('account-2');
      await Future<void>.delayed(Duration.zero);
      delegationWireJsonGate.complete();
      await delegate;

      expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 0);
      expect(rust.storedDelegationTxHashes, isEmpty);
      final reloaded = await container.read(
        votingSessionProvider(kRoundId).future,
      );
      expect(reloaded.accountUuid, 'account-2');
      expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);
    },
  );

  test('spent delegation nullifier uses bounded recovery polling', () async {
    final responses = votingHttpResponses();
    responses['/shielded-vote/v1/delegate-vote'] = {
      'tx_hash': 'rejected-delegation-tx',
      'code': 1,
      'log': 'nullifier already spent: abc123',
    };
    responses['/shielded-vote/v1/tx/rejected-delegation-tx'] = jsonResponse({
      'error': 'not found',
    }, statusCode: 404);
    final http = FakeVotingHttpClient(responses: responses);
    final rust = FakeVotingRustApi(bundleCount: 3);
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: FakeVotingRecoveryApi(state: recoveryState(bundleCount: 3)),
      txConfirmationPolling: const VotingTxConfirmationPolling(
        attempts: 45,
        delay: Duration.zero,
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(
      state.error?.message,
      "Voting has already started for these funds, but Vizor couldn't "
      'recover the submission status. If you used another wallet, return '
      'to it to see the status.',
    );
    expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 1);
    expect(
      http.requests
          .where(
            (request) =>
                request.method == 'GET' &&
                request.uri.path ==
                    '/shielded-vote/v1/tx/rejected-delegation-tx',
          )
          .length,
      3,
    );
    expect(rust.storedDelegationTxHashes, isEmpty);
    expect(rust.delegationRecoveryCalls, 1);
  });

  test(
    'spent delegation nullifier resumes when its tx already landed',
    () async {
      final responses = votingHttpResponses();
      responses['/shielded-vote/v1/delegate-vote'] = {
        'tx_hash': 'delegation-tx',
        'code': 1,
        'log': 'nullifier already spent: abc123',
      };
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(
        http: FakeVotingHttpClient(responses: responses),
        rust: rust,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundles(mnemonic: kTestMnemonic);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.delegated);
      expect(state.error, isNull);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
      expect(rust.storedVanPositions, ['0:0']);
      expect(rust.delegationRecoveryCalls, 0);
    },
  );

  test('spent delegation nullifier waits for tx indexing', () async {
    final responses = votingHttpResponses();
    final confirmation = responses['/shielded-vote/v1/tx/delegation-tx']!;
    responses['/shielded-vote/v1/delegate-vote'] = {
      'tx_hash': 'delegation-tx',
      'code': 1,
      'log': 'nullifier already spent: abc123',
    };
    responses['/shielded-vote/v1/tx/delegation-tx'] =
        SequentialVotingHttpResponses([
          jsonResponse({'error': 'not found'}, statusCode: 404),
          confirmation,
        ]);
    final http = FakeVotingHttpClient(responses: responses);
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(
      http: http,
      rust: rust,
      txConfirmationPolling: const VotingTxConfirmationPolling(
        attempts: 2,
        delay: Duration.zero,
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(state.error, isNull);
    expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
    expect(
      http.requests
          .where(
            (request) =>
                request.method == 'GET' &&
                request.uri.path == '/shielded-vote/v1/tx/delegation-tx',
          )
          .length,
      3,
    );
  });

  test(
    'spent delegation without a tx hash recovers the bundle set from the tree',
    () async {
      final responses = votingHttpResponses();
      responses['/shielded-vote/v1/delegate-vote'] = {
        'code': 1,
        'log': 'nullifier already spent: abc123',
      };
      final http = FakeVotingHttpClient(responses: responses);
      final rust = FakeVotingRustApi(
        bundleCount: 3,
        recoveredDelegationBundleIndices: const {0, 1, 2},
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: FakeVotingRecoveryApi(
          state: recoveryState(bundleCount: 3),
        ),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundles(mnemonic: kTestMnemonic);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.delegated);
      expect(state.error, isNull);
      expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 1);
      expect(rust.delegationRecoveryCalls, 1);
      expect(rust.delegationRecoveryStoredHotkeySecrets, [
        rust.delegationStoredHotkeySecrets.first,
      ]);
      expect(rust.storedDelegationTxHashes, isEmpty);
    },
  );

  test('delegation proves at most three bundles concurrently', () async {
    final proofGate = Completer<void>();
    final rust = FakeVotingRustApi(
      bundleCount: 4,
      delegationProofGate: proofGate,
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(bundleCount: 4),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final delegation = container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(mnemonic: kTestMnemonic);
    while (rust.delegationBundleCalls.length < 3 ||
        (container
                    .read(votingSessionProvider(kRoundId))
                    .value
                    ?.delegationProgress
                    .length ??
                0) <
            3) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(rust.delegationBundleCalls, [0, 1, 2]);
    expect(rust.maxConcurrentDelegationProofs, 3);
    final activeState = container.read(votingSessionProvider(kRoundId)).value!;
    expect(activeState.currentBundleIndex, isNull);
    expect(activeState.delegationProgress.keys, {0, 1, 2});

    proofGate.complete();
    await delegation;

    expect(rust.delegationBundleCalls, [0, 1, 2, 3]);
    expect(rust.maxConcurrentDelegationProofs, 3);
    expect(rust.storedDelegationTxHashes, [
      '0:delegation-tx',
      '1:delegation-tx',
      '2:delegation-tx',
      '3:delegation-tx',
    ]);
  });

  test('delegation drains siblings and preserves successful bundles', () async {
    final proofErrors = <int, Object>{
      1: StateError('injected bundle proof failure'),
    };
    final confirmed = <int, rust_frb_types.DelegationRecoveryView>{};
    late FakeVotingRecoveryApi recoveryApi;
    final rust = FakeVotingRustApi(
      bundleCount: 3,
      delegationStreamErrorsByBundle: proofErrors,
      onDelegationConfirmed: (bundleIndex, txHash, vanLeafPosition) {
        confirmed[bundleIndex] = rust_frb_types.DelegationRecoveryView(
          bundleIndex: bundleIndex,
          phase: VotingWorkflowPhase.submittedDelegation,
          txHash: txHash,
          vanLeafPosition: vanLeafPosition,
        );
        recoveryApi.state = recoveryState(
          bundleCount: 3,
          delegationWorkflows: confirmed.values.toList(),
        );
      },
    );
    recoveryApi = FakeVotingRecoveryApi(state: recoveryState(bundleCount: 3));
    final http = FakeVotingHttpClient(responses: votingHttpResponses());
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.delegatePendingBundles(mnemonic: kTestMnemonic);
    var state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('bundle proof failure'));
    expect(state.resumePlan?.pendingDelegationBundleIndexes, [1]);
    expect(rust.delegationBundleCalls, [0, 1, 2]);
    expect(rust.storedDelegationTxHashes, [
      '0:delegation-tx',
      '2:delegation-tx',
    ]);
    expect(rust.resetVotingSessionStateCalls, isEmpty);

    proofErrors.clear();
    await notifier.delegatePendingBundles(mnemonic: kTestMnemonic);
    state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.delegationBundleCalls, [0, 1, 2, 1]);
    expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 3);
    expect(rust.storedDelegationTxHashes, [
      '0:delegation-tx',
      '2:delegation-tx',
      '1:delegation-tx',
    ]);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
  });

  test('delegation serializes broadcasts and overlaps confirmations', () async {
    final http = _DelegationConcurrencyHttpClient(
      responses: votingHttpResponses(),
    );
    final rust = FakeVotingRustApi(bundleCount: 3);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(bundleCount: 3),
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
        .delegatePendingBundles(mnemonic: kTestMnemonic);

    expect(http.maxConcurrentDelegationPosts, 1);
    expect(http.maxConcurrentConfirmationGets, 3);
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

  test(
    'delegation passes only exact snapshot matches for PIR failover',
    () async {
      final primary = Uri.parse('https://pir-primary.example');
      final behind = Uri.parse('https://pir-behind.example');
      final failover = Uri.parse('https://pir-failover.example');
      final rust = FakeVotingRustApi();
      final pir = FakePirResolver(
        resolution: PirSnapshotResolution(
          endpoint: failover,
          diagnostics: [
            PirSnapshotEndpointDiagnostic(
              endpoint: primary,
              status: PirSnapshotEndpointStatus.matched,
              reportedHeight: 123,
            ),
            PirSnapshotEndpointDiagnostic(
              endpoint: behind,
              status: PirSnapshotEndpointStatus.behind,
              reportedHeight: 122,
            ),
            PirSnapshotEndpointDiagnostic(
              endpoint: failover,
              status: PirSnapshotEndpointStatus.matched,
              reportedHeight: 123,
            ),
          ],
        ),
      );
      final container = _sessionContainer(rust: rust, pirResolver: pir);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundles(mnemonic: kTestMnemonic);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.delegated);
      expect(state.pirEndpoint, failover);
      expect(rust.delegationPirServerUrlBatches, [
        [failover.toString(), primary.toString()],
      ]);
      expect(rust.delegationBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
    },
  );

  test('delegation retry preserves PIR failover endpoints', () async {
    final primary = Uri.parse('https://pir-primary.example');
    final failover = Uri.parse('https://pir-failover.example');
    final proofErrors = <int, Object>{
      0: StateError('temporary delegation failure'),
    };
    final rust = FakeVotingRustApi(delegationStreamErrorsByBundle: proofErrors);
    final container = _sessionContainer(
      rust: rust,
      pirResolver: FakePirResolver(
        resolution: _pirResolution(primary, [primary, failover]),
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.delegatePendingBundles(mnemonic: kTestMnemonic);
    expect(
      container.read(votingSessionProvider(kRoundId)).value?.phase,
      VotingSessionPhase.error,
    );

    proofErrors.clear();
    await notifier.delegatePendingBundles(mnemonic: kTestMnemonic);

    expect(rust.delegationPirServerUrlBatches, [
      [primary.toString(), failover.toString()],
      [primary.toString(), failover.toString()],
    ]);
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

  test('hardware voting retries stale Keystone setup overwrite once', () async {
    final rust = FakeVotingRustApi(
      keystoneDelegationRequestFailuresByCall: {
        0: StateError(
          'delegate::keystone_request failed: Invalid input: '
          'refusing to overwrite pczt_sighash for round=round-id, bundle=0',
        ),
      },
    );
    final container = _sessionContainer(rust: rust, accountIsHardware: true);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.keystoneSigning);
    expect(state.keystoneSigningRequest?.bundleIndex, 0);
    expect(state.error, isNull);
    expect(rust.deleteSkippedBundleKeepCounts, isEmpty);
    expect(rust.resetVotingSessionStateCalls, contains('account-1:$kRoundId'));
    expect(rust.keystoneDelegationRequestCalls, [0, 0]);
    expect(rust.setupCalls, 2);
  });

  test(
    'hardware voting stale-setup recovery preserves unsigned Keystone bundles',
    () async {
      final rust = FakeVotingRustApi(
        bundleCount: 2,
        keystoneDelegationRequestFailuresByCall: {
          0: StateError(
            'delegate::keystone_request failed: Invalid input: '
            'refusing to overwrite padded_note_secrets for round=round-id, bundle=1',
          ),
        },
      );
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
        hotkeyStore: FakeVotingHotkeyStore(const [42, 43, 44]),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneSigningRequest?.bundleIndex, 1);
      expect(state.keystoneSignatures.keys, [0]);
      expect(state.resumePlan?.bundleCount, 2);
      expect(rust.deleteSkippedBundleKeepCounts, isEmpty);
      expect(
        rust.resetVotingSessionStateCalls,
        contains('account-1:$kRoundId'),
      );
      expect(rust.keystoneDelegationRequestCalls, [1, 1]);
      expect(rust.setupCalls, 2);
    },
  );

  test(
    'hardware restart after first keystone signature requests next unsigned bundle',
    () async {
      final rust = FakeVotingRustApi(bundleCount: 2);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(bundleCount: 2),
      );
      final hotkeyStore = FakeVotingHotkeyStore(const [42, 43, 44]);
      var container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
        hotkeyStore: hotkeyStore,
      );

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneBatchSignatures([_keystoneBatchSignature(0)]);

      container.dispose();
      await Future<void>.delayed(Duration.zero);

      container = _sessionContainer(
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
      expect(state.keystoneSigningRequest?.bundleIndex, 1);
      expect(state.keystoneSignatures.keys, [0]);
      expect(state.resumePlan?.bundleCount, 2);
      expect(rust.deleteSkippedBundleKeepCounts, isEmpty);
      expect(rust.keystoneDelegationRequestCalls, [0, 1, 1]);
    },
  );

  test(
    'hardware voting surfaces non-recoverable Keystone request failures',
    () async {
      final rust = FakeVotingRustApi(
        keystoneDelegationRequestFailuresByCall: {
          0: StateError(
            'delegate::keystone_request failed: invalid branch id from lightwalletd',
          ),
        },
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(
        state.error?.message,
        contains('invalid branch id from lightwalletd'),
      );
      expect(rust.keystoneDelegationRequestCalls, [0]);
      expect(rust.deleteSkippedBundleKeepCounts, isEmpty);
    },
  );

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
          .handleKeystoneBatchSignatures([_keystoneBatchSignature(99)]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneScanError, contains('do not match'));
      expect(rust.storedKeystoneSignatures, isEmpty);
    },
  );

  test(
    'hardware voting rejects a conflicting persisted Keystone signature',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(List.filled(64, 7)),
        sighash: Uint8List.fromList(const [99, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneBatchSignatures([_keystoneBatchSignature(0)]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneScanError, contains('conflicts'));
      expect(rust.storedKeystoneSignatures[0]?.sig, List.filled(64, 7));
    },
  );

  test(
    'hardware voting resumes with a differently randomized persisted signature',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(List.filled(64, 7)),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneBatchSignatures([_keystoneBatchSignature(0)]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.keystoneScanError, isNull);
      expect(rust.storedKeystoneSignatures, hasLength(1));
    },
  );

  test(
    'hardware voting retries the same response after an atomic store failure',
    () async {
      final rust = FakeVotingRustApi(
        keystoneSignatureBatchFailuresRemaining: 1,
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      final response = [_keystoneBatchSignature(0)];

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneBatchSignatures(response);
      var state = container.read(votingSessionProvider(kRoundId)).value!;
      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(
        state.keystoneSigningRequests.map((request) => request.bundleIndex),
        [0],
      );
      expect(state.keystoneScanError, contains('same Keystone result'));
      expect(rust.storedKeystoneSignatures, isEmpty);

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneBatchSignatures(response);
      state = container.read(votingSessionProvider(kRoundId)).value!;
      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.keystoneScanError, isNull);
      expect(rust.storedKeystoneSignatures.keys, [0]);
    },
  );

  test(
    'hardware voting fills a missing suffix from a partially persisted batch',
    () async {
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
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(List.filled(64, 30)),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneBatchSignatures([
            _keystoneBatchSignature(0),
            _keystoneBatchSignature(1),
          ]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(rust.storedKeystoneSignatures.keys, [0, 1]);
      expect(rust.storedKeystoneSignatures[1]?.sig, List.filled(64, 31));
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
          .handleKeystoneBatchSignatures([_keystoneBatchSignature(0)]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.keystoneSigningRequest, isNull);
      expect(state.keystoneSignatures.keys, [0]);
      expect(rust.storedKeystoneSignatures[0]?.sig, List.filled(64, 30));
    },
  );

  test('hardware voting stores one compact signature batch', () async {
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
    var state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(
      state.keystoneSigningRequests.map((request) => request.bundleIndex),
      [0, 1],
    );

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .handleKeystoneBatchSignatures([
          VotingKeystoneBatchSignature(
            bundleIndex: 0,
            pool: 1,
            actionIndex: 0,
            signature: List.filled(64, 30),
          ),
          VotingKeystoneBatchSignature(
            bundleIndex: 1,
            pool: 1,
            actionIndex: 0,
            signature: List.filled(64, 31),
          ),
        ]);
    state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.readyToDelegate);
    expect(state.keystoneSigningRequests, isEmpty);
    expect(state.keystoneSignatures.keys, [0, 1]);
    expect(rust.storedKeystoneSignatures[0]?.sig, List.filled(64, 30));
    expect(rust.storedKeystoneSignatures[1]?.sig, List.filled(64, 31));
  });

  test(
    'hardware voting rejects an Orchard PCZT signature before storing',
    () async {
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
          .handleKeystoneBatchSignatures([
            VotingKeystoneBatchSignature(
              bundleIndex: 0,
              pool: 1,
              actionIndex: 0,
              signature: List.filled(64, 30),
            ),
            VotingKeystoneBatchSignature(
              bundleIndex: 1,
              pool: 0,
              actionIndex: 0,
              signature: List.filled(64, 31),
            ),
          ]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneScanError, contains('invalid voting signature'));
      expect(rust.storedKeystoneSignatures, isEmpty);
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
        .handleKeystoneBatchSignatures([_keystoneBatchSignature(0)]);
    var state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.keystoneSigning);
    expect(state.keystoneSigningRequest?.bundleIndex, 1);
    expect(state.keystoneSignatures.keys, [0]);
    expect(rust.keystoneDelegationRequestCalls, [0, 1]);

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .handleKeystoneBatchSignatures([_keystoneBatchSignature(1)]);
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
    expect(rust.maxConcurrentKeystoneDelegationProofs, 2);
    expect(rust.storedDelegationTxHashes, [
      '0:delegation-tx',
      '1:delegation-tx',
    ]);
  });

  test('hardware partial delegation retry skips confirmed siblings', () async {
    final proofErrors = <int, Object>{
      1: StateError('injected Keystone bundle proof failure'),
    };
    final confirmed = <int, rust_frb_types.DelegationRecoveryView>{};
    late FakeVotingRecoveryApi recoveryApi;
    final rust = FakeVotingRustApi(
      bundleCount: 3,
      keystoneDelegationStreamErrorsByBundle: proofErrors,
      onDelegationConfirmed: (bundleIndex, txHash, vanLeafPosition) {
        confirmed[bundleIndex] = rust_frb_types.DelegationRecoveryView(
          bundleIndex: bundleIndex,
          phase: VotingWorkflowPhase.submittedDelegation,
          txHash: txHash,
          vanLeafPosition: vanLeafPosition,
        );
        recoveryApi.state = recoveryState(
          bundleCount: 3,
          delegationWorkflows: confirmed.values.toList(),
        );
      },
    );
    for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++) {
      rust.storedKeystoneSignatures[bundleIndex] =
          rust_wire.KeystoneSignatureRecord(
            bundleIndex: bundleIndex,
            sig: Uint8List.fromList([3, bundleIndex]),
            sighash: Uint8List.fromList([10, bundleIndex]),
            rk: Uint8List.fromList([2, bundleIndex]),
          );
    }
    recoveryApi = FakeVotingRecoveryApi(state: recoveryState(bundleCount: 3));
    final http = FakeVotingHttpClient(responses: votingHttpResponses());
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
      accountIsHardware: true,
      hotkeyStore: FakeVotingHotkeyStore(const [42, 43, 44]),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.delegatePendingBundlesWithKeystoneSignatures();
    var state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('Keystone bundle proof failure'));
    expect(state.resumePlan?.pendingDelegationBundleIndexes, [1]);
    expect(rust.keystoneProofBundleCalls, [0, 1, 2]);
    expect(rust.storedKeystoneSignatures.keys, [0, 1, 2]);
    expect(rust.resetVotingSessionStateCalls, isEmpty);

    proofErrors.clear();
    await notifier.delegatePendingBundlesWithKeystoneSignatures();
    state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.keystoneProofBundleCalls, [0, 1, 2, 1]);
    expect(_postRequestCount(http, '/shielded-vote/v1/delegate-vote'), 3);
    expect(rust.storedKeystoneSignatures.keys, [0, 1, 2]);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
  });

  test(
    'hardware voting can skip unsigned Keystone bundles after prefix signed',
    () async {
      late FakeVotingRecoveryApi recoveryApi;
      late FakeVotingRustApi rust;
      rust = FakeVotingRustApi(
        bundleCount: 2,
        setupEligibleWeight: 4900000000,
        onDeleteSkippedBundles: (keepCount) {
          recoveryApi.state = recoveryState(bundleCount: keepCount);
          rust.setupEligibleWeight = 3712500000;
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
          .handleKeystoneBatchSignatures([_keystoneBatchSignature(0)]);
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
      expect(state.eligibleWeightZatoshi, BigInt.from(3712500000));
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
      expect(state.error?.message, contains('missing stored voting hotkey'));
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

  test('hardware delegation passes PIR failover endpoints to Rust', () async {
    final primary = Uri.parse('https://pir-primary.example');
    final failover = Uri.parse('https://pir-failover.example');
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
      pirResolver: FakePirResolver(
        resolution: _pirResolution(primary, [primary, failover]),
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundlesWithKeystoneSignatures();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(state.pirEndpoint, primary);
    expect(rust.keystonePirServerUrlBatches, [
      [primary.toString(), failover.toString()],
    ]);
    expect(rust.keystoneProofBundleCalls, [0]);
    expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
  });

  test(
    'hardware voting blocks delegation when later Keystone bundle is unsigned',
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
        hotkeyStore: FakeVotingHotkeyStore(const [42, 43, 44]),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(
        state.error?.message,
        contains('Sign delegation bundle 2 with Keystone before submitting'),
      );
      expect(rust.keystoneProofBundleCalls, isEmpty);
      expect(rust.storedDelegationTxHashes, isEmpty);
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
      expect(state.error?.message, contains('missing stored voting hotkey'));
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

  test('submission job rejects a round without an end time', () async {
    final roundStatus =
        roundStatusJson(roundId: kRoundId, includeVoteEnd: false)
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
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(
      http: http,
      rust: rust,
      draftPersistence: draftPersistence,
    );
    addTearDown(container.dispose);

    final startedKey = await container
        .read(votingSubmissionJobsProvider.notifier)
        .start(kRoundId);
    final failed = await _waitForJobStatus(
      container,
      startedKey!,
      VotingSubmissionJobStatus.error,
    );

    expect(
      failed.errorMessage,
      'Voting round end time is unavailable. Retry in a moment.',
    );
    expect(rust.eligibilityCheckCalls, 0);
    expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 0);
    expect(_postRequestCount(http, '/shielded-vote/v1/shares'), 0);
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
      expect(rust.generateVotingHotkeyCalls, 1);
      expect(hotkeyStore.hotkey, [42, 43, 44]);
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
          needsSetupPlan,
          delegatePlan,
          delegatePlan,
          votePlan,
          votePlan,
          votePlan,
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
        accountBip39Passphrase: '  My TREZOR phrase  ',
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
      expect(rust.delegationMnemonics, [
        const SoftwareWalletSecret(
          mnemonic: kTestMnemonic,
          bip39Passphrase: '  My TREZOR phrase  ',
        ).encodeForStorage(),
      ]);
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
        accountMnemonic: null,
        hotkeyStore: const FailingVotingHotkeyStore(),
        pirResolver: FakePirResolver(error: StateError('unexpected PIR')),
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
      expect(rust.setupCalls, 0);
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
        hotkeyStore: const FailingVotingHotkeyStore(),
        pirResolver: FakePirResolver(error: StateError('unexpected PIR')),
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
      expect(rust.setupCalls, 0);
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
    'submission job revalidates completed session after draft load failure',
    () async {
      final rust = FakeVotingRustApi();
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
        roundPlanSequence: [completedPlan, completedPlan],
      );
      final draftPersistence = FakeVotingDraftPersistence()
        ..loadError = StateError('draft load failed');
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        draftPersistence: draftPersistence,
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
      final completed = await _waitForJobStatus(
        container,
        startedKey!,
        VotingSubmissionJobStatus.complete,
      );

      expect(completed.errorMessage, isNull);
      expect(rust.eligibilityCheckCalls, 1);
      expect(rust.setupCalls, 0);
    },
  );

  test('submitted delegation recovery continues pending share recovery', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shareNullifier = Uint8List.fromList(List.filled(32, 1));
    final shareId = _hexFromBytes(shareNullifier);
    final acceptedShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://helper-a.example'],
      ambiguousUrls: const [],
      targetCount: 1,
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
            roundStatus: roundStatusJson(
              roundId: kRoundId,
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
                {'status': 'confirmed'},
            'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
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
  });

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
        ambiguousUrls: const [],
        targetCount: 1,
        nullifier: shareNullifier,
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.zero,
        createdAt: BigInt.one,
      );
      final trackingGate = Completer<void>();
      final rust = FakeVotingRustApi(trackingPassPolicyGate: trackingGate);
      addTearDown(() {
        if (!trackingGate.isCompleted) trackingGate.complete();
      });
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
      expect(
        container.read(votingShareTrackingRegistryProvider).registeredKeys,
        {startedKey},
      );
      expect(rust.confirmedShares, isEmpty);
      expect(trackingGate.isCompleted, isFalse);
      await rust.trackingPassPolicyStarted.future;
      expect(
        container.read(votingSubmissionJobProvider(startedKey)).status,
        VotingSubmissionJobStatus.complete,
      );
      expect(rust.helperDeliveryContexts, hasLength(1));
      expect(rust.helperDeliveryContexts.single.isDisposed, isFalse);
      expect(
        rust.shareTrackingPassHandles.single.context,
        same(rust.helperDeliveryContexts.single),
      );

      var drained = false;
      final drain = container
          .read(votingShareTrackingRegistryProvider)
          .quiesceAndDrain(accountUuid: 'account-1')
          .then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);

      trackingGate.complete();
      await drain;
      expect(drained, isTrue);
      expect(rust.shareTrackingPassHandles, hasLength(1));
      expect(rust.shareTrackingPassHandles.single.accountUuid, 'account-1');
      expect(rust.shareTrackingPassHandles.single.roundId, kRoundId);
      expect(rust.shareTrackingPassHandles.single.isCancelled, isTrue);
      expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
      expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
    },
  );

  test('provider disposal closes an in-flight share tracking handle', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pendingShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://helper-a.example'],
      ambiguousUrls: const [],
      targetCount: 1,
      nullifier: Uint8List.fromList(List.filled(32, 3)),
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.from(nowSeconds - 100),
    );
    final rust = FakeVotingRustApi()
      ..trackPendingSharesGate = Completer<void>();
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: FakeVotingRecoveryApi(
        state: recoveryState(
          shareDelegations: [pendingShare],
          unconfirmedShareDelegations: [pendingShare],
        ),
      ),
    );
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: kRoundId);

    await container.read(votingSubmissionSessionProvider(key).future);
    final pass = container
        .read(votingSubmissionSessionProvider(key).notifier)
        .runShareTrackingPass();
    await rust.trackPendingSharesStarted.future;

    container.dispose();
    await pass;

    expect(rust.shareTrackingPassHandles, hasLength(1));
    expect(rust.shareTrackingPassHandles.single.isCancelled, isTrue);
    expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
    expect(rust.helperDeliveryContexts, hasLength(1));
    expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
  });

  test('immediate share waits until two accepted helpers corroborate', () async {
    final fullTrackingGate = Completer<void>();
    addTearDown(() {
      if (!fullTrackingGate.isCompleted) fullTrackingGate.complete();
    });
    final shareNullifier = Uint8List.fromList(List.filled(32, 9));
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
      ambiguousUrls: const [],
      targetCount: 2,
      nullifier: shareNullifier,
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.one,
    );
    final confirmedShare = rust_frb_types.ShareDelegationRecordView(
      roundId: acceptedShare.roundId,
      bundleIndex: acceptedShare.bundleIndex,
      proposalId: acceptedShare.proposalId,
      shareIndex: acceptedShare.shareIndex,
      sentToUrls: acceptedShare.sentToUrls,
      ambiguousUrls: acceptedShare.ambiguousUrls,
      targetCount: acceptedShare.targetCount,
      nullifier: acceptedShare.nullifier,
      phase: VotingWorkflowPhase.confirmed,
      confirmed: true,
      submitAt: acceptedShare.submitAt,
      createdAt: acceptedShare.createdAt,
    );
    late final FakeVotingRecoveryApi recoveryApi;
    final rust = FakeVotingRustApi(
      trackingPassPolicyGate: fullTrackingGate,
      onShareConfirmed: (_, _, _) {
        recoveryApi.state = recoveryState(
          bundleCount: 1,
          shareDelegations: [confirmedShare],
        );
      },
    );
    recoveryApi = _submittedDelegationWithShareRecoveryApi(
      acceptedShare,
      designateImmediateShare: true,
    );
    final http = FakeVotingHttpClient(
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
                {'status': 'confirmed'},
            'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'confirmed'},
          }),
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    final key = await container
        .read(votingSubmissionJobsProvider.notifier)
        .start(kRoundId);
    final completed = await _waitForJobStatus(
      container,
      key!,
      VotingSubmissionJobStatus.complete,
    );

    expect(completed.errorMessage, isNull);
    expect(rust.confirmedShares, ['0:7:0']);
    expect(rust.focusedShareConfirmationCalls, ['0:7:0']);
    expect(rust.trackingPassPolicyStarted.isCompleted, isFalse);
    expect(rust.shareTrackingPassHandles, hasLength(1));
    expect(rust.shareTrackingPassHandles.single.isCancelled, isFalse);
    expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
    expect(rust.helperDeliveryContexts, hasLength(1));
    await container.pump();
    expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
    expect(
      http.requests
          .where((request) => request.uri.path.contains('/share-status/'))
          .map((request) => request.uri.host),
      ['helper-a.example', 'helper-b.example'],
    );
  });

  test('share tracking drain awaits focused confirmation', () async {
    final confirmationGate = Completer<void>();
    addTearDown(() {
      if (!confirmationGate.isCompleted) confirmationGate.complete();
    });
    final pendingShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://helper-a.example'],
      ambiguousUrls: const [],
      targetCount: 1,
      nullifier: Uint8List.fromList(List.filled(32, 9)),
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.one,
    );
    final rust = FakeVotingRustApi(
      focusedShareConfirmationGate: confirmationGate,
    );
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: _submittedDelegationWithShareRecoveryApi(
        pendingShare,
        designateImmediateShare: true,
      ),
    );
    addTearDown(container.dispose);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);

    await container.read(votingSessionProvider(kRoundId).future);
    final confirmation = notifier.refreshImmediateShareConfirmation();
    await rust.focusedShareConfirmationStarted.future.timeout(
      const Duration(seconds: 1),
    );

    var drained = false;
    final drain = notifier.stopAndDrainShareTracking().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(drained, isFalse);
    expect(rust.shareTrackingPassHandles.single.isCancelled, isTrue);
    expect(rust.helperDeliveryContexts.single.isDisposed, isFalse);

    confirmationGate.complete();
    await drain;
    await confirmation;

    expect(drained, isTrue);
    expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
    expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
  });

  test(
    'full and focused tracking serialize through destructive drain',
    () async {
      final fullTrackingGate = Completer<void>();
      final focusedConfirmationGate = Completer<void>();
      addTearDown(() {
        if (!fullTrackingGate.isCompleted) fullTrackingGate.complete();
        if (!focusedConfirmationGate.isCompleted) {
          focusedConfirmationGate.complete();
        }
      });
      final pendingShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        ambiguousUrls: const [],
        targetCount: 1,
        nullifier: Uint8List.fromList(List.filled(32, 9)),
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.zero,
        createdAt: BigInt.one,
      );
      final rust = FakeVotingRustApi(
        focusedShareConfirmationGate: focusedConfirmationGate,
      )..trackPendingSharesGate = fullTrackingGate;
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: _submittedDelegationWithShareRecoveryApi(
          pendingShare,
          designateImmediateShare: true,
        ),
      );
      addTearDown(container.dispose);
      const key = VotingSessionKey(accountUuid: 'account-1', roundId: kRoundId);
      final notifier = container.read(
        votingSubmissionSessionProvider(key).notifier,
      );

      await container.read(votingSubmissionSessionProvider(key).future);
      final fullPass = notifier.runShareTrackingPass();
      await rust.trackPendingSharesStarted.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw StateError('full tracking did not start'),
      );
      final focusedPass = notifier.refreshImmediateShareConfirmation();
      await Future<void>.delayed(Duration.zero);

      expect(rust.focusedShareConfirmationStarted.isCompleted, isFalse);
      expect(rust.shareTrackingPassHandles, hasLength(1));

      var drained = false;
      final drain = notifier.stopAndDrainShareTracking().then((_) {
        drained = true;
      });
      await Future.wait([fullPass, focusedPass, drain]);

      expect(drained, isTrue);
      expect(rust.focusedShareConfirmationStarted.isCompleted, isFalse);
      expect(rust.shareTrackingPassHandles.single.isCancelled, isTrue);
      expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
      expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
    },
  );

  test(
    'expiry confirms an immediate share with only outcome-unknown delivery',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final voteEndSeconds = nowSeconds + 2;
      final shareNullifier = Uint8List.fromList(List.filled(32, 9));
      final shareId = _hexFromBytes(shareNullifier);
      final acceptedShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const [],
        ambiguousUrls: const ['https://helper-a.example'],
        targetCount: 1,
        nullifier: shareNullifier,
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.zero,
        createdAt: BigInt.one,
      );
      final confirmedShare = rust_frb_types.ShareDelegationRecordView(
        roundId: acceptedShare.roundId,
        bundleIndex: acceptedShare.bundleIndex,
        proposalId: acceptedShare.proposalId,
        shareIndex: acceptedShare.shareIndex,
        sentToUrls: acceptedShare.sentToUrls,
        ambiguousUrls: acceptedShare.ambiguousUrls,
        targetCount: acceptedShare.targetCount,
        nullifier: acceptedShare.nullifier,
        phase: VotingWorkflowPhase.confirmed,
        confirmed: true,
        submitAt: acceptedShare.submitAt,
        createdAt: acceptedShare.createdAt,
      );
      late final FakeVotingRecoveryApi recoveryApi;
      final rust = FakeVotingRustApi(
        onShareConfirmed: (_, _, _) {
          recoveryApi.state = recoveryState(
            bundleCount: 1,
            shareDelegations: [confirmedShare],
          );
        },
      );
      recoveryApi = _submittedDelegationWithShareRecoveryApi(
        acceptedShare,
        designateImmediateShare: true,
      );
      final http = FakeVotingHttpClient(
        responses:
            votingHttpResponses(
              roundStatus: roundStatusJson(
                roundId: kRoundId,
                voteEnd: voteEndSeconds,
              ),
              dynamicConfig: dynamicConfigJson(
                voteServers: const [
                  {'url': 'https://helper-a.example', 'label': 'helper-a'},
                  {'url': 'https://helper-b.example', 'label': 'helper-b'},
                ],
              ),
            )..addAll({
              'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  SequentialVotingHttpResponses([
                    {'status': 'pending'},
                    {'status': 'confirmed'},
                  ]),
              'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  SequentialVotingHttpResponses([
                    {'status': 'pending'},
                    {'status': 'confirmed'},
                  ]),
            }),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      final key = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      await _waitForStoredVanPosition(rust, '0:0');
      expect(
        container.read(votingSubmissionJobProvider(key!)).status,
        VotingSubmissionJobStatus.running,
      );

      final completed = await _waitForJobStatus(
        container,
        key,
        VotingSubmissionJobStatus.complete,
        attempts: 400,
      );

      expect(completed.errorMessage, isNull);
      expect(rust.confirmedShares, ['0:7:0']);
      expect(
        http.requests.where(
          (request) => request.uri.path.contains('/share-status/'),
        ),
        hasLength(4),
      );
    },
  );

  test(
    'unconfirmed immediate share fails the submission job when voting ends',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final voteEndSeconds = nowSeconds + 2;
      final shareNullifier = Uint8List.fromList(List.filled(32, 9));
      final shareId = _hexFromBytes(shareNullifier);
      final acceptedShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        ambiguousUrls: const [],
        targetCount: 1,
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
              roundStatus: roundStatusJson(
                roundId: kRoundId,
                voteEnd: voteEndSeconds,
              ),
              dynamicConfig: dynamicConfigJson(
                voteServers: const [
                  {'url': 'https://helper-a.example', 'label': 'helper-a'},
                ],
              ),
            )..addAll({
              'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  StateError('helper unavailable'),
            }),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: _submittedDelegationWithShareRecoveryApi(
          acceptedShare,
          designateImmediateShare: true,
        ),
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      final key = await container
          .read(votingSubmissionJobsProvider.notifier)
          .start(kRoundId);
      await _waitForStoredVanPosition(rust, '0:0');
      expect(
        container.read(votingSubmissionJobProvider(key!)).status,
        VotingSubmissionJobStatus.running,
      );

      final waitUntilExpiry = DateTime.fromMillisecondsSinceEpoch(
        voteEndSeconds * 1000,
      ).difference(DateTime.now());
      if (waitUntilExpiry > Duration.zero) {
        await Future<void>.delayed(
          waitUntilExpiry + const Duration(milliseconds: 50),
        );
      }
      final failed = await _waitForJobStatus(
        container,
        key,
        VotingSubmissionJobStatus.error,
      );

      expect(
        failed.errorMessage,
        'The voting round ended before a helper confirmed the immediate share. '
        'Check the voting status before retrying.',
      );
      expect(
        container
            .read(votingSubmissionGuardProvider.notifier)
            .guardForAccount('account-1'),
        isNull,
      );
    },
  );

  test(
    'share tracking releases its registration when the round expires',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final voteEndSeconds = nowSeconds + 2;
      final acceptedShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        ambiguousUrls: const [],
        targetCount: 1,
        nullifier: Uint8List.fromList(List.filled(32, 1)),
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.zero,
        createdAt: BigInt.one,
      );
      final trackingGate = Completer<void>();
      final rust = FakeVotingRustApi(trackingPassPolicyGate: trackingGate);
      addTearDown(() {
        if (!trackingGate.isCompleted) trackingGate.complete();
      });
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            voteEnd: voteEndSeconds,
          ),
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
      await _waitForJobStatus(
        container,
        startedKey!,
        VotingSubmissionJobStatus.complete,
      );
      await rust.trackingPassPolicyStarted.future;

      final registry = container.read(votingShareTrackingRegistryProvider);
      expect(registry.registeredKeys, {startedKey});

      final waitUntilExpiry = DateTime.fromMillisecondsSinceEpoch(
        voteEndSeconds * 1000,
      ).difference(DateTime.now());
      if (waitUntilExpiry > Duration.zero) {
        await Future<void>.delayed(
          waitUntilExpiry + const Duration(milliseconds: 50),
        );
      }
      trackingGate.complete();
      for (var i = 0; i < 100 && registry.registeredKeys.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(registry.registeredKeys, isEmpty);
      expect(rust.shareTrackingPassHandles, hasLength(1));
      expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
      expect(rust.helperDeliveryContexts, hasLength(1));
      expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
    },
  );

  test('share tracking failure fails the job and releases its guard', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pendingShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const [],
      ambiguousUrls: const [],
      targetCount: 0,
      nullifier: Uint8List.fromList(List.filled(32, 1)),
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.one,
    );
    final rust = FakeVotingRustApi(
      shareResubmissionError: StateError('share retry planning failed'),
    );
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(
        roundStatus: roundStatusJson(
          roundId: kRoundId,
          voteEnd: nowSeconds + 1000,
        ),
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
      recoveryApi: _submittedDelegationWithShareRecoveryApi(
        pendingShare,
        includeCommitmentBundle: true,
      ),
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    final key = await container
        .read(votingSubmissionJobsProvider.notifier)
        .start(kRoundId);
    expect(
      key,
      const VotingSessionKey(roundId: kRoundId, accountUuid: 'account-1'),
    );
    final failed = await _waitForJobStatus(
      container,
      key!,
      VotingSubmissionJobStatus.error,
    );

    expect(failed.errorMessage, 'share retry planning failed');
    // The failure came from a tracking pass that actually ran.
    expect(rust.trackPendingSharesCalls, isNotEmpty);
    expect(rust.shareTrackingPassHandles, hasLength(1));
    expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
    expect(rust.helperDeliveryContexts, hasLength(1));
    expect(rust.helperDeliveryContexts.single.isDisposed, isFalse);
    expect(container.read(votingShareTrackingRegistryProvider).registeredKeys, {
      key,
    });
    expect(
      container
          .read(votingSubmissionGuardProvider.notifier)
          .guardForAccount('account-1'),
      isNull,
    );
  });

  test('submission job clears stale vote progress at start', () async {
    final rust = FakeVotingRustApi(emitCommitments: true);
    final readiness = _MutableVotingWalletSyncReadinessChecker(ready: true);
    final persistence = FakeVotingDraftPersistence();
    const draftKey = VotingSessionKey(
      roundId: kRoundId,
      accountUuid: 'account-1',
    );
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(
        roundStatus: roundStatusJson(roundId: kRoundId)
          ..['proposals'] = [
            {
              'id': 7,
              'title': 'One',
              'options': [
                {'index': 0, 'label': 'No'},
                {'index': 1, 'label': 'Yes'},
              ],
            },
          ],
      ),
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      draftPersistence: persistence,
      walletSyncReadinessChecker: readiness,
      walletSyncPollInterval: const Duration(milliseconds: 1),
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    final submissionSessionSubscription = container.listen(
      votingSubmissionSessionProvider(draftKey),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(submissionSessionSubscription.close);

    await container.read(votingSubmissionSessionProvider(draftKey).future);
    await container
        .read(votingSubmissionSessionProvider(draftKey).notifier)
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
    final staleSession = container
        .read(votingSubmissionJobSessionProvider(draftKey))
        .value!;
    expect(staleSession.voteSubmissionProgress, 1);
    expect(staleSession.voteSubmissionCompletedCount, 1);

    readiness.ready = false;
    container.read(votingDraftProvider(draftKey).notifier).setChoice(7, 1);
    await Future<void>.delayed(Duration.zero);
    final key = await container
        .read(votingSubmissionJobsProvider.notifier)
        .start(kRoundId, accountUuid: 'account-1');
    expect(key, draftKey);
    await _waitForJobSessionPhase(
      container,
      draftKey,
      VotingSessionPhase.waitingForWalletSync,
    );
    final resetSession = container
        .read(votingSubmissionJobSessionProvider(draftKey))
        .value!;

    expect(resetSession.voteSubmissionProgress, isNull);
    expect(resetSession.voteSubmissionCompletedCount, 0);
    expect(resetSession.voteSubmissionTotalCount, 0);
  });

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
    final rust = FakeVotingRustApi(emitCommitments: true);
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

    expect(state.phase, VotingSessionPhase.done);
    expect(state.voteProgress.keys.toSet(), {
      const VotingVoteKey(bundleIndex: 0, proposalId: 7),
      const VotingVoteKey(bundleIndex: 1, proposalId: 7),
    });
    expect(rust.voteCommitBundleCalls, [0, 1]);
  });

  test('spent nullifier reports status and stops queued broadcasts', () async {
    final responses = votingHttpResponses();
    responses['/shielded-vote/v1/cast-vote'] = {
      'tx_hash': 'rejected-vote-tx',
      'code': 1,
      'log': 'nullifier already spent: abc123',
    };
    responses['/shielded-vote/v1/tx/rejected-vote-tx'] = jsonResponse({
      'error': 'not found',
    }, statusCode: 404);
    final http = FakeVotingHttpClient(responses: responses);
    final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 3);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 3,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
            vote(bundleIndex: bundleIndex, proposalId: 7),
        ],
      ),
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _singleProposalDrafts());
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(
      state.error?.message,
      "Voting has already started for these funds, but Vizor couldn't recover "
      'the submission status. If you used another wallet, return to it to see '
      'the status.',
    );
    expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 1);
    expect(rust.storedVoteTxHashes, isEmpty);
  });

  test('account switch stops vote broadcasts waiting for the permit', () async {
    final http = _GatedFirstVotePostHttpClient(
      responses: votingHttpResponses(),
    );
    final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 3);
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 3,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
            vote(bundleIndex: bundleIndex, proposalId: 7),
        ],
      ),
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
    final cast = container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _singleProposalDrafts());
    await http.firstVotePostStarted.future;
    await _waitForPlannedShareCount(rust, 3);

    container.read(activeAccountProvider.notifier).set('account-2');
    await Future<void>.delayed(Duration.zero);
    http.releaseFirstVotePost.complete();
    await cast;

    expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 1);
    expect(rust.storedVoteTxHashes, ['0:7:vote-tx-0']);
    final reloaded = await container.read(
      votingSessionProvider(kRoundId).future,
    );
    expect(reloaded.accountUuid, 'account-2');
    expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);
  });

  test('account switch during vote serialization stops dispatch', () async {
    final voteWireJsonGate = Completer<void>();
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      voteWireJsonGate: voteWireJsonGate,
    );
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final http = FakeVotingHttpClient(responses: votingHttpResponses());
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: _singleVoteRecoveryApi(),
      activeAccountUuidListenable: activeAccountProvider,
    );
    final subscription = container.listen(
      votingSessionProvider(kRoundId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final cast = container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _singleProposalDrafts());
    await rust.voteWireJsonStarted.future;

    container.read(activeAccountProvider.notifier).set('account-2');
    await Future<void>.delayed(Duration.zero);
    voteWireJsonGate.complete();
    await cast;

    expect(_postRequestCount(http, '/shielded-vote/v1/cast-vote'), 0);
    expect(rust.storedVoteTxHashes, isEmpty);
    final reloaded = await container.read(
      votingSessionProvider(kRoundId).future,
    );
    expect(reloaded.accountUuid, 'account-2');
    expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);
  });

  test(
    'spent nullifier rejection resumes when its tx already landed',
    () async {
      final responses = votingHttpResponses();
      responses['/shielded-vote/v1/cast-vote'] = {
        'tx_hash': 'vote-tx',
        'code': 1,
        'log': 'nullifier already spent: abc123',
      };
      final http = FakeVotingHttpClient(responses: responses);
      final rust = FakeVotingRustApi(emitCommitments: true);
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: _singleVoteRecoveryApi(),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(draftVotes: _singleProposalDrafts());
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.done);
      expect(state.error, isNull);
      expect(rust.storedVoteTxHashes, ['0:7:vote-tx']);
    },
  );

  test(
    'vote submission progress displays questions while bundle work advances',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
      final initialRoundPlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        allDecided: false,
      );
      final completedRoundPlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        allDecided: true,
        completedVoteArtifact: true,
      );
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
        roundPlanSequence: [
          initialRoundPlan,
          initialRoundPlan,
          completedRoundPlan,
        ],
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

      expect(state.phase, VotingSessionPhase.done);
      expect(state.voteSubmissionCompletedCount, 2);
      expect(state.voteSubmissionTotalCount, 2);
      expect(state.voteSubmissionProgress, 1);
      expect(rust.voteCommitBundleCalls, [0, 1, 0, 1]);

      final activeProgressCounts = observed
          .where((state) => state.voteSubmissionTotalCount == 2)
          .map((state) => state.voteSubmissionCompletedCount)
          .toSet();
      expect(activeProgressCounts, containsAll(<int>{0, 1, 2}));
      final progressValues = observed
          .where((state) => state.voteSubmissionTotalCount == 2)
          .map((state) => state.voteSubmissionProgress)
          .whereType<double>()
          .toList();
      expect(progressValues.first, greaterThanOrEqualTo(0));
      expect(progressValues.last, 1);
      expect(progressValues.any((value) => value > 0 && value < 1), isTrue);
      for (var index = 1; index < progressValues.length; index++) {
        expect(
          progressValues[index],
          greaterThanOrEqualTo(progressValues[index - 1]),
        );
      }

      expect(
        observed.where(
          (state) =>
              state.phase == VotingSessionPhase.done &&
              state.voteSubmissionCompletedCount == 2 &&
              state.voteSubmissionProgress == 1,
        ),
        isNotEmpty,
      );
    },
  );

  test('proposal wave proves at most three bundles concurrently', () async {
    final proofGate = Completer<void>();
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      bundleCount: 4,
      voteCommitmentGate: proofGate,
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 4,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 4; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 4; bundleIndex++)
            vote(bundleIndex: bundleIndex, proposalId: 7),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final cast = container
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
    while (rust.voteCommitBundleCalls.length < 3 ||
        (container
                    .read(votingSessionProvider(kRoundId))
                    .value
                    ?.voteProgress
                    .length ??
                0) <
            3) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(rust.voteCommitBundleCalls, [0, 1, 2]);
    expect(rust.maxConcurrentVoteCommitments, 3);
    expect(rust.syncedVoteTrees, [kRoundId]);
    expect(
      container.read(votingSessionProvider(kRoundId)).value!.voteProgress.keys,
      {
        const VotingVoteKey(bundleIndex: 0, proposalId: 7),
        const VotingVoteKey(bundleIndex: 1, proposalId: 7),
        const VotingVoteKey(bundleIndex: 2, proposalId: 7),
      },
    );

    proofGate.complete();
    await cast;

    expect(rust.voteCommitBundleCalls, [0, 1, 2, 3]);
    expect(rust.maxConcurrentVoteCommitments, 3);
  });

  test(
    'proposal wave preserves successful bundles after proof failure',
    () async {
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        bundleCount: 3,
        voteCommitmentErrorsByKey: {
          '1:7': StateError('injected vote proof failure'),
        },
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 3,
          delegationTxHashes: [
            for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
              rust_frb_types.DelegationRecoveryView(
                bundleIndex: bundleIndex,
                phase: VotingWorkflowPhase.submittedDelegation,
                txHash: 'delegation-$bundleIndex',
                vanLeafPosition: null,
              ),
          ],
          votes: [
            for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
              vote(bundleIndex: bundleIndex, proposalId: 7),
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

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('vote proof failure'));
      expect(rust.storedVoteTxHashes, ['0:7:vote-tx', '2:7:vote-tx']);
      expect(rust.resetVotingSessionStateCalls, isEmpty);
    },
  );

  test('proposal wave settles every confirmation persistence result', () async {
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      bundleCount: 3,
      failingVoteConfirmationKeys: const {'1:7'},
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 3,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
            vote(bundleIndex: bundleIndex, proposalId: 7),
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

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('confirmation persistence failure'));
    expect(
      rust.storedVanPositions.any((value) => value.startsWith('0:')),
      isTrue,
    );
    expect(
      rust.storedVanPositions.any((value) => value.startsWith('1:')),
      isFalse,
    );
    expect(
      rust.storedVanPositions.any((value) => value.startsWith('2:')),
      isTrue,
    );
    expect(recoveryApi.roundPlanProposalIds.length, greaterThan(1));
  });

  test(
    'proposal wave submits ready bundle shares while another confirms',
    () async {
      final confirmationResponse =
          votingHttpResponses()['/shielded-vote/v1/tx/vote-tx']!;
      final http = _GatedVoteConfirmationHttpClient(
        responses: {
          ...votingHttpResponses(),
          '/shielded-vote/v1/tx/vote-tx-0': confirmationResponse,
          '/shielded-vote/v1/tx/vote-tx-1': confirmationResponse,
        },
      );
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 2,
          delegationTxHashes: [
            for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++)
              rust_frb_types.DelegationRecoveryView(
                bundleIndex: bundleIndex,
                phase: VotingWorkflowPhase.submittedDelegation,
                txHash: 'delegation-$bundleIndex',
                vanLeafPosition: null,
              ),
          ],
          votes: [
            for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++)
              vote(bundleIndex: bundleIndex, proposalId: 7),
          ],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);
      addTearDown(() {
        if (!http.releaseSlowConfirmation.isCompleted) {
          http.releaseSlowConfirmation.complete();
        }
      });

      await container.read(votingSessionProvider(kRoundId).future);
      final cast = container
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

      await http.slowConfirmationStarted.future;
      for (var attempt = 0; attempt < 100; attempt++) {
        if (rust.recordedShares.any((share) => share.bundleIndex == 1)) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        rust.recordedShares.any((share) => share.bundleIndex == 1),
        isTrue,
      );
      expect(
        rust.recordedShares.any((share) => share.bundleIndex == 0),
        isFalse,
      );
      expect(rust.operationLog, contains('mark_vote_confirmed:1:7'));

      http.releaseSlowConfirmation.complete();
      await cast;

      expect(rust.recordedShares.map((share) => share.bundleIndex).toSet(), {
        0,
        1,
      });
    },
  );

  test(
    'proposal wave polls later bundles while the share pool is saturated',
    () async {
      final confirmationResponse =
          votingHttpResponses()['/shielded-vote/v1/tx/vote-tx']!;
      final http = _SeparatedVoteStagePoolsHttpClient(
        responses: {
          ...votingHttpResponses(),
          for (var bundleIndex = 0; bundleIndex < 4; bundleIndex++)
            '/shielded-vote/v1/tx/vote-tx-$bundleIndex': confirmationResponse,
        },
      );
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 4);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 4,
          delegationTxHashes: [
            for (var bundleIndex = 0; bundleIndex < 4; bundleIndex++)
              rust_frb_types.DelegationRecoveryView(
                bundleIndex: bundleIndex,
                phase: VotingWorkflowPhase.submittedDelegation,
                txHash: 'delegation-$bundleIndex',
                vanLeafPosition: null,
              ),
          ],
          votes: [
            for (var bundleIndex = 0; bundleIndex < 4; bundleIndex++)
              vote(bundleIndex: bundleIndex, proposalId: 7),
          ],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);
      addTearDown(http.releaseShares);

      await container.read(votingSessionProvider(kRoundId).future);
      final cast = container
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

      await http.firstThreeSharesStarted.future;
      await http.fourthConfirmationStarted.future.timeout(
        const Duration(seconds: 1),
      );
      const fourthKey = VotingVoteKey(bundleIndex: 3, proposalId: 7);
      for (var attempt = 0; attempt < 100; attempt++) {
        final fourthProgress = container
            .read(votingSessionProvider(kRoundId))
            .value
            ?.voteProgress[fourthKey];
        if (fourthProgress?.phase == 'confirmed') break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(http.sharePostCount, 3);
      expect(http.maxConcurrentSharePosts, 3);
      final saturatedState = container
          .read(votingSessionProvider(kRoundId))
          .value!;
      expect(saturatedState.voteProgress[fourthKey]?.phase, 'confirmed');
      expect(saturatedState.voteSubmissionProgress, closeTo(0.95, 0.001));
      for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++) {
        final key = VotingVoteKey(bundleIndex: bundleIndex, proposalId: 7);
        expect(
          saturatedState.voteProgress[key]?.phase,
          'submitting_shares',
          reason: 'bundle $bundleIndex must remain visibly in flight',
        );
      }

      http.releaseShares();
      await cast;

      expect(http.sharePostCount, 4);
      expect(http.maxConcurrentSharePosts, 3);
      expect(rust.recordedShares.map((share) => share.bundleIndex).toSet(), {
        0,
        1,
        2,
        3,
      });
    },
  );

  test(
    'proposal wave serializes broadcasts and overlaps confirmations',
    () async {
      final http = _DelegationConcurrencyHttpClient(
        responses: votingHttpResponses(),
      );
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 3);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 3,
          delegationTxHashes: [
            for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
              rust_frb_types.DelegationRecoveryView(
                bundleIndex: bundleIndex,
                phase: VotingWorkflowPhase.submittedDelegation,
                txHash: 'delegation-$bundleIndex',
                vanLeafPosition: null,
              ),
          ],
          votes: [
            for (var bundleIndex = 0; bundleIndex < 3; bundleIndex++)
              vote(bundleIndex: bundleIndex, proposalId: 7),
          ],
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

      expect(http.maxConcurrentVotePosts, 1);
      expect(http.maxConcurrentConfirmationGets, 3);
    },
  );

  test('each bundle confirms a proposal before proving the next one', () async {
    final confirmationResponse =
        votingHttpResponses()['/shielded-vote/v1/tx/vote-tx']!;
    final http = _UniqueVoteTxHttpClient(
      responses: {
        ...votingHttpResponses(),
        for (var index = 0; index < 4; index++)
          '/shielded-vote/v1/tx/vote-tx-$index': confirmationResponse,
      },
    );
    final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++) ...[
            vote(bundleIndex: bundleIndex, proposalId: 7),
            vote(bundleIndex: bundleIndex, proposalId: 8),
          ],
        ],
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
        .castVotes(draftVotes: _twoProposalDrafts());

    // The fake rejects a vote proved against an already-spent vote authority
    // note, so reaching four submissions is itself the ordering proof.
    expect(
      rust.operationLog
          .where((entry) => entry.startsWith('mark_vote_submitted:'))
          .toSet(),
      {
        'mark_vote_submitted:0:7',
        'mark_vote_submitted:1:7',
        'mark_vote_submitted:0:8',
        'mark_vote_submitted:1:8',
      },
    );
    for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++) {
      expect(
        rust.operationLog.indexOf('build_vote:$bundleIndex:8'),
        greaterThan(
          rust.operationLog.indexOf('mark_vote_confirmed:$bundleIndex:7'),
        ),
        reason:
            'bundle $bundleIndex must confirm proposal 7 before proving '
            'proposal 8 — the confirmation is what advances its VAN',
      );
    }
    // At least one sync per proposal step, and never more than one per
    // (bundle, proposal) pair. How many of the four collapse depends on
    // whether the bundles reach a step together; the deterministic
    // coalescing case is pinned by the 4-bundle single-proposal test.
    expect(rust.syncedVoteTrees.length, greaterThanOrEqualTo(2));
    expect(rust.syncedVoteTrees.length, lessThanOrEqualTo(4));
    expect(rust.maxConcurrentVoteTreeSyncs, 1);
    expect(rust.syncedVoteTrees.toSet(), {kRoundId});
  });

  test('vote tree failover waits for prior sync witnesses', () async {
    final rust = _WitnessHandoffVotingRustApi();
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(
        dynamicConfig: dynamicConfigJson(
          voteServers: const [
            {'url': 'https://voting.example', 'label': 'primary'},
            {'url': 'https://voting-failover.example', 'label': 'failover'},
          ],
        ),
      ),
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++) ...[
            vote(bundleIndex: bundleIndex, proposalId: 7),
            vote(bundleIndex: bundleIndex, proposalId: 8),
          ],
        ],
      ),
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);
    addTearDown(rust.releaseFirstWitness);

    await container.read(votingSessionProvider(kRoundId).future);
    final cast = container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _twoProposalDrafts());

    await rust.firstWitnessStarted.future;
    for (var attempt = 0; attempt < 100; attempt++) {
      if (rust.operationLog.contains('mark_vote_confirmed:1:7')) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(rust.operationLog, contains('mark_vote_confirmed:1:7'));

    // Bundle 1 has requested its next fresh sync, but bundle 0 is still using
    // the tree produced by the first sync. Starting failover now would clear
    // bundle 0's witness source before it can materialize the witness.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rust.syncedVoteTreeNodeUrls, ['https://voting.example']);
    expect(rust.resetVoteTreeCalls, isEmpty);

    rust.releaseFirstWitness();
    await cast;

    expect(
      rust.syncedVoteTreeNodeUrls,
      containsAllInOrder([
        'https://voting.example',
        'https://voting.example',
        'https://voting-failover.example',
      ]),
    );
    expect(rust.resetVoteTreeCalls, ['account-1:$kRoundId']);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
    expect(
      rust.operationLog
          .where((entry) => entry.startsWith('mark_vote_submitted:'))
          .toSet(),
      {
        'mark_vote_submitted:0:7',
        'mark_vote_submitted:1:7',
        'mark_vote_submitted:0:8',
        'mark_vote_submitted:1:8',
      },
    );
  });

  test('a slow bundle does not hold back the other bundles', () async {
    final confirmationResponse =
        votingHttpResponses()['/shielded-vote/v1/tx/vote-tx']!;
    final http = _GatedVoteConfirmationHttpClient(
      responses: {
        ...votingHttpResponses(),
        for (var index = 0; index < 4; index++)
          '/shielded-vote/v1/tx/vote-tx-$index': confirmationResponse,
      },
    );
    final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++) ...[
            vote(bundleIndex: bundleIndex, proposalId: 7),
            vote(bundleIndex: bundleIndex, proposalId: 8),
          ],
        ],
      ),
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (!http.releaseSlowConfirmation.isCompleted) {
        http.releaseSlowConfirmation.complete();
      }
    });

    await container.read(votingSessionProvider(kRoundId).future);
    final cast = container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _twoProposalDrafts());

    // `vote-tx-0` is the first broadcast, and its confirmation is held open.
    await http.slowConfirmationStarted.future;
    final gatedEntry = rust.storedVoteTxHashes.firstWhere(
      (entry) => entry.endsWith(':vote-tx-0'),
    );
    final gatedBundle = int.parse(gatedEntry.split(':').first);
    final freeBundle = gatedBundle == 0 ? 1 : 0;

    // The unblocked bundle must reach its second proposal while the gated one
    // is still waiting on its first confirmation.
    for (var attempt = 0; attempt < 200; attempt++) {
      if (rust.operationLog.contains('build_vote:$freeBundle:8')) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      rust.operationLog,
      contains('build_vote:$freeBundle:8'),
      reason: 'bundle $freeBundle must not wait on bundle $gatedBundle',
    );
    expect(rust.operationLog, isNot(contains('build_vote:$gatedBundle:8')));

    http.releaseSlowConfirmation.complete();
    await cast;

    expect(
      rust.operationLog
          .where((entry) => entry.startsWith('mark_vote_confirmed:'))
          .toSet(),
      {
        'mark_vote_confirmed:0:7',
        'mark_vote_confirmed:1:7',
        'mark_vote_confirmed:0:8',
        'mark_vote_confirmed:1:8',
      },
    );
  });

  test(
    'fake rejects a second vote proved against an already-spent VAN',
    () async {
      // Pins the regression guard itself: if this stops throwing, the
      // "each bundle confirms before proving the next" test above silently
      // stops proving anything.
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 1);
      const dbPath = 'db';
      const account = 'account-1';

      final anchorHeight = await rust.syncVoteTree(
        dbPath: dbPath,
        accountUuid: account,
        roundId: kRoundId,
        nodeUrl: 'https://voting.example',
      );
      final witness = await rust.generateVanWitness(
        dbPath: dbPath,
        accountUuid: account,
        roundId: kRoundId,
        bundleIndex: 0,
        anchorHeight: anchorHeight,
      );

      // Prove both proposals against the same VAN state — the shape the
      // round-wide pipeline produced.
      for (final proposalId in [7, 8]) {
        await rust
            .buildVoteCommitmentsWithProgress(
              dbPath: dbPath,
              accountUuid: account,
              network: 'main',
              roundId: kRoundId,
              bundleIndex: 0,
              storedHotkeySecret: const [42, 43, 44],
              vanWitness: witness,
              draftVotes: [
                rust_wire.DraftVote(
                  proposalId: proposalId,
                  choice: 0,
                  numOptions: 2,
                  vcTreePosition: BigInt.zero,
                  singleShare: false,
                ),
              ],
            )
            .drain<void>();
      }

      await rust.markVoteSubmitted(
        dbPath: dbPath,
        accountUuid: account,
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        txHash: 'vote-tx-0',
      );
      await expectLater(
        rust.markVoteSubmitted(
          dbPath: dbPath,
          accountUuid: account,
          roundId: kRoundId,
          bundleIndex: 0,
          proposalId: 8,
          txHash: 'vote-tx-1',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('duplicate van_nullifier'),
          ),
        ),
      );
    },
  );

  test('a failed bundle chain stops at that bundle only', () async {
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      bundleCount: 2,
      voteCommitmentErrorsByKey: {
        '0:7': StateError('injected earlier proposal proof failure'),
      },
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++)
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: bundleIndex,
              phase: VotingWorkflowPhase.submittedDelegation,
              txHash: 'delegation-$bundleIndex',
              vanLeafPosition: null,
            ),
        ],
        votes: [
          for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++) ...[
            vote(bundleIndex: bundleIndex, proposalId: 7),
            vote(bundleIndex: bundleIndex, proposalId: 8),
          ],
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _twoProposalDrafts());

    // Bundle 1 runs to completion; bundle 0 stops at the failed step because
    // proposal 8 cannot be proved without proposal 7's VAN advance.
    expect(
      rust.operationLog,
      containsAll(['mark_vote_submitted:1:7', 'mark_vote_submitted:1:8']),
    );
    expect(rust.operationLog, isNot(contains('mark_vote_submitted:0:7')));
    expect(rust.operationLog, isNot(contains('build_vote:0:8')));
    final message = container
        .read(votingSessionProvider(kRoundId))
        .value!
        .error!
        .message;
    expect(message, contains('earlier proposal proof failure'));
    expect(
      message,
      contains('proposal 7'),
      reason: 'failures must name the proposal, not just the bundle',
    );
  });

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
      expect(rust.operationLog.take(7).toList(), [
        'recover_vote:1:7',
        'prepare_share_delivery:1:7',
        'mark_vote_submitted:1:7',
        'mark_vote_confirmed:1:7',
        'submit_prepared_shares:1:7',
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
      ambiguousUrls: const [],
      targetCount: 1,
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
        immediateShareKey: const rust_share_policy.ImmediateShareKey(
          bundleIndex: 1,
          proposalId: 7,
          shareIndex: 0,
        ),
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
    // Dart supplies only the complete round roster; the SDK derives any
    // immediate share from its durable ballot intent and bundle state.
    expect(rust.planImmediateShareIndexes, [null, null, null]);
    expect(rust.operationLog.take(5).toList(), [
      'recover_vote:1:7',
      'prepare_share_delivery:1:7',
      'submit_prepared_shares:1:7',
      'record_share:1:7:1',
      'build_vote:0:8',
    ]);
  });

  test(
    'recovery maps immediate share zero to a reordered subset position',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rust = FakeVotingRustApi(
        commitmentShareCount: 3,
        recoveredShareOrder: const [2, 0],
      );
      final recoveryApi = FakeVotingRecoveryApi(
        roundPlan: apiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          nextSteps: const [
            rust_wire.NextStepView(
              kind: 'submit_shares',
              bundleIndex: 0,
              proposalId: 7,
              shareIndex: 2,
              choice: 0,
            ),
            rust_wire.NextStepView(
              kind: 'submit_shares',
              bundleIndex: 0,
              proposalId: 7,
              shareIndex: 0,
              choice: 0,
            ),
          ],
          openProposals: Uint32List(0),
          immediateShareKey: const rust_share_policy.ImmediateShareKey(
            bundleIndex: 0,
            proposalId: 7,
            shareIndex: 0,
          ),
          allDecided: true,
        ),
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
          commitmentBundles: [
            rust_frb_types.RecoverableCommitmentBundle(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(55),
            ),
          ],
        ),
      );
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            ceremonyStart: nowSeconds - 100,
            voteEnd: nowSeconds + 1000,
          ),
        ),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        http: http,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(draftVotes: const []);

      expect(rust.planImmediateShareIndexes, [null]);
      final recoveredShares = rust.recordedShares.where(
        (share) => share.bundleIndex == 0 && share.proposalId == 7,
      );
      expect(
        recoveredShares.map((share) => share.shareIndex),
        unorderedEquals([0, 2]),
      );
      expect(
        recoveredShares.singleWhere((share) => share.shareIndex == 0).submitAt,
        greaterThan(BigInt.zero),
      );
      expect(
        recoveredShares.singleWhere((share) => share.shareIndex == 2).submitAt,
        greaterThan(BigInt.zero),
      );
    },
  );

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
      expect(rust.operationLog.take(7).toList(), [
        'mark_vote_confirmed:1:7',
        'recover_vote:1:7',
        'prepare_share_delivery:1:7',
        'submit_prepared_shares:1:7',
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
      hotkeyStore: const FailingVotingHotkeyStore(),
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
    'submitted vote recovery ignores a successful stale confirmation response',
    () async {
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = previousDebugPrint);

      final responses = votingHttpResponses();
      responses['/shielded-vote/v1/tx/submitted-vote-tx'] =
          responses['/shielded-vote/v1/tx/vote-tx']!;
      final http = _GatedSubmittedVoteConfirmationHttpClient(
        responses: responses,
      );
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
      final activeAccountProvider =
          NotifierProvider<_ActiveVotingAccountNotifier, String?>(
            _ActiveVotingAccountNotifier.new,
          );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
        hotkeyStore: const FailingVotingHotkeyStore(),
        activeAccountUuidListenable: activeAccountProvider,
        txConfirmationPolling: const VotingTxConfirmationPolling(
          attempts: 2,
          delay: Duration.zero,
        ),
      );
      final subscription = container.listen(
        votingSessionProvider(kRoundId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);
      addTearDown(() {
        if (!http.releaseConfirmation.isCompleted) {
          http.releaseConfirmation.complete();
        }
      });

      await container.read(votingSessionProvider(kRoundId).future);
      final casting = container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(draftVotes: const []);
      await http.confirmationStarted.future;

      container.read(activeAccountProvider.notifier).set('account-2');
      final switched = await container.read(
        votingSessionProvider(kRoundId).future,
      );
      expect(switched.accountUuid, 'account-2');

      http.releaseConfirmation.complete();
      await casting;

      expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);
      expect(
        container.read(votingSessionProvider(kRoundId)).value!.accountUuid,
        'account-2',
      );
      expect(
        logs.any((line) => line.contains('session action failed')),
        isFalse,
        reason:
            'stale recovery poll must rethrow _StaleVotingSessionAction, '
            'not wrap it in _VoteWaveBatchException',
      );
      expect(
        logs.any(
          (line) =>
              line.contains('ignored stale session update') &&
              line.contains('reason=action'),
        ),
        isTrue,
      );
      expect(rust.operationLog, isNot(contains('mark_vote_confirmed:0:7')));
    },
  );

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

  test('vote tree pre-sync retries failover servers', () async {
    final rust = FakeVotingRustApi(
      failingVoteTreeNodeUrls: const {'https://voting.example'},
    );
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(
        dynamicConfig: dynamicConfigJson(
          voteServers: const [
            {'url': 'https://voting.example', 'label': 'primary'},
            {'url': 'https://voting-failover.example', 'label': 'failover'},
          ],
        ),
      ),
    );
    final container = _sessionContainer(http: http, rust: rust);
    addTearDown(container.dispose);

    final service = container.read(votingTreePreSyncProvider);
    await service.preSyncRound(kRoundId);

    expect(rust.syncedVoteTreeNodeUrls, [
      'https://voting.example',
      'https://voting-failover.example',
    ]);
    expect(rust.resetVoteTreeCalls, ['account-1:$kRoundId']);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
  });

  test('vote tree sync runs before each proposal', () async {
    final rust = FakeVotingRustApi(emitCommitments: true);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _twoProposalDrafts());

    // A bundle's second vote needs the VAN leaf its first vote created, and
    // that leaf is only witnessable after another sync.
    expect(rust.syncedVoteTrees, [kRoundId, kRoundId]);
    expect(rust.voteCommitBundleCalls, [0, 0]);
  });

  test('cast-time vote tree sync retries failover servers', () async {
    final rust = FakeVotingRustApi(
      failingVoteTreeNodeUrls: const {'https://voting.example'},
    );
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(
        dynamicConfig: dynamicConfigJson(
          voteServers: const [
            {'url': 'https://voting.example', 'label': 'primary'},
            {'url': 'https://voting-failover.example', 'label': 'failover'},
          ],
        ),
      ),
    );
    final container = _sessionContainer(http: http, rust: rust);
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

    expect(rust.syncedVoteTreeNodeUrls, [
      'https://voting.example',
      'https://voting-failover.example',
    ]);
    expect(rust.resetVoteTreeCalls, ['account-1:$kRoundId']);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
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

  test(
    'final ballot plan sends only its designated share immediately',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        commitmentShareCount: 3,
      );
      final initialPlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List.fromList(const [7]),
        allDecided: false,
      );
      final finalPlan = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        immediateShareKey: const rust_share_policy.ImmediateShareKey(
          bundleIndex: 0,
          proposalId: 7,
          shareIndex: 0,
        ),
        allDecided: true,
      );
      final recoveryApi = FakeVotingRecoveryApi(
        roundPlanSequence: [initialPlan, finalPlan],
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
        http: FakeVotingHttpClient(
          responses: votingHttpResponses(
            roundStatus: roundStatusJson(
              roundId: kRoundId,
              ceremonyStart: nowSeconds - 100,
              voteEnd: nowSeconds + 903,
            ),
          ),
        ),
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: _singleProposalDrafts(),
            allProposalIds: const [7],
          );

      expect(rust.planImmediateShareIndexes, [null]);
      final sharesByIndex = {
        for (final share in rust.recordedShares) share.shareIndex: share,
      };
      expect(sharesByIndex[0]!.submitAt, greaterThan(BigInt.zero));
      expect(sharesByIndex[1]!.submitAt, greaterThan(BigInt.zero));
      expect(sharesByIndex[2]!.submitAt, greaterThan(BigInt.zero));
    },
  );

  test('recovery keeps immediate share identity outside its subset', () async {
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      commitmentShareCount: 2,
      recoveredShareOrder: const [1],
    );
    final recoveryApi = FakeVotingRecoveryApi(
      roundPlan: apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'submit_shares',
            bundleIndex: 0,
            proposalId: 7,
            shareIndex: 1,
            choice: 1,
          ),
        ],
        openProposals: Uint32List(0),
        immediateShareKey: const rust_share_policy.ImmediateShareKey(
          bundleIndex: 0,
          proposalId: 7,
          shareIndex: 0,
        ),
        allDecided: true,
      ),
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
        commitmentBundles: [
          rust_frb_types.RecoverableCommitmentBundle(
            bundleIndex: 0,
            proposalId: 7,
            commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
            vcTreePosition: BigInt.from(2),
          ),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: const []);

    expect(rust.planImmediateShareIndexes, [null]);
    expect(rust.recordedShares.single.shareIndex, 1);
    expect(
      rust.operationLog.where(
        (entry) =>
            entry == 'prepare_share_delivery:0:7' ||
            entry == 'submit_prepared_shares:0:7',
      ),
      ['prepare_share_delivery:0:7', 'submit_prepared_shares:0:7'],
    );
  });

  test(
    'vote commitment submits shares concurrently and persists completions',
    () async {
      final http = _GatedSharePostVotingHttpClient(
        expectedShareCount: 3,
        gatedShareIndexes: const {2},
        responses: votingHttpResponses(),
      );
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        commitmentShareCount: 3,
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
      final cast = container
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

      await http.allSharePostsStarted.future.timeout(
        const Duration(seconds: 1),
      );
      expect(http.startedShareIndexes, {0, 1, 2});
      expect(rust.helperDeliveryContexts, hasLength(1));
      expect(rust.preflightDeliveryContexts, [
        same(rust.helperDeliveryContexts.single),
      ]);
      expect(rust.initialDeliveryContexts, hasLength(1));
      expect(
        rust.initialDeliveryContexts,
        everyElement(same(rust.helperDeliveryContexts.single)),
      );
      expect(rust.submittedSharePlans, hasLength(3));
      for (var index = 0; index < rust.submittedSharePlans.length; index++) {
        expect(
          rust.submittedSharePlans[index],
          same(rust.plannedSharePlans[index]),
        );
      }
      expect(
        rust.operationLog.indexOf('prepare_share_delivery:0:7'),
        lessThan(rust.operationLog.indexOf('mark_vote_submitted:0:7')),
      );
      expect(
        rust.operationLog.indexOf('mark_vote_confirmed:0:7'),
        lessThan(rust.operationLog.indexOf('submit_prepared_shares:0:7')),
      );
      await _waitForRecordedShareCount(rust, 2);
      expect(rust.recordedShares.map((share) => share.shareIndex).toSet(), {
        0,
        1,
      });

      http.releaseSharePosts.complete();
      await cast;

      expect(rust.recordedShares, hasLength(3));
      expect(
        rust.recordedShares.map((share) => share.shareIndex),
        unorderedEquals([0, 1, 2]),
      );
      expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
    },
  );

  test('helper preflight settles before vote proof work starts', () async {
    final preflightGate = Completer<void>();
    addTearDown(() {
      if (!preflightGate.isCompleted) preflightGate.complete();
    });
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      helperPreflightGate: preflightGate,
    );
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: _singleVoteRecoveryApi(),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final cast = container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _singleProposalDrafts());

    await rust.helperPreflightStarted.future.timeout(
      const Duration(seconds: 1),
    );
    expect(rust.voteCommitmentStarted.isCompleted, isFalse);

    preflightGate.complete();
    await cast;

    expect(rust.voteCommitmentStarted.isCompleted, isTrue);
  });

  test('helper planning failure prevents vote broadcast', () async {
    final http = FakeVotingHttpClient(responses: votingHttpResponses());
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      prepareCommittedShareDeliveryError: StateError('planning failed'),
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: _singleVoteRecoveryApi(),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _singleProposalDrafts());

    expect(
      http.requests.where(
        (request) =>
            request.method == 'POST' && request.uri.path.endsWith('/cast-vote'),
      ),
      isEmpty,
    );
    expect(rust.storedVoteTxHashes, isEmpty);
    expect(rust.submittedSharePlans, isEmpty);
    final state = container.read(votingSessionProvider(kRoundId)).value!;
    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('helper-share planning'));
  });

  test('helper fan-out honors the shared concurrent post cap', () async {
    final http = _GatedSharePostVotingHttpClient(
      expectedShareCount: 2,
      gatedShareIndexes: const {0, 1, 2},
      responses: votingHttpResponses(),
    );
    addTearDown(() {
      if (!http.releaseSharePosts.isCompleted) {
        http.releaseSharePosts.complete();
      }
    });
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      commitmentShareCount: 3,
      maxConcurrentHelperPosts: 2,
    );
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: _singleVoteRecoveryApi(),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final cast = container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _singleProposalDrafts());

    await http.allSharePostsStarted.future.timeout(const Duration(seconds: 1));
    expect(http.startedShareIndexes, hasLength(2));
    expect(http.maxConcurrentSharePostCount, 2);

    http.releaseSharePosts.complete();
    await cast;

    expect(http.startedShareIndexes, {0, 1, 2});
    expect(http.maxConcurrentSharePostCount, 2);
  });

  test('helper traffic uses the regtest endpoint mapping', () async {
    const logicalHelper = 'https://helper-a.vizor-vote.invalid';
    const mappedHelper =
        'http://127.0.0.1:18080/gateway/helper-a.vizor-vote.invalid';
    final http = FakeVotingHttpClient(
      responses:
          votingHttpResponses(
            dynamicConfig: dynamicConfigJson(
              voteServers: const [
                {'url': logicalHelper, 'label': 'helper-a'},
              ],
            ),
          )..addAll({
            '$mappedHelper/shielded-vote/v1/status': {'status': 'ok'},
            '$mappedHelper/shielded-vote/v1/shares': {'status': 'queued'},
          }),
    );
    final rust = FakeVotingRustApi(emitCommitments: true);
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: _singleVoteRecoveryApi(),
      extraOverrides: [
        votingEndpointMapperProvider.overrideWithValue(
          VotingEndpointMapper(
            isRegtest: true,
            gatewayUrl: 'http://127.0.0.1:18080/gateway',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: _singleProposalDrafts());

    expect(rust.preflightConfiguredHelperUrls, [
      [mappedHelper],
    ]);
    expect(
      http.requests
          .where((request) => request.uri.path.endsWith('/shares'))
          .map((request) => request.uri.toString()),
      contains('$mappedHelper/shielded-vote/v1/shares'),
    );
  });

  test('vote commitment validates all shares before submission', () async {
    final http = FakeVotingHttpClient(responses: votingHttpResponses());
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      commitmentShareCount: 3,
      failingVoteShareWireIndexes: const {2},
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
    expect(sharePosts, isEmpty);
    expect(rust.recordedShares, isEmpty);
    final state = container.read(votingSessionProvider(kRoundId)).value!;
    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('invalid vote share 2'));
  });

  test(
    'vote commitment persists sibling shares after one persistence failure',
    () async {
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        commitmentShareCount: 3,
        failingRecordShareIndexes: const {1},
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

      expect(rust.recordShareAttempts, unorderedEquals([0, 1, 2]));
      expect(
        rust.recordedShares.map((share) => share.shareIndex),
        unorderedEquals([0, 2]),
      );
      final state = container.read(votingSessionProvider(kRoundId)).value!;
      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('share persistence failed 1'));
    },
  );

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

  test('initial shares replace an unavailable helper', () async {
    final helperUrls = [
      for (var i = 1; i <= 6; i++)
        {'url': 'https://helper-$i.example', 'label': 'helper-$i'},
    ];
    final http = _GatedVotingHttpClient(
      responses: {
        ...votingHttpResponses(
          dynamicConfig: dynamicConfigJson(voteServers: helperUrls),
        ),
        'https://helper-1.example/shielded-vote/v1/status': jsonResponse({
          'error': 'unavailable',
        }, statusCode: 503),
      },
    );
    const confirmationPath = '/shielded-vote/v1/tx/vote-tx';
    const statusPath = '/shielded-vote/v1/status';
    final confirmationGate = http.gateNextGet(confirmationPath);
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
    addTearDown(() {
      if (!confirmationGate.isCompleted) confirmationGate.complete();
    });

    await container.read(votingSessionProvider(kRoundId).future);
    final submission = container
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
    await http
        .waitForGetCount(confirmationPath, 1)
        .timeout(const Duration(seconds: 1));
    await http
        .waitForGetCount(statusPath, helperUrls.length)
        .timeout(const Duration(seconds: 1));

    expect(confirmationGate.isCompleted, isFalse);
    confirmationGate.complete();
    await submission;

    final statusHosts = http.requests
        .where(
          (request) =>
              request.method == 'GET' && request.uri.path == statusPath,
        )
        .map((request) => request.uri.host);
    expect(
      statusHosts,
      unorderedEquals([
        'helper-1.example',
        'helper-2.example',
        'helper-3.example',
        'helper-4.example',
        'helper-5.example',
        'helper-6.example',
      ]),
    );

    final sharePosts = http.requests.where(
      (request) =>
          request.method == 'POST' &&
          request.uri.path == '/shielded-vote/v1/shares',
    );
    expect(sharePosts.map((request) => request.uri.host), [
      'helper-2.example',
      'helper-3.example',
      'helper-4.example',
    ]);
    expect(sharePosts.map((request) => request.timeout).toSet(), {
      const Duration(seconds: 30),
    });
    expect(rust.recordedShares.single.sentToUrls, [
      'https://helper-2.example',
      'https://helper-3.example',
      'https://helper-4.example',
    ]);
    expect(rust.recordedShares.single.ambiguousUrls, isEmpty);
    expect(rust.recordedShares.single.targetCount, 3);
  });

  test(
    'ambiguous-only initial share delivery is persisted for tracking',
    () async {
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        initialShareSubmissionReport: const rust_api.ApiShareSubmissionReport(
          acceptedUrls: [],
          ambiguousUrls: ['https://voting.example'],
          targetCount: 1,
        ),
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
          );

      final recorded = rust.recordedShares.single;
      expect(recorded.sentToUrls, isEmpty);
      expect(recorded.ambiguousUrls, ['https://voting.example']);
      expect(recorded.targetCount, 1);
      expect(container.read(votingSessionProvider(kRoundId)).hasError, isFalse);
    },
  );

  test(
    'initial share delivery fails when no helper outcome was retained',
    () async {
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        initialShareSubmissionReport: const rust_api.ApiShareSubmissionReport(
          acceptedUrls: [],
          ambiguousUrls: [],
          targetCount: 1,
        ),
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
          );

      final state = container.read(votingSessionProvider(kRoundId)).value!;
      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('No helper accepted share'));
      expect(rust.recordedShares, hasLength(1));
      expect(rust.recordedShares.single.sentToUrls, isEmpty);
      expect(rust.recordedShares.single.ambiguousUrls, isEmpty);
      expect(rust.helperDeliveryContexts, hasLength(1));
      expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
    },
  );

  test(
    'share submission schedules submit_at before last-moment buffer',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final voteEnd = nowSeconds + 903;
      final ceremonyStart = nowSeconds - 100;
      final lastMomentBuffer = 402;
      final deadline = voteEnd - lastMomentBuffer;
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            ceremonyStart: ceremonyStart,
            voteEnd: voteEnd,
          ),
        ),
      );
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        commitmentShareCount: 3,
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

      final submitAt = http.requests
          .firstWhere(
            (request) =>
                request.method == 'POST' &&
                request.uri.path == '/shielded-vote/v1/shares',
          )
          .body!['submit_at'];
      expect(submitAt, isA<int>());
      expect(submitAt as int, greaterThanOrEqualTo(nowSeconds));
      expect(submitAt, lessThan(deadline));
      expect(rust.planLastMomentBufferSeconds, [BigInt.from(lastMomentBuffer)]);
      expect(rust.planSingleShareValues, [false]);
      expect(
        rust.recordedShares.map((share) => share.submitAt),
        everyElement(BigInt.from(submitAt)),
      );
    },
  );

  test(
    'share planning maps the round immediate key to its batch position',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            ceremonyStart: nowSeconds - 100,
            voteEnd: nowSeconds + 1000,
          ),
        ),
      );
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        commitmentShareCount: 3,
      );
      final beforeIntent = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List.fromList(const [7]),
        allDecided: false,
      );
      final afterIntent = apiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List.fromList(const [7]),
        immediateShareKey: const rust_share_policy.ImmediateShareKey(
          bundleIndex: 0,
          proposalId: 7,
          shareIndex: 0,
        ),
        allDecided: false,
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
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
        roundPlanSequence: [beforeIntent, beforeIntent, afterIntent],
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

      expect(rust.planImmediateShareIndexes, [null]);
      final submitAtByShare = {
        for (final share in rust.recordedShares)
          share.shareIndex: share.submitAt,
      };
      expect(submitAtByShare[0], greaterThan(BigInt.zero));
      expect(submitAtByShare[1], greaterThan(BigInt.zero));
      expect(submitAtByShare[2], greaterThan(BigInt.zero));
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
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        commitmentShareCount: 2,
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
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
        roundPlan: apiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: false,
          nextSteps: const [],
          openProposals: Uint32List.fromList(const [7]),
          immediateShareKey: const rust_share_policy.ImmediateShareKey(
            bundleIndex: 0,
            proposalId: 7,
            shareIndex: 0,
          ),
          allDecided: false,
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
      expect(rust.planSingleShareValues, [true]);
      expect(rust.planImmediateShareIndexes, [null]);
      expect(
        http.requests
            .where(
              (request) =>
                  request.method == 'POST' &&
                  request.uri.path == '/shielded-vote/v1/shares',
            )
            .map((request) => request.body!['submit_at']),
        everyElement(0),
      );
      expect(
        rust.recordedShares.map((share) => share.submitAt),
        everyElement(BigInt.zero),
      );
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

  test(
    'expired persisted shares stop before config or round requests',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final http = FakeVotingHttpClient();
      final container = _sessionContainer(
        http: http,
        pendingShareRoundLoader:
            ({required dbPath, required accountUuids}) async {
              return [
                rust_api.ApiPendingShareRound(
                  accountUuid: 'account-1',
                  roundId: kRoundId,
                  sessionJson: jsonEncode({'vote_end_time': nowSeconds - 1}),
                ),
              ];
            },
      );
      addTearDown(container.dispose);

      await container.read(votingShareTrackingRestorerProvider).restore();

      expect(http.requests, isEmpty);
    },
  );

  test('active rounds without an end time do not track shares', () {
    final round = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(roundId: kRoundId, includeVoteEnd: false),
      ),
    );

    expect(shouldTrackPendingVotingShares(round), isFalse);
  });

  test('persisted share discovery waits for unlock', () async {
    var loadCount = 0;
    final security = _MutableVotingSecurityNotifier(
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: false),
    );
    final container = _sessionContainer(
      securityNotifier: security,
      pendingShareRoundLoader:
          ({required dbPath, required accountUuids}) async {
            loadCount++;
            return const [];
          },
    );
    addTearDown(container.dispose);

    final restorer = container.read(votingShareTrackingRestorerProvider);
    await restorer.restore();
    expect(loadCount, 0);

    security.setUnlocked(true);
    await pumpEventQueue();

    expect(loadCount, 1);
  });

  test('locking drains discovery and unlocking resumes it', () async {
    var loadCount = 0;
    final loaderStarted = Completer<void>();
    final releaseLoader = Completer<void>();
    final security = _MutableVotingSecurityNotifier(
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true),
    );
    final container = _sessionContainer(
      securityNotifier: security,
      pendingShareRoundLoader:
          ({required dbPath, required accountUuids}) async {
            loadCount++;
            if (loadCount == 1) {
              loaderStarted.complete();
              await releaseLoader.future;
            }
            return const [];
          },
    );
    addTearDown(container.dispose);

    container.read(votingShareTrackingRestorerProvider);
    await loaderStarted.future;

    security.setUnlocked(false);
    final registry = container.read(votingShareTrackingRegistryProvider);
    expect(registry.isQuiesced('account-1'), isTrue);
    expect(registry.beginDiscovery(), isNull);

    releaseLoader.complete();
    security.setUnlocked(true);
    await pumpEventQueue();

    expect(loadCount, 2);
    expect(registry.isQuiesced('account-1'), isFalse);
  });

  test('destructive drain waits for persisted share discovery', () async {
    final loaderStarted = Completer<void>();
    final releaseLoader = Completer<void>();
    final container = _sessionContainer(
      pendingShareRoundLoader:
          ({required dbPath, required accountUuids}) async {
            loaderStarted.complete();
            await releaseLoader.future;
            return const [];
          },
    );
    addTearDown(container.dispose);

    final restorer = container.read(votingShareTrackingRestorerProvider);
    final restore = restorer.restore();
    await loaderStarted.future;

    final registry = container.read(votingShareTrackingRegistryProvider);
    var drained = false;
    final drain = registry
        .quiesceAndDrain(accountUuid: 'account-1')
        .then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);

    expect(drained, isFalse);
    expect(registry.beginDiscovery(), isNull);

    releaseLoader.complete();
    await restore;
    await drain;
    expect(drained, isTrue);
  });

  test('global quiescence remains until every owner resumes', () async {
    final registry = VotingShareTrackingRegistry();

    await registry.quiesceAndDrain();
    await registry.quiesceAndDrain();
    registry.resume();

    expect(registry.isQuiesced('account-1'), isTrue);
    expect(registry.beginDiscovery(), isNull);

    registry.resume();
    expect(registry.isQuiesced('account-1'), isFalse);
    final releaseDiscovery = registry.beginDiscovery();
    expect(releaseDiscovery, isNotNull);
    releaseDiscovery!();
  });

  test('account quiescence remains until every owner resumes', () async {
    final registry = VotingShareTrackingRegistry();

    await registry.quiesceAndDrain(accountUuid: 'account-1');
    await registry.quiesceAndDrain(accountUuid: 'account-1');
    registry.resume(accountUuid: 'account-1');

    expect(registry.isQuiesced('account-1'), isTrue);
    expect(registry.isQuiesced('account-2'), isFalse);
    expect(registry.beginDiscovery(), isNull);

    registry.resume(accountUuid: 'account-1');
    expect(registry.isQuiesced('account-1'), isFalse);
    final releaseDiscovery = registry.beginDiscovery();
    expect(releaseDiscovery, isNotNull);
    releaseDiscovery!();
  });

  test('repeated lifecycle pause acquires one quiescence owner', () async {
    final container = _sessionContainer(
      pendingShareRoundLoader:
          ({required dbPath, required accountUuids}) async => const [],
    );
    addTearDown(container.dispose);

    final restorer = container.read(votingShareTrackingRestorerProvider);
    await restorer.restore();
    final registry = container.read(votingShareTrackingRegistryProvider);

    await Future.wait([restorer.pause(), restorer.pause()]);
    expect(registry.isQuiesced('account-1'), isTrue);

    await Future.wait([restorer.resume(), restorer.resume()]);
    expect(registry.isQuiesced('account-1'), isFalse);
  });

  test('restore request restarts discovery after destructive drain', () async {
    var loadCount = 0;
    final container = _sessionContainer(
      pendingShareRoundLoader:
          ({required dbPath, required accountUuids}) async {
            loadCount++;
            return const [];
          },
    );
    addTearDown(container.dispose);

    final restorer = container.read(votingShareTrackingRestorerProvider);
    await restorer.restore();
    expect(loadCount, 1);

    final registry = container.read(votingShareTrackingRegistryProvider);
    await registry.quiesceAndDrain(accountUuid: 'account-1');
    registry.resume(accountUuid: 'account-1');
    registry.requestRestore();
    await restorer.restore();

    expect(loadCount, 2);
  });

  test('unlock resumes discovery after a tracking drain fails', () async {
    final container = _sessionContainer(
      pendingShareRoundLoader:
          ({required dbPath, required accountUuids}) async => const [],
    );
    addTearDown(container.dispose);

    final restorer = container.read(votingShareTrackingRestorerProvider);
    await restorer.restore();
    final registry = container.read(votingShareTrackingRegistryProvider);
    final owner = Object();
    expect(
      registry.register(
        key: const VotingSessionKey(
          accountUuid: 'account-1',
          roundId: kRoundId,
        ),
        owner: owner,
        stopAndDrain: () async => throw StateError('injected drain failure'),
      ),
      isTrue,
    );

    await restorer.pause();

    expect(registry.isQuiesced('account-1'), isTrue);
    expect(registry.registeredKeys, isEmpty);

    await restorer.resume();

    expect(registry.isQuiesced('account-1'), isFalse);
  });

  test(
    'submission session completes its initial tracking schedule first',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final pendingShare = rust_frb_types.ShareDelegationRecordView(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        ambiguousUrls: const [],
        targetCount: 1,
        nullifier: Uint8List.fromList(List.filled(32, 1)),
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.from(nowSeconds + 100),
        createdAt: BigInt.from(nowSeconds),
      );
      final scheduleGate = Completer<void>();
      final rust = FakeVotingRustApi(nextShareTrackingDelayGate: scheduleGate);
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: FakeVotingRecoveryApi(
          state: recoveryState(
            shareDelegations: [pendingShare],
            unconfirmedShareDelegations: [pendingShare],
          ),
        ),
      );
      addTearDown(container.dispose);
      const key = VotingSessionKey(accountUuid: 'account-1', roundId: kRoundId);

      var loaded = false;
      final load = container
          .read(votingSubmissionSessionProvider(key).future)
          .then((state) {
            loaded = true;
            return state;
          });
      await rust.nextShareTrackingDelayStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(loaded, isFalse);

      scheduleGate.complete();
      await load;

      expect(
        container.read(votingShareTrackingRegistryProvider).registeredKeys,
        {key},
      );
      await container
          .read(votingShareTrackingRegistryProvider)
          .quiesceAndDrain();
    },
  );

  test('destructive drain ignores a completed tracking pass failure', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pendingShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://helper-a.example'],
      ambiguousUrls: const [],
      targetCount: 1,
      nullifier: Uint8List.fromList(List.filled(32, 1)),
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.from(nowSeconds - 100),
    );
    final rust = _GatedFailingShareTrackingRustApi();
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: FakeVotingRecoveryApi(
        state: recoveryState(
          shareDelegations: [pendingShare],
          unconfirmedShareDelegations: [pendingShare],
        ),
      ),
    );
    addTearDown(container.dispose);
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: kRoundId);

    await container.read(votingSubmissionSessionProvider(key).future);
    final pass = container
        .read(votingSubmissionSessionProvider(key).notifier)
        .runShareTrackingPass();
    final passFailure = expectLater(pass, throwsA(isA<StateError>()));
    await rust.started.future;

    final registry = container.read(votingShareTrackingRegistryProvider);
    var drained = false;
    final drain = registry.quiesceAndDrain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);

    rust.release.complete();
    await passFailure;
    await drain;

    expect(drained, isTrue);
    expect(registry.registeredKeys, isEmpty);
    expect(rust.shareTrackingPassHandles, hasLength(1));
    expect(rust.shareTrackingPassHandles.single.isCancelled, isTrue);
    expect(rust.shareTrackingPassHandles.single.isDisposed, isTrue);
    expect(rust.helperDeliveryContexts, hasLength(1));
    expect(rust.helperDeliveryContexts.single.isDisposed, isTrue);
    registry.resume();
  });

  test('restores persisted shares across async session loading', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const unknownRoundId =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    final pendingShare = rust_wire.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://helper-a.example'],
      ambiguousUrls: const [],
      targetCount: 1,
      nullifier: Uint8List.fromList(List.filled(32, 2)),
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.from(nowSeconds - 1000),
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        delegationTxHashes: [
          const rust_wire.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'delegation-0',
            vanLeafPosition: null,
          ),
        ],
        commitmentBundles: [
          rust_wire.RecoverableCommitmentBundle(
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
    final shareId = _hexFromBytes(pendingShare.nullifier);
    final http = _YieldingFakeVotingHttpClient(
      responses:
          votingHttpResponses(
            roundStatus: roundStatusJson(
              roundId: kRoundId,
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
          }),
    );
    final container = _sessionContainer(
      http: http,
      recoveryApi: recoveryApi,
      pendingShareRoundLoader:
          ({required dbPath, required accountUuids}) async {
            return [
              rust_api.ApiPendingShareRound(
                accountUuid: 'account-1',
                roundId: kRoundId,
                sessionJson: jsonEncode({'vote_end_time': nowSeconds + 1000}),
              ),
              rust_api.ApiPendingShareRound(
                accountUuid: 'account-1',
                roundId: kOtherRoundId,
                sessionJson: jsonEncode({'vote_end_time': nowSeconds - 1}),
              ),
              rust_api.ApiPendingShareRound(
                accountUuid: 'account-1',
                roundId: unknownRoundId,
                sessionJson: jsonEncode({'vote_end_time': nowSeconds + 1000}),
              ),
            ];
          },
    );
    addTearDown(container.dispose);

    await container.read(votingShareTrackingRestorerProvider).restore();

    expect(
      http.requests.where(
        (request) =>
            request.method == 'POST' &&
            request.uri.host == 'helper-b.example' &&
            request.uri.path == '/shielded-vote/v1/shares',
      ),
      hasLength(1),
    );
    final roundRequests = http.requests.where(
      (request) => request.uri.path.contains('/shielded-vote/v1/round/'),
    );
    expect(roundRequests, isNotEmpty);
    expect(
      roundRequests.every((request) => request.uri.path.endsWith(kRoundId)),
      isTrue,
    );
    final registry = container.read(votingShareTrackingRegistryProvider);
    expect(registry.registeredKeys, {
      const VotingSessionKey(accountUuid: 'account-1', roundId: kRoundId),
    });

    await registry.quiesceAndDrain();
    expect(registry.registeredKeys, isEmpty);
  });

  test('accepted shares confirm after two helpers corroborate', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shareNullifier = Uint8List.fromList(List.filled(32, 1));
    final shareId = _hexFromBytes(shareNullifier);
    final acceptedShare = rust_frb_types.ShareDelegationRecordView(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const [
        'https://removed-helper.example',
        'https://helper-a.example',
        'https://helper-b.example',
      ],
      ambiguousUrls: const [],
      targetCount: 3,
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
    final http = FakeVotingHttpClient(
      responses:
          votingHttpResponses(
            roundStatus: roundStatusJson(
              roundId: kRoundId,
              voteEnd: nowSeconds + 1000,
            ),
            dynamicConfig: dynamicConfigJson(
              voteServers: const [
                {'url': 'https://helper-a.example', 'label': 'helper-a'},
                {'url': 'https://helper-b.example', 'label': 'helper-b'},
              ],
            ),
          )..addAll({
            'https://removed-helper.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'confirmed'},
            'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'confirmed'},
            'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'confirmed'},
          }),
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
        .runShareTrackingPass();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.done);
    // Confirming durably clears the share, so the refreshed plan no longer
    // lists it as outstanding.
    expect(state.resumePlan?.unconfirmedShareDelegations, isEmpty);
    expect(rust.confirmedShares, ['0:7:0']);
    expect(
      http.requests.where(
        (request) => request.uri.host == 'removed-helper.example',
      ),
      isEmpty,
    );
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
        ambiguousUrls: const [],
        targetCount: 1,
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
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            voteEnd: nowSeconds + 1000,
          ),
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
          .runShareTrackingPass();

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
      ambiguousUrls: const [],
      targetCount: 1,
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
    final rust = FakeVotingRustApi();
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
                {
                  'url': 'https://helper-a.example',
                  'label': 'helper-a-duplicate',
                },
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
    final container = _sessionContainer(
      http: http,
      rust: rust,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .runShareTrackingPass();

    final helperBPost = http.requests.singleWhere(
      (request) =>
          request.method == 'POST' && request.uri.host == 'helper-b.example',
    );
    expect(helperBPost.uri.path, '/shielded-vote/v1/shares');
    // The resubmission body and the randomized helper order are built inside
    // `zcash_voting` and are covered by its own tests.
    expect(
      http.requests.where(
        (request) =>
            request.method == 'POST' && request.uri.host == 'helper-a.example',
      ),
      isEmpty,
    );
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

  test(
    'snapshot bundle precompute needs no hotkey and joins delegation',
    () async {
      final precomputeGate = Completer<void>();
      final rust = FakeVotingRustApi(
        generatedHotkeys: const [
          [42, 43, 44],
          [99, 99, 99],
        ],
        precomputeGate: precomputeGate,
      );
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final container = _sessionContainer(rust: rust, hotkeyStore: hotkeyStore);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final notifier = container.read(votingSessionProvider(kRoundId).notifier);
      await notifier.refreshEligibleWeight();
      final precomputeFuture = notifier.precomputeSnapshotBundles(
        accountUuid: 'account-1',
      );
      await rust.precomputeStarted.future;

      final delegationFuture = notifier.delegatePendingBundles(
        mnemonic: kTestMnemonic,
      );
      await Future<void>.delayed(Duration.zero);

      expect(rust.generateVotingHotkeyCalls, 0);

      precomputeGate.complete();
      await Future.wait([precomputeFuture, delegationFuture]);

      expect(rust.generateVotingHotkeyCalls, 1);
      expect(hotkeyStore.hotkey, [42, 43, 44]);
      expect(rust.snapshotBundlePrecomputeAccounts, ['account-1']);
      expect(rust.delegationStoredHotkeySecrets, [
        [42, 43, 44],
      ]);
    },
  );

  test(
    'snapshot bundle precompute runs without reading a voting hotkey',
    () async {
      final precomputeGate = Completer<void>();
      final rust = FakeVotingRustApi(precomputeGate: precomputeGate);
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final container = _sessionContainer(rust: rust, hotkeyStore: hotkeyStore);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final notifier = container.read(votingSessionProvider(kRoundId).notifier);
      await notifier.refreshEligibleWeight();
      final precomputeFuture = notifier.precomputeSnapshotBundles(
        accountUuid: 'account-1',
      );
      await rust.precomputeStarted.future;

      expect(rust.snapshotBundlePrecomputeAccounts, ['account-1']);
      expect(rust.generateVotingHotkeyCalls, 0);
      expect(hotkeyStore.hotkey, isNull);
      expect(rust.setupCalls, 0);
      expect(rust.warmVotingProvingCachesCalls, greaterThanOrEqualTo(1));

      precomputeGate.complete();
      await precomputeFuture;
      await rust.precomputeFinished.future;
    },
  );

  test('prepareDelegation warms proving caches before bundle setup', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareDelegation();

    expect(rust.warmVotingProvingCachesCalls, greaterThanOrEqualTo(1));
    expect(rust.setupCalls, 1);
  });

  test(
    'snapshot bundle precompute runs for a fresh round without durable bundles',
    () async {
      final rust = FakeVotingRustApi();
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final container = _sessionContainer(
        rust: rust,
        hotkeyStore: hotkeyStore,
        recoveryApi: FakeVotingRecoveryApi(
          state: recoveryState(bundleCount: 0),
        ),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final notifier = container.read(votingSessionProvider(kRoundId).notifier);
      await notifier.refreshEligibleWeight();
      await notifier.precomputeSnapshotBundles(accountUuid: 'account-1');

      expect(rust.setupCalls, 0);
      expect(rust.snapshotBundlePrecomputeAccounts, ['account-1']);
      expect(rust.generateVotingHotkeyCalls, 0);
      expect(hotkeyStore.hotkey, isNull);
    },
  );

  test(
    'snapshot bundle precompute does not regenerate Keystone hotkey',
    () async {
      final rust = FakeVotingRustApi();
      rust.storedKeystoneSignatures[0] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final container = _sessionContainer(
        rust: rust,
        accountIsHardware: true,
        hotkeyStore: hotkeyStore,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final notifier = container.read(votingSessionProvider(kRoundId).notifier);
      await notifier.refreshEligibleWeight();
      await notifier.precomputeSnapshotBundles(accountUuid: 'account-1');

      expect(rust.generateVotingHotkeyCalls, 0);
      expect(hotkeyStore.hotkey, isNull);
      expect(rust.setupCalls, 0);
      expect(rust.snapshotBundlePrecomputeAccounts, ['account-1']);
    },
  );

  test('snapshot bundle precompute skips after account switch', () async {
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
        .precomputeSnapshotBundles(accountUuid: 'account-1');

    expect(rust.snapshotBundlePrecomputeAccounts, isEmpty);
  });

  test('bundle setup waits for snapshot bundle precompute', () async {
    final precomputeGate = Completer<void>();
    final rust = FakeVotingRustApi(precomputeGate: precomputeGate);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.refreshEligibleWeight();
    final precomputeFuture = notifier.precomputeSnapshotBundles(
      accountUuid: 'account-1',
    );
    await rust.precomputeStarted.future;

    final delegationFuture = notifier.delegatePendingBundles(
      mnemonic: kTestMnemonic,
    );

    VotingSessionState? waitingState;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
      final current = container.read(votingSessionProvider(kRoundId)).value;
      if (current?.phase == VotingSessionPhase.loadingWitnesses) {
        waitingState = current;
        break;
      }
    }

    expect(waitingState?.phase, VotingSessionPhase.loadingWitnesses);
    expect(rust.setupCalls, 0);
    expect(rust.delegationBundleCalls, isEmpty);

    precomputeGate.complete();
    await Future.wait([precomputeFuture, delegationFuture]);

    final finalState = container.read(votingSessionProvider(kRoundId)).value!;
    expect(finalState.phase, VotingSessionPhase.delegated);
    expect(rust.setupCalls, 1);
    expect(rust.delegationBundleCalls, [0]);
  });

  test(
    'snapshot bundle precompute failure is a non-fatal cache miss',
    () async {
      final rust = FakeVotingRustApi(failPrecompute: true);
      final container = _sessionContainer(rust: rust);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final notifier = container.read(votingSessionProvider(kRoundId).notifier);
      await notifier.refreshEligibleWeight();
      await notifier.precomputeSnapshotBundles(accountUuid: 'account-1');
      await notifier.delegatePendingBundles(mnemonic: kTestMnemonic);

      expect(rust.snapshotBundlePrecomputeAccounts, ['account-1']);
      expect(rust.delegationBundleCalls, [0]);
      expect(rust.resetVotingSessionStateCalls, isEmpty);
    },
  );

  test('session dispose clears round-scoped process state', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);

    await container.read(votingSessionProvider(kRoundId).future);
    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(rust.resetVotingSessionStateCalls, ['account-1:$kRoundId']);
  });

  test(
    'session dispose skips process-local reset while a submission is guarded',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust);
      addTearDown(container.dispose);

      final guard = container
          .read(votingSubmissionGuardProvider.notifier)
          .acquire(accountUuid: 'account-1', roundId: kRoundId);
      addTearDown(
        () => container
            .read(votingSubmissionGuardProvider.notifier)
            .release(guard),
      );

      await container.read(votingSessionProvider(kRoundId).future);
      container.invalidate(votingSessionProvider(kRoundId));
      await Future<void>.delayed(Duration.zero);

      expect(rust.resetVotingSessionStateCalls, isEmpty);
    },
  );

  test(
    'submission session dispose skips process-local reset while guarded',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust);
      addTearDown(container.dispose);
      const key = VotingSessionKey(accountUuid: 'account-1', roundId: kRoundId);

      final guard = container
          .read(votingSubmissionGuardProvider.notifier)
          .acquire(accountUuid: key.accountUuid, roundId: key.roundId);
      addTearDown(
        () => container
            .read(votingSubmissionGuardProvider.notifier)
            .release(guard),
      );

      final subscription = container.listen(
        votingSubmissionSessionProvider(key),
        (_, _) {},
      );
      await container.read(votingSubmissionSessionProvider(key).future);
      subscription.close();
      container.invalidate(votingSubmissionSessionProvider(key));
      await Future<void>.delayed(Duration.zero);

      expect(rust.resetVotingSessionStateCalls, isEmpty);
    },
  );

  test('hotkey failure moves session into error phase', () async {
    final rust = FakeVotingRustApi();
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
      rust: rust,
      hotkeyStore: const FailingVotingHotkeyStore(),
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
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.cause, isA<VotingHotkeyUnavailable>());
    expect(recoveryApi.ballotIntents, isEmpty);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
  });

  Map<String, Object> warmupHttpResponses() =>
      votingHttpResponses()
        ..['/shielded-vote/v1/rounds'] = {
          'rounds': [roundStatusJson(roundId: kRoundId)],
        };

  test(
    'background PIR cache warmup warms active rounds without hotkey or setup',
    () async {
      final rust = FakeVotingRustApi();
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final container = _sessionContainer(
        rust: rust,
        hotkeyStore: hotkeyStore,
        http: FakeVotingHttpClient(responses: warmupHttpResponses()),
      );
      addTearDown(container.dispose);

      await container.read(votingPirWarmupProvider).maybeWarmActiveRounds();

      expect(rust.warmPirProofCacheAccountUuids, ['account-1']);
      expect(rust.warmPirProofCacheSnapshotHeights, [123]);
      // Every active round's expected nullifier IMT root survives pruning
      // (roundStatusJson uses 32 bytes of 0x03).
      expect(rust.warmPirProofCacheKeepRoots, [
        [List<int>.filled(32, 3)],
      ]);
      // The warm-up path mints no hotkey and creates no round/bundle rows.
      expect(rust.generateVotingHotkeyCalls, 0);
      expect(hotkeyStore.hotkey, isNull);
      expect(rust.setupCalls, 0);
      expect(rust.snapshotBundlePrecomputeAccounts, isEmpty);
    },
  );

  test(
    'background PIR cache warmup dedupes concurrent and repeated passes',
    () async {
      final rust = FakeVotingRustApi()..warmPirProofCacheGate = Completer();
      final container = _sessionContainer(
        rust: rust,
        http: FakeVotingHttpClient(responses: warmupHttpResponses()),
      );
      addTearDown(container.dispose);

      final coordinator = container.read(votingPirWarmupProvider);
      final first = coordinator.maybeWarmActiveRounds();
      final second = coordinator.maybeWarmActiveRounds();
      await rust.warmPirProofCacheStarted.future;
      rust.warmPirProofCacheGate!.complete();
      await Future.wait([first, second]);

      expect(rust.warmPirProofCacheSnapshotHeights, [123]);

      // A completed snapshot is not re-warmed by a later pass.
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, [123]);
    },
  );

  test(
    'background PIR cache warmup skips a second pass within the min interval',
    () async {
      final rust = FakeVotingRustApi();
      final http = FakeVotingHttpClient(responses: warmupHttpResponses());
      final container = _sessionContainer(rust: rust, http: http);
      addTearDown(container.dispose);

      final coordinator = container.read(votingPirWarmupProvider);
      await coordinator.maybeWarmActiveRounds();
      final roundListCalls = http.requests
          .where(
            (request) => request.uri.path.endsWith('/shielded-vote/v1/rounds'),
          )
          .length;
      expect(roundListCalls, greaterThan(0));
      expect(rust.warmPirProofCacheSnapshotHeights, [123]);

      // Polls -> round-detail entry must not fire another list/status burst.
      await coordinator.maybeWarmActiveRounds();
      expect(
        http.requests
            .where(
              (request) =>
                  request.uri.path.endsWith('/shielded-vote/v1/rounds'),
            )
            .length,
        roundListCalls,
      );
      expect(rust.warmPirProofCacheSnapshotHeights, [123]);
    },
  );

  test(
    'background PIR cache warmup min interval does not block a new account',
    () async {
      final rust = FakeVotingRustApi();
      final activeAccountProvider =
          NotifierProvider<_ActiveVotingAccountNotifier, String?>(
            _ActiveVotingAccountNotifier.new,
          );
      final container = _sessionContainer(
        rust: rust,
        http: FakeVotingHttpClient(responses: warmupHttpResponses()),
        activeAccountUuidListenable: activeAccountProvider,
      );
      addTearDown(container.dispose);

      final coordinator = container.read(votingPirWarmupProvider);
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheAccountUuids, ['account-1']);

      container.read(activeAccountProvider.notifier).set('account-2');
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheAccountUuids, ['account-1', 'account-2']);
    },
  );

  test(
    'background PIR cache warmup failure is non-fatal and retried next pass',
    () async {
      final rust = FakeVotingRustApi()
        ..warmPirProofCacheError = StateError('pir fetch failed');
      final container = _sessionContainer(
        rust: rust,
        http: FakeVotingHttpClient(responses: warmupHttpResponses()),
      );
      addTearDown(container.dispose);

      final coordinator = container.read(votingPirWarmupProvider);
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, [123]);

      // The failed snapshot is not recorded as completed, so the next
      // trigger retries immediately instead of waiting out the success
      // min-interval.
      rust.warmPirProofCacheError = null;
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, [123, 123]);
    },
  );

  test(
    'background PIR cache warmup retries after a stale served root',
    () async {
      final rust = FakeVotingRustApi()
        ..warmPirProofCacheServedRoot = Uint8List(32);
      final container = _sessionContainer(
        rust: rust,
        http: FakeVotingHttpClient(responses: warmupHttpResponses()),
      );
      addTearDown(container.dispose);

      final coordinator = container.read(votingPirWarmupProvider);
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, [123]);

      rust.warmPirProofCacheServedRoot = Uint8List.fromList(
        List<int>.filled(32, 3),
      );
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, [123, 123]);

      // The matching response completes the snapshot, so later triggers are
      // gated normally.
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, [123, 123]);
    },
  );

  test('background PIR cache warmup skips quietly when no PIR endpoint serves '
      'the snapshot height', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(
      rust: rust,
      http: FakeVotingHttpClient(responses: warmupHttpResponses()),
      pirResolver: const FakePirResolver(
        error: PirSnapshotNoMatchingEndpoint(
          expectedSnapshotHeight: 123,
          diagnostics: [],
        ),
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingPirWarmupProvider).maybeWarmActiveRounds();

    expect(rust.warmPirProofCacheSnapshotHeights, isEmpty);
  });

  test(
    'background PIR cache warmup gives up on wallet-sync timeout and retries '
    'on the next trigger',
    () async {
      final rust = FakeVotingRustApi();
      final readiness = _MutableVotingWalletSyncReadinessChecker(ready: false);
      final container = _sessionContainer(
        rust: rust,
        http: FakeVotingHttpClient(responses: warmupHttpResponses()),
        walletSyncReadinessChecker: readiness,
        extraOverrides: [
          votingPirWarmupSyncMaxWaitProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(votingPirWarmupProvider);
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, isEmpty);

      readiness.ready = true;
      await coordinator.maybeWarmActiveRounds();
      expect(rust.warmPirProofCacheSnapshotHeights, [123]);
    },
  );

  test('background PIR cache warmup skips after account switch', () async {
    final rust = FakeVotingRustApi();
    final readiness = _GatedVotingWalletSyncReadinessChecker();
    final activeAccountProvider =
        NotifierProvider<_ActiveVotingAccountNotifier, String?>(
          _ActiveVotingAccountNotifier.new,
        );
    final container = _sessionContainer(
      rust: rust,
      http: FakeVotingHttpClient(responses: warmupHttpResponses()),
      walletSyncReadinessChecker: readiness,
      activeAccountUuidListenable: activeAccountProvider,
    );
    addTearDown(container.dispose);

    final warmup = container
        .read(votingPirWarmupProvider)
        .maybeWarmActiveRounds();
    await readiness.firstCheck.future;
    container.read(activeAccountProvider.notifier).set('account-2');
    readiness.allowReady();
    await warmup;

    expect(rust.warmPirProofCacheSnapshotHeights, isEmpty);
  });

  test('background PIR cache warmup skips hidden [TEST] rounds', () async {
    final rust = FakeVotingRustApi();
    final testRound = roundStatusJson(roundId: kRoundId)
      ..['title'] = '[TEST] Hidden poll';
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(roundStatus: testRound)
        ..['/shielded-vote/v1/rounds'] = {
          'rounds': [testRound],
        },
    );
    final container = _sessionContainer(
      rust: rust,
      http: http,
      visibilityStore: FakeVotingRoundVisibilityStore(),
    );
    addTearDown(container.dispose);

    await container.read(votingPirWarmupProvider).maybeWarmActiveRounds();

    expect(rust.warmPirProofCacheSnapshotHeights, isEmpty);
    expect(
      http.requests.any(
        (request) => request.uri.path == '/shielded-vote/v1/round/$kRoundId',
      ),
      isFalse,
    );
  });

  test(
    'background PIR cache warmup includes [TEST] rounds when shown',
    () async {
      final rust = FakeVotingRustApi();
      final testRound = roundStatusJson(roundId: kRoundId)
        ..['title'] = '[TEST] Opt-in poll';
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(roundStatus: testRound)
          ..['/shielded-vote/v1/rounds'] = {
            'rounds': [testRound],
          },
      );
      final container = _sessionContainer(
        rust: rust,
        http: http,
        visibilityStore: FakeVotingRoundVisibilityStore(showTestRounds: true),
      );
      addTearDown(container.dispose);

      await container.read(votingPirWarmupProvider).maybeWarmActiveRounds();

      expect(rust.warmPirProofCacheSnapshotHeights, [123]);
      expect(
        http.requests.any(
          (request) => request.uri.path == '/shielded-vote/v1/round/$kRoundId',
        ),
        isTrue,
      );
    },
  );
}

ProviderContainer _container({
  required VotingHttpClient http,
  VotingConfigSourceStore? sourceStore,
  VotingRoundVisibilityStore? visibilityStore,
}) {
  return ProviderContainer(
    overrides: [
      votingConfigSourceStoreProvider.overrideWithValue(
        sourceStore ?? FakeVotingConfigSourceStore(),
      ),
      votingRoundVisibilityStoreProvider.overrideWithValue(
        visibilityStore ?? FakeVotingRoundVisibilityStore(),
      ),
      votingHttpClientProvider.overrideWithValue(http),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: http,
          sourceUrl: 'https://voting.example/static-voting-config.json',
          resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
          resolveVotingConfigFromAttempts:
              ({
                required source,
                required staticBytes,
                required attempts,
                previous,
              }) => fakeResolveVotingConfig(
                dynamicBytes: attempts.last.bytes!,
                previous: previous,
                authenticatedRoundIds: const [kRoundId, kOtherRoundId],
              ),
        ),
      ),
      votingActiveAccountUuidProvider.overrideWithValue(() async => null),
    ],
  );
}

class FakeVotingRoundVisibilityStore implements VotingRoundVisibilityStore {
  FakeVotingRoundVisibilityStore({this.showTestRounds = false});

  bool showTestRounds;

  @override
  Future<bool> readShowTestRounds() async => showTestRounds;

  @override
  Future<void> writeShowTestRounds(bool show) async {
    showTestRounds = show;
  }
}

final class _ProviderDisposalObserver extends ProviderObserver {
  _ProviderDisposalObserver(this.targetProvider);

  final Object targetProvider;
  bool disposed = false;

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    if (context.provider == targetProvider) disposed = true;
  }
}

class _YieldingFakeVotingHttpClient extends FakeVotingHttpClient {
  _YieldingFakeVotingHttpClient({super.responses});

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    await Future<void>.delayed(Duration.zero);
    return super.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }
}

class _GatedSharePostVotingHttpClient extends FakeVotingHttpClient {
  _GatedSharePostVotingHttpClient({
    required this.expectedShareCount,
    required this.gatedShareIndexes,
    super.responses,
  });

  final int expectedShareCount;
  final Set<int> gatedShareIndexes;
  final Set<int> startedShareIndexes = {};
  int _activeSharePostCount = 0;
  int maxConcurrentSharePostCount = 0;
  final Completer<void> allSharePostsStarted = Completer<void>();
  final Completer<void> releaseSharePosts = Completer<void>();

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    if (uri.path == '/shielded-vote/v1/shares') {
      final shareIndex = body['share_index'] as int;
      startedShareIndexes.add(shareIndex);
      _activeSharePostCount++;
      if (_activeSharePostCount > maxConcurrentSharePostCount) {
        maxConcurrentSharePostCount = _activeSharePostCount;
      }
      final expectedPostsStarted =
          startedShareIndexes.length == expectedShareCount;
      if (expectedPostsStarted && !allSharePostsStarted.isCompleted) {
        allSharePostsStarted.complete();
      }
      try {
        if (gatedShareIndexes.contains(shareIndex)) {
          await releaseSharePosts.future;
        }
      } finally {
        _activeSharePostCount--;
      }
    }
    return super.postJson(uri, body, timeout: timeout);
  }
}

Future<void> _waitForRecordedShareCount(
  FakeVotingRustApi rust,
  int expectedCount,
) async {
  for (var i = 0; i < 100; i++) {
    if (rust.recordedShares.length >= expectedCount) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for $expectedCount recorded shares. '
    'Saw ${rust.recordedShares.length}.',
  );
}

Future<void> _waitForPlannedShareCount(
  FakeVotingRustApi rust,
  int expectedCount,
) async {
  for (var i = 0; i < 100; i++) {
    if (rust.plannedSharePlans.length >= expectedCount) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for $expectedCount planned shares. '
    'Saw ${rust.plannedSharePlans.length}.',
  );
}

class _CountingVotingRoundsNotifier extends VotingRoundsNotifier {
  int reloadCount = 0;

  @override
  Future<List<VotingRoundView>> build() async => const [];

  @override
  Future<void> reload() async {
    reloadCount++;
  }
}

PirSnapshotResolution _pirResolution(Uri selected, List<Uri> matches) {
  return PirSnapshotResolution(
    endpoint: selected,
    diagnostics: [
      for (final endpoint in matches)
        PirSnapshotEndpointDiagnostic(
          endpoint: endpoint,
          status: PirSnapshotEndpointStatus.matched,
          reportedHeight: 123,
        ),
    ],
  );
}

ProviderContainer _sessionContainer({
  List<Override> extraOverrides = const [],
  FakeVotingHttpClient? http,
  FakeVotingRustApi? rust,
  FakeVotingRecoveryApi? recoveryApi,
  AppSecurityNotifier? securityNotifier,
  VotingDraftPersistence? draftPersistence,
  PirSnapshotResolver? pirResolver,
  VotingHotkeyStore? hotkeyStore,
  VotingRoundVisibilityStore? visibilityStore,
  Future<String?> Function()? activeAccountUuid,
  ProviderListenable<String?>? activeAccountUuidListenable,
  bool accountIsHardware = false,
  Set<String>? hardwareAccountUuids,
  String? accountMnemonic = kTestMnemonic,
  String accountBip39Passphrase = '',
  List<ProviderObserver>? observers,
  VotingTxConfirmationPolling? txConfirmationPolling,
  VotingWalletSyncReadinessChecker? walletSyncReadinessChecker,
  void Function()? walletSyncStarter,
  Duration? walletSyncPollInterval,
  VotingPendingShareRoundLoader? pendingShareRoundLoader,
  List<String> authenticatedRoundIds = const [kRoundId, kOtherRoundId],
  Map<String, Uint8List>? authenticatedRoundEaPks,
  List<String> skippedRoundIds = const [],
  rust_config.ConfigSwitchKind Function(rust_config.ResolvedVotingConfig?)?
  configSwitchKind,
}) {
  final effectiveHttp =
      http ?? FakeVotingHttpClient(responses: votingHttpResponses());
  final effectiveRust = rust ?? FakeVotingRustApi();
  // Helper requests are made by the crate in production; point the fake at the
  // test transport so provider tests can still observe them.
  effectiveRust.helperTransport = effectiveHttp;
  if (recoveryApi != null) effectiveRust.helperRecoveryApi = recoveryApi;
  final effectiveHardwareAccountUuids =
      hardwareAccountUuids ?? (accountIsHardware ? {'account-1'} : <String>{});
  return ProviderContainer(
    observers: observers,
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      if (securityNotifier != null)
        appSecurityProvider.overrideWith(() => securityNotifier),
      votingConfigSourceStoreProvider.overrideWithValue(
        FakeVotingConfigSourceStore(),
      ),
      votingRoundVisibilityStoreProvider.overrideWithValue(
        visibilityStore ?? FakeVotingRoundVisibilityStore(),
      ),
      votingHttpClientProvider.overrideWithValue(effectiveHttp),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: effectiveHttp,
          sourceUrl: 'https://voting.example/static-voting-config.json',
          resolveStaticVotingConfig: fakeResolveStaticVotingConfig,
          resolveVotingConfigFromAttempts:
              ({
                required source,
                required staticBytes,
                required attempts,
                previous,
              }) => fakeResolveVotingConfig(
                dynamicBytes: attempts.last.bytes!,
                previous: previous,
                authenticatedRoundIds: authenticatedRoundIds,
                authenticatedRoundEaPks: authenticatedRoundEaPks,
                skippedRoundIds: skippedRoundIds,
                switchKind: configSwitchKind?.call(previous),
              ),
        ),
      ),
      votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
      if (pendingShareRoundLoader != null)
        votingPendingShareRoundLoaderProvider.overrideWithValue(
          pendingShareRoundLoader,
        ),
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
        () => _FakeVotingAccountNotifier(
          mnemonic: accountMnemonic,
          bip39Passphrase: accountBip39Passphrase,
        ),
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
      votingRustApiProvider.overrideWithValue(effectiveRust),
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
      ...extraOverrides,
    ],
  );
}

final _pollEligibilityOverrides = <Override>[
  votingPollEligibilityWalletRevisionProvider.overrideWithValue((
    locked: false,
    sync: (false, null),
  )),
  votingRoundsProvider.overrideWith(_PollEligibilityRoundsNotifier.new),
];

class _PollEligibilityRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async => [];

  @override
  Future<void> reload() async => state = AsyncData([]);
}

class _PollEligibilitySyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  void progress() =>
      state = AsyncData(state.requireValue.copyWith(percentage: 50));

  void complete() => state = AsyncData(
    state.requireValue.copyWith(lastSyncCompletedAt: DateTime(2026, 8, 26)),
  );
}

class _GatedPollEligibilityRustApi extends FakeVotingRustApi {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    final result = await super.checkVotingEligibility(ctx: ctx);
    return rust_api.ApiVotingEligibility(
      isEligible: ctx.accountUuid != 'account-1',
      distinctNoteCount: result.distinctNoteCount,
      eligibleWeightZatoshi: result.eligibleWeightZatoshi,
      privacyTrimDroppedValueZatoshi: result.privacyTrimDroppedValueZatoshi,
    );
  }
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
  rust_frb_types.ShareDelegationRecordView share, {
  bool includeCommitmentBundle = false,
  bool designateImmediateShare = false,
}) {
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
    immediateShareKey: designateImmediateShare
        ? rust_share_policy.ImmediateShareKey(
            bundleIndex: share.bundleIndex,
            proposalId: share.proposalId,
            shareIndex: share.shareIndex,
          )
        : null,
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
      commitmentBundles: includeCommitmentBundle
          ? [
              rust_frb_types.RecoverableCommitmentBundle(
                bundleIndex: share.bundleIndex,
                proposalId: share.proposalId,
                commitmentBundleJson: commitmentBundleRecoveryJson(),
                vcTreePosition: BigInt.from(42),
              ),
            ]
          : const [],
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
  VotingSubmissionJobStatus status, {
  int attempts = 100,
}) async {
  for (var i = 0; i < attempts; i++) {
    final state = container.read(votingSubmissionJobProvider(key));
    if (state.status == status) return state;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final last = container.read(votingSubmissionJobProvider(key));
  fail(
    'Timed out waiting for voting submission job status $status. '
    'Last status: ${last.status}, error: ${last.errorMessage}',
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

  final Map<String, rust_api.VotingConfigResolution> _configs;
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

  Future<rust_api.VotingConfigResolution> load(String sourceUrl) async {
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
  Future<rust_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
    void Function(VotingConfigMirrorFailure failure)? mirrorFailureObserver,
  }) {
    return _loads.load(_sourceUrl);
  }
}

class _GatedVotingHttpClient extends FakeVotingHttpClient {
  _GatedVotingHttpClient({super.responses});

  final Map<String, List<Completer<void>>> _getGates = {};
  final Map<String, int> _getCounts = {};
  final Map<String, List<_GetCountWaiter>> _getCountWaiters = {};

  Completer<void> gateNextGet(String path) {
    final gate = Completer<void>();
    (_getGates[path] ??= []).add(gate);
    return gate;
  }

  Future<void> waitForGetCount(String path, int count) {
    if ((_getCounts[path] ?? 0) >= count) {
      return Future<void>.value();
    }
    final waiter = _GetCountWaiter(count);
    (_getCountWaiters[path] ??= []).add(waiter);
    return waiter.completer.future;
  }

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    _recordGet(uri.path);
    final gates = _getGates[uri.path];
    if (gates != null && gates.isNotEmpty) {
      await gates.removeAt(0).future;
    }
    return super.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }

  void _recordGet(String path) {
    final count = (_getCounts[path] ?? 0) + 1;
    _getCounts[path] = count;
    final waiters = _getCountWaiters[path];
    if (waiters == null || waiters.isEmpty) return;
    waiters.removeWhere((waiter) {
      if (count < waiter.count) return false;
      waiter.completer.complete();
      return true;
    });
  }
}

class _GetCountWaiter {
  _GetCountWaiter(this.count);

  final int count;
  final Completer<void> completer = Completer<void>();
}

rust_api.VotingConfigResolution _configForVoteServer(String url) {
  final defaultEaPk = Uint8List.fromList(List.filled(32, 1));
  final config = rust_config.ResolvedVotingConfig(
    sourceFingerprint: 'test-source-fingerprint',
    trustedKeyFingerprint: 'test-trusted-key-fingerprint',
    dynamicConfigFingerprint: 'test-dynamic-config-fingerprint',
    voteServers: [rust_config.ServiceEndpoint(url: url, label: 'primary')],
    pirEndpoints: const [
      rust_config.ServiceEndpoint(url: 'https://pir.example', label: 'pir'),
    ],
    pirLayout: const rust_config.PirLayout(
      pirDepth: 19,
      tier0Layers: 12,
      tier1Layers: 7,
      polyLen: 4096,
    ),
    supportedVersions: const rust_config.SupportedVersions(
      pir: ['v0'],
      voteProtocol: 'v0',
      tally: 'v0',
      voteServer: 'v1',
    ),
    authenticatedRounds: [
      rust_config.AuthenticatedRound(roundId: kRoundId, eaPk: defaultEaPk),
      rust_config.AuthenticatedRound(roundId: kOtherRoundId, eaPk: defaultEaPk),
    ],
    skippedRoundIds: const [],
    conditions: const [],
  );
  return rust_api.VotingConfigResolution(
    config: config,
    switchKind: rust_config.ConfigSwitchKind.unchanged,
    skippedMirrors: const [],
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
  '/shielded-vote/v1/status': {'status': 'ok'},
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
    '{"rk":"Ag==","spend_auth_sig":"Aw==","tx1_effects":"BA==","signed_note_nullifier":"BQ==","cmx_new":"Bg==","van_cmx":"Bw==","gov_nullifiers":["CA=="],"proof":"AQ==","vote_round_id":"$_roundIdBase64"}';
const _voteCommitmentWireGolden =
    '{"van_nullifier":"$_bytes1x32Base64","vote_authority_note_new":"$_bytes2x32Base64","vote_commitment":"$_bytes3x32Base64","proposal_id":7,"proof":"BA==","vote_round_id":"$_roundIdBase64","vote_comm_tree_anchor_height":10,"r_vpk":"$_bytes13x32Base64","vote_auth_sig":"$_bytes12x64Base64"}';
const _voteShareWireGolden =
    '{"vote_round_id":"$kRoundId","shares_hash":"$_bytes7x32Base64","proposal_id":7,"vote_decision":1,"enc_share":{"c1":"CA==","c2":"CQ==","share_index":0},"share_index":0,"tree_position":2,"share_comms":["$_bytes10x32Base64"],"primary_blind":"$_bytes11x32Base64","submit_at":0}';
const _fastTxConfirmationPolling = VotingTxConfirmationPolling(
  attempts: 1,
  delay: Duration.zero,
);

/// Mirrors the Rust resolver's schema handling: v2 names an ordered list, v1
/// names exactly one URL and resolves to a single-entry list.
Future<List<String>> fakeResolveStaticVotingConfig({
  required String source,
  required List<int> staticBytes,
}) async {
  final staticJson = decodeVotingJsonObject(utf8.decode(staticBytes));
  final dynamicConfigUrls = staticJson['dynamic_config_urls'];
  if (dynamicConfigUrls is List && dynamicConfigUrls.isNotEmpty) {
    return dynamicConfigUrls
        .map((value) => value.toString())
        .toList(growable: false);
  }
  final dynamicConfigUrl = staticJson['dynamic_config_url']?.toString();
  if (dynamicConfigUrl == null || dynamicConfigUrl.isEmpty) {
    throw const FormatException('Missing required string: dynamic_config_url');
  }
  return [dynamicConfigUrl];
}

Future<rust_api.VotingConfigResolution> fakeResolveVotingConfig({
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
  final pirLayout = dynamicJson['pir_layout'] as Map<String, dynamic>;
  final versions = dynamicJson['supported_versions'] as Map<String, dynamic>;
  final dynamicRounds = dynamicJson['rounds'] as Map<String, dynamic>;
  final effectiveAuthenticatedRoundIds =
      authenticatedRoundIds ?? dynamicRounds.keys.toList(growable: false);
  final authenticatedRounds = effectiveAuthenticatedRoundIds
      .map((roundId) {
        final configuredEaPk = authenticatedRoundEaPks?[roundId];
        if (configuredEaPk != null) {
          return rust_config.AuthenticatedRound(
            roundId: roundId,
            eaPk: configuredEaPk,
          );
        }
        final dynamicRound = dynamicRounds[roundId] as Map<String, dynamic>?;
        final eaPkB64 = dynamicRound?['ea_pk']?.toString();
        if (eaPkB64 == null || eaPkB64.isEmpty) {
          throw FormatException(
            'Missing required string: rounds.$roundId.ea_pk',
          );
        }
        return rust_config.AuthenticatedRound(
          roundId: roundId,
          eaPk: base64Decode(eaPkB64),
        );
      })
      .toList(growable: false);
  final resolved = rust_config.ResolvedVotingConfig(
    sourceFingerprint: 'test-source-fingerprint',
    trustedKeyFingerprint: 'test-trusted-key-fingerprint',
    dynamicConfigFingerprint: 'test-dynamic-config-fingerprint',
    voteServers: voteServers,
    pirEndpoints: pirEndpoints,
    pirLayout: rust_config.PirLayout(
      pirDepth: (pirLayout['pir_depth'] as num).toInt(),
      tier0Layers: (pirLayout['tier0_layers'] as num).toInt(),
      tier1Layers: (pirLayout['tier1_layers'] as num).toInt(),
      polyLen: (pirLayout['poly_len'] as num).toInt(),
    ),
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

  return rust_api.VotingConfigResolution(
    config: resolved,
    switchKind:
        switchKind ??
        (previous == null
            ? rust_config.ConfigSwitchKind.initialLoad
            : rust_config.ConfigSwitchKind.unchanged),
    skippedMirrors: const [],
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
  Map<String, int> pirLayout = const {
    'pir_depth': 19,
    'tier0_layers': 12,
    'tier1_layers': 7,
    'poly_len': 4096,
  },
}) => {
  'config_version': 1,
  'vote_servers': voteServers,
  'pir_endpoints': [
    {'url': 'https://pir.example', 'label': 'pir'},
  ],
  'pir_layout': pirLayout,
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
  bool includeVoteEnd = true,
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
  if (includeVoteEnd) {
    json['vote_end_time'] = voteEnd ?? 4102444800;
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
    'vote_round_id': kRoundId,
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

VotingKeystoneBatchSignature _keystoneBatchSignature(int bundleIndex) {
  return VotingKeystoneBatchSignature(
    bundleIndex: bundleIndex,
    pool: 1,
    actionIndex: 0,
    signature: List.filled(64, 30 + bundleIndex),
  );
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
    late final rust_wire.RoundPlanView plan;
    if (sequence != null && sequence.isNotEmpty) {
      var index = _roundPlanCallCount;
      _roundPlanCallCount++;
      if (index >= sequence.length) index = sequence.length - 1;
      plan = sequence[index];
    } else {
      plan =
          roundPlan ??
          apiRoundPlanFromRecoveryState(
            state: state,
            roundId: roundId,
            proposalIds: proposalIds,
          );
    }
    final immediate = plan.immediateShareKey;
    final confirmed =
        immediate != null &&
        state.shareDelegations.any(
          (share) =>
              share.bundleIndex == immediate.bundleIndex &&
              share.proposalId == immediate.proposalId &&
              share.shareIndex == immediate.shareIndex &&
              share.confirmed,
        );
    return confirmed && !plan.immediateShareConfirmed
        ? _withImmediateShareConfirmed(plan)
        : plan;
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

rust_wire.RoundPlanView _withImmediateShareConfirmed(
  rust_wire.RoundPlanView plan,
) {
  return rust_wire.RoundPlanView(
    roundId: plan.roundId,
    pendingRecovery: plan.pendingRecovery,
    blockingRecovery: plan.blockingRecovery,
    blockingShareWork: plan.blockingShareWork,
    hotkeyBound: plan.hotkeyBound,
    completedVoteArtifact: plan.completedVoteArtifact,
    completedForDisplay: plan.completedForDisplay,
    completedVoteDisplay: plan.completedVoteDisplay,
    needsDraftSetup: plan.needsDraftSetup,
    primaryAction: plan.primaryAction,
    nextSteps: plan.nextSteps,
    delegationStatuses: plan.delegationStatuses,
    recoveredDelegationWork: plan.recoveredDelegationWork,
    recoveredVoteWork: plan.recoveredVoteWork,
    openProposals: plan.openProposals,
    immediateShareKey: plan.immediateShareKey,
    immediateShareConfirmed: true,
    allDecided: plan.allDecided,
  );
}

class FakeVotingDraftPersistence implements VotingDraftPersistence {
  final _stored = <VotingSessionKey, VotingDraftState>{};
  final _deletedAccountUuids = <String>{};
  Object? loadError;

  @override
  Future<VotingDraftState> load(VotingSessionKey key) async {
    final error = loadError;
    if (error != null) throw error;
    return _stored[key] ?? const VotingDraftState();
  }

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {
    if (_deletedAccountUuids.contains(key.accountUuid)) return;
    if (draft.choices.isEmpty) {
      _stored.remove(key);
    } else {
      _stored[key] = VotingDraftState(choices: Map.of(draft.choices));
    }
  }

  @override
  Future<void> deleteForAccount(String accountUuid) async {
    _deletedAccountUuids.add(accountUuid);
    _stored.removeWhere((key, _) => key.accountUuid == accountUuid);
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
  _FakeVotingAccountNotifier({
    required String? mnemonic,
    required String bip39Passphrase,
  }) : softwareSecret = mnemonic == null
           ? null
           : SoftwareWalletSecret(
               mnemonic: mnemonic,
               bip39Passphrase: bip39Passphrase,
             );

  final SoftwareWalletSecret? softwareSecret;

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
    return softwareSecret?.mnemonic;
  }

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async {
    return softwareSecret;
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

class _MutableVotingWalletSyncReadinessChecker
    implements VotingWalletSyncReadinessChecker {
  _MutableVotingWalletSyncReadinessChecker({required this.ready});

  bool ready;

  @override
  Future<VotingWalletSyncReadiness> check({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  }) async {
    return VotingWalletSyncReadiness(
      scannedHeight: ready ? snapshotHeight : snapshotHeight - 1,
      snapshotHeight: snapshotHeight,
      chainTipHeight: snapshotHeight,
    );
  }
}

class _MutableVotingSecurityNotifier extends AppSecurityNotifier {
  _MutableVotingSecurityNotifier(this.initialState);

  final AppSecurityState initialState;

  @override
  AppSecurityState build() => initialState;

  void setUnlocked(bool value) {
    state = state.copyWith(isUnlocked: value);
  }
}

class _DelegationConcurrencyHttpClient extends FakeVotingHttpClient {
  _DelegationConcurrencyHttpClient({required super.responses});

  int _activeDelegationPosts = 0;
  int _activeVotePosts = 0;
  int _activeConfirmationGets = 0;
  int maxConcurrentDelegationPosts = 0;
  int maxConcurrentVotePosts = 0;
  int maxConcurrentConfirmationGets = 0;

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final isDelegation = uri.path.endsWith('/delegate-vote');
    final isVote = uri.path.endsWith('/cast-vote');
    if (!isDelegation && !isVote) {
      return super.postJson(uri, body, timeout: timeout);
    }
    if (isDelegation) {
      _activeDelegationPosts++;
      if (_activeDelegationPosts > maxConcurrentDelegationPosts) {
        maxConcurrentDelegationPosts = _activeDelegationPosts;
      }
    } else {
      _activeVotePosts++;
      if (_activeVotePosts > maxConcurrentVotePosts) {
        maxConcurrentVotePosts = _activeVotePosts;
      }
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return await super.postJson(uri, body, timeout: timeout);
    } finally {
      if (isDelegation) {
        _activeDelegationPosts--;
      } else {
        _activeVotePosts--;
      }
    }
  }

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    if (!uri.path.contains('/tx/')) {
      return super.get(
        uri,
        headers: headers,
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
    }
    _activeConfirmationGets++;
    if (_activeConfirmationGets > maxConcurrentConfirmationGets) {
      maxConcurrentConfirmationGets = _activeConfirmationGets;
    }
    try {
      // Deliberately slower than a broadcast POST, matching real chains where
      // a confirmation wait spans blocks. This is what makes "confirmations
      // overlap the next bundle's broadcast" observable.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return await super.get(
        uri,
        headers: headers,
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
    } finally {
      _activeConfirmationGets--;
    }
  }
}

class _UniqueVoteTxHttpClient extends FakeVotingHttpClient {
  _UniqueVoteTxHttpClient({required super.responses});

  var _votePostCount = 0;

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    if (!uri.path.endsWith('/cast-vote')) {
      return super.postJson(uri, body, timeout: timeout);
    }
    requests.add(
      FakeVotingHttpRequest('POST', uri, body: body, timeout: timeout),
    );
    return jsonResponse({
      'tx_hash': 'vote-tx-${_votePostCount++}',
      'code': 0,
      'log': '',
    });
  }
}

class _GatedFirstVotePostHttpClient extends _UniqueVoteTxHttpClient {
  _GatedFirstVotePostHttpClient({required super.responses});

  final Completer<void> firstVotePostStarted = Completer<void>();
  final Completer<void> releaseFirstVotePost = Completer<void>();

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    if (!uri.path.endsWith('/cast-vote') || _votePostCount != 0) {
      return super.postJson(uri, body, timeout: timeout);
    }
    requests.add(
      FakeVotingHttpRequest('POST', uri, body: body, timeout: timeout),
    );
    firstVotePostStarted.complete();
    await releaseFirstVotePost.future;
    return jsonResponse({
      'tx_hash': 'vote-tx-${_votePostCount++}',
      'code': 0,
      'log': '',
    });
  }
}

class _GatedVoteConfirmationHttpClient extends _UniqueVoteTxHttpClient {
  _GatedVoteConfirmationHttpClient({required super.responses});

  final Completer<void> slowConfirmationStarted = Completer<void>();
  final Completer<void> releaseSlowConfirmation = Completer<void>();

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    if (uri.path.endsWith('/tx/vote-tx-0')) {
      if (!slowConfirmationStarted.isCompleted) {
        slowConfirmationStarted.complete();
      }
      await releaseSlowConfirmation.future;
    }
    return super.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }
}

class _GatedSubmittedVoteConfirmationHttpClient extends FakeVotingHttpClient {
  _GatedSubmittedVoteConfirmationHttpClient({required super.responses});

  final Completer<void> confirmationStarted = Completer<void>();
  final Completer<void> releaseConfirmation = Completer<void>();

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    if (uri.path.endsWith('/tx/submitted-vote-tx')) {
      if (!confirmationStarted.isCompleted) {
        confirmationStarted.complete();
      }
      await releaseConfirmation.future;
    }
    return super.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }
}

class _SeparatedVoteStagePoolsHttpClient extends _UniqueVoteTxHttpClient {
  _SeparatedVoteStagePoolsHttpClient({required super.responses});

  final Completer<void> firstThreeSharesStarted = Completer<void>();
  final Completer<void> fourthConfirmationStarted = Completer<void>();
  final Completer<void> _releaseSharePosts = Completer<void>();
  var sharePostCount = 0;
  var _activeSharePosts = 0;
  var maxConcurrentSharePosts = 0;

  void releaseShares() {
    if (!_releaseSharePosts.isCompleted) _releaseSharePosts.complete();
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    if (!uri.path.endsWith('/shares')) {
      return super.postJson(uri, body, timeout: timeout);
    }
    sharePostCount++;
    _activeSharePosts++;
    if (_activeSharePosts > maxConcurrentSharePosts) {
      maxConcurrentSharePosts = _activeSharePosts;
    }
    if (sharePostCount == 3 && !firstThreeSharesStarted.isCompleted) {
      firstThreeSharesStarted.complete();
    }
    try {
      if (sharePostCount <= 3) await _releaseSharePosts.future;
      return await super.postJson(uri, body, timeout: timeout);
    } finally {
      _activeSharePosts--;
    }
  }

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    if (uri.path.endsWith('/tx/vote-tx-3') &&
        !fourthConfirmationStarted.isCompleted) {
      fourthConfirmationStarted.complete();
    }
    return super.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }
}

class _WitnessHandoffVotingRustApi extends FakeVotingRustApi {
  _WitnessHandoffVotingRustApi() : super(emitCommitments: true, bundleCount: 2);

  final Completer<void> firstWitnessStarted = Completer<void>();
  final Completer<void> _releaseFirstWitness = Completer<void>();
  var _primarySyncCalls = 0;
  var _firstWitnessReleased = false;
  var _treeReady = false;

  void releaseFirstWitness() {
    if (!_releaseFirstWitness.isCompleted) {
      _releaseFirstWitness.complete();
    }
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String nodeUrl,
  }) async {
    if (nodeUrl == 'https://voting.example' && _primarySyncCalls++ == 1) {
      syncedVoteTrees.add(roundId);
      syncedVoteTreeNodeUrls.add(nodeUrl);
      throw StateError('injected second primary tree-sync failure');
    }
    final height = await super.syncVoteTree(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      nodeUrl: nodeUrl,
    );
    _treeReady = true;
    return height;
  }

  @override
  Future<rust_vote.VanWitness> generateVanWitness({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  }) async {
    if (bundleIndex == 0 && !_firstWitnessReleased) {
      _firstWitnessReleased = true;
      if (!firstWitnessStarted.isCompleted) firstWitnessStarted.complete();
      await _releaseFirstWitness.future;
    }
    if (!_treeReady) {
      throw StateError('vote tree cache reset before witness generation');
    }
    return super.generateVanWitness(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      anchorHeight: anchorHeight,
    );
  }

  @override
  Future<void> resetVoteTree({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {
    _treeReady = false;
    await super.resetVoteTree(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );
  }
}

int _fakeShareTargetCount(int serverCount) => (serverCount + 1) ~/ 2;

rust_api.ApiChainSubmissionOutcome _acceptedChainOutcome(String txHash) =>
    rust_api.ApiChainSubmissionOutcome(
      status: 'accepted',
      txHash: txHash,
      knownTxHashes: [txHash],
      code: 0,
      message: null,
      vanLeafPosition: null,
      vcTreePosition: null,
    );

rust_api.ApiChainSubmissionOutcome _pendingChainOutcome(String txHash) =>
    rust_api.ApiChainSubmissionOutcome(
      status: 'pending',
      txHash: null,
      knownTxHashes: [txHash],
      code: null,
      message: null,
      vanLeafPosition: null,
      vcTreePosition: null,
    );

rust_api.ApiChainSubmissionOutcome _rejectedChainOutcome(
  int code,
  String message,
) => rust_api.ApiChainSubmissionOutcome(
  status: 'rejected',
  txHash: null,
  knownTxHashes: const [],
  code: code,
  message: message,
  vanLeafPosition: null,
  vcTreePosition: null,
);

rust_api.ApiChainSubmissionOutcome _cancelledChainOutcome() =>
    const rust_api.ApiChainSubmissionOutcome(
      status: 'cancelled',
      txHash: null,
      knownTxHashes: [],
      code: null,
      message: null,
      vanLeafPosition: null,
      vcTreePosition: null,
    );

class FakeVotingRustApi implements VotingRustApi {
  FakeVotingRustApi({
    this.setupDelay = Duration.zero,
    this.setupGate,
    this.emitCommitments = false,
    this.generatedHotkeys = const [
      [42, 43, 44],
    ],
    this.hotkeyGenerationGate,
    this.precomputeGate,
    this.failPrecompute = false,
    this.bundleCount = 1,
    this.setupEligibleWeight = 100,
    this.eligibilityDistinctNoteCount = 5,
    this.eligibilityEligible,
    this.commitmentShareCount = 1,
    this.mismatchKeystoneSubmission = false,
    this.delegationStreamError,
    this.delegationStreamErrorsByBundle = const {},
    this.keystoneDelegationStreamErrorsByBundle = const {},
    this.recoveredDelegationBundleIndices = const {},
    this.onDelegationConfirmed,
    this.delegationProofGate,
    this.keystoneDelegationProofGate,
    this.delegationWireJsonGate,
    this.voteCommitmentGate,
    this.voteWireJsonGate,
    this.voteCommitmentErrorsByKey = const {},
    this.failingVoteConfirmationKeys = const {},
    this.onDeleteSkippedBundles,
    this.keystoneDelegationRequestFailuresByCall = const {},
    this.failingVoteTreeNodeUrls = const {},
    this.keystoneSignatureBatchFailuresRemaining = 0,
    this.shareResubmissionError,
    this.nextShareTrackingDelayGate,
    this.trackingPassPolicyGate,
    this.helperPreflightGate,
    this.focusedShareConfirmationGate,
    this.failingVoteShareWireIndexes = const {},
    this.failingRecordShareIndexes = const {},
    this.ambiguousShareServerUrls = const {},
    this.initialShareSubmissionReport,
    this.prepareCommittedShareDeliveryError,
    this.onShareConfirmed,
    this.recoveredShareOrder,
    this.helperPostTimeoutMilliseconds = 30000,
    this.initialDeliveryTimeoutMilliseconds = 60000,
    this.maxConcurrentHelperPosts = 16,
  });

  final Duration setupDelay;
  final Completer<void>? setupGate;
  final bool emitCommitments;
  final List<List<int>> generatedHotkeys;
  final Completer<void>? hotkeyGenerationGate;
  final Completer<void>? precomputeGate;
  final bool failPrecompute;
  final int bundleCount;
  int setupEligibleWeight;
  final int eligibilityDistinctNoteCount;
  final bool? eligibilityEligible;
  final int commitmentShareCount;
  final bool mismatchKeystoneSubmission;
  final Object? delegationStreamError;
  final Map<int, Object> delegationStreamErrorsByBundle;
  final Map<int, Object> keystoneDelegationStreamErrorsByBundle;
  final Set<int> recoveredDelegationBundleIndices;
  final void Function(int bundleIndex, String txHash, int vanLeafPosition)?
  onDelegationConfirmed;
  final Completer<void>? delegationProofGate;
  final Completer<void>? keystoneDelegationProofGate;
  final Completer<void>? delegationWireJsonGate;
  final Completer<void>? voteCommitmentGate;
  final Completer<void>? voteWireJsonGate;
  final Map<String, Object> voteCommitmentErrorsByKey;
  final Set<String> failingVoteConfirmationKeys;
  final void Function(int keepCount)? onDeleteSkippedBundles;
  final Map<int, Object> keystoneDelegationRequestFailuresByCall;
  final Set<String> failingVoteTreeNodeUrls;
  int keystoneSignatureBatchFailuresRemaining;
  final Object? shareResubmissionError;
  final Completer<void>? nextShareTrackingDelayGate;
  final Completer<void>? trackingPassPolicyGate;
  final Completer<void>? helperPreflightGate;
  final Completer<void>? focusedShareConfirmationGate;
  final Set<int> failingVoteShareWireIndexes;
  final Set<int> failingRecordShareIndexes;
  final Set<String> ambiguousShareServerUrls;
  final rust_api.ApiShareSubmissionReport? initialShareSubmissionReport;
  final Object? prepareCommittedShareDeliveryError;
  final void Function(int bundleIndex, int proposalId, int shareIndex)?
  onShareConfirmed;
  final List<int>? recoveredShareOrder;
  final int helperPostTimeoutMilliseconds;
  final int initialDeliveryTimeoutMilliseconds;
  final int maxConcurrentHelperPosts;
  var _chainOperationEpoch = 1;
  final Map<int, String> _delegationAttemptHashes = {};
  final Map<String, String> _voteAttemptHashes = {};

  @override
  BigInt beginVotingChainOperation() => BigInt.from(_chainOperationEpoch);

  @override
  void cancelVotingChainOperations() => _chainOperationEpoch++;

  bool _chainOperationCancelled(BigInt epoch) =>
      epoch != BigInt.from(_chainOperationEpoch);
  int setupCalls = 0;
  int _activeSetups = 0;
  int maxConcurrentSetups = 0;
  int _activeDelegationProofs = 0;
  int maxConcurrentDelegationProofs = 0;
  int _activeKeystoneDelegationProofs = 0;
  int maxConcurrentKeystoneDelegationProofs = 0;
  int _activeVoteCommitments = 0;
  int maxConcurrentVoteCommitments = 0;
  final delegationBundleCalls = <int>[];
  final delegationPirServerUrlBatches = <List<String>>[];
  final delegationMnemonics = <String>[];
  final voteCommitBundleCalls = <int>[];
  final voteCommitmentKeys = <String>[];
  final recoveredVoteCommitmentKeys = <String>[];
  final storedDelegationTxHashes = <String>[];
  final storedVoteTxHashes = <String>[];
  final storedCommitmentBundles = <String>[];
  final Map<String, BigInt> _confirmedVotePositions = {};
  final Map<String, int> _committedShareCounts = {};
  final storedVanPositions = <String>[];
  final operationLog = <String>[];
  final recordedShares = <_RecordedShare>[];
  final recordShareAttempts = <int>[];
  final syncedVoteTrees = <String>[];
  final syncedVoteTreeNodeUrls = <String>[];
  final snapshotBundlePrecomputeAccounts = <String>[];
  final warmPirProofCacheAccountUuids = <String>[];
  final warmPirProofCacheSnapshotHeights = <int>[];
  final warmPirProofCacheKeepRoots = <List<List<int>>>[];
  final warmPirProofCachePirServerUrls = <String>[];
  final warmPirProofCacheStarted = Completer<void>();
  Completer<void>? warmPirProofCacheGate;
  Object? warmPirProofCacheError;
  Uint8List? warmPirProofCacheServedRoot;
  final delegationStoredHotkeySecrets = <List<int>>[];
  final delegationRecoveryStoredHotkeySecrets = <List<int>>[];
  int delegationRecoveryCalls = 0;
  int warmVotingProvingCachesCalls = 0;
  final setupStarted = Completer<void>();
  final delegationProofStarted = Completer<void>();
  final keystoneDelegationProofStarted = Completer<void>();
  final delegationWireJsonStarted = Completer<void>();
  final voteCommitmentStarted = Completer<void>();
  final voteWireJsonStarted = Completer<void>();
  final hotkeyGenerationStarted = Completer<void>();
  final precomputeStarted = Completer<void>();
  final precomputeFinished = Completer<void>();
  final nextShareTrackingDelayStarted = Completer<void>();
  final trackingPassPolicyStarted = Completer<void>();
  final helperPreflightStarted = Completer<void>();
  final focusedShareConfirmationStarted = Completer<void>();
  final resetVoteTreeCalls = <String>[];
  final resetVotingSessionStateCalls = <String>[];
  final draftSingleShareValues = <bool>[];
  final planLastMomentBufferSeconds = <BigInt?>[];
  final planSingleShareValues = <bool>[];
  final planImmediateShareIndexes = <int?>[];
  final planProposalIdRosters = <List<int>>[];
  final plannedSharePlans = <_FakeSharePlan>[];
  final submittedSharePlans = <_FakeSharePlan>[];
  final _preparedShareDeliveries = <String, _FakePreparedShareDelivery>{};
  final accountUuids = <String>[];
  final confirmedShares = <String>[];
  final eligibilityAccountUuids = <String>[];
  final keystoneDelegationRequestCalls = <int>[];
  final keystoneProofBundleCalls = <int>[];
  final keystonePirServerUrlBatches = <List<String>>[];
  final deleteSkippedBundleKeepCounts = <int>[];
  final storedKeystoneSignatures = <int, rust_wire.KeystoneSignatureRecord>{};
  rust_wire.VotingRoundParams? lastTrustedRoundParams;
  rust_wire.VotingRoundParams? lastSetupRoundParams;
  rust_config.PirLayout? lastPirLayout;
  int trustedRoundParamsCalls = 0;
  int eligibilityCheckCalls = 0;
  BigInt privacyTrimDroppedValueZatoshi = BigInt.zero;
  int generateVotingHotkeyCalls = 0;
  int extractSpendAuthSignatureCalls = 0;

  @override
  String? selectPirSnapshotEndpoint({
    required List<rust_api.ApiPirSnapshotEndpointDiagnostic> diagnostics,
    required BigInt expectedSnapshotHeight,
    required BigInt matchIndex,
  }) {
    final matches = diagnostics
        .where(
          (diagnostic) =>
              diagnostic.status ==
                  rust_api.ApiPirSnapshotEndpointStatus.matched &&
              diagnostic.reportedHeight == expectedSnapshotHeight,
        )
        .map((diagnostic) => diagnostic.endpoint)
        .toList(growable: false);
    return matches.isEmpty
        ? null
        : matches[matchIndex.toInt() % matches.length];
  }

  // --- Vote authority note (VAN) model -------------------------------------
  //
  // A cast vote spends the bundle's VAN: the proof binds the bundle's current
  // proposal-authority mask and VAN leaf position, submission clears that
  // proposal's bit, and confirmation appends the replacement leaf. Two votes on
  // one bundle proved against the same state share a `van_nullifier`, so the
  // second is a double spend. The fake reproduces that so the provider's
  // ordering is checked here instead of on-chain.
  static const int _fullProposalAuthority = 0xFFFE; // bit 0 is the sentinel
  final Map<int, int> _bundleAuthority = <int, int>{};
  final Map<int, int> _bundleVanPosition = <int, int>{};
  final Map<int, int> _bundleMinAnchor = <int, int>{};
  final Map<String, int> _capturedAuthority = <String, int>{};
  final Map<String, int> _capturedVanPosition = <String, int>{};
  int _voteTreeAnchor = 10;
  int _nextVanPosition = 1000;
  int _activeVoteTreeSyncs = 0;
  int maxConcurrentVoteTreeSyncs = 0;

  int _authorityFor(int bundleIndex) =>
      _bundleAuthority[bundleIndex] ?? _fullProposalAuthority;

  int _vanPositionFor(int bundleIndex) =>
      _bundleVanPosition[bundleIndex] ?? bundleIndex;

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
  Future<rust_api.ApiBundleLayout> setupDelegationBundles({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    lastSetupRoundParams = ctx.roundParams;
    lastPirLayout = ctx.pirLayout;
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
    return rust_api.ApiBundleLayout(
      bundleCount: bundleCount,
      eligibleWeight: BigInt.from(setupEligibleWeight),
      droppedCount: 0,
      privacyTrimDroppedBundles: 0,
      privacyTrimDroppedNotes: 0,
      privacyTrimDroppedValueZatoshi: privacyTrimDroppedValueZatoshi,
    );
  }

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    eligibilityCheckCalls++;
    eligibilityAccountUuids.add(ctx.accountUuid);
    return rust_api.ApiVotingEligibility(
      isEligible: eligibilityEligible ?? setupEligibleWeight > 0,
      distinctNoteCount: eligibilityDistinctNoteCount,
      eligibleWeightZatoshi: BigInt.from(setupEligibleWeight),
      privacyTrimDroppedValueZatoshi: privacyTrimDroppedValueZatoshi,
    );
  }

  @override
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required String mnemonic,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) async* {
    accountUuids.add(ctx.accountUuid);
    delegationBundleCalls.add(bundleIndex);
    delegationPirServerUrlBatches.add(List<String>.from(pirServerUrls));
    delegationMnemonics.add(mnemonic);
    delegationStoredHotkeySecrets.add(List<int>.from(storedHotkeySecret));
    _activeDelegationProofs++;
    if (_activeDelegationProofs > maxConcurrentDelegationProofs) {
      maxConcurrentDelegationProofs = _activeDelegationProofs;
    }
    try {
      final error =
          delegationStreamErrorsByBundle[bundleIndex] ?? delegationStreamError;
      if (error != null) throw error;
      if (!delegationProofStarted.isCompleted) {
        delegationProofStarted.complete();
      }
      yield const rust_api.ApiDelegationProofEvent(
        phase: 'proving',
        proofProgress: 0.1,
        signedDelegationPayload: null,
      );
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
            tx1Effects: base64Encode(const [4]),
            nfSigned: base64Encode(const [5]),
            cmxNew: base64Encode(const [6]),
            govComm: base64Encode(const [7]),
            govNullifiers: [
              base64Encode(const [8]),
            ],
            proof: base64Encode(const [1]),
            voteRoundId: base64Encode(
              _bytesFromHex(ctx.roundParams.voteRoundId),
            ),
          ),
          eligibleWeightZatoshi: BigInt.from(100),
          delegatedWeightZatoshi: BigInt.from(100),
          bundleCount: bundleCount,
          bundleIndex: bundleIndex,
        ),
      );
    } finally {
      _activeDelegationProofs--;
    }
  }

  @override
  Future<List<int>> generateVotingHotkey({required String network}) async {
    final callIndex = generateVotingHotkeyCalls++;
    if (!hotkeyGenerationStarted.isCompleted) {
      hotkeyGenerationStarted.complete();
    }
    await hotkeyGenerationGate?.future;
    final hotkeyIndex = callIndex < generatedHotkeys.length
        ? callIndex
        : generatedHotkeys.length - 1;
    return List<int>.from(generatedHotkeys[hotkeyIndex]);
  }

  Future<rust_delegate.KeystoneSigningRequest> _buildKeystoneDelegationRequest({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) async {
    final callIndex = keystoneDelegationRequestCalls.length;
    accountUuids.add(ctx.accountUuid);
    keystoneDelegationRequestCalls.add(bundleIndex);
    final forcedFailure = keystoneDelegationRequestFailuresByCall[callIndex];
    if (forcedFailure != null) {
      throw forcedFailure;
    }
    return rust_delegate.KeystoneSigningRequest(
      pcztBytes: Uint8List.fromList([20, bundleIndex]),
      redactedPcztBytes: Uint8List.fromList([21, bundleIndex]),
      pcztSighash: Uint8List.fromList([10, bundleIndex]),
      rk: Uint8List.fromList([2, bundleIndex]),
      actionIndex: 0,
      displayMemo:
          'I am authorizing this hotkey managed by my wallet to vote on ${ctx.roundName}.\nAmount: 0.00000100 ZEC.',
      eligibleWeightZatoshi: BigInt.from(100),
      delegatedWeightZatoshi: BigInt.from(100),
      bundleCount: bundleCount,
      bundleIndex: bundleIndex,
    );
  }

  @override
  Future<List<rust_delegate.KeystoneSigningRequest>>
  buildKeystoneDelegationRequests({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> storedHotkeySecret,
    required List<int> bundleIndices,
  }) async {
    final requests = <rust_delegate.KeystoneSigningRequest>[];
    for (final bundleIndex in bundleIndices) {
      requests.add(
        await _buildKeystoneDelegationRequest(
          ctx: ctx,
          storedHotkeySecret: storedHotkeySecret,
          bundleIndex: bundleIndex,
        ),
      );
    }
    return requests;
  }

  @override
  Future<rust_api.ApiKeystoneSignatureBatchResult>
  storeKeystoneSignaturesBatch({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<rust_api.ApiKeystoneSignatureInput> signatures,
  }) async {
    if (keystoneSignatureBatchFailuresRemaining > 0) {
      keystoneSignatureBatchFailuresRemaining--;
      throw StateError('injected Keystone signature batch failure');
    }
    var inserted = 0;
    var alreadyPresent = 0;
    final next = Map<int, rust_wire.KeystoneSignatureRecord>.from(
      storedKeystoneSignatures,
    );
    for (final signature in signatures) {
      final existing = next[signature.bundleIndex];
      if (existing != null) {
        if (!listEquals(existing.sighash, signature.sighash) ||
            !listEquals(existing.rk, signature.rk)) {
          return rust_api.ApiKeystoneSignatureBatchResult(
            inserted: 0,
            alreadyPresent: 0,
            conflictingBundleIndex: signature.bundleIndex,
          );
        }
        alreadyPresent++;
        continue;
      }
      next[signature.bundleIndex] = rust_wire.KeystoneSignatureRecord(
        bundleIndex: signature.bundleIndex,
        sig: Uint8List.fromList(signature.sig),
        sighash: Uint8List.fromList(signature.sighash),
        rk: Uint8List.fromList(signature.rk),
      );
      inserted++;
    }
    storedKeystoneSignatures
      ..clear()
      ..addAll(next);
    return rust_api.ApiKeystoneSignatureBatchResult(
      inserted: inserted,
      alreadyPresent: alreadyPresent,
      conflictingBundleIndex: null,
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
    required List<String> pirServerUrls,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
  }) async* {
    accountUuids.add(ctx.accountUuid);
    keystoneProofBundleCalls.add(bundleIndex);
    keystonePirServerUrlBatches.add(List<String>.from(pirServerUrls));
    _activeKeystoneDelegationProofs++;
    if (_activeKeystoneDelegationProofs >
        maxConcurrentKeystoneDelegationProofs) {
      maxConcurrentKeystoneDelegationProofs = _activeKeystoneDelegationProofs;
    }
    try {
      if (!keystoneDelegationProofStarted.isCompleted) {
        keystoneDelegationProofStarted.complete();
      }
      yield const rust_api.ApiDelegationProofEvent(
        phase: 'proving',
        proofProgress: 0.1,
        signedDelegationPayload: null,
      );
      await keystoneDelegationProofGate?.future;
      final error = keystoneDelegationStreamErrorsByBundle[bundleIndex];
      if (error != null) throw error;
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
            tx1Effects: base64Encode(keystoneSighash),
            nfSigned: base64Encode(const [5]),
            cmxNew: base64Encode(const [6]),
            govComm: base64Encode(const [7]),
            govNullifiers: [
              base64Encode(const [8]),
            ],
            proof: base64Encode(const [1]),
            voteRoundId: base64Encode(
              _bytesFromHex(ctx.roundParams.voteRoundId),
            ),
          ),
          eligibleWeightZatoshi: BigInt.from(100),
          delegatedWeightZatoshi: BigInt.from(100),
          bundleCount: bundleCount,
          bundleIndex: bundleIndex,
        ),
      );
    } finally {
      _activeKeystoneDelegationProofs--;
    }
  }

  @override
  Future<String> delegationSubmissionWireJson({
    required rust_wire.SignedDelegationPayloadView submission,
  }) async {
    final gate = delegationWireJsonGate;
    if (gate != null) {
      if (!delegationWireJsonStarted.isCompleted) {
        delegationWireJsonStarted.complete();
      }
      await gate.future;
    }
    final wire = submission.submission;
    return jsonEncode({
      'rk': wire.rk,
      'spend_auth_sig': wire.spendAuthSig,
      'tx1_effects': wire.tx1Effects,
      'signed_note_nullifier': wire.nfSigned,
      'cmx_new': wire.cmxNew,
      'van_cmx': wire.govComm,
      'gov_nullifiers': wire.govNullifiers,
      'proof': wire.proof,
      'vote_round_id': wire.voteRoundId,
    });
  }

  @override
  Future<rust_api.ApiChainSubmissionOutcome> submitChainDelegation({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required rust_wire.SignedDelegationPayloadView submission,
    required List<String> apiServerUrls,
    required BigInt operationEpoch,
  }) async {
    final body =
        jsonDecode(await delegationSubmissionWireJson(submission: submission))
            as Map<String, dynamic>;
    if (_chainOperationCancelled(operationEpoch)) {
      return _cancelledChainOutcome();
    }
    final response = await helperTransport!.postJson(
      Uri.parse('${apiServerUrls.first}/shielded-vote/v1/delegate-vote'),
      body,
    );
    final result = VotingTxResult.fromJson(
      jsonDecode(response.bodyText) as Map<String, dynamic>,
    );
    if (result.code != 0) {
      if (result.txHash.isNotEmpty) {
        _delegationAttemptHashes[bundleIndex] = result.txHash;
      }
      return rust_api.ApiChainSubmissionOutcome(
        status: result.log.toLowerCase().contains('nullifier already spent:')
            ? 'already_spent_unresolved'
            : 'rejected',
        txHash: null,
        knownTxHashes: result.txHash.isEmpty ? const [] : [result.txHash],
        code: result.code,
        message: result.log,
        vanLeafPosition: null,
        vcTreePosition: null,
      );
    }
    await markDelegationSubmitted(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      txHash: result.txHash,
    );
    return _acceptedChainOutcome(result.txHash);
  }

  @override
  Future<rust_api.ApiChainSubmissionOutcome> reconcileChainDelegation({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required List<String> apiServerUrls,
    required BigInt operationEpoch,
  }) async {
    final prefix = '$bundleIndex:';
    final stored = storedDelegationTxHashes
        .where((value) => value.startsWith(prefix))
        .lastOrNull;
    final txHash =
        stored?.substring(prefix.length) ??
        _delegationAttemptHashes[bundleIndex] ??
        helperRecoveryApi?.state.delegation
            .where((value) => value.bundleIndex == bundleIndex)
            .map((value) => value.txHash)
            .nonNulls
            .lastOrNull;
    if (txHash == null) return _pendingChainOutcome('');
    final response = await helperTransport!.get(
      Uri.parse('${apiServerUrls.first}/shielded-vote/v1/tx/$txHash'),
    );
    if (_chainOperationCancelled(operationEpoch)) {
      return _cancelledChainOutcome();
    }
    if (response.statusCode == 404) return _pendingChainOutcome(txHash);
    final confirmation = VotingTxConfirmation.fromJson(
      jsonDecode(response.bodyText) as Map<String, dynamic>,
    );
    if (confirmation.code != 0) {
      return _rejectedChainOutcome(confirmation.code, confirmation.log);
    }
    final recorded = await confirmDelegationSubmission(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      txHash: txHash,
      eventsJson: confirmation.eventsJson,
    );
    return rust_api.ApiChainSubmissionOutcome(
      status: 'confirmed',
      txHash: txHash,
      knownTxHashes: [txHash],
      code: 0,
      message: null,
      vanLeafPosition: recorded.vanLeafPosition,
      vcTreePosition: null,
    );
  }

  @override
  Future<List<int>> recoverConfirmedDelegations({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> storedHotkeySecret,
    required List<String> apiServerUrls,
    required BigInt operationEpoch,
  }) async {
    delegationRecoveryCalls++;
    delegationRecoveryStoredHotkeySecrets.add(
      List<int>.from(storedHotkeySecret),
    );
    final recovered = recoveredDelegationBundleIndices.toList()..sort();
    final recovery = helperRecoveryApi;
    if (recovery != null) {
      recovery.state = _withRecoveredDelegations(recovery.state, recovered);
    }
    return recovered;
  }

  @override
  Future<rust_api.ApiSnapshotBundlePrecomputeResult> precomputeSnapshotBundles({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
  }) async {
    accountUuids.add(ctx.accountUuid);
    snapshotBundlePrecomputeAccounts.add(ctx.accountUuid);
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
    return rust_api.ApiSnapshotBundlePrecomputeResult(
      bundleCount: bundleCount,
      eligibleWeight: BigInt.from(setupEligibleWeight),
      droppedCount: 0,
      privacyTrimDroppedBundles: 0,
      privacyTrimDroppedNotes: 0,
      privacyTrimDroppedValueZatoshi: BigInt.zero,
      bundles: List.generate(
        bundleCount,
        (_) => const rust_api.ApiSnapshotBundlePirResult(
          cachedCount: 0,
          fetchedCount: 1,
        ),
      ),
    );
  }

  @override
  Future<rust_api.ApiPirCacheWarmupResult> warmPirProofCache({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String lightwalletdUrl,
    required BigInt snapshotHeight,
    required String pirServerUrl,
    required rust_config.PirLayout pirLayout,
    required List<Uint8List> keepRoots,
  }) async {
    warmPirProofCacheAccountUuids.add(accountUuid);
    warmPirProofCacheSnapshotHeights.add(snapshotHeight.toInt());
    warmPirProofCacheKeepRoots.add(
      keepRoots.map((root) => List<int>.from(root)).toList(),
    );
    warmPirProofCachePirServerUrls.add(pirServerUrl);
    if (!warmPirProofCacheStarted.isCompleted) {
      warmPirProofCacheStarted.complete();
    }
    await warmPirProofCacheGate?.future;
    final error = warmPirProofCacheError;
    if (error != null) throw error;
    return rust_api.ApiPirCacheWarmupResult(
      noteCount: 2,
      cachedCount: 0,
      fetchedCount: 2,
      servedRoot:
          warmPirProofCacheServedRoot ??
          Uint8List.fromList(List<int>.filled(32, 3)),
      prunedCount: 0,
    );
  }

  @override
  void warmVotingProvingCaches() {
    warmVotingProvingCachesCalls++;
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
    _addUnique(storedVanPositions, '$bundleIndex:$vanLeafPosition');
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
    final alreadyConfirmed = storedVanPositions.contains(
      '$bundleIndex:$vanLeafPosition',
    );
    _recordDelegationConfirmed(
      bundleIndex: bundleIndex,
      txHash: txHash,
      vanLeafPosition: vanLeafPosition,
    );
    if (!alreadyConfirmed) {
      onDelegationConfirmed?.call(bundleIndex, txHash, vanLeafPosition);
    }
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
    syncedVoteTreeNodeUrls.add(nodeUrl);
    _activeVoteTreeSyncs++;
    if (_activeVoteTreeSyncs > maxConcurrentVoteTreeSyncs) {
      maxConcurrentVoteTreeSyncs = _activeVoteTreeSyncs;
    }
    try {
      // Yield so overlapping syncs would actually be observable; failover
      // resets round-global state, so the provider must never allow one.
      await Future<void>.delayed(Duration.zero);
      if (failingVoteTreeNodeUrls.contains(nodeUrl)) {
        throw StateError('syncVoteTree failed for $nodeUrl');
      }
      return ++_voteTreeAnchor;
    } finally {
      _activeVoteTreeSyncs--;
    }
  }

  @override
  Future<rust_vote.VanWitness> generateVanWitness({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  }) async {
    final minAnchor = _bundleMinAnchor[bundleIndex];
    if (minAnchor != null && anchorHeight < minAnchor) {
      throw StateError(
        'vote tree witness for bundle $bundleIndex is stale: anchor '
        '$anchorHeight predates this bundle\'s last cast-vote confirmation',
      );
    }
    return rust_vote.VanWitness(
      authPath: const [],
      position: _vanPositionFor(bundleIndex),
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
  Future<void> resetVoteTree({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {
    resetVoteTreeCalls.add('$accountUuid:${roundId ?? '*'}');
  }

  @override
  Stream<rust_api.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> storedHotkeySecret,
    required rust_vote.VanWitness vanWitness,
    required List<rust_wire.DraftVote> draftVotes,
  }) async* {
    voteCommitBundleCalls.add(bundleIndex);
    _activeVoteCommitments++;
    if (_activeVoteCommitments > maxConcurrentVoteCommitments) {
      maxConcurrentVoteCommitments = _activeVoteCommitments;
    }
    try {
      if (!voteCommitmentStarted.isCompleted) {
        voteCommitmentStarted.complete();
      }
      for (final draft in draftVotes) {
        yield rust_api.ApiVoteCommitEvent(
          phase: 'proving',
          proposalId: draft.proposalId,
          bundleIndex: bundleIndex,
          proofProgress: 0.1,
          commitments: null,
        );
      }
      await voteCommitmentGate?.future;
      for (final draft in draftVotes) {
        final key = '$bundleIndex:${draft.proposalId}';
        final error = voteCommitmentErrorsByKey[key];
        if (error != null) throw error;
        if (vanWitness.position != _vanPositionFor(bundleIndex)) {
          throw StateError(
            'VAN witness position ${vanWitness.position} does not match '
            'current bundle position ${_vanPositionFor(bundleIndex)} for '
            'bundle $bundleIndex',
          );
        }
        final minAnchor = _bundleMinAnchor[bundleIndex];
        if (minAnchor != null && vanWitness.anchorHeight < minAnchor) {
          throw StateError(
            'vote tree witness for bundle $bundleIndex is stale: anchor '
            '${vanWitness.anchorHeight} predates this bundle\'s last '
            'cast-vote confirmation',
          );
        }
        // Snapshot the state this proof binds; submission re-checks it.
        _capturedAuthority[key] = _authorityFor(bundleIndex);
        _capturedVanPosition[key] = _vanPositionFor(bundleIndex);
        voteCommitmentKeys.add(key);
        operationLog.add('build_vote:$key');
        draftSingleShareValues.add(draft.singleShare);
        final committedShareCount = draft.singleShare
            ? 1
            : commitmentShareCount;
        _committedShareCounts[key] = committedShareCount;
        final commitments = emitCommitments
            ? _commitments(
                roundId: roundId,
                bundleIndex: bundleIndex,
                proposalId: draft.proposalId,
                choice: draft.choice,
                shareCount: committedShareCount,
              )
            : null;
        yield rust_api.ApiVoteCommitEvent(
          phase: 'result',
          proposalId: draft.proposalId,
          bundleIndex: bundleIndex,
          proofProgress: null,
          commitments: commitments,
        );
      }
    } finally {
      _activeVoteCommitments--;
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
    final commitments = _commitments(
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      choice: 1,
      shareCount: commitmentShareCount,
      shareOrder: recoveredShareOrder,
    );
    _committedShareCounts['$bundleIndex:$proposalId'] = commitmentShareCount;
    return commitments;
  }

  @override
  Future<String> voteCommitmentWireJson({
    required rust_wire.VoteCommitmentWire commitment,
  }) async {
    final gate = voteWireJsonGate;
    if (gate != null) {
      if (!voteWireJsonStarted.isCompleted) voteWireJsonStarted.complete();
      await gate.future;
    }
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
  Future<rust_api.ApiChainSubmissionOutcome> submitChainVote({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required List<String> apiServerUrls,
    required BigInt operationEpoch,
  }) async {
    final wire = _commitments(
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      choice: 1,
      shareCount: commitmentShareCount,
    ).commitments.single.wire;
    final body =
        jsonDecode(await voteCommitmentWireJson(commitment: wire))
            as Map<String, dynamic>;
    if (_chainOperationCancelled(operationEpoch)) {
      return _cancelledChainOutcome();
    }
    final response = await helperTransport!.postJson(
      Uri.parse('${apiServerUrls.first}/shielded-vote/v1/cast-vote'),
      body,
    );
    final result = VotingTxResult.fromJson(
      jsonDecode(response.bodyText) as Map<String, dynamic>,
    );
    if (result.code != 0) {
      if (result.txHash.isNotEmpty) {
        _voteAttemptHashes['$bundleIndex:$proposalId'] = result.txHash;
      }
      return rust_api.ApiChainSubmissionOutcome(
        status: result.log.toLowerCase().contains('nullifier already spent:')
            ? 'already_spent_unresolved'
            : 'rejected',
        txHash: null,
        knownTxHashes: result.txHash.isEmpty ? const [] : [result.txHash],
        code: result.code,
        message: result.log,
        vanLeafPosition: null,
        vcTreePosition: null,
      );
    }
    await markVoteSubmitted(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      txHash: result.txHash,
    );
    return _acceptedChainOutcome(result.txHash);
  }

  @override
  Future<rust_api.ApiChainSubmissionOutcome> reconcileChainVote({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required List<String> apiServerUrls,
    required BigInt operationEpoch,
  }) async {
    final prefix = '$bundleIndex:$proposalId:';
    final stored = storedVoteTxHashes
        .where((value) => value.startsWith(prefix))
        .lastOrNull;
    final txHash =
        stored?.substring(prefix.length) ??
        _voteAttemptHashes['$bundleIndex:$proposalId'] ??
        helperRecoveryApi?.state.votes
            .where(
              (value) =>
                  value.bundleIndex == bundleIndex &&
                  value.proposalId == proposalId,
            )
            .map((value) => value.txHash)
            .nonNulls
            .lastOrNull;
    if (txHash == null) return _pendingChainOutcome('');
    final response = await helperTransport!.get(
      Uri.parse('${apiServerUrls.first}/shielded-vote/v1/tx/$txHash'),
    );
    if (_chainOperationCancelled(operationEpoch)) {
      return _cancelledChainOutcome();
    }
    if (response.statusCode == 404) return _pendingChainOutcome(txHash);
    final confirmation = VotingTxConfirmation.fromJson(
      jsonDecode(response.bodyText) as Map<String, dynamic>,
    );
    if (confirmation.code != 0) {
      return _rejectedChainOutcome(confirmation.code, confirmation.log);
    }
    final recorded = await confirmVoteSubmission(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      txHash: txHash,
      eventsJson: confirmation.eventsJson,
    );
    return rust_api.ApiChainSubmissionOutcome(
      status: 'confirmed',
      txHash: txHash,
      knownTxHashes: [txHash],
      code: 0,
      message: null,
      vanLeafPosition: recorded.vanLeafPosition,
      vcTreePosition: recorded.vcTreePosition,
    );
  }

  @override
  BigInt? lastMomentBufferSeconds({
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  }) {
    final duration = voteEndTimeSeconds - ceremonyStartSeconds;
    if (duration <= BigInt.zero) return null;
    final buffer =
        ((duration * BigInt.from(2)) + BigInt.from(4)) ~/ BigInt.from(5);
    final max = BigInt.from(6 * 60 * 60);
    return buffer < max ? buffer : max;
  }

  @override
  bool isLastMoment({
    required BigInt nowSeconds,
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  }) {
    final buffer = lastMomentBufferSeconds(
      ceremonyStartSeconds: ceremonyStartSeconds,
      voteEndTimeSeconds: voteEndTimeSeconds,
    );
    final deadline = buffer == null ? null : voteEndTimeSeconds - buffer;
    return deadline != null &&
        nowSeconds >= deadline &&
        nowSeconds < voteEndTimeSeconds;
  }

  /// Records tracking passes the session provider delegates to the crate.
  ///
  /// Helper protocol behavior itself is covered by `zcash_voting`'s own tests;
  /// what matters here is that Dart starts, cancels, and reacts to a pass.
  final trackPendingSharesCalls = <String>[];
  final focusedShareConfirmationCalls = <String>[];
  Completer<void>? trackPendingSharesGate;
  final trackPendingSharesStarted = Completer<void>();
  final helperDeliveryContexts = <_FakeVotingHelperDeliveryContext>[];
  final preflightDeliveryContexts = <VotingHelperDeliveryContext>[];
  final preflightConfiguredHelperUrls = <List<String>>[];
  final initialDeliveryContexts = <VotingHelperDeliveryContext>[];
  final shareTrackingPassHandles = <_FakeVotingShareTrackingPassHandle>[];
  rust_api.ApiShareTrackingReport Function()? trackPendingSharesResult;

  /// Transport used to keep helper requests observable from Dart tests.
  ///
  /// Production helper traffic is made by the crate over its own transport, so
  /// this exists only so provider tests can still assert on request shape and
  /// ordering. It deliberately implements no health or retry policy — those
  /// belong to `zcash_voting` and are tested there.
  FakeVotingHttpClient? helperTransport;

  /// Recovery double whose share rows a tracking pass advances.
  FakeVotingRecoveryApi? helperRecoveryApi;

  @override
  Future<bool> confirmShareWithHelpers({
    required VotingShareTrackingPassHandle passHandle,
    required List<String> configuredHelperUrls,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required BigInt nowSeconds,
  }) async {
    final context = (passHandle as _FakeVotingShareTrackingPassHandle).context;
    focusedShareConfirmationCalls.add('$bundleIndex:$proposalId:$shareIndex');
    if (!focusedShareConfirmationStarted.isCompleted) {
      focusedShareConfirmationStarted.complete();
    }
    await focusedShareConfirmationGate?.future;
    if (passHandle.isCancelled) return false;
    final recovery = helperRecoveryApi;
    final transport = helperTransport;
    if (recovery == null || transport == null) return false;
    final share = recovery.state.shareDelegations
        .where(
          (record) =>
              record.bundleIndex == bundleIndex &&
              record.proposalId == proposalId &&
              record.shareIndex == shareIndex,
        )
        .firstOrNull;
    if (share == null) {
      throw StateError('focused helper share not found');
    }
    if (share.confirmed) return true;

    final shareId = share.nullifier
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final quorum = configuredHelperUrls.length == 1 ? 1 : 2;
    var confirmations = 0;
    for (final helperUrl in configuredHelperUrls) {
      if (passHandle.isCancelled) return false;
      try {
        final response = await transport.get(
          Uri.parse(
            '$helperUrl/shielded-vote/v1/share-status/'
            '${passHandle.roundId}/$shareId',
          ),
        );
        final status = (jsonDecode(response.bodyText) as Map)['status'];
        if (status == 'confirmed') confirmations++;
      } catch (_) {
        // Mirrors the production API: unusable helper responses do not make
        // the focused quorum check itself fail.
      }
      if (confirmations >= quorum) {
        await _markShareConfirmed(
          dbPath: context.dbPath,
          accountUuid: passHandle.accountUuid,
          roundId: passHandle.roundId,
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          shareIndex: shareIndex,
        );
        return true;
      }
    }
    return false;
  }

  @override
  Future<rust_api.ApiShareTrackingReport> trackPendingShares({
    required VotingShareTrackingPassHandle passHandle,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  }) async {
    final context = (passHandle as _FakeVotingShareTrackingPassHandle).context;
    final dbPath = context.dbPath;
    final accountUuid = passHandle.accountUuid;
    final roundId = passHandle.roundId;
    bool isCancelled() => passHandle.isCancelled;
    trackPendingSharesCalls.add(roundId);
    if (!trackPendingSharesStarted.isCompleted) {
      trackPendingSharesStarted.complete();
    }
    await trackPendingSharesGate?.future;
    final failure = shareResubmissionError;
    if (failure != null) throw failure;
    final build = trackPendingSharesResult;
    if (build != null) return build();

    final recovery = helperRecoveryApi;
    final transport = helperTransport;
    if (recovery == null || transport == null) {
      return rust_api.ApiShareTrackingReport(
        confirmed: const [],
        resubmitted: const [],
        ambiguous: const [],
        unrecoverable: const [],
        cancelled: isCancelled(),
        nextDelaySeconds: null,
      );
    }

    final durablyConfirmed = <rust_api.ApiShareKey>[];
    final resubmitted = <rust_api.ApiResubmittedShare>[];
    final stillUnconfirmed = <rust_frb_types.ShareDelegationRecordView>[];
    final configured = configuredHelperUrls.toSet();

    for (final share in recovery.state.unconfirmedShareDelegations) {
      if (isCancelled()) {
        stillUnconfirmed.add(share);
        continue;
      }
      final flags = await _trackingFlags(
        share: share,
        nowSeconds: nowSeconds,
        voteEndTimeSeconds: voteEndTimeSeconds,
      );
      final ready = (flags & 1) != 0;
      final overdue = (flags & 2) != 0;
      if (!ready && !overdue) {
        stillUnconfirmed.add(share);
        continue;
      }

      final accepted = share.sentToUrls.where(configured.contains).toList();
      final shareId = share.nullifier
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

      String? confirmingServerUrl;
      if (ready) {
        for (final helperUrl in configuredHelperUrls) {
          try {
            final response = await transport.get(
              Uri.parse(
                '$helperUrl/shielded-vote/v1/share-status/$roundId/$shareId',
              ),
            );
            final status =
                (jsonDecode(response.bodyText) as Map)['status'] as String?;
            if (status == 'confirmed') {
              confirmingServerUrl = helperUrl;
              break;
            }
          } catch (_) {
            // A helper that cannot answer is simply skipped here; scoring is
            // the crate's job and is tested there.
          }
        }
      }

      if (confirmingServerUrl != null) {
        final key = rust_api.ApiShareKey(
          bundleIndex: share.bundleIndex,
          proposalId: share.proposalId,
          shareIndex: share.shareIndex,
        );
        var corroborated = configuredHelperUrls.length == 1;
        for (final helperUrl in configuredHelperUrls) {
          if (helperUrl == confirmingServerUrl) continue;
          try {
            final response = await transport.get(
              Uri.parse(
                '$helperUrl/shielded-vote/v1/share-status/$roundId/$shareId',
              ),
            );
            final status =
                (jsonDecode(response.bodyText) as Map)['status'] as String?;
            if (status == 'confirmed') {
              corroborated = true;
              break;
            }
          } catch (_) {
            // A failed helper check does not fail the tracking pass.
          }
        }
        if (corroborated) {
          await _markShareConfirmed(
            dbPath: dbPath,
            accountUuid: accountUuid,
            roundId: share.roundId,
            bundleIndex: share.bundleIndex,
            proposalId: share.proposalId,
            shareIndex: share.shareIndex,
          );
          durablyConfirmed.add(key);
        } else {
          stillUnconfirmed.add(share);
        }
        continue;
      }

      if (overdue) {
        for (final helperUrl in configuredHelperUrls) {
          if (accepted.contains(helperUrl)) continue;
          try {
            await transport.postJson(
              Uri.parse('$helperUrl/shielded-vote/v1/shares'),
              <String, dynamic>{'share_index': share.shareIndex},
            );
            resubmitted.add(
              rust_api.ApiResubmittedShare(
                share: rust_api.ApiShareKey(
                  bundleIndex: share.bundleIndex,
                  proposalId: share.proposalId,
                  shareIndex: share.shareIndex,
                ),
                serverUrl: helperUrl,
              ),
            );
            await recovery.addSentServers(
              dbPath: dbPath,
              accountUuid: accountUuid,
              roundId: roundId,
              bundleIndex: share.bundleIndex,
              proposalId: share.proposalId,
              shareIndex: share.shareIndex,
              newUrls: [helperUrl],
            );
            break;
          } catch (_) {
            // Try the next helper.
          }
        }
      }
      stillUnconfirmed.add(share);
    }

    if (durablyConfirmed.isNotEmpty) {
      recovery.state = _withUnconfirmedShares(recovery.state, stillUnconfirmed);
    }

    return rust_api.ApiShareTrackingReport(
      confirmed: durablyConfirmed,
      resubmitted: resubmitted,
      ambiguous: const [],
      unrecoverable: const [],
      cancelled: isCancelled(),
      nextDelaySeconds: stillUnconfirmed.isEmpty ? null : BigInt.from(15),
    );
  }

  @override
  VotingHelperDeliveryContext createVotingHelperDeliveryContext({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) {
    final context = _FakeVotingHelperDeliveryContext(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );
    helperDeliveryContexts.add(context);
    return context;
  }

  @override
  VotingShareTrackingPassHandle beginShareTrackingPass({
    required VotingHelperDeliveryContext context,
  }) {
    final passHandle = _FakeVotingShareTrackingPassHandle(
      context: context,
      accountUuid: context.accountUuid,
      roundId: context.roundId,
      onCancel: () {
        final gate = trackPendingSharesGate;
        if (gate != null && !gate.isCompleted) gate.complete();
      },
    );
    shareTrackingPassHandles.add(passHandle);
    return passHandle;
  }

  @override
  Future<rust_api.ApiVotingHelperPreflight> preflightVotingHelpers({
    required VotingHelperDeliveryContext context,
    required List<String> configuredHelperUrls,
  }) async {
    preflightDeliveryContexts.add(context);
    preflightConfiguredHelperUrls.add(List.of(configuredHelperUrls));
    if (!helperPreflightStarted.isCompleted) {
      helperPreflightStarted.complete();
    }
    await helperPreflightGate?.future;
    if (configuredHelperUrls.isEmpty ||
        configuredHelperUrls.toSet().length != configuredHelperUrls.length) {
      throw ArgumentError('configured helper URLs must be nonempty and unique');
    }
    final transport = helperTransport;
    if (transport == null) {
      return rust_api.ApiVotingHelperPreflight(
        configuredHelperUrls: configuredHelperUrls,
        readyHelperUrls: configuredHelperUrls,
      );
    }
    final readiness = await Future.wait([
      for (final helperUrl in configuredHelperUrls)
        () async {
          try {
            final response = await transport.get(
              Uri.parse('$helperUrl/shielded-vote/v1/status'),
            );
            final status =
                (jsonDecode(response.bodyText) as Map)['status'] as String?;
            return status?.toLowerCase() == 'ok';
          } catch (_) {
            return false;
          }
        }(),
    ]);
    return rust_api.ApiVotingHelperPreflight(
      configuredHelperUrls: configuredHelperUrls,
      readyHelperUrls: [
        for (var index = 0; index < configuredHelperUrls.length; index++)
          if (readiness[index]) configuredHelperUrls[index],
      ],
    );
  }

  @override
  Future<void> prepareCommittedShareDelivery({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiVotingHelperPreflight preflight,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    required List<int> proposalIds,
    BigInt? lastMomentBufferSeconds,
  }) async {
    initialDeliveryContexts.add(context);
    final injectedError = prepareCommittedShareDeliveryError;
    if (injectedError != null) throw injectedError;
    final deliveryKey = '$bundleIndex:$proposalId';
    if (_preparedShareDeliveries.containsKey(deliveryKey)) return;
    planLastMomentBufferSeconds.add(lastMomentBufferSeconds);
    final shareCount =
        _committedShareCounts['$bundleIndex:$proposalId'] ??
        commitmentShareCount;
    final singleShare = shareCount == 1;
    planSingleShareValues.add(singleShare);
    planProposalIdRosters.add(List<int>.of(proposalIds));
    final immediateShareIndex =
        proposalIds.isNotEmpty &&
            proposalId ==
                proposalIds.reduce(
                  (left, right) => left < right ? left : right,
                ) &&
            bundleIndex == bundleCount - 1
        ? 0
        : null;
    planImmediateShareIndexes.add(immediateShareIndex);

    final ready = preflight.readyHelperUrls;
    final configured = preflight.configuredHelperUrls;
    final ranked = <String>[
      ...ready,
      for (final helper in configured)
        if (!ready.contains(helper)) helper,
    ];
    final targetCount = _fakeShareTargetCount(configured.length);
    final planningHelperCount =
        (ready.length < targetCount ? targetCount : ready.length).clamp(
          0,
          ranked.length,
        );
    final now = nowSeconds.toInt();
    final voteEnd = voteEndTimeSeconds.toInt();
    final buffer = lastMomentBufferSeconds?.toInt();
    final deadline = buffer == null ? now : voteEnd - buffer;
    final delayedSubmitAt = singleShare || buffer == null || deadline <= now
        ? BigInt.zero
        : BigInt.from(now + 1);
    final shareIndexes =
        recoveredShareOrder ?? List<int>.generate(shareCount, (index) => index);
    if (shareIndexes.any(failingVoteShareWireIndexes.contains)) {
      throw FormatException(
        "invalid vote share ${shareIndexes.firstWhere(failingVoteShareWireIndexes.contains)}",
      );
    }
    final plans = [
      for (final shareIndex in shareIndexes)
        _FakeSharePlan(
          immediate: immediateShareIndex == shareIndex,
          submitAt: immediateShareIndex == shareIndex
              ? BigInt.zero
              : delayedSubmitAt,
          targetCount: targetCount,
          targetServers: [
            for (var offset = 0; offset < targetCount; offset++)
              ranked[(shareIndex * targetCount + offset) % planningHelperCount],
          ],
        ),
    ];
    plannedSharePlans.addAll(plans);
    _preparedShareDeliveries[deliveryKey] = _FakePreparedShareDelivery(
      configuredHelperUrls: List<String>.of(configured),
      shareIndexes: List<int>.of(shareIndexes),
      plans: plans,
      legacyBestEffort: recoveredShareOrder != null,
    );
    operationLog.add('prepare_share_delivery:$bundleIndex:$proposalId');
  }

  @override
  Future<rust_api.ApiShareBatchDeliveryReport> submitPreparedSharesToHelpers({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
  }) async {
    final prepared = _preparedShareDeliveries['$bundleIndex:$proposalId'];
    if (prepared == null) {
      throw StateError(
        'missing prepared share delivery for $bundleIndex:$proposalId',
      );
    }
    if (!_sameStringList(prepared.configuredHelperUrls, configuredHelperUrls)) {
      throw StateError('configured helper fleet changed after planning');
    }
    final configured = prepared.configuredHelperUrls;
    final shareIndexes = prepared.shareIndexes;
    final plans = prepared.plans;
    final shareCount =
        _committedShareCounts['$bundleIndex:$proposalId'] ??
        commitmentShareCount;
    submittedSharePlans.addAll(plans);
    operationLog.add('submit_prepared_shares:$bundleIndex:$proposalId');

    Future<rust_api.ApiShareDeliveryOutcome> deliver(
      int shareIndex,
      _FakeSharePlan plan,
    ) async {
      final existing = helperRecoveryApi?.state.shareDelegations
          .where(
            (share) =>
                share.bundleIndex == bundleIndex &&
                share.proposalId == proposalId &&
                share.shareIndex == shareIndex,
          )
          .firstOrNull;
      if (existing?.confirmed ?? false) {
        return rust_api.ApiShareDeliveryOutcome(
          shareIndex: shareIndex,
          submission: rust_api.ApiShareSubmissionReport(
            acceptedUrls: existing!.sentToUrls,
            ambiguousUrls: existing.ambiguousUrls,
            targetCount: existing.targetCount,
          ),
        );
      }
      final candidateServers = <String>{
        ...plan.targetServers,
        ...configured,
      }.toList(growable: false);
      final configuredReport = initialShareSubmissionReport;
      late final rust_api.ApiShareSubmissionReport submission;
      if (configuredReport != null) {
        submission = configuredReport;
      } else {
        final transport = helperTransport;
        if (transport == null) {
          submission = rust_api.ApiShareSubmissionReport(
            acceptedUrls: candidateServers
                .take(plan.targetCount)
                .toList(growable: false),
            ambiguousUrls: const [],
            targetCount: plan.targetCount,
          );
        } else {
          BigInt? confirmedPosition =
              _confirmedVotePositions["$bundleIndex:$proposalId"];
          if (confirmedPosition == null) {
            for (final vote in helperRecoveryApi?.state.votes ?? const []) {
              if (vote.bundleIndex == bundleIndex &&
                  vote.proposalId == proposalId) {
                confirmedPosition = vote.vcTreePosition;
                break;
              }
            }
          }
          final body = <String, dynamic>{
            "vote_round_id": context.roundId,
            "shares_hash": base64Encode(Uint8List.fromList(List.filled(32, 7))),
            "proposal_id": proposalId,
            "vote_decision": 1,
            "enc_share": {
              "c1": base64Encode(Uint8List.fromList([8 + shareIndex])),
              "c2": base64Encode(Uint8List.fromList([9 + shareIndex])),
              "share_index": shareIndex,
            },
            "share_index": shareIndex,
            "tree_position": (confirmedPosition ?? BigInt.from(9)).toInt(),
            "share_comms": [
              for (var i = 0; i < shareCount; i++)
                base64Encode(Uint8List.fromList(List.filled(32, 10 + i))),
            ],
            "primary_blind": base64Encode(
              Uint8List.fromList(List.filled(32, 11 + shareIndex)),
            ),
            "submit_at": plan.submitAt.toInt(),
          };
          final accepted = <String>[];
          final ambiguous = <String>[];
          for (final serverUrl in candidateServers) {
            if (accepted.length >= plan.targetCount) break;
            try {
              await transport.postJson(
                Uri.parse("$serverUrl/shielded-vote/v1/shares"),
                body,
                timeout: Duration(milliseconds: helperPostTimeoutMilliseconds),
              );
              accepted.add(serverUrl);
            } catch (_) {
              if (ambiguousShareServerUrls.contains(serverUrl)) {
                ambiguous.add(serverUrl);
              }
            }
          }
          submission = rust_api.ApiShareSubmissionReport(
            acceptedUrls: accepted,
            ambiguousUrls: ambiguous,
            targetCount: plan.targetCount,
          );
        }
      }
      await _persistShareDelivery(
        bundleIndex: bundleIndex,
        proposalId: proposalId,
        shareIndex: shareIndex,
        submitAt: plan.submitAt,
        acceptedUrls: submission.acceptedUrls,
        ambiguousUrls: submission.ambiguousUrls,
        targetCount: submission.targetCount,
      );
      return rust_api.ApiShareDeliveryOutcome(
        shareIndex: shareIndex,
        submission: submission,
      );
    }

    final deliveries = <rust_api.ApiShareDeliveryOutcome>[];
    for (
      var offset = 0;
      offset < plans.length;
      offset += maxConcurrentHelperPosts
    ) {
      final end = (offset + maxConcurrentHelperPosts).clamp(0, plans.length);
      deliveries.addAll(
        await Future.wait([
          for (var index = offset; index < end; index++)
            deliver(shareIndexes[index], plans[index]),
        ]),
      );
    }
    return rust_api.ApiShareBatchDeliveryReport(
      deliveries: deliveries,
      pendingShareIndices: Uint32List(0),
      cancelled: false,
      legacyBestEffort: prepared.legacyBestEffort,
    );
  }

  Future<int> _trackingFlags({
    required rust_frb_types.ShareDelegationRecordView share,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  }) async {
    if (!trackingPassPolicyStarted.isCompleted) {
      trackingPassPolicyStarted.complete();
    }
    await trackingPassPolicyGate?.future;
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
    if (!nextShareTrackingDelayStarted.isCompleted) {
      nextShareTrackingDelayStarted.complete();
    }
    await nextShareTrackingDelayGate?.future;
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
  Future<void> markVoteSubmitted({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) async {
    final key = '$bundleIndex:$proposalId';
    final capturedAuthority = _capturedAuthority[key];
    if (capturedAuthority != null) {
      // Stand-in for the chain rejecting a duplicate `van_nullifier`: the proof
      // spent a vote authority note that another vote on this bundle already
      // spent.
      if (capturedAuthority != _authorityFor(bundleIndex) ||
          _capturedVanPosition[key] != _vanPositionFor(bundleIndex)) {
        throw StateError(
          'cast-vote rejected: duplicate van_nullifier for bundle '
          '$bundleIndex proposal $proposalId (proved against a vote authority '
          'note that was already spent)',
        );
      }
    }
    _bundleAuthority[bundleIndex] =
        _authorityFor(bundleIndex) & ~(1 << proposalId);
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
    _confirmedVotePositions['$bundleIndex:$proposalId'] = vcTreePosition;
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
    if (failingVoteConfirmationKeys.contains('$bundleIndex:$proposalId')) {
      throw StateError(
        'injected vote confirmation persistence failure '
        '$bundleIndex:$proposalId',
      );
    }
    final leafPositions = castVoteLeafPositionsFromTxEventsJson(
      eventsJson,
      roundId,
    );
    // The replacement VAN leaf only becomes witnessable after another tree
    // sync, so require a strictly newer anchor for this bundle from here on.
    _bundleVanPosition[bundleIndex] = ++_nextVanPosition;
    _bundleMinAnchor[bundleIndex] = _voteTreeAnchor + 1;
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

  Future<void> _persistShareDelivery({
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required BigInt submitAt,
    required List<String> acceptedUrls,
    required List<String> ambiguousUrls,
    required int targetCount,
  }) async {
    recordShareAttempts.add(shareIndex);
    if (failingRecordShareIndexes.contains(shareIndex)) {
      throw StateError('share persistence failed $shareIndex');
    }
    operationLog.add('record_share:$bundleIndex:$proposalId:$shareIndex');
    recordedShares.add(
      _RecordedShare(
        bundleIndex: bundleIndex,
        proposalId: proposalId,
        shareIndex: shareIndex,
        submitAt: submitAt,
        sentToUrls: acceptedUrls,
        ambiguousUrls: ambiguousUrls,
        targetCount: targetCount,
      ),
    );
  }

  Future<void> _markShareConfirmed({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) async {
    confirmedShares.add('$bundleIndex:$proposalId:$shareIndex');
    onShareConfirmed?.call(bundleIndex, proposalId, shareIndex);
  }
}

class _GatedFailingShareTrackingRustApi extends FakeVotingRustApi {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<rust_api.ApiShareTrackingReport> trackPendingShares({
    required VotingShareTrackingPassHandle passHandle,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    throw StateError('injected tracking pass failure');
  }
}

void _addUnique<T>(List<T> values, T value) {
  if (!values.contains(value)) {
    values.add(value);
  }
}

class _FakeSharePlan {
  const _FakeSharePlan({
    required this.immediate,
    required this.submitAt,
    required this.targetCount,
    required this.targetServers,
  });

  final bool immediate;
  final BigInt submitAt;
  final int targetCount;
  final List<String> targetServers;
}

class _FakePreparedShareDelivery {
  const _FakePreparedShareDelivery({
    required this.configuredHelperUrls,
    required this.shareIndexes,
    required this.plans,
    required this.legacyBestEffort,
  });

  final List<String> configuredHelperUrls;
  final List<int> shareIndexes;
  final List<_FakeSharePlan> plans;
  final bool legacyBestEffort;
}

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _RecordedShare {
  const _RecordedShare({
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.submitAt,
    required this.sentToUrls,
    required this.ambiguousUrls,
    required this.targetCount,
  });

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final BigInt submitAt;
  final List<String> sentToUrls;
  final List<String> ambiguousUrls;
  final int targetCount;
}

class _FakeVotingShareTrackingPassHandle
    implements VotingShareTrackingPassHandle {
  _FakeVotingShareTrackingPassHandle({
    required this.context,
    required this.accountUuid,
    required this.roundId,
    this.onCancel,
  });

  final VotingHelperDeliveryContext context;

  @override
  final String accountUuid;

  @override
  final String roundId;

  final void Function()? onCancel;

  @override
  bool isCancelled = false;

  @override
  bool isDisposed = false;

  @override
  void cancel() {
    if (isCancelled || isDisposed) return;
    isCancelled = true;
    onCancel?.call();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    isDisposed = true;
  }
}

class _FakeVotingHelperDeliveryContext implements VotingHelperDeliveryContext {
  _FakeVotingHelperDeliveryContext({
    required this.dbPath,
    required this.accountUuid,
    required this.roundId,
  });

  @override
  final String dbPath;

  @override
  final String accountUuid;

  @override
  final String roundId;

  @override
  bool isDisposed = false;

  @override
  void dispose() {
    if (isDisposed) return;
    isDisposed = true;
  }
}

List<rust_wire.DraftVote> _twoProposalDrafts() => [
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
];

List<rust_wire.DraftVote> _singleProposalDrafts() => [
  rust_wire.DraftVote(
    proposalId: 7,
    choice: 1,
    numOptions: 2,
    vcTreePosition: BigInt.zero,
    singleShare: false,
  ),
];

FakeVotingRecoveryApi _singleVoteRecoveryApi() {
  return FakeVotingRecoveryApi(
    state: recoveryState(
      bundleCount: 1,
      delegationTxHashes: const [
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
}

rust_wire.SignedVoteCommitmentsView _commitments({
  required String roundId,
  required int bundleIndex,
  required int proposalId,
  required int choice,
  int shareCount = 1,
  List<int>? shareOrder,
}) {
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
      ),
    ],
  );
}

/// Returns [state] with its unconfirmed share rows replaced.
///
/// A tracking pass confirms shares durably in production; the fake mirrors that
/// so a later plan reload stops reporting them as outstanding.
rust_frb_types.RoundRecoveryStateView _withUnconfirmedShares(
  rust_frb_types.RoundRecoveryStateView state,
  List<rust_frb_types.ShareDelegationRecordView> unconfirmed,
) {
  return rust_frb_types.RoundRecoveryStateView(
    roundId: state.roundId,
    bundleCount: state.bundleCount,
    delegation: state.delegation,
    votes: state.votes,
    commitmentBundles: state.commitmentBundles,
    shares: state.shares,
    shareDelegations: state.shareDelegations,
    unconfirmedShareDelegations: unconfirmed,
  );
}

rust_frb_types.RoundRecoveryStateView _withRecoveredDelegations(
  rust_frb_types.RoundRecoveryStateView state,
  List<int> recoveredBundleIndexes,
) {
  final delegations = <int, rust_frb_types.DelegationRecoveryView>{
    for (final delegation in state.delegation)
      delegation.bundleIndex: delegation,
  };
  for (final bundleIndex in recoveredBundleIndexes) {
    delegations[bundleIndex] = rust_frb_types.DelegationRecoveryView(
      bundleIndex: bundleIndex,
      phase: VotingWorkflowPhase.confirmed,
      txHash: null,
      vanLeafPosition: bundleIndex,
    );
  }
  return rust_frb_types.RoundRecoveryStateView(
    roundId: state.roundId,
    bundleCount: state.bundleCount,
    delegation: delegations.values.toList(),
    votes: state.votes,
    commitmentBundles: state.commitmentBundles,
    shares: state.shares,
    shareDelegations: state.shareDelegations,
    unconfirmedShareDelegations: state.unconfirmedShareDelegations,
  );
}
