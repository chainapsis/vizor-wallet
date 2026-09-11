import 'dart:io';
import 'dart:convert';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_entry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_participation_provider.dart';
import 'package:zcash_wallet/src/features/voting/voting_poll_ordering.dart';
import 'package:zcash_wallet/src/services/voting/voting_participation_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as voting_rust;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import 'mobile_regtest_flow.dart';

const _roundId = String.fromEnvironment('ZCASH_E2E_VOTE_ROUND_ID');

Future<void> initializeMobileVotingRegtestRuntime() async {
  if (kZcashDefaultNetworkName != 'regtest') throw StateError('regtest only');
  await initializeZcashWalletRuntime();
  await voting_rust.configureRegtestVotingParticipation(
    chainId: const String.fromEnvironment('ZCASH_E2E_VOTE_CHAIN_ID'),
    validatorHash: const String.fromEnvironment(
      'ZCASH_E2E_VOTE_VALIDATOR_HASH',
    ),
  );
}

Future<Widget> buildMobileVotingRegtestApp() => buildBootstrappedZcashWalletApp(
  overrides: [
    votingParticipationSourceSupportedProvider.overrideWithValue(
      (network, source) =>
          network == 'regtest' && source == kE2eStaticVotingConfigSource,
    ),
    votingParticipationClientProvider.overrideWith((ref) {
      final http = DartIoVotingHttpClient();
      ref.onDispose(() => http.close(force: true));
      return VotingParticipationClient(
        http,
        const VotingParticipationBridge(),
        cache: ref.read(votingFileCacheProvider),
        regtestEndpoint: Uri.parse(
          const String.fromEnvironment('ZCASH_E2E_VOTING_GATEWAY_URL'),
        ),
      );
    }),
  ],
);

Future<void> expectVotingHomeHidden(
  WidgetTester tester,
  ProviderContainer container, {
  required bool restored,
}) async {
  String? lastObservation;
  await pumpUntil(
    tester,
    () {
      final account = container.read(accountProvider).value?.activeAccountUuid;
      final source = container
          .read(votingConfigSourceProvider)
          .value
          ?.sourceUrl;
      if (account == null || source == null) return false;
      final cache = container.read(votingHomeCacheProvider.notifier);
      final list = cache.list(votingHomeListKey('regtest', source));
      if (list == null) return false;
      final rounds = list.rounds.where((r) => r.roundId == _roundId).toList();
      if (rounds.length != 1 ||
          votingPollListStatus(rounds.single.status) !=
              VotingPollListStatus.active) {
        return false;
      }
      final end = votingRoundEndDate(rounds.single.rawJson);
      if (end != null && !DateTime.now().isBefore(end)) {
        fail('Round expired before the Home assertion');
      }
      final fact = cache.fact(
        votingHomeFactKey('regtest', list.fingerprint, account, _roundId),
      );
      final observation =
          'decision=${fact.decision.name} progress=${fact.progress.name} '
          'scanned=${container.read(syncProvider).value?.scannedHeight} '
          'snapshot=${fact.snapshotHeight} used=${fact.participation?.usedCount} '
          'remaining=${fact.participation?.remainingEligible} local=${fact.participation?.localState} '
          'card=${tester.any(find.byKey(const ValueKey('mobile_home_coinholder_voting')))}';
      if (observation != lastObservation) {
        logE2e('Home assertion: $observation');
        lastObservation = observation;
      }
      if (fact.decision != VotingHomeDecision.hide) return false;
      if (restored) {
        if (fact.participation?.unavailable != true ||
            fact.participation!.usedCount == 0 ||
            fact.participation!.localState) {
          return false;
        }
        if (fact.progress != VotingHomeProgress.unknown) {
          fail('Restored check used old local progress');
        }
        if ((container.read(syncProvider).value?.scannedHeight ?? 0) <
            (fact.snapshotHeight ?? 1)) {
          return false;
        }
      } else if (fact.progress != VotingHomeProgress.completed) {
        return false;
      }
      return tester.any(find.byKey(const ValueKey('mobile_home_send'))) &&
          !tester.any(
            find.byKey(const ValueKey('mobile_home_coinholder_voting')),
          );
    },
    description: restored
        ? 'verified restored participation hides Home card'
        : 'completed local voting hides Home card',
    timeout: const Duration(minutes: 10),
  );
  expect(
    find.byKey(const ValueKey('mobile_home_coinholder_voting')),
    findsNothing,
  );
}

