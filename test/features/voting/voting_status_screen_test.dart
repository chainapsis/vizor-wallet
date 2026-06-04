import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_proposal_detail_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_polls_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_review_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_results_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_submission_confirmation_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_api;
import 'package:zcash_wallet/src/rust/api/voting_config.dart'
    as rust_config_api;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
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
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';

import 'round_plan_test_utils.dart';
import 'tx_event_json_test_utils.dart';
import '../../services/voting/fake_voting_http.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  testWidgets('status screen requires software account without mnemonic', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi();
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..addAll({
          '/shielded-vote/v1/cast-vote': {
            'tx_hash': 'vote-tx',
            'code': 0,
            'log': '',
          },
          '/shielded-vote/v1/tx/vote-tx': {
            'height': 11,
            'code': 0,
            'log': '',
            'events': [
              {
                'type': 'cast_vote',
                'attributes': [
                  {'key': 'leaf_index', 'value': '1,2'},
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/shares': {'status': 'queued'},
        }),
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _NoMnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Software account required'));

    expect(find.text('Software account required'), findsOneWidget);
    expect(find.text('submission confirmed route'), findsNothing);
  });

  testWidgets('status screen reports empty draft as retryable error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(
      tester,
      find.text('Choose at least one vote before submitting.'),
    );

    expect(find.text('Choose at least one vote before submitting.'), findsOne);
    expect(find.text('Retry'), findsOne);
  });

  testWidgets('status screen clears failed submission progress', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(
      tester,
      find.text('Choose at least one vote before submitting.'),
    );

    expect(find.text('Choose at least one vote before submitting.'), findsOne);
    expect(
      find.byKey(const ValueKey('voting_status_clear_submission_error')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('voting_status_clear_submission_error')),
    );
    await tester.pumpAndSettle();

    expect(find.text('voting route'), findsOneWidget);
    expect(
      find.text('Choose at least one vote before submitting.'),
      findsNothing,
    );
  });

  testWidgets('status screen explains ineligible account voting failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      rust: _IneligibleVotingRustApi(),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    const message =
        'This account is not eligible for this poll. It had no eligible '
        'shielded funds at snapshot block 3,359,740. Switch to an eligible '
        'account to vote.';
    await _pumpUntilFound(tester, find.text(message));

    expect(find.text(message), findsOneWidget);
    expect(find.text('Voting failed.'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('status screen explains minimum voting eligibility failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      rust: _MinimumVotingEligibilityRustApi(),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 123. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text(message));

    expect(find.text(message), findsOneWidget);
    expect(find.text('Voting failed.'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('status screen revalidates eligibility before cast recovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(
        delegationWorkflows: const [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.confirmed,
            txHash: 'delegation-0',
            vanLeafPosition: 0,
          ),
        ],
      )
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List.fromList([1]),
        allDecided: false,
      );
    final rust = _MinimumVotingEligibilityRustApi(recoveryApi);
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: rust,
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 123. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text(message));

    expect(find.text(message), findsOneWidget);
    expect(rust.eligibilityCheckCalls, 1);
    expect(rust.voteCommitmentCalls, 0);
  });

  testWidgets('status screen revalidates eligibility before completion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        allDecided: true,
        completedVoteArtifact: true,
        completedForDisplay: true,
      );
    final rust = _MinimumVotingEligibilityRustApi(recoveryApi);
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: rust,
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 123. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text(message));

    expect(find.text(message), findsOneWidget);
    expect(find.text('submission confirmed route'), findsNothing);
    expect(rust.eligibilityCheckCalls, 1);
  });

  testWidgets('status screen retry keeps setup errors specific', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      rust: _IneligibleVotingRustApi(),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    const message =
        'This account is not eligible for this poll. It had no eligible '
        'shielded funds at snapshot block 3,359,740. Switch to an eligible '
        'account to vote.';
    await _pumpUntilFound(tester, find.text(message));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text(message));

    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('Voting could not continue'), findsNothing);
  });

  testWidgets('submitted route does not confirm incomplete current account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _submissionHarness(),
      ),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Submission not complete'));

    expect(find.text('Submission confirmed!'), findsNothing);
    expect(
      find.text('This account has not completed submission for this poll.'),
      findsOneWidget,
    );
  });

  testWidgets('submitted route does not confirm without eligibility', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final completedRoundPlan = apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: false,
      nextSteps: const [],
      openProposals: Uint32List(0),
      allDecided: true,
      completedVoteArtifact: true,
      completedForDisplay: true,
    );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      overrides: [
        votingSessionProvider(_roundId).overrideWith(
          () => _FailingEligibilityVotingSessionNotifier(
            VotingSessionState(
              roundId: _roundId,
              accountUuid: 'account-1',
              phase: VotingSessionPhase.done,
              roundPlan: completedRoundPlan,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _submissionHarness(),
      ),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 3,359,740. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text(message));

    expect(find.text(message), findsOneWidget);
    expect(find.text('Submission confirmed!'), findsNothing);
  });

  testWidgets('submitted route can retry eligibility refresh', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final completedRoundPlan = apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: false,
      nextSteps: const [],
      openProposals: Uint32List(0),
      allDecided: true,
      completedVoteArtifact: true,
      completedForDisplay: true,
    );
    late _RetryableEligibilityVotingSessionNotifier notifier;
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      overrides: [
        votingSessionProvider(_roundId).overrideWith(() {
          notifier = _RetryableEligibilityVotingSessionNotifier(
            VotingSessionState(
              roundId: _roundId,
              accountUuid: 'account-1',
              phase: VotingSessionPhase.done,
              roundPlan: completedRoundPlan,
            ),
          );
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _submissionHarness(),
      ),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Retry'));

    expect(find.text('Submission not complete'), findsOneWidget);
    expect(find.textContaining('temporary setup unavailable'), findsOneWidget);
    expect(notifier.refreshCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Submission confirmed!'));

    expect(find.text('Submission confirmed!'), findsOneWidget);
    expect(find.text('Voting power'), findsOneWidget);
    expect(find.text('0.000001 ZEC'), findsOneWidget);
    expect(notifier.refreshCalls, 2);
  });

  testWidgets(
    'submitted route refreshes poll rows before returning to vote menu',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1512, 982));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      late _CountingVotingConfigNotifier configNotifier;
      late _BlockingVotingRoundsNotifier roundsNotifier;
      final reloadGate = Completer<void>();
      final completedRoundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        allDecided: true,
        completedVoteArtifact: true,
        completedForDisplay: true,
      );
      final container = _statusContainer(
        accountOverride: _MnemonicAccountNotifier.new,
        overrides: [
          votingConfigProvider.overrideWith(() {
            configNotifier = _CountingVotingConfigNotifier();
            return configNotifier;
          }),
          votingSessionProvider(_roundId).overrideWith(
            () => _StaticVotingSessionNotifier(
              VotingSessionState(
                roundId: _roundId,
                accountUuid: 'account-1',
                phase: VotingSessionPhase.done,
                roundPlan: completedRoundPlan,
                eligibleWeightZatoshi: BigInt.from(100),
              ),
            ),
          ),
          votingRoundsProvider.overrideWith(() {
            roundsNotifier = _BlockingVotingRoundsNotifier(
              reloadGate.future,
              initialRows: const [
                VotingRoundView(
                  roundId: _roundId,
                  title: 'Stale poll',
                  status: 'active',
                ),
              ],
              refreshedRows: const [
                VotingRoundView(
                  roundId: _roundId,
                  title: 'Refreshed poll',
                  status: 'closed',
                ),
              ],
            );
            return roundsNotifier;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _submissionHarness(votingRoute: const VotingPollsScreen()),
        ),
      );
      await _pumpUntilFound(tester, find.text('Submission confirmed!'));

      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(configNotifier.refreshCount, 1);
      expect(roundsNotifier.reloadCount, 1);
      expect(find.text('Updating polls...'), findsOneWidget);
      expect(find.text('Updating...'), findsOneWidget);
      expect(find.text('Refreshed poll'), findsNothing);

      await tester.tap(find.text('Updating...'), warnIfMissed: false);
      await tester.pump();

      expect(configNotifier.refreshCount, 1);
      expect(roundsNotifier.reloadCount, 1);

      reloadGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Refreshed poll'), findsOneWidget);
      expect(find.text('View results'), findsOneWidget);
      expect(find.text('Stale poll'), findsNothing);
    },
  );

  testWidgets('status screen does not complete all-decided empty account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(bundleCount: 0)
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List(0),
        allDecided: true,
      );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(
      tester,
      find.text('Choose at least one vote before submitting.'),
    );

    expect(find.text('submission confirmed route'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.text('Choose at least one vote before submitting.'), findsOne);
  });

  testWidgets(
    'status screen polls delegation-only recovery before draft error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1512, 982));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      final http = FakeVotingHttpClient(
        responses: _votingHttpResponses()
          ..['/shielded-vote/v1/tx/delegation-tx'] = {
            'height': 10,
            'code': 0,
            'log': '',
            'events': [
              {
                'type': 'delegate_vote',
                'attributes': [
                  {'key': 'leaf_index', 'value': '0'},
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
      );
      final recoveryApi = _MutableVotingRecoveryApi()
        ..state = _recoveryState(
          bundleCount: 1,
          delegationWorkflows: const [
            rust_frb_types.DelegationRecoveryView(
              bundleIndex: 0,
              phase: 'submitted_delegation',
              txHash: 'delegation-tx',
              vanLeafPosition: null,
            ),
          ],
        )
        ..roundPlan = apiRoundPlan(
          roundId: _roundId,
          pendingRecovery: true,
          nextSteps: const [
            rust_wire.NextStepView(
              kind: 'poll_delegation',
              bundleIndex: 0,
              proposalId: 0,
              choice: 0,
              shareIndex: 0,
            ),
          ],
          openProposals: Uint32List.fromList(const [1]),
          allDecided: false,
        );
      final container = _statusContainer(
        http: http,
        accountOverride: _MnemonicAccountNotifier.new,
        recoveryApi: recoveryApi,
        rust: _VotingStatusRustApi(recoveryApi),
        hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _statusHarness(),
        ),
      );
      await tester.pumpAndSettle();
      await _pumpUntilFound(
        tester,
        find.text('Choose at least one vote before submitting.'),
      );

      expect(
        find.text('Choose at least one vote before submitting.'),
        findsOne,
      );
      expect(find.text('submission confirmed route'), findsNothing);
      expect(
        http.requests.any(
          (request) =>
              request.method == 'GET' &&
              request.uri.path == '/shielded-vote/v1/tx/delegation-tx',
        ),
        isTrue,
      );
      expect(recoveryApi.ballotIntents, isEmpty);
    },
  );

  testWidgets('status screen blocks mixed delegation recovery without draft', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/tx/delegation-tx'] = {
          'height': 10,
          'code': 0,
          'log': '',
          'events': [
            {
              'type': 'delegate_vote',
              'attributes': [
                {'key': 'leaf_index', 'value': '0'},
                {'key': 'vote_round_id', 'value': _roundId},
              ],
            },
          ],
        },
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(
        bundleCount: 2,
        delegationWorkflows: const [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: 'submitted_delegation',
            txHash: 'delegation-tx',
            vanLeafPosition: null,
          ),
        ],
      )
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'poll_delegation',
            bundleIndex: 0,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
          rust_wire.NextStepView(
            kind: 'delegate',
            bundleIndex: 1,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List.fromList(const [1]),
        allDecided: false,
      );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(
      tester,
      find.text('Choose at least one vote before submitting.'),
    );

    expect(find.text('Choose at least one vote before submitting.'), findsOne);
    expect(find.text('submission confirmed route'), findsNothing);
    expect(
      http.requests.any(
        (request) =>
            request.method == 'GET' &&
            request.uri.path == '/shielded-vote/v1/tx/delegation-tx',
      ),
      isFalse,
    );
  });

  testWidgets('status screen requires closed ballot for no-draft recovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'confirm_share',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List.fromList(const [2]),
        allDecided: false,
      );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(
      tester,
      find.text('Choose at least one vote before submitting.'),
    );

    expect(find.text('Choose at least one vote before submitting.'), findsOne);
    expect(find.text('submission confirmed route'), findsNothing);
    expect(recoveryApi.ballotIntents, isEmpty);
  });

  testWidgets('status screen resumes share recovery without draft choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final shareNullifier = Uint8List.fromList(List.filled(32, 1));
    final shareId = List.filled(32, '01').join();
    final share = rust_frb_types.ShareDelegationRecordView(
      roundId: _roundId,
      bundleIndex: 0,
      proposalId: 1,
      shareIndex: 0,
      sentToUrls: const ['https://voting.example'],
      nullifier: shareNullifier,
      phase: 'submitted_share',
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.zero,
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(
        delegationWorkflows: const [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.confirmed,
            txHash: 'delegation-0',
            vanLeafPosition: 0,
          ),
        ],
        shareDelegations: [share],
        unconfirmedShareDelegations: [share],
      )
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'confirm_share',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['https://voting.example/shielded-vote/v1/share-status/$_roundId/$shareId'] =
            {'status': 'confirmed'},
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('submission confirmed route'));

    expect(find.text('submission confirmed route'), findsOne);
    expect(
      find.text('Choose at least one vote before submitting.'),
      findsNothing,
    );
    expect(recoveryApi.ballotIntents, isEmpty);
  });

  testWidgets('hardware status screen resumes share recovery without Keystone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final shareNullifier = Uint8List.fromList(List.filled(32, 1));
    final shareId = List.filled(32, '01').join();
    final share = rust_frb_types.ShareDelegationRecordView(
      roundId: _roundId,
      bundleIndex: 0,
      proposalId: 1,
      shareIndex: 0,
      sentToUrls: const ['https://voting.example'],
      nullifier: shareNullifier,
      phase: 'submitted_share',
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.zero,
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(
        delegationWorkflows: const [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.confirmed,
            txHash: 'delegation-0',
            vanLeafPosition: 0,
          ),
        ],
        shareDelegations: [share],
        unconfirmedShareDelegations: [share],
      )
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'confirm_share',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['https://voting.example/shielded-vote/v1/share-status/$_roundId/$shareId'] =
            {'status': 'confirmed'},
    );
    final rust = _VotingStatusRustApi(recoveryApi);
    final container = _statusContainer(
      http: http,
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: rust,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('submission confirmed route'));

    expect(find.text('submission confirmed route'), findsOne);
    expect(find.text('Sign bundle 1 of 1'), findsNothing);
    expect(find.text('Scan signature'), findsNothing);
    expect(rust.eligibilityCheckCalls, 2);
    expect(rust.setupDelegationBundleCalls, 0);
    expect(rust.keystoneDelegationRequestCalls, 0);
    expect(recoveryApi.ballotIntents, isEmpty);
  });

  testWidgets('hardware status screen casts after delegated without Keystone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()
      ..['proposals'] = [
        _proposalJson(1, 'First proposal', ['Yes', 'No']),
        _proposalJson(2, 'Second proposal', ['Aye', 'Nay', 'Abstain']),
      ];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..addAll({
          '/shielded-vote/v1/cast-vote': {
            'tx_hash': 'vote-tx',
            'code': 0,
            'log': '',
          },
          '/shielded-vote/v1/tx/vote-tx': {
            'height': 11,
            'code': 0,
            'log': '',
            'events': [
              {
                'type': 'cast_vote',
                'attributes': [
                  {'key': 'leaf_index', 'value': '1,2'},
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/shares': {'status': 'queued'},
        }),
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(
        delegationWorkflows: const [
          rust_frb_types.DelegationRecoveryView(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.confirmed,
            txHash: 'delegation-0',
            vanLeafPosition: 0,
          ),
        ],
      )
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
    final rust = _VotingStatusRustApi(recoveryApi);
    final container = _statusContainer(
      http: http,
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: rust,
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container
        .read(
          votingDraftProvider(
            const VotingSessionKey(
              roundId: _roundId,
              accountUuid: 'hardware-1',
            ),
          ).notifier,
        )
        .setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('submission confirmed route'));

    expect(find.text('submission confirmed route'), findsOne);
    expect(find.text('Sign bundle 1 of 1'), findsNothing);
    expect(find.text('Scan signature'), findsNothing);
    expect(rust.eligibilityCheckCalls, 2);
    expect(rust.setupDelegationBundleCalls, 0);
    expect(rust.keystoneDelegationRequestCalls, 0);
    expect(
      http.requests.any(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/shielded-vote/v1/delegate-vote',
      ),
      isFalse,
    );
  });

  testWidgets('status screen keeps async session errors specific', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      activeAccountUuid: () => throw StateError('active account lookup failed'),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('active account lookup failed'), findsOne);
    expect(find.text('Voting session action failed.'), findsNothing);
    expect(find.text('Retry'), findsOne);
  });

  testWidgets(
    'status screen opens already completed job on confirmation route',
    (tester) async {
      const key = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');
      final container = _statusContainer(
        accountOverride: _MnemonicAccountNotifier.new,
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
                status: VotingSubmissionJobStatus.complete,
                generation: 1,
              ),
            ),
          ),
          votingSubmissionJobSessionProvider(key).overrideWithValue(
            AsyncValue.data(
              VotingSessionState(
                roundId: _roundId,
                accountUuid: 'account-1',
                phase: VotingSessionPhase.done,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _statusHarness(
            initialLocation: votingStatusRoute(
              _roundId,
              accountUuid: 'account-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('submission confirmed route'), findsOneWidget);
    },
  );

  testWidgets('status screen shows finalizing step before job completion', (
    tester,
  ) async {
    const key = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');
    final completedRoundPlan = apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: false,
      nextSteps: const [],
      openProposals: Uint32List(0),
      allDecided: true,
      completedVoteArtifact: true,
    );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
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
              accountUuid: 'account-1',
              phase: VotingSessionPhase.done,
              roundPlan: completedRoundPlan,
              voteSubmissionCompletedCount: 3,
              voteSubmissionTotalCount: 3,
              voteSubmissionProgress: 1,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _statusHarness(
          initialLocation: votingStatusRoute(
            _roundId,
            accountUuid: 'account-1',
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('Finalizing submission'));

    expect(find.text('Casting votes and submitting shares'), findsOneWidget);
    expect(find.text('Finalizing submission'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('submission confirmed route'), findsNothing);
  });

  testWidgets('status screen ignores stale completed plan for running draft', (
    tester,
  ) async {
    const key = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');
    final completedRoundPlan = apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: false,
      nextSteps: const [],
      openProposals: Uint32List.fromList(const [1]),
      allDecided: false,
      completedVoteArtifact: true,
      completedForDisplay: true,
    );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
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
              accountUuid: 'account-1',
              phase: VotingSessionPhase.done,
              roundPlan: completedRoundPlan,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _statusHarness(
          initialLocation: votingStatusRoute(
            _roundId,
            accountUuid: 'account-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Casting votes and submitting shares'), findsOneWidget);
    expect(find.text('Finalizing submission'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('submission confirmed route'), findsNothing);
  });

  testWidgets('proposal detail hides View more when description fits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final proposal = _proposalJson(1, 'First proposal', ['Yes', 'No'])
      ..['zip_number'] = 'ZIP 233'
      ..['forum_url'] = 'https://forum.zcashcommunity.com/t/zip-233';
    final round = _roundStatusJson()
      ..['summary'] = '[TEST] Max Proposals'
      ..['proposals'] = [proposal];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('[TEST] Max Proposals'), findsOneWidget);
    expect(find.text('Voting power 0.000001 ZEC'), findsOneWidget);
    expect(find.text('ZIP-233'), findsOneWidget);
    expect(find.text('Forum discussion'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Review answers'), findsOneWidget);
    expect(find.text('Start Voting'), findsNothing);
    expect(find.text('View more'), findsNothing);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(container.read(votingDraftProvider(_draftKey)).choices, {1: 0});

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(container.read(votingDraftProvider(_draftKey)).isEmpty, true);
  });

  testWidgets('proposal detail shows View more when description truncates', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final longDescription = List.filled(
      8,
      'This poll description should overflow the collapsed row.',
    ).join(' ');
    final round = _roundStatusJson()..['summary'] = longDescription;
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View more'), findsOneWidget);
  });

  testWidgets('proposal detail shows completed vote with stale local draft', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List.fromList(const [1]),
        allDecided: true,
        completedVoteArtifact: true,
        completedForDisplay: true,
        completedVoteDisplay: rust_wire.CompletedVoteDisplayView(
          choices: const [
            rust_wire.CompletedVoteChoiceView(proposalId: 1, choice: 0),
          ],
          votedAt: BigInt.from(1717260000),
        ),
      );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Voted'), findsOneWidget);
    expect(find.text('Review answers'), findsNothing);
  });

  testWidgets('proposal detail routes non-active rounds to results', (
    tester,
  ) async {
    final round = _roundStatusJson()..['status'] = 'pending';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: _MutableVotingRecoveryApi(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('results route'), findsOneWidget);
    expect(find.text('Review answers'), findsNothing);
  });

  testWidgets('review routes non-active rounds to results', (tester) async {
    final round = _roundStatusJson()..['status'] = 'pending';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: _MutableVotingRecoveryApi(),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(
          initialLocation: '/voting/poll/$_roundId/review',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('results route'), findsOneWidget);
    expect(find.text('Confirm & submit'), findsNothing);
  });

  testWidgets('proposal detail shows completed vote before eligibility loads', (
    tester,
  ) async {
    final round = _roundStatusJson()..['status'] = 'pending';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List.fromList(const [1]),
        allDecided: true,
        completedVoteArtifact: true,
        completedForDisplay: true,
        completedVoteDisplay: rust_wire.CompletedVoteDisplayView(
          choices: const [
            rust_wire.CompletedVoteChoiceView(proposalId: 1, choice: 0),
          ],
          votedAt: BigInt.from(1717260000),
        ),
      );
    final rust = _PendingVotingEligibilityRustApi(recoveryApi);
    addTearDown(rust.completeEligible);
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: rust,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await _pumpUntilFound(tester, find.textContaining('Voted'));
    await _pumpUntilCondition(tester, () => rust.eligibilityCheckCalls == 1);

    expect(find.textContaining('Voted'), findsOneWidget);
    expect(find.text('results route'), findsNothing);
  });

  testWidgets('proposal detail shows recovery before non-active redirect', (
    tester,
  ) async {
    final round = _roundStatusJson()..['status'] = 'pending';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    final sessionState = container.read(votingSessionProvider(_roundId)).value!;
    expect(sessionState.roundPlan?.blockingRecovery, isTrue);
    expect(find.text('Vote in progress'), findsOneWidget);
    expect(find.text('Continue voting'), findsOneWidget);
    expect(find.text('results route'), findsNothing);
  });

  testWidgets('poll stops preparing voting power when setup fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _FailingVotingPowerRustApi(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Voting power unavailable'), findsOneWidget);
    expect(find.text('Retry eligibility'), findsOneWidget);
    expect(find.text('Preparing voting power'), findsNothing);
  });

  testWidgets('poll retries voting power from error state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi();
    final rust = _RetryableVotingPowerRustApi(recoveryApi);
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: rust,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Retry eligibility'));

    expect(rust.eligibilityCheckCalls, 1);

    await tester.tap(find.text('Retry eligibility'));
    await _pumpUntilCondition(tester, () => rust.eligibilityCheckCalls == 2);
    await tester.pumpAndSettle();

    expect(rust.eligibilityCheckCalls, 2);
    expect(find.text('Retry eligibility'), findsNothing);
    expect(find.text('Review answers'), findsOneWidget);
  });

  testWidgets('proposal detail shows read-only options when eligibility fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _MinimumVotingEligibilityRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 123. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text('Not eligible'));

    expect(find.text(message), findsNothing);
    expect(find.text('First proposal'), findsOneWidget);
    expect(find.text('Voting power 0 ZEC'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Review answers'), findsNothing);
    expect(find.text('Not eligible'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(container.read(votingDraftProvider(_draftKey)).isEmpty, true);
    expect(find.text('Not eligible for this poll'), findsOneWidget);
    expect(find.text(message), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not eligible'));
    await tester.pumpAndSettle();

    expect(find.text('Not eligible for this poll'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('proposal detail hides completed vote when eligibility fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: false,
        nextSteps: const [],
        openProposals: Uint32List.fromList(const [1]),
        allDecided: true,
        completedVoteArtifact: true,
        completedForDisplay: true,
        completedVoteDisplay: rust_wire.CompletedVoteDisplayView(
          choices: const [
            rust_wire.CompletedVoteChoiceView(proposalId: 1, choice: 0),
          ],
          votedAt: BigInt.from(1717260000),
        ),
      );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _MinimumVotingEligibilityRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 123. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text('Not eligible'));

    expect(find.text(message), findsNothing);
    expect(find.textContaining('Voted'), findsNothing);
    expect(find.text('Voting power 0 ZEC'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Review answers'), findsNothing);
  });

  testWidgets('proposal detail hides pending recovery when eligibility fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List.fromList([1]),
        allDecided: false,
        completedVoteArtifact: true,
      );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _MinimumVotingEligibilityRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 123. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text('Not eligible'));

    expect(find.text(message), findsNothing);
    expect(find.text('Vote in progress'), findsNothing);
    expect(find.text('Continue voting'), findsNothing);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Not eligible'), findsOneWidget);
  });

  testWidgets('review hides stale choices when eligibility fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _MinimumVotingEligibilityRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(
          initialLocation: '/voting/poll/$_roundId/review',
        ),
      ),
    );
    await tester.pumpAndSettle();

    const message =
        'Voting requires at least 5 eligible shielded notes totaling 0.125 ZEC '
        'at snapshot block 123. Switch to an eligible account to vote.';
    await _pumpUntilFound(tester, find.text(message));

    expect(find.text(message), findsOneWidget);
    expect(find.text('Yes'), findsNothing);
    final submitButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & submit'),
    );
    expect(submitButton.onPressed, isNull);
  });

  testWidgets('review disables submit until eligibility is confirmed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _FailingVotingPowerRustApi(),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(
          initialLocation: '/voting/poll/$_roundId/review',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Review your answers'));

    final submitButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & submit'),
    );
    expect(submitButton.onPressed, isNull);

    await tester.tap(find.text('Confirm & submit'));
    await tester.pumpAndSettle();

    expect(find.text('Review your answers'), findsOneWidget);
    expect(find.textContaining('status account:'), findsNothing);
  });

  testWidgets('results screen renders flat tally rows as ZEC totals', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    const optionDescription =
        'Mint option explanation for detail screens only.';
    final round = _roundStatusJson()
      ..['status'] = 'closed'
      ..['summary'] = 'Completed poll'
      ..['proposals'] = [
        _proposalJson(1, 'First proposal', ['Yes', 'No']),
        {
          'id': 2,
          'title': 'Second proposal',
          'zip_number': 'ZIP 231',
          'forum_url': 'https://forum.zcashcommunity.com/t/zip-231',
          'options': [
            {'index': 0, 'label': 'Mint', 'description': optionDescription},
            {'index': 1, 'label': 'Burn'},
          ],
        },
      ];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..['/shielded-vote/v1/tally-results/$_roundId'] = {
          'vote_round_id': _roundId,
          'results': [
            {'proposal_id': 1, 'total_value': 4},
            {'proposal_id': 1, 'vote_decision': 1, 'total_value': 2},
            {'proposal_id': 2, 'vote_decision': 0, 'total_value': 1},
          ],
        },
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(
        votes: const [
          rust_frb_types.VoteRecoveryView(
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            phase: VotingWorkflowPhase.submittedVote,
            hasCommitmentBundle: false,
          ),
        ],
      );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _resultsHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Poll'), findsOneWidget);
    expect(find.text('Completed poll'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('First proposal'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('0.50 ZEC'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('0.25 ZEC'), findsOneWidget);
    expect(find.text('Total: 0.75 ZEC'), findsOneWidget);
    expect(find.text('Voted: Yes'), findsOneWidget);
    expect(find.text('Second proposal'), findsOneWidget);
    expect(find.text('ZIP-231'), findsOneWidget);
    expect(find.text('Forum discussion'), findsOneWidget);
    expect(find.text('Mint'), findsOneWidget);
    expect(find.text(optionDescription), findsNothing);
    expect(find.text('0.13 ZEC'), findsOneWidget);
    expect(find.text('Burn'), findsOneWidget);
    expect(find.text('0.00 ZEC'), findsOneWidget);
  });

  testWidgets('results screen keeps empty tallies visible as zero rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()..['status'] = 'closed';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..['/shielded-vote/v1/tally-results/$_roundId'] = {
          'vote_round_id': _roundId,
          'results': const [],
        },
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _resultsHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('First proposal'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('0.00 ZEC'), findsNWidgets(2));
    expect(find.text('Results pending...'), findsNothing);
    expect(find.textContaining("Couldn't load results"), findsNothing);
  });

  testWidgets('results screen refreshes pending tally responses', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()..['status'] = 'tallying';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..['/shielded-vote/v1/tally-results/$_roundId'] =
            SequentialVotingHttpResponses([
              {'vote_round_id': _roundId, 'status': 'pending'},
              {
                'vote_round_id': _roundId,
                'results': [
                  {'proposal_id': 1, 'vote_decision': 0, 'total_value': 8},
                ],
              },
            ]),
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _resultsHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Results pending...'), findsOneWidget);
    expect(_tallyRequestCount(http), 1);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Results pending...'), findsNothing);
    expect(find.text('First proposal'), findsOneWidget);
    expect(find.text('1.00 ZEC'), findsOneWidget);
    expect(_tallyRequestCount(http), greaterThanOrEqualTo(2));
  });

  testWidgets('results screen treats not-ready tally errors as pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()..['status'] = '2';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..['/shielded-vote/v1/tally-results/$_roundId'] = jsonResponse({
          'error': 'tally not ready',
        }, statusCode: 404),
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _resultsHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Results pending...'), findsOneWidget);
    expect(find.textContaining("Couldn't load results"), findsNothing);
  });

  testWidgets('results screen surfaces non-pending tally errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()..['status'] = 'tallying';
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..['/shielded-vote/v1/tally-results/$_roundId'] = jsonResponse({
          'error': 'server unavailable',
        }, statusCode: 500),
    );
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _resultsHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Results pending...'), findsNothing);
    expect(find.textContaining("Couldn't load results"), findsOneWidget);
  });

  testWidgets('results screen rejects unauthenticated round ids', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final http = FakeVotingHttpClient(responses: _votingHttpResponses());
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _resultsHarness(
          initialLocation: '/voting/poll/$_unauthenticatedRoundId/results',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't load results"), findsOneWidget);
    expect(
      find.textContaining('not authenticated by voting config'),
      findsOneWidget,
    );
    expect(_tallyRequestCount(http, _unauthenticatedRoundId), 0);
  });

  testWidgets('reviewing partial votes warns and marks skipped rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final firstProposal = _proposalJson(1, 'First proposal', ['Yes', 'No'])
      ..['zip_number'] = 'ZIP 233';
    final round = _roundStatusJson()
      ..['forum_link'] = 'https://forum.zcashcommunity.com/t/zip-233'
      ..['proposals'] = [
        firstProposal,
        _proposalJson(2, 'Second proposal', ['Aye', 'Nay']),
      ];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _NoMnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review answers'));
    await tester.pumpAndSettle();

    expect(find.text('Skip unanswered questions?'), findsOneWidget);
    expect(
      find.textContaining('You have not answered 1 of 2 questions.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue to review'));
    await tester.pumpAndSettle();

    expect(find.text('Review your answers'), findsOneWidget);
    expect(find.text('Confirm & submit'), findsOneWidget);
    expect(find.text('ZIP-233'), findsOneWidget);
    expect(find.text('Forum discussion'), findsOneWidget);
    expect(find.text('First proposal'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Second proposal'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);

    await tester.tap(find.text('Confirm & submit'));
    await tester.pumpAndSettle();

    expect(find.text('status account: account-1'), findsOneWidget);
  });

  testWidgets('review uses short option label without option description', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final longDescription =
        'Keep the existing halving schedule for new ZEC. Only fees and '
        'donated funds are smoothed and reissued.';
    final round = _roundStatusJson()
      ..['proposals'] = [
        {
          'id': 1,
          'title': 'NSM issuance smoothing',
          'description': 'Question about the NSM issuance smoothing policy.',
          'options': [
            {
              'index': 0,
              'label': 'Preserve halvings',
              'description': longDescription,
            },
            {
              'index': 1,
              'label': 'Smooth issuance curve',
              'description': 'Replace halvings with a gradual issuance curve.',
            },
          ],
        },
      ];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _NoMnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preserve halvings'), findsOneWidget);
    expect(find.text(longDescription), findsOneWidget);

    await tester.tap(find.text('Preserve halvings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review answers'));
    await tester.pumpAndSettle();

    expect(find.text('Review your answers'), findsOneWidget);
    expect(find.text('Preserve halvings'), findsOneWidget);
    expect(find.text(longDescription), findsNothing);
  });

  testWidgets('review screen scrolls long ballots without overflowing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 520));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()
      ..['proposals'] = [
        for (var i = 1; i <= 15; i++)
          _proposalJson(i, 'Long proposal title number $i', [
            'A very long answer label that must not overflow the review row $i',
            'No',
          ]),
      ];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round},
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _NoMnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);
    final draftNotifier = container.read(
      votingDraftProvider(_draftKey).notifier,
    );
    for (var i = 1; i <= 15; i++) {
      draftNotifier.setChoice(i, 0);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(
          initialLocation: '/voting/poll/$_roundId/review',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);

    final submitButtonLabel = find.text('Confirm & submit');
    final submitButton = find.ancestor(
      of: submitButtonLabel,
      matching: find.byType(AppButton),
    );
    final reviewScrollView = find
        .descendant(
          of: find.byType(VotingReviewScreen),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    expect(submitButtonLabel, findsOneWidget);
    expect(submitButton, findsOneWidget);
    expect(tester.getBottomLeft(submitButton).dy, lessThanOrEqualTo(520));
    expect(
      tester.getBottomLeft(reviewScrollView).dy,
      lessThanOrEqualTo(tester.getTopLeft(submitButton).dy),
    );

    await tester.drag(reviewScrollView, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(submitButtonLabel, findsOneWidget);
    expect(submitButton, findsOneWidget);
    expect(tester.getBottomLeft(submitButton).dy, lessThanOrEqualTo(520));
    expect(
      tester.getBottomLeft(reviewScrollView).dy,
      lessThanOrEqualTo(tester.getTopLeft(submitButton).dy),
    );
  });

  testWidgets('pending vote continue keeps the session account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi()
      ..roundPlan = apiRoundPlan(
        roundId: _roundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_wire.NextStepView(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _proposalHarness(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue voting'));
    await tester.pumpAndSettle();

    expect(find.text('status account: account-1'), findsOneWidget);
  });

  testWidgets('status screen ignores stale start results after route change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    const staleKey = VotingSessionKey(
      roundId: 'round-a',
      accountUuid: 'account-a',
    );
    const currentKey = VotingSessionKey(
      roundId: 'round-b',
      accountUuid: 'account-b',
    );
    final firstStart = Completer<VotingSessionKey?>();
    final secondStart = Completer<VotingSessionKey?>();
    final starts = <VotingSessionKey>[];
    late final GoRouter router;
    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      overrides: [
        votingSubmissionJobsProvider.overrideWith(
          () => _ControlledVotingSubmissionJobsNotifier(
            starts: starts,
            completions: [firstStart, secondStart],
          ),
        ),
        votingSubmissionJobProvider(staleKey).overrideWith(
          () => _StaticVotingSubmissionJobNotifier(
            staleKey,
            const VotingSubmissionJobState(
              key: staleKey,
              status: VotingSubmissionJobStatus.error,
              generation: 1,
              errorMessage: 'stale key selected',
            ),
          ),
        ),
        votingSubmissionJobProvider(currentKey).overrideWith(
          () => _StaticVotingSubmissionJobNotifier(
            currentKey,
            const VotingSubmissionJobState(
              key: currentKey,
              status: VotingSubmissionJobStatus.running,
              generation: 1,
            ),
          ),
        ),
        votingSubmissionJobSessionProvider(staleKey).overrideWithValue(
          AsyncValue.data(
            VotingSessionState(
              roundId: 'round-a',
              accountUuid: 'account-a',
              phase: VotingSessionPhase.error,
            ),
          ),
        ),
        votingSubmissionJobSessionProvider(currentKey).overrideWithValue(
          AsyncValue.data(
            VotingSessionState(
              roundId: 'round-b',
              accountUuid: 'account-b',
              phase: VotingSessionPhase.submittingShares,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    router = GoRouter(
      initialLocation: '/voting/poll/round-a/status?account=account-a',
      routes: [
        GoRoute(
          path: '/voting/poll/:roundId/status',
          builder: (_, state) => VotingStatusScreen(
            roundId: state.pathParameters['roundId']!,
            accountUuid: state.uri.queryParameters['account'],
          ),
        ),
      ],
    );

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
    await tester.pump();

    router.go('/voting/poll/round-b/status?account=account-b');
    await tester.pump();
    firstStart.complete(staleKey);
    secondStart.complete(currentKey);
    await tester.pump();

    expect(starts, [staleKey, currentKey]);
    expect(find.text('stale key selected'), findsNothing);
    expect(find.text('Submitting votes'), findsOneWidget);
  });

  testWidgets('status screen navigates after successful submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()
      ..['proposals'] = [
        _proposalJson(1, 'First proposal', ['Yes', 'No']),
        _proposalJson(2, 'Second proposal', ['Aye', 'Nay', 'Abstain']),
      ];
    final shareId = List.filled(32, '01').join();
    final http = _GatedShareVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..addAll({
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
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/cast-vote': {
            'tx_hash': 'vote-tx',
            'code': 0,
            'log': '',
          },
          '/shielded-vote/v1/tx/vote-tx': {
            'height': 11,
            'code': 0,
            'log': '',
            'events': [
              {
                'type': 'cast_vote',
                'attributes': [
                  {'key': 'leaf_index', 'value': '1,2'},
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/shares': {'status': 'queued'},
          '/shielded-vote/v1/share-status/$_roundId/$shareId': {
            'status': 'confirmed',
          },
        }),
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(
        recoveryApi,
        shareTrackingDelaySeconds: BigInt.one,
      ),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirmed by helper'), findsNothing);
    await _pumpUntilCondition(
      tester,
      () => http.shareRequestStarted.isCompleted,
    );
    expect(http.shareRequestStarted.isCompleted, isTrue);

    expect(find.text('submission confirmed route'), findsNothing);
    expect(
      http.requests.any(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/shielded-vote/v1/shares',
      ),
      isTrue,
    );
    expect(
      http.requests.any(
        (request) => request.uri.path.contains('/share-status/'),
      ),
      isFalse,
    );

    http.allowShareResponse.complete();
    await _pumpUntilFound(tester, find.text('submission confirmed route'));

    expect(find.text('submission confirmed route'), findsOne);
    expect(
      find.text('Choose at least one vote before submitting.'),
      findsNothing,
    );
    expect(recoveryApi.ballotIntents, ['1:2:false:0', '2:3:true:null']);
    expect(
      http.requests.any(
        (request) => request.uri.path.contains('/share-status/'),
      ),
      isTrue,
    );

    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 20; i++) {
      if (http.requests.any(
        (request) => request.uri.path.contains('/share-status/'),
      )) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('submission confirmed route'), findsOne);
    expect(
      http.requests.any(
        (request) => request.uri.path.contains('/share-status/'),
      ),
      isTrue,
    );
  });

  testWidgets('hardware status screen scans Keystone signature and submits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()
      ..['proposals'] = [
        _proposalJson(1, 'First proposal', ['Yes', 'No']),
        _proposalJson(2, 'Second proposal', ['Aye', 'Nay', 'Abstain']),
      ];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..addAll({
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
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/cast-vote': {
            'tx_hash': 'vote-tx',
            'code': 0,
            'log': '',
          },
          '/shielded-vote/v1/tx/vote-tx': {
            'height': 11,
            'code': 0,
            'log': '',
            'events': [
              {
                'type': 'cast_vote',
                'attributes': [
                  {'key': 'leaf_index', 'value': '1,2'},
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/shares': {'status': 'queued'},
        }),
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container
        .read(
          votingDraftProvider(
            const VotingSessionKey(
              roundId: _roundId,
              accountUuid: 'hardware-1',
            ),
          ).notifier,
        )
        .setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _statusHarness(keystoneScanResult: const [3]),
      ),
    );
    await _pumpUntilFound(tester, find.text('Sign bundle 1 of 1'));

    expect(find.text('Sign bundle 1 of 1'), findsOneWidget);
    expect(find.text('Memo'), findsOneWidget);
    expect(find.textContaining('Amount: 0.00000100 ZEC'), findsOneWidget);
    expect(find.text('Scan signature'), findsOneWidget);
    expect(find.text('Software account required'), findsNothing);
    await tester.tap(find.text('Scan signature'));
    await tester.pumpAndSettle();

    expect(find.text('keystone scan route'), findsOneWidget);
    await tester.tap(find.text('Return Signature'));
    await _pumpUntilFound(tester, find.text('submission confirmed route'));

    expect(find.text('submission confirmed route'), findsOneWidget);
    expect(
      http.requests.any(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/shielded-vote/v1/delegate-vote',
      ),
      isTrue,
    );
    expect(recoveryApi.ballotIntents, ['1:2:false:0', '2:3:true:null']);
  });

  testWidgets('hardware status screen can skip unsigned Keystone bundles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final round = _roundStatusJson()
      ..['proposals'] = [
        _proposalJson(1, 'First proposal', ['Yes', 'No']),
        _proposalJson(2, 'Second proposal', ['Aye', 'Nay', 'Abstain']),
      ];
    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..['/shielded-vote/v1/round/$_roundId'] = {'round': round}
        ..addAll({
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
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/cast-vote': {
            'tx_hash': 'vote-tx',
            'code': 0,
            'log': '',
          },
          '/shielded-vote/v1/tx/vote-tx': {
            'height': 11,
            'code': 0,
            'log': '',
            'events': [
              {
                'type': 'cast_vote',
                'attributes': [
                  {'key': 'leaf_index', 'value': '1,2'},
                  {'key': 'vote_round_id', 'value': _roundId},
                ],
              },
            ],
          },
          '/shielded-vote/v1/shares': {'status': 'queued'},
        }),
    );
    final recoveryApi = _MutableVotingRecoveryApi()
      ..state = _recoveryState(bundleCount: 2);
    final container = _statusContainer(
      http: http,
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi, bundleCount: 2),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container
        .read(
          votingDraftProvider(
            const VotingSessionKey(
              roundId: _roundId,
              accountUuid: 'hardware-1',
            ),
          ).notifier,
        )
        .setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _statusHarness(keystoneScanResult: const [3]),
      ),
    );
    await _pumpUntilFound(tester, find.text('Sign bundle 1 of 2'));

    await tester.tap(find.text('Scan signature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return Signature'));
    await _pumpUntilFound(tester, find.text('Skip'));

    expect(find.text('Sign bundle 2 of 2'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Use signed bundles only?'), findsOneWidget);

    await tester.tap(find.text('Skip bundles'));
    await _pumpUntilFound(tester, find.text('submission confirmed route'));

    expect(find.text('submission confirmed route'), findsOneWidget);
    expect(
      http.requests.any(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/shielded-vote/v1/delegate-vote',
      ),
      isTrue,
    );
    expect(recoveryApi.ballotIntents, ['1:2:false:0', '2:3:true:null']);
  });

  testWidgets('hardware status screen scrolls in a short window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1152, 768));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container
        .read(
          votingDraftProvider(
            const VotingSessionKey(
              roundId: _roundId,
              accountUuid: 'hardware-1',
            ),
          ).notifier,
        )
        .setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await _pumpUntilFound(tester, find.text('Sign bundle 1 of 1'));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Sign bundle 1 of 1'), findsOneWidget);
  });

  testWidgets('hardware status screen shows retry when Keystone QR fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      _RustApiFake.failPcztEncoding = false;
      await tester.binding.setSurfaceSize(null);
    });
    _RustApiFake.failPcztEncoding = true;

    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container
        .read(
          votingDraftProvider(
            const VotingSessionKey(
              roundId: _roundId,
              accountUuid: 'hardware-1',
            ),
          ).notifier,
        )
        .setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await _pumpUntilFound(
      tester,
      find.textContaining('Failed to prepare Keystone voting QR'),
    );

    expect(
      find.textContaining('Failed to prepare Keystone voting QR'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Scan signature'), findsNothing);
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 50,
}) async {
  for (var i = 0; i < attempts; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'Timed out waiting for $finder.');
}

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 50,
}) async {
  for (var i = 0; i < attempts; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
}

ProviderContainer _statusContainer({
  FakeVotingHttpClient? http,
  AccountNotifier Function()? accountOverride,
  Future<String?> Function()? activeAccountUuid,
  bool accountIsHardware = false,
  Set<String>? hardwareAccountUuids,
  VotingRecoveryApi? recoveryApi,
  VotingRustApi? rust,
  VotingHotkeyStore? hotkeyStore,
  List<Override> overrides = const [],
}) {
  final effectiveHttp =
      http ?? FakeVotingHttpClient(responses: _votingHttpResponses());
  final effectiveHardwareAccountUuids =
      hardwareAccountUuids ??
      (accountIsHardware ? {'account-1', 'hardware-1'} : <String>{});
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(_NoopSyncNotifier.new),
      if (accountOverride != null)
        accountProvider.overrideWith(accountOverride),
      votingConfigSourceStoreProvider.overrideWithValue(
        _FakeVotingConfigSourceStore(),
      ),
      votingHttpClientProvider.overrideWithValue(effectiveHttp),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: effectiveHttp,
          sourceUrl: 'https://voting.example/static-voting-config.json',
          resolveStaticVotingConfig:
              ({required String source, required List<int> staticBytes}) async {
                return 'https://voting.example/dynamic-voting-config.json';
              },
          resolveVotingConfig:
              ({
                required String source,
                required List<int> staticBytes,
                required List<int> dynamicBytes,
                rust_config.ResolvedVotingConfig? previous,
              }) async {
                return rust_config_api.VotingConfigResolution(
                  config: rust_config.ResolvedVotingConfig(
                    sourceFingerprint: 'test-source-fingerprint',
                    trustedKeyFingerprint: 'test-trusted-key-fingerprint',
                    dynamicConfigFingerprint: 'test-dynamic-config-fingerprint',
                    voteServers: [
                      rust_config.ServiceEndpoint(
                        url: 'https://voting.example',
                        label: 'vote-primary',
                      ),
                    ],
                    pirEndpoints: [
                      rust_config.ServiceEndpoint(
                        url: 'https://pir.example',
                        label: 'pir-primary',
                      ),
                    ],
                    supportedVersions: rust_config.SupportedVersions(
                      pir: ['2.0'],
                      voteProtocol: '2.0',
                      tally: '2.0',
                      voteServer: '2.0',
                    ),
                    authenticatedRounds: [
                      rust_config.AuthenticatedRound(
                        roundId: _roundId,
                        eaPk: Uint8List.fromList([1, 2, 3]),
                      ),
                    ],
                    skippedRoundIds: [],
                    conditions: [],
                  ),
                  switchKind: rust_config.ConfigSwitchKind.initialLoad,
                );
              },
        ),
      ),
      votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
      votingActiveAccountUuidProvider.overrideWithValue(
        activeAccountUuid ?? () async => 'account-1',
      ),
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
        VotingRecoveryService(api: recoveryApi ?? _FakeVotingRecoveryApi()),
      ),
      votingDraftPersistenceProvider.overrideWithValue(
        _MemoryVotingDraftPersistence(),
      ),
      votingPirResolverProvider.overrideWithValue(
        const _MatchedPirSnapshotResolver(),
      ),
      votingRustApiProvider.overrideWithValue(rust ?? _NoopVotingRustApi()),
      votingWalletSyncReadinessCheckerProvider.overrideWithValue(
        _FakeVotingWalletSyncReadinessChecker(),
      ),
      votingWalletSyncStarterProvider.overrideWithValue(() {}),
      votingWalletSyncPollIntervalProvider.overrideWithValue(Duration.zero),
      if (hotkeyStore != null)
        votingHotkeyStoreProvider.overrideWithValue(hotkeyStore),
      votingTxConfirmationPollingProvider.overrideWithValue(
        const VotingTxConfirmationPolling(attempts: 1, delay: Duration.zero),
      ),
      ...overrides,
    ],
  );
}

