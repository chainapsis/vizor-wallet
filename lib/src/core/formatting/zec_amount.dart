import 'package:flutter/services.dart';

import '../config/network_config.dart';

final BigInt zatoshiPerZec = BigInt.from(100000000);

String _formatZecAmount(
  BigInt zatoshi, {
  int minFractionDigits = 0,
  int maxFractionDigits = 8,
  bool trimTrailingZeros = true,
}) {
  assert(minFractionDigits >= 0 && minFractionDigits <= 8);
  assert(maxFractionDigits >= 0 && maxFractionDigits <= 8);
  assert(minFractionDigits <= maxFractionDigits);

  final sign = zatoshi < BigInt.zero ? '-' : '';
  final abs = zatoshi.abs();
  final whole = abs ~/ zatoshiPerZec;
  var fraction = (abs % zatoshiPerZec).toString().padLeft(8, '0');

  if (maxFractionDigits < 8) {
    fraction = fraction.substring(0, maxFractionDigits);
  }
  if (trimTrailingZeros) {
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  }
  if (fraction.length < minFractionDigits) {
    fraction = fraction.padRight(minFractionDigits, '0');
  }

  return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
}

BigInt? _parseZecAmount(String input) {
  var value = input.trim();
  if (value.isEmpty || value == '.' || value.contains(',')) return null;
  if (value.startsWith('.')) value = '0$value';

  final parts = value.split('.');
  if (parts.length > 2) return null;

  final wholePart = parts[0];
  final fractionPart = parts.length > 1 ? parts[1] : '';
  if (!_digitsOnly(wholePart) || !_digitsOnly(fractionPart)) return null;
  if (fractionPart.length > 8) return null;

  final whole = BigInt.parse(wholePart.isEmpty ? '0' : wholePart);
  final fraction = BigInt.parse(fractionPart.padRight(8, '0'));
  return (whole * zatoshiPerZec) + fraction;
}

bool _digitsOnly(String value) => RegExp(r'^\d*$').hasMatch(value);

/// Formats a raw zatoshi value as decimal text without appending a denomination.
String formatZecAmount(BigInt zatoshi, {int minFractionDigits = 0}) {
  return _formatZecAmount(zatoshi, minFractionDigits: minFractionDigits);
}

/// Parses user-entered Zcash amount text into raw zatoshi.
BigInt? parseZecAmount(String input) {
  return ZecAmount.tryParse(input)?.zatoshi;
}

enum ZecDenomStyle { none, lower, upper }

/// Typed wrapper for amounts stored in zatoshi, with UI-oriented presets.
class ZecAmount {
  const ZecAmount.fromZatoshi(this.zatoshi);

  static ZecAmount? tryParse(String input) {
    final zatoshi = _parseZecAmount(input);
    if (zatoshi == null) return null;
    return ZecAmount.fromZatoshi(zatoshi);
  }

  final BigInt zatoshi;

  ZecAmountPretty pretty({
    int minFractionDigits = 0,
    int maxFractionDigits = 8,
    ZecDenomStyle denomStyle = ZecDenomStyle.none,
    String? denomination,
    bool signed = false,
  }) {
    return ZecAmountPretty._(
      zatoshi,
      minFractionDigits: minFractionDigits,
      maxFractionDigits: maxFractionDigits,
      denomStyle: denomStyle,
      denomination: denomination,
      signed: signed,
      trimTrailingZeros: true,
    );
  }

  ZecAmountPretty get balance => pretty(minFractionDigits: 2);

  ZecAmountPretty receiptPretty({String? denomination}) => pretty(
    minFractionDigits: 2,
    denomStyle: ZecDenomStyle.lower,
    denomination: denomination,
  );

  ZecAmountPretty get receipt => receiptPretty();

  ZecAmountPretty feePretty({String? denomination}) =>
      pretty(denomStyle: ZecDenomStyle.upper, denomination: denomination);

  ZecAmountPretty get fee => feePretty();

  ZecAmountPretty activityPretty({String? denomination}) =>
      _activity(signed: false, denomination: denomination);

  ZecAmountPretty get activity => activityPretty();

  ZecAmountPretty activityDetailPretty({String? denomination}) => pretty(
    minFractionDigits: 2,
    denomStyle: ZecDenomStyle.upper,
    denomination: denomination,
  );

  ZecAmountPretty get activityDetail => activityDetailPretty();

  ZecAmountPretty signedActivityPretty({String? denomination}) =>
      _activity(signed: true, denomination: denomination);

  ZecAmountPretty get signedActivity => signedActivityPretty();

  ZecAmountPretty _activity({
    required bool signed,
    required String? denomination,
  }) {
    final abs = zatoshi.abs();
    final whole = abs ~/ zatoshiPerZec;
    final fraction = abs % zatoshiPerZec;
    // Activity rows show extra precision for non-zero values below 0.01.
    final showFullFraction =
        whole == BigInt.zero &&
        fraction > BigInt.zero &&
        fraction < BigInt.from(1000000);

    return ZecAmountPretty._(
      signed ? zatoshi : abs,
      minFractionDigits: 0,
      maxFractionDigits: showFullFraction ? 8 : 4,
      denomStyle: ZecDenomStyle.upper,
      denomination: denomination,
      signed: signed,
      trimTrailingZeros: true,
    );
  }
}

/// Immutable formatted Zcash amount; call [toString] for amount plus denom.
class ZecAmountPretty {
  const ZecAmountPretty._(
    this._zatoshi, {
    required int minFractionDigits,
    required int maxFractionDigits,
    required ZecDenomStyle denomStyle,
    required String? denomination,
    required bool signed,
    required bool trimTrailingZeros,
  }) : _minFractionDigits = minFractionDigits,
       _maxFractionDigits = maxFractionDigits,
       _denomStyle = denomStyle,
       _denomination = denomination,
       _signed = signed,
       _trimTrailingZeros = trimTrailingZeros;

  final BigInt _zatoshi;
  final int _minFractionDigits;
  final int _maxFractionDigits;
  final ZecDenomStyle _denomStyle;
  final String? _denomination;
  final bool _signed;
  final bool _trimTrailingZeros;

  String get amountText {
    final value = _formatZecAmount(
      _zatoshi,
      minFractionDigits: _minFractionDigits,
      maxFractionDigits: _maxFractionDigits,
      trimTrailingZeros: _trimTrailingZeros,
    );
    if (!_signed) return value;
    return _zatoshi > BigInt.zero ? '+$value' : value;
  }

  String get denomText {
    final value = _denomination?.trim();
    final denomination = value == null || value.isEmpty
        ? kZcashDefaultCurrencyTicker
        : value;
    return switch (_denomStyle) {
      ZecDenomStyle.none => '',
      ZecDenomStyle.lower => denomination.toLowerCase(),
      ZecDenomStyle.upper => denomination.toUpperCase(),
    };
  }

  @override
  String toString() {
    if (_denomStyle == ZecDenomStyle.none) return amountText;
    return '$amountText $denomText';
  }
}

class ZecAmountInputFormatter extends TextInputFormatter {
  const ZecAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty) return newValue.copyWith(text: text);
    if (!RegExp(r'^[0-9.]*$').hasMatch(text)) return oldValue;
    if ('.'.allMatches(text).length > 1) return oldValue;

    final dotIndex = text.indexOf('.');
    if (dotIndex != -1 && text.length - dotIndex - 1 > 8) return oldValue;

    return newValue.copyWith(text: text);
  }
}
