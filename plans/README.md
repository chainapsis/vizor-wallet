# Mobile UI and motion fix plans

Written against commit `0604ac893` (`main`, 2026-11-11). Each plan is self-contained: exact files, current code, target values, steps, boundaries and verification. An executor needs no other context.

Ground rule for every plan: follow the code's existing conventions and do not change logic or patterns beyond what the plan states. If the code no longer matches a plan's "current" excerpt, stop and report instead of improvising.

## Plans

| # | Title | Severity | Change type | Status |
|---|---|---|---|---|
| [001](001-ios-reduce-motion-bridge.md) | Make iOS Reduce Motion reach the app's reduced-motion checks | HIGH | Small addition (new root widget) | APPLIED (uncommitted) |
| [002](002-activity-amount-width.md) | Stop cutting off amounts in mobile activity rows | HIGH | Value | APPLIED (uncommitted) |
| [003](003-home-idle-redraws.md) | Cut needless redraws on the Home tab | HIGH | Wrapper / rebuild scope | TODO |
| [004](004-tab-bar-motion.md) | Calm the tab bar icon motion | HIGH | Values | APPLIED (uncommitted) |
| [005](005-list-row-touch-feedback.md) | Give mobile list rows feedback on touch-down | HIGH | Small addition — **needs dev + design sign-off** | TODO |
| [006](006-activity-subrow-replay.md) | Stop activity sub-rows from replaying their entrance on scroll | HIGH | Small logic addition — **needs dev sign-off** | TODO |
| [007](007-balance-card-price-badge-contrast.md) | Make the 24h price badge on the balance card readable | HIGH | Small addition (copies `homeCard` token pattern) | APPLIED (uncommitted) |
| [008](008-text-token-contrast.md) | Fix four text color tokens that fail contrast | HIGH / MEDIUM | Values | APPLIED (uncommitted) |

## Recommended order

1. **008, 004, 002** — pure value changes. Lowest risk, easiest to review.
2. **007** — right after 008, in the same release. 008 darkens `text.positiveStrong`, which drops the balance card's "price up" badge (mobile and desktop) from 4.00:1 to 2.55:1 until 007 moves that badge to its own token. Both edit `app_text_colors.dart`, so run them in sequence.
3. **001, 003** — small additions with no visible change at default settings.
4. **005, 006** — only after sign-off.

## Dependencies and shared files

- `lib/src/core/theme/colors/app_text_colors.dart`: 007 and 008. Run in sequence.
- `lib/src/features/home/screens/mobile/mobile_home_screen.dart`: 003 and 007. Run in sequence.
- `lib/src/features/activity/widgets/activity_feed.dart`: 002 and 006. Run in sequence.
- No plan depends on another plan's result; the order above only avoids edit conflicts.

## Not planned (needs a decision first)

