import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_picture.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_allocation_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_delegate_directory_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_delegate_profile_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_round_delegation.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_review_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_snapshot_warmup_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import 'delegate_picture_fakes.dart';
import 'mock_proxy_delegation_repository.dart';
import 'proxy_test_scenarios.dart';

export 'proxy_test_scenarios.dart';

/// What a pumped proxy route hands back to a test.
class ProxyTestHarness {
  /// Creates the harness.
  ProxyTestHarness(this.repository, this.router, this.container, this.jobs);

  /// The mock behind every screen.
  final MockProxyDelegationRepository repository;

  /// The router hosting the delegator views.
  final GoRouter router;

  /// The provider container.
  final ProviderContainer container;

  /// The submission jobs the vote review started.
  final RecordingSubmissionJobs jobs;

  /// Location of the top route, pushed or not.
  String get location => topRouteLocation(router);

  /// The session a delegation submit records its answers in.
  ProxyTestSession get session =>
      container.read(votingSubmissionSessionProvider(kProxyTestKey).notifier)
          as ProxyTestSession;
}

/// Location of [router]'s top route, pushed or not.
String topRouteLocation(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  final top = configuration.matches.last;
  if (top is ImperativeRouteMatch) return top.matches.uri.toString();
  return configuration.uri.toString();
}

