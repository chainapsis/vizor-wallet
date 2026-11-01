// Scenario tests for the swap composer's use of one-time swap addresses: the
// update stop, the live tip each reservation is checked against, the
// per-account review address cache, the privacy setting's effect on open and
// new swaps, and hardware accounts. They drive `SwapNotifier` through a
// ProviderContainer with the production reservation, staging address and
// activity tracker services, without widgets or Rust.
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
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
        reserve: (_, _) async => throw const api.ReceiveError(
          message:
              'Update Vizor to keep checking private swap addresses. '
              'Your saved progress is kept.',
          kind: api.ReceiveErrorKind.upgradeRequired,
        ),
      );
      await h.review('25');
      expect(h.reservations, 1);
      expect(h.sync.awaited, 0);
      expect(
        h.state.quoteError,
        'Update Vizor to keep checking private swap addresses. '
        'Your saved progress is kept.',
      );
    },
  );

  /// Each quote reserves on the active account, and switching back to an
  /// account quotes its address again. The fake stands in for the wallet
  /// resuming the account's draft, so the notifier's own per-account cache is
  /// checked by the next test.
  test('each account quotes its own address across switches', () async {
    final drafts = <String, SwapZecStagingAddress>{};
    final h = await _Harness.create(
      reserve: (account, _) async => drafts[account] ??= SwapZecStagingAddress(
        address: 'u1$account-${drafts.length + 1}',
        reservationIndex: BigInt.from(drafts.length + 1),
      ),
    );
    await h.review('25');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-1');
    await h.switchTo(_second);
    await h.review('26');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_second-2');
    await h.switchTo(_first);
    await h.review('27');
    expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-1');
    expect(h.reservations, 3, reason: 'each quote prepares its address');
  });

  /// A preparation still running when the user switches accounts stays cached
  /// for its account. Back on that account, the next quote waits for it before
  /// asking the wallet again, so two preparations for one account never
  /// overlap. Every fake reservation is distinct, so only the notifier's cache
  /// can order them. The outdated quote never reaches NEAR.
  test(
    "a held preparation makes the account's next one wait across switches",
    () async {
      final held = Completer<SwapZecStagingAddress>();
      var calls = 0;
      final h = await _Harness.create(
        reserve: (account, _) async {
          if (++calls == 1) return held.future;
          return SwapZecStagingAddress(
            address: 'u1$account-$calls',
            reservationIndex: BigInt.from(calls),
          );
        },
      );
      final first = h.review('25');
      await pumpEventQueue();
      await h.switchTo(_second);
      await h.review('26');
      expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_second-2');

      await h.switchTo(_first);
      final again = h.review('27');
      await pumpEventQueue();
      expect(
        [for (final r in h.reserved) r.account],
        [_first, _second],
        reason: 'the second preparation waits for the held one',
      );

      held.complete(
        SwapZecStagingAddress(
          address: 'u1$_first-held',
          reservationIndex: BigInt.one,
        ),
      );
      await first;
      await again;
      expect(
        [for (final r in h.reserved) r.account],
        [_first, _second, _first],
      );
      expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-3');
      expect(h.provider.quoted, ['u1$_second-2', 'u1$_first-3']);
    },
  );

  /// The wallet checks a swap address against the chain tip the endpoint
  /// reports when the quote is made, not a saved height, in both directions.
  test('each quote reserves with the live tip in both directions', () async {
    final h = await _Harness.create();
    await h.review('25');
    h.liveTip = BigInt.from(3000007);
    await h.review('0.5', sell: true);
    expect(h.reserved, [
      (account: _first, incoming: true, tip: BigInt.from(3000000)),
      (account: _first, incoming: false, tip: BigInt.from(3000007)),
    ]);
    expect(h.provider.quoted, ['u1$_first-1', 'u1$_first-2']);
  });

  /// Without a live tip there is nothing to check a swap address against, so
  /// the quote stops before it reserves one or reaches NEAR.
  test('an unreachable endpoint stops the quote before it reserves', () async {
    final h = await _Harness.create();
    h.liveTip = null;
    await h.review('25');
    expect(h.reserved, isEmpty);
    expect(h.provider.quoted, isEmpty);
    expect(h.state.reviewVisible, isFalse);
    // The private wording, which leaves out closing older swaps.
    expect(
      h.state.quoteError,
      'Could not prepare a fresh wallet receive address. '
      'Try again after wallet sync.',
    );
  });

  /// A cached draft is checked against the live tip again on every quote. The
  /// first account quotes its draft, then the tip moves 11 blocks past its
  /// filters while the user quotes on the second account. Back on the first,
  /// the wallet refuses the draft (the fake refuses past 10 blocks, standing
  /// in for the wallet's own freshness check, which the Rust scenarios test),
  /// so the old address doesn't reach NEAR: the
  /// quote waits for a recovery round and stops while filters stay behind.
  /// Once a round catches them up, the same draft is quoted again.
  test(
    'a cached draft re-quoted after the tip moves waits for its filters',
    () async {
      final start = BigInt.from(3000000);
      // The first account's filters, which only a recovery round moves.
      var filters = start;
      var catchesUp = false;
      final drafts = <String, SwapZecStagingAddress>{};
      final h = await _Harness.create(
        reserve: (account, tip) async {
          if (account == _first && tip - filters > BigInt.from(10)) {
            throw const api.ReceiveError(
              message:
                  'Preparing a private swap address. Try again in a moment.',
              kind: api.ReceiveErrorKind.receiveHistory,
            );
          }
          return drafts[account] ??= SwapZecStagingAddress(
            address: 'u1$account-draft',
            reservationIndex: BigInt.from(drafts.length + 1),
          );
        },
      );
      h.sync.onRecovery = () {
        if (catchesUp) filters = h.liveTip!;
      };
      await h.review('25');
      await h.switchTo(_second);
      h.liveTip = start + BigInt.from(11);
      await h.review('26');
      expect(h.provider.quoted, ['u1$_first-draft', 'u1$_second-draft']);

      await h.switchTo(_first);
      await h.review('27');
      expect(h.sync.awaited, 1, reason: 'the refusal waited for a round');
      expect(h.state.reviewVisible, isFalse);
      expect(
        h.provider.quoted,
        hasLength(2),
        reason: 'the stale draft never reached NEAR',
      );

      catchesUp = true;
      await h.review('28');
      expect(h.sync.awaited, 2);
      expect(h.state.reviewAddressPlan?.oneClickRecipient, 'u1$_first-draft');
      expect(h.provider.quoted.last, 'u1$_first-draft');
      expect(
        [for (final r in h.reserved.where((r) => r.account == _first)) r.tip],
        [start, ...List.filled(4, start + BigInt.from(11))],
        reason: 'every attempt checked the draft against the live tip',
      );
    },
  );

  /// Turning one-time swap addresses off while a private swap is open still
  /// polls the open swap, and the production tracker still hands its statuses
  /// to the wallet, which needs them to settle or release its address, and
  /// asks for a recovery round once one promises ZEC, which for an incoming
  /// swap is NEAR's SUCCESS. New quotes use an ordinary address and reserve
  /// nothing until the setting is back on.
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
    h.observed.clear();
    h.provider.statusRequests.clear();
    await h.notifier.refreshOpenIntentStatuses();
    await pumpEventQueue();
    expect(h.provider.statusRequests, contains(open.depositAddress));
    expect(h.observed, [
      (
        account: _first,
        incoming: true,
        depositAddress: open.depositAddress,
        memo: open.depositMemo,
        status: SwapIntentStatus.awaitingExternalDeposit,
        raw: 'PENDING_DEPOSIT',
      ),
    ]);
    expect(h.sync.recoveryRequests, 0, reason: 'no ZEC is promised yet');

    // NEAR has the deposit and is still swapping it.
    h.provider.status = SwapIntentStatus.processing;
    await h.notifier.refreshOpenIntentStatuses();
    await pumpEventQueue();
    expect(h.observed.last.raw, 'PROCESSING');
    expect(h.sync.recoveryRequests, 0, reason: 'no payout is promised yet');

    // NEAR reports the payout sent.
    h.provider.status = SwapIntentStatus.complete;
    await h.notifier.refreshOpenIntentStatuses();
    await pumpEventQueue();
    expect(h.observed.last.raw, 'SUCCESS');
    expect(h.sync.recoveryRequests, 1, reason: 'the payout owes a round');

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
/// through `reserve`), an in-memory activity store, and the production
/// activity tracker, whose statuses reach the fake wallet's `observe`.
class _Harness {
  _Harness._(this.container, this.sync, this.provider);

