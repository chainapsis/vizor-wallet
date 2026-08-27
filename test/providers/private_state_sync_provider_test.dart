import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/private_state_sync_provider.dart';

void main() {
  test('private sync defaults off and does not construct a remote store', () {
    final container = _container();
    addTearDown(container.dispose);

    expect(container.read(privateStateSyncRequestsAllowedProvider), isFalse);
    expect(container.read(privateStateRemoteStoreProvider), isNull);
  });

  test('persisted opt-in starts enabled and constructs a remote store', () {
    final container = _container(enabled: true);
    addTearDown(container.dispose);

    expect(container.read(privateStateSyncRequestsAllowedProvider), isTrue);
    expect(container.read(privateStateRemoteStoreProvider), isNotNull);
  });

  test('enabling permits requests only after persistence succeeds', () async {
    final store = _ControlledStore();
    final container = _container(store: store);
    addTearDown(container.dispose);

    final mutation = container
        .read(privateStateSyncSettingsProvider.notifier)
        .setEnabled(true);

    expect(
      container.read(privateStateSyncSettingsProvider).displayedEnabled,
      isTrue,
    );
    expect(container.read(privateStateSyncRequestsAllowedProvider), isFalse);
    expect(container.read(privateStateRemoteStoreProvider), isNull);

    await Future<void>.delayed(Duration.zero);
    store.completeNext();
    await mutation;

    expect(container.read(privateStateSyncRequestsAllowedProvider), isTrue);
    expect(container.read(privateStateRemoteStoreProvider), isNotNull);
  });

  test('disabling blocks new requests before persistence completes', () async {
    final store = _ControlledStore();
    final container = _container(enabled: true, store: store);
    addTearDown(container.dispose);

    expect(container.read(privateStateRemoteStoreProvider), isNotNull);
    final mutation = container
        .read(privateStateSyncSettingsProvider.notifier)
        .setEnabled(false);

    expect(container.read(privateStateSyncRequestsAllowedProvider), isFalse);
    expect(container.read(privateStateRemoteStoreProvider), isNull);

    await Future<void>.delayed(Duration.zero);
    store.completeNext();
    await mutation;
    expect(container.read(privateStateSyncSettingsProvider).enabled, isFalse);
  });

  test('failed persistence rolls back to the last persisted value', () async {
    final store = _ControlledStore();
    final container = _container(store: store);
    addTearDown(container.dispose);

    final mutation = container
        .read(privateStateSyncSettingsProvider.notifier)
        .setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    store.failNext(StateError('write failed'));

    await expectLater(mutation, throwsStateError);
    final state = container.read(privateStateSyncSettingsProvider);
    expect(state.enabled, isFalse);
    expect(state.displayedEnabled, isFalse);
    expect(state.error, isA<StateError>());
    expect(container.read(privateStateSyncRequestsAllowedProvider), isFalse);
  });

  test('failed off persistence remains fail-closed for the session', () async {
    final store = _ControlledStore();
    final container = _container(enabled: true, store: store);
    addTearDown(container.dispose);

    final mutation = container
        .read(privateStateSyncSettingsProvider.notifier)
        .setEnabled(false);
    await Future<void>.delayed(Duration.zero);
    store.failNext(StateError('write failed'));

    await expectLater(mutation, throwsStateError);
    final state = container.read(privateStateSyncSettingsProvider);
    expect(state.enabled, isTrue);
    expect(state.displayedEnabled, isFalse);
    expect(state.error, isA<StateError>());
    expect(container.read(privateStateSyncRequestsAllowedProvider), isFalse);
    expect(container.read(privateStateRemoteStoreProvider), isNull);
  });

  test('serialized mutations honor the latest requested value', () async {
    final store = _ControlledStore();
    final container = _container(store: store);
    addTearDown(container.dispose);
    final notifier = container.read(privateStateSyncSettingsProvider.notifier);

    final enable = notifier.setEnabled(true);
    final disable = notifier.setEnabled(false);
    expect(container.read(privateStateSyncRequestsAllowedProvider), isFalse);

    await Future<void>.delayed(Duration.zero);
    store.completeNext();
    await enable;
    expect(store.values, [true, false]);
    expect(container.read(privateStateSyncRequestsAllowedProvider), isFalse);

    store.completeNext();
    await disable;
    expect(store.values, [true, false]);
    expect(container.read(privateStateSyncSettingsProvider).enabled, isFalse);
  });
}

ProviderContainer _container({
  bool enabled = false,
  PrivateStateSyncSettingsStore? store,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState.empty.copyWithPrivateStateSync(enabled),
      ),
      if (store != null)
        privateStateSyncSettingsStoreProvider.overrideWithValue(store),
    ],
  );
}

extension on AppBootstrapState {
  AppBootstrapState copyWithPrivateStateSync(bool enabled) {
    return AppBootstrapState(
      initialLocation: initialLocation,
      initialAccountState: initialAccountState,
      initialSyncSnapshot: initialSyncSnapshot,
      network: network,
      rpcEndpointConfig: rpcEndpointConfig,
      themeMode: themeMode,
      privacyModeEnabled: privacyModeEnabled,
      isPasswordConfigured: isPasswordConfigured,
      isUnlocked: isUnlocked,
      passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
      privateStateSyncEnabled: enabled,
    );
  }
}

class _ControlledStore implements PrivateStateSyncSettingsStore {
  final values = <bool>[];
  final _pending = <Completer<void>>[];

  @override
  Future<void> writeEnabled(bool enabled) {
    values.add(enabled);
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext() => _pending.removeAt(0).complete();

  void failNext(Object error) => _pending.removeAt(0).completeError(error);
}