/// Pumps [router] at [size] and [textScale] in the light theme under
/// [overrides], settles it, and returns its provider container. Both the
/// delegator and the delegate-mode harnesses pump through it.
Future<ProviderContainer> pumpProxyApp(
  WidgetTester tester,
  GoRouter router, {
  required List<Override> overrides,
  required Size size,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(router.dispose);
  // A widget-owned scope disposes the container when the test tree unmounts,
  // so stream timers stop before flutter_test checks for pending timers.
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        localizationsDelegates: appLocalizationsDelegates,
        routerConfig: router,
        builder: (context, child) => AppTheme(
          data: AppThemeData.light,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  await settleProxy(tester);
  return container;
}

/// Pictures that Rust would refuse, so screens draw identicons unless a test
/// passes its own cache.
DelegatePictureCache _refusingPictures() {
  final cache = DelegatePictureCache(
    FakeDelegatePictureDecoder()..failure = 'refused',
  );
  addTearDown(cache.clear);
  return cache;
}

/// Pumps [location] in a router holding every delegator view and a poll
/// route with the round screen's delegation line, without the desktop
/// shell. [pictureCache] backs the delegate pictures. [backing] replaces
/// the mock behind every screen.
Future<ProxyTestHarness> pumpProxyRoute(
  WidgetTester tester,
  String location, {
  ProxyMockScenario? scenario,
  Size size = const Size(1000, 2400),
  List<RouteBase> extraRoutes = const [],
  List<RouteBase>? routes,
  double textScale = 1,
  DelegatePictureCache? pictureCache,
  ProxyDelegationRepository? backing,
  VotingDraftState answers = const VotingDraftState(),
}) async {
  final repository = MockProxyDelegationRepository(
    scenario ?? proxyTestScenario(),
  );

  /// Hosts [child] in a [Scaffold] for Material ancestors.
  Widget page(Widget child) => Scaffold(body: child);

  /// The route's `roundId` parameter.
  String round(GoRouterState state) => state.pathParameters['roundId'] ?? '';
  final router = GoRouter(
    initialLocation: location,
    routes: routes != null
        ? [...extraRoutes, ...routes]
        : [
            ...extraRoutes,
            GoRoute(
              path: '/voting/poll/:roundId',
              builder: (_, state) => page(
                SingleChildScrollView(
                  child: Column(
                    children: [
                      Text('poll ${round(state)}'),
                      ProxyVotingPowerLine(roundId: round(state)),
                    ],
                  ),
                ),
              ),
            ),
            GoRoute(
              path: kProxyDelegateDirectoryPath,
              builder: (_, state) => page(
                ProxyDelegateDirectoryView(
                  roundId: round(state),
                  showDesktopToolbar: true,
                ),
              ),
            ),
            GoRoute(
              path: kProxyDelegateProfilePath,
              builder: (_, state) => page(
                ProxyDelegateProfileView(
                  roundId: round(state),
                  delegateIndex: int.parse(
                    state.pathParameters['delegateIndex']!,
                  ),
                  showDesktopToolbar: true,
                ),
              ),
            ),
            GoRoute(
              path: '/voting/poll/:roundId/review',
              builder: (_, state) => page(
                VotingReviewView(
                  roundId: round(state),
                  showDesktopToolbar: true,
                ),
              ),
            ),
            GoRoute(
              path: '/voting/poll/:roundId/status',
              builder: (_, state) =>
                  page(Text('status ${state.uri.queryParameters['account']}')),
            ),
            GoRoute(
              path: kProxyAllocationPath,
              builder: (_, state) => page(
                ProxyAllocationView(
                  roundId: round(state),
                  showDesktopToolbar: true,
                ),
              ),
            ),
          ],
  );
  final container = await pumpProxyApp(
    tester,
    router,
    size: size,
    textScale: textScale,
    overrides: [
      proxyDelegationFeatureEnabledProvider.overrideWithValue(true),
      proxyActiveSessionKeyProvider.overrideWith(
        (ref, roundId) =>
            VotingSessionKey(roundId: roundId, accountUuid: kProxyTestAccount),
      ),
      proxyDelegationRepositoryProvider.overrideWith(
        (ref, key) => backing ?? repository,
      ),
      proxyClockProvider.overrideWithValue(() => kProxyTestNow),
      delegatePictureCacheProvider.overrideWithValue(
        pictureCache ?? _refusingPictures(),
      ),
      votingSessionProvider(kProxyTestRoundId).overrideWith(
        () =>
            ProxyTestSession(proxyTestSession(scenario ?? repository.scenario)),
      ),
      votingSubmissionSessionProvider(kProxyTestKey).overrideWith(
        () =>
            ProxyTestSession(proxyTestSession(scenario ?? repository.scenario)),
      ),
      votingDraftPersistenceProvider.overrideWithValue(_MemoryDrafts(answers)),
      votingSubmissionJobsProvider.overrideWith(RecordingSubmissionJobs.new),
    ],
  );
  // Kept, so [ProxyTestHarness.session] still holds what a submit recorded.
  container.listen(votingSubmissionSessionProvider(kProxyTestKey), (_, _) {});
  return ProxyTestHarness(
    repository,
    router,
    container,
    container.read(votingSubmissionJobsProvider.notifier)
        as RecordingSubmissionJobs,
  );
}

/// The account every proxy test's voting session belongs to.
const kProxyTestAccount = 'account-1';

/// The proxy test round for [kProxyTestAccount].
const kProxyTestKey = VotingSessionKey(
  roundId: kProxyTestRoundId,
  accountUuid: kProxyTestAccount,
);

/// A voting session for [scenario]'s round: eligible, with its proposals
/// and vote end.
VotingSessionState proxyTestSession(ProxyMockScenario scenario) {
  final round = scenario.round;
  return VotingSessionState(
    roundId: kProxyTestRoundId,
    accountUuid: kProxyTestAccount,
    eligibleWeightZatoshi: BigInt.from(5000000000),
    round: VotingRoundDetails(
      roundId: kProxyTestRoundId,
      title: round.title,
      status: 'SESSION_STATUS_ACTIVE',
      snapshotHeight: 100,
      eaPk: Uint8List(32),
      ncRoot: Uint8List(32),
      nullifierImtRoot: Uint8List(32),
      rawJson: {
        'vote_end_time': round.voteEndTime.millisecondsSinceEpoch ~/ 1000,
        'proposals': [
          for (final proposal in round.proposals)
            {
              'id': proposal.id,
              'title': proposal.title,
              'options': [
                for (final option in proposal.options)
                  {'index': option.index, 'label': option.label},
              ],
            },
        ],
      },
    ),
  );
}

/// A voting session that stays as built, recording the ballot intents a
/// delegation submit records and clears.
class ProxyTestSession extends VotingSubmissionSessionNotifier {
  /// Creates the session.
  ProxyTestSession(this._state) : super(kProxyTestKey);

  final VotingSessionState _state;

  /// Every recorded ballot, as each proposal's choice, in order.
  final recorded = <Map<int, int>>[];

  /// Every cleared set of proposal ids, in order.
  final cleared = <List<int>>[];

  @override
  Future<void> recordBallotIntents({
    required List<VotingDraftVote> draftVotes,
    List<int>? allProposalIds,
  }) async => recorded.add({
    for (final vote in draftVotes) vote.proposalId: vote.choice,
  });

  @override
  Future<void> clearBallotIntents(List<int> proposalIds) async =>
      cleared.add(proposalIds);

  @override
  Future<VotingSessionState> build() async => _state;

  @override
  Future<BigInt?> refreshEligibleWeight() async => _state.eligibleWeightZatoshi;

  @override
  Future<VotingSnapshotWarmupResult> precomputeSnapshotBundles({
    required String accountUuid,
  }) async => const VotingSnapshotWarmupResult.ready();
}

/// Ballot drafts kept in memory, starting from [initial].
class _MemoryDrafts implements VotingDraftPersistence {
  _MemoryDrafts(this.initial);

  /// The stored draft.
  VotingDraftState initial;

  @override
  Future<VotingDraftState> load(VotingSessionKey key) async => initial;

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async =>
      initial = draft;

  @override
  Future<void> deleteForAccount(String accountUuid) async {}
}

/// Submission jobs that record which job the vote review started.
class RecordingSubmissionJobs extends VotingSubmissionJobsNotifier {
  /// Vote jobs started, by round.
  final started = <String>[];

  /// Proxy jobs started, by round.
  final proxyStarted = <String>[];

  /// The account of every job started, vote or proxy, in order.
  final accounts = <String?>[];

  @override
  Future<VotingSessionKey?> start(String roundId, {String? accountUuid}) async {
    started.add(roundId);
    accounts.add(accountUuid);
    return VotingSessionKey(
      roundId: roundId,
      accountUuid: accountUuid ?? kProxyTestAccount,
    );
  }

  @override
  Future<VotingSessionKey?> startProxy(
    String roundId, {
    String? accountUuid,
  }) async {
    proxyStarted.add(roundId);
    accounts.add(accountUuid);
    return VotingSessionKey(
      roundId: roundId,
      accountUuid: accountUuid ?? kProxyTestAccount,
    );
  }
}

/// Lets providers resolve and page transitions finish without waiting for
/// spinners to stop.
Future<void> settleProxy(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 20));
}

/// Every string rendered by a [Text] or [RichText] under the app.
List<String> renderedTexts(WidgetTester tester) => [
  for (final widget in tester.widgetList<Text>(find.byType(Text)))
    widget.data ?? widget.textSpan?.toPlainText() ?? '',
  for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
    widget.text.toPlainText(),
];

/// A delegation count ("12 delegations", "at least 3") or a ZEC total in
/// the same sentence as "total".
final _proxyCountOrTotal = [
  RegExp(r'\b\d[\d,]*\s+(delegations?|delegators?|supporters|people)\b'),
  RegExp(r'\bat least \d'),
  RegExp(r'total[^.]*\d[\d,.]*\s*ZEC|\d[\d,.]*\s*ZEC[^.]*\btotal'),
];

/// Fails when any rendered text shows a delegation count or ZEC total.
void expectNoProxyCountsOrTotals(WidgetTester tester) {
  final texts = renderedTexts(tester);
  expect(texts, isNotEmpty);
  for (final text in texts) {
    for (final pattern in _proxyCountOrTotal) {
      expect(
        pattern.hasMatch(text.toLowerCase()) || pattern.hasMatch(text),
        isFalse,
        reason: '"$text" shows a delegation count or ZEC total',
      );
    }
  }
}
