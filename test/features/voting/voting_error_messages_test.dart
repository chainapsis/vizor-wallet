import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';
import 'package:zcash_wallet/src/features/voting/voting_message.dart';
import '../../support/test_l10n.dart';
import 'package:zcash_wallet/src/features/voting/voting_error_messages.dart';

void main() {
  const app = 'Open the Zcash app on your Ledger.';

  test('Ledger vote failures are worded by kind without status codes', () {
    final expected = {
      'ledger_status_6985: Ledger request was rejected or the PCZT was not finalized':
          'The vote signature was rejected on your Ledger. Retry to sign again.',
      'ledger_status_5515: Ledger device is locked; unlock it and reopen the Zcash app':
          'Unlock your Ledger. $app',
      'ledger_status_6d00: The running Ledger app does not support this command':
          '$app Then retry.',
      'ledger_cancelled: Ledger operation was cancelled. Retry when ready.':
          testL10n.votingErrorLedgerCancelled,
    };
    for (final MapEntry(key: error, value: message) in expected.entries) {
      expect(
        ledgerVotingErrorMessage(
          testL10n,
          StateError(error),
          appInstruction: app,
        ),
        message,
        reason: error,
      );
    }
    expect(
      ledgerVotingErrorMessage(
        testL10n,
        'ledger_capacity: Ledger supports at most 32 shielded actions; found 33',
        appInstruction: app,
      ),
      'This vote is too large for your Ledger to sign.',
    );
  });

  test('voting text never keeps a Ledger code prefix', () {
    expect(
      votingTextMessage(
        'Bad state: ledger_linux_usb_access: No Ledger device found.',
      ),
      const VotingLiteralMessage('No Ledger device found.'),
    );
    expect(
      votingMessageForError(
        StateError('ledger_status_6f01: Ledger Zcash app returned status'),
      ),
      const VotingLiteralMessage('Ledger Zcash app returned status'),
    );
    expect(
      votingTextMessage('ledger_transport: No Ledger device found.'),
      const VotingLiteralMessage('No Ledger device found.'),
    );
    expect(
      votingTextMessage(
        'ledger_signature_mismatch: Validate Ledger transparent signature 0',
      ),
      const VotingLiteralMessage('Validate Ledger transparent signature 0'),
    );
  });

  test('untranslated SDK text is not shown', () {
    expect(
      friendlyVotingErrorText(
        testL10n,
        'Bad state: ledger_linux_usb_access: No Ledger device found.',
      ),
      testL10n.votingErrorSessionFailed,
    );
  });

  group('untranslated SDK text', () {
    final ko = lookupAppLocalizations(const Locale('ko'));

    test('shows only its summary in the shown language', () {
      expect(
        const VotingLiteralMessage(
          'rpc: deadline exceeded',
          summary: VotingNoticeKind.chainRecoveryPending,
        ).text(ko),
        ko.votingErrorChainRecoveryPending,
      );
    });

    test('is not summarized twice inside a message that has its own', () {
      expect(
        const VotingKeystoneQrFailure(
          VotingLiteralMessage('invalid batch plan'),
        ).text(ko),
        ko.votingErrorKeystoneQrPrepareFailed('invalid batch plan'),
      );
      expect(
        const VotingBatchFailure(
          VotingBatchFailureKind.voteCasting,
          'bundle 1 proposal 2: ledger_status_6985: denied',
        ).text(ko),
        ko.votingErrorVoteCastingFailed('bundle 1 proposal 2: denied'),
      );
    });

    test('a mismatched Ledger signature has its own copy', () {
      expect(
        const VotingNotice(VotingNoticeKind.ledgerSignatureMismatch).text(ko),
        ko.votingErrorLedgerSignatureMismatch,
      );
    });
  });
}
