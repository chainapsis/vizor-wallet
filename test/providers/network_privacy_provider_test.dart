import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';

void main() {
  test('preference read failure pauses native updates before launch', () async {
    final events = <String>[];
    try {
      await initializeNetworkPrivacyRuntime(
        store: _ThrowingReadStore(events),
        runtime: _FakeRuntime(events, NetworkPrivacyConnectionStatus.connected),
        nativeUpdates: _FakeNativeUpdateCoordinator(events),
      );

      expect(events, ['store:read', 'begin-enable', 'native:true']);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(networkPrivacyProvider).startupNotice,
        kTorStartupFailureNotice,
      );
      container.read(networkPrivacyProvider.notifier).clearStartupNotice();
      expect(container.read(networkPrivacyProvider).startupNotice, isNull);
    } finally {
      await initializeNetworkPrivacyRuntime(
        store: _FakeStore(<String>[]),
        runtime: _FakeRuntime(<String>[], NetworkPrivacyConnectionStatus.off),
        nativeUpdates: _FakeNativeUpdateCoordinator(<String>[]),
      );
    }
  });

  test('enabling quiesces direct traffic before persistence', () async {
    final events = <String>[];
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _FakeStore(events),
        ),
        networkPrivacyRuntimeProvider.overrideWithValue(
          _FakeRuntime(events, NetworkPrivacyConnectionStatus.connected),
        ),
        networkPrivacyNativeUpdateCoordinatorProvider.overrideWithValue(
          _FakeNativeUpdateCoordinator(events),
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

    expect(events, [
      'native:true',
      'begin-enable',
      'restart',
      'store:true',
      'configure:true',
    ]);
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
        networkPrivacyNativeUpdateCoordinatorProvider.overrideWithValue(
          _FakeNativeUpdateCoordinator(events),
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
    expect(events, [
      'native:true',
      'begin-enable',
      'restart',
      'store:true',
      'configure:true',
    ]);
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
        networkPrivacyNativeUpdateCoordinatorProvider.overrideWithValue(
          _FakeNativeUpdateCoordinator(events),
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

    expect(events, [
      'restart',
      'store:false',
      'configure:false',
      'native:false',
    ]);
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

  test(
    'failed transport quiescence never configures Tor as connected',
    () async {
      final events = <String>[];
      final container = ProviderContainer(
        overrides: [
          networkPrivacyPreferenceStoreProvider.overrideWithValue(
            _FakeStore(events),
          ),
          networkPrivacyRuntimeProvider.overrideWithValue(
            _FakeRuntime(events, NetworkPrivacyConnectionStatus.connected),
          ),
          networkPrivacyNativeUpdateCoordinatorProvider.overrideWithValue(
            _FakeNativeUpdateCoordinator(events),
          ),
          networkPrivacyTransportRestartProvider.overrideWithValue((_) async {
            events.add('restart');
            throw StateError('network tasks did not stop');
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(networkPrivacyProvider.notifier).setTorEnabled(true);

      expect(events, ['native:true', 'begin-enable', 'restart']);
      expect(
        container.read(networkPrivacyProvider),
        isA<NetworkPrivacyState>()
            .having((state) => state.torEnabled, 'torEnabled', isTrue)
            .having(
              (state) => state.status,
              'status',
              NetworkPrivacyConnectionStatus.failed,
            ),
      );
    },
  );

  test('active native update rejects Tor before route activation', () async {
    final events = <String>[];
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _FakeStore(events),
        ),
        networkPrivacyRuntimeProvider.overrideWithValue(
          _FakeRuntime(events, NetworkPrivacyConnectionStatus.connected),
        ),
        networkPrivacyNativeUpdateCoordinatorProvider.overrideWithValue(
          _RejectingNativeUpdateCoordinator(events),
        ),
        networkPrivacyTransportRestartProvider.overrideWithValue((_) async {
          events.add('restart');
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(networkPrivacyProvider.notifier).setTorEnabled(true);

    expect(events, ['native:true']);
    expect(
      container.read(networkPrivacyProvider),
      isA<NetworkPrivacyState>()
          .having((state) => state.torEnabled, 'torEnabled', isFalse)
          .having(
            (state) => state.status,
            'status',
            NetworkPrivacyConnectionStatus.off,
          )
          .having(
            (state) => state.startupNotice,
            'startupNotice',
            kTorUpdateInProgressNotice,
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

class _ThrowingReadStore implements NetworkPrivacyPreferenceStore {
  _ThrowingReadStore(this.events);

  final List<String> events;

  @override
  Future<bool> readTorEnabled() async {
    events.add('store:read');
    throw StateError('read failed');
  }

  @override
  Future<void> writeTorEnabled(bool enabled) async {
    throw UnimplementedError();
  }
}

class _FakeRuntime implements NetworkPrivacyRuntime {
  _FakeRuntime(this.events, this.result);

  final List<String> events;
  final NetworkPrivacyConnectionStatus result;

  @override
  void beginEnable() {
    events.add('begin-enable');
  }

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
  void beginEnable() {
    events.add('begin-enable');
  }

  @override
  Future<NetworkPrivacyConnectionStatus> configure({
    required bool enabled,
  }) async {
    events.add('configure:$enabled');
    throw StateError('bootstrap failed');
  }
}

class _FakeNativeUpdateCoordinator
    implements NetworkPrivacyNativeUpdateCoordinator {
  _FakeNativeUpdateCoordinator(this.events);

  final List<String> events;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    events.add('native:$enabled');
  }
}

class _RejectingNativeUpdateCoordinator
    implements NetworkPrivacyNativeUpdateCoordinator {
  _RejectingNativeUpdateCoordinator(this.events);

  final List<String> events;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    events.add('native:$enabled');
    throw StateError('update in progress');
  }
}
