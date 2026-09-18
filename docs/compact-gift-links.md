# Compact gift links

V3 encodes the original English BIP-39 entropy in the fragment of
`https://link.vizor.cash/payment-links/open#v3=<payload>`. The origin remains
configurable through `VIZOR_DEEPLINK_BASE_URL`. No resolver, remote presentation
lookup, or new route is needed. New gifts still use 24 words. Decoding also
supports existing 12, 15, 18, and 21 word phrases.

The message remains inline. It is not placed in, or fetched from, a funding
transaction memo. The amount and birthday retain their existing meanings.

## Positional JSON schema

The fragment contains unpadded Base64url of a UTF-8 JSON array. The array uses
these fixed positions, with at least the first four entries and at most eight:

| Index | Value | JSON type |
| --- | --- | --- |
| 0 | Network, `main` or gated `regtest` | String |
| 1 | Original BIP-39 entropy, unpadded Base64url | String |
| 2 | Positive birthday height, at most 4,294,967,295 | Integer |
| 3 | Positive zatoshi, at most 2,100,000,000,000,000 | Decimal string |
| 4 | Artwork ID, such as `knightMagic` | String or null |
| 5 | Finite, nonnegative USD snapshot | Number or null |
| 6 | Personal message | String or null |
| 7 | Custom label; null or absent means `Payment link` | String or null |

Omit trailing null entries when writing. Keep null placeholders when a later
optional field is present. An empty custom label is allowed. Amounts use decimal
strings without a sign, exponent, or leading zeroes. The version is already in
`#v3=` and is not repeated in the array.

The complete URL is bounded to 16 KiB before decoding. Both Base64url strings
use only `A-Z`, `a-z`, `0-9`, `-`, and `_`, without padding or noncanonical trailing
bits. JSON whitespace and normal JSON string escaping are accepted. Wrong
field types, missing required fields, extra fields, and out-of-range values are
rejected using the existing presentation and recovery limits.

Strings keep the existing trimmed semantics. Artwork IDs are ASCII identifiers
of at most 64 characters; unknown IDs use the local artwork fallback. Messages
remain limited to 128 grapheme clusters and 512 UTF-8 bytes.

Entropy is 16, 20, 24, 28, or 32 bytes, reconstructing the original English
mnemonic with an empty BIP-39 passphrase and ZIP32 account zero. New gifts still
use 32 bytes, or 24 words. Legacy cards with alternate mnemonic whitespace
share as v2 after verifying the original address and validating the canonical
phrase. Their original secret,
recovery records, and claim-cache identity remain unchanged. Other conversion or
address-validation errors fail sharing; they never trigger a v2 fallback.
Synchronous FFI only converts mnemonic and entropy; address validation remains
asynchronous and local.

This uses standard JSON serialization, with no binary header, bit flags, length
prefixes, artwork-code registry, or custom checksum. JSON parsing validates the
structure, and the claim flow verifies actual funding. This replaces the
unreleased binary v3 prototype; v1/v2 compatibility is preserved.

## Compatibility and recovery

`toShareUri()` always writes v3. The verified sharing helper preserves v2
only for legacy mnemonic whitespace. `toRecoveryUri()`
continues writing the established v2 JSON format. `toUri()` remains a v2 alias
for existing callers. Sender addresses, creation times, status, funding
transactions, and claim evidence stay in their existing secure records.
Incoming v3 links persist through that same v2 representation. Decoding rejects
links whose v2 recovery URI exceeds 16 KiB, including the expanded mnemonic,
JSON field names, string escaping, and Base64 encoding.

`preparePaymentLinkShareUri()` verifies a locally known address against the
mnemonic before dropping it from compact sharing. A failure leaves the record
untouched and reports a sharing error. Funding creation checks the selected
share and recovery representations before the durable draft and broadcast.
All funding signers share this path. No retry replaces a funded secret.

The claim cache continues using network, mnemonic, and birthday, including its
existing legacy-directory preference when submission evidence exists. Intake
equality continues comparing normalized logical payloads rather than the wire
version. Different amounts, birthdays, labels, or presentation remain distinct.

Desktop and mobile share v3 without an older-version copy
option. Recipients must upgrade to a v3-capable Vizor to claim compact links.
Existing v1 and v2 links remain readable.

| Reader | v1 | v2 | v3 |
| --- | --- | --- | --- |
| V1-only Vizor | Yes | No | No |
| V2-capable Vizor | Yes | Yes | No |
| This implementation | Yes | Yes | Yes |

An older installed app may intercept a new link before a browser fallback can
help. Recipients need a v3-capable build for new links. Existing v1/v2 links
remain readable without migration.

## Rollout and local testing

V3 sharing is enabled by default, with no build flag. The gateway must accept
opaque `#v3=` envelopes and recipients must have a v3-capable wallet. There is
no online recipient capability check or automatic downgrade for older apps.
This PR does not deploy the gateway.

Run `fvm flutter test test/features/payment_links/compact_payment_link_test.dart`
for codec, persistence, copy, and QR navigation regressions. The existing
regtest lane exercises default v3 sharing:

```sh
scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh
scripts/e2e/flutter-macos-regtest-payment-link-recovery.sh
```

Use the repository's native signing and local secure-storage setup. The
regtest lane creates disposable accounts and cleans its regtest wallet. It
must not be pointed at a personal wallet. Bridge regeneration uses
`scripts/generate-rust-bridge.sh` from the repository root, which invokes FRB
with the repository's existing expanded-Rust compatibility wrapper.

Reader tests cover v1/v2 equivalence, persistence representation, JSON types and
positions, truncation, numeric bounds, unknown artwork, custom labels, Unicode,
and exact sizes. Native tests additionally verify real BIP-39
conversion and the retained funding address. The round-trip lane checks a real
funded gift through copy, import, claim, and confirmation. Hardware devices,
iOS/Android native handoff, and deployed browser behavior still require their
normal release qualification; unit tests are not a substitute for those checks.

## Synthetic reference and sizes

The following unfunded public vector uses 32 zero entropy bytes (23 `abandon`
words followed by `art`), mainnet, height 3,483,141, amount 1,000,000 zatoshi,
artwork `knightMagic`, USD 11.1747, and the exact message
`It's a great day to shield your ZEC 🛡️`. Do not fund this published secret.

Its decoded JSON is:

```json
["main","AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",3483141,"1000000","knightMagic",11.1747,"It's a great day to shield your ZEC 🛡️"]
```

The full link is:

```text
https://link.vizor.cash/payment-links/open#v3=WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNzQ3LCJJdCdzIGEgZ3JlYXQgZGF5IHRvIHNoaWVsZCB5b3VyIFpFQyDwn5uh77iPIl0
```

It is 233 characters: 46 for the URL prefix and 187 for the Base64url encoding
of 140 JSON bytes. The message itself occupies 43 UTF-8 bytes.

| Contents, default label | 24 words | 12 words (decoder support only) |
| --- | ---: | ---: |
| Plain | 142 | 114 |
| Artwork and fiat | 172 | 144 |
| Artwork, fiat, example message | 233 | 205 |
| Artwork, fiat, 512-byte message | 858 | 830 |

The original v1 example in planning measured 914 characters. Its bearer secret
is not included in source or fixtures. Positional JSON retains a 74.5% reduction
for the decorated example, while using standard JSON tooling.

Further size reductions are deferred: 12-word generation saves about 28
characters; `/gift` saves 14; placing the example message on-chain saves about 61 but
adds memo retrieval and its privacy/availability tradeoffs; compression has
variable savings and adds parser complexity.
