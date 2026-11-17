# 007 — Make the 24h price badge on the balance card readable

- **Status**: APPLIED (uncommitted, 2026-11-12)
- **Commit**: 0604ac893
- **Severity**: HIGH
- **Category**: UI craft (color contrast)
- **Estimated scope**: 3 source files + 1 test file, ~20 lines
- **Change type**: Small addition that copies an existing token pattern (`text.homeCard`). All values are existing primitives; no new colors.
- **Ship together with 008.** Plan 008 darkens `text.positiveStrong` in light mode to `#007F49`. On this dark card that drops the "price up" badge from 4.00:1 to **2.55:1**, on both mobile and desktop. This plan moves both badges off the page tokens, which removes that regression.

## Problem

The Home balance card is dark in both themes (light mode `#2E3232`, dark mode `#1B1F1F`; `background.homeCard`), on mobile and on desktop. Its text already uses a theme-invariant token, `text.homeCard`. But the 24h price badge uses the ordinary page tokens, which are tuned for the page background, not for this dark card. Mobile:

```dart
// lib/src/features/home/screens/mobile/mobile_home_screen.dart:1906-1912 — current
final priceChangeColor = roundedPriceChangePct == null
    ? null
    : roundedPriceChangePct > 0
    ? colors.text.positiveStrong
    : roundedPriceChangePct < 0
    ? colors.text.destructive
    : cardText;
```

Desktop has the same badge on the same `background.homeCard`:

```dart
// lib/src/features/home/screens/home_screen.dart:1661-1667 — current
final priceChangeColor = roundedPriceChangePct == null
    ? null
    : roundedPriceChangePct > 0
    ? colors.text.positiveStrong
    : roundedPriceChangePct < 0
    ? colors.text.destructive
    : colors.text.homeCard;
```

Measured WCAG 2.x contrast (the badge is 14 pt regular, so it needs 4.5:1):

| Mode | Badge | Color | On card | Ratio |
|---|---|---|---|---|
| Light | price down | `text.destructive` = `PlumPrimitives.p300Light` `#AB40BF` | `#2E3232` | **2.61:1** |
| Light | price up | `text.positiveStrong` = `GreenPrimitives.p500Light` `#00A460` (after plan 008: `p600Light` `#007F49`) | `#2E3232` | **4.00:1** (after 008: **2.55:1**) |
| Dark | price down | `text.destructive` = `PlumPrimitives.p500Dark` `#B85BC8` | `#1B1F1F` | **4.25:1** |
| Dark | price up | `text.positiveStrong` = `GreenPrimitives.p400Dark` `#3BD38B` | `#1B1F1F` | passes |

## Target

Two new theme-invariant text tokens for the card, next to `homeCard`, built only from existing primitives:

| Token | Light set | Dark set | Ratio on card (light / dark) |
|---|---|---|---|
| `homeCardPositive` | `GreenPrimitives.p300Light` (`#3BD38B`) | `GreenPrimitives.p400Dark` (`#3BD38B`) | 6.72:1 / passes (same color as today in dark) |
| `homeCardNegative` | `PlumPrimitives.p100Light` (`#CD8CD9`) | `PlumPrimitives.p600Dark` (`#C06ECE`) | 5.16:1 / 5.04:1 |

The light set uses light-face primitives with the same hex as the dark-face ones (`GreenPrimitives.p300Light == p400Dark`, `PlumPrimitives.p100Light == p700Dark`). That keeps each set inside its own face, the convention noted in `app_surface_colors.dart:51-52`.

## Repo conventions to follow

- `text.homeCard` is the existing exception token for this card (`app_text_colors.dart:21`, `:36`, `:51`, `:66`, `:84`). Add the new tokens the same way: doc bullet, constructor parameter, field, and one entry in each of `dark` and `light`.
- `AppTextColors` is only constructed in its own file (confirmed with `grep -rln 'AppTextColors(' lib test`), so no other call sites need updating.

## Steps

1. In `lib/src/core/theme/colors/app_text_colors.dart`:
   - After the doc line 21 (`/// * [homeCard] — ...`), add:

     ```dart
     /// * [homeCardPositive] / [homeCardNegative] — 24h price change on the
     ///   home balance card. Theme-invariant, like [homeCard].
     ```

   - After `required this.homeCard,` (line 36), add:

     ```dart
         required this.homeCardPositive,
         required this.homeCardNegative,
     ```

   - After `final Color homeCard;` (line 51), add:

     ```dart
       final Color homeCardPositive;
       final Color homeCardNegative;
     ```

   - In `static const dark`, after `homeCard: Primitives.p800Dark,` (line 66), add:

     ```dart
         homeCardPositive: GreenPrimitives.p400Dark,
         homeCardNegative: PlumPrimitives.p600Dark,
     ```

   - In `static const light`, after `homeCard: Primitives.p0Light,` (line 84), add:

     ```dart
         homeCardPositive: GreenPrimitives.p300Light,
         homeCardNegative: PlumPrimitives.p100Light,
     ```

2. In `lib/src/features/home/screens/mobile/mobile_home_screen.dart:1906-1912`, change only the two token names:

   ```dart
   final priceChangeColor = roundedPriceChangePct == null
       ? null
       : roundedPriceChangePct > 0
       ? colors.text.homeCardPositive
       : roundedPriceChangePct < 0
       ? colors.text.homeCardNegative
       : cardText;
   ```

3. In `lib/src/features/home/screens/home_screen.dart:1661-1667` (desktop), make the same two token swaps:

   ```dart
   final priceChangeColor = roundedPriceChangePct == null
       ? null
       : roundedPriceChangePct > 0
       ? colors.text.homeCardPositive
       : roundedPriceChangePct < 0
       ? colors.text.homeCardNegative
       : colors.text.homeCard;
   ```

4. In `test/features/home/home_desktop_screen_test.dart`, update the two expectations that name the old tokens:
   - lines 284-287: `AppThemeData.light.colors.text.positiveStrong` → `AppThemeData.light.colors.text.homeCardPositive`
   - line 312: `AppThemeData.light.colors.text.destructive` → `AppThemeData.light.colors.text.homeCardNegative`

## Boundaries

- Do NOT change `positiveStrong` or `destructive` here (plan 008 handles page-level tokens).
- Do NOT change the badge text, size, weight or the neutral (`0.00%`) color.
- Do NOT add new hex values; use only the primitives listed above.
- If the excerpt in step 2 does not match (drift since commit 0604ac893), STOP and report.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test test/core/theme/ test/features/home/home_desktop_screen_test.dart` → all pass.
  - `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/home/mobile_home_screen_test.dart` → all pass (the test at line 1507 checks only the text `+ 13.12% (24h)`).
- **Visual check** (iOS Simulator, mobile form factor, light and dark mode):
  - When ZEC is down over 24h, the `- x.xx% (24h)` badge reads clearly as light plum on the dark card in both modes.
  - When ZEC is up, the `+ x.xx% (24h)` badge is a bright green in light mode (it was a darker green before) and unchanged in dark mode.
  - Optional: run a contrast checker on a screenshot. Each badge should be at least 4.5:1 against the card.
- **Done when**: both badges are at least 4.5:1 on the card in both themes and tests pass.
