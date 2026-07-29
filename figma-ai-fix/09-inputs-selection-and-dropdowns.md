# Inputs, selection, and dropdowns

Use the existing state/type properties for fields and selection controls. Preserve the Figma property's exact spelling when addressing an instance property programmatically.

## [Inputs](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=355-13933&m=dev)

Page ID: `355:13933`. Top-level children: 10. Reusable assets found: 3 component sets and 2 standalone components.

### Component sets

#### `Field` — `355:13970`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Label#355:20` | `BOOLEAN` | `true` |
| `Field Value#355:21` | `TEXT` | `1234` |
| `Placehodler#355:22` | `TEXT` | `Min. 8 chars and symbols` |
| `Show Leading Icon#355:23` | `BOOLEAN` | `true` |
| `Field Icon#355:24` | `INSTANCE_SWAP` | `410:45071` |
| `Input ZEC Unit#5372:15` | `BOOLEAN` | `false` |
| `Input $ Unit#5378:30` | `BOOLEAN` | `false` |
| `Show Input Error#5378:45` | `BOOLEAN` | `false` |
| `Show Currency Switch#5378:58` | `BOOLEAN` | `false` |
| `State` | `VARIANT` | `Default` |
| `Type` | `VARIANT` | `Primary` |

Variants (12):

| Variant | Node ID |
| --- | --- |
| `State=Default, Type=Primary` | `355:13932` |
| `State=Default, Type=Secondary` | `4363:120364` |
| `State=Error, Type=Primary` | `355:22867` |
| `State=Error, Type=Secondary` | `4363:120381` |
| `State=Hovered, Type=Primary` | `355:13992` |
| `State=Hovered, Type=Secondary` | `4363:120415` |
| `State=Focus, Type=Primary` | `371:29909` |
| `State=Focus, Type=Secondary` | `4363:120431` |
| `State=Active, Type=Primary` | `4040:77507` |
| `State=Active, Type=Secondary` | `4363:120448` |
| `State=Filled, Type=Primary` | `355:14026` |
| `State=Filled, Type=Secondary` | `4363:120465` |

#### `Text Area` — `355:23636`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Label#355:116` | `BOOLEAN` | `true` |
| `Field Value#355:117` | `TEXT` | `Zcash is a privacy-focused cryptocurrency which features an encrypted ledger using zero-knowledge proofs. Launched in October 2016, Zcash was developed by cryptographers at Johns Hopkins University and MIT and derived its code from bitcoin.` |
| `Placehodler#355:118` | `TEXT` | `Placeholder` |
| `Show Icon#355:119` | `BOOLEAN` | `true` |
| `Field Icon#355:120` | `INSTANCE_SWAP` | `344:8467` |
| `State` | `VARIANT` | `Default` |

Variants (6):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `355:24157` |
| `State=Hover` | `4040:77427` |
| `State=Active` | `4040:77533` |
| `State=Focus` | `355:20782` |
| `State=Filled` | `4040:77454` |
| `State=Error` | `355:24211` |

#### `Field Word` — `415:48466`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Index#417:135` | `TEXT` | `01` |
| `Word#417:140` | `TEXT` | `Cinnamon` |
| `State` | `VARIANT` | `Default` |

Variants (6):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `415:48465` |
| `State=Hover` | `415:48467` |
| `State=Active` | `417:50921` |
| `State=Filled` | `417:50932` |
| `State=Fcosed` | `417:50943` |
| `State=Error` | `417:50954` |

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `_Input Switch Currency` | `5378:138384` | — |
| `Field Title` | `355:14243` | — |

### Supporting showroom or source material

- `Showroom Dark` (`FRAME`)
- `Showroom Light` (`FRAME`)

## [Dropdown](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=2841-108859&m=dev)

Page ID: `2841:108859`. Top-level children: 4. Reusable assets found: 0 component sets and 1 standalone components.

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `_Accounts Dropdown` | `4058:153252` | — |

### Supporting showroom or source material

- `_Filters Dropdown` (`FRAME`)
- `Dropdown` (`FRAME`)

## [Radio / Checkbox](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=677-55548&m=dev)

Page ID: `677:55548`. Top-level children: 5. Reusable assets found: 4 component sets and 0 standalone components.

### Component sets

#### `Radio PFP` — `677:55553`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `677:55561` |
| `State=Selected` | `746:56306` |
| `State=Focsued` | `746:56315` |

#### `Radio Card` — `746:57484`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Leading Icon#746:72` | `BOOLEAN` | `true` |
| `Description#746:76` | `TEXT` | `Auto changes.` |
| `Show Description#746:80` | `BOOLEAN` | `true` |
| `Title#746:84` | `TEXT` | `System (Auto)` |
| `Show Badge#806:88` | `BOOLEAN` | `false` |
| `State` | `VARIANT` | `Default` |
| `Size` | `VARIANT` | `S` |

Variants (4):

| Variant | Node ID |
| --- | --- |
| `State=Default, Size=S` | `746:57482` |
| `State=Current, Size=S` | `746:57483` |
| `State=Selected (Focus), Size=S` | `4077:382537` |
| `State=Disabled, Size=S` | `806:59256` |

#### `Checkbox Card` — `5283:102612`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Leading Icon#746:72` | `BOOLEAN` | `true` |
| `Description#746:76` | `TEXT` | `Auto changes.` |
| `Show Description#746:80` | `BOOLEAN` | `true` |
| `Title#746:84` | `TEXT` | `System (Auto)` |
| `Show Badge#806:88` | `BOOLEAN` | `false` |
| `State` | `VARIANT` | `UNchecked` |
| `Size` | `VARIANT` | `S` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=UNchecked, Size=S` | `5283:102613` |
| `State=Checked, Size=S` | `5283:102625` |
| `State=Disabled, Size=S` | `5283:102649` |

#### `Checkbox` — `2779:48810`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `2779:48809` |
| `State=Check` | `2779:48808` |