Widget _statusHarness({
  List<int>? keystoneScanResult,
  String? initialLocation,
}) {
  final router = GoRouter(
    initialLocation: initialLocation ?? '/voting/poll/$_roundId/status',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/status',
        builder: (_, state) => VotingStatusScreen(
          roundId: state.pathParameters['roundId']!,
          accountUuid: state.uri.queryParameters['account'],
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/submitted',
        builder: (_, _) => const Text('submission confirmed route'),
      ),
      GoRoute(
        path: '/voting/keystone/scan',
        builder: (_, _) =>
            _ScanReturnScreen(result: keystoneScanResult ?? const [3]),
      ),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting route')),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings route'),
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

Widget _proposalHarness({String? initialLocation}) {
  final router = GoRouter(
    initialLocation: initialLocation ?? '/voting/poll/$_roundId',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId',
        builder: (_, state) => VotingProposalDetailScreen(
          roundId: state.pathParameters['roundId']!,
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/review',
        builder: (_, state) =>
            VotingReviewScreen(roundId: state.pathParameters['roundId']!),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/status',
        builder: (_, state) => Text(
          'status account: ${state.uri.queryParameters['account'] ?? ''}',
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/results',
        builder: (_, _) => const Text('results route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings route'),
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

Widget _submissionHarness({Widget votingRoute = const Text('voting route')}) {
  final router = GoRouter(
    initialLocation: '/voting/poll/$_roundId/submitted',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/submitted',
        builder: (_, state) => VotingSubmissionConfirmationScreen(
          roundId: state.pathParameters['roundId']!,
        ),
      ),
      GoRoute(path: '/voting', builder: (_, _) => votingRoute),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings route'),
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

Widget _resultsHarness({String? initialLocation}) {
  final router = GoRouter(
    initialLocation: initialLocation ?? '/voting/poll/$_roundId/results',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/results',
        builder: (_, state) =>
            VotingResultsScreen(roundId: state.pathParameters['roundId']!),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings route'),
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

class _ScanReturnScreen extends StatelessWidget {
  const _ScanReturnScreen({required this.result});

  final List<int> result;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('keystone scan route'),
          TextButton(
            onPressed: () => context.pop<List<int>>(result),
            child: const Text('Return Signature'),
          ),
        ],
      ),
    );
  }
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/voting/poll/$_roundId/status',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1votingstatusaddress',
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

Map<String, Object> _votingHttpResponses() => {
  'https://voting.example/static-voting-config.json': _staticConfigJson(),
  'https://voting.example/dynamic-voting-config.json': _dynamicConfigJson(),
  '/shielded-vote/v1/round/$_roundId': {'round': _roundStatusJson()},
  '/shielded-vote/v1/delegate-vote': {
    'tx_hash': 'delegation-tx',
    'code': 0,
    'log': '',
  },
  '/shielded-vote/v1/tx/delegation-tx': {
    'height': 11,
    'code': 0,
    'log': '',
    'events': [
      {
        'type': 'delegate_vote',
        'attributes': [
          {'key': 'leaf_index', 'value': '1'},
          {'key': 'vote_round_id', 'value': _roundId},
        ],
      },
    ],
  },
  '/shielded-vote/v1/cast-vote': {'tx_hash': 'vote-tx', 'code': 0, 'log': ''},
  '/shielded-vote/v1/tx/vote-tx': {
    'height': 11,
    'code': 0,
    'log': '',
    'events': [
      {
        'type': 'cast_vote',
        'attributes': [
          {'key': 'leaf_index', 'value': '1,2'},
          {'key': 'vote_round_id', 'value': _roundId},
        ],
      },
    ],
  },
  '/shielded-vote/v1/shares': {'status': 'queued'},
  'https://voting.example/shielded-vote/v1/share-status/$_roundId/$_shareIdOne':
      {'status': 'confirmed'},
};

int _tallyRequestCount(FakeVotingHttpClient http, [String? roundId]) {
  final targetRoundId = roundId ?? _roundId;
  return http.requests
      .where(
        (request) => request.uri.path.endsWith('/tally-results/$targetRoundId'),
      )
      .length;
}

const _roundId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _unauthenticatedRoundId =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _draftKey = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');
const _bytes1x32Base64 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _bytes2x32Base64 = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';
const _bytes3x32Base64 = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=';
const _shareIdOne =
    '0101010101010101010101010101010101010101010101010101010101010101';
const _bytes12x64Base64 =
    'DAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA==';

Map<String, dynamic> _staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _bytes1x32Base64},
  ],
};

Map<String, dynamic> _dynamicConfigJson() => {
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
    _roundId: {
      'auth_version': 1,
      'ea_pk': _bytes1x32Base64,
      'signatures': [
        {'key_id': 'demo', 'alg': 'ed25519', 'sig': _bytes12x64Base64},
      ],
    },
  },
};

Map<String, dynamic> _roundStatusJson() => {
  'vote_round_id': _roundId,
  'round_id': _roundId,
  'title': 'Poll',
  'status': 'active',
  'snapshot_height': 123,
  'ea_pk': _bytes1x32Base64,
  'nc_root': _bytes2x32Base64,
  'nullifier_imt_root': _bytes3x32Base64,
  'proposals': [
    _proposalJson(1, 'First proposal', ['Yes', 'No']),
  ],
};

Map<String, dynamic> _proposalJson(
  int id,
  String title,
  List<String> options,
) => {
  'id': id,
  'title': title,
  'options': [
    for (var index = 0; index < options.length; index++)
      {'index': index, 'label': options[index]},
  ],
};

rust_frb_types.RoundRecoveryStateView _recoveryState({
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
    roundId: _roundId,
    bundleCount: bundleCount,
    delegation: delegationByBundle.values.toList(),
    votes: votesByKey.values.toList(),
    commitmentBundles: commitmentBundles,
    shares: shareWorkflows,
    shareDelegations: shareDelegations,
    unconfirmedShareDelegations: unconfirmedShareDelegations,
  );
}

class _NoMnemonicAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _bootstrap.initialAccountState;

  @override
  Future<String?> getActiveMnemonic() async => null;

  @override
  Future<String?> getMnemonicForAccount(String uuid) async => null;
}

