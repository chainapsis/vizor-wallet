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

  SyncState state({
    SyncFailure? failure,
    List<rust_sync.PendingSpendableEntry>? pendingSpendable,
  }) => SyncState(
    failure: failure,
    accountUuid: _account,
    hasAccountScopedData: true,
    isSyncComplete: true,
    scannedHeight: _tip,
    chainTipHeight: _tip,
    spendableBalance: _zec,
    orchardPendingBalance: _zec,
    pendingSpendable:
        pendingSpendable ??
        [
          rust_sync.PendingSpendableEntry(
            txidHex: 'received',
            isChange: false,
            value: _zec,
            blocksUntilSpendable: 5,
            confirmations: 1,
          ),
        ],
  );

  test('a balance with a confirming receipt states its wait', () async {
    final c = container(state());
    await c.read(syncProvider.future);
    final sub = c.listen(spendableWaitProvider(_account), (_, _) {});
    addTearDown(sub.close);

    final wait = sub.read()!;
    expect(wait.availableNow, _zec);
    expect(wait.receivedWaiting, _zec);
    expect(wait.wait, const AvailableIn.minutes(1, 3));

    final receipts = c.listen(
      receivedSpendableWaitsProvider(_account),
      (_, _) {},
    );
    addTearDown(receipts.close);
    expect(receipts.read()['received']?.confirmations, 1);
    expect(receipts.read()['received']?.requiredConfirmations, 6);
  });

  test('pending value the wallet lists no wait for is not waiting', () async {
    final c = container(state(pendingSpendable: const []));
    await c.read(syncProvider.future);
    final sub = c.listen(spendableWaitProvider(_account), (_, _) {});
    addTearDown(sub.close);

    expect(sub.read()!.hasWait, isFalse);
    expect(sub.read()!.total, _zec);
  });

  test('a failed sync states nothing', () async {
    final c = container(
      state(
        failure: const SyncFailure(
          kind: SyncFailureKind.network,
          rawMessage: 'offline',
        ),
      ),
    );
    await c.read(syncProvider.future);
    final sub = c.listen(spendableWaitProvider(_account), (_, _) {});
    addTearDown(sub.close);
    final receipts = c.listen(
      receivedSpendableWaitsProvider(_account),
      (_, _) {},
    );
    addTearDown(receipts.close);

    expect(sub.read(), isNull);
    expect(receipts.read(), isEmpty);
  });

  test('another account reads no wait from this balance', () async {
    final c = container(state());
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
}
