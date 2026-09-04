import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';

/// `_IncomingLinkHost` re-runs the payment-URI drain on this flag's
/// false → true edge and nowhere else, so what the notifier publishes when a
/// receipt is left decides whether a `zcash:` link parked behind a running
/// send ever gets delivered.
void main() {
  late ProviderContainer container;
  late SendStatusTerminalNotifier notifier;
  late List<bool> published;

  setUp(() {
    container = ProviderContainer();
    published = [];
    container.listen<bool>(
      sendStatusTerminalProvider,
      (_, next) => published.add(next),
    );
    notifier = container.read(sendStatusTerminalProvider.notifier);
  });

  tearDown(() => container.dispose());

  Future<void> flushMicrotasks() => Future<void>.delayed(Duration.zero);

  test('a receipt left before its send went terminal publishes terminal, '
      'then clears', () async {
    // A broadcast started and came back pending; the user left the receipt.
    notifier.reset();
    notifier.resetAfterNavigation();
    await flushMicrotasks();

    expect(
      published,
      [true, false],
      reason:
          'the drain listener needs the false → true edge to re-run, and '
          'the next send needs a clear flag',
    );
    expect(container.read(sendStatusTerminalProvider), isFalse);
  });

  test('a receipt that already went terminal only clears', () async {
    notifier.reset();
    notifier.markTerminal();
    published.clear();

    notifier.resetAfterNavigation();
    await flushMicrotasks();

    expect(published, [false]);
  });

  test('a receipt left mid-release publishes terminal only once the release '
      'lands', () async {
    // A failed software send that never consumed its proposal: the receipt
    // is still releasing it when the user leaves.
    final release = Completer<bool>();
    notifier.reset();
    notifier.resetAfterNavigation(afterRelease: release.future);
    await flushMicrotasks();

    expect(
      published,
      isEmpty,
      reason:
          'the drain must not be told the send is safe to leave while its '
          'proposal still locks the inputs a parked request would check',
    );

    release.complete(true);
    await flushMicrotasks();

    expect(published, [true, false]);
  });

  test('a release Rust never confirmed retries once, then publishes', () async {
    SendStatusTerminalNotifier.debugUnconfirmedReleaseGrace = Duration.zero;
    addTearDown(() {
      SendStatusTerminalNotifier.debugUnconfirmedReleaseGrace = const Duration(
        seconds: 3,
      );
    });
    var retries = 0;
    notifier.reset();
    notifier.resetAfterNavigation(
      afterRelease: Future<bool>.value(false),
      retryRelease: () async {
        retries++;
        return true;
      },
    );
    await flushMicrotasks();
    await flushMicrotasks();

    expect(retries, 1);
    expect(published, [true, false]);
  });

  test('a departing receipt leaves a newer send\'s flag alone', () async {
    notifier.reset();
    notifier.resetAfterNavigation();
    // A new status screen started its broadcast before the microtask ran.
    notifier.reset();
    await flushMicrotasks();

    expect(published, isEmpty);
    expect(container.read(sendStatusTerminalProvider), isFalse);
  });
}
