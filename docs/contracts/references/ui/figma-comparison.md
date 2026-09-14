# Figma comparison

Use when comparing or implementing Figma designs, registering captures, or choosing visual evidence.

Implementation: [figma_compare_scenarios.dart](../../../../lib/figma_compare/figma_compare_scenarios.dart), [figma-compare.sh](../../../../scripts/figma-compare.sh).

- Use widget-test capture in both Figma/Flutter directions. Register a deterministic
  screen/state scenario, reusing a Widgetbook fixture where available. Exclude
  production wallet data, storage, network, and Rust state.
- Match form factor, logical viewport, theme, locale, content, and component
  state. Capture with `scripts/figma-compare.sh widget --scenario <name> --theme
  <dark|light>`; mobile adds `--form-factor mobile`.
- Compare `content.widget.png` with Figma side by side; add an overlay/diff where
  useful. Correct actionable differences and recapture.
  Widgetbook chrome is not app-content evidence.
- Desktop font rasterization varies across Figma and OSes. Match numeric weight
  rather than changing it for pixel parity; still check family, size, line height,
  letter spacing, wrapping, and position.
- Add a missing deterministic scenario before falling back to a native app.
  Temporary production routes/provider overrides are last resorts and must be
  removed. Native capture is for OS chrome, real window restoration/insets, or
  material renderer differences the widget path cannot represent.
- Ignore `_MacOS Light Mode`/`_MacOS Dark Mode` presentation images and a `Controls`
  sibling of `Window Contents`. App content then starts inside `Window Contents`
  at `Trailing Pane`. Recreate native chrome only when explicitly requested.
- Keystone QR codes prioritize scanning: black square modules on white with an
  explicit quiet zone. Decorative QR styling must not weaken scan reliability.
- Comparison does not authorize Figma edits. For explicit mutation, read
  [FIGMA-AI-FIX.md](../../../../FIGMA-AI-FIX.md) completely; follow its target, copy-only,
  visual-verification, capture-output, native-restoration, and cleanup workflow.

## Verification

- Use a registered widget capture for visible changes. A native-window change
  additionally needs the real window surface. General commands are in
  [CONTRIBUTING.md](../../../../CONTRIBUTING.md#testing).
