import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_error_messages.dart';

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
    expect(usb('Proposal not found (expired or already consumed)'), isNull);
    expect(usb('User rejected approval (0x6985)'), isNull);
  });

  test('shielding input limit copy counts the approvals', () {
    final message = ledgerShieldingInputLimitMessage(inputCount: 41, limit: 32);
    expect(message, contains('up to 32'));
    expect(message, contains('all 41 inputs'));
    expect(message, contains('2 approvals'));
    expect(
      ledgerShieldingInputLimitMessage(inputCount: 65, limit: 32),
      contains('3 approvals'),
    );
  });

  test('signatures from a different Ledger name the account mismatch', () {
    for (final error in [
      'Apply Ledger Orchard signature at action 0: InvalidSpendAuthSignature',
      'Validate Ledger transparent signature 1: InvalidSignature',
    ]) {
      expect(
        ledgerActionableErrorMessage(error),
        contains('do not match this account'),
      );
      expect(ledgerRequestNeedsRebuilding(error), isFalse);
    }
  });

  test('a different wallet detected before signing keeps retry open', () {
    const error = 'Exception: $kLedgerWrongWalletMessage';
    expect(ledgerActionableErrorMessage(error), kLedgerWrongWalletMessage);
    expect(ledgerRequestNeedsRebuilding(error), isFalse);
    expect(ledgerRequestExceedsCapacity(error), isFalse);
  });

  test('only transaction counts are classified as smaller transfers', () {
    for (final label in [
      'transparent inputs',
      'transparent outputs',
      'shielded actions',
    ]) {
      expect(
        ledgerRequestExceedsCapacity(
          'Ledger supports at most 32 $label; found 33',
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
  });

  test(
    'capacity guidance follows the real action, not a generic amount edit',
    () {
      const error = 'Ledger supports at most 32 transparent inputs; found 33';
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
        contains('cannot split this request yet'),
      );
      expect(
        messages[LedgerRequestKind.migration],
        contains('Return to review'),
      );
      expect(
        messages[LedgerRequestKind.voting],
        isNot(contains('try a smaller amount')),
      );
    },
  );

  test(
    'preconditions and capacity require a new request, not reconnection',
    () {
      for (final error in [
        'Ledger signing preconditions were not met (0x6986)',
        'Ledger supports at most 32 transparent inputs; found 33',
      ]) {
        expect(ledgerRequestNeedsRebuilding(error), isTrue);
        expect(ledgerActionableErrorMessage(error), isNotNull);
        expect(
          ledgerActionableErrorMessage(error),
          isNot(contains('rejected')),
        );
      }
    },
  );

  test(
    'device internal failures request an app restart without blaming users',
    () {
      for (final code in ['0x6f01', '0x6f03']) {
        expect(ledgerRequestNeedsRebuilding(code), isFalse);
        expect(
          ledgerActionableErrorMessage(code),
          contains('Close and reopen'),
        );
      }
    },
  );

  test('user cancellation and unrelated failures retain existing handling', () {
    expect(ledgerActionableErrorMessage('0x6985'), isNull);
    expect(ledgerActionableErrorMessage('network unavailable'), isNull);
    expect(ledgerRequestNeedsRebuilding('0x6985'), isFalse);
  });
}
