# Compact gift links

V3 encodes the original English BIP-39 entropy in the fragment of
`https://link.vizor.cash/payment-links/open#v3=<payload>`. The origin remains
configurable through `VIZOR_DEEPLINK_BASE_URL`. No resolver, remote presentation
lookup, or new route is needed. New gifts still use 24 words. Decoding also
supports existing 12, 15, 18, and 21 word phrases.

The message remains inline. It is not placed in, or fetched from, a funding
transaction memo. The amount and birthday retain their existing meanings.

## Wire contract

Integers are unsigned and little endian. The payload is unpadded Base64url
using only `A-Z`, `a-z`, `0-9`, `-`, and `_`. Padding, percent escapes,
noncanonical trailing bits, unknown profiles/flags, trailing bytes, and malformed
UTF-8 are rejected. The complete URL is bounded to 16 KiB before decoding.

| Field | Bytes | Encoding |
| --- | ---: | --- |
| Header | 1 | Bits 0–1 network, bits 2–4 entropy code, bits 5–7 derivation profile |
| Optional fields | 1 | Bit 0 artwork, bit 1 fiat, bit 2 message, bit 3 custom label; other bits zero |
| Original entropy | 16–32 | Entropy codes 0–4 mean 16, 20, 24, 28, 32 bytes |
| Birthday | 4 | Positive block height |
| Recipient amount | 8 | Positive zatoshi, at most 2,100,000,000,000,000 |
| Artwork, if present | 1 or variable | Permanent code below, or 255 followed by u8 UTF-8 length and ID |
| Fiat, if present | 8 | Finite, nonnegative IEEE-754 binary64 USD snapshot |
| Message, if present | 2 + length | u16 UTF-8 length, at most 512 bytes and 128 grapheme clusters |
| Label, if present | 2 + length | u16 UTF-8 length; absent means `Payment link` |
| Corruption checksum | 4 | First four bytes of SHA-256 over domain followed by all preceding bytes |

The checksum domain is the UTF-8 bytes of `VizorPaymentLink/v3` followed by
one NUL byte. It detects accidental corruption; it does not authenticate the
sender or prevent deliberate payload changes. Actual funding remains verified
by the claim flow.

Network 0 is mainnet. Network 2 is regtest and requires the existing
`VIZOR_PAYMENT_LINK_REGTEST_ENABLED` build flag. Codes 1 and 3 are reserved.
Profile 0 reconstructs the same English mnemonic, uses the empty BIP-39
passphrase, and derives ZIP32 account zero through the existing gift funding
and import paths. Other profiles are rejected. Entropy is not a derived seed.
Only the canonical English mnemonic is compactly shareable. A legacy phrase
with alternate whitespace keeps its legacy link rather than changing the
mnemonic string used by an existing claim-cache directory.
Synchronous FFI performs only bounded mnemonic conversion; key derivation and
address validation remain asynchronous and perform no network access.

Optional strings use the existing trimmed presentation semantics. Empty
messages are omitted. A custom label may be empty, but must not repeat the
implicit default. Known artwork must use its numeric code; escaped artwork
must be a valid nonempty ASCII identifier of at most 64 characters. Unknown
numeric codes are rejected. Unknown escaped IDs are retained and rendered
with the existing local artwork fallback, without fetching an asset.

| Code | Artwork ID |
| ---: | --- |
| 1 | knightMagic |
| 2 | knight |
| 3 | chestLava |
| 4 | chestCave |
| 5 | dragon |
| 6 | gandalf |
| 7 | crystal |
| 8 | diamond |
| 9 | ruby |
| 10 | coin |
| 11 | gift |

These assignments are permanent and independent of picker order. Never reuse
a code for different artwork.

## Compatibility and recovery

`toShareUri()` selects v2 or v3 using the build flag below. `toRecoveryUri()`
continues writing the established v2 JSON format. `toUri()` remains a v2 alias
for existing callers. Sender addresses, creation times, status, funding
transactions, and claim evidence stay in their existing secure records.
Incoming v3 links persist through that same v2 representation. Decoding rejects
links whose v2 recovery URI exceeds 16 KiB, including JSON escaping and Base64
expansion of custom labels.

