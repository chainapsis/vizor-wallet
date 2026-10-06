# Onboarding

This document describes the mobile onboarding behavior integrated in PR #793
and the planned desktop integration. Desktop entry paths retain their existing
behavior until the relevant slices below are merged. Shared account persistence,
credentials, bootstrap, and recovery changes also apply to desktop and are
validated in the desktop test lane. Mobile builds, tests, and captures use
`--dart-define=VIZOR_FORM_FACTOR=mobile`.

## Entry and account setup

| Entry | Account preparation | Completion |
| --- | --- | --- |
| Create a wallet | Introduction, address types, things to know, secret passphrase, passcode, account customisation | Optional Face ID, then Home |
| Import a secret passphrase | Phrase entry and review, wallet birthday, passcode when needed, account customisation | Optional Face ID for initial setup, then Home |
| Import a hardware wallet | Existing Keystone or Ledger connection, account/birthday steps, passcode when needed, account customisation | Existing capability and device gates apply |
| Link Vizor Desktop | Introduction, scan, account selection, contacts, passcode when needed | Optional Face ID for initial setup, then Home |
| Redeem a gift card into a new wallet | Card inspection, passcode, account customisation | Claim handoff, optional Face ID, then Home |
| Redeem a gift card into an imported wallet | Card inspection, existing import flow, receiving-account selection when needed | Claim handoff, optional Face ID, then Home |

- Both Welcome and Add account offer the gift card entry, with new-account
  creation and wallet-import choices after inspection. Add account reuses the
  configured passcode, preserves existing accounts, and returns to Home without
  repeating biometric setup. It creates the recipient via the normal additional
  software-account path, never by replacing the wallet DB.
- A gift link opened without a wallet uses the same card entry screen. Existing
  wallets retain their unlock and gift card routes; other arriving cards remain
  queued while setup is in progress.
- Welcome uses the native video player with a static WebP poster underneath.
  The poster is also used for deterministic previews, reduced motion, or decoder
  failure. The mobile video includes a brief loop crossfade. Playback follows
  both route visibility and app lifecycle.
- Account customisation reuses the shared name/profile controls and random
  suggestions. Gift creation requires this step and has no Back or Skip action.
- The passcode is six digits, using the existing wallet credential model. The
  keypad's reset/help action appears only on the app-start unlock screen.
- Placeholder Terms/Privacy links are excluded until their documents exist.

## Progress bar

Progress describes the current position in **account preparation**. It does not
measure elapsed time, QR decoding, wallet sync, or gift claim completion.

`OnboardingProgressPlan` derives positions from semantic steps and an immutable
entry snapshot of whether a passcode must be created. The snapshot affects UI
only; authentication and account mutations still use the current security state.

Let `A = 60 / 196` (about 30.6%), `N` be the number of preparation steps, and `i`
be the step's position starting at 1:

```text
Entry position: A
Preparation step: A + (1 - A) × i / (N + 1)
Account ready: 1
```

| Flow | Preparation steps after the entry position |
| --- | --- |
| Create | Address types → Things to know → Secret passphrase → Passcode → Customise account |
| Passphrase import | Phrase entry → Phrase review → Birthday → Passcode → Customise account |
| Keystone | Device intro → Device scan → Account selection → Birthday → Passcode → Customise account |
| Ledger | Device connect → Birthday → Passcode → Customise account |
| Wallet Link | Link intro → Link scan → Account selection → Contact selection → Passcode |
| Gift creation | Passcode → Customise account |

- Welcome does not show a progress bar. Introduction and method/device selection
  use the common entry position.
- An existing passcode removes only the Passcode step from the selected plan.
  Account-ready/Face ID is 100%; the final preparation step stays below 100%.
- Back returns to that screen's position. Choosing another method starts that
  method's plan rather than carrying forward a previous maximum.
- Education Skip advances to Secret passphrase without removing the skipped
  steps. Paste/manual entry, passcode confirmation, retries, and modal sheets
  retain their current position.
- Progress is not persisted. The route context carries no duplicate credential
  or mnemonic data, and invalid flow/step combinations fail explicitly.

## Gift inspection, storage, and claim

### Before account creation

Explicit paste or scan inspects the card in a temporary claim wallet without a
receiving account. Checking uses the shared skeleton, hides amount/artwork, and
disables dismissal. Error and unavailable-card states expose their existing
exit/retry controls. Opening the scanner or reading/validating clipboard text
keeps the entry card; the skeleton begins only when a valid card is inspected.
Old birthdays keep the existing long-scan warning sheet.

