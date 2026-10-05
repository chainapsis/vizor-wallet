# Transparent history support: public and private modes

What Vizor's transaction history gets right for each case of the transparent
history qualification (H01-H13, wallet-libraries
`docs/transparent-pir-history-qualification.md`), in public mode
(lightwalletd discovery, production today) and in private mode
(`PrivateRequired`: recovery from a transparent PIR service, #839), measured by
the Rust layer of the H01-H13 suite (`rust/tests/transparent_history_cases`)
on an isolated regtest chain.

Runs: 2026-10-05, branch `claude/tpir-private-history` (on #839 `4e1427a6c`,
wallet-libraries main `bdebaffcb`). Private column: `e216252bc`, Rust layer
241 s. Public column: `9c7b005a1`, Rust layer 180 s; `e216252bc` changes only
the private profile's balance check, so the public result stands for it. Both
profiles ran the same cases, each on its own chain. The expectations come from
zcashd and the authored case intent only (the suite's oracle), never from
Vizor.

## How to read the table

Variants: **R** is the wallet that built or observed each transaction, **O**
is a copy of R's files reopened, **N** is a fresh restore of the same seeds.
Fault variants: **N_pending** restores while H12's transactions are unmined;
**N_pre** is a fresh restore's first view; public injects **N_cut** (address
history streams cut) and **N_utxo_fail** (UTXO requests fail); private injects
**N_lag** (publication 60 blocks behind the tip) and **N_pir_fail** (every
private query answered 500). The suite has no N_seq variant (adding an account
to a synced wallet); #818 adds it.

Cell values:

- **pass**: every row and account check matches the profile exactly.
- **pass; incomplete by design: row (fields)**: passes, and the private
  profile accepts these rows as honestly incomplete, because private mode's
  evidence cannot complete them: the payment details of a transaction the
  wallet did not build (no `GetTransaction`, and regtest has no Enhance PIR),
  and the fee and pool of a transaction the account took part in only through
  its shielded notes. The movement is exact, nothing shown as final is false,
  and no fee is zero. The fields are what the wallet showed as incomplete:
  details (recipients), fee (unknown), pool (unknown), provisional
  (classification may change).
- **pass; details incomplete by design: row**: an exact amount and whole fee
  with the recipients unknown (private mode, a transparent-only send the
  account fully funded: the library reconstructs the payment from the
  recovered metadata).
- **fail (code)**: a product defect, listed below.
- **-**: the case has no such variant.

## Support table

| Case | Public R | Public O | Public N | Public faults | Private R | Private O | Private N | Private faults |
|---|---|---|---|---|---|---|---|---|
| H01 Transparent-only send | - | pass | fail (G1) | - | - | pass; details incomplete by design: send | pass; details incomplete by design: send | - |
| H02 Several inputs or recipients | - | pass | fail (G1) | - | - | pass; details incomplete by design: send | pass; details incomplete by design: send | - |
| H03 Ordinary transparent receive | pass | pass | pass | - | pass | pass | pass | - |
| H04 Retained local transaction | pass | pass | pass | - | pass | pass | pass | - |
| H05 Shared funding | - | fail (G2) | fail (G2) | - | - | fail (D2: fee unknown on shared funding) | fail (D2: fee unknown on shared funding) | - |
| H06 Self/cross-account transfer | pass | - | fail (G3) | - | pass; details incomplete by design: cross-account send; incomplete by design: self-transfer (details) | - | pass; details incomplete by design: cross-account send; incomplete by design: cross-account from Orchard (details, fee, pool, provisional), self-transfer (details) | - |
| H07 Owned shielding/unshielding | pass | pass | pass | - | pass | pass | fail (D2: fee unknown on shield, unshield) | - |
| H08 External transparent unshielding | pass | - | pass | - | pass | - | pass; incomplete by design: unshield to Bob (details, fee, pool, provisional) | - |
| H09 Other mixed-pool transaction | - | - | fail (G1) | - | - | - | fail (D2: fee unknown on mixed-pool send) | - |
| H10 TEX/multi-step operation | pass | - | pass | - | pass | - | fail (D2: fee unknown on TEX leg 1) | - |
| H11 Swap/gift-card operation | pass | - | pass | - | pass; incomplete by design: gift-card claim (details) | - | pass; incomplete by design: gift-card claim (details), gift-card create (details, fee, pool, provisional), swap deposit (details, fee, pool, provisional) | - |
| H12 Pending/expired/conflicted | pass (pending, pre-reorg, final) | - | fail (G4) | N_pending: pass | pass (pending, pre-reorg, final); details incomplete by design: conflicting spend (pre-reorg, final) | - | fail (D2: fee unknown on pending shield) | N_pending: pass |
| H13 Incomplete coverage | - | - | - | N_cut: fail (G5)<br>N_pre: pass<br>N_utxo_fail: pass | - | - | - | N_lag: pass<br>N_pir_fail: pass<br>N_pre: pass |

Gate verdicts. Public: H03, H04, H07, H08, H10 and H11 pass; H01, H02, H05,
H06, H09, H12 and H13 fail on G1-G5. Private: H01, H02, H03, H04, H06, H08,
H11 and H13 pass; H05, H07, H09, H10 and H12 fail on D2 alone. In both runs
all four negative controls (a wrong fee, a wrong input count, an omitted
ledger event, a wrong ownership mapping) make the comparison fail, as
required.

## Request capture

The requests each wallet made up to its last checkpoint, summed over the
variants of each profile. A transparent subject is an
address method (`GetAddressUtxosStream`, `GetTaddressTxids`) or a
`GetTransaction`: a request that names a transparent address or a txid to
lightwalletd.

| | Public | Private |
|---|---|---|
| lightwalletd requests | 870 | 332 |
| with a transparent subject | 524 (229 `GetAddressUtxosStream`, 72 `GetTaddressTxids`, 223 `GetTransaction`) | 0 |
| block and tree data (`GetLatestBlock`, `GetBlockRange`, `GetTreeState`, `GetSubtreeRoots`) | 320 | 303 |
| `SendTransaction` (the wallet's own transactions) | 26 | 29 |
| transparent PIR service requests | - | 1,648 (1,152 directory and 34 page queries, the rest catalog, manifest and setup) |
| privacy violations at the PIR service (Alice's script in a path, header or body, a query string, an unknown route) | - | 0 |

The private request policy allows block and tree data and the wallet's own
broadcasts only; any other method fails the run. Under `PrivateRequired` the
lookup gate withholds every transparent lookup, in every variant including
the faults.

## Product defects

Codes in the table. D codes are private-mode defects found by this run; G
codes are public-mode gaps the suite found earlier, which #818 addresses with
wallet-libraries PRs that are not merged (#87-#92). This run does not verify
#818.

**D1, fixed here (`9c7b005a1`): a privately recovered send showed as a
receive.** Under private recovery, a transparent-only send the account fully
funded is known from the transparent PIR events only. The library reconstructs
its exact payment from the recovered metadata (`AggregatePayment::Exact`,
classification `Reconstructed`, whole fee known), but no output the account
paid is visible, and Vizor's mapper ignored that payment: the debit fell
through to its change. A send of 1.25 ZEC with change showed as "received
1.7499 ZEC"; one without change showed as "unknown 0". Affected H01, H02, the
sending side of H06, H10 TEX leg 2 and H12's conflicting spend, in R, O and N.
The history read now keeps the reconstructed payment
(`HistoryCompleteness::inferred_payment` in
`rust/src/wallet/sync/transactions.rs`), and such a debit is one sent row with
that amount, the transparent pool, the known fee and incomplete details.
Public evidence carries no transaction metadata, so public rows are
unchanged. Two unit tests cover it.

**D2, open: the whole fee from the recovered metadata is not shown.** When the
account is not the sole transparent funder (shared funding, H05) or the
transaction has shielded components (shield and unshield, H07; mixed pool,
H09; TEX leg 1, H10; H12's pending shield once mined), the history row's fee is
unknown, although every recovered event of the transaction carries the exact
whole fee. The library's history read sets `fee` from the metadata only for a
sole-funded transparent-only transaction
(`zcash_client_sqlite/src/wallet/transparent_ledger/history.rs`, the `fee`
match, at `bdebaffcb`) and exposes the metadata separately in
`TransactionHistoryDetails::transaction_metadata`; Vizor maps only `fee`. The
ledger architecture lists the whole-transaction fee as covered before
enrichment for shared funding, and a shielding fee as shown when known. The
fee is honestly unknown, never zero, and nothing else in these rows fails. It
is not fixed here: Vizor subtracts a known fee from a provisional debit to
estimate the payment, so showing the whole fee of a shared transaction would
assign it to one account, which the ledger architecture rules out ("Do not
infer that account's payment amount or fee share"). The fix needs a whole fee
for display kept apart from the fee used in payment arithmetic, in the
library's history contract or in Vizor's mapper. For H09, H10 leg 1 and H12
the architecture does not list the fee as covered; the private profile expects
it because the recovered metadata has it.

**G1** (public, H01, H02, H09 N): a restored wallet's send has pool unknown,
incomplete details and a provisional mark after enrichment; #818 gaps 2 and 4.
**G2** (H05 N, O): a shared-funding transaction shows a payment amount, a
fabricated attribution; #818 gap 3. **G3** (H06 N): a self-transfer shows as a
receive of the gross output; #818 gaps 2 and 4. **G4** (H12 N): a restored
wallet misses an H12 receive and the conflicting spend; #818 gap 6. **G5**
(H13 N_cut): with address history streams cut, sync still reports success and
current authority; #818 gap 7.

## Harness defects fixed in this run

Harness defects, fixed and committed on this branch. The first three are
#818's harness fixes, cherry-picked without the rest of #818; the fourth is
new.

- `64bfdb681` (#818 `0139b39da`): the gate failed any case whose checkpoint
  label contains "fail", so H13 failed with every variant passing
  (`h13_pir_fail:pass`, `h13_utxo_fail:pass`).
- `02f7bfa55` (#818 `6d0a7f708`, V9): `detail_outputs_real` checked a received
  row's own receipts as payments. Only sent rows are checked now.
- `91d226874` (#818 `6ba005122`, gap 5b): the oracle compared the transparent
  balance with mined UTXOs only, so public H12 R failed on its reorged-away
  receive, which is back in the mempool and which Vizor's public policy
  counts in the transparent balance.
- `e216252bc`: with gap 5b, the private profile inherited the public rule that
  counts that pending receive. Under `PrivateRequired` the transparent balance
  is the recovered, confirmed ledger, and regtest has no status lane to show a
  receive is still pending, so private H12 R failed on that alone. The balance
  check now takes a profile flag; the private profile counts no unmined
  receive.

One private run (not the one tabled, run while a public run shared the
machine) stopped when the oracle crashed deriving H12's pending checkpoint:
`owned_ledger` got no transaction (`Chain.raw` returned `None`) for a txid
from zcashd's address index. The cause is not established; it did not recur in
the two later private runs, and it is not fixed.

## Limits of the private column

- The harness is the publisher: it builds the shards from zcashd with the
  extraction rules of wallet-pir's filter server and serves them in process
  over loopback HTTP. This qualifies Vizor's private mode against a correct
  publisher, not the production publisher.
- The adapter accepts mainnet maps only, so the regtest publication carries
  mainnet's network label and genesis hash; every block hash from height 1 is
  the real regtest one.
- Regtest has no Enhance PIR or status service, so a transaction the wallet did
  not build keeps incomplete details. On mainnet, payload PIR could complete
  some of the rows marked incomplete by design here; this run does not measure
  that.
- N_pre is weak in private mode: nothing is held, so its snapshot follows the
  first sync.
- Rust layer only. The app layer (desktop, mobile) has no private expectations.
- Debug builds only: the regtest switches (`ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT`,
  the loopback HTTP transport) are not compiled into release builds.

## Reproduce

From the repository root, with Docker running:

```bash
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/public" \
  scripts/e2e/transparent-history-cases.sh --profile public
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/private" \
  scripts/e2e/transparent-history-cases.sh --profile private
```

Each writes `results.json` (case by variant matrix, negative controls) and the
per-checkpoint `report-*.json`; the private run adds `pir-requests.json`. The
two profiles can run at the same time: each builds its own chain on its own
ports.