class _MnemonicAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _bootstrap.initialAccountState;

  @override
  Future<String?> getActiveMnemonic() async => 'abandon abandon abandon';

  @override
  Future<String?> getMnemonicForAccount(String uuid) async {
    return uuid == 'account-1' ? 'abandon abandon abandon' : null;
  }
}

class _HardwareAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'hardware-1',
        name: 'Keystone',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'hardware-1',
    activeAddress: 'u1hardwarevotingaddress',
  );
}

class _StaticVotingSubmissionJobNotifier extends VotingSubmissionJobNotifier {
  _StaticVotingSubmissionJobNotifier(super.key, this._initial);

  final VotingSubmissionJobState _initial;

  @override
  VotingSubmissionJobState build() => _initial;
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

class _ControlledVotingSubmissionJobsNotifier
    extends VotingSubmissionJobsNotifier {
  _ControlledVotingSubmissionJobsNotifier({
    required this.starts,
    required this.completions,
  });

  final List<VotingSessionKey> starts;
  final List<Completer<VotingSessionKey?>> completions;

  @override
  VotingSubmissionJobsState build() => const VotingSubmissionJobsState();

  @override
  Future<VotingSessionKey?> start(String roundId, {String? accountUuid}) {
    final key = VotingSessionKey(
      roundId: roundId,
      accountUuid: accountUuid ?? 'resolved-account',
    );
    starts.add(key);
    return completions[starts.length - 1].future;
  }
}

class _FakeVotingRecoveryApi implements VotingRecoveryApi {
  @override
  Future<void> addSentServers({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) async {}

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
    return _recoveryState();
  }

