import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../fakes/fake_sync_notifier.dart';

/// Rust stand-in whose proposal is held open until the test releases it, so
/// "checking" is an observable state rather than a race.
class _FakeSendApi {
  _FakeSendApi({
    this.addressIsValid = true,
    this.addressType = 'unified',
    this.addressWrongNetwork = false,
  });

  bool addressIsValid;
  String addressType;

  /// The address is well-formed but belongs to another Zcash network, which
  /// Rust reports as not-valid plus a `wrongNetwork` flag.
  bool addressWrongNetwork;
  Object? proposeThrows;
  Completer<void>? gate;
  var nextProposalId = 1;

  /// Every entry into the propose path, including the ones that throw. What
  /// the re-check tests count: a card that re-checked itself is one that
  /// asked again.
  var proposeAttempts = 0;
  final discarded = <BigInt>[];
  final proposed = <BigInt>[];

  PaymentRequestPrecheck get precheck => PaymentRequestPrecheck(
    spendableIsAuthoritativeNow: () => true,
    validateAddress:
        ({required String address, required String network}) async =>
            rust_sync.AddressValidationResult(
              isValid: addressIsValid && !addressWrongNetwork,
              addressType: addressType,
              wrongNetwork: addressWrongNetwork,
            ),
    proposeTransfer:
        ({
          required String accountUuid,
          required String sendFlowId,
          required String address,
          required String addressType,
          required BigInt amountZatoshi,
          String? memo,
          bool isPaymentRequest = false,
          String? requestedBy,
          BigInt? requestedAmountZatoshi,
        }) async {
          proposeAttempts++;
          final pending = gate;
          if (pending != null) await pending.future;
          final failure = proposeThrows;
          if (failure != null) throw failure;
          final id = BigInt.from(nextProposalId++);
          proposed.add(id);
          return SendReviewArgs(
            proposalId: id,
            sendFlowId: sendFlowId,
            proposalAccountUuid: accountUuid,
            address: address,
            addressType: addressType,
            amountZatoshi: amountZatoshi,
            feeZatoshi: BigInt.from(10000),
            needsSaplingParams: false,
            isPaymentRequest: isPaymentRequest,
            requestedBy: requestedBy,
            requestedAmountZatoshi: requestedAmountZatoshi,
          );
        },
    discardProposal:
        ({
          required BigInt proposalId,
          required String sendFlowId,
          required String logContext,
        }) async => discarded.add(proposalId),
  );
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
    ],
    activeAccountUuid: 'account-1',
  );

  void switchToForTest(String uuid) {
    state = AsyncData(state.value!.copyWith(activeAccountUuid: uuid));
  }
}

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  void lockForTest() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
  );
}

SendPrefillArgs request(
  String address, {
  String? amountText = '0.5',
  String? memoText,
}) => SendPrefillArgs(
  id: 'payment-uri-$address',
  source: kPaymentUriPrefillSource,
  address: address,
  amountText: amountText,
  memoText: memoText,
  preserveMemoText: memoText != null,
  label: 'Coffee shop',
);

/// A sync state whose spendable balance is settled: scanned to a real tip,
/// nothing running, nothing failed.
SyncState syncedState({required BigInt spendable}) => SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  isSyncComplete: true,
  chainTipHeight: 3000000,
  scannedHeight: 3000000,
  spendableBalance: spendable,
);

/// Mid-scan: nothing about the balance can be trusted yet.
SyncState scanningState() => SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  isSyncing: true,
  chainTipHeight: 3000000,
  scannedHeight: 12000,
);

/// Scanned to the tip, nothing running — and no balance for the account.
///
/// What `withoutAccountScopedData` leaves behind, and what a sync-progress
/// event whose balance fetch failed publishes for an account that never had
/// one: the wallet-wide sync fields say "settled" while `displaySpendable` is
/// a zero nobody read.
SyncState settledWithoutBalanceState() => SyncState(
  accountUuid: 'account-1',
  hasBalanceData: false,
  hasRecentTransactionsData: false,
  isSyncComplete: true,
  chainTipHeight: 3000000,
  scannedHeight: 3000000,
);

/// What Rust says when it has no anchor heights yet — the error the pre-check
/// maps onto [PaymentRequestStatus.syncing].
Exception get walletMustSync => Exception('Wallet must sync before sending');

FakeSyncNotifier syncNotifier(ProviderContainer container) =>
    container.read(syncProvider.notifier) as FakeSyncNotifier;

