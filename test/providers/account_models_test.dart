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

  test('Ledger signer kind survives JSON persistence', () {
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

    expect(restored.isHardware, isTrue);
    expect(restored.hardwareSignerKind, HardwareSignerKind.ledger);
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
      ledgerWalletFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ledgerWalletName: 'Cold storage',
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
    expect(
      restored.ledgerWalletFingerprint,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(restored.ledgerWalletName, 'Cold storage');
  });

  test('legacy Ledger accounts default to automatic connection selection', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-1',
      'name': 'Ledger',
      'order': 0,
      'isHardware': true,
      'hardwareSignerKind': 'ledger',
    });

    expect(
      account.ledgerConnectionPreference,
      LedgerConnectionPreference.automatic,
    );
    expect(account.ledgerLastTransport, isNull);
    expect(account.ledgerDeviceId, isNull);
  });

  test('software accounts are neither Keystone nor Ledger accounts', () {
    const account = AccountInfo(uuid: 'account-1', name: 'Software', order: 0);

    expect(account.isHardware, isFalse);
    expect(account.isKeystone, isFalse);
    expect(account.isLedger, isFalse);
  });

  group('resolveAccountFamilies', () {
    const fingerprintA =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const fingerprintB =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    AccountInfo ledgerAccount({
      required String uuid,
      required int order,
      String? fingerprint,
    }) => AccountInfo(
      uuid: uuid,
      name: 'Ledger $uuid',
      order: order,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      ledgerWalletFingerprint: fingerprint,
    );

    test('groups Ledger accounts with the same fingerprint', () {
      final first = ledgerAccount(
        uuid: 'ledger-1',
        order: 0,
        fingerprint: fingerprintA,
      );
      final second = ledgerAccount(
        uuid: 'ledger-2',
        order: 1,
        fingerprint: fingerprintA,
      );

      final families = resolveAccountFamilies([first, second]);

      expect(families, hasLength(1));
      expect(families.single.kind, AccountFamilyKind.ledger);
      expect(families.single.accounts, [same(first), same(second)]);
      expect(families.single.name, 'Ledger wallet');
      expect(families.single.stableKey, isNot(contains(fingerprintA)));
    });

    test('keeps different verified Ledger fingerprints separate', () {
      final families = resolveAccountFamilies([
        ledgerAccount(uuid: 'ledger-a', order: 0, fingerprint: fingerprintA),
        ledgerAccount(uuid: 'ledger-b', order: 1, fingerprint: fingerprintB),
      ]);

      expect(families, hasLength(2));
      expect(families.map((family) => family.kind), [
        AccountFamilyKind.ledger,
        AccountFamilyKind.ledger,
      ]);
      expect(families.map((family) => family.accounts.single.uuid), [
        'ledger-a',
        'ledger-b',
      ]);
      expect(families[0].stableKey, isNot(families[1].stableKey));
    });

    test('keeps Ledger accounts without a fingerprint standalone', () {
      final families = resolveAccountFamilies([
        ledgerAccount(uuid: 'missing', order: 0),
        ledgerAccount(uuid: 'empty', order: 1, fingerprint: '   '),
        ledgerAccount(uuid: 'invalid', order: 2, fingerprint: 'not-verified'),
      ]);

      expect(families, hasLength(3));
      expect(
        families.map((family) => family.kind),
        everyElement(AccountFamilyKind.standalone),
      );
      expect(families.map((family) => family.accounts.single.uuid), [
        'missing',
        'empty',
        'invalid',
      ]);
    });

    test('keeps software and Keystone accounts standalone', () {
      const software = AccountInfo(
        uuid: 'software',
        name: 'Software',
        order: 0,
        ledgerWalletFingerprint: fingerprintA,
      );
      const keystone = AccountInfo(
        uuid: 'keystone',
        name: 'Keystone',
        order: 1,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.keystone,
        ledgerWalletFingerprint: fingerprintA,
      );

      final families = resolveAccountFamilies([software, keystone]);

      expect(families, hasLength(2));
      expect(
        families.map((family) => family.kind),
        everyElement(AccountFamilyKind.standalone),
      );
      expect(families.map((family) => family.accounts.single.uuid), [
        'software',
        'keystone',
      ]);
    });

    test('preserves family and member input order', () {
      final firstLedger = ledgerAccount(
        uuid: 'ledger-2',
        order: 20,
        fingerprint: fingerprintA,
      );
      const software = AccountInfo(
        uuid: 'software',
        name: 'Software',
        order: 0,
      );
      final secondLedger = ledgerAccount(
        uuid: 'ledger-1',
        order: 10,
        fingerprint: fingerprintA,
      );

      final families = resolveAccountFamilies([
        firstLedger,
        software,
        secondLedger,
      ]);

      expect(families, hasLength(2));
      expect(families.first.accounts.map((account) => account.uuid), [
        'ledger-2',
        'ledger-1',
      ]);
      expect(families.last.accounts.single.uuid, 'software');
    });
  });
}
