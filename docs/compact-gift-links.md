# Compact gift links (v3 and v4)

Gift links place their payload in the URL fragment, so the secret is not sent
to the HTTPS origin. V4 links use
`https://link.vizor.cash/gift#v4=<payload>`. The origin remains configurable
through `VIZOR_DEEPLINK_BASE_URL`. V1 through v3 links retain their existing
`/payment-links/open` route and remain readable.

New 12-word gifts use v4. Existing 24-word gifts continue to share as v3, so a
funded secret is never shortened or replaced. V4 always means mainnet and has
no network field. Writers reject non-mainnet cards.

## V4 core

The payload is unpadded canonical Base64url of this binary sequence:

| Order | Value | Encoding |
| --- | --- | --- |
| 0 | Locator mode | One byte: `00`, `01`, or `02` |
| 1 | Original 12-word BIP-39 entropy | 16 bytes |
| 2 | Recipient amount in zatoshi | Minimal unsigned LEB128 |
| 3 | Locator | Mode-dependent, below |
| 4 | Display options | Zero or more TLVs |

The amount is positive. It plus the 10,000 zatoshi claim fee reserve must not
exceed the 21 million ZEC monetary maximum. Nonminimal, unterminated, and
overflowing ULEB128 values are invalid.

### Locator modes

| Mode | Meaning | Locator bytes | Claim behavior |
| --- | --- | --- | --- |
| `00` | Birthday | Positive block height as big-endian `u32` | Discover funding from birthday, then observe later spends |
| `01` | Funding height | Positive block height as big-endian `u32` | Resolve the card's funding transaction in that block |
| `02` | Funding transaction | 32-byte txid in display-hex byte order | Retrieve that transaction directly |

The model carries exactly one locator. Modes `01` and `02` select direct claim;
mode `00` uses the merged single-funding Ironwood discovery/observer path.
A funding-height claim verifies the
expected recipient amount while resolving the transaction. Once found, its
txid is durable claim state; it is not written back into or substituted for
the original shared locator.

Transaction bytes follow the successive pairs of the conventional
64-character display hex. They are not reversed by this codec. Rust converts
them to protocol order at the transaction lookup boundary.

## V4 display TLVs

Each optional display field is `[tag: u8][length: minimal ULEB128][value]`.
These values affect presentation only. They do not select funds or change the
claim locator.

| Tag | Value |
| --- | --- |
| `01` | One-byte artwork code |
| `02` | USD snapshot as IEEE-754 float64, big-endian |
| `03` | Reserved; messages are carried in the funding output memo |

Artwork codes are stable: `1 knight`, `2 chestLava`, `3 chestCave`, `4 dragon`,
`5 knightMagic`, `6 gandalf`, `7 crystal`, `8 diamond`, `9 ruby`, `10 coin`,
and `11 gift`. A writer omits an unknown local artwork ID.

Fiat values must be finite and nonnegative. A gift message uses the standard
UTF-8 memo on its shielded funding output, with no custom header. App writers
trim messages, allow at most 128 grapheme clusters / 512 UTF-8 bytes, and reject
NUL characters before funding. An absent or invalid display memo never blocks
a valid claim. Funding validation failures retain their existing behavior.
Labels are local and are not shared.

Readers skip complete unknown TLVs. If the display suffix is truncated,
noncanonical, duplicated, or contains a malformed known option, parsing stops
at that option. The valid core and every valid preceding display option are
retained. This allows display metadata to evolve without weakening validation
of the secret, amount, or locator. Malformed core data always rejects the link.

The decoded binary payload is capped at 1,024 bytes. Accepted links must also
fit the existing 16 KiB local recovery envelope.

## External issuer CLI

`tool/gift_link_v4.dart` builds v4 URLs directly from 16-byte entropy after an
external issuer funds a card. It does not initialize the Rust bridge and never
accepts a mnemonic. Treat the input and output as secrets.

JSON input may be one object or an array:

```json
[
  {
    "entropyHex": "00000000000000000000000000000000",
    "amountZatoshi": "1000000",
    "locatorKind": "fundingHeight",
    "fundingHeight": 4000000,
    "artworkId": "gift",
    "fiatUsd": 0.42
  },
  {
    "entropyHex": "00000000000000000000000000000001",
    "amountZatoshi": "2500000",
    "locatorKind": "fundingTxid",
    "fundingTxid": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
  }
]
```

```bash
fvm dart run tool/gift_link_v4.dart --input cards.json --output links.txt
```

CSV uses the same field names in its header. Empty optional cells are omitted:

```csv
entropyHex,amountZatoshi,locatorKind,birthdayHeight,fundingHeight,fundingTxid,artworkId,fiatUsd
00000000000000000000000000000000,1000000,fundingHeight,,4000000,,gift,0.42
```

```bash
fvm dart run tool/gift_link_v4.dart --format csv --input cards.csv
```

The command writes one URL per input record. It exits nonzero on the first
invalid record and does not print the secret-bearing input in its error.
`message` input is rejected: this encoder cannot add a memo to an already
funded gift. External issuers must attach the message when constructing each
funding output, before broadcasting. Funding messages cannot be edited later.

## V3 compatibility

V3 is unpadded Base64url of a UTF-8 JSON array with four required and four
optional positions:

| Index | Value |
| --- | --- |
| 0 | Network (`main` or gated `regtest`) |
| 1 | BIP-39 entropy as unpadded Base64url |
| 2 | Positive birthday height (`u32`) |
| 3 | Positive zatoshi as a decimal string |
| 4 | Artwork ID or null |
| 5 | Finite nonnegative USD snapshot or null |
| 6 | Personal message or null |
| 7 | Custom label or null |

