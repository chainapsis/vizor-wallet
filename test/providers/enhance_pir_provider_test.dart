import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

class _Api extends RustLibApi {
  final values = <bool>[];
  bool running = false;
  int cancellations = 0;
  int statusReads = 0;
  Completer<EnhanceRecoveryStatus>? statusResponse;
  @override
  bool crateApiSyncIsSyncRunning() => running;
  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;
  @override
  void crateApiSyncSetSyncMode({required int mode}) {}
  @override
  void crateApiSyncCancelFullSync() {
    cancellations++;
    running = false;
  }

  @override
  void crateApiSyncSetEnhancePirEnabled({required bool enabled}) =>
      values.add(enabled);
  @override
  Future<EnhanceRecoveryStatus> crateApiSyncGetEnhanceRecoveryStatus({
    required String dbPath,
    required String network,
  }) {
    statusReads++;
    return statusResponse?.future ??
        Future.value(
          const EnhanceRecoveryStatus(
            queries: 0,
            rediscovery: 0,
            suspended: 0,
            serviceState: '',
          ),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements EnhancePirPreferenceStore {
  bool? value;
  bool fail = false;
  @override
  Future<bool?> readEnabled() async => value;
  @override
  Future<void> writeEnabled(bool enabled) async {
    if (fail) throw StateError('disk full');
    value = enabled;
  }
}

class _Sync extends SyncNotifier {
  var gate = Completer<void>();
  int transitions = 0;
  @override
  Future<SyncState> build() async => SyncState();
  @override
  Future<void> withRecoverySettingPaused(Future<void> Function() action) async {
    transitions++;
    await gate.future;
    await action();
  }
}

// Uses the production pause/transition implementation. Only app restart is
// suppressed: these tests have no wallet/accounts to launch another sync for.
class _RealSync extends SyncNotifier {
  _RealSync(IronwoodMigrationBackgroundLifecycle lifecycle)
    : super(
        recoveryLifecycle: lifecycle,
        recoveryTransitionTimeout: const Duration(milliseconds: 20),
      );
  int resumes = 0;
  @override
  Future<SyncState> build() async => SyncState();
  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {
    endWalletMutationPause();
    resumes++;
  }
}

class _StatusSync extends SyncNotifier {
  _StatusSync()
    : super(walletDbPathResolver: () async => '/tmp/status-wallet.db');

  @override
  Future<SyncState> build() async => SyncState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.values.clear();
    api.running = false;
    api.cancellations = 0;
    api.statusReads = 0;
    api.statusResponse = null;
  });
  ProviderContainer setup(
    _Store store,
    SyncNotifier sync, {
    bool initialEnabled = false,
    bool hasAccount = false,
  }) => ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/settings',
          initialAccountState: hasAccount
              ? const AccountState(
                  accounts: [
                    AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
                  ],
                  activeAccountUuid: 'account-1',
                )
              : const AccountState(),
          initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('fixture'),
          network: 'main',
          rpcEndpointConfig: defaultRpcEndpointConfig('main'),
          themeMode: ThemeMode.system,
          privacyModeEnabled: false,
          isPasswordConfigured: false,
          isUnlocked: true,
          passwordRotationRecoveryFailed: false,
          enhancePirEnabled: initialEnabled,
        ),
      ),
      enhancePirPreferenceStoreProvider.overrideWithValue(store),
      syncProvider.overrideWith(() => sync),
    ],
  );
  for (final stalled in [false, true]) {
    test(
      'real transition: native ${stalled ? "timeout and retry" : "pause before cancellation and commit"}',
      () async {
        const channel = MethodChannel('test/recovery-lifecycle');
        final native = Completer<bool>();
        final leases = <String>[];
        var pauseCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              leases.add(
                '${call.method}:${(call.arguments as Map)['leaseId']}',
              );
              if (call.method == 'quiesce' && pauseCalls++ == 0) {
                return native.future;
              }
              return true;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final lifecycle = IronwoodMigrationBackgroundLifecycle(
          channel: channel,
          isIOS: true,
          isAndroid: false,
          resumeRetryDelays: [Duration.zero],
        );
        final store = _Store();
        final sync = _RealSync(lifecycle);
        final container = setup(store, sync);
        addTearDown(container.dispose);
        await container.read(syncProvider.future);
        api.running = true;
        final notifier = container.read(enhancePirProvider.notifier);
        final change = notifier.toggle();
        await Future<void>.delayed(Duration.zero);
        expect(store.value, isNull);
        expect(api.cancellations, 0);
        await notifier
            .toggle(); // Busy interactions cannot enqueue another pause.
        if (!stalled) {
          native.complete(true);
        }
        await change;
        expect(leases.length, 2);
        expect(leases[0].split(':').skip(1), leases[1].split(':').skip(1));
        expect(sync.resumes, 1);
        if (stalled) {
          expect(native.isCompleted, isFalse);
          expect(store.value, isNull);
          expect(api.values, isEmpty);
          expect(
            container.read(enhancePirTransitionProvider),
            contains('Try again'),
          );
          await notifier.toggle();
          expect(leases.length, 4);
          expect(leases[0], isNot(leases[2]));
        }
        expect(api.cancellations, 1);
        expect(api.running, isFalse);
        expect(store.value, isTrue);
        expect(api.values, [true]);
      },
    );
  }
  test(
    'quiescence precedes persistence and repeated toggles are ignored',
    () async {
      final store = _Store();
      final sync = _Sync();
      final container = setup(store, sync);
      addTearDown(container.dispose);
      final notifier = container.read(enhancePirProvider.notifier);
      final changing = notifier.toggle();
      await notifier.toggle();
      expect(sync.transitions, 1);
      expect(store.value, isNull);
      expect(api.values, isEmpty);
      expect(container.read(enhancePirProvider), isFalse);
      sync.gate.complete();
      await changing;
      expect(store.value, isTrue);
      expect(api.values, [true]);
      expect(container.read(enhancePirProvider), isTrue);
    },
  );
  for (final failPause in [true, false]) {
    test(
      failPause
          ? 'timeout retains committed mode'
          : 'write failure retains committed mode',
      () async {
        final store = _Store()..fail = !failPause;
        final sync = _Sync();
        final container = setup(store, sync);
        addTearDown(container.dispose);
        final changing = container.read(enhancePirProvider.notifier).toggle();
        if (failPause) {
          sync.gate.completeError(TimeoutException('quiescence'));
        } else {
          sync.gate.complete();
        }
        await changing;
        expect(container.read(enhancePirProvider), isFalse);
        expect(store.value, isNull);
        expect(api.values, isEmpty);
        expect(
          container.read(enhancePirTransitionProvider),
          contains('Try again'),
        );
      },
    );
  }
  test(
    'polling retries active work at an unchanged tip, not suspensions alone',
    () {
      final current = SyncState(isSyncComplete: true, chainTipHeight: 100);
      expect(
        shouldStartSyncForPolledTip(current, 100, hasActiveRecovery: true),
        isTrue,
      );
      expect(shouldStartSyncForPolledTip(current, 100), isFalse);
    },
  );

  group('RecoveryRestartGate', () {
    late DateTime clock;
    RecoveryRestartGate gate() => RecoveryRestartGate(now: () => clock);

    setUp(() => clock = DateTime.utc(2026));

    test('suspension-only work never schedules a restart', () {
      expect(gate().shouldRestart(0), isFalse);
    });

    test('the first outstanding obligation retries immediately', () {
      expect(gate().shouldRestart(3), isTrue);
    });

    test('a stalled obligation backs off instead of retrying every poll', () {
      final g = gate();
      expect(g.shouldRestart(3), isTrue);
      // The 10-second poll keeps firing inside the first window.
      for (var i = 0; i < 2; i++) {
        clock = clock.add(const Duration(seconds: 10));
        expect(g.shouldRestart(3), isFalse);
      }
      clock = clock.add(const Duration(seconds: 10));
      expect(g.shouldRestart(3), isTrue);
      // The unchanged count doubled the wait, so the old interval is too soon.
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(3), isFalse);
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(3), isTrue);
    });

    test('the backoff is capped', () {
      final g = gate();
      for (var i = 0; i < 20; i++) {
        clock = clock.add(kRecoveryRestartMaxBackoff);
        expect(g.shouldRestart(3), isTrue);
      }
      clock = clock.add(
        kRecoveryRestartMaxBackoff - const Duration(seconds: 1),
      );
      expect(g.shouldRestart(3), isFalse);
      clock = clock.add(const Duration(seconds: 1));
      expect(g.shouldRestart(3), isTrue);
    });

    test('progress restores the base interval', () {
      final g = gate();
      expect(g.shouldRestart(3), isTrue);
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(3), isTrue); // stalled: now waiting 60s
      clock = clock.add(const Duration(seconds: 60));
      expect(g.shouldRestart(2), isTrue); // progressed
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(2), isTrue); // base interval again
    });

    test('newly discovered work also restores the base interval', () {
      final g = gate();
      expect(g.shouldRestart(3), isTrue);
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(3), isTrue); // stalled: now waiting 60s
      clock = clock.add(const Duration(seconds: 60));
      expect(g.shouldRestart(5), isTrue);
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(5), isTrue);
    });

    test('draining the queue clears the backoff for the next obligation', () {
      final g = gate();
      expect(g.shouldRestart(3), isTrue);
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(3), isTrue);
      expect(g.shouldRestart(0), isFalse);
      expect(g.shouldRestart(1), isTrue);
    });
  });
  test('a failed preference write can be retried', () async {
    final store = _Store()..fail = true;
    final sync = _Sync()..gate.complete();
    final container = setup(store, sync);
    addTearDown(container.dispose);
    final notifier = container.read(enhancePirProvider.notifier);
    await notifier.toggle();
    expect(container.read(enhancePirProvider), isFalse);
    store.fail = false;
    await notifier.toggle();
    expect(container.read(enhancePirProvider), isTrue);
    expect(api.values, [true]);
  });
  test(
    'disabling commits standard mode before the paused sync is resumed',
    () async {
      final store = _Store()..value = true;
      final sync = _Sync()..gate.complete();
      final container = setup(store, sync, initialEnabled: true);
      addTearDown(container.dispose);

      await container.read(enhancePirProvider.notifier).toggle();

      expect(sync.transitions, 1);
      expect(store.value, isFalse);
      expect(api.values, [false]);
      expect(container.read(enhancePirProvider), isFalse);
    },
  );
  test('quiescence timeout returns even if native never settles', () async {
    final source = Completer<void>();
    var reported = false;
    final waiting = waitForRecoveryQuiescence(
      source.future,
      timeout: Duration.zero,
    ).whenComplete(() => reported = true);
    final expectation = expectLater(waiting, throwsA(isA<TimeoutException>()));

    await Future<void>.delayed(const Duration(milliseconds: 1));
    await expectation;
    expect(source.isCompleted, isFalse);
    expect(reported, isTrue);
  });
  test('masquerade builds cannot enable the production PIR service', () {
    expect(
      isEnhancePirAvailableForNetwork('main', isMasquerade: true),
      isFalse,
    );
    expect(
      isEnhancePirAvailableForNetwork('main', isMasquerade: false),
      isTrue,
    );
  });

  test(
    'wallet mutation drains admitted status reads and blocks new ones',
    () async {
      final pendingStatus = Completer<EnhanceRecoveryStatus>();
      api.statusResponse = pendingStatus;
      final sync = _StatusSync();
      final container = setup(
        _Store(),
        sync,
        initialEnabled: true,
        hasAccount: true,
      );
      addTearDown(container.dispose);
      await container.read(syncProvider.future);

      final admitted = sync.recoveryStatus();
      await Future<void>.delayed(Duration.zero);
      expect(api.statusReads, 1);

      var pauseCompleted = false;
      final pausing = sync.pauseForWalletMutation().whenComplete(
        () => pauseCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(pauseCompleted, isFalse);
      expect(await sync.recoveryStatus(), isNull);
      expect(api.statusReads, 1);

      pendingStatus.complete(
        const EnhanceRecoveryStatus(
          queries: 1,
          rediscovery: 0,
          suspended: 0,
          serviceState: 'recovering',
        ),
      );
      await admitted;
      await pausing;
      sync.endWalletMutationPause();
    },
  );
}
