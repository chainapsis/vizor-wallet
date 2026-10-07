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
  _CarrySync(this.initial, {required super.privateTransparentRecovery})
    : super(walletDbPathResolver: () => Completer<String>().future);

  final SyncState initial;

  @override
  Future<SyncState> build() async => initial;
}

class _EnhancePir extends EnhancePirNotifier {
  _EnhancePir(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;
}

SyncState _current({required bool private}) => SyncState(
  accountUuid: _accountUuid,
  hasAccountScopedData: true,
  transparentBalance: BigInt.from(5),
  transparentPendingBalance: BigInt.from(2),
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
    bool privateTransparentRecovery = false,
    bool privateQueries = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        enhancePirProvider.overrideWith(() => _EnhancePir(privateQueries)),
        syncProvider.overrideWith(
          () => _CarrySync(
            initial,
            privateTransparentRecovery: privateTransparentRecovery,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    container.read(syncProvider.notifier).startSync();
    final started = container.read(syncProvider).requireValue;
    expect(started.isSyncing, isTrue);
    return started;
  }

  test('a sync start demotes a carried private current balance', () async {
    final started = await startFrom(_current(private: true));

    expect(
      started.transparentAuthority,
      rust_sync.TransparentBalanceAuthority.lastKnown,
    );
    expect(started.transparentLastKnownBalance, BigInt.from(7));
    expect(started.transparentBalance, BigInt.zero);
    expect(started.transparentPendingBalance, BigInt.zero);
    expect(started.canShieldTransparentBalance, isFalse);
    expect(started.transparentPrivate, isTrue);
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
      privateTransparentRecovery: true,
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
    for (final (flag, queries) in [(false, true), (true, false)]) {
      final started = await startFrom(
        _current(private: false),
        privateTransparentRecovery: flag,
        privateQueries: queries,
      );

      expect(
        started.transparentAuthority,
        rust_sync.TransparentBalanceAuthority.current,
      );
      expect(started.transparentBalance, BigInt.from(5));
      expect(started.canShieldTransparentBalance, isTrue);
    }
  });

  test('a sync start keeps a stopped recovery and its reason', () async {
    final started = await startFrom(
      SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
        transparentLastKnownBalance: BigInt.from(9),
        transparentStop: rust_sync.TransparentStopReason.notSelected,
        transparentPrivate: true,
      ),
    );

    expect(
      started.transparentAuthority,
      rust_sync.TransparentBalanceAuthority.stopped,
    );
    expect(
      started.transparentStop,
      rust_sync.TransparentStopReason.notSelected,
    );
    expect(started.transparentLastKnownBalance, BigInt.from(9));
  });
}
