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
   shared passcode screen confirms six digits in live flow memory only. Shared
   account customisation retains persona randomisation and omits back/skip controls.
5. Customise Continue runs the existing setup boundary: credential preparation,
   account creation, durable Card and receiving UUID, credential commit, journal
   cleanup. Pre-account failures stay inline. If the account exists but storage
   fails, recover its pending mnemonic/account metadata and verify the durable
   Card's receiving UUID and payload before continuing. Repeated recovery errors
   stay on Customise with the existing inline error and **Try again** action;
   persona controls are locked and retries never recreate the account or prepare
   its credential again. The live flow retains the checked inspection and passcode
   through route refresh, then clears them on completion or leaving the screen.
   They are not serialized into route restoration or browser history. Locking
   still routes to unlock and leaves the durable journal for existing recovery.
   An uncertain DB result uses the existing reopen message and disables recreation.
6. The existing inspection goes to `claimSetupCard`, independently of navigation.
   Face ID opt-in then Home proceed without waiting for broadcast or confirmations.
   Saved Card recovery owns binding/network errors; no account creation retry.
7. Choosing an existing wallet saves the resolved Card and pre-import account
   UUIDs in OS secure storage before leaving the Card screen. Normal import
   commits the credential and retains all three import methods: secret
   passphrase, Link Vizor Desktop, and hardware wallet (Keystone/Ledger under
   their existing capability gates). A sole imported account receives the gift
   automatically. Multiple imported accounts reuse the existing **Choose
   receiving account** sheet, including additional ZIP32 passphrase accounts.
   Confirmation switches Home to the selected account, pins that recipient in
   the encrypted Received store, registers the existing inspection with the
   claim runner, and then clears the import journal before Face ID. Broadcast
   and confirmations remain independent of navigation; no extra handoff scan.
   Closing the sheet continues to Face ID/Home with an unbound, unclaimed Card
   in Received. Restart before selection also retains it for manual claim;
   recovery never guesses from the active account. A recipient saved before
   interruption is preserved even if import-journal cleanup was incomplete.
8. Home uses the committed backup/Zcash manual carousel and real Gift Activity
   indexing. Definitive setup-claim failure shows one neutral, dismissible toast
   once the recipient's Home is visible: "Couldn’t redeem your gift card." and
   "View card" opens its existing Received detail. Face ID defers the toast;
   leaving Home, locking, or switching accounts closes it. An unknown broadcast
   stays in recovery. An attempt without a txid does not create Activity.
   No Gift banner, new return page, or setup-failure screen.

## Review and preview

Widgetbook: Screens > Gift Cards > Mobile > Onboarding - Full walkthrough
(and focused entry/checking/passcode/customise/Face ID/warning/error cases,
including **Onboarding - Storage recovery**, **Onboarding - Claim failure toast**
and **Onboarding - Imported receiving account**). The storage case simulates a
post-creation storage error, fails its first immediate recovery, then succeeds
on Try again using the same account. The receiving case starts at passcode
confirmation and exercises the production Wallet Link import and receiving sheet
with two preview accounts.
The interactive walkthrough enables the existing Welcome animation; deterministic
Welcome captures continue to use their separate poster scenario.
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

Immediate storage recovery follow-up:

- Focused default regressions: **67 passed**, including the actual account
  recovery after mnemonic, account JSON, active-account and Received-store writes fail.
- Focused mobile regressions: **90 passed**, covering immediate recovery,
  repeated recovery failures, incomplete Card persistence, retry-only setup,
  locking, normal onboarding, routing and the interactive Widgetbook flows.
- Scoped analysis of all 13 changed Dart files: **no issues**.
- Light/dark storage-recovery capture tests: **2 passed**, visually inspected.
  Existing entry/recipient-sheet/toast captures remain applicable to their
  unchanged states; recovery screenshots show the new locked persona and retry action.
- An explicit journal-clear/handoff race test verifies that recovery cannot
  launch an extra scan before the existing inspection is registered. A stalled
  broadcast still permits Face ID and Home.

Previous recipient selection and toast alignment follow-up:

- Focused default regressions: **79 passed**.
- Focused mobile regressions: **131 passed**.
- Scoped analysis of all 13 changed Dart files: **no issues**.
- Light/dark receiving-sheet captures: **2 passed**, visually inspected.
  Light/dark aligned Home toast and component captures were also inspected.

- Mobile regression tests cover Wallet Link/passphrase multi-account choice,
  dismissal, single-account automatic claim, an ordinary import without Gift
  intent, lock during selection, and restart before/after a durable receiving choice.
- Widgetbook exercises confirmation/dismissal of the same production sheet.
- Tests assert that the live import handoff does not perform an additional scan.
- The deferred Home failure notice is still in memory; restart before Home can
  lose that notice while the failed Card itself remains in Received. This is a
  separate outstanding review item.

Previous review fixes and initial toast polish (`b81638150`):

- Focused default regressions: 64 tests passed.
- Focused mobile regressions: 118 tests passed, including pre-Face-ID submission,
  import-journal restart recovery/cancellation, incoming links on mounted entry,
  failure before/after Home, and Received detail navigation.
- Scoped analysis of the 19 changed Dart files: no issues.
- Both light and dark failure-toast capture tests passed and were inspected.
- Toast interaction tests cover persistent dismissal/action, a 320 px viewport
  at 200% text size, live-region semantics, and scoped dismissal after replacement.
- Native screen-reader announcements and device focus behavior remain unverified.

Initial PR baseline:

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

## Toast polish review

### Clear hierarchy and copy

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `lib/src/core/widgets/app_toast.dart:145`; `lib/src/features/payment_links/widgets/gift_claim_failure_toast_listener.dart:74` | Message and action had the same weight in one row. | Regular message with an underlined "View card" action. | The failure is readable and the recovery destination is clearly interactive. |

### Shared axes and edges

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `lib/src/core/widgets/app_toast.dart:191` | Arbitrary top offsets and a circled dismiss glyph made the message and controls appear misaligned. | Status, message, action and a simple X share one vertical center; visible leading/trailing glyph insets match. Large text places the action below the message on its logical leading edge. | Makes the recovery action easy to scan and preserves alignment in RTL and at 200% text size. |

### Accessible reading and controls

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `lib/src/features/payment_links/widgets/gift_claim_failure_toast_listener.dart:77` | The notice disappeared after five seconds. | It stays until dismissal/action; leaving Home, locking, or switching accounts also closes it. | Gives users time to read and reach the recovery action. |
| MEDIUM | `lib/src/core/widgets/app_toast.dart:64`; `lib/src/core/widgets/app_toast.dart:172` | Small action target and truncated copy. | Native buttons, at least 44 px targets, wrapping copy and a live-region announcement. | Supports large text and clear, labeled controls. |

Verification: light/dark static captures, default/mobile interaction tests,
LTR/RTL shared-axis checks, 320 px at 200% text, navigation and replacement
lifecycle. Earlier two-row toast captures are stale after this alignment change.
Not verified: native VoiceOver/TalkBack, device keyboard focus, and hover/pressed rendering on device.
No custom toast motion was added. **Approve** for the inspected widget surface.
