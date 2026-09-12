# UI and platform contracts

Use this for design tokens, shared navigation surfaces, desktop windows, copy,
and visual comparison. Business-flow destinations belong to the relevant
[send](send.md), [swap](swap-pay.md), or [payment-link](payment-links.md) contract.

## Entry points

| Question | Implementation |
| --- | --- |
| Compiled form factor and token selection | [app_form_factor.dart](../../lib/src/core/layout/app_form_factor.dart), [app_typography.dart](../../lib/src/core/theme/app_typography.dart), [app_sizing.dart](../../lib/src/core/theme/app_sizing.dart) |
| Mobile shell, history, and bottom inset | [app_mobile_shell.dart](../../lib/src/core/layout/mobile/app_mobile_shell.dart), [mobile_tab_history.dart](../../lib/src/core/navigation/mobile_tab_history.dart), [mobile_bottom_safe_area.dart](../../lib/src/core/layout/mobile/mobile_bottom_safe_area.dart) |
| Desktop creation, appearance, and showing | [app.dart](../../lib/app.dart): `initializeZcashWalletRuntime`, `runZcashWalletApp`; [app_layout.dart](../../lib/src/core/layout/app_layout.dart); [MainFlutterWindow.swift](../../macos/Runner/MainFlutterWindow.swift) |
| Deterministic visual states | [figma_compare_scenarios.dart](../../lib/figma_compare/figma_compare_scenarios.dart), [figma-compare.sh](../../scripts/figma-compare.sh) |

## Form factor and tests

- `VIZOR_FORM_FACTOR=desktop|mobile` is a build-time define; desktop is the
  default. Every mobile `run`, `build`, `test`, and `drive` needs
  `--dart-define=VIZOR_FORM_FACTOR=mobile`. Release builds have no assertion
  guard, so release/CI commands must supply it too.
- App code uses unsuffixed selectors (`AppTypography`, `AppInputSizing`, etc.)
  and `kAppFormFactor` for layout choices. OS checks are for OS behavior, not
  selecting UI metrics. The const selectors allow the unused mode to be
  tree-shaken.
- New mode-dependent tokens use Desktop/Mobile const sets plus an unsuffixed
  selector. Spacing, radii, units, and window groups shared by both modes stay
  single-mode. Explicit `*Desktop`/`*Mobile` sets are for previews and tests
  that must inspect or pin a mode.
- A test binary has one form factor. Mobile-UI files start with
  `@Tags(['mobile'])`; [dart_test.yaml](../../dart_test.yaml) skips them in the
  default desktop lane. Run the mobile lane with all three flags:
  `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`.
- `--run-skipped` lifts every skip in the selected tests. Do not use `skip:` to
  park broken mobile tests. Untagged tests must work in either lane: compare
  token constants rather than desktop-only numeric literals.
- The app entry point asserts platform/form-factor agreement in debug.
  Widgetbook intentionally allows mobile previews on a desktop host:
  `fvm flutter run -t lib/widgetbook.dart --dart-define=VIZOR_FORM_FACTOR=mobile`.

