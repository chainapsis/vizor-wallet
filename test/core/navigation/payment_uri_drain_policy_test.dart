import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';

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
  Map<String, String> queryParameters = const {},
  bool sendStatusIsTerminal = false,
  bool hasBusySurface = false,
}) => decidePaymentUriDrain(
  hasParkedPrefill: hasParkedPrefill,
  parkedFor: parkedFor,
  hasBlockingFailure: hasBlockingFailure,
  walletIsLoading: walletIsLoading,
  walletHasError: walletHasError,
  hasWallet: hasWallet,
  isUnlocked: isUnlocked,
  matchedLocation: matchedLocation,
  queryParameters: queryParameters,
  sendStatusIsTerminal: sendStatusIsTerminal,
  hasBusySurface: hasBusySurface,
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

    test('outranks every other row, including navigation ones', () {
      final stale = kPaymentUriParkTtl + const Duration(minutes: 5);
      for (final decision in [
        decide(parkedFor: stale, hasBlockingFailure: true),
        decide(parkedFor: stale, hasWallet: false),
        decide(parkedFor: stale, isUnlocked: false),
        decide(parkedFor: stale, matchedLocation: '/send/review'),
      ]) {
        expect(decision.action, PaymentUriDrainAction.dropSilently);
      }
    });

    test('an unknown park age never counts as stale', () {
      expect(decide(parkedFor: null).action, PaymentUriDrainAction.deliver);
    });
  });

  group('bootstrap and wallet failure', () {
    test('a blocking storage failure drops the link with a message', () {
      final decision = decide(hasBlockingFailure: true);
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriUnavailableMessage);
    });

    test('a wallet load error drops the link with a message', () {
      final decision = decide(walletHasError: true);
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriUnavailableMessage);
    });

    test('a still-loading wallet leaves the link parked', () {
      expect(
        decide(walletIsLoading: true, hasWallet: false).action,
        PaymentUriDrainAction.wait,
      );
    });
  });

  group('onboarding locations', () {
    const onboardingLocations = [
      '/welcome',
      '/add-account',
      '/onboarding/intro',
      '/onboarding/secret-passphrase',
      '/onboarding/set-password',
      '/onboarding/set-passcode',
      '/onboarding/customise-account',
      '/onboarding/keystone/scan',
      '/onboarding/link-desktop/accounts',
      '/import',
      '/import/manual',
      '/import/review',
      '/import/birthday',
      '/import/set-password',
      '/import/customise-account',
      '/import-keystone',
      '/import-keystone/set-password',
    ];

    test(
      'stay put with the onboarding message when there is no wallet yet',
      () {
        for (final location in onboardingLocations) {
          final decision = decide(hasWallet: false, matchedLocation: location);
          expect(
            decision.action,
            PaymentUriDrainAction.dropWithMessage,
            reason: location,
          );
          // The welcome screen has not started anything yet, so it keeps the
          // plain no-wallet wording; every other setup step says "finish".
          expect(
            decision.message,
            location == '/welcome'
                ? kPaymentUriNoWalletMessage
                : kPaymentUriOnboardingMessage,
            reason: location,
          );
        }
      },
    );

    test('stay put with the onboarding message when a wallet exists', () {
      for (final location in onboardingLocations) {
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

    test('isOnboardingLocation excludes ordinary app locations', () {
      for (final location in [
        '/home',
        '/send',
        '/settings',
        '/unlock',
        '/lost-password',
        '/accounts',
      ]) {
        expect(isOnboardingLocation(location), isFalse, reason: location);
      }
    });
  });

  group('no wallet outside onboarding', () {
    test('routes to /welcome with the set-up message', () {
      final decision = decide(hasWallet: false, matchedLocation: '/home');
      expect(decision.action, PaymentUriDrainAction.routeToWelcome);
      expect(decision.message, kPaymentUriNoWalletMessage);
    });

    test('a busy non-send surface outranks the no-wallet redirect', () {
      // The uninstall flow ends with hasWallet == false on purpose, so the
      // no-wallet row must not pull its done stage over to /welcome.
      for (final location in [
        '/settings/uninstall',
        '/migration/private/status',
        '/swap/review',
        '/voting/poll/round-1/review',
      ]) {
        final decision = decide(hasWallet: false, matchedLocation: location);
        expect(
          decision.action,
          PaymentUriDrainAction.dropWithMessage,
          reason: location,
        );
        expect(decision.message, kPaymentUriBusyMessage, reason: location);
      }
    });

    test('a busy non-send surface also outranks the locked redirect', () {
      final decision = decide(
        isUnlocked: false,
        matchedLocation: '/settings/uninstall',
      );
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriBusyMessage);
    });

    test('send surfaces still fall through to the no-wallet redirect', () {
      // /send* is unreachable without a wallet, and the terminal /send/status
      // exception needs the delivery path, so the send rows stay below.
      for (final location in ['/send', '/send/status']) {
        expect(
          decide(hasWallet: false, matchedLocation: location).action,
          PaymentUriDrainAction.routeToWelcome,
          reason: location,
        );
      }
    });
  });

  group('locked wallet', () {
    test('routes to /unlock and leaves the link parked', () {
      final decision = decide(isUnlocked: false, matchedLocation: '/home');
      expect(decision.action, PaymentUriDrainAction.routeToUnlock);
      expect(decision.message, isNull);
    });

    test('stays put when already on /unlock', () {
      expect(
        decide(isUnlocked: false, matchedLocation: '/unlock').action,
        PaymentUriDrainAction.wait,
      );
    });

    test('stays put on /lost-password so the reset is not unmounted', () {
      expect(
        decide(isUnlocked: false, matchedLocation: '/lost-password').action,
        PaymentUriDrainAction.wait,
      );
    });

    test('isUnlockFlowLocation covers exactly the unlock and reset routes', () {
      expect(isUnlockFlowLocation('/unlock'), isTrue);
      expect(isUnlockFlowLocation('/lost-password'), isTrue);
      expect(isUnlockFlowLocation('/home'), isFalse);
      expect(isUnlockFlowLocation('/welcome'), isFalse);
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

  group('swap deposit signing', () {
    test('blocks the swap activity detail while it signs a ZEC deposit', () {
      final decision = decide(
        matchedLocation: '/activity/swap/swap-1',
        queryParameters: const {
          swapActivitySignQueryKey: swapActivitySignZecDepositValue,
        },
      );
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriBusyMessage);
    });

    test('still delivers on the same detail without the signing query', () {
      expect(
        decide(
          matchedLocation: '/activity/swap/swap-1',
          queryParameters: const {swapActivityReturnQueryKey: 'swap'},
        ).action,
        PaymentUriDrainAction.deliver,
      );
    });

    test('outranks the no-wallet row, like the other busy surfaces', () {
      // A reset landing mid-signature must not be yanked to /welcome.
      final decision = decide(
        hasWallet: false,
        matchedLocation: '/activity/swap/swap-1',
        queryParameters: const {
          swapActivitySignQueryKey: swapActivitySignZecDepositValue,
        },
      );
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriBusyMessage);
    });
  });

  group('wallet transition', () {
    test('drops only on the true -> false reset edge', () {
      expect(
        paymentUriShouldDropOnWalletTransition(
          previousHasWallet: true,
          hasWallet: false,
        ),
        isTrue,
      );
    });

    test('does not drop on any other edge', () {
      for (final edge in [
        (previous: true, next: true),
        (previous: false, next: true),
        (previous: false, next: false),
      ]) {
        expect(
          paymentUriShouldDropOnWalletTransition(
            previousHasWallet: edge.previous,
            hasWallet: edge.next,
          ),
          isFalse,
          reason: '${edge.previous} -> ${edge.next}',
        );
      }
    });

    test('an unseeded baseline is not a reset', () {
      // The listener seeds the baseline from bootstrap precisely so this
      // case cannot stand in for a real reset.
      for (final hasWallet in [true, false]) {
        expect(
          paymentUriShouldDropOnWalletTransition(
            previousHasWallet: null,
            hasWallet: hasWallet,
          ),
          isFalse,
          reason: 'null -> $hasWallet',
        );
      }
    });
  });

  group('busy surface with no route of its own', () {
    test('a held busy surface drops the link with the busy message', () {
      final decision = decide(hasBusySurface: true);
      expect(decision.action, PaymentUriDrainAction.dropWithMessage);
      expect(decision.message, kPaymentUriBusyMessage);
    });

    test('no hold on the same location delivers', () {
      expect(
        decide(hasBusySurface: false).action,
        PaymentUriDrainAction.deliver,
      );
    });

    test('outranks the send rows, including a terminal send status', () {
      for (final location in const [
        '/send',
        '/send/review',
        '/send/status',
        '/send/keystone/scan',
      ]) {
        final decision = decide(
          hasBusySurface: true,
          matchedLocation: location,
          sendStatusIsTerminal: true,
        );
        expect(decision.action, PaymentUriDrainAction.dropWithMessage);
        expect(decision.message, kPaymentUriBusyMessage);
        expect(decision.clearSendStatusPayload, isFalse);
      }
    });

    test('outranks the no-wallet and locked navigation rows', () {
      for (final decision in [
        decide(hasBusySurface: true, hasWallet: false),
        decide(hasBusySurface: true, isUnlocked: false),
      ]) {
        expect(decision.action, PaymentUriDrainAction.dropWithMessage);
        expect(decision.message, kPaymentUriBusyMessage);
      }
    });

    test('does not outrank the stale, failure, or onboarding rows', () {
      expect(
        decide(
          hasBusySurface: true,
          parkedFor: kPaymentUriParkTtl + const Duration(minutes: 1),
        ).action,
        PaymentUriDrainAction.dropSilently,
      );
      expect(
        decide(hasBusySurface: true, hasBlockingFailure: true).message,
        kPaymentUriUnavailableMessage,
      );
      expect(
        decide(hasBusySurface: true, walletIsLoading: true).action,
        PaymentUriDrainAction.wait,
      );
      expect(
        decide(hasBusySurface: true, matchedLocation: '/import').message,
        kPaymentUriOnboardingMessage,
      );
    });

    test('nothing parked still waits', () {
      expect(
        decide(
          hasBusySurface: true,
          hasParkedPrefill: false,
          parkedFor: null,
        ).action,
        PaymentUriDrainAction.wait,
      );
    });
  });
}
