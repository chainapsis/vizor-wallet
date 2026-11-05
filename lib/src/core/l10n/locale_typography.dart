import 'package:flutter/material.dart';

/// System CJK fonts for each UI language, most specific first; a family the
/// platform lacks is skipped. Without them the engine falls back by operating
/// system language, not app language, so on a Korean Mac Chinese text draws
/// Korean-style Han glyphs.
const kSimplifiedChineseFontFallback = [
  'PingFang SC',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'Noto Sans SC',
];
const kKoreanFontFallback = [
  'Apple SD Gothic Neo',
  'Malgun Gothic',
  'Noto Sans CJK KR',
  'Noto Sans KR',
];

List<String>? fontFamilyFallbackFor(Locale locale) {
  return switch (locale.languageCode) {
    'zh' => kSimplifiedChineseFontFallback,
    'ko' => kKoreanFontFallback,
    _ => null,
  };
}

/// Gives the theme text styles and the default text style the current
/// language's font fallback, so `Text` widgets using `AppTypography` styles
/// inherit it. A `TextPainter` built from a token style does not; merge with
/// `DefaultTextStyle.of(context).style` where measurement must match.
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
