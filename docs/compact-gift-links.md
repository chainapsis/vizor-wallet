# Compact gift links (v3 and v4)

V3 encodes the original English BIP-39 entropy in the fragment of
`https://link.vizor.cash/payment-links/open#v3=<payload>`. The origin remains
configurable through `VIZOR_DEEPLINK_BASE_URL`. No resolver, remote presentation
lookup, or new route is needed. New gifts use 12 words. Decoding continues to
support existing 12, 15, 18, 21, and 24 word phrases in v1–v3. V4 fixes
event phrases at 12 words.

V4 is a compact binary format for mainnet event cards. A required funding txid
selects direct claim without a separate `skipScan` flag. Network, fiat value,
custom labels, and birthday height are omitted from sharing. Artwork and an
optional message remain inline. Ordinary cards continue sharing as unchanged v3 JSON.

Event links are issued and printed with separate tooling. The application's
single-card and batch-creation UI continues creating ordinary cards; this
change adds no event-mode toggle or funding-txid input to that UI. Event
redemption applies at the shared claim boundary, including onboarding,
Settings → My gift cards, and interrupted-claim recovery.

The txid-based claim code is carried over from the earlier event-card work.
The local checks cover encoding, decoding, recovery, shared claim routing,
and funded direct claims. Regtest uses the local recovery envelope rather than
mainnet v4 sharing, so those runs do not qualify deployed v4 wire handoff.

The message remains inline. It is not placed in, or fetched from, a funding
transaction memo. The amount retains its existing advertised-recipient meaning.
V4 has no shared birthday; its isolated claim wallet uses Sapling activation
as a stable local birthday and still processes only identified transaction blocks.

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

The v3 writer rounds the display-only USD snapshot to two decimal places and
keeps it a JSON number. Readers continue accepting older full-precision USD
snapshots in v1, v2, and v3 without rounding them. Local v2 recovery records
retain their original precision; resharing a card rounds only the v3 snapshot.
The ZEC amount, mnemonic, birthday, and claim calculations are unaffected.

The complete URL is bounded to 16 KiB before decoding. Both Base64url strings
use only `A-Z`, `a-z`, `0-9`, `-`, and `_`, without padding or noncanonical trailing
bits. JSON whitespace and normal JSON string escaping are accepted. Wrong
field types, missing required fields, extra fields, and out-of-range values are
rejected using the existing presentation and recovery limits.

Strings keep the existing trimmed semantics. Artwork IDs are ASCII identifiers
of at most 64 characters; unknown IDs use the local artwork fallback. Messages
remain limited to 128 grapheme clusters and 512 UTF-8 bytes.

Entropy is 16, 20, 24, 28, or 32 bytes, reconstructing the original English
mnemonic with an empty BIP-39 passphrase and ZIP32 account zero. New gifts use
16 bytes, or 12 words, instead of 32 bytes, or 24 words. This changes only new
gift funding accounts; existing funded secrets are never shortened. Ordinary
wallet creation and the recipient wallet automatically created during Gift
Card onboarding continue using independent 24-word mnemonics. Legacy cards with
alternate mnemonic whitespace share as v2 after verifying the original address
and validating the canonical phrase. Their original secret, recovery records,
and claim-cache identity remain unchanged. Other conversion or address-validation
errors fail sharing; they never trigger a v2 fallback.
Synchronous FFI only converts mnemonic and entropy; address validation remains
asynchronous and local.

V3 uses standard JSON serialization, with no binary header, bit flags, length
prefixes, artwork-code registry, or custom checksum. JSON parsing validates the
structure, and the claim flow verifies actual funding. This replaces the
unreleased binary v3 prototype; v1/v2 compatibility is preserved.

## V4 binary schema

The fragment is `#v4=<unpadded Base64url>`. Decode once to the bytes below.
V4 always means mainnet; it never takes its network from the current wallet.
Sharing a non-mainnet card as v4 is rejected even in a regtest-enabled build.
Earlier unreleased JSON and binary v4 layouts are replaced without
compatibility branches.

| Order | Value | Bytes |
| --- | --- | --- |
| 0 | Original 12-word BIP-39 entropy | 16 |
| 1 | Positive recipient amount in zatoshi | 8, unsigned big-endian |
| 2 | Full funding txid | 32, display-hex byte order |
| 3 | Artwork code | 1 |
| 4 | Optional message | All remaining bytes, UTF-8 |

