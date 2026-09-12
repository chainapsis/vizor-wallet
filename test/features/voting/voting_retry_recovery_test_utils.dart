import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import 'round_plan_test_utils.dart';

const _roundId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _key = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');
const _message =
    'an unclassified submission reservation survived process interruption';

/// Exercises the real Retry path while wallet readiness remains pending.
Future<void> expectVotingRetryClearsError(
  WidgetTester tester, {
  required Widget Function(String roundId) screenBuilder,
  required Size surfaceSize,
}) async {
  final readiness = Completer<void>();
  final session = _RetryRecoveryVotingSessionNotifier(_key, readiness);
  final container = ProviderContainer(
    overrides: [
      votingSubmissionJobsProvider.overrideWith(_InterruptedSubmissionJobs.new),
      votingSubmissionJobProvider(
        _key,
      ).overrideWith(() => _InterruptedSubmissionJob(_key)),
      votingSubmissionSessionProvider(_key).overrideWith(() => session),
      votingDraftPersistenceProvider.overrideWithValue(
        _EmptyDraftPersistence(),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    readiness.complete();
  });
  final router = GoRouter(
    initialLocation: '/voting/poll/$_roundId/status',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/status',
        builder: (_, state) => screenBuilder(state.pathParameters['roundId']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(_message), findsOneWidget);

  await tester.tap(find.text('Retry'));
  // Observe the first frame while the next attempt is blocked on readiness.
  await tester.pump();
  expect(session.readinessRequested, isTrue);
  expect(find.text('Voting failed.'), findsNothing);
  expect(find.text(_message), findsNothing);
  expect(find.text('Retry'), findsNothing);
  expect(
    container.read(votingSubmissionJobProvider(_key)).status,
    VotingSubmissionJobStatus.running,
  );
  expect(
    container.read(votingSubmissionSessionProvider(_key)).value!.phase,
    VotingSessionPhase.readyToVote,
  );
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.text('Voting failed.'), findsNothing);
}

class _InterruptedSubmissionJob extends VotingSubmissionJobNotifier {
  _InterruptedSubmissionJob(super.key);

  @override
  VotingSubmissionJobState build() => const VotingSubmissionJobState(
    key: _key,
    status: VotingSubmissionJobStatus.error,
    errorMessage: _message,
  );
}

class _InterruptedSubmissionJobs extends VotingSubmissionJobsNotifier {
  @override
  VotingSubmissionJobsState build() =>
      const VotingSubmissionJobsState(jobKeys: [_key]);

  @override
  Future<VotingSessionKey?> start(
    String roundId, {
    String? accountUuid,
  }) async => _key;
}

class _RetryRecoveryVotingSessionNotifier
    extends VotingSubmissionSessionNotifier {
  _RetryRecoveryVotingSessionNotifier(super.key, this._readiness);

  final Completer<void> _readiness;
  bool readinessRequested = false;

  @override
  Future<VotingSessionState> build() async => VotingSessionState(
    roundId: _roundId,
    accountUuid: _key.accountUuid,
    phase: VotingSessionPhase.error,
    error: const VotingSessionError(message: _message),
    roundPlan: apiRoundPlan(
      roundId: _roundId,
      primaryAction: rust_wire.RoundPlanActionKind.vote,
      allDecided: true,
      pendingRecovery: true,
      blockingRecovery: true,
      openProposals: Uint32List(0),
      nextSteps: const [
        rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.advanceVote,
          bundleIndex: 0,
          proposalId: 1,
          choice: 0,
          shareIndex: 0,
        ),
      ],
    ),
    eligibleWeightZatoshi: BigInt.from(100),
    round: VotingRoundDetails(
      roundId: _roundId,
      title: 'Test round',
      status: 'active',
      snapshotHeight: 3359740,
      eaPk: Uint8List(32),
      ncRoot: Uint8List(32),
      nullifierImtRoot: Uint8List(32),
      rawJson: const {
        'vote_end_time': 4102444800,
        'proposals': [
          {'id': 1, 'title': 'Test proposal'},
        ],
      },
    ),
  );

  @override
  Future<void> ensureWalletReadyForVoting() {
    readinessRequested = true;
    return _readiness.future;
  }
}

class _EmptyDraftPersistence implements VotingDraftPersistence {
  @override
  Future<VotingDraftState> load(VotingSessionKey key) async =>
      const VotingDraftState();

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {}

  @override
  Future<void> deleteForAccount(String accountUuid) async {}
}
