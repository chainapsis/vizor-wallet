import 'dart:async';

import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../../../../l10n/app_localizations.dart';

enum SwapFailureOperation {
  tokenList,
  quote,
  start,
  refreshStatus,
  submitDeposit,
  sendZecDeposit,
}

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
  Object error,
  AppLocalizations l10n,
) {
  final category = swapFailureCategory(operation, error);
  return _messageFor(l10n, operation, category);
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
  AppLocalizations l10n,
  SwapFailureOperation operation,
  SwapFailureCategory category,
) {
  return switch (category) {
    SwapFailureCategory.unsupportedAsset => _unsupportedAssetMessage(
      l10n,
      operation,
    ),
    SwapFailureCategory.amountTooLow => l10n.swapErrAmountTooLow,
    SwapFailureCategory.amountPrecision => l10n.swapErrAmountPrecision,
    SwapFailureCategory.invalidRouteOrAddress => l10n.swapErrInvalidRoute,
    SwapFailureCategory.noQuoteOrLiquidity => l10n.swapErrNoQuote,
    SwapFailureCategory.serviceUnavailable => _serviceUnavailableMessage(
      l10n,
      operation,
    ),
    SwapFailureCategory.networkTimeout => _timeoutMessage(l10n, operation),
    SwapFailureCategory.unverifiedResponse => _unverifiedResponseMessage(
      l10n,
      operation,
    ),
    SwapFailureCategory.retryLater => _retryLaterMessage(l10n, operation),
    SwapFailureCategory.zecDepositFunding => l10n.swapErrZecDepositFunding,
    SwapFailureCategory.walletPreflight => l10n.swapErrWalletPreflight,
    SwapFailureCategory.depositNotFound => l10n.swapErrDepositNotFound,
    SwapFailureCategory.depositRejected => l10n.swapErrDepositRejected,
    SwapFailureCategory.unknown => _unknownMessage(l10n, operation),
  };
}

String _unsupportedAssetMessage(
  AppLocalizations l10n,
  SwapFailureOperation operation,
) {
  return switch (operation) {
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      l10n.swapErrUnsupportedPairNoResend,
    _ => l10n.swapErrAssetUnavailable,
  };
}

String _serviceUnavailableMessage(
  AppLocalizations l10n,
  SwapFailureOperation operation,
) {
  return switch (operation) {
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      l10n.swapErrServiceUnavailableNoResend,
    _ => l10n.swapErrServiceUnavailable,
  };
}

String _timeoutMessage(AppLocalizations l10n, SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.quote => l10n.swapErrQuoteTimeout,
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      l10n.swapErrTimeoutNoResend,
    _ => l10n.swapErrTimeout,
  };
}

String _retryLaterMessage(
  AppLocalizations l10n,
  SwapFailureOperation operation,
) {
  return switch (operation) {
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      l10n.swapErrProcessingNoResend,
    _ => l10n.swapErrProcessing,
  };
}

String _unverifiedResponseMessage(
  AppLocalizations l10n,
  SwapFailureOperation operation,
) {
  return switch (operation) {
    SwapFailureOperation.quote => l10n.swapErrQuoteUnverified,
    _ => l10n.swapErrResponseUnverified,
  };
}

String _unknownMessage(AppLocalizations l10n, SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.tokenList => l10n.swapErrTokenList,
    SwapFailureOperation.quote => l10n.swapErrQuoteUnavailable,
    SwapFailureOperation.start => l10n.swapErrStartFailed,
    SwapFailureOperation.refreshStatus => l10n.swapErrRefreshFailed,
    SwapFailureOperation.submitDeposit => l10n.swapErrSubmitDepositFailed,
    SwapFailureOperation.sendZecDeposit => l10n.swapErrSendZecDepositFailed,
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
