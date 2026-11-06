import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';

/// Shows languages that are still being translated (`--dart-define=
/// VIZOR_I18N_PREVIEW=true`). Without it a build offers released languages
/// only, so a Korean or Chinese device keeps the English UI until those
/// translations ship.
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
  ko(tag: 'ko', nativeName: '한국어', released: false),

  /// Simplified Chinese. The `zh` base also serves Traditional-script devices
  /// until a `zh_Hant` file exists.
  zh(tag: 'zh', nativeName: '简体中文', released: false);

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

/// Stored value for "follow the device language".
const kAppLanguageSystemValue = 'system';

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

/// The `MaterialApp.locale` for a saved preference. `null` follows the
/// device; a language this build does not offer also follows the device.
Locale? appLocaleFor(AppLanguage? preference, List<AppLanguage> available) {
  if (preference == null || !available.contains(preference)) return null;
  return preference.locale;
}

/// The language "follow the device" resolves to, matching `MaterialApp`'s
/// default resolution: the first device locale whose language is offered,
/// else English.
AppLanguage resolveDeviceLanguage(
  List<Locale> deviceLocales,
  List<AppLanguage> available,
) {
  final locale = basicLocaleListResolution(deviceLocales, [
    for (final language in available) language.locale,
  ]);
  return AppLanguage.fromTag(locale.languageCode) ?? AppLanguage.en;
}

/// `null` means follow the device language, including for unknown values.
AppLanguage? decodeAppLanguagePreference(String? raw) {
  return AppLanguage.fromTag(raw);
}

String encodeAppLanguagePreference(AppLanguage? preference) {
  return preference?.tag ?? kAppLanguageSystemValue;
}
