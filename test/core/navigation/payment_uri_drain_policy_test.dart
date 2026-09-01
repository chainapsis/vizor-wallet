import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';

/// Calls [decidePaymentUriDrain] with the "healthy, unlocked, on /home, link
/// just arrived" baseline so each test only states the row it exercises.
PaymentUriDrainDecision decide({
  bool hasParkedPrefill = true,
  bool hasBlockingFailure = false,
  bool walletIsLoading = false,
  bool walletHasError = false,
  bool hasWallet = true,
  bool isUnlocked = true,
  String matchedLocation = '/home',
  bool sendStatusIsTerminal = false,
}) => decidePaymentUriDrain(
  hasParkedPrefill: hasParkedPrefill,
  hasBlockingFailure: hasBlockingFailure,
  walletIsLoading: walletIsLoading,
  walletHasError: walletHasError,
  hasWallet: hasWallet,
  isUnlocked: isUnlocked,
  matchedLocation: matchedLocation,
  sendStatusIsTerminal: sendStatusIsTerminal,
);

void main() {
  group('nothing to deliver', () {
    test('waits when no prefill is parked', () {
      expect(
        decide(hasParkedPrefill: false).action,
        PaymentUriDrainAction.wait,
      );
    });
  });

  group('bootstrap and wallet failure', () {
    test('a blocking storage failure leaves the link parked', () {
      expect(
        decide(hasBlockingFailure: true).action,
        PaymentUriDrainAction.wait,
      );
    });

    test('a wallet load error leaves the link parked', () {
      expect(decide(walletHasError: true).action, PaymentUriDrainAction.wait);
    });

    test('a still-loading wallet leaves the link parked', () {
      expect(
        decide(walletIsLoading: true, hasWallet: false).action,
        PaymentUriDrainAction.wait,
      );
    });
  });
  group('no wallet', () {
    test('routes to /welcome with the set-up message', () {
      final decision = decide(hasWallet: false, matchedLocation: '/home');
      expect(decision.action, PaymentUriDrainAction.routeToWelcome);
      expect(decision.message, kPaymentUriNoWalletMessage);
    });
  });

  group('locked wallet', () {
    test('routes to /unlock and leaves the link parked', () {
      final decision = decide(isUnlocked: false, matchedLocation: '/home');
      expect(decision.action, PaymentUriDrainAction.routeToUnlock);
      expect(decision.message, isNull);
    });
  });
  group('unlocked but still on the unlock screen', () {
    test('waits so the unlock screen keeps ownership of the claim', () {
      expect(
        decide(matchedLocation: '/unlock').action,
        PaymentUriDrainAction.wait,
      );
    });
  });

  group('blocked surfaces', () {
    test('an open send flow keeps the send-specific message', () {
      for (final location in [
        '/send',
        '/send/amount',
        '/send/review',
        '/send/keystone-sign',
        '/send/keystone/scan',
      ]) {
        final decision = decide(matchedLocation: location);
        expect(
          decision.action,
          PaymentUriDrainAction.dropWithMessage,
          reason: location,
        );
        expect(
          decision.message,
          kPaymentUriSendInProgressMessage,
          reason: location,
        );
      }
    });

    test('other in-progress surfaces get the generic busy message', () {
      for (final location in [
        '/swap/review',
        '/swap/keystone-sign',
        '/pay/review',
        '/migration',
        '/migration/private/keystone/denominations/sign',
        '/migration/private/keystone/batch/sign',
        '/migration/immediate/keystone/sign',
        '/voting/keystone/scan',
        '/voting/poll/round-1/review',
        '/voting/poll/round-1/status',
        '/settings/uninstall',
        '/home/keystone-shield',
      ]) {
        final decision = decide(matchedLocation: location);
        expect(
          decision.action,
          PaymentUriDrainAction.dropWithMessage,
          reason: location,
        );
        expect(decision.message, kPaymentUriBusyMessage, reason: location);
      }
    });
  });

  group('/send/status', () {
    test('is blocked while the send is still in flight', () {
      final decision = decide(matchedLocation: '/send/status');
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriSendInProgressMessage);
      expect(decision.clearSendStatusPayload, isFalse);
    });

    test('delivers once the send is terminal, releasing the route payload', () {
      final decision = decide(
        matchedLocation: '/send/status',
        sendStatusIsTerminal: true,
      );
      expect(decision.action, PaymentUriDrainAction.deliver);
      expect(decision.clearSendStatusPayload, isTrue);
    });

    test('a terminal send does not unblock the other send legs', () {
      for (final location in ['/send', '/send/review']) {
        expect(
          decide(matchedLocation: location, sendStatusIsTerminal: true).action,
          PaymentUriDrainAction.dropWithMessage,
          reason: location,
        );
      }
    });
  });

  group('delivery', () {
    test('delivers from ordinary locations', () {
      for (final location in [
        '/home',
        '/activity',
        '/activity/tx/deadbeef',
        '/settings',
        '/settings/endpoint',
        '/receive',
        '/accounts',
        '/swap',
        '/pay',
        '/voting',
        '/voting/poll/round-1/results',
      ]) {
        final decision = decide(matchedLocation: location);
        expect(
          decision.action,
          PaymentUriDrainAction.deliver,
          reason: location,
        );
        expect(decision.message, isNull, reason: location);
        expect(decision.clearSendStatusPayload, isFalse, reason: location);
      }
    });
  });
}
