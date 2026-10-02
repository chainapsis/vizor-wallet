# Compact gift links (v3 and v4)

V3 encodes the original English BIP-39 entropy in the fragment of
`https://link.vizor.cash/payment-links/open#v3=<payload>`. The origin remains
configurable through `VIZOR_DEEPLINK_BASE_URL`. No resolver, remote presentation
lookup, or new route is needed. New gifts still use 24 words. Decoding also
supports existing 12, 15, 18, and 21 word phrases.

V4 retains those compact fields and adds a named options object for event
policy. Ordinary cards continue sharing as v3; a scan policy or funding txid
selects v4.

Event links are issued and printed with separate tooling. The application's
single-card and batch-creation UI continues creating ordinary cards; this
change adds no event-mode toggle or funding-txid input to that UI. Event
redemption applies at the shared claim boundary, including onboarding,
Settings → My gift cards, and interrupted-claim recovery.

The txid-based claim path is implemented at the shared redemption boundary.
Isolated regtest verified real Orchard and Ironwood proof generation, node
acceptance, mined recipient balances, and history while processing only the
funding block. The Ironwood funding transaction was 5,003 blocks old and its
anchor differed from the current tip. Rust preparation used four read RPCs;
preparation plus submission used six. Account setup, Dart intake, recipient
sync, and recovery make additional calls. This is not a six-RPC bound on the
entire onboarding flow. Subsequent integration covered duplicate rejection,
funding and claim reorgs, interrupted submission with reuse of signed bytes,
and expiry followed by an explicit retry. A native iOS Simulator walkthrough
also completed actual first-wallet creation, claim submission, recipient sync,
the `0.50 TAZ` Home balance, and redeemed-gift activity. Physical devices and
production-network claims still require qualification.
The explicit integration lane is in
[`regtest_direct_gift_claim.rs`](../rust/tests/regtest_direct_gift_claim.rs).

The message remains inline. It is not placed in, or fetched from, a funding
transaction memo. The amount and birthday retain their existing meanings.

## V3 positional JSON schema

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
the fragment prefix and is not repeated in the array.

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
use 32 bytes, or 24 words. Ordinary legacy cards with alternate mnemonic whitespace
share as v2 after verifying the original address and validating the canonical
phrase. Their original secret,
recovery records, and claim-cache identity remain unchanged. Other conversion or
address-validation errors fail sharing; they never trigger a v2 fallback.
Event options never downgrade to v2; event sharing rejects alternate mnemonic
whitespace because compact sharing cannot preserve that original secret.
Synchronous FFI only converts mnemonic and entropy; address validation remains
asynchronous and local.

This uses standard JSON serialization, with no binary header, bit flags, length
prefixes, artwork-code registry, or custom checksum. JSON parsing validates the
structure, and the claim flow verifies actual funding. This replaces the
unreleased binary v3 prototype; v1/v2 compatibility is preserved.

## Compatibility and recovery

`toShareUri()` writes v3 for ordinary cards and v4 for cards carrying the
optional `skipScan` policy or funding txid. The verified sharing helper preserves v2
for legacy mnemonic whitespace. `toRecoveryUri()`
continues writing the established v2 JSON format. `toUri()` remains a v2 alias
for existing callers. Sender addresses, creation times, status, funding
transactions, and claim evidence stay in their existing secure records. Event
links additionally include the funding txid for direct retrieval.
Incoming v3/v4 links persist through that same v2 representation. Decoding rejects
links whose v2 recovery URI exceeds 16 KiB, including the expanded mnemonic,
JSON field names, string escaping, and Base64 encoding.

`preparePaymentLinkShareUri()` verifies a locally known address against the
mnemonic before dropping it from compact sharing. A failure leaves the record
untouched and reports a sharing error. Funding creation checks the selected
share and recovery representations before the durable draft and broadcast.
All funding signers share this path. No retry replaces a funded secret.

Ordinary claim caches continue using network, mnemonic, and birthday, including
the existing legacy-directory preference when submission evidence exists. Event
caches additionally include the validated funding txid and a direct-claim policy
suffix, and never reuse an ordinary card's legacy cache. Intake
equality continues comparing normalized logical payloads rather than the wire
version. Different amounts, birthdays, labels, or presentation remain distinct.
Persisted event policy, funding txid, destination, and submission evidence must
survive restart and must not be overwritten by an incoming policy-free link.
Cached quotes and proposals must not carry event preparation into ordinary
claims or retain stale preparation after a failed verification.

