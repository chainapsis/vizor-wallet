import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../fakes/fake_sync_notifier.dart';

/// Rust stand-in whose proposal is held open until the test releases it, so
/// "checking" is an observable state rather than a race.
class _FakeSendApi {
  _FakeSendApi({this.addressIsValid = true, this.addressWrongNetwork = false});

  bool addressIsValid;

  /// What Rust calls the recipient. Settable so a test can stand in a
  /// non-unified recipient; every case here uses the default.
  var addressType = 'unified';

  /// The address is well-formed but belongs to another Zcash network, which
  /// Rust reports as not-valid plus a `wrongNetwork` flag.
  bool addressWrongNetwork;
  Object? proposeThrows;
  Completer<void>? gate;

  /// The VZR-42 gate as the pre-check re-reads it. Settable so a test can
  /// start a scan under a check that is already in flight.
  var spendableIsAuthoritative = true;

  /// Runs inside the awaited address validation, i.e. after the check has
  /// read the balance and before it decides anything.
  void Function()? whileValidating;

  /// Set by [makeContainer], so the live balance re-read answers from the
  /// providers the production wiring reads.
  ProviderContainer? container;

  /// Holds every discard open until the test releases it, so "the inputs
  /// are still locked" is an observable state rather than a race.
  Completer<void>? discardGate;

  /// How many more discards Rust fails to confirm before one succeeds.
  int discardFailuresRemaining = 0;
  var nextProposalId = 1;

  /// Every entry into the propose path, including the ones that throw. What
  /// the re-check tests count: a card that re-checked itself is one that
  /// asked again.
  var proposeAttempts = 0;
  final discarded = <BigInt>[];
  final proposed = <BigInt>[];

  /// Proposals and discards in the order Rust would have seen them.
  final events = <String>[];

