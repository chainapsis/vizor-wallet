import 'dart:async';

import '../domain/near_intents_one_click_swap_provider.dart';

enum SwapFailureOperation {
  tokenList,
  quote,
  start,
  refreshStatus,
  submitDeposit,
  sendZecDeposit,
}

extension SwapFailureOperationCopy on SwapFailureOperation {
  String get prefix => switch (this) {
    SwapFailureOperation.tokenList => 'Could not load swap token list',
    SwapFailureOperation.quote => 'Could not load quote',
    SwapFailureOperation.start => 'Could not start swap',
    SwapFailureOperation.refreshStatus => 'Could not refresh status',
    SwapFailureOperation.submitDeposit => 'Could not submit deposit tx',
    SwapFailureOperation.sendZecDeposit => 'Could not send ZEC deposit',
  };
}

String swapFailureMessage(SwapFailureOperation operation, Object error) {
  return '${operation.prefix}. ${_recoveryFor(operation, error)}';
}

String _recoveryFor(SwapFailureOperation operation, Object error) {
  if (error is TimeoutException) {
    return 'The swap service timed out. Check the network connection and retry.';
  }
  if (error is FormatException) {
    return 'The swap service returned an unexpected response. Keep the current draft or receipt and retry later.';
  }
  if (error is OneClickApiException) {
    return _oneClickRecovery(operation, error);
  }
  final detail = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
  return 'Retry once. If it repeats, keep the current receipt and wait before trying again. Detail: $detail';
}

String _oneClickRecovery(
  SwapFailureOperation operation,
  OneClickApiException error,
) {
  final statusCode = error.statusCode;
  if (statusCode == 401 || statusCode == 403) {
    return 'The swap service is temporarily unavailable. Retry later.';
  }
  if (_isUnsupportedAssetError(error)) {
    return switch (operation) {
      SwapFailureOperation.quote =>
        'This route uses an asset the current swap token list does not support. Choose another asset or retry after token support changes.',
      SwapFailureOperation.refreshStatus ||
      SwapFailureOperation.submitDeposit =>
        'The swap service returned a status for an unsupported asset pair. Keep the receipt, do not resend funds, and retry status later.',
      _ =>
        'This route uses an asset the current swap token list does not support. Choose another asset or retry later.',
    };
  }
  if (statusCode == 404 && operation == SwapFailureOperation.refreshStatus) {
    return 'The swap service cannot find this deposit yet. Verify the one-time address and memo, then refresh after the source-chain transaction appears.';
  }
  if (statusCode == 400 || statusCode == 422) {
    return switch (operation) {
      SwapFailureOperation.quote =>
        'The swap service rejected this route or address. Edit the amount, asset, destination, or refund address and request a new quote.',
      SwapFailureOperation.submitDeposit =>
        'The swap service rejected the submitted tx hash. Check the deposit address, memo, and source-chain tx hash before submitting again.',
      _ =>
        'The swap service rejected the request. Review the route details and try again with a fresh quote.',
    };
  }
  if (statusCode == 409 || statusCode == 429) {
    return 'The swap service is not ready for this request yet. Wait a moment, then retry without changing the deposit details.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'The swap service returned a server error. Wait before retrying; do not resend funds while status is unclear.';
  }
  return 'The swap service returned an error. Keep the current draft or receipt and retry after checking the route details.';
}

bool _isUnsupportedAssetError(OneClickApiException error) {
  final message = error.message.toLowerCase();
  return message.contains('does not currently list') ||
      message.contains('unsupported 1click status pair');
}
