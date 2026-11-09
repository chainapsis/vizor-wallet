# Localization for developers

How localized text works in Vizor, and what to do when you add or change it.
Read this before you touch user-facing text, ARB files, language selection, or
copy that native code draws. Translators start from [README.md](README.md).

## How it fits together

UI strings come from Flutter `gen-l10n`. `l10n.yaml` reads the ARB files, with
`app_en.arb` as the template, and `generate: true` in `pubspec.yaml` makes
`flutter pub get` regenerate the committed Dart files.

```text
lib/l10n/app_en.arb ────────────────────────────┐
lib/l10n/source/app_ko.arb ─ korean_arb ─ lib/l10n/app_ko.arb ─┼─ gen-l10n ─ lib/l10n/app_localizations*.dart ─ context.l10n
lib/l10n/app_zh.arb ────────────────────────────┘

native* keys in the same ARB files ─ native_strings ─ NativeStrings.swift, NativeStrings.kt
```

### Where things live

| Path | What it holds |
| --- | --- |
| `lib/l10n/app_en.arb` | English source text and every key's `@key` description |
| `lib/l10n/source/app_ko.arb` | Korean, edited by hand |
| `lib/l10n/app_ko.arb` | Generated Korean; never edit |
| `lib/l10n/app_zh.arb` | Simplified Chinese, edited by hand |
| `lib/l10n/app_localizations*.dart` | Generated Dart; never edit |
| `lib/l10n/glossary.yaml` | One entry per term; the gate test reads it |
| `lib/src/core/l10n/app_language.dart` | `AppLanguage`, the only list of languages |
| `lib/src/core/l10n/l10n.dart` | `context.l10n` |
| `lib/src/core/l10n/inline_spans.dart` | Icons, links and emphasis inside a message |
| `lib/src/core/l10n/locale_typography.dart` | CJK font fallback |
| `lib/src/core/l10n/native_language.dart` | Tells native code the shown language |
| `lib/src/core/l10n/untranslated_text_log.dart` | Logs Rust or SDK text that a screen replaced |
| `lib/src/core/widgets/untranslated_details.dart` | The "Show details" button for that text |
| `lib/src/providers/app_language_provider.dart` | The saved language and the languages on offer |
| `tool/l10n/` | `strings.dart`, `korean_arb.dart`, `native_strings.dart`, `migrated_dirs.txt` |
| `test/l10n/`, `test/tool/` | Gate tests and generator tests |
| `test/support/test_l10n.dart`, `localized_test_scope.dart` | Test helpers |

## Languages and the preview flag

`AppLanguage` is the only list of languages. A new language is one enum entry
plus one ARB file; [adding-a-language.md](adding-a-language.md) has every step.
English stays first because locale resolution falls back to the first entry.

Each entry has a `released` flag, and `VIZOR_I18N_PREVIEW` decides whether a
build also offers the unreleased ones:

| Build | Languages offered | A Korean or Chinese device shows |
| --- | --- | --- |
| Default, including every release | Released: English, Korean, Simplified Chinese | English until the user picks a language |
| `--dart-define=VIZOR_I18N_PREVIEW=true` | Every entry, including any unreleased one | English until the user picks a language |
| Widgetbook, figma-compare | Every entry | Whatever the tool selects |

A copy change in a released language reaches users in the next release. All
three are released today, so none of them needs the flag.

### The saved preference

`zcash_app_language` holds a language tag. It is plain storage, read during
bootstrap like the theme mode, and `appLanguageProvider` exposes it.

- Nothing stored, or a value this build does not know, is English. Existing
  installs keep the English UI until the user picks a language.
- A saved language this build does not offer also shows English
  (`appLocaleFor`).
- There is no "follow the device" option. On a device in a language Vizor lacks,
  it would look like that language.

## App roots

Every `MaterialApp` root passes `appSupportedLocales()` and
`appLocalizationsDelegates`, and applies `LocaleTypography` in its `builder`. A
new root must do the same. `lib/app.dart` is the main root;
`linux_keyring_gate.dart`, `figma_compare_app.dart` and the Widgetbook and preview
apps are the others.

## Reading strings

- **In a widget**: `context.l10n.<key>`. There is no English fallback. When a
  tree has no localizations it throws an error that names the fix.
