import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  test(
    'imports account metadata and USB model without a wallet identity',
    () async {
      final notifier = _CapturingAccountNotifier();
      final container = ProviderContainer(
        overrides: [accountProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(ledgerAccountImporterProvider)(
        name: 'Ledger',
        account: const LedgerDeviceAccount(
          ufvk: 'uview-test',
          seedFingerprint: [1, 2, 3],
          accountIndex: 7,
          appVersion: '3.9.3',
          deviceModel: 'Ledger Nano S Plus',
        ),
        birthdayHeight: 3000000,
        profilePictureId: kDefaultProfilePictureId,
      );
      expect(notifier.importedUfvk, 'uview-test');
      expect(notifier.importedIndex, 7);
      expect(notifier.importedSeedFingerprint, [1, 2, 3]);
      expect(notifier.importedDeviceModel, 'Ledger Nano S Plus');
    },
  );

  for (final sameUfvk in [true, false]) {
    test(
      'duplicate check compares UFVK, not account index: $sameUfvk',
      () async {
        final container = ProviderContainer(
          overrides: [
            accountProvider.overrideWith(
              () => _CapturingAccountNotifier(
                const AccountState(
                  accounts: [
                    AccountInfo(
                      uuid: 'existing',
                      name: 'Existing',
                      order: 0,
                      isHardware: true,
                      hardwareSignerKind: HardwareSignerKind.ledger,
                      zip32AccountIndex: 0,
                    ),
                  ],
                ),
              ),
            ),
            ledgerAccountUfvkLoaderProvider.overrideWithValue((uuid) async {
              expect(uuid, 'existing');
              return sameUfvk ? 'uview-new' : 'uview-other';
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        final result = container.read(ledgerAccountDuplicateCheckerProvider)(
          'uview-new',
        );
        if (sameUfvk) {
          await expectLater(
            result,
            throwsA(isA<LedgerDuplicateAccountException>()),
          );
        } else {
          await result;
        }
      },
    );
  }
}

class _CapturingAccountNotifier extends AccountNotifier {
  _CapturingAccountNotifier([this.initial = const AccountState()]);
  final AccountState initial;
  String? importedUfvk;
  int? importedIndex;
  List<int>? importedSeedFingerprint;
  String? importedDeviceModel;

  @override
  FutureOr<AccountState> build() => initial;

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
  }) async {
    importedUfvk = ufvk;
    importedIndex = zip32Index;
    importedSeedFingerprint = seedFingerprint;
    importedDeviceModel = ledgerDeviceModel;
  }
}
