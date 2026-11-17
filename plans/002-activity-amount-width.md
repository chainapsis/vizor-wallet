# 002 — Stop cutting off amounts in mobile activity rows

- **Status**: APPLIED (uncommitted, 2026-11-12)
- **Commit**: 0604ac893
- **Severity**: HIGH
- **Category**: UI craft (layout)
- **Estimated scope**: 1 file, ~6 lines
- **Change type**: Value change, behind the file's existing form-factor constant pattern. Desktop is unchanged.

## Problem

On mobile Home and the Activity tab, received amounts are cut off with an ellipsis: a row shows `+0.0006849 Z…` while the left side of the row has free space. A wallet must never clip an amount or its unit.

The amount column has a hard cap of 128 pt, which fits the desktop 13–14 pt label but not the mobile 16 pt `labelLarge`:

```dart
// lib/src/features/activity/widgets/activity_feed.dart:1158 — current
return ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 128),
  child: Column(
```

The row is `Row[Expanded(icon + title), SizedBox(10), _ActivityRowAmount]` (`activity_feed.dart:1009-1025`), so the title side already shrinks and ellipsizes when the amount needs more room.

## Target

On mobile the amount column may grow to 200 pt; on desktop it stays 128 pt.

```dart
/// Amount column cap. Desktop keeps 128 px; mobile's 16px label needs room
/// for a full 8-decimal amount plus the ticker without an ellipsis.
const _activityAmountMaxWidth = kAppFormFactor == AppFormFactor.mobile
    ? 200.0
    : 128.0;
```

Why 200: the mobile content width is about 361 pt. The title side needs about 130 pt (40 pt icon + gap + "Received"/"Sent"), and the gap is 10 pt, which leaves about 220 pt. 200 pt fits strings like `+0.00068491 ZEC` and `-1,234.5678 ZEC` at 16 pt w600 while keeping the title readable.

## Repo conventions to follow

- This file already switches sizes by form factor with top-level consts, e.g. `activity_feed.dart:31-38`:

  ```dart
  const _activitySupportingStyle = kAppFormFactor == AppFormFactor.mobile
      ? AppTypography.labelLarge
      : AppTypography.labelSmall;
  ```

  `kAppFormFactor` is a compile-time const, so the unused branch is tree-shaken. `app_form_factor.dart` is already imported (line 7).

## Steps

1. In `lib/src/features/activity/widgets/activity_feed.dart`, directly after `_activityRowSubtitleIconSize` (ends around line 38), add:

   ```dart

   /// Amount column cap. Desktop keeps 128 px; mobile's 16px label needs room
   /// for a full 8-decimal amount plus the ticker without an ellipsis.
   const _activityAmountMaxWidth = kAppFormFactor == AppFormFactor.mobile
       ? 200.0
       : 128.0;
   ```

2. In `_ActivityRowAmount.build` (around line 1158), change only the constraint:

   ```dart
   return ConstrainedBox(
     constraints: const BoxConstraints(maxWidth: _activityAmountMaxWidth),
     child: Column(
   ```

## Boundaries

- Do NOT change `TextOverflow.ellipsis` / `maxLines` on the amount text (`activity_feed.dart:1206-1207`). Truly extreme values should still ellipsize instead of overflowing.
- Do NOT change the row structure, the 10 px gap, the title widgets or the desktop value.
- Do NOT touch the receipt / detail screens.
- If line 1158 no longer shows `maxWidth: 128` (drift since commit 0604ac893), STOP and report.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test test/activity_feed_row_test.dart test/features/activity/` → all pass.
  - `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/home/mobile_home_screen_test.dart` → all pass.
- **Feel check** (iOS Simulator, mobile form factor, wallet with activity):
  - Home › Recent activity: `+0.0006849 ZEC` shows in full, with the `ZEC` ticker.
  - Activity tab: the same rows show in full; swap rows with sub-rows still align right.
  - Turn on the largest text size (Settings › Accessibility › Display & Text Size › Larger Text): the title ellipsizes before the amount does. No yellow-black overflow stripes.
  - Desktop build (`fvm flutter run -d macos`): activity rows look exactly as before.
- **Done when**: no realistic amount (up to 8 decimals, up to 6 integer digits with grouping) is ellipsized on a 402 pt-wide iPhone at default text size.
