# Translating Vizor

Vizor ships English, with Korean and Simplified Chinese in progress. All app
copy lives in `lib/l10n/app_<locale>.arb`; `app_en.arb` is the source.

Korean is the exception: edit `lib/l10n/source/app_ko.arb`, then run
`fvm dart run tool/l10n/korean_arb.dart`. The generated `lib/l10n/app_ko.arb`
adds invisible word joiners so lines break between words.

- [Glossary](../../lib/l10n/glossary.yaml): one entry per concept. Use the
  term for your language whenever the English source contains the English
  term.
- Style guides: [Korean](style-ko.md), [Simplified Chinese](style-zh.md).
- [Adding a language](adding-a-language.md).

## How a string gets translated

1. A developer adds a key to `app_en.arb` with an `@key` description that names
   the screen, the element and any length limit. Security copy (secret
   passphrase, signing, amounts, warnings) says `[security]` in its
   description.
2. A translation draft is written from the glossary, the style guide, the
   description and, where available, a screenshot of the screen.
3. A native reviewer for the language approves it. A `[security]` string
   always needs that approval.
4. The language is checked on screen: truncation, wrapping and fonts.

Unreleased languages stay hidden behind `--dart-define=VIZOR_I18N_PREVIEW=true`
until every message is translated and reviewed.

## What the tests enforce

`test/l10n/l10n_gates_test.dart` runs with `fvm flutter test` and fails when a
translation:

- drops or renames a placeholder such as `{language}`;
- adds a URL, or a number the English source does not contain;
- translates a never-translate term (`ZEC`, `Vizor`, `Ledger`, ...) or uses a
  forbidden variant from the glossary;
- misses a `confirmed` glossary term.

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