Price lookup is independent of inspection and claim execution. Entering the
card screen reuses a fresh persisted ZEC price or fetches it once in the
background. A stored card fiat snapshot takes precedence; otherwise an available
price supplies the approximate value. While price is missing or unavailable,
only ZEC is shown. No loading indicator, periodic refresh, or awaited price
request is added to account setup, binding, or claiming. Non-mainnet pricing
keeps the existing feature gate.

Inspection is a snapshot. It does not guarantee that funds remain available or
that a later claim succeeds. A checked or confirmation-waiting card can proceed
to wallet setup.

### New-wallet commit boundary

1. Passcode confirmation retains the digits in live flow memory. It does not
   create the account or finish credential setup.
2. Customise Continue prepares the credential, creates the account, and durably
   saves its metadata and the incoming card with the receiving account UUID.
3. Commit the credential and finish the setup journal before handing the checked
   inspection to `PaymentLinkClaimCoordinator.claimSetupCard`.
4. Continue to optional Face ID and Home without waiting for binding, broadcast,
   or confirmations. The coordinator owns that work independently of the screen.

Pre-account failures remain inline and can roll back the newly prepared
credential. If account creation may already have succeeded, retain the credential
and recover the same account. A known UUID with incomplete storage is recovered
immediately; repeated failures lock the persona controls and offer **Try again**
on Customise. Retrying does not create another account or prepare its credential
again. An uncertain database result uses the existing reopen message and disables
recreation.

The recovery journal preserves whether the inspected creation date is provisional.
After recovery, a later funding scan can still replace it with the transaction's
block time; an already resolved date remains unchanged.

The live flow retains the inspection/passcode through route refresh and clears
them on completion or exit. They are not serialized into route restoration or
browser history. Locking routes to unlock; the durable journal supports recovery.

### Import and receiving-account selection

Choosing an existing wallet saves the card and the pre-import account UUIDs in
OS secure storage before leaving the card screen. All existing import methods
remain available: secret passphrase, Link Vizor Desktop, and the hardware wallet
options under their existing capability gates.

At startup, this import handoff also identifies unfinished first-wallet setup.
If no account exists, discard the prepared credential so the next import asks
for a passcode again; keep the bearer journal for recovery. A durable account
keeps its credential and routes to unlock. An unreadable account DB blocks
startup without removing either credential or journal.

In a live import, a sole imported account receives the card automatically.
Multiple imported accounts reuse **Choose receiving account**, including additional ZIP32 accounts.
Confirmation switches Home to that account, saves the pinned recipient, registers
the existing inspection, and clears the import journal before Face ID.

Closing the sheet continues to Face ID/Home with an unbound, unclaimed card in
**Settings > My gift cards > Received**. Restart before selection also preserves
it for manual claim. Restart before any recipient binding also preserves a
single-account import for manual selection: a new UUID alone cannot prove it
belongs to the interrupted import. Cancelling the import clears its durable
handoff even if no live request survived. A receiving choice already saved
survives interruption during journal cleanup. Removing a received card cancels
its matching handoff before deletion so restart recovery cannot recreate it.

### Execution and recovery

- Binding reuses the inspected database and re-estimates amount/fee for the
  saved recipient. **Do not add another sync or a background freshness scan at
  this handoff.** Existing later claim/recovery scans remain unchanged.
- Confirmation waiting remains pending. Definitive rejection/failure stays
  actionable in Received. An uncertain submission retains recovery state rather
  than being treated as a definite failure. Preparation timeouts remain
  retryable; pausing an inspection does not persist an intermediate no-balance
  result onto an automatically recoverable setup card. A malformed import
  handoff is preserved and cannot block recovery of other Received cards.
- Eligible saved setup claims can resume after restart, unlock, foreground
  entry, or the existing retry timer, after setup journals/start markers are
  cleared. Completing durable account recovery explicitly wakes claim recovery,
  including when the account UUID was already present. Account switching cannot
  redirect claims to another recipient.
- Failed, rejected, spent-elsewhere, archived, and terminal empty cards do not
  automatically submit. A missing receiving account is not substituted.
- Submitted claims use the existing Home Activity transaction identity. Waiting
  or failure without a txid does not create a synthetic transaction row.
- A failed live setup-claim attempt shows a dismissible Home toast with
  **View card**, once the recipient's Home is visible. Face ID defers the notice.
  Leaving Home, either wallet/privacy lock, or account switching hides the notice
  without acknowledging it; it returns on the recipient's unlocked Home until
  dismissed or opened. Temporary copy feedback restores the persistent notice
  afterward. There is no Gift status banner, return page, or setup-failure screen.
