import 'package:zcash_wallet/src/services/voting/voting_participation_client.dart';
import 'dart:async';
import 'dart:convert';
import '../../fakes/memory_voting_home_cache_store.dart';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import '../../features/voting/round_plan_test_utils.dart';

const roundId =
    '0000000000000000000000000000000000000000000000000000000000000001';
const secondRoundId =
    '0000000000000000000000000000000000000000000000000000000000000002';
final now = DateTime.utc(2026, 9, 10);
final listKey = votingHomeListKey('main', 'source');
final factKey = votingHomeFactKey('main', 'fingerprint', 'account-a', roundId);

VotingRoundSummary round({
  String id = roundId,
  String title = 'Vote',
  String status = '1',
  DateTime? end,
}) => VotingRoundSummary.fromJson({
  'vote_round_id': id,
  'title': title,
  'status': status,
  if (end != null) 'vote_end_time': end.toIso8601String(),
});

void main() {
  late ProviderContainer container;
  late MemoryVotingHomeCacheStore store;
  late VotingHomeCacheNotifier cache;
  setUp(() {
    store = MemoryVotingHomeCacheStore();
    container = ProviderContainer(
      overrides: [votingHomeCacheStoreProvider.overrideWithValue(store)],
    );
    cache = container.read(votingHomeCacheProvider.notifier);
  });
  tearDown(() => container.dispose());

  Future<void> seed(List<VotingRoundSummary> rounds) => cache.recordList(
    listKey,
    VotingHomeRoundList(
      checkedAt: now,
      fingerprint: 'fingerprint',
      rounds: rounds,
    ),
  );
  bool visible({String account = 'account-a', bool showTest = false}) =>
      cache.shouldShow(
        listKey: listKey,
        network: 'main',
        accountUuid: account,
        showTestRounds: showTest,
        now: now,
      );

  const unused = VotingParticipationResult(
    fingerprint: 'notes',
    usedCount: 0,
    noteCount: 1,
    remainingEligible: true,
    localState: false,
  );
  const used = VotingParticipationResult(
    fingerprint: 'notes',
    usedCount: 1,
    noteCount: 1,
    remainingEligible: false,
    localState: false,
  );

  test(
    'compact persistence preserves decisions, deadlines and snapshot hints',
    () async {
      final end = now.add(const Duration(hours: 1));
      await seed([
        VotingRoundSummary.fromJson({
          'vote_round_id': roundId,
          'title': 'Vote',
          'status': '1',
          'snapshot_height': '500',
          'session': {'vote_end_time': end.millisecondsSinceEpoch ~/ 1000},
          'proposals': [
            {'description': List.filled(250000, 'x').join()},
          ],
        }),
      ]);
      await cache.recordParticipation(factKey, 500, unused);
      expect(visible(), true);
      expect(store.value!.length, lessThan(2000));
      final saved = jsonDecode(store.value!) as Map<String, dynamic>;
      final savedRound = saved['lists'][listKey]['rounds'][0] as Map;
      expect(savedRound.containsKey('proposals'), false);
      expect(savedRound.containsKey('session'), false);

      container.dispose();
      container = ProviderContainer(
        overrides: [votingHomeCacheStoreProvider.overrideWithValue(store)],
      );
      cache = container.read(votingHomeCacheProvider.notifier);
      await cache.ensureLoaded();
      expect(visible(), true);
      final restored = cache.list(listKey)!.rounds.single;
      expect(restored.roundId, roundId);
      expect(restored.title, 'Vote');
      expect(restored.status, '1');
      expect(restored.rawJson['snapshot_height'], 500);
      expect(
        cache.shouldShow(
          listKey: listKey,
          network: 'main',
          accountUuid: 'account-a',
          showTestRounds: false,
          now: end,
        ),
        false,
      );
      await cache.recordParticipation(factKey, 500, used);
      container.dispose();
      container = ProviderContainer(
        overrides: [votingHomeCacheStoreProvider.overrideWithValue(store)],
      );
      cache = container.read(votingHomeCacheProvider.notifier);
      await cache.ensureLoaded();
      expect(cache.fact(factKey).decision, VotingHomeDecision.hide);
      expect(visible(), false);
    },
  );

  test(
    'unknown and eligibility-only rounds stay hidden until participation succeeds',
    () async {
      await seed([round()]);
      expect(visible(), false);
      await cache.recordEligibility(factKey, true, 500);
      expect(visible(), false);
      await cache.recordParticipation(factKey, 500, unused);
      expect(visible(), true);
      expect(visible(account: 'account-b'), false);
      await cache.recordParticipation(factKey, 500, used);
      expect(visible(), false);
    },
  );

  test('no eligible notes is hidden even when unavailable is false', () async {
    await seed([round()]);
    const empty = VotingParticipationResult(
      fingerprint: 'empty',
      usedCount: 0,
      noteCount: 0,
      remainingEligible: false,
      localState: false,
    );
    expect(empty.unavailable, false);
    await cache.recordParticipation(factKey, 500, empty);
    expect(cache.fact(factKey).decision, VotingHomeDecision.hide);
    expect(visible(), false);
  });

  test('local records alone do not confirm an actionable recovery', () async {
    await seed([round()]);
    await cache.recordParticipation(
      factKey,
      500,
      const VotingParticipationResult(
        fingerprint: 'notes',
        usedCount: 1,
        noteCount: 1,
        remainingEligible: false,
        localState: true,
      ),
    );
    expect(visible(), false);
    expect(cache.fact(factKey).needsRecheck, true);
  });

  test('confirmed state survives recheck scheduling and restart', () async {
    await seed([round()]);
    for (final result in [unused, used]) {
      await cache.recordParticipation(factKey, 500, result);
      await cache.invalidateEligibilityAfterRewind(
        network: 'main',
        accountUuid: 'account-a',
        scannedHeight: 499,
        trigger: 'actual-rewind',
      );
      expect(visible(), result.remainingEligible);
      expect(cache.fact(factKey).needsRecheck, true);
      expect(cache.fact(factKey).participation, isNotNull);
      container.dispose();
      container = ProviderContainer(
        overrides: [votingHomeCacheStoreProvider.overrideWithValue(store)],
      );
      cache = container.read(votingHomeCacheProvider.notifier);
      expect(visible(), false);
      await cache.ensureLoaded();
      expect(visible(), result.remainingEligible);
      expect(cache.fact(factKey).needsRecheck, true);
    }
  });

  test(
    'incomplete negative observations preserve the previous decision',
    () async {
      const partial = VotingParticipationResult(
        fingerprint: 'partial',
        usedCount: 1,
        noteCount: 2,
        remainingEligible: false,
        localState: false,
        complete: false,
      );
      await seed([round()]);
      await cache.recordParticipation(factKey, 500, partial);
      expect(cache.fact(factKey).decision, VotingHomeDecision.unknown);
      expect(visible(), false);
      await cache.recordParticipation(factKey, 500, unused);
      await cache.recordParticipation(factKey, 500, partial);
      expect(visible(), true);
      expect(cache.fact(factKey).hasCheckedParticipation, false);
      expect(cache.fact(factKey).participation!.unavailable, false);
    },
  );

  test('only a confirmed active round keeps the entry visible', () async {
    await seed([round(), round(id: secondRoundId)]);
    await cache.recordParticipation(factKey, 500, used);
    expect(visible(), false);
    await cache.recordParticipation(
      votingHomeFactKey('main', 'fingerprint', 'account-a', secondRoundId),
      500,
      unused,
    );
    expect(visible(), true);
    await seed([]);
    expect(visible(), false);
    await seed([round(title: '[TEST] Vote')]);
    await cache.recordParticipation(factKey, 500, unused);
    expect(visible(), false);
    expect(visible(showTest: true), true);
    await seed([round(status: '3')]);
    expect(visible(), false);
    await seed([round(end: now)]);
    expect(visible(), false);
  });

  test(
    'eligibility improvement schedules recheck without erasing last decision',
    () async {
      await seed([round()]);
      await cache.recordParticipation(factKey, 500, unused);
      await cache.recordEligibility(factKey, false, 500);
      expect(visible(), false);
      await cache.recordEligibility(factKey, true, 500);
      expect(visible(), false);
      expect(cache.fact(factKey).hasCheckedParticipation, false);
      await cache.recordParticipation(factKey, 500, unused);
      expect(visible(), true);
      expect(cache.fact(factKey).hasCheckedParticipation, true);
    },
  );

  test('a changed round snapshot requires a new decision', () async {
    await seed([round()]);
    await cache.recordParticipation(factKey, 500, unused);
    expect(visible(), true);
    await seed([
      VotingRoundSummary.fromJson({...round().rawJson, 'snapshot_height': 600}),
    ]);
    expect(visible(), false);
    expect(cache.fact(factKey).decision, VotingHomeDecision.unknown);
  });

  test(
    'completion hides but partial votes and blocking recovery stay visible',
    () async {
      await seed([round()]);
      await cache.recordPlan(
        factKey,
        apiRoundPlan(
          roundId: roundId,
          pendingRecovery: false,
          nextSteps: [],
          openProposals: Uint32List(0),
          allDecided: true,
          completedForDisplay: true,
          needsDraftSetup: false,
        ),
      );
      expect(visible(), false);
      await cache.recordPlan(
        factKey,
        apiRoundPlan(
          roundId: roundId,
          pendingRecovery: false,
          nextSteps: [],
          openProposals: Uint32List.fromList([2]),
          allDecided: false,
          completedForDisplay: true,
          needsDraftSetup: false,
        ),
      );
      expect(visible(), true);
      await cache.recordEligibility(factKey, false, 500);
      await cache.recordPlan(
        factKey,
        apiRoundPlan(
          roundId: roundId,
          pendingRecovery: true,
          blockingRecovery: true,
          nextSteps: [],
          openProposals: Uint32List(0),
          allDecided: true,
        ),
      );
      expect(visible(), true);
    },
  );

  test('six-hour successful snapshot and facts survive restart', () async {
    await seed([round()]);
    await cache.recordEligibility(factKey, false, 500);
    container.dispose();
    container = ProviderContainer(
      overrides: [votingHomeCacheStoreProvider.overrideWithValue(store)],
    );
    cache = container.read(votingHomeCacheProvider.notifier);
    await cache.ensureLoaded();
    expect(visible(), false);
    expect(
      cache
          .list(listKey)!
          .isFresh(now.add(const Duration(hours: 5, minutes: 59))),
      true,
    );
    expect(
      cache.list(listKey)!.isFresh(now.add(const Duration(hours: 6))),
      false,
    );
    expect(
      cache.list(listKey)!.isFresh(now.subtract(const Duration(seconds: 1))),
      false,
    );
  });

  test('deletion waits for a write and clears only that account', () async {
    await seed([round()]);
    final registry = container.read(votingShareTrackingRegistryProvider);
    store.writeGate = Completer<void>();
    final writing = cache.recordEligibility(factKey, false, 500);
    await Future<void>.delayed(Duration.zero);
    var drained = false;
    final draining = registry.quiesceAndDrain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, false);
    store.writeGate!.complete();
    await writing;
    await draining;
    await cache.removeAccount('account-a');
    expect(visible(), false);
    registry.resume();
  });

  test('reset clears memory and quiescence prevents late writes', () async {
    await seed([round()]);
    final registry = container.read(votingShareTrackingRegistryProvider);
    await registry.quiesceAndDrain();
    cache.clearForReset();
    await cache.recordEligibility(factKey, false, 500);
    expect(cache.list(listKey), null);
    expect(cache.fact(factKey).eligibility, VotingHomeEligibility.unknown);
    registry.resume();
  });

  test('synchronous operation failure releases its discovery lease', () async {
    final action = Provider(
      (ref) =>
          () => observeVotingHomeResult<int>(
            ref,
            operation: () => throw StateError('query failed'),
            record: (_, _) async {},
          ),
    );
    await expectLater(container.read(action)(), throwsStateError);
    final registry = container.read(votingShareTrackingRegistryProvider);
    await registry.quiesceAndDrain().timeout(const Duration(seconds: 1));
    registry.resume();
  });

  test(
    'synchronous recording failure preserves result and releases lease',
    () async {
      final action = Provider(
        (ref) =>
            () => observeVotingHomeResult<int>(
              ref,
              operation: () async => 7,
              record: (_, _) => throw StateError('cache failed'),
            ),
      );
      expect(await container.read(action)(), 7);
      final registry = container.read(votingShareTrackingRegistryProvider);
      await registry.quiesceAndDrain().timeout(const Duration(seconds: 1));
      registry.resume();
    },
  );

  test('corrupt cache is treated as unverified', () async {
    store.value = '{broken';
    await cache.ensureLoaded();
    expect(visible(), false);
    await seed([round()]);
    expect(visible(), false);
  });
}
