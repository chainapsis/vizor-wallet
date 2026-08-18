import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_coordinator_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

void main() {
  testWidgets('starts recovery after the host has built', (tester) async {
    var discoveryCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
          appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
          votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
          votingPendingShareRoundLoaderProvider.overrideWithValue(({
            required dbPath,
            required accountUuids,
          }) async {
            discoveryCount++;
            return const [];
          }),
        ],
        child: const VotingShareTrackingCoordinatorHost(child: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(discoveryCount, 1);
  });

  test('retries a failed initial discovery pass', () async {
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)});
    final check = sessions.gateNextCheck(key);
    var discoveryCount = 0;
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareDiscoveryRetryDelayProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          discoveryCount++;
          if (discoveryCount == 1) {
            throw StateError('sidecar temporarily unavailable');
          }
          return const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ];
        }),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'round-1'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final retryCompleted = Completer<void>();
    final subscription = container.listen<VotingShareTrackingCoordinatorState>(
      votingShareTrackingCoordinatorProvider,
      (_, next) {
        if (!next.isRefreshing &&
            next.trackedRoundCount == 1 &&
            next.lastError == null &&
            !retryCompleted.isCompleted) {
          retryCompleted.complete();
        }
      },
    );
    addTearDown(subscription.close);

    await container
        .read(votingShareTrackingCoordinatorProvider.notifier)
        .refresh();

    expect(
      container.read(votingShareTrackingCoordinatorProvider).lastError,
      isA<StateError>(),
    );
    await check.started.future.timeout(const Duration(seconds: 1));
    check.release.complete();
    await retryCompleted.future.timeout(const Duration(seconds: 1));

    expect(discoveryCount, 2);
    expect(sessions.checkCount(key), 1);
  });

  test(
    'restores authenticated pending rounds and releases completed work',
    () async {
      const trackedKey = VotingSessionKey(
        accountUuid: 'account-1',
        roundId: 'round-1',
      );
      var pending = [
        const rust_api.ApiPendingShareRound(
          accountUuid: 'account-1',
          roundId: 'round-1',
        ),
        const rust_api.ApiPendingShareRound(
          accountUuid: 'account-2',
          roundId: 'round-not-authenticated',
        ),
      ];
      final sessions = _FakeSessionStore({
        trackedKey: _round(trackedKey.roundId),
      });
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
          appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
          votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
          votingPendingShareRoundLoaderProvider.overrideWithValue(
            ({required dbPath, required accountUuids}) async => pending,
          ),
          votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
            () async => {'round-1'},
          ),
          votingSubmissionSessionProvider.overrideWith2(
            (key) => _FakeSubmissionSessionNotifier(key, sessions),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        votingShareTrackingCoordinatorProvider.notifier,
      );
      await notifier.refresh();

      expect(sessions.buildCount(trackedKey), 1);
      expect(sessions.checkCount(trackedKey), 1);
      expect(
        container
            .read(votingShareTrackingCoordinatorProvider)
            .trackedRoundCount,
        1,
      );

      pending = [];
      await notifier.refresh();
      await container.pump();

      expect(sessions.disposeCount(trackedKey), 1);
      expect(
        container
            .read(votingShareTrackingCoordinatorProvider)
            .trackedRoundCount,
        0,
      );
    },
  );

  test('rechecks pending rounds after config authentication changes', () async {
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)});
    var authenticatedRoundIds = <String>{};
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(
          ({required dbPath, required accountUuids}) async => const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ],
        ),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => authenticatedRoundIds,
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    await notifier.refresh();
    expect(sessions.checkCount(key), 0);

    authenticatedRoundIds = {'round-1'};
    container
        .read(votingConfigResolutionRevisionProvider.notifier)
        .markResolved();
    for (var attempt = 0; attempt < 10; attempt++) {
      if (sessions.checkCount(key) == 1) break;
      await container.pump();
    }

    expect(sessions.buildCount(key), 1);
    expect(sessions.checkCount(key), 1);
  });

  test(
    'releases sessions as soon as share tracking becomes terminal',
    () async {
      const endedKey = VotingSessionKey(
        accountUuid: 'account-1',
        roundId: 'round-ended',
      );
      const completedKey = VotingSessionKey(
        accountUuid: 'account-2',
        roundId: 'round-complete',
      );
      final sessions = _FakeSessionStore({
        endedKey: _round(endedKey.roundId),
        completedKey: _round(completedKey.roundId),
      });
      sessions.statesAfterCheck[endedKey] = VotingSessionState(
        roundId: endedKey.roundId,
        accountUuid: endedKey.accountUuid,
        round: _round(endedKey.roundId, status: 'closed'),
      );
      sessions.statesAfterCheck[completedKey] = _completedShareState(
        completedKey,
      );
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
          appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
          votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
          votingPendingShareRoundLoaderProvider.overrideWithValue(
            ({required dbPath, required accountUuids}) async => const [
              rust_api.ApiPendingShareRound(
                accountUuid: 'account-1',
                roundId: 'round-ended',
              ),
              rust_api.ApiPendingShareRound(
                accountUuid: 'account-2',
                roundId: 'round-complete',
              ),
            ],
          ),
          votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
            () async => {'round-ended', 'round-complete'},
          ),
          votingSubmissionSessionProvider.overrideWith2(
            (key) => _FakeSubmissionSessionNotifier(key, sessions),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(votingShareTrackingCoordinatorProvider.notifier)
          .refresh();
      await container.pump();

      expect(sessions.checkCount(endedKey), 1);
      expect(sessions.checkCount(completedKey), 1);
      expect(sessions.disposeCount(endedKey), 1);
      expect(sessions.disposeCount(completedKey), 1);
      expect(
        container
            .read(votingShareTrackingCoordinatorProvider)
            .trackedRoundCount,
        0,
      );
    },
  );

  test('pauses while locked and restores tracking after unlock', () async {
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)});
    late _ShareTrackingSecurityNotifier security;
    var discoveryCount = 0;
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(
          () => security = _ShareTrackingSecurityNotifier(),
        ),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          discoveryCount++;
          return const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ];
        }),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'round-1'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    await notifier.refresh();
    expect(discoveryCount, 1);
    expect(sessions.checkCount(key), 1);

    security.setLocked(true);
    await container.pump();
    await notifier.refresh();
    expect(discoveryCount, 1);
    expect(sessions.disposeCount(key), 1);
    expect(
      container.read(votingShareTrackingCoordinatorProvider).trackedRoundCount,
      0,
    );

    security.setLocked(false);
    for (var attempt = 0; attempt < 10; attempt++) {
      if (sessions.checkCount(key) == 2) break;
      await container.pump();
    }
    expect(discoveryCount, 2);
    expect(sessions.buildCount(key), 2);
    expect(sessions.checkCount(key), 2);
  });

  test('quiesce drains active tracking and suppresses new checks', () async {
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)});
    final check = sessions.gateNextCheck(key);
    final discoveredAccountUuids = <List<String>>[];
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          discoveredAccountUuids.add(accountUuids);
          return const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ];
        }),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'round-1'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    final refresh = notifier.refresh();
    await check.started.future;
    var drained = false;
    final drain = notifier
        .quiesceAndDrain(accountUuid: key.accountUuid)
        .then((_) => drained = true);
    await container.pump();

    expect(drained, isFalse);
    expect(sessions.stopCount(key), 1);

    check.release.complete();
    await Future.wait([refresh, drain]);
    await container.pump();

    expect(drained, isTrue);
    expect(sessions.disposeCount(key), 1);
    expect(
      container.read(votingShareTrackingCoordinatorProvider).trackedRoundCount,
      0,
    );

    await notifier.refresh();
    expect(sessions.buildCount(key), 1);
    expect(sessions.checkCount(key), 1);
    expect(discoveredAccountUuids.last, ['account-2']);

    notifier.resumeAfterMutation(accountUuid: key.accountUuid, refresh: false);
    await notifier.refresh();
    expect(sessions.buildCount(key), 2);
    expect(sessions.checkCount(key), 2);
    expect(discoveredAccountUuids.last, ['account-1', 'account-2']);
  });

  test('does not check or retain ended and uncertain rounds', () async {
    const endedKey = VotingSessionKey(
      accountUuid: 'account-1',
      roundId: 'ended',
    );
    const uncertainKey = VotingSessionKey(
      accountUuid: 'account-2',
      roundId: 'missing-end',
    );
    final sessions = _FakeSessionStore({
      endedKey: _round(endedKey.roundId, status: 'closed'),
      uncertainKey: _round(uncertainKey.roundId, includeEnd: false),
    });
    final pending = [
      const rust_api.ApiPendingShareRound(
        accountUuid: 'account-1',
        roundId: 'ended',
      ),
      const rust_api.ApiPendingShareRound(
        accountUuid: 'account-2',
        roundId: 'missing-end',
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(
          ({required dbPath, required accountUuids}) async => pending,
        ),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'ended', 'missing-end'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(votingShareTrackingCoordinatorProvider.notifier)
        .refresh();
    await container.pump();

    expect(sessions.checkCount(endedKey), 0);
    expect(sessions.checkCount(uncertainKey), 0);
    expect(sessions.disposeCount(endedKey), 1);
    expect(sessions.disposeCount(uncertainKey), 1);
    expect(
      container.read(votingShareTrackingCoordinatorProvider).trackedRoundCount,
      0,
    );
  });

  test('discovery failure preserves previously retained sessions', () async {
    var failDiscovery = false;
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)});
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          if (failDiscovery) throw StateError('sidecar unavailable');
          return const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ];
        }),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'round-1'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    await notifier.refresh();
    failDiscovery = true;
    await notifier.refresh();
    await container.pump();

    final state = container.read(votingShareTrackingCoordinatorProvider);
    expect(sessions.disposeCount(key), 0);
    expect(state.trackedRoundCount, 1);
    expect(state.lastError, isA<StateError>());
  });

  test('discovery failure retries while sessions are retained', () async {
    var failNextDiscovery = false;
    var discoveryCount = 0;
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)});
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareDiscoveryRetryDelayProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          discoveryCount++;
          if (failNextDiscovery) {
            failNextDiscovery = false;
            throw StateError('sidecar temporarily unavailable');
          }
          return const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ];
        }),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'round-1'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    await notifier.refresh();
    final retryCheck = sessions.gateNextCheck(key);
    final retryCompleted = Completer<void>();
    final subscription = container.listen<VotingShareTrackingCoordinatorState>(
      votingShareTrackingCoordinatorProvider,
      (_, next) {
        if (discoveryCount >= 3 &&
            !next.isRefreshing &&
            next.lastError == null &&
            !retryCompleted.isCompleted) {
          retryCompleted.complete();
        }
      },
    );
    addTearDown(subscription.close);

    failNextDiscovery = true;
    await notifier.refresh();
    expect(
      container.read(votingShareTrackingCoordinatorProvider).lastError,
      isA<StateError>(),
    );
    await retryCheck.started.future.timeout(const Duration(seconds: 1));
    retryCheck.release.complete();
    await retryCompleted.future.timeout(const Duration(seconds: 1));

    expect(discoveryCount, 3);
    expect(sessions.checkCount(key), 2);
    expect(sessions.disposeCount(key), 0);
  });

  test('failed sessions are rebuilt on the next lifecycle pass', () async {
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)})
      ..remainingBuildFailures[key] = 1;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(
          ({required dbPath, required accountUuids}) async => const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ],
        ),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'round-1'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    await notifier.refresh();
    await container.pump();
    expect(sessions.buildCount(key), 1);
    expect(sessions.disposeCount(key), 1);
    expect(sessions.checkCount(key), 0);
    expect(
      container.read(votingShareTrackingCoordinatorProvider).trackedRoundCount,
      0,
    );

    await notifier.refresh();

    expect(sessions.buildCount(key), 2);
    expect(sessions.checkCount(key), 1);
    expect(
      container.read(votingShareTrackingCoordinatorProvider).trackedRoundCount,
      1,
    );
  });

  test('trailing discovery checks each retained session once', () async {
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    const trailingKey = VotingSessionKey(
      accountUuid: 'account-1',
      roundId: 'round-2',
    );
    final sessions = _FakeSessionStore({
      key: _round(key.roundId),
      trailingKey: _round(trailingKey.roundId),
    });
    final firstLoadStarted = Completer<void>();
    final releaseFirstLoad = Completer<void>();
    var pendingLoadCount = 0;
    final container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          pendingLoadCount++;
          if (pendingLoadCount == 1) {
            firstLoadStarted.complete();
            await releaseFirstLoad.future;
          }
          return [
            const rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
            if (pendingLoadCount > 1)
              const rust_api.ApiPendingShareRound(
                accountUuid: 'account-1',
                roundId: 'round-2',
              ),
          ];
        }),
        votingAuthenticatedRoundIdsLoaderProvider.overrideWithValue(
          () async => {'round-1', 'round-2'},
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    final firstRefresh = notifier.refresh();
    await firstLoadStarted.future;
    final trailingRefresh = notifier.refresh();
    releaseFirstLoad.complete();
    await Future.wait([firstRefresh, trailingRefresh]);

    expect(pendingLoadCount, 2);
    expect(sessions.checkCount(key), 1);
    expect(sessions.checkCount(trailingKey), 1);
  });

  test('resume refresh rearms an initially failed voting config', () async {
    const key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');
    final sessions = _FakeSessionStore({key: _round(key.roundId)});
    late _RecoveringVotingConfigNotifier configNotifier;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        accountProvider.overrideWith(_ShareTrackingAccountNotifier.new),
        appSecurityProvider.overrideWith(_ShareTrackingSecurityNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(
          ({required dbPath, required accountUuids}) async => const [
            rust_api.ApiPendingShareRound(
              accountUuid: 'account-1',
              roundId: 'round-1',
            ),
          ],
        ),
        votingConfigProvider.overrideWith(
          () => configNotifier = _RecoveringVotingConfigNotifier(
            _resolvedConfig(key.roundId),
          ),
        ),
        votingSubmissionSessionProvider.overrideWith2(
          (key) => _FakeSubmissionSessionNotifier(key, sessions),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      votingShareTrackingCoordinatorProvider.notifier,
    );

    await notifier.refresh();
    expect(sessions.buildCount(key), 0);
    expect(
      container.read(votingShareTrackingCoordinatorProvider).lastError,
      isA<StateError>(),
    );

    await notifier.refresh(refreshConfig: true);

    expect(configNotifier.refreshCount, 1);
    expect(sessions.checkCount(key), 1);
    expect(
      container.read(votingShareTrackingCoordinatorProvider).trackedRoundCount,
      1,
    );
  });
}

