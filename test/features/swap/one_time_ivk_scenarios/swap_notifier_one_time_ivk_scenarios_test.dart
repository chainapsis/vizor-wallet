// Scenario tests for the swap composer's use of one-time swap addresses: the
// update stop, the per-account review address cache, the privacy setting's
// effect on open and new swaps, and hardware accounts. They drive
// `SwapNotifier` through a ProviderContainer with the production reservation
// and staging address services, without widgets or Rust.
import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_tracker.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_receive_reservation_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart' as api;

const _first = 'account-1';
const _second = 'account-2';
const _hardware = 'keystone-1';
const _recipient = '0x52908400098527886e0f7030069857d2e4169ee7';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// An outdated receiver service is not something a retry fixes, so the
  /// quote stops at once with the update message.
  test(
    'an upgrade-required reservation asks for an update without retrying',
    () async {
      final h = await _Harness.create(
        reserve: (_) async => throw const api.ReceiveError(
          message:
              'Update Vizor to keep checking private swap addresses. '
              'Your saved progress is kept.',
          kind: api.ReceiveErrorKind.upgradeRequired,
        ),
      );
      await h.review('25');
      expect(h.reservations, 1);
      expect(h.sync.awaited, 0);
      expect(h.state.quoteError, kSwapRecoveryUpdateMessage);
    },
  );

  /// Each account keeps its own reserved address, and switching back to an
  /// account quotes its address again rather than reserving another.
  test('reserved addresses are kept per account across switches', () async {
    final h = await _Harness.create();
    await h.review('25');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-1');
    await h.switchTo(_second);
    await h.review('26');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_second-2');
    await h.switchTo(_first);
    await h.review('27');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-1');
    expect(h.reservations, 2);
  });

  /// Turning one-time swap addresses off while a private swap is open still
  /// polls the open swap, and its statuses still reach the wallet, which
  /// needs them to settle or release its address. New quotes use an ordinary
  /// address and reserve nothing until the setting is back on.
  test('turning off with a private swap open keeps polling it and quotes an '
      'ordinary address', () async {
    final open = _privateIncomingSwap(
      'open',
      deadline: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final h = await _Harness.create(
      intents: [open],
      providerStatus: SwapIntentStatus.awaitingExternalDeposit,
    );
    await h.review('25');
    expect(h.state.reviewVisible, isTrue);
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-1');

    await h.privacy(false);
    h.recorded.clear();
    h.provider.statusRequests.clear();
    await h.notifier.refreshOpenIntentStatuses();
    await pumpEventQueue();
    expect(h.provider.statusRequests, contains(open.depositAddress));
    expect(h.recorded, [SwapIntentStatus.awaitingExternalDeposit]);

    await h.review('26');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1ordinary-$_first');
    expect(h.reservations, 1, reason: 'nothing is reserved while off');
    expect(h.ordinary, [_first], reason: 'the ordinary service quoted it');

    await h.privacy(true);
    await h.review('27');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-2');
  });

  /// A hardware account never gets a private address, whatever the setting
  /// and however often it changes, while a software account in the same
  /// wallet does whenever it is on.
  test(
    'a hardware account quotes ordinary addresses through every toggle',
    () async {
      final h = await _Harness.create();
      await h.switchTo(_hardware);
      for (final on in [true, false, true]) {
        await h.privacy(on);
        await h.review('25');
        expect(
          h.state.reviewAddressPlan?.oneClickRecipient,
          'u1ordinary-$_hardware',
          reason: 'on $on',
        );
      }
      expect(h.reservations, 0);
      expect(
        h.ordinary,
        List.filled(3, _hardware),
        reason: 'every hardware quote used the ordinary service',
      );
      await h.switchTo(_first);
      await h.review('26');
      expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-1');
    },
  );
}

/// A started USDC-to-ZEC swap quoted with a reserved receive address, never
/// paid, whose deposit deadline is `deadline`.
SwapIntent _privateIncomingSwap(String id, {required DateTime deadline}) =>
    SwapIntent(
      id: id,
      pair: 'USDC -> ZEC',
      sellAmount: '25 USDC',
      receiveEstimate: '0.25 ZEC',
      provider: 'NEAR Intents',
      status: SwapIntentStatus.awaitingExternalDeposit,
      nextAction: 'Send USDC',
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      depositAddress: '0x$id',
      depositMemo: 'memo',
      providerQuoteId: 'quote-$id',
      oneClickRecipient: 'u1$id',
      oneClickRefundTo: _recipient,
      depositDeadline: deadline,
      accountUuid: _first,
      privateAddress: true,
    );

