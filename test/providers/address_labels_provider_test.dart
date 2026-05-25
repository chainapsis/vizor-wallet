import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/address_labels_provider.dart';
import 'package:zcash_wallet/src/providers/hidden_memos_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemorySecureStorage storage;
  late AppSecureStore store;
  late ProviderContainer container;

  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [appSecureStoreProvider.overrideWithValue(store)],
  );

  setUp(() {
    storage = _InMemorySecureStorage();
    store = AppSecureStore.testing(storage: storage);
    container = makeContainer();
  });

  tearDown(() {
    container.dispose();
  });

  AddressLabelsNotifier notifier() =>
      container.read(addressLabelsProvider.notifier);

  // Lets build()'s fire-and-forget load() (and its async storage read) settle.
  Future<void> pumpAsync() => Future<void>.delayed(Duration.zero);

  test('setLabel stores label for account+address', () async {
    await notifier().setLabel(
      accountUuid: 'A',
      address: 'u1aaa',
      label: 'Donations',
    );
    final label =
        container.read(addressLabelsProvider).labelFor('A', 'u1aaa');
    expect(label, 'Donations');
  });

  test('setLabel with blank label removes the entry', () async {
    await notifier().setLabel(
      accountUuid: 'A',
      address: 'u1aaa',
      label: 'Donations',
    );
    await notifier().setLabel(
      accountUuid: 'A',
      address: 'u1aaa',
      label: '   ',
    );
    final label =
        container.read(addressLabelsProvider).labelFor('A', 'u1aaa');
    expect(label, isNull);
  });

  test('removeLabel removes the entry', () async {
    await notifier().setLabel(
      accountUuid: 'A',
      address: 'u1aaa',
      label: 'Donations',
    );
    await notifier().removeLabel(accountUuid: 'A', address: 'u1aaa');
    final label =
        container.read(addressLabelsProvider).labelFor('A', 'u1aaa');
    expect(label, isNull);
  });

  test('labels are per-account', () async {
    await notifier().setLabel(
      accountUuid: 'A',
      address: 'u1aaa',
      label: 'Donations',
    );
    final labelB =
        container.read(addressLabelsProvider).labelFor('B', 'u1aaa');
    expect(labelB, isNull);
  });

  test('persisted JSON round-trips to a second provider instance', () async {
    await notifier().setLabel(
      accountUuid: 'A',
      address: 'u1aaa',
      label: 'Donations',
    );

    final container2 = makeContainer();
    addTearDown(container2.dispose);

    await container2.read(addressLabelsProvider.notifier).load();
    final label = container2.read(addressLabelsProvider).labelFor('A', 'u1aaa');
    expect(label, 'Donations');
  });

  test(
    'self-initializes from storage without an explicit load() call',
    () async {
      // Pre-seed the fake storage directly with a label.
      await storage.write(
        key: kAddressLabelsKey,
        value: jsonEncode({
          'A': {'u1aaa': 'Mining Reward'},
        }),
      );

      // Fresh container; only watch the provider — never call load().
      final fresh = makeContainer();
      addTearDown(fresh.dispose);
      fresh.read(addressLabelsProvider);

      // Let build()'s Future.microtask(load) and its storage read settle.
      await pumpAsync();

      final label = fresh.read(addressLabelsProvider).labelFor('A', 'u1aaa');
      expect(label, 'Mining Reward');
    },
  );
}

/// Minimal in-memory [FlutterSecureStorage] fake backing the plain
/// read/write/delete paths exercised by [AppSecureStore.readPlain] /
/// [AppSecureStore.writePlain]. Mirrors the option-signature convention used
/// by the fakes in `test/core/storage/app_secure_store_test.dart`.
class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }
}
