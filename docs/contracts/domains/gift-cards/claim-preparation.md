# Gift Card claim preparation

Read when changing a claim destination, scan preparation, temporary-wallet reuse, or session discard.

- Funding and claim orchestration: [`payment_link_service.dart`](../../../../lib/src/features/payment_links/services/payment_link_service.dart).

Preparation requires an unlocked wallet, resolves the active destination address
again by captured account UUID, and rechecks lock and account state after the
async lookup. The destination must be shielded; the link network must match the
active endpoint.

The service validates the advertised birthday against the current tip, requests
confirmation before a long scan, then imports the bearer mnemonic into an isolated
temporary wallet directory. Reuse cached claim wallets only if their derived
address matches the link. Preparation syncs the wallet, computes maximum
claimable amount and fee, and reports funding confirmation and availability
without broadcasting.

Leaving a checked card may retain its record and scanned temporary wallet.
Discarding a claim session cancels its scan and deletes the temporary database.

## Verification

- [`payment_link_service_test.dart`](../../../../test/features/payment_links/payment_link_service_test.dart):
  destination identity and retained claim wallets.

## Related changes

- When changing submission or recovery after preparation, read [claim submission](claim-submission.md).
- When changing the meaning of availability, read [Gift Card claim outcomes](claim-outcomes.md).
