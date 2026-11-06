# Korean style guide

## Voice

- Use 해요체: `복구 문구를 입력해 주세요.`, `거래를 보냈어요.` Do not use
  합니다체 or 하십시오체.
- Avoid pronouns. Write `지갑을 가져오세요`, not `당신의 지갑을 가져오세요`.
- Keep sentences short. A Korean message may be shorter than the English one.

## Buttons and labels

- Buttons end in a noun form: `지갑 만들기`, `가져오기`, `다시 시도`, `복사`.
- Labels and titles have no trailing period.
- English sentence case does not apply; Korean has no letter case.

## Sentences

- End full sentences with a period. Questions end with `?`.
- Error messages say what happened and what to do next:
  `연결하지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.`

## Numbers, units and names

- Put a space between a number and a unit or symbol: `0.5 ZEC`, `3 블록`.
- Keep brand and protocol names in Latin script: `Vizor`, `Zcash`, `Ledger`,
  `Keystone`, `Tor`.
- Use the glossary term for every wallet and Zcash concept.

## Line breaks

Flutter can break Korean lines inside a word. `tool/l10n/korean_arb.dart`
inserts invisible word joiners into the shipped translations, so write normal
text with ordinary spaces in `lib/l10n/source/app_ko.arb` and never insert
joiners or manual line breaks yourself.
