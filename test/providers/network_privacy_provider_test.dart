import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/rust/network_privacy.dart' as rust_types;

void main() {
  test('preference read failure pauses native updates before launch', () async {
    final events = <String>[];
    try {
      await initializeNetworkPrivacyRuntime(
        store: _ThrowingReadStore(events),
        runtime: _FakeRuntime(events, NetworkPrivacyConnectionStatus.connected),
        nativeUpdates: _FakeNativeUpdateCoordinator(events),
        directRequests: _FakeDirectRequestGate(events),
      );

      expect(events, [
        'store:read',
        'native:force-pause',
        'begin-enable',
        'runtime-quiesce',
        'direct-quiesce',
      ]);
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
        directRequests: _FakeDirectRequestGate(<String>[]),
      );
    }
  });

  test('direct runtime configuration skips Tor directory lookup', () async {
    var directoryLookups = 0;
    String? configuredDirectory;
    final runtime = RustNetworkPrivacyRuntime(
      resolveTorDirectory: () async {
        directoryLookups++;
        throw StateError('application support unavailable');
      },
      configureRuntime: ({required enabled, required torDirectory}) async {
        configuredDirectory = torDirectory;
        return rust_types.NetworkPrivacyStatus.direct;
      },
    );

    final status = await runtime.configure(enabled: false);

    expect(status, NetworkPrivacyConnectionStatus.off);
    expect(directoryLookups, 0);
    expect(configuredDirectory, isEmpty);
  });

  test(
    'preference failure waits for an active native update to quiesce',
    () async {
      final events = <String>[];
      final nativeUpdates = _DeferredPauseNativeUpdateCoordinator(events);
      try {
        final initialization = initializeNetworkPrivacyRuntime(
          store: _ThrowingReadStore(events),
          runtime: _FakeRuntime(
            events,
            NetworkPrivacyConnectionStatus.connected,
          ),
          nativeUpdates: nativeUpdates,
          directRequests: _FakeDirectRequestGate(events),
        );
        await Future<void>.delayed(Duration.zero);

        expect(events, ['store:read', 'native:force-pause']);

        nativeUpdates.completePause();
        await initialization;
        expect(events, [
          'store:read',
          'native:force-pause',
          'native:paused',
          'begin-enable',
          'runtime-quiesce',
          'direct-quiesce',
        ]);
      } finally {
        await initializeNetworkPrivacyRuntime(
          store: _FakeStore(<String>[]),
          runtime: _FakeRuntime(<String>[], NetworkPrivacyConnectionStatus.off),
          nativeUpdates: _FakeNativeUpdateCoordinator(<String>[]),
          directRequests: _FakeDirectRequestGate(<String>[]),
        );
      }
    },
  );

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
        networkPrivacyDirectRequestGateProvider.overrideWithValue(
          _FakeDirectRequestGate(events),
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
      'runtime-quiesce',
      'direct-quiesce',
      'restart',
      'store:true',
      'configure:true',
      'native-resume',
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
        networkPrivacyDirectRequestGateProvider.overrideWithValue(
          _FakeDirectRequestGate(events),
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
      'runtime-quiesce',
      'direct-quiesce',
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
        networkPrivacyDirectRequestGateProvider.overrideWithValue(
          _FakeDirectRequestGate(events),
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
      'direct-allow',
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
          networkPrivacyDirectRequestGateProvider.overrideWithValue(
            _FakeDirectRequestGate(events),
          ),
          networkPrivacyTransportRestartProvider.overrideWithValue((_) async {
            events.add('restart');
            throw StateError('network tasks did not stop');
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(networkPrivacyProvider.notifier).setTorEnabled(true);

      expect(events, [
        'native:true',
        'begin-enable',
        'runtime-quiesce',
        'direct-quiesce',
        'restart',
      ]);
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
        networkPrivacyDirectRequestGateProvider.overrideWithValue(
          _FakeDirectRequestGate(events),
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

  test('failed Tor disable preserves the effective Tor route', () async {
    final events = <String>[];
    final runtime = _FakeRuntime(
      events,
      NetworkPrivacyConnectionStatus.connected,
      throwOnDisable: true,
    );
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _FakeStore(events),
        ),
        networkPrivacyRuntimeProvider.overrideWithValue(runtime),
        networkPrivacyNativeUpdateCoordinatorProvider.overrideWithValue(
          _FakeNativeUpdateCoordinator(events),
        ),
        networkPrivacyDirectRequestGateProvider.overrideWithValue(
          _FakeDirectRequestGate(events),
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
    events.clear();
    await container.read(networkPrivacyProvider.notifier).setTorEnabled(false);

    expect(events, ['restart', 'store:false', 'configure:false']);
    expect(
      container.read(networkPrivacyProvider),
      isA<NetworkPrivacyState>()
          .having((state) => state.torEnabled, 'torEnabled', isTrue)
          .having(
            (state) => state.targetTorEnabled,
            'targetTorEnabled',
            isFalse,
          )
          .having(
            (state) => state.status,
            'status',
            NetworkPrivacyConnectionStatus.failed,
          ),
    );

    events.clear();
    await container.read(networkPrivacyProvider.notifier).retry();
    expect(events, ['restart', 'store:false', 'configure:false']);
  });

  test(
    'native updater recovery failure keeps the direct route truthful',
    () async {
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
            _DisableFailingNativeUpdateCoordinator(events),
          ),
          networkPrivacyDirectRequestGateProvider.overrideWithValue(
            _FakeDirectRequestGate(events),
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

      await container
          .read(networkPrivacyProvider.notifier)
          .setTorEnabled(false);

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
              (state) => state.softwareUpdatesAvailable,
              'softwareUpdatesAvailable',
              isFalse,
            )
            .having(
              (state) => state.startupNotice,
              'startupNotice',
              kSoftwareUpdateUnavailableNotice,
            ),
      );
    },
  );

  test(
    'updater resume failure keeps Tor connected and shows a notice',
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
            _ResumeFailingNativeUpdateCoordinator(events),
          ),
          networkPrivacyDirectRequestGateProvider.overrideWithValue(
            _FakeDirectRequestGate(events),
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

      expect(
        container.read(networkPrivacyProvider),
        isA<NetworkPrivacyState>()
            .having((state) => state.torEnabled, 'torEnabled', isTrue)
            .having(
              (state) => state.status,
              'status',
              NetworkPrivacyConnectionStatus.connected,
            )
            .having(
              (state) => state.startupNotice,
              'startupNotice',
              kTorUpdateUnavailableNotice,
            )
            .having(
              (state) => state.softwareUpdatesAvailable,
              'softwareUpdatesAvailable',
              isFalse,
            ),
      );

      await container
          .read(networkPrivacyProvider.notifier)
          .retrySoftwareUpdates();
      expect(
        container.read(networkPrivacyProvider).softwareUpdatesAvailable,
        isTrue,
      );
    },
  );
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
  _FakeRuntime(this.events, this.result, {this.throwOnDisable = false});

  final List<String> events;
  final NetworkPrivacyConnectionStatus result;
  final bool throwOnDisable;
  var _torEnabled = false;

  @override
  void beginEnable() {
    _torEnabled = true;
    events.add('begin-enable');
  }

  @override
  bool isTorEnabled() => _torEnabled;

  @override
  Future<void> quiesceDirectRequests() async {
    events.add('runtime-quiesce');
  }

  @override
  Future<NetworkPrivacyConnectionStatus> configure({
    required bool enabled,
  }) async {
    events.add('configure:$enabled');
    if (!enabled && throwOnDisable) {
      throw StateError('direct switch failed');
    }
    _torEnabled = enabled;
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
  bool isTorEnabled() => true;

  @override
  Future<void> quiesceDirectRequests() async {
    events.add('runtime-quiesce');
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

  @override
  Future<void> pauseForFailClosedStartup() async {
    events.add('native:force-pause');
  }

  @override
  Future<void> resumeTorUpdates() async {
    events.add('native-resume');
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

  @override
  Future<void> pauseForFailClosedStartup() async {
    events.add('native:force-pause');
  }

  @override
  Future<void> resumeTorUpdates() async {
    throw UnimplementedError();
  }
}

class _DeferredPauseNativeUpdateCoordinator
    extends _FakeNativeUpdateCoordinator {
  _DeferredPauseNativeUpdateCoordinator(super.events);

  final _pause = Completer<void>();

  void completePause() => _pause.complete();

  @override
  Future<void> pauseForFailClosedStartup() async {
    events.add('native:force-pause');
    await _pause.future;
    events.add('native:paused');
  }
}

class _ResumeFailingNativeUpdateCoordinator
    extends _FakeNativeUpdateCoordinator {
  _ResumeFailingNativeUpdateCoordinator(super.events);

  var attempts = 0;

  @override
  Future<void> resumeTorUpdates() async {
    events.add('native-resume');
    attempts++;
    if (attempts == 1) throw StateError('updater proxy failed');
  }
}

class _DisableFailingNativeUpdateCoordinator
    extends _FakeNativeUpdateCoordinator {
  _DisableFailingNativeUpdateCoordinator(super.events);

  @override
  Future<void> setTorEnabled(bool enabled) async {
    events.add('native:$enabled');
    if (!enabled) throw StateError('native updater route failed');
  }
}

class _FakeDirectRequestGate implements NetworkPrivacyDirectRequestGate {
  _FakeDirectRequestGate(this.events);

  final List<String> events;

  @override
  void allow() {
    events.add('direct-allow');
  }

  @override
  Future<void> quiesce() async {
    events.add('direct-quiesce');
  }
}
