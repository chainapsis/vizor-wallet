import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_polls_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart';

void main() {
  setUp(resetVotingPollListRecentRefreshForTests);

  testWidgets('poll list reloads when screen opens and route returns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    late _TrackingVotingRoundsNotifier roundsNotifier;
    late _TrackingVotingConfigNotifier configNotifier;
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/voting',
      routes: [
        GoRoute(path: '/voting', builder: (_, _) => const VotingPollsScreen()),
        GoRoute(
          path: '/voting/poll/:roundId/results',
          builder: (_, _) => const Text('results route'),
        ),
        GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/address-book',
          builder: (_, _) => const Text('address book'),
        ),
        GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
        GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
        GoRoute(path: '/about', builder: (_, _) => const Text('about')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_SoftwareAccountNotifier.new),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
          swapFeatureEnabledProvider.overrideWithValue(false),
          votingConfigProvider.overrideWith(() {
            configNotifier = _TrackingVotingConfigNotifier();
            return configNotifier;
          }),
          votingRoundsProvider.overrideWith(() {
            roundsNotifier = _TrackingVotingRoundsNotifier();
            return roundsNotifier;
          }),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(roundsNotifier.reloadCount, 1);
    expect(configNotifier.refreshCount, 1);

    final returnReload = Completer<void>();
    roundsNotifier.nextReload = returnReload.future;

    await tester.tap(find.text('View results'));
    await tester.pumpAndSettle();

    expect(find.text('results route'), findsOneWidget);
    expect(roundsNotifier.reloadCount, 1);

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(roundsNotifier.reloadCount, 2);
    expect(configNotifier.refreshCount, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('View results'), findsOneWidget);

    returnReload.complete();
    await tester.pumpAndSettle();

    expect(find.text('View results'), findsOneWidget);
  });

  testWidgets('account reload shows loading instead of previous account rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    late _SwitchingAccountNotifier accountNotifier;
    late _AccountReloadVotingRoundsNotifier roundsNotifier;
    final accountReloadGate = Completer<void>();
    final router = GoRouter(
      initialLocation: '/voting',
      routes: [
        GoRoute(path: '/voting', builder: (_, _) => const VotingPollsScreen()),
        GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/address-book',
          builder: (_, _) => const Text('address book'),
        ),
        GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
        GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
        GoRoute(path: '/about', builder: (_, _) => const Text('about')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(() {
            accountNotifier = _SwitchingAccountNotifier();
            return accountNotifier;
          }),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
          swapFeatureEnabledProvider.overrideWithValue(false),
          votingConfigProvider.overrideWith(_TrackingVotingConfigNotifier.new),
          votingRoundsProvider.overrideWith(() {
            roundsNotifier = _AccountReloadVotingRoundsNotifier(
              accountReloadGate.future,
            );
            return roundsNotifier;
          }),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(roundsNotifier.reloadCount, 1);
    expect(find.text('Account 1 poll'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    accountNotifier.activate('account-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Account 1 poll'), findsNothing);
    expect(find.text('Account 2 poll'), findsNothing);

    accountReloadGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Account 2 poll'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('poll cards show round forum discussion links', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final router = GoRouter(
      initialLocation: '/voting',
      routes: [
        GoRoute(path: '/voting', builder: (_, _) => const VotingPollsScreen()),
        GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/address-book',
          builder: (_, _) => const Text('address book'),
        ),
        GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
        GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
        GoRoute(path: '/about', builder: (_, _) => const Text('about')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_SoftwareAccountNotifier.new),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
          swapFeatureEnabledProvider.overrideWithValue(false),
          votingConfigProvider.overrideWith(_TrackingVotingConfigNotifier.new),
          votingRoundsProvider.overrideWith(_ForumLinkVotingRoundsNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forum discussion'), findsOneWidget);
  });

  testWidgets(
    'initial entry refresh hides stale load errors until rows arrive',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1512, 982));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      late _TrackingVotingConfigNotifier configNotifier;
      late _InitiallyFailingVotingRoundsNotifier roundsNotifier;
      final reloadGate = Completer<void>();
      final router = GoRouter(
        initialLocation: '/voting',
        routes: [
          GoRoute(
            path: '/voting',
            builder: (_, _) => const VotingPollsScreen(),
          ),
          GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(
            path: '/address-book',
            builder: (_, _) => const Text('address book'),
          ),
          GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
          GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
          GoRoute(path: '/about', builder: (_, _) => const Text('about')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(_SoftwareAccountNotifier.new),
            syncProvider.overrideWith(_NoopSyncNotifier.new),
            swapFeatureEnabledProvider.overrideWithValue(false),
            votingConfigProvider.overrideWith(() {
              configNotifier = _TrackingVotingConfigNotifier();
              return configNotifier;
            }),
            votingRoundsProvider.overrideWith(() {
              roundsNotifier = _InitiallyFailingVotingRoundsNotifier(
                reloadGate.future,
              );
              return roundsNotifier;
            }),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(configNotifier.refreshCount, 1);
      expect(roundsNotifier.reloadCount, 1);
      expect(
        find.textContaining('Bad state: first load became stale'),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      reloadGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Closed poll'), findsOneWidget);
      expect(find.text('View results'), findsOneWidget);
    },
  );
}

class _TrackingVotingConfigNotifier extends VotingConfigNotifier {
  int refreshCount = 0;

  @override
  Future<ResolvedVotingConfig> build() async {
    return const ResolvedVotingConfig(
      sourceFingerprint: 'source-fingerprint',
      trustedKeyFingerprint: 'trusted-key-fingerprint',
      dynamicConfigFingerprint: 'dynamic-config-fingerprint',
      voteServers: [],
      pirEndpoints: [],
      supportedVersions: SupportedVersions(
        pir: [],
        voteProtocol: 'vote-protocol',
        tally: 'tally',
        voteServer: 'vote-server',
      ),
      authenticatedRounds: [],
      skippedRoundIds: [],
      conditions: [],
    );
  }

  @override
  Future<void> refresh() async {
    refreshCount++;
  }
}

class _TrackingVotingRoundsNotifier extends VotingRoundsNotifier {
  int reloadCount = 0;
  Future<void>? nextReload;

  @override
  Future<List<VotingRoundView>> build() async {
    return const [
      VotingRoundView(
        roundId: 'round-1',
        title: 'Closed poll',
        status: 'closed',
        rawJson: {'description': 'Closed poll description'},
      ),
    ];
  }

  @override
  Future<void> reload() async {
    reloadCount++;
    state = const AsyncLoading<List<VotingRoundView>>();
    final pendingReload = nextReload;
    nextReload = null;
    if (pendingReload != null) {
      await pendingReload;
    }
    state = const AsyncData([
      VotingRoundView(
        roundId: 'round-1',
        title: 'Closed poll',
        status: 'closed',
        rawJson: {'description': 'Closed poll description'},
      ),
    ]);
  }
}

class _InitiallyFailingVotingRoundsNotifier extends VotingRoundsNotifier {
  _InitiallyFailingVotingRoundsNotifier(this.reloadGate);

  final Future<void> reloadGate;
  int reloadCount = 0;

  @override
  Future<List<VotingRoundView>> build() async {
    throw StateError('first load became stale');
  }

  @override
  Future<void> reload() async {
    reloadCount++;
    state = const AsyncLoading<List<VotingRoundView>>();
    await reloadGate;
    state = const AsyncData([
      VotingRoundView(
        roundId: 'round-1',
        title: 'Closed poll',
        status: 'closed',
        rawJson: {'description': 'Closed poll description'},
      ),
    ]);
  }
}

class _ForumLinkVotingRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async => const [_round];

  @override
  Future<void> reload() async {
    state = const AsyncData([_round]);
  }

  static const _round = VotingRoundView(
    roundId: 'round-1',
    title: 'Active poll',
    status: 'active',
    rawJson: {
      'description': 'Active poll description',
      'discussion_url': 'https://forum.zcashcommunity.com/t/active-poll',
    },
  );
}

class _AccountReloadVotingRoundsNotifier extends VotingRoundsNotifier {
  _AccountReloadVotingRoundsNotifier(this.accountReloadGate);

  final Future<void> accountReloadGate;
  int reloadCount = 0;

  @override
  Future<List<VotingRoundView>> build() async {
    final loadActiveAccount = ref.watch(votingActiveAccountUuidProvider);
    final activeAccountUuid = await loadActiveAccount();
    if (activeAccountUuid == 'account-2') {
      await accountReloadGate;
    }
    return [_rowFor(activeAccountUuid)];
  }

  @override
  Future<void> reload() async {
    reloadCount++;
    final activeAccountUuid = await ref
        .read(votingActiveAccountUuidProvider)
        .call();
    state = AsyncData([_rowFor(activeAccountUuid)]);
  }

  VotingRoundView _rowFor(String? activeAccountUuid) {
    final isSecondAccount = activeAccountUuid == 'account-2';
    return VotingRoundView(
      roundId: 'round-1',
      title: isSecondAccount ? 'Account 2 poll' : 'Account 1 poll',
      status: 'closed',
      voted: !isSecondAccount,
      rawJson: const {'description': 'Closed poll description'},
    );
  }
}

class _SoftwareAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1softwareaddress',
  );
}

class _SwitchingAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _stateFor('account-1');

  void activate(String accountUuid) {
    state = AsyncData(_stateFor(accountUuid));
  }

  AccountState _stateFor(String activeAccountUuid) {
    return AccountState(
      accounts: const [
        AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
      ],
      activeAccountUuid: activeAccountUuid,
      activeAddress: 'u1$activeAccountUuid',
    );
  }
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
}
