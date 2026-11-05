# Moving strings into ARB files

How to move hard-coded copy from Dart code into `lib/l10n`. The English UI must
not change: every ARB English value equals the literal it replaces, byte for
byte.

## Find what is left

```bash
fvm dart run tool/l10n/strings.dart list lib/src/features/send
```

`slot` findings sit in a widget text slot and are user-facing. `likely`
findings look like copy and include some false positives.

## Add keys

Add each key to `lib/l10n/app_en.arb` with an `@key` description, then the
same key to `lib/l10n/source/app_ko.arb` and `lib/l10n/app_zh.arb`. Keep keys
sorted. Then regenerate:

```bash
fvm dart run tool/l10n/korean_arb.dart   # writes lib/l10n/app_ko.arb
fvm flutter gen-l10n                     # writes lib/l10n/app_localizations*.dart
```

Never edit `lib/l10n/app_ko.arb` or the generated Dart files by hand.

### Key names

lowerCamelCase, starting with the feature: `sendReviewTitle`,
`settingsThemeLabel`. Phrases that several features show with the same
meaning use a shared prefix:

| Prefix | Use |
| --- | --- |
| `common*` | Generic actions and states: Cancel, Close, Continue, Try again, Copied |
| `nav*` | Sidebar and tab bar destinations |
| `password*`, `passcode*` | Wallet password and mobile passcode fields and errors |
| `secretPassphrase*`, `bip39Passphrase*` | Seed phrase and the optional 25th word |
| `endpoint*` | lightwalletd endpoint settings |
| `update*` | App update prompts |
| `sync*`, `pool*` | Sync status, Shielded and Transparent badges |

Reuse an existing key only when the English is byte-identical and the meaning
is the same. Two literals that differ only in case or punctuation get two
keys.

### Descriptions

One sentence naming where the text appears and what it does, written for a
translator who cannot see the screen. Start it with `[security] ` when the
text warns about seed phrases, passphrases, passwords, passcodes, keys or
irreversible deletion.

### Placeholders and plurals

`'Send $amount'` becomes `"Send {amount}"` with a typed placeholder. Pass
formatted numbers and amounts as `String`. Use ICU plurals only where the
English already varies by count, and keep the English identical for every
count the code produces.

## Change the code

- Widgets read `context.l10n.<key>` (`lib/src/core/l10n/l10n.dart`).
- A constructor default such as `this.label = 'Cancel'` becomes a nullable
  parameter resolved in `build`: `label ?? context.l10n.commonCancel`.
- A label getter on an enum becomes a method that takes `AppLocalizations`:
  `step.label(context.l10n)`.
- A function or mapper outside a widget whose output is shown (status
  presenters, row mappers, error mappers) takes `AppLocalizations l10n` as its
  first parameter. Widgets pass `context.l10n`; tests pass `testL10n` from
  `test/support/test_l10n.dart`. Never pass a `BuildContext` into them.
- A provider or notifier that keeps display text in its state stores an enum
  or code instead, and the widget turns it into text (`ActivityEta`,
  `AddressFormatFinding`). Text written to persisted records stays English
  until the record stores a code.
- Never decide behaviour by comparing a label: a localized label differs in
  every language. Give the data a kind (`SwapStatusDetailKind`) and branch on
  that.
- Dates go through `lib/src/core/formatting/date_format.dart` or
  `DateFormat(..., l10n.localeName)` from `intl`, never ARB keys for month or
  weekday names. `DateFormat` throws until the localization delegates have
  loaded intl's date data, even for `'en'`, so format dates only below an app
  root. Tests get the data from `test/flutter_test_config.dart`.

## Leave these as literals

Add a trailing `// l10n-ignore: <reason>` on the line when the scanner lists
it:

- log and debug messages, analytics names, storage keys, route paths, keys;
- strings compared with `==`, `.contains` or `switch`, used as map keys, or
  parsed back;
- Rust and SDK error text passed through;
- lone product or protocol names (`Vizor`, `Zcash`, `ZEC`, `Keystone`,
  `Ledger`) and amount formats such as `'$amount ZEC'`;
- addresses, sample keys, URLs and the Welcome tagline.

A file that holds only data, such as generated account names that are saved
as the account name, starts a line with `// l10n-ignore-file: <reason>`. Never
use it to hide display text that is still English (state messages, persisted
labels): that text has to stay visible to the scanner as remaining work.

## Finish

1. `fvm flutter analyze`
2. `fvm flutter test test/l10n test/tool`
3. The tests of the screens you changed, in both lanes when mobile files
   changed.
4. Add a directory (or file) whose scanner list is now empty to
   `tool/l10n/migrated_dirs.txt`. The gate test then fails when new
   hard-coded copy appears there.