class _ShareTrackingAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() {
    return const AccountState(
      accounts: [
        AccountInfo(uuid: 'account-1', name: 'One', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Two', order: 1),
      ],
      activeAccountUuid: 'account-1',
    );
  }
}

class _ShareTrackingSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  }

  void setLocked(bool locked) {
    state = AppSecurityState(isPasswordConfigured: true, isUnlocked: !locked);
  }
}

class _FakeSessionStore {
  _FakeSessionStore(this.rounds);

  final Map<VotingSessionKey, VotingRoundDetails?> rounds;
  final Map<VotingSessionKey, int> remainingBuildFailures = {};
  final Map<VotingSessionKey, int> _buildCounts = {};
  final Map<VotingSessionKey, int> _checkCounts = {};
  final Map<VotingSessionKey, int> _disposeCounts = {};
  final Map<VotingSessionKey, int> _stopCounts = {};
  final Map<VotingSessionKey, _GatedSessionCheck> _nextChecks = {};
  final Map<VotingSessionKey, _GatedSessionCheck> _activeChecks = {};
  final Map<VotingSessionKey, VotingSessionState> statesAfterCheck = {};

  int buildCount(VotingSessionKey key) => _buildCounts[key] ?? 0;

  int checkCount(VotingSessionKey key) => _checkCounts[key] ?? 0;

