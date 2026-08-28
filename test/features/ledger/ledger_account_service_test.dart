import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

const _fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  const exportedAccount = LedgerDeviceAccount(
    ufvk: 'uview-test',
    seedFingerprint: [1, 2, 3],
    accountIndex: 0,
    appVersion: '3.9.2',
  );

  test('Ledger import rejects an export without wallet identity', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(ledgerAccountImporterProvider)(
        name: 'Ledger',
        account: exportedAccount,
        birthdayHeight: 2_900_000,
        profilePictureId: kDefaultProfilePictureId,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('Ledger import forwards the authenticated wallet fingerprint', () async {
    final notifier = _CapturingAccountNotifier();
    final container = ProviderContainer(
      overrides: [accountProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    await container.read(ledgerAccountImporterProvider)(
      name: 'Ledger',
      account: exportedAccount.withWalletIdentity(
        const LedgerWalletIdentity(fingerprint: _fingerprint),
      ),
      birthdayHeight: 2_900_000,
      profilePictureId: kDefaultProfilePictureId,
    );

    expect(notifier.importedFingerprint, _fingerprint);
  });
}

class _CapturingAccountNotifier extends AccountNotifier {
  String? importedFingerprint;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> importLedgerAccount({
    required String name,
    required String ufvk,
    required List<int> seedFingerprint,
    required int zip32Index,
    required int birthdayHeight,
    String profilePictureId = kDefaultProfilePictureId,
    LedgerConnectionTransport? connectionTransport,
    String? ledgerDeviceId,
    String? ledgerDeviceName,
    String? ledgerDeviceModel,
    required String ledgerWalletFingerprint,
  }) async {
    importedFingerprint = ledgerWalletFingerprint;
  }
}
