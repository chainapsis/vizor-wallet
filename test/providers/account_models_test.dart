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

  test('legacy hardware accounts default to the Keystone signer', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-1',
      'name': 'Legacy hardware',
      'order': 0,
      'isHardware': true,
    });

    expect(account.hardwareSignerKind, HardwareSignerKind.keystone);
    expect(account.isKeystone, isTrue);
    expect(account.isLedger, isFalse);
  });

  test('Ledger signer and derivation metadata survive JSON persistence', () {
    const account = AccountInfo(
      uuid: 'account-1',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      birthdayHeight: 2500000,
      zip32AccountIndex: 12,
    );

    final restored = AccountInfo.fromJson(account.toJson());

    expect(restored.isLedger, isTrue);
    expect(restored.isKeystone, isFalse);
    expect(restored.birthdayHeight, 2500000);
    expect(restored.zip32AccountIndex, 12);
  });

  test('Ledger connection metadata survives JSON persistence', () {
    const account = AccountInfo(
      uuid: 'account-1',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      ledgerConnectionPreference: LedgerConnectionPreference.bluetooth,
      ledgerLastTransport: LedgerConnectionTransport.bluetooth,
      ledgerDeviceId: 'device-id',
      ledgerDeviceName: 'Rowan Ledger',
      ledgerDeviceModel: 'Nano X',
    );

    final restored = AccountInfo.fromJson(account.toJson());

    expect(
      restored.ledgerConnectionPreference,
      LedgerConnectionPreference.bluetooth,
    );
    expect(restored.ledgerLastTransport, LedgerConnectionTransport.bluetooth);
    expect(restored.ledgerDeviceId, 'device-id');
    expect(restored.ledgerDeviceName, 'Rowan Ledger');
    expect(restored.ledgerDeviceModel, 'Nano X');
  });

  test('software accounts do not retain Ledger-only metadata', () {
    const account = AccountInfo(
      uuid: 'account-1',
      name: 'Software',
      order: 0,
      ledgerDeviceId: 'ignored',
    );

    final json = account.toJson();

    expect(account.isKeystone, isFalse);
    expect(account.isLedger, isFalse);
    expect(json['ledgerDeviceId'], isNull);
  });
}
