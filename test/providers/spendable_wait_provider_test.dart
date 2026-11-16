import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';
import 'package:zcash_wallet/src/core/zcash/spendable_wait.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/block_spacing_provider.dart';
import 'package:zcash_wallet/src/providers/spendable_wait_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

const _account = 'account-1';
const _tip = 1000;
final _zec = BigInt.from(100000000);

void main() {
  ProviderContainer container(SyncState state) {
    final container = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(() => _SyncNotifier(state)),
        blockSpacingProvider.overrideWithValue(
          const BlockSpacing(
            preNu7BlockSeconds: 75,
            nu7BlockSeconds: 25,
            nu7ActivationHeight: 1,
          ),
        ),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  SyncState settled({
    bool syncComplete = true,
    bool isSyncing = false,
    bool startedFromCompletedSync = false,
    int? chainTipHeight,
    int scannedHeight = _tip,
    SpendableBalanceFreshness freshness =
        SpendableBalanceFreshness.authoritative,
    SyncFailure? failure,
  }) => SyncState(
    isSyncing: isSyncing,
    startedFromCompletedSync: startedFromCompletedSync,
    displaySpendableFreshness: freshness,
    failure: failure,
    accountUuid: _account,
    hasAccountScopedData: true,
    isSyncComplete: syncComplete,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight ?? _tip,
    spendableBalance: _zec,
    orchardPendingBalance: _zec,
    valuePendingSpendability: _zec,
    recentTransactions: [_received(minedHeight: _tip)],
  );

  test('a settled balance with a confirming receipt states its wait', () async {
    final c = container(settled());
    await c.read(syncProvider.future);
    final sub = c.listen(spendableWaitProvider(_account), (_, _) {});
    addTearDown(sub.close);

    final wait = sub.read()!;
    expect(wait.availableNow, _zec);
    expect(wait.receivedWaiting, _zec);
    expect(wait.wait, const AvailableIn.minutes(1, 3));

    final clock = c.listen(
      receivedSpendableWaitClockProvider(_account),
      (_, _) {},
    );
    addTearDown(clock.close);
    expect(clock.read()?.tipHeight, _tip);
  });

  test('the wait holds through the catch-up each new block starts', () async {
    final notifier = _SyncNotifier(settled());
    final c = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(() => notifier),
        blockSpacingProvider.overrideWithValue(
          const BlockSpacing(
            preNu7BlockSeconds: 75,
            nu7BlockSeconds: 25,
            nu7ActivationHeight: 1,
          ),
        ),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(syncProvider.future);
    final seen = <SpendableWait?>[];
    final sub = c.listen(
      spendableWaitProvider(_account),
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    addTearDown(sub.close);
    final clock = c.listen(
      receivedSpendableWaitClockProvider(_account),
      (_, _) {},
    );
    addTearDown(clock.close);

    // A new block: the tip moves first, then the sync restarts on the last
    // completed balance, then it settles one block higher.
    notifier.set(settled(chainTipHeight: _tip + 1));
    await c.pump();
    expect(sub.read()?.receivedWait, const AvailableIn.minutes(1, 2));

    notifier.set(
      settled(
        syncComplete: false,
        isSyncing: true,
        startedFromCompletedSync: true,
        chainTipHeight: _tip + 1,
        freshness: SpendableBalanceFreshness.lastCompletedSync,
      ),
    );
    await c.pump();
    expect(sub.read()?.receivedWait, const AvailableIn.minutes(1, 2));
    expect(clock.read()?.catchingUp, isTrue);
    expect(clock.read()?.tipHeight, _tip + 1);

    notifier.set(settled(chainTipHeight: _tip + 1, scannedHeight: _tip + 1));
    await c.pump();
    expect(sub.read()?.receivedWait, const AvailableIn.minutes(1, 2));
    expect(clock.read()?.catchingUp, isFalse);
    expect(seen, everyElement(isNotNull));
  });

  test('a first scan or a failed sync states nothing', () async {
    final scanning = container(
      settled(
        syncComplete: false,
        isSyncing: true,
        freshness: SpendableBalanceFreshness.lastCompletedSync,
      ),
    );
    await scanning.read(syncProvider.future);
    final scanningSub = scanning.listen(
      spendableWaitProvider(_account),
      (_, _) {},
    );
    addTearDown(scanningSub.close);
    expect(scanningSub.read(), isNull);
  });

  test('a balance still syncing states nothing', () async {
    final c = container(settled(syncComplete: false));
    await c.read(syncProvider.future);
    final sub = c.listen(spendableWaitProvider(_account), (_, _) {});
    addTearDown(sub.close);

    expect(sub.read(), isNull);
  });

  test('another account reads no wait from this balance', () async {
    final c = container(settled());
    await c.read(syncProvider.future);
    final sub = c.listen(spendableWaitProvider('account-2'), (_, _) {});
    addTearDown(sub.close);

    expect(sub.read(), isNull);
  });
}

class _SyncNotifier extends SyncNotifier {
  _SyncNotifier(this._state);

  final SyncState _state;

  @override
  Future<SyncState> build() async => _state;

  void set(SyncState next) => state = AsyncData(next);
}

rust_sync.TransactionInfo _received({required int minedHeight}) {
  return rust_sync.TransactionInfo(
    txidHex: 'received',
    minedHeight: BigInt.from(minedHeight),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    feeState: rust_sync.TransactionFeeState.notApplicable,
    detailsComplete: true,
    provisional: false,
    amountIncludesFee: false,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'received',
    displayAmount: _zec,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