  final ProviderContainer container;
  final _Sync sync;
  final _Provider provider;
  int get reservations => reserved.length;
  var _requests = 0;

  /// The chain tip the endpoint reports, or null for an unreachable endpoint.
  BigInt? liveTip = BigInt.from(3000000);

  /// Every reservation the wallet received, in order.
  final reserved = <({String account, bool incoming, BigInt tip})>[];

  /// Every status the wallet received, in order.
  final observed = <_Observed>[];

  /// Accounts the ordinary receive address service handed an address to.
  final ordinary = <String>[];

  /// Builds the notifier, with `intents` saved for the first account, and
  /// waits for its asset catalog. `reserve` defaults to a new reservation per
  /// call, numbered across accounts, and gets the live tip it was asked with.
  /// Status requests answer `providerStatus`.
  static Future<_Harness> create({
    List<SwapIntent> intents = const [],
    Future<SwapZecStagingAddress> Function(String account, BigInt tip)? reserve,
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
          (_, _) async =>
              h.liveTip ?? (throw const SocketException('endpoint down')),
        ),
        // The production staging address provider decides between a private
        // and an ordinary address. Only the wallet calls behind it are fake.
        swapReceiveReservationServiceProvider.overrideWithValue(
          SwapReceiveReservationService(
            store: (account) async => _Reservations(
              account,
              reserveNext: (incoming, tip) {
                h.reserved.add((
                  account: account,
                  incoming: incoming,
                  tip: tip,
                ));
                return reserve?.call(account, tip) ??
                    Future.value(
                      SwapZecStagingAddress(
                        address: 'u1$account-${h.reservations}',
                        reservationIndex: incoming
                            ? BigInt.from(h.reservations)
                            : null,
                        refundIndex: incoming
                            ? null
                            : BigInt.from(h.reservations),
                      ),
                    );
              },
              nextRequest: () => 'request-${++h._requests}',
              observed: h.observed,
            ),
          ),
        ),
        receiveAddressServiceProvider.overrideWith(
          (ref) =>
              _OrdinaryAddresses(ref, (account) => h.ordinary.add(account)),
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

  /// Quotes `amount` USDC into ZEC for review on the active account, or ZEC
  /// into USDC with `sell`.
  Future<void> review(String amount, {bool sell = false}) async {
    notifier.selectDirection(
      sell ? SwapDirection.zecToExternal : SwapDirection.externalToZec,
    );
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
  var recoveryRequests = 0;

  /// A synced wallet with spendable ZEC.
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _first,
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(10000000000),
    displaySpendableBalance: BigInt.from(10000000000),
    totalBalance: BigInt.from(10000000000),
  );

  /// Runs after each recovery round a quote waits for.
  void Function()? onRecovery;

  /// Counts the recovery rounds a quote waits for, each of which succeeds.
  @override
  Future<Object?> awaitSwapRecovery() async {
    awaited++;
    onRecovery?.call();
    return null;
  }

  /// Starts nothing.
  @override
  void continueSwapRecovery() {}

  /// Counts the rounds a status asked for, starting none.
  @override
  void requestSwapRecovery() => recoveryRequests++;

  /// Refreshes nothing.
  @override
  Future<void> refreshAfterSend() async {}
}

/// One status the wallet received for `account`'s swap address, with NEAR's
/// raw status.
typedef _Observed = ({
  String account,
  bool incoming,
  String? depositAddress,
  String? memo,
  SwapIntentStatus status,
  String? raw,
});

/// One account's swap address records, which accept every quote. Reservations
/// come from `reserveNext`, given the direction and live tip, and request ids
/// from `nextRequest`. Statuses are added to `observed`, and the wallet says
/// it tracks every address and, as its normalizer reads NEAR, expects ZEC
/// once an incoming swap reports SUCCESS. Refunds aren't modeled. Other calls
/// fail.
class _Reservations extends Fake implements ReceiveReservationStore {
  _Reservations(
    this.account, {
    required this.reserveNext,
    required this.nextRequest,
    required this.observed,
  });
  final String account;
  final Future<SwapZecStagingAddress> Function(bool incoming, BigInt tip)
  reserveNext;
  final String Function() nextRequest;
  final List<_Observed> observed;

  @override
  Future<api.SwapAddress> reserve({
    required bool incoming,
    required BigInt tip,
  }) async {
    final staged = await reserveNext(incoming, tip);
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

  @override
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote) async {}

  @override
  Future<api.SwapStatusRecord> observe({
    required bool incoming,
    required String depositAddress,
    required String? memo,
    required SwapIntentSnapshot snapshot,
    required DateTime checkedAt,
  }) async {
    observed.add((
      account: account,
      incoming: incoming,
      depositAddress: depositAddress,
      memo: memo,
      status: snapshot.status,
      raw: snapshot.providerStatusRaw,
    ));
    return api.SwapStatusRecord(
      tracked: true,
      receiptExpected: incoming && snapshot.providerStatusRaw == 'SUCCESS',
    );
  }
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

  /// The receive or refund address of every quote request that was sent.
  final quoted = <String>[];

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async =>
      swapExternalAssets;

  /// Sends the request through its hook, then answers. A ZEC deposit is
  /// address-only, as refund addresses require.
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await request.beforeSend?.call(
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    quoted.add(
      request.direction.sendsZec
          ? request.refundAddress ?? ''
          : request.destination,
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
        memo: request.direction.sendsZec ? null : 'memo-live',
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
        providerStatusRaw: _raw[status],
        statusOnly: true,
        depositInstruction: SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: address,
          expiresInLabel: '10:00',
          reuseWarning: '',
        ),
      );
}

/// NEAR 1Click's raw status for each status the app shows. The rest are the
/// app's own and have none.
const _raw = {
  SwapIntentStatus.awaitingDeposit: 'PENDING_DEPOSIT',
  SwapIntentStatus.awaitingExternalDeposit: 'PENDING_DEPOSIT',
  SwapIntentStatus.depositObserved: 'KNOWN_DEPOSIT_TX',
  SwapIntentStatus.processing: 'PROCESSING',
  SwapIntentStatus.incompleteDeposit: 'INCOMPLETE_DEPOSIT',
  SwapIntentStatus.complete: 'SUCCESS',
  SwapIntentStatus.refunded: 'REFUNDED',
  SwapIntentStatus.failed: 'FAILED',
};

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
