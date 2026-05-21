import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/account_name_policy.dart';

void main() {
  test('counts user-perceived characters for account names', () {
    final twentyEmoji = List.filled(20, '😀').join();
    final twentyOneEmoji = List.filled(21, '😀').join();

    expect(accountNameCharacterLength(twentyEmoji), 20);
    expect(isAccountNameLengthValid(twentyEmoji), isTrue);
    expect(isAccountNameLengthValid(twentyOneEmoji), isFalse);
  });

  test('trims account names before validating length', () {
    expect(normalizeAccountName('  Account  '), 'Account');
    expect(isAccountNameLengthValid('   '), isFalse);
  });

  test('throws for invalid account names', () {
    expect(() => validateAccountName(''), throwsArgumentError);
    expect(
      () => validateAccountName('123456789012345678901'),
      throwsArgumentError,
    );
  });
}
