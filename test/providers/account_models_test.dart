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

  test('AccountInfo round-trips seed family metadata', () {
    const account = AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      seedFamilyId: 'a1b2c3d4',
    );

    final restored = AccountInfo.fromJson(account.toJson());

    expect(restored.seedFamilyId, 'a1b2c3d4');
  });

  test(
    'groupAccountsBySeedFamily groups matching metadata and puts active first',
    () {
      const accounts = [
        AccountInfo(uuid: 'a', name: 'First', order: 0, seedFamilyId: 'one'),
        AccountInfo(uuid: 'b', name: 'Second', order: 1, seedFamilyId: 'one'),
        AccountInfo(uuid: 'c', name: 'Third', order: 2, seedFamilyId: 'two'),
      ];

      final families = groupAccountsBySeedFamily(accounts, 'b');

      expect(families, hasLength(2));
      expect(families.first.containsActiveAccount, isTrue);
      expect(families.first.accounts.map((account) => account.uuid), [
        'b',
        'a',
      ]);
      expect(families.last.accounts.single.uuid, 'c');
    },
  );

  test('groupAccountsBySeedFamily isolates accounts without metadata', () {
    const accounts = [
      AccountInfo(uuid: 'a', name: 'First', order: 0),
      AccountInfo(uuid: 'b', name: 'Second', order: 1),
    ];

    final families = groupAccountsBySeedFamily(accounts, 'a');

    expect(families, hasLength(2));
    expect(families.first.accounts.single.uuid, 'a');
    expect(families.last.accounts.single.uuid, 'b');
  });
}
