# Data, cards, lists, and tables

This group contains reusable asset rows, menus, pagination, card families, review information, and list content. Keep the distinction between public components and underscore-prefixed internal building blocks.

## [Assets / Tables](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=377-31688&m=dev)

Page ID: `377:31688`. Top-level children: 22. Reusable assets found: 9 component sets and 4 standalone components.

### Component sets

#### `Asset Image` — `333:7271`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Asset Sub Icon#400:128` | `BOOLEAN` | `false` |
| `Icon#1510:4` | `INSTANCE_SWAP` | `366:27297` |
| `Show PFP Chain#2864:24` | `BOOLEAN` | `false` |
| `Show Network#2870:31` | `BOOLEAN` | `false` |
| `Type` | `VARIANT` | `Default` |

Variants (6):

| Variant | Node ID |
| --- | --- |
| `Type=Default` | `4046:88839` |
| `Type=Simple Icon` | `4231:67999` |
| `Type=Swap Progress` | `2814:85472` |
| `Type=Sub Tx` | `2814:83819` |
| `Type=PFP` | `2011:32645` |
| `Type=Currency` | `2771:35839` |

#### `Content Line` — `344:8468`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Left Left Label#344:11` | `BOOLEAN` | `true` |
| `Show Right Icon#344:12` | `BOOLEAN` | `false` |
| `Show Left Icon#344:13` | `BOOLEAN` | `false` |
| `Left Icon#344:14` | `INSTANCE_SWAP` | `333:7316` |
| `Right Icon#344:15` | `INSTANCE_SWAP` | `333:7316` |
| `State` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `398:40639` |
| `State=Hover` | `1510:31381` |
| `State=Focus Keyboard` | `677:54568` |

#### `_Divider` — `4360:100898`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Type` | `VARIANT` | `Default` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `Type=Default` | `1183:17856` |
| `Type=Expand` | `4360:100899` |

#### `_Page Content` — `1433:28031`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Icon#1439:0` | `INSTANCE_SWAP` | `107:2422` |
| `Type` | `VARIANT` | `Text` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `Type=Text` | `1433:27988` |
| `Type=Icon` | `1433:28032` |

#### `_Page Item` — `1439:28071`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (4):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `1439:28080` |
| `State=Hover` | `1439:28130` |
| `State=Focused` | `1510:30416` |
| `State=Current` | `1510:30411` |

#### `_Asset Left` — `392:40268`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Left Leading Icon#398:124` | `BOOLEAN` | `false` |
| `Property 1` | `VARIANT` | `Default` |

Variants (1):

| Variant | Node ID |
| --- | --- |
| `Property 1=Default` | `392:40267` |

#### `Context Menu` — `2011:33232`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `2011:33231` |
| `State=Hover` | `2011:33233` |
| `State=Open` | `2011:33256` |

#### `Context Menu Item` — `2071:42249`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `2011:33186` |
| `State=Hover` | `2071:42250` |

#### `_Network` — `2771:36893`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Network` | `VARIANT` | `USDC` |

Variants (5):

| Variant | Node ID |
| --- | --- |
| `Network=USDC` | `2771:36892` |
| `Network=ZEC` | `2771:36891` |
| `Network=ETH` | `2865:120648` |
| `Network=NEAR` | `2865:120663` |
| `Network=Solana` | `2865:120666` |

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `Context Menu` | `2011:33204` | — |
| `Table Paginantion` | `1439:28156` | — |
| `_Asset Right` | `398:40774` | — |
| `Context Menu Divider` | `2011:33208` | — |

### Supporting showroom or source material

- `Showroom Dark` (`SECTION`)
- `Showroom Light` (`SECTION`)
- `ZCASH` (`FRAME`)
- `ETH` (`FRAME`)

## [Cards](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=400-42053&m=dev)

Page ID: `400:42053`. Top-level children: 15. Reusable assets found: 7 component sets and 3 standalone components.

### Component sets

#### `_Pagination Item` — `400:42495`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Active` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `State=Active` | `400:42483` |
| `State=Default` | `400:42499` |

#### `Seed Card` — `1764:53297`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Birthday Height#1764:8` | `BOOLEAN` | `false` |
| `State` | `VARIANT` | `Default` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `1510:30936` |
| `State=Warning` | `1764:53298` |

#### `Full Width Card` — `4018:54553`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Type` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `Type=Default` | `4018:54541` |
| `Type=Transparent` | `4063:318424` |
| `Type=Importing` | `4018:54600` |

#### `Password Card` — `4080:388821`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (4):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `4080:388775` |
| `State=Typing` | `4080:388822` |
| `State=Filled` | `4080:388849` |
| `State=Error` | `4080:388888` |

#### `Review Card` — `4083:434671`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Type` | `VARIANT` | `Default` |

Variants (5):

| Variant | Node ID |
| --- | --- |
| `Type=Default` | `4083:430947` |
| `Type=Success` | `4199:1094600` |
| `Type=Failed` | `4083:434672` |
| `Type=Swap` | `4091:500296` |
| `Type=Type4` | `4091:532220` |

#### `Custom Endpoint` — `4083:458266`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Property 1` | `VARIANT` | `Default` |

Variants (1):

| Variant | Node ID |
| --- | --- |
| `Property 1=Default` | `4083:457642` |

#### `_Reivew Info` — `4265:59168`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Title#4265:0` | `TEXT` | `You’re sending` |
| `Large Text#4265:4` | `TEXT` | `123 ZEC` |
| `Bottom Leading Icon#4265:6` | `BOOLEAN` | `false` |
| `Bottom Trailing Icon#4265:8` | `BOOLEAN` | `false` |
| `Bottom Text#4265:10` | `TEXT` | `Shielded` |
| `Bottom Copy#4265:12` | `BOOLEAN` | `false` |
| `Property 1` | `VARIANT` | `Default` |

Variants (1):

| Variant | Node ID |
| --- | --- |
| `Property 1=Default` | `4265:59147` |

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `Pagination` | `400:42501` | — |
| `Seed Card  Settings` | `1764:52509` | — |
| `Review Info` | `4265:59314` | — |

### Supporting showroom or source material

- `image 1` (`RECTANGLE`)
- `image 3` (`RECTANGLE`)
- `image 5` (`RECTANGLE`)
- `Reivew` (`FRAME`)

## [Lists](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=970-72935&m=dev)

Page ID: `970:72935`. Top-level children: 4. Reusable assets found: 0 component sets and 2 standalone components.

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `Unordered List` | `970:73010` | — |
| `List Item` | `970:72989` | — |

### Supporting showroom or source material

- `List Item` (`FRAME`)