/// A swap notifier over fakes: two software accounts and a hardware one, with
/// NEAR swap privacy on until [privacy] turns it off (every reservation goes
/// through `reserve`), an in-memory activity store and a tracker that records
/// what reaches the wallet.
class _Harness {
  _Harness._(this.container, this.sync, this.provider);

  final ProviderContainer container;
  final _Sync sync;
  final _Provider provider;
  var reservations = 0;
  var _requests = 0;

  /// Statuses the wallet recorded, in order.
  final recorded = <SwapIntentStatus>[];

  /// Accounts the ordinary receive address service handed an address to.
  final ordinary = <String>[];

  /// Builds the notifier, with `intents` saved for the first account, and
  /// waits for its asset catalog. `reserve` defaults to a new incoming
  /// reservation per call, numbered across accounts. Status requests answer
  /// `providerStatus`.
  static Future<_Harness> create({
    List<SwapIntent> intents = const [],
    Future<SwapZecStagingAddress> Function(String account)? reserve,
    SwapIntentStatus providerStatus = SwapIntentStatus.processing,
  }) async {
    final sync = _Sync();
    final provider = _Provider()..status = providerStatus;
    final activity = _MemoryStore(intents);
    late _Harness h;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        accountProvider.overrideWith(_Accounts.new),
        nearSwapPrivacyProvider.overrideWith(_Privacy.new),
        networkPrivacyProvider.overrideWith(_DirectRoute.new),
        syncProvider.overrideWith(() => sync),
        swapIntentProvider.overrideWithValue(provider),
        swapActivityStoreProvider.overrideWithValue(activity),
        swapComposerPreferencesStoreProvider.overrideWithValue(activity),
        paySelectedAssetStoreProvider.overrideWithValue(activity),
        swapStatusPollIntervalProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
        swapPriceRefreshIntervalProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
        rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
          (_) async => 'inert-no-failover',
        ),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_, _) async => BigInt.zero,
        ),
        // The production staging address provider decides between a private
        // and an ordinary address. Only the wallet calls behind it are fake.
        swapReceiveReservationServiceProvider.overrideWithValue(
          SwapReceiveReservationService(
            store: (account) async => _Reservations(() {
              h.reservations++;
              return reserve?.call(account) ??
                  Future.value(
                    SwapZecStagingAddress(
                      address: 'u1$account-${h.reservations}',
                      reservationIndex: BigInt.from(h.reservations),
                    ),
                  );
            }, () => 'request-${++h._requests}'),
          ),
        ),
        receiveAddressServiceProvider.overrideWith(
          (ref) =>
              _OrdinaryAddresses(ref, (account) => h.ordinary.add(account)),
        ),
        swapActivityTrackerProvider.overrideWith(
          (ref) => SwapActivityTracker(
            activityStore: activity,
            swapProvider: provider,
            onProviderSnapshot: (_, snapshot, _) async {
              h.recorded.add(snapshot.status);
              return true;
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    h = _Harness._(container, sync, provider);
    container.listen(swapStateProvider, (_, _) {});
    await container.read(syncProvider.future);
    await pumpEventQueue();
    return h;
  }

  SwapNotifier get notifier => container.read(swapStateProvider.notifier);
  SwapState get state => container.read(swapStateProvider);

  /// Quotes `amount` USDC into ZEC for review on the active account.
  Future<void> review(String amount) async {
    notifier.selectDirection(SwapDirection.externalToZec);
    notifier.updateAmount(amount);
    notifier.updateDestination(_recipient);
    await notifier.showReview();
    await pumpEventQueue();
  }

  /// Turns NEAR swap privacy on or off, as the settings toggle does once its
  /// change is applied.
  Future<void> privacy(bool on) async {
    (container.read(nearSwapPrivacyProvider.notifier) as _Privacy).turn(on);
    await pumpEventQueue();
  }

  /// Makes `account` active, as the account switcher does.
  Future<void> switchTo(String account) async {
    await container.read(accountProvider.notifier).switchAccount(account);
    await pumpEventQueue();
  }
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/swap',
  initialAccountState: _accounts,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const _accounts = AccountState(
  accounts: [
    AccountInfo(uuid: _first, name: 'Primary', order: 0),
    AccountInfo(uuid: _second, name: 'Trading', order: 1),
    AccountInfo(uuid: _hardware, name: 'Keystone', order: 2, isHardware: true),
  ],
  activeAccountUuid: _first,
  activeAddress: 'u1active',
);

class _Accounts extends AccountNotifier {
  /// Two software accounts and a hardware one, the first active.
  @override
  FutureOr<AccountState> build() => _accounts;

  /// Makes `uuid` active without native calls.
  @override
  Future<void> switchAccount(String uuid) async {
    state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
  }
}

class _Privacy extends NearSwapPrivacyNotifier {
  /// NEAR swap privacy on until [turn] changes it.
  @override
  bool build() => true;

  /// Changes the setting without the settings store or native calls.
  void turn(bool on) => state = on;
}

class _DirectRoute extends NetworkPrivacyNotifier {
  /// Tor off.
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}

class _Sync extends SyncNotifier {
  var awaited = 0;

  /// A synced wallet with spendable ZEC.
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _first,
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(10000000000),
    displaySpendableBalance: BigInt.from(10000000000),
    totalBalance: BigInt.from(10000000000),
  );

  /// Counts the recovery rounds a quote waits for, each of which succeeds.
  @override
  Future<Object?> awaitSwapRecovery() async {
    awaited++;
    return null;
  }

  /// Starts nothing.
  @override
  void continueSwapRecovery() {}

  /// Refreshes nothing.
  @override
  Future<void> refreshAfterSend() async {}
}

/// Incoming reservation records that accept every quote, whose reservations
/// come from `reserveNext` and request ids from `nextRequest`. Other calls
/// fail.
class _Reservations extends Fake implements ReceiveReservationStore {
  _Reservations(this.reserveNext, this.nextRequest);
  final Future<SwapZecStagingAddress> Function() reserveNext;
  final String Function() nextRequest;

  @override
  Future<api.SwapAddress> reserve({
    required bool incoming,
    required BigInt tip,
  }) async {
    final staged = await reserveNext();
    return api.SwapAddress(
      address: staged.address,
      refundIndex: staged.refundIndex,
      reservationIndex: staged.reservationIndex,
    );
  }

  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async =>
      nextRequest();

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {}
}

/// Ordinary receive addresses without a wallet, recording each account asked.
class _OrdinaryAddresses extends ReceiveAddressService {
  _OrdinaryAddresses(super.ref, this.onReserve);
  final void Function(String account) onReserve;

  @override
  Future<String> reserveOrchardAddress({required String accountUuid}) async {
    onReserve(accountUuid);
    return 'u1ordinary-$accountUuid';
  }
}

/// 1Click as the composer sees it: quotes that run the send hook, and a
/// configurable status answer. Other calls fail.
class _Provider extends Fake implements SwapProvider {
  SwapIntentStatus status = SwapIntentStatus.processing;
  final statusRequests = <String>[];

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async =>
      swapExternalAssets;

  /// Sends the request through its hook, then answers.
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await request.beforeSend?.call(
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final estimate = SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      mode: request.mode,
      amount: request.amount,
      slippageBps: request.slippageBps ?? 50,
    );
    return SwapQuote(
      direction: estimate.direction,
      sellAsset: estimate.sellAsset,
      receiveAsset: estimate.receiveAsset,
      externalAsset: estimate.externalAsset,
      mode: estimate.mode,
      sellAmount: estimate.sellAmount,
      receiveAmount: estimate.receiveAmount,
      minimumReceiveAmount: estimate.minimumReceiveAmount,
      providerLabel: providerLabel,
      feeLabel: estimate.feeLabel,
      expiryLabel: estimate.expiryLabel,
      providerQuoteId: 'quote-live',
      depositInstruction: SwapDepositInstruction(
        asset: estimate.sellAsset,
        address: '0xlive-deposit',
        expiresInLabel: '10:00',
        reuseWarning: '',
        memo: 'memo-live',
        deadline: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
  }

  /// Answers [status] for `intentId`.
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(intentId);
    return _snapshot(intentId, status);
  }

  /// A status-only answer for `address`.
  SwapIntentSnapshot _snapshot(String address, SwapIntentStatus status) =>
      SwapIntentSnapshot(
        id: address,
        providerLabel: providerLabel,
        pairText: 'ZEC -> USDC',
        sellAmountText: '1 ZEC',
        receiveEstimateText: '70 USDC',
        status: status,
        nextAction: status.label,
        providerStatusRaw: status.name,
        statusOnly: true,
        depositInstruction: SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: address,
          expiresInLabel: '10:00',
          reuseWarning: '',
        ),
      );
}

/// Activity, composer preferences and Pay asset, kept in memory per account.
class _MemoryStore
    implements
        SwapActivityStore,
        SwapComposerPreferencesStore,
        PaySelectedAssetStore {
  _MemoryStore(List<SwapIntent> intents) {
    for (final intent in intents) {
      _records
          .putIfAbsent(intent.accountUuid!, () => [])
          .add(SwapIntentRecord.fromIntent(intent));
    }
  }

  final _records = <String, List<SwapIntentRecord>>{};

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async => [...?_records[accountUuid]];

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async => _records[accountUuid] = [...records];

  @override
  Future<void> deleteForAccount({required String accountUuid}) async =>
      _records.remove(accountUuid);

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async => null;

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {}

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async =>
      null;

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {}
}
