> **Scope gate:** If the user has not explicitly asked you to modify a Figma
> file or design, stop here. You do not need to read any further.

# Figma AI Fix

This documentation covers only the Vizor design system in
[Vizor Design System AI Test](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?m=dev).
It does not document product flows, feature mockups, WIP screens, QA pages, or
implementation behavior.

The topic documents under `figma-ai-fix/` remain design-system-only. The
workflow below governs how product screens are identified and safely copied
when the user explicitly requests a Figma change; it does not add those product
screens to the design-system documentation.

## Screen matching and approval gate

Unless the user specifies another source, find the Figma screen corresponding
to the code in
[Vizor Design System AI Test](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=5572-69081&m=dev).

If no confident match can be found in that default location, do not force a
match, select a merely similar screen or component, or expand the search to
other Figma pages without the user's direction. Report that no confident match
was found, summarize the location and candidates checked, and wait for the
user to provide another location or target before copying or editing anything.
Treat an uncertain candidate the same as no match.

Treat every match as a candidate until the user approves it. Before copying or
editing anything:

1. Report the Figma page name, screen or component name, node ID, direct URL,
   and the concrete reason it matches the code.
2. If more than one candidate is plausible, report the candidates instead of
   choosing one silently.
3. Explicitly tell the user that nothing has been copied or edited yet and ask
   whether the identified screen or component is the intended target.
4. Wait for explicit approval. Do not copy or edit the candidate before that
   approval.

Use this confirmation format:

```markdown
I found the likely matching Figma screen:

- Page:
- Screen/component:
- Node ID:
- URL:
- Match rationale:

I have not copied or edited anything yet. Is this the correct screen/component
to use?
```

## Copy-only editing policy

The Vizor design system itself is strictly read-only and must never be
modified. This prohibition includes every design-system page, component
master, component set, variant, variable, style, token, and shared asset. It
still applies when changing the design system would appear to be the easiest
way to satisfy the request.

Existing Figma screens and components are immutable. Never rename, delete,
move, reparent, detach, resize, restyle, or otherwise mutate an existing source
node. Do not modify an existing component's variants, properties, auto-layout,
text, fills, effects, variables, styles, or main component. Shared assets that
could change an existing screen are also immutable.

After the user approves the target:

1. Copy only the approved screen or component into the
   [AI Test page](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=8001-32299&m=dev).
2. Apply every requested change only to that new copy and its descendants.
   When modifying or adding a screen, reuse the existing Vizor design-system
   component instances, variables, styles, tokens, and layout patterns as much
   as possible. Do not recreate an available design-system asset with detached
   or ad-hoc layers.
3. If a nested shared component must change, copy that component into the AI
   Test page too, then retarget only the copied screen's instance to the copied
   component. Never change the original main component.
4. If the requested change would require mutating anything outside the copied
   subtree, stop and ask the user before continuing.
   If a required asset does not exist in the design system, also stop and ask
   the user rather than adding it to or modifying the design system.
5. Before reporting completion, verify that every mutated node is a descendant
   of the approved copy on the AI Test page and that all original nodes remain
   unchanged.

## Code-to-Figma visual parity workflow

Use this workflow when the user explicitly asks to apply a design change that
already exists in Flutter code to Figma. Complete the screen-matching,
approval, and copy-only steps above before starting this workflow. The running
Flutter implementation is the visual reference; never change production
styling or layout temporarily to make the reference resemble the Figma copy.

### 1. Establish an isolated, reproducible runtime reference

1. Record the starting Git status and preserve all pre-existing user changes.
2. Determine which form factors the code change affects. Validate both desktop
   and mobile when both are affected; otherwise validate only the affected or
   explicitly requested form factor.
3. Use `lib/figma_compare.dart` instead of the production entry point or
   Widgetbook chrome whenever the required state is registered in
   `lib/figma_compare/figma_compare_scenarios.dart`. This entry point reproduces
   the production desktop window bootstrap but skips Rust, wallet, storage,
   sync, and network initialization.