The fixed prefix is 57 bytes. There is no header, birthday, message flag, or
message length prefix. Exactly 57 bytes means no message; a longer payload
uses its entire tail as the message. No string field follows it. V4 accepts
only 16-byte entropy (12 words); ordinary v1–v3 retain every supported size.
Labels are not shared; readers use `Payment link`. Messages must be valid
UTF-8, nonempty and already trimmed, with the existing 128-grapheme and
512-byte limits. Truncation of the fixed prefix or a UTF-8 sequence, unknown
artwork codes, noncanonical Base64url, and out-of-range amounts are rejected
before mnemonic reconstruction. Links must also fit v2 recovery. This format
does not promise to detect changes to otherwise valid entropy, txid, or message
bytes; claim preparation verifies the funding transaction against its reported
block and decrypts it with the card's key.

The SDK birthday remains local metadata, not a scan request: mainnet uses its
Sapling activation height from the existing network configuration. Direct claim
never falls back to a birthday-to-tip scan. Event caches use network, mnemonic,
and funding txid; their identity does not change when funding is remined at a
different height. This also avoids setting the birthday at a height that a
funding reorg could move behind. V2 local recovery stores this local birthday
alongside the txid, destination, and submission evidence.

A fresh activation-birthday DB can have no chain tip. Before the SDK's existing
transaction-height lookup, direct preparation initializes a missing tip with
the already-fetched value. An existing tip is preserved for reorg detection:
the SDK filters transaction heights above that tip. The regular post-rewind
tip update remains in place. No additional RPC is introduced.

Txid bytes are the successive pairs of its conventional 64-character display
hex, in the same order. They are not a numeric field and are not reversed by
this codec. The existing Rust transaction lookup converts them to protocol
order. This carries all 256 bits, without truncation or a block locator.

Artwork codes are permanent and independent of UI enum order:

| Code | Artwork ID |
| --- | --- |
| 0 | No specified artwork |
| 1 | `knight` |
| 2 | `chestLava` |
| 3 | `chestCave` |
| 4 | `dragon` |
| 5 | `knightMagic` |
| 6 | `gandalf` |
| 7 | `crystal` |
| 8 | `diamond` |
| 9 | `ruby` |
| 10 | `coin` |
| 11 | `gift` |

Append new codes; never renumber or reuse assigned values. V3 retains string
artwork IDs and its existing fallback for unknown strings. V4 writers reject
unregistered artwork IDs instead of silently dropping the chosen image.

### Size vectors

All sizes include the 46-character default HTTPS prefix. Event gifts use
12 words (16-byte entropy); no message yields 57 payload bytes, 76 Base64url
characters, and a **122-character URL**, with artwork. Adding
`It's a great day to shield your ZEC 🛡️` adds 43 UTF-8 bytes and yields a
**180-character URL**. A message can increase the total; 122 is not an upper
bound on every card.

The public zero-entropy vectors use recipient amount 1,000,000 zatoshi,
artwork `knightMagic`, and txid bytes 1–32. Do not fund this published secret.

```text
No message: AAAAAAAAAAAAAAAAAAAAAAAAAAAAD0JAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAF
Example message: AAAAAAAAAAAAAAAAAAAAAAAAAAAAD0JAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAFSXQncyBhIGdyZWF0IGRheSB0byBzaGllbGQgeW91ciBaRUMg8J-boe-4jw
```

| 12-word sample | V3 URL characters | V4 URL characters |
| --- | ---: | ---: |
| No artwork, fiat, or message | 114 | 122 |
| Artwork; no fiat or message | 133 | 122 |
| Artwork and fiat; no message | 144 | 122 |
| Artwork and message; no fiat | 201 | 180 |
| Artwork, fiat, and message | 205 | 180 |

V3 uses birthday 3,483,141 and, where present, fiat 11.1747. V4 omits both and
adds the full funding txid. Amount, entropy, artwork, and message are the same.
The minimal v3 link remains shorter because it carries no funding txid.

## Compatibility and recovery

`toShareUri()` writes v3 for ordinary cards and binary v4 for cards carrying a
funding txid. The verified sharing helper preserves v2 for existing ordinary
cards with legacy mnemonic whitespace. Event cards reject that whitespace.
`toRecoveryUri()` continues writing the established local v2 JSON representation;
`toUri()` remains its alias. The event funding txid persists as a named field in
local recovery and implies direct claim. There is no separate stored scan flag.
Sender addresses, creation times, status, funding transactions, and claim
submission evidence stay in their existing secure records. The v4 share writer
omits creation-time fiat and custom labels without mutating the sender's local model.
A recipient obtains its own current price through the existing claim flow.
Incoming links must fit their expanded v2 recovery URI within 16 KiB.

`preparePaymentLinkShareUri()` verifies a locally known address against the
mnemonic before dropping it from compact sharing. A failure leaves the record
untouched and reports a sharing error. Funding creation checks the selected
share and recovery representations before the durable draft and broadcast.
All funding signers share this path. No retry replaces a funded secret.

