import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

void main() {
  test('AccountInfo.fromJson normalizes legacy profile picture ids', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-1',
      'name': 'Legacy Samurai',
      'order': 0,
      'profilePictureId': 'samurai',
    });

    expect(account.profilePictureId, 'pfp-03');
  });

  test('AccountInfo.fromJson keeps wallet link source account uuid', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-1',
      'name': 'Linked',
      'order': 0,
      'walletLinkSourceAccountUuid': ' 550e8400-e29b-41d4-a716-446655440000 ',
    });

    expect(
      account.walletLinkSourceAccountUuid,
      '550e8400-e29b-41d4-a716-446655440000',
    );
  });

  test(
    'mergeBootstrappedAccountInfo keeps UI metadata but trusts Rust signer metadata',
    () {
      const rustAccount = AccountInfo(
        uuid: 'account-1',
        name: 'Rust Name',
        order: 0,
        isSeedAnchor: true,
      );
      const storedAccount = AccountInfo(
        uuid: 'account-1',
        name: 'Stored Name',
        order: 9,
        isHardware: true,
        isSeedAnchor: false,
        profilePictureId: 'pfp-04',
        walletLinkSourceAccountUuid: 'desktop-account-1',
      );

      final merged = mergeBootstrappedAccountInfo(
        rustAccount: rustAccount,
        storedAccount: storedAccount,
        order: 3,
      );

      expect(merged.uuid, 'account-1');
      expect(merged.name, 'Stored Name');
      expect(merged.order, 9);
      expect(merged.isHardware, isFalse);
      expect(merged.isSeedAnchor, isTrue);
      expect(merged.profilePictureId, 'pfp-04');
      expect(merged.walletLinkSourceAccountUuid, 'desktop-account-1');
    },
  );

  test(
    'mergeBootstrappedAccountInfo normalizes legacy profile picture ids',
    () {
      const rustAccount = AccountInfo(
        uuid: 'account-1',
        name: 'Rust Name',
        order: 0,
      );
      const storedAccount = AccountInfo(
        uuid: 'account-1',
        name: 'Stored Name',
        order: 0,
        profilePictureId: 'samurai',
      );

      final merged = mergeBootstrappedAccountInfo(
        rustAccount: rustAccount,
        storedAccount: storedAccount,
        order: 0,
      );

      expect(merged.profilePictureId, 'pfp-03');
    },
  );

  test('mergeBootstrappedAccountInfo falls back to Rust metadata', () {
    const rustAccount = AccountInfo(
      uuid: 'account-2',
      name: 'Rust Name',
      order: 0,
    );

    final merged = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: null,
      order: 1,
    );

    expect(merged.uuid, 'account-2');
    expect(merged.name, 'Rust Name');
    expect(merged.order, 1);
    expect(merged.isHardware, isFalse);
    expect(merged.isSeedAnchor, isFalse);
  });

  test('mergeBootstrappedAccountInfo recovers Rust hardware metadata', () {
    const rustAccount = AccountInfo(
      uuid: 'account-3',
      name: 'Rust Keystone',
      order: 1,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.keystone,
    );
    const storedAccount = AccountInfo(
      uuid: 'account-3',
      name: 'Stored Keystone',
      order: 1,
    );

    final merged = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: storedAccount,
      order: 1,
    );

    expect(merged.isHardware, isTrue);
    expect(merged.name, 'Stored Keystone');
  });

  test('mergeBootstrappedAccountInfo uses Rust Ledger signer kind', () {
    const rustAccount = AccountInfo(
      uuid: 'account-ledger',
      name: 'Rust hardware',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      birthdayHeight: 2600000,
      zip32AccountIndex: 7,
    );
    const storedAccount = AccountInfo(
      uuid: 'account-ledger',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.keystone,
      birthdayHeight: 1,
      zip32AccountIndex: 99,
    );

    final merged = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: storedAccount,
      order: 0,
    );

    expect(merged.hardwareSignerKind, HardwareSignerKind.ledger);
    expect(merged.birthdayHeight, 2600000);
    expect(merged.zip32AccountIndex, 7);
  });

  test('bootstrap preserves persisted Ledger pairing and preferences', () {
    const rustAccount = AccountInfo(
      uuid: 'ledger',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
    );
    for (final preference in LedgerConnectionPreference.values) {
      final stored = rustAccount.copyWith(
        ledgerDeviceId: 'paired-device',
        ledgerDeviceName: 'My Ledger',
        ledgerDeviceModel: 'nanoX',
        ledgerLastTransport: LedgerConnectionTransport.bluetooth,
        ledgerConnectionPreference: preference,
      );
      final merged = mergeBootstrappedAccountInfo(
        rustAccount: rustAccount,
        storedAccount: AccountInfo.fromJson(stored.toJson()),
        order: 0,
      );
      expect(merged.ledgerDeviceId, 'paired-device');
      expect(merged.ledgerDeviceName, 'My Ledger');
      expect(merged.ledgerDeviceModel, 'nanoX');
      expect(merged.ledgerLastTransport, LedgerConnectionTransport.bluetooth);
      expect(merged.ledgerConnectionPreference, preference);
      expect(
        AccountInfo.fromJson(merged.toJson()).ledgerDeviceId,
        'paired-device',
      );
    }
    final fresh = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: null,
      order: 0,
    );
    expect(fresh.ledgerDeviceId, isNull);
    expect(
      fresh.ledgerConnectionPreference,
      LedgerConnectionPreference.automatic,
    );
  });

  test('legacy hardware backfill preserves each stored signer kind', () {
    const accounts = [
      AccountInfo(uuid: 'software', name: 'Software', order: 0),
      AccountInfo(
        uuid: 'keystone',
        name: 'Keystone',
        order: 1,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.keystone,
      ),
      AccountInfo(
        uuid: 'ledger',
        name: 'Ledger',
        order: 2,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
      ),
    ];

    final backfill = legacyHardwareAccountsForBackfill(accounts);

    expect(backfill, hasLength(2));
    expect(backfill[0].accountUuid, 'keystone');
    expect(backfill[0].hardwareSignerKind, 'keystone');
    expect(backfill[1].accountUuid, 'ledger');
    expect(backfill[1].hardwareSignerKind, 'ledger');
  });

  test('empty bootstrap has no password rotation recovery failure', () {
    expect(AppBootstrapState.empty.passwordRotationRecoveryFailed, isFalse);
  });

  test('empty bootstrap starts with privacy mode disabled', () {
    expect(AppBootstrapState.empty.privacyModeEnabled, isFalse);
  });

  test(
    'empty bootstrap starts with sync keep-awake disabled and unprompted',
    () {
      expect(AppBootstrapState.empty.syncKeepAwakeEnabled, isFalse);
      expect(AppBootstrapState.empty.syncKeepAwakePromptSeen, isFalse);
    },
  );
}
