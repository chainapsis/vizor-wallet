import 'package:flutter/painting.dart';

import '../config/network_config.dart';

const kDefaultPrivacyMaskLength = 6;

/// The character a masked amount repeats: the bullet (U+2022), as in
/// password fields, so a hidden amount reads as hidden rather than as text.
const kPrivacyMaskCharacter = '\u2022';

String fixedPrivacyMask({int length = kDefaultPrivacyMaskLength}) {
  return kPrivacyMaskCharacter * length;
}

/// Letter spacing, in ems, for the mask in a Young Serif amount. The font
/// gives the bullet a digit's width (0.53 em around a 0.21 em dot), so its
/// dots stand a dot and a half apart and read as separate marks. At -0.2 em
/// about half a dot separates them, close to the app's sans text.
const kSerifPrivacyMaskLetterSpacingEm = -0.2;

/// [text] in [style], a Young Serif style, with its mask drawn tight
/// ([kSerifPrivacyMaskLetterSpacingEm]). The last bullet keeps the style's
/// own spacing, so the gap to what follows (the ticker) stays the same.
/// Text without a mask comes back as one plain span.
TextSpan serifPrivacyMaskSpan(String text, TextStyle style) {
  final start = text.indexOf(kPrivacyMaskCharacter);
  if (start < 0) return TextSpan(text: text, style: style);
  var end = start;
  while (end < text.length && text[end] == kPrivacyMaskCharacter) {
    end++;
  }
  if (end - start < 2) return TextSpan(text: text, style: style);
  final fontSize = style.fontSize ?? kDefaultFontSize;
  return TextSpan(
    style: style,
    children: [
      if (start > 0) TextSpan(text: text.substring(0, start)),
      TextSpan(
        text: text.substring(start, end - 1),
        style: TextStyle(
          letterSpacing: kSerifPrivacyMaskLetterSpacingEm * fontSize,
        ),
      ),
      TextSpan(text: text.substring(end - 1)),
    ],
  );
}

String hideIfPrivacyMode(
  String visibleText, {
  required bool privacyModeEnabled,
  int maskLength = kDefaultPrivacyMaskLength,
  String suffix = '',
}) {
  if (!privacyModeEnabled) return visibleText;
  return '${fixedPrivacyMask(length: maskLength)}$suffix';
}

String hideAmountIfPrivacyMode(
  String visibleText, {
  required bool privacyModeEnabled,
  int maskLength = kDefaultPrivacyMaskLength,
  String? denomination,
}) {
  final effectiveDenomination = denomination == null
      ? kZcashDefaultCurrencyTicker
      : denomination.trim();
  return hideIfPrivacyMode(
    visibleText,
    privacyModeEnabled: privacyModeEnabled,
    maskLength: maskLength,
    suffix: effectiveDenomination.isEmpty ? '' : ' $effectiveDenomination',
  );
}
