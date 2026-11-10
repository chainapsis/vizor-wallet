import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';

/// Waits for the Gift Card recovery that the activity list starts once its
/// rows are visible.
///
/// Ending a test with that pass in flight tears the app down from the test's
/// error zone, which cannot observe the interruption raised in the app's zone;
/// the run then reports it as an uncaught error.
Future<void> settleDeferredGiftCardRecovery(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ZcashWalletApp)),
  );
  // Let the post-frame callback that starts the pass run first.
  await tester.pump(const Duration(milliseconds: 500));
  try {
    await container
        .read(paymentLinkOperationsProvider)
        .recoverCreatedLinks()
        .timeout(const Duration(minutes: 1));
  } catch (_) {
    // Only quiescence matters here; recovery results are not under test.
  }
  await tester.pump(const Duration(milliseconds: 100));
}

/// Returns a desktop activity row by its visual index.
///
/// Full-screen rows use stable transaction/swap identities so their element
/// state survives pending-to-settled updates. Compact home rows retain the
/// older prefix-and-index keys.
Finder desktopActivityRowFinder(String rowKeyPrefix, int index) {
  if (rowKeyPrefix != 'activity_screen') {
    return find.byKey(ValueKey('${rowKeyPrefix}_row_$index'));
  }
  return desktopActivityRowsFinder().at(index);
}

Finder desktopActivityRowsFinder() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      (key.value.startsWith('tx:') || key.value.startsWith('swap:'));
});

Finder desktopActivityRowFinderForKey(Key key) {
  if (key case ValueKey<String>(
    value: final value,
  ) when value.startsWith('activity_screen_row_')) {
    final index = int.parse(value.substring('activity_screen_row_'.length));
    return desktopActivityRowFinder('activity_screen', index);
  }
  return find.byKey(key);
}
