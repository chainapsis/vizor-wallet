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

Queries occur after settled layout, not on every animation frame. Each card
caches up to four successful geometries, invalidating them for viewport changes
and lifecycle transitions. Keyboard appearance restores 32; closing it restores
the eligible native geometry. Late responses are invalidated on keyboard,
viewport, lifecycle, route animation and disposal changes. Transparent cards
own their surfaces and make no query.

Both fallback and adapted corners remain superellipses. A 250 ms ease-out cubic
animation interpolates only the radii, so interrupted keyboard transitions
continue from the current shape. Reduce Motion disables that interpolation.
The material clip, shadow and inner highlight share the same shape.

## Validation (2026-09-23)

Vizor PR688 E2E, iPhone 17 Pro, iOS 26.5, 402 × 874 logical points, scale 3:

| State | Top radius | Bottom left/right | Card frame (x, y, w, h) |
| --- | --- | --- | --- |
| Dark bottom sheet | 32 | 46 / 46 | 16, 607, 370, 251 |
| Software keyboard (335 pt) | 32 | 32 / 32 | 16, 272, 370, 251 |
| Keyboard closed | 32 | 46 / 46 | 16, 607, 370, 251 |
| Centered dialog | 32 | 32 / 32 | 40, 325.5, 322, 251 |
| Light tall sheet | 32 | 46 / 46 | 16, 306, 370, 552 |

The real Runner and production modal widgets were used with a deterministic
preview entry point, without initializing the Dart wallet/Rust runtime or sync.
Screenshots verified surface, clip and shadow alignment. This is simulator
validation; physical-device validation remains separate.

The focused tests cover fallback and timeout, asymmetric radii, keyboard
interruption, stale responses, route entrance/dismissal, content resizing,
rotation/lifecycle recovery, centered/transparent cards, and Android behavior.
The broader mobile run passed 116 tests with one pre-existing failure:
`vote config matches the default mobile Figma modal` expects y=294 but gets
310. The identical failure was reproduced from unchanged base `106c8528`.
Five desktop modal tests and the full Flutter analyzer passed.

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
`results.json`, asserting native adaptation, keyboard fallback/restoration and
fixed centered corners. It expects an iOS 26+ rounded iPhone simulator. The
normal `lib/main.dart` entry point does not import this harness.
