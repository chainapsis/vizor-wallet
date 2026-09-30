# Onboarding design improvements

## Scope

Integrate the mobile onboarding designs through small pull requests targeting
`rowan/onboarding-design-integration`. Start from the current upstream base;
extract UI changes without importing the Gift Card feature branch history.

## Delivery slices

1. Mobile Welcome: video/poster assets, brief loop crossfades,
   adjusted gradient overlays, button tokens and interaction effects.
   Show the Gift Card button only before an account exists; keep redemption
   disconnected with a source TODO until the claim flow is finalized.
2. Mobile introduction: card, pattern, spacing, progress track, and actions.
3. Mobile import method selection.
4. Mobile hardware wallet selection.

Desktop Welcome, import/hardware selectors, introduction, and their navigation
changes are removed from this umbrella and preserved in an independent draft.
The original desktop entry paths remain available here. Shared button effects
and video dependencies stay because mobile Welcome uses them. Each mobile slice
includes focused tests and deterministic captures.

## Integration status (2026-10-01)

- The original mobile and desktop slices were merged through #794–#799.
- The mobile priority follow-up restores desktop files to the upstream base and
  removes desktop-only assets, routes, fixtures, and new tests.
- Desktop design work is preserved independently from `main`, including the
  desktop testnet import summary correction.
- Mobile progress refactoring follows the removal PR; its existing local work
  remains preserved while it is prepared without desktop changes.

## Deferred behavior

- Gift Card claim, account setup, recovery, and incoming-link routing.
- Gift Card progress and education banners on Home.
- Terms/Privacy footer links until the actual documents are available.
- Link Vizor Desktop on desktop, which has no supported entry flow.

## References

- [Mobile Welcome](https://www.figma.com/design/jhozt3bbbVYms9MkpGJgoI/Vizor--Design-System?node-id=8635-103040)
- [Accent hover](https://www.figma.com/design/jhozt3bbbVYms9MkpGJgoI/Vizor--Design-System?node-id=8668-27441)
- [Secondary hover](https://www.figma.com/design/jhozt3bbbVYms9MkpGJgoI/Vizor--Design-System?node-id=8668-27447)