  PaymentRequestPrecheck get precheck => PaymentRequestPrecheck(
    spendableIsAuthoritativeNow: () => spendableIsAuthoritative,
    spendableBalanceNow: () {
      final read = container;
      if (read == null) return BigInt.zero;
      return paymentRequestSpendableOf(
        (read.read(syncProvider).value ?? SyncState()).scopedToAccount(
          read.read(accountProvider).value?.activeAccountUuid,
        ),
        gatedByMigration: read.read(migrationSendGateProvider),
      );
    },
    // The production wiring reads this off `rpcEndpointProvider`; these
    // cases never vary it, so the build default stands in.
    readNetworkName: () => kZcashDefaultNetworkName,
    validateAddress:
        ({required String address, required String network}) async {
          whileValidating?.call();
          return rust_sync.AddressValidationResult(
            isValid: addressIsValid && !addressWrongNetwork,
            addressType: addressType,
            wrongNetwork: addressWrongNetwork,
          );
        },
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
          events.add('propose $id');
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
        }) async {
          final pending = discardGate;
          if (pending != null) await pending.future;
          discarded.add(proposalId);
          events.add('discard $proposalId');
          if (discardFailuresRemaining > 0) {
            discardFailuresRemaining--;
            return false;
          }
          return true;
        },
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
  api.container = container;
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

    final handoff = await notifier.editHandingBack();

    expect((handoff as PaymentRequestEditReady).prefill.address, 'u1a');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(api.discarded, [BigInt.one]);
  });

  test('handing the request to the composer completes only once Rust has '
      'released the proposal', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    var handedBack = false;
    final pending = notifier.editHandingBack().then((handoff) {
      handedBack = true;
      return handoff;
    });
    await pumpEventQueue();

    // The card is gone at once; the caller is still waiting on the release.
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(handedBack, isFalse);
    expect(api.discarded, isEmpty);

    api.discardGate!.complete();
    final handoff = await pending;

    expect((handoff as PaymentRequestEditReady).prefill.address, 'u1a');
    expect(api.discarded, [BigInt.one]);
  });

  test('a hand-back overtaken by an account switch opens nothing', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    final pendingReview = notifier.reviewHandingBack();
    await pumpEventQueue();
    expect(container.read(paymentRequestFlowProvider), isNull);

    // The card is already down, so the account listener's clear finds no
    // state — it still has to stop the hand-back, or the review would open
    // on the newly active account.
    notifier.clear(logContext: 'PaymentRequest(account switched)');
    api.discardGate!.complete();

    expect(await pendingReview, isA<PaymentRequestReviewOvertaken>());
  });

  test('a hand-back whose release Rust did not confirm retries once, then '
      'opens', () async {
    debugUnconfirmedReleaseGrace = Duration.zero;
    addTearDown(
      () => debugUnconfirmedReleaseGrace = const Duration(seconds: 3),
    );
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardFailuresRemaining = 1;
    final handoff = await notifier.reviewHandingBack();

    expect(handoff, isA<PaymentRequestReviewReady>());
    expect(api.discarded, [BigInt.one, BigInt.one]);
  });

  test('a replacement pre-check waits for the retry of an unconfirmed '
      'release', () async {
    debugUnconfirmedReleaseGrace = const Duration(milliseconds: 50);
    addTearDown(
      () => debugUnconfirmedReleaseGrace = const Duration(seconds: 3),
    );
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1first'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardFailuresRemaining = 1;
    final pending = notifier.reviewHandingBack();
    await pumpEventQueue();
    // The first release failed; the retry is waiting out its grace.
    expect(api.events, ['propose 1', 'discard 1']);

    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    expect(await pending, isA<PaymentRequestReviewOvertaken>());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await pumpEventQueue();

    expect(
      api.events,
      ['propose 1', 'discard 1', 'discard 1', 'propose 2'],
      reason:
          'the newer request must not be checked against inputs the '
          'first proposal still held',
    );
  });

  test('a lock during a hand-back re-parks the request instead of dropping '
      'it', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    final pending = notifier.reviewHandingBack();
    await pumpEventQueue();
    // The card is down; only the hand-back still knows the request.
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNull);

    (container.read(appSecurityProvider.notifier) as _FakeSecurityNotifier)
        .lockForTest();
    api.discardGate!.complete();

    expect(await pending, isA<PaymentRequestReviewOvertaken>());
    expect(
      container.read(paymentUriPrefillProvider)?.address,
      'u1a',
      reason:
          'the unlock flow re-presents the parked request; without the park '
          'the answered request would be gone with nothing to say',
    );
  });

  test('a hand-back invalidated by an account switch is not re-parked on '
      'lock', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    final pending = notifier.reviewHandingBack();
    await pumpEventQueue();

    notifier.clear(logContext: 'PaymentRequest(account switched)');
    (container.read(appSecurityProvider.notifier) as _FakeSecurityNotifier)
        .lockForTest();
    api.discardGate!.complete();

    expect(await pending, isA<PaymentRequestReviewOvertaken>());
    expect(
      container.read(paymentUriPrefillProvider),
      isNull,
      reason: 'the request belonged to the account that was switched away',
    );
  });

  test('an edit hand-back overtaken by a newer link opens nothing', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1first'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    final pending = notifier.editHandingBack();
    await pumpEventQueue();
    expect(container.read(paymentRequestFlowProvider), isNull);

    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    api.discardGate!.complete();
    await pumpEventQueue();

    expect(await pending, isA<PaymentRequestEditOvertaken>());
    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.prefill.address, 'u1second');
    expect(state.view.replacedNotice, isTrue);
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

  test('a replacement waits for the displaced proposal to be handed back '
      'before it asks', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1first'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(api.proposed, [BigInt.one]);

    // The first card's inputs stay locked until Rust answers the discard.
    api.discardGate = Completer<void>();
    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    final waiting = container.read(paymentRequestFlowProvider)!;
    expect(waiting.prefill.address, 'u1second');
    expect(waiting.view.status, PaymentRequestStatus.checking);
    expect(
      api.proposeAttempts,
      1,
      reason:
          'a check against still-locked inputs would read a shortfall '
          'that is not there',
    );

    api.discardGate!.complete();
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(state.reviewArgs!.proposalId, BigInt.two);
    expect(api.events, ['propose 1', 'discard 1', 'propose 2']);
  });

  test('a replacement waits for a displaced check that is still running '
      'to hand its proposal back', () async {
    final api = _FakeSendApi()..gate = Completer<void>();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1first'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(api.proposeAttempts, 1);

    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(
      api.proposeAttempts,
      1,
      reason:
          'the displaced check has not created, let alone released, '
          'its proposal yet',
    );

    // Rust answers the first check: its proposal has no card, is handed
    // back, and only then does the second check ask.
    api.gate!.complete();
    await pumpEventQueue();

    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.prefill.address, 'u1second');
    expect(state.reviewArgs!.proposalId, BigInt.two);
    expect(api.events, ['propose 1', 'discard 1', 'propose 2']);
  });

  test('a link arriving right after a dismiss waits for that discard '
      'too', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1first'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    notifier.dismiss();
    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(api.proposeAttempts, 1);

    api.discardGate!.complete();
    await pumpEventQueue();

    expect(
      container.read(paymentRequestFlowProvider)!.view.status,
      PaymentRequestStatus.ready,
    );
    expect(api.events, ['propose 1', 'discard 1', 'propose 2']);
  });

  test('handing the proposal back for mobile review completes only once '
      'Rust has released it', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    var handedBack = false;
    final pending = notifier.reviewHandingBack().then((args) {
      handedBack = true;
      return args;
    });
    await pumpEventQueue();

    // The card is gone at once; the caller is still waiting on the release.
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(handedBack, isFalse);
    expect(api.discarded, isEmpty);

    api.discardGate!.complete();
    final handoff = await pending;

    final args = (handoff as PaymentRequestReviewReady).args;
    expect(args.proposalId, BigInt.one);
    expect(args.isPaymentRequest, isTrue);
    expect(api.discarded, [BigInt.one]);
  });

  test('a mobile hand-back overtaken by a newer link opens nothing', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1first'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    api.discardGate = Completer<void>();
    final pending = notifier.reviewHandingBack();
    await pumpEventQueue();
    expect(container.read(paymentRequestFlowProvider), isNull);

    // A second link lands while the first proposal is still being released.
    notifier.present(request('u1second'), source: PaymentRequestSource.link);
    api.discardGate!.complete();
    await pumpEventQueue();

    expect(
      await pending,
      isA<PaymentRequestReviewOvertaken>(),
      reason:
          'the review of a request the user is no longer looking at must '
          'not open under the newer card — and the caller has to be able to '
          'tell that from "there was nothing to review"',
    );
    final state = container.read(paymentRequestFlowProvider)!;
    expect(state.prefill.address, 'u1second');
    expect(state.reviewArgs!.proposalId, BigInt.two);
    expect(
      state.view.replacedNotice,
      isTrue,
      reason:
          'the dropped Review tap is accounted for on the card that took '
          "its place; `present` could not raise the notice itself because "
          'the hand-back had already cleared the card it replaced',
    );
    expect(api.events, ['propose 1', 'discard 1', 'propose 2']);
  });

  // There is no "the card drops a memo the recipient cannot receive" case:
  // `Zip321PaymentRequest.parse` refuses `memo` on a `t`-prefixed address, so
  // no such request ever becomes a card. See
  // `test/app_payment_uri_rejection_test.dart`.

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

  test('a memo keeps its surrounding whitespace on the card', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(
          request('u1a', memoText: '  invoice 42\n'),
          source: PaymentRequestSource.link,
        );
    await pumpEventQueue();

    final view = container.read(paymentRequestFlowProvider)!.view;
    expect(
      view.memo,
      '  invoice 42\n',
      reason:
          'the pre-check proposes these exact bytes, so the card has to '
          'show them unchanged or the payer reads a memo they do not pay',
    );
    expect(view.displayMemo, '  invoice 42\n');
    expect(view.memoIsWhitespaceOnly, isFalse);
  });

  test('a whitespace-only memo still reaches the card, flagged', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(
          request('u1a', memoText: '   '),
          source: PaymentRequestSource.link,
        );
    await pumpEventQueue();

    final view = container.read(paymentRequestFlowProvider)!.view;
    expect(
      view.displayMemo,
      '   ',
      reason:
          'those bytes are paid, so the memo is present — dropping it here '
          'would hide from the payer a memo their transaction carries',
    );
    expect(
      view.memoIsWhitespaceOnly,
      isTrue,
      reason:
          'rendering the value verbatim draws nothing, so the surface needs '
          'to be told to show a placeholder instead',
    );
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

  test('a shortfall found after the wallet started scanning waits for the '
      'sync instead of blocking the card', () async {
    final api = _FakeSendApi();
    final container = makeContainer(
      api,
      sync: syncedState(spendable: BigInt.from(21000000)),
    );
    // 0.5 is more than the 0.21 the check reads, but the wallet starts
    // scanning while the address is being validated, so that 0.21 is stale
    // by the time the shortfall would be published.
    api.whileValidating = () {
      api.spendableIsAuthoritative = false;
      syncNotifier(container).emit(scanningState());
    };

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    expect(
      flowState(container)!.view.status,
      PaymentRequestStatus.syncing,
      reason: 'a final insufficient would strand the card on a stale figure',
    );
    expect(api.proposeAttempts, 0);

    // And it really is waiting on the sync: the completion re-checks it.
    api.whileValidating = null;
    api.spendableIsAuthoritative = true;
    syncNotifier(
      container,
    ).emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    expect(flowState(container)!.view.status, PaymentRequestStatus.ready);
    expect(api.proposeAttempts, 1);
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

  test('a re-check that is still syncing spends its budget, then waits for '
      'the next sync', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api, sync: scanningState());
    final sync = syncNotifier(container);
    await _presentSyncingCard(container, api);

    // First completion: the wallet reports settled, but the propose path has
    // not caught up, so the card lands back on syncing — with the sync state
    // still settled, so no further crossing is coming. The card answers that
    // itself for as long as its budget lasts (2), and then stops: the first
    // look, the crossing's re-check, and the two immediate ones.
    sync.emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();
    expect(
      flowState(container)!.view.status,
      PaymentRequestStatus.syncStalled,
      reason:
          'the budget is spent and the wallet is settled, so nothing is '
          'coming — the card stops promising an update it cannot make',
    );
    expect(
      flowState(container)!.view.resolvedStatusMessage,
      'Still syncing — check again when the wallet is up to date',
    );
    expect(api.proposeAttempts, 4);

    // A settled state that was already settled is not a new completion, and
    // the immediate budget is spent — this is where the spin would show.
    sync.emit(syncedState(spendable: BigInt.from(100000001)));
    await pumpEventQueue();
    await pumpEventQueue();
    expect(
      api.proposeAttempts,
      4,
      reason:
          'at most one re-check per sync completion, and the immediate '
          'budget is bounded',
    );

    // A real second cycle: back to scanning, then settled again.
    sync.emit(scanningState());
    await pumpEventQueue();
    api.proposeThrows = null;
    sync.emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    final state = flowState(container)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(api.proposeAttempts, 5);
    expect(state.reviewArgs!.proposalId, BigInt.one);
  });

  test('a syncing verdict on an already-settled wallet re-checks itself '
      'rather than waiting for a crossing that cannot come', () async {
    final api = _FakeSendApi()..proposeThrows = walletMustSync;
    final container = makeContainer(
      api,
      sync: syncedState(spendable: BigInt.from(100000000)),
    );
    final sync = syncNotifier(container);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    // The wallet was settled before the link arrived, so the watch has no
    // false→true crossing left to fire on. The card says it will update
    // itself when the sync finishes, so it has to ask again now.
    expect(flowState(container)!.view.status, PaymentRequestStatus.syncStalled);
    expect(
      api.proposeAttempts,
      3,
      reason:
          'the first look, plus one immediate re-check, plus one more '
          'because that landed on syncing again',
    );

    // Budget spent. Further already-settled states are not a crossing, so
    // nothing else runs: the card waits instead of spinning.
    sync.emit(syncedState(spendable: BigInt.from(100000001)));
    await pumpEventQueue();
    await pumpEventQueue();
    expect(api.proposeAttempts, 3);

    // A real sync cycle still re-checks it.
    sync.emit(scanningState());
    await pumpEventQueue();
    api.proposeThrows = null;
    sync.emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    final state = flowState(container)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(state.canReview, isTrue);
    expect(api.proposeAttempts, 4);
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

  test('a stalled card answers "Check again" by asking Rust again', () async {
    final api = _FakeSendApi()..proposeThrows = walletMustSync;
    final container = makeContainer(
      api,
      sync: syncedState(spendable: BigInt.from(100000000)),
    );
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(flowState(container)!.view.status, PaymentRequestStatus.syncStalled);
    expect(api.proposeAttempts, 3);

    // The wallet caught up between the stall and the tap, which is the whole
    // reason the card offers the tap.
    api.proposeThrows = null;
    notifier.recheck();
    await pumpEventQueue();

    final state = flowState(container)!;
    expect(state.view.status, PaymentRequestStatus.ready);
    expect(state.canReview, isTrue);
    expect(
      api.proposeAttempts,
      4,
      reason: 'a tap is one more ask, and it does not need the budget',
    );
  });

  test('a re-check that stalls again leaves the card askable', () async {
    final api = _FakeSendApi()..proposeThrows = walletMustSync;
    final container = makeContainer(
      api,
      sync: syncedState(spendable: BigInt.from(100000000)),
    );
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(api.proposeAttempts, 3);

    notifier.recheck();
    await pumpEventQueue();

    expect(
      flowState(container)!.view.status,
      PaymentRequestStatus.syncStalled,
      reason: 'still nothing to answer with, and still the user\'s move',
    );
    expect(
      api.proposeAttempts,
      4,
      reason: 'one ask per tap: the card must not spin on its own',
    );
  });

  test('recheck does nothing for a card that is not stalled', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    final notifier = container.read(paymentRequestFlowProvider.notifier);

    notifier.present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(flowState(container)!.view.status, PaymentRequestStatus.ready);

    notifier.recheck();
    await pumpEventQueue();

    expect(flowState(container)!.view.status, PaymentRequestStatus.ready);
    expect(api.proposeAttempts, 1);
  });

  test('a stalled card still takes the answer a real sync brings', () async {
    final api = _FakeSendApi()..proposeThrows = walletMustSync;
    final container = makeContainer(
      api,
      sync: syncedState(spendable: BigInt.from(100000000)),
    );
    final sync = syncNotifier(container);

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    expect(flowState(container)!.view.status, PaymentRequestStatus.syncStalled);

    // The stall is not a dead end: the watch is still installed, so a real
    // sync cycle answers the card without the user touching it.
    sync.emit(scanningState());
    await pumpEventQueue();
    api.proposeThrows = null;
    sync.emit(syncedState(spendable: BigInt.from(100000000)));
    await pumpEventQueue();

    expect(flowState(container)!.view.status, PaymentRequestStatus.ready);
  });

  test('locking re-parks the request so the unlock claim can present it '
      'again', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1a'), source: PaymentRequestSource.link);
    await pumpEventQueue();

    _securityNotifier(container).lockForTest();
    await pumpEventQueue();

    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(
      api.discarded,
      [BigInt.one],
      reason: 'the proposal is still handed back; only the request survives',
    );

    final claimed = container
        .read(paymentUriPrefillProvider.notifier)
        .takeIfFresh();
    expect(
      claimed.prefill?.address,
      'u1a',
      reason:
          'the unlock claim is what re-presents it, so the request has to be '
          'back in the park the claim reads',
    );
    expect(claimed.expired, isFalse);
  });

  test('a lock does not displace a newer link already parked', () async {
    final api = _FakeSendApi();
    final container = makeContainer(api);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(request('u1card'), source: PaymentRequestSource.link);
    await pumpEventQueue();
    // A second link arrived while the card was up and is still parked — held
    // behind a busy surface, say.
    container.read(paymentUriPrefillProvider.notifier).set(request('u1newer'));

    _securityNotifier(container).lockForTest();
    await pumpEventQueue();

    expect(
      container.read(paymentUriPrefillProvider)?.address,
      'u1newer',
      reason: 'latest link wins, the same answer the park gives everywhere',
    );
  });
}
