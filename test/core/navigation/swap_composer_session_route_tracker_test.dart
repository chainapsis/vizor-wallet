import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/swap_composer_session_route_tracker.dart';

void main() {
  test('review, requote, signing and flow switches preserve a session', () {
    final tracker = SwapComposerSessionRouteTracker(initialPath: '/home');
    for (final path in [
      '/swap',
      '/swap/review',
      '/swap',
      '/pay',
      '/pay/review',
      '/swap/keystone-sign',
      '/swap/ledger-sign',
      '/pay',
    ]) {
      expect(tracker.didEndSession(path), isFalse, reason: path);
    }
    expect(tracker.didEndSession('/home'), isTrue);
    expect(tracker.didEndSession('/activity'), isFalse);
  });

  test('submitted, activity, close and lock end a composing session', () {
    for (final path in [
      '/pay/submitted/intent-1',
      '/activity/swap/intent-1',
      '/home',
      '/unlock',
    ]) {
      final tracker = SwapComposerSessionRouteTracker(initialPath: '/pay');
      expect(tracker.didEndSession(path), isTrue, reason: path);
      expect(tracker.didEndSession('/swap'), isFalse);
      expect(tracker.didEndSession('/activity'), isTrue);
    }
  });
}
