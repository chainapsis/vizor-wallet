import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_account_import_context.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

const _walletA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _walletB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  test(
    'groups only matching Ledger fingerprints and suggests the first gap',
    () {
      final accounts = [
        _ledger('a-0', 0, 0, _walletA),
        _ledger('a-1', 1, 1, _walletA),
        _ledger('a-3', 3, 2, _walletA),
        _ledger('b-2', 2, 3, _walletB),
        const AccountInfo(uuid: 'software', name: 'Software', order: 4),
      ];

      final result = resolveLedgerAccountImportContext(
        accounts: accounts,
        sourceAccountUuid: 'a-0',
      )!;

      expect(result.knownAccounts.map((account) => account.uuid), [
        'a-0',
        'a-1',
        'a-3',
      ]);
      expect(result.usedIndexes, {0, 1, 3});
      expect(result.suggestedIndex, 2);
      expect(result.usesIndex(2), isFalse);
      expect(result.usesIndex(3), isTrue);
    },
  );

  test('keeps a Ledger account without an identity isolated', () {
    final result = resolveLedgerAccountImportContext(
      accounts: [
        _ledger('legacy', 4, 0, null),
        _ledger('known', 0, 1, _walletA),
      ],
      sourceAccountUuid: 'legacy',
    )!;

    expect(result.knownAccounts.map((account) => account.uuid), ['legacy']);
    expect(result.suggestedIndex, 0);
  });

  test('allows the same index on a different Ledger wallet', () {
    final result = resolveLedgerAccountImportContext(
      accounts: [_ledger('a', 0, 0, _walletA), _ledger('b', 0, 1, _walletB)],
      sourceAccountUuid: 'a',
    )!;

    expect(result.usedIndexes, {0});
    expect(result.knownAccounts.map((account) => account.uuid), ['a']);
  });
}

AccountInfo _ledger(String uuid, int index, int order, String? fingerprint) =>
    AccountInfo(
      uuid: uuid,
      name: 'Ledger $uuid',
      order: order,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      zip32AccountIndex: index,
      ledgerWalletFingerprint: fingerprint,
    );
