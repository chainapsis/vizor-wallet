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

enum SwapFailureCategory {
  unsupportedAsset,
  amountPrecision,
  amountTooSmall,
  invalidRouteOrAddress,
  noQuoteOrLiquidity,
  serviceUnavailable,
  networkTimeout,
  networkUnreachable,
  unverifiedResponse,
  retryLater,
  walletPreflight,
  depositNotFound,
  depositRejected,
  unknown,
}

String swapFailureMessage(SwapFailureOperation operation, Object error) {
  final category = swapFailureCategory(operation, error);
  return _messageFor(operation, category);
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

  // Non-typed errors surface as plain strings (StateError from the zwap
  // adapter, SocketException from dart:io on the atomic-swap backend). Classify
  // them by content so the user gets an actionable message instead of the
  // generic "could not be started / try again later".
  final text = error.toString();
  if (_isAmountTooSmallError(text)) {
    return SwapFailureCategory.amountTooSmall;
  }
  if (_isInsufficientLiquidityError(text)) {
    return SwapFailureCategory.noQuoteOrLiquidity;
  }
  if (_isNetworkUnreachableError(text)) {
    return SwapFailureCategory.networkUnreachable;
  }

  return switch (operation) {
    SwapFailureOperation.sendZecDeposit => SwapFailureCategory.walletPreflight,
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      SwapFailureCategory.serviceUnavailable,
    _ => SwapFailureCategory.unknown,
  };
}

/// The zwap adapter's receive-side dust guard (`_assertReceiveSweepable`) and
/// the Rust sweep both reject amounts that can't cover the network fee. The
/// message is stable; match it so the user is told to increase the amount.
bool _isAmountTooSmallError(String text) {
  final t = text.toLowerCase();
  return t.contains('amount too small') ||
      (t.contains('note value') && t.contains('fee'));
}

/// The zwap price-server rejects an order (HTTP 409) when the solver can't
/// fund the requested receive amount. Surfaced as a StateError carrying the
/// server JSON. Map to the "try a smaller amount" guidance rather than the
/// generic unknown message.
bool _isInsufficientLiquidityError(String text) {
  final t = text.toLowerCase();
  return t.contains('insufficient solver liquidity') ||
      t.contains('insufficient liquidity');
}

/// True when a give-ZEC deposit `propose` failed only because the wallet's
/// CONFIRMED spendable balance was momentarily 0 — the classic unconfirmed-
/// change race right after a prior swap spent a note (the funds exist, they
/// just need a block confirmation). The give-ZEC flow uses this to auto-retry
/// the deposit once the change confirms instead of orphaning the order.
/// Deliberately distinct from solver-side "insufficient liquidity".
bool swapDepositBalanceStillConfirming(Object error) {
  final t = error.toString().toLowerCase();
  return t.contains('insufficient balance') &&
      !t.contains('insufficient solver') &&
      !t.contains('insufficient liquidity');
}

/// Connection-level failures reaching the atomic-swap orderbook/solver
/// (localhost during dev, remote in prod). Covers dart:io SocketException
/// variants and http client connection errors without importing dart:io
/// (keeps this file web-safe).
bool _isNetworkUnreachableError(String text) {
  final t = text.toLowerCase();
  return t.contains('socketexception') ||
      t.contains('connection refused') ||
      t.contains('connection reset') ||
      t.contains('connection closed') ||
      t.contains('connection terminated') ||
      t.contains('clientexception') ||
      t.contains('failed host lookup') ||
      t.contains('network is unreachable');
}

SwapFailureCategory _oneClickCategory(
  SwapFailureOperation operation,
  OneClickApiException error,
) {
  if (_isUnsupportedAssetError(error)) {
    return SwapFailureCategory.unsupportedAsset;
  }
  if (_isAmountPrecisionError(error)) {
    return SwapFailureCategory.amountPrecision;
  }
  if (_isUnverifiedResponseError(error)) {
    return SwapFailureCategory.unverifiedResponse;
  }
  if (_isNoQuoteOrLiquidityError(error)) {
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
) {
  return switch (category) {
    SwapFailureCategory.unsupportedAsset => _unsupportedAssetMessage(operation),
    SwapFailureCategory.amountPrecision =>
      'Amount has too many decimal places.\nUse fewer decimals and try again.',
    SwapFailureCategory.amountTooSmall =>
      'Amount is too small to cover the network fee.\nIncrease the amount and try again.',
    SwapFailureCategory.invalidRouteOrAddress =>
      'This route or address was rejected.\nEdit the details and request a new quote.',
    SwapFailureCategory.noQuoteOrLiquidity =>
      'No quote is available for this route or amount.\nTry a smaller amount or another asset.',
    SwapFailureCategory.serviceUnavailable => _serviceUnavailableMessage(
      operation,
    ),
    SwapFailureCategory.networkTimeout => _timeoutMessage(operation),
    SwapFailureCategory.networkUnreachable => _networkUnreachableMessage(
      operation,
    ),
    SwapFailureCategory.unverifiedResponse => _unverifiedResponseMessage(
      operation,
    ),
    SwapFailureCategory.retryLater => _retryLaterMessage(operation),
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

String _networkUnreachableMessage(SwapFailureOperation operation) {
  return switch (operation) {
    SwapFailureOperation.refreshStatus || SwapFailureOperation.submitDeposit =>
      "Can't reach the swap service.\nDo not resend funds. Try again in a moment.",
    _ => "Can't reach the swap service.\nCheck your connection and try again.",
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
  final message = error.message.toLowerCase();
  return message.contains('does not currently list') ||
      message.contains('unsupported 1click status pair');
}

bool _isAmountPrecisionError(OneClickApiException error) {
  final message = error.message.toLowerCase();
  return message.contains('amount exceeds token precision') ||
      message.contains('too many decimal');
}

bool _isUnverifiedResponseError(OneClickApiException error) {
  final message = error.message.toLowerCase();
  return message.contains('did not match the requested route') ||
      message.contains('malformed 1click') ||
      message.contains('expected a json') ||
      message.contains('missing string field') ||
      message.contains('invalid amount field');
}

bool _isNoQuoteOrLiquidityError(OneClickApiException error) {
  final message = error.message.toLowerCase();
  return message.contains('liquidity') ||
      message.contains('no quote') ||
      message.contains('no route') ||
      message.contains('route not found') ||
      message.contains('solver') ||
      message.contains('market maker') ||
      message.contains('cannot fulfill') ||
      message.contains("can't fulfill");
}
