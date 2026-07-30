import 'dart:async';

import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';

enum SwapFailureOperation {
  tokenList,
  quote,
  start,
  refreshStatus,
  submitDeposit,
  sendZecDeposit,
}

enum SwapFailureSurface { swap, pay }

enum SwapFailureCategory {
  unsupportedAsset,
  amountTooLow,
  amountPrecision,
  invalidRouteOrAddress,
  noQuoteOrLiquidity,
  serviceUnavailable,
  networkTimeout,
  unverifiedResponse,
  retryLater,
  zecDepositFunding,
  walletPreflight,
  depositNotFound,
  depositRejected,
  unknown,
}

String swapFailureMessage(
  SwapFailureOperation operation,
  Object error, {
  SwapFailureSurface surface = SwapFailureSurface.swap,
}) {
  final category = swapFailureCategory(operation, error);
  return _messageFor(operation, category, surface);
}

SwapFailureCategory swapFailureCategory(
  SwapFailureOperation operation,
  Object error,
) {
  if (error is TimeoutException) {
    return SwapFailureCategory.networkTimeout;
  }
  if (error is FormatException) {
    return SwapFailureCategory.unverifiedResponse;
  }
  if (error is OneClickApiException) {
    return _oneClickCategory(operation, error);
  }

  if (operation == SwapFailureOperation.sendZecDeposit &&
      _isZecDepositFundingError(error)) {
    return SwapFailureCategory.zecDepositFunding;
  }

  return switch (operation) {
    SwapFailureOperation.sendZecDeposit => SwapFailureCategory.walletPreflight,
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      SwapFailureCategory.serviceUnavailable,
    _ => SwapFailureCategory.unknown,
  };
}

SwapFailureCategory _oneClickCategory(
  SwapFailureOperation operation,
  OneClickApiException error,
) {
  if (_isUnsupportedAssetError(error)) {
    return SwapFailureCategory.unsupportedAsset;
  }
  final isQuoteFailure = operation == SwapFailureOperation.quote;
  if (isQuoteFailure && _isAmountTooLowError(error)) {
    return SwapFailureCategory.amountTooLow;
  }
  if (isQuoteFailure && _isAmountPrecisionError(error)) {
    return SwapFailureCategory.amountPrecision;
  }
  if (_isUnverifiedResponseError(error)) {
    return SwapFailureCategory.unverifiedResponse;
  }
  if (isQuoteFailure && _isNoQuoteOrLiquidityError(error)) {
    return SwapFailureCategory.noQuoteOrLiquidity;
  }

  final statusCode = error.statusCode;
  if (statusCode == 401 || statusCode == 403) {
    return SwapFailureCategory.serviceUnavailable;
  }
  if (statusCode == 404 && operation == SwapFailureOperation.refreshStatus) {
    return SwapFailureCategory.depositNotFound;
  }
  if (operation == SwapFailureOperation.submitDeposit &&
      (statusCode == 400 || statusCode == 404 || statusCode == 422)) {
    return SwapFailureCategory.depositRejected;
  }
  if (statusCode == 400 || statusCode == 422) {
    return SwapFailureCategory.invalidRouteOrAddress;
  }
  if (statusCode == 409 || statusCode == 429) {
    return SwapFailureCategory.retryLater;
  }
  if (statusCode != null && statusCode >= 500) {
    return SwapFailureCategory.serviceUnavailable;
  }
  return SwapFailureCategory.unknown;
}

String _messageFor(
  SwapFailureOperation operation,
  SwapFailureCategory category,
  SwapFailureSurface surface,
) {
  return switch (category) {
    SwapFailureCategory.unsupportedAsset => _unsupportedAssetMessage(operation),
    SwapFailureCategory.amountTooLow =>
      surface == SwapFailureSurface.pay
          ? 'Amount is too low for this payment.\nTry a larger amount.'
          : 'Amount is too low for this swap.\nTry a larger amount.',
    SwapFailureCategory.amountPrecision =>
      'Amount has too many decimal places.\nUse fewer decimals and try again.',
    SwapFailureCategory.invalidRouteOrAddress =>
      'This route or address was rejected.\nEdit the details and request a new quote.',
    SwapFailureCategory.noQuoteOrLiquidity =>
      'No quote is available for this route or amount.\n'
          'Adjust the amount, slippage, or asset and try again.',
    SwapFailureCategory.serviceUnavailable => _serviceUnavailableMessage(
      operation,
    ),
    SwapFailureCategory.networkTimeout => _timeoutMessage(operation),
    SwapFailureCategory.unverifiedResponse => _unverifiedResponseMessage(
      operation,
    ),
    SwapFailureCategory.retryLater => _retryLaterMessage(operation),
    SwapFailureCategory.zecDepositFunding =>
      'Not enough spendable ZEC to cover this swap and its network fee.\n'
          'Try a smaller amount or use Max.',
    SwapFailureCategory.walletPreflight =>
      'ZEC deposit could not be prepared.\nCheck your balance and try again.',
    SwapFailureCategory.depositNotFound =>
      'Deposit is not indexed yet.\nCheck again in a few minutes.',
    SwapFailureCategory.depositRejected =>
      'Deposit transaction was rejected.\nCheck the address, memo, and tx hash.',
    SwapFailureCategory.unknown => _unknownMessage(operation),
  };
}

