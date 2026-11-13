# Liquid Glass dependency review

Reviewed on 2026-11-13 for the iOS bottom tab bar. This is a scoped source and
dependency review, not a guarantee that the package is free of vulnerabilities.

## Artifact and dependency integrity

- Package: [`liquid_glass_widgets` 1.17.2](https://pub.dev/packages/liquid_glass_widgets/versions/1.17.2).
- Upstream: <https://github.com/sdegenaar/liquid_glass_widgets>; MIT license.
- Downloaded the published archive directly from pub.dev before adding it.
  Its SHA-256 matches the pub.dev API and the hash in `pubspec.lock`:
  `bd6c27d70dff598920cb96b03018a044fe75306ee1c23bd0f480a98bac673edd`.
- Validated archive paths before extraction: regular files/directories only,
  no links or path traversal.
- The only runtime dependency is the Flutter SDK. `flutter pub get` added one
  package and did not upgrade any existing dependency. Both `pubspec.yaml`
  (exact version, no caret) and `pubspec.lock` pin the reviewed release.
- Queried OSV for this exact Pub package/version; it returned no advisories.
  Absence of a published advisory does not establish absence of vulnerabilities.

## Source checks

Inspected the package manifests, complete iOS Swift implementation and CocoaPods
specification, initialization code, brightness/accessibility resolution, shader
loading and the bottom-tab implementation. Scanned all 155 runtime Dart files
for imports and network, filesystem, process, FFI and platform-channel APIs.

- All runtime imports resolve to the Flutter SDK, Dart SDK or package-local
  sources. The only `dart:io` file checks whether `FLUTTER_TEST` is present;
  it does not enumerate or transmit environment values.
- No executable runtime network requests, analytics endpoints, wallet/keychain
  access, process execution, dynamic native library loading or downloaded code
  were found. Network-image examples occur in documentation comments only.
- No packaged native binaries, build hooks, install scripts, CocoaPods
  `script_phase`/`prepare_command`, or non-Flutter native dependencies were found.
- The iOS plugin exposes the `liquid_glass_widgets/reserved_regions` method
  channel. It reads UIKit reserved screen regions/vertical-bar placement and
  observes layout/foreground changes. It has no storage or networking code.
  APIs from newer iOS SDKs are guarded at compile time and runtime.
- Shader loading uses package-bundled fragment programs. Screen/backdrop
  sampling is used locally for rendering; no persistence or transmission path
  was found in the reviewed code.

## Integration limits

- Only native iOS horizontal bottom tabs instantiate `GlassTabBar.bottom`.
  Android, web, desktop previews and vertical system-side tabs keep the existing
  surface. The package registers an iOS plugin and bundles its shaders through
  Flutter's normal dependency mechanism; platform rendering selection does not
  remove those package assets from other platform bundles.
- The glass theme is scoped to the tab bar and explicitly follows `AppTheme`,
  including an app theme that differs from the system theme. No global wrapping,
  brightness sampling, performance monitor or startup initialization is added.
  The package lazily loads its bundled shaders and supplies its renderer fallback.
- The iOS 27 material uses existing panel tint, active selection and icon tokens,
  icon-only tabs at 28px, 64px bar height and shell-owned margins/safe areas.
  Backdrop detail is made more visible with frost opacity 0.65 (light) / 0.75
  (dark), thickness 36 and refractive index 1.30; the preset's blur and frost
  radii remain unchanged. These optical adjustments need native-device review.
  Chromatic aberration is 0.08 on the platter and 0.15 on the selection lens,
  whose remaining settings inherit the iOS 27 indicator preset. The package's
  frosted/indicator shader paths constrain where dispersion appears; these
  values do not add a decorative rainbow outline.
- Reduced motion uses the existing instant-switch bar rather than the package's
  draggable indicator springs. Semantics labels and caller-owned route selection
  are retained, including VoiceOver activation.
- The package receives only tab labels, icon widgets, theme colors and the
  selected index; wallet providers, account data and secrets are not passed in.
  This limits integration coupling, not the privileges of third-party code.

Repeat this review before changing the pinned version, especially if future
releases add dependencies, native code, build hooks, permissions or network APIs.

## Validation

- `fvm flutter analyze --no-pub`: no issues.
- Mobile lane: 19 tests passed across `ios_liquid_tab_bar_test.dart`,
  `mobile_shell_components_test.dart`, `mobile_bottom_safe_area_test.dart` and
  `mobile_lane_sanity_test.dart`, using `--tags mobile --run-skipped
  --dart-define=VIZOR_FORM_FACTOR=mobile`.
- Desktop lane: 369 tests passed across `platform_asset_contract_test.dart`,
  `app_desktop_shell_test.dart` and `figma_compare_test.dart`.
- Visually inspected light and dark widget captures from the deterministic
  `mobile-ios-liquid-tabs` scenario (393 × 852).
- iOS simulator configuration and CocoaPods installation passed with the mobile
  define. Type-checked the plugin's complete Swift source against Flutter's
  simulator framework and the installed iOS 26.5 SDK (deployment target iOS 15).
- Widget captures exercise the package's host-renderer fallback. No full native
  app build or physical-device GPU/refraction/performance verification was run.
