import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

class _Api extends RustLibApi {
  final values = <bool>[];

  /// Shared with the store, background sink and reconciler when a test checks
  /// the order across all of them.
  List<String>? events;
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
  void crateApiSyncSetEnhancePirEnabled({required bool enabled}) {
    values.add(enabled);
    events?.add('rust:$enabled');
  }

  @override
  void crateApiSyncSetEnhancePirPreferenceConfirmed({
    required bool confirmed,
  }) => events?.add('confirmed:$confirmed');

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
            status: 0,
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
  bool failEnabled = false;
  Completer<void>? pending;
  List<String>? events;
  @override
  Future<bool?> readEnabled() async => value;
  @override
  Future<void> writeEnabled(bool enabled) async {
    if (pending != null) await pending!.future;
    if (fail || (enabled && failEnabled)) throw StateError('disk full');
    events?.add('store:$enabled');
    value = enabled;
  }
}

ApiAppliedTransparentPolicy _applied(bool private, int generation) =>
    ApiAppliedTransparentPolicy(
      mode: private
          ? ApiTransparentLedgerMode.privateRequired
          : ApiTransparentLedgerMode.public,
      generation: BigInt.from(generation),
      changed: true,
    );

/// Records transparent policy reconciliation, which can fail per direction.
class _Reconciler {
  _Reconciler([this.events]);
  final List<String>? events;
  final calls = <bool>[];
  bool failRaise = false;
  bool failLower = false;
  int generation = 1;

  /// Whether lowering finds a private wallet to lower.
  bool lowers = true;
  Future<ApiAppliedTransparentPolicy?> call(bool privateQueries) async {
    calls.add(privateQueries);
    events?.add('reconcile:$privateQueries');
    if (privateQueries ? failRaise : failLower) {
      throw StateError('public lookups did not drain');
    }
    if (!privateQueries && !lowers) return null;
    return _applied(privateQueries, ++generation);
  }
}

/// Models the durable policy boundary: every build can lower a private wallet,
/// but a default build cannot raise it again through mode selection.
class _DurableReconciler extends _Reconciler {
  _DurableReconciler({required this.buildFlag});

  final bool buildFlag;
  bool privateRequired = true;

  @override
  Future<ApiAppliedTransparentPolicy?> call(bool privateQueries) async {
    await super.call(privateQueries);
    if (privateQueries && !buildFlag) return null;
    final changed = privateRequired != privateQueries;
    privateRequired = privateQueries;
    return changed ? _applied(privateQueries, generation) : null;
  }
}

/// The persisted marker of an unfinished opt-out.
class _OptOut implements TransparentOptOutStore {
  _OptOut([this.events]);
  final List<String>? events;
  bool value = false;
  bool failWrite = false;
  @override
  Future<bool> readPending() async => value;
  @override
  Future<void> writePending(bool pending) async {
    if (failWrite) throw StateError('disk full');
    events?.add('optout:$pending');
    value = pending;
  }
}

/// Records native background updates alongside store writes.
class _Background {
  _Background(this.events);
  final List<String> events;
  bool failEnable = false;
  bool failDisable = false;
  Completer<void>? stall;
  Future<void> call(bool enabled) async {
    await stall?.future;
    if (enabled ? failEnable : failDisable) {
      throw StateError('native unavailable');
    }
    events.add('native:$enabled');
  }
}

class _Sync extends SyncNotifier {
  var gate = Completer<void>();
  int transitions = 0;
  int starts = 0;
  @override
  Future<SyncState> build() async => SyncState();
  @override
  void startSync({int? latestTipHeight}) => starts++;
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
  void resumeAfterWalletMutation(
    WalletMutationSyncPause pause, {
    bool forceRestart = false,
  }) {
    endWalletMutationPause();
    resumes++;
  }
}

/// Records restart attempts without touching Rust or the wallet DB.
class _RestartSync extends SyncNotifier {
  _RestartSync({
    IronwoodMigrationBackgroundLifecycle? lifecycle,
    Duration transitionTimeout = const Duration(seconds: 120),
  }) : super(
         recoveryLifecycle: lifecycle,
         recoveryTransitionTimeout: transitionTimeout,
       );

