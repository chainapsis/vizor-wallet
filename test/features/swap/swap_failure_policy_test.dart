import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_one_click_swap_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_failure_policy.dart';

void main() {
  test('credential failures are shown as temporary service issues', () {
    final message = swapFailureMessage(
      SwapFailureOperation.quote,
      const OneClickApiException('unauthorized', statusCode: 401),
    );

    expect(message, contains('Could not load quote.'));
    expect(message, contains('temporarily unavailable'));
  });

  test('status 404 asks the user to verify deposit details', () {
    final message = swapFailureMessage(
      SwapFailureOperation.refreshStatus,
      const OneClickApiException('not found', statusCode: 404),
    );

    expect(message, contains('Could not refresh status.'));
    expect(message, contains('one-time address and memo'));
  });

  test('route rejection asks for a fresh quote with corrected input', () {
    final message = swapFailureMessage(
      SwapFailureOperation.quote,
      const OneClickApiException('invalid route', statusCode: 422),
    );

    expect(message, contains('Edit the amount, asset, destination'));
  });

  test('unsupported quote assets ask the user to choose another route', () {
    final message = swapFailureMessage(
      SwapFailureOperation.quote,
      const OneClickApiException(
        'NEAR Intents does not currently list USDC',
        operation: 'quote',
      ),
    );

    expect(message, contains('Could not load quote.'));
    expect(message, contains('current swap token list does not support'));
    expect(message, contains('Choose another asset'));
  });

  test('unsupported status pairs warn not to resend funds', () {
    final message = swapFailureMessage(
      SwapFailureOperation.refreshStatus,
      const OneClickApiException(
        'Unsupported 1Click status pair: nep141:x -> nep141:y',
        operation: 'status',
      ),
    );

    expect(message, contains('Could not refresh status.'));
    expect(message, contains('unsupported asset pair'));
    expect(message, contains('do not resend funds'));
  });

  test('provider server errors warn not to resend funds', () {
    final message = swapFailureMessage(
      SwapFailureOperation.submitDeposit,
      const OneClickApiException('server error', statusCode: 500),
    );

    expect(message, contains('do not resend funds'));
  });

  test('timeouts preserve a retryable network hint', () {
    final message = swapFailureMessage(
      SwapFailureOperation.tokenList,
      TimeoutException('slow provider'),
    );

    expect(message, contains('Could not load swap token list.'));
    expect(message, contains('timed out'));
  });
}
