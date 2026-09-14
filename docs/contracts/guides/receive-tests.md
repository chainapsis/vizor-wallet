# Receive tests

Read when validating Receive amounts, draft state, request presentation, or QR
export. Use [Test execution](testing.md) for setup, focused reruns, and lane flags.

| Changed behavior | Start with |
| --- | --- |
| ZIP-321 encoding, amount/memo limits, parser round-trip | [URI builder](../../../test/core/zcash/zip321_payment_request_builder_test.dart) |
| ZEC/USD meaning, price loss, unit toggles, draft memo rules | [Draft](../../../test/features/receive/zec_request_draft_test.dart) |
| Request validity, QR payload, summary amount | [View model](../../../test/features/receive/request_amount_model_test.dart) |
| Desktop compose/result controls | [Desktop widgets](../../../test/features/receive/request_amount_widgets_test.dart) |
| Sheet compose/result controls at a mobile-sized viewport | [Request sheet](../../../test/features/receive/request_amount_sheet_test.dart) |
| PNG encoding and export-button callbacks/busy state | [QR export](../../../test/features/receive/request_qr_export_test.dart) |
| Mobile screen integration and navigation | [Mobile screen](../../../test/features/receive/mobile_receive_screen_test.dart) (`mobile` tag) |

The first six files are untagged and can run explicitly with either form factor.
The sheet file's viewport does not make it part of `--tags mobile`.

For a draft regression, select its exact case before repeating the broader set:

```sh
fvm flutter test --no-pub test/features/receive/zec_request_draft_test.dart \
  --plain-name 'ZecRequestDraft switching an unfinished ZEC field to USD derives nothing'
```

For a change spanning draft validity and request presentation, finish with the
builder, draft, view-model, desktop, and sheet files from the table. Include QR
export when payload/rendering or sharing changes. Check the affected untagged UI
files with both token definitions; add the mobile-tagged screen test when its
integration or navigation changes. These are selected task checks, not a
replacement for [required PR checks](../../../CONTRIBUTING.md#testing).
