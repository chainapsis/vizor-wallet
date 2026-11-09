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

## Particles after placeholders

- A particle after a placeholder depends on how the inserted value ends, which
  the message cannot know. Do not hedge it as `{method}(으)로` or
  `{label}을(를)`. Put a fixed noun between them (`{method} 잠금 해제를`,
  `{label} 연락처를`, `{signer} 기기에서`), use a particle that does not change
  (`{amount}만큼`), or attach the particle to a word in parentheses
  (`금액({amount})과`).
- When every value of a placeholder ends the same way, a fixed particle is
  fine: `{feature}` always ends in `잠금 해제`, so `{feature}를` is correct.
- The l10n gate test rejects a hedged particle after a placeholder.

## Numbers, units and names

- Put a space between a number and a unit or symbol: `0.5 ZEC`, `3 블록`.
- Keep brand and protocol names in Latin script: `Vizor`, `Zcash`, `Ledger`,
  `Keystone`, `Tor`.
- Use the glossary term for every wallet and Zcash concept.
- Translate `shielded / transparent` as `비공개 / 공개`: `비공개 주소`,
  `공개 잔액`. For shielding, use `비공개로 전환` for an action and
  `비공개 전환` for a transaction title. This moves funds on-chain; keep it
  distinct from hiding the balance on screen and from `비공개 조회`.
  Avoid the literal `차폐`.

## Line breaks

Flutter can break Korean lines inside a word. `tool/l10n/korean_arb.dart`
inserts invisible joiners (U+200D) into the shipped translations, so write normal
text with ordinary spaces in `lib/l10n/source/app_ko.arb` and never insert
joiners or manual line breaks yourself.