  @override
  Future<rust_wire.RoundPlanView> getRoundPlan({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<int> proposalIds,
  }) async {
    return apiRoundPlanFromRecoveryState(
      state: await getRoundRecoveryState(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
      ),
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
  }) async {}
}

class _MutableVotingRecoveryApi extends _FakeVotingRecoveryApi {
  rust_frb_types.RoundRecoveryStateView state = _recoveryState();
  rust_wire.RoundPlanView? roundPlan;
  final ballotIntents = <String>[];

  @override
  Future<rust_frb_types.RoundRecoveryStateView> getRoundRecoveryState({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) async {
    return state;
  }

  @override
  Future<rust_wire.RoundPlanView> getRoundPlan({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<int> proposalIds,
  }) async {
    return roundPlan ??
        super.getRoundPlan(
          dbPath: dbPath,
          accountUuid: accountUuid,
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
    ballotIntents.add('$proposalId:$numOptions:$skipped:${choice ?? 'null'}');
  }
}

class _StaticVotingSessionNotifier extends VotingSessionNotifier {
  _StaticVotingSessionNotifier(this._state) : super(_state.roundId);

  final VotingSessionState _state;

  @override
  Future<VotingSessionState> build() async => _state;

  @override
  Future<BigInt?> refreshEligibleWeight() async => _state.eligibleWeightZatoshi;
}

class _FailingEligibilityVotingSessionNotifier
    extends _StaticVotingSessionNotifier {
  _FailingEligibilityVotingSessionNotifier(super.state);

  @override
  Future<BigInt?> refreshEligibleWeight() async {
    throw Exception(
      'Invalid input: minimum voting eligibility requires at least 5 eligible '
      'notes and 12500000 zatoshi voting weight; selected 2 distinct eligible '
      'notes with 25000000 zatoshi voting weight at snapshot height 3359740',
    );
  }
}

class _RetryableEligibilityVotingSessionNotifier
    extends _StaticVotingSessionNotifier {
  _RetryableEligibilityVotingSessionNotifier(super.state);

  int refreshCalls = 0;

  @override
  Future<BigInt?> refreshEligibleWeight() async {
    refreshCalls++;
    if (refreshCalls == 1) {
      throw StateError('temporary setup unavailable');
    }
    final refreshed = _state.copyWith(eligibleWeightZatoshi: BigInt.from(100));
    state = AsyncData(refreshed);
    return refreshed.eligibleWeightZatoshi;
  }
}

class _CountingVotingConfigNotifier extends VotingConfigNotifier {
  int refreshCount = 0;

  @override
  Future<rust_config.ResolvedVotingConfig> build() async {
    return const rust_config.ResolvedVotingConfig(
      sourceFingerprint: 'source-fingerprint',
      trustedKeyFingerprint: 'trusted-key-fingerprint',
      dynamicConfigFingerprint: 'dynamic-config-fingerprint',
      voteServers: [],
      pirEndpoints: [],
      supportedVersions: rust_config.SupportedVersions(
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

class _BlockingVotingRoundsNotifier extends VotingRoundsNotifier {
  _BlockingVotingRoundsNotifier(
    this.reloadGate, {
    this.initialRows = const [],
    this.refreshedRows = const [],
  });

  final Future<void> reloadGate;
  final List<VotingRoundView> initialRows;
  final List<VotingRoundView> refreshedRows;
  int reloadCount = 0;

  @override
  Future<List<VotingRoundView>> build() async => initialRows;

  @override
  Future<void> reload() async {
    reloadCount++;
    state = const AsyncLoading<List<VotingRoundView>>();
    await reloadGate;
    state = AsyncData(refreshedRows);
  }
}

class _NoopVotingRustApi implements VotingRustApi {
  @override
  Future<rust_wire.VotingRoundParams> trustedVotingRoundParamsFromConfig({
    required rust_config.ResolvedVotingConfig config,
    required String roundId,
    required BigInt snapshotHeight,
    required List<int> ncRoot,
    required List<int> nullifierImtRoot,
  }) async {
    rust_config.AuthenticatedRound? matchedRound;
    for (final round in config.authenticatedRounds) {
      if (round.roundId == roundId) {
        matchedRound = round;
        break;
      }
    }
    return rust_wire.VotingRoundParams(
      voteRoundId: roundId,
      snapshotHeight: snapshotHeight,
      eaPk: matchedRound?.eaPk ?? Uint8List.fromList(const [1, 2, 3]),
      ncRoot: Uint8List.fromList(ncRoot),
      nullifierImtRoot: Uint8List.fromList(nullifierImtRoot),
    );
  }

  @override
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {}

  @override
  Future<void> resetVoteTree({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {}

  @override
  Future<List<int>> generateVotingHotkey({required String network}) async {
    return [9, 9, 9];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingVotingPowerRustApi extends _NoopVotingRustApi {
  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    throw StateError('snapshot setup unavailable');
  }
}

class _PendingVotingEligibilityRustApi extends _VotingStatusRustApi {
  _PendingVotingEligibilityRustApi(super.recoveryApi);

  final _eligibility = Completer<rust_api.ApiVotingEligibility>();

  void completeEligible() {
    if (_eligibility.isCompleted) return;
    _eligibility.complete(
      rust_api.ApiVotingEligibility(
        isEligible: true,
        distinctNoteCount: 5,
        eligibleWeightZatoshi: BigInt.from(100),
      ),
    );
  }

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) {
    eligibilityCheckCalls++;
    return _eligibility.future;
  }
}

class _RetryableVotingPowerRustApi extends _VotingStatusRustApi {
  _RetryableVotingPowerRustApi(super.recoveryApi);

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    eligibilityCheckCalls++;
    if (eligibilityCheckCalls == 1) {
      throw StateError('temporary setup unavailable');
    }
    return rust_api.ApiVotingEligibility(
      isEligible: true,
      distinctNoteCount: 5,
      eligibleWeightZatoshi: BigInt.from(100),
    );
  }
}

class _MinimumVotingEligibilityRustApi extends _VotingStatusRustApi {
  _MinimumVotingEligibilityRustApi([_MutableVotingRecoveryApi? recoveryApi])
    : super(recoveryApi ?? _MutableVotingRecoveryApi());

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    eligibilityCheckCalls++;
    return rust_api.ApiVotingEligibility(
      isEligible: false,
      distinctNoteCount: 2,
      eligibleWeightZatoshi: BigInt.from(25000000),
    );
  }
}

class _IneligibleVotingRustApi extends _VotingStatusRustApi {
  _IneligibleVotingRustApi() : super(_MutableVotingRecoveryApi());

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
    throw Exception(
      'Invalid input: no spendable voting notes at snapshot height 3359740',
    );
  }
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async {
    return SyncState();
  }
}

class _MatchedPirSnapshotResolver implements PirSnapshotResolver {
  const _MatchedPirSnapshotResolver();

  @override
  Future<PirSnapshotResolution> resolve({
    required List<Uri> endpoints,
    required int expectedSnapshotHeight,
  }) async {
    return PirSnapshotResolution(
      endpoint: Uri.parse('https://pir.example'),
      diagnostics: [
        PirSnapshotEndpointDiagnostic(
          endpoint: Uri.parse('https://pir.example'),
          status: PirSnapshotEndpointStatus.matched,
          reportedHeight: expectedSnapshotHeight,
        ),
      ],
    );
  }
}

class _FakeVotingConfigSourceStore implements VotingConfigSourceStore {
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

class _MemoryVotingDraftPersistence implements VotingDraftPersistence {
  final _drafts = <VotingSessionKey, VotingDraftState>{};
  final _deletedAccountUuids = <String>{};

  @override
  Future<VotingDraftState> load(VotingSessionKey key) async {
    return _drafts[key] ?? const VotingDraftState();
  }

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {
    if (_deletedAccountUuids.contains(key.accountUuid)) return;
    _drafts[key] = draft;
  }

  @override
  Future<void> deleteForAccount(String accountUuid) async {
    _deletedAccountUuids.add(accountUuid);
    _drafts.removeWhere((key, _) => key.accountUuid == accountUuid);
  }
}

class _FakeVotingWalletSyncReadinessChecker
    implements VotingWalletSyncReadinessChecker {
  @override
  Future<VotingWalletSyncReadiness> check({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  }) async {
    return VotingWalletSyncReadiness(
      scannedHeight: snapshotHeight,
      snapshotHeight: snapshotHeight,
      chainTipHeight: snapshotHeight,
    );
  }
}

class _FakeVotingHotkeyStore implements VotingHotkeyStore {
  const _FakeVotingHotkeyStore(this.hotkey);

  final List<int> hotkey;

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
  }) async {}

  @override
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) async {}
}

class _VotingStatusRustApi extends _NoopVotingRustApi {
  _VotingStatusRustApi(
    this.recoveryApi, {
    this.bundleCount = 1,
    this.shareTrackingDelaySeconds,
  });

  final _MutableVotingRecoveryApi recoveryApi;
  final int bundleCount;
  final BigInt? shareTrackingDelaySeconds;
  final storedKeystoneSignatures = <int, rust_wire.KeystoneSignatureRecord>{};
  int setupDelegationBundleCalls = 0;
  int eligibilityCheckCalls = 0;
  int keystoneDelegationRequestCalls = 0;
  int voteCommitmentCalls = 0;

  @override
  Future<rust_round.BundleLayout> setupDelegationBundles({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    setupDelegationBundleCalls++;
    return rust_round.BundleLayout(
      bundleCount: bundleCount,
      eligibleWeight: BigInt.from(100),
      droppedCount: 0,
    );
  }

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) async {
    eligibilityCheckCalls++;
    return rust_api.ApiVotingEligibility(
      isEligible: true,
      distinctNoteCount: 5,
      eligibleWeightZatoshi: BigInt.from(100),
    );
  }

  @override
  Future<rust_wire.DelegationPirPrecomputeResultView> precomputeDelegationPir({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) async {
    return rust_wire.DelegationPirPrecomputeResultView(
      cachedCount: 0,
      fetchedCount: 1,
      bundleCount: bundleCount,
      bundleIndex: bundleIndex,
    );
  }

  @override
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
    required String mnemonic,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) async* {
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
    return [42, 43, 44];
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
    final removed = storedKeystoneSignatures.keys
        .where((bundleIndex) => bundleIndex >= keepCount)
        .toList();
    for (final bundleIndex in removed) {
      storedKeystoneSignatures.remove(bundleIndex);
    }
    recoveryApi.state = _recoveryState(bundleCount: keepCount);
    return bundleCount - keepCount;
  }

  @override
  Future<rust_delegate.KeystoneSigningRequest> buildKeystoneDelegationRequest({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) async {
    keystoneDelegationRequestCalls++;
    return rust_delegate.KeystoneSigningRequest(
      pcztBytes: Uint8List.fromList(const [1]),
      redactedPcztBytes: Uint8List.fromList(const [2]),
      pcztSighash: Uint8List.fromList(const [3]),
      rk: Uint8List.fromList(const [4]),
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
  Future<rust_api.ParsedSignedVotingPczt> parseSignedVotingPczt({
    required List<int> signedPcztBytes,
    required int actionIndex,
  }) async {
    return rust_api.ParsedSignedVotingPczt(
      sighash: Uint8List.fromList(signedPcztBytes),
      spendAuthSig: Uint8List.fromList([5, actionIndex]),
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
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
  }) async* {
    final signature = storedKeystoneSignatures[bundleIndex];
    yield rust_api.ApiDelegationProofEvent(
      phase: 'result',
      proofProgress: null,
      signedDelegationPayload: rust_wire.SignedDelegationPayloadView(
        pcztBytes: Uint8List.fromList(const []),
        status: 'ready_for_submission',
        message: null,
        submission: rust_wire.DelegationSubmissionWire(
          rk: base64Encode(signature?.rk ?? const [4]),
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
        bundleCount: 1,
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
  Future<void> markDelegationSubmitted({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  }) async {}

  void _recordDelegationConfirmed({
    required int bundleIndex,
    required String txHash,
    required int vanLeafPosition,
  }) {
    recoveryApi.state = _recoveryState(
      delegationWorkflows: [
        rust_frb_types.DelegationRecoveryView(
          bundleIndex: bundleIndex,
          phase: VotingWorkflowPhase.confirmed,
          txHash: txHash,
          vanLeafPosition: vanLeafPosition,
        ),
      ],
    );
    recoveryApi.roundPlan = null;
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
    voteCommitmentCalls++;
    for (final draft in draftVotes) {
      yield rust_api.ApiVoteCommitEvent(
        phase: 'result',
        proposalId: draft.proposalId,
        bundleIndex: bundleIndex,
        proofProgress: null,
        commitments: _commitments(
          roundId: roundId,
          bundleIndex: bundleIndex,
          proposalId: draft.proposalId,
          choice: draft.choice,
        ),
      );
    }
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
    return [
      for (var i = 0; i < shareCount; i++)
        rust_share_policy.ShareSubmissionPlan(
          submitAt: BigInt.zero,
          targetCount: targetCount,
          targetServers: serverUrls.take(targetCount).toList(growable: false),
        ),
    ];
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
  }) async => shareTrackingDelaySeconds;

  @override
  Future<String> recoveredVoteShareWireJson({
    required String commitmentBundleJson,
    required int proposalId,
    required int shareIndex,
    required BigInt vcTreePosition,
    required BigInt submitAt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markVoteSubmitted({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) async {}

  void _recordVoteConfirmed({
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required int vanPosition,
    required BigInt vcTreePosition,
  }) {
    recoveryApi.state = _recoveryState(
      delegationWorkflows: [
        rust_frb_types.DelegationRecoveryView(
          bundleIndex: bundleIndex,
          phase: VotingWorkflowPhase.confirmed,
          txHash: 'delegation-tx',
          vanLeafPosition: vanPosition,
        ),
      ],
      votes: [
        rust_frb_types.VoteRecoveryView(
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          choice: 0,
          phase: VotingWorkflowPhase.confirmed,
          txHash: txHash,
          vcTreePosition: vcTreePosition,
          hasCommitmentBundle: true,
        ),
      ],
    );
    recoveryApi.roundPlan = null;
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
    final current = recoveryApi.state;
    bool matches(rust_frb_types.ShareDelegationRecordView share) {
      return share.roundId == roundId &&
          share.bundleIndex == bundleIndex &&
          share.proposalId == proposalId &&
          share.shareIndex == shareIndex;
    }

    final recorded = rust_frb_types.ShareDelegationRecordView(
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      sentToUrls: sentToUrls,
      nullifier: Uint8List.fromList(List.filled(32, shareIndex + 1)),
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: submitAt,
      createdAt: BigInt.zero,
    );
    final nextShares = [
      for (final share in current.shareDelegations)
        if (!matches(share)) share,
      recorded,
    ];
    final nextUnconfirmed = [
      for (final share in current.unconfirmedShareDelegations)
        if (!matches(share)) share,
      recorded,
    ];
    recoveryApi.state = _recoveryState(
      bundleCount: current.bundleCount,
      delegationWorkflows: current.delegation,
      votes: current.votes,
      commitmentBundles: current.commitmentBundles,
      shareWorkflows: current.shares,
      shareDelegations: nextShares,
      unconfirmedShareDelegations: nextUnconfirmed,
    );
    recoveryApi.roundPlan = null;
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
    final current = recoveryApi.state;
    bool matches(rust_frb_types.ShareDelegationRecordView share) {
      return share.roundId == roundId &&
          share.bundleIndex == bundleIndex &&
          share.proposalId == proposalId &&
          share.shareIndex == shareIndex;
    }

    rust_frb_types.ShareDelegationRecordView confirmed(
      rust_frb_types.ShareDelegationRecordView share,
    ) {
      return rust_frb_types.ShareDelegationRecordView(
        roundId: share.roundId,
        bundleIndex: share.bundleIndex,
        proposalId: share.proposalId,
        shareIndex: share.shareIndex,
        sentToUrls: share.sentToUrls,
        nullifier: share.nullifier,
        phase: 'confirmed',
        confirmed: true,
        submitAt: share.submitAt,
        createdAt: share.createdAt,
      );
    }

    final nextUnconfirmed = [
      for (final share in current.unconfirmedShareDelegations)
        if (!matches(share)) share,
    ];
    recoveryApi.state = rust_frb_types.RoundRecoveryStateView(
      roundId: current.roundId,
      bundleCount: current.bundleCount,
      delegation: current.delegation,
      votes: current.votes,
      commitmentBundles: current.commitmentBundles,
      shares: current.shares,
      shareDelegations: [
        for (final share in current.shareDelegations)
          if (matches(share)) confirmed(share) else share,
      ],
      unconfirmedShareDelegations: nextUnconfirmed,
    );
    recoveryApi.roundPlan = null;
  }
}

List<int> _bytesFromHex(String hex) {
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

rust_wire.SignedVoteCommitmentsView _commitments({
  required String roundId,
  required int bundleIndex,
  required int proposalId,
  required int choice,
}) {
  final wireShare = rust_types.WireEncryptedShare(
    c1: Uint8List.fromList(const [8]),
    c2: Uint8List.fromList(const [9]),
    shareIndex: 0,
  );
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
          proof: base64Encode(Uint8List.fromList(const [4])),
          voteRoundId: base64Encode(_bytesFromHex(roundId)),
          anchorHeight: 10,
          rVpk: base64Encode(Uint8List.fromList(List.filled(32, 13))),
          voteAuthSig: base64Encode(Uint8List.fromList(List.filled(64, 12))),
        ),
        shares: [
          rust_wire.VoteShareWire(
            sharesHash: base64Encode(Uint8List.fromList(List.filled(32, 7))),
            proposalId: proposalId,
            voteDecision: choice,
            encryptedShare: wireShare,
            shareIndex: wireShare.shareIndex,
            vcTreePosition: BigInt.from(9),
            allEncryptedShares: [wireShare],
            shareComms: [base64Encode(Uint8List.fromList(List.filled(32, 10)))],
            primaryBlind: base64Encode(Uint8List.fromList(List.filled(32, 11))),
            submitAt: BigInt.zero,
          ),
        ],
      ),
    ],
  );
}

class _GatedShareVotingHttpClient extends FakeVotingHttpClient {
  _GatedShareVotingHttpClient({required super.responses});

  final shareRequestStarted = Completer<void>();
  final allowShareResponse = Completer<void>();

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    if (uri.path != '/shielded-vote/v1/shares') {
      return super.postJson(uri, body, timeout: timeout);
    }
    requests.add(
      FakeVotingHttpRequest('POST', uri, body: body, timeout: timeout),
    );
    if (!shareRequestStarted.isCompleted) {
      shareRequestStarted.complete();
    }
    await allowShareResponse.future;
    return jsonResponse({'status': 'queued', 'share_id': '0102'});
  }
}

class _RustApiFake implements RustLibApi {
  static bool failPcztEncoding = false;

  @override
  Future<List<String>> crateApiKeystoneEncodePcztUrParts({
    required List<int> pcztBytes,
    required BigInt maxFragmentLen,
  }) async {
    if (failPcztEncoding) {
      throw StateError('forced PCZT encoding failure');
    }
    return const ['ur:zcash-pczt/test'];
  }

  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  void crateApiSyncCancelFullSync() {}

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  void crateApiSyncStopMempoolObserver() {}

  @override
  Stream<rust_sync.ApiMempoolTxEvent> crateApiSyncStartMempoolObserver({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
  }) {
    return const Stream.empty();
  }

  @override
  Stream<rust_sync.ApiSyncProgressEvent> crateApiSyncStartFullSync({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required int mode,
  }) {
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
