# Payment Links and Gift Cards contract

## Scope and entry points

A Vizor Gift Card is a bearer payment link: its fragment contains the mnemonic
for a generated temporary wallet. Treat the URI and every persisted recovery
record as secret material. Opening or checking a link does not reserve its
funds; competing claims are resolved by the chain.

- Payload validation: [`vizor_payment_link.dart`](../../lib/src/features/payment_links/models/vizor_payment_link.dart).
- Funding and claim orchestration: [`payment_link_service.dart`](../../lib/src/features/payment_links/services/payment_link_service.dart).
- Incoming queue: [`payment_link_intake_provider.dart`](../../lib/src/features/payment_links/providers/payment_link_intake_provider.dart).
- Claim lifetime: [`payment_link_claim_coordinator_provider.dart`](../../lib/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart).
- Sender and receiver persistence: [`payment_link_recovery_store.dart`](../../lib/src/features/payment_links/services/payment_link_recovery_store.dart)
  and [`payment_link_received_store.dart`](../../lib/src/features/payment_links/services/payment_link_received_store.dart).

## Payload and intake

Version 1 accepts the Vizor payment-link endpoint, a fragment-only `v1=`
payload, supported network, positive amount, recovery phrase, positive birthday
height, valid timestamp, and bounded presentation fields. The fiat snapshot is
display-only and never participates in funding or claim math.

Incoming links use a bounded in-memory FIFO of 16 items. They do not expire and
survive wallet reset because they claim funds outside the current wallet.
Identical canonical payloads coalesce; matching account/birthday alone does not
make two links duplicates. Malformed or overflow links never clear an earlier
queued bearer secret. Entry policy defers navigation during onboarding,
unlock-sensitive tasks, Send, Swap, Pay, migration, voting, and a live ZIP-321
request card.

## Deep-link origin

- [`VizorDeepLink`](../../lib/src/core/navigation/vizor_deep_link.dart) reads
  `VIZOR_DEEPLINK_BASE_URL`, defaulting to `https://link.vizor.cash`.
  [`classifyIncomingLink`](../../lib/src/core/navigation/incoming_link_dispatch.dart)
  owns path classification: bare origin and `/` without query/fragment open
  Home; `/payment-links/open` carries Gift Cards. Unknown paths on this origin
  stop there without falling through to ZIP-321 parsing or logging bearer data.
- Android derives its manifest host and native allowlist from the same Flutter
  dart-define in [`build.gradle.kts`](../../android/app/build.gradle.kts). Do not
  introduce an independent Gradle/environment knob. Direct Gradle invocation
  falls back to the default host.
- iOS separately uses `VIZOR_DEEPLINK_HOST` in
  [`ios/Flutter/`](../../ios/Flutter) xcconfigs for its plist and entitlements.
  Change it together with the Dart origin. Mobile universal-link verification
  needs public HTTPS association files; test recipes are in the
  [E2E guide](../../scripts/e2e/README.md#gift-cards).

## Sender funding and recovery

Funding sends the requested amount plus a fixed claim-fee reserve to one newly
generated shielded account. Quote totals keep recipient amount, funding fee,
and claim reserve distinct. The link's recovery draft is persisted before any
proposal can cross the signing/broadcast boundary.

Software funding records that submission began before broadcast. Hardware
funding additionally records the prepared txid and expiry after proofs, before
showing completion. Once submission may have started, failures retain the draft
because retrying funding could duplicate value. A funded card remains protected
until it is marked shared; source-account deletion checks unshared funded cards.
An uncertain hardware response becomes shareable only with sufficient mined
evidence.

Keystone funding follows [hardware signing](hardware-signing.md). Cancellation
must release the proposal before removing an unbroadcast draft. A proposal
release or authoritative balance-refresh failure keeps cancellation/retry
incomplete. Removing the unbroadcast recovery draft is best-effort; a failed
removal retains its record but does not by itself block returning to Review.

## Claim preparation and destination

Preparation requires an unlocked wallet and resolves the active destination
address again by its captured account UUID. It rechecks lock and account state
after the async lookup. The destination must be shielded and the link network
must match the active endpoint.

The service validates the advertised birthday against the current tip, asks for
confirmation before a long scan, then imports the bearer mnemonic into an
isolated temporary wallet directory. Existing cached claim wallets are reused
only when their derived address matches the link. Preparation syncs that wallet,
computes the maximum claimable amount and fee, and reports funding confirmation
and availability without broadcasting.

Leaving a checked card may retain its record and scanned temporary wallet.
Discarding a claim session cancels its scan and deletes the temporary database.

## Submission, persistence, and recovery

Starting a claim persists a ready record, captures the temporary wallet's prior
local txids, and marks the destination binding before broadcast. The coordinator
deduplicates submissions by card address while allowing different cards to run
concurrently. Screen disposal does not own the submission lifetime.

Broadcast results distinguish accepted, pending, and partial outcomes. Claim
txids and optional destination-pool metadata are persisted after submission;
pool lookup is best-effort and never changes lifecycle success. If an error is
known to occur before submission, the card returns to ready. Once submission
may have crossed the network boundary, the bearer link and temporary wallet stay
available for rebroadcast, reorg, and metadata recovery.

Recovery pauses while locked, resumes on unlock/app resume, serializes manual
and background inspection, and retries while any record needs recovery. Wallet
reset first quiesces and drains submissions, retention writes, and recovery;
new work is rejected until reset completes. Active receiving claims protect
their destination account from deletion.

Availability, transaction lifecycle, archive state, confirmation finality, and
older-record defaults are detailed in
[Gift Card claim outcomes](../gift-card-claim-outcomes.md). Keep that document
as the authority instead of duplicating its settlement matrix here.

## Verification map

- [`vizor_payment_link_test.dart`](../../test/features/payment_links/vizor_payment_link_test.dart)
  and [`payment_link_intake_provider_test.dart`](../../test/features/payment_links/payment_link_intake_provider_test.dart):
  payload rejection, canonical identity, FIFO, and capacity.
- [`payment_link_service_test.dart`](../../test/features/payment_links/payment_link_service_test.dart):
  funding/claim boundaries, destination identity, metadata, and retained wallets.
- [`payment_link_claim_coordinator_provider_test.dart`](../../test/features/payment_links/payment_link_claim_coordinator_provider_test.dart):
  concurrent claims, duplicate joining, lock/resume, and reset drain.
- [`payment_link_received_store_test.dart`](../../test/features/payment_links/payment_link_received_store_test.dart)
  and [`payment_link_recovery_reconciler_test.dart`](../../test/features/payment_links/payment_link_recovery_reconciler_test.dart):
  persisted invariants and restart recovery.

See [security lifecycle](security-lifecycle.md) for locked storage and reset
ordering, and [account storage](account-storage.md) for deletion protections.
