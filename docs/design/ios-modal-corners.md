# iOS modal corners

On iOS, modal surfaces use Flutter's `RoundedSuperellipseBorder`. Top corners
remain fixed. Bottom-anchored `MobileModalCard` surfaces can adapt their bottom
corners to the display; centered cards set `followsScreenCorners: false` and
keep fixed radii. `AppModalCard` and Material dialogs also use continuous corners
on iOS. Existing explicit dialog radii remain intact. Other platforms keep
circular corners.

## Geometry and fallback

`ModalCornerHandler` uses the public iOS 26 `UIView.cornerConfiguration` and
`effectiveRadius(corner:)` APIs. It lays out one detached, reusable UIView at the
actual Flutter card rectangle in window coordinates, with bottom radii configured
as `containerConcentric(minimum: 32)`. It never inserts this view into the
hierarchy or creates a Flutter PlatformView. Flutter owns painting, input,
accessibility, clipping, shadows and animations.

The detached-view calculation was verified on the iPhone simulator, including
rotation. Its implicit scene selection is not a documented multi-scene contract:
queries are restricted to a single active, full-screen iPhone Flutter host whose
viewport and scale match the request. Unsupported iOS versions, inactive or
ambiguous hosts, off-window geometry, malformed responses, channel errors and
300 ms timeouts fall back to the original 32-point bottom radius. No private
screen-radius API or device-model lookup table is used.

### Cache lifetime and eligibility

The engine-owned native handler keeps a bounded 64-entry memory LRU. Successful
results survive modal closure and foreground/background transitions, but not
engine/process restarts. Geometry is never loaded from or saved to disk.
Keys include orientation, logical viewport, display scale/native dimensions and
left/right/bottom placement. Content height and top position are excluded.
Hardware/OS identifiers are unnecessary within one process. Failed queries are
not cached. Rotation selects a different key without clearing prior entries.

UIKit receives a tall reference rectangle extending from the window's top to
the actual modal's bottom, retaining its horizontal position and width. This
makes the first calculation independent of which modal opens first. Applying
its result requires actual height >= `2 * (32 + max(bottomLeft, bottomRight))`;
width must also be >= `4 * max(bottomLeft, bottomRight)`. These are conservative
app policies, not UIKit formulas. Smaller cards use the original 32-point radius
and never populate the shared cache. Eligibility is checked on cache hits too.
At a 46-point bottom radius, the minimum height is 156 points.

Even a hit passes through the native channel to check the current active,
single-scene, full-screen host. It skips UIKit's radius calculation, not host
validation. This avoids applying a stale Dart-only cache after a window/scene
change. Centered and transparent cards do not query geometry.

### First visible frame

For iOS `showAppMobileSheet`, `PreparedModalSheetRoute` uses ModalRoute's offstage
layout to measure the genuine final frame. The route's entrance waits for the
initial radius. Once ready, the shape is installed without interpolation and
the ordinary Material entrance starts from zero. The content stays mounted
through preparation, preserving text fields and camera state.

Direct/inline `MobileModalCard` users also suppress paint, pointer events and
semantics until their first settled geometry resolves. Their surrounding route
is not hidden or restarted. Preparation waits at most 100 ms for a native
response after measurement; missing/failed/slow responses choose 32. A late
initial response cannot change the currently displayed card. Native successful
results can still populate the cache for a future presentation. The channel's
own 300 ms timeout bounds its request independently.

Both fallback and adapted corners remain superellipses. Only subsequent layout
changes (such as the keyboard) interpolate radii with a 250 ms ease-out cubic
animation; interrupted transitions continue from the current shape. Keyboard
appearance selects 32 without deleting cached screen geometry. Foreground
recovery validates geometry again without first resetting the visible corners.
Reduce Motion disables radius interpolation. Material clip, shadow and inner
highlight share one shape.

## Validation (2026-09-23)

Vizor PR688 E2E, iPhone 17 Pro, iOS 26.5, 402 × 874 logical points, scale 3:

| State | Top radius | Bottom left/right | Card frame (x, y, w, h) |
| --- | --- | --- | --- |
| Dark bottom sheet | 32 | 46 / 46 | 16, 607, 370, 251 |
| Software keyboard (335 pt) | 32 | 32 / 32 | 16, 272, 370, 251 |
| Keyboard closed | 32 | 46 / 46 | 16, 607, 370, 251 |
| Centered dialog | 32 | 32 / 32 | 40, 325.5, 322, 251 |
| Light tall sheet | 32 | 46 / 46 | 16, 306, 370, 552 |

Memory-cache regression coverage checks height-independent reference geometry,
conservative size eligibility, in-memory reuse, empty new instances,
invalid-value rejection and bounded LRU retention. Flutter
regressions cover late timeout responses, first visible frames, preserving child
identity, covered/closed preparation, interrupted resize queries and localized
scrim semantics. No height-by-height simulator sweep was performed.

The memory-cache revision passed 127 Flutter tests, three native tests and
Flutter analysis. The designated simulator E2E passed: one UIKit calculation
for the first sheet, two memory hits across keyboard restoration and the tall
sheet, with stable 46-point entrance frames and 32-point keyboard/centered
fallback. These checks do not replace physical-device validation.

The real Runner and production modal widgets were used with a deterministic
preview entry point, without initializing the Dart wallet/Rust runtime or sync.
Screenshots verified surface, clip and shadow alignment. This is simulator
validation; physical-device validation remains separate.

The focused tests cover fallback and timeout, asymmetric radii, keyboard
interruption, stale responses, route entrance/dismissal, content resizing,
rotation/lifecycle recovery, centered/transparent cards, and Android behavior.
The broader mobile run now passes all 127 tests. The pre-existing vote-config
position failure was an outdated 32-point outer-margin expectation left after
PR #729 changed the shared gap to 16. The test now checks outer clearance
independently from modal-relative content geometry, runs on iOS and Android,
and covers 34/48-point bottom insets and keyboard clearance. The deterministic
`mobile-voting-config-default` widget capture confirms the 393 × 852 layout:
modal frame (16, 310, 361, 526), with 16-point side and bottom gaps and no clipped
controls. No production layout change was required. Five desktop modal tests
passed during the corner implementation; the full Flutter analyzer also passes
after this test correction.

## Reproduce native captures

Use a dedicated simulator: the preview replaces its installed Vizor executable.
Enable the software keyboard in Simulator. Build and install the preview, then
run the capture script with that simulator's UDID:

```bash
fvm flutter build ios --simulator --debug --no-pub \
  --dart-define=VIZOR_FORM_FACTOR=mobile -t lib/modal_corner_preview.dart
xcrun simctl install <UDID> build/ios/iphonesimulator/Runner.app
python3 scripts/e2e/ios-modal-corners.py --device <UDID> --output /tmp/modal-captures
```

The script launches the installed preview, captures five screenshots and writes
`results.json`, asserting native adaptation, keyboard fallback/restoration,
fixed centered corners and constant radii from the first visible entrance frame.
Every run restarts the process and expects one UIKit calculation, then at least
two memory hits across keyboard restoration and a different-height sheet.
It expects an iOS 26+ rounded iPhone simulator. The
normal `lib/main.dart` entry point does not import this harness.
