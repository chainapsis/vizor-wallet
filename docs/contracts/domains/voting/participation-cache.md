# Voting participation cache and recovery

Use when changing persistence, refresh cancellation, cache invalidation, or partial participation recovery.

Implementation: [voting_participation_provider.dart](../../../../lib/src/providers/voting/voting_participation_provider.dart).

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

## Related changes

For proof verification, trust assumptions, or RPC request limits, read
[participation proof](participation-proof.md). A failed proof never means unused rights.
