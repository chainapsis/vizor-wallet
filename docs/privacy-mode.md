# Privacy mode

Privacy mode ("Hide balance") replaces wallet amounts with `••••••`, so anyone
who can see the screen — nearby, over screen sharing, in a screenshot, or
through a screen reader — cannot learn how much the wallet holds or has moved.
Users toggle it with the eye button on home and in the desktop sidebar, and in
the mobile gift card list header. On mobile, flip to hide also toggles it from
any wallet page (below).

It changes presentation only. Validation, Max, proposals, and signing keep
using real values, and network requests, storage, and native surfaces are
unaffected. The setting is one flag shared by every account
(`privacyModeProvider`, stored as `zcash_privacy_mode_enabled`). An incomplete
reveal is tracked separately by `zcash_privacy_mode_reveal_pending_v1` in the
same secure-store bucket and is cleared by a full wallet reset.

## Hide balance on unlock

Settings > Hide balance > Hide balance on unlock is available on desktop and
mobile. It is off by default and stored separately from the current eye-button
state (`hideBalanceOnUnlockProvider`, `zcash_hide_balance_on_unlock`). Changing
this preference does not immediately change the displayed balance.

When enabled, successful wallet authentication hides amounts before the wallet
is uncovered: password/passcode/biometric sign-in, the desktop migration lock,
and the mobile sync keep-awake lock. Other password confirmations do not apply
it. An ordinary return to an already-unlocked app does not apply it either.
Users can show amounts with the eye button or flip gesture as usual; the next
unlock hides them again. All accounts share the preference, and a full wallet
reset clears it.

Automatic hiding updates the in-memory mask before persistence and keeps it
hidden if saving fails. Writes are ordered with manual eye-button changes so a
late write cannot reveal amounts after authentication.

## Flip to hide (mobile)

Flip to hide is off by default for both new installs and upgrades. Enable it
in Settings > Hide balance > Flip to hide.

When enabled, turning the phone screen-down hides amounts at once, and they stay
hidden when it is turned back. With amounts hidden, a flip down and back up
within 2 seconds shows them again. A phone left screen-down longer, on a table
or in a bag, only ever hides, so picking it up never reveals the balance. A slow turn
(such as holding the phone overhead lying down) is not a flip. A haptic and a
"Balance hidden" or "Balance shown" toast confirm the change, since the page
in view may show no amount.

Flip hiding applies the mask before saving and keeps it hidden if saving
fails. Revealing waits for a successful save and an active sensor session.
Pending changes share ordering with the eye button and automatic unlock hiding;
the detector reads the latest requested visibility, even while a save waits.
Success feedback follows a completed, still-current change. A failed save uses
an error toast; hiding failures explicitly say the balance remains hidden.
Locking, backgrounding, disabling the setting, or removing the host cancels a
pending reveal and suppresses its feedback. Before writing the visible flag,
the provider durably records a pending reveal. A failed preparation never writes
the visible flag. If a session ends during the visible write, the provider
attempts to restore the saved mask; failure leaves the pending marker intact.
Superseding requests retain that marker until their own save succeeds.

The final ownership/session check and in-memory reveal commit are synchronous.
Marker cleanup follows this commit in the same ordered queue; a session ending
during cleanup suppresses feedback but does not cancel an already-applied reveal.
Cleanup failure is nonfatal: if the marker remains, the next launch hides amounts
conservatively. Only a successful accepted change or saved hide may clear it.

Bootstrap reads the marker before the Boolean preference. Any existing marker,
including an unknown value, forces the first amount frame and semantics to be
hidden even when the saved flag says visible. Startup attempts to save hiding
before deleting the marker. A failed repair leaves it for a later startup or
privacy change; no unbounded retry or detached cleanup runs. Unknown reads hide
amounts, while unavailable secure storage retains the existing blocking startup
flow. Legacy installs with no marker keep their saved Boolean preference.

- `FlipToHideDetector` (`lib/src/core/privacy/flip_to_hide_detector.dart`)
  holds the thresholds: screen-down within about 40° of straight down, a turn
  from screen-up within 1 second, the 2 second show window.
- `FlipToHideBalanceHost` sits in the wallet's root shell route
  (`buildMobileRoutes`), so it covers every wallet page and its toast shows
  above pushed pages and sheets. It reads the sensor only while the app is
  visible, a wallet is unlocked, and the setting is on.
- The sensor is the `com.zcash.wallet/screen_facing` event channel
  (`screenFacingEvents`): gravity along the screen's normal, -1 screen up and
  1 screen down, from Core Motion on iOS and the gravity sensor on Android.
  Neither asks for a permission.
- Settings > Hide balance > Flip to hide controls the preference
  (`flipToHideBalanceProvider`, stored as
  `zcash_flip_to_hide_balance_enabled`). Only a saved `true` enables it.
  The earlier default-on implementation shipped only in QA/RC builds
  (`mobile/v0.0.63` and release candidates); its disabled flag is not migrated.

