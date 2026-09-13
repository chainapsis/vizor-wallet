# Restored voting participation

Home schedules a client-side check for active candidate rounds (including those whose Home card is hidden) after
wallet sync settles with the snapshot available. Detail entry also waits for the same deduplicated
check before preparing voting power. The list preview and submission/recovery
jobs do not start another participation check. Home keeps its card hidden until a positive actionable result is confirmed.
Previously confirmed visibility is retained while checks wait or fail. Settings remains a permanent entry point.

Rust reads the account's Orchard full viewing key and snapshot notes. It derives
real-note governance nullifiers with the pinned `zcash_voting` SDK. This works for
UFVK-only Keystone accounts without QR interaction, spending keys, hotkeys, PIR,
or proof generation. Actual voting still uses the existing signer flow.

The Dart client uses the wallet's network HTTP transport, including its Tor policy.
It reads `/commit`, `/validators`, then one `/abci_query` per previously unknown real note, four at a
time, at the signed header height minus one. Each request has a ten-second timeout;
a check has a four-minute budget and a 1,024-note cap. It does not query Lambda
with account identifiers. A vote RPC can observe and correlate the queried
governance identifiers; this is not private information retrieval. Do not log
query URLs, keys, evidence, or raw transport errors.

## Proof and trust boundary

The Cosmos vote store key is `01 00 || round_id || governance_nullifier`.
Rust verifies IAVL membership (value `01`) or non-membership, then the multistore
proof for `vote` against the signed header's app hash. It checks chain ID, height,
header hash, time (at most ten minutes old or one minute ahead), validator-set
hash and the Tendermint commit's signature quorum. Missing/pruned/invalid proofs
remain unknown. Valid sibling proofs are retained; unknown notes are not used to
prepare a new delegation. A partial result only changes visibility when its
proven unused subset already meets the voting threshold. Otherwise the prior
display decision is retained.
Without a previous decision, the card stays hidden.

This is a reader anchored to a bundled consensus committee, not a full rotating
light client. The bundled public keys and original voting powers live in
`rust/src/wallet/voting/trust/`. Their hashes must match the original pins below,
which were captured from the official RPCs on 2026-09-10:

| Network | Chain | RPC | Validator-set hash |
| --- | --- | --- | --- |
| main | zvote-1 | https://vote-rpc-primary.valargroup.org | 621A1E2C532170C3C0BC2E951D26C1CCA7A0EFB009AA15820D648D336C64F6BD |
| test | svote-1 | https://stage.vote-rpc-primary.valargroup.org | 6E81F631CB63A527AB5A659529BA8942C46CCF78BA87D1B3AD4CF8AE5BDC2E8B |

The initial trust anchor relies on that official HTTPS bootstrap. The current
validator set must hash to the signed header, but need not hash to the bundled
pin. The same commit must have strictly more than two-thirds signing power under
both the bundled original powers and the current powers. Public-key/address
consistency, duplicate validators/signers and voting-power bounds are checked.
New powers cannot inflate a signer's contribution under the bundled anchor.

This permits limited validator replacement and power changes without more RPCs.
It does not advance the trust anchor or implement a time-bounded rotating light
client. Cumulative changes that lose the bundled >2/3 quorum require a reviewed
anchor update. The original committee remains a long-lived trust assumption;
this does not provide automatic protection against compromise of its retired
keys. Custom sources remain unsupported. Regtest retains its explicit disposable
exact-set anchor. Failed checks preserve the last confirmed display decision.

## Persistence and recovery

Before note inspection, the coordinator loads the durable local round plan
using the authenticated round's complete proposal IDs. Actionable recovery or
remaining local proposals restore Home visibility; full completion hides it.
These decisions do not require the participation RPC, even when the Home
summary is missing. Participation backoff does not block local recovery when
round details are already available. New round details still require the
existing config/status data path; this is not a fully offline discovery path.
An explicit forced check still inspects notes after saving the local decision.

Each verified note observation is stored in Dart app-private ordinary files beside
its wallet DB (`<wallet-db>.voting-cache`), not secure storage. The scope is
network / account UUID / round ID / snapshot / governance derivation version.
Records hold the full governance store key, a used/unused flag and proof height;
they contain no viewing keys, spend keys, note plaintext or vote secrets.
Both used and unused observations persist until the round ends. The current
policy assumes voting occurs only in this app and the Tendermint voting chain
has finality: no TTL or periodic revalidation of a known note is performed.

