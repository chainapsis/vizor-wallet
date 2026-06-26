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

  test('AccountInfo.fromJson preserves multisig account kind', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-4',
      'name': 'Family vault',
      'order': 2,
      'kind': 'multisig',
      'isHardware': false,
    });

    expect(account.kind, AccountKind.multisig);
    expect(account.isMultisig, isTrue);
    expect(account.isHardware, isFalse);
    expect(account.hasLocalMnemonic, isFalse);
    expect(account.supportsSeedPhraseReveal, isFalse);
    expect(account.supportsSoftwareSigning, isFalse);
    expect(account.isSeedAnchor, isFalse);
    expect(account.toJson()['kind'], 'multisig');
  });

  test('AccountInfo account kind helpers distinguish mnemonic accounts', () {
    const software = AccountInfo(uuid: 'account-1', name: 'Software', order: 0);
    const hardware = AccountInfo(
      uuid: 'account-2',
      name: 'Keystone',
      order: 1,
      kind: AccountKind.hardware,
    );
    const multisig = AccountInfo(
      uuid: 'account-3',
      name: 'Family vault',
      order: 2,
      kind: AccountKind.multisig,
    );

    expect(software.isSoftware, isTrue);
    expect(software.hasLocalMnemonic, isTrue);
    expect(software.supportsSeedPhraseReveal, isTrue);
    expect(software.supportsSoftwareSigning, isTrue);

    expect(hardware.isSoftware, isFalse);
    expect(hardware.hasLocalMnemonic, isFalse);
    expect(hardware.supportsSeedPhraseReveal, isFalse);
    expect(hardware.supportsSoftwareSigning, isFalse);

    expect(multisig.isSoftware, isFalse);
    expect(multisig.hasLocalMnemonic, isFalse);
    expect(multisig.supportsSeedPhraseReveal, isFalse);
    expect(multisig.supportsSoftwareSigning, isFalse);
  });
}