Desktop and mobile share ordinary cards as v3 without an older-version copy
option. Event links carrying the scan policy require a v4-capable reader.
Existing v1 and v2 links remain readable.

| Reader | v1 | v2 | v3 | v4 |
| --- | --- | --- | --- | --- |
| V1-only Vizor | Yes | No | No | No |
| V2-capable Vizor | Yes | Yes | No | No |
| Existing v3 reader | Yes | Yes | Yes | No |
| This implementation | Yes | Yes | Yes | Yes |

An older installed app may intercept a new link before a browser fallback can
help. Recipients need a v3-capable build for ordinary compact links and a
v4-capable build for event-option links. Existing v1/v2/v3 links remain readable
without migration.

### Optional event policy in v4

V3 keeps its original four-to-eight-entry array and rejects extra fields.
V4 uses `#v4=<payload>` with the same entries at positions 0 through 7 and
an optional options object at position 8. Its array has four to nine entries;
all options belong in that object rather than new array positions.

```json
{"skipScan": true, "fundingTxid": "<64 hexadecimal characters>"}
```

Missing or null options, or a missing or false `skipScan`, mean the ordinary
policy. A present `skipScan` must be a boolean. Unknown option keys are ignored
when reading and omitted when reserializing. Writers select v4 when the known
policy is enabled or a funding txid is present; normal links retain their
existing v3 representation. A txid without `skipScan: true` still uses ordinary
sync; optimizing that path to start at funding height is outside this change.
An event share requires a funding txid. It is lowercase display-order hex;
wrong types or lengths are rejected before mnemonic conversion. Draft recovery
records may omit it, but externally issued event links must identify their
confirmed funding transaction before printing. The first event format supports
one funding transaction per card; one transaction may fund multiple cards.
Comma-separated txids and discovery of additional funding are unsupported.
Future optional keys can use the same object without changing v3's schema.

The link model retains this policy through metadata resolution, sharing, and
the sender and recipient stores' v2 recovery representation. It participates
in payload equality. Event claim-wallet cache identities include the scan policy
and funding txid, so an ordinary card cannot reuse a partially scanned event DB.
Ordinary cache identities and legacy cache recovery remain unchanged.
The v2 recovery representation is existing local storage, not the selected
event-sharing format. Apps without a v4 reader reject v4 links rather than
silently ignoring the event policy.

The event claim contract retrieves the identified funding transaction and
processes its block with the preceding tree frontier. It leaves birthday-to-tip gaps
unscanned. Claim estimates and proposals only select notes decrypted for that
funding txid, with real Merkle witnesses and the existing two-confirmation
claim policy. Retained claims must query their known outgoing transactions
instead of falling back to historical scanning. This is bounded block processing, not
zero block processing. It does not defer the skipped range to Home or background
sync. The recipient wallet's own sync follows its existing policy. Ordinary
cards keep the existing scan path.

Reading a funding block does not establish that the card's notes were never
spent in later blocks. The event path verifies actual decrypted funds and fees,
but network validation remains necessary before a claim can be reported as
submitted. It must not turn an absent RPC response into evidence of an empty,
previously claimed, or successfully received card. Creating the recipient
account and claiming the card are separate completion states.

### Reorg contract

Do not embed a funding height, block hash, witness, or anchor in the link.
Resolve the identified transaction against the current chain before preparing
the claim. If the same txid is included in another block, retain the printed
link and rebuild the note position and witness. A same-height reorg can also
change the tree; comparing heights alone is insufficient.