String _unsupportedAssetMessage(SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      'Swap status uses an unsupported asset pair.\nDo not resend funds. Try again later.',
    _ =>
      'This asset is not available for swap right now.\nChoose another asset or try again later.',
  };
}

String _serviceUnavailableMessage(SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      'Swap service is temporarily unavailable.\nDo not resend funds. Try again later.',
    _ => 'Swap service is temporarily unavailable.\nTry again later.',
  };
}

String _timeoutMessage(SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.quote =>
      'Quote request timed out.\nCheck your connection and try again.',
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      'Request timed out.\nDo not resend funds. Try again later.',
    _ => 'Request timed out.\nCheck your connection and try again.',
  };
}

String _retryLaterMessage(SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      'Swap service is still processing.\nDo not resend funds. Try again later.',
    _ => 'Swap service is still processing.\nWait a moment and try again.',
  };
}

String _unverifiedResponseMessage(SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.quote =>
      'Quote response could not be verified.\nTry again later.',
    _ => 'Swap response could not be verified.\nTry again later.',
  };
}

String _unknownMessage(SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.tokenList =>
      'Swap tokens could not be loaded.\nTry again later.',
    SwapFailureOperation.quote =>
      'Quote is unavailable right now.\nTry again later.',
    SwapFailureOperation.start =>
      'Swap could not be started.\nTry again later.',
    SwapFailureOperation.refreshStatus =>
      'Could not refresh swap status.\nTry again later.',
    SwapFailureOperation.submitDeposit =>
      'Deposit status could not be submitted.\nTry again later.',
    SwapFailureOperation.sendZecDeposit =>
      'ZEC deposit could not be sent.\nTry again later.',
  };
}

bool _isUnsupportedAssetError(OneClickApiException error) {
  final message = _oneClickSearchableMessage(error);
  return message.contains('does not currently list') ||
      message.contains('unsupported 1click status pair') ||
      message.contains('tokenin is not valid') ||
      message.contains('tokenout is not valid');
}

bool _isAmountTooLowError(OneClickApiException error) {
  final message = _oneClickSearchableMessage(error);
  return message.contains('amount is too low') ||
      message.contains('try at least') ||
      message.contains('no quotes found') ||
      message.contains('below minimum') ||
      (message.contains('minimum') && message.contains('amount'));
}

bool _isAmountPrecisionError(OneClickApiException error) {
  final message = _oneClickSearchableMessage(error);
  return message.contains('amount exceeds token precision') ||
      message.contains('too many decimal');
}

bool _isUnverifiedResponseError(OneClickApiException error) {
  final message = _oneClickSearchableMessage(error);
  return message.contains('did not match the requested route') ||
      message.contains('malformed 1click') ||
      message.contains('expected a json') ||
      message.contains('missing string field') ||
      message.contains('invalid amount field');
}

bool _isNoQuoteOrLiquidityError(OneClickApiException error) {
  final message = _oneClickSearchableMessage(error);
  return message.contains('liquidity') ||
      message.contains('failed to get quote') ||
      message.contains('no quote') ||
      message.contains('no route') ||
      message.contains('route not found') ||
      message.contains('solver') ||
      message.contains('market maker') ||
      message.contains('cannot fulfill') ||
      message.contains("can't fulfill");
}

bool _isZecDepositFundingError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('insufficient balance') ||
      message.contains('insufficient funds');
}

String _oneClickSearchableMessage(OneClickApiException error) {
  return [
    error.providerMessage,
    error.message,
  ].whereType<String>().join(' ').toLowerCase();
}