- **Outside a widget**: a function whose output is shown takes
  `AppLocalizations l10n` as its first parameter. Widgets pass `context.l10n`;
  tests pass `testL10n`. Never pass a `BuildContext` into it.
- **In provider state**: store an enum or a code, and let the widget turn it
  into text.
- **An icon, link or emphasis inside a sentence**: pass the slot text as a
  placeholder and use `inlineSlotSpans` or `emphasisSpans`. A translator can
  then place it wherever the grammar needs it. Do not stitch fragments around
  the widget.
- **Dates**: `lib/src/core/formatting/date_format.dart` or
  `DateFormat(..., l10n.localeName)`, never ARB keys for month or weekday names.

Code never branches on a translated label (`status == 'Completed'`). Give the
data a kind and branch on that. The gate test rejects such comparisons in
`lib/src`.

[extracting-strings.md](extracting-strings.md) has the constructor-default,
enum-label and mapper patterns, and what stays a literal
(`// l10n-ignore: <reason>`).

## Adding or changing a string

1. **English.** Add the key to `lib/l10n/app_en.arb` with an `@key` description
   (`required-resource-attributes`). The description names the screen, the
   element and any length limit, for a translator who cannot see the screen.
   Start it with `[security] ` for security copy. Keep keys sorted, and check
   `glossary.yaml` for shared terms. Naming rules are in
   [extracting-strings.md](extracting-strings.md#key-names).
2. **Korean and Chinese.** Add the same key to `lib/l10n/source/app_ko.arb` and
   `lib/l10n/app_zh.arb`, following the [Korean](style-ko.md) and
   [Chinese](style-zh.md) style guides. When you change the meaning of an English
   message, update both. No test notices a translation that still says the old
   thing.
3. **Regenerate.**

   ```bash
   fvm dart run tool/l10n/korean_arb.dart   # writes lib/l10n/app_ko.arb
   fvm flutter gen-l10n                     # writes lib/l10n/app_localizations*.dart
   fvm dart run tool/l10n/native_strings.dart   # only when native* keys changed
   ```

4. **Update literals.** Widgetbook fixtures (`lib/widgetbook/`) and tests that
   assert the literal string break when copy changes.
5. **Check.** See [Before you open a pull request](#before-you-open-a-pull-request).

Commit the generated files with the change.

While a language is unreleased, a missing key shows the English message and
`gen-l10n` lists it in `build/l10n_untranslated.json`. A released language must
translate every key. To remove a key, remove it from all three source files: a
translation cannot keep a key that English does not have.

### Korean line breaks

Korean is edited in `lib/l10n/source/app_ko.arb`. `tool/l10n/korean_arb.dart`
generates `lib/l10n/app_ko.arb`, joining the characters of each word with
invisible U+200D so Flutter breaks Korean lines between words, not inside them.

A test that compares shipped Korean removes that tool's `wordJoiner` first:

```dart
import '../../../tool/l10n/korean_arb.dart' show wordJoiner;

String plain(String text) => text.replaceAll(wordJoiner, '');
```

## Text that is not translated

Never translate Rust error strings, or strings that code matches with
`.contains` or uses as keys.

- **Rust and SDK text**: branch on a code, not on the message. A screen shows
  its own copy, puts the original behind `untranslatedDetailsButton`, and logs it
  with `logUntranslatedText` under `vizor.untranslated`.
  [rust-messages.md](rust-messages.md) lists every site.
- **Broadcast results** carry `notices`, Rust's English `message` as sentences.
  Show them with `broadcastResultText`. A reworded sentence changes Rust, its
  `broadcastNotice*` key and `test/fixtures/broadcast_notices_en.json` together.
- **Persisted records** store a code, not display text. Records from earlier
  builds keep their stored English, so reading them has to keep working.

## Native copy

Copy that Swift or Kotlin draws (notifications, background-task captions, system
prompts, native error messages Dart shows) uses `native*` ARB keys.

- `fvm dart run tool/l10n/native_strings.dart` regenerates
  `ios/Runner/NativeStrings.swift`, which the macOS target also compiles, and
  `android/app/src/main/kotlin/com/keplr/vizor/NativeStrings.kt`. Never edit them
  by hand.
- Native strings take plain `{name}` placeholders only, no ICU plurals or
  selects.
- `NativeLanguageSync` in the app root sends the shown language over
  `com.zcash.wallet/native_strings`, and native code stores it for background
  work. Native code uses English until it arrives.
- Do not add `.lproj`, `values-<lang>` or `localeConfig` before a language ships.
  They would show translated permission prompts and store listings in an
  English-only build. The release steps are in
  [adding-a-language.md](adding-a-language.md#native-resources-at-release).

## Fonts and layout

- `LocaleTypography` gives Korean and Chinese UI their own CJK font fallback.
  Without it the engine picks Han glyphs by the OS language, so Chinese on a
  Korean Mac draws Korean-style glyphs.
- A `TextPainter` built from a token style misses that fallback. Measure with
  `withLocaleFontFallback(context, style)`.
- Fixed-height boxes that fit English exactly overflow in CJK, so prefer minimum
  heights. Lines that mix Latin and CJK in the serif display fonts run about 1px
  taller.
- Fix a break by shortening the translation or by letting the layout grow.
  English must render as before.

## Writing tests

- Every test `MaterialApp` passes
  `localizationsDelegates: appLocalizationsDelegates`.
- A test without a `MaterialApp` wraps its tree in `LocalizedTestScope`.
- A test that calls an l10n-taking function directly passes `testL10n`.

## Checks

### What the gate tests fail on

`test/l10n/l10n_gates_test.dart` runs with `fvm flutter test`:

| Test | Fails when |
| --- | --- |
| `app_ko.arb is generated from its source` | `korean_arb.dart` was not run |
| `native string tables are generated from the ARB files` | `native_strings.dart` was not run |
| `Korean never hedges a particle after a placeholder` | A message has `{x}(으)로` or `{x}을(를)` |
| `Chinese quotes biometric names, which may be Latin or Chinese` | `{method}` is not in quotes |
| `message keys are sorted so parallel changes rarely conflict` | Keys are out of order |
| `has no keys missing from the English template` | A translation has a key English does not have |
| `a released language translates every message` | A released language misses a key |
| `copies no description tag into a message` | `[security]` or similar reached the text |
| `keeps placeholders, URLs and numbers of the source` | A placeholder changed, or a URL or number was added |
| `follows the glossary` | A never-translate or `confirmed` term is missing, or a `forbidden` variant is used |
| `code does not compare text with English copy` | Code compares a label with English text |
| `migrated directories have no hardcoded user-facing strings` | A path in `tool/l10n/migrated_dirs.txt`, which covers all of `lib/src`, gains a literal |

Other tests: `test/l10n/native_locale_declarations_test.dart` compares native
language declarations with `released`, and `test/l10n/broadcast_notice_text_test.dart`
pins the English that Rust and Dart share.

**No GitHub workflow in this repository runs these tests.** They only protect
the code when someone runs them, so run them before you open a pull request.

### Before you open a pull request

```bash
fvm flutter analyze
fvm flutter test test/l10n test/tool
fvm flutter test
fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile
```

When a message gets longer, also run the layout scan over every scenario
([README.md](README.md#checking-a-language-on-screen)). It is skipped by default
and is the only check that finds text cut off in Korean or Chinese. Fetch its
fonts once with `scripts/fetch-capture-fonts.sh`. To look at one screen:

```bash
scripts/figma-compare.sh widget --scenario <id> --locale ko
```

`fvm dart run tool/l10n/strings.dart list <dir>` lists the literals the gate
would reject.

### Common failures

| Symptom | Cause and fix |
| --- | --- |
| `No AppLocalizations found above this widget.` | The tree has no delegates. Pass `appLocalizationsDelegates` to the `MaterialApp`, or wrap a test in `LocalizedTestScope`. |
| `gen-l10n` cannot write `build/l10n_untranslated.json` | A fresh checkout has no `build/` directory. Run `mkdir build`. |
| A Korean string looks equal in a failing test | Invisible U+200D. Remove `wordJoiner` before comparing. |
| The gate test reports a literal that is not copy | Add `// l10n-ignore: <reason>` on that line, if it fits the list in [extracting-strings.md](extracting-strings.md#leave-these-as-literals). |
| Overflow only in Korean or Chinese | A fixed-height box. Use a minimum height, or shorten the translation. |
| `DateFormat` throws | Date data loads with the localization delegates, so format dates only below an app root. |
