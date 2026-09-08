import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_hotkey_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

const _key = VotingSessionKey(accountUuid: 'account-1', roundId: 'round-1');

void main() {
  test('other accounts and rounds do not wait for a pending hotkey', () async {
    final store = _HotkeyStore();
    final firstGeneration = Completer<List<int>>();
    addTearDown(() {
      if (!firstGeneration.isCompleted) firstGeneration.complete([1]);
    });
    var generations = 0;
    final coordinator = VotingHotkeyCoordinator(
      store: store,
      generateHotkey: ({required network}) async {
        final index = ++generations;
        return index == 1 ? firstGeneration.future : [index];
      },
    );
    final first = coordinator.ensureHotkey(
      key: _key,
      network: 'main',
      alreadyBound: false,
    );
    await Future<void>.delayed(Duration.zero);
    for (final otherKey in const [
      VotingSessionKey(accountUuid: 'account-2', roundId: 'round-1'),
      VotingSessionKey(accountUuid: 'account-1', roundId: 'round-2'),
    ]) {
      final hotkey = await coordinator.ensureHotkey(
        key: otherKey,
        network: 'main',
        alreadyBound: false,
      );
      expect(hotkey, [generations]);
      expect(store.hotkeys[otherKey], hotkey);
    }
    expect(firstGeneration.isCompleted, isFalse);
    firstGeneration.complete([1]);
    expect(await first, [1]);
    expect(store.hotkeys, {
      _key: [1],
      const VotingSessionKey(accountUuid: 'account-2', roundId: 'round-1'): [2],
      const VotingSessionKey(accountUuid: 'account-1', roundId: 'round-2'): [3],
    });
  });

  test('a failed write reaches all callers and can be retried', () async {
    final store = _HotkeyStore()..failWrites = true;
    var generations = 0;
    final coordinator = VotingHotkeyCoordinator(
      store: store,
      generateHotkey: ({required network}) async => [++generations],
    );
    final first = coordinator.ensureHotkey(
      key: _key,
      network: 'main',
      alreadyBound: false,
    );
    final second = coordinator.ensureHotkey(
      key: _key,
      network: 'main',
      alreadyBound: false,
    );
    await Future.wait([
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError),
    ]);
    expect(generations, 1);
    expect(store.hotkeys, isEmpty);

    store.failWrites = false;
    final hotkey = await coordinator.ensureHotkey(
      key: _key,
      network: 'main',
      alreadyBound: false,
    );
    expect(hotkey, [2]);
    expect(store.hotkeys[_key], hotkey);
  });

  test(
    'completed operations reread storage and never replace a bound key',
    () async {
      final store = _HotkeyStore()..hotkeys[_key] = [9];
      var generations = 0;
      final coordinator = VotingHotkeyCoordinator(
        store: store,
        generateHotkey: ({required network}) async => [++generations],
      );
      expect(
        await coordinator.ensureHotkey(
          key: _key,
          network: 'main',
          alreadyBound: true,
        ),
        [9],
      );
      await store.deleteHotkey(
        accountUuid: _key.accountUuid,
        roundId: _key.roundId,
      );
      await expectLater(
        coordinator.ensureHotkey(
          key: _key,
          network: 'main',
          alreadyBound: true,
        ),
        throwsA(isA<VotingHotkeyUnavailable>()),
      );
      expect(generations, 0);
      expect(store.hotkeys, isEmpty);
    },
  );
}

class _HotkeyStore implements VotingHotkeyStore {
  final hotkeys = <VotingSessionKey, List<int>>{};
  bool failWrites = false;

  @override
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) async =>
      hotkeys[VotingSessionKey(accountUuid: accountUuid, roundId: roundId)];

  @override
  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) async {
    if (failWrites) throw StateError('injected secure storage write failure');
    hotkeys[VotingSessionKey(accountUuid: accountUuid, roundId: roundId)] =
        List<int>.from(hotkey);
  }

  @override
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) async {
    hotkeys.remove(
      VotingSessionKey(accountUuid: accountUuid, roundId: roundId),
    );
  }
}
