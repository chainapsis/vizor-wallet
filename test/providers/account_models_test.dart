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

  test('AccountInfo round-trips seed family and display-name metadata', () {
    const account = AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      seedFamilyId: 'a1b2c3d4',
      accountGroupName: 'Everyday wallet',
    );

    final restored = AccountInfo.fromJson(account.toJson());

    expect(restored.seedFamilyId, 'a1b2c3d4');
    expect(restored.accountGroupName, 'Everyday wallet');
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
      expect(families.first.name, 'Wallet 1');
      expect(families.last.name, 'Wallet 2');
    },
  );

  test(
    'resolveActiveAccountForDisplay falls back to the first ordered account',
    () {
      const accounts = [
        AccountInfo(uuid: 'later', name: 'Later', order: 2),
        AccountInfo(uuid: 'first', name: 'First', order: 0),
      ];

      expect(
        resolveActiveAccountForDisplay(accounts, 'removed-account')?.uuid,
        'first',
      );
    },
  );

  test(
    'groupAccountsBySeedFamily isolates hardware accounts with matching seed metadata',
    () {
      const accounts = [
        AccountInfo(
          uuid: 'software',
          name: 'Software',
          order: 0,
          seedFamilyId: 'shared-fingerprint',
        ),
        AccountInfo(
          uuid: 'hardware-1',
          name: 'Keystone 1',
          order: 1,
          isHardware: true,
          seedFamilyId: 'shared-fingerprint',
        ),
        AccountInfo(
          uuid: 'hardware-2',
          name: 'Keystone 2',
          order: 2,
          isHardware: true,
          seedFamilyId: 'shared-fingerprint',
        ),
      ];

      final families = groupAccountsBySeedFamily(accounts, 'hardware-1');

      expect(families, hasLength(3));
      expect(families.first.accounts.single.uuid, 'hardware-1');
      expect(families[1].accounts.single.uuid, 'software');
      expect(families[2].accounts.single.uuid, 'hardware-2');
    },
  );

  test(
    'group names stay tied to creation order when another family is active',
    () {
      const accounts = [
        AccountInfo(uuid: 'a', name: 'First', order: 0, seedFamilyId: 'one'),
        AccountInfo(
          uuid: 'b',
          name: 'Second',
          order: 1,
          seedFamilyId: 'two',
          accountGroupName: 'Savings wallet',
        ),
      ];

      final families = groupAccountsBySeedFamily(accounts, 'b');

      expect(families.first.anchorAccountUuid, 'b');
      expect(families.first.name, 'Savings wallet');
      expect(families.last.anchorAccountUuid, 'a');
      expect(families.last.name, 'Wallet 1');
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
