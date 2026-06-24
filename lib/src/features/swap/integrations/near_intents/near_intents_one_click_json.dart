part of 'near_intents_one_click_swap_adapter.dart';

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  throw OneClickApiException('Missing string field: $key');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  throw OneClickApiException('Invalid string field: $key');
}

String? _cleanOptionalText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed.startsWith('<')) {
    return null;
  }
  return trimmed;
}

String? _firstOptionalString(
  Map<String, dynamic> json,
  String camelKey,
  String snakeKey,
) {
  final value = json[camelKey] ?? json[snakeKey];
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is List) {
    for (final item in value) {
      if (item == null) continue;
      final string = item is String ? item : item.toString();
      final trimmed = string.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
  return null;
}

String? _firstChainTxHash(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) return null;
  for (final item in value) {
    if (item is Map) {
      final raw = item['hash'] ?? item['txHash'] ?? item['tx_hash'];
      final hash = raw is String ? raw.trim() : raw?.toString().trim();
      if (hash != null && hash.isNotEmpty) return hash;
      continue;
    }
    final hash = item?.toString().trim();
    if (hash != null && hash.isNotEmpty) return hash;
  }
  return null;
}

SwapQuoteMode _oneClickSwapMode(String? value) {
  return switch (value?.trim().toUpperCase()) {
    'EXACT_OUTPUT' => SwapQuoteMode.exactOutput,
    _ => SwapQuoteMode.exactInput,
  };
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw OneClickApiException('Missing integer field: $key');
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value);
  }
  throw OneClickApiException('Invalid number field: $key');
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  throw OneClickApiException('Invalid integer field: $key');
}

int? _appFeeBpsOrNull(Object? value) {
  if (value is! List || value.isEmpty) return null;
  var total = 0;
  for (final item in value) {
    if (item is! Map) continue;
    final fee = item['fee'];
    if (fee is int) {
      total += fee;
    } else if (fee is num) {
      total += fee.toInt();
    } else if (fee is String) {
      total += int.tryParse(fee) ?? 0;
    }
  }
  return total > 0 ? total : null;
}

double _parseAmount(String value, String fieldName) {
  final parsed = double.tryParse(value);
  if (parsed == null) {
    throw OneClickApiException('Invalid amount field: $fieldName');
  }
  return parsed;
}

String _toBaseUnits(String amount, int decimals) {
  if (decimals < 0) {
    throw const OneClickApiException('Invalid token decimals');
  }
  return _decimalStringToBaseUnits(amount, decimals);
}

BigInt _parseBaseUnits(String? value, String fieldName) {
  if (value == null) {
    throw OneClickApiException('Missing $fieldName amount');
  }
  final parsed = BigInt.tryParse(value);
  if (parsed == null || parsed < BigInt.zero) {
    throw OneClickApiException('Invalid $fieldName amount');
  }
  return parsed;
}

void _validateFormattedAmountMatchesBaseUnits({
  required String formatted,
  required BigInt baseUnits,
  required int decimals,
  required String fieldName,
  String? operation,
}) {
  late final String formattedBaseUnitsText;
  try {
    formattedBaseUnitsText = _decimalStringToBaseUnits(formatted, decimals);
  } on OneClickApiException catch (error) {
    throw OneClickApiException(
      error.message,
      operation: operation ?? error.operation,
      statusCode: error.statusCode,
    );
  }
  final formattedBaseUnits = BigInt.parse(formattedBaseUnitsText);
  if (formattedBaseUnits != baseUnits) {
    throw OneClickApiException(
      'Mismatched $fieldName formatted and base-unit amounts',
      operation: operation,
    );
  }
}

String _decimalStringToBaseUnits(String value, int decimals) {
  var normalized = value.trim().toLowerCase();
  if (normalized.startsWith('+')) {
    normalized = normalized.substring(1);
  }
  if (normalized.startsWith('-') || normalized.isEmpty) {
    throw const OneClickApiException('Invalid quote amount');
  }

  final exponentParts = normalized.split('e');
  if (exponentParts.length > 2 || exponentParts.first.isEmpty) {
    throw const OneClickApiException('Invalid quote amount');
  }
  final exponent = exponentParts.length == 2
      ? int.tryParse(exponentParts[1])
      : 0;
  if (exponent == null) {
    throw const OneClickApiException('Invalid quote amount');
  }

  final mantissa = exponentParts.first;
  final decimalPointCount = '.'.allMatches(mantissa).length;
  if (decimalPointCount > 1) {
    throw const OneClickApiException('Invalid quote amount');
  }
  final pointIndex = mantissa.indexOf('.');
  final fractionalDigits = pointIndex == -1
      ? 0
      : mantissa.length - pointIndex - 1;
  var digits = mantissa.replaceAll('.', '');
  if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
    throw const OneClickApiException('Invalid quote amount');
  }

  final decimalPlaces = fractionalDigits - exponent;
  final shift = decimals - decimalPlaces;
  if (shift >= 0) {
    digits = digits.padRight(digits.length + shift, '0');
  } else {
    throw const OneClickApiException('Amount exceeds token precision');
  }

  final raw = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return raw.isEmpty ? '0' : raw;
}

String _expiryLabel(String? isoDate) {
  if (isoDate == null) {
    return 'Quote expiry pending';
  }
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) {
    return 'Quote expiry pending';
  }
  final local = parsed.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Expires $hour:$minute';
}

DateTime? _parseIsoDateTime(String? isoDate) {
  if (isoDate == null) return null;
  return DateTime.tryParse(isoDate)?.toUtc();
}

String _rateText({
  required SwapAsset sellAsset,
  required double sellAmount,
  required SwapAsset receiveAsset,
  required double receiveAmount,
}) {
  if (sellAmount <= 0) {
    return 'Rate pending';
  }
  final precision = receiveAsset == SwapAsset.zec ? 4 : 2;
  final rate = receiveAmount / sellAmount;
  return '1 ${sellAsset.symbol} = '
      '${rate.toStringAsFixed(precision)} ${receiveAsset.symbol}';
}

SwapIntentStatus _statusFromOneClick(String status, SwapQuote quote) {
  return switch (status) {
    'PENDING_DEPOSIT' =>
      quote.direction.sendsZec
          ? SwapIntentStatus.awaitingDeposit
          : SwapIntentStatus.awaitingExternalDeposit,
    'KNOWN_DEPOSIT_TX' => SwapIntentStatus.depositObserved,
    'PROCESSING' => SwapIntentStatus.processing,
    'INCOMPLETE_DEPOSIT' => SwapIntentStatus.incompleteDeposit,
    'SUCCESS' => SwapIntentStatus.complete,
    'REFUNDED' => SwapIntentStatus.refunded,
    'FAILED' => SwapIntentStatus.failed,
    _ => SwapIntentStatus.providerStatusUnknown,
  };
}

String _nextAction(SwapIntentStatus status, SwapQuote quote) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit =>
      'Send ${quote.sellAsset.symbol} to the one-time deposit address',
    SwapIntentStatus.depositObserved => 'Deposit detected',
    SwapIntentStatus.processing => 'Swap is processing',
    SwapIntentStatus.providerStatusUnknown =>
      'Provider returned a status this wallet does not recognize',
    SwapIntentStatus.incompleteDeposit => 'Deposit is below the quoted amount',
    SwapIntentStatus.complete => 'Swap complete',
    SwapIntentStatus.refunded => 'Refund sent to your refund address',
    SwapIntentStatus.expired => 'Start a fresh quote',
    SwapIntentStatus.failed => 'Swap failed',
  };
}