- Received lists saved incoming cards, including pending/unsuccessful ones; it
  does not imply an on-chain receipt. Inspection/binding alone does not save a
  card, so setup must persist it before claim handoff.
- Destructive operations drain accepted setup/claim work before deleting account
  data. After account removal, reconciliation forgets unclaimed setup cards bound
  to that recipient and deletes their temporary claim wallets. It preserves cards
  bound to other accounts and unbound cards. Cleanup failure retains the record
  for retry; it never chooses a replacement recipient. Removing the final account
  resets Vizor and clears the entire Received store. Successful claims clean up
  their temporary claim wallet and recovery secrets after the existing
  six-scanned-confirmation condition.

### Shared account-setup safety

Ordinary first-wallet creation and passphrase import write encrypted recovery
material before the Rust DB mutation. Import recovery includes the BIP39
passphrase and all discovered ZIP32 accounts. A DB account that may already
exist keeps its credential; restart/unlock finishes its original secret and
metadata writes instead of creating a replacement account. Existing stored
recovery material is verified against the DB before any missing secret is added.

Pre-account rollback deletes the pending journal before removing its credential.
A failed cleanup blocks a replacement credential until retry succeeds. Successful
hardware/Wallet Link setup clears its start marker without deleting a pending
mnemonic journal. Forgot passcode explicitly warns that resetting an unbacked
account makes its funds unrecoverable.

Abandoned Customise inspections are released only when no account handoff owns
them. The cleanup service preserves a cache while account-setup recovery material
is pending. The existing lock-time cleanup guard still defers deletion; scheduling
that deferred cleanup across unlock/restart remains a separate follow-up.

Mobile root back dispatch includes Gift routes, and the themed system-bar region
restores icon contrast after leaving Welcome in the same light/dark theme.

## Home, backup, and education

Home's setup carousel is **manual**, using swipe and page indicators. It contains
account-scoped backup guidance and Zcash education, with no chevron or automatic
rotation. Account customisation is completed before Home; neither carousel item
asks the user to name the account again.

The backup entry opens an introduction before revealing the phrase. **Remind me
later** hides that account's Home reminder without marking backup complete. Its
stored delays are 2 days, then 14 days, then 30 days for later deferrals; the
button does not promise a fixed number of days. Foreground entry and the deadline
refresh visibility. Settings still provides access during deferral.

Passcode or available biometric re-confirmation gates the reveal. Wallet birthday
height and best-effort date load alongside the phrase and have separate copy
actions when available. **I’ve written it down** saves explicit backup completion,
clears reminder deferral, and returns after persistence. The account remains
accessible in Settings even after Home guidance disappears. These reminder and
completion controls belong to post-creation backup, not the ordinary creation
screen's phrase/Continue step.

Zcash introduction, address types, and things-to-know screens complete education
independently of backup. Removing an unbacked account shows its backup warning;
removing the last account becomes **Reset Vizor**. Combined removal warnings
remain scrollable at enlarged text sizes and use button confirmation without
requiring typed `remove`.

## Preview and verification

Widgetbook: **Screens > Gift Cards > Mobile > Onboarding - Full walkthrough**.
Focused cases cover entry, checking, inspected card, passcode, customisation,
Face ID, long-scan warning, storage recovery, failure toast, and imported
receiving-account selection. Preview broadcast/confirmation adapters are
simulated; they are not evidence of a real transfer.

Deterministic capture scenarios include `mobile-gift-onboarding-entry`,
`mobile-gift-onboarding-checking`, `mobile-gift-onboarding-inspected`, and
`mobile-gift-onboarding-customise`. Use the widget renderer for content comparison:

```bash
scripts/figma-compare.sh widget --form-factor mobile --scenario <scenario> --theme <light|dark>
fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile
fvm flutter test
fvm flutter analyze
```

Permanent iOS simulator regtest coverage runs with:

```bash
SIMULATOR_UDID=<simulator-uuid> scripts/e2e/flutter-ios-regtest-mobile-gift-onboarding.sh
scripts/e2e/flutter-ios-regtest-mobile-create-sync.sh
scripts/e2e/flutter-ios-regtest-mobile-import-sync.sh
```

The Gift runner covers an unfunded card's exit, first-wallet creation and import,
automatic real 0.1 TAZ receipt in Home balance/Activity, manual carousel selection,
backup deferral and completion, loaded birthday metadata, and Zcash education.
It also removes an unconfirmed card's recipient after adding another account
and verifies removal of both the saved Card and temporary claim DB. Finalized
receipts retain transaction evidence while deleting the bearer and temporary DB
after six scanned confirmations. It is part of the full mobile E2E runner;
the older Settings Gift round trip remains a separate scenario. No mnemonic or
bearer link is logged or captured. Simulator runs choose **Not now** on Face ID.

