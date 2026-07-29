# Navigation, tabs, and modals

Compose navigation and overlays from their public component sets. Internal assets with leading underscores are documented for identification, not as the default entry point.

## [Navigation](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=303-1919&m=dev)

Page ID: `303:1919`. Top-level children: 10. Reusable assets found: 4 component sets and 3 standalone components.

### Component sets

#### `Navigtaion Item` — `303:2119`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Indicator#4001:0` | `BOOLEAN` | `false` |
| `Page Icon#4002:0` | `INSTANCE_SWAP` | `107:2329` |
| `Page Title#4002:4` | `TEXT` | `Intro to Zcash` |
| `State` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `303:1976` |
| `State=Hover` | `1198:22288` |
| `State=Active` | `303:2120` |

#### `Sidebar` — `303:2206`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Type` | `VARIANT` | `Onboarding` |

Variants (4):

| Variant | Node ID |
| --- | --- |
| `Type=Onboarding` | `303:2000` |
| `Type=Import Wallet` | `1136:19345` |
| `Type=Keystone` | `2216:39887` |
| `Type=Wallet` | `324:4791` |

#### `Nav User` — `324:5473`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Keystone Badge#2216:19` | `BOOLEAN` | `false` |
| `State` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `324:5101` |
| `State=Hover` | `1202:25842` |
| `State=Open` | `4058:162254` |

#### `User Image` — `677:52637`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Keystone badge#2216:15` | `BOOLEAN` | `false` |
| `Size` | `VARIANT` | `XS` |

Variants (6):

| Variant | Node ID |
| --- | --- |
| `Size=XS` | `4353:81254` |
| `Size=S` | `324:5092` |
| `Size=M` | `677:52638` |
| `Size=L` | `4001:50904` |
| `Size=XL` | `677:53310` |
| `Size=XXL` | `4190:1083094` |

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `_Nav Account` | `4001:50932` | — |
| `Page Toolbar` | `415:47179` | — |
| `_Nav Item Indicator` | `4001:52382` | — |

### Supporting showroom or source material

- `Home Default` (`FRAME`)

## [Tabs](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=485-30867&m=dev)

Page ID: `485:30867`. Top-level children: 4. Reusable assets found: 3 component sets and 0 standalone components.

### Component sets

#### `Tab` — `946:64280`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Tab Label#946:99` | `TEXT` | `Shielded` |
| `Show Leading Icon#946:100` | `BOOLEAN` | `true` |
| `Tab Icon#946:101` | `INSTANCE_SWAP` | `115:3411` |
| `State` | `VARIANT` | `Default` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `946:64210` |
| `State=Active` | `946:64281` |

#### `Tabs` — `970:65945`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Tab` | `VARIANT` | `1` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `Tab=1` | `946:64216` |
| `Tab=2` | `970:65946` |

#### `Simple Tabs` — `1510:33746`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Show Icons#2809:0` | `BOOLEAN` | `false` |
| `Tab 1#2809:3` | `TEXT` | `Enter the Date` |
| `Tab 2#2809:6` | `TEXT` | `Enter the Block Height` |
| `Select` | `VARIANT` | `1` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `Select=1` | `1510:33747` |
| `Select=2` | `1510:33744` |

## [Modal](https://www.figma.com/design/HJxo289BJD7R6tz0OoGSQu/Vizor--Design-System--AI-Test-?node-id=485-26307&m=dev)

Page ID: `485:26307`. Top-level children: 7. Reusable assets found: 4 component sets and 1 standalone components.

### Component sets

#### `Cal Cell` — `485:28276`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Type` | `VARIANT` | `Default` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `Type=Default` | `485:26298` |
| `Type=Hover` | `485:31212` |
| `Type=Selected` | `485:28277` |

#### `_Modal Type` — `664:49157`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `Dialog Body#677:69` | `SLOT` | — |
| `Unordered List#970:102` | `SLOT` | — |
| `Show Close#4236:0` | `BOOLEAN` | `false` |
| `Type` | `VARIANT` | `Date Picker` |

Variants (16):

| Variant | Node ID |
| --- | --- |
| `Type=Date Picker` | `485:29175` |
| `Type=Update Name` | `664:49158` |
| `Type=Update PFP` | `677:54419` |
| `Type=Edit/Add Contact` | `2841:111387` |
| `Type=Dialog` | `2071:43954` |
| `Type=Radio Group` | `746:57351` |
| `Type=Info / List` | `970:67827` |
| `Type=Address Verification` | `4470:68773` |
| `Type=Address Verification Non Zec` | `4731:86101` |
| `Type=Seed Security` | `1644:45231` |
| `Type=Keystone QR` | `2218:58297` |
| `Type=Swap Address` | `2779:43450` |
| `Type=QR Scan` | `2779:52359` |
| `Type=Slippage` | `2785:8754` |
| `Type=Asset Select` | `2809:73422` |
| `Type=Contacts` | `4058:182744` |

#### `Camera Modal` — `2782:53932`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Modal Camera` |

Variants (3):

| Variant | Node ID |
| --- | --- |
| `State=Loading` | `2782:53931` |
| `State=Utility` | `2782:53930` |
| `State=Modal Camera` | `2782:53929` |

#### `_Asset Modal Scroll` — `2809:74618`

Properties:

| Property | Type | Default |
| --- | --- | --- |
| `State` | `VARIANT` | `Default` |

Variants (2):

| Variant | Node ID |
| --- | --- |
| `State=Default` | `2809:74515` |
| `State=Empty` | `2809:74619` |

### Standalone components

| Component | Node ID | Description |
| --- | --- | --- |
| `Modal Scrim` | `664:48921` | — |

### Supporting showroom or source material

- `Screen` (`FRAME`)
- `Access Denied` (`FRAME`)
- `No Cam found` (`FRAME`)
