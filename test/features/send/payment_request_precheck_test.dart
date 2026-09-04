import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

/// A fake stand-in for the two Rust calls behind the card: address validation
/// and proposal creation, plus the discard the handle owns.
class FakeSendApi {
  FakeSendApi({
    this.addressType = 'unified',
    this.addressIsValid = true,
    this.addressWrongNetwork = false,
    this.validateThrows,
    this.proposeThrows,
    this.feeZatoshi,
    this.spendableIsAuthoritativeNow = true,
  });

  String addressType;
  bool addressIsValid;

  /// Validation refused the address only because it belongs to another
  /// network. Implies [addressIsValid] false, the way Rust reports it.
  bool addressWrongNetwork;
  Object? validateThrows;
  Object? proposeThrows;
  BigInt? feeZatoshi;

  /// What the wallet's spendable balance looks like *now* — the VZR-42 gate
  /// the card re-reads before quoting a shortfall, on either side of the
  /// proposal.
  bool spendableIsAuthoritativeNow;

  /// Runs inside the awaited address validation, so a test can move the
  /// wallet under a check that is already in flight.
  void Function()? whileValidating;

  var validateCalls = 0;
  var proposeCalls = 0;
  String? lastValidatedNetwork;
  final discarded = <BigInt>[];
  String? lastProposedMemo;
  String? lastRequestedBy;

  Future<rust_sync.AddressValidationResult> validateAddress({
    required String address,
    required String network,
  }) async {
    validateCalls++;
    lastValidatedNetwork = network;
    whileValidating?.call();
    final failure = validateThrows;
    if (failure != null) throw failure;
    return rust_sync.AddressValidationResult(
      isValid: addressIsValid && !addressWrongNetwork,
      addressType: addressType,
      wrongNetwork: addressWrongNetwork,
    );
  }