Future<void> expectVotingRecheckUsesDiskCache(
  ProviderContainer container,
) async {
  final requests = await participationRequestCount();
  // Drop client memory; preserve the production file store and crypto bridge.
  container.invalidate(votingParticipationClientProvider);
  final beforeCheck = container.read(votingHomeCacheProvider);
  await container
      .read(votingParticipationProvider)
      .checkRound(_roundId, force: true);
  expect(
    container.read(votingHomeCacheProvider),
    greaterThan(beforeCheck),
    reason: 'Forced reevaluation must succeed, not silently fail',
  );
  expect(
    await participationRequestCount(),
    requests,
    reason: 'A new client must reuse persisted used/unused observations',
  );
}

/// Read the production file store; never seed/modify observations in E2E.
Future<void> expectVotingNoteCachePersisted(
  WidgetTester tester,
  ProviderContainer container, {
  required bool used,
}) async {
  final account = container
      .read(accountProvider)
      .requireValue
      .activeAccountUuid!;
  final source = container
      .read(votingConfigSourceProvider)
      .requireValue
      .sourceUrl;
  final cache = container.read(votingHomeCacheProvider.notifier);
  final list = cache.list(votingHomeListKey('regtest', source))!;
  final factKey = votingHomeFactKey(
    'regtest',
    list.fingerprint,
    account,
    _roundId,
  );
  final fact = cache.fact(factKey);
  expect(fact.snapshotHeight, isNotNull);
  final files = container.read(votingFileCacheProvider);
  final scope = jsonEncode([
    'regtest',
    _roundId,
    '${fact.snapshotHeight}',
    'governance-v1',
  ]);
  final notes = await files.readNotes(account, scope);
  // Compare aggregates only: failure logs must not expose governance keys.
  expect(
    notes.isNotEmpty,
    true,
    reason: 'Verified note observations must persist',
  );
  final usedCount = notes.values
      .where((note) => (note as Map)['used'] == true)
      .length;
  expect(
    usedCount > 0,
    used,
    reason: used
        ? 'Confirmed delegation must persist used notes'
        : 'Fresh round notes must persist as unused',
  );
  // Visibility can update before its serialized write finishes. Wait for the
  // saved decision too rather than mistaking the initial hidden UI for success.
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    final raw = await files.read(votingHomeCacheKey);
    if (raw != null) {
      final saved = (jsonDecode(raw) as Map)['facts'] as Map;
      if ((saved[factKey] as Map?)?['decision'] == fact.decision.name) return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('The confirmed Home decision was not persisted');
}

Future<void> captureVotingRegtest(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  await postDriver(
    '/screenshot',
    {'name': name},
    baseUrl: const String.fromEnvironment('ZCASH_E2E_VOTING_GATEWAY_URL'),
  );
}

Future<int> participationRequestCount() async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse(
        '${const String.fromEnvironment('ZCASH_E2E_VOTING_GATEWAY_URL')}/metrics',
      ),
    )).close();
    final text = await response.transform(const Utf8Decoder()).join();
    return (jsonDecode(text) as Map)['participation_requests'] as int;
  } finally {
    client.close(force: true);
  }
}

