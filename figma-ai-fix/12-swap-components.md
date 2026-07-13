# Swap components

This document covers only reusable assets on the Swap UI design-system page. It intentionally excludes swap business logic, routing, transaction states outside the component variants, and product-screen layouts.

## [Swap UI](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=2788-43761&m=dev)

Page ID: `2788:43761`. Top-level children: 7. Reusable assets found: 6 component sets and 1 standalone components.

### Component sets

#### `Swap Card` — `2771:37005`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `2771:36919` |
| `State=Active` | `2771:37006` |

#### `Swap Currency Picker` — `2771:37425`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Type` | `VARIANT` | `Non-Selectable` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `Type=Non-Selectable` | `2771:37424` |
| `Type=Slectable` | `2771:37433` |

#### `Slippage` — `2774:37766`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (4):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `2774:37760` |
| `State=Hover` | `2774:37772` |
| `State=Destructive` | `2774:37767` |
| `State=Destructive Hover` | `2774:37876` |

#### `_Swap Card Content_` — `2777:38264`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Type` | `VARIANT` | `Receive ZEC` |

Variants (4):

| Variant | Node ID |
| --- | --- |
| `Type=Receive ZEC` | `2777:38263` |
| `Type=Pay Zec` | `2777:38265` |
| `Type=Pay Crypto` | `2779:38470` |
| `Type=Receive Crypto` | `2783:61578` |

#### `_Swap Card Address` — `2779:38543`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `2779:38504` |
| `State=Hover` | `2779:38544` |
| `State=Set` | `2779:38549` |

#### `_Swap Route` — `2915:220637`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Step` | `VARIANT` | `1` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `Step=1` | `2915:220192` |
| `Step=2` | `2915:220638` |

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `_Swap near Logo` | `2872:159543` | — |
