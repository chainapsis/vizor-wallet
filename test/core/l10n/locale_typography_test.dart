import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/theme/app_typography.dart';

void main() {
  Future<List<String>?> fallbackOf(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: appSupportedLocales(preview: true),
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => LocaleTypography(child: child!),
        // Scaffold's Material replaces the default text style with the theme's,
        // so this also proves the theme carries the fallback.
        home: const Scaffold(body: Text('设置', style: AppTypography.bodyMedium)),
      ),
    );
    final text = tester.widget<RichText>(find.byType(RichText).last).text;
    return text.style?.fontFamilyFallback;
  }

  testWidgets('Chinese UI prefers Simplified Chinese fonts', (tester) async {
    expect(
      await fallbackOf(tester, const Locale('zh')),
      kSimplifiedChineseFontFallback,
    );
  });

  testWidgets('Korean UI prefers Korean fonts', (tester) async {
    expect(await fallbackOf(tester, const Locale('ko')), kKoreanFontFallback);
  });

  testWidgets('English UI keeps the platform fallback', (tester) async {
    expect(await fallbackOf(tester, const Locale('en')), isNull);
  });

  testWidgets('token styles keep their own font family', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: appSupportedLocales(preview: true),
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => LocaleTypography(child: child!),
        home: const Scaffold(body: Text('设置', style: AppTypography.bodyMedium)),
      ),
    );
    final style = tester
        .widget<RichText>(find.byType(RichText).last)
        .text
        .style!;
    expect(style.fontFamily, AppTypography.bodyMedium.fontFamily);
  });
}
