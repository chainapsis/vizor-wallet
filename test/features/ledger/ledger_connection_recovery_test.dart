import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_recovery.dart';

void main() {
  test('duplicate recovery shares one request and ends ready', () async {
    final controller = LedgerConnectionRecoveryController();
    addTearDown(controller.dispose);
    final ready = Completer<void>();
    var calls = 0;
    Future<void> prepare(String _) {
      calls++;
      return ready.future;
    }

    final first = controller.reconnect('a', prepare);
    final second = controller.reconnect('a', prepare);
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(controller.phase, LedgerConnectionRecoveryPhase.reconnecting);
    ready.complete();
    await first;
    expect(controller.phase, LedgerConnectionRecoveryPhase.ready);
  });

  test(
    'account reset ignores old completion and serializes new recovery',
    () async {
      final controller = LedgerConnectionRecoveryController();
      addTearDown(controller.dispose);
      final old = Completer<void>();
      final current = Completer<void>();
      final calls = <String>[];
      final first = controller.reconnect('old', (id) {
        calls.add(id);
        return old.future;
      });
      await Future<void>.delayed(Duration.zero);
      controller.reset();
      final second = controller.reconnect('new', (id) {
        calls.add(id);
        return current.future;
      });
      expect(calls, ['old']);
      old.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['old', 'new']);
      expect(controller.phase, LedgerConnectionRecoveryPhase.reconnecting);
      current.complete();
      await second;
      expect(controller.phase, LedgerConnectionRecoveryPhase.ready);
    },
  );

  test('failure stays failed until an explicit new recovery', () async {
    final controller = LedgerConnectionRecoveryController();
    addTearDown(controller.dispose);
    await controller.reconnect(
      'a',
      (_) async => throw StateError('still closing'),
    );
    expect(controller.phase, LedgerConnectionRecoveryPhase.failed);
    expect(controller.message, contains('still closing'));
    await controller.reconnect('a', (_) async {});
    expect(controller.phase, LedgerConnectionRecoveryPhase.ready);
    expect(controller.message, isNull);
  });

  test('dispose ignores late failure without notifying listeners', () async {
    final controller = LedgerConnectionRecoveryController();
    final pending = Completer<void>();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final request = controller.reconnect('a', (_) => pending.future);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    final before = notifications;
    pending.completeError(StateError('late'));
    await request;
    expect(notifications, before);
  });
}
