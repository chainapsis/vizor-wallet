# Widgetbook

One entry per surface: inspect states with knobs and explore connected steps
inside the existing screen. Do not add a separate flow/playground entry.

## Run and explore

```bash
# Desktop tokens (default)
fvm flutter run -d macos -t lib/widgetbook.dart
# Mobile tokens on the same desktop host
fvm flutter run -d macos -t lib/widgetbook.dart --dart-define=VIZOR_FORM_FACTOR=mobile
```

- Browse `Screens > <feature> > <screen>`. Nest feature-specific elements under
  `Components` and overlays under `Modals`; shared primitives stay in the root
  `Components` gallery. Never keep aliases at old paths.
- Use knobs for initial state and the Theme addon for dark/light. Send, Receive,
  Pay, Swap and Settings support connected, in-memory interactions through their
  existing screen entry. Other previews may be static; check their notices.
- Results are simulated, not signed or broadcast. Settings are session-local;
  camera, device, security and external actions must be faked or visibly blocked.
  Send accepts fixture addresses (recipient knob/contact picker), not arbitrary
  addresses. Supported interactions can differ by lane.

## Compare desktop and mobile

`Layout` swaps widget classes, not build-time tokens. Live **Compare layouts**
is a structural preview: the opposite lane is labelled `approx.`. Use the mobile
build above for mobile typography and sizing. `WbLaneOnly` shows a run command
when a cross-lane render cannot work correctly.

Inspect exact typography and sizing in each lane's build. Figma linkage and
generated design-status documents are outside the current workflow.

## Authoring contracts

- Keep `build*UseCase(BuildContext)` names, files and signatures in
  `lib/widgetbook/*_use_cases.dart`: capture scenarios and tests import them.
  Prefer existing-fixture dispatch, then parameterized helpers with unchanged
  old-builder delegates, then new fixtures for missing states.
- Put knob-driven entries in `gallery/<feature>_gallery.dart`, exporting
  `<feature>GalleryNodes`. Keep `widgetbook_app.dart` to addons and the tree.
- Use `wbStateKnob` dropdowns with product-language `labelBuilder` labels and
  feature-prefixed gallery names/enums. Keep enums in the gallery file. Use one
  knob per independent axis; fixture dispatch may temporarily combine axes.
- Use one entry with `wbLayoutKnob`/`WbFrame` for dual-layout surfaces, not
  Desktop/Mobile entries. Register lane-specific knobs inside the layout branch
  and filter unavailable options. Single-layout surfaces need no Layout knob.
- Connected screens reuse real presentation widgets with isolated services.
  Carry inputs through review/back, reset to a fresh session, and label simulated
  outcomes. Never touch real wallet storage, signing or network services.
- Compare panes need lane-unique keys for root-element searches. Root-navigator
  sheets cover both panes. Scanner fakes are process-wide: install
  `WbFakeMobileScannerPlatform` and `WbFakeUrScanRustApi` before rendering, and
  configure through a layout-keyed mount driver, not competing lane builds.
- Static modal previews use a plain frame, not a live composer; use `maybePop()`
  rather than popping the Widgetbook root.

## Verify the changed surface

Run analysis and focused tests; check changed visuals with a capture or live
preview. Gallery tests use `test/widgetbook/support/wb_gallery_harness.dart`
and must distinguish every knob option. These untagged tests intentionally
preview both widget classes under desktop tokens; test mobile-token behavior
separately with the mobile lane.

```bash
fvm flutter analyze
fvm flutter test test/widgetbook/<changed_surface_test>.dart
fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/widgetbook/<changed_mobile_test>.dart
```
