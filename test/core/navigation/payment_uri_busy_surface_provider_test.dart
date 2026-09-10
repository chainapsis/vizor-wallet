import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_busy_surface_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  PaymentUriBusySurfaceNotifier notifier() =>
      container.read(paymentUriBusySurfaceProvider.notifier);

  int count() => container.read(paymentUriBusySurfaceProvider);

  test('starts with no hold', () {
    expect(count(), 0);
  });

  test('a single acquire/release pair opens and closes the latch', () {
    notifier().acquire();
    expect(count(), 1);

    notifier().release();
    expect(count(), 0);
  });

  test(
    'overlapping holders keep the latch closed until the last one leaves',
    () {
      notifier()
        ..acquire()
        ..acquire();
      expect(count(), 2);

      notifier().release();
      expect(count(), 1, reason: 'the second holder still owns a hold');

      notifier().release();
      expect(count(), 0);
    },
  );

  test('a stray release cannot drive the count negative', () {
    notifier()
      ..release()
      ..release();
    expect(count(), 0);

    notifier().acquire();
    expect(
      count(),
      1,
      reason: 'an over-release must not leave the latch owing a hold',
    );
  });

  test('releaseAfterNavigation defers the release to a microtask', () async {
    notifier().acquire();
    notifier().releaseAfterNavigation();
    expect(count(), 1, reason: 'still held for the rest of this turn');

    await Future<void>.delayed(Duration.zero);
    expect(count(), 0);
  });

  test(
    'a deferred release from a departing holder leaves a newer hold alone',
    () async {
      notifier()
        ..acquire()
        ..releaseAfterNavigation()
        ..acquire();

      await Future<void>.delayed(Duration.zero);
      expect(count(), 1, reason: 'the incoming holder keeps its own hold');
    },
  );

  test(
    'a disposed container drops pending releases without throwing',
    () async {
      final scoped = ProviderContainer();
      final scopedNotifier = scoped.read(
        paymentUriBusySurfaceProvider.notifier,
      );
      scopedNotifier
        ..acquire()
        ..releaseAfterNavigation();
      scoped.dispose();

      await Future<void>.delayed(Duration.zero);
    },
  );
}