On 2026-10-02, all three Gift scenarios and the existing ordinary creation and
funded-import scenarios passed on iPhone 17 Pro / iOS 26.3. The import-restart
fix also passed 73 focused bootstrap/setup-recovery tests; scoped analysis of
six affected Dart files found no issues. Each Gift scenario mounts a fresh app
and drains accepted claim work before teardown. It does not clear storage under
a live flow. The full 19-scenario mobile suite was not run in this verification.

Integrated validation on 2026-10-02 used an iPhone 17 Pro / iOS 26.3 simulator
and an isolated Zcash regtest chain. It covered native Welcome playback, a real
0.1 TAZ claim, Home balance/Activity, manual carousel, reminder deferral and
completion, birthday, education, Received, six scanned confirmations, and
ordinary creation/additional import. The walkthrough masked all 24 mnemonic
words before rendering; capture-only source changes and harnesses were removed.

A subsequent native run exercised **Accounts > Reset Vizor → create a wallet →
import an additional account**, without replacing the app root or directly
clearing storage after entry. It verified account/passcode reset, two accounts
after recreation/import, and no widget exceptions. This exposed and fixed an
unsupported Ledger outbox read during removal checks on regtest: recovery now
uses the existing Ledger capability gate, while mainnet lookup errors remain
errors. Focused regression tests cover both non-mainnet networks and mainnet.

An earlier combined harness that replaced app roots and directly reset storage
failed with an unmounted widget reference and a covered import-route payload
error. The supported UI sequence above did not reproduce those errors; their
exact cause in that artificial harness remains unconfirmed.

The recording used **Not now** on Face ID. Physical device/hardware pairing,
biometric enrollment/authentication, OS process termination of the claimed
wallet, native screenshot exclusion, and the complete repository test suite
remain unverified by this walkthrough. Native storage reload/unlock is not an
OS process-restart test.

Known follow-up: the deferred failure toast is in memory. Restart before Home
can lose the notice while the card remains durably recoverable in Received.
Persisting unseen notices is separate from the completed flow connection.

The subsequent local repair passed 436 selected tests with mobile tokens and
59 selected tests with desktop tokens, including ordinary setup, BIP39 import,
partial storage failure/restart, rollback, claim retry, cancellation, removal,
privacy lock, root back, and notification replacement. These counts overlap.
Scoped analysis of 34 changed Dart files found no issues. Deterministic mobile
captures confirmed the reset warning in both themes at 393 × 852. Native
Rust/storage adapters were faked or fault-injected for these tests; the earlier
native results above do not validate this subsequent patch. Native E2E, Android
Activity behavior, and Linux concurrent keyring operations were not rerun.

Separate follow-ups remain: confirmation evidence for nonstandard/split card
funding, and a typed Rust execution outcome that can distinguish definitive
pre-broadcast failure from interrupted/ambiguous submission. The current patch
retains ambiguous submission state; moving the durable submission marker after
the Rust call would lose recovery for broadcasts interrupted before returning.

## Implementation references

- [Mobile routes and immutable progress context](../lib/src/core/navigation/mobile_onboarding_routes.dart)
- [Progress model](../lib/src/features/onboarding/mobile/mobile_onboarding_progress.dart)
- [Welcome media lifecycle](../lib/src/features/onboarding/shared/welcome_video_backdrop.dart)
- [Gift setup and handoff](../lib/src/features/payment_links/services/gift_claim_setup_coordinator.dart)
- [Credential/account setup boundary](../lib/src/features/payment_links/services/gift_wallet_setup.dart)
- [Claim coordinator](../lib/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart)
- [Post-creation backup](../lib/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart)
- [Home reminder visibility](../lib/src/features/home/providers/backup_reminder_provider.dart)
- [Account metadata and removal](../lib/src/providers/account_provider.dart)

## Interrupted first-wallet imports

Wallet Link writes an encrypted recovery journal before importing its first
account. If Rust creates accounts but mnemonic or account-metadata persistence
fails, the prepared credential is retained. Bootstrap lists the existing DB;
unlock matches each journal entry by seed and account index, restores only
accounts already present, and clears the journal after durable storage. Entries
not yet imported are not created during recovery. The existing nonempty-DB guard
continues to prevent a retry from replacing those accounts.

First Keystone and Ledger imports also retain the credential if the DB contains
an account or its state cannot be verified after a failure. The hardware UFVK
is already in Rust; no software mnemonic journal is needed. Desktop Ledger uses
the same failure boundary.

