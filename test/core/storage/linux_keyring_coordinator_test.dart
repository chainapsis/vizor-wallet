import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';

Future<void> drain() => Future<void>.delayed(Duration.zero);
Matcher code(String expected) =>
    isA<PlatformException>().having((error) => error.code, 'code', expected);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LinuxKeyringCoordinator coordinator;
  setUp(() => coordinator = LinuxKeyringCoordinator.testing());
  tearDown(() => coordinator.dispose());

  test(
    'a locked read stays pending until explicit retry returns its result',
    () async {
      var calls = 0;
      var completed = false;
      final read = coordinator
          .runStorageOperation(() async {
            if (++calls == 1) throw PlatformException(code: 'KeyringLocked');
            return 'same wallet';
          }, isRead: true)
          .then((value) {
            completed = true;
            return value;
          });
      await drain();
      expect(calls, 1);
      expect(completed, isFalse);
      expect(coordinator.state.phase, LinuxKeyringPhase.keyringLocked);
      await drain();
      expect(calls, 1);
      await coordinator.retry(requestId: coordinator.state.requestId!);
      expect(await read, 'same wallet');
      expect(calls, 2);
      expect(coordinator.state.phase, LinuxKeyringPhase.ready);
    },
  );

  test(
    'an in-flight native call has no retry or cancellation control',
    () async {
      final native = Completer<String>();
      final read = coordinator.runStorageOperation(
        () => native.future,
        isRead: true,
      );
      await drain();
      expect(coordinator.state.phase, LinuxKeyringPhase.working);
      expect(coordinator.state.canCancel, isFalse);
      expect(coordinator.state.canRetry, isFalse);
      await coordinator.retry(requestId: coordinator.state.requestId!);
      await coordinator.cancel(requestId: coordinator.state.requestId!);
      native.complete('value');
      expect(await read, 'value');
    },
  );

  test(
    'a following write waits through recovery of the preceding read',
    () async {
      final calls = <String>[];
      final read = coordinator.runStorageOperation(() async {
        calls.add('read');
        if (calls.length == 1) throw PlatformException(code: 'Libsecret error');
        return 'value';
      }, isRead: true);
      final write = coordinator.runStorageOperation(() async {
        calls.add('write');
      }, isRead: false);
      await drain();
      expect(calls, ['read']);
      await coordinator.retry(requestId: coordinator.state.requestId!);
      await Future.wait([read, write]);
      expect(calls, ['read', 'read', 'write']);
    },
  );

  test(
    'cancel abandons a failed read and releases the following request',
    () async {
      final read = coordinator.runStorageOperation(() async {
        throw PlatformException(code: 'KeyringLocked');
      }, isRead: true);
      final failure = expectLater(read, throwsA(code('storage_cancelled')));
      final next = coordinator.runStorageOperation(() async => 7, isRead: true);
      await drain();
      await coordinator.cancel(requestId: coordinator.state.requestId!);
      await failure;
      expect(await next, 7);
    },
  );

  test(
    'mutation ownership survives retry without replaying wallet work',
    () async {
      var walletCalls = 0;
      var nativeCalls = 0;
      final mutation = coordinator.runMutation(() async {
        walletCalls++;
        expect(await coordinator.runMutation(() async => 7), 7);
        return coordinator.runStorageOperation(() async {
          if (++nativeCalls == 1) {
            throw PlatformException(code: 'KeyringLocked');
          }
          return 42;
        }, isRead: true);
      });
      await drain();
      final requestId = coordinator.state.requestId!;
      await coordinator.cancel(requestId: requestId);
      expect(coordinator.hasPendingMutation, isTrue);
      expect(nativeCalls, 1);
      await expectLater(
        coordinator.runMutation(() async => fail('second mutation')),
        throwsA(isA<LinuxWalletMutationBusyException>()),
      );
      await coordinator.retry(requestId: requestId);
      expect(await mutation, 42);
      expect(walletCalls, 1);
      expect(nativeCalls, 2);
      expect(coordinator.hasPendingMutation, isFalse);
    },
  );

  test(
    'a positively rejected locked write can retry but cannot cancel',
    () async {
      var calls = 0;
      final write = coordinator.runStorageOperation(() async {
        if (++calls == 1) throw PlatformException(code: 'KeyringLocked');
      }, isRead: false);
      await drain();
      expect(coordinator.state.canCancel, isFalse);
      final requestId = coordinator.state.requestId!;
      await coordinator.cancel(requestId: requestId);
      expect(calls, 1);
      await coordinator.retry(requestId: requestId);
      await write;
      expect(calls, 2);
    },
  );

  for (final errorCode in [
    'Libsecret error',
    'SecretNotFound',
    'StorageError',
  ]) {
    test(
      'an ambiguous $errorCode write blocks later calls without replay',
      () async {
        var writes = 0;
        final write = coordinator.runStorageOperation(() async {
          writes++;
          throw PlatformException(code: errorCode);
        }, isRead: false);
        final failed = expectLater(write, throwsA(code(errorCode)));
        final following = coordinator.runStorageOperation(
          () async => fail('later call'),
          isRead: true,
        );
        final blocked = expectLater(
          following,
          throwsA(code('StorageOutcomeUnknown')),
        );
        await Future.wait([failed, blocked]);
        expect(coordinator.state.phase, LinuxKeyringPhase.outcomeUnknown);
        expect(coordinator.state.canRetry, isFalse);
        await coordinator.retry(requestId: 1);
        await coordinator.cancel(requestId: 1);
        expect(writes, 1);
        await expectLater(
          coordinator.runMutation(() async => fail('new mutation')),
          throwsA(isA<LinuxWalletMutationBusyException>()),
        );
      },
    );
  }

  test(
    'corrupt reads wait for explicit recovery without exposing an empty wallet',
    () async {
      var calls = 0;
      final read = coordinator.runStorageOperation(() async {
        if (++calls == 1) throw PlatformException(code: 'StorageError');
        return {'account': 'existing'};
      }, isRead: true);
      await drain();
      expect(coordinator.state.phase, LinuxKeyringPhase.storageCorrupt);
      await coordinator.retry(requestId: coordinator.state.requestId!);
      expect(await read, {'account': 'existing'});
    },
  );

  test(
    'stale and repeated actions cannot control the next failed request',
    () async {
      Future<int> locked() async =>
          throw PlatformException(code: 'KeyringLocked');
      final first = coordinator.runStorageOperation(locked, isRead: true);
      final firstFailure = expectLater(
        first,
        throwsA(code('storage_cancelled')),
      );
      await drain();
      final firstId = coordinator.state.requestId!;
      await coordinator.cancel(requestId: firstId);
      await firstFailure;
      var calls = 0;
      final next = coordinator.runStorageOperation(() async {
        calls++;
        return locked();
      }, isRead: true);
      final nextFailure = expectLater(next, throwsA(code('storage_cancelled')));
      await drain();
      final nextId = coordinator.state.requestId!;
      expect(nextId, isNot(firstId));
      await coordinator.retry(requestId: firstId);
      await coordinator.cancel(requestId: firstId);
      expect(calls, 1);
      expect(coordinator.state.requestId, nextId);
      await coordinator.cancel(requestId: nextId);
      await nextFailure;
    },
  );

  test(
    'unexpected programming errors are propagated without a recovery loop',
    () async {
      await expectLater(
        coordinator.runStorageOperation(() async {
          throw PlatformException(code: 'Bad arguments');
        }, isRead: false),
        throwsA(code('Bad arguments')),
      );
      expect(coordinator.state.phase, LinuxKeyringPhase.ready);
    },
  );

  test('other platforms propagate errors without Linux interception', () async {
    final disabled = LinuxKeyringCoordinator.testing(enabled: false);
    addTearDown(disabled.dispose);
    await expectLater(
      disabled.runStorageOperation(() async {
        throw PlatformException(code: 'KeyringLocked');
      }, isRead: true),
      throwsA(code('KeyringLocked')),
    );
    expect(disabled.state.phase, LinuxKeyringPhase.ready);
    expect(await disabled.runMutation(() async => 42), 42);
  });

  test('disposal releases recovery and prevents queued native calls', () async {
    final local = LinuxKeyringCoordinator.testing();
    final read = local.runStorageOperation(() async {
      throw PlatformException(code: 'KeyringLocked');
    }, isRead: true);
    final failure = expectLater(read, throwsA(code('storage_cancelled')));
    final next = local.runStorageOperation(
      () async => fail('queued call'),
      isRead: true,
    );
    final blocked = expectLater(next, throwsA(isA<StateError>()));
    await drain();
    local.dispose();
    await Future.wait([failure, blocked]);
  });

  test(
    'a native error returned after disposal never starts recovery',
    () async {
      final local = LinuxKeyringCoordinator.testing();
      final native = Completer<String>();
      final read = local.runStorageOperation(() => native.future, isRead: true);
      final failure = expectLater(read, throwsA(code('KeyringLocked')));
      await drain();
      local.dispose();
      native.completeError(PlatformException(code: 'KeyringLocked'));
      await failure;
    },
  );
}
