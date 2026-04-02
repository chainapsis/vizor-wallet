# Design System Document

This document outlines the core aesthetic and functional principles of the Zcash Wallet design system. It serves as the authoritative reference for all UI decisions — both human-authored and AI-assisted.

## Brand Identity

### Brand Personality

- **Voice**: Confident, minimal, trustworthy
- **Tone**: Calm authority — a vault, not a toy
- **3-word personality**: Secure. Clean. Precise.
- **Emotional goal**: The user should feel their funds are safe and in their control

### Design Principles

1. **Privacy is visible** — Shielded status is always surfaced, never hidden. The user should always know their privacy state.
2. **Quiet confidence** — No flashy gradients or neon accents. Strength comes from restraint, contrast, and whitespace.
3. **Information density over decoration** — Every pixel earns its place. No decorative cards, no filler icons.
4. **Progressive disclosure** — Show what matters now, reveal details on demand. Sync progress is ambient, not alarming.

## Color Palette

Built on the Stitch design system. Colors are tinted neutrals (cool blue-grey undertone, never pure gray) with a green accent for privacy/shielded indicators.

### Semantic Tokens

| Role | Token | Hex | Usage |
|------|-------|-----|-------|
| Surface | `surface` | `#F9F9F9` | Primary background |
| Surface Low | `surface-container-low` | `#F2F4F4` | Subtle containers, avatars |
| Surface High | `surface-container-high` | `#E4E9EA` | Elevated containers, inactive buttons |
| Surface Highest | `surface-container-highest` | `#DDE4E5` | Highest elevation containers |
| On Surface | `on-surface` | `#2D3435` | Primary text — tinted dark, not pure black |
| Primary | `primary` | `#5F5E5E` | Key interactive elements (Send button) |
| On Primary | `on-primary` | `#FAF7F6` | Text on primary — warm off-white, not pure white |
| Secondary | `secondary` | `#4D626C` | Supporting text, progress bars, muted actions |
| Tertiary | `tertiary` | `#1C6D25` | Privacy/shielded indicators, success, received tx |
| Outline | `outline` | `#757C7D` | Borders, disabled text, timestamps |
| On Surface Variant | `on-surface-variant` | `#5A6061` | Secondary text |
| Error | `error` | `#9F403D` | Destructive actions, failed transactions |

### Color Rules

- **No pure black** (`#000000`) or **pure white** (`#FFFFFF`). Use tinted neutrals.
- **60-30-10 distribution**: 60% neutral surfaces, 30% secondary/text, 10% tertiary accent.
- **Green = shielded/private.** This association must be consistent across every screen.
- **Contrast**: Body text on surface must exceed 4.5:1 (AA). `#2D3435` on `#F9F9F9` = ~13:1.

### Dark Mode (Future)

When implementing dark mode, use lighter surfaces for depth instead of shadows:
```
surface-1: tinted dark (~15% lightness, chroma 0.01)
surface-2: slightly lighter (~20%)
surface-3: lighter still (~25%)
```
Redefine semantic tokens only — primitive tokens stay the same.

## Typography

### Font Stack

| Role | Family | Fallback | Rationale |
|------|--------|----------|-----------|
| Headlines | `Manrope` | system-ui, sans-serif | Geometric sans-serif with strong presence. Bold, tight tracking for authority. |
| Body | `Inter` | system-ui, sans-serif | Optimized for screen readability at small sizes. |
| Labels | `Inter` | system-ui, sans-serif | Consistent with body for clarity in small UI elements. |

### Type Scale

| Role | Size | Weight | Letter Spacing | Line Height | Font |
|------|------|--------|----------------|-------------|------|
| Hero Balance | 56px | 800 (ExtraBold) | -2px | 1.0 | Manrope |
| Section Heading | 20px | 700 (Bold) | -0.3px | 1.2 | Manrope |
| Body | 15px | 700 | 0 | 1.4 | Manrope |
| Body Secondary | 14px | 400-500 | 0 | 1.5 | Inter |
| Label (uppercase) | 11px | 600-700 | 1.5px | 1.0 | Inter |
| Caption | 10px | 700 | 1.5px | 1.0 | Inter |

### Typography Rules

- **Max 3 weights per screen**: Regular (400), Semibold (600-700), ExtraBold (800).
- **Uppercase labels** always pair with wide letter-spacing (1.5px+) and small size (10-11px).
- **Headlines use tight tracking** (-0.3 to -2px). Body text uses default or slightly loose tracking.
- **Minimum touch-target text**: 14px for anything interactive.
- **Measure**: Body text blocks should not exceed 65 characters per line.

## Spacing

### Base Unit: 4pt

All spacing values are multiples of 4. The 4pt grid allows finer control than 8pt while maintaining visual rhythm.

### Scale

| Token | Value | Usage |
|-------|-------|-------|
| `2xs` | 4px | Tight icon-text gap |
| `xs` | 8px | Related element gap (icon + label in nav) |
| `sm` | 12px | Button gap, grid gap between action buttons |
| `md` | 16px | Standard internal padding |
| `lg` | 20px | List item internal gap (icon to text) |
| `xl` | 24px | Screen horizontal padding, section internal padding |
| `2xl` | 32px | Section bottom margin |
| `3xl` | 40px | Major section separation (activity header from buttons) |
| `4xl` | 48px | Hero section bottom padding |

