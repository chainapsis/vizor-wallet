import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_address_wait_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart';

class _NearSwapPrivacy extends NearSwapPrivacyNotifier {
  @override
  bool build() => true;
}

class _Sync extends SyncNotifier {
  _Sync(this.initial);

  final SyncState initial;

  @override
  Future<SyncState> build() async => initial;

  /// Publishes a completed sync.
  void complete() =>
      state = AsyncData(SyncState(lastSyncCompletedAt: DateTime.now()));
}

/// Two accounts, `account-a` active until [select] picks another.
class _Accounts extends AccountNotifier {
  @override
  AccountState build() => _accounts('account-a');

  /// Makes `uuid` the active account.
  void select(String uuid) => state = AsyncData(_accounts(uuid));

  static AccountState _accounts(String active) => AccountState(
    accounts: const [
      AccountInfo(uuid: 'account-a', name: 'A', order: 0),
      AccountInfo(uuid: 'account-b', name: 'B', order: 1),
    ],
    activeAccountUuid: active,
  );
}

const _ready = SwapAccountReadiness(
  seedWalk: false,
  lookups: false,
  awaitingAdmission: false,
);

const _restoring = SwapAccountReadiness(
  seedWalk: true,
  lookups: false,
  awaitingAdmission: false,
);

void main() {
  group('swapRefundAddressNeedsSync', () {
    bool needsSync({required int tip, int scanned = 0, int? pendingStart}) =>
        swapRefundAddressNeedsSync(
          chainTipHeight: tip,
          scannedHeight: scanned,
          pendingScanStartHeight: pendingStart,
        );

    test('waits once the fully scanned height is over 1 block behind', () {
      expect(needsSync(tip: 1000, scanned: 1000), isFalse);
      expect(needsSync(tip: 1000, scanned: 999), isFalse);
      expect(needsSync(tip: 1000, scanned: 998), isTrue);
    });

    test('an unscanned range ends the fully scanned height before it', () {
      // Scanned to the tip, but an earlier range is still pending.
      expect(needsSync(tip: 1000, scanned: 1000, pendingStart: 900), isTrue);
      expect(needsSync(tip: 1000, scanned: 1000, pendingStart: 1000), isFalse);
      expect(needsSync(tip: 1000, scanned: 1000, pendingStart: 999), isTrue);
    });

    test('an unknown tip never waits', () {
      expect(needsSync(tip: 0, scanned: 0), isFalse);
    });
  });

  group('swapAddressHistoryPendingProvider', () {
    ProviderContainer container(
      Future<SwapAccountReadiness?> Function(String account) readiness,
    ) {
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_Accounts.new),
          swapAccountReadinessReaderProvider.overrideWithValue(readiness),
          nearSwapPrivacyProvider.overrideWith(_NearSwapPrivacy.new),
          syncProvider.overrideWith(() => _Sync(SyncState())),
        ],
      );
      addTearDown(container.dispose);
      container.listen(swapAddressHistoryPendingProvider, (_, _) {});
      return container;
    }

    Future<void> select(ProviderContainer c, String account) async {
      (c.read(accountProvider.notifier) as _Accounts).select(account);
      await pumpEventQueue();
    }

    test("holds quotes while the account's seed walk runs", () async {
      var readiness = _restoring;
      final c = container((_) async => readiness);
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);

      readiness = _ready;
      c.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });

    test("another account's recovery does not hold a ready account", () async {
      final c = container(
        (account) async => account == 'account-b' ? _restoring : _ready,
      );
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);

      await select(c, 'account-b');
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);

      await select(c, 'account-a');
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });

    test('a refused quote stays with its account', () async {
      final c = container((_) async => _ready);
      await pumpEventQueue();
      c
          .read(swapAddressHistoryPendingProvider.notifier)
          .quoteRefused('account-a');
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);

      await select(c, 'account-b');
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
      // A late refusal for the account left behind is ignored.
      c
          .read(swapAddressHistoryPendingProvider.notifier)
          .quoteRefused('account-a');
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });

    test('a failed round lets a press show the reason', () async {
      final c = container((_) async => _restoring);
      await pumpEventQueue();
      c.read(swapRecoveryRoundFailedProvider.notifier).set(true);
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);

      c.read(swapRecoveryRoundFailedProvider.notifier).set(false);
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);
    });

    test('a read the wallet refuses keeps the last answer', () async {
      var busy = false;
      final c = container((_) async {
        if (busy) throw StateError('wallet busy');
        return _restoring;
      });
      await pumpEventQueue();
      busy = true;
      c.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);
    });

    test('a refused quote waits for the next round', () async {
      final c = container((_) async => _ready);
      await pumpEventQueue();
      c
          .read(swapAddressHistoryPendingProvider.notifier)
          .quoteRefused('account-a');
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);

      c.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });

    test('a refused quote is rechecked once filters catch up', () async {
      final c = container((_) async => _ready);
      await pumpEventQueue();
      final pending = c.read(swapAddressHistoryPendingProvider.notifier);
      pending.quoteRefused('account-a');
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);

      // A filter step advanced the marker, and no round ran.
      c.read(swapFilterStepsProvider.notifier).ended();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);

      pending.quoteRefused('account-a');
      expect(c.read(swapAddressHistoryPendingProvider), isTrue);
      (c.read(syncProvider.notifier) as _Sync).complete();
      await pumpEventQueue();
      expect(c.read(swapAddressHistoryPendingProvider), isFalse);
    });
  });

  group('swapAddressWaitProvider', () {
    ProviderContainer container({bool oneTime = true, SyncState? sync}) {
      final container = ProviderContainer(
        overrides: [
          swapUsesOneTimeAddressProvider.overrideWithValue(oneTime),
          accountProvider.overrideWith(_Accounts.new),
          swapAccountReadinessReaderProvider.overrideWithValue(
            (_) async => _restoring,
          ),
          nearSwapPrivacyProvider.overrideWith(_NearSwapPrivacy.new),
          syncProvider.overrideWith(() => _Sync(sync ?? SyncState())),
        ],
      );
      addTearDown(container.dispose);
      container.listen(swapAddressWaitProvider(false), (_, _) {});
      container.listen(swapAddressWaitProvider(true), (_, _) {});
      return container;
    }

    test('a ZEC payout waits for its address to be prepared', () async {
      final c = container();
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(false)), SwapAddressWait.preparing);
    });

    test('a payout whose round waits for a server asks for one', () async {
      final c = container();
      await pumpEventQueue();
      c.read(swapRecoveryNeedsServerProvider.notifier).set(true);
      expect(c.read(swapAddressWaitProvider(false)), SwapAddressWait.server);
      expect(swapAddressWaitLabel(SwapAddressWait.server), 'Choose a server');

      c.read(swapRecoveryNeedsServerProvider.notifier).set(false);
      expect(c.read(swapAddressWaitProvider(false)), SwapAddressWait.preparing);
    });

    test('a ZEC refund address waits for sync', () async {
      final c = container(
        sync: SyncState(chainTipHeight: 1000, scannedHeight: 900),
      );
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(true)), SwapAddressWait.sync);
    });

    test('a synced refund address does not wait', () async {
      final c = container(
        sync: SyncState(chainTipHeight: 1000, scannedHeight: 1000),
      );
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(true)), isNull);
    });

    test('regular addresses never wait', () async {
      final c = container(
        oneTime: false,
        sync: SyncState(chainTipHeight: 1000, scannedHeight: 900),
      );
      await pumpEventQueue();
      expect(c.read(swapAddressWaitProvider(false)), isNull);
      expect(c.read(swapAddressWaitProvider(true)), isNull);
    });
  });
}
