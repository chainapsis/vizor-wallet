# 001 — Make iOS Reduce Motion reach the app's reduced-motion checks

- **Status**: APPLIED (uncommitted, 2026-11-12)
- **Commit**: 0604ac893
- **Severity**: HIGH
- **Category**: Accessibility
- **Estimated scope**: 1 new file (~45 lines), 1 new test file, 2-line edit in `lib/app.dart`
- **Change type**: Small addition. No existing logic changes. Every existing reduced-motion check stays exactly as written.

## Problem

All 86 reduced-motion checks in `lib/` read `MediaQuery.disableAnimations` (or `MediaQuery.disableAnimationsOf` / `maybeDisableAnimationsOf`). Two examples:

```dart
// lib/src/core/layout/mobile/app_mobile_tab_bar.dart:74 — current
final motion = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
```

```dart
// lib/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart:131 — current
final reduce = MediaQuery.disableAnimationsOf(context);
```

On iOS, Flutter 3.47.8 never sets `disableAnimations`. iOS Settings › Accessibility › Motion › Reduce Motion is reported only as `AccessibilityFeatures.reduceMotion`:

- SDK: `engine/src/flutter/shell/platform/darwin/ios/framework/Source/AccessibilityFeatures.swift:45-46` inserts only `.reduceMotion`.
- SDK docs: `packages/flutter/lib/src/widgets/media_query.dart:668-669` — "On iOS, reduced motion is exposed separately via [dart:ui.AccessibilityFeatures.reduceMotion] and does not set this flag."
- `MediaQueryData.fromView` does not copy `reduceMotion` into `MediaQueryData` (`media_query.dart:316-330`), so a change of that flag alone does not even rebuild `MediaQuery` dependents.

Result: on iPhone, every reduced-motion branch in the app is dead code. The welcome video, liquid-metal shader, shield particles, carousel, shimmers and tab-bar spring all keep moving for users who asked the OS for less motion.

## Target

One widget at the app root folds the platform flag into `MediaQuery.disableAnimations` for the whole app. The existing 86 checks then work on iOS with no edits.

- `disableAnimations` becomes `media.disableAnimations || platformDispatcher.accessibilityFeatures.reduceMotion`.
- The widget always returns a `MediaQuery` (never switches between `child` and `MediaQuery(child)`), so toggling the setting never remounts the app subtree.
- It listens to `WidgetsBindingObserver.didChangeAccessibilityFeatures` because `MediaQuery` itself does not rebuild when only `reduceMotion` changes.

Out of scope: `AnimationController`'s automatic speed-up reads `SemanticsBinding.disableAnimations`, not `MediaQuery`. It stays as it is.

## Repo conventions to follow

- Shared motion code lives in `lib/src/core/motion/` (today: `onboarding_motion.dart`). Put the new widget there.
- `WidgetsBindingObserver` usage follows `lib/src/core/layout/mobile/mobile_modal_corners.dart:28-50`: `with WidgetsBindingObserver`, `WidgetsBinding.instance.addObserver(this)` in `initState`, `removeObserver` in `dispose`.
- `MediaQuery` overrides follow `lib/src/core/layout/mobile/mobile_adaptive_frame.dart:251`: `MediaQuery(data: <copied MediaQueryData>, child: ...)`.
- Tests that fake accessibility flags already exist, e.g. `test/core/widgets/sync_keep_awake_privacy_lock_host_test.dart` uses `FakeAccessibilityFeatures`.

## Steps