Full wallet reset sweeps wallet-named voting-cache directories in the app's
support directory after draining voting work. It does not depend on the current
secure-storage DB name, so cache deletion can be retried after a partial reset
has already erased that name. One failed directory does not prevent cleanup of
the others; failures still make reset report an error. Per-account deletion
continues to remove only that account's observations.

Rust re-derives the current snapshot candidates and calculates eligibility from
the known unused subset. Only unknown keys require RPC. A shared header is
verified once and each note proof independently; successful siblings survive
partial failures. Existing durable delegation confirmations promote matching
notes to used without an RPC, including confirmations recovered after restart.
Merging is monotonic: a late unused result cannot overwrite used.

Consecutive failures back off for 1, 2, 4, 8, 16, then at most 30 minutes, per
network/source/account/round. Home reentry, foregrounding, sync completion and
relevant provider changes can retry after that deadline; the deadline alone
does not start a retry, and the Home minute timer never checks participation.
Only remaining unknown notes are queried.
Backoff lives in memory and resets after success. Cancelled work (lock, account
or source change) and incomplete sync do not increase the delay.
Detail's **Check again** refreshes round details and reevaluates candidates and
eligibility, reusing known note observations.

Each durable fact stores an `unknown`, `show` or `hide` decision separately from
`needsRecheck`. A successful participation result confirms `show` only when
`remainingEligible` is true; `unavailable == false` alone is insufficient (it
also includes empty wallets). Existing local bundles require the recovery planner
with the round's proposal IDs before deciding whether work remains. Missing
proposals or a failed planner call preserves the previous successful observation.
Eligibility-only positive results are not enough to promote an unknown card.

Sync progress heights never invalidate a decision. Dart registers inspected
snapshot heights using tiny revision files. Rust changes those tokens before
an actual affected scan/rewind and after affected Orchard note mutations.
Scans entirely above a snapshot leave its token unchanged, regardless of how
many new blocks arrive. After sync, a changed token triggers local candidate
reevaluation; unchanged governance keys reuse their observations, and only new
keys are queried. A token change during evaluation rejects the round summary
while retaining verified note observations. This supports Zcash rescans/rewinds
without assuming monotonically increasing displayed progress.

Home summaries are also ordinary files. Home renders before loading them
asynchronously; a saved show decision restores independently of sync or RPC.
App bootstrap does not wait for voting storage. Loaded summaries stay in memory
across Home reentry.
There is no old-cache migration. A changed round snapshot discards the old
summary; closure, deadlines, completion and account/source/network scoping
remain independent of sync. Explicit terminal round status deletes its note
files and prevents late writes from recreating them. Missing listings or an
individual proposal ending do not delete the whole round cache. Tiny snapshot
revision/ended-round markers remain until wallet reset; account deletion removes
that account's notes. Real voting/recovery records are not disposed with caches.

Verified used notes are excluded from new eligibility, precomputation and all
software/Keystone delegation preparation paths. The adapter retains the SDK's
selection layout, witness, proof and signing algorithms. The sidecar's
`vizor_voting_participation` table belongs to Vizor and is cleared on account
deletion. Existing bundle plans are never rewritten: local recovery takes
precedence, including when a bundle was concurrently prepared.

If some unused notes still meet the SDK's voting threshold, voting remains
available with that subset. If used notes leave no eligible bundle and there is
no existing local bundle state, Home hides the card and detail explains that
voting cannot be restarted on this device. This means the snapshot voting rights
were used for delegation; it does **not** prove every proposal was voted on.
Lost voting hotkey secrets cannot be recreated from a wallet seed or Keystone UFVK.

All asynchronous checking/persistence registers with the account deletion/reset
drain before its first await. Account/network/source/lock changes cancel results;
queued checks are serialized and concurrent checks for a round share one future.

## Not enforced on the SDK round-session branch

Discovery still runs and still records the exclusion set, but **bundle
planning does not currently consult it.**

