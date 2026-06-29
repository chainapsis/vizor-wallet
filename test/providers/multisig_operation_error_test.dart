import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/multisig_operation_error.dart';

void main() {
  test('classifies idempotency in-progress conflict as benign progress', () {
    final error = Exception(
      '{"marker":"zcash_wallet_multisig_error_v1","kind":"conflict","message":"Idempotency-Key request is still in progress","httpStatus":409,"retryable":true}',
    );

    final parsed = MultisigOperationException.from(error);

    expect(parsed.isConflict, isTrue);
    expect(parsed.isIdempotencyInProgress, isTrue);
    expect(multisigErrorLooksIdempotencyInProgress(error), isTrue);
    expect(
      normalizeMultisigProgressDetail(error.toString()),
      'Previous request is still being processed. Try again in a moment.',
    );
  });

  test('does not hide conflicting idempotency key reuse', () {
    final error = Exception(
      '{"marker":"zcash_wallet_multisig_error_v1","kind":"conflict","message":"Idempotency-Key was reused with a different request","httpStatus":409,"retryable":true}',
    );

    final parsed = MultisigOperationException.from(error);

    expect(parsed.isConflict, isTrue);
    expect(parsed.isIdempotencyInProgress, isFalse);
    expect(multisigErrorLooksIdempotencyInProgress(error), isFalse);
  });
}