Trailing nulls are omitted. V3 readers support 12, 15, 18, 21, and 24-word
English phrases. New writers use v4 for 12-word phrases and preserve v3 for
24-word reshares. V1 and v2 parsing and v2 local recovery remain unchanged.

The v3 writer rounds the display-only USD snapshot to two decimal places and
keeps it a JSON number. Readers continue accepting older full-precision USD
snapshots in v1, v2, and v3 without rounding them. Local v2 recovery records
retain their original precision; resharing rounds only the v3 snapshot. V4's
binary float64 display option retains its original precision. The ZEC amount,
mnemonic, birthday, and claim calculations are unaffected.

`toRecoveryUri()` writes the local v2 JSON representation. It stores
`fundingHeight` or `fundingTxid` when present. Address, creation time, and
durable claim state remain in the enclosing sender or receiver record;
presentation remains in the v2 payload. Incoming v4 links use `Payment link`
as their local label.

| Reader | v1 | v2 | v3 | v4 |
| --- | --- | --- | --- | --- |
| V1-only Vizor | Yes | No | No | No |
| V2-capable Vizor | Yes | Yes | No | No |
| Existing v3 reader | Yes | Yes | Yes | No |
| This implementation | Yes | Yes | Yes | Yes |

## Link size comparison

For the same 12-word entropy, 0.5 ZEC recipient amount, and height 4,000,000,
including the HTTPS origin, path, and version prefix:

| Payload | v3 JSON | v4 birthday | v4 funding height | v4 funding txid |
| --- | ---: | ---: | ---: | ---: |
| Required fields only | 116 characters | 66 | 66 | 103 |
| Plus gift artwork, USD 25 snapshot, and `For you` | 145 | 83 | 83 | 120 |

V4's height modes save 50 characters without optional metadata and 62 with
the displayed example. The full txid mode saves 13 and 25 respectively; its
message is in the funding output rather than the link. These are examples,
not fixed lengths: amount varint size, text length, and a configured origin
change the total. V3 itself uses JSON containing
binary entropy, rather than JSON containing the mnemonic words.

## Claim verification

All three locators use the same claim-check API, endpoint routing, foreground
admission, cancellation, and progress ownership. Birthday links discover the
first funding transaction by scanning from birthday, then observe nullifiers
and claim transaction IDs through later blocks without further wallet scanning
or enhancement. Historical block-range downloads still remain in this mode;
it is not a direct lookup. Retained legacy birthday receipts can continue their
older sync recovery path.

Height mode scans exactly the specified block using the preceding tree state.
It requires one positive received shielded note worth recipient amount plus
the 10,000 zatoshi reserve, and a unique transaction satisfying that condition.
Zero-valued padding is ignored. Missing, split, or ambiguous funding fails;
there is no neighboring-block search or fallback scan. On first open, a reorg
moving funding out of that block requires a corrected link or the txid mode.
After discovery, the local isolated claim DB persists the resolved txid and
retries follow its current mined height while preserving the original link.

Direct preparation does not establish whether the note was spent in a later
block. The node validates spentness when the claim is broadcast. Its funding
lookup currently uses the existing public transaction-payload path, so do not
interpret a shorter height locator as hiding the resolved txid from the
endpoint. The separate recent-anchor work is not included here.
Direct claims refresh their funding preparation again before submission and
use the same cancellable check when recovering retained receipts. They do not
enter the birthday observer or fall back to scanning historical ranges.

The funded regtest uses temporary claim DBs and an explicitly selected isolated
node stack. `VIZOR_DIRECT_GIFT_PROJECT` can select an owned Compose project;
`VIZOR_DIRECT_GIFT_IRONWOOD_GAP` bounds a fresh fixture's mining workload while
the default retains the 5,000-block lane. The desktop round-trip fixture accepts
`--dart-define=VIZOR_E2E_FUNDING_HEIGHT_GIFT_CARD=true` to exercise the height
locator through Settings and the generated Rust bridge. Shared v4 remains
mainnet-only; regtest uses the same model's local recovery envelope.

## Funding messages

Messages belong to a shielded output, not to a transaction as a whole. Readers
bind the memo to the isolated gift account, funding transaction, pool, and
output index. Only a unique transaction with one positive received note equal
to the advertised recipient amount plus the 10,000-zatoshi reserve is eligible.
Zero-valued notes, unrelated accounts, split funding, and ambiguous top-ups do
not supply a display message. Txid mode uses the link identity; height mode
uses the durable resolution identity even after a reorg.

Direct height/txid preparation already decrypts the funding payload: reading
its memo adds no RPC. Birthday claim sync skips transaction enhancement, so
missing metadata is recovered from the isolated claim database through the
existing payload scheduler, with a five-second total display budget. The SDK
routes pure Ironwood funding notes to Enhance PIR when Private queries is
on; transactions it explicitly routes to public transport retain the normal
lightwalletd lookup. No PIR failure, missing coverage, or timeout authorizes a
public fallback. A temporarily unavailable message is omitted without blocking
the claim. Public lookups disclose the funding txid to the chosen endpoint;
PIR uses the existing position query and authenticated note-recovery path.

URL messages in v1-v3 retain precedence. Otherwise readers use a retained
received-record message, then the newly decoded funding memo. Inspection and
session carry `fundingMessage` separately from link identity. Checking stays
read-only; the message is saved with the existing claim/retention operation,
without rewriting the recovery link, and survives secret/database cleanup.
The outgoing claim transaction still carries no sender message.

Ledger batch quotes conservatively bound memo review retention at 1,024 bytes
across randomized outputs (ASCII text length, otherwise a 64-byte hash).
The signing parser also accounts for the device's actual ordered retention
across both shielded pools; older apps reject any hash display path. Messages
remain in Keystone's compact PCZT, so they can increase QR frame count.
Maximum-device batches still require physical Ledger/Keystone validation.
