import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';

void main() {
  test('enabling persists Tor intent before transport configuration', () async {
    final events = <String>[];
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _FakeStore(events),
        ),
        networkPrivacyRuntimeProvider.overrideWithValue(
          _FakeRuntime(events, NetworkPrivacyConnectionStatus.connected),
        ),
        networkPrivacyTransportRestartProvider.overrideWithValue((
          update,
        ) async {
          events.add('restart');
          await update();
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(networkPrivacyProvider.notifier).setTorEnabled(true);

    expect(events, ['store:true', 'restart', 'configure:true']);
    expect(
      container.read(networkPrivacyProvider).status,
      NetworkPrivacyConnectionStatus.connected,
    );
    expect(container.read(networkPrivacyProvider).torEnabled, isTrue);
  });

  test('Tor bootstrap failure remains enabled and fail-closed', () async {
    final events = <String>[];
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _FakeStore(events),
        ),
        networkPrivacyRuntimeProvider.overrideWithValue(
          _ThrowingRuntime(events),
        ),
        networkPrivacyTransportRestartProvider.overrideWithValue((
          update,
        ) async {
          events.add('restart');
          await update();
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(networkPrivacyProvider.notifier).setTorEnabled(true);

    final state = container.read(networkPrivacyProvider);
    expect(events, ['store:true', 'restart', 'configure:true']);
    expect(state.torEnabled, isTrue);
    expect(state.status, NetworkPrivacyConnectionStatus.failed);
    expect(state.error, contains('bootstrap failed'));
  });

  test('disabling persists direct intent and restarts transport', () async {
    final events = <String>[];
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _FakeStore(events),
        ),
        networkPrivacyRuntimeProvider.overrideWithValue(
          _FakeRuntime(events, NetworkPrivacyConnectionStatus.off),
        ),
        networkPrivacyTransportRestartProvider.overrideWithValue((
          update,
        ) async {
          events.add('restart');
          await update();
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(networkPrivacyProvider.notifier).setTorEnabled(false);

    expect(events, ['store:false', 'restart', 'configure:false']);
    expect(
      container.read(networkPrivacyProvider),
      isA<NetworkPrivacyState>()
          .having((state) => state.torEnabled, 'torEnabled', isFalse)
          .having(
            (state) => state.status,
            'status',
            NetworkPrivacyConnectionStatus.off,
          ),
    );
  });
}

class _FakeStore implements NetworkPrivacyPreferenceStore {
  _FakeStore(this.events);

  final List<String> events;

  @override
  Future<bool> readTorEnabled() async => false;

  @override
  Future<void> writeTorEnabled(bool enabled) async {
    events.add('store:$enabled');
  }
}

class _FakeRuntime implements NetworkPrivacyRuntime {
  _FakeRuntime(this.events, this.result);

  final List<String> events;
  final NetworkPrivacyConnectionStatus result;

  @override
  Future<NetworkPrivacyConnectionStatus> configure({
    required bool enabled,
  }) async {
    events.add('configure:$enabled');
    return result;
  }
}

class _ThrowingRuntime implements NetworkPrivacyRuntime {
  _ThrowingRuntime(this.events);

  final List<String> events;

  @override
  Future<NetworkPrivacyConnectionStatus> configure({
    required bool enabled,
  }) async {
    events.add('configure:$enabled');
    throw StateError('bootstrap failed');
  }
}
