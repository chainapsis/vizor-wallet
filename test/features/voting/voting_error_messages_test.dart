import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_error_messages.dart';

void main() {
  const app = 'Open the Zcash app on your Ledger.';

  test('Ledger vote failures are worded by kind without status codes', () {
    const expected = {
      'ledger_status_6985: Ledger request was rejected or the PCZT was not finalized':
          'The vote signature was rejected on your Ledger. Retry to sign again.',
      'ledger_status_5515: Ledger device is locked; unlock it and reopen the Zcash app':
          'Unlock your Ledger. $app',
      'ledger_status_6d00: The running Ledger app does not support this command':
          '$app Then retry.',
      'ledger_cancelled: Ledger operation was cancelled. Retry when ready.':
          kLedgerVotingCancelledMessage,
    };
    for (final MapEntry(key: error, value: message) in expected.entries) {
      expect(
        ledgerVotingErrorMessage(StateError(error), appInstruction: app),
        message,
        reason: error,
      );
    }
    expect(
      ledgerVotingErrorMessage(
        'ledger_capacity: Ledger supports at most 32 shielded actions; found 33',
        appInstruction: app,
      ),
      contains('Your vote was not signed.'),
    );
  });

  test('voting text never shows a Ledger code prefix', () {
    expect(
      friendlyVotingErrorText(
        'Bad state: ledger_linux_usb_access: No Ledger device found.',
      ),
      'No Ledger device found.',
    );
    expect(
      friendlyVotingErrorMessage(
        StateError('ledger_status_6f01: Ledger Zcash app returned status'),
      ),
      'Ledger Zcash app returned status',
    );
    expect(
      friendlyVotingErrorText('ledger_transport: No Ledger device found.'),
      'No Ledger device found.',
    );
    expect(
      friendlyVotingErrorText(
        'ledger_signature_mismatch: Validate Ledger transparent signature 0',
      ),
      'Validate Ledger transparent signature 0',
    );
  });
}
