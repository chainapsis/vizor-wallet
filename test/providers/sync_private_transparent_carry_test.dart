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
const _otherAccountUuid = 'account-2';

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

/// The production [SyncNotifier], built from the bootstrap snapshot unless
/// [initial] is given. Its syncs never resolve the wallet path, so a start
/// publishes its starting state and goes no further.
class _Sync extends SyncNotifier {
  _Sync(this.initial)
    : super(walletDbPathResolver: () => Completer<String>().future);

  final SyncState? initial;

  /// Counts starts instead of running them.
  bool countStarts = false;
  int starts = 0;

  void replaceStateForTesting(SyncState next) => state = AsyncData(next);

  @override
  Future<SyncState> build() async => initial ?? await super.build();

  @override
  void startSync({int? latestTipHeight}) {
    if (!countStarts) return super.startSync(latestTipHeight: latestTipHeight);
    starts++;
  }
}

class _EnhancePir extends EnhancePirNotifier {
  _EnhancePir(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;

  /// Turns private queries on, as a successful raise does.
  void raise() => state = true;
}

rust_sync.ApiAppliedTransparentPolicy _policy(
  rust_sync.ApiTransparentLedgerMode mode,
  int generation,
) => rust_sync.ApiAppliedTransparentPolicy(
  mode: mode,
  generation: BigInt.from(generation),
);

/// A current startup read of `account-1`, all of it transparent.
AppSyncSnapshot _snapshot({required bool private}) => AppSyncSnapshot(
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
  saplingPendingBalance: BigInt.zero,
  orchardPendingBalance: BigInt.zero,
  ironwoodPendingBalance: BigInt.zero,
  canShieldTransparentBalance: true,
  shieldTransparentFee: BigInt.zero,
  shieldTransparentAmount: BigInt.zero,
  spendableBalance: BigInt.zero,
  totalBalance: BigInt.from(7),
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

  Future<(ProviderContainer, _Sync)> mount({
    SyncState? initial,
    bool privateSnapshot = false,
    bool privateQueries = false,
    rust_sync.ApiAppliedTransparentPolicy? startupApplied,
  }) async {
    final sync = _Sync(initial);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/home',
            initialAccountState: const AccountState(),
            initialSyncSnapshot: _snapshot(private: privateSnapshot),
            network: AppBootstrapState.empty.network,
            rpcEndpointConfig: AppBootstrapState.empty.rpcEndpointConfig,
            themeMode: AppBootstrapState.empty.themeMode,
            privacyModeEnabled: false,
            isPasswordConfigured: false,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        accountProvider.overrideWith(_Accounts.new),
        enhancePirProvider.overrideWith(() => _EnhancePir(privateQueries)),
        if (startupApplied != null)
          transparentPolicyStartupProvider.overrideWithValue(
            TransparentPolicyStartup(appliedPolicy: startupApplied),
          ),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(container.dispose);
    // The production build defers its initial sync start; let it run while
    // mounted.
    addTearDown(pumpEventQueue);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    return (container, sync);
  }

  group('the carry rule', () {
    test('demotes a private amount always, a public one only when a private '
        'policy may apply, and either when the policy changed', () {
      for (final (private, mayApply, policyChanged, demoted) in [
        (true, false, false, true),
        (false, true, false, true),
        (false, false, false, false),
        (false, false, true, true),
        (true, false, true, true),
      ]) {
        final carried = _current(private: private).carryingTransparentAuthority(
          privatePolicyMayApply: mayApply,
          policyChanged: policyChanged,
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

    test('leaves an amount that is not current unchanged', () {
      for (final authority in [
        rust_sync.TransparentBalanceAuthority.lastKnown,
        rust_sync.TransparentBalanceAuthority.stopped,
      ]) {
        final notCurrent = SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          transparentAuthority: authority,
          transparentLastKnownBalance: BigInt.from(9),
          transparentPrivate: true,
        );
        expect(
          notCurrent.carryingTransparentAuthority(
            privatePolicyMayApply: true,
            policyChanged: true,
          ),
          same(notCurrent),
        );
      }
    });
  });

  test('a sync start demotes a private current amount, and a public one '
      'only when private queries may raise the policy', () async {
    for (final (private, queries, demoted) in [
      (true, false, true),
      (false, false, false),
      (false, true, true),
    ]) {
      final (container, sync) = await mount(
        initial: _current(private: private),
        privateQueries: queries,
      );
      sync.startSync();
      final started = container.read(syncProvider).requireValue;
      expect(started.isSyncing, isTrue);
      if (demoted) {
        _expectDemoted(started, shielded: _currentShielded);
      } else {
        _expectCurrent(started);
      }
      expect(started.transparentPrivate, private);
    }
  });

  group('an applied policy', () {
    test('that makes the wallet private demotes a public amount right away '
        'and restarts sync, once per generation', () async {
      final (container, sync) = await mount(initial: _current(private: false));
      sync.countStarts = true;
      // Nothing applied changes nothing.
      sync.adoptAppliedTransparentPolicy(null);
      _expectCurrent(container.read(syncProvider).requireValue);

      final applied = _policy(
        rust_sync.ApiTransparentLedgerMode.privateRequired,
        2,
      );
      sync.adoptAppliedTransparentPolicy(applied);
      _expectDemoted(
        container.read(syncProvider).requireValue,
        shielded: _currentShielded,
      );
      expect(sync.starts, 1);

      // Fresh reads replaced the demoted state; the same generation again
      // changes nothing.
      sync.replaceStateForTesting(_current(private: false));
      sync.adoptAppliedTransparentPolicy(applied);
      _expectCurrent(container.read(syncProvider).requireValue);
      expect(sync.starts, 1);

      // While the wallet is private, a public read carried to a sync start
      // is stale even though the Dart setting is off.
      sync.countStarts = false;
      sync.startSync();
      _expectDemoted(
        container.read(syncProvider).requireValue,
        shielded: _currentShielded,
      );
    });

    test('with a new generation demotes a cached public amount', () async {
      final (container, sync) = await mount(initial: _current(private: false));
      sync.countStarts = true;
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
    });
  });

  group('a startup read', () {
    test(
      'is demoted when private, or when a private policy may apply',
      () async {
        for (final (private, queries, demoted) in [
          (true, false, true),
          (false, true, true),
          (false, false, false),
        ]) {
          final (container, _) = await mount(
            privateSnapshot: private,
            privateQueries: queries,
          );
          final built = container.read(syncProvider).requireValue;
          if (demoted) {
            // The snapshot's whole total is transparent.
            _expectDemoted(built, shielded: BigInt.zero);
          } else {
            _expectCurrent(built);
          }
        }
      },
    );

    test('is demoted by a startup reconciliation, which may find a '
        'generation set after the read', () async {
      for (final mode in rust_sync.ApiTransparentLedgerMode.values) {
        final (container, _) = await mount(startupApplied: _policy(mode, 9));
        _expectDemoted(
          container.read(syncProvider).requireValue,
          shielded: BigInt.zero,
        );
      }
    });

    test('publishes whether the wallet reads transparent privately', () async {
      for (final private in [false, true]) {
        final (container, _) = await mount(privateSnapshot: private);
        await pumpEventQueue();
        expect(container.read(walletTransparentPrivateProvider), private);
        // Settings offers to lower a private wallet with private queries off.
        expect(container.read(transparentOptOutActionProvider), private);
      }
    });
  });

  test('switching back demotes a cached public amount only after a policy '
      'raise on another account', () async {
    for (final raise in [false, true]) {
      final (container, _) = await mount();
      _expectCurrent(container.read(syncProvider).requireValue);
      final accounts = container.read(accountProvider.notifier) as _Accounts;

      accounts.activate(_otherAccountUuid);
      if (raise) {
        (container.read(enhancePirProvider.notifier) as _EnhancePir).raise();
      }
      accounts.activate(_accountUuid);

      final restored = container.read(syncProvider).requireValue;
      expect(restored.accountUuid, _accountUuid);
      if (raise) {
        _expectDemoted(restored, shielded: BigInt.zero);
      } else {
        _expectCurrent(restored);
      }
    }
  });
}
