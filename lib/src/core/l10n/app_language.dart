import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';

/// Shows languages that are still being translated (`--dart-define=
/// VIZOR_I18N_PREVIEW=true`). Without it a build offers released languages
/// only.
const kI18nPreviewEnabled = bool.fromEnvironment('VIZOR_I18N_PREVIEW');

/// The single list of app languages. Adding a language means one entry here
/// and one `lib/l10n/app_<tag>.arb` file. Releasing one also needs the native
/// declarations in docs/i18n/adding-a-language.md, which
/// test/l10n/native_locale_declarations_test.dart keeps in step with
/// [released].
enum AppLanguage {
  // English stays first: locale resolution falls back to the first entry.
  en(
    tag: 'en',
    nativeName: 'English', // l10n-ignore: language's own name
    released: true,
  ), // l10n-ignore: language's own name
  ko(tag: 'ko', nativeName: '한국어', released: true),

  /// Simplified Chinese.
  zh(tag: 'zh', nativeName: '简体中文', released: true);

  const AppLanguage({
    required this.tag,
    required this.nativeName,
    required this.released,
  });

  /// Stored preference value and ARB locale.
  final String tag;

  /// Shown in its own script whatever the current UI language is.
  final String nativeName;

  /// Whether builds without [kI18nPreviewEnabled] offer this language.
  final bool released;

  Locale get locale => Locale(tag);

  static AppLanguage? fromTag(String? tag) {
    for (final language in values) {
      if (language.tag == tag) return language;
    }
    return null;
  }
}

/// Languages this build offers, English first.
List<AppLanguage> availableAppLanguages({bool preview = kI18nPreviewEnabled}) {
  return [
    for (final language in AppLanguage.values)
      if (language.released || preview) language,
  ];
}

List<Locale> appSupportedLocales({bool preview = kI18nPreviewEnabled}) {
  return [
    for (final language in availableAppLanguages(preview: preview))
      language.locale,
  ];
}

const appLocalizationsDelegates = AppLocalizations.localizationsDelegates;

/// The `MaterialApp.locale` for a saved preference. A language this build
/// does not offer shows English.
Locale appLocaleFor(AppLanguage preference, List<AppLanguage> available) {
  return (available.contains(preference) ? preference : AppLanguage.en).locale;
}

/// The saved language tag. Nothing stored, or a value this build does not
/// know, is English, so existing installs keep the English UI until the user
/// picks a language.
AppLanguage decodeAppLanguagePreference(String? raw) {
  return AppLanguage.fromTag(raw) ?? AppLanguage.en;
}
