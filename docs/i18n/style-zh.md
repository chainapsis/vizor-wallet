# Simplified Chinese style guide

The `zh` locale is Simplified Chinese. Traditional-script devices also see it
until a `zh_Hant` translation exists.

## Voice

- Address the user as 你, sparingly. Prefer sentences without a pronoun:
  `请输入助记词`, not `请你输入你的助记词`.
- Keep sentences short and direct.

## Punctuation

- Use full-width punctuation in Chinese text: `，。！？：；（）`.
- Use `“”` for quotes.
- Labels, titles and buttons have no trailing punctuation.

## Spacing

- Put a space between Chinese characters and Latin letters or numbers:
  `发送 0.5 ZEC`, `使用 Ledger 签名`.
- No space between Chinese characters and full-width punctuation.
- A biometric name (`{method}`, `{biometric}`) can be Latin (`Face ID`) or
  Chinese (`指纹`), so no spacing suits both. Quote it: `使用“{method}”解锁`.

## Terms

- Use the glossary term for every wallet and Zcash concept.
- Translate `shielded / transparent` as `隐私 / 公开`: `隐私地址`,
  `公开余额`. For shielding, use `转为隐私余额` for an action and
  `隐私转换` for a transaction title. This moves funds on-chain; keep it
  distinct from hiding the balance on screen and from `隐私查询`.
  Avoid `屏蔽`, which can read as blocked or muted, and the literal `透明`.
- Write `密钥`, never `秘钥`.
- Keep brand and protocol names in Latin script: `Vizor`, `Zcash`, `Ledger`,
  `Keystone`, `Tor`.