/// Exercise the real sync engine without replacing its state or Home decision.
/// Observe provider transitions too, so a brief hide between frames cannot pass.
Future<void> expectVotingHomeVisibleDuringResync(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final card = find.byKey(const ValueKey('mobile_home_coinholder_voting'));
  await pumpUntil(
    tester,
    () => container.read(syncProvider).value?.isSyncing == false,
    description: 'initial voting wallet sync finished',
  );
  expect(card, findsOneWidget);
  expect(container.read(votingHomeEntryVisibleProvider), true);
  final before = container.read(syncProvider).value!;
  final requests = await participationRequestCount();
  var hidden = false;
  var syncingFrames = 0;
  var captured = false;
  final visibility = container.listen(votingHomeEntryVisibleProvider, (
    _,
    next,
  ) {
    if (!next) hidden = true;
  });
  try {
    int? target;
    Object? miningError;
    final mining =
        postDriver(
          '/mine-for-home-sync',
          const {},
          baseUrl: const String.fromEnvironment('ZCASH_E2E_VOTING_GATEWAY_URL'),
        ).then<void>(
          (result) {
            target = result['height'] as int;
            // If tip polling already started the sync, the normal duplicate guard
            // leaves that operation running. Otherwise explicitly start real sync.
            container
                .read(syncProvider.notifier)
                .startSync(latestTipHeight: target);
          },
          onError: (Object error) {
            miningError = error;
          },
        );
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 16));
      if (miningError != null) throw miningError!;
      expect(
        hidden,
        false,
        reason: 'Confirmed Home visibility changed during resync',
      );
      expect(
        card,
        findsOneWidget,
        reason: 'Voting card disappeared during resync',
      );
      final sync = container.read(syncProvider).value!;
      if (sync.isSyncing) {
        syncingFrames++;
        if (!captured) {
          captured = true;
          // No extra pump here: capture the already-asserted syncing frame.
          await postDriver(
            '/screenshot',
            {'name': 'home-during-resync'},
            baseUrl: const String.fromEnvironment(
              'ZCASH_E2E_VOTING_GATEWAY_URL',
            ),
          );
        }
      }
      if (target != null &&
          !sync.isSyncing &&
          sync.scannedHeight >= target! &&
          sync.lastSyncCompletedAt != before.lastSyncCompletedAt) {
        break;
      }
    }
    await mining;
    expect(target, greaterThan(before.scannedHeight));
    expect(
      syncingFrames,
      greaterThan(0),
      reason: 'Must observe a rendered real sync frame',
    );
    final after = container.read(syncProvider).value!;
    expect(after.isSyncing, false);
    expect(after.scannedHeight, greaterThanOrEqualTo(target!));
    expect(after.lastSyncCompletedAt, isNot(before.lastSyncCompletedAt));
    await container.read(votingParticipationProvider).checkHomeCandidates();
    await tester.pump();
    expect(hidden, false);
    expect(card, findsOneWidget);
    expect(
      await participationRequestCount(),
      requests,
      reason: 'Blocks above the voting snapshot must reuse participation',
    );
    await captureVotingRegtest(tester, 'home-after-resync');
    logE2e(
      'voting Home stayed visible across real resync: '
      'from=${before.scannedHeight} to=${after.scannedHeight} '
      'syncingFrames=$syncingFrames extraParticipationRequests=0',
    );
  } finally {
    visibility.close();
  }
}

