// The secure-storage platform fake needs the platform-interface packages,
// which are transitive deps, hence the ignore (same as swap_screen_test).
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/core/config/fiat_currencies.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/fiat_currency_provider.dart';

/// Secure-storage fake whose reads block on [readGate] — lets a test hold
/// the initial hydration read open while the user selection races past it.
class _GatedSecureStoragePlatform extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  _GatedSecureStoragePlatform(Map<String, String> seed)
    : values = Map<String, String>.of(seed);

  final Map<String, String> values;
  final Completer<void> readGate = Completer<void>();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    await readGate.future;
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    await readGate.future;
    return values.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    await readGate.future;
    return Map<String, String>.of(values);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _GatedSecureStoragePlatform installPlatform(Map<String, String> seed) {
    final platform = _GatedSecureStoragePlatform(seed);
    final previous = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = platform;
    addTearDown(() => FlutterSecureStoragePlatform.instance = previous);
    return platform;
  }

  Future<void> settleMicrotasks() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('hydration applies the stored currency before any selection', () async {
    final platform = installPlatform({kFiatCurrencyKey: 'krw'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(fiatCurrencyProvider).code, 'usd');

    platform.readGate.complete();
    await settleMicrotasks();

    expect(container.read(fiatCurrencyProvider).code, 'krw');
  });

  test('a selection made before hydration completes is not overwritten by '
      'the stale stored value', () async {
    final platform = installPlatform({kFiatCurrencyKey: 'eur'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // build() kicks off the hydration read, which is still gated when the
    // user picks KRW.
    expect(container.read(fiatCurrencyProvider).code, 'usd');
    await container
        .read(fiatCurrencyProvider.notifier)
        .set(fiatCurrencyForCode('krw'));
    expect(container.read(fiatCurrencyProvider).code, 'krw');

    platform.readGate.complete();
    await settleMicrotasks();

    // The late 'eur' read must not clobber the newer selection for the
    // session, and storage holds the selection.
    expect(container.read(fiatCurrencyProvider).code, 'krw');
    expect(platform.values[kFiatCurrencyKey], 'krw');
  });
}
