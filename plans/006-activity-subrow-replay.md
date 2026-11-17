# 006 — Stop activity sub-rows from replaying their entrance on scroll

- **Status**: TODO — **needs dev sign-off before execution**
- **Commit**: 0604ac893
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 1 file, ~30 lines changed
- **Change type**: Small logic addition. `ActivityFeedRowGroup` becomes a `StatefulWidget` that remembers which sub-rows were already there. The animation itself (280 ms, `easeOutCubic`, fade + 6 px slide) is unchanged. Sign-off is needed because this converts a public widget from stateless to stateful.

## Problem

Swap activity rows can have sub-rows (e.g. an absorbed swap payout). The comment says the sub-row should "ease in instead of popping" when it appears later. But the animation is a `TweenAnimationBuilder` that starts at `begin: 0`, so it plays on every mount, not only when a sub-row is new:

```dart
// lib/src/features/activity/widgets/activity_feed.dart:891-933 — current (excerpt)
class ActivityFeedRowGroup extends StatelessWidget {
  const ActivityFeedRowGroup({required this.row, super.key});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    // The child slot is always present so a sub row appearing later (e.g. an
    // absorbed swap payout) eases in instead of popping.
    return Column(
      children: [
        ActivityFeedRow(row: row),
        AnimatedSize(
          ...
          child: Column(
            children: [
              for (final childRow in row.childRows)
                TweenAnimationBuilder<double>(
                  key: ValueKey(
                    'activity_child_${childRow.stableId ?? childRow.title}',
                  ),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    ...
```

The mobile Activity list is a lazy `SliverChildBuilderDelegate` (`activity_feed.dart:188-189`), and Home rows are keyed by index (`mobile_home_screen.dart:1438`). So sub-rows fade and slide in again every time they scroll back into view, and whenever Home rows shift. Motion seen this often, with no new information, should not play.

## Target

- Sub-rows present when the group first builds (or when it is handed a different parent row) show immediately: `Tween(begin: 1, end: 1)`, so nothing visibly animates.
- A sub-row that arrives later while the group is on screen still eases in exactly as today: `Tween(begin: 0, end: 1)`, 280 ms, `Curves.easeOutCubic`, fade plus 6 px slide.

## Repo conventions to follow

- State held in a private `State` class with `initState` / `didUpdateWidget`, like `ActivityFeedRow` right below it in the same file (`activity_feed.dart:937`, `class ActivityFeedRow extends StatefulWidget`).
- Keep the existing key string `'activity_child_${childRow.stableId ?? childRow.title}'` exactly, so tests and element identity are unchanged.

## Steps

1. In `lib/src/features/activity/widgets/activity_feed.dart`, replace the `ActivityFeedRowGroup` class (lines 891-933) with:

   ```dart
   class ActivityFeedRowGroup extends StatefulWidget {
     const ActivityFeedRowGroup({required this.row, super.key});

     final ActivityRowData row;

     @override
     State<ActivityFeedRowGroup> createState() => _ActivityFeedRowGroupState();
   }

   class _ActivityFeedRowGroupState extends State<ActivityFeedRowGroup> {
     /// Sub rows already present when this group first built, or when it was
     /// handed a different parent row. Only sub rows that arrive later ease in;
     /// scrolling a lazy list back to a row must not replay the entrance.
     late Set<String> _settledChildKeys;

     static String _childKey(ActivityRowData childRow) =>
         'activity_child_${childRow.stableId ?? childRow.title}';

     static Set<String> _childKeys(ActivityRowData row) => {
       for (final childRow in row.childRows) _childKey(childRow),
     };

     @override
     void initState() {
       super.initState();
       _settledChildKeys = _childKeys(widget.row);
     }

     @override
     void didUpdateWidget(covariant ActivityFeedRowGroup oldWidget) {
       super.didUpdateWidget(oldWidget);
       // Index-keyed lists can hand this state a different parent row.
       if (oldWidget.row.stableId != widget.row.stableId) {
         _settledChildKeys = _childKeys(widget.row);
       }
     }

     @override
     Widget build(BuildContext context) {
       final row = widget.row;
       // The child slot is always present so a sub row appearing later (e.g. an
       // absorbed swap payout) eases in instead of popping.
       return Column(
         children: [
           ActivityFeedRow(row: row),
           AnimatedSize(
             duration: const Duration(milliseconds: 240),
             curve: Curves.easeOutCubic,
             alignment: Alignment.topCenter,
             child: Column(
               children: [
                 for (final childRow in row.childRows)
                   TweenAnimationBuilder<double>(
                     key: ValueKey(_childKey(childRow)),
                     tween: Tween(
                       begin: _settledChildKeys.contains(_childKey(childRow))
                           ? 1
                           : 0,
                       end: 1,
                     ),
                     duration: const Duration(milliseconds: 280),
                     curve: Curves.easeOutCubic,
                     builder: (context, t, child) => Opacity(
                       opacity: t,
                       child: Transform.translate(
                         offset: Offset(0, (1 - t) * -6),
                         child: child,
                       ),
                     ),
                     child: ActivityFeedRow(
                       row: childRow,
                       compact: true,
                       childRow: true,
                     ),
                   ),
               ],
             ),
           ),
         ],
       );
     }
   }
   ```

   Everything inside `build` is the current code, except for `final row = widget.row;`, the key helper, and the `begin:` expression.

## Boundaries

- Do NOT change the animation values (240 ms `AnimatedSize`, 280 ms `TweenAnimationBuilder`, `Curves.easeOutCubic`, the 6 px offset).
- Do NOT change `ActivityFeedRow`, the list builders, the Home index keys or the row data models.
- Do NOT touch the desktop/mobile split; this widget is shared and the fix is correct for both.
- If the class no longer matches the excerpt (drift since commit 0604ac893), STOP and report.

## Verification

- **Mechanical**:
  - `fvm flutter analyze` → no new issues.
  - `fvm flutter test test/activity_feed_row_test.dart test/features/activity/` → all pass.
  - `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/home/mobile_home_screen_test.dart` → all pass.
  - Add one widget test next to the existing activity feed tests: pump an `ActivityFeedRowGroup` whose row has one child row, then assert the child's `Opacity` is `1.0` after a single `pump()` (no animation on mount). Then rebuild with a second child row and assert its `Opacity` is below `1.0` after `pump(const Duration(milliseconds: 50))` and `1.0` after `pumpAndSettle()`.
- **Feel check** (iOS Simulator, mobile form factor, a wallet with a swap that has a payout sub-row):
  - Activity tab: scroll the swap row off screen and back. The sub-row is simply there; no fade or slide.
  - Home: receive or send something so Home rows shift down. Existing sub-rows do not re-animate.
  - When a swap completes and its payout sub-row first appears while the row is visible, it still eases in.
- **Done when**: sub-rows animate only when they are new to a row that is already on screen.
