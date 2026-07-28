# Ironwood migration status carousel

Status: Approved and implemented

Surface: Desktop migration status

Figma file: `jhozt3bbbVYms9MkpGJgoI`

## 1. Goal

Add one reusable core carousel, register its migration variants in Widgetbook,
and use it at the bottom of the desktop Ironwood migration status surface.

- During migration preparation, show the three preparation tips in the order
  specified below.
- During migration in progress, show the three migration tips in the order
  specified below.
- Advance automatically on a fixed interval.
- Allow deliberate pointer/touch dragging in either direction.
- Match the Figma viewport, side fades, card geometry, typography, icons, and
  page indicator.
- Keep the carousel shell and interaction model reusable; migration-specific
  copy and artwork are supplied as immutable item data.
- Keep the carousel informational. It must not read or mutate migration
  progress, scheduling, signing, or transaction state.

## 2. Evidence boundary

### Figma nodes used for the shell

| State | Screen | Carousel shell |
|---|---|---|
| Preparation | `7279:7907` | `7298:8443` |
| Migration in progress | `7152:57747` | `7298:8480` |

The two screen nodes establish the desktop placement. The two carousel nodes
establish the viewport, mask, track, and indicator. They use the same shell.

The screen frames also contain macOS presentation layers. `_MacOS Light Mode`,
`_MacOS Dark Mode`, and the `Controls` sibling of `Window Contents` are not app
UI and are excluded from implementation.

### Figma nodes used for card content

The card nodes explicitly supplied for this task are authoritative for copy,
icon, and order.

| State | Supplied node | Effective card node |
|---|---|---|
| Preparation 1 | `7298:8453` | `7298:8453` |
| Preparation 2 | `7298:8452` | `7298:8458` |
| Preparation 3 | `7298:8463` | `7298:8463` |
| Migration 1 | `7296:8699` | `7296:8699` |
| Migration 2 | `7296:8698` | `7296:8704` |
| Migration 3 | `7296:8709` | `7296:8709` |

`7298:8452` and `7296:8698` are `Slides` containers, not card 2. Their centered
children are the effective card nodes listed above.

The preparation screen sample contains an older or alternate third-card copy.
That conflict is resolved in favor of the individually linked card nodes,
because the request explicitly defines those nodes as the ordered card set.

### Motion evidence

Figma motion context is empty for both screen nodes. Figma therefore specifies
the static appearance, but not autoplay timing, transition duration, easing,
looping, drag threshold, or pause behavior. Section 8 clearly marks the proposed
runtime contract that still requires approval.

## 3. Placement and geometry

The current desktop status content is a `420 × 656` surface. Coordinates below
are relative to that content surface.

| Element | Geometry |
|---|---|
| Carousel | `560 × 116`, `x=-70`, `bottom=16` (`y=524` at 656px height) |
| Masked viewport | `560 × 100`, `x=0`, `y=0` |
| Card | `396 × 74` |
| Center card | `x=82`, vertically centered in the 100px viewport |
| Card gap | `19px` |
| Card pitch | `415px` |
| Visible neighbor width | `63px` on each side |
| Indicator gap below viewport | `10px` |
| Indicator row | `88 × 6`, horizontally centered |
| Bottom inset | `16px` |

The carousel is 140px wider than the 420px content surface and extends 70px on
both sides. The status content must allow this intentional overflow while the
trailing pane remains the outer clipping boundary. The current status surface
is fixed at `420 × 656`; implementation should still anchor the carousel with
`bottom: 16` so the Figma bottom inset remains explicit if that surface later
becomes height-responsive.

A `560px` page viewport with page extent `415px` maps to a viewport fraction of
`415 / 560 = 0.7410714286`. Each page slot then needs `9.5px` horizontal inset
to produce a `396px` card and the exact `19px` inter-card gap.

## 4. Fade mask

The side treatment is one alpha mask over the complete slide viewport, not
per-card opacity and not a background-colored overlay.

- Mask size: `560 × 100`
- Direction: horizontal
- Alpha stops:
  - `0.00`: transparent
  - `0.15`: opaque
  - `0.85`: opaque
  - `1.00`: transparent
- Fade width: `84px` on each side
- The full `63px` visible portion of each neighboring card sits inside the
  fade.

Flutter mapping: a clipped viewport containing a `ShaderMask` with
`BlendMode.dstIn`. Applying opacity to individual cards would produce visible
steps during dragging and would not match Figma.

## 5. Shared card

| Property | Value | Project mapping |
|---|---|---|
| Size | `396 × 74` | Carousel-local fixed geometry |
| Background | `#1B1F1F` | `colors.background.ground` |
| Radius | `24px` | `AppRadii.large` |
| Border / shadow | None | None |
| Content row | `364 × 42`, at `x=16`, `y=16` | Fixed card padding |
| Horizontal padding | `16px` | `AppSpacing.sm` |
| Icon-to-copy gap | `8px` | `AppSpacing.xs` |
| Icon tile | `32 × 32` | Fixed carousel geometry |
| Icon tile radius | `8.875px` | Carousel-local Figma value |
| Copy area | `324 × 42` | Remaining row width |
| Copy | Geist Regular, `14/21`, `-0.21px` | `AppTypography.bodyMedium` |
| Copy color | `#FFFFFF` | `colors.text.accent` |
| Copy lines | Exactly two for the approved English strings | No ellipsis |

The icon is decorative. The whole card exposes one semantic label containing
the full copy and its logical position, such as “Migration tip 2 of 3”.

## 6. Ordered card data

### Preparation

