import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import '../../../support/test_l10n.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_step_row.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_test_harness.dart';
import 'support/proxy_values.dart';

final _voteEnd = kProxyTestNow.add(const Duration(days: 3));

const _key = VotingSessionKey(
  roundId: kProxyTestRoundId,
  accountUuid: kProxyTestAccount,
);

/// Delegations to Alice and Dana, each at [stage].
ApiProxyDelegationProgress _progress(
  ProxyDelegationStage stage, {
  bool refusedByChain = false,
}) => proxyProgress(
  delegations: [
    for (final (index, handle) in const [(1, 'alice_votes'), (4, 'dana')])
      proxyView(
        delegateIndex: index,
        handle: handle,
        ballots: BigInt.from(100),
        stage: stage,
        ballot: proxyBallot(ApiDelegateBallotKind.noBallotYet),
      ),
  ],
  refusedByChain: refusedByChain,
);

/// [proxyBallotProgress] at the test's clock.
ProxyBallotProgress _rows(
  ApiProxyDelegationProgress delegation, {
  bool castsVotes = false,
  int? ballotStep,
  bool ballotComplete = false,
  bool jobComplete = false,
}) => proxyBallotProgress(
  delegation: delegation,
  castsVotes: castsVotes,
  ballotStep: ballotStep,
  ballotComplete: ballotComplete,
  jobComplete: jobComplete,
  now: kProxyTestNow,
  voteEnd: _voteEnd,
);

/// Each row as `done`, `active` or `todo`, in order.
List<String> _marks(ProxyBallotProgress rows) => [
  for (var i = 0; i < rows.steps.length; i++)
    i < rows.current
        ? 'done'
        : i == rows.current && rows.running
        ? 'active'
        : 'todo',
];

/// The step rows on screen, as `label: mark`.
List<String> _shownRows(WidgetTester tester) => [
  for (final row in tester.widgetList<VotingStepRow>(
    find.byType(VotingStepRow),
  ))
    '${row.label}: ${row.complete
        ? 'done'
        : row.active
        ? 'active'
        : 'todo'}',
];

/// A job that stays as built.
class _StaticJob extends VotingSubmissionJobNotifier {
  _StaticJob(this._state) : super(_key);

  final VotingSubmissionJobState _state;

  @override
  VotingSubmissionJobState build() => _state;
}