  int starts = 0;
  @override
  Future<SyncState> build() async => SyncState();
  @override
  void startSync({int? latestTipHeight}) => starts++;
}

/// Runs the production `startSync` guards and counts every entry. Tests set
/// `api.running` so a start that passes the guards stops at "already running"
/// instead of reaching Rust.
class _GuardedSync extends SyncNotifier {
  int attempts = 0;
  VoidCallback? onAttempt;
  @override
  Future<SyncState> build() async => SyncState();
  @override
  void startSync({int? latestTipHeight}) {
    attempts++;
    onAttempt?.call();
    super.startSync(latestTipHeight: latestTipHeight);
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
    api.events = null;
    api.running = false;
    api.cancellations = 0;
    api.statusReads = 0;
    api.statusResponse = null;
  });
  ProviderContainer setup(
    _Store store,
    SyncNotifier sync, {
    bool? initialEnabled = false,
    bool hasAccount = false,
    _Background? background,
    _Reconciler? reconciler,
    _OptOut? optOut,
    LinuxKeyringCoordinator? coordinator,
  }) => ProviderContainer(
    overrides: [
      transparentOptOutStoreProvider.overrideWithValue(optOut ?? _OptOut()),
      if (coordinator != null)
        linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
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
      transparentPolicyReconcilerProvider.overrideWithValue(
        (reconciler ?? _Reconciler()).call,
      ),
      syncProvider.overrideWith(() => sync),
      if (background != null)
        enhancePirBackgroundSinkProvider.overrideWithValue(background.call),
    ],
  );
  test(
    'first sync requested during preference save resumes with private policy',
    () async {
      final store = _Store()..pending = Completer<void>();
      final policiesAtStart = <List<bool>>[];
      final sync = _GuardedSync()
        ..onAttempt = () => policiesAtStart.add(List.of(api.values));
      final container = setup(store, sync, hasAccount: true);
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
      final change = container.read(enhancePirProvider.notifier).set(true);
      await Future<void>.delayed(Duration.zero);
      // Stop at the duplicate-sync guard after the production pause guards,
      // avoiding network access in this test.
      api.running = true;
      sync.startSync();
      expect(sync.attempts, 1);
      expect(api.values, isEmpty);
      store.pending!.complete();
      await change;
      expect(store.value, isTrue);
      expect(policiesAtStart, [
        <bool>[],
        [true],
      ]);
      expect(container.read(enhancePirProvider), isTrue);
    },
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
        // A transition that never acquired a pause must not release one: the
        // stalled branch fails inside `quiesce()`, before `pause` exists.
        expect(sync.resumes, stalled ? 0 : 1);
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
          // The retry does take a pause, so it releases exactly that one.
          expect(sync.resumes, 1);
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
  test(
    'enabling and disabling apply the stricter state first on every side',
    () async {
      final events = <String>[];
      api.events = events;
      final store = _Store()..events = events;
      final background = _Background(events);
      final sync = _Sync()..gate.complete();
      final optOut = _OptOut(events);
      final container = setup(
        store,
        sync,
        background: background,
        reconciler: _Reconciler(events),
        optOut: optOut,
      );
      addTearDown(container.dispose);
      final notifier = container.read(enhancePirProvider.notifier);

      await notifier.set(true);
      expect(container.read(enhancePirProvider), isTrue);
      await notifier.set(false);

      expect(events, [
        'native:true',
        'store:true',
        'rust:true',
        'confirmed:true',
        // Turning on supersedes an unfinished opt-out.
        'optout:false',
        'reconcile:true',
        // The opt-out is persisted before anything weakens, and cleared
        // only once the lowering applied.
        'optout:true',
        'store:false',
        'rust:false',
        'reconcile:false',
        'native:false',
        'optout:false',
      ]);
      expect(optOut.value, isFalse);
      expect(container.read(transparentOptOutPendingProvider), isFalse);
      expect(container.read(enhancePirProvider), isFalse);
      expect(container.read(enhancePirTransitionProvider), isNull);
    },
  );
  test(
    'enabling aborts before commit when background work cannot follow',
    () async {
      final events = <String>[];
      final store = _Store()..events = events;
      final background = _Background(events)..failEnable = true;
      final reconciler = _Reconciler();
      final sync = _Sync()..gate.complete();
      final container = setup(
        store,
        sync,
        background: background,
        reconciler: reconciler,
      );
      addTearDown(container.dispose);

      await container.read(enhancePirProvider.notifier).set(true);

      expect(events, isEmpty);
      expect(store.value, isNull);
      expect(api.values, isEmpty);
      expect(reconciler.calls, isEmpty);
      expect(container.read(enhancePirProvider), isFalse);
      expect(
        container.read(enhancePirTransitionProvider),
        contains('Try again'),
      );
    },
  );
  // Previously a failed raise rolled the shielded setting back off. The
  // shielded setting now stays where the user put it; the startup and sync
  // raise paths retry the transparent raise.
  test(
    'a failed raise on enable keeps private queries on and reports it',
    () async {
      final events = <String>[];
      api.events = events;
      final store = _Store()..events = events;
      final sync = _Sync()..gate.complete();
      final container = setup(
        store,
        sync,
        background: _Background(events),
        reconciler: _Reconciler(events)..failRaise = true,
      );
      addTearDown(container.dispose);

      await container.read(enhancePirProvider.notifier).set(true);

      expect(events, [
        'native:true',
        'store:true',
        'rust:true',
        'confirmed:true',
        'reconcile:true',
      ]);
      expect(api.values, [true], reason: 'no rollback');
      expect(store.value, isTrue);
      expect(container.read(enhancePirProvider), isTrue);
      expect(
        container.read(enhancePirTransitionProvider),
        kTransparentRaisePendingMessage,
      );
      // Nothing was applied, so nothing is adopted.
      expect(sync.appliedTransparentPolicy, isNull);
    },
  );
  // Previously a failed lowering restored Rust and the saved preference to
  // on. The shielded setting now stays off and the opt-out stays persisted,
  // so startup retries it; the durable private policy keeps governing every
  // transparent lookup meanwhile.
  test('a failed lowering on disable keeps private queries off and persists '
      'the opt-out', () async {
    final events = <String>[];
    api.events = events;
    final store = _Store()
      ..value = true
      ..events = events;
    final optOut = _OptOut(events);
    final reconciler = _DurableReconciler(buildFlag: false)..failLower = true;
    final sync = _Sync()..gate.complete();
    final container = setup(
      store,
      sync,
      initialEnabled: true,
      background: _Background(events),
      reconciler: reconciler,
      optOut: optOut,
    );
    addTearDown(container.dispose);

    await container.read(enhancePirProvider.notifier).set(false);

    expect(events, [
      'optout:true',
      'store:false',
      'rust:false',
      'native:false',
    ]);
    expect(api.values, [false], reason: 'no rollback');
    expect(store.value, isFalse);
    expect(container.read(enhancePirProvider), isFalse);
    // Fail-closed: the wallet is still durably private.
    expect(reconciler.privateRequired, isTrue);
    expect(reconciler.calls, [false]);
    expect(optOut.value, isTrue);
    expect(container.read(transparentOptOutPendingProvider), isTrue);
    expect(container.read(transparentOptOutActionProvider), isTrue);
    expect(
      container.read(enhancePirTransitionProvider),
      kTransparentOptOutPendingMessage,
    );
    expect(sync.appliedTransparentPolicy, isNull);
  });
  test('a pending opt-out can be finished from Settings', () async {
    final store = _Store()..value = true;
    final optOut = _OptOut();
    final reconciler = _DurableReconciler(buildFlag: false)..failLower = true;
    final sync = _Sync()..gate.complete();
    final container = setup(
      store,
      sync,
      initialEnabled: true,
      background: _Background(<String>[]),
      reconciler: reconciler,
      optOut: optOut,
    );
    addTearDown(container.dispose);
    final notifier = container.read(enhancePirProvider.notifier);
    await notifier.set(false);
    expect(optOut.value, isTrue);
    // A second off is not a change of the setting.
    await notifier.set(false);
    expect(reconciler.calls, [false]);

    reconciler.failLower = false;
    await notifier.finishTransparentOptOut();

    expect(reconciler.calls, [false, false]);
    expect(reconciler.privateRequired, isFalse);
    expect(optOut.value, isFalse);
    expect(container.read(transparentOptOutPendingProvider), isFalse);
    expect(container.read(transparentOptOutActionProvider), isFalse);
    expect(container.read(enhancePirTransitionProvider), isNull);
    expect(container.read(enhancePirProvider), isFalse);
    expect(
      sync.appliedTransparentPolicy?.mode,
      ApiTransparentLedgerMode.public,
    );
  });
  test('a failed opt-out marker write changes nothing', () async {
    final events = <String>[];
    api.events = events;
    final store = _Store()
      ..value = true
      ..events = events;
    final reconciler = _DurableReconciler(buildFlag: false);
    final container = setup(
      store,
      _Sync()..gate.complete(),
      initialEnabled: true,
      background: _Background(events),
      reconciler: reconciler,
      optOut: _OptOut()..failWrite = true,
    );
    addTearDown(container.dispose);

    await container.read(enhancePirProvider.notifier).set(false);

    expect(events, isEmpty);
    expect(reconciler.calls, isEmpty);
    expect(reconciler.privateRequired, isTrue);
    expect(container.read(enhancePirProvider), isTrue);
    expect(
      container.read(enhancePirTransitionProvider),
      kEnhancePirUnchangedMessage,
    );
  });
  test(
    'a pending disable save leaves durable private policy untouched',
    () async {
      final events = <String>[];
      api.events = events;
      final store = _Store()
        ..value = true
        ..events = events
        ..pending = Completer<void>();
      final reconciler = _DurableReconciler(buildFlag: false);
      final sync = _Sync()..gate.complete();
      final container = setup(
        store,
        sync,
        initialEnabled: true,
        background: _Background(events),
        reconciler: reconciler,
      );
      addTearDown(container.dispose);

      final change = container.read(enhancePirProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);

      expect(reconciler.privateRequired, isTrue);
      expect(reconciler.calls, isEmpty);
      expect(api.values, isEmpty);
      expect(events, isEmpty);
      expect(store.value, isTrue);
      expect(container.read(enhancePirProvider), isTrue);
      store.pending!.complete();
      await change;
      expect(store.value, isFalse);
      expect(reconciler.privateRequired, isFalse);
      expect(reconciler.calls, [false]);
      expect(api.values, [false]);
      expect(events, ['store:false', 'rust:false', 'native:false']);
      expect(container.read(enhancePirProvider), isFalse);
      expect(container.read(enhancePirTransitionProvider), isNull);
    },
  );
  for (final buildFlag in [false, true]) {
    test('a failed disable save preserves durable private policy with '
        'build flag $buildFlag', () async {
      final store = _Store()
        ..value = true
        ..fail = true;
      final reconciler = _DurableReconciler(buildFlag: buildFlag);
      final events = <String>[];
      final optOut = _OptOut();
      addTearDown(() => expect(optOut.value, isFalse));
      final container = setup(
        store,
        _Sync()..gate.complete(),
        initialEnabled: true,
        background: _Background(events),
        reconciler: reconciler,
        optOut: optOut,
      );
      addTearDown(container.dispose);

      await container.read(enhancePirProvider.notifier).set(false);

      expect(reconciler.privateRequired, isTrue);
      expect(reconciler.calls, isEmpty);
      expect(api.values, isEmpty);
      expect(events, isEmpty);
      expect(store.value, isTrue);
      expect(container.read(enhancePirProvider), isTrue);
      expect(
        container.read(enhancePirTransitionProvider),
        'Setting unchanged. Try again.',
      );
    });
  }
  // Previously a failed lowering tried to restore the saved preference to
  // on. Nothing is restored now: the opt-out stays saved and pending.
  test('a failed lowering never lowers durable private policy nor restores '
      'the setting', () async {
    final store = _Store()
      ..value = true
      ..failEnabled = true;
    final reconciler = _DurableReconciler(buildFlag: false)..failLower = true;
    final events = <String>[];
    final container = setup(
      store,
      _Sync()..gate.complete(),
      initialEnabled: true,
      background: _Background(events),
      reconciler: reconciler,
    );
    addTearDown(container.dispose);

    await container.read(enhancePirProvider.notifier).set(false);

    expect(reconciler.privateRequired, isTrue);
    expect(reconciler.calls, [false]);
    expect(api.values, [false]);
    expect(events, ['native:false']);
    expect(store.value, isFalse);
    expect(container.read(enhancePirProvider), isFalse);
    expect(
      container.read(enhancePirTransitionProvider),
      kTransparentOptOutPendingMessage,
    );
  });
  test(
    'a failed disable save changes no policy for an unreadable preference',
    () async {
      final events = <String>[];
      api.events = events;
      final store = _Store()
        ..events = events
        ..fail = true;
      final sync = _Sync()..gate.complete();
      final container = setup(
        store,
        sync,
        // Unreadable at launch: on for the launch, but never raised.
        initialEnabled: null,
        background: _Background(events),
        reconciler: _Reconciler(events)..lowers = false,
      );
      addTearDown(container.dispose);

      await container.read(enhancePirProvider.notifier).set(false);

      // No runtime, durable or native policy changes until the save succeeds.
      expect(events, isEmpty);
      expect(api.values, isEmpty);
      expect(store.value, isNull);
      expect(container.read(enhancePirProvider), isTrue);
      expect(
        container.read(enhancePirTransitionProvider),
        'Setting unchanged. Try again.',
      );
    },
  );
  test('an unreadable saved setting is on for this launch', () {
    final container = setup(_Store(), _Sync(), initialEnabled: null);
    addTearDown(container.dispose);
    expect(container.read(enhancePirProvider), isTrue);
  });
  test(
    'a lowering is adopted before the native sink or marker is awaited',
    () async {
      final events = <String>[];
      final store = _Store()..events = events;
      final background = _Background(events)..stall = Completer<void>();
      final sync = _Sync()..gate.complete();
      final container = setup(
        store,
        sync,
        initialEnabled: true,
        background: background,
      );
      addTearDown(container.dispose);

      final change = container.read(enhancePirProvider.notifier).set(false);
      await pumpEventQueue();
      // The native sink is still stalled, but the lowered policy already
      // drives demotion.
      expect(
        sync.appliedTransparentPolicy?.mode,
        ApiTransparentLedgerMode.public,
      );
      background.stall!.complete();
      await change;
    },
  );

  test('a wallet reset forgets the applied policy of the old wallet', () async {
    final sync = _Sync()..gate.complete();
    final container = setup(_Store(), sync, initialEnabled: true);
    addTearDown(container.dispose);
    await container.read(syncProvider.future);
    sync.adoptAppliedTransparentPolicy(
      ApiAppliedTransparentPolicy(
        mode: ApiTransparentLedgerMode.privateRequired,
        generation: BigInt.from(7),
        changed: true,
      ),
    );
    sync.pauseForWalletMutation();
    sync.endWalletMutationPause();
    expect(sync.appliedTransparentPolicy, isNull);
  });

  test('disabling commits even when background work stays private', () async {
    final events = <String>[];
    final store = _Store()..events = events;
    final background = _Background(events)..failDisable = true;
    final sync = _Sync()..gate.complete();
    final container = setup(
      store,
      sync,
      initialEnabled: true,
      background: background,
    );
    addTearDown(container.dispose);

    await container.read(enhancePirProvider.notifier).set(false);

    expect(events, ['store:false']);
    expect(api.values, [false]);
    expect(container.read(enhancePirProvider), isFalse);
    expect(container.read(enhancePirTransitionProvider), isNull);
  });
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

  group('toggle, reset and deletion serialize on every platform', () {
    for (final linux in [false, true]) {
      final platform = linux ? 'Linux' : 'other platforms';
      test(
        'a toggle during a reset or deletion changes nothing ($platform)',
        () async {
          final coordinator = LinuxKeyringCoordinator.testing(enabled: linux);
          addTearDown(coordinator.dispose);
          final store = _Store();
          final reconciler = _Reconciler();
          final sync = _Sync()..gate.complete();
          final container = setup(
            store,
            sync,
            reconciler: reconciler,
            coordinator: coordinator,
          );
          addTearDown(container.dispose);
          final release = Completer<void>();
          // A reset or deletion, as `runWithSyncPausedForAccountMutation` runs it.
          final reset = coordinator.runMutation(() => release.future);

          final notifier = container.read(enhancePirProvider.notifier);
          await notifier.set(true);

          expect(sync.transitions, 0, reason: 'never paused sync');
          expect(store.value, isNull);
          expect(reconciler.calls, isEmpty);
          expect(api.values, isEmpty);
          expect(container.read(enhancePirProvider), isFalse);
          expect(
            container.read(enhancePirTransitionProvider),
            kEnhancePirUnchangedMessage,
          );

          release.complete();
          await reset;
          await notifier.set(true);
          expect(store.value, isTrue);
          expect(container.read(enhancePirProvider), isTrue);
        },
      );

      test(
        'a reset or deletion during a toggle is refused ($platform)',
        () async {
          final coordinator = LinuxKeyringCoordinator.testing(enabled: linux);
          addTearDown(coordinator.dispose);
          final store = _Store();
          final sync = _Sync();
          final container = setup(store, sync, coordinator: coordinator);
          addTearDown(container.dispose);

          final change = container.read(enhancePirProvider.notifier).set(true);
          await Future<void>.delayed(Duration.zero);
          expect(sync.transitions, 1);
          await expectLater(
            coordinator.runMutation(() async => fail('reset ran')),
            throwsA(isA<WalletMutationBusyException>()),
          );

          sync.gate.complete();
          await change;
          expect(store.value, isTrue);
          // The lane is free again.
          expect(await coordinator.runMutation(() async => 7), 7);
        },
      );
    }

    test(
      'a toggle nested inside the running mutation keeps ownership',
      () async {
        final coordinator = LinuxKeyringCoordinator.testing(enabled: false);
        addTearDown(coordinator.dispose);
        final store = _Store();
        final container = setup(
          store,
          _Sync()..gate.complete(),
          coordinator: coordinator,
        );
        addTearDown(container.dispose);

        await coordinator.runMutation(
          () => container.read(enhancePirProvider.notifier).set(true),
        );

        expect(store.value, isTrue);
        expect(container.read(enhancePirTransitionProvider), isNull);
      },
    );
  });

  test('the wallet reconciler never names a wallet into existence', () async {
    var resolved = 0;
    final reconcile = walletTransparentPolicyReconciler(
      'main',
      resolveExistingDbPath: () async {
        resolved++;
        return null;
      },
    );
    // The mock Rust API would throw if reconciliation reached it.
    expect(await reconcile(true), isNull);
    expect(await reconcile(false), isNull);
    expect(resolved, 2);
  });

  test(
    'a policy applied by the toggle is adopted and restarts sync once',
    () async {
      final store = _Store();
      final sync = _Sync()..gate.complete();
      final container = setup(store, sync, reconciler: _Reconciler());
      addTearDown(container.dispose);
      await container.read(syncProvider.future);

      await container.read(enhancePirProvider.notifier).set(true);

      expect(
        sync.appliedTransparentPolicy?.mode,
        ApiTransparentLedgerMode.privateRequired,
      );
      // `_Sync` takes no pause, so the adopted generation restarts directly.
      expect(sync.starts, 1);
    },
  );

  group('overlapping wallet mutations', () {
    late ProviderContainer container;
    late _RestartSync sync;

    setUp(() {
      sync = _RestartSync();
      container = setup(_Store(), sync, hasAccount: true);
      addTearDown(container.dispose);
      container.read(syncProvider.notifier);
    });

    test('a restart waits for the last pause to exit', () async {
      // Account deletion takes the outer pause; the recovery toggle takes the
      // inner one while deletion is still writing the wallet DB.
      final deletion = await sync.pauseForWalletMutation();
      final toggle = await sync.pauseForWalletMutation();

      sync.resumeAfterWalletMutation(toggle, forceRestart: true);
      expect(sync.starts, 0, reason: 'deletion still owns the wallet DB');

      sync.resumeAfterWalletMutation(deletion);
      expect(sync.starts, 1);
    });

    test('an opt-out exit discards a deferred restart', () async {
      final reset = await sync.pauseForWalletMutation();
      final toggle = await sync.pauseForWalletMutation();

      sync.resumeAfterWalletMutation(toggle, forceRestart: true);
      expect(sync.starts, 0);

      // A full reset ends with no wallet to sync, so it opts out entirely.
      expect(reset.hadWorkToPause, isFalse);
      sync.endWalletMutationPause();
      expect(sync.starts, 0);
    });

    test('a reset nested inside a toggle cancels the toggle restart', () async {
      // The toggle pauses first; a full reset pauses inside it, deletes the
      // wallet, and exits first with the opt-out.
      final toggle = await sync.pauseForWalletMutation();
      final reset = await sync.pauseForWalletMutation();
      expect(reset.hadWorkToPause, isFalse);
      sync.endWalletMutationPause();

      sync.resumeAfterWalletMutation(toggle, forceRestart: true);
      expect(
        sync.starts,
        0,
        reason: 'the toggle snapshot names a deleted wallet',
      );
    });

    test('a lone pause restarts immediately', () async {
      final toggle = await sync.pauseForWalletMutation();
      sync.resumeAfterWalletMutation(toggle, forceRestart: true);
      expect(sync.starts, 1);
    });

    test('a transition that never paused cannot release a deletion', () async {
      const channel = MethodChannel('test/overlap-lifecycle');
      // Never answers, so `quiesce()` times out before a pause is taken.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) => Completer<bool>().future,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final stalling = _RestartSync(
        lifecycle: IronwoodMigrationBackgroundLifecycle(
          channel: channel,
          isIOS: true,
          isAndroid: false,
          resumeRetryDelays: const [Duration.zero],
        ),
        transitionTimeout: const Duration(milliseconds: 20),
      );
      final overlapContainer = setup(_Store(), stalling, hasAccount: true);
      addTearDown(overlapContainer.dispose);
      await overlapContainer.read(syncProvider.future);

      final deletion = await stalling.pauseForWalletMutation();
      await expectLater(
        stalling.withRecoverySettingPaused(() async {}),
        throwsA(isA<TimeoutException>()),
      );

      expect(stalling.starts, 0, reason: 'deletion still owns the wallet DB');
      // The deletion's pause survived, so releasing it is what restarts.
      stalling.resumeAfterWalletMutation(deletion, forceRestart: true);
      expect(stalling.starts, 1);
    });
  });

  group('sync starts during a wallet mutation', () {
    late ProviderContainer container;
    late _GuardedSync sync;

    setUp(() async {
      sync = _GuardedSync();
      container = setup(_Store(), sync, hasAccount: true);
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
    });

    test(
      'an app-resume start is deferred until the last pause exits',
      () async {
        // Account deletion holds the only pause; nothing was running to resume.
        final deletion = await sync.pauseForWalletMutation();
        api.running = true;

        sync.startSync(); // e.g. onResume or an account-count callback
        expect(sync.attempts, 1);

        sync.resumeAfterWalletMutation(deletion);
        expect(
          sync.attempts,
          2,
          reason: 'the start refused during the pause is replayed on exit',
        );
      },
    );

    test('a toggle overlapping a deletion never starts sync early', () async {
      final deletion = await sync.pauseForWalletMutation();
      final toggle = await sync.pauseForWalletMutation();
      api.running = true;

      sync.resumeAfterWalletMutation(toggle, forceRestart: true);
      sync.startSync();
      expect(sync.attempts, 1, reason: 'only the refused direct start');

      sync.resumeAfterWalletMutation(deletion);
      expect(sync.attempts, 2);
    });

    test('a start requested before a nested reset is dropped', () async {
      final toggle = await sync.pauseForWalletMutation();
      api.running = true;
      sync.startSync(); // deferred: the toggle owns the DB
      expect(sync.attempts, 1);

      await sync.pauseForWalletMutation(); // the reset
      sync.endWalletMutationPause();

      sync.resumeAfterWalletMutation(toggle);
      expect(sync.attempts, 1, reason: 'that start was for the deleted wallet');
    });

    test('a start requested after a nested reset still runs', () async {
      final toggle = await sync.pauseForWalletMutation();
      await sync.pauseForWalletMutation(); // the reset
      sync.endWalletMutationPause();

      // A new wallet is created while the toggle is still held.
      api.running = true;
      sync.startSync();
      expect(sync.attempts, 1);

      sync.resumeAfterWalletMutation(toggle, forceRestart: true);
      expect(
        sync.attempts,
        2,
        reason: 'the new wallet still gets its first sync on the last exit',
      );
    });

    test('a reset that opts out discards a refused start', () async {
      final reset = await sync.pauseForWalletMutation();
      api.running = true;
      sync.startSync();

      sync.endWalletMutationPause();
      expect(sync.attempts, 1, reason: 'no wallet is left to sync');
      expect(reset.hadWorkToPause, isFalse);
    });
  });

  test('deferred private status work counts toward a recovery restart', () {
    const statusOnly = EnhanceRecoveryStatus(
      queries: 0,
      rediscovery: 0,
      suspended: 0,
      status: 1,
      serviceState: '',
    );
    expect(recoveryRestartUnits(statusOnly), 1);
    expect(
      RecoveryRestartGate().shouldRestart(recoveryRestartUnits(statusOnly)),
      isTrue,
    );
    const suspendedOnly = EnhanceRecoveryStatus(
      queries: 0,
      rediscovery: 0,
      suspended: 2,
      status: 0,
      serviceState: '',
    );
    expect(recoveryRestartUnits(suspendedOnly), 0);
  });

  test('deferred private status work counts toward a recovery restart', () {
    const statusOnly = EnhanceRecoveryStatus(
      queries: 0,
      rediscovery: 0,
      suspended: 0,
      status: 1,
      serviceState: '',
    );
    expect(recoveryRestartUnits(statusOnly), 1);
    expect(
      RecoveryRestartGate().shouldRestart(recoveryRestartUnits(statusOnly)),
      isTrue,
    );
    // Suspended work is not retryable and never schedules a restart.
    const suspendedOnly = EnhanceRecoveryStatus(
      queries: 0,
      rediscovery: 0,
      suspended: 2,
      status: 0,
      serviceState: '',
    );
    expect(recoveryRestartUnits(suspendedOnly), 0);
  });

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

    test(
      'a count change inside a long backoff returns to the base interval',
      () {
        final g = gate();
        // Stall until the backoff is capped at ten minutes.
        for (var i = 0; i < 20; i++) {
          clock = clock.add(kRecoveryRestartMaxBackoff);
          expect(g.shouldRestart(3), isTrue);
        }
        // A tip-driven sync completes one obligation shortly after.
        clock = clock.add(const Duration(seconds: 5));
        expect(g.shouldRestart(2), isFalse, reason: 'that sync ran recovery');
        clock = clock.add(
          kRecoveryRestartInitialBackoff - const Duration(seconds: 1),
        );
        expect(g.shouldRestart(2), isFalse);
        clock = clock.add(const Duration(seconds: 1));
        expect(
          g.shouldRestart(2),
          isTrue,
          reason: 'not the ten minutes left on the stale deadline',
        );
      },
    );

    test('an unchanged count inside the window keeps the backoff', () {
      final g = gate();
      expect(g.shouldRestart(3), isTrue);
      clock = clock.add(kRecoveryRestartInitialBackoff);
      expect(g.shouldRestart(3), isTrue); // stalled: now waiting 60s
      clock = clock.add(const Duration(seconds: 45));
      expect(g.shouldRestart(3), isFalse);
      clock = clock.add(const Duration(seconds: 15));
      expect(g.shouldRestart(3), isTrue);
    });

    test('a rebase never pushes an earlier deadline later', () {
      final g = gate();
      expect(g.shouldRestart(3), isTrue); // deadline in 30s
      clock = clock.add(const Duration(seconds: 20));
      expect(g.shouldRestart(4), isFalse);
      clock = clock.add(const Duration(seconds: 10));
      expect(g.shouldRestart(4), isTrue, reason: 'the original 30s deadline');
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
          status: 0,
          serviceState: 'recovering',
        ),
      );
      await admitted;
      await pausing;
      sync.endWalletMutationPause();
    },
  );
}
