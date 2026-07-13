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

Existing Figma screens and components are immutable. Never rename, delete,
move, reparent, detach, resize, restyle, or otherwise mutate an existing source
node. Do not modify an existing component's variants, properties, auto-layout,
text, fills, effects, variables, styles, or main component. Shared assets that
could change an existing screen are also immutable.

After the user approves the target:

1. Copy only the approved screen or component into the
   [AI Test page](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=8001-32299&m=dev).
2. Apply every requested change only to that new copy and its descendants.
3. If a nested shared component must change, copy that component into the AI
   Test page too, then retarget only the copied screen's instance to the copied
   component. Never change the original main component.
4. If the requested change would require mutating anything outside the copied
   subtree, stop and ask the user before continuing.
5. Before reporting completion, verify that every mutated node is a descendant
   of the approved copy on the AI Test page and that all original nodes remain
   unchanged.

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