void main() {
  group('the rows of a ballot that carries a delegation', () {
    test('a delegation alone runs proving, delegating and finalizing, with '
        'no casting row', () {
      expect(_rows(_progress(ProxyDelegationStage.preparing)).steps, const [
        ProxyBallotStep.proving,
        ProxyBallotStep.delegating,
        ProxyBallotStep.finalizing,
      ]);
      expect(_marks(_rows(_progress(ProxyDelegationStage.preparing))), [
        'active',
        'todo',
        'todo',
      ]);
      expect(_marks(_rows(_progress(ProxyDelegationStage.submitting))), [
        'done',
        'active',
        'todo',
      ]);
      // Finalizing runs until the immediate share's reveal is confirmed.
      expect(_marks(_rows(_progress(ProxyDelegationStage.included))), [
        'done',
        'done',
        'active',
      ]);
      expect(_rows(_progress(ProxyDelegationStage.handedOff)).complete, isTrue);
    });

    test('with the wallet\'s own answers the delegation goes first, then '
        'the casts, then finalizing', () {
      List<String> at(
        ProxyDelegationStage stage, {
        required int ballotStep,
        bool ballotComplete = false,
        bool jobComplete = false,
      }) => _marks(
        _rows(
          _progress(stage),
          castsVotes: true,
          ballotStep: ballotStep,
          ballotComplete: ballotComplete,
          jobComplete: jobComplete,
        ),
      );

      expect(
        _rows(
          _progress(ProxyDelegationStage.preparing),
          castsVotes: true,
          ballotStep: 0,
        ).steps,
        ProxyBallotStep.values,
      );
      expect(at(ProxyDelegationStage.preparing, ballotStep: 0), [
        'active',
        'todo',
        'todo',
        'todo',
      ]);
      expect(at(ProxyDelegationStage.submitting, ballotStep: 0), [
        'done',
        'active',
        'todo',
        'todo',
      ]);
      expect(at(ProxyDelegationStage.included, ballotStep: 1), [
        'done',
        'done',
        'active',
        'todo',
      ]);
      expect(
        at(ProxyDelegationStage.handedOff, ballotStep: 2, ballotComplete: true),
        ['done', 'done', 'done', 'active'],
      );
      expect(
        at(
          ProxyDelegationStage.handedOff,
          ballotStep: 2,
          ballotComplete: true,
          jobComplete: true,
        ),
        ['done', 'done', 'done', 'done'],
      );
    });

    test('a refusal holds the delegating row without moving it', () {
      final rows = _rows(
        _progress(ProxyDelegationStage.submitting, refusedByChain: true),
      );
      expect(rows.outcome, isA<ProxyProgressRefused>());
      expect(_marks(rows), ['done', 'todo', 'todo']);
    });

    test('the live progress and the stored status merge to the further '
        'stage', () {
      final status = ApiProxyAllocationStatus(
        delegations: _progress(ProxyDelegationStage.included).delegations,
        keptBallots: BigInt.from(100),
      );
      final merged = mergedProxyProgress(
        status: status,
        progress: _progress(
          ProxyDelegationStage.submitting,
          refusedByChain: true,
        ),
      );
      expect(merged.delegations.map((view) => view.stage).toSet(), {
        ProxyDelegationStage.included,
      });
      expect(merged.refusedByChain, isTrue);
    });
  });

  group('the vote status rows', () {
    /// Pumps [content] in the app theme.
    Future<void> pump(WidgetTester tester, Widget content) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
          home: Scaffold(body: content),
        ),
      );
    }

    testWidgets('casts that fail after the delegation landed retry like '
        'votes, with the delegation done', (tester) async {
      var retried = false;
      await pump(
        tester,
        VotingStatusContent(
          phase: VotingSessionPhase.error,
          errorMessage: 'Casting failed.',
          onRetry: () => retried = true,
          delegation: _rows(
            _progress(ProxyDelegationStage.handedOff),
            castsVotes: true,
            ballotStep: 1,
          ),
        ),
      );
      expect(_shownRows(tester), [
        'Proving voting authority: done',
        'Delegating to @alice_votes and @dana: done',
        'Casting votes and submitting shares: todo',
        'Finalizing submission: todo',
      ]);
      expect(find.text('Casting failed.'), findsOne);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });
  });

  group('the vote status screen with a committed delegation', () {
    /// Pumps the status screen for a [job] carrying [scenario]'s committed
    /// delegation, with the flag [enabled]. Only [_key]'s repository may be
    /// read.
    Future<ProviderContainer> pumpStatus(
      WidgetTester tester, {
      required ProxyMockScenario scenario,
      VotingSubmissionJobState? job,
      bool enabled = true,
    }) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          proxyDelegationFeatureEnabledProvider.overrideWithValue(enabled),
          proxyClockProvider.overrideWithValue(() => kProxyTestNow),
          proxyDelegationRepositoryProvider.overrideWith((ref, key) {
            expect(key, _key, reason: 'only the shown account is read');
            return MockProxyDelegationRepository(scenario);
          }),
          if (job != null) ...[
            votingSubmissionJobsProvider.overrideWith(
              RecordingSubmissionJobs.new,
            ),
            votingSubmissionJobProvider(
              _key,
            ).overrideWith(() => _StaticJob(job)),
          ],
          votingSubmissionJobSessionProvider(
            _key,
          ).overrideWithValue(AsyncValue.data(proxyTestSession(scenario))),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: votingStatusRoute(
          kProxyTestRoundId,
          accountUuid: kProxyTestAccount,
        ),
        routes: [
          GoRoute(
            path: '/voting/poll/:roundId/status',
            builder: (_, state) => Scaffold(
              body: VotingStatusView(
                roundId: state.pathParameters['roundId']!,
                accountUuid: state.uri.queryParameters['account'],
                submissionProgressBuilder: (_, _) =>
                    const Text('platform progress'),
              ),
            ),
          ),
          GoRoute(
            path: '/voting/poll/:roundId',
            builder: (_, _) => const Text('round'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            localizationsDelegates: appLocalizationsDelegates,
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await settleProxy(tester);
      return container;
    }

    /// A scenario with a committed delegation to Alice and Dana.
    ProxyMockScenario committed() {
      final scenario = proxyTestScenario();
      scenario.status = proxyStatus(scenario, [
        'alice_votes',
        'dana_research',
      ], stage: ProxyDelegationStage.submitting);
      return scenario;
    }

    testWidgets('shows the delegation\'s rows in place of the platform '
        'progress', (tester) async {
      await pumpStatus(
        tester,
        scenario: committed(),
        job: const VotingSubmissionJobState(
          key: _key,
          status: VotingSubmissionJobStatus.running,
          kind: VotingSubmissionJobKind.ballot,
        ),
      );
      expect(find.text('platform progress'), findsNothing);
      expect(
        find.text('Delegating to @alice_votes and @dana_research'),
        findsOne,
      );
      expect(find.text('Casting votes and submitting shares'), findsOne);
    });

    testWidgets('a refused delegation shows one notice that it keeps '
        'trying', (tester) async {
      final scenario = committed();
      await pumpStatus(
        tester,
        scenario: scenario,
        job: VotingSubmissionJobState(
          key: _key,
          status: VotingSubmissionJobStatus.running,
          kind: VotingSubmissionJobKind.proxy,
          proxyProgress: proxyProgress(
            delegations: scenario.status!.delegations,
            refusedByChain: true,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('proxy_progress_refused')), findsOne);
      expect(find.text(testL10n.proxyRefused), findsOne);
      expect(
        find.text('Delegating to @alice_votes and @dana_research'),
        findsOne,
      );
    });

    testWidgets('with the dormant flag off the rows are the vote\'s own', (
      tester,
    ) async {
      await pumpStatus(
        tester,
        scenario: committed(),
        enabled: false,
        job: const VotingSubmissionJobState(
          key: _key,
          status: VotingSubmissionJobStatus.running,
        ),
      );
      expect(find.text('platform progress'), findsOne);
      expect(find.textContaining('Delegating to'), findsNothing);
    });
  });
}
