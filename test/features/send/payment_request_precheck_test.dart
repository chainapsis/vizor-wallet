import 'package:flutter_test/flutter_test.dart';
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
    this.validateThrows,
    this.proposeThrows,
    this.feeZatoshi,
  });

  String addressType;
  bool addressIsValid;
  Object? validateThrows;
  Object? proposeThrows;
  BigInt? feeZatoshi;

  var validateCalls = 0;
  var proposeCalls = 0;
  final discarded = <BigInt>[];
  String? lastProposedMemo;
  String? lastRequestedBy;

  Future<rust_sync.AddressValidationResult> validateAddress({
    required String address,
  }) async {
    validateCalls++;
    final failure = validateThrows;
    if (failure != null) throw failure;
    return rust_sync.AddressValidationResult(
      isValid: addressIsValid,
      addressType: addressType,
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
    validateAddress: validateAddress,
    proposeTransfer: proposeTransfer,
    discardProposal: discardProposal,
  );
}

SendPrefillArgs prefill({String? amountText = '0.5', String? memoText}) =>
    SendPrefillArgs(
      id: 'payment-uri-1',
      source: kPaymentUriPrefillSource,
      address: 'u1recipient',
      amountText: amountText,
      memoText: memoText,
      label: 'Coffee  shop\n',
    );

Future<PaymentRequestPrecheckResult> run(
  FakeSendApi api, {
  SendPrefillArgs? request,
  String? accountUuid = 'account-1',
  BigInt? spendable,
}) => api.precheck.run(
  prefill: request ?? prefill(),
  sendFlowId: 'flow-1',
  accountUuid: accountUuid,
  spendableBalance: spendable ?? BigInt.from(100000000),
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
    expect(await run(api), isA<PaymentRequestPrecheckInvalidAddress>());
    expect(api.proposeCalls, 0);
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

  test('any other proposal failure carries a friendly message', () async {
    final api = FakeSendApi(proposeThrows: Exception('grpc connect failed'));
    final result = await run(api);
    expect(result, isA<PaymentRequestPrecheckFailed>());
    expect(
      (result as PaymentRequestPrecheckFailed).message,
      'Network error. Check your connection and try again.',
    );
  });

  test('an unreadable amount fails instead of proposing zero', () async {
    final api = FakeSendApi();
    final result = await run(api, request: prefill(amountText: 'not-a-number'));
    expect(result, isA<PaymentRequestPrecheckFailed>());
    expect(api.proposeCalls, 0);
  });

  test('a transparent recipient drops the memo the link carried', () async {
    final api = FakeSendApi(addressType: 'transparent');
    await run(api, request: prefill(memoText: 'thanks'));
    expect(api.lastProposedMemo, isNull);
  });

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
