import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_tracking_lifecycle_provider.dart';

void main() {
  test('a lazy observer inherits an already acquired reset fence', () async {
    final registry = GiftCardTrackingLifecycle();
    await registry.quiesceAndDrain();
    var stopped = false;
    final owner = Object();
    registry.register(
      owner: owner,
      quiesceAndDrain: () async {
        stopped = true;
      },
      resume: () {
        stopped = false;
      },
    );
    expect(stopped, isTrue);
    registry.resume();
    expect(stopped, isFalse);
    registry.unregister(owner);
  });
}