Invalidate quotes and proposals derived from the old chain while preserving
signed/submitted claim IDs and recovery records. A mempool transaction or one
mined only on a fork is not ready for claim preparation. The RPC height
sentinels are `0` for mempool and `u64::MAX` for a non-main-chain fork; neither
is a confirmed funding height. See the
[lightwalletd protocol](https://raw.githubusercontent.com/zcash/lightwallet-protocol/master/walletrpc/service.proto).

Preparation clears its persisted marker before any remote lookup. A failed or
cancelled refresh cannot create a new direct quote from the old marker. Funding
height moves and stored block-hash changes rewind the card DB before rebuilding
the witness. Known outgoing claims also rewind their previous mined state when
the node reports them missing, unmined, or mined at another height. Recovery
resubmits the existing signed bytes under the existing lifecycle and expiry
policy; it does not create a replacement claim automatically.

If the funding transaction must be replaced by a new txid, the issuer must
regenerate and redistribute the link. There is no resolver or automatic scan
that discovers the replacement for the printed URL. This is an external
issuance responsibility, not an application creation-UI feature. A mined card
does not expire merely because it is old; transaction expiry matters if an
unmined transaction can no longer be included. See
[ZIP 203](https://zips.z.cash/zip-0203).

### Privacy trade-offs under validation

The payload contains the card's bearer recovery secret, not the recipient's
wallet seed, account name, profile, or passcode. Possession of the link already
grants access to the card's funds and recoverable transaction history. Adding
the funding txid makes it easier to correlate cards funded in the same batch.
Correlation among cards distributed by the same event host is accepted for
this use case. It does not authorize exposing recipient IPs or changing the
privacy policy of ordinary sends.

Direct `GetTransaction` requests disclose the requested txid to lightwalletd.
In direct networking mode, the server can associate it with the connecting IP;
Tor changes that transport exposure but does not hide the requested txid from
the server. The funding txid does not reveal shielded addresses or amounts on
its own. A funding transaction that contains transparent components may expose
those components independently of this feature.

Using a witness at the funding block also uses an older on-chain anchor than
ordinary sends. This can distinguish the event claims and link them as a
cohort; it does not by itself prove which shielded output was spent. Zcash's
[wallet guidance on anchor selection](https://zips.z.cash/zip-0315#anchor-selection)
recommends a fixed depth near the tip. This departure needs explicit review
before release; it must not change ordinary wallet sends.

## Rollout and local testing

Ordinary cards use v3 sharing by default, with no build flag. Event options
select v4. The gateway must accept opaque `#v3=` and `#v4=` envelopes. Ordinary
recipients need a v3-capable wallet; event recipients need a v4-capable wallet.
There is no online recipient capability check or automatic downgrade for older
apps. These local changes do not deploy the gateway.

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

### Event direct-claim integration lane

The disposable stack uses different ports from the shared regtest stack. Its
node configuration activates Ironwood at height 500. Build the existing local
`vizor-ironwood-regtest-lightwalletd:latest` image before running it. Start with
empty `.regtest/zcashd` and `.regtest/lightwalletd` directories in an isolated
checkout; do not reuse a personal wallet or reset another test stack.

```sh
docker compose -f docker-compose.direct-gift-regtest.yml up -d
# In a second terminal; counts real RPCs and injects submission outages.
node scripts/regtest/direct-gift-rpc-proxy.cjs
# Fresh chain: Orchard, then Ironwood with 5,000 blocks after funding.
VIZOR_DIRECT_GIFT_COMPOSE="$PWD/docker-compose.direct-gift-regtest.yml" \
  cargo test --manifest-path rust/Cargo.toml --test regtest_direct_gift_claim \
  known_funding_block_claims_without_scanning_the_historical_gap \
  -- --ignored --nocapture --test-threads=1
```

For subsequent runs on this same owned chain, set
`VIZOR_DIRECT_GIFT_REUSE_CHAIN=1`. That lane uses a shorter 200-block funding gap
while retaining duplicate, reorg, failed-submission recovery, and expiry checks.
The test never clears the chain. An explicit fixture lane funds a new card for
the native mobile walkthrough:

```sh
VIZOR_DIRECT_GIFT_COMPOSE="$PWD/docker-compose.direct-gift-regtest.yml" \
  VIZOR_DIRECT_GIFT_FIXTURE_OUTPUT=/tmp/vizor-event-gift-fixture.json \
  cargo test --manifest-path rust/Cargo.toml --test regtest_direct_gift_claim \
  create_mobile_event_fixture -- --ignored --nocapture --test-threads=1
```

Run `integration_test/regtest_mobile_event_gift_onboarding_test.dart` on a
disposable iOS Simulator with
`fvm flutter test --tags mobile --run-skipped -d <simulator-uuid>`, supplying
these dart-defines: `VIZOR_FORM_FACTOR=mobile`, `ZCASH_DEFAULT_NETWORK=regtest`,
`ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=500`,
`ZCASH_E2E_LIGHTWALLETD_URL=http://127.0.0.1:9267`,
`ZCASH_E2E_ZCASHD_RPC_URL=http://127.0.0.1:18252`,
`VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true`, and
`VIZOR_EVENT_GIFT_FIXTURE=<base64-encoded fixture JSON>`.
The JSON contains a bearer secret: keep it local and delete it after use.
This scenario uses the actual app, passcode setup, account creation, proof,
submission, and recipient sync. The separate Widgetbook skip-scan walkthrough
is only a deterministic UX preview.

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
