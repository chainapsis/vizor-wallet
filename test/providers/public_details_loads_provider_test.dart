import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/public_details_loads_provider.dart';

void main() {
  test('a lock cancels only a load that is running', () async {
    var cancels = 0;
    final loads = PublicDetailsLoads(
      cancelInRust: () => cancels++,
      epochInRust: () => BigInt.zero,
    );

    loads.cancel();
    expect(cancels, 0, reason: 'nothing to cancel');

    final release = Completer<void>();
    final running = loads.run((_) => release.future);
    loads.cancel();
    expect(cancels, 1);
    release.complete();
    expect(await running, isTrue);
  });

  test('a cancellation reaches a load still in its Dart steps', () async {
    var epoch = BigInt.from(3);
    final loads = PublicDetailsLoads(
      cancelInRust: () => epoch += BigInt.one,
      epochInRust: () => epoch,
    );
    final step = Completer<void>();
    late PublicDetailsLoadTicket ticket;
    var reachedNative = false;
    final running = loads.run((t) async {
      ticket = t;
      await step.future;
      t.ensureNotCancelled();
      reachedNative = true;
    });
    expect(ticket.cancelEpoch, BigInt.from(3));
    expect(ticket.cancelled, isFalse);

    loads.cancel();
    expect(ticket.cancelled, isTrue);
    expect(epoch, BigInt.from(4), reason: 'Rust moved past the ticket epoch');
    step.complete();
    await expectLater(running, throwsStateError);
    expect(reachedNative, isFalse);

    // A later load is not cancelled by the earlier lock.
    expect(
      await loads.run((t) async {
        expect(t.cancelled, isFalse);
        expect(t.cancelEpoch, BigInt.from(4));
      }),
      isTrue,
    );
  });

  test('a wallet change cancels and waits for a running load, then refuses '
      'new ones until it resumes', () async {
    var cancels = 0;
    final loads = PublicDetailsLoads(
      cancelInRust: () => cancels++,
      epochInRust: () => BigInt.zero,
    );
    final release = Completer<void>();
    final running = loads.run((_) => release.future);

    var drained = false;
    final drain = loads.quiesceAndDrain().then((_) => drained = true);
    await pumpEventQueue();
    expect(cancels, 1);
    expect(drained, isFalse, reason: 'the running load is awaited');

    var ran = false;
    expect(await loads.run((_) async => ran = true), isFalse);
    expect(ran, isFalse);

    release.complete();
    await drain;
    expect(await running, isTrue);
    expect(drained, isTrue);

    loads.resume();
    expect(await loads.run((_) async => ran = true), isTrue);
    expect(ran, isTrue);
  });

  test('a failing load still leaves the drain', () async {
    final loads = PublicDetailsLoads(
      cancelInRust: () {},
      epochInRust: () => BigInt.zero,
    );
    await expectLater(
      loads.run((_) async => throw StateError('lookup failed')),
      throwsStateError,
    );
    await loads.quiesceAndDrain();
    loads.resume();
  });
}