  Future<SendReviewArgs> proposeTransfer({
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
    proposeCalls++;
    lastProposedMemo = memo;
    lastRequestedBy = requestedBy;
    final failure = proposeThrows;
    if (failure != null) throw failure;
    return SendReviewArgs(
      proposalId: BigInt.from(7),
      sendFlowId: sendFlowId,
      proposalAccountUuid: accountUuid,
      address: address,
      addressType: addressType,
      amountZatoshi: amountZatoshi,
      feeZatoshi: feeZatoshi ?? BigInt.from(10000),
      needsSaplingParams: false,
      memo: memo,
      isPaymentRequest: isPaymentRequest,
      requestedBy: sanitisePaymentRequestLabel(requestedBy),
      requestedAmountZatoshi: requestedAmountZatoshi,
    );
  }

  Future<void> discardProposal({
    required BigInt proposalId,
    required String sendFlowId,
    required String logContext,
  }) async {
    discarded.add(proposalId);
  }

  PaymentRequestPrecheck get precheck => PaymentRequestPrecheck(
    spendableIsAuthoritativeNow: () => spendableIsAuthoritativeNow,
    validateAddress: validateAddress,
    proposeTransfer: proposeTransfer,
    discardProposal: discardProposal,
  );
}

SendPrefillArgs prefill({
  String? amountText = '0.5',
  String? memoText,
  bool preserveMemoText = false,
}) => SendPrefillArgs(
  id: 'payment-uri-1',
  source: kPaymentUriPrefillSource,
  address: 'u1recipient',
  amountText: amountText,
  memoText: memoText,
  preserveMemoText: preserveMemoText,
  label: 'Coffee  shop\n',
);

Future<PaymentRequestPrecheckResult> run(
  FakeSendApi api, {
  SendPrefillArgs? request,
  String? accountUuid = 'account-1',
  BigInt? spendable,
  bool spendableIsAuthoritative = true,
}) => api.precheck.run(
  prefill: request ?? prefill(),
  sendFlowId: 'flow-1',
  accountUuid: accountUuid,
  spendableBalance: spendable ?? BigInt.from(100000000),
  spendableIsAuthoritative: spendableIsAuthoritative,
);

void main() {
  test('a payable request proposes and hands back a live proposal', () async {
    final api = FakeSendApi();
    final result = await run(api);

    expect(result, isA<PaymentRequestPrecheckReady>());
    final ready = result as PaymentRequestPrecheckReady;
    expect(ready.proposal, isNotNull);
    expect(api.proposeCalls, 1);
    expect(ready.reviewArgs!.isPaymentRequest, isTrue);
    expect(ready.reviewArgs!.amountZatoshi, BigInt.from(50000000));
    expect(
      ready.reviewArgs!.requestedAmountZatoshi,
      ready.reviewArgs!.amountZatoshi,
      reason: 'an unedited request was requested for exactly this amount',
    );
    expect(
      ready.reviewArgs!.requestedBy,
      'Coffee shop',
      reason: 'the untrusted label is collapsed to one line',
    );
  });

  test('an amount-less request is ready with nothing proposed', () async {
    final api = FakeSendApi();
    final result = await run(api, request: prefill(amountText: null));

    expect(result, isA<PaymentRequestPrecheckReady>());
    expect((result as PaymentRequestPrecheckReady).proposal, isNull);
    expect(
      api.proposeCalls,
      0,
      reason: 'there is no amount to propose, so nothing is locked',
    );
  });

  test('an unpayable address never reaches the proposal', () async {
    final api = FakeSendApi(addressIsValid: false);
    final result = await run(api);
    expect(result, isA<PaymentRequestPrecheckInvalidAddress>());
    expect(
      (result as PaymentRequestPrecheckInvalidAddress).message,
      isNull,
      reason: 'a malformed address keeps the card default copy',
    );
    expect(api.proposeCalls, 0);
  });

  test('validation runs against the network this build talks to', () async {
    final api = FakeSendApi();
    await run(api);
    expect(api.lastValidatedNetwork, kZcashDefaultNetworkName);
  });

  test('an address for another network says so instead of "invalid"', () async {
    final api = FakeSendApi(addressWrongNetwork: true);
    final result = await run(api);

    expect(result, isA<PaymentRequestPrecheckInvalidAddress>());
    expect(
      (result as PaymentRequestPrecheckInvalidAddress).message,
      kWrongNetworkAddressMessage,
    );
    expect(
      api.proposeCalls,
      0,
      reason: 'the address is unpayable here, so nothing is locked',
    );
  });

  test('a validation call that throws is an invalid address', () async {
    final api = FakeSendApi(validateThrows: Exception('rust exploded'));
    expect(await run(api), isA<PaymentRequestPrecheckInvalidAddress>());
    expect(api.proposeCalls, 0);
  });

  test('an amount above the spendable balance never proposes', () async {
    final api = FakeSendApi();
    final result = await run(api, spendable: BigInt.from(21000000));

    expect(result, isA<PaymentRequestPrecheckInsufficientFunds>());
    expect(
      (result as PaymentRequestPrecheckInsufficientFunds).spendableText,
      '0.21 ZEC',
    );
    expect(api.proposeCalls, 0);
  });

  test('a shortfall whose balance stopped being settled mid-check waits for '
      'the sync', () async {
    final api = FakeSendApi();
    // The wallet starts scanning while the check is awaiting the address
    // validation, so the settled 0.21 it read is already history.
    api.whileValidating = () => api.spendableIsAuthoritativeNow = false;

    final result = await run(api, spendable: BigInt.from(21000000));

    expect(
      result,
      isA<PaymentRequestPrecheckSyncing>(),
      reason:
          'VZR-42: a shortfall against a balance the scan has moved under is '
          'not a final answer, and only syncing re-checks itself',
    );
    expect(api.proposeCalls, 0);
  });

  test('a shortfall on a balance that is not settled yet defers to the '
      'proposal', () async {
    final api = FakeSendApi();
    final result = await run(
      api,
      spendable: BigInt.zero,
      spendableIsAuthoritative: false,
    );

    expect(
      result,
      isA<PaymentRequestPrecheckReady>(),
      reason: 'VZR-42: a mid-scan zero is not an answer about affordability',
    );
    expect(
      api.proposeCalls,
      1,
      reason: 'the proposal waits for the authoritative spendable and decides',
    );
  });

  test('an unsettled balance still reports the insufficiency Rust '
      'confirms', () async {
    final api = FakeSendApi(
      proposeThrows: StateError('InsufficientFunds: not enough'),
    );
    final result = await run(
      api,
      spendable: BigInt.from(21000000),
      spendableIsAuthoritative: false,
    );

    expect(
      result,
      isA<PaymentRequestPrecheckInsufficientFunds>(),
      reason:
          'the proposal waited for a settled spendable, and the balance is '
          'still settled when its answer comes back',
    );
    expect(api.proposeCalls, 1);
  });

  test('a shortfall Rust reports while the balance is still moving is '
      'syncing', () async {
    final api = FakeSendApi(
      proposeThrows: StateError(
        'Insufficient balance (have 0, need 0.5 including fee)',
      ),
      spendableIsAuthoritativeNow: false,
    );
    final result = await run(
      api,
      spendable: BigInt.zero,
      spendableIsAuthoritative: false,
    );

    expect(
      result,
      isA<PaymentRequestPrecheckSyncing>(),
      reason:
          'VZR-42: a shortfall computed against a partly-scanned wallet is '
          'not an answer, wherever it was computed',
    );
    expect(api.proposeCalls, 1);
  });

  test('a mid-sync proposal failure is syncing, never insufficient', () async {
    final api = FakeSendApi(
      proposeThrows: StateError('Wallet sync is still finishing. Try again.'),
    );
    expect(await run(api), isA<PaymentRequestPrecheckSyncing>());
  });

  test('an insufficient-funds proposal failure states the balance', () async {
    final api = FakeSendApi(
      proposeThrows: Exception('InsufficientFunds: available 0.21'),
    );
    final result = await run(api, spendable: BigInt.from(21000000));
    expect(result, isA<PaymentRequestPrecheckInsufficientFunds>());
    expect(
      (result as PaymentRequestPrecheckInsufficientFunds).spendableText,
      '0.21 ZEC',
    );
  });

  test('a request with no active account names the fix', () async {
    final api = FakeSendApi();
    final result = await run(api, accountUuid: null);

    expect(result, isA<PaymentRequestPrecheckFailed>());
    expect(
      (result as PaymentRequestPrecheckFailed).message,
      'No active account — choose one, then open this link again',
      reason: 'the same term the composer and Receive already use',
    );
    expect(api.proposeCalls, 0);
  });

  test('a network failure says so in the card\'s own words', () async {
    final api = FakeSendApi(proposeThrows: Exception('grpc connect failed'));
    final result = await run(api);
    expect(result, isA<PaymentRequestPrecheckFailed>());
    expect(
      (result as PaymentRequestPrecheckFailed).message,
      "Couldn't reach the network — check your connection and open the link "
      'again',
    );
  });

  test('any other proposal failure names the exit the card has', () async {
    final api = FakeSendApi(proposeThrows: Exception('something unmapped'));
    final result = await run(api);
    expect(result, isA<PaymentRequestPrecheckFailed>());
    expect(
      (result as PaymentRequestPrecheckFailed).message,
      "Couldn't check this request — open Edit to review the details",
      reason: 'nothing was sent from this card, so no send wording applies',
    );
  });

  test('an address the proposal refuses is an invalid address', () async {
    for (final raw in const [
      'Error decoding the address from a payment request',
      'Bad address: IncorrectNetwork { expected: Main, actual: Test }',
    ]) {
      final api = FakeSendApi(proposeThrows: Exception(raw));
      expect(
        await run(api),
        isA<PaymentRequestPrecheckInvalidAddress>(),
        reason: raw,
      );
    }
  });

  test('the sync message Rust actually emits is syncing', () async {
    final api = FakeSendApi(
      proposeThrows: StateError(
        'Wallet must sync before sending; no chain tip is known yet',
      ),
    );
    expect(await run(api), isA<PaymentRequestPrecheckSyncing>());
  });

  test('an unreadable amount fails instead of proposing zero', () async {
    final api = FakeSendApi();
    final result = await run(api, request: prefill(amountText: 'not-a-number'));
    expect(result, isA<PaymentRequestPrecheckFailed>());
    expect(
      (result as PaymentRequestPrecheckFailed).message,
      "This link doesn't ask for a payable amount — enter one to continue",
    );
    expect(api.proposeCalls, 0);
  });

  test('a request for zero is treated as a request with no amount', () async {
    for (final amount in const ['0', '0.00000000']) {
      final api = FakeSendApi();
      final result = await run(api, request: prefill(amountText: amount));

      expect(result, isA<PaymentRequestPrecheckReady>(), reason: amount);
      expect(
        (result as PaymentRequestPrecheckReady).proposal,
        isNull,
        reason: amount,
      );
      expect(
        api.proposeCalls,
        0,
        reason: 'zero is not a payment, so there is nothing to propose',
      );
    }
  });

  // A memo on a transparent-like recipient has no branch here on purpose:
  // `Zip321PaymentRequest.parse` refuses that combination outright, so the
  // payer is told the link is invalid before a card is built. The end-to-end
  // proof is `test/app_payment_uri_rejection_test.dart`, "a memo on a
  // transparent address is refused as an invalid link".

  test(
    'a memo the link says to preserve reaches the proposal untouched',
    () async {
      final api = FakeSendApi();
      await run(
        api,
        request: prefill(memoText: '  order 42\n', preserveMemoText: true),
      );

      expect(
        api.lastProposedMemo,
        '  order 42\n',
        reason:
            'the compose form preserves the same bytes through '
            'preserveMemoText, so both routes must pay the same memo',
      );
    },
  );

  test('a shielded recipient keeps the memo', () async {
    final api = FakeSendApi();
    await run(api, request: prefill(memoText: 'thanks'));
    expect(api.lastProposedMemo, 'thanks');
  });

  group('proposal handle', () {
    test('discard is idempotent', () async {
      final api = FakeSendApi();
      final ready = await run(api) as PaymentRequestPrecheckReady;
      final handle = ready.proposal!;

      await handle.discard();
      await handle.discard();
      await handle.discard();

      expect(api.discarded, [BigInt.from(7)]);
    });

    test('release transfers ownership, so discard becomes a no-op', () async {
      final api = FakeSendApi();
      final ready = await run(api) as PaymentRequestPrecheckReady;
      final handle = ready.proposal!;

      expect(handle.release().proposalId, BigInt.from(7));
      expect(handle.isReleased, isTrue);
      await handle.discard();

      expect(
        api.discarded,
        isEmpty,
        reason: 'the review screen owns the proposal after a release',
      );
    });
  });
}
