# Mobile gift onboarding flow connection

Branch: `rowan/mobile-gift-onboarding-connection`, based on umbrella
#793 at `4be899f75`, after #819 and #820 were squash-merged.
Claim execution/resumption and unbacked account removal are already in the base.

## Flow

1. Initial mobile Welcome activates the Gift button. Add-account Welcome omits it.
2. A fresh-wallet HTTPS Gift link opens the same `/gift` surface. Existing wallets
   retain their unlock and Payment Links path. Other arriving Cards stay queued.
3. Explicit paste or scan starts account-free inspection. Checking uses the shared
   skeleton, hides amount/artwork, and disables dismissal. Failures expose existing
   close/retry controls. Old birthdays retain the existing long-scan warning sheet.
4. A checked or confirmation-waiting Card can enter Gift wallet creation. The
   shared passcode screen confirms six digits in route memory only. Shared account
   customisation retains persona randomisation and omits back/skip controls.
5. Customise Continue runs the existing setup boundary: credential preparation,
   account creation, durable Card and receiving UUID, credential commit, journal
   cleanup. Pre-account failures stay inline. A known created account continues
   without recreation; its saved journal owns incomplete-storage recovery. An
   uncertain DB result uses the existing reopen message and disables recreation.
6. The existing inspection goes to `claimSetupCard`, independently of navigation.
   Face ID opt-in then Home proceed without waiting for broadcast or confirmations.
   Saved Card recovery owns binding/network errors; no account creation retry.
7. Choosing an existing wallet reuses normal import. Its active newly imported
   account is pinned in the received store before the same automatic handoff.
   Ambiguous imports retain the existing manual claim surface.
8. Home uses the committed backup/Zcash manual carousel and real Gift Activity
   indexing. No Gift banner, new return page, or setup-failure screen.

## Review and preview

Widgetbook: Screens > Gift Cards > Mobile > Onboarding - Full walkthrough
(and focused entry/checking/passcode/customise/Face ID/warning/error cases).
The fixture shares in-memory account, credential, received-store, sync and
Activity state through Home, backup and Zcash education. Preview broadcast and
confirmation adapters are simulated; production uses the real coordinator.

Deterministic captures: `mobile-gift-onboarding-entry`,
`mobile-gift-onboarding-checking`, `mobile-gift-onboarding-inspected`,
`mobile-gift-onboarding-customise`.

## Separate completed work

- #819 owns claim execution, saved-account binding, and restart/unlock resumption.
- #820 owns unbacked account removal/reset warnings, scrolling, and previews.

## Verification boundary

Run the flow, routing, existing onboarding, and Widgetbook checks on this base.
Deterministic previews simulate broadcast and confirmation; they do not prove
live-chain submission or native process-termination recovery. Desktop onboarding
and a cross-store transaction redesign remain outside this slice.

## Current validation

- Default tests: 153 passed, covering flow ownership/cleanup, intake, claim
  resumption, receiving records, first-wallet setup/restart, and existing
  desktop link navigation.
- Mobile tests: 79 flow/Welcome/Face ID/progress/Widgetbook checks and 134
  adjacent route/passcode/customisation/import/account checks passed.
- Scoped analysis of the 28 changed Dart files: no issues.
- Reviewed entry, checking, and inspected light captures and customisation
  dark capture. The entry explanation reflects account creation before claim.
- Widgetbook exercises the production Home Activity index, manual carousel,
  backup with birthday information, reminder deferral, and Zcash education.
- Live-chain claim, native biometrics, process interruption, and the full
  repository suite have not been run for this screen-connection slice.
