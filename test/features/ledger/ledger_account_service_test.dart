import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

void main() {
  for (final pendingPassword in [null, 'Password1!']) {
    for (final fails in [false, true]) {
      test(
        'account setup password=$pendingPassword import failure=$fails',
        () async {
          final events = <String>[];
          final security = _RecordingSecurityNotifier(events);
          final container = ProviderContainer(
            overrides: [
              appSecurityProvider.overrideWith(() => security),
              ledgerAccountImporterProvider.overrideWithValue(({
                required name,
                required account,
                required birthdayHeight,
                required profilePictureId,
              }) async {
                events.add('import');
                if (fails) throw StateError('import failed');
              }),
            ],
          );
          addTearDown(container.dispose);
          final result = container.read(ledgerAccountSetupProvider)(
            name: 'Ledger',
            account: const LedgerDeviceAccount(
              ufvk: 'uview-test',
              seedFingerprint: [1],
              accountIndex: 0,
            ),
            birthdayHeight: 3000000,
            profilePictureId: kDefaultProfilePictureId,
            pendingPassword: pendingPassword,
          );
          if (fails) {
            await expectLater(result, throwsStateError);
          } else {
            await result;
          }
          expect(
            events,
            pendingPassword == null
                ? ['import']
                : ['prepare', 'import', if (fails) 'rollback' else 'commit'],
          );
        },
      );
    }
  }

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

class _RecordingSecurityNotifier extends AppSecurityNotifier {
  _RecordingSecurityNotifier(this.events);
  final List<String> events;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);

  @override
  Future<void> preparePasswordSetup(String password) async {
    events.add('prepare');
  }

  @override
  void commitPasswordSetup() => events.add('commit');

  @override
  Future<void> rollbackPasswordSetup() async {
    events.add('rollback');
  }
}
