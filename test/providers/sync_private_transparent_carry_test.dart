import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _accountUuid = 'account-1';

class _Api extends RustLibApi {
  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  void crateApiSyncSetActiveSyncAccount({String? accountUuid}) {}

  @override
  void crateApiSyncCancelFullSync() {}

  @override
  void crateApiSyncStopMempoolObserver() {}

  /// Accepts the receiver-round cancellation the sync notifier sends.
  @override
  void crateApiOneTimeIvkCancelSwapRecovery() {}

  /// Finishes a receiver round at once without wallet work.
  @override
  Future<bool> crateApiOneTimeIvkRunSwapRecovery({
    required String dbPath,
    required String networkName,
  }) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
  );
}

/// Starts from [initial] and never resolves the wallet path, so a sync start
/// publishes its starting state and goes no further.
class _CarrySync extends SyncNotifier {
  _CarrySync(this.initial, {Future<String> Function()? walletDbPathResolver})
    : super(
        walletDbPathResolver:
            walletDbPathResolver ?? () => Completer<String>().future,
      );

  final SyncState initial;
  int starts = 0;

  void replaceStateForTesting(SyncState next) => state = AsyncData(next);

  @override
  Future<SyncState> build() async => initial;

  /// Counts restarts after the first start, which tests make themselves.
  bool countStarts = false;

  @override
  void startSync({int? latestTipHeight}) {
    if (countStarts) {
      starts++;
      return;
    }
    super.startSync(latestTipHeight: latestTipHeight);
  }
}

/// A progress event during the scan, which reads nothing from Rust.
SyncProgressEvent _scanning({required int tip}) => SyncProgressEvent(
  scannedHeight: 5,
  chainTipHeight: tip,
  percentage: 0.5,
  displayTargetPercentage: 0.5,
  displayTargetBlocks: 0,
  isSyncing: true,
  isComplete: false,
  hasNewTx: false,
);

rust_sync.ApiAppliedTransparentPolicy _policy(
  rust_sync.ApiTransparentLedgerMode mode,
  int generation,
) => rust_sync.ApiAppliedTransparentPolicy(
  mode: mode,
  generation: BigInt.from(generation),
);

class _EnhancePir extends EnhancePirNotifier {
  _EnhancePir(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;

  /// Turns private queries on, as a successful raise does.
  void raise() => state = true;
}

const _otherAccountUuid = 'account-2';

/// Two accounts, `account-1` active, switchable with [activate].
class _Accounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0),
      AccountInfo(uuid: _otherAccountUuid, name: 'Account 2', order: 1),
    ],
    activeAccountUuid: _accountUuid,
  );

  void activate(String uuid) => state = AsyncData(
    AccountState(accounts: state.value!.accounts, activeAccountUuid: uuid),
  );
}

/// The production [SyncNotifier] build, from the bootstrap snapshot, whose
/// syncs never resolve the wallet path and so go no further than their start.
class _LiveSync extends SyncNotifier {
  _LiveSync() : super(walletDbPathResolver: () => Completer<String>().future);
}

AppBootstrapState _bootstrapWith(AppSyncSnapshot snapshot) => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(),
  initialSyncSnapshot: snapshot,
  network: AppBootstrapState.empty.network,
  rpcEndpointConfig: AppBootstrapState.empty.rpcEndpointConfig,
  themeMode: AppBootstrapState.empty.themeMode,
  privacyModeEnabled: false,
  isPasswordConfigured: false,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

