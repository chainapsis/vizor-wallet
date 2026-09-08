import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/voting_hotkey_store.dart';

const _key = (accountUuid: 'account-1', roundId: 'round-1');

void main() {
  test('other accounts and rounds do not wait for a pending hotkey', () async {
    final store = _HotkeyStore();
    final firstGeneration = Completer<List<int>>();
    addTearDown(() {
      if (!firstGeneration.isCompleted) firstGeneration.complete([1]);
    });
    var generations = 0;
    Future<List<int>> generate() async {
      final index = ++generations;
      return index == 1 ? firstGeneration.future : [index];
    }

    final first = store.service.getOrCreate(
      accountUuid: _key.accountUuid,
      roundId: _key.roundId,
      generate: generate,
      allowCreation: true,
    );
    await Future<void>.delayed(Duration.zero);
    for (final otherKey in const [
      (accountUuid: 'account-2', roundId: 'round-1'),
      (accountUuid: 'account-1', roundId: 'round-2'),
    ]) {
      final hotkey = await store.service.getOrCreate(
        accountUuid: otherKey.accountUuid,
        roundId: otherKey.roundId,
        generate: generate,
        allowCreation: true,
      );
      expect(hotkey, [generations]);
      expect(store.hotkeys[otherKey], hotkey);
    }
    expect(firstGeneration.isCompleted, isFalse);
    firstGeneration.complete([1]);
    expect(await first, [1]);
    expect(store.hotkeys, {
      _key: [1],
      (accountUuid: 'account-2', roundId: 'round-1'): [2],
      (accountUuid: 'account-1', roundId: 'round-2'): [3],
    });
  });

  test('callers share completion through the entire storage write', () async {
    final store = _HotkeyStore()..writeGate = Completer<void>();
    addTearDown(() {
      if (!store.writeGate!.isCompleted) store.writeGate!.complete();
    });
    var generations = 0;
    var completions = 0;
    final first = store.service.getOrCreate(
      accountUuid: _key.accountUuid,
      roundId: _key.roundId,
      generate: () async => [++generations],
      allowCreation: true,
    );
    first.then((_) => completions++);
    await store.writeStarted.future;
    final second = store.service.getOrCreate(
      accountUuid: _key.accountUuid,
      roundId: _key.roundId,
      generate: () async => fail('concurrent caller generated another key'),
      allowCreation: false,
    );
    second.then((_) => completions++);
    await Future<void>.delayed(Duration.zero);
    expect(completions, 0);
    expect(store.hotkeys, isEmpty);
    expect(generations, 1);
    expect(store.writes, 1);
    store.writeGate!.complete();
    expect(await first, [1]);
    expect(await second, [1]);
    expect(store.hotkeys[_key], [1]);
  });

  test('a failed write reaches all callers and can be retried', () async {
    final store = _HotkeyStore()..failWrites = true;
    var generations = 0;
    Future<List<int>> generate() async => [++generations];
    final first = store.service.getOrCreate(
      accountUuid: _key.accountUuid,
      roundId: _key.roundId,
      generate: generate,
      allowCreation: true,
    );
    final second = store.service.getOrCreate(
      accountUuid: _key.accountUuid,
      roundId: _key.roundId,
      generate: generate,
      allowCreation: true,
    );
    await Future.wait([
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError),
    ]);
    expect(generations, 1);
    expect(store.hotkeys, isEmpty);

    store.failWrites = false;
    final hotkey = await store.service.getOrCreate(
      accountUuid: _key.accountUuid,
      roundId: _key.roundId,
      generate: generate,
      allowCreation: true,
    );
    expect(hotkey, [2]);
    expect(store.hotkeys[_key], hotkey);
  });

  test(
    'completed operations reread storage and never replace a bound key',
    () async {
      final store = _HotkeyStore()..hotkeys[_key] = [9];
      var generations = 0;
      Future<List<int>> generate() async => [++generations];
      expect(
        await store.service.getOrCreate(
          accountUuid: _key.accountUuid,
          roundId: _key.roundId,
          generate: generate,
          allowCreation: false,
        ),
        [9],
      );
      await store.deleteHotkey(
        accountUuid: _key.accountUuid,
        roundId: _key.roundId,
      );
      await expectLater(
        store.service.getOrCreate(
          accountUuid: _key.accountUuid,
          roundId: _key.roundId,
          generate: generate,
          allowCreation: false,
        ),
        throwsA(isA<VotingHotkeyUnavailable>()),
      );
      expect(generations, 0);
      expect(store.hotkeys, isEmpty);
    },
  );
}

class _HotkeyStore {
  final hotkeys = <({String accountUuid, String roundId}), List<int>>{};
  late final service = VotingHotkeyStore(
    readHotkey: readHotkey,
    writeHotkey: writeHotkey,
    deleteHotkey: deleteHotkey,
  );
  bool failWrites = false;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  int writes = 0;

  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) async => hotkeys[(accountUuid: accountUuid, roundId: roundId)];

  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) async {
    writes++;
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (failWrites) throw StateError('injected secure storage write failure');
    hotkeys[(accountUuid: accountUuid, roundId: roundId)] = List<int>.from(
      hotkey,
    );
  }

  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) async {
    hotkeys.remove((accountUuid: accountUuid, roundId: roundId));
  }
}
