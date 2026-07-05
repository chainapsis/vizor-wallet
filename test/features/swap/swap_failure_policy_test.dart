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

  test(
    'quote liquidity failures ask for a smaller amount or another asset',
    () {
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
        'Try a smaller amount or another asset.',
      );
    },
  );

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

  test(
    'generic ZEC deposit failures are treated as wallet preflight issues',
    () {
      final error = StateError('insufficient balance');

      expect(
        swapFailureCategory(SwapFailureOperation.sendZecDeposit, error),
        SwapFailureCategory.walletPreflight,
      );
      expect(
        swapFailureMessage(SwapFailureOperation.sendZecDeposit, error),
        'ZEC deposit could not be prepared.\nCheck your balance and try again.',
      );
    },
  );

  test('dust-guard StateError on start asks to increase the amount', () {
    // Mirrors the zwap adapter's _assertReceiveSweepable message.
    final error = StateError(
      'Amount too small: this swap yields about 10000 zatoshi of ZEC, '
      'below the 30000 zat minimum needed to cover the 15000 zat network '
      'sweep fee. Increase the amount and retry.',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.start, error),
      SwapFailureCategory.amountTooSmall,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.start, error),
      'Amount is too small to cover the network fee.\n'
      'Increase the amount and try again.',
    );
  });

  test('insufficient solver liquidity on start asks for a smaller amount', () {
    // The zwap client rethrows the price-server 409 as a StateError string.
    final error = StateError(
      'zwap GET http://localhost:3600/v1/attest?from=btc&to=zec&amount=10000 '
      '→ HTTP 409: {"error":"insufficient solver liquidity for requested '
      'amount","requiredSmallest":"17960000"}',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.start, error),
      SwapFailureCategory.noQuoteOrLiquidity,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.start, error),
      'No quote is available for this route or amount.\n'
      'Try a smaller amount or another asset.',
    );
  });

  test('connection reset on start is a reachability issue, not unknown', () {
    // dart:io SocketException stringifies with "SocketException" + the OS
    // "Connection reset by peer" text; match without importing dart:io.
    final error = Exception(
      'SocketException: Connection reset by peer (OS Error: '
      'Connection reset by peer, errno = 54), address = localhost',
    );

    expect(
      swapFailureCategory(SwapFailureOperation.start, error),
      SwapFailureCategory.networkUnreachable,
    );
    expect(
      swapFailureMessage(SwapFailureOperation.start, error),
      "Can't reach the swap service.\nCheck your connection and try again.",
    );
  });

  group('swapDepositBalanceStillConfirming', () {
    test('true for the give-ZEC unconfirmed-change race (have 0)', () {
      expect(
        swapDepositBalanceStillConfirming(
          StateError(
            'Propose failed: Insufficient balance '
            '(have 0, need 1010000 including fee)',
          ),
        ),
        isTrue,
      );
    });

    test('false for solver-side insufficient liquidity', () {
      expect(
        swapDepositBalanceStillConfirming(
          Exception('insufficient solver liquidity'),
        ),
        isFalse,
      );
      expect(
        swapDepositBalanceStillConfirming(Exception('insufficient liquidity')),
        isFalse,
      );
    });

    test('false for unrelated wallet errors (not auto-retryable)', () {
      expect(
        swapDepositBalanceStillConfirming(
          StateError('Mnemonic not found for the active account'),
        ),
        isFalse,
      );
    });
  });
}
