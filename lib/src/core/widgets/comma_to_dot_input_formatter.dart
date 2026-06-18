import 'package:flutter/services.dart';

/// Normalises a locale decimal comma (`,`) to a period (`.`).
///
/// The iOS decimal pad (`TextInputType.numberWithOptions(decimal: true)`)
/// shows the *device locale's* decimal separator, so in comma-decimal
/// locales the key emits `,`. The app standardises on `.` as the decimal
/// separator everywhere, so without this the downstream validators reject
/// the comma and the user can't type a decimal at all. Both characters
/// are a single code unit, so the in-place swap preserves the selection
/// offset.
///
/// Place this BEFORE the decimal validator in a field's `inputFormatters`
/// list so the validator only ever sees a period.
class CommaToDotInputFormatter extends TextInputFormatter {
  const CommaToDotInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains(',')) return newValue;
    return newValue.copyWith(text: newValue.text.replaceAll(',', '.'));
  }
}
