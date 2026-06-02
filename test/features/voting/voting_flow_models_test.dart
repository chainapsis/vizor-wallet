import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('proposal parser preserves explicit service proposal ids', () {
    final proposals = proposalsFromJson({
      'proposals': [
        {
          'id': 1,
          'title': 'First',
          'options': [
            {'index': 0, 'label': 'Yes'},
            {'index': 1, 'label': 'No'},
          ],
        },
        {
          'id': 2,
          'title': 'Second',
          'options': [
            {'index': 0, 'label': 'Abstain'},
            {'index': 1, 'label': 'Support'},
          ],
        },
      ],
    });

    expect(proposals.map((proposal) => proposal.id), [1, 2]);
    expect(proposals.first.options.map((option) => option.index), [0, 1]);
    expect(proposals.last.options.map((option) => option.label), [
      'Abstain',
      'Support',
    ]);
  });

  test('proposal parser rejects missing proposal ids', () {
    expect(
      () => proposalsFromJson({
        'proposals': [
          {'title': 'Missing id'},
        ],
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required int: id',
        ),
      ),
    );
  });

  test('proposal parser rejects ids outside Rust vote protocol range', () {
    expect(
      () => proposalsFromJson({
        'proposals': [
          {'id': 0, 'title': 'Zero'},
        ],
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'id must be 1..15, got 0',
        ),
      ),
    );
  });

  test('proposal parser rejects fractional proposal ids', () {
    expect(
      () => proposalsFromJson({
        'proposals': [
          {'id': 1.9, 'title': 'Fractional'},
        ],
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'id must be an integer',
        ),
      ),
    );
  });

  test('draft choices can be cleared by proposal id', () {
    final draft = const VotingDraftState()
        .setChoice(1, 0)
        .setChoice(2, 1)
        .clearChoice(1);

    expect(draft.choices, {2: 1});
    expect(draft.isEmpty, false);
    expect(draft.clearChoice(2).isEmpty, true);
  });

  test('secure draft persistence deletes matching account drafts', () async {
    const persistence = SecureVotingDraftPersistence();
    const removedAccountRoundOne = VotingSessionKey(
      accountUuid: 'account-1',
      roundId: 'round-1',
    );
    const removedAccountRoundTwo = VotingSessionKey(
      accountUuid: 'account-1',
      roundId: 'round-2',
    );
    const retainedAccountRound = VotingSessionKey(
      accountUuid: 'account-2',
      roundId: 'round-1',
    );

    await persistence.save(
      removedAccountRoundOne,
      const VotingDraftState(choices: {1: 0}),
    );
    await persistence.save(
      removedAccountRoundTwo,
      const VotingDraftState(choices: {2: 1}),
    );
    await persistence.save(
      retainedAccountRound,
      const VotingDraftState(choices: {3: 0}),
    );

    await persistence.deleteForAccount('account-1');
    await persistence.save(
      removedAccountRoundOne,
      const VotingDraftState(choices: {4: 1}),
    );

    expect((await persistence.load(removedAccountRoundOne)).isEmpty, true);
    expect((await persistence.load(removedAccountRoundTwo)).isEmpty, true);
    expect((await persistence.load(retainedAccountRound)).choices, {3: 0});
  });

  test('draft notifier merges early edits with persisted choices', () async {
    final key = const VotingSessionKey(
      roundId: 'round-1',
      accountUuid: 'account-1',
    );
    final persistence = _DelayedDraftPersistence();
    final container = ProviderContainer(
      overrides: [
        votingDraftPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    container.read(votingDraftProvider(key));
    final notifier = container.read(votingDraftProvider(key).notifier);
    notifier.setChoice(3, 0);

    expect(container.read(votingDraftProvider(key)).choices, {3: 0});

    persistence.completeLoad(const VotingDraftState(choices: {1: 0, 2: 1}));
    await notifier.ensureLoaded();
    await persistence.waitForSaveCount(1);

    expect(container.read(votingDraftProvider(key)).choices, {
      1: 0,
      2: 1,
      3: 0,
    });
    expect(persistence.saved.single.choices, {1: 0, 2: 1, 3: 0});
  });

  test('draft notifier applies early clears to persisted choices', () async {
    final key = const VotingSessionKey(
      roundId: 'round-1',
      accountUuid: 'account-1',
    );
    final persistence = _DelayedDraftPersistence();
    final container = ProviderContainer(
      overrides: [
        votingDraftPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    container.read(votingDraftProvider(key));
    final notifier = container.read(votingDraftProvider(key).notifier);
    notifier.clearChoice(1);

    persistence.completeLoad(const VotingDraftState(choices: {1: 0, 2: 1}));
    await notifier.ensureLoaded();
    await persistence.waitForSaveCount(1);

    expect(container.read(votingDraftProvider(key)).choices, {2: 1});
    expect(persistence.saved.single.choices, {2: 1});
  });
}

class _DelayedDraftPersistence implements VotingDraftPersistence {
  final _load = Completer<VotingDraftState>();
  final saved = <VotingDraftState>[];
  final _saveWaiters = <({int count, Completer<void> waiter})>[];

  @override
  Future<VotingDraftState> load(VotingSessionKey key) => _load.future;

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {
    saved.add(draft);
    for (final entry in _saveWaiters.toList()) {
      if (saved.length >= entry.count && !entry.waiter.isCompleted) {
        entry.waiter.complete();
        _saveWaiters.remove(entry);
      }
    }
  }

  @override
  Future<void> deleteForAccount(String accountUuid) async {}

  void completeLoad(VotingDraftState draft) {
    _load.complete(draft);
  }

  Future<void> waitForSaveCount(int count) {
    if (saved.length >= count) return Future.value();
    final waiter = Completer<void>();
    _saveWaiters.add((count: count, waiter: waiter));
    return waiter.future;
  }
}
