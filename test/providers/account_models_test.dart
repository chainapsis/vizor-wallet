import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

void main() {
  test(
    'AccountInfo.fromJson infers legacy first software account as seed anchor',
    () {
      final account = AccountInfo.fromJson({
        'uuid': 'account-1',
        'name': 'Primary Vault',
        'order': 0,
        'isHardware': false,
      });

      expect(account.isSeedAnchor, isTrue);
    },
  );

  test(
    'AccountInfo.fromJson does not infer imported or hardware accounts as seed anchors',
    () {
      final imported = AccountInfo.fromJson({
        'uuid': 'account-2',
        'name': 'Imported Vault',
        'order': 1,
        'isHardware': false,
      });
      final hardware = AccountInfo.fromJson({
        'uuid': 'account-3',
        'name': 'Keystone',
        'order': 0,
        'isHardware': true,
      });

      expect(imported.isSeedAnchor, isFalse);
      expect(hardware.isSeedAnchor, isFalse);
    },
  );

  test('AccountInfo.fromJson preserves explicit seed anchor flag', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-1',
      'name': 'Imported First',
      'order': 0,
      'isHardware': false,
      'isSeedAnchor': false,
    });

    expect(account.isSeedAnchor, isFalse);
  });
}
