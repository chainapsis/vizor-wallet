/// Keystroke guards for the desktop and mobile "Request ZEC" amount fields.
/// Uses the shared amount formatters: normalize commas, prefix leading decimal
/// points with zero, and reject edits outside the precision and length limits.
library;

import 'package:flutter/services.dart';

import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/decimal_amount_input_formatter.dart';

/// A zatoshi is the eighth decimal place; cents are the second.
const int _kZecFractionDigits = 8;
const int _kUsdFractionDigits = 2;

/// `21000000.00000000` is 17 characters, and no ZEC amount is longer. The
/// dollar cap is the send composer's.
const int _kZecMaxLength = 17;
const int _kUsdMaxLength = 12;

const List<TextInputFormatter> _zecAmountFormatters = [
  CommaToDotInputFormatter(),
  DecimalAmountInputFormatter(
    maxFractionDigits: _kZecFractionDigits,
    maxLength: _kZecMaxLength,
  ),
];

const List<TextInputFormatter> _usdAmountFormatters = [
  CommaToDotInputFormatter(),
  DecimalAmountInputFormatter(
    maxFractionDigits: _kUsdFractionDigits,
    maxLength: _kUsdMaxLength,
  ),
];

/// The formatters a request amount field installs for the unit it is
/// currently collecting.
List<TextInputFormatter> requestAmountInputFormatters({required bool isUsd}) =>
    isUsd ? _usdAmountFormatters : _zecAmountFormatters;
