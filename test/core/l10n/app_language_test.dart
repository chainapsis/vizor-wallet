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
      final released = availableAppLanguages(preview: false);
      final all = availableAppLanguages(preview: true);
      expect(appLocaleFor(AppLanguage.ko, released), const Locale('en'));
      expect(appLocaleFor(AppLanguage.ko, all), const Locale('ko'));
    });
  });

  group('shown language', () {
    Future<Locale> shown(
      WidgetTester tester,
      List<Locale> deviceLocales, {
      required AppLanguage saved,
      required bool preview,
    }) async {
      tester.platformDispatcher.localesTestValue = deviceLocales;
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      late Locale resolved;
      await tester.pumpWidget(
        MaterialApp(
          locale: appLocaleFor(saved, availableAppLanguages(preview: preview)),
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

    testWidgets('a Korean device stays English until Korean is picked', (
      tester,
    ) async {
      expect(
        await shown(
          tester,
          const [Locale('ko', 'KR')],
          saved: decodeAppLanguagePreference(null),
          preview: true,
        ),
        const Locale('en'),
      );
    });

    testWidgets('a picked language ignores the device language', (
      tester,
    ) async {
      expect(
        await shown(
          tester,
          const [Locale('ja', 'JP')],
          saved: AppLanguage.ko,
          preview: true,
        ),
        const Locale('ko'),
      );
    });

    testWidgets('Korean stays English until it ships', (tester) async {
      expect(
        await shown(
          tester,
          const [Locale('ko', 'KR')],
          saved: AppLanguage.ko,
          preview: false,
        ),
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
    expect(material.cancelButtonLabel, isNot('Cancel'));
  });
}
