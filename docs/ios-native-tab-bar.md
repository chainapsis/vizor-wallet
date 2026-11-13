# Native iOS tab bar

The iOS 26+ bottom-navigation lane uses an app-owned Swift `UITabBar`, hosted
through one Flutter platform view in a root overlay. Flutter still owns the
destination list, localized titles, app theme, routing, and branch history. UIKit owns the glass
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

`IosNativeTabBarRootHost` wraps the router and ordinary app overlays, including
the payment-request card. Its native bar is the last child of a fixed root
Stack, above normal pages, sheets and cards, and below the existing security
and privacy hosts. A page's Cupertino transition does not move this host.
The tab shell publishes its item configuration, guarded branch callback,
navigation mode and viewport through an owned registration. It keeps a
transparent native-height slot rather than hosting another native view.
Releasing an old registration cannot clear a newer owner or accept its input.

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
timing; pointer ownership itself does not navigate. Explicit route/overlay
visibility and callback guards block input as soon as coverage starts. Hidden bars
also ignore Flutter pointers so their empty bounds cannot consume taps meant
to clear focus or interact with a covering surface.
Covered routes, popups, payment cards and navigation holds request a physical
exit. During the exit the bar draws above the incoming content, with touch and
accessibility disabled. A return to the eligible tab shell requests another
entrance once the outgoing cover has finished. Eligibility comes from the
source shell and all enclosing routes, not the root host's `ModalRoute`.
Security/privacy locks, logout and loss of the owning wallet context suppress
painting immediately instead of waiting for an exit animation.

## First presentation

On a native-eligible iOS host, capability and icon preparation initially occupy
a transparent slot rather than briefly showing the Flutter fallback bar. An
unsupported capability or preparation failure selects the original bar;
other platforms keep their existing path. Preparation does not unmount the
shell body or router.

The first native entrance waits until the view is attached and its nonzero
layout, safe area, native fitting height, and Flutter slot agree. Items and
theme are laid out while the bar is still hidden. Once prepared, the bar enters
from below using the normal entrance curve. This is tied to layout readiness,
not an arbitrary startup delay. Input remains blocked until both native
presentation and Flutter's input eligibility allow it.

Reattachment and a requested entrance are separate events. An explicit show
request after a hidden/offstage period waits for valid attached geometry and
enters from below, even when the native instance is reused. Reparenting an
already visible view does not itself request another entrance. A new show
request that interrupts an exit resumes from its current presented position.

## Visibility transitions

Flutter continues to decide when the bar is needed. UIKit independently slides
it up into its fixed slot when shown and down out of the slot when hidden;
this animation does not follow a Flutter route or modal's transition progress.
The entrance uses 180 ms with cubic Bézier control points `(0.2, 0.8, 0.2, 1)`:
it moves promptly and settles gently. The exit uses 140 ms with control points
`(0.3, 0, 0.8, 0.7)` for a short accelerating departure. The native bar's
material and selection lens retain their system behavior.

A hide request immediately blocks touch, accessibility, and selection
callbacks. The existing native view finishes its exit using the last displayed
items, titles, and selection. New configuration received during the exit or
while hidden is retained and applied before the next entrance. No screenshot
of wallet content is taken. Input becomes available only after UIKit confirms
that the entrance has completed.

Native presentation acknowledgements include the phase and settled-hidden
state. Flutter takes the platform view offstage only after the matching exit
has actually completed, excluding it and its effects from composition while
retaining its state. A stale exit acknowledgement cannot offstage a newer show.
Security suppression excludes painting immediately and cancels native motion.

The Flutter slot keeps its native fitting height throughout. Only an inner
native container moves, with safe-area geometry anchored to the stationary
host. Reversals resume from the current presented position; reversals and
geometry changes scale the duration by the remaining fraction of a full trip,
capped at the normal duration. A remaining distance of at most 0.5 pt settles
immediately. A visibility epoch and native presentation revision reject old
readiness acknowledgements and selection callbacks, including a rapid hide/show
cycle while a channel update is in flight. There are no per-frame Flutter
channel messages. A separate show-request ID survives coalesced readiness
updates and distinguishes an explicit entrance from a layout/input update.

Reduce Motion skips the slide. The root host's single view can survive normal
route coverage; disposing it cancels pending preparation and animations.
Callbacks are invalidated immediately when the source owner is released.

## Native shadow containment

A standalone `UITabBar` can draw effects above its platform-view bounds.
When an opaque Flutter sheet was composited above the old shell-owned view,
that overflow left a faint shadow stripe on the sheet at the platform-view
boundary. The root overlay avoids this partial covering: the complete material
exits above ordinary Flutter content, then leaves composition when hidden.
The implementation does not clip away the native glass/shadow to hide the
artifact; that diagnostic workaround changed backdrop composition in the probe.

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

The fixture's `Hide tabs` / `Show tabs` control exercises a complete exit and
entrance. `Reverse after 80 ms` interrupts an exit with an entrance so its
continuity and input gate can be checked without production wallet state.
The fixture has its own Navigator for `Open modal`, `Push page`, and
`Push translucent page`. These exercise exit-above-cover and return entrances.
`Recreate shell` replaces the publishing shell to check ownership handoff while
the root view remains stable. `Account sheet` opens the actual account-edit
sheet with deterministic local data, including its real surface and cancel row.
`Hard hide` / `Release hard hide` exercise immediate security-style suppression
without a wallet, followed by a prepared entrance.

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

The root-overlay revision was subsequently checked on a dedicated iOS 26.5
simulator with the actual Vizor target and the deterministic scenario. The
real account-edit sheet, a dialog, opaque and translucent routes, immediate
suppression, shell replacement, interrupted exits and repeated selections all
passed interaction checks. A cancelled back gesture kept the bar hidden; a
completed back gesture restored it without changing selection. The isolated
native suite passed 30 tab-bar tests, including explicit entrances,
settled-hidden acknowledgements and immediate suppression. These checks cover
the native bridge and compositor behavior, not production wallet lifecycle or
real-device performance.