4. If the required state is not registered, prefer adding a deterministic
   dev-only scenario that reuses an existing Widgetbook fixture. A scenario
   must not depend on production wallet data, storage, network, or Rust state.
   Temporary production routing, bootstrap, or provider changes are a last
   resort and must still be removed before completion.
5. Keep comparison fixtures and any temporary routing or mock changes isolated
   from production design changes. Do not alter the target's visual properties,
   component structure, text, layout, or tokens merely to influence the
   comparison.
6. Fix the content, loading or error state, theme, locale, text scale, and any
   time-dependent data so repeated captures show the same screen.

### 2. Capture the Flutter reference on each required form factor

Always use `fvm flutter`, never bare `flutter`.

- **Desktop:** Run the macOS desktop app without a mobile form-factor define,
  using the comparison entry point and a registered deterministic scenario:

  ```bash
  fvm flutter run -d macos -t lib/figma_compare.dart \
    --dart-define=FIGMA_COMPARE_SCENARIO=pay-recipient \
    --dart-define=FIGMA_COMPARE_THEME=dark \
    --dart-define=FIGMA_COMPARE_OUTPUT=pay-recipient/content.png
  ```

  A relative output path is written below the sandbox's system temporary
  directory, normally
  `~/Library/Containers/com.keplr.vizor/Data/tmp/vizor-figma-compare/`.
  The command prints both resolved paths. It produces:

  - `content.png`: the Flutter app-content render at a deterministic 1x logical
    pixel ratio. Use this as the primary Figma parity reference.
  - `content.window.png`: the exact native NSWindow at its backing pixel ratio,
    including the macOS titlebar and traffic lights. Use this only to verify the
    production window shell, sizing, and native insets.

  The macOS capture transaction records the current window and foreground-app
  state. If the comparison window is minimized or hidden, it deminiaturizes and
  activates the window, makes it key and visible, waits for Flutter and privacy
  state to settle, captures the exact window ID, then restores the previous
  minimized/hidden state and foreground app. Do not bypass the production
  privacy overlay. `FIGMA_COMPARE_START_MINIMIZED=true` exists only to verify
  this restoration behavior; it is not needed for normal captures.

  macOS 14 and newer use ScreenCaptureKit; macOS 11-13 use the restored-window
  Core Graphics compatibility path. If Screen Recording permission is
  requested, grant it before treating the native-window capture as evidence.
- **Mobile:** Boot an iOS Simulator and run the app with
  `--dart-define=VIZOR_FORM_FACTOR=mobile` and a scenario explicitly marked as
  mobile-capable. Record the simulator device, OS, orientation, and viewport,
  then capture the same target state with deterministic data. Use
  `xcrun simctl io <device-id> screenshot <output.png>` for the simulator
  screenshot.

Do not treat operating-system chrome as app UI. Crop or otherwise normalize
captures to compare the same app-content bounds. Follow the repository's Figma
layer-interpretation rules for presentation-only macOS backgrounds and window
controls.

### 3. Capture and compare the Figma copy

1. Set the copied Figma screen to the same viewport or frame dimensions,
   theme, locale, content, and component state as the Flutter reference.
2. Capture only the modified copy on the AI Test page. Never use a modified
   original screen or design-system asset as comparison evidence.
3. Compare the Flutter and Figma captures side by side and, when practical,
   with a transparent overlay or image-difference view.
4. Check at least frame and container dimensions, layout, spacing, alignment,
   typography, colors, borders, effects, icons, images, component states,
   clipping, wrapping, and overflow.
5. Treat correctable layout, sizing, color, asset, and state differences as
   mismatches. Ignore only unavoidable rendering noise such as minor native
   font rasterization or operating-system chrome that is outside the app UI.

### 4. Iterate until no actionable difference remains

When a mismatch is found, modify only the approved copy on the AI Test page,
capture that copy again, and repeat the comparison against the Flutter
reference. Do not impose an arbitrary iteration limit. Continue until every
required desktop and mobile capture is effectively identical and no
correctable difference remains.

