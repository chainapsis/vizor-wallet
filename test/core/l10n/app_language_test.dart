import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../../tool/l10n/korean_arb.dart' show wordJoiner;

void main() {
  group('availableAppLanguages', () {
    test('offers released languages only without the preview define', () {
      expect(availableAppLanguages(preview: false), [AppLanguage.en]);
      expect(appSupportedLocales(preview: false), [const Locale('en')]);
    });

    test('previews every language with English first', () {
      expect(availableAppLanguages(preview: true), AppLanguage.values);
      expect(AppLanguage.values.first, AppLanguage.en);
    });

    test('every language has a generated localization', () {
      expect(
        AppLocalizations.supportedLocales.toSet(),
        appSupportedLocales(preview: true).toSet(),
      );
    });
  });

  group('preference', () {
    test('round-trips explicit languages and system', () {
      for (final language in [null, ...AppLanguage.values]) {
        expect(
          decodeAppLanguagePreference(encodeAppLanguagePreference(language)),
          language,
        );
      }
      expect(encodeAppLanguagePreference(null), kAppLanguageSystemValue);
    });

    test('unknown or missing values follow the device', () {
      expect(decodeAppLanguagePreference(null), isNull);
      expect(decodeAppLanguagePreference('ja'), isNull);
    });

    test('a language this build does not offer follows the device', () {
      final released = availableAppLanguages(preview: false);
      final all = availableAppLanguages(preview: true);
      expect(appLocaleFor(AppLanguage.ko, released), isNull);
      expect(appLocaleFor(AppLanguage.ko, all), const Locale('ko'));
      expect(appLocaleFor(null, all), isNull);
    });

    test('the device language resolves like MaterialApp', () {
      final all = availableAppLanguages(preview: true);
      const hant = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      );
      expect(
        resolveDeviceLanguage(const [Locale('ko', 'KR')], all),
        AppLanguage.ko,
      );
      expect(resolveDeviceLanguage(const [hant], all), AppLanguage.zh);
      expect(
        resolveDeviceLanguage(const [Locale('ja'), Locale('zh')], all),
        AppLanguage.zh,
      );
      expect(resolveDeviceLanguage(const [Locale('ja')], all), AppLanguage.en);
      expect(
        resolveDeviceLanguage(const [Locale('ko')], [AppLanguage.en]),
        AppLanguage.en,
      );
    });
  });

  group('device locale resolution', () {
    Future<Locale> resolve(
      WidgetTester tester,
      List<Locale> deviceLocales, {
      required bool preview,
    }) async {
      tester.platformDispatcher.localesTestValue = deviceLocales;
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      late Locale resolved;
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: appSupportedLocales(preview: preview),
          localizationsDelegates: appLocalizationsDelegates,
          home: Builder(
            builder: (context) {
              resolved = Localizations.localeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return resolved;
    }

    testWidgets('a Korean device stays English until Korean ships', (
      tester,
    ) async {
      expect(
        await resolve(tester, const [Locale('ko', 'KR')], preview: false),
        const Locale('en'),
      );
    });

    testWidgets('a Korean device gets Korean in a preview build', (
      tester,
    ) async {
      expect(
        await resolve(tester, const [Locale('ko', 'KR')], preview: true),
        const Locale('ko'),
      );
    });

    testWidgets('a Traditional Chinese device gets the zh base', (
      tester,
    ) async {
      expect(
        await resolve(tester, [
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
            countryCode: 'TW',
          ),
        ], preview: true),
        const Locale('zh'),
      );
    });

    testWidgets('an unsupported device language falls back to English', (
      tester,
    ) async {
      expect(
        await resolve(tester, const [Locale('ja', 'JP')], preview: true),
        const Locale('en'),
      );
    });
  });

  testWidgets('delegates load app and Material strings for the locale', (
    tester,
  ) async {
    late AppLocalizations app;
    late MaterialLocalizations material;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: appSupportedLocales(preview: true),
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (context) {
            app = AppLocalizations.of(context);
            material = MaterialLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // Shipped Korean strings carry word joiners (tool/l10n/korean_arb.dart).
    String visible(String text) => text.replaceAll(wordJoiner, '');
    expect(visible(app.settingsLanguageLabel), '언어');
    expect(
      visible(app.languageSystemOption(AppLanguage.ko.nativeName)),
      '시스템 (한국어)',
    );
    expect(material.cancelButtonLabel, isNot('Cancel'));
  });
}
