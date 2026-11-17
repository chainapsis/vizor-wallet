# Native iOS tab bar

The iOS 26+ navigation lane uses an app-owned Swift `UITabBar` for bottom
navigation and a child `UITabBarController` for system side tabs on iPhone Duo.
Both are hosted through one Flutter platform view in a root overlay. Flutter
still owns the destination list, localized titles, app theme, routing, and branch
history. UIKit owns the glass material, item layout, selection lens, touch
handling, and accessibility.

## Appearance and scope

- Selected icons and titles use the existing `colors.navPanel.activeIcon`
  accent through `UITabBar.tintColor`. Native material, background, blur,
  refraction, springs, item spacing and title typography use UIKit defaults.
  Icons remain template images; no `UITabBarAppearance` recipe or hand-drawn
  glass layer is installed.
- Native icons are compiled from SVGs in Xcode's asset catalog and loaded by
  name in Swift as cached 25-point template images. Flutter sends only the icon
  name, not PNG data. This is icon preparation, not capture of the background.
- The native height includes its bottom safe-area clearance. The floating
  Flutter fallback bar's 60-pixel height and surrounding margins do not wrap
  this lane. Flutter's tab icon flourishes and surrounding touch blocker also
  stay in the fallback lane; UIKit owns native motion and hit testing.
- The resolved app theme and text direction are passed to UIKit. Item titles
  come from the existing Flutter localizations.
- Other platforms, older iOS versions and the expanded wallet sidebar retain
  their current implementations. Duo system side tabs use the native path.

## iPhone Duo system side tabs

The native geometry bridge reads the system's physical vertical-bar edge. A
right or left system rail selects `NativeSideTabBarPlatformView`; bottom
navigation retains the standalone bar. The side implementation embeds a real
`UITabBarController` as a child of the existing Flutter controller, with
transparent placeholder destinations. UIKit owns vertical placement and glass;
Flutter still commits destination changes through the guarded routing callback.
The root controller and Flutter engine are not replaced.

The side controller occupies the full viewport so it can adopt the scene's
system layout. Flutter's hit-test wrapper claims only the rectangle reported by
the native bar. Other content continues to receive Flutter taps and scrolling.
The native host forwards those hits through the controller view: modern UIKit
can render and handle the vertical glass outside the public `UITabBar` proxy.
No private view names, rotated bottom bars or extracted native bars are used.
The passive press observer belongs to the controller and accepts direct hits
on its native side surface, excluding placeholder content.

Every native geometry change advances a layout revision. Input requires a
Flutter acknowledgement of that exact revision and a matching laid-out slot,
as well as the existing visibility epoch, owner, security and route gates.
Changing between bottom, left and right recreates only the native surface;
the Flutter router and branch state remain mounted. A delayed callback from a
previous surface/owner cannot select a destination for its replacement.

Right-side tabs enter from the right and leave to the right. Left-side tabs
mirror that direction. Durations, easing, Reduce Motion, exit-state freezing,
interruption handling and input gates match bottom navigation. Only rendered
controller contents move horizontally; native layout and safe-area registration
stay stationary. The full platform view goes offstage after the matching exit
acknowledgement, so no hidden material remains over a modal.

Before detaching or reattaching the side controller, its view is made invisible
and the horizontal layer translation is reset to identity. UIKit must resolve
its floating glass in an unshifted coordinate system. The next explicit show
still performs the normal prepared entrance after layout acknowledgement.

The reattachment regression removes and restores the real native host repeatedly
with both Reduce Motion settings, an immediate hide, and hidden theme changes.
It compares the native hit surface's actual converted bounds and rejects hits
on transparent destination content; checking `UITabBar.frame` alone misses this
failure. Simulator interaction checks also need to select tabs after each
complete hide/show cycle.

## Icon assets and synchronization

`assets/icons/` is the source of truth for the tab artwork. The native catalog
intentionally contains byte-identical SVG copies so UIKit can load its own
images without Flutter's SVG parser, PNG encoder or asset bundle. Xcode compiles
these SVGs into native assets; no runtime SVG library is added to Swift.

| Flutter source | Native image set |
| --- | --- |
| `assets/icons/home.svg` | `VizorTab_home.imageset` |
| `assets/icons/swap_arrows.svg` | `VizorTab_swap_arrows.imageset` |
| `assets/icons/history.svg` | `VizorTab_history.imageset` |
| `assets/icons/cog.svg` | `VizorTab_cog.imageset` |

All four sets live in `ios/Runner/Assets.xcassets/`. Keep their SVG contents
unchanged from the Flutter originals. Swift normalizes their intrinsic sizes
(20 points for Swap, 24 for the others) to the existing 25-point tab icon size.
The catalog preserves vector data and marks the images as templates; selected
icons and labels continue to share the app tint.

After editing a source SVG, refresh and verify the committed native copies:

```bash
scripts/sync-ios-native-tab-icons.py --apply
scripts/sync-ios-native-tab-icons.py --check
fvm flutter test test/core/ios_native_tab_icon_asset_contract_test.dart
```

The default script invocation is also read-only. Commit both copies and any
catalog metadata changes together. When adding or renaming a tab icon, update
the source, `mobileDestinations`, the script's icon list and Swift's native
catalog mapping. The contract test checks exact SVG equality, template/vector
metadata, and coverage against the actual mobile destinations. Native tests
also load every mapped image from the built application bundle and check its
size and rendering mode.

