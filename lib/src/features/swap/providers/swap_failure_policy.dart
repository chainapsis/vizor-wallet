import 'dart:async';

import '../../../core/zcash/network_upgrade_hold.dart';
import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../models/swap_message.dart';

export '../models/swap_message.dart'
    show
        SwapFailureCategory,
        SwapFailureMessage,
        SwapFailureOperation,
        SwapFailureSurface,
        SwapLiteralMessage,
        SwapMessage;

/// The message for a failed swap [operation]. The network-upgrade hold stays
/// English pass-through text; everything else is a code the screen words.
SwapMessage swapFailureMessage(
  SwapFailureOperation operation,
  Object error, {
  SwapFailureSurface surface = SwapFailureSurface.swap,
  bool torEnabled = false,
}) {
  if (operation == SwapFailureOperation.sendZecDeposit) {
    final upgradeHold = networkUpgradeHoldMessage(error);
    if (upgradeHold != null) return SwapLiteralMessage(upgradeHold);
  }
  return SwapFailureMessage(
    operation,
    swapFailureCategory(operation, error, torEnabled: torEnabled),
    surface: surface,
  );
}

SwapFailureCategory swapFailureCategory(
  SwapFailureOperation operation,
  Object error, {
  bool torEnabled = false,
}) {
  if (error is TimeoutException) {
    return SwapFailureCategory.networkTimeout;
  }
  if (error is FormatException) {
    return SwapFailureCategory.unverifiedResponse;
  }
  if (error is OneClickApiException) {
    return _oneClickCategory(operation, error, torEnabled: torEnabled);
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
  OneClickApiException error, {
  required bool torEnabled,
}) {
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
  if (torEnabled && _isTorExitBlockedResponse(error)) {
    return SwapFailureCategory.torBlocked;
  }
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

bool _isTorExitBlockedResponse(OneClickApiException error) {
  if (error.statusCode != 403) return false;
  final body = error.responseBody?.toLowerCase();
  return body != null &&
      body.contains('request blocked') &&
      body.contains('cloudfront');
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