`preparePaymentLinkShareUri()` verifies a locally known address against the
mnemonic before dropping it from compact sharing. A failure leaves the record
untouched. Funding creation checks the selected share, recovery, and v1
compatibility representations before the durable draft and broadcast. All
funding signers share this path. No retry replaces a funded secret.

The claim cache continues using network, mnemonic, and birthday, including its
existing legacy-directory preference when submission evidence exists. Intake
equality continues comparing normalized logical payloads rather than the wire
version. Different amounts, birthdays, labels, or presentation remain distinct.

The desktop and mobile QR share views offer **Copy link for older Vizor**.
This emits v1 with the original address and time when those are known. It
controls the same gift, with the same secret; it does not create another gift.
A decoded v2/v3 link without resolved metadata cannot yet produce v1.

| Reader | v1 | v2 | v3 |
| --- | --- | --- | --- |
| V1-only Vizor | Yes | No | No |
| V2-capable Vizor | Yes | Yes | No |
| This implementation | Yes | Yes | Yes |

An older installed app may intercept a new link before a browser fallback can
help. Testers need this build for v3, or the sender must use the compatibility
copy action. Turning off the writer does not remove any reader.

## Rollout and local testing

`VIZOR_PAYMENT_LINK_COMPACT_SHARING` defaults to `false`. Deploy the gateway
reader for opaque `#v3=` envelopes first, release wallet readers on supported
platforms, then enable the writer in release configuration. No online
recipient capability check is introduced. This PR does not deploy the gateway
or change production release configuration.

Enable local generation with `--dart-define=VIZOR_PAYMENT_LINK_COMPACT_SHARING=true`.
The existing regtest lane accepts the corresponding environment variable:

```sh
VIZOR_PAYMENT_LINK_COMPACT_SHARING=true scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh
VIZOR_PAYMENT_LINK_COMPACT_SHARING=true scripts/e2e/flutter-macos-regtest-payment-link-recovery.sh
```

Use the repository's native signing and local secure-storage setup. The
regtest lane creates disposable accounts and cleans its regtest wallet. It
must not be pointed at a personal wallet. Bridge regeneration uses
`scripts/generate-rust-bridge.sh` from the repository root, which invokes FRB
with the repository's existing expanded-Rust compatibility wrapper.

Reader tests cover v1/v2 equivalence, persistence representation, corruption,
truncation, unsupported fields, numeric bounds, unknown artwork, custom labels,
Unicode, and exact sizes. Native tests additionally verify real BIP-39
conversion and the retained funding address. The round-trip lane checks a real
funded gift through copy, import, claim, and confirmation. Hardware devices,
iOS/Android native handoff, and deployed browser behavior still require their
normal release qualification; unit tests are not a substitute for those checks.

## Synthetic reference and sizes

The following unfunded public vector uses 32 zero entropy bytes (23 `abandon`
words followed by `art`), mainnet, height 3,483,141, amount 1,000,000 zatoshi,
artwork `knightMagic`, USD 11.1747, and the exact message
`It's a great day to shield your ZEC 🛡️`. Do not fund this published secret.

```text
https://link.vizor.cash/payment-links/open#v3=EAcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUmNQBAQg8AAAAAAAHvOEVHclkmQCsASXQncyBhIGdyZWF0IGRheSB0byBzaGllbGQgeW91ciBaRUMg8J-boe-4jz32S0A
```

It is 185 characters: 46 for the URL prefix and 139 for 104 binary bytes.
The message occupies 43 UTF-8 bytes plus its two-byte length.

| Contents, default label | 24 words | 12 words (decoder support only) |
| --- | ---: | ---: |
| Plain | 113 | 92 |
| Artwork and fiat | 125 | 104 |
| Artwork, fiat, example message | 185 | 164 |
| Artwork, fiat, 512-byte message | 810 | 789 |

The original v1 example in planning measured 914 characters. Its bearer secret
is not included in source or fixtures. The earlier illustrative encoding was
not a released v3 contract; the checksum domain and artwork table above define
this implementation.

Further size reductions are deferred: 12-word generation saves about 21–22
characters; `/gift` saves 14; placing the example message on-chain saves 60 but
adds memo retrieval and its privacy/availability tradeoffs; compression has
variable savings and adds parser complexity.
