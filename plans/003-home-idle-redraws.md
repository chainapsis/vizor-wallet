# 003 — Cut needless redraws on the Home tab

- **Status**: TODO
- **Commit**: 0604ac893
- **Severity**: HIGH
- **Category**: Performance
- **Estimated scope**: 3 files, ~15 lines
- **Change type**: Wrapper and rebuild-scope changes only. What the user sees is unchanged.

## Problem

The app runs at 120 Hz (`ios/Runner/Info.plist:24-25`, `CADisableMinimumFrameDurationOnPhone`). On Home, three things keep producing frames or repaint more than they need to. Every frame also re-runs the floating tab bar's `BackdropFilter` blur (`app_mobile_tab_bar.dart:105`).

**A. Importing view rebuilds every 20 ms.** The display-progress provider interpolates on a 20 ms timer (`sync_display_progress_provider.dart:8`, `:211`), and the Home importing view watches the raw double even though it only shows a whole percentage:

```dart
// lib/src/features/home/screens/mobile/mobile_home_screen.dart:905-911 — current
class _MobileHomeImportingProgress extends ConsumerWidget {
  const _MobileHomeImportingProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ImportingView(progress: ref.watch(syncDisplayPercentageProvider));
  }
}
```

```dart
// mobile_home_screen.dart:2614, :2636, :2645 — current
const _ImportingView({required this.progress});
...
final double progress;
...
'${formatSyncStatusPercentage(progress)}%',
```

`progress` is used nowhere else in `_ImportingView`. Most rebuilds produce the same text.

**B. Sync label animates without a repaint boundary.** While a sync runs (minutes to hours on a restore), the top-nav sync label rebuilds every frame. It has a `ShaderMask` label and a glow bar whose shadow blur changes each frame, and nothing isolates it from the rest of the top nav:

```dart
// lib/src/core/layout/mobile/mobile_sync_status.dart:253-260 — current
@override
Widget build(BuildContext context) => !_shouldAnimate
    ? _row(null)
    : AnimatedBuilder(
        animation: _activeController,
        builder: (context, _) => _row(_activeController.value),
      );
```

**C. Migration banner ripple loops forever without a repaint boundary.** In the "migrate to Ironwood" state, the banner's ripple repeats every second (`mobile_ironwood_migration_attention.dart:156`, `_controller.repeat()`), and its `AnimatedBuilder` at line 271 changes size and position each frame inside the Home list, next to the balance card.

## Target

- **A**: rebuild `_ImportingView` only when the displayed percentage text changes. Use Riverpod `select` with the same formatter the view already uses, so the shown text is identical.
- **B, C**: wrap each forever-running `AnimatedBuilder` in a `RepaintBoundary`, so its per-frame repaint does not repaint the surrounding Home content.

## Repo conventions to follow

- `select` on providers is already used in this codebase, e.g. `lib/src/providers/sync_display_progress_provider.dart:73-74`: `ref.watch(syncProvider.select((value) { ... }))`.
- `RepaintBoundary` around continuously animating content is already used in `lib/src/core/widgets/liquid_metal.dart:231` and `lib/src/features/onboarding/shared/welcome_video_backdrop.dart:167`.

## Steps

1. **A.** In `lib/src/features/home/screens/mobile/mobile_home_screen.dart`, replace the body of `_MobileHomeImportingProgress.build` (line 910):

   ```dart
   @override
   Widget build(BuildContext context, WidgetRef ref) {
     // The display provider ticks every 20 ms while it interpolates; rebuild
     // only when the shown whole percentage changes.
     final percentText = ref.watch(
       syncDisplayPercentageProvider.select(formatSyncStatusPercentage),
     );
     return _ImportingView(percentText: percentText);
   }
   ```

2. **A.** In `_ImportingView`, rename the input to match. Change only these three lines:
   - line 2614: `const _ImportingView({required this.progress});` → `const _ImportingView({required this.percentText});`
   - line 2636: `final double progress;` → `final String percentText;`
   - line 2645: `'${formatSyncStatusPercentage(progress)}%',` → `'$percentText%',`

   `_ImportingView` is private and constructed only at line 910. Confirm with `grep -n "_ImportingView(" lib/src/features/home/screens/mobile/mobile_home_screen.dart` (expect exactly one call site).

3. **B.** In `lib/src/core/layout/mobile/mobile_sync_status.dart:253-260`, wrap the animating branch:

   ```dart
   @override
   Widget build(BuildContext context) => !_shouldAnimate
       ? _row(null)
       : RepaintBoundary(
           child: AnimatedBuilder(
             animation: _activeController,
             builder: (context, _) => _row(_activeController.value),
           ),
         );
   ```

   Note: this changes the tree shape only when `_shouldAnimate` flips between syncing and synced. That already rebuilds the row from scratch today, so nothing that was kept is lost.

4. **C.** In `lib/src/features/migration/widgets/mobile/mobile_ironwood_migration_attention.dart`, wrap the `AnimatedBuilder(` that starts at line 271 (the `else` branch after the `AppIcons.loader` icon) in a `RepaintBoundary`:

   ```dart
   else
     RepaintBoundary(
       child: AnimatedBuilder(
         animation: _controller,
         builder: (context, _) {
           // ... unchanged builder body ...
         },
       ),
     ),
   ```

   Keep the builder body and all `ValueKey`s exactly as they are.

## Boundaries

- Do NOT change `syncDisplayPercentageProvider`, its 20 ms timer, `formatSyncStatusPercentage` or `syncDisplayWholePercentageProvider`.
- Do NOT change animation durations, curves, colors or the shimmer/ripple visuals.
- Do NOT touch the tab bar blur, the shield flow or other screens.
- If any excerpt above does not match the file (drift since commit 0604ac893), STOP and report.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test test/providers/sync_checking_display_test.dart test/core/layout/mobile/mobile_sync_status_test.dart` → all pass.
  - `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/home/mobile_home_screen_test.dart test/figma_compare/mobile_home_importing_scenario_test.dart` → all pass, unchanged.
- **Feel check** (a profile build on a real iPhone is best; the simulator only shows relative changes):
  - `fvm flutter run --profile --dart-define=VIZOR_FORM_FACTOR=mobile`, open DevTools › Performance and turn on "Track widget builds".
  - Import a wallet so Home shows the importing view. Before the change, `_ImportingView` builds about 50 times a second; after, about once per percent.
  - With a sync running, turn on the repaint rainbow (DevTools › Flutter Inspector › "Highlight repaints"): only the sync label flashes, not the whole top nav or Home list.
  - The importing percentage, the sync shimmer and the migration ripple look exactly as before.
- **Done when**: tests pass, the displayed percentage text is unchanged frame for frame, and the repaint rainbow is confined to the animating widgets.
