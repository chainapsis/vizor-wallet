@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_polls_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_submission_confirmation_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart';

import '../round_plan_test_utils.dart';

const _roundId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final _bootstrap = AppBootstrapState(
  initialLocation: '/voting',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1softwareaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

void main() {
  setUp(resetVotingPollListRecentRefreshForTests);

  testWidgets('polls screen lists rounds and opens results for closed polls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = _pollsRouter();
    await tester.pumpWidget(
      _app(
        router,
        overrides: [
          votingConfigProvider.overrideWith(_StaticVotingConfigNotifier.new),
          votingRoundsProvider.overrideWith(_StaticVotingRoundsNotifier.new),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Closed poll'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voting_header_beta_label')),
      findsOneWidget,
    );

    await tester.tap(find.text('View results'));
    await tester.pumpAndSettle();

    expect(find.text('results route'), findsOneWidget);
  });

  testWidgets('polls screen shows the empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        _pollsRouter(),
        overrides: [
          votingConfigProvider.overrideWith(_StaticVotingConfigNotifier.new),
          votingRoundsProvider.overrideWith(_EmptyVotingRoundsNotifier.new),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No voting rounds available'), findsOneWidget);
  });

  testWidgets('status screen blocks back while a submission guard is active', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const key = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        accountProvider.overrideWith(_SoftwareAccountNotifier.new),
        syncProvider.overrideWith(_NoopSyncNotifier.new),
        votingSubmissionJobsProvider.overrideWith(
          () => _StaticVotingSubmissionJobsNotifier(
            const VotingSubmissionJobsState(jobKeys: [key]),
          ),
        ),
        votingSubmissionJobProvider(key).overrideWith(
          () => _StaticVotingSubmissionJobNotifier(
            key,
            const VotingSubmissionJobState(
              key: key,
              status: VotingSubmissionJobStatus.running,
              generation: 1,
            ),
          ),
        ),
        votingSubmissionJobSessionProvider(key).overrideWithValue(
          AsyncValue.data(
            VotingSessionState(
              roundId: _roundId,
              accountUuid: 'account-1',
              phase: VotingSessionPhase.delegating,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final guard = container
        .read(votingSubmissionGuardProvider.notifier)
        .acquire(accountUuid: 'account-1', roundId: _roundId);

    final router = _statusRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _routerApp(router)),
    );
    // The active step renders an indeterminate spinner, so settle-based
    // pumping never converges; use fixed pumps throughout.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Submitting votes'), findsOneWidget);
    expect(find.text('Delegating voting authority'), findsOneWidget);

    // The top-nav back tap is refused with the guard message.
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Submitting votes'), findsOneWidget);
    expect(find.text(kVotingSubmissionInProgressMessage), findsOneWidget);

    // Releasing the guard unblocks the exit.
    container.read(votingSubmissionGuardProvider.notifier).release(guard);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('voting route'), findsOneWidget);
  });

  testWidgets('status screen shows the Keystone step for hardware accounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const key = VotingSessionKey(roundId: _roundId, accountUuid: 'hardware-1');
    await tester.pumpWidget(
      _app(
        _statusRouter(accountUuid: 'hardware-1'),
        overrides: [
          votingSubmissionJobsProvider.overrideWith(
            () => _StaticVotingSubmissionJobsNotifier(
              const VotingSubmissionJobsState(jobKeys: [key]),
            ),
          ),
          votingSubmissionJobProvider(key).overrideWith(
            () => _StaticVotingSubmissionJobNotifier(
              key,
              const VotingSubmissionJobState(
                key: key,
                status: VotingSubmissionJobStatus.running,
                generation: 1,
              ),
            ),
          ),
          votingSubmissionJobSessionProvider(key).overrideWithValue(
            AsyncValue.data(
              VotingSessionState(
                roundId: _roundId,
                accountUuid: 'hardware-1',
                phase: VotingSessionPhase.delegating,
                isHardwareAccount: true,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Signing with Keystone'), findsOneWidget);
    expect(find.text('Delegating voting authority'), findsOneWidget);
  });

  testWidgets('confirmation screen shows the receipt for a completed vote', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final completedRoundPlan = apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: false,
      nextSteps: const [],
      openProposals: Uint32List(0),
      allDecided: true,
      completedVoteArtifact: true,
      completedForDisplay: true,
    );
    await tester.pumpWidget(
      _app(
        _confirmationRouter(),
        overrides: [
          votingConfigProvider.overrideWith(_StaticVotingConfigNotifier.new),
          votingRoundsProvider.overrideWith(_StaticVotingRoundsNotifier.new),
          votingSessionProvider(_roundId).overrideWith(
            () => _StaticVotingSessionNotifier(
              VotingSessionState(
                roundId: _roundId,
                accountUuid: 'account-1',
                phase: VotingSessionPhase.done,
                roundPlan: completedRoundPlan,
                eligibleWeightZatoshi: BigInt.from(12500000),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Submission confirmed!'), findsOneWidget);
    expect(find.text('Voting round'), findsOneWidget);
    expect(find.text('Voting power'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voting_submission_done_button')),
      findsOneWidget,
    );
  });
}

GoRouter _pollsRouter() {
  return GoRouter(
    initialLocation: '/voting',
    routes: [
      GoRoute(
        path: '/voting',
        builder: (_, _) => const MobileVotingPollsScreen(),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/results',
        builder: (_, _) => const Text('results route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );
}

GoRouter _statusRouter({String accountUuid = 'account-1'}) {
  return GoRouter(
    initialLocation: votingStatusRoute(_roundId, accountUuid: accountUuid),
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/status',
        builder: (_, state) => MobileVotingStatusScreen(
          roundId: state.pathParameters['roundId']!,
          accountUuid: state.uri.queryParameters['account'],
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/submitted',
        builder: (_, _) => const Text('submission confirmed route'),
      ),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting route')),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );
}

GoRouter _confirmationRouter() {
  return GoRouter(
    initialLocation: '/voting/poll/$_roundId/submitted',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/submitted',
        builder: (_, state) => MobileVotingSubmissionConfirmationScreen(
          roundId: state.pathParameters['roundId']!,
        ),
      ),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting route')),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );
}

Widget _app(GoRouter router, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      accountProvider.overrideWith(_SoftwareAccountNotifier.new),
      syncProvider.overrideWith(_NoopSyncNotifier.new),
      ...overrides,
    ],
    child: _routerApp(router),
  );
}

Widget _routerApp(GoRouter router) {
  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

class _StaticVotingConfigNotifier extends VotingConfigNotifier {
  @override
  Future<ResolvedVotingConfig> build() async {
    return const ResolvedVotingConfig(
      sourceFingerprint: 'source-fingerprint',
      trustedKeyFingerprint: 'trusted-key-fingerprint',
      dynamicConfigFingerprint: 'dynamic-config-fingerprint',
      voteServers: [],
      pirEndpoints: [],
      pirLayout: PirLayout(
        pirDepth: 19,
        tier0Layers: 12,
        tier1Layers: 7,
        polyLen: 4096,
      ),
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
  Future<void> refresh() async {}
}

class _StaticVotingRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async {
    return const [
      VotingRoundView(
        roundId: _roundId,
        title: 'Closed poll',
        status: 'closed',
        rawJson: {'description': 'Closed poll description'},
      ),
    ];
  }

  @override
  Future<void> reload() async {
    state = const AsyncData([
      VotingRoundView(
        roundId: _roundId,
        title: 'Closed poll',
        status: 'closed',
        rawJson: {'description': 'Closed poll description'},
      ),
    ]);
  }
}

class _EmptyVotingRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async => const [];

  @override
  Future<void> reload() async {
    state = const AsyncData([]);
  }
}

class _SoftwareAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _bootstrap.initialAccountState;
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
}

class _StaticVotingSubmissionJobsNotifier extends VotingSubmissionJobsNotifier {
  _StaticVotingSubmissionJobsNotifier(this._initial);

  final VotingSubmissionJobsState _initial;

  @override
  VotingSubmissionJobsState build() => _initial;

  @override
  Future<VotingSessionKey?> start(String roundId, {String? accountUuid}) async {
    if (_initial.jobKeys.isEmpty) return null;
    return _initial.jobKeys.first;
  }
}

class _StaticVotingSubmissionJobNotifier extends VotingSubmissionJobNotifier {
  _StaticVotingSubmissionJobNotifier(super.key, this._initial);

  final VotingSubmissionJobState _initial;

  @override
  VotingSubmissionJobState build() => _initial;
}

class _StaticVotingSessionNotifier extends VotingSessionNotifier {
  _StaticVotingSessionNotifier(this._state) : super(_state.roundId);

  final VotingSessionState _state;

  @override
  Future<VotingSessionState> build() async => _state;

  @override
  Future<BigInt?> refreshEligibleWeight() async => _state.eligibleWeightZatoshi;
}
