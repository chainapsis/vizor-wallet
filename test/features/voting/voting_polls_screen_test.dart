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
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart';

void main() {
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

    await tester.tap(find.text('View results'));
    await tester.pumpAndSettle();

    expect(find.text('results route'), findsOneWidget);
    expect(roundsNotifier.reloadCount, 1);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('View results'), findsOneWidget);
    expect(roundsNotifier.reloadCount, 2);
    expect(configNotifier.refreshCount, 2);
  });
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

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
}