/// A public, current startup read of `account-1`, whose whole total is
/// transparent: 5 spendable, 2 pending, and [locked].
AppSyncSnapshot _publicSnapshot({bool private = false, BigInt? locked}) =>
    AppSyncSnapshot(
      transparentPrivate: private,
      accountUuid: _accountUuid,
      hasAccountScopedData: true,
      scannedHeight: 10,
      chainTipHeight: 10,
      percentage: 1,
      transparentBalance: BigInt.from(5),
      saplingBalance: BigInt.zero,
      orchardBalance: BigInt.zero,
      ironwoodBalance: BigInt.zero,
      orchardLockedBalance: BigInt.zero,
      transparentPendingBalance: BigInt.from(2),
      transparentLockedBalance: locked,
      saplingPendingBalance: BigInt.zero,
      orchardPendingBalance: BigInt.zero,
      ironwoodPendingBalance: BigInt.zero,
      canShieldTransparentBalance: true,
      shieldTransparentFee: BigInt.zero,
      shieldTransparentAmount: BigInt.zero,
      spendableBalance: BigInt.zero,
      totalBalance: BigInt.from(7) + (locked ?? BigInt.zero),
      recentTransactions: const [],
    );

/// A startup read of `account-1` under `PrivateRequired`, whose recovery is
/// stopped for [reason] with a last-known amount of 7.
AppSyncSnapshot _stoppedSnapshot(rust_sync.TransparentStopReason reason) =>
    AppSyncSnapshot(
      transparentPrivate: true,
      transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
      transparentLastKnownBalance: BigInt.from(7),
      transparentStop: reason,
      accountUuid: _accountUuid,
      hasAccountScopedData: true,
      scannedHeight: 10,
      chainTipHeight: 10,
      percentage: 1,
      transparentBalance: BigInt.zero,
      saplingBalance: BigInt.zero,
      orchardBalance: BigInt.zero,
      ironwoodBalance: BigInt.zero,
      orchardLockedBalance: BigInt.zero,
      transparentPendingBalance: BigInt.zero,
      saplingPendingBalance: BigInt.zero,
      orchardPendingBalance: BigInt.zero,
      ironwoodPendingBalance: BigInt.zero,
      canShieldTransparentBalance: false,
      shieldTransparentFee: BigInt.zero,
      shieldTransparentAmount: BigInt.zero,
      spendableBalance: BigInt.zero,
      totalBalance: BigInt.zero,
      recentTransactions: const [],
    );

/// [shielded] is the total without the demoted transparent amount.
void _expectDemoted(SyncState state, {required BigInt shielded}) {
  expect(
    state.transparentAuthority,
    rust_sync.TransparentBalanceAuthority.lastKnown,
  );
  expect(state.transparentLastKnownBalance, BigInt.from(7));
  expect(state.transparentBalance, BigInt.zero);
  expect(state.transparentPendingBalance, BigInt.zero);
  expect(state.canShieldTransparentBalance, isFalse);
  expect(state.totalBalance, shielded);
  expect(state.displayTotalBalance, shielded);
}

void _expectCurrent(SyncState state) {
  expect(
    state.transparentAuthority,
    rust_sync.TransparentBalanceAuthority.current,
  );
  expect(state.transparentBalance, BigInt.from(5));
  expect(state.transparentPendingBalance, BigInt.from(2));
  expect(state.canShieldTransparentBalance, isTrue);
}

/// The shielded part of [_current]'s total.
final _currentShielded = BigInt.from(10);

