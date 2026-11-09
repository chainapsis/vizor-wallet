import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/core/naming/zns_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/zns_names_setting.dart';
import 'package:zcash_wallet/src/core/naming/zns_recipient_lookup.dart';
import '../../support/test_l10n.dart';

class _MemoryStore implements ZnsNamesSettingStore {
  _MemoryStore({this.enabled = false, this.failWrites = false});

  bool enabled;
  bool failWrites;
  final writes = <bool>[];

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async {
    writes.add(value);
    if (failWrites) throw StateError('disk full');
    enabled = value;
  }
}

class _ThrowingReadStore extends _MemoryStore {
  @override
  Future<bool> readEnabled() => Future.error(StateError('corrupt'));
}

ProviderContainer _container(ZnsNamesSettingStore store) {
  final container = ProviderContainer(
    overrides: [znsNamesSettingStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SharedPreferencesZnsNamesSettingStore', () {
    test('names are off until the user turns them on', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SharedPreferencesZnsNamesSettingStore();

      expect(await store.readEnabled(), isFalse);
      await store.writeEnabled(true);
      expect(await store.readEnabled(), isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(kZnsNamesEnabledStorageKey), isTrue);
    });
  });

  group('znsNamesEnabledProvider', () {
    test('loads the stored setting and saves a change', () async {
      final store = _MemoryStore();
      final container = _container(store);

      expect(await container.read(znsNamesEnabledProvider.future), isFalse);
      expect(container.read(znsNamesOnProvider), isFalse);

      await container.read(znsNamesEnabledProvider.notifier).setEnabled(true);

      expect(store.enabled, isTrue);
      expect(container.read(znsNamesOnProvider), isTrue);
    });

    test('a failed save leaves names as they were', () async {
      final store = _MemoryStore(failWrites: true);
      final container = _container(store);
      await container.read(znsNamesEnabledProvider.future);

      await expectLater(
        container.read(znsNamesEnabledProvider.notifier).setEnabled(true),
        throwsStateError,
      );

      expect(container.read(znsNamesOnProvider), isFalse);
    });

    test('an unreadable setting reads as off', () async {
      final container = _container(_ThrowingReadStore());

      expect(await container.read(znsNamesEnabledProvider.future), isFalse);
    });

    test('names are off while the setting loads', () {
      final container = _container(_MemoryStore(enabled: true));

      expect(container.read(znsNamesOnProvider), isFalse);
    });
  });

  group('names off', () {
    test('the resolver provider gives the off resolver', () async {
      final container = _container(_MemoryStore());
      await container.read(znsNamesEnabledProvider.future);

      expect(container.read(znsNameResolverProvider), kZnsNamesOffResolver);
    });

    test('a lookup says where to turn names on, with no request', () async {
      final lookup = await lookUpZnsRecipient(kZnsNamesOffResolver, 'alice');

      expect(
        lookup,
        isA<ZnsRecipientMissing>().having(
          (missing) => missing.status,
          'status',
          ZnsLookupStatus.namesOff,
        ),
      );
      expect(ZnsLookupStatus.namesOff.isError, isTrue);
      expect(ZnsLookupStatus.namesOff.addressType, 'invalid');
      expect(
        ZnsLookupStatus.namesOff.localizedMessage(testL10n),
        'Turn on Zcash names in Settings',
      );
    });
  });
}
