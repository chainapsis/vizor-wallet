import 'package:flutter_test/flutter_test.dart';
// Imported through app.dart as well: the predicate is part of app.dart's
// public surface and callers reach it from there.
import 'package:zcash_wallet/app.dart' as app;
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';

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

    test('blocks the whole Ironwood migration subtree', () {
      for (final location in [
        '/migration',
        '/migration/prepare',
        '/migration/intro',
        '/migration/how-it-works',
        '/migration/what-to-expect',
        '/migration/options',
        '/migration/review',
        '/migration/complete',
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
  });
}
