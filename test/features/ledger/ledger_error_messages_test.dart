import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_error_messages.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';

void main() {
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

  test('signatures from a different Ledger name the account mismatch', () {
    for (final error in [
      'ledger_signature_mismatch: Apply Orchard signature at action 0: InvalidSpendAuthSignature',
      'ledger_signature_mismatch: Validate Ledger transparent signature 1: InvalidSignature',
    ]) {
      expect(
        ledgerActionableErrorMessage(error),
        contains('do not match this account'),
      );
      expect(ledgerRequestNeedsRebuilding(error), isFalse);
    }
    // Only the Rust prefix identifies a mismatch.
    expect(
      ledgerActionableErrorMessage(
        'Apply Orchard signature at action 0: InvalidSpendAuthSignature',
      ),
      isNull,
    );
  });

  test('only transaction counts are classified as smaller transfers', () {
    for (final label in [
      'transparent inputs',
      'transparent outputs',
      'shielded actions',
    ]) {
      expect(
        ledgerRequestExceedsCapacity(
          'ledger_capacity: Ledger supports at most 32 $label; found 33',
        ),
        isTrue,
      );
    }
    const derivation =
        'Ledger supports at most 1 BIP32 derivation per transparent output';
    expect(ledgerRequestExceedsCapacity(derivation), isFalse);
    expect(
      ledgerActionableErrorMessage(derivation),
      isNot(contains('smaller amount')),
    );
    expect(ledgerRequestExceedsCapacity('0x6986'), isFalse);
    expect(
      ledgerRequestExceedsCapacity(
        'Ledger supports at most 32 transparent outputs; found 33',
      ),
      isFalse,
    );
  });

  test(
    'capacity guidance follows the real action, not a generic amount edit',
    () {
      const error =
          'ledger_capacity: Ledger supports at most 32 transparent inputs; found 33';
      final messages = {
        for (final kind in LedgerRequestKind.values)
          kind: ledgerActionableErrorMessage(error, requestKind: kind)!,
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

  test('preconditions and capacity require a new request, not reconnection', () {
    for (final error in [
      'ledger_status_6986: Ledger Zcash app returned status 0x6986',
      'ledger_capacity: Ledger supports at most 32 transparent inputs; found 33',
    ]) {
      expect(ledgerRequestNeedsRebuilding(error), isTrue);
      expect(ledgerActionableErrorMessage(error), isNotNull);
      expect(ledgerActionableErrorMessage(error), isNot(contains('rejected')));
    }
  });

  test(
    'device internal failures request an app restart without blaming users',
    () {
      for (final code in ['6f01', '6f03', '5223']) {
        final error = 'ledger_status_$code: Ledger Zcash app returned status';
        expect(ledgerRequestNeedsRebuilding(error), isFalse);
        expect(
          ledgerActionableErrorMessage(error),
          allOf(
            contains('Close and reopen'),
            contains('(0x$code)'),
            isNot(contains('rejected')),
          ),
        );
      }
    },
  );

  test('status codes map to their own guidance, not to rejection copy', () {
    const expected = {
      'ledger_status_6a80: Ledger rejected the PCZT data or key path':
          kLedgerHostRequestRejectedMessage,
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
    };
    for (final MapEntry(key: error, value: message) in expected.entries) {
      expect(ledgerActionableErrorMessage(error), message, reason: error);
      expect(message, isNot(contains('rejected')));
    }
    // Only the typed version check asks for an app update.
    expect(
      ledgerActionableErrorMessage(
        const LedgerAppReadinessException(
          LedgerAppReadinessFailure.unsupportedVersion,
          'Update the Ledger Zcash app to version 3.9.3 or newer.',
        ),
      ),
      'Update the Zcash app on your Ledger to 3.9.3 or newer, then try again.',
    );
    // Surfaces word these themselves.
    for (final error in [
      'ledger_status_6e00: Ledger device does not support this command class',
      'ledger_status_6d00: The running Ledger app does not support this command',
      'ledger_status_6985: Ledger request was rejected or the PCZT was not finalized',
      'ledger_status_5501: Ledger request was rejected on the device',
      'ledger_status_5515: Ledger device is locked; unlock it and reopen the Zcash app',
      'ledger_cancelled: Ledger operation was cancelled. Retry when ready.',
    ]) {
      expect(ledgerActionableErrorMessage(error), isNull, reason: error);
      expect(ledgerRequestNeedsRebuilding(error), isFalse, reason: error);
    }
  });

  test('only requests the device refuses as built need rebuilding', () {
    for (final error in [
      'ledger_status_6a80: Ledger rejected the PCZT data or key path',
      'ledger_capacity: Ledger supports at most 32 shielded actions; found 33',
    ]) {
      expect(ledgerRequestNeedsRebuilding(error), isTrue, reason: error);
    }
    for (final error in [
      'ledger_status_6d00: The running Ledger app does not support this command',
      'ledger_status_b007: Ledger Zcash app is in the wrong state; close and reopen the app',
      'ledger_status_6601: Ledger device is busy switching apps; retry shortly',
    ]) {
      expect(ledgerRequestNeedsRebuilding(error), isFalse, reason: error);
    }
  });

  test('host-rejected copy follows the request that was refused', () {
    const error =
        'ledger_status_6a80: Ledger rejected the PCZT data or key path';
    for (final kind in [LedgerRequestKind.voting, LedgerRequestKind.giftCard]) {
      final message = ledgerActionableErrorMessage(error, requestKind: kind)!;
      expect(
        message,
        isNot(kLedgerHostRequestRejectedMessage),
        reason: '$kind',
      );
      expect(message, isNot(contains('rejected')), reason: '$kind');
    }
    expect(
      ledgerActionableErrorMessage(
        error,
        requestKind: LedgerRequestKind.giftCard,
      ),
      contains('create a new gift card'),
    );
  });

  test('user cancellation and unrelated failures retain existing handling', () {
    expect(ledgerActionableErrorMessage('0x6985'), isNull);
    expect(ledgerActionableErrorMessage('network unavailable'), isNull);
    expect(ledgerRequestNeedsRebuilding('0x6985'), isFalse);
  });
}
