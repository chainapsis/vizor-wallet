import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';

void main() {
  test(
    'drain waits through nested result persistence and rejects new work',
    () async {
      final lifecycle = LedgerOperationLifecycle();
      final broadcast = Completer<void>();
      final persist = Completer<void>();
      final writing = Completer<void>();
      final operation = lifecycle.run(() async {
        await broadcast.future;
        await lifecycle.run(() async {
          writing.complete();
          await persist.future;
        });
      });
      var drained = false;
      final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
      await expectLater(lifecycle.run(() async {}), throwsStateError);
      broadcast.complete();
      await writing.future;
      expect(drained, isFalse);
      persist.complete();
      await operation;
      await drain;
      expect(drained, isTrue);
      expect(lifecycle.isPaused, isTrue);
      lifecycle.resume();
      await lifecycle.run(() async {});
    },
  );

  test(
    'nested unawaited child is still drained after its parent finishes',
    () async {
      final lifecycle = LedgerOperationLifecycle();
      final beginChild = Completer<void>();
      final childGate = Completer<void>();
      final parent = lifecycle.run(() async {
        await beginChild.future;
        unawaited(lifecycle.run(() => childGate.future));
      });
      var drained = false;
      final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
      beginChild.complete();
      await parent;
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      childGate.complete();
      await drain;
      lifecycle.resume();
    },
  );

  test(
    'failed work releases drain without turning failure into success',
    () async {
      final lifecycle = LedgerOperationLifecycle();
      final gate = Completer<void>();
      final operation = lifecycle.run(() async {
        await gate.future;
        throw StateError('broadcast failed');
      });
      final expectation = expectLater(operation, throwsStateError);
      final drain = lifecycle.quiesceAndDrain();
      gate.complete();
      await expectation;
      await drain;
      lifecycle.resume();
      expect(await lifecycle.run(() async => 42), 42);
    },
  );

  test('overlapping destructive owners cannot resume each other', () async {
    final lifecycle = LedgerOperationLifecycle();
    await lifecycle.quiesceAndDrain();
    await lifecycle.quiesceAndDrain();
    lifecycle.resume();
    await expectLater(lifecycle.run(() async {}), throwsStateError);
    lifecycle.resume();
    await lifecycle.run(() async {});
  });

  test('escaped completed owner cannot bypass a later pause', () async {
    final lifecycle = LedgerOperationLifecycle();
    final trigger = Completer<void>();
    late Future<void> escaped;
    await lifecycle.run(() async {
      escaped = trigger.future.then((_) => lifecycle.run(() async {}));
    });
    await lifecycle.quiesceAndDrain();
    final expectation = expectLater(escaped, throwsStateError);
    trigger.complete();
    await expectation;
    lifecycle.resume();
  });
}