SyncState _current({required bool private}) => SyncState(
  accountUuid: _accountUuid,
  hasAccountScopedData: true,
  transparentBalance: BigInt.from(5),
  transparentPendingBalance: BigInt.from(2),
  totalBalance: _currentShielded + BigInt.from(7),
  transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
  transparentPrivate: private,
  canShieldTransparentBalance: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _Api()));
  tearDownAll(RustLib.dispose);

  Future<SyncState> startFrom(
    SyncState initial, {
    bool privateQueries = false,
    int? latestTipHeight,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        enhancePirProvider.overrideWith(() => _EnhancePir(privateQueries)),
        syncProvider.overrideWith(() => _CarrySync(initial)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    container
        .read(syncProvider.notifier)
        .startSync(latestTipHeight: latestTipHeight);
    final started = container.read(syncProvider).requireValue;
    expect(started.isSyncing, isTrue);
    return started;
  }

  test('a sync start that moves the known tip demotes a carried private '
      'current balance', () async {
    // `_current` was read at tip 0; the polled tip is 12.
    final started = await startFrom(
      _current(private: true),
      latestTipHeight: 12,
    );
    expect(started.chainTipHeight, 12);

    expect(
      started.transparentAuthority,
      rust_sync.TransparentBalanceAuthority.lastKnown,
    );
    expect(started.transparentLastKnownBalance, BigInt.from(7));
    expect(started.transparentBalance, BigInt.zero);
    expect(started.transparentPendingBalance, BigInt.zero);
    expect(started.canShieldTransparentBalance, isFalse);
    expect(started.transparentPrivate, isTrue);
    expect(started.totalBalance, _currentShielded);
    expect(started.displayTotalBalance, _currentShielded);
  });

  // A sync start used to count as a tip crossing even when the tip had not
  // moved. Only a real move makes a privately read amount stale.
  test(
    'a sync start at an unchanged tip keeps a private current balance',
    () async {
      for (final tip in [null, 0]) {
        final started = await startFrom(
          _current(private: true),
          latestTipHeight: tip,
        );
        _expectCurrent(started);
        expect(started.totalBalance, _currentShielded + BigInt.from(7));
      }
    },
  );

  test('a tip move reported during the sync demotes a private current '
      'balance', () async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        enhancePirProvider.overrideWith(() => _EnhancePir(false)),
        syncProvider.overrideWith(
          () => _CarrySync(
            _current(private: true),
            walletDbPathResolver: () async => 'wallet.db',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    final notifier = container.read(syncProvider.notifier);

    // No move: the carried amount stays current.
    await notifier.handleSyncProgressForTesting(_scanning(tip: 0));
    _expectCurrent(container.read(syncProvider).requireValue);

    // The scan discovers a newer tip without reading a balance.
    await notifier.handleSyncProgressForTesting(_scanning(tip: 13));
    final moved = container.read(syncProvider).requireValue;
    expect(moved.chainTipHeight, 13);
    _expectDemoted(moved, shielded: _currentShielded);
  });

  group('an applied policy', () {
    Future<(ProviderContainer, _CarrySync)> mounted(SyncState initial) async {
      final sync = _CarrySync(initial)..countStarts = true;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_Accounts.new),
          enhancePirProvider.overrideWith(() => _EnhancePir(false)),
          syncProvider.overrideWith(() => sync),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      return (container, sync);
    }

    test('that makes the wallet private demotes a public amount right away '
        'and restarts sync', () async {
      final (container, sync) = await mounted(_current(private: false));
      _expectCurrent(container.read(syncProvider).requireValue);

      sync.adoptAppliedTransparentPolicy(
        _policy(rust_sync.ApiTransparentLedgerMode.privateRequired, 2),
      );

      _expectDemoted(
        container.read(syncProvider).requireValue,
        shielded: _currentShielded,
      );
      expect(sync.starts, 1);
      // While the wallet is private, a public read carried to a sync start
      // is stale even though the Dart setting is off.
      sync.replaceStateForTesting(_current(private: false));
      sync.countStarts = false;
      sync.startSync();
      _expectDemoted(
        container.read(syncProvider).requireValue,
        shielded: _currentShielded,
      );
    });

    test(
      'with a new generation demotes a private amount, and the cache',
      () async {
        final (container, sync) = await mounted(_current(private: true));
        // Cache account-1, then come back to it after the policy changed.
        final accounts = container.read(accountProvider.notifier) as _Accounts;
        accounts.activate(_otherAccountUuid);

        sync.adoptAppliedTransparentPolicy(
          _policy(rust_sync.ApiTransparentLedgerMode.public, 5),
        );
        accounts.activate(_accountUuid);

        _expectDemoted(
          container.read(syncProvider).requireValue,
          shielded: _currentShielded,
        );
      },
    );

    test(
      'nothing applied, or the same generation again, changes nothing',
      () async {
        final (container, sync) = await mounted(_current(private: true));
        sync.adoptAppliedTransparentPolicy(null);
        _expectCurrent(container.read(syncProvider).requireValue);

        sync.adoptAppliedTransparentPolicy(
          _policy(rust_sync.ApiTransparentLedgerMode.privateRequired, 2),
        );
        expect(sync.starts, 1);
        // Fresh reads replace the demoted state.
        sync.replaceStateForTesting(_current(private: true));
        sync.adoptAppliedTransparentPolicy(
          _policy(rust_sync.ApiTransparentLedgerMode.privateRequired, 2),
        );
        _expectCurrent(container.read(syncProvider).requireValue);
        expect(sync.starts, 1);
      },
    );
  });

  group('a successful toggle-off', () {
    test('tells Settings at once, before any balance read', () async {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrapWith(_publicSnapshot(private: true)),
          ),
          accountProvider.overrideWith(_Accounts.new),
          enhancePirProvider.overrideWith(() => _EnhancePir(false)),
          syncProvider.overrideWith(() => _LiveSync()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(pumpEventQueue);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      await pumpEventQueue();
      expect(container.read(walletTransparentPrivateProvider), isTrue);
      expect(container.read(privateQueriesControlEnabledProvider), isTrue);

      // The lowering applied; the wallet path never resolves, so no balance
      // is read, as while offline or waiting for Tor.
      container
          .read(syncProvider.notifier)
          .adoptAppliedTransparentPolicy(
            _policy(rust_sync.ApiTransparentLedgerMode.public, 5),
          );
      await pumpEventQueue();

      expect(
        container.read(syncProvider).requireValue.transparentPrivate,
        isFalse,
      );
      expect(container.read(walletTransparentPrivateProvider), isFalse);
      expect(container.read(privateQueriesControlEnabledProvider), isFalse);
      expect(container.read(privateQueriesTurnOffDisclosesProvider), isFalse);
    });

    test("clears a stopped account's reason, here and in the cache", () async {
      final stopped = SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        totalBalance: _currentShielded,
        transparentAuthority: rust_sync.TransparentBalanceAuthority.lastKnown,
        transparentLastKnownBalance: BigInt.from(7),
        transparentStop: rust_sync.TransparentStopReason.quarantined,
        transparentPrivate: true,
      );
      final sync = _CarrySync(stopped)..countStarts = true;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_Accounts.new),
          enhancePirProvider.overrideWith(() => _EnhancePir(false)),
          syncProvider.overrideWith(() => sync),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      void expectLowered(SyncState state) {
        expect(state.transparentPrivate, isFalse);
        expect(state.transparentStop, isNull);
        expect(
          state.transparentAuthority,
          rust_sync.TransparentBalanceAuthority.lastKnown,
        );
        expect(state.transparentLastKnownBalance, BigInt.from(7));
      }

      sync.adoptAppliedTransparentPolicy(
        _policy(rust_sync.ApiTransparentLedgerMode.public, 5),
      );
      expectLowered(container.read(syncProvider).requireValue);

      // Raising again marks the wallet private at once, and lowering once
      // more reaches an account cached in the meantime.
      sync.replaceStateForTesting(stopped);
      final accounts = container.read(accountProvider.notifier) as _Accounts;
      accounts.activate(_otherAccountUuid);
      sync.adoptAppliedTransparentPolicy(
        _policy(rust_sync.ApiTransparentLedgerMode.public, 7),
      );
      accounts.activate(_accountUuid);
      expectLowered(container.read(syncProvider).requireValue);

      sync.adoptAppliedTransparentPolicy(
        _policy(rust_sync.ApiTransparentLedgerMode.privateRequired, 8),
      );
      expect(
        container.read(syncProvider).requireValue.transparentPrivate,
        isTrue,
      );
    });
  });

  test('a sync start carries a public current balance unchanged', () async {
    final started = await startFrom(_current(private: false));

    expect(
      started.transparentAuthority,
      rust_sync.TransparentBalanceAuthority.current,
    );
    expect(started.transparentBalance, BigInt.from(5));
    expect(started.transparentPendingBalance, BigInt.from(2));
    expect(started.canShieldTransparentBalance, isTrue);
  });

  test('a sync start demotes a public current balance read before private '
      'queries raised the policy', () async {
    final started = await startFrom(
      _current(private: false),
      privateQueries: true,
    );

    expect(
      started.transparentAuthority,
      rust_sync.TransparentBalanceAuthority.lastKnown,
    );
    expect(started.transparentLastKnownBalance, BigInt.from(7));
    expect(started.transparentBalance, BigInt.zero);
    expect(started.transparentPendingBalance, BigInt.zero);
    expect(started.canShieldTransparentBalance, isFalse);
  });

  test('a sync start carries a public current balance when private queries '
      'cannot raise the policy', () async {
    final started = await startFrom(
      _current(private: false),
      privateQueries: false,
    );

    expect(
      started.transparentAuthority,
      rust_sync.TransparentBalanceAuthority.current,
    );
    expect(started.transparentBalance, BigInt.from(5));
    expect(started.canShieldTransparentBalance, isTrue);
  });

  test('a sync start keeps a stopped recovery and its reason', () async {
    final started = await startFrom(
      SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
        transparentLastKnownBalance: BigInt.from(9),
        transparentStop: rust_sync.TransparentStopReason.optOutUnfinished,
        transparentPrivate: true,
      ),
    );

    expect(
      started.transparentAuthority,
      rust_sync.TransparentBalanceAuthority.stopped,
    );
    expect(
      started.transparentStop,
      rust_sync.TransparentStopReason.optOutUnfinished,
    );
    expect(started.transparentLastKnownBalance, BigInt.from(9));
  });

  group('the carry rule', () {
    test('demotes only a current amount the carry can make stale', () {
      for (final (private, mayApply, crossesTip, demoted) in [
        (true, false, true, true),
        (true, true, true, true),
        (true, true, false, false),
        (false, true, false, true),
        (false, true, true, true),
        (false, false, true, false),
      ]) {
        final carried = _current(private: private).carryingTransparentAuthority(
          privatePolicyMayApply: mayApply,
          crossesTip: crossesTip,
        );
        if (demoted) {
          _expectDemoted(carried, shielded: _currentShielded);
        } else {
          _expectCurrent(carried);
          expect(carried.totalBalance, _currentShielded + BigInt.from(7));
        }
        expect(carried.transparentPrivate, private);
      }
    });

    test('demotes transparent funds a pending spend holds with the rest', () {
      for (final (spendable, pending, locked) in [(5, 2, 3), (0, 0, 4)]) {
        final transparent = spendable + pending + locked;
        final current = SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          transparentBalance: BigInt.from(spendable),
          transparentPendingBalance: BigInt.from(pending),
          transparentLockedBalance: BigInt.from(locked),
          totalBalance: _currentShielded + BigInt.from(transparent),
          transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
          canShieldTransparentBalance: true,
        );
        final carried = current.carryingTransparentAuthority(
          privatePolicyMayApply: false,
          crossesTip: false,
          policyChanged: true,
        );
        expect(
          carried.transparentAuthority,
          rust_sync.TransparentBalanceAuthority.lastKnown,
        );
        expect(carried.transparentLastKnownBalance, BigInt.from(transparent));
        expect(carried.transparentLockedBalance, BigInt.zero);
        expect(carried.totalBalance, _currentShielded);
        expect(carried.displayTotalBalance, _currentShielded);
      }
    });

    test('leaves an amount that is not current unchanged', () {
      final stopped = SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
        transparentLastKnownBalance: BigInt.from(9),
        transparentStop: rust_sync.TransparentStopReason.optOutUnfinished,
        transparentPrivate: true,
      );
      expect(
        stopped.carryingTransparentAuthority(
          privatePolicyMayApply: true,
          crossesTip: true,
        ),
        same(stopped),
      );
    });
  });

  group('with the production build', () {
    ProviderContainer containerFor({required bool privateQueries}) {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrapWith(_publicSnapshot()),
          ),
          accountProvider.overrideWith(_Accounts.new),
          enhancePirProvider.overrideWith(() => _EnhancePir(privateQueries)),
          syncProvider.overrideWith(() => _LiveSync()),
        ],
      );
      addTearDown(container.dispose);
      // The build defers its initial sync start; let it run while mounted.
      addTearDown(pumpEventQueue);
      container.listen(syncProvider, (_, _) {});
      return container;
    }

    test(
      'a startup read before startup lowered the policy is not current',
      () async {
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrapWith(_publicSnapshot()),
            ),
            accountProvider.overrideWith(_Accounts.new),
            enhancePirProvider.overrideWith(() => _EnhancePir(false)),
            transparentPolicyStartupProvider.overrideWithValue(
              TransparentPolicyStartup(
                appliedPolicy: _policy(
                  rust_sync.ApiTransparentLedgerMode.public,
                  7,
                ),
              ),
            ),
            syncProvider.overrideWith(() => _LiveSync()),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(pumpEventQueue);
        container.listen(syncProvider, (_, _) {});
        _expectDemoted(
          await container.read(syncProvider.future),
          shielded: BigInt.zero,
        );
      },
    );

    test(
      'a no-op startup reconciliation demotes a snapshot without its generation',
      () async {
        for (final mode in rust_sync.ApiTransparentLedgerMode.values) {
          final container = ProviderContainer(
            overrides: [
              appBootstrapProvider.overrideWithValue(
                _bootstrapWith(_publicSnapshot(private: true)),
              ),
              accountProvider.overrideWith(_Accounts.new),
              enhancePirProvider.overrideWith(() => _EnhancePir(false)),
              transparentPolicyStartupProvider.overrideWithValue(
                TransparentPolicyStartup(
                  appliedPolicy: rust_sync.ApiAppliedTransparentPolicy(
                    mode: mode,
                    generation: BigInt.from(9),
                  ),
                ),
              ),
              syncProvider.overrideWith(() => _LiveSync()),
            ],
          );
          addTearDown(container.dispose);
          addTearDown(pumpEventQueue);
          container.listen(syncProvider, (_, _) {});
          _expectDemoted(
            await container.read(syncProvider.future),
            shielded: BigInt.zero,
          );
        }
      },
    );

    test('a startup that finished an opt-out applies the public policy to '
        'the snapshot read before it', () async {
      for (final mode in rust_sync.ApiTransparentLedgerMode.values) {
        final private =
            mode == rust_sync.ApiTransparentLedgerMode.privateRequired;
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrapWith(
                _stoppedSnapshot(rust_sync.TransparentStopReason.optOutUnfinished),
              ),
            ),
            accountProvider.overrideWith(_Accounts.new),
            enhancePirProvider.overrideWith(() => _EnhancePir(false)),
            transparentPolicyStartupProvider.overrideWithValue(
              TransparentPolicyStartup(appliedPolicy: _policy(mode, 3)),
            ),
            syncProvider.overrideWith(() => _LiveSync()),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(pumpEventQueue);
        container.listen(syncProvider, (_, _) {});
        final initial = await container.read(syncProvider.future);
        await pumpEventQueue();

        expect(initial.transparentPrivate, private, reason: '$mode');
        // A public policy stops no account; a private one keeps its reason.
        expect(
          initial.transparentStop,
          private ? rust_sync.TransparentStopReason.optOutUnfinished : null,
          reason: '$mode',
        );
        // The amount still waits for a fresh read either way.
        expect(
          initial.transparentAuthority,
          rust_sync.TransparentBalanceAuthority.stopped,
        );
        expect(initial.transparentLastKnownBalance, BigInt.from(7));
        // The single toggle stays on only while the opt-out is unfinished.
        expect(container.read(walletTransparentPrivateProvider), private);
        expect(container.read(privateQueriesControlEnabledProvider), private);
      }
    });

    test(
      'a startup that reported no policy keeps the snapshot policy',
      () async {
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrapWith(
                _stoppedSnapshot(rust_sync.TransparentStopReason.optOutUnfinished),
              ),
            ),
            accountProvider.overrideWith(_Accounts.new),
            enhancePirProvider.overrideWith(() => _EnhancePir(false)),
            syncProvider.overrideWith(() => _LiveSync()),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(pumpEventQueue);
        container.listen(syncProvider, (_, _) {});
        final initial = await container.read(syncProvider.future);
        expect(initial.transparentPrivate, isTrue);
        expect(
          initial.transparentStop,
          rust_sync.TransparentStopReason.optOutUnfinished,
        );
      },
    );

    test('a startup read keeps or demotes its locked transparent amount '
        'with the rest', () async {
      for (final privateQueries in [false, true]) {
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrapWith(_publicSnapshot(locked: BigInt.from(3))),
            ),
            accountProvider.overrideWith(_Accounts.new),
            enhancePirProvider.overrideWith(() => _EnhancePir(privateQueries)),
            syncProvider.overrideWith(() => _LiveSync()),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(pumpEventQueue);
        container.listen(syncProvider, (_, _) {});
        final initial = await container.read(syncProvider.future);
        if (privateQueries) {
          expect(initial.transparentLastKnownBalance, BigInt.from(10));
          expect(initial.transparentLockedBalance, BigInt.zero);
          expect(initial.totalBalance, BigInt.zero);
        } else {
          _expectCurrent(initial);
          expect(initial.transparentLockedBalance, BigInt.from(3));
          expect(initial.totalBalance, BigInt.from(10));
        }
      }
    });

    test('publishes whether the wallet reads transparent privately', () async {
      for (final private in [false, true]) {
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrapWith(_publicSnapshot(private: private)),
            ),
            accountProvider.overrideWith(_Accounts.new),
            enhancePirProvider.overrideWith(() => _EnhancePir(false)),
            syncProvider.overrideWith(() => _LiveSync()),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(pumpEventQueue);
        container.listen(syncProvider, (_, _) {});
        await container.read(syncProvider.future);
        await pumpEventQueue();
        expect(container.read(walletTransparentPrivateProvider), private);
        // The single toggle stays on until the private wallet is lowered.
        expect(container.read(privateQueriesControlEnabledProvider), private);
      }
    });

    test('a startup read before the policy raise is not current', () async {
      final container = containerFor(privateQueries: true);
      // The snapshot's whole total is transparent.
      _expectDemoted(
        await container.read(syncProvider.future),
        shielded: BigInt.zero,
      );
    });

    test(
      'a startup read stays current when nothing raises the policy',
      () async {
        final container = containerFor(privateQueries: false);
        _expectCurrent(await container.read(syncProvider.future));
      },
    );

    test('switching back after a policy raise on another account demotes '
        'the cached amount', () async {
      final container = containerFor(privateQueries: false);
      _expectCurrent(await container.read(syncProvider.future));
      final accounts = container.read(accountProvider.notifier) as _Accounts;

      accounts.activate(_otherAccountUuid);
      (container.read(enhancePirProvider.notifier) as _EnhancePir).raise();
      accounts.activate(_accountUuid);

      final restored = container.read(syncProvider).requireValue;
      expect(restored.accountUuid, _accountUuid);
      _expectDemoted(restored, shielded: BigInt.zero);
    });

    test('switching back keeps a cached amount current when nothing '
        'changed', () async {
      final container = containerFor(privateQueries: false);
      await container.read(syncProvider.future);
      final accounts = container.read(accountProvider.notifier) as _Accounts;

      accounts.activate(_otherAccountUuid);
      accounts.activate(_accountUuid);

      _expectCurrent(container.read(syncProvider).requireValue);
    });
  });
}
