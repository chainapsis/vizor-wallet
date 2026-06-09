import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

void main() {
  test('mergeBootstrappedAccountInfo keeps stored UI metadata', () {
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
    );

    final merged = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: storedAccount,
      order: 3,
    );

    expect(merged.uuid, 'account-1');
    expect(merged.name, 'Stored Name');
    expect(merged.order, 9);
    expect(merged.isHardware, isTrue);
    expect(merged.isSeedAnchor, isTrue);
    expect(merged.profilePictureId, 'pfp-04');
  });

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

  test('empty bootstrap has no password rotation recovery failure', () {
    expect(AppBootstrapState.empty.passwordRotationRecoveryFailed, isFalse);
  });

  test('empty bootstrap starts with privacy mode disabled', () {
    expect(AppBootstrapState.empty.privacyModeEnabled, isFalse);
  });
}
