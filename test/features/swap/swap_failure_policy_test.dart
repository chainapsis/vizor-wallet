import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_failure_policy.dart';

void main() {
  test('credential failures are hidden as temporary service issues', () {
    const error = OneClickApiException('unauthorized', statusCode: 401);

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.serviceUnavailable,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'Swap service is temporarily unavailable.\nTry again later.',
    );
  });

  test('quote liquidity failures ask the user to adjust swap details', () {
    const error = OneClickApiException(
      'No quote: insufficient liquidity from solver',
      statusCode: 400,
    );

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.noQuoteOrLiquidity,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'No quote is available for this route or amount.\n'
      'Adjust the amount, slippage, or asset and try again.',
    );
  });

  test('quote amount minimum failures ask for a larger amount', () {
    const error = OneClickApiException(
      'NEAR Intents quote failed (400): '
      '{"message":"Amount is too low for bridge, try at least 74256"}',
      statusCode: 400,
      providerMessage: 'Amount is too low for bridge, try at least 74256',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.amountTooLow,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'Amount is too low for this swap.\nTry a larger amount.',
    );
  });

  test('no quotes found failures follow the low amount guidance', () {
    const error = OneClickApiException(
      'NEAR Intents quote failed (400): {"message":"No quotes found"}',
      statusCode: 400,
      providerMessage: 'No quotes found',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.amountTooLow,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'Amount is too low for this swap.\nTry a larger amount.',
    );
  });

  test('failed to get quote failures stay in quote unavailable guidance', () {
    const error = OneClickApiException(
      'NEAR Intents quote failed (400): {"message":"Failed to get quote"}',
      statusCode: 400,
      providerMessage: 'Failed to get quote',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.noQuoteOrLiquidity,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'No quote is available for this route or amount.\n'
      'Adjust the amount, slippage, or asset and try again.',
    );
  });

  test('low amount messages do not override status refresh guidance', () {
    const error = OneClickApiException(
      'NEAR Intents status failed (404): {"message":"No quotes found"}',
      statusCode: 404,
      providerMessage: 'No quotes found',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.refreshStatus, error),
      SwapFailureCategory.depositNotFound,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.refreshStatus, error),
      'Deposit is not indexed yet.\nCheck again in a few minutes.',
    );
  });

  test('low amount messages do not override submit deposit guidance', () {
    const error = OneClickApiException(
      'NEAR Intents submit failed (422): '
      '{"message":"Amount is too low for bridge, try at least 74256"}',
      statusCode: 422,
      providerMessage: 'Amount is too low for bridge, try at least 74256',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.submitDeposit, error),
      SwapFailureCategory.depositRejected,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.submitDeposit, error),
      'Deposit transaction was rejected.\n'
      'Check the address, memo, and tx hash.',
    );
  });

  test('route rejection asks for corrected input', () {
    const error = OneClickApiException('invalid recipient', statusCode: 422);

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.invalidRouteOrAddress,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'This route or address was rejected.\n'
      'Edit the details and request a new quote.',
    );
  });

  test('unsupported quote assets ask the user to choose another asset', () {
    const error = OneClickApiException(
      'NEAR Intents does not currently list USDC',
      operation: 'quote',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.unsupportedAsset,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'This asset is not available for swap right now.\n'
      'Choose another asset or try again later.',
    );
  });

  test('unsupported status pairs warn not to resend funds', () {
    const error = OneClickApiException(
      'Unsupported 1Click status pair: nep141:x -> nep141:y',
      operation: 'status',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.refreshStatus, error),
      SwapFailureCategory.unsupportedAsset,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.refreshStatus, error),
      'Swap status uses an unsupported asset pair.\n'
      'Do not resend funds. Try again later.',
    );
  });

  test('amount precision failures ask for fewer decimals', () {
    const error = OneClickApiException('Amount exceeds token precision');

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.amountPrecision,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'Amount has too many decimal places.\n'
      'Use fewer decimals and try again.',
    );
  });

  test('quote response mismatches are treated as unverified responses', () {
    const error = OneClickApiException(
      '1Click quote response did not match the requested route',
      operation: 'quote',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.quote, error),
      SwapFailureCategory.unverifiedResponse,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.quote, error),
      'Quote response could not be verified.\nTry again later.',
    );
  });

  test('status 404 asks the user to check again later', () {
    const error = OneClickApiException('not found', statusCode: 404);

    expect(
      swapFailureCategory(SwapFailureOperation.refreshStatus, error),
      SwapFailureCategory.depositNotFound,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.refreshStatus, error),
      'Deposit is not indexed yet.\nCheck again in a few minutes.',
    );
  });

  test('submit deposit rejection asks for deposit details', () {
    const error = OneClickApiException('tx hash rejected', statusCode: 422);

    expect(
      swapFailureCategory(SwapFailureOperation.submitDeposit, error),
      SwapFailureCategory.depositRejected,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.submitDeposit, error),
      'Deposit transaction was rejected.\n'
      'Check the address, memo, and tx hash.',
    );
  });

  test('provider server errors after deposit warn not to resend funds', () {
    const error = OneClickApiException('server error', statusCode: 500);

    expect(
      swapFailureCategory(SwapFailureOperation.submitDeposit, error),
      SwapFailureCategory.serviceUnavailable,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.submitDeposit, error),
      'Swap service is temporarily unavailable.\n'
      'Do not resend funds. Try again later.',
    );
  });

  test('post-deposit retry-later responses warn not to resend funds', () {
    const error = OneClickApiException('too many requests', statusCode: 429);

    expect(
      swapFailureCategory(SwapFailureOperation.submitDeposit, error),
      SwapFailureCategory.retryLater,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.submitDeposit, error),
      'Swap service is still processing.\n'
      'Do not resend funds. Try again later.',
    );
  });

  test('timeouts keep operation-specific retry hints', () {
    final quoteMessage = swapFailureMessage(
      SwapFailureOperation.quote,
      TimeoutException('slow provider'),
    );
    final statusMessage = swapFailureMessage(
      SwapFailureOperation.refreshStatus,
      TimeoutException('slow provider'),
    );

    expect(
      swapFailureCategory(
        SwapFailureOperation.quote,
        TimeoutException('slow provider'),
      ),
      SwapFailureCategory.networkTimeout,
    );
    expect(
      quoteMessage,
      'Quote request timed out.\nCheck your connection and try again.',
    );
    expect(
      statusMessage,
      'Request timed out.\nDo not resend funds. Try again later.',
    );
  });

  test('ZEC deposit funding failures explain fee and spendable balance', () {
    final error = Exception(
      'Propose failed: Insufficient balance '
      '(have 0, need 210000 including fee)',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.sendZecDeposit, error),
      SwapFailureCategory.zecDepositFunding,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.sendZecDeposit, error),
      'Not enough spendable ZEC to cover this swap and its network fee.\n'
      'Try a smaller amount or use Max.',
    );
  });

  test('generic ZEC deposit failures keep the wallet preflight fallback', () {
    final error = StateError('wallet database locked');

    expect(
      swapFailureCategory(SwapFailureOperation.sendZecDeposit, error),
      SwapFailureCategory.walletPreflight,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.sendZecDeposit, error),
      'ZEC deposit could not be prepared.\nCheck your balance and try again.',
    );
  });
}