Ordinary claim caches continue using network, mnemonic, and birthday, including
the existing legacy-directory preference when submission evidence exists. Event
caches use network, mnemonic, and the validated funding txid, without birthday,
and never reuse an ordinary card's legacy cache. Intake
equality continues comparing normalized logical payloads rather than the wire
version. Different amounts, labels, or presentation remain distinct; birthday
changes matter only to ordinary cards. Event recovery normalizes its local
birthday to network activation.
Persisted funding txid, destination, and submission evidence must
survive restart and must not be overwritten by an incoming policy-free link.
Cached quotes and proposals must not carry event preparation into ordinary
claims or retain stale preparation after a failed verification.

Desktop and mobile share ordinary cards as v3 without an older-version copy
option. Event links require a v4-capable reader.
Existing v1 and v2 links remain readable.

| Reader | v1 | v2 | v3 | v4 |
| --- | --- | --- | --- | --- |
| V1-only Vizor | Yes | No | No | No |
| V2-capable Vizor | Yes | Yes | No | No |
| Existing v3 reader | Yes | Yes | Yes | No |
| This implementation | Yes | Yes | Yes | Yes |

An older installed app may intercept a new link before a browser fallback can
help. Recipients need a v3-capable build for ordinary compact links and a
v4-capable build for event links. Existing v1/v2/v3 links remain readable
without migration.

### Direct event claim

V3 keeps its original four-to-eight-entry JSON array and rejects extra fields.
Every valid v4 link contains one funding txid and selects direct claim. There
is no v4 mode for ordinary scanning. Use v3 for ordinary cards. A missing or
malformed v4 txid makes the payload invalid; RPC failure remains retryable and
never triggers an automatic historical scan. One funding transaction may fund
multiple event cards. Multiple txids per card and discovery of later top-ups
are unsupported. Event links must identify confirmed funding before printing.

Event cache identities include their funding txid and never reuse ordinary
card caches. The v2 recovery representation is local storage, not the selected
event-sharing format. A restored event card retains its direct claim path.
Apps without a v4 reader reject v4 links rather than ignoring their semantics.

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

Ordinary cards use v3 sharing by default, with no build flag. A funding txid
selects binary v4. The gateway draft already accepts opaque `#v4=` envelopes
without parsing their contents, so the binary format needs no additional gateway
parser. Its `#v4=` support still needs deployment. Ordinary recipients need a
v3-capable wallet; event recipients need a v4-capable wallet.
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
`VIZOR_DIRECT_GIFT_REUSE_CHAIN=1` once Ironwood is active (height above 500).
That lane uses a shorter 200-block funding gap
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
This scenario uses the local v2 recovery envelope with its funding txid because
v4 sharing is mainnet-only. It covers the actual app, passcode setup, account
creation, proof, submission, and recipient sync; it does not qualify mainnet v4
wire handoff. The separate Widgetbook event walkthrough is a deterministic
UX preview.

Reader tests cover v1/v2 equivalence, persistence representation, JSON types and
positions, truncation, numeric bounds, unknown artwork, custom labels, Unicode,
and exact sizes. Native tests additionally verify real BIP-39
conversion and the retained funding address. The round-trip lane checks a real
funded gift through copy, import, claim, and confirmation. Hardware devices,
iOS/Android native handoff, and deployed browser behavior still require their
normal release qualification; unit tests are not a substitute for those checks.

## Synthetic reference and sizes

The following unfunded public vector uses 16 zero entropy bytes (11 `abandon`
words followed by `about`), mainnet, height 3,483,141, amount 1,000,000 zatoshi,
artwork `knightMagic`, USD 11.17, and the exact message
`It's a great day to shield your ZEC 🛡️`. Do not fund this published secret.

Its decoded JSON is:

```json
["main","AAAAAAAAAAAAAAAAAAAAAA",3483141,"1000000","knightMagic",11.17,"It's a great day to shield your ZEC 🛡️"]
```

The full link is:

```text
https://link.vizor.cash/payment-links/open#v3=WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNywiSXQncyBhIGdyZWF0IGRheSB0byBzaGllbGQgeW91ciBaRUMg8J-boe-4jyJd
```

It is 202 characters: 46 for the URL prefix and 156 for the Base64url encoding
of 117 JSON bytes. The message itself occupies 43 UTF-8 bytes.

| Contents, default label | 24 words (legacy) | 12 words (new gifts) |
| --- | ---: | ---: |
| Plain | 142 | 114 |
| Artwork and fiat | 169 | 141 |
| Artwork, fiat, example message | 230 | 202 |
| Artwork, fiat, 512-byte message | 856 | 828 |

The original v1 example in planning measured 914 characters. Its bearer secret
is not included in source or fixtures. Positional JSON retains a 77.9% reduction
for the decorated example, while using standard JSON tooling.

Twelve-word generation saves about 28 characters. Further size reductions are
deferred: `/gift` saves 14; placing the example message on-chain saves about 61 but
adds memo retrieval and its privacy/availability tradeoffs; compression has
variable savings and adds parser complexity.

