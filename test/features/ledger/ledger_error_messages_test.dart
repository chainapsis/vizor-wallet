import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_error_messages.dart';

void main() {
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
