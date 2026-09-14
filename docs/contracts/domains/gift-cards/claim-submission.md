# Gift Card claim submission and recovery

Read when changing claim submission lifetime, persisted outcomes, concurrent recovery, or reset draining.

- Claim lifetime: [`payment_link_claim_coordinator_provider.dart`](../../../../lib/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart).
- Sender and receiver persistence: [`payment_link_recovery_store.dart`](../../../../lib/src/features/payment_links/services/payment_link_recovery_store.dart)
  and [`payment_link_received_store.dart`](../../../../lib/src/features/payment_links/services/payment_link_received_store.dart).

Before broadcast, claim start persists a ready record, captures the temporary
wallet's prior local txids, and marks destination binding. The coordinator
deduplicates submissions by card address; different cards can run concurrently.
Screen disposal does not own submission lifetime.

Broadcast results distinguish accepted, pending, and partial outcomes. Claim
txids and optional destination-pool metadata persist after submission; best-effort
pool lookup never changes lifecycle success. Known pre-submission errors return
the card to ready. Once submission may have crossed the network boundary, retain
the bearer link and temporary wallet for rebroadcast, reorg, and metadata recovery.

Recovery pauses while locked, resumes on unlock/app resume, serializes manual
and background inspection, and retries while any record needs recovery. Before
wallet reset, quiesce and drain submissions, retention writes, and recovery;
reject new work until reset completes. Active receiving claims protect their
destination account from deletion.

[Gift Card claim outcomes](claim-outcomes.md) is authoritative for
availability, transaction lifecycle, archive state, confirmation finality, and
older-record defaults. Do not duplicate its settlement matrix here.

## Verification

- [`payment_link_service_test.dart`](../../../../test/features/payment_links/payment_link_service_test.dart):
  claim boundaries and destination-pool metadata.
- [`payment_link_claim_coordinator_provider_test.dart`](../../../../test/features/payment_links/payment_link_claim_coordinator_provider_test.dart):
  concurrent claims, duplicate joining, lock/resume, and reset drain.
- [`payment_link_received_store_test.dart`](../../../../test/features/payment_links/payment_link_received_store_test.dart)
  and [`payment_link_recovery_reconciler_test.dart`](../../../../test/features/payment_links/payment_link_recovery_reconciler_test.dart):
  persisted invariants and restart recovery.

## Related changes

- When changing whole-wallet reset ordering, read [wallet reset](../wallet/reset.md).
- When changing destination-account deletion protections, read [account deletion](../accounts/delete.md).
- When changing lock/unlock transitions, read [wallet lock and unlock](../wallet/lock-unlock.md).
