# Adding a language

1. Add an entry to `AppLanguage` in `lib/src/core/l10n/app_language.dart`
   with `released: false`, its tag and its name in its own script.
2. Add `lib/l10n/app_<tag>.arb` with `"@@locale": "<tag>"` and translations.
   Keys stay sorted.
3. Add the language to `lib/l10n/glossary.yaml` (a column per term) and write
   `docs/i18n/style-<tag>.md`.
4. When the language ships (step 7), declare it to the OS and the stores:
   `knownRegions` in the iOS and macOS Runner projects,
   `<tag>.lproj/InfoPlist.strings` in both Runner targets, and Android
   `res/xml/locales_config.xml` with `android:localeConfig`. Earlier, the
   stores would list a language the app does not offer.
   `test/l10n/native_locale_declarations_test.dart` fails when these and
   `released` disagree.
5. Check fonts: the language's script needs a system font on every platform.
   A CJK language also gets its own list in `fontFamilyFallbackFor`
   (`lib/src/core/l10n/locale_typography.dart`).
6. Review it on screen with `--dart-define=VIZOR_I18N_PREVIEW=true`.
7. Set `released: true` once every message is translated and a native
   reviewer approved the `[security]` strings. The gate test then requires
   complete coverage.

Right-to-left languages also need a layout audit first: most layouts use
left/right geometry (`EdgeInsets.fromLTRB`, `left:`) instead of directional
variants.