Future<void> completeMobileRegtestVote(WidgetTester tester) async {
  tolerateRenderOverflows();
  if (_roundId.length != 64) {
    fail('ZCASH_E2E_VOTE_ROUND_ID must be a 64-character round id.');
  }
  if (const String.fromEnvironment('ZCASH_E2E_VOTING_KEEP_APP_STATE') != '1') {
    addTearDown(cleanupE2eWalletState);
  }
  await cleanupE2eWalletState();

  await tester.pumpWidget(await buildMobileVotingRegtestApp());
  await importWalletViaPaste(
    tester,
    mnemonic: mobileIronwoodE2eMnemonic,
    birthdayHeight: 1,
    isFirstWallet: true,
  );

  logE2e('waiting for the confirmed Ironwood voting balance');
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_home_coinholder_voting'))),
    description: 'mobile voting entry point',
    timeout: const Duration(minutes: 5),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(const ValueKey('mobile_home_coinholder_voting'))),
  );

  await expectVotingNoteCachePersisted(tester, container, used: false);
  await expectVotingRecheckUsesDiskCache(container);
  await expectVotingHomeVisibleDuringResync(tester, container);
  await captureVotingRegtest(tester, 'before-vote');
  await tapWidget(tester, const ValueKey('mobile_home_coinholder_voting'));
  await tapAppButton(
    tester,
    ValueKey('voting_poll_action_$_roundId'),
    timeout: const Duration(minutes: 2),
  );

  await pumpUntil(
    tester,
    () {
      final session = container.read(votingSessionProvider(_roundId));
      return session.hasError || session.value?.round != null;
    },
    description: 'mobile voting session round to load',
    timeout: const Duration(minutes: 2),
  );
  var session = container.read(votingSessionProvider(_roundId));
  if (session.hasError) {
    fail('Voting session failed to load: ${session.error}');
  }
  await pumpUntil(
    tester,
    () {
      session = container.read(votingSessionProvider(_roundId));
      final value = session.value;
      return session.hasError ||
          value?.error != null ||
          value?.hasConfirmedVotingEligibility == true;
    },
    description: 'mobile Ironwood voting eligibility to confirm',
    timeout: const Duration(minutes: 10),
  );
  if (session.hasError) {
    fail('Voting eligibility failed: ${session.error}');
  }
  final eligibleSession = session.value!;
  if (!eligibleSession.hasConfirmedVotingEligibility) {
    fail(
      'Voting eligibility was rejected: '
      '${eligibleSession.error?.message ?? 'unknown error'}',
    );
  }

  final accountUuid = eligibleSession.accountUuid;
  expect(accountUuid, isNotNull);
  final draftKey = VotingSessionKey(
    roundId: _roundId,
    accountUuid: accountUuid!,
  );
  for (var proposalId = 1; proposalId <= 4; proposalId++) {
    final optionKey = ValueKey('voting_proposal_${proposalId}_option_0');
    await _scrollUntilVisible(tester, optionKey);
    await _tapVotingOption(
      tester,
      optionKey,
      timeout: const Duration(minutes: 2),
    );
    await pumpUntil(
      tester,
      () =>
          container.read(votingDraftProvider(draftKey)).choices[proposalId] ==
          0,
      description: 'mobile proposal $proposalId selection to persist',
    );
  }

  await _scrollUntilVisible(
    tester,
    const ValueKey('voting_review_answers_button'),
  );
  await tapAppButton(tester, const ValueKey('voting_review_answers_button'));
  await tapAppButton(tester, const ValueKey('voting_confirm_submit_button'));

  await pumpUntil(
    tester,
    () {
      final job = container.read(votingSubmissionJobProvider(draftKey));
      return job.isInFlight ||
          job.status == VotingSubmissionJobStatus.error ||
          job.status == VotingSubmissionJobStatus.complete;
    },
    description: 'mobile voting submission job to start',
    timeout: const Duration(minutes: 2),
  );
  var job = container.read(votingSubmissionJobProvider(draftKey));
  if (!job.isInFlight && job.status != VotingSubmissionJobStatus.complete) {
    fail('Voting submission did not start: ${job.errorMessage}');
  }

  logE2e('waiting on the voting progress screen for submission');
  await pumpUntil(tester, () {
    job = container.read(votingSubmissionJobProvider(draftKey));
    return tester.any(
          find.byKey(
            const ValueKey('mobile_voting_submission_progress_content'),
          ),
        ) ||
        job.status == VotingSubmissionJobStatus.complete ||
        job.status == VotingSubmissionJobStatus.error;
  }, description: 'mobile voting submission progress screen');

  logE2e('waiting for real mobile vote proofs and receipt');
  await pumpUntil(
    tester,
    () {
      job = container.read(votingSubmissionJobProvider(draftKey));
      return job.status == VotingSubmissionJobStatus.complete ||
          job.status == VotingSubmissionJobStatus.error;
    },
    description: 'mobile voting submission to finish',
    timeout: const Duration(minutes: 40),
  );
  if (job.status == VotingSubmissionJobStatus.error) {
    fail('Voting submission failed: ${job.errorMessage}');
  }
  expect(job.status, VotingSubmissionJobStatus.complete);

  const submittedTitleKey = ValueKey('mobile_voting_submitted_title');
  const submittedHomeButtonKey = ValueKey(
    'mobile_voting_submitted_home_button',
  );
  await pumpUntil(
    tester,
    () => tester.any(find.byKey(submittedHomeButtonKey)),
    description: 'mobile voted confirmation screen',
    timeout: const Duration(minutes: 2),
  );
  expect(find.byKey(submittedTitleKey), findsOneWidget);
  await tapAppButton(tester, submittedHomeButtonKey);
  await expectVotingHomeHidden(tester, container, restored: false);
  await expectVotingNoteCachePersisted(tester, container, used: true);
  await captureVotingRegtest(tester, 'completed-home');
}

Future<void> _tapVotingOption(
  WidgetTester tester,
  Key key, {
  required Duration timeout,
}) async {
  final row = find.byKey(key);
  final inkWell = find.descendant(of: row, matching: find.byType(InkWell));
  await pumpUntil(
    tester,
    () => tester.any(inkWell) && tester.widget<InkWell>(inkWell).onTap != null,
    description: '$key voting option to become enabled',
    timeout: timeout,
  );
  final hitTestable = inkWell.hitTestable();
  if (tester.any(hitTestable)) {
    await tester.tap(hitTestable);
  } else {
    tester.widget<InkWell>(inkWell).onTap!.call();
  }
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _scrollUntilVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (tester.any(finder)) {
    await tester.ensureVisible(finder);
    return;
  }
  final scrollable = find.byType(Scrollable).last;
  await pumpUntil(
    tester,
    () => tester.any(scrollable),
    description: 'mobile poll list for $key',
  );
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: scrollable,
    maxScrolls: 20,
  );
  await tester.pump(const Duration(milliseconds: 250));
}
