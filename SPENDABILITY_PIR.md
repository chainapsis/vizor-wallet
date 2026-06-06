# Spendability PIR

This document maps the Spendability PIR execution flow in `vizor-wallet` across three actors:

- `vizor` (Dart + Rust entrypoints in this repo)
- `librustzcash` (wallet DB APIs and PIR witness validation/persistence)
- `pir server` (nullifier and witness endpoints)


## What problem does it solve

Your wallet has been inactive for a few weeks, you open it, and the funds are immediately spendable.

## What it does not solve

- Accounting for concurrent usage from multiple devices.
- Full DAG-sync balance reconstruction.

## How Does It Work

- At startup, we query all unspent notes and ensure that they have matching witnesses
- At spend height, we detect if all transactions within a proposal match anchor heights. If yes, spend is eligible. If not, we refresh witnesses to match.

- If there is a receipt further in the sync height, we currently do not account for it.
   * Ideally, we should detect it and refetch witnesses with matching heights for all unspent notes from that point. Alternatively, have a concurrent worker that monitors and updates.

## Startup Flow (Wallet Open)

At app startup (and also after unlock refresh), Vizor triggers a fire-and-forget startup PIR pass before normal sync continues.

### Sequence Diagram

```text
Actors: [vizor] [librustzcash] [pir server]

[vizor] -> [vizor]         wallet opens
[vizor] -> [vizor]         SyncNotifier._startInitialSync()
[vizor] -> [vizor]         PirSpendabilityNotifier.run()
[vizor] -> [vizor]         runStartupPir() -> api::pir::run_startup_pir()
[vizor] -> [vizor]         wallet::spendability_pir::run_startup_pir()

[vizor] -> [librustzcash]  get_unspent_orchard_notes_for_pir()
[librustzcash] -> [vizor]  unspent notes with nullifiers

LOOP nullifier preflight (for each note)
  [vizor] -> [pir server]  SpendClient.connect(/params,/metadata)
  [vizor] -> [pir server]  SpendClient.is_spent(nullifier) via POST /query
  [pir server] -> [vizor]  spent or unspent

IF any spent:
  [vizor] -> [vizor]       emit skipped(any_spent), stop witness PIR
ELSE none spent:
  [vizor] -> [librustzcash]  get_notes_needing_pir_witness()
  [librustzcash] -> [vizor]  notes needing witness refresh

  LOOP witness fetch (for each candidate note)
    [vizor] -> [pir server]   WitnessClient.connect(/params,/broadcast)
    [vizor] -> [pir server]   WitnessClient.get_witness(position) via POST /query
    [pir server] -> [vizor]   witness siblings + anchor root/height

    [vizor] -> [librustzcash] validate_pir_orchard_witness(...)
    [librustzcash] -> [vizor] validation result

    IF valid:
      [vizor] -> [librustzcash] insert_pir_witness(...)
    ELSE invalid:
      [vizor] -> [vizor]       skip insert for that note

  [vizor] -> [vizor]       emit done(witnesses_inserted)
```

## Concrete Call Chain

1. Dart startup trigger:
   - `lib/src/providers/sync_provider.dart`
   - `_startInitialSync()` calls:
     - `unawaited(ref.read(pirSpendabilityProvider.notifier).run())`
2. PIR provider:
   - `lib/src/providers/pir_spendability_provider.dart`
   - `PirSpendabilityNotifier.run()` calls:
     - `rust_pir.runStartupPir(...)`
3. Dart Rust bridge wrapper:
   - `lib/src/rust/api/pir.dart`
   - `runStartupPir(...)` forwards to FRB-generated API.
4. Rust API entrypoint:
   - `rust/src/api/pir.rs`
   - `run_startup_pir(...)` sets running/cancel guards and calls wallet PIR core.
5. Wallet PIR core:
   - `rust/src/wallet/spendability_pir.rs`
   - `run_startup_pir(...)` performs nullifier gate and witness fetch/insert loop.

## librustzcash Handoffs

The following `WalletDb` calls are invoked by Vizor's startup PIR runner:

- `get_unspent_orchard_notes_for_pir()`
- `get_notes_needing_pir_witness()`
- `validate_pir_orchard_witness(...)`
- `insert_pir_witness(...)`

These methods are exposed in:

- `librustzcash/zcash_client_sqlite/src/lib.rs`

and implemented in:

- `librustzcash/zcash_client_sqlite/src/wallet/spendability_pir.rs`

## PIR Server Calls

### Nullifier server

From `spendability-pir/nullifier/spend-client/src/lib.rs`:

- `SpendClient::connect(url)`:
  - GET `/params`
  - GET `/metadata`
- `SpendClient::is_spent(nullifier)`:
  - POST `/query`
  - decode PIR row and scan bucket for matching nullifier

### Witness server

From `spendability-pir/witness/witness-client/src/lib.rs`:

- `WitnessClient::connect(url)`:
  - GET `/params`
  - GET `/broadcast`
- `WitnessClient::get_witness(position)`:
  - validate position is inside server window
  - POST `/query`
  - decode row and reconstruct full witness path

## Branch and Control Behavior

- Startup PIR is intentionally fire-and-forget from Dart (`unawaited(...)`).
- Rust-side singleton guard:
  - `STARTUP_PIR_RUNNING` prevents concurrent runs.
- Rust cancellation:
  - `STARTUP_PIR_CANCEL` is checked in nullifier and witness loops.
- Progress is streamed to Dart using phases:
  - `nullifier`, `witness`, `skipped`, `done`.

## Spend-Time Follow-up (Optional Path)

PIR witnesses are consumed later during transaction creation:

- `rust/src/wallet/sync/send.rs`
  - `create_transactions_with_optional_pir_retry(...)`
  - `should_use_pir_witnesses(...)`
  - `refresh_proposal_pir_witnesses(...)` on PIR anchor mismatch

On anchor mismatch, Vizor refreshes witnesses for selected Orchard inputs and retries transaction creation once.
