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
  _FakeSendApi({this.addressIsValid = true, this.addressType = 'unified'});

  bool addressIsValid;
  String addressType;
  Object? proposeThrows;
  Completer<void>? gate;
  var nextProposalId = 1;
  final discarded = <BigInt>[];
  final proposed = <BigInt>[];

  PaymentRequestPrecheck get precheck => PaymentRequestPrecheck(
    spendableIsAuthoritativeNow: () => true,
    validateAddress: ({required String address}) async =>
        rust_sync.AddressValidationResult(
          isValid: addressIsValid,
          addressType: addressType,
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
    expect(state.canReview, isFalse);
  });

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
}
