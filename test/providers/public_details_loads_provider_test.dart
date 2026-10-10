import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/public_details_loads_provider.dart';

void main() {
  test('a lock cancels only a load that is running', () async {
    var cancels = 0;
    final loads = PublicDetailsLoads(cancelInRust: () => cancels++);

    loads.cancel();
    expect(cancels, 0, reason: 'nothing to cancel');

    final release = Completer<void>();
    final running = loads.run(() => release.future);
    loads.cancel();
    expect(cancels, 1);
    release.complete();
    expect(await running, isTrue);
  });

  test('a wallet change cancels and waits for a running load, then refuses '
      'new ones until it resumes', () async {
    var cancels = 0;
    final loads = PublicDetailsLoads(cancelInRust: () => cancels++);
    final release = Completer<void>();
    final running = loads.run(() => release.future);

    var drained = false;
    final drain = loads.quiesceAndDrain().then((_) => drained = true);
    await pumpEventQueue();
    expect(cancels, 1);
    expect(drained, isFalse, reason: 'the running load is awaited');

    var ran = false;
    expect(await loads.run(() async => ran = true), isFalse);
    expect(ran, isFalse);

    release.complete();
    await drain;
    expect(await running, isTrue);
    expect(drained, isTrue);

    loads.resume();
    expect(await loads.run(() async => ran = true), isTrue);
    expect(ran, isTrue);
  });

  test('a failing load still leaves the drain', () async {
    final loads = PublicDetailsLoads(cancelInRust: () {});
    await expectLater(
      loads.run(() async => throw StateError('lookup failed')),
      throwsStateError,
    );
    await loads.quiesceAndDrain();
    loads.resume();
  });
}