  int disposeCount(VotingSessionKey key) => _disposeCounts[key] ?? 0;

  int stopCount(VotingSessionKey key) => _stopCounts[key] ?? 0;

  _GatedSessionCheck gateNextCheck(VotingSessionKey key) {
    final check = _GatedSessionCheck();
    _nextChecks[key] = check;
    return check;
  }

  void recordBuild(VotingSessionKey key) {
    _buildCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
  }

  Future<void> recordCheck(VotingSessionKey key) async {
    _checkCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    final check = _nextChecks.remove(key);
    if (check == null) return;
    _activeChecks[key] = check;
    check.started.complete();
    try {
      await check.release.future;
    } finally {
      _activeChecks.remove(key);
    }
  }

  Future<void> stopAndDrain(VotingSessionKey key) async {
    _stopCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    await _activeChecks[key]?.release.future;
  }

  void recordDispose(VotingSessionKey key) {
    _disposeCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
  }

  bool takeBuildFailure(VotingSessionKey key) {
    final remaining = remainingBuildFailures[key] ?? 0;
    if (remaining == 0) return false;
    remainingBuildFailures[key] = remaining - 1;
    return true;
  }
}

class _FakeSubmissionSessionNotifier extends VotingSubmissionSessionNotifier {
  _FakeSubmissionSessionNotifier(this.key, this.sessions) : super(key);

