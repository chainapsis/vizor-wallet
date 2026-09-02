import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_busy_surface_provider.dart';

/// Asserts that [surface] holds `paymentUriBusySurfaceProvider` for exactly as
/// long as it is mounted: the count is 1 while it is up and back to 0 once it
/// is gone.
///
/// [host] wraps the surface in whatever app shell the screen needs; it is
/// called again with a placeholder to unmount the surface while keeping the
/// container (and therefore the count) alive.
///
/// [drainExceptions] is for surfaces whose camera preview or Rust calls cannot
/// run in a widget test. Those failures happen inside the scanner and say
/// nothing about the latch.
Future<void> expectPaymentUriBusySurfaceHeldWhileMounted(
  WidgetTester tester, {
  required ProviderContainer container,
  required Widget Function(Widget child) host,
  required Widget surface,
  Widget unmounted = const SizedBox.shrink(),
  bool drainExceptions = false,
  int settlePumps = 1,

  /// Advanced after the surface is gone, so one-shot timers a torn-down
  /// signing flow left behind fire inside the test rather than tripping the
  /// binding's "timer still pending" invariant.
  Duration postUnmountSettle = Duration.zero,
}) async {
  expect(container.read(paymentUriBusySurfaceProvider), 0);

  await tester.pumpWidget(host(surface));
  for (var i = 0; i < settlePumps; i++) {
    await tester.pump();
  }
  if (drainExceptions) _drainExceptions(tester);

  expect(
    container.read(paymentUriBusySurfaceProvider),
    1,
    reason:
        'a mounted Keystone signing surface makes the payment-URI '
        'drain wait instead of covering it with a card',
  );

  await tester.pumpWidget(host(unmounted));
  // The release is deferred to a microtask because `dispose` is one of the
  // places Riverpod forbids a synchronous provider write.
  await tester.pump();
  if (drainExceptions) _drainExceptions(tester);

  expect(container.read(paymentUriBusySurfaceProvider), 0);

  if (postUnmountSettle > Duration.zero) {
    await tester.pump(postUnmountSettle);
    if (drainExceptions) _drainExceptions(tester);
  }
}

void _drainExceptions(WidgetTester tester) {
  while (tester.takeException() != null) {}
}
