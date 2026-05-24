import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
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

  HiddenMemosNotifier notifier() =>
      container.read(hiddenMemosProvider.notifier);

  // Lets build()'s fire-and-forget load() (and its async storage read) settle.
  Future<void> pumpAsync() => Future<void>.delayed(Duration.zero);

  test('hide adds key for account', () async {
    await notifier().hide(accountUuid: 'A', key: 'tx:2:0');
    final keys = container.read(hiddenMemosProvider).keysFor('A');
    expect(keys, contains('tx:2:0'));
  });

  test('restore removes key for account', () async {
    await notifier().hide(accountUuid: 'A', key: 'tx:2:0');
    await notifier().restore(accountUuid: 'A', key: 'tx:2:0');
    final keys = container.read(hiddenMemosProvider).keysFor('A');
    expect(keys, isNot(contains('tx:2:0')));
  });

  test('keys are per-account', () async {
    await notifier().hide(accountUuid: 'A', key: 'tx:2:0');
    final keysB = container.read(hiddenMemosProvider).keysFor('B');
    expect(keysB, isEmpty);
  });

  test('persisted JSON round-trips to a second provider instance', () async {
    await notifier().hide(accountUuid: 'A', key: 'tx:2:0');

    final container2 = makeContainer();
    addTearDown(container2.dispose);

    await container2.read(hiddenMemosProvider.notifier).load();
    final keys = container2.read(hiddenMemosProvider).keysFor('A');
    expect(keys, contains('tx:2:0'));
  });

  test(
    'self-initializes from storage without an explicit load() call',
    () async {
      // Pre-seed the fake storage directly with a hidden key.
      await storage.write(
        key: kHiddenMemosKey,
        value: jsonEncode({
          'A': ['tx:9:1'],
        }),
      );

      // Fresh container; only watch the provider — never call load().
      final fresh = makeContainer();
      addTearDown(fresh.dispose);
      fresh.read(hiddenMemosProvider);

      // Let build()'s Future.microtask(load) and its storage read settle.
      await pumpAsync();

      final keys = fresh.read(hiddenMemosProvider).keysFor('A');
      expect(keys, contains('tx:9:1'));
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
