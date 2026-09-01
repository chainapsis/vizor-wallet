import 'package:flutter_test/flutter_test.dart';
// Imported through app.dart as well: the predicate is part of app.dart's
// public surface and callers reach it from there.
import 'package:zcash_wallet/app.dart' as app;
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';

void main() {
  group('paymentUriBlockedAtLocation', () {
    test('blocks every leg of the send flow', () {
      for (final location in [
        // Desktop tree (app.dart `_desktopRoutes`).
        '/send',
        '/send/review',
        '/send/status',
        '/send/keystone/scan',
        // Mobile tree (mobile_routes.dart).
        '/send/amount',
        '/send/keystone-sign',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isTrue,
          reason: location,
        );
        expect(
          paymentUriBlockedSurfaceAt(location),
          PaymentUriBlockedSurface.send,
          reason: location,
        );
      }
    });

    test('blocks swap and pay review/signing surfaces', () {
      for (final location in [
        '/swap/review',
        '/swap/keystone-sign',
        '/pay/review',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isTrue,
          reason: location,
        );
        expect(
          paymentUriBlockedSurfaceAt(location),
          PaymentUriBlockedSurface.other,
          reason: location,
        );
      }
    });

    test('blocks the working Ironwood migration screens', () {
      for (final location in [
        // A redirect resolver, not a resting place: it routes on to
        // /migration/prepare or the private status screen.
        '/migration',
        '/migration/prepare',
        // Holds an unsubmitted mode choice and launches the plan work.
        '/migration/options',
        '/migration/review',
        '/migration/fast/review',
        '/migration/immediate/review',
        '/migration/immediate/keystone/sign',
        '/migration/private/review',
        '/migration/private/start',
        '/migration/private/status',
        '/migration/private/schedule',
        '/migration/private/notifications',
        '/migration/private/preparation-schedule',
        '/migration/private/keystone/sign',
        '/migration/private/keystone/denominations/sign',
        '/migration/private/keystone/batch/sign',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isTrue,
          reason: location,
        );
      }
    });

    test('allows informational and terminal migration screens', () {
      for (final location in [
        '/migration/intro',
        '/migration/how-it-works',
        '/migration/what-to-expect',
        '/migration/complete',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isFalse,
          reason: location,
        );
        expect(
          paymentUriBlockedSurfaceAt(location),
          PaymentUriBlockedSurface.none,
          reason: location,
        );
      }
    });

    test('the migration allowlist is exact-match', () {
      for (final location in [
        '/migration/intro/step',
        '/migration/complete/details',
        '/migration/how-it-works-2',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isTrue,
          reason: location,
        );
      }
    });

    test('blocks voting review, submission status, and the Keystone scan', () {
      for (final location in [
        '/voting/keystone/scan',
        '/voting/poll/round-1/review',
        '/voting/poll/round-1/status',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isTrue,
          reason: location,
        );
      }
    });

    test('blocks the uninstall flow and the mobile shield flow', () {
      for (final location in ['/settings/uninstall', '/home/keystone-shield']) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isTrue,
          reason: location,
        );
      }
    });

    test('blocks the desktop wallet-link pairing screen', () {
      expect(app.paymentUriBlockedAtLocation('/settings/link-mobile'), isTrue);
      expect(
        paymentUriBlockedSurfaceAt('/settings/link-mobile'),
        PaymentUriBlockedSurface.other,
      );
    });

    test('allows browsing surfaces', () {
      for (final location in [
        '/home',
        '/unlock',
        '/lost-password',
        '/welcome',
        '/activity',
        '/activity/tx/deadbeef',
        '/activity/swap/swap-1',
        '/settings',
        '/settings/endpoint',
        '/settings/change-password',
        '/receive',
        '/accounts',
        '/address-book',
        '/about',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isFalse,
          reason: location,
        );
        expect(
          paymentUriBlockedSurfaceAt(location),
          PaymentUriBlockedSurface.none,
          reason: location,
        );
      }
    });

    test('allows swap and pay composers and terminal receipts', () {
      for (final location in ['/swap', '/pay', '/pay/submitted/intent-1']) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isFalse,
          reason: location,
        );
      }
    });

    test('allows voting browsing and terminal voting steps', () {
      for (final location in [
        '/voting',
        '/voting/poll/round-1',
        '/voting/poll/round-1/submitted',
        '/voting/poll/round-1/results',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isFalse,
          reason: location,
        );
      }
    });

    test('matches whole path segments, not string prefixes', () {
      for (final location in [
        '/sender',
        '/sendings',
        '/migrations',
        '/migration-notes',
        '/voting/polls/round-1/review',
        '/voting/poll//review',
      ]) {
        expect(
          app.paymentUriBlockedAtLocation(location),
          isFalse,
          reason: location,
        );
      }
    });

    test('blocks a swap activity detail that is signing its ZEC deposit', () {
      const signing = {
        swapActivitySignQueryKey: swapActivitySignZecDepositValue,
      };

      // The signing query is what makes the surface busy; the same path
      // without it is a receipt the user is merely reading.
      expect(
        paymentUriBlockedSurfaceAt(
          '/activity/swap/abc',
          queryParameters: signing,
        ),
        PaymentUriBlockedSurface.other,
      );
      expect(
        paymentUriBlockedAtLocation(
          '/activity/swap/abc',
          queryParameters: signing,
        ),
        isTrue,
      );
      expect(
        paymentUriBlockedSurfaceAt('/activity/swap/abc'),
        PaymentUriBlockedSurface.none,
      );

      // Not a swap detail at all: an empty id falls back to the activity
      // list, and /activity never hosts a signature.
      for (final location in ['/activity/swap/', '/activity']) {
        expect(
          paymentUriBlockedSurfaceAt(location, queryParameters: signing),
          PaymentUriBlockedSurface.none,
          reason: location,
        );
      }

      // Any other value of the query is not the deposit signature.
      expect(
        paymentUriBlockedSurfaceAt(
          '/activity/swap/abc',
          queryParameters: const {swapActivitySignQueryKey: 'something-else'},
        ),
        PaymentUriBlockedSurface.none,
      );
    });
  });
}
