import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
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
    expect(merged.isHardware, isTrue);
    expect(merged.isSeedAnchor, isTrue);
    expect(merged.profilePictureId, 'pfp-04');
    expect(merged.walletLinkSourceAccountUuid, 'desktop-account-1');
  });

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

  test(
    'empty bootstrap starts with sync keep-awake disabled and unprompted',
    () {
      expect(AppBootstrapState.empty.syncKeepAwakeEnabled, isFalse);
      expect(AppBootstrapState.empty.syncKeepAwakePromptSeen, isFalse);
    },
  );

  group('private Ironwood recovery preference', () {
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

    test('degrades to off when the preference store fails', () async {
      final storage = storeWith({kLegacyEnhancePirEnabledKey: 'true'});

      expect(
        await readEnhancePirEnabledPreference(
          storage,
          preferences: _FailingEnhancePirStore(),
        ),
        isFalse,
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
  @override
  Future<bool?> readEnabled() async => throw StateError('read failed');

  @override
  Future<void> writeEnabled(bool enabled) async {}
}