## Desktop integration

Desktop onboarding is delivered through a draft umbrella based on `main` after
#826. Its child PRs target the umbrella in the order below. The existing shared
account journals, credential retention, and unlock recovery apply to desktop;
the recovery slice connects and verifies desktop retry and navigation behavior.

1. Import-method and hardware selectors: first/additional-account entry,
   Back/Cancel destinations, and testnet capability copy.
2. Welcome: desktop video/poster, WebP playback, gradient, buttons, and network
   settings. Gift activation is connected in the later Gift slices.
3. Ordinary setup screens: introduction, password and account customisation,
   using the existing shared name/profile controls.
4. Interrupted setup: preserve existing accounts and credentials across storage
   failure, lock and restart; retry recovery instead of creating replacements.
5. Post-creation backup: password confirmation, phrase and birthday, explicit
   completion and Remind me later, with continued Settings access.
6. Gift into a new account: inspection, password if needed, customisation,
   durable setup and claim handoff, then Home; include additional accounts.
7. Gift into an imported account: software/Keystone/Ledger import, recipient
   selection when needed, and cancellation/restart recovery.
8. Home guidance and education: manual carousel, account-specific backup state
   and Zcash education. Do not add Gift status banners.
9. Full-flow E2E and walkthroughs: ordinary and Gift setup, first/additional
   accounts, failures, lock and restart. Hide mnemonic text in recordings.

Complete recovery and backup before integrating Gift onboarding. Desktop keeps
its existing password flow rather than adopting the mobile passcode/Face ID
screens. Link Vizor Desktop is excluded from the desktop import selector because
it is a phone-to-desktop QR flow. Ledger choices and summary copy follow the
existing capability gates; this work does not expand Ledger network support.

### Desktop import selection

Welcome and Add account open `/import/method`, offering secret-passphrase and
hardware import. `/import/hardware` offers Keystone and, where the existing
capability allows it, Ledger. The summary uses the same capability gate.
Selector-origin parameters survive birthday, password and customisation steps
without changing typed route extras. Cancel returns to the originating Welcome
or Add account screen; direct import/device entry retains its original fallback.

Preview the selectors from Widgetbook's desktop Welcome use case by clicking
Import wallet. The `desktop-onboarding-import` and
`desktop-onboarding-hardware` capture scenarios render deterministic content.

### Desktop Welcome

Welcome uses the desktop video and static WebP poster with the adjusted gradient
and shared accent-button effects. macOS uses the existing video player;
Windows/Linux use animated WebP without another player dependency. Both animation
assets contain the loop crossfade. Reduced motion and deterministic captures use
the poster; playback follows route visibility and app lifecycle.

Get started opens ordinary creation. Import wallet opens the selectors above,
including the additional-account return context. Initial Welcome retains network
settings; additional-account Welcome retains Back. The initial Welcome Gift
button is disabled until the later desktop Gift integration; Gift account
creation and claim paths are not activated by this visual slice.

Widgetbook has Large and Add account Welcome entries. Deterministic captures use
`desktop-onboarding-welcome` and `desktop-onboarding-add-account-welcome`.

The Figma Welcome reference (`8648:104679`, 1080 × 720) includes a Terms/Privacy
footer that is not implemented in this slice. Record it as a remaining visual
difference in review; the initial Gift action also remains disabled until the
later Gift integration slice.

### Desktop interrupted setup recovery

Password setup forwards its draft to Customise without creating an account;
additional accounts retain their existing credential and skip password setup.

If account persistence is interrupted or its DB state cannot be confirmed,
Customise freezes the name/profile and Back controls and offers **Retry setup**.
Retry locks the session and reloads the existing startup snapshot without
creating another account or preparing another password. Startup inspects the
DB: an existing account goes to Unlock, confirmed empty setup goes to Welcome,
and an unreadable DB goes to the existing startup error/retry screen. Unlock
must finish pending storage writes before Home opens. A lock during setup
reloads the snapshot before the router can expose Unlock.

This connection includes Ledger's callback-based Customise screen. Ordinary
errors before account creation retain editable fields and the existing inline
retry flow. The durable recovery journal and restart/unlock behavior remain
shared with mobile; this slice connects the desktop retry action.

Deterministic widget captures use `desktop-onboarding-recovery`,
`desktop-onboarding-recovery-uncertain`,
`desktop-onboarding-recovery-retry-error`,
`desktop-onboarding-recovery-pending`, `desktop-onboarding-ledger-recovery`,
and `desktop-onboarding-submit-error` in both light and dark themes.
