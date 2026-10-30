import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_scanner.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';

class _ValidationApi implements RustLibApi {
  String? lastNetwork;
  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) async {
    lastNetwork = network;
    return AddressValidationResult(
      isValid: address == 'u1valid',
      addressType: 'unified',
      wrongNetwork: address == 'utest1other',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final api = _ValidationApi();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  test('a bare address starts an amountless request without old terms', () {
    final result = parsePaymentRequestQr('u1valid');
    expect(result.amountText, isNull);
    expect(result.memoText, isNull);
    expect(result.label, isNull);
    expect(result.message, isNull);
    expect(result.requestSource, PaymentRequestSource.qrCode);
  });
  test('the active network validates the replacement address', () async {
    final result = await decodePaymentRequestQr(
      'zcash:u1valid?amount=1',
      networkName: 'test',
    );
    expect(api.lastNetwork, 'test');
    expect(result.amountText, '1');
    await expectLater(
      decodePaymentRequestQr('utest1other', networkName: 'main'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'This address belongs to a different network.',
        ),
      ),
    );
    await expectLater(
      decodePaymentRequestQr('not-a-zcash-address', networkName: 'main'),
      throwsFormatException,
    );
  });
  test('a scanned request carries all new terms and its input provenance', () {
    final result = parsePaymentRequestQr(
      'zcash:u1recipient?amount=0.75&memo=IG5ldyBtZW1vIA&label=New&message=Note',
    );
    expect(result.address, 'u1recipient');
    expect(result.amountText, '0.75');
    expect(result.outgoingMemoText, ' new memo ');
    expect(result.label, 'New');
    expect(result.message, 'Note');
    expect(result.requestSource, PaymentRequestSource.qrCode);
  });
  test(
    'unsupported multi-recipient terms are not downgraded to an address',
    () {
      expect(
        () => parsePaymentRequestQr(
          'zcash:u1one?address.1=u1two&amount=1&amount.1=2',
        ),
        throwsFormatException,
      );
    },
  );
  test('malformed terms and Gift links cannot become a payment request', () {
    for (final raw in [
      'zcash:u1recipient?amount=bad',
      'https://link.vizor.cash/payment-links/open#fixture',
    ]) {
      expect(() => parsePaymentRequestQr(raw), throwsFormatException);
    }
  });
}