### Spacing Rules

- **Screen horizontal padding**: 24px (consistent across all screens).
- **Vertical rhythm**: Section gaps should feel generous (40-48px). Internal gaps should feel tight (8-16px).
- **Use `gap`** for sibling spacing, not margins, when possible.
- **Related elements group tightly** (8-12px). **Distinct sections separate generously** (40-48px).

## Roundedness

Minimal roundedness — sharp enough to feel precise, soft enough to feel approachable.

| Element | Radius | Rationale |
|---------|--------|-----------|
| Action buttons | 8px | Subtle curve, not pill-shaped |
| Bottom nav active state | 12px | Slightly softer for selection indicator |
| Badges (shielded label) | 20px | Pill shape for small inline badges |
| Avatar circles | 50% | Full circle for sync status icons |
| Progress bars | 4px | Barely rounded |

### Roundedness Rules

- **No default large radius on everything.** Each element's radius is intentional.
- **Cards are discouraged.** Not every content group needs a container with rounded corners and a shadow. Use spacing and typography hierarchy to create grouping instead.

## Shadows & Elevation

- **Prefer surface color changes over shadows** for elevation hierarchy.
  - Level 0: `surface` (#F9F9F9)
  - Level 1: `surface-container-low` (#F2F4F4)
  - Level 2: `surface-container-high` (#E4E9EA)
- **No drop shadows on cards.** If a shadow is clearly visible, it is too strong.
- **Bottom nav** uses background opacity (0.9) for subtle layering, not shadow.

## Motion (Future)

When adding animations:

| Duration | Use |
|----------|-----|
| 100-150ms | Button press feedback, toggle |
| 200-300ms | State changes (menu, tooltip) |
| 300-500ms | Layout changes (drawer, modal) |

### Motion Rules

- **Default easing**: `Curves.easeOutQuart` (confident, not bouncy).
- **Never use bounce or elastic easing.** This is a financial app.
- **Only animate opacity and transform** where possible.
- **Sync progress bar**: Use slow ease-out transitions (1000ms) to smooth between batch updates.

## Interaction Patterns

### Touch Targets

- Minimum 48x48px for all interactive elements.
- Bottom nav items include generous padding (16px horizontal, 8px vertical) beyond the icon.

### Action Hierarchy

- **Primary action** (Send): Filled button with `primary` background, `on-primary` text.
- **Secondary action** (Receive): Surface button with `surface-container-high` background, `on-surface` text.
- **Tertiary action** (View All): Text-only link with `secondary` color, uppercase, wide tracking.

### Sync Status

Sync is **ambient, not alarming**:
- Displayed as a list item in Recent Activity, not a modal or banner.
- Progress bar is thin (4px height), secondary color, 2/3 width — understated.
- Percentage shown as small uppercase label next to "Syncing..." text.
- When complete: single check icon + "Fully synced" text. No celebration animation.

## Anti-Patterns

Things this design system explicitly avoids:

- **Pure black or pure white** — All neutrals are tinted (cool blue-grey undertone)
- **Purple-to-blue gradients** — No gradients anywhere
- **Neon accents on dark backgrounds** — Not a crypto-bro aesthetic
- **Glassmorphism** — No frosted glass effects
- **Cards nested in cards** — Flat hierarchy, use spacing instead
- **Identical card grids** — (icon + heading + text, repeated 3x) — banned
- **Decorative icons** — Every icon has a functional purpose
- **Bounce/elastic animations** — This is a financial tool, not a game
- **Centered everything** — Left-align text in lists and content areas
- **Modals for non-critical flows** — Use inline UI or navigation instead
- **Gradient text** — Never
- **Sparklines as decoration** — Only show charts when data is meaningful

## Component Reference

### Top Bar
- Height: ~56px (16px vertical padding)
- Left: Shield icon (22px) + "Zcash" wordmark (Manrope 800, 20px, -0.5 tracking)
- Right: QR scanner icon button

### Hero Balance
- "SHIELDED BALANCE" badge: pill shape, tertiary/10% background, 10px uppercase label
- Balance: Manrope 800, 56px, -2px tracking
- "ZEC" unit: Manrope 600, 28px, secondary color

### Action Buttons
- 2-column grid, 12px gap
- Height: ~52px (16px vertical padding)
- Icon (20px) + uppercase label (11px, 2px tracking)
- Send = filled primary, Receive = surface-container-high

### Activity List
- Item height: ~48px icon + content
- Icon: 48px circle, surface-container-low background
- Text: Manrope 700 15px title, Inter metadata
- Spacing: 20px gap between icon and text, 32px between items

### Bottom Navigation
- Background: surface at 90% opacity
- 3 items: Wallet, History, Settings
- Active: surface-container-high pill + on-surface color
- Inactive: outline color
- Icon: 24px, Label: 11px uppercase, 1.5px tracking