## Which amounts to mask

Classify each amount by where it comes from, not by the screen it is on.

| Category | Privacy mode | What belongs here | Examples |
| --- | --- | --- | --- |
| Holdings | Mask | Any value derived from the wallet's balances, including a value from which a balance can be worked out | Home and sidebar balances and their fiat; spendable or available labels; `Max: X`, `Use max: X`; "X available" in error copy; a shortfall such as "Additional ZEC needed" (total minus balance); the transparent amount on shield screens; migration amounts (Orchard balance, left to migrate, per-note, migrated); voting power and the amount left out of a vote |
| History | Mask | Amounts and fees of stored records | Activity rows; transaction receipts; swap and Pay detail and status pages; gift card lists and group detail |
| Current draft | Show | The amount the user is entering in this flow and what is computed from it, through the flow's own result screen | Composer amount, fiat conversion, quote, fee estimate, review; send status after submitting; the gift card ready screen; an incoming card being claimed; the amount in a payment request someone sent |
| Not wallet data | Show | Values that do not depend on this wallet | Prices and 24h change, swap rates, slippage, fee rates, round-wide vote tallies, protocol minimums |

Boundary rules:

- **Flow screen or record screen.** A screen that belongs to the composing
  flow shows the draft. A screen that displays a stored record masks, even when
  the app opens it right after a submit: swap and Pay continue to their
  activity detail page, which is a record screen.
- **Amounts the user acts on are shown.** When the user needs an amount to do
  the task in front of them, show it even if it comes from holdings or a
  record. Import discovery shows per-account balances because the user chooses
  accounts by them. The swap awaiting-deposit pages show the amount to deposit
  because the user may send it from another device, and the deposit QR carries
  no amount. A value that only tells the user how much the wallet holds stays
  masked, such as Max labels, shortfalls, and the shield amount.
- **Explicit actions carry real values.** Copy, CSV export, share, and the Max
  fill may use the real amount because the user chose where it goes. After
  tapping Max, the amount field shows the filled amount; the Max label stays
  masked. Nothing the app shows on its own may reveal a masked value.
- **Keep progress without amounts.** Where amounts are masked, keep
  percentages, counts, and step progress, such as migration progress and
  signing batches.
- **Zero is an amount.** Mask a zero balance too. Loading placeholders and
  fixed copy with no number ("Not enough ZEC") stay as they are.
- **Presence is out of scope.** UI that appears or is disabled because of the
  wallet's holdings, such as the transparent strip or a disabled Review button,
  is not masked.

## Every channel, both form factors

Mask the value in every channel that presents it: visible text, painted or
animated text, `Semantics` labels, tooltips, and status or error messages.
Desktop and mobile build most screens separately (`lib/src/app.dart` and
`buildMobileRoutes` in `lib/src/core/navigation/mobile_routes.dart`), so
masking a screen on one form factor requires checking its counterpart.

## Implementation

- Use the helpers in `lib/src/core/privacy/privacy_mask.dart`:
  `hideAmountIfPrivacyMode` for an amount with its denomination,
  `hideIfPrivacyMode` for a bare value, and `fixedPrivacyMask()` where the
  denomination or currency is drawn separately. Swap and Pay amounts use
  `swapAmountTextForPrivacy`, which keeps the leg's own symbol and masks any
  unrecognized text that contains a number.
- If the code appends the unit after the value (`'$amount ZEC'`, or a
  `Semantics` label that adds the currency), mask the bare number. Masking the
  full amount there renders `•••••• ZEC ZEC`.
- Mask where the display string is built, and pass that same string to `Text`
  and `Semantics`. Keep raw values for logic.
- Young Serif gives the bullet a digit's width, so a masked serif amount reads
  as spaced dots. A large serif amount (Home's balance card, a transaction
  record's hero amount) builds its span with `serifPrivacyMaskSpan`, which
  draws the bullets about half a dot apart and keeps the gap to the ticker.
  The plain text, and so `find.text` and the semantics label, stays the same.
- Read the flag with `ref.watch(privacyModeProvider)` in the build that
  produces the string, or pass it down as `privacyModeEnabled`, so a toggle
  updates the screen in place. A few presentational widgets default
  `privacyModeEnabled` to `false` because Widgetbook builds them without a
  `ProviderScope`; their production callers must still pass the watched flag.
- Test each masked site with privacy mode on (the raw amount is absent from
  text and semantics) and off (it is shown). Mobile-UI tests carry
  `@Tags(['mobile'])`. Existing examples are
  `test/core/privacy/privacy_mask_test.dart`,
  `test/support/gift_card_privacy_checks.dart` (registered in both lanes), and
  `ZEC swap composer masks the max balance in privacy mode` in
  `test/features/swap/swap_screen_test.dart`.
