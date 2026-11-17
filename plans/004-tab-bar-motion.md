# 004 — Calm the tab bar icon motion

- **Status**: APPLIED (uncommitted, 2026-11-12)
- **Commit**: 0604ac893
- **Severity**: HIGH
- **Category**: Purpose & frequency, Easing & duration
- **Estimated scope**: 1 file, value changes on ~6 lines plus one doc comment line
- **Change type**: Values only. Widget structure, controllers and the sliding pill are unchanged.

## Problem

The tab bar is the most-tapped control in the app (tens of times a day). Every tap stacks three bouncy effects on the icon:

1. **Press**: the icon scales to 0.9 (outside the 0.95–0.98 press range), then releases with an overshooting `Curves.easeOutBack`.
2. **Pop**: when an item becomes active, it pops 1.0 → 1.12 → 1.0 over 250 ms. The settle leg uses `Curves.easeIn` while the controller runs forward, so it starts slow and lands at full speed — a hard stop on every tab switch.
3. **Pill**: the shared highlight pill overshoots by about 5% (`_selectCurve`). This one is a documented, tuned design decision (`app_mobile_tab_bar.dart:56-60`) and stays as it is.

```dart
// lib/src/core/layout/mobile/app_mobile_tab_bar.dart:184-202 — current
late final AnimationController _pop = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 250),
);
late final Animation<double> _popScale = TweenSequence<double>([
  TweenSequenceItem(
    tween: Tween(
      begin: 1.0,
      end: 1.12,
    ).chain(CurveTween(curve: Curves.easeOut)),
    weight: 45,
  ),
  TweenSequenceItem(
    tween: Tween(
      begin: 1.12,
      end: 1.0,
    ).chain(CurveTween(curve: Curves.easeIn)),
    weight: 55,
  ),
]).animate(_pop);
```

```dart
// lib/src/core/layout/mobile/app_mobile_tab_bar.dart:251-254 — current
child: AnimatedScale(
  scale: _pressed ? 0.9 : 1.0,
  duration: Duration(milliseconds: _pressed ? 90 : 180),
  curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
```

Frequency rule: motion seen tens of times a day must be removed or drastically reduced. The pill already shows which tab is active; the icon only needs light press feedback.

## Target

- **Pop**: peak 1.12 → **1.04**, total duration 250 ms → **200 ms**, settle leg `Curves.easeIn` → **`Curves.easeOutCubic`** (lands softly instead of hitting rest at full speed).
- **Press**: scale 0.9 → **0.96**; press-in 90 ms → **100 ms** with `Curves.easeOut`; release 180 ms → **160 ms** with **`Curves.easeOut`** (no overshoot). Press feedback range: 0.95–0.98 scale, 100–160 ms, ease-out.
- **Pill**: unchanged.
- Reduced motion: unchanged. The existing `widget.motion` gates still skip the pop and the press scale.

Alternative for the designers (not part of this plan): delete the pop entirely and keep only press feedback plus the pill. That removes `_pop`, `_popScale`, the `ScaleTransition` and `SingleTickerProviderStateMixin`, so it is a structural change and needs design sign-off.

## Repo conventions to follow

- Press feedback elsewhere in the app already uses these values: `lib/src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart:325-328` — `AnimatedScale(scale: _pressed ? 0.96 : 1, duration: const Duration(milliseconds: 90), curve: Curves.easeOut, ...)`.
- The code uses Flutter's built-in `Curves.*` for these small effects; keep doing that (no new curve tokens in this plan).

## Steps

1. In `lib/src/core/layout/mobile/app_mobile_tab_bar.dart`, in `_TabBarItemState`:
   - line 186: `duration: const Duration(milliseconds: 250),` → `duration: const Duration(milliseconds: 200),`
   - line 192: `end: 1.12,` → `end: 1.04,`
   - line 198: `begin: 1.12,` → `begin: 1.04,`
   - line 200: `).chain(CurveTween(curve: Curves.easeIn)),` → `).chain(CurveTween(curve: Curves.easeOutCubic)),`
2. In the same file, in `_TabBarItemState.build`:
   - line 252: `scale: _pressed ? 0.9 : 1.0,` → `scale: _pressed ? 0.96 : 1.0,`
   - line 253: `duration: Duration(milliseconds: _pressed ? 90 : 180),` → `duration: Duration(milliseconds: _pressed ? 100 : 160),`
   - line 254: `curve: _pressed ? Curves.easeOut : Curves.easeOutBack,` → `curve: Curves.easeOut,`
3. Update the doc comment on `_pop` (lines 182-183) so it no longer says "bounce". Current:

   ```dart
   /// One-shot pop when this item becomes the active one — a small
   /// bounce timed to land with the arriving pill.
   ```

   Target:

   ```dart
   /// One-shot, subtle lift when this item becomes the active one, timed
   /// to land with the arriving pill.
   ```

## Boundaries

- Do NOT change `_selectCurve`, `selectDuration`, the pill (`AnimatedAlign`), the icon tint tween, haptics or the blur.
- Do NOT remove the pop controller or change the widget structure (see the alternative above for that).
- Do NOT change reduced-motion handling.
- If any line above does not match (drift since commit 0604ac893), STOP and report.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/core/layout/mobile/mobile_shell_components_test.dart test/core/navigation/mobile_routes_test.dart` → all pass.
- **Feel check** (iOS Simulator or device, mobile form factor):
  - Tap each tab several times quickly: the icon dips slightly on touch-down and returns without bouncing past full size.
  - Switch tabs: the new icon gives a barely visible lift that settles softly, landing together with the pill. The pill still has its small overshoot.
  - In DevTools, set "Slow animations" (Flutter Inspector › Slow Animations, 5×): confirm no leg of the icon motion speeds up into the end position.
- **Done when**: the values above are in place, tests pass, and the icon no longer visibly bounces on a plain tap.