## Validation for the binary v4 branch

Base: PR #830, `b1d2419307065c55984344da3fc1124dd0f4015e`.
Reviewed as draft PR #822, stacked on `feat/twelve-word-gift-cards` (#830).

- Dart codec, model, shared claim-service, inspection, and received-store tests:
  214 passed after removing v4 birthday/header/message-length fields. Includes
  legacy v1/v2/v3 vectors, binary v4 vectors, malformed input, mainnet-only
  sharing, actual parsed-v4 routing through the shared claim API, recipient
  restart evidence, and sender-local fiat and custom-label retention.
- Claim coordinator, interruption/recovery, and inspection checks: 71 passed
  (the default desktop lane skips one mobile-tagged test).
- Mobile Widgetbook onboarding walkthrough tests: 12 passed with the mobile
  form-factor define. The event case is a mock UX preview, not a funded claim.
- Rust direct-claim unit tests: 3 passed, including a real decrypted funding note
  derived from a newly generated 12-word gift account and a claim quote while
  historical scan gaps remain unscanned, with the local birthday at Sapling
  activation.
- Earlier native gift tests: 18 passed, including real BIP-39 conversion, funding-address
  preservation, and existing gift funding/signing restrictions.
- Bridge regenerated in the earlier #822 qualification with
  `scripts/generate-rust-bridge.sh`; this revision changes no Rust API.
- Rust library and integration-test targets passed `cargo check --tests` in that
  earlier qualification; current direct-claim unit and integration targets compile.
- Changed Rust files pass focused rustfmt checks. Whole-crate `cargo fmt --check`
  reports existing formatting differences in three unchanged files:
  `rust/src/wallet/sync/mod.rs`, `rust/tests/gift_link_legacy_whitespace.rs`, and
  `rust/tests/software_account_recovery.rs`.
- Deeplink server draft #3 validates an opaque v4 envelope, independently of
  this binary layout. Its earlier 31-test run used the previous 129/189-character
  vectors; server tests were not rerun for this layout change.

### Funded E2E after field removal (2026-10-03)

- Orchard and Ironwood cards both used the local activation birthday (regtest
  height 1). Funding was 203 blocks old; each card processed only one block,
  used four preparation RPCs, and delivered 50,000,000 zatoshi. Preparation took
  57 ms for Orchard and 60 ms for Ironwood on the local isolated stack.
- Orchard passed in the fresh-chain run. That run was intentionally stopped
  during the later 5,000-block mining step; it is not a complete fresh-lane pass.
  The Ironwood-active reuse lane then passed with a 200-block requested gap,
  including duplicate rejection, funding reorg, submission-outage recovery with
  the original signed transaction, claim reorg, and expired-claim retry.
- This run exposed a fresh-DB error: the SDK transaction-height lookup requires
  a chain tip even when the transaction is absent. The missing-tip initialization
  described above fixes it while preserving existing-tip/reorg ordering.
- Logs are recorded locally in `/tmp/vizor-v4-minimal-e2e.log` (Orchard phase),
  `/tmp/vizor-v4-minimal-reuse-e2e.log` (complete reuse lane), and
  `/tmp/vizor-v4-minimal-rust.log` (direct-claim unit tests).

### Earlier funded E2E validation (before field removal, 2026-10-03)

- The Rust direct-claim integration scenario passed on a newly created isolated
  regtest chain. Orchard funding was 203 blocks old; Ironwood funding was 5,003
  blocks old. Both card databases processed only one block, used four preparation
  RPCs, and delivered 50,000,000 zatoshi to their recipients.
- Duplicate claims were rejected. Funding reorg, submission-outage recovery with
  the original signed transaction, claim reorg, and expired-claim retry passed.
- The mobile event onboarding integration test passed on a disposable iPhone 17
  Pro Simulator running iOS 26.3.1. It exercised card inspection, passcode setup,
  account customization, the biometric opt-out, actual claim submission, and
  Home's `0.50 TAZ` balance and `Redeemed a gift card` activity.
- The initial Rust run exposed a fixture setup error: a birthday of 1 caused a
  request for unsupported tree-state height 0. The fixture funder now starts at
  the current chain tip; the rerun passed. No production code changed for this.
- Logs and source fingerprints are recorded locally in
  `/tmp/vizor-v4-e2e-results.json`, `/tmp/vizor-v4-e2e-rust.log`, and
  `/tmp/vizor-v4-e2e-mobile.log`.

The mobile test carries the event txid in the local v2 recovery envelope because
v4 sharing is mainnet-only. Mainnet v4 wire handoff through a deployed gateway,
production claims, and recording were not run. Recent-anchor preparation remains
separate from this change in PR #825.
