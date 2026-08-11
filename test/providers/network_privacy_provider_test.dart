import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/rust/network_privacy.dart' as rust_types;

void main() {
  // The launch this owner exists for reads almost nothing: a locked app routes
  // to `/unlock`, `syncKeepAwakeActiveProvider` returns early on
  // `requiresUnlock` before it reaches `syncProvider`, and the unlock screens
  // only read that provider when the user submits. Nothing here builds a
  // provider at all, which is the point — the persisted route is applied
  // regardless of the lock, so the intent has to have an owner regardless too.
  group('Tor dormancy lifecycle', () {
    tearDown(disposeTorDormancyLifecycle);

    testWidgets('sleeps only where backgrounding stops the process', (
      tester,
    ) async {
      // Lane-dependent on purpose, and the desktop half is the load-bearing
      // one: a desktop app with every window hidden keeps polling, and a
      // client put to sleep underneath it pays a circuit build on each poll.
      for (final (formFactor, expected) in [
        (AppFormFactor.mobile, [true]),
        (AppFormFactor.desktop, <bool>[]),
      ]) {
        final dormancy = <bool>[];
        startTorDormancyLifecycle(
          setTorDormant: ({required dormant}) => dormancy.add(dormant),
          formFactor: formFactor,
        );

        await _sendAppLifecycleState(AppLifecycleState.inactive);
        await _sendAppLifecycleState(AppLifecycleState.hidden);

        expect(dormancy, expected, reason: '$formFactor');
      }
    });

    testWidgets('wakes on every foreground entry', (tester) async {
      // Asked for unconditionally: a sleep request that outlived its asker —
      // issued before Tor finished bootstrapping, so it lands on the client
      // only once that client exists — would otherwise keep the client asleep
      // for the whole foreground session.
      final dormancy = <bool>[];
      startTorDormancyLifecycle(
        setTorDormant: ({required dormant}) => dormancy.add(dormant),
      );

      await _sendAppLifecycleState(AppLifecycleState.inactive);
      await _sendAppLifecycleState(AppLifecycleState.resumed);

      expect(dormancy, contains(false));
    });
  });


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

  test('enabling keeps the Tor directory out of device backups', () async {
    final excluded = <String>[];
    final runtime = RustNetworkPrivacyRuntime(
      resolveTorDirectory: () async => '/tmp/vizor-tor',
      configureRuntime: ({required enabled, required torDirectory}) async =>
          rust_types.NetworkPrivacyStatus.ready,
      excludeTorDirectoryFromBackup: (directory) async =>
          excluded.add(directory),
    );

    await runtime.configure(enabled: true);

    // Once before the bootstrap, because the directory holds guard state from
    // its first moment and the process can be killed during it, and once after,
    // because the mark is best-effort.
    expect(excluded, ['/tmp/vizor-tor', '/tmp/vizor-tor']);
  });

  test('a failed bootstrap still excludes the Tor directory', () async {
    // Rust creates the directory and Arti writes guard state into it before
    // the bootstrap can fail, so the failure path leaves exactly the state the
    // exclusion exists to keep off a second device.
    final excluded = <String>[];
    final runtime = RustNetworkPrivacyRuntime(
      resolveTorDirectory: () async => '/tmp/vizor-tor',
      configureRuntime: ({required enabled, required torDirectory}) async =>
          throw StateError('bootstrap failed'),
      excludeTorDirectoryFromBackup: (directory) async =>
          excluded.add(directory),
    );

    await expectLater(
      runtime.configure(enabled: true),
      throwsA(isA<StateError>()),
    );

    expect(excluded, ['/tmp/vizor-tor', '/tmp/vizor-tor']);
  });

  test('a backup exclusion failure is reported', () async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previousDebugPrint);
    final runtime = RustNetworkPrivacyRuntime(
      resolveTorDirectory: () async => '/tmp/vizor-tor',
      configureRuntime: ({required enabled, required torDirectory}) async =>
          rust_types.NetworkPrivacyStatus.ready,
      excludeTorDirectoryFromBackup: (_) async =>
          throw StateError('attribute write refused'),
    );

    await runtime.configure(enabled: true);

    expect(logs, hasLength(2));
    expect(logs.first, contains('attribute write refused'));
  });

  test('a backup exclusion failure does not fail the route', () async {
    final runtime = RustNetworkPrivacyRuntime(
      resolveTorDirectory: () async => '/tmp/vizor-tor',
      configureRuntime: ({required enabled, required torDirectory}) async =>
          rust_types.NetworkPrivacyStatus.ready,
      excludeTorDirectoryFromBackup: (_) async =>
          throw StateError('no native side'),
    );

    expect(
      await runtime.configure(enabled: true),
      NetworkPrivacyConnectionStatus.connected,
    );
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
      'store:true',
      'begin-enable',
      'runtime-quiesce',
      'direct-quiesce',
      'restart',
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
      'store:true',
      'begin-enable',
      'runtime-quiesce',
      'direct-quiesce',
      'restart',
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
      'native-prepare-disable',
      'restart',
      'configure:false',
      'store:false',
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

  test('disabling waits for the native Tor update cycle to drain', () async {
    final events = <String>[];
    final nativeUpdates = _DeferredDisableNativeUpdateCoordinator(events);
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _FakeStore(events),
        ),
        networkPrivacyRuntimeProvider.overrideWithValue(
          _FakeRuntime(events, NetworkPrivacyConnectionStatus.connected),
        ),
        networkPrivacyNativeUpdateCoordinatorProvider.overrideWithValue(
          nativeUpdates,
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

    final disabling = container
        .read(networkPrivacyProvider.notifier)
        .setTorEnabled(false);
    await Future<void>.delayed(Duration.zero);

    expect(events, ['native-prepare-disable']);
    expect(
      container.read(networkPrivacyProvider),
      isA<NetworkPrivacyState>()
          .having((state) => state.torEnabled, 'torEnabled', isTrue)
          .having(
            (state) => state.status,
            'status',
            NetworkPrivacyConnectionStatus.connecting,
          )
          .having(
            (state) => state.targetTorEnabled,
            'targetTorEnabled',
            isFalse,
          ),
    );

    nativeUpdates.completeDrain();
    await disabling;

    expect(events, [
      'native-prepare-disable',
      'native-disable-drained',
      'restart',
      'configure:false',
      'store:false',
      'direct-allow',
      'native:false',
    ]);
  });

  test('failed native disable preflight preserves the Tor route', () async {
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
          _RejectingDisableNativeUpdateCoordinator(events),
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

    expect(events, ['native-prepare-disable']);
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
            kTorDisableUpdateInProgressNotice,
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
        'store:true',
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

    expect(events, [
      'native-prepare-disable',
      'restart',
      'configure:false',
      'native-resume',
    ]);
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
    expect(events, [
      'native-prepare-disable',
      'restart',
      'configure:false',
      'native-resume',
    ]);
  });

  test('the saved route may be stricter than the runtime, never laxer', () {
    // A wake that declares Tor and cannot afford it defers; a wake that
    // declares direct against a session enforcing Tor puts wallet queries and
    // signed transactions on a direct connection.
    expect(
      networkPrivacyPersistedRouteIsSafe(
        persistedTorEnabled: true,
        runtimeTorDesired: true,
      ),
      isTrue,
    );
    expect(
      networkPrivacyPersistedRouteIsSafe(
        persistedTorEnabled: false,
        runtimeTorDesired: false,
      ),
      isTrue,
    );
    expect(
      networkPrivacyPersistedRouteIsSafe(
        persistedTorEnabled: true,
        runtimeTorDesired: false,
      ),
      isTrue,
    );
    expect(
      networkPrivacyPersistedRouteIsSafe(
        persistedTorEnabled: false,
        runtimeTorDesired: true,
      ),
      isFalse,
    );
  });

  test('a failed strict save aborts the enable before anything changes', () async {
    final events = <String>[];
    final runtime = _FakeRuntime(
      events,
      NetworkPrivacyConnectionStatus.connected,
    );
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _WriteFailingStore(events, failOn: true),
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

    // Refused before the process changes: no fail-closed switch, no drain, no
    // transport restart. Requests keep flowing directly, the saved route
    // still says direct, and the updater preflight is undone — the toggle
    // simply never happened, apart from the failure the user is shown.
    expect(events, ['native:true', 'store:write-failed', 'native:false']);
    expect(runtime.isTorEnabled(), isFalse);
    final state = container.read(networkPrivacyProvider);
    expect(state.torEnabled, isFalse);
    expect(state.status, NetworkPrivacyConnectionStatus.failed);
    expect(state.targetTorEnabled, isTrue);
  });

  test('a failed direct save still opens the direct request gate', () async {
    final events = <String>[];
    final runtime = _FakeRuntime(
      events,
      NetworkPrivacyConnectionStatus.connected,
    );
    final container = ProviderContainer(
      overrides: [
        networkPrivacyPreferenceStoreProvider.overrideWithValue(
          _WriteFailingStore(events, failOn: false),
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

    // The runtime is direct with its Tor client dropped, so the gate follows
    // it: left shut, every direct request would fail for the rest of the
    // session behind a UI that reports Tor off. The saved route stays at Tor
    // — the stricter half — so the next launch comes back on Tor instead of
    // silently staying direct.
    expect(events, [
      'native-prepare-disable',
      'restart',
      'configure:false',
      'store:write-failed',
      'direct-allow',
    ]);
    expect(runtime.isTorEnabled(), isFalse);
    final state = container.read(networkPrivacyProvider);
    expect(state.torEnabled, isFalse);
    expect(state.status, NetworkPrivacyConnectionStatus.failed);
    expect(state.targetTorEnabled, isFalse);
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

  test('a user toggle stops the startup activation mid-flight', () async {
    final events = <String>[];
    final nativeUpdates = _DeferredEnableNativeUpdateCoordinator(events);
    final runtime = _PendingBootstrapRuntime(events);
    try {
      await initializeNetworkPrivacyRuntime(
        store: _EnabledStore(events),
        runtime: runtime,
        nativeUpdates: nativeUpdates,
        directRequests: _FakeDirectRequestGate(events),
      ).timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

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
          networkPrivacyTransportRestartProvider.overrideWithValue(
            (update) async => update(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(networkPrivacyProvider.notifier).setTorEnabled(false);
      events.clear();

      // The activation was parked inside its native-updater call; releasing it
      // must not push Tor routing onto a runtime the user moved to Direct.
      nativeUpdates.completeEnable();
      runtime.completeBootstrap(NetworkPrivacyConnectionStatus.connected);
      await Future<void>.delayed(Duration.zero);

      expect(runtime.configuredEnable, isFalse);
      expect(events, isNot(contains('native-resume')));
      expect(
        container.read(networkPrivacyProvider).status,
        NetworkPrivacyConnectionStatus.off,
      );
    } finally {
      nativeUpdates.completeEnable();
      runtime.completeBootstrap(NetworkPrivacyConnectionStatus.connected);
      await initializeNetworkPrivacyRuntime(
        store: _FakeStore(<String>[]),
        runtime: _FakeRuntime(<String>[], NetworkPrivacyConnectionStatus.off),
        nativeUpdates: _FakeNativeUpdateCoordinator(<String>[]),
        directRequests: _FakeDirectRequestGate(<String>[]),
      );
    }
  });

  test('a wallet reset publishes the direct route it applied', () async {
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
        networkPrivacyTransportRestartProvider.overrideWithValue(
          (update) async => update(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(networkPrivacyProvider.notifier).setTorEnabled(true);
    expect(container.read(networkPrivacyProvider).torEnabled, isTrue);

    container.read(networkPrivacyProvider.notifier).markRouteDirectAfterReset();

    final state = container.read(networkPrivacyProvider);
    expect(state.torEnabled, isFalse);
    expect(state.status, NetworkPrivacyConnectionStatus.off);
  });

  test('startup does not wait for Tor to bootstrap', () async {
    final events = <String>[];
    final runtime = _PendingBootstrapRuntime(events);
    try {
      await initializeNetworkPrivacyRuntime(
        store: _EnabledStore(events),
        runtime: runtime,
        nativeUpdates: _FakeNativeUpdateCoordinator(events),
        directRequests: _FakeDirectRequestGate(events),
      ).timeout(const Duration(seconds: 1));

      // Fail-closed routing is installed, and the bootstrap has been started
      // without the app having to wait for it.
      expect(events, contains('begin-enable'));
      await Future<void>.delayed(Duration.zero);
      expect(runtime.configureStarted, isTrue);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(networkPrivacyProvider),
        isA<NetworkPrivacyState>()
            .having((state) => state.torEnabled, 'torEnabled', isTrue)
            .having(
              (state) => state.status,
              'status',
              NetworkPrivacyConnectionStatus.connecting,
            ),
      );

      runtime.completeBootstrap(NetworkPrivacyConnectionStatus.connected);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(networkPrivacyProvider).status,
        NetworkPrivacyConnectionStatus.connected,
      );
    } finally {
      runtime.completeBootstrap(NetworkPrivacyConnectionStatus.connected);
      await initializeNetworkPrivacyRuntime(
        store: _FakeStore(<String>[]),
        runtime: _FakeRuntime(<String>[], NetworkPrivacyConnectionStatus.off),
        nativeUpdates: _FakeNativeUpdateCoordinator(<String>[]),
        directRequests: _FakeDirectRequestGate(<String>[]),
      );
    }
  });

  test('a user toggle during startup bootstrap wins', () async {
    final events = <String>[];
    final runtime = _PendingBootstrapRuntime(events);
    try {
      await initializeNetworkPrivacyRuntime(
        store: _EnabledStore(events),
        runtime: runtime,
        nativeUpdates: _FakeNativeUpdateCoordinator(events),
        directRequests: _FakeDirectRequestGate(events),
      ).timeout(const Duration(seconds: 1));

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
          ) async => update(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(networkPrivacyProvider).status,
        NetworkPrivacyConnectionStatus.connecting,
      );

      await container.read(networkPrivacyProvider.notifier).setTorEnabled(false);
      expect(
        container.read(networkPrivacyProvider).status,
        NetworkPrivacyConnectionStatus.off,
      );

      // The superseded startup bootstrap must not publish over the user's
      // choice when it finally resolves.
      runtime.completeBootstrap(NetworkPrivacyConnectionStatus.connected);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(networkPrivacyProvider).status,
        NetworkPrivacyConnectionStatus.off,
      );
      // Nor may it leave the native updaters routed for a Tor session the
      // user has turned off.
      expect(events, isNot(contains('native-resume')));
    } finally {
      runtime.completeBootstrap(NetworkPrivacyConnectionStatus.connected);
      await initializeNetworkPrivacyRuntime(
        store: _FakeStore(<String>[]),
        runtime: _FakeRuntime(<String>[], NetworkPrivacyConnectionStatus.off),
        nativeUpdates: _FakeNativeUpdateCoordinator(<String>[]),
        directRequests: _FakeDirectRequestGate(<String>[]),
      );
    }
  });
}

class _EnabledStore implements NetworkPrivacyPreferenceStore {
  _EnabledStore(this.events);

  final List<String> events;

  @override
  Future<bool> readTorEnabled() async => true;

  @override
  Future<void> writeTorEnabled(bool enabled) async {
    events.add('store:$enabled');
  }
}

/// Stands in for an Arti bootstrap that has not finished — the state a user on
/// a Tor-blocked network stays in indefinitely.
class _PendingBootstrapRuntime implements NetworkPrivacyRuntime {
  _PendingBootstrapRuntime(this.events);

  final List<String> events;
  final _bootstrap = Completer<NetworkPrivacyConnectionStatus>();
  var configureStarted = false;
  var configuredEnable = false;
  var _torEnabled = false;

  void completeBootstrap(NetworkPrivacyConnectionStatus status) {
    if (_bootstrap.isCompleted) return;
    _bootstrap.complete(status);
  }

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
    if (!enabled) {
      _torEnabled = false;
      return NetworkPrivacyConnectionStatus.off;
    }
    configureStarted = true;
    configuredEnable = true;
    return _bootstrap.future;
  }
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

/// Fails the write in one direction only, the shape a full disk has: the
/// previously saved value is already on disk when the new one is refused.
class _WriteFailingStore implements NetworkPrivacyPreferenceStore {
  _WriteFailingStore(this.events, {required this.failOn});

  final List<String> events;
  final bool failOn;

  @override
  Future<bool> readTorEnabled() async => false;

  @override
  Future<void> writeTorEnabled(bool enabled) async {
    if (enabled == failOn) {
      events.add('store:write-failed');
      throw StateError('Could not save the Tor preference.');
    }
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

/// Parks inside the enable call so a test can toggle the route while the
/// startup activation is still mid-flight.
class _DeferredEnableNativeUpdateCoordinator
    implements NetworkPrivacyNativeUpdateCoordinator {
  _DeferredEnableNativeUpdateCoordinator(this.events);

  final List<String> events;
  final _enable = Completer<void>();

  void completeEnable() {
    if (_enable.isCompleted) return;
    _enable.complete();
  }

  @override
  Future<void> prepareForTorDisable() async {
    events.add('native-prepare-disable');
  }

  @override
  Future<void> setTorEnabled(bool enabled) async {
    events.add('native:$enabled');
    if (enabled) await _enable.future;
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

class _FakeNativeUpdateCoordinator
    implements NetworkPrivacyNativeUpdateCoordinator {
  _FakeNativeUpdateCoordinator(this.events);

  final List<String> events;

  @override
  Future<void> prepareForTorDisable() async {
    events.add('native-prepare-disable');
  }

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
  Future<void> prepareForTorDisable() async {
    events.add('native-prepare-disable');
  }

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

class _DeferredDisableNativeUpdateCoordinator
    extends _FakeNativeUpdateCoordinator {
  _DeferredDisableNativeUpdateCoordinator(super.events);

  final _drain = Completer<void>();

  void completeDrain() => _drain.complete();

  @override
  Future<void> prepareForTorDisable() async {
    events.add('native-prepare-disable');
    await _drain.future;
    events.add('native-disable-drained');
  }
}

class _RejectingDisableNativeUpdateCoordinator
    extends _FakeNativeUpdateCoordinator {
  _RejectingDisableNativeUpdateCoordinator(super.events);

  @override
  Future<void> prepareForTorDisable() async {
    events.add('native-prepare-disable');
    throw StateError('update in progress');
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

Future<void> _sendAppLifecycleState(AppLifecycleState state) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(state.toString()),
        (_) {},
      );
}
