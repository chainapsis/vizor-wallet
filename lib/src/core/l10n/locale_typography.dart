import 'package:flutter/material.dart';

/// Pretendard covers modern Hangul syllables and its supported jamo; Noto Sans
/// SC covers all 8,105 TGH 2013 characters. Keep Latin token fonts and use the
/// language's system fonts for characters outside these bundled subsets.
const kKoreanUiFontFamily = 'Vizor Korean UI'; // l10n-ignore: font family name
const kChineseUiFontFamily =
    'Vizor Chinese UI'; // l10n-ignore: font family name

const kSimplifiedChineseFontFallback = [
  kChineseUiFontFamily,
  kKoreanUiFontFamily,
  'PingFang SC', // l10n-ignore: font family name
  'Microsoft YaHei', // l10n-ignore: font family name
  'Noto Sans CJK SC', // l10n-ignore: font family name
  'Noto Sans SC', // l10n-ignore: font family name
];
const kKoreanFontFallback = [
  kKoreanUiFontFamily,
  kChineseUiFontFamily,
  'Apple SD Gothic Neo', // l10n-ignore: font family name
  'Malgun Gothic', // l10n-ignore: font family name
  'Noto Sans CJK KR', // l10n-ignore: font family name
  'Noto Sans KR', // l10n-ignore: font family name
];

List<String>? fontFamilyFallbackFor(Locale locale) {
  return switch (locale.languageCode) {
    'zh' => kSimplifiedChineseFontFallback,
    'ko' => kKoreanFontFallback,
    _ => null,
  };
}

/// [style] with the current language's font fallback. A `TextPainter` does
/// not inherit [LocaleTypography], so one that measures translated text uses
/// this to get the widths the rendered `Text` will have. A style that already
/// names a fallback is returned unchanged.
TextStyle withLocaleFontFallback(BuildContext context, TextStyle style) {
  if (style.fontFamilyFallback != null) return style;
  final locale = Localizations.maybeLocaleOf(context);
  final fallback = locale == null ? null : fontFamilyFallbackFor(locale);
  if (fallback == null) return style;
  return style.copyWith(fontFamilyFallback: fallback);
}

/// Gives the theme text styles and the default text style the current
/// language's font fallback, so `Text` widgets using `AppTypography` styles
/// inherit it. A `TextPainter` built from a token style does not; measure
/// with [withLocaleFontFallback].
class LocaleTypography extends StatelessWidget {
  const LocaleTypography({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    final fallback = locale == null ? null : fontFamilyFallbackFor(locale);
    if (fallback == null) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamilyFallback: fallback),
        primaryTextTheme: theme.primaryTextTheme.apply(
          fontFamilyFallback: fallback,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontFamilyFallback: fallback),
        child: child,
      ),
    );
  }
}
