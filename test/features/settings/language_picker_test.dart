import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/widgets/language_picker.dart';

Widget _modal({
  AppLanguage? current,
  Future<void> Function(AppLanguage?)? onUpdate,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: appSupportedLocales(preview: true),
    localizationsDelegates: appLocalizationsDelegates,
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: DesktopLanguageModal(
            current: current,
            available: AppLanguage.values,
            onCancel: () {},
            onUpdate: onUpdate ?? (_) async {},
          ),
        ),
      ),
    ),
  );
}

/// The span of the option under [key] that draws [text].
TextSpan _span(WidgetTester tester, String key, String text) {
  final label = tester.widget<Text>(
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
  );
  return (label.textSpan! as TextSpan).children!
      .whereType<TextSpan>()
      .singleWhere((span) => span.text == text);
}

void main() {
  testWidgets('System names the language the device resolves to', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_modal());

    expect(find.text('System (한국어)'), findsOneWidget);
  });

  testWidgets('a failed save keeps the modal open with an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _modal(onUpdate: (_) async => throw StateError('storage unavailable')),
    );

    await tester.tap(find.byKey(const ValueKey('language_option_zh')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('account_modal_action_button')));
    await tester.pump();

    expect(find.text("Couldn't update language."), findsOneWidget);
    expect(find.byKey(const ValueKey('language_option_zh')), findsOneWidget);
  });

  testWidgets('the picker speaks the current UI language', (tester) async {
    await tester.pumpWidget(_modal(locale: const Locale('zh')));

    expect(find.text('语言'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    // Language names stay in their own script whatever the UI language is.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);
  });

  testWidgets('System draws the device language name in its own glyphs', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      _modal(current: AppLanguage.ko, locale: const Locale('ko')),
    );

    final name = _span(tester, 'language_option_system', '简体中文');
    expect(name.style!.locale, const Locale('zh'));
    expect(name.style!.fontFamilyFallback, kSimplifiedChineseFontFallback);
  });

  testWidgets('the mobile System option does the same', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: appSupportedLocales(preview: true),
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
        home: const Scaffold(
          body: MobileLanguageSheet(
            current: AppLanguage.ko,
            available: AppLanguage.values,
          ),
        ),
      ),
    );

    final name = _span(tester, 'mobile_language_option_system', '简体中文');
    expect(name.style!.locale, const Locale('zh'));
    expect(name.style!.fontFamilyFallback, kSimplifiedChineseFontFallback);
  });
}
