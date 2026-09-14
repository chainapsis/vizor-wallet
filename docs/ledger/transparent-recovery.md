# Ledger transparent recovery

Import stores the Ledger UFVK and returns to Home. The next wallet sync recovers
mined transparent history for that one BIP44 account, without another device
connection. This is not discovery of additional hardened accounts.

## Initial recovery

- Query `GetTaddressTxids` (the existing compatible name for the full-transaction
  history RPC) from height 0 to a fixed tip for each external/internal address.
- Use `GapLimits::default()`: external 10, internal 5. A fully spent address still
  extends discovery because use is determined from history, not remaining UTXOs.
- Keep at most four history streams open. Drain and store transaction bodies
  incrementally rather than retaining an address's full history in memory.
- Persist each address's completion only after its stream finishes successfully.
  An error, malformed transaction, or cancellation never counts as an unused
  address. Replaying partially stored history is idempotent.
- Store per-scope progress in `ext_vizor_ledger_initial_discovery` in the wallet DB.
  A restarted pass checks its saved tip hash. Wallet rewinds invalidate affected
  checkpoints before truncation; account deletion removes its checkpoints.
- Home does not expose recovery status. The existing shielding status and PCZT
  creation paths reject shielding until both scopes complete.

## Normal sync and shielding

Completed accounts do not repeat history discovery on subsequent syncs. Existing
UTXO refreshes cover registered candidates; librustzcash grows the address gap
when it observes use. Ledger UTXO queries do not assume transparent funds were
received after the shielded birthday. This does not guarantee discovery if an
external wallet uses and fully spends an entire candidate window while Vizor is
offline, then moves beyond it. Explicit extended recovery is outside this change.

Each Shield action selects at most 10 inputs, matching Vizor's current conservative
Ledger serializer limit. Larger balances are shielded with subsequent actions;
the normal signed-operation checkpoint/retry pipeline remains responsible for
broadcast recovery. Inputs retain the selected account, scope and address index.
No additional discovery UI, periodic full-history job, or account picker is added.

## Verification

Automated tests use a deterministic in-process history source with real wallet
DBs and transaction parsing/storage. They cover fully spent history beyond both
initial gaps, pre-birthday transactions, retry after a stream failure, reopening
the DB, cancellation, chain changes, and bounded shielding PCZT construction.

For a device/data check, run the macOS debug app normally and watch Rust logs:

```sh
log stream --level info --predicate 'subsystem == "frb_user" AND eventMessage CONTAINS "ledger discovery:"'
```

Import the Ledger account and approve viewing-key export. The device is no longer
needed for discovery. Check the logged account/scope/index, `used`, gap count and
completion against known Ledger Live history. Restart during recovery to check
resume, then sync again after completion: there should be no new history requests
for that completed account. Keys, UFVKs and addresses are not logged by discovery.
Actual device signing and broadcasting remain a separate user-operated check;
automated tests do not move funds.

## Bounded transparent refresh costs

Ledger external and ordinary internal scopes each select the highest 20 child
indices plus up to 20 older indices in a rotating sweep. The unused gap candidates
are included in the highest indices. Ephemeral/standalone receivers and software
internal receivers keep their prior snapshot behavior.

Each selection is split into unqueried and previously checked addresses, so a new
candidate does not pull checked addresses back to height 0. Each scope schedules
at most four UTXO RPCs for at most 40 addresses per refresh; the global concurrency
limit remains four streams. Checked addresses use the minimum checked height in
the batch, with a 100-block lookback. Older addresses remain eligible indefinitely:
a fresh payment to one can be delayed until its sweep turn. For 1,000 addresses,
one complete sweep requires 49 refreshes; this is not a wall-clock guarantee.

Cache completion is published only after UTXO persistence. Internal metadata is
stored separately from external metadata in the existing receive sidecar and
survives receive-address cache regeneration. Wallet rewinds persist a new epoch
in `ext_vizor_transparent_refresh_epoch` before truncation, including anchor-root
repairs. A sidecar from an earlier epoch discards both scopes' query heights and
sweep positions. The reset may perform extra bounded queries but cannot skip
rewound data because of stale heights. As with the existing external path, an
unavailable/corrupt sidecar falls back to a complete snapshot with a warning;
the 40-address bound applies to healthy-cache operation, not this fallback.

Initial history recovery now reads only the next bounded range of cached
transparent receivers from SQLite instead of repeatedly decoding and sorting all
receivers. It still drains complete transaction histories and preserves the same
gap/retry rules. Repeated transaction processing and interleaving discovery with
shielded scanning are intentionally unchanged.

Cost logs contain account UUID/scope, address or transaction counts, RPC counts,
protobuf response bytes (excluding transport overhead), and elapsed milliseconds.
They contain no address/key material. Planning and per-UTXO-request times are
separate; history-body timing includes parsing/storage but excludes stream opening.
To collect them along with discovery progress:

```sh
log stream --level info --predicate 'subsystem == "frb_user" AND (eventMessage CONTAINS "transparent refresh" OR eventMessage CONTAINS "ledger discovery")'
```

Deterministic tests exercise 1,000-address bounded round-robin coverage, fresh
candidates, cache persistence and scope separation, failed/uncommitted plans,
rewind invalidation, and agreement with the library's receiver set. Production
network/device timings must be measured with real account data; unit-test counts
are not a latency benchmark.
