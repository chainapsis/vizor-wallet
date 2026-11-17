# 008 — Fix four text color tokens that fail contrast

- **Status**: APPLIED (uncommitted, 2026-11-12)
- **Commit**: 0604ac893
- **Severity**: HIGH (positiveStrong) / MEDIUM (the other three)
- **Category**: UI craft (color contrast)
- **Estimated scope**: 1 file, 4 one-line value changes
- **Change type**: Values only. Each token points at a different existing primitive. No new colors, no call-site changes. Each step can be shipped or reverted on its own.

## Problem

Four text tokens in `lib/src/core/theme/colors/app_text_colors.dart` fall below WCAG 2.x AA for normal-size text (4.5:1). All are used at 14–16 pt regular or semibold, so the 3:1 large-text rule does not apply. Backgrounds: light window `#F7F7F7`; dark window `#0F0F0F`; dark card (`background.base` / `surface.card`) `#232828`.

| # | Token (mode) | Line | Current | Worst case | Ratio |
|---|---|---|---|---|---|
| A | `positiveStrong` (light) | 79 | `GreenPrimitives.p500Light` `#00A460` | on window | **3.03:1** |
| B | `warning` (light) | 78 | `GoldPrimitives.p400Light` `#B0844F` | on window | **3.13:1** |
| C | `brandCrimson` (dark) | 65 | `CrimsonPrimitives.p400Dark` `#A83861` | on card | **2.42:1** (3.11:1 on window) |
| D | `destructive` (dark) | 62 | `PlumPrimitives.p500Dark` `#B85BC8` | on card | **3.82:1** |

Where they show up on mobile:

- **A**: received amounts in every activity row on Home and the Activity tab (`activity_row_mapper.dart:150-153`). 7 mobile uses, plus desktop.
- **B**: warning copy, e.g. Home (`mobile_home_screen.dart:1491`), accounts (`mobile_accounts_screen.dart:840`), swap status, migration review. 5 mobile uses.
- **C**: Tor status labels in Settings (`mobile_tor_control.dart:170`, `:229-262`). 12 mobile uses.
- **D**: error and destructive text inside cards in dark mode. 63 mobile uses.

## Target

| # | Token (mode) | New value | New worst-case ratio |
|---|---|---|---|
| A | `positiveStrong` (light) | `GreenPrimitives.p600Light` `#007F49` | 4.74:1 on window |
| B | `warning` (light) | `GoldPrimitives.p600Light` `#6E4E33` | 7.00:1 on window |
| C | `brandCrimson` (dark) | `CrimsonPrimitives.p700Dark` `#CF92A8` | 5.93:1 on card |
| D | `destructive` (dark) | `PlumPrimitives.p600Dark` `#C06ECE` | 4.53:1 on card |

Notes for design review:

- **B**: `GoldPrimitives.p500Light` (`#956B45`) reaches only 4.39:1, so the nearest passing gold is the darker, browner `p600Light`.
- **A** and **D** are one step darker (light) / lighter (dark) on their existing ramps, so the hue stays the same.
- Light `brandCrimson`, light `destructive`, dark `positiveStrong` and dark `warning` already pass and do not change.

## Repo conventions to follow

- Token sets reference primitives by name, one per line, e.g. `app_text_colors.dart:60-66` and `:78-84`. Keep that form; never inline hex.
- `text.success` (lines 64 and 82) uses the same gold as `warning` but has no mobile uses. Leave it unchanged.

## Steps

1. **A** — line 79, in `static const light`:
   `positiveStrong: GreenPrimitives.p500Light,` → `positiveStrong: GreenPrimitives.p600Light,`
2. **B** — line 78, in `static const light`:
   `warning: GoldPrimitives.p400Light,` → `warning: GoldPrimitives.p600Light,`
3. **C** — line 65, in `static const dark`:
   `brandCrimson: CrimsonPrimitives.p400Dark,` → `brandCrimson: CrimsonPrimitives.p700Dark,`
4. **D** — line 62, in `static const dark`:
   `destructive: PlumPrimitives.p500Dark,` → `destructive: PlumPrimitives.p600Dark,`

## Boundaries

- Do NOT change icon tokens (`app_icon_colors.dart`): `icon.success`, `icon.brandCrimson` and the others keep their values. `test/core/theme/design_tokens_test.dart:287-290` asserts some of them.
- Do NOT change background or surface tokens, primitives, or any call site.
- Do NOT touch the hard-coded `Color(0xFF00A460)` values in `mobile_transaction_progress_screen.dart:15` and `mobile_ironwood_migration_step_options.dart:103`. Those are fills, not text, and their tests assert them.
- Do NOT change `text.muted` here. It also fails (3.41:1 light), but no existing primitive fits between `p500` and `p600`, so it needs a design decision.
- If a line does not match the "current" value above (drift since commit 0604ac893), STOP and report.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test test/core/theme/ test/activity_feed_row_test.dart test/core/widgets/review_components_test.dart test/features/settings/settings_screen_test.dart test/features/voting/mobile_voting_design_test.dart test/features/activity/received_receipt_view_test.dart` → all pass (these compare against the token by name, so they follow the new values).
  - `fvm flutter test` (default lane) and `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile` → no new failures.
- **Visual check** (iOS Simulator, mobile form factor):
  - Light mode, Home: received amounts (`+0.006444 ZEC`) are a deeper green and easy to read.
  - Light mode: a warning line (e.g. the Home private-status coverage notice, if shown) reads as dark gold-brown.
  - Dark mode, Settings › Network privacy (Tor): the crimson status label is clearly readable on its card.
  - Dark mode: an error message inside a card (e.g. a failed send detail) is readable.
  - Desktop (`fvm flutter run -d macos`): these tokens are shared, so check the same four places look acceptable there too.
- **Done when**: each of the four tokens reaches at least 4.5:1 on its worst-case background, and all tests pass.