1. Create `lib/src/core/motion/platform_reduce_motion_scope.dart` with exactly this content:

   ```dart
   import 'package:flutter/widgets.dart';

   /// Folds the platform "Reduce Motion" flag into
   /// [MediaQueryData.disableAnimations] for everything below it.
   ///
   /// iOS reports Settings › Accessibility › Motion › Reduce Motion only as
   /// `AccessibilityFeatures.reduceMotion`; Flutter leaves
   /// `MediaQuery.disableAnimations` false there. Every reduced-motion gate
   /// in this app reads `disableAnimations`, so the bridge lives once, at the
   /// app root, instead of in each gate.
   ///
   /// `MediaQuery` does not rebuild when only `reduceMotion` changes, so the
   /// scope listens to [WidgetsBindingObserver.didChangeAccessibilityFeatures]
   /// itself. It always returns a `MediaQuery` so toggling the setting never
   /// remounts the subtree.
   class PlatformReduceMotionScope extends StatefulWidget {
     const PlatformReduceMotionScope({required this.child, super.key});

     final Widget child;

     @override
     State<PlatformReduceMotionScope> createState() =>
         _PlatformReduceMotionScopeState();
   }

   class _PlatformReduceMotionScopeState extends State<PlatformReduceMotionScope>
       with WidgetsBindingObserver {
     @override
     void initState() {
       super.initState();
       WidgetsBinding.instance.addObserver(this);
     }

     @override
     void dispose() {
       WidgetsBinding.instance.removeObserver(this);
       super.dispose();
     }

     @override
     void didChangeAccessibilityFeatures() => setState(() {});

     @override
     Widget build(BuildContext context) {
       final media = MediaQuery.of(context);
       final reduceMotion = View.of(
         context,
       ).platformDispatcher.accessibilityFeatures.reduceMotion;
       return MediaQuery(
         data: media.copyWith(
           disableAnimations: media.disableAnimations || reduceMotion,
         ),
         child: widget.child,
       );
     }
   }
   ```

2. In `lib/app.dart`, add the import next to the other `src/core/...` imports:

   ```dart
   import 'src/core/motion/platform_reduce_motion_scope.dart';
   ```

3. In `lib/app.dart`, at the end of the `MaterialApp.router` `builder:` (currently around lines 1963-1971), wrap the returned widget. Current:

   ```dart
   return kAppFormFactor == AppFormFactor.mobile
       ? MobileWindowPolicyScope(
           policy: MobileWindowPolicy.resolve(MediaQuery.of(context)),
           child: localized,
         )
       : localized;
   ```

   Target:

   ```dart
   return PlatformReduceMotionScope(
     child: kAppFormFactor == AppFormFactor.mobile
         ? MobileWindowPolicyScope(
             policy: MobileWindowPolicy.resolve(MediaQuery.of(context)),
             child: localized,
           )
         : localized,
   );
   ```

4. Add `test/core/motion/platform_reduce_motion_scope_test.dart` with three cases. Use `tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(...)` and `addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue)`. Read the flag below the scope with a `Builder` that captures `MediaQuery.disableAnimationsOf(context)`.
   - `reduceMotion: true` → `disableAnimations` is `true`.
   - Default features → `disableAnimations` is `false`.
   - Start with default features, pump, then set `reduceMotion: true` and call `tester.binding.handleAccessibilityFeaturesChanged()`, pump → `disableAnimations` is `true`. This proves the observer path.

   No `@Tags(['mobile'])` is needed; the widget is form-factor independent.

## Boundaries

- Do NOT edit any of the 86 existing reduced-motion checks.
- Do NOT change `AppThemeHost`, `MobileWindowPolicyScope` or any other host in the builder chain.
- Do NOT add dependencies.
- If the builder's `return` statement no longer matches the excerpt in step 3 (drift since commit 0604ac893), STOP and report instead of improvising.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test test/core/motion/platform_reduce_motion_scope_test.dart` → all pass.
  - `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/core/layout/mobile/mobile_shell_components_test.dart test/features/home/mobile_home_screen_test.dart` → all pass, unchanged.
  - `fvm flutter test` (default lane) → no new failures.
- **Feel check** (iOS Simulator, `fvm flutter run --dart-define=VIZOR_FORM_FACTOR=mobile`):
  - In the simulator, open Settings › Accessibility › Motion and turn Reduce Motion on, then return to Vizor without restarting it.
  - Switch tabs: the highlight pill and icon tint snap instantly, with no spring overshoot and no icon pop.
  - Sign out to the welcome screen (or use a fresh install): the background video is paused.
  - Turn Reduce Motion off again: the tab pill slides again. No screen reloads or loses state when toggling.
- **Done when**: with iOS Reduce Motion on, `MediaQuery.disableAnimationsOf(context)` is `true` everywhere below the app root, and all tests pass.