- **`text.muted` contrast** (3.41:1 light, 4.09:1 dark on cards): no existing primitive sits between `p500` and `p600`. Needs a new color from design.
- **Dark-mode balance card separation** (card `#1B1F1F` on window `#0F0F0F`, 1.15:1): raising the card a surface step or adding a shadow is a visual design change.
- **Removing the tab bar pop entirely** (instead of plan 004's reduction): structural; needs design sign-off.
- Medium and low motion findings from the review (sheet transitions, toasts, gesture tracking, curve tokens) were not selected for this round.

## Done outside these plans (uncommitted, 2026-11-12)

Requested directly for the Receive page, no plan file:

- **Toasts, app-wide** (`lib/src/core/widgets/app_toast.dart`): drop in from above with a fade (350 ms, `Cubic(0.23, 1, 0.32, 1)`), leave the same way (200 ms). A replacement swaps in place; reduced motion fades only. `test/core/widgets/app_toast_test.dart` updated for the timing, plus two motion tests.
- **Renew button** (`ReceiveRenewButton`, mobile and desktop): the icon spins (700 ms per turn) from the tap until the renewal ends, then a critically damped spring brings it to rest upright. Replaces the swap to a `CircularProgressIndicator`. No spin under `disableAnimations`, like `AppLoadingIcon`.
- **Mobile receive pool switch** (`mobile_receive_screen.dart`): 420 ms `easeInOutCubic` → 300 ms `Cubic(0.32, 0.72, 0, 1)`; the off-center card scales to 0.94 and half-fades. The desktop receive pager still uses 420 ms.
- **Mobile sizing, after a reference app** (mobile only; global tokens and desktop untouched):
  - Tab bar (`app_mobile_tab_bar.dart`): 64 → 52 pt tall, 44 pt items, 24 pt icons, and it hugs its tabs (64 pt each) instead of spanning the screen. The vertical rail uses the same items.
  - Activity rows on Home and Activity (`activity_feed.dart`, `activity_skeleton_row.dart`): 40 → 44 pt circles with 20 pt glyphs, 44 → 56 pt rows (68 pt pitch). Row text stays 16 pt. 48 pt circles or 18 pt titles cut off "Redeemed a gift card" beside a full Activity timestamp on a 393 pt phone, which `gift_card_progress_use_cases_test.dart` guards.
  - Home header name and "Recent activity": 16 → 18 pt (`headlineSmall`).
  - Fades: every tab root (Home, Swap, Activity, Settings) wraps its scroll view in `MobileTabRootScrollFades` (`mobile_tab_root_scroll_fades.dart`): a 64 pt top fade under the nav and a fade under the tab bar. Swap's scroll insets now match Activity and Settings (12 pt under the nav, `kMobileTabBarHeight + 48` bottom clearance instead of a literal 96).
  - `MobileTopScrollFade` / `MobileBottomScrollFade` apply updates that arrive mid-layout (a scroll position re-settling after its content resized) after the frame, which fixes a "Build scheduled during frame" assertion Settings' sheets exposed.
- **Tab icon flourishes** (`mobile_tab_bar_icon.dart`), one-shot when a tab becomes active, skipped under reduced motion, plain icon at rest:
  - Home tower: damped turn about the vertical axis (about 35°, 15°, 3°), 600 ms.
  - Swap arrows: half turn, 420 ms, `Cubic(0.77, 0, 0.175, 1)`.
  - History: the ring arrow spins one full turn clockwise while the hand sweeps two turns counter-clockwise, 650 ms, `Cubic(0.77, 0, 0.175, 1)` (the 24px artwork is split by a clip, no new assets).
  - Settings cog: quarter turn that coasts, 520 ms, `Cubic(0.23, 1, 0.32, 1)`.
- **Draggable tab pill** (`app_mobile_tab_bar.dart`): dragging anywhere along the bar moves the pill 1:1; each icon's tint follows how much of the pill covers it (smoothstep), so a tab lights up as the pill arrives; a strong haptic (`AppHaptics.tabSwitch`, iOS heavy impact) marks each tab it crosses; tracking counts from touch-down (no slop lag); release projects the flick's momentum (rate 0.99), snaps to the nearest tab and selects it, settling on a strong ease-out `Cubic(0.23, 1, 0.32, 1)` with no overshoot (taps keep the tuned select curve). Tapping a tab now plays the same strong haptic (was the selection tick).
- **Active tab pill**: no stroke; a neutral near-black tint (`navPanel.tabBarActiveBg`: `#141818` at 10% light, 50% dark). The sidebars keep the crimson `activeBg`.

## UI review, visual-consistency batch (uncommitted, 2026-11-12)

From the six-domain mobile UI review (better-interface). Mobile-only, existing tokens:

- Transaction detail card: labels on `labelLarge` (were 14pt `labelMedium`; fee row override removed), status value at regular weight, 8pt gap after Status like the other rows, help icons on `icon.muted`.
- Action labels on the 16pt label: Home "Shield" (`labelLarge`), Activity retry (`AppButtonSize.medium` on mobile).
- Ad-hoc styles: tabular figures on the Home balance and fiat/24h figures; Face ID and remove-account sheets use the shared sheet title (`bodyLarge` w600) and body (`bodyMedium`); fee and not-available sheet titles match; Activity month headers drop w600 on mobile; the emphasized Home entry subtitle keeps the token line height when it wraps.
- Settings: toggle rows (Keep screen awake, Use Tor, Private queries) use the chevron-row anatomy; toggle-card titles use the list-group spacing; list groups end with 16pt instead of 32pt; Profile picture value-to-chevron gap matches `MobileListRow`.
- Shared edges: Receive address and buttons share the QR card width (292pt); the top bar's trailing item sits inside the 16pt margin; the Swap address chip ends on the card edge.
- Icons: review-row ZEC coin and icon badge on `AppAssetSize.size`; help icons on `icon.muted`; Home entry chevron on `AppIconSize.medium`.
- Left as is (documented Figma values): Home activity list inset, Home balance 45pt hero and 14pt card labels, Receive 320pt pool tabs.
- Still open from the review: the copy items. The seven HIGH findings are fixed in the next section.

## UI review, blocking fixes (uncommitted, 2026-11-12)

The seven HIGH findings from the same review. Mobile-only unless noted:

- **Button role**: the Swap composer's custom taps, the Receive renew button and the Receive icon buttons report as buttons.
  - `AppButton` and `MobileListRow` are unchanged. About 37 call sites already wrap them in `Semantics(button: true, label: …)`, so callers own the role. Adding the role inside the shared widgets split those call sites into two nodes, one with the label and one with the tap, and 10 tests caught it.
  - `AppButton` uses with no wrapper still have no button role. The fix is a team decision: add wrappers at those call sites, or move the role into `AppButton` and remove the 37 wrappers.
- **Names**: the Swap direction toggle reads "Switch swap direction" (new `swapSwitchDirection` string in en, ko and zh); the two Swap amount fields are named "You pay" and "You receive"; the transaction detail memo toggle is named and reports expanded or collapsed.
- **Readable grey**: Activity supporting amounts and the Swap composer titles use `text.secondary` instead of `text.muted`; the light sync error text uses `p600` (was under 4.5:1).
- **Text grows instead of clipping** (large text sizes): fixed heights became minimum heights in Activity rows and month titles, transaction detail rows, Home "See all", the keep-awake, Tor and Private queries rows, and the Receive address summary. The Home balance card and its strip, and the Swap composer rows, scale their fixed parts with the text scaler.
- **Toggle off state**: the off outline of the keep-awake, Tor and Private queries toggles uses `icon.muted` (3.65:1 light, about 4.5:1 dark on the card); `border.medium` is only 2:1 and the border ramp has no step in between.
- **Dark tab bar icon**: new `navPanel.tabBarActiveIcon` (dark `CrimsonPrimitives.p600Dark`, about 4.9:1 on the dark pill; light unchanged). The sidebars keep `activeIcon`, which is 2.96:1 on the dark tab pill.
- **iOS Reduce Motion**: plan 001 applied as written (`PlatformReduceMotionScope` at the app root).
- Tests updated: the Home "See all" target is now at least 24pt (the label's own line height makes it 25pt); tab bar tests read `tabBarActiveIcon`.
- Still open at accessibility text sizes (horizontal, not clipped vertically): Activity and Home rows, the Home balance and the Home buttons truncate with an ellipsis, and the Receive pool tabs break words mid-word. Each needs a stacked or scale-to-fit layout, which is a design decision.

## Activity list without cards (uncommitted, 2026-11-12)

Requested directly. Mobile Activity lists months and rows straight on the page, like Home's recent activity: no card surface, rows 24pt in from the screen edge (the 16pt screen margin plus 8pt), month titles aligned with the rows, no card padding above or below a month. Desktop keeps its cards (`_activityFeedOnCards` in `activity_feed.dart`). The scroll anchor's offset estimate now uses the real row height (56pt on mobile) and the card padding constant. `activity_feed_mobile_test.dart` checks that no card surface is drawn.

## Mobile text at 16pt minimum (uncommitted, 2026-11-12)

Requested directly: no mobile text under 15–16pt where the phone has room. The tokens stay as Figma defines them; call sites in mobile-only files move up one step:

- `labelMedium` / `labelSmall` (14) to `labelLarge` (16), `bodySmall` (14) to `bodyMedium` (16), `codeSmall` (13) to `codeMedium` (16). 91 lines in 43 files: error and helper text, form labels and values, list subtitles, endpoint and explorer settings, Swap and Pay notes, migration and Ledger copy, and the default `MobileTextField` text and placeholder (the Send address field among them).
- Swap status rows always use the 16pt label (they used it only in Pay mode).
- Home balance card labels ("Shielded balance", fiat value, 24h change, Transparent strip, migration pill) use 16 / 17 instead of 14 / 16; the card's text-height budget is 82 (was 80), and the strip's is 17 (was 16).
- Keystone's inline firmware link uses a 16pt label in its 24pt small button.
- Kept at 14pt after the mobile lane caught them:
  - The sync status label ("Vizor is synced", top bar and sidebar). The top bar reserves a fixed slot for it beside the account. At 16pt the 320pt-wide guard test overflows the account row by 5.1pt. That test uses Flutter's 1em-wide test font, and the real font would fit, but the row has no way to shrink for a long label. Raising this label needs a top-bar layout decision.
  - The keep-awake lock's slowdown note, which sits inside the ring. At 16pt it reaches the ring ticks at larger text sizes.
- Left small where there is no room or size carries rank: seed-word grids (words in 90pt cells and their 01–24 indexes), word indexes on the import review, the create-step badge, the Keystone and migration signing badges and progress percentage, and the Ledger help's secondary notes.

## Sheet motion (uncommitted, 2026-11-12)

Requested directly: sheets felt laggy, the Swap slippage sheet most. Measured by recording the simulator and reading the card position frame by frame (debug build):

- **Swap and Pay modals had no motion.** They opened through `showGeneralDialog` with `transitionDuration: Duration.zero`. The scrim appeared at once; the card stayed at opacity 0 until `MobileModalCorners` resolved its corners, so it popped in about 120ms later; then the autofocused slippage field raised the keyboard and the card rode the keyboard inset in jumps of up to 130pt per frame. Closing removed scrim and card in one frame. Both screens now open their surfaces through `showAppMobileSheet` (`mobile_swap_screen.dart`, `mobile_pay_screen.dart`): the same 250ms entrance and 200ms exit, iOS corner preparation, scrim and drag-to-dismiss as every other mobile sheet. One sheet still hosts all surfaces and switches content in place. The sheet keeps drawing its last surface while it slides out, because the route's future completes on pop. The unused "Dismiss" barrier strings (`swapDismissBarrierLabel`, `payScanBarrierDismiss`) are removed; the sheets use the shared scrim label.
- **Keyboard during the entrance.** The slippage, Send memo and Receive request sheets autofocused their field, so the keyboard rose while the sheet was still sliding (or, on iOS, still offstage). They now call `focusWhenMobileSheetOpens` (`app_mobile_sheet.dart`) from `initState`, which focuses once the route is onstage and its entrance has completed. The Receive request sheet passes its own `FocusNode` through `RequestAmountSheetCompose` (the field still autofocuses when none is given, as in previews) and refocuses on returning from the result step.
- **Reduce Motion.** `ModalBottomSheetRoute`'s controller does not read `MediaQuery`, so iOS Reduce Motion never reached it. `showAppMobileSheet` now passes `AnimationStyle.noAnimation` when `MediaQuery.disableAnimationsOf` is true (iOS Reduce Motion included, through plan 001), on all three sheet paths.
- **Standard sheets were already smooth**: 60fps, a 200ms decelerating entrance and a 170ms exit. On iOS the route waits about 51ms in debug between push and motion: about 40ms building and laying out the sheet offstage (work the first frame needs anyway), 1–2.5ms for the native corner lookup and about 8ms for the post-frame hop. Left as is.
- **Still open:** while the keyboard animates, frames in the debug build come about 33ms apart. Every `MediaQuery.of` dependent (including the screen under the sheet, whose `Scaffold` resizes for the keyboard) rebuilds on each inset change. Profile builds do not run on the simulator, so this is unmeasured in release.
- Tests: Pay tests settle the sheet's entrance before acting on it; the Swap route test no longer expects a tap in the gap under the card to dismiss, matching every other mobile sheet.

## One sheet template (uncommitted, 2026-11-12)

Requested directly: every mobile bottom sheet on the same layout. The template is `MobileModalScaffold` (`app_mobile_sheet.dart`, Figma `_Modal Type` 4697:102962): top 32, bottom 24, sides 16, a 16px title-to-body gap, the title in `bodyLarge` w600 `text.accent`, the shared close button pinned top-right; then 24 from the body to the buttons and 12 between stacked buttons. An inventory of 52 sheet bodies found:

- **Removed overrides with no stated reason**:
  - `bottomPadding: 32` from 15 sheets: theme, language, keep-awake prompt, seed screenshot warning, share link, voting settings, request compose and result, Send memo, Keystone scan issues, migration notifications (sheet and preview), and both forgot-passcode sheets.
  - `bodyGap` 24 or 12 from 5 of those.
  - Every sheet now uses the template's bottom padding, so a change to it is one line.
- **Kept, because they are commented or are a different kind of surface**:
  - The asset picker (8px title gap, 12px bottom, Figma `Asset` variant) and the slippage stepper.
  - The scanner permission card, the contact edit sheet (title under the avatar), the accounts sheet and the payment request card.
  - The title-plus-subtitle sheets, which keep a 4px gap so the subtitle reads with the title.
  - The hero announcement sheets (Ironwood announcement and attention, NU7), the camera scanner and the birthday calendar.
- **Button stacks**:
  - 8px gaps became 12 in the payment-link confirm, long-sync warning, account discovery, unknown birthday, theme and language sheets, and in the payment request card's mobile layout.
  - Ledger's secondary help buttons now sit 12px below the primary (they touched it).
  - Body-to-buttons gaps became 24 in network settings (was 16), the Send memo (12) and the two migration sheets (32, whose title-to-body gap was also 32).
- **Moved onto the scaffold** (they built their own header, padding and close button, or had none):
  - The network fee sheet, the error-details sheet (mobile only; desktop keeps its dialog) and the Sapling parameters prompt, which has 8 callers and gets a ghost Cancel and an expanded Download.
  - The Receive address info sheet, the gift-card "How it works" sheet, and the account edit and profile picture sheets. `MobileSheetClose` is removed, since it had no other users.
- **Text**: the voting unanswered-questions sheet and the mobile error-details hint went from 14 to 16pt.
- **Left, needs a decision**:
  - The Swap service notice puts the ghost "Status page" above "OK". It is shared with desktop, where that order may be intended.
  - The payment request intro keeps its own header and 8px gap, also shared with desktop.
  - `unsupported_sheet.dart` has no callers.
- Tests: the widgetbook Receive info test reads the template, with no custom close and a 24px bottom.

## Swap composer and asset picker (uncommitted, 2026-11-12)

- **Asset list edges (Swap and Pay)**: rows were cut flat at the list's fixed-height top and bottom edges. The list now dissolves into the card through `MobileTopScrollFade` and `MobileBottomScrollFade` (32px bands in the sheet's `background.base`; both fades gained an optional `color`, defaulting to the window as before). Each fade appears only while rows wait beyond that edge, so the first and last rows rest uncovered.
- **Currency picker**: a tappable asset shows the list-row chevron (`AppIconSize.medium`, `icon.muted`) after its name; the fixed ZEC side does not.
- **Direction button**: the arrows turn half a turn each time the direction flips, always the same way round, 300ms on `Cubic(0.77, 0, 0.175, 1)` (the tab bar's swap curve); no turn under reduced motion. The direction key moved from the button to its tap target so a flip no longer remounts the button.

## Settings layout after a reference app (uncommitted, 2026-11-12)

Requested directly, from a reference Profile screen (measured at 393pt):

- **Account card at the top** (`_SettingsAccountCard`): the active account's 56pt picture, its name (`headlineSmall` w600) and "Manage accounts" (secondary), with a chevron. It is an 88pt raised card that opens the account switcher (`showMobileAccountsSheet`), as Home's header does. The Account group's picture and name rows stay.
- **Section titles sit above their cards** (`MobileSettingsSection` in `settings/widgets/mobile/mobile_settings_section.dart`): the 16pt secondary label, 12pt to the card, 24pt between sections. Used by the list groups, the Syncing card and the Privacy card.
- **Chevrons**: 20pt in Settings (`_settingsChevronSize`); `MobileListRow` gained an optional `chevronSize` (16pt default, so other screens are unchanged).
- **Rows**: 60pt (were 44), split by 0.5pt `border.subtle` hairlines across the content width (`MobileSettingsDivider`). Leading icons are `icon.accent` (were muted); chevrons are `icon.muted` (were accent), as in the reference.
- **Shadow**: cards take `mobileSettingsCardShadows`, a soft two-layer lift (0/2/8 and 0/6/20 in the subtle shadow token) instead of `appSurfaceShadow`'s tight outline. It shows in light mode and is transparent in dark mode. `MobileSurfaceCard` gained an optional `shadows` parameter (none by default).
- **Card padding**: 8px above the first row and below the last in the list sections; the Syncing and Privacy cards are 8 and 16 above and 24 below.
- Kept: the 16pt screen margins of the other tabs (the reference uses 24), the row text at 16pt, and value text in `text.accent`. The two Privacy blocks are long descriptions, so space separates them rather than a divider.
- Tests: the footer test measures from the Misc section, the private-queries test scrolls to the toggle, "John" appears on the card and in the Account Name row, and chevrons read `icon.muted`.

## Activity rows on the screen margin, larger primary line (uncommitted, 2026-11-12)

Requested directly:

- **Margin**: Home's recent activity and the Activity tab put rows 16px from the screen edge, the edge the balance card and action buttons use (they sat at 24, plus a 4px row inset). Home drops its 8px list padding (a Figma value until now). The feed's mobile row and month-title insets are 0 (`_activityFeedRowInset`, `_activityFeedTitleInset`). Mobile rows drop their 4px inner inset (`_activityRowHorizontalPadding`), which only framed the desktop hover and selection fill. Month titles keep 4px above and below but none at the sides, so their text starts on the row edge.
- **Type** (after a better-interface review of the rows):
  - The primary line, title and amount, is the 18 / 22 `headlineSmall` on mobile (was the 16px label). The two lines now differ in size as well as weight, and the text block (22 + 4 + 17) stands as tall as the 44px circle.
  - Subtitles and dates stay at 16px. Child rows (a swap's legs) stay on the label under their parent. Desktop is unchanged.
  - Amounts and dates use tabular figures (`withTabularFigures`), so stacked digits align. This applies on desktop as well.
- Left as is: Home's "Recent activity" header (18 w600) is now the same size as the row titles; weight alone sets it apart.
- Tests: Home's activity inset test now checks that rows share the buttons' edge. The gift-card truncation guard passes at 18px.

## Tab bar strip, row second line, swap arrows (uncommitted, 2026-11-12)

Requested directly:

- **Taps beside the tab bar**: the bar hugs its tabs, so taps beside or below it reached the rows scrolled underneath. The shell's `bottomNavigationBar` slot is wrapped in an opaque `Listener` (`app_mobile_shell.dart`), so the whole strip, gaps included, belongs to the bar. The bar keeps its own taps and drags. Content no longer scrolls from a drag that starts in that strip.
- **Shielded rows** show the filled shield (`AppIcons.shieldKeyhole`, crimson, 16px) in the subtitle on mobile; desktop keeps the outline. The row mapper is unchanged; the mobile row draws the filled glyph.
- **Second line**: on mobile the timestamp takes the subtitle's style, the 16px label at regular weight in `text.secondary` (it was weight 500 with letter spacing 0). It keeps tabular figures.
- **No minus on outgoing amounts** (mobile): `activityAmountTextForFormFactor` drops a leading "-" in front of a digit (the "--" placeholder stays), for transaction and swap rows. The title and icon already say the funds left; received amounts keep "+".
- **Swap direction arrows**: the earlier half-turn never played. The direction-dependent key sits on the tap target, which wrapped the `AnimatedRotation`, so each flip remounted it at its end value. The button's state now owns an `AnimationController` that drives a `RotationTransition`. That state survives flips, and a flip mid-turn continues from the current angle. `mobile_swap_modal_route_test.dart` checks the arrows are mid-turn 150ms after a flip and land on 0.5, then 1, turns. On the simulator the turn now spans about 270ms at 60fps.
- Tests: the sub-line icon test expects the filled shield; row amount pins in the Activity, Home and swap mapper tests are unsigned.

## Privacy card and one-tone amounts (uncommitted, 2026-11-12)

Requested directly:

- **Privacy card dividers**: a hairline now splits the Tor and Private queries blocks. `MobilePrivateQueriesControl(divided: true)` draws it itself, so it disappears with the control when private queries are unavailable. The Welcome network sheet keeps the default (no divider).
- **Private query server**: on mobile the cog beside the toggle is gone. A chevron row (`WalletPirServerSettingsRow`: cog, "Private query server", 20px chevron) sits under the description behind a hairline, shown only while private queries are on, and opens the same server sheet. It keeps the `wallet_pir_server_settings_button` key. Desktop keeps the cog (`WalletPirServerSettingsButton`).
- **Amounts in one tone (mobile)**: received amounts use the row's accent tone, like sent ones (`inboundAmountColor` in `activity_row_mapper.dart`). The "+" sign marks money in. Desktop keeps the green; failed rows keep their own treatment.

## Home balance card and 20px page margin (uncommitted, 2026-11-12)

Requested directly:

- **Balance card** (`mobile_home_screen.dart`): the balance is 40 / 44 and its ticker 28 / 31 (were 45 / 48 and 32 / 33). The card's inner padding is 24 at the bottom (was 16), and its height is 216 (was 200), so "Shielded balance" stands further from the figure. The text budget that keeps the figure clear of the label is 78 (17 + 17 + 44).
- **Page margin 20** (trial): a new `kMobilePageMargin = 20` sits beside `kMobileTopNavHeight` in `mobile_top_nav.dart`. The account top nav's leading and trailing gaps use it, as do the back variant's trailing slot and the scroll content of the four tab roots: Home (and its importing state), Activity, Swap and Settings. It replaces the 16px `AppSpacing.sm`, which stays the spacing token everywhere else.
  - Activity tab: the headerless feed sliver adds 12px at each side, so the screen pads `kMobilePageMargin - AppSpacing.s`. Before this, the screen padded 4, which put rows at 16.
  - Not changed: pushed screens (Send, Receive, Pay, Swap review, details, settings sub-pages, onboarding) and bottom sheets keep 16. The tab bar keeps its own margins (it hugs its tabs).
  - Tests: the empty-activity Rest canvas test uses a 402-wide surface. At 390 the 340px Figma canvas no longer fits inside the margins and scales to 334.
  - Checked: the gift card title on the Activity tab still fits on a 393-wide frame (the `gift_card_progress_use_cases` guard).

## 20px margin everywhere, Receive handover, shared surface style, Accounts over the tab bar (uncommitted, 2026-11-12)

Requested directly:

- **Page margin 20 on every mobile page**: `kMobilePageMargin` replaces the 16px `AppSpacing.sm` page margins on the mobile pushed and full-screen pages:
  - Send (recipient, amount, review, status), Pay, Receive (phone layout), transaction and swap/pay status, Address book, About, Donation, Accounts (and removal passcode), keep-awake lock.
  - Onboarding: the shared step scaffold covers about 25 steps; plus passcode, unlock, Welcome, wallet link.
  - Settings sub-pages (endpoints, explorer, seed phrase, viewing key, change passcode) and Gift Card mobile pages (`_sideInset`).
  - Swap review and status pages, voting mobile pages, Ironwood migration pages and Keystone signing.
  - Every edit swaps the value only. Width math that mirrors the margin (QR and scanner sizes, part-row widths, ring widths) moved with it. Normal and compact passcode layouts agree.
  - Left at 16: bottom sheets (their own template), card internals, overlays and toasts, the tab bar, the wide Receive split layout (its 560pt threshold assumes 16), and the Welcome landscape pane (button width clamp).
  - Pages that already used another margin keep it (24 in places, 0 on centred states).
  - Gift Card mobile cards are 361 wide, so on a 393pt phone they now clamp to 353 at the same height (as 375pt phones already did).
- **Receive pool switch**: the address line follows the QR pager's position, like the chip and the cards. It used to swap on tap with its own 140ms cross-fade, so the two addresses overlapped while the cards were still moving. Now one line shows at a time and drifts up to 12px with the cards. The pager's iOS curve covers half the distance in about 45ms, so the split is uneven: the outgoing address fades over the first 35% of travel (`addressFadeOut`), and the selected one fades in over the rest, about 250ms as the cards settle. Mid-swipe both sides of the handover sit at the same low opacity, swipes scrub it, and RTL mirrors the drift. The test 'the address hands over with the cards, never doubled' pins it.
- **Shared surface style** (core):
  - `mobile_surface_card.dart` now holds `mobileSurfaceShadows` (the Settings soft lift), and `MobileSurfaceCard` uses it by default (`shadows: const []` for a flat card).
  - `mobile_section.dart` adds `MobileSection` (label above the card), `MobileSectionRows` (rows split by hairlines) and `MobileSectionDivider`.
  - The Settings-only file is gone and Settings uses the core widgets.
  - Accounts' Current and Other groups use the section style: label above the card, 60px rows, hairlines, sections 24 apart.
  - Standalone ground-coloured page surfaces (the swap ticket and others) get the same lift: see the rollout notes below.
- **Accounts covers the tab bar**: `/accounts` moved out of the Home branch to the top-level detail routes, the same push-over-the-shell pattern as the Settings detail screens. Its list and row menu clear only the bottom inset now. Back falls back to `/home` when nothing is underneath (the viewing-key retry reaches it with `go`). Route tests cover push/back and go/back.
- **Send review confirm button** keeps its label on one line (`constrainContent` plus ellipsis, as the amount step already did), since the narrower page could overflow long status labels.
- Rollout notes:
  - The soft lift was added to page cards: the swap ticket, swap review/status cards, pay amount and review cards, the transaction detail card, explorer and endpoint options, Address Types cards, Ledger/Keystone onboarding cards, wallet-link cards, the Gift Card review summary, migration schedule cards, the Home notice and entry cards, and the Keystone voting memo box.
  - Mobile cards that had the outline or 1px shadow moved to it: voting poll/result/proposal cards, migration status/option/review/preview cards, Home's balance-card group, and `ReviewWrapCard` on mobile only.
  - The address book's network groups use `MobileSection`, with the network icon in its new `leading` slot. Rows are 60px with hairlines.
  - Send review and swap/pay status put their side margins inside the scroll view, so the lift isn't clipped. The two migration schedule lists still clip it at the card sides; that would need a larger restructure, so it's left.
  - Not converted: lists whose labels already sit on the page above separate tappable cards (wallet link, Keystone accounts, endpoint presets, migration rounds), and Gift Card lists, which are cardless by design.
- **Import review Continue** gets the same one-line guard as its Clear button, for the same reason as the send review confirm button.
- Tests:
  - About 40 mobile-lane geometry pins moved to the 20px margin: page-wide widths 361 → 353 (488 → 480 and 408 → 400 on wider frames), and left edges 16 → 20. Accounts rows, padding and menu clearance moved too.
  - Pins on flat cards that now carry the soft lift expect `mobileSurfaceShadows` (Home voting entry, pay amount card).
  - The pay review tests run on a 402pt frame: inside the 20px margins, the test font (every glyph a full em) needs that much width for the quote-expiry label.
  - Sheets and modals keep their 16px pins.
  - Results: `fvm flutter analyze` is clean; the mobile lane passes (3132) and the desktop lane passes (7329).

## Transaction record redesign (uncommitted, 2026-11-12)

Requested directly. Figma: file `jhozt3bbbVYms9MkpGJgoI`, page 🎨 Design Updates 🎨, section ACTIVITY & STATUS. Frames: Sent `9293:34799` (the "Recipient" revision of `9284:34246`), Received `9292:34716`, Failed `9296:35482`.

- **Layout** (`mobile_transaction_status_screen.dart`):
  - From the top: small sans title (`headlineSmall`), the transaction type icon, the status chip, the amount in Young Serif 40 with a 32 ticker, then a line for the pool or source.
  - One card with a soft lift: To/From (pool icon, name or truncated address, a chevron that opens the full-address sheet), Message, Tx ID, then Timestamp and Tx fee.
  - Gift cards keep their card art in place of the type icon. Shielding, migration, incomplete-details and transparent-details variants keep their content in the same row style.
- **Figma wording** (follow-up, requested): seven new keys with English, Korean and Chinese:
  - Titles: `activityTitleSentZec` "Sent ZEC", `activityTitleSendingZec` "Sending ZEC...", `activityTitleSendZecFailed` "Send ZEC failed", `activityTitleReceivedZec` "Received ZEC", `activityTitleReceivingZec` "Receiving ZEC...", `activityTitleReceiveZecFailed` "Receive ZEC failed".
  - Label: `activityReceiptRecipient` "Recipient", for a send's counterparty row (and its loading and unknown-recipient rows). Shielding and migration rows keep "To".
  - Korean uses the short noun form (`ZEC 보냄`, `ZEC 받음`) with no particle after ZEC. Chinese follows the existing 已发送/已接收 forms. ZEC stays untranslated.
  - Generated with `tool/l10n/generate.dart`; the font subsets were already current.
  - The shared receipt test helpers take the titles and the recipient label per form factor; desktop keeps its strings.
- **Dollar value** (follow-up): under the amount, at today's ZEC price (`zecHomeUsdUnitPriceProvider`, the price Home's balance uses; transactions store no historical price). It is masked with the amount in privacy mode (receipts are History).
  - It replaces the pool line on sends; the recipient row's icon keeps the pool.
  - Shielding, migration and receives keep their source or receiving line under it.
  - Without a price, the page is unchanged. Key `mobile_tx_status_fiat`.
- **Top area is the type icon, status, ZEC, USD only** (follow-up, for all records). Everything that sat under the amount moved into the card:
  - **Shielding:** a "From: Transparent balance" row (new key `activityBalanceTransparent`, with Korean 공개 잔액 and Chinese 公开余额) above "To: Shielded balance".
  - **Migration:** "From: Orchard balance" above "To: Ironwood balance".
  - **Net change:** fee-inclusive and fee-only entries get a "Net change" row (`mobile_tx_status_net_change`) with the amount.
  - **Pools:** a send's or sender's pool stays on the counterparty row's icon, with a screen-reader label.
  - **Receives:** the wallet's own receiving address is no longer shown. Under the amount it read as the sender, whom Zcash never reveals.
  - The hero keeps one reserved line for the dollar value, so the card does not move when the price arrives.
  - Tests: pool checks use the row icon's label; the shared transparent-details helpers take `showsOwnReceivingAddress` (desktop true, mobile false).
- **Backdrop** (follow-up): the faded castle engraving from the send status screen (`mobileTransactionProgressBackgroundImage`) sits behind the whole record at 60% opacity, fixed at the top and fading out halfway down, as in the updated Figma frame.
  - Light theme only: the art is light and has no dark version.
- **Known gaps from Figma**:
  - Ordinary transactions have no fiat value, so the line under the amount shows the pool or source.
  - The Figma Received frame shows a fee and no sender row; existing logic keeps the sender row and hides the fee on receives.
- **Tests**:
  - The transaction status tests and the shared receipt test helpers follow the new structure.
  - The fee-help test scrolls the fee into view.

## UI tweaks: toggles, tab pill, settings icons, balance card (uncommitted, 2026-11-12)

Requested directly:

1. **Toggles without an outline**: `MobilePrivacyToggle` (Tor and Private queries) and `_SyncKeepAwakeToggle` drop their border.
   - The off track moves from `background.raised` to `background.overlay`, one step further from the card in both themes, as the voting toggle already does.
   - The white thumb takes `appSurfaceShadow`, which outlines it on light cards and is transparent in dark.
   - The old outline was there for 3:1 non-text contrast of the off track. The thumb's shadow and the darker track now carry that boundary, at lower measured contrast in light mode.
2. **Tab bar, dark**: the active pill is white at 10% (`Primitives.p900Alpha10Dark`, was black 50%), so it stands out from the dark bar.
   - The active icon is the saturated brand crimson `CrimsonPrimitives.p400Dark`, the shielded marks' tint (was the lifted `p600Dark`).
   - Measured about 2.2:1 on the pill, under the 3:1 non-text guideline. This is a deliberate design choice; the pill also marks the selection. Light mode is unchanged.
3. **Use Tor and Private queries icons** are `icon.accent`, like the other Settings rows (they were grey when off and crimson when on). The status text and toggle carry the state. The mobile Tor presentation drops its unused per-state icon colour; desktop is unchanged.
4. **Support Vizor**: its heart is brand crimson (`_RowIcon(brand: true)` uses `icon.brandCrimson`).
5. **Home balance card**: the 7% white outline is gone; the fill separates the card in both themes.

## Receive actions and add-account back (uncommitted, 2026-11-12)

Requested directly:

1. **Receive, share in the nav**: Share leaves the action row for the top nav's trailing slot (`_ShareNavButton`), opposite the back chevron and drawn like it: a bare 24pt icon on a 44pt target, `icon.accent`, `icon.disabled` until an address loads. Its accessible label still names the pool ("Share shielded address").
2. **Receive, full-width actions**: Copy address and Request ZEC each span the 292pt column the QR card sets, 12pt apart. Request is a secondary button (was text-only ghost); Copy keeps primary on Shielded and secondary on Transparent.
   - The wide (landscape and tablet) layout gets the same: share in its nav, request secondary.
   - The now-unused "Share address" label (`receiveShareAddress`) is removed from en, ko and zh and regenerated.
3. **Add account back chevron**: it called `context.go('/home')`, which threw away the history and always jumped to Home, however Add account was opened. It now pops back to the screen that opened it (Accounts from Settings, or the tab under the accounts sheet) and goes home only when there is nothing to pop, the same pattern as the Gift Card education screen.
   - A regression test pushes Add account over an Accounts route and checks Back returns there.

## Mobile page transition: fade and zoom (uncommitted, 2026-11-13)

Requested directly ("don't like the slide effect"; picked "Fade + zoom" from the options).

- **`MobilePage`** (`lib/src/core/navigation/mobile_page.dart`) replaces `CupertinoPage` for every mobile screen:
  - `_mobilePage` in `mobile_routes.dart` (tab shell and every pushed screen).
  - `_mobileOnboardingPage` in `mobile_onboarding_routes.dart`.
  - The Gift Card steps in `payment_links_mobile_body.dart`.
  - Translucent fades (`MobileShieldPage`, Ledger signing overlays) and the onboarding `CustomTransitionPage` fades are unchanged.
- **Look**: the new page fades in while growing from 94% to full size, and the page it covers grows to 103%. A pop plays it backwards.
  - 320ms in, 260ms out, on a strong ease-out (`Cubic(0.23, 1, 0.32, 1)`) and its mirror.
  - Nothing slides on its own.
  - With reduced motion (`MediaQuery.disableAnimations`, which includes iOS Reduce Motion) only the fade remains.
  - Only another `MobilePage` moves the page underneath; sheets and translucent overlays leave it still, as Cupertino did.
- **Back swipe kept**: a drag from the leading 20pt edge (wider on a notched side) pops the page.
  - The page follows the finger 1:1 while it fades and shrinks.
  - A fling over one screen width per second, or a drag past halfway, completes the pop; anything less settles back over 350ms.
  - These are `CupertinoPageRoute`'s rules, reimplemented in the route because Flutter keeps its gesture code private. Swipes stay off where a `PopScope` blocks popping.
- **Tests**:
  - `test/core/navigation/mobile_page_test.dart`: the push fades and zooms in place, the covered page grows, reduced motion keeps only the fade, and the edge swipe follows the finger, settles back or pops.
  - `mobile_routes_test.dart`: route type checks now expect `MobilePageRoute`. The wide-layout test measures the pushed page's layout size mid-push, since the zoom makes its on-screen size smaller.
- **Haptic on every page change** (follow-up, requested): `MobilePageRoute` plays `AppHaptics.pageTransition()`, a light tap, when a page is pushed or popped, including a completed back swipe.
  - A navigator's first page (the tab shell after unlock, the first Gift Card step) appears without one, and a swipe that settles back is silent.
  - Home's Send, Receive and Pay buttons already tap (`AppHaptics.action()`) before they push. The page tap skips itself within 150ms of an action tap, so those give one tap, not two.
  - Tests in `mobile_page_test.dart`, now tagged `mobile`: one tap per push and per pop, none for the first page or a cancelled swipe, and no second tap after a button's tap.

## Received amount sign on the record (uncommitted, 2026-11-13)

Requested directly: the transaction record's hero amount for a receive (and a pending "receiving") reads "+0.0006849 ZEC", like its activity row. `ZecAmount.activityDetailPretty` takes `signed` (as `signedActivityPretty` already did) and the record passes `_isIncoming`. Sends, shieldings, migrations and privacy-masked amounts are unchanged. Test: `a received amount reads as money in`.

## Performance: page fade and sheet keyboard (uncommitted, 2026-11-13)

Requested directly after the performance review: fix the page fade and the keyboard rising in sheets (every instance).

- **Page fade** (`mobile_page.dart`): the opacity now runs on its own curve, `Interval(0, 0.4, curve: Curves.easeOut)`, which tracks the old fade within 0.07 but reaches 1 at 128ms. The page is drawn through a full-screen offscreen layer only for those 128ms instead of all 320ms. A pop fades out over its first 40% (`Interval(0.6, 1, curve: Curves.easeIn)`) and draws nothing after. The zoom, including the covered page's 1.03, is unchanged: the covered page renders every frame of a transition anyway, so dropping its zoom would save nothing. A back swipe still fades linearly with the finger. Test: `the fade ends early, so most of the zoom draws opaque`.
- **Keyboard in sheets**, every `MediaQuery` keyboard read was checked:
  - App root (`app.dart`): the `MaterialApp.builder` read `MediaQuery.of`, so all ~20 root hosts rebuilt on each keyboard frame. The read moved into a `Builder` around `MobileWindowPolicyScope` only.
  - Screens beneath a sheet: `CoveredRouteKeyboardHold` wraps every `MobilePage` and the wallet shell route. A covered route whose keyboard was down holds the bottom inset and padding, so the shell, its tabs and the covered page no longer rebuild and lay out on each keyboard frame. Uncovered, it keeps holding while that keyboard goes down and follows the keyboard as soon as it rises again. A route covered with its own keyboard up behaves as before.
  - Sheet bodies sized to the keyboard: the add/edit contact sheet, the Pay add-contact card, the swap asset selector and the contact picker read `MediaQuery.of` in their build, so the whole body rebuilt per keyboard frame. `MobileKeyboardAwareHeight` now computes the same height (same formula and clamps) and only its builder runs per frame.
  - Narrowed to `viewInsetsOf` / `viewPaddingOf`: `MobileModalCard.bottomGapFor` and `MobileKeyboardToolbar`.
  - iOS shell geometry: every metrics change (each keyboard frame) makes `MobileAdaptiveFrame` re-read the native navigation geometry, and it called `setState` even for an identical snapshot, rebuilding the shell under a sheet every frame. `MobileNavigationGeometry` now has value equality and an unchanged snapshot is skipped.
  - Checked and left: the slippage stepper (reads `viewInsetsOf` in `didChangeDependencies` to reveal the stepper; small sheet), `MobileModalCorners` (inside the card, which follows the keyboard anyway), `mobile_exit_back_guard`, the QR scan card (no keyboard), the two no-text-scaling `Text` leaves, `MobilePageViewport` and `MobileAdaptiveFrame` (follow a page's own keyboard; held under sheets).
  - Tests: `covered_route_keyboard_hold_test.dart`.

## Home Receive opens a sheet: receive, request, redeem (uncommitted, 2026-11-15)

Requested directly: the mobile Home Receive button opens a bottom sheet instead of the Receive page, with Receive ZEC, Request ZEC and Redeem gift card, with icons and corrected copy. Follow-up, from a reference screenshot: the three buttons became cards (round icon badge, title, description), built as a reusable component; Receive gets the QR icon, and Request keeps a placeholder until the designer's icon is ready.

- **Card** (`core/widgets/mobile/mobile_action_card.dart`): `MobileActionCard(icon, title, subtitle, onTap)`, a reusable action card. It is a `MobileSurfaceCard` (the settings groups' ground surface with the shared `mobileSurfaceShadows` lift, no stroke) with `AppRadii.large` corners, a 36px round badge in the primary button's colours (`button.primary.bg` with a `button.primary.label` 20px icon: dark in light theme, light in dark theme), `labelLarge` title and `bodyMedium` secondary description. One semantics button reads the title then the description. No haptics or navigation of its own.
- **Sheet** (`receive/widgets/mobile/receive_options_sheet.dart`): `showReceiveOptionsSheet` shows `ReceiveOptionsSheet` in the shared `MobileModalScaffold` (title "Receive", close button) and resolves to a `ReceiveOption`; Home acts on it after the sheet closes, as it does for its other sheets. Icons: `qr` for Receive, `link` as Request's placeholder, `giftCard` (as in Settings). The earlier primary/secondary distinction between the buttons is gone: the cards are alike, as in the reference.
- **Copy**: titles "Receive ZEC" (`receiveTitle`), "Request ZEC" (`receiveRequestButton`) and `homeReceiveRedeemGiftCard` "Redeem gift card" (sentence case; the glossary spells "gift card" in lower case). Descriptions: `homeReceiveReceiveSubtitle` "Share your address or QR code", `homeReceiveRequestSubtitle` "Ask for an exact amount", `homeReceiveRedeemGiftCardSubtitle` "Add a card someone sent you", with Korean and Chinese following the existing gift card and request terms. The reused keys' descriptions name the sheet.
- **Both Home Receive buttons** open the sheet: the funded-state Receive and the empty-wallet "Receive your first ZEC".
- **Receive ZEC** pushes `/receive` as before. **Request ZEC** opens the existing request sheet for the active account's shielded address (`showActiveAccountRequestSheet` in `receive_request_sheet.dart`, the address the Receive screen opens on), with the existing load-failure toast. **Redeem gift card** pushes `/payment-links?redeem=1`; `PaymentLinksScreen.startOnRedeem` opens it on the paste page, and back leads to the Gift Card home, as after a waiting card link. The router is built once at launch, so a hot reload does not pick up the route change; a restart does.
- Widgetbook "Receive / Mobile / Home options sheet" and the `mobile-receive-options-sheet` capture scenario. Tests: `MobileActionCard` (mobile commons), Home (both buttons, each card's title, description and icon, each option's destination), routes (`receive pushes over a mobile shell page` goes through the sheet), Gift Cards (`opened to redeem, back leads to the Gift Card home`), Widgetbook. The mobile regtest flows reach the Receive screen through the sheet (`openReceiveScreen`); they were not run.

## Standard mobile radio card (uncommitted, 2026-11-15)

Requested directly with screenshots of the theme picker and the private query server sheet: reuse the Receive cards' style for cards like these, remove the stroke from unselected radio cards (keep the thick stroke on the selected one), replace the server sheet's hand-built cards, and replace any other custom radio cards.

- **Component** (`core/widgets/mobile/mobile_radio_card.dart`): `MobileRadioCard(title, selected, onTap, details, iconName, titleLocale, semanticsLabel)`, following the Figma `Radio Card` (4654:74580) the Keystone and endpoint cards already cited: a `MobileSurfaceCard` (ground fill, `mobileSurfaceShadows`, 16px radius), min height 64, a 2px strong stroke only when selected (drawn over the card, so content no longer shifts by the stroke), a 32px icon cell dimmed to half when unselected, a `labelLarge` title (w600 selected, w500 not), `labelLarge` regular detail lines (accent when selected), and the trailing 24px check (`background.raised` when empty). A selection haptic when the choice changes. Its `Semantics` now carries the tap action: the old cards excluded their subtree, which dropped the gesture's action, so screen readers could not select them.
- **Moved onto it**: `MobileSettingsOptionCard` (theme and language pickers; it delegates and keeps its API), the mobile private query server rows (`_ServerRow` in `wallet_pir_server_settings.dart` branches on `kAppFormFactor`; address and latency are detail lines; rows stack 12px apart; the desktop rows and dialog are unchanged), `_ExplorerOptionCard`, the endpoint `_PresetCard` and the Keystone `_AccountCard` (private wrappers kept, so keys and call sites are unchanged).
- **Visible changes**: the theme, language and server cards lose their stroke and gain the shared shadow; the explorer's unselected card loses its faint stroke; the server rows lose their left crimson dot for the trailing check; the theme and language titles use the radio card's `labelLarge` weights.
- **Follow-up, requested directly: the migration and voting source cards moved too.** `MobileRadioCard` gained a `description` paragraph (the icon and check then align to the top), a `titleTrailing` widget beside the title, `actions` before the check, and `enabled` (dims to half and ignores taps; a null `onTap` alone still only blocks taps). Its semantics are one button node with the visuals excluded, so the actions keep their own buttons. The Ironwood `_MobileMigrationOptionCard` keeps its keys and the green "Recommended" badge (`_RecommendedBadge`); it moves from 24px to the standard 16px radius, a 24px check on `raised` and the radio card's title weights. The voting `_MobileSourceRow` keeps its edit and delete buttons as actions; it gains the shared shadow, loses its ripple and outlined empty check, and its title follows the selection weight. Tests that pinned the old internals now read `MobileRadioCard.selected`, the icon's opacity and the check icon's position.
- **Not moved** (from an audit of every mobile option card): the multi-select checkbox cards (account discovery, wallet-link import) and the vote choices (deselect on tap, auto-advance spinner). Desktop-only radio cards were out of scope. Titles and detail lines wrap rather than ellipsize, except a title that shares its line with a badge.
- `AGENTS.md` gains a "Mobile Cards" section naming `MobileRadioCard` and `MobileActionCard` as the standard. Widgetbook "Private query server" gains the sheet use case `buildWalletPirServerMobileSheetUseCase` and the `mobile-wallet-pir-server-sheet` capture scenario. Test: `MobileRadioCard strokes only the selected choice` (mobile commons).

## 3D removed from the transaction record (2026-11-15)

- The 3D coin and shield are removed completely: the renderer (`lib/src/core/widgets/model_3d/`), `TransactionCoinHero`, the models (`assets/3d/`), the Blender prep script and web playground (`tool/3d/`), their tests, the `assets/3d/` pubspec entry, the AGENTS.md "3D Models" section, the `3d-playground` launch configuration, and their entries in this file. The deleted files are in the macOS Trash.
- The record now opens on its type's icon in liquid metal (`TransactionTypeHero`, 128pt): the activity row's icon (`activityKindIconName`) rasterized from its SVG (`SvgShapeImage`) and drawn by the NU7 shader (`LiquidMetal`).
- A Gift Card record keeps the card, scaled to 70% so it no longer spans the page.

## One bottom gap for page buttons (2026-11-15)

Requested directly: one distance between the bottom of the screen and every page's bottom buttons, docked or floating, matching Send, Enter amount, Review Send and Review Donation.

- **Token**: `kMobileFooterGap` (12, in `mobile_sticky_bottom_action.dart`) above the bottom safe-area inset, so 46pt from the edge on a current iPhone. `MobileStickyBottomAction.bottomOffset` uses the padding inset, so above a raised keyboard only the gap remains.
- **Moved onto it**: the floating buttons (Accounts, Endpoints, a Sent record's add-to-contacts, Gift Cards; were 16pt from the edge on iOS), Pay amount and recipient, Swap and Pay review, Donation amount (were 24pt from the edge on iOS through `MobileBottomSafeArea(bottomPadding: 24)`), the secret passphrase gate and backup completion (16 above the inset), Welcome (16), the Keystone signing page (32), the Keystone shield footers (24), the gift claim page (24), and the onboarding education steps (14 or 24).
- **Not moved**: sheets keep the iOS proportional rule; buttons inside content (Receive, status screens, swap status card) stay in the content flow.
- Measured on iOS for every mobile capture scenario with a temporary widget test; the remaining differences were capture-frame insets, not page code.

## Endpoints, Send "(you)", success circle, Home sizes (2026-11-15)

- **Endpoints**: the current endpoint line moved under the tabs, so the tabs no longer shift when it appears on the custom tab. On the custom tab, a failed update shows under the endpoint card with the format error.
- **Send**: the name under the recipient field reads "{name} (you)" (`sendRecipientOwnAccountName`; ko "(나)", zh "（我）") when the address belongs to one of the user's accounts.
- **Success circle**: the green ripple runs 1,950ms (was 650ms). The success haptic (`AppHaptics.sendSuccess`, a full-intensity double pulse on iPhone) fires on Send, Donation, Gift Card, voting and Shield success. Follow-up, requested directly: the Pay success screen now plays it too, once, when the deposit lands while the screen is open (`ref.listen` on the screen's phase); opening an already finished payment plays nothing.
- **Home**: "Recent activity" and the top account name are back to the 16px label (were 18px).

## Review fixes and the Mobile UI Standards (2026-11-15)

From the review of the reusable components another session added (better-interface, better-ui):

- **No fade strip over the engraving**: the page fades paint the window color, so on light-mode records and success screens they drew a flat strip under the nav across the castle engraving once the page scrolled. `MobileScrollEdgeFades.off` now wraps the content in front of that backdrop: the record (`_RecordBackdrop`), `MobileTransactionProgressScreen` (Send, Pay, Donation status) and the voting progress and submitted screens. A render of the scrolled record matches the no-fade render exactly.
- **Gift Card claim fades**: the claim route sits outside `MobilePageViewport`, so both of its mobile states install `MobileScrollEdgeFades(color: window, bottomHeight: AppSpacing.xl)` themselves.
- Tests: the progress screen draws no page fade over the engraving (it failed before the fix); the Gift screen fades its cut edge.
- **AGENTS.md "Mobile UI Standards"**: one section for anyone building mobile UI without a design. It lists the shared components and the rules for spacing, pages, fades, sheets, cards, type, color, controls, motion, haptics and checks, above the existing detailed subsections.
- **3D sweep**: the `3d-playground` launch configuration, a doc comment and the 3D entries in this file are gone, along with stale `assets/3d` copies in `build/`. Nothing in the project references the 3D coin or shield.

## Records, Send amount, Contacts, viewing key (2026-11-15)

Requested directly:

- **Transaction record**: the status moved from above the amount into the detail card as its first row (`mobile_tx_status_status`, label `activityReceiptStatus`), in the card's value weight with its icon and color. The hero amount grew from 40 / 32 to the Send amount's 48 / 38 and still scales down to fit. A Gift Card record shows its card art without the amount (`PaymentLinkGiftCard(showAmount: false)`); the amount and the saved dollar value sit under it like every record. The castle engraving now shows in dark mode too: the asset is a translucent grey, as the send status screen already showed it.
- **Send amount**: up to 48pt of spare height goes to the amount, half above and half below (`_kMobileSendAmountBreathingRoom`); a short phone with the keyboard up keeps the compact layout.
- **Contacts**: the top-right "+" is gone; with contacts, "Add contact" floats at the bottom (`MobileStickyBottomAction`), as Add account does on Accounts. The empty page keeps its centered button.
- **Menu wording**: "Show viewing key" and, for one verb in the menu, "Show secret phrase" (en; zh 显示助记词; ko already 보기).
- **Viewing key (mobile)**: the choice step opens on the account's picture and name; the key step uses Receive's tab bar (QR code and Text with icons), Receive's 292pt QR card, the account name under it, and the text in the same column and height. Copying confirms with a toast ("Viewing key copied", or a failure toast) instead of changing the button. Desktop is unchanged.
- AGENTS.md "Mobile UI Standards" gained rules for list-page add actions, two-way tabs, the account header, hero amounts, transaction records, copy feedback and the "Show" verb.

## Vote config in three sheets, message icon (2026-11-15)

Requested directly:

- **Vote config** (`mobile_voting_config_settings_sheet.dart`): the sheet keeps the intro, a Settings-style "Source ___ Default ›" row (the active source's name: Default, a saved title, or Custom source), the test-round switch and Close. The row opens **Source** (`MobileVotingSourceSheet`): radio cards for the default and every saved source; a tap only marks one and a single primary Update applies it (closing when nothing changed); "Add custom source" is secondary. Adding, and editing through a saved card's pencil, opens **Custom source** (`MobileVotingCustomSourceSheet`): title and URL fields, Save source, and Delete saved source when editing. The three sheets share one mutation mixin (one change at a time, blocked during a vote submission, errors shown in the sheet that made the change); the provider calls are unchanged.
- Removed: the dashed add card and the inline editor; the unused "Sources" and "Delete {name}" strings. New: `votingConfigSource` "Source" (ko 소스, zh 来源).
- Capture scenarios `mobile-voting-source` and `mobile-voting-custom-source`; tests cover the Settings row, marking without applying, and each sheet closing back to the one under it.
- **Message icon**: Send review's Message row shows the expand chevrons (`AppIcons.expand`) instead of the unit-switch arrows, as the record does.

## Swap card room, network search, viewing key balance (2026-11-15)

Requested directly:

- **Swap card**: each half pads its amount 24pt above and below (was Figma's 20; 28 at first, then a step back on request), so the pay and receive values have room; the switch button still sits on the seam.
- **Select network** (Contacts add/edit): a search field over the list (the Contacts search field, hint "Search network"), filtering on name and ticker as desktop does; the list keeps one height capped above the keyboard, and "No networks found" shows when nothing matches. Test: `the network picker filters networks by name or ticker`.
- **Viewing key**: the choice step shows the account's balance under its name, same size in `text.secondary`, masked in privacy mode, and left out for an account whose balance is not loaded (only the active one's is). Tests cover privacy on and off.

## Design-system icons, passphrase header (2026-11-15)

Requested directly:

- **Request icon** from the Vizor Design System (Figma `jhozt3bbbVYms9MkpGJgoI`, node 9391-58635), exported without the frame fill as `assets/icons/request.svg` (`AppIcons.request`, in the Widgetbook icon gallery). It replaces the link on the Request ZEC card.
- **Viewing key icons**: the eye marks viewing keys (the Settings row, "Show viewing key" in the account menus, and now the Full viewing key card, which showed the history clock); the Incoming only card shows the receive arrow (`AppIcons.arrowDownCircle`, was the bottom-left arrow). The cards are shared, so desktop shows them too. Two lock icons from the same Figma page were tried and dropped on request.
- **Secret passphrase (mobile)**: the reveal opens on `MobileAccountHeader`, the viewing key's picture, name and balance, now a shared component in `lib/src/core/widgets/mobile/`. **Optional** (a proposal; the team may decline it): it is there to make the user treat the screen with care, since the words are that wallet's master key. Removing it means dropping that one block in `mobile_seed_phrase_screen.dart` (marked in a comment); no passphrase test depends on it, and the viewing key keeps its header either way.

## One top for the tab roots (2026-11-15)

Requested directly:

- **Home** had a 12pt spacer above its account row and 16pt above its balance card, so its header sat 12pt and its first card 16pt lower than on Swap, Activity and Settings (nav at the safe-area top, first card 12pt under it), and both jumped when switching tabs. Home now uses the same top. Test: `content starts where the other tab roots start theirs`; Activity's test already pins the same offset.

## Instant onboarding, Ledger icon (2026-11-15)

Requested directly:

- **Onboarding transitions**: onboarding steps (create, import, hardware, Wallet Link, Gift Card setup, Welcome and Add account) switch instantly. `MobilePage` gained `animated` (default true); `_mobileOnboardingPage` passes false. The back swipe and the page haptic stay.
- **Ledger icon**: `assets/icons/ledger.svg` is the Vizor Design System Ledger mark (Figma node 8668-27228), so every `AppIcons.ledger` use changes; the voting Ledger panel used the separate `ledgerBrand` logo and now uses it too (`ledger_brand.svg` removed).

## Privacy mask bullets (2026-11-15)

Requested directly:

- **Privacy mode** hides amounts with bullets (U+2022, `••••••`, activity rows `•••`) instead of asterisks. One constant, `kPrivacyMaskCharacter` in `lib/src/core/privacy/privacy_mask.dart`, so every masked amount on mobile and desktop changes; `docs/privacy-mode.md` and the tests that pin the mask moved with it.
- **Tighter serif dots.** Young Serif sets the bullet as wide as a digit (0.53 em around a 0.21 em dot), so the masked balance read as six spaced dots. `serifPrivacyMaskSpan` (same file) draws all but the last bullet at -0.2 em, about half a dot apart, on Home's balance card and the transaction record's hero amount; the gap to the ticker and the plain text are unchanged. Desktop's balance and the smaller serif amounts in the Ironwood migration screens keep the default spacing.

## Flip to hide (2026-11-15)

Requested directly:

- **Flip to hide** (mobile): turning the phone screen-down hides amounts on any wallet page; with amounts hidden, a flip down and back up within 2 seconds shows them. A phone left screen-down only hides, and a slow turn is not a flip. Haptic plus a "Balance hidden" / "Balance shown" toast. A native `screen_facing` event channel (Core Motion on iOS, the gravity sensor on Android, no new package, no permission), `FlipToHideDetector` in Dart, `FlipToHideBalanceHost` in the wallet's root shell route, and a Settings > Hide balance > Flip to hide switch, on by default. Rules in `docs/privacy-mode.md`.

## Onboarding intro update (2026-11-15)

Requested directly, from Figma `New Wallet01` (9394:58807):

- **Intro step** reads "About Zcash" (a mobile key; desktop keeps "The Shielded World") at 36, its card loses the pattern and outline and shows the 72 shield in liquid metal, and the citadel art sits behind the page (`MobileOnboardingCitadelBackground`, the unlock screen's asset). The old card pattern `assets/illustrations/mobile_onboarding_intro_pattern.svg` is no longer referenced.
- **Progress bar** sits in one place on every onboarding step: the intro, method and hardware selection, and Gift Card entry screens dropped their own nav height, offset and track color for the shared `MobileTopNav.steps` geometry.

## Passcode key press (2026-11-15)

Requested directly:

- **Passcode keys** dim to 50% while held, at once on the touch and fading back over 150ms on release, on every numpad (unlock, set and confirm passcode, the keep-awake lock). Keys still fire on finger-down. The help and delete keys behave the same.

## One Shielded label (2026-11-15)

Requested directly:

- **Pool lines** use the activity rows' label everywhere it fits: `PoolBadge` (crimson shield, "Shielded" in secondary text) now takes the 16px regular label on mobile, Send's Recents show it under a bare address instead of crimson text (`MobileRecipientRow.isShielded`), and Pay's estimated ZEC line uses it instead of a grey shield with dark text. The transaction record and Send review already paired the crimson shield with their text and are unchanged.

## Backup reminder left to the team (2026-11-16)

Requested directly:

- **Removed** the mobile create flow that skipped the secret passphrase and the Home "Back up your secret passphrase" sheet. The passphrase step (`MobileSecretPassphraseScreen`), its route, progress stage, strings and Widgetbook previews are back as they were; the sheet, its strings, preview, capture scenario and tests are gone. Home's backup card still reminds while a backup is due.
- **Left a note** for the developers: `TODO(backup-reminder)` in `mobile_home_screen.dart` and "Mobile Backup Reminder (to integrate)" in `AGENTS.md` point to where Tony Yoon's backup reminder should go.

## Tab bar, switch haptics, Receive fit, opaque back swipe (2026-11-16)

Requested directly:

- **Tab bar** is a bit larger: 52 by 72 items (were 44 by 64), so the bar is 60 tall and its pill grows with it. Tab switches play a medium haptic instead of a heavy one (`AppHaptics.tabSwitch`).
- **Segmented controls** tick `AppHaptics.selection()` when a tap changes the choice (Receive's pools, the viewing key's QR code and Text), and Receive's pager ticks it when a swipe changes the pool.
- **Receive** shows its QR at 228 (was 260, about 12% smaller) so the page fits one phone screen; the card, the renew button, the centre badge, the address and the buttons follow it (card 260 wide).
- **Back swipe** on every mobile page slides the page opaque and at full size; it used to fade and shrink under the finger, so the page below showed through. Opening and closing keep their fade and zoom; onboarding steps stay instant.

## Pay's shield, Request ZEC as a page (2026-11-16)

Requested directly:

- **Pay's Shielded label** now draws its shield like Home's activity rows. `PoolBadge` on mobile takes the icon tokens (`icon.brandCrimson`, `icon.muted`) the rows use; it took the text crimson, a lighter pink in dark mode. Every mobile pool line that uses `PoolBadge` (Pay, Send's recents, the request summary) follows. Desktop keeps its colors.
- **Request ZEC** opens as a full page, like Pay, instead of a bottom sheet: `/receive/request` (`MobileReceiveRequestScreen`), opened from Receive and from Home's Receive sheet with the address snapshotted by the caller. The two steps (`RequestAmountComposeStep`, `RequestAmountResultStep`, in `request_amount_steps.dart`) are page bodies with `MobileTopNav.back` and buttons docked at `kMobileFooterGap`. Back on the result returns to compose with the draft intact (system Back too); Back on compose leaves the page. The route falls back to Receive without an address, and leaving needs no sidebar exit policy (a draft request is discarded by leaving, as closing the sheet did).

## Request ZEC: Pay's card, Send's message sheet, centred QR (2026-11-16)

Requested directly:

- **Amount card**: Request ZEC types its amount in Pay's card without the asset picker. The card is now a shared component, `MobileAmountCard` (`core/widgets/mobile/mobile_amount_card.dart`), used by both; The card is 240 tall either way (Pay's height); without the header the amount and its unit switch are centred in it. Pay's card keeps its keys. Request's amount takes Pay's type (`displayLarge`, unit 38 at half strength, muted hint) and Pay's unit-switch icon colour.
- **Message**: the inline memo editor is gone. A line under the card reads "Add a message" (or shows the saved message with the expand icon) and opens Send's message sheet, now shared as `showMobileMemoSheet` / `MobileMemoSheet` (`core/widgets/mobile/mobile_memo_sheet.dart`). Send opens it unchanged; Request passes its title, the "Anyone you send the link to can read this" hint, a "Clear" label and `stripUnsupportedZip321MemoText`, so unsupported characters still leave the field as they are typed.
- **QR step**: the amount is in the Home balance card's serif (now shared as `kMobileSerifAmountStyle` / `kMobileSerifTickerStyle`), the Shielded badge under it, and the QR, amount and badge sit centred between the header and the buttons (scrolling only when there is not room).
- Tests: the request keyboard test now checks the docked Create button on five phone and keyboard setups and the message sheet path (saving, the 512-byte limit, long messages); Receive's tests cover adding, clearing and stripping a message in the sheet.

