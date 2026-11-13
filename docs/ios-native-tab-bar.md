# Native iOS tab bar

The iOS 26+ bottom-navigation lane uses an app-owned Swift `UITabBar`, hosted
through one Flutter platform view. Flutter still owns the destination list,
localized titles, app theme, routing, and branch history. UIKit owns the glass
material, item layout, selection lens, touch handling, and accessibility.

## Appearance and scope

- Selected icons and titles use the existing `colors.navPanel.activeIcon`
  accent through `UITabBar.tintColor`. Native material, background, blur,
  refraction, springs, item spacing and title typography use UIKit defaults.
  Icons remain template images; no `UITabBarAppearance` recipe or hand-drawn
  glass layer is installed.
- The existing SVG icons are rasterized as small template images and cached.
  This is icon preparation, not capture of the app's background.
- The native height includes its bottom safe-area clearance. The floating
  Flutter bar's 64-pixel height and surrounding margins do not wrap this lane.
- The resolved app theme and text direction are passed to UIKit. Item titles
  come from the existing Flutter localizations.
- Other platforms, older iOS versions, and existing vertical/sidebar navigation
  retain their current implementations.

This implementation is independent of `liquid_glass_widgets`. The earlier
experiment remains on `codex/ios-liquid-glass-tabs`.

## Ownership and updates

The view is registered from `AppDelegate.didInitializeImplicitFlutterEngine`,
using Flutter's existing scene lifecycle. The app's root controller and its
Flutter engine are retained; they are not replaced when a tab changes.

Each destination has a stable ID derived from its route. UIKit reports only
committed selections, including re-selection. Flutter maps these back to the
existing GoRouter branches and synchronizes programmatic changes without
generating another user-selection callback. Removing Swap does not change the
identity of Activity or Settings.

The platform view persists across normal builds. Small state updates replace
neither the platform view nor unchanged native items. Icon work and native
messages must not publish stale state after a destination update or disposal.
The platform view claims its pointer sequences immediately with an
`EagerGestureRecognizer`. Without this, the app-wide tap-to-unfocus recognizer
holds the gesture arena open during a stationary press, suppressing UIKit's
lens until movement rejects the ancestor tap. UIKit still owns selection
timing; pointer ownership itself does not navigate. Flutter modal barriers and
the existing native visibility/callback guards remain in force. Hidden bars
also ignore Flutter pointers so their empty bounds cannot consume taps meant
to clear focus or interact with a covering surface.
Covered routes, popups, navigation guards, and the keyboard disable or hide the
native bar; its native lifecycle does not grant navigation around a Flutter
access gate.

## Background and performance validation

Native material and native background sampling are separate claims. A lens
that magnifies its native icon does not prove that it refracts Flutter content.
Validate actual moving Flutter pixels under the bar before claiming parity.

The deterministic `mobile-native-tab-bar` scenario contains scrolling color
bands and large text, without wallet, network, secure-storage, or Rust startup.
Changing tabs changes the color sequence. Run it on iOS with the mobile token
define; leave the capture output empty for interaction:

```bash
fvm flutter run -d <ios-simulator-id> -t lib/figma_compare.dart \
  --dart-define=VIZOR_FORM_FACTOR=mobile \
  --dart-define=FIGMA_COMPARE_SCENARIO=mobile-native-tab-bar \
  --dart-define=FIGMA_COMPARE_OUTPUT=
```

Use a dedicated simulator/install for native checks. The normal Runner still
has native startup hooks even when its Dart entry point omits wallet startup.
Widget tests verify the Dart state/channel contract and fallback layout; they
cannot capture the UIKit material. Native screenshots need the simulator's
compositor rather than `RepaintBoundary.toImage`.

For performance, compare the same content, device, OS, and build mode against
the previous implementation. Measure scrolling and tab dragging after warm-up,
including Flutter frame timing, compositor/GPU cost, memory, and sustained
thermal behavior. Simulator debug timings are diagnostic only. UIKit may
reduce custom shader work, but platform-view composition is not free.

## References

- [Flutter iOS platform views](https://docs.flutter.dev/platform-integration/ios/platform-views)
- [Flutter platform-view composition costs](https://api.flutter.dev/flutter/dart-ui/SceneBuilder/addPlatformView.html)
- [Apple UITabBar](https://developer.apple.com/documentation/uikit/uitabbar)
- [Apple scrollEdgeAppearance](https://developer.apple.com/documentation/uikit/uitabbar/scrolledgeappearance)
- [adaptive_platform_ui native tab-bar implementation](https://github.com/berkaycatak/adaptive_platform_ui/blob/main/ios/adaptive_platform_ui/Sources/adaptive_platform_ui/iOS26TabBarPlatformView.swift)

The reference package informs the platform-view bridge design; it is not an
application dependency. A standalone tab bar does not provide every
`UITabBarController` feature, including its controller-managed scroll-edge
appearance and automatic integration with native scroll views. Flutter
scrolling is not automatically a UIKit scroll view.

## Verification record

On 2026-11-13, an isolated Flutter 3.47.8 app using the exact Swift host was
run on a dedicated iPhone 17 Pro simulator with iOS 26.5. It did not contain
wallet services or Rust code. Its default standalone tab-bar geometry matched
an untouched native `UITabBarController` reference in that environment.

Solid red and blue Flutter backgrounds changed the visible glass color.
More usefully, 16-point black/white Flutter stripes were sharp outside the
native bar and visibly blurred inside it. This demonstrates filtering of
Flutter background pixels in this configuration, rather than only a lens over
native icons. It is not a guarantee for every Flutter/OS/GPU combination.

All seven `NativeTabBarTests` also passed in the isolated simulator host,
covering atomic configuration updates, item/image reuse, selection callbacks,
theme/direction/visibility, native appearance and template images, height
notifications, and channel disposal.

The same isolated host was checked on an iOS 27.1 iPhone Duo simulator. Both
OS runs logged the Impeller Metal backend and showed smoothing of Flutter
stripes through the native material. For a fixed stripe scanline on 26.5,
grayscale standard deviation fell from 127.4 with the bar hidden to 31.1 inside
the visible material, with intermediate edge values instead of only black and
white. The 27.1 sample showed the same qualitative effect. Different display
geometry and system materials make these numbers unsuitable for comparing
blur strength between OS versions.

Maestro interaction checks in the isolated host observed one callback per
selection, repeat selections, and no destination commit during a held drag
before release. System optics outside the tested positions and exact optical
parity were not exhaustively measured.

The actual Vizor simulator target also builds with the deterministic scenario.
It was installed only on the dedicated 26.5 simulator. A Maestro smoke test
selected Swap, selected it again, and selected Settings; the Flutter fixture
observed exactly three committed selections through the production bridge,
using the real SVG icons and dark app theme.
Focused Dart bridge tests (12), the mobile routing/layout regression set (68),
and full Flutter analysis passed. A warmed debug-simulator probe recorded a
Flutter raster P95 around 0.9 ms, but this excludes UIKit compositor/GPU work;
it establishes neither a device frame-rate guarantee nor a performance win
over the previous shader implementation. Real-device profile/release,
memory, energy and sustained thermal comparisons remain required before
claiming such a win.

The independent review found two integration gaps: a queued native selection
could navigate beneath the mobile sync privacy lock, and UIKit accessibility
selection was not counted by Flutter's idle-activity listener. Both were fixed
and covered by regression tests, including blocked re-selection and inactive
lifecycle events. The migration privacy overlay is desktop-only, so its raw
state does not incorrectly disable mobile native tabs.