_FakeAccountNotifier _accountNotifier(ProviderContainer container) =>
    container.read(accountProvider.notifier) as _FakeAccountNotifier;

_FakeSecurityNotifier _securityNotifier(ProviderContainer container) =>
    container.read(appSecurityProvider.notifier) as _FakeSecurityNotifier;

PaymentRequestFlowState? flowState(ProviderContainer container) =>
    container.read(paymentRequestFlowProvider);

/// Presents [address] and settles on the `syncing` status: the wallet could
/// not answer, so the card is left waiting on the sync.
Future<void> _presentSyncingCard(
  ProviderContainer container,
  _FakeSendApi api, {
  String address = 'u1a',
}) async {
  api.proposeThrows = walletMustSync;
  container
      .read(paymentRequestFlowProvider.notifier)
      .present(request(address), source: PaymentRequestSource.link);
  await pumpEventQueue();
  expect(flowState(container)!.view.status, PaymentRequestStatus.syncing);
}

// ignore: library_private_types_in_public_api
ProviderContainer makeContainer(_FakeSendApi api, {SyncState? sync}) {
  final container = ProviderContainer(
    overrides: [
      paymentRequestPrecheckProvider.overrideWithValue(api.precheck),
      accountProvider.overrideWith(_FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          sync ?? syncedState(spendable: BigInt.from(100000000)),
        ),
      ),
      migrationSendGateProvider.overrideWithValue(false),
      zecHomeUsdUnitPriceProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('present starts in checking and lands on ready', () async {
    final api = _FakeSendApi()..gate = Completer<void>();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);

    var state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.checking);
    expect(state.view.amountZecText, '0.50 ZEC');
    expect(state.view.requesterLabel, 'Coffee shop');
    expect(state.canReview, isFalse);

    api.gate!.complete();
    await pumpEventQueue();

    state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(state.canReview, isTrue);
    expect(state.reviewArgs!.proposalId, BigInt.one);
  });

  test('an amount-less request is ready but cannot go to review', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(
          request('u1a', amountText: null),
          source: PaymentRequestSource.link,
        );
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(state.view.amountZecText, isNull);
    expect(state.canReview, isFalse);
  });

  test('an unpayable address renders the invalid-address status', () async {
    final api = _FakeSendApi(addressIsValid: false);
    final container = makeContainer(api);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.invalidAddress);
    expect(
      state.view.resolvedStatusMessage,
      "Recipient address doesn't look right",
      reason: 'a malformed address keeps the status default copy',
    );
    expect(state.canReview, isFalse);
  });

  test(
    'an address for another network publishes its own status message',
    () async {
      final api = _FakeSendApi(addressWrongNetwork: true);
      final container = makeContainer(api);

      container
          .read(paymentRequestFlowProvider.notifier)
          .present(request('utest1a'), source: PaymentRequestSource.link);
      await pumpEventQueue();

      final state = container.read(paymentRequestFlowProvider)!;
      expect(state.view.status, PaymentRequestStatus.invalidAddress);
      expect(state.view.resolvedStatusMessage, kWrongNetworkAddressMessage);
      expect(state.canReview, isFalse);
    },
  );

  test('a check that could not complete is failed, not invalid '
      'address', () async {
    final api = _FakeSendApi()..proposeThrows = Exception('something unmapped');
    final container = makeContainer(api);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.failed);
    expect(
      state.view.resolvedStatusMessage,
      "Couldn't check this request — open Edit to review the details",
    );
    expect(state.canReview, isFalse);
  });

  test('a newer link replaces the card, says so, and frees the old '
      'proposal', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1first'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(api.proposed, [BigInt.one]);

    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    expect(
      container.read(paymentRequestFlowProvider)!.view.replacedNotice,
      isTrue,
    );
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.prefill.address, 'u1second');
    expect(state.reviewArgs!.proposalId, BigInt.two);
    expect(
      api.discarded,
      [BigInt.one],
      reason: 'the displaced request must not leave a proposal behind',
    );
  });

  test('edit clears the card, frees the proposal, and returns the '
      'request', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final prefill = notifier.edit();
    await pumpEventQueue();

    expect(prefill!.address, 'u1a');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(api.discarded, [BigInt.one]);
  });

  test('dismiss frees the proposal', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    notifier.dismiss();
    await pumpEventQueue();

    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(api.discarded, [BigInt.one]);
  });

  test('review hands the proposal on without discarding it', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final args = notifier.review();
    await pumpEventQueue();

    expect(args!.proposalId, BigInt.one);
    expect(args.isPaymentRequest, isTrue);
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(
      api.discarded,
      isEmpty,
      reason: 'the review screen owns the proposal from here',
    );
  });

  test('a pre-check that finishes after its card is gone frees its own '
      'proposal', () async {
    final api = _FakeSendApi()..gate = Completer<void>();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    notifier.dismiss();
    api.gate!.complete();
    await pumpEventQueue();

    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(api.discarded, [BigInt.one]);
  });

  test('a memo a transparent recipient cannot receive leaves the '
      'card', () async {
    final api = _FakeSendApi(addressType: 'tex');
    final container = makeContainer(api);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(
          request('tex1recipient', memoText: 'invoice 42'),
          source: PaymentRequestSource.link,
        );
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(
      state.view.memo,
      isNull,
      reason:
          'the proposal drops it, so the consent surface must not '
          'keep promising it',
    );
  });

  test('a memo a shielded recipient can receive stays on the card', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(
          request('u1a', memoText: 'invoice 42'),
          source: PaymentRequestSource.link,
        );
    await pumpEventQueue();

    expect(container.read(paymentRequestFlowProvider)!.view.memo, 'invoice 42');
  });

  test('a shortfall read mid-sync never lands on insufficient funds', () async {
    final api = _FakeSendApi();
    final container = makeContainer(
      api,
      sync: SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        chainTipHeight: 3000000,
        scannedHeight: 12000,
      ),
    );

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(
      state.view.status,
      PaymentRequestStatus.ready,
      reason: 'VZR-42: a balance still being scanned cannot say "not enough"',
    );
    expect(api.proposed, [BigInt.one]);
  });

  test('a shortfall on a settled balance is insufficient funds', () async {
    final api = _FakeSendApi();
    final container = makeContainer(
      api,
      sync: syncedState(spendable: BigInt.from(21000000)),
    );

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.insufficientFunds);
    expect(state.view.spendableText, '0.21 ZEC');
    expect(api.proposed, isEmpty);
  });

  test('locking the wallet takes the card down and frees the '
      'proposal', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    (container.read(appSecurityProvider.notifier) as _FakeSecurityNotifier)
        .lockForTest();
    await pumpEventQueue();

    expect(
      container.read(paymentRequestFlowProvider),
      isNull,
      reason:
          'the host renders above the router, so a card left standing '
          'would sit on the unlock screen with the request still on it',
    );
    expect(api.discarded, [BigInt.one]);
  });

  test('a lock during the pre-check frees the proposal it was still '
      'making', () async {
    final api = _FakeSendApi()..gate = Completer<void>();
    final container = makeContainer(api);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);

    (container.read(appSecurityProvider.notifier) as _FakeSecurityNotifier)
        .lockForTest();
    api.gate!.complete();
    await pumpEventQueue();

    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(api.discarded, [BigInt.one]);
  });

  test('switching accounts takes the card down and frees the '
      'proposal', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    (container.read(accountProvider.notifier) as _FakeAccountNotifier)
        .switchToForTest('account-2');
    await pumpEventQueue();

    expect(
      container.read(paymentRequestFlowProvider),
      isNull,
      reason: 'the proposal belongs to the account that made it',
    );
    expect(api.discarded, [BigInt.one]);
  });

  test('clear frees the proposal without a user answer', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    notifier.clear();
    await pumpEventQueue();

    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(api.discarded, [BigInt.one]);
  });

  test('a syncing card re-checks itself once the wallet finishes '
      'syncing', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    await _presentSyncingCard(container, api);
    expect(api.proposeAttempts, 1);

    // The wallet settles, and the request that could not be answered can be.
    api.proposeThrows = null;
    api.gate = Completer<void>();
    syncNotifier(
      container,
    ).emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    var state = flowState(container)!;
    expect(
      state.view.status,
      PaymentRequestStatus.checking,
      reason: 'the card says it is working again, not that it is blocked',
    );
    expect(state.view.resolvedStatusMessage, isNull);
    expect(api.proposeAttempts, 2);

    api.gate!.complete();
    await pumpEventQueue();

    state = flowState(container)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(state.canReview, isTrue);
    expect(state.reviewArgs!.proposalId, BigInt.one);
    expect(api.discarded, isEmpty);
  });

  test('a re-check that is still syncing keeps waiting for the next '
      'sync', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    final sync = syncNotifier(container);
    await _presentSyncingCard(container, api);

    // First completion: the wallet reports settled, but the propose path has
    // not caught up, so the card lands back on syncing.
    sync.emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();
    expect(flowState(container)!.view.status, PaymentRequestStatus.syncing);
    expect(api.proposeAttempts, 2);

    // A settled state that was already settled is not a new completion.
    sync.emit(syncedState(spendable: BigInt.from(100000001)));
    await pumpEventQueue();
    expect(
      api.proposeAttempts,
      2,
      reason: 'at most one re-check per sync completion',
    );

    // A real second cycle: back to scanning, then settled again.
    sync.emit(scanningState());
    await pumpEventQueue();
    api.proposeThrows = null;
    sync.emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    final state = flowState(container)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(api.proposeAttempts, 3);
    expect(state.reviewArgs!.proposalId, BigInt.one);
  });

  test('a settled state carrying no balance for the account is not a '
      'sync completion', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    final sync = syncNotifier(container);
    await _presentSyncingCard(container, api);
    expect(api.proposeAttempts, 1);

    // Scanned to the tip with no balance read for this account. The
    // wallet-wide fields alone would call this settled, and the re-check
    // would then hand the card a shortfall computed against a zero.
    sync.emit(settledWithoutBalanceState());
    await pumpEventQueue();

    expect(
      flowState(container)!.view.status,
      PaymentRequestStatus.syncing,
      reason: 'a balance nobody fetched cannot answer the request',
    );
    expect(api.proposeAttempts, 1);

    // The same tip, now with the account's balance actually in hand.
    api.proposeThrows = null;
    sync.emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    final state = flowState(container)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(api.proposeAttempts, 2);
  });

  test('a card that is not syncing never re-checks on sync '
      'completion', () async {
    final api = _FakeSendApi();
    final container = makeContainer(
      api,
      sync: syncedState(spendable: BigInt.from(21000000)),
    );
    final sync = syncNotifier(container);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(
      flowState(container)!.view.status,
      PaymentRequestStatus.insufficientFunds,
    );
    expect(api.proposeAttempts, 0);

    // A full sync cycle underneath a settled verdict.
    sync.emit(scanningState());
    await pumpEventQueue();
    sync.emit(syncedState(spendable: BigInt.from(21000000)));
    await pumpEventQueue();

    expect(
      flowState(container)!.view.status,
      PaymentRequestStatus.insufficientFunds,
      reason: 'only the syncing status is waiting on the sync',
    );
    expect(api.proposeAttempts, 0);
  });

  test('dismissing during a re-check publishes nothing and frees the late '
      'proposal', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    final notifier = container.read(paymentRequestFlowProvider.notifier);
    await _presentSyncingCard(container, api);

    api.proposeThrows = null;
    api.gate = Completer<void>();
    syncNotifier(
      container,
    ).emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();
    expect(flowState(container)!.view.status, PaymentRequestStatus.checking);

    notifier.dismiss();
    api.gate!.complete();
    await pumpEventQueue();

    expect(flowState(container), isNull);
    expect(
      api.discarded,
      [BigInt.one],
      reason:
          'the re-check made a proposal for a card that no longer exists, '
          'so nothing would ever consume it',
    );
  });

  test('switching accounts while syncing stops the re-check '
      'listener', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    await _presentSyncingCard(container, api);

    _accountNotifier(container).switchToForTest('account-2');
    await pumpEventQueue();
    expect(flowState(container), isNull);

    api.proposeThrows = null;
    syncNotifier(
      container,
    ).emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    expect(flowState(container), isNull);
    expect(
      api.proposeAttempts,
      1,
      reason: 'the request belonged to the account that is no longer active',
    );
  });

  test('locking while syncing clears the card without re-checking', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    await _presentSyncingCard(container, api);

    _securityNotifier(container).lockForTest();
    await pumpEventQueue();
    expect(flowState(container), isNull);

    api.proposeThrows = null;
    syncNotifier(
      container,
    ).emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    expect(flowState(container), isNull);
    expect(
      api.proposeAttempts,
      1,
      reason: 'a locked wallet must not run a payment check of its own',
    );
  });

  test('a newer link replaces a syncing card and takes over the '
      'watch', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    final notifier = container.read(paymentRequestFlowProvider.notifier);
    await _presentSyncingCard(container, api);

    api.proposeThrows = null;
    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final state = flowState(container)!;
    expect(state.prefill.address, 'u1second');
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(api.proposeAttempts, 2);

    // The replaced card's watch must be gone with it.
    syncNotifier(
      container,
    ).emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();
    expect(api.proposeAttempts, 2);
  });
}