1. History
   - Copy: “Once preparation finishes, your migration will begin automatically
     after a long intentional delay.”
   - Tile: `#9667E2`
   - Glyph: `AppIcons.history`, white, optical size `15 × 15` in a `20 × 20`
     slot
2. Wallet
   - Copy: “We’re organizing your balance into common-sized parts. This makes
     your migration harder to link.”
   - Tile: `#00A460`
   - Glyph: `AppIcons.wallet`, white, optical size `15 × 12` in a `20 × 20`
     slot
3. Multiple rounds
   - Copy: “We may have to do multiple rounds of note splitting depending on
     your balance.”
   - Tile: `#B90A4A`
   - Image: `assets/illustrations/ironwood_migration_expect_running.png`,
     full-bleed `32 × 32`, clipped by the tile

### Migration in progress

1. Pause and resume
   - Copy: “You can close Vizor anytime. Migration will pause, and you can
     restart it when you return.”
   - Tile: `#9667E2`
   - Glyph: Figma pause glyph, white, in a `20 × 20` slot
2. Block timing
   - Copy: “Each Zcash block takes about 75 seconds to create, but timing can
     vary with network conditions.”
   - Tile: `#00A460`
   - Glyph: `AppIcons.migrationTimer`, white, in a `20 × 20` slot
   - `75` must come from the existing migration seconds-per-block source of
     truth rather than a second hard-coded timing constant.
3. Keep Vizor running
   - Copy: “Keep Vizor running and the migration will automatically run in the
     background.”
   - Tile: `#B90A4A`
   - Image: `assets/illustrations/ironwood_migration_expect_running.png`,
     full-bleed `32 × 32`, clipped by the tile

The Figma helmet PNG and the existing repository asset have identical SHA-256
content, so no new raster asset is required. Existing history and wallet SVGs
use the same paths as Figma and can be tinted through `AppIcon`. The pause glyph
does not currently have an exact typed repository asset and should be added from
the supplied Figma vector during implementation.

## 7. Page indicator

- Row: `88 × 6`
- Gap: `4px`
- Inactive segment: `20 × 6`, `#393E3E`
- Active segment: `40 × 6`, `#F7F7F7`
- Radius: `999px` / stadium

Figma does not show a click or tap interaction on the indicator. The proposed
implementation keeps it presentational; navigation is through autoplay,
dragging, and keyboard arrow actions when the carousel has focus.

## 8. Approved runtime contract

These values are approved implementation decisions, not Figma facts.

| Behavior | Proposal |
|---|---|
| Initial page | Start with card 1 |
| Autoplay interval | 5 seconds of dwell time |
| Transition | 400ms, `easeInOutCubic` |
| Looping | Continuous in both directions |
| Manual interaction | Horizontal pointer/touch drag |
| Drag start | Pause autoplay immediately |
| Drag settle | Restart a full 5-second dwell |
| Indicator update | Change the active segment after page settle |
| Hover / focus | Pause autoplay so desktop users can read |
| Route hidden / app inactive | Pause autoplay |
| Reduced motion | Disable autoplay and indicator width animation; retain manual paging |
| Keyboard | Previous/next with left/right arrows while focused |
| Indicator | Visual only; no separate 44px click targets |

The timer and page controller must be disposed with the widget. Rebuilds caused
by block height or migration progress must not reset the selected page or create
additional timers. A change between preparation and migration-in-progress is
not an ordinary progress rebuild: it resets to that phase's card 1 and starts a
fresh dwell interval.

## 9. State mapping

The carousel is selected by the existing presentation state, not by a new Rust
or provider state.

Apply these conditions in order:

1. If `action != _StatusAction.none`, hide the carousel.
2. Otherwise, if `_shouldShowPreparingStatusContent(...) == true`, show the
   preparation cards.
3. Otherwise, show the migration-in-progress cards.

| Existing UI state | Carousel |
|---|---|
| `_StatusAction.needsInput` | Hidden; signing card and CTA keep the bottom area |
| `_StatusAction.retry` | Hidden; recovery action takes priority |
| Complete / `_StatusAction.backHome` | Hidden; completion surface owns the screen |
| Passive preparation | Preparation cards |
| Passive migration progress | Migration-in-progress cards |

This mapping avoids overlapping the existing Keystone signing card at `y=511`
and keeps action-required/error states focused on the user action. Figma only
provides carousel evidence for passive preparation and passive migration
progress states.

## 10. Acceptance criteria

### Visual

- The centered card is `396 × 74` at the exact desktop location.
- Neighbor cards expose `63px` before the mask is applied.
- Side fading is continuous while dragging and uses the four Figma alpha stops.
- Card radius, padding, icon tile, copy metrics, wrapping, and colors match the
  linked card nodes.
- The indicator uses `40/20/20` widths for the active first page and updates
  correctly for every settled page.
- Both preparation and migration use the same shell component.

### Behavior

- The carousel advances only after the approved dwell interval.
- Dragging left or right settles to the corresponding logical card and restarts
  the dwell timer.
- Repeated auto and manual paging loops without an end stop.
- Hover, focus, inactive lifecycle, and reduced-motion behavior follow the
  approved runtime contract.
- No timer fires after disposal.
- A migration-state rebuild preserves the current logical page.
- A preparation-to-migration phase change resets to migration card 1 and starts
  a fresh dwell.

### Regression

- Preparation summary metrics remain visible.
- Passive migration summary metrics remain visible.
- Keystone signing, retry, and completion surfaces retain their existing bottom
  content without overlap.
- Carousel display has no effect on migration computation or persistence.
