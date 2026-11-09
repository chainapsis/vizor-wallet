import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../../tool/l10n/korean_arb.dart' show wordJoiner;

void main() {
  group('availableAppLanguages', () {
    test('offers English, Korean and Chinese without the preview define', () {
      expect(availableAppLanguages(preview: false), [
        AppLanguage.en,
        AppLanguage.ko,
        AppLanguage.zh,
      ]);
      expect(appSupportedLocales(preview: false), const [
        Locale('en'),
        Locale('ko'),
        Locale('zh'),
      ]);
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
    test('round-trips every language', () {
      for (final language in AppLanguage.values) {
        expect(decodeAppLanguagePreference(language.tag), language);
      }
    });

    test('missing or unknown values are English', () {
      expect(decodeAppLanguagePreference(null), AppLanguage.en);
      expect(decodeAppLanguagePreference('ja'), AppLanguage.en);
      expect(decodeAppLanguagePreference('system'), AppLanguage.en);
    });

    test('a language this build does not offer shows English', () {
      expect(
        appLocaleFor(AppLanguage.ko, const [AppLanguage.en]),
        const Locale('en'),
      );
      expect(
        appLocaleFor(AppLanguage.ko, AppLanguage.values),
        const Locale('ko'),
      );
    });
  });

  group('shown language', () {
    Future<Locale> shown(
      WidgetTester tester,
      List<Locale> deviceLocales, {
      required AppLanguage saved,
    }) async {
      tester.platformDispatcher.localesTestValue = deviceLocales;
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      late Locale resolved;
      await tester.pumpWidget(
        MaterialApp(
          locale: appLocaleFor(saved, availableAppLanguages()),
          supportedLocales: appSupportedLocales(),
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

    testWidgets('a Korean device stays English until Korean is picked', (
      tester,
    ) async {
      expect(
        await shown(tester, const [
          Locale('ko', 'KR'),
        ], saved: decodeAppLanguagePreference(null)),
        const Locale('en'),
      );
    });

    testWidgets('a picked language ignores the device language', (
      tester,
    ) async {
      expect(
        await shown(tester, const [Locale('ja', 'JP')], saved: AppLanguage.ko),
        const Locale('ko'),
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
    expect(material.cancelButtonLabel, isNot('Cancel'));
  });
}
