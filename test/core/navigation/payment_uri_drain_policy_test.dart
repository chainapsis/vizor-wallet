import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';

/// Calls [decidePaymentUriDrain] with the "healthy, unlocked, on /home, link
/// just arrived" baseline so each test only states the row it exercises.
PaymentUriDrainDecision decide({
  bool hasParkedPrefill = true,
  Duration? parkedFor = Duration.zero,
  bool hasBlockingFailure = false,
  bool walletIsLoading = false,
  bool walletHasError = false,
  bool hasWallet = true,
  bool isUnlocked = true,
  String matchedLocation = '/home',
  bool hasBusySurface = false,
  bool sendGatedByMigration = false,
}) => decidePaymentUriDrain(
  hasParkedPrefill: hasParkedPrefill,
  parkedFor: parkedFor,
  hasBlockingFailure: hasBlockingFailure,
  walletIsLoading: walletIsLoading,
  walletHasError: walletHasError,
  hasWallet: hasWallet,
  isUnlocked: isUnlocked,
  matchedLocation: matchedLocation,
  hasBusySurface: hasBusySurface,
  sendGatedByMigration: sendGatedByMigration,
);

void main() {
  group('nothing to deliver', () {
    test('waits when no prefill is parked', () {
      expect(
        decide(hasParkedPrefill: false, parkedFor: null).action,
        PaymentUriDrainAction.wait,
      );
    });
  });

  group('stale prefill', () {
    test('drops a prefill parked longer than the TTL, silently', () {
      final decision = decide(
        parkedFor: kPaymentUriParkTtl + const Duration(seconds: 1),
      );
      expect(decision.action, PaymentUriDrainAction.dropSilently);
      expect(decision.message, isNull);
    });

    test('delivers a prefill parked for exactly the TTL', () {
      expect(
        decide(parkedFor: kPaymentUriParkTtl).action,
        PaymentUriDrainAction.deliver,
      );
    });

    test('age outranks every other row, including a busy surface', () {
      expect(
        decide(
          parkedFor: kPaymentUriParkTtl + const Duration(minutes: 1),
          hasBusySurface: true,
          hasWallet: false,
          isUnlocked: false,
        ).action,
        PaymentUriDrainAction.dropSilently,
      );
    });
  });

  group('the wallet cannot be opened', () {
    test('a blocking bootstrap failure drops with the unavailable message', () {
      final decision = decide(hasBlockingFailure: true);
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriUnavailableMessage);
    });

    test('a wallet load error drops with the unavailable message', () {
      final decision = decide(walletHasError: true);
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriUnavailableMessage);
    });

    test('waits while wallet existence is still unknown', () {
      expect(decide(walletIsLoading: true).action, PaymentUriDrainAction.wait);
    });
  });

  group('setup flows', () {
    test('drops on every onboarding location with the onboarding message', () {
      for (final location in [
        '/add-account',
        '/onboarding/create',
        '/import/seed',
      ]) {
        final decision = decide(matchedLocation: location);
        expect(
          decision.action,
          PaymentUriDrainAction.dropWithMessage,
          reason: location,
        );
        expect(
          decision.message,
          kPaymentUriOnboardingMessage,
          reason: location,
        );
      }
    });

    test('/welcome with no wallet gets the plainer no-wallet wording', () {
      final decision = decide(matchedLocation: '/welcome', hasWallet: false);
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriNoWalletMessage);
    });

    test('/welcome with a wallet gets the onboarding wording', () {
      expect(
        decide(matchedLocation: '/welcome').message,
        kPaymentUriOnboardingMessage,
      );
    });
  });

  group('busy surface', () {
    test('waits rather than dropping while a signing session is up', () {
      final decision = decide(hasBusySurface: true);
      expect(decision.action, PaymentUriDrainAction.wait);
      expect(decision.message, isNull);
    });

    test('presents once the hold is given back', () {
      expect(
        decide(hasBusySurface: false).action,
        PaymentUriDrainAction.deliver,
      );
    });

    test('waiting outranks the migration gate and the wallet rows', () {
      expect(
        decide(
          hasBusySurface: true,
          sendGatedByMigration: true,
          hasWallet: false,
        ).action,
        PaymentUriDrainAction.wait,
      );
    });

    test('onboarding still outranks a busy surface', () {
      expect(
        decide(matchedLocation: '/import/seed', hasBusySurface: true).action,
        PaymentUriDrainAction.dropWithMessage,
      );
    });
  });

  group('migration send gate', () {
    test('drops with the migration message', () {
      final decision = decide(sendGatedByMigration: true);
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriMigrationSendGateMessage);
    });

    test('outranks the no-wallet and locked rows', () {
      final decision = decide(
        sendGatedByMigration: true,
        hasWallet: false,
        isUnlocked: false,
      );
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriMigrationSendGateMessage);
    });
  });

  group('no wallet', () {
    test('routes to /welcome with the no-wallet message', () {
      final decision = decide(hasWallet: false);
      expect(decision.action, PaymentUriDrainAction.routeToWelcome);
      expect(decision.message, kPaymentUriNoWalletMessage);
    });
  });

  group('locked wallet', () {
    test('routes to /unlock and keeps the prefill parked', () {
      final decision = decide(isUnlocked: false);
      expect(decision.action, PaymentUriDrainAction.routeToUnlock);
      expect(decision.message, isNull);
    });

    test('waits on the unlock and reset flows instead of navigating', () {
      for (final location in ['/unlock', '/lost-password']) {
        expect(
          decide(isUnlocked: false, matchedLocation: location).action,
          PaymentUriDrainAction.wait,
          reason: location,
        );
      }
    });

    test('waits on /unlock after unlocking: the unlock screen presents', () {
      expect(
        decide(matchedLocation: '/unlock').action,
        PaymentUriDrainAction.wait,
      );
    });
  });

  group('no route blocks the card any more', () {
    test('presents over every surface that used to be blocked', () {
      for (final location in [
        // The send flow itself, mid-compose and mid-review.
        '/send',
        '/send/review',
        '/send/status',
        '/send/amount',
        // Swap and pay review.
        '/swap/review',
        '/pay/review',
        // The working migration screens.
        '/migration/prepare',
        '/migration/private/status',
        // Voting review and the uninstall flow.
        '/voting/poll/round-1/review',
        '/settings/uninstall',
        // A swap activity detail signing a ZEC deposit.
        '/activity/swap/swap-1',
      ]) {
        expect(
          decide(matchedLocation: location).action,
          PaymentUriDrainAction.deliver,
          reason: location,
        );
      }
    });
  });
}
