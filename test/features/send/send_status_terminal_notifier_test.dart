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
