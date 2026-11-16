# 005 — Give mobile list rows feedback on touch-down

- **Status**: TODO — **needs dev + design sign-off before execution**
- **Commit**: 0604ac893
- **Severity**: HIGH
- **Category**: Physicality (press feedback)
- **Estimated scope**: 1 file, ~40 added lines
- **Change type**: Small addition. Adds a private `StatefulWidget` to `mobile_list_row.dart` that copies an existing pattern in the app (`_AccountSheetButtonShell`). Tap behaviour and callbacks are unchanged. Sign-off is needed because it adds a visible pressed state to 18 rows (Settings, accounts and others).

## Problem

`MobileListRow` — the row used in Settings (14 rows), the accounts screens and other mobile lists — gives no feedback when touched. Nothing changes until the finger lifts and the next screen opens:

```dart
// lib/src/core/widgets/mobile/mobile_list_row.dart:152-157 — current
if (onTap == null || !enabled) return row;
return GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: row,
);
```

Feedback must start on touch-down so the user knows the touch registered. iOS list rows do this with a background highlight, not a scale; a scale reads oddly on a full-width row.

## Target

On touch-down the row gets a subtle background tint; on release or cancel the tint fades out.

- Tint color: `colors.state.hoverOpacity` (light: `Primitives.p900Alpha5Light`, 5% near-black; dark: `Primitives.p0Alpha15Dark`). The same token already tints activity rows on hover (`activity_feed.dart:1004`).
- Shape: `BorderRadius.circular(AppRadii.small)` (12), the same radius activity rows use (`activity_feed.dart:1007`).
- Timing: tint in over 100 ms, out over 160 ms, `Curves.easeOut` both ways (press feedback range 100–160 ms, ease-out).
- Reduced motion: no change needed. A color fade is allowed under reduced motion.

## Repo conventions to follow

Copy the press-state pattern from `lib/src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart:294-330` (`_AccountSheetButtonShell`): a private `StatefulWidget` with `var _pressed = false;` and a `GestureDetector` whose `onTapDown` / `onTapCancel` / `onTapUp` set `_pressed`, and whose `onTap` calls the callback. Only the visual differs: a tint instead of `AnimatedScale`.

## Steps

1. In `lib/src/core/widgets/mobile/mobile_list_row.dart`, replace the final `return GestureDetector(...)` (lines 153-157) with:

   ```dart
   return _MobileListRowPressShell(onTap: onTap!, child: row);
   ```

   Keep line 152 (`if (onTap == null || !enabled) return row;`) as it is.

2. At the end of the same file, add:

   ```dart
   /// Touch-down highlight for tappable rows — the same press-state shape
   /// as the accounts sheet buttons, with an iOS-style row tint instead of
   /// a scale.
   class _MobileListRowPressShell extends StatefulWidget {
     const _MobileListRowPressShell({required this.onTap, required this.child});

     final VoidCallback onTap;
     final Widget child;

     @override
     State<_MobileListRowPressShell> createState() =>
         _MobileListRowPressShellState();
   }

   class _MobileListRowPressShellState extends State<_MobileListRowPressShell> {
     var _pressed = false;

     @override
     Widget build(BuildContext context) {
       final colors = context.colors;
       return GestureDetector(
         behavior: HitTestBehavior.opaque,
         onTapDown: (_) => setState(() => _pressed = true),
         onTapCancel: () => setState(() => _pressed = false),
         onTapUp: (_) => setState(() => _pressed = false),
         onTap: widget.onTap,
         child: AnimatedContainer(
           duration: Duration(milliseconds: _pressed ? 100 : 160),
           curve: Curves.easeOut,
           decoration: BoxDecoration(
             color: _pressed
                 ? colors.state.hoverOpacity
                 : colors.state.hoverOpacity.withValues(alpha: 0),
             borderRadius: BorderRadius.circular(AppRadii.small),
           ),
           child: widget.child,
         ),
       );
     }
   }
   ```

   `AppRadii` and `context.colors` come from `../../theme/app_theme.dart`, which the file already imports (it exports `app_radii.dart` and `colors/app_colors.dart`). `AnimatedContainer`, `BoxDecoration`, `Curves` come from `package:flutter/widgets.dart`, also already imported.

   Fading to the same color at alpha 0 (instead of a fully transparent black) keeps the tint from turning gray mid-fade.

## Boundaries

- Do NOT change `MobileListRow`'s public constructor, its layout, its text colors or the disabled path.
- Do NOT apply this to `AppTappable`, the top-nav back button or Home tiles in this plan. They need their own decision (scale for icon buttons, tint for rows).
- Do NOT add haptics.
- If lines 152-157 do not match (drift since commit 0604ac893), STOP and report.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/core/widgets/mobile/mobile_commons_test.dart test/features/settings/mobile_settings_screen_test.dart` → all pass. If a test finds the row's `GestureDetector` by type, update the finder to `find.byType(MobileListRow)` taps — tapping behaviour is the same.
- **Feel check** (iOS Simulator and a real iPhone, light and dark mode):
  - Settings tab: press and hold a row. A soft rounded tint appears under it within one or two frames; lift and it fades out while the next screen opens.
  - Start a press on a row, then scroll the list: the tint clears (tap cancelled) and the row does not open.
  - Note: like Flutter's own `InkWell`, a very quick tap inside a scroll view can open the next screen before the tint shows. That is expected.
  - Check the tint looks right against the card's 16 pt padding and 20 pt corners. If design prefers the tint to run to the card edges, stop and ask; that needs a different structure.
- **Done when**: every tappable `MobileListRow` shows a touch-down tint, with no change to what tapping does.