`participation::filter_notes` used to run inside `participation::prepare_bundle`,
which replaced the SDK's own bundle preparation. Once voting execution moved
into the SDK round session, the SDK derives the note set itself:
`delegate::prepare_delegation_bundle` (reached from
`delegation_pipeline/proving.rs` while proving) re-plans from an unfiltered
selection and then calls `require_bundle_notes` against the persisted rows.

That makes partial filtering worse than none. A plan persisted from a filtered
set fails the SDK's own check with `bundle_index N notes do not match persisted
setup`, so filtering in `setup_delegation_bundles` alone would break delegation
for precisely the wallets that have exclusions. The note set has to be derived
identically everywhere, and one of those places is inside the pinned SDK.

Re-enabling this needs the SDK to filter its own selection — a note-filter hook
on `DelegationPipeline`/`prepare_delegation_bundle` — after which
`setup_delegation_bundles`, `check_voting_eligibility`, and snapshot precompute
can all filter again. `prepare_bundle` is kept as the reference for what that
wiring looked like.

## Validation

The JSON fixtures in `rust/tests/fixtures/voting-participation` contain public
mainnet/stage signed headers, validator sets, and actual membership/non-membership
proofs. Tests use each fixture header's timestamp, so they remain deterministic.
Corruption tests cover signatures, validator power, app hash, query key/height,
proof bytes, value, wrong network and stale/future headers. Deterministic signed
headers also cover partial validator replacement, changed powers, both strict
quorum boundaries, forged validator addresses and duplicate signers. No private wallet
material is included.

## Mobile reinstall regtest E2E

Run `scripts/e2e/flutter-ios-regtest-mobile-voting-reinstall.sh` with an explicit
`SIMULATOR_UDID` when multiple simulators are booted. The existing mobile voting
runner also asserts that a fully completed vote removes its Home card and
persists the confirmed hidden decision. Before voting it checks unused note
observations on disk; after delegation it checks that used observations persist.

The reinstall runner keeps the same Zcash and vote chain alive between two
Flutter integration invocations. Phase one imports, syncs and votes through the
real mobile UI. The host verifies the app is uninstalled after Flutter test cleanup,
explicitly uninstalling it if the Flutter runner leaves it installed. Phase two asserts the old DB/sidecar are absent, clears only
the regtest app's surviving secure storage, and imports the same mnemonic from
birthday 1. The test checks that the ordinary voting-cache directory is absent
before cleanup, rather than inspecting an obsolete secure-storage key. No
database, voting hotkey, progress or participation cache is copied.

Tests configure transport/source support and the newly created local chain's
trust anchor. They do not override eligibility, participation, Home visibility,
or cryptographic verification. The regtest anchor is immutable for that process
and is never consulted for mainnet/testnet. The gateway relays actual CometBFT
proofs and records aggregate request counts without logging queried identifiers.

The restored Home assertion requires an active round in the actual cached list,
a synced snapshot, verified used notes, no remaining voting rights and no local
recovery state. It then asserts the card is absent, checks Settings/detail access,
and checks that Home reentry does not repeat participation RPCs. Request counts
are compared against the start of the restore phase so first-phase requests
cannot satisfy the restored-check assertion. Both unused and used observations
are reevaluated with a fresh client and a forced check, proving disk reuse without
additional participation RPCs. Initial hidden UI alone never satisfies the test:
it requires a confirmed hide decision. Screenshots are
saved under `.regtest-voting/logs/screenshots/`.

Home participation work stops at asynchronous boundaries when Home is left or
the app backgrounds. An already dispatched request may finish; subsequent
requests, evaluation and remaining rounds are skipped. A new Home visit gets a
new scope, while explicit detail checks remain independent of Home visibility.
Round details are retained in memory per network/config/account/round only while
waiting for snapshot sync, avoiding repeated detail requests during that wait.
Manual retries fetch fresh details.

Within one participation check, a transient HTTP failure retries only that request
once after 300 ms. Successful responses and the selected proof height are retained.
Permanent HTTP errors, malformed data and failed proof verification are not retried
inside the operation. The four-minute budget and Home cancellation still apply;
a final failure falls back to the coordinator's exponential backoff.

When preparation finds no unknown snapshot notes, no participation RPC is sent.
Rust rereads the wallet and reevaluates the same candidate fingerprint using
locally stored observations. The existing local result/persistence path still runs; zero notes never
means previously used voting rights. It confirms a hidden Home decision when
there is no actionable local recovery.
