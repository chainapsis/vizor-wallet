import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/home/providers/backup_reminder_provider.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'bootstrap preserves pending, snoozed, and completed backups after relaunch',
    () {
      final now = DateTime.utc(2026, 10, 1);
      const rustAccount = AccountInfo(
        uuid: 'account-1',
        name: 'Rust Name',
        order: 0,
      );
      final pending = rustAccount.copyWith(setupPending: true);
      final snoozed = pending.copyWith(
        backupReminderSnoozedUntilUtc: now.add(const Duration(days: 14)),
        backupReminderSnoozeCount: 2,
      );
      final completed = snoozed.copyWith(
        setupPending: false,
        clearBackupReminderSnooze: true,
      );
      for (final stored in [pending, snoozed, completed]) {
        final merged = mergeBootstrappedAccountInfo(
          rustAccount: rustAccount,
          storedAccount: AccountInfo.fromJson(stored.toJson()),
          order: 0,
        );
        expect(merged.setupPending, stored.setupPending);
        expect(
          merged.backupReminderSnoozedUntilUtc,
          stored.backupReminderSnoozedUntilUtc,
        );
        expect(
          merged.backupReminderSnoozeCount,
          stored.backupReminderSnoozeCount,
        );
        expect(
          shouldShowBackupReminder(merged, now),
          identical(stored, pending),
        );
        if (identical(stored, snoozed)) {
          expect(
            shouldShowBackupReminder(merged, now.add(const Duration(days: 14))),
            isTrue,
          );
        }
      }
    },
  );

  test(
    'bootstrap preserves deferred Zcash education independently of backup',
    () {
      const rustAccount = AccountInfo(
        uuid: 'education',
        name: 'Rust',
        order: 0,
      );
      for (final backupPending in [false, true]) {
        for (final educationPending in [false, true]) {
          final stored = rustAccount.copyWith(
            setupPending: backupPending,
            giftEducationPending: educationPending,
          );
          final merged = mergeBootstrappedAccountInfo(
            rustAccount: rustAccount,
            storedAccount: AccountInfo.fromJson(stored.toJson()),
            order: 0,
          );
          expect(merged.setupPending, backupPending);
          expect(merged.giftEducationPending, educationPending);
        }
      }
      expect(
        mergeBootstrappedAccountInfo(
          rustAccount: rustAccount,
          storedAccount: null,
          order: 0,
        ).giftEducationPending,
        isFalse,
      );
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
    expect(merged.setupPending, isFalse);
    expect(merged.backupReminderSnoozedUntilUtc, isNull);
    expect(merged.backupReminderSnoozeCount, 0);
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

  test('bootstrap preserves Ledger pairing and ignores legacy preferences', () {
    const rustAccount = AccountInfo(
      uuid: 'ledger',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
    );
    for (final preference in ['automatic', 'usb', 'bluetooth']) {
      final stored = rustAccount.copyWith(
        ledgerDeviceId: 'paired-device',
        ledgerDeviceName: 'My Ledger',
        ledgerDeviceModel: 'nanoX',
        ledgerLastTransport: LedgerConnectionTransport.bluetooth,
      );
      final merged = mergeBootstrappedAccountInfo(
        rustAccount: rustAccount,
        storedAccount: AccountInfo.fromJson({
          ...stored.toJson(),
          'ledgerConnectionPreference': preference,
        }),
        order: 0,
      );
      expect(merged.ledgerDeviceId, 'paired-device');
      expect(merged.ledgerDeviceName, 'My Ledger');
      expect(merged.ledgerDeviceModel, 'nanoX');
      expect(merged.ledgerLastTransport, LedgerConnectionTransport.bluetooth);
      expect(merged.toJson().containsKey('ledgerConnectionPreference'), false);
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

  group('private queries preference', () {
    AppSecureStore storeWith(Map<String, String> values) {
      FlutterSecureStorage.setMockInitialValues(values);
      return AppSecureStore.testing(storage: const FlutterSecureStorage());
    }

    test('migrates the legacy secure-store flag on first read', () async {
      final storage = storeWith({kLegacyEnhancePirEnabledKey: 'true'});
      final preferences = _FakeEnhancePirStore();

      final enabled = await readEnhancePirEnabledPreference(
        storage,
        preferences: preferences,
      );

      expect(enabled, isTrue);
      expect(preferences.saved, isTrue);
      expect(await storage.readPlain(kLegacyEnhancePirEnabledKey), isNull);
    });

    test('records an explicit off so the legacy key is read once', () async {
      final storage = storeWith({});
      final preferences = _FakeEnhancePirStore();

      expect(
        await readEnhancePirEnabledPreference(
          storage,
          preferences: preferences,
        ),
        isFalse,
      );
      expect(preferences.saved, isFalse);
      expect(preferences.writes, 1);
    });

    test('prefers the saved preference over the legacy flag', () async {
      final storage = storeWith({kLegacyEnhancePirEnabledKey: 'true'});
      final preferences = _FakeEnhancePirStore(saved: false);

      expect(
        await readEnhancePirEnabledPreference(
          storage,
          preferences: preferences,
        ),
        isFalse,
      );
      expect(preferences.writes, 0);
      expect(
        await storage.readPlain(kLegacyEnhancePirEnabledKey),
        'true',
        reason: 'the legacy key is only dropped by an actual migration',
      );
    });

    for (final legacy in [null, 'false', 'true']) {
      test(
        'an unreadable preference is private for this launch (legacy=$legacy)',
        () async {
          final storage = storeWith({kLegacyEnhancePirEnabledKey: ?legacy});
          final preferences = _FailingEnhancePirStore();

          expect(
            await readEnhancePirEnabledPreference(
              storage,
              preferences: preferences,
            ),
            isTrue,
            reason: 'unknown must never relax native private mode',
          );
          expect(preferences.writes, 0, reason: 'the saved choice is kept');
          expect(await storage.readPlain(kLegacyEnhancePirEnabledKey), legacy);
        },
      );
    }

    test('an unreadable legacy flag is private and not migrated', () async {
      final storage = _UnreadableSecureStore();
      final preferences = _FakeEnhancePirStore();

      expect(
        await readEnhancePirEnabledPreference(
          storage,
          preferences: preferences,
        ),
        isTrue,
      );
      expect(preferences.writes, 0, reason: 'nothing was known to migrate');
      expect(
        storage.deletes,
        isEmpty,
        reason: 'the legacy key stays for retry',
      );
    });

    test('keeps the migrated value when the write fails', () async {
      final storage = storeWith({kLegacyEnhancePirEnabledKey: 'true'});

      expect(
        await readEnhancePirEnabledPreference(
          storage,
          preferences: _FakeEnhancePirStore(writeThrows: true),
        ),
        isTrue,
      );
      expect(
        await storage.readPlain(kLegacyEnhancePirEnabledKey),
        'true',
        reason: 'a failed migration must stay retryable on the next launch',
      );
    });
  });
}

class _FakeEnhancePirStore implements EnhancePirPreferenceStore {
  _FakeEnhancePirStore({this.saved, this.writeThrows = false});

  bool? saved;
  final bool writeThrows;
  var writes = 0;

  @override
  Future<bool?> readEnabled() async => saved;

  @override
  Future<void> writeEnabled(bool enabled) async {
    writes++;
    if (writeThrows) throw StateError('write failed');
    saved = enabled;
  }
}

class _FailingEnhancePirStore implements EnhancePirPreferenceStore {
  var writes = 0;

  @override
  Future<bool?> readEnabled() async => throw StateError('read failed');

  @override
  Future<void> writeEnabled(bool enabled) async => writes++;
}

/// A secure store whose plaintext reads fail, e.g. a locked keychain.
class _UnreadableSecureStore extends AppSecureStore {
  _UnreadableSecureStore()
    : super.testing(storage: const FlutterSecureStorage());

  final deletes = <String>[];

  @override
  Future<String?> readPlain(String key) async =>
      throw StateError('keychain locked');

  @override
  Future<void> delete(String key) async => deletes.add(key);
}
