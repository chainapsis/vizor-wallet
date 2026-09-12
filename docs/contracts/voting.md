# Voting contracts

Use this for account ownership, signing, recovery, and Home participation.
Protocol internals and detailed delivery policy remain in the
[Rust integration guide](../../rust/src/wallet/voting/README.md).

## Entry points

| Question | Implementation / detailed contract |
| --- | --- |
| Round UI and account changes | [voting_session_provider.dart](../../lib/src/providers/voting/voting_session_provider.dart): `VotingSessionNotifier` |
| Work that survives leaving the screen | [voting_submission_job_provider.dart](../../lib/src/providers/voting/voting_submission_job_provider.dart), `VotingSubmissionSessionNotifier` in the session library |
| Durable recovery plan | [voting_recovery_service.dart](../../lib/src/features/voting/voting_recovery_service.dart), [api/voting.rs](../../rust/src/api/voting.rs) |
| Home visibility and discovery | [voting-home-discovery.md](../voting-home-discovery.md) |
| Snapshot participation and cache | [voting-participation.md](../voting-participation.md), [voting_participation_provider.dart](../../lib/src/providers/voting/voting_participation_provider.dart) |
| Delete/reset drain | [voting_share_tracking_registry_provider.dart](../../lib/src/providers/voting/voting_share_tracking_registry_provider.dart), [wallet_mutation_guard.dart](../../lib/src/providers/wallet_mutation_guard.dart) |

## Ownership and durable state

- The SDK owns durable bundle/vote/share phases and restart planning. Vizor
  orchestrates those APIs; do not add parallel workflow tables or infer recovery
  phases from a transient screen state. Pass the round's complete proposal-ID
  set to `loadRoundPlan`; planner failures must propagate.
- Context includes wallet DB, network, source, account UUID, and round. Actions
  use their captured context. The foreground session listens for account
  changes, advances its generation, and reloads for the new account; stale
  results cannot update that new UI.
- Background submission sessions are separately keyed and pinned to their
  original account. They deliberately do not follow the foreground account
  listener. Switching accounts or disposing a screen must not clear work still
  owned by an active submission.
- Per-account/per-round hotkeys are random secrets stored by Dart. A missing
  hotkey after hotkey-bound artifacts exist is a recovery error; regenerating
  one or deriving it from the wallet seed cannot recover the old voting rights.
  Software delegation SpendAuth signing needs the wallet seed; hotkey generation
  and later vote signing do not. Hardware delegation uses the device signer.

## Signing, cancellation, and recovery

- Reload durable recovery state before deciding which bundles/proposals/shares
  still need work. Serialize mutating UI actions through `_enqueue`.
- Validate Keystone request identity, expected bundle/signature counts, and
  signature contents before persisting. Validation/persistence errors remain
  recoverable scan errors so the same response can be scanned again.
- Cancelling signing preserves saved partial signatures. On reentry, reload
  them and request only unsigned bundles. Closing the QR scanner is not the
  same operation as abandoning the signing screen. See
  [hardware signing](hardware-signing.md) for the batch transport boundary.
- A submission/accepted share is not equivalent to chain confirmation. Keep
  exact durable artifacts and pending work available for retry/recovery;
  completed local voting can hide Home even without another participation RPC.
- Process-local vote-tree reset does not delete durable recovery rows or stop
  already running proof jobs. `reset_voting_session_state` additionally clears
  unsigned abandoned delegation setup; it is not a harmless warmup reset.
- Helper-share tracking can outlive foreground submission. Register its owner
  before dropping the submission guard. The tracking registry is the drain
  barrier even after the status job has finished its foreground work.

## Home and participation

- Unknown Home rounds start hidden. A verified remaining eligible subset or
  actionable local recovery confirms visibility; an active round alone does
  not. Preserve the last confirmed decision while checking, syncing, or failing.
  Settings remains an entry point independently of Home visibility.
- Bootstrap does not wait for voting storage. Home first renders, then loads
  summaries asynchronously. Its minute timer reevaluates deadlines in memory;
  it does not poll discovery or participation.
- Viewing-key snapshot inspection supports UFVK-only hardware accounts without
  signing or proof generation. Used voting rights do not prove every proposal
  was voted on. Existing local recovery takes precedence over preparing new
  delegation state.
- Participation proofs and their trust assumptions, request limits, cancellation,
  backoff, and cache invalidation are defined in
  [voting-participation.md](../voting-participation.md). The current used/unused
  cache assumes voting occurs only in this app and the voting chain has finality;
  it has no periodic TTL revalidation. Do not treat a failed proof as unused.
- Route requests through the configured network transport. Participation
  queries expose correlatable governance identifiers to the vote RPC; do not
  log query keys, URLs, evidence, or raw transport errors.

## Destructive operations

- Work that may read/write wallet-side voting state or secure storage registers
  before its first asynchronous step. `beginBackgroundWork` may reject a new
  lease while quiesced; callers must not start that work anyway.
- Account deletion/reset blocks new work and awaits existing leases/tracking
  before deleting account or wallet data. A timer cancellation alone is not a
  drain. Keep migration quiescence and foreground sync pause ordering intact;
  see [account storage](account-storage.md) and [lock/sync](lock-sync.md).
- Lock/account/network/source changes invalidate asynchronous results. Deleting
  caches must not be confused with deleting durable voting recovery records.
  Account deletion and full reset have different cleanup scopes.

## Focused verification

- [Voting providers](../../test/providers/voting/voting_providers_test.dart):
  account changes, pinned submissions, partial signing, participation and drain.
- [Recovery service](../../test/features/voting/voting_recovery_service_test.dart):
  bundle/proposal keys, exact retry artifacts, and remaining planner work.
- [Mutation guard](../../test/providers/wallet_mutation_guard_test.dart):
  destructive drain before sync pause and mutation/failure recovery.
- Source-only or mocked checks do not prove real voting-chain/device behavior;
  relevant regtest runners are documented in the existing participation guide.
