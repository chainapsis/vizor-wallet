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

The engine-owned native handler reads a bounded 64-entry persistent LRU cache
from UserDefaults when it is registered. Successful results survive modal
closure, foreground/background transitions and process restarts. Failed queries
and timeouts are never stored. Keys include hardware model, OS version,
orientation, logical viewport, display scale/native dimensions, the exact final
card rectangle (including height), minimum radius and cache schema version.
No time-based expiration is needed. Rotation selects a different key without
throwing away the previous orientation's entries.

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

First-frame/cache follow-up: both cold and warm runs kept bottom radii at
46 throughout every sampled entrance frame for the short and tall sheets.
The cold run performed two UIKit calculations (one per distinct rectangle) and
one cache hit on keyboard dismissal. After process restart, the warm run used
three cache hits and performed zero UIKit calculations. Keyboard transitions
still interpolate 46 → 32 → 46; centered dialog frames stay at 32.

Three native `ModalCornerCacheTests` passed on the designated simulator's Xcode
test clone: persistence/profile separation, corrupt-value rejection (including
valid 32-point caching), and bounded LRU retention. Flutter regressions cover
late timeout responses, first visible frames, preserving child identity,
covered/closed preparation, interrupted resize queries and localized scrim
semantics.

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
Use `--expect-cache cold` for a fresh cache, then run again with
`--expect-cache warm` to verify zero UIKit recalculations after process restart.
It expects an iOS 26+ rounded iPhone simulator. The
normal `lib/main.dart` entry point does not import this harness.