The native capability response reports only icon names that actually load.
Flutter checks all requested names before creating the platform view. An
unsupported OS or unavailable icon selects the original Flutter bar, whose
SVG cache has not been touched by native preparation. Invalid native updates
are rejected atomically without partially replacing the displayed items.

Do not reintroduce Flutter-side SVG-to-PNG preparation for this lane. The old
`SvgAssetLoader(assetBundle: ...)` path could capture a cached `Future` through
the bundle when the release parser spawned an isolate. That failed before the
native bar was created, and `flutter_svg` 2.2.4 retained the failed load under
the same cache key used by fallback icons. Debug parsing did not spawn this
isolate, so debug simulator checks alone did not exercise the failure.

## Ownership and updates

The view is registered from `AppDelegate.didInitializeImplicitFlutterEngine`,
using Flutter's existing scene lifecycle. The app's root controller and its
Flutter engine are retained; they are not replaced when a tab changes.

`IosNativeTabBarRootHost` wraps the router and ordinary app overlays, including
the payment-request card. Its native bar is the last child of a fixed root
Stack, above normal pages, sheets and cards, and below the existing security
and privacy hosts. A mobile page's fade/zoom or back swipe does not move this
host. Accounts is a detail page that covers the tab bar; callbacks queued before
the route change cannot select a tab behind it.
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
neither the platform view nor unchanged native items. Native
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
accessibility disabled. A page return to the eligible tab shell requests an
entrance as the return starts, while input remains blocked until navigation
settles. Closing popups and payment cards retain their coverage until the
cover has finished. Eligibility comes from the source shell and all enclosing
routes, not the root host's `ModalRoute`.
Security/privacy locks, logout and loss of the owning wallet context suppress
painting immediately instead of waiting for an exit animation.

## Press haptics

An enabled native tab item emits one system `.soft` impact when a direct
finger contact begins, including repeated presses of the selected item. This
acknowledges the press rather than a destination change: dragging or cancelling
does not add another pulse, and selection/re-selection callbacks never emit a
second one. Programmatic selection and accessibility activation do not use this
touch-only path.

A passive native gesture observer sees item contacts without recognizing a
gesture, cancelling touches or delaying delivery. It cannot prevent or be
prevented by UIKit's recognizers. Bottom-bar control hit-testing excludes the
bare tab background, transparent wrapper, home-indicator area and foreign views;
no private tab-button class names or inferred item rectangles are used.

The existing native `isInteractive` gate also controls the observer. Hidden,
entering, exiting, unprepared and visible-but-input-disabled bars cannot emit
press feedback, including a bar previewed during a back gesture. The feedback
generator is retained with the native view and prepared when input is enabled
and after a pulse. Disposing the native view removes the observer.

## First presentation

On a native-eligible iOS host, capability and native icon availability checks occupy
a transparent slot rather than briefly showing the Flutter fallback bar. An
unsupported capability or unavailable native icon selects the original bar;
other platforms keep their existing path. Preparation does not unmount the
shell body or router.

The first native entrance waits until the view is attached and its nonzero
layout, safe area, native fitting height, and Flutter slot agree. Items and
theme are laid out while the bar is still hidden. Once prepared, the bottom bar
enters from below and side tabs enter from their physical edge using the normal
curve. This is tied to layout readiness,
not an arbitrary startup delay. Input remains blocked until both native
presentation and Flutter's input eligibility allow it.

Reattachment and a requested entrance are separate events. An explicit show
request after a hidden/offstage period waits for valid attached geometry and
enters from its placement edge, even when the native instance is reused.
Reparenting an already visible view does not itself request another entrance. A new show
request that interrupts an exit resumes from its current presented position.

## Visibility transitions

Flutter continues to decide when the bar is needed. UIKit independently slides
bottom tabs up into their fixed slot when shown and down when hidden, or
side tabs horizontally from/to their physical edge;
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

The Flutter slot keeps its native fitting height throughout. For bottom
navigation, only an inner native container moves, with safe-area geometry
anchored to the stationary
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

## Returning to the tab shell

Page return visibility and input readiness are separate decisions. A committed
page pop can request the tab bar's entrance before the outgoing page finishes
its reverse animation. A mobile edge-back gesture can also preview the bar while
the finger is still down, but only when its exact previous route is the owning
tab shell. Returning between two detail pages does not reveal the tab bar.

The bar uses its normal 180 ms entrance rather than following the gesture's
progress. Even if it finishes entering during a held swipe, Flutter pointers,
UIKit touch/drag handling, accessibility and committed-selection callbacks
remain disabled. Input requires both settled navigation (including the end of
the back gesture) and the native visible/readiness acknowledgement.

Cancelling the swipe requests a hide from the bar's current presentation,
without first enabling input. Return tracking distinguishes an actual
cancellation from pointer releases while another finger still controls the
drag, and releases its pointer subscriptions with the owning registration.
Popups, payment-card closing, navigation holds, keyboards
and security/privacy suppression retain their respective coverage gates.
Route-owned redirects continue to wait for route completion; the early visual
preview belongs only to the native tab bar.

## Native shadow containment

A standalone `UITabBar` can draw effects above its platform-view bounds.
The root overlay keeps the complete material above ordinary Flutter content
throughout its exit, then removes it from composition while hidden. Avoid
clipping the native glass or shadow because that can change backdrop composition.

## Background and performance

Native material and native background sampling are separate claims. A lens
that magnifies its native icon does not prove that it refracts Flutter content.
Validate actual moving Flutter pixels under the bar before claiming parity.
Widget tests cover the Dart state/channel contract and fallback layout; UIKit
material requires the native compositor rather than `RepaintBoundary.toImage`.

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