Startup routes and the first-frame account/sync snapshot are owned by the
[account bootstrap contract](account-storage.md#startup-snapshot).

## Mobile and desktop geometry

- Sheet bodies and the floating tab bar use `MobileBottomSafeArea`, with
  `bottomPadding` equal to the content's actual padding below its last control.
  On iOS, padding of at least `kIosHomeIndicatorClearance` (16) suppresses the
  additional bottom inset; Android always honors its navigation-bar inset.
  Keyboard `viewInsets` remain separate. Tests override `defaultTargetPlatform`.
- The mobile tab bar has a 16px bottom gap on iOS and 12px plus the inset on
  Android. Keep the wrapper argument aligned when changing a padding token.
- `window_manager` owns desktop sizing and lifecycle; `desktop_window_bootstrap`
  owns native appearance. Create the OS window before initializing its visuals.
  The current runtime requests `DesktopWindowVisualStyle.opaque`.
- `runZcashWalletApp` shows Windows after the first Flutter frame; other desktop
  platforms show during runtime initialization. Preserve this platform-specific
  ordering instead of assuming every window is shown before `runApp`.
- Keep appearance changes in the native/bootstrap owner. If a surface is meant
  to expose a translucent native region, its Flutter background must be
  transparent; opaque fills cover that region. This does not require making
  the current opaque shell translucent.
- For sync animation, [sync_display_progress_provider.dart](../../lib/src/providers/sync_display_progress_provider.dart)
  owns the 20ms UI interpolation timer. Smooth indicators read its raw progress;
  labels read whole percentages. Rust/provider progress remains authoritative,
  and only real completion produces 100%.

## Copy

- Use sentence case for user-facing strings; preserve proper names and acronyms
  such as Vizor, Zcash, Keystone, ZEC, USDC, USDT, and NEAR. Interpolated symbols
  keep their casing, while surrounding words remain sentence case.
- Figma display headings, sidebar entries, and screen titles may retain title
  case. Do not normalize those exceptions in broad copy sweeps.
- Update [Widgetbook fixtures](../../lib/widgetbook) and literal assertions in
  [tests](../../test) with changed copy. Historical copy-audit CSVs may exist in
  local checkouts, but they are not required tracked files; these conventions
  remain the shared reference.

## Figma comparison

- Use widget-test capture for both Figma-to-Flutter and Flutter-to-Figma work.
  Register the needed screen/state as a deterministic scenario, reusing a
  Widgetbook fixture when available. It must not use production wallet data,
  storage, network, or Rust state.
- Match form factor, logical viewport, theme, locale, content, and component
  state. Capture with `scripts/figma-compare.sh widget --scenario <name> --theme
  <dark|light>`; mobile adds `--form-factor mobile`.
- Compare `content.widget.png` with the Figma capture side by side and, where
  useful, with an overlay/diff. Correct actionable differences and recapture.
  Widgetbook chrome is not app-content evidence.
- Desktop font-weight rasterization varies across Figma and OSes. Match the
  configured numeric weight; do not change it merely to force pixel parity.
  Still check family, size, line height, letter spacing, wrapping, and position.
- Add a missing deterministic scenario before falling back to a native app.
  Temporary production routes/provider overrides are a last resort and must
  be removed. Native capture is for OS chrome, real window restoration/insets,
  or material renderer differences the widget path cannot represent.
- Ignore `_MacOS Light Mode`/`_MacOS Dark Mode` presentation images and a `Controls`
  layer that is a sibling of `Window Contents`. In that structure, app content
  begins inside `Window Contents`, from `Trailing Pane` onward. Recreate native
  chrome only when it is explicitly part of the requested work.
- Keystone QR codes prioritize scanning: black square modules on white with an
  explicit quiet zone. Decorative QR styling must not weaken scan reliability.
- A comparison request does not authorize editing Figma. For an explicit Figma
  mutation, read [FIGMA-AI-FIX.md](../../FIGMA-AI-FIX.md) completely and follow
  its target, copy-only, and visual-verification workflow. That document also
  owns capture outputs, native restoration, and cleanup details.

## Focused verification

- [Design tokens](../../test/core/theme/design_tokens_test.dart) and
  [mobile lane sanity](../../test/mobile_lane_sanity_test.dart) verify mode use.
- [Mobile bottom inset](../../test/core/layout/mobile/mobile_bottom_safe_area_test.dart)
  verifies both OS geometries; [sync display progress](../../test/providers/sync_display_progress_provider_test.dart)
  verifies interpolation without replacing authoritative progress.
- Use a registered widget capture for visible changes. A native-window change
  additionally needs the real window surface. General commands are in
  [CONTRIBUTING.md](../../CONTRIBUTING.md#testing).
