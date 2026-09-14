# Receive request draft

Read when changing Receive request address snapshots, amount units, or Create/Edit behavior.

- Receive composition: [`zec_request_draft.dart`](../../../../lib/src/features/receive/services/zec_request_draft.dart)
  and [`request_amount_model.dart`](../../../../lib/src/features/receive/widgets/request/request_amount_model.dart).

- Snapshot the selected address when opening the desktop modal or mobile sheet.
  Address renewal or a different Receive tab must not repoint the draft. Both
  [`receive_screen.dart`](../../../../lib/src/features/receive/screens/receive_screen.dart)
  and [`receive_request_sheet.dart`](../../../../lib/src/features/receive/widgets/mobile/receive_request_sheet.dart)
  snapshot the resolved result on Create; later price ticks must not rewrite
  its QR or shared link. Editing returns to a live draft for the next snapshot.
- ZEC input is canonical. User-typed USD converts at the live usable price until
  Create. USD derived by toggling from ZEC is only a rounded display: preserve
  the exact original ZEC until the user edits the USD field.
- Missing/expired price blocks creating from typed USD and entering USD mode,
  but never prevents returning to ZEC using the carried amount. Derived USD
  remains creatable without a price. Keep sub-cent amounts in ZEC when their
  USD field would round to zero.
- Emit a positive amount, at most eight decimals and 21 million ZEC, normalized
  through integer zatoshi. An unfinished amount produces no request; other
  invalid input gets an actionable field error. Only a valid URI enables Create.
- Emit only address, amount, and optional text `memo`; never emit `label` or
  `message` from local account names. Strip unsupported control/bidi characters
  at draft input; transparent requests omit the memo.

## Verification

- [`zec_request_draft_test.dart`](../../../../test/features/receive/zec_request_draft_test.dart):
  amount meaning, price loss, and draft memo rules.
- For view-model, desktop/sheet, QR export, and mobile-screen coverage, use
  [Receive tests](../../guides/receive-tests.md).

## Related changes

- When changing generated URI bytes or fields, read [ZIP-321 codec](../../references/zcash/zip321-codec.md).
