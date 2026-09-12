# Send contract

## Scope and entry points

This contract covers ordinary Send and donation transfers across desktop and
mobile, including software execution, Keystone handoff, cancellation, and the
status receipt. Swap deposits and Gift Card funding reuse parts of the send
stack but have their own ownership rules.

- Dart orchestration: [`send_flow.dart`](../../lib/src/features/send/services/send_flow.dart)
  (`SendReviewArgs`, `proposeSendTransfer`, `discardSendProposal`,
  `runSendBroadcast`).
- Desktop review: [`send_review_screen.dart`](../../lib/src/features/send/screens/send_review_screen.dart).
- Mobile composer and review: [`mobile_send_screen.dart`](../../lib/src/features/send/screens/mobile/mobile_send_screen.dart).
- Rust software execution: [`send.rs`](../../rust/src/wallet/sync/send.rs).
- Rust hardware execution: [`pczt.rs`](../../rust/src/wallet/sync/pczt.rs).

## Amount and fee validation

- Parse decimal input with
  [`parseZecAmount`](../../lib/src/core/formatting/zec_amount.dart) into integer
  zatoshi (`BigInt`), accepting at most eight fractional digits. Do not derive
  execution amounts from floating-point values or rounded display text.
- Desktop/mobile composers estimate fees as inputs change and reject stale
  estimates with input-generation checks. Validate amount plus fee against
  usable spendable funds before Review; proposal creation in Rust remains the
  final authority.

## Proposal ownership

`proposeSendTransfer` waits for authoritative spendable state, then creates a
Rust proposal and returns its `proposalId`, `sendFlowId`, proposal account,
amount, fee, address type, and Sapling-parameter requirement. Keep the proposal
account and both IDs together through review, signing, cleanup, and status;
the active account may change independently.

Rust stores proposals in memory and locks their selected wallet inputs in
SQLite. Software execution and PCZT creation consume the in-memory proposal on
entry, but the owner-scoped input lock remains until completion or explicit
cleanup. A consumed proposal is therefore not proof that its inputs are free.

Every exit that has not handed ownership to execution must call the idempotent
`discardSendProposal`. It retries Rust release three times, then refreshes the
proposal account's balance. `true` means both release and refresh completed.
A `false` result must keep retry unavailable; it may be retried idempotently,
and height expiry remains the final lock-release fallback.

## Review, signing, and cancellation

- A software send hands `SendReviewArgs` to the status route, which executes
  and broadcasts it.
- A hardware send creates and proves PCZT data, obtains Keystone signatures,
  then hands `KeystoneBroadcastArgs` to status. A signature is not a broadcast
  receipt.
- Desktop review cancel releases the proposal before leaving Send or Donation.
- Desktop Keystone cancel releases and refreshes, then reproposes the same
  address, amount, memo, request framing, and `sendFlowId`. The user remains on
  Review with a fresh fee and proposal. Failed recovery leaves Review inactive
  and offers cancellation again.
- Mobile Keystone cancel returns a null signing result. The composer preserves
  its recipient, amount, memo, contact, and review step, waits for release and
  balance refresh, invalidates Max and fee snapshots, then refreshes the review
  fee before Confirm becomes available.
- Scanner "Back to QR code" only resets the current signing scan. It is not a
  send cancellation. Cancellation and back are disabled while a signature is
  being decoded or finalized.

Review and signing are payment-URI busy surfaces. Their hold must outlast
proposal release so a parked request cannot pre-check or propose against inputs
that the abandoned send still owns.

## Broadcast results

`runSendBroadcast` returns `succeeded`, `pendingBroadcast`, `failed`, or
`aborted`, plus whether Rust consumed the proposal. It obtains Sapling
parameters when required, executes software signing or hardware PCZT
finalization, applies endpoint failover policy, and refreshes wallet state.

After transaction creation, transport or partial-broadcast failures are
recoverable pending outcomes rather than permission to resend. TEX receipts
use the final dependent transaction; ordinary sends use the first transaction.
An expired hardware transaction is a failure that requires a fresh review.
Errors before broadcast release the proposal. An ambiguous hardware broadcast
may retain its input lock until expiry to prevent a conflicting retry.

Software mnemonic bytes are fetched only for the proposal account, passed to
Rust, and overwritten immediately after starting execution. macOS may instead
use the native stored-mnemonic path. Hardware accounts never enter either
software-key branch.

## Verification map

- [`send_proposal_release_test.dart`](../../test/features/send/send_proposal_release_test.dart):
  retry, refresh, owner identity, and lock-release behavior.
- [`send_review_screen_test.dart`](../../test/features/send/send_review_screen_test.dart):
  desktop cancellation, re-proposal, disposal, and status handoff.
- [`mobile_send_screen_test.dart`](../../test/features/send/mobile_send_screen_test.dart):
  preserved review inputs, cancellation ordering, refreshed fees, and busy
  surfaces.
- [`mobile_keystone_pczt_signing_flow_test.dart`](../../test/features/keystone/mobile_keystone_pczt_signing_flow_test.dart):
  QR/scanner transitions and finalization guards.

See [hardware signing](hardware-signing.md) for PCZT roles and protocol
exceptions. See [lock and sync](lock-sync.md) for the broader wallet lifecycle.
