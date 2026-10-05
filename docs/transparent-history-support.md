# Transparent history support: public and private modes

What Vizor's transaction history gets right for each case of the transparent
history qualification (H01-H13, wallet-libraries
`docs/transparent-pir-history-qualification.md`), in public mode
(lightwalletd discovery, production today) and in private mode
(`PrivateRequired`: recovery from a transparent PIR service, #839), measured by
the H01-H13 suite on an isolated regtest chain: its Rust layer
(`rust/tests/transparent_history_cases`) in both profiles, and its desktop app
layer (`integration_test/regtest_transparent_history_cases_test.dart`, the
macOS app) in both modes.

Runs: 2026-10-05, branch `claude/tpir-private-history` on #839 `c65418c33`
(D1 and D2 fixed), wallet-libraries main `bdebaffcb`.

| Run | Commit | Output | Time | Exit |
|---|---|---|---|---|
| Private, Rust layer | `b889501a2` | `private3` | 298 s | 0 |
| Public, Rust layer | `b889501a2` | `public3` | 192 s | 101 (G1-G5) |
| Public, Rust and desktop app layers | `552b96b3e` | `public-desktop` | 133 s + 456 s | 101, 1 |
| Private, Rust and desktop app layers | `51649c973` | `private-desktop` | 237 s + 172 s | 0, 0 |

`552b96b3e` changes only the desktop runner's environment, so the Rust results
at `b889501a2` stand for it; the desktop run's Rust matrix is identical to
`public3`. Each run builds its own chain. The expectations come from zcashd
and the authored case intent only (the suite's oracle), never from Vizor.

## How to read the table

Variants: **R** is the wallet that built or observed each transaction, **O**
is a copy of R's files reopened, **N** is a fresh restore of the same seeds.
Fault variants: **N_pending** restores while H12's transactions are unmined;
**N_pre** is a fresh restore's first view; public injects **N_cut** (address
history streams cut) and **N_utxo_fail** (UTXO requests fail); private injects
**N_lag** (publication 60 blocks behind the tip) and **N_pir_fail** (every
private query answered 500). The suite has no N_seq variant (adding an account
to a synced wallet); #818 adds it. **App** is a fresh restore (N) in the
macOS app, checking each expected activity row's title, amount, pool label,
detail status and whole fee: 49 rows over 11 cases in public mode; in
private mode 47 rows over the same cases, three of them optional, also
checking the "Details incomplete" marker on the row and the receipt.

Cell values:

- **pass**: every row and account check matches the profile exactly.
- **pass; incomplete by design: row (fields)**: passes, and the private
  profile accepts these rows as honestly incomplete, because private mode's
  evidence cannot complete them: the payment details of a transaction the
  wallet did not build (no `GetTransaction`, and regtest has no Enhance PIR),
  the pool and classification of one the account did not fund alone or that
  has shielded components, and the fee of one the account took part in only
  through its shielded notes. The movement is exact, nothing shown as final
  is false, and a shown fee is the whole fee, never zero. Fields: details
  (recipients), fee (unknown), pool (unknown), provisional (classification
  may change).
- **pass; details incomplete by design: row**: an exact amount and whole fee
  with the recipients unknown (private mode, a transparent-only send the
  account fully funded: the library reconstructs the payment from the
  recovered metadata).
- **fail (code)**: a product defect or gap, listed below.
- **-**: the case has no such variant. **not run**: see the run table.

## Support table

| Case | Public R | Public O | Public N | Public faults | Public app | Private R | Private O | Private N | Private faults | Private app |
|---|---|---|---|---|---|---|---|---|---|---|
| H01 Transparent-only send | - | pass | fail (G1) | - | fail (G1) | - | pass; details incomplete by design: send | pass; details incomplete by design: send | - | pass (2 rows); details incomplete by design: send |
| H02 Several inputs or recipients | - | pass | fail (G1) | - | fail (G1) | - | pass; details incomplete by design: send | pass; details incomplete by design: send | - | pass (4 rows); details incomplete by design: send |
| H03 Ordinary transparent receive | pass | pass | pass | - | pass | pass | pass | pass | - | pass (3 rows) |
| H04 Retained local transaction | pass | pass | pass | - | - | pass | pass | pass | - | - |
| H05 Shared funding | - | fail (G2) | fail (G2) | - | pass (row and fee only) | - | pass; incomplete by design: shared funding (details, pool, provisional) | pass; incomplete by design: shared funding (details, pool, provisional) | - | pass (6 rows); 3 marked incomplete |
| H06 Self/cross-account transfer | pass | - | fail (G3) | - | fail (G3) | pass; details incomplete by design: cross-account send; incomplete by design: self-transfer (details) | - | pass; details incomplete by design: cross-account send; incomplete by design: cross-account from Orchard (details, fee, pool, provisional), self-transfer (details) | - | pass (8 rows); 4 marked incomplete |
| H07 Owned shielding/unshielding | pass | pass | pass | - | pass | pass | pass | pass; incomplete by design: shield, self-unshield (details, pool, provisional) | - | pass (4 rows); 3 marked incomplete |
| H08 External transparent unshielding | pass | - | pass | - | pass | pass | - | pass; incomplete by design: unshield to Bob (details, fee, pool, provisional) | - | pass (2 rows); 2 marked incomplete |
| H09 Other mixed-pool transaction | - | - | fail (G1) | - | fail (G6) | - | - | pass; incomplete by design: mixed-pool send (details, pool, provisional) | - | pass (2 rows); 1 marked incomplete |
| H10 TEX/multi-step operation | pass | - | pass | - | pass | pass | - | pass; details incomplete by design: TEX leg 2; incomplete by design: TEX leg 1 (details, pool, provisional) | - | pass (4 rows, TEX leg 1 shown); 3 marked incomplete |
| H11 Swap/gift-card operation | pass | - | pass | - | pass | pass; incomplete by design: gift-card claim (details) | - | pass; incomplete by design: gift-card claim (details), gift-card create (details, fee, pool, provisional), swap deposit (details, fee, pool, provisional) | - | pass (5 rows); 5 marked incomplete |
| H12 Pending/expired/conflicted | pass (pending, pre-reorg, final) | - | fail (G4) | N_pending: pass | fail (G4) | pass (pending, pre-reorg, final); details incomplete by design: conflicting spend (pre-reorg, final) | - | pass; details incomplete by design: conflicting spend; incomplete by design: pending shield (details, pool, provisional) | N_pending: pass | pass (6 rows; the unmined receive, optional, not shown); 3 marked incomplete |
| H13 Incomplete coverage | - | - | - | N_cut: fail (G5)<br>N_pre: pass<br>N_utxo_fail: pass | - | - | - | - | N_lag: pass<br>N_pir_fail: pass<br>N_pre: pass | - |

Gate verdicts. Private: all 13 cases pass. Public: H03, H04, H07, H08, H10
and H11 pass; H01, H02, H05, H06, H09, H12 and H13 fail on G1-G5. In every
run all four negative controls (a wrong fee, a wrong input count, an omitted
ledger event, a wrong ownership mapping) make the comparison fail, as
required. Public app layer: 8 of 49 rows fail, in H01, H02, H06, H09 and H12.
Private app layer: every row passes. The unmined H12 receive is optional and
not shown: private recovery reads mined blocks, and the mempool observer
matches shielded outputs only.
For shared funding (H05) the app layer checks only that a row exists and that
a shown fee is the whole fee; the Rust layer checks its amount.

## Request capture

The requests each wallet made, summed over checkpoints and variants. A
transparent subject is an address method (`GetAddressUtxosStream`,
`GetTaddressTxids`) or a `GetTransaction`: a request that names a transparent
address or a txid to lightwalletd.

| | Public | Private |
|---|---|---|
| lightwalletd requests | 868 | 332 |
| with a transparent subject | 529 (226 `GetAddressUtxosStream`, 80 `GetTaddressTxids`, 223 `GetTransaction`) | 0 |
| block and tree data (`GetLatestBlock`, `GetBlockRange`, `GetTreeState`, `GetSubtreeRoots`) | 313 | 303 |
| `SendTransaction` (the wallet's own transactions) | 26 | 29 |
| transparent PIR service requests | - | 1,648 (1,152 directory and 34 page queries, the rest catalog, manifest and setup) |
| privacy violations at the PIR service (Alice's script in a path, header or body, a query string, an unknown route) | - | 0 |

The private request policy allows block and tree data and the wallet's own
broadcasts only; any other method fails the run. Under `PrivateRequired` the
lookup gate withholds every transparent lookup, in every variant including
the faults. The private capture is identical to the run before D2's fix, which
changes display only. The public desktop run's Rust layer made 871 requests
(525 with a transparent subject: 229, 75 and 221; 320 block and tree; 26
broadcasts); the public app layer's own requests are not captured.

The private app layer reaches lightwalletd through a recording proxy
(`private-desktop`, whose Rust layer made 341 requests, none with a
transparent subject). The app made 44 lightwalletd requests, none with a
transparent subject: 26 `GetLatestBlock`, 4 `GetBlock`, 2 `GetBlockRange`, 2
`GetTreeState`, 4 `GetSubtreeRoots`, 3 `GetLightdInfo` and 3
`GetMempoolStream` (the whole mempool, no subject). It made 78 transparent PIR
requests (56 directory and 2 page queries), with no privacy violation.

## Product defects

D codes are private-mode defects found by these runs. G codes are public-mode
gaps; G1-G5 were found earlier and #818 addresses them with wallet-libraries
PRs that are not merged (#87-#92). These runs do not verify #818.

**D1, fixed in #839 (`2dbfb2758`): a privately recovered send showed as a
receive.** A transparent-only send the account fully funded is known from the
transparent PIR events only. The library reconstructs its exact payment
(`AggregatePayment::Exact`, classification `Reconstructed`, whole fee known),
but Vizor's mapper ignored it, so the debit fell through to its change: a send
of 1.25 ZEC showed as "received 1.7499 ZEC". It affected H01, H02, the sending
side of H06, H10 TEX leg 2 and H12's conflicting spend. Such a debit is now one
sent row with the reconstructed amount, the transparent pool, the known fee
and incomplete details (`HistoryCompleteness::inferred_payment` in
`rust/src/wallet/sync/transactions.rs`). Two unit tests.

**D2, fixed in #839 (`c65418c33`): the whole fee from the recovered metadata
was not shown.** When the account did not fund a transaction alone or it has
shielded components, the account's fee is unknown, although the library's
`TransactionHistoryDetails::transaction_metadata` carries the exact whole fee.
Vizor now keeps that whole fee apart from the account's fee
(`HistoryCompleteness::whole_fee`): when the account's fee is unknown and the
metadata has `WholeTransactionFee::Exact`, every row of the transaction shows
it as the network fee. It is display only: provisional debits, pending sends
and payments are still computed with the account's fee, so a shared fee is
never charged to one account. A recorded account fee or a provable absence of
one wins, public evidence carries no metadata, and the library is unchanged.
Four unit tests. In the private run the fee is now known, amounts unchanged:
H05 O and N 15,000 on A0 and A1; H07 N shield 65,000, self-unshield 15,000;
H09 N 15,000; H10 N leg 1 15,000; H12 N pending shield 20,000. Rows where the
account took part only through shielded notes keep an unknown fee: H06's
cross-account from Orchard, H08's unshield to Bob, H11's gift-card create and
swap deposit. On these incomplete rows the amount is the account's movement,
which already includes the fee, so the shown fee overlaps it (H07 N shield:
amount 65,000, fee 65,000; H05 N A1: 150,015,000 and fee 15,000). No list row
adds the two; only the gift-card batch detail sums amount and fee.

**D3, fixed in #839 (`0b08b3659`): a reorged-away receive's detail failed in
private R and O.** H12's receive that a reorg returned to the mempool showed
correctly in the list, but its transaction detail read failed with "Invalid
column type Null at index: 3, name: expired_unmined":
`read_history_base_by_txid` read `v_transactions.expired_unmined` as a non-null
bool. The fix applies #836's change and regression test to this path; the suite
does not open detail screens, so it does not check this row.

**G1** (H01, H02, H09 N): a restored wallet's send has pool unknown,
incomplete details and a provisional mark after enrichment; in the app, the
H01 and H02 sent rows have no pool label; #818 gaps 2 and 4. **G2** (H05 N,
O): a shared-funding transaction shows a payment amount, a fabricated
attribution; #818 gap 3. **G3** (H06 N): a self-transfer shows as a receive of
the gross output (app: no sent row, "+1.9999" where "+1.2" is expected); #818
gaps 2 and 4. **G4** (H12 N): a restored wallet misses an H12 receive and the
conflicting spend (the app also misses the pending receive, still after 11
extra syncs); #818 gap 6. **G5** (H13 N_cut): with address history streams
cut, sync still reports success and current authority; #818 gap 7. **G6**
(H09 app, new): once its details are fetched, the mixed-pool send shows the
gross transparent spend ("-1.9998", Mixed) and a separate "+0.7" shielded
change receive, where "-1.2998" is expected. The Rust layer's R and O rows
show the same split, and did before D2's fix, but the suite evaluates H09 in
N only, where the row is not yet enriched. Not matched to a #818 gap.

## Harness defects fixed

Fixed and committed on this branch. The first three are #818's harness fixes,
cherry-picked without the rest of #818.

- `02ff99d3d` (#818 `0139b39da`): the gate failed any case whose checkpoint
  label contains "fail", so H13 failed with every variant passing.
- `825d8c3a4` (#818 `6d0a7f708`, V9): `detail_outputs_real` checked a received
  row's own receipts as payments. Only sent rows are checked now.
- `2e09e4a59` (#818 `6ba005122`, gap 5b): the oracle compared the transparent
  balance with mined UTXOs only, so public H12 R failed on its reorged-away
  receive, which is back in the mempool and which Vizor's public policy
  counts.
- `2fc2f9a82`: with gap 5b, the private profile inherited the rule that counts
  that pending receive. Under `PrivateRequired` the transparent balance is the
  recovered, confirmed ledger, and regtest has no status lane to show the
  receive pending, so the private profile counts no unmined receive.
- `552b96b3e`: the Rust layer makes every ephemeral (TEX) address check due on
  each sync (`ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW=1`) but the desktop app layer
  did not, so the app checked them on its daily schedule and never found H10's
  TEX leg 2. The runner now passes the switch to the macOS app, and H10
  passes. The mobile layer still lacks it.

One earlier private run, while a public run shared the machine, stopped when
the oracle crashed deriving H12's pending checkpoint (`Chain.raw` returned
`None` for a txid from zcashd's address index). The cause is not established;
it has not recurred, and it is not fixed.

## Limits

- Private: the harness is the publisher. It builds the shards from zcashd with
  the extraction rules of wallet-pir's filter server and serves them in
  process over loopback HTTP, so this qualifies Vizor's private mode against a
  correct publisher, not the production one.
- Private: the adapter accepts mainnet maps only, so the regtest publication
  carries mainnet's network label and genesis hash; every block hash from
  height 1 is the real regtest one.
- Private: regtest has no Enhance PIR or status service, so a transaction the
  wallet did not build keeps incomplete details. On mainnet, payload PIR could
  complete some rows marked incomplete by design; these runs do not measure
  that.
- Private: N_pre is weak: nothing is held, so its snapshot follows the first
  sync.
- Private app layer: desktop only. The simulator's app does not inherit the
  runner's environment, which carries the Rust switches.
- The mobile app layer was not run in either profile.
- Debug builds only: the regtest switches
  (`ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT`, the loopback HTTP transport,
  `ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW`) are not compiled into release builds,
  and the app's `ZCASH_E2E_PRIVATE_TRANSPARENT_REGTEST` is `kDebugMode` and
  the define, constant false in profile and release builds.

## Reproduce

From the repository root, with Docker running:

```bash
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/private3" \
  scripts/e2e/transparent-history-cases.sh --profile private
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/public3" \
  scripts/e2e/transparent-history-cases.sh --profile public
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/public-desktop" \
  scripts/e2e/transparent-history-cases.sh --profile public --flutter desktop
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/private-desktop" \
  scripts/e2e/transparent-history-cases.sh --profile private --flutter desktop
```

Each writes `results.json` (case by variant matrix, negative controls) and the
per-checkpoint `report-*.json` and `observed-*.json`; the private run adds
`pir-requests.json`, the desktop run `expected-ui.json` and
`flutter-desktop.log`. The two Rust-only runs can share the machine: each
builds its own chain on its own ports. The desktop run builds the macOS app,
which needs a local signing team for `com.keplr.vizor` in the Runner's Debug
settings; without one the build fails before any case runs.
