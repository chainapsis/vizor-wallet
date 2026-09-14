# Form factor and test lanes

Use when changing build-time token selection, mobile flags, or test-lane assumptions.

Implementation: [app_form_factor.dart](../../../../lib/src/core/layout/app_form_factor.dart), [app_typography.dart](../../../../lib/src/core/theme/app_typography.dart), [app_sizing.dart](../../../../lib/src/core/theme/app_sizing.dart).

- `VIZOR_FORM_FACTOR=desktop|mobile` is a build-time define; desktop is the
  default. Every mobile `run`, `build`, `test`, and `drive`, including release/CI,
  needs `--dart-define=VIZOR_FORM_FACTOR=mobile`. Release builds have no assertion guard.
- App code uses unsuffixed selectors (`AppTypography`, `AppInputSizing`, etc.)
  and `kAppFormFactor` for layouts. OS checks select OS behavior, not UI metrics.
  Const selectors let the unused mode be tree-shaken.
- New mode-dependent tokens use Desktop/Mobile const sets plus an unsuffixed
  selector. Spacing, radii, units, and window groups shared by both modes stay
  single-mode. Explicit `*Desktop`/`*Mobile` sets are for previews/tests inspecting
  or pinning a mode.
- A test binary has one form factor. Mobile-UI files start with
  `@Tags(['mobile'])`; [dart_test.yaml](../../../../dart_test.yaml) skips them in the
  default desktop lane. Run the mobile lane with all three flags:
  `fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`.
- `--run-skipped` lifts every skip in the selected tests. Do not use `skip:` to
  park broken mobile tests. Untagged tests must work in either lane: compare
  token constants rather than desktop-only numeric literals.
- The app entry point asserts platform/form-factor agreement in debug;
  Widgetbook allows mobile previews on desktop:
  `fvm flutter run -t lib/widgetbook.dart --dart-define=VIZOR_FORM_FACTOR=mobile`.

Startup routes and first-frame account/sync snapshot: [account bootstrap contract](../../domains/wallet/bootstrap.md).

## Verification

- [Design tokens](../../../../test/core/theme/design_tokens_test.dart) and
  [mobile lane sanity](../../../../test/mobile_lane_sanity_test.dart) verify mode use.
