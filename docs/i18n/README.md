# Translating Vizor

Vizor ships English, with Korean and Simplified Chinese in progress. All app
copy lives in `lib/l10n/app_<locale>.arb`; `app_en.arb` is the source.

Korean is the exception: edit `lib/l10n/source/app_ko.arb`, then run
`fvm dart run tool/l10n/korean_arb.dart`. The generated `lib/l10n/app_ko.arb`
joins the characters of each word with invisible U+200D so lines break
between words.

- [Glossary](../../lib/l10n/glossary.yaml): one entry per concept. Use the
  term for your language whenever the English source contains the English
  term.
- Style guides: [Korean](style-ko.md), [Simplified Chinese](style-zh.md).
- [Adding a language](adding-a-language.md).
- [Moving strings into ARB files](extracting-strings.md), for developers.

## How a string gets translated

1. A developer adds a key to `app_en.arb` with an `@key` description that names
   the screen, the element and any length limit. Security copy (secret
   passphrase, signing, amounts, warnings) says `[security]` in its
   description.
2. A translation draft is written from the glossary, the style guide, the
   description and, where available, a screenshot of the screen.
3. A native reviewer for the language approves it. A `[security]` string
   always needs that approval, and only an in-house native reviewer gives
   it: a translator or community contributor may propose `[security]` copy
   but not approve it.
4. The language is checked on screen: truncation, wrapping and fonts.

Unreleased languages stay hidden behind `--dart-define=VIZOR_I18N_PREVIEW=true`
until every message is translated and reviewed.

## Checking a language on screen

Flutter tests cannot read system fonts. Fetch the Korean and Chinese capture
fonts once with `scripts/fetch-capture-fonts.sh`; it stores them in
`~/.cache/vizor/capture-fonts`, outside the repository.

- One screen: `scripts/figma-compare.sh widget --scenario <id> --locale ko`
  (add `--form-factor mobile` for a mobile scenario).
- Every registered screen, in every language:

  ```bash
  fvm flutter test --no-pub --tags figma-capture --run-skipped \
    --dart-define=LOCALE_SCAN_REPORT=/absolute/path/desktop.jsonl \
    test/figma_compare/locale_layout_scan_desktop_test.dart
  fvm flutter test --no-pub --tags figma-capture --run-skipped \
    --dart-define=VIZOR_FORM_FACTOR=mobile \
    --dart-define=LOCALE_SCAN_REPORT=/absolute/path/mobile.jsonl \
    test/figma_compare/locale_layout_scan_mobile_test.dart
  ```

  Each line records one scenario in one language: the first layout exception,
  the texts cut off by `maxLines` or a single line, the Korean words broken
  across lines because their box is too narrow (`wordSplits`), and the Rows
  and Columns whose children do not fit. A translation that adds an exception
  or cut-off text that English does not have breaks that screen, and so does
  any word split. Add
  `--dart-define=LOCALE_SCAN_SCENARIOS=<id prefixes>` to rerun a few, and
  `--update-goldens --dart-define=LOCALE_SCAN_OUTPUT=<directory>` for PNGs.

Fix a break by shortening the translation or by letting the layout grow (a
minimum height instead of a fixed one); English must render exactly as before.
Lines that mix Latin and CJK in the serif display fonts run about 1px taller
per line, so fixed-height boxes with no slack overflow by a few pixels.

## What the tests enforce

`test/l10n/l10n_gates_test.dart` runs with `fvm flutter test` and fails when a
translation:

- drops or renames a placeholder such as `{language}`;
- adds a URL, or a number the English source does not contain;
- translates a never-translate term (`ZEC`, `Vizor`, `Ledger`, ...) or uses a
  forbidden variant from the glossary;
- misses a `confirmed` glossary term;
- copies a description tag such as `[security]` into the message.

The same test fails when app code gains a hard-coded English string or
compares text with English copy (`label == 'Selected'`), which breaks as soon
as the label is translated.

Translations are a security surface in a wallet: the URL and number checks
exist so that no translation can point users somewhere else or change an
amount.

## Rules for every language

- Keep placeholders (`{count}`) and ICU syntax exactly; reorder them freely.
- Never translate brand names, token symbols or protocol names.
- Keep warnings as strong as the source.
- Translate meaning, not words. Ask in the pull request when the English is
  unclear instead of guessing.
- Do not translate `Shielded by default`, the Welcome tagline. It is part of
  the brand.