The initial target approval covers visual corrections within the approved
copied subtree. Stop and ask the user again if the target or requested scope
changes, an edit would escape that subtree, or the work requires a missing or
modified design-system asset.

### 5. Clean up and report completion

Before reporting completion:

1. Remove every temporary route, bootstrap override, dependency override,
   mock, and other one-off capture-only code change. Never commit those
   temporary changes. The permanent comparison entry point and reusable,
   deterministic scenario registry are repository tooling and are not removed.
2. Confirm that the Git state has returned to its starting condition apart
   from pre-existing user changes and any separately authorized repository
   documentation changes.
   Remove generated comparison artifacts with:

   ```bash
   rm -rf "$HOME/Library/Containers/com.keplr.vizor/Data/tmp/vizor-figma-compare"
   ```

   Generated captures must never be committed.
3. Confirm that all Figma mutations are descendants of the approved AI Test
   copy and that the source screen, all other existing screens, and the entire
   design system remain unchanged.
4. Report the source-node URL, copied-node URL, validated platforms and
   device/window configuration, tested UI states, comparison evidence,
   mismatches corrected during iteration, and any remaining unavoidable
   rendering-only differences.

Report success only after all required form factors meet these completion
conditions. If parity cannot be reached, report the concrete blocker instead
of claiming completion.

Read [source and scope](figma-ai-fix/00-source-and-scope.md) first. Then read
only the topic documents needed for the requested Figma change.

| Document | Purpose and contents |
| --- | --- |
| [00-source-and-scope.md](figma-ai-fix/00-source-and-scope.md) | Source file, authoritative design-system page set, exclusions, naming rules, and inventory totals. |
| [01-color-system.md](figma-ai-fix/01-color-system.md) | Dark/Light color variables: primitives, semantic roles, and OS utility colors. |
| [02-sizing-and-layout.md](figma-ai-fix/02-sizing-and-layout.md) | Desktop/Mobile sizing variables for units, spacing, radii, windows, and component dimensions. |
| [03-typography.md](figma-ai-fix/03-typography.md) | Desktop/Mobile font variables, local text styles, and the Paragraph component. |
| [04-effects-and-grid.md](figma-ai-fix/04-effects-and-grid.md) | Local effect styles and the desktop layout grid. |
| [05-brand-and-app-icon.md](figma-ai-fix/05-brand-and-app-icon.md) | Vizor identity, logos, symbols, 3D marks, and app-icon assets. |
| [06-icons.md](figma-ai-fix/06-icons.md) | Complete local icon-component inventory and exact node IDs. |
| [07-illustrations-assets-and-placeholders.md](figma-ai-fix/07-illustrations-assets-and-placeholders.md) | Illustrations, PFPs, full-page states, user imagery, and placeholders. |
| [08-actions-status-and-feedback.md](figma-ai-fix/08-actions-status-and-feedback.md) | Buttons, badges, chips, tooltips, and toasts with properties and variants. |
| [09-inputs-selection-and-dropdowns.md](figma-ai-fix/09-inputs-selection-and-dropdowns.md) | Fields, text areas, dropdowns, radio controls, and checkboxes. |
| [10-navigation-tabs-and-modals.md](figma-ai-fix/10-navigation-tabs-and-modals.md) | Sidebar/navigation assets, tabs, and modal families. |
| [11-data-cards-lists-and-tables.md](figma-ai-fix/11-data-cards-lists-and-tables.md) | Asset/table building blocks, context menus, cards, pagination, and lists. |
| [12-swap-components.md](figma-ai-fix/12-swap-components.md) | Design-system components from the Swap UI page; no product-flow behavior. |
| [13-platform-and-local-utilities.md](figma-ai-fix/13-platform-and-local-utilities.md) | Scrollbars, macOS presentation utilities, keyboards, and local organizational helpers. |

The live Figma file is the source of truth. If a documented value or node no
longer matches Figma, re-read the relevant design-system page instead of
guessing or copying a product-screen override.
