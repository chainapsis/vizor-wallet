import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

void main() {
  group('LedgerRequestFailure.fromError', () {
    const typed = {
      LedgerMobileFailure.busy: LedgerRequestFailure.busy,
      LedgerMobileFailure.permissionDenied: LedgerRequestFailure.transportLost,
      LedgerMobileFailure.locationDisabled: LedgerRequestFailure.transportLost,
      LedgerMobileFailure.bluetoothOff: LedgerRequestFailure.transportLost,
      LedgerMobileFailure.pairingRejected: LedgerRequestFailure.transportLost,
      LedgerMobileFailure.pairingInvalid: LedgerRequestFailure.transportLost,
      LedgerMobileFailure.disconnected: LedgerRequestFailure.transportLost,
      LedgerMobileFailure.locked: LedgerRequestFailure.deviceLocked,
      LedgerMobileFailure.rejected: LedgerRequestFailure.declined,
      LedgerMobileFailure.wrongApp: LedgerRequestFailure.wrongApp,
      LedgerMobileFailure.cancelled: LedgerRequestFailure.cancelled,
      LedgerMobileFailure.unavailable: LedgerRequestFailure.other,
    };

    test('covers every typed mobile failure', () {
      expect(typed.keys, containsAll(LedgerMobileFailure.values));
    });

    for (final MapEntry(key: failure, value: expected) in typed.entries) {
      test('typed $failure takes precedence over diagnostic text', () {
        expect(
          LedgerRequestFailure.fromError(
            LedgerMobileException(failure, 'ledger_status_6985: rejected'),
          ),
          expected,
        );
      });
    }

    const statuses = {
      'ledger_status_6985: Ledger request was rejected':
          LedgerRequestFailure.declined,
      'ledger_status_5501: Ledger request was rejected on the device':
          LedgerRequestFailure.declined,
      'ledger_status_6a80: Ledger rejected the PCZT data or key path':
          LedgerRequestFailure.requestRejected,
      'ledger_status_6986: Ledger Zcash app returned status 0x6986':
          LedgerRequestFailure.requestRejected,
      'ledger_status_5515: Ledger device is locked':
          LedgerRequestFailure.deviceLocked,
      'ledger_status_5502: Ledger device PIN is not set':
          LedgerRequestFailure.pinNotSet,
      'ledger_status_6e00: Ledger device does not support this command class':
          LedgerRequestFailure.wrongApp,
      'ledger_status_6807: The Zcash app is not installed on this Ledger':
          LedgerRequestFailure.appNotInstalled,
      'ledger_status_b007: Ledger Zcash app is in the wrong state':
          LedgerRequestFailure.appWrongState,
      'ledger_status_6601: Ledger device is busy switching apps':
          LedgerRequestFailure.busy,
      'ledger_status_5223: Ledger Zcash app returned status':
          LedgerRequestFailure.unexpectedStatus,
      'ledger_capacity: Ledger supports at most 32 transparent inputs; found 33':
          LedgerRequestFailure.requestRejected,
      'ledger_cancelled: Ledger operation was cancelled. Retry when ready.':
          LedgerRequestFailure.cancelled,
      'ledger_transport: Write Ledger HID packet: device disconnected':
          LedgerRequestFailure.transportLost,
      'ledger_signature_mismatch: Validate Ledger transparent signature 1':
          LedgerRequestFailure.signatureMismatch,
    };
    for (final MapEntry(key: error, value: expected) in statuses.entries) {
      test('${error.split(':').first} is $expected', () {
        expect(LedgerRequestFailure.fromError(StateError(error)), expected);
      });
    }

    test('nested connection and readiness wrappers preserve the cause', () {
      const rejection = LedgerMobileException(
        LedgerMobileFailure.rejected,
        'Device response',
      );
      expect(
        LedgerRequestFailure.fromError(
          const LedgerConnectionRequiredException(
            'Connection failed',
            cause: LedgerAppReadinessException(
              LedgerAppReadinessFailure.unavailable,
              'App failed',
              cause: rejection,
            ),
          ),
        ),
        LedgerRequestFailure.declined,
      );
      expect(
        LedgerRequestFailure.fromError(
          const LedgerAppReadinessException(
            LedgerAppReadinessFailure.rejected,
            'Rejected',
            cause: LedgerMobileException(
              LedgerMobileFailure.cancelled,
              'Cancelled locally',
            ),
          ),
        ),
        LedgerRequestFailure.cancelled,
      );
    });

    test('readiness rejection without a cause remains declined', () {
      expect(
        LedgerRequestFailure.fromError(
          const LedgerAppReadinessException(
            LedgerAppReadinessFailure.rejected,
            'Device response',
          ),
        ),
        LedgerRequestFailure.declined,
      );
    });

    // Device decisions always carry a code; wording alone is not evidence.
    for (final message in ['Transaction rejected', 'APDU status 0x6985']) {
      test('uncoded text is not a rejection: $message', () {
        expect(
          LedgerRequestFailure.fromError(StateError(message)),
          LedgerRequestFailure.other,
        );
      });
    }

    test('unknown failures do not invent a rejection', () {
      expect(
        LedgerRequestFailure.fromError(StateError('Device response missing')),
        LedgerRequestFailure.other,
      );
      expect(
        LedgerRequestFailure.fromError(
          const LedgerConnectionRequiredException('Connection failed'),
        ),
        LedgerRequestFailure.transportLost,
      );
    });

    test('only a request the device cannot accept is not retryable', () {
      for (final failure in LedgerRequestFailure.values) {
        expect(
          failure.retryable,
          failure != LedgerRequestFailure.requestRejected,
          reason: '$failure',
        );
      }
    });
  });

  group('ledgerFailureGuidance', () {
    test('0x6a80 is a request that must be rebuilt', () {
      final guidance = ledgerFailureGuidance(
        StateError(
          'ledger_status_6a80: Ledger rejected the PCZT data or key path',
        ),
      )!;
      expect(guidance.retryable, isFalse);
      expect(guidance.message, kLedgerHostRequestRejectedMessage);
      expect(guidance.message, contains('create a new request'));
      expect(guidance.showDeviceAppPrompt, isFalse);
      expect(
        LedgerRequestFailure.requestRejected.title,
        'Request could not be accepted',
      );
    });

    test('0x6985 stays with the caller as a decline', () {
      const error = 'ledger_status_6985: Ledger request was rejected';
      expect(ledgerFailureGuidance(StateError(error)), isNull);
      expect(
        LedgerRequestFailure.fromError(StateError(error)),
        LedgerRequestFailure.declined,
      );
    });

    test('capacity is a non-retryable request rejection', () {
      final guidance = ledgerFailureGuidance(
        'ledger_capacity: Ledger supports at most 32 transparent inputs; found 33',
      )!;
      expect(guidance.retryable, isFalse);
      expect(guidance.message, contains('try a smaller amount'));
    });

    test('a status inside a connection failure reaches the guidance', () {
      final guidance = ledgerFailureGuidance(
        const LedgerConnectionRequiredException(
          'Connect and unlock your Ledger with USB, then try again.',
          cause: LedgerAppReadinessException(
            LedgerAppReadinessFailure.rejected,
            'Vizor could not prepare the Ledger Zcash app. Try again.',
            cause: 'ledger_status_6a80: Ledger rejected the PCZT data',
          ),
        ),
      )!;
      expect(guidance.retryable, isFalse);
      expect(guidance.message, kLedgerHostRequestRejectedMessage);
    });

    test('a connection failure without a device cause keeps its message', () {
      final guidance = ledgerFailureGuidance(
        const LedgerConnectionRequiredException(
          'Connect and unlock your Ledger with USB, then try again.',
          cause: 'ledger_transport: No Ledger device found',
        ),
      )!;
      expect(
        guidance.message,
        'Connect and unlock your Ledger with USB, then try again.',
      );
      expect(guidance.retryable, isTrue);
    });

    test('device-app failures show the device-app prompt', () {
      for (final error in [
        'ledger_status_6e00: Ledger device does not support this command class',
        'ledger_status_6d00: The running Ledger app does not support this command',
        'ledger_status_6807: The Zcash app is not installed on this Ledger',
      ]) {
        expect(
          ledgerFailureGuidance(error)!.showDeviceAppPrompt,
          isTrue,
          reason: error,
        );
      }
      expect(
        ledgerFailureGuidance(
          const LedgerAppReadinessException(
            LedgerAppReadinessFailure.unsupportedVersion,
            'Update the Ledger Zcash app to version 3.9.3 or newer.',
          ),
        )!.message,
        'Update the Ledger Zcash app to version 3.9.3 or newer.',
      );
      expect(
        LedgerRequestFailure.appUpdateRequired.message,
        'Update the Zcash app on your Ledger to 3.9.3 or newer, then try again.',
      );
    });

    test('status codes map to their own guidance, not to rejection copy', () {
      const expected = {
        'ledger_status_6986: Ledger Zcash app returned status 0x6986':
            kLedgerHostRequestRejectedMessage,
        'ledger_status_b007: Ledger Zcash app is in the wrong state; close and reopen the app':
            'Close and reopen the Zcash app on your Ledger, then try again.',
        'ledger_status_6601: Ledger device is busy switching apps; retry shortly':
            'Your Ledger is busy. Wait a moment, then try again.',
        'ledger_status_6901: Ledger display is busy starting a review; retry shortly':
            'Your Ledger is busy. Wait a moment, then try again.',
        'ledger_status_6807: The Zcash app is not installed on this Ledger':
            'Install the Zcash app on your Ledger with Ledger Live, then try again.',
        'ledger_status_5502: Ledger device PIN is not set':
            'Set up a PIN on your Ledger, then try again.',
        'ledger_status_5515: Ledger device is locked; unlock it and reopen the Zcash app':
            'Unlock your Ledger, then try again.',
      };
      for (final MapEntry(key: error, value: message) in expected.entries) {
        expect(ledgerFailureGuidance(error)!.message, message, reason: error);
        expect(message, isNot(contains('rejected')));
      }
      // Surfaces word these themselves.
      for (final error in [
        'ledger_status_6985: Ledger request was rejected or the PCZT was not finalized',
        'ledger_status_5501: Ledger request was rejected on the device',
        'ledger_cancelled: Ledger operation was cancelled. Retry when ready.',
        'ledger_transport: No Ledger device found',
        '0x6985',
        'network unavailable',
      ]) {
        expect(ledgerFailureGuidance(error), isNull, reason: error);
      }
    });

    test('device internal failures request an app restart with their code', () {
      for (final code in ['6f01', '6f03', '5223']) {
        final error = 'ledger_status_$code: Ledger Zcash app returned status';
        final guidance = ledgerFailureGuidance(error)!;
        expect(guidance.retryable, isTrue);
        expect(
          guidance.message,
          allOf(
            contains('Close and reopen'),
            contains('(0x$code)'),
            isNot(contains('rejected')),
          ),
        );
      }
    });

    test('signatures from a different Ledger name the account mismatch', () {
      for (final error in [
        'ledger_signature_mismatch: Apply Orchard signature at action 0: InvalidSpendAuthSignature',
        'ledger_signature_mismatch: Validate Ledger transparent signature 1: InvalidSignature',
      ]) {
        final guidance = ledgerFailureGuidance(error)!;
        expect(guidance.message, contains('do not match this account'));
        expect(guidance.retryable, isTrue);
      }
      // Only the Rust prefix identifies a mismatch.
      expect(
        ledgerFailureGuidance(
          'Apply Orchard signature at action 0: InvalidSpendAuthSignature',
        ),
        isNull,
      );
    });

    test('an unsupported transaction format is not a smaller transfer', () {
      const derivation =
          'Ledger supports at most 1 BIP32 derivation per transparent output';
      final guidance = ledgerFailureGuidance(derivation)!;
      expect(guidance.retryable, isFalse);
      expect(guidance.message, isNot(contains('smaller amount')));
      expect(guidance.message, contains('create a new request'));
    });

    test(
      'capacity guidance follows the real action, not a generic amount edit',
      () {
        const error =
            'ledger_capacity: Ledger supports at most 32 transparent inputs; found 33';
        final messages = {
          for (final kind in LedgerRequestKind.values)
            kind: ledgerFailureGuidance(error, requestKind: kind)!.message,
        };
        expect(
          messages[LedgerRequestKind.send],
          contains('try a smaller amount'),
        );
        expect(
          messages[LedgerRequestKind.swap],
          contains('review the new quote'),
        );
        expect(
          messages[LedgerRequestKind.payment],
          contains('Do not send a smaller amount'),
        );
        expect(
          messages[LedgerRequestKind.shield],
          allOf(
            contains('nothing was shielded for this approval'),
            isNot(contains('cannot split')),
          ),
        );
        expect(
          messages[LedgerRequestKind.migration],
          contains('Return to review'),
        );
        expect(
          messages[LedgerRequestKind.voting],
          isNot(contains('try a smaller amount')),
        );
        expect(
          messages[LedgerRequestKind.giftCard],
          contains('create a gift card with a smaller amount'),
        );
      },
    );

    test('host-rejected copy follows the request that was refused', () {
      const error =
          'ledger_status_6a80: Ledger rejected the PCZT data or key path';
      for (final kind in [
        LedgerRequestKind.voting,
        LedgerRequestKind.giftCard,
        LedgerRequestKind.viewingKey,
      ]) {
        final message = ledgerFailureGuidance(
          error,
          requestKind: kind,
        )!.message;
        expect(
          message,
          isNot(kLedgerHostRequestRejectedMessage),
          reason: '$kind',
        );
        expect(message, isNot(contains('rejected')), reason: '$kind');
      }
      expect(
        ledgerFailureGuidance(
          error,
          requestKind: LedgerRequestKind.giftCard,
        )!.message,
        contains('create a new gift card'),
      );
    });

    test('typed mobile failures keep their recovery flags', () {
      expect(
        ledgerFailureGuidance(
          const LedgerMobileException(LedgerMobileFailure.bluetoothOff, 'off'),
        )!.bluetoothRecovery,
        isTrue,
      );
      final invalid = ledgerFailureGuidance(
        const LedgerMobileException(
          LedgerMobileFailure.pairingInvalid,
          'invalid',
        ),
      )!;
      expect(invalid.pairingInvalid, isTrue);
      expect(invalid.pairingRecovery, isTrue);
      expect(
        ledgerFailureGuidance(
          const LedgerMobileException(LedgerMobileFailure.wrongApp, 'Open'),
        )!.showDeviceAppPrompt,
        isTrue,
      );
    });
  });

  test('USB transport failures are told apart', () {
    const app = 'Open the Zcash app.';
    String? usb(
      String error, {
      TargetPlatform platform = TargetPlatform.macOS,
    }) => ledgerUsbErrorMessage(error, appInstruction: app, platform: platform);

    expect(
      usb('No Ledger device found. Connect and unlock the Nano S+.'),
      startsWith('Connect and unlock your Ledger.'),
    );
    expect(
      usb(
        "Open Ledger HID device: hidapi error: Failed to open a device with path '/dev/hidraw3': Permission denied",
        platform: TargetPlatform.linux,
      ),
      contains('udev'),
    );
    expect(
      usb(
        'Open Ledger HID device: hidapi error: Access is denied.',
        platform: TargetPlatform.windows,
      ),
      allOf(contains('USB device permissions'), isNot(contains('udev'))),
    );
    expect(
      usb(
        'Open Ledger HID device: hidapi error: exclusive access and device already open',
      ),
      contains('could not open it'),
    );
    expect(
      usb('Read Ledger HID packet: hidapi error: device disconnected'),
      contains('interrupted'),
    );
    expect(
      usb('ledger_transport: Write Ledger HID packet: device disconnected'),
      contains('interrupted'),
    );
    expect(usb('Proposal not found (expired or already consumed)'), isNull);
    expect(usb('User rejected approval (0x6985)'), isNull);
    expect(usb('connection reset by peer'), isNull);
  });
}
