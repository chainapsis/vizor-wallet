# Mobile Ledger modal result — 2026-09-17

Mobile Ledger operations now retain the originating screen behind a floating
modal. Desktop UI and USB/Bluetooth behavior remain unchanged.

## Implementation

- Mobile content lives in `lib/src/features/ledger/widgets/mobile/`. It uses
  `MobileModalScaffold` and the existing `MobileModalCard` geometry; it does not
  wrap the desktop card. Discovery, device selection, verification, Bluetooth
  recovery and signing status have dedicated mobile layouts.
- `LedgerPairingSession` and `LedgerBluetoothSession` own shared, headless
  lifecycle/state logic. Desktop renders its existing presentation from the
  same sessions. Connection services and native transports were not changed.
- Send, swap/pay and shielding retain operation owners on non-opaque routes.
  Gift Card retains its review behind its inner Ledger route. Migration and
  voting retain their background views beneath the modal. No additional modal
  route is pushed when discovery changes to verification or signing.
- Mobile onboarding uses the same mobile Bluetooth recovery content. Lists and
  long help text scroll within a bounded modal, with the close header remaining
  visible. Active work has an animated status indicator; device approval is
  explicitly labeled as waiting for the user.
- Saved-device verification bypass, replacement-device account verification,
  metadata writes, per-operation selection and multi-round signing are retained.

## Review and visual iterations

1. Initial implementation and captures: verified bottom placement, background
   retention, names, loading feedback and light/dark appearance.
2. Refined approval copy and removed its redundant Ledger icon. Found and fixed
   the migration background's competing system-back callback, and the remaining
   desktop Bluetooth recovery layout in mobile onboarding.
3. Found that the mobile picker close callback did not itself settle selection
   before notifying its owner. Added a regression that fails before the fix,
   then restored immediate cancellation before the callback. This prevents a
   delayed host removal from leaving the picker request live.
4. Final complete review and commit-tree verification: no open/deferred findings.

## Validation

- `fvm flutter analyze --no-pub`: no issues.
- Desktop focused regression run: 391 passed, 7 skipped (mobile-tagged cases).
  Includes Ledger services/widgets, voting, Gift Card, onboarding and Widgetbook.
- Mobile focused regression run with `VIZOR_FORM_FACTOR=mobile`: 79 passed.
  Includes send/TEX, swap, selection lifetime, cancellation guards, small-screen
  scrolling, metadata route refresh, onboarding, Gift Card, and voting screens.
- Actual Flutter widget captures: 56 mobile states/configurations passed;
  46 desktop captures passed and are byte-identical to the previous approved
  desktop captures. Both themes were checked. Stress captures use a 320×568
  viewport with 1.8× text in the Ledger modal, and iOS/Android safe-area behavior.
- Screenshots use deterministic fixtures, not production wallet data. Real
  hardware Bluetooth/pairing and native operating-system prompts were not run.

Capture directory:
`/Users/yjh/.codex/visualizations/2026/09/17/01a0ae34-f63b-7be1-9d5f-3ad7e6563299/ledger-mobile-modal-final`

## Git

Source: `codex/ledger-mobile-bluetooth-ux` at
`fd5ec01a78096906b44bfd0d4b4d9ba42b077c45`.
Temporary review branch: `codex/review-fix-ledger-mobile-modal`.
Only commits from this workflow are consolidated before the user-authorized
fast-forward. No remote push is part of this task.