  final VotingSessionKey key;
  final _FakeSessionStore sessions;

  @override
  Future<VotingSessionState> build() async {
    sessions.recordBuild(key);
    ref.onDispose(() => sessions.recordDispose(key));
    if (sessions.takeBuildFailure(key)) {
      throw StateError('session load failed');
    }
    return VotingSessionState(
      roundId: key.roundId,
      accountUuid: key.accountUuid,
      round: sessions.rounds[key],
    );
  }

  @override
  Future<void> submitPendingShares() async {
    await sessions.recordCheck(key);
    final next = sessions.statesAfterCheck.remove(key);
    if (next != null) state = AsyncData(next);
  }

  @override
  Future<void> stopAndDrainShareTracking() {
    return sessions.stopAndDrain(key);
  }
}

class _GatedSessionCheck {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
}

class _RecoveringVotingConfigNotifier extends VotingConfigNotifier {
  _RecoveringVotingConfigNotifier(this.config);

  final rust_config.ResolvedVotingConfig config;
  int refreshCount = 0;

  @override
  Future<rust_config.ResolvedVotingConfig> build() async {
    throw StateError('voting config unavailable');
  }

  @override
  Future<void> refresh() async {
    refreshCount++;
    state = AsyncData(config);
  }
}

rust_config.ResolvedVotingConfig _resolvedConfig(String roundId) {
  return rust_config.ResolvedVotingConfig(
    sourceFingerprint: 'source',
    trustedKeyFingerprint: 'trusted',
    dynamicConfigFingerprint: 'dynamic',
    voteServers: const [
      rust_config.ServiceEndpoint(url: 'https://vote.example', label: 'vote'),
    ],
    pirEndpoints: const [
      rust_config.ServiceEndpoint(url: 'https://pir.example', label: 'pir'),
    ],
    pirLayout: const rust_config.PirLayout(
      pirDepth: 19,
      tier0Layers: 12,
      tier1Layers: 7,
    ),
    supportedVersions: const rust_config.SupportedVersions(
      pir: ['1'],
      voteProtocol: '1',
      tally: '1',
      voteServer: '1',
    ),
    authenticatedRounds: [
      rust_config.AuthenticatedRound(
        roundId: roundId,
        eaPk: Uint8List.fromList(List<int>.filled(32, 1)),
      ),
    ],
    skippedRoundIds: const [],
    conditions: const [],
  );
}

VotingRoundDetails _round(
  String roundId, {
  String status = 'active',
  bool includeEnd = true,
}) {
  final rawJson = <String, dynamic>{
    if (includeEnd)
      'vote_end_time':
          DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
  };
  return VotingRoundDetails(
    roundId: roundId,
    title: 'Round',
    status: status,
    snapshotHeight: 1,
    eaPk: Uint8List(32),
    ncRoot: Uint8List(32),
    nullifierImtRoot: Uint8List(32),
    rawJson: rawJson,
  );
}

VotingSessionState _completedShareState(VotingSessionKey key) {
  final resumePlan = const VotingRecoveryService().buildResumePlan(
    rust_wire.RoundRecoveryStateView(
      roundId: key.roundId,
      bundleCount: 0,
      delegation: const [],
      votes: const [],
      commitmentBundles: const [],
      shares: const [],
      shareDelegations: const [],
      unconfirmedShareDelegations: const [],
    ),
  );
  return VotingSessionState(
    roundId: key.roundId,
    accountUuid: key.accountUuid,
    round: _round(key.roundId),
    resumePlan: resumePlan,
  );
}
