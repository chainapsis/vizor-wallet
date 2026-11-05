# Adding a language

1. Add an entry to `AppLanguage` in `lib/src/core/l10n/app_language.dart`
   with `released: false`, its tag and its name in its own script.
2. Add `lib/l10n/app_<tag>.arb` with `"@@locale": "<tag>"` and translations.
   Keys stay sorted.
3. Add the language to `lib/l10n/glossary.yaml` (a column per term) and write
   `docs/i18n/style-<tag>.md`.
4. Add native resources: iOS `<tag>.lproj` (`InfoPlist.strings` and the string
   catalog used by background notifications) and Android
   `values-<qualifier>` plus its `localeConfig` entry.
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
