# Transparent history support: public and private modes

What Vizor's transaction history gets right for each case of the transparent
history qualification (H01-H13, wallet-libraries
`docs/transparent-pir-history-qualification.md`), in public mode
(lightwalletd discovery, production today) and in private mode
(`PrivateRequired`: recovery from a transparent PIR service, #839). It is
measured by the H01-H13 suite on an isolated regtest chain, in two layers:
- the Rust layer (`rust/tests/transparent_history_cases`), in both profiles;
- the desktop app layer (`integration_test/regtest_transparent_history_cases_test.dart`,
  the macOS app), in both modes.

Runs: 2026-10-07, branch `claude/tpir-private-history` on #839 `3d7810c4a`,
wallet-libraries main `a3dee2ab5`, wallet-pir `648264bb`.

| Run | Commit | Output | Time | Exit |
|---|---|---|---|---|
| Public, Rust and desktop app layers | `5b6fa1070` | `final2-public-desktop` | 139 s + 445 s | 101 (G2, G4, G5), 1 (G4) |
| Private, Rust and desktop app layers | `393da3c7b` | `final3-private-desktop` | 243 s + 176 s | 0, 0 |
| Public, Rust layer | `35430bec2` | `fix-public` | 157 s | 101 (G2, G4, G5) |
| Private, Rust layer | `35430bec2` | `fix-private` | 257 s | 0 |

`393da3c7b` changes only the private profile, so the public results at
`5b6fa1070` stand for it. The Rust-only runs check N_seq's premise (see How to
read the table) before the app-layer expectations changed; their Rust matrices
are identical to the desktop runs'. Each run builds its own chain. The
expectations come from zcashd and the authored case intent only (the suite's
oracle), never from Vizor.

## How to read the table

Variants:
- **R** is the wallet that built or observed each transaction.
- **O** is a copy of R's files, reopened.
- **N** is a fresh restore of both seeds, imported before the first sync.
- **N_seq** is the same restore in the order users reach: A0 alone is restored
  and synced to the tip, and only then is A1 added, which rewinds a synced
  wallet. It is held to N's expectations. The run fails if A0 alone does not
  reach a synchronized wallet; in private mode A0 must also have recovered
  privately with current transparent authority, and adding A1 must keep the
  wallet requiring private recovery.

Fault variants:
- **N_pending** restores while H12's transactions are unmined.
- **N_pre** is a fresh restore's first view.
- Public injects **N_cut** (address history streams cut) and **N_utxo_fail**
  (UTXO requests fail).
- Private injects **N_lag** (publication 60 blocks behind the tip) and
  **N_pir_fail** (every private query answered 500).

**App** is a fresh restore in the macOS app, in N_seq's order (A0 synced before
A1 is added). It checks each expected activity row's title, amount, pool
label, detail status and whole fee: 49 rows over 11 cases in public mode and
48 in private mode, 4 of them optional. In private mode it also checks:
- the "Details: Incomplete" line on the receipt;
- the "Details incomplete" marker that replaces the time on the row;
- that a spend's receipt shows its fee once (see Fee presentation).

Pool labels follow #858 and #863 (on #839's base): a payment shows its exact
shielded pool, Orchard or Sapling by name, with Ironwood shown as "Shielded".

Cell values:

- **pass**: every row and account check matches the profile exactly.
- **pass; incomplete by design: row**: passes, and the private profile accepts
  these rows as honestly incomplete because private mode's evidence cannot
  complete them:
  - the payment details of a transaction the wallet did not build (no
    `GetTransaction`, and regtest has no Enhance PIR);
  - the pool and classification of a transaction the account did not fund
    alone, or one with shielded components;
  - the fee of a transaction the account took part in only through its
    shielded notes, marked "(fee unknown)".

  The movement is exact, nothing shown as final is false, and a shown fee is
  the whole fee, never zero.
- **pass; details incomplete by design: row**: an exact amount and whole fee
  with the recipients unknown. This is private mode on a transparent-only
  transaction the account funded alone: the library reconstructs the payment
  from the recovered metadata.
- **fail (code)**: a product defect or gap, listed below.
- **-**: the case has no such variant.

In the app columns, "receipts marked incomplete" counts the expected rows
whose receipt must say "Details: Incomplete". "Rows marked" counts the rows
that must also show "Details incomplete" in place of their time. That happens
only when the row's role or pool is not established, which is when the
account spent and the transaction has shielded components or an input
another party funded (#876).

## Support table

| Case | Public R | Public O | Public N, N_seq | Public faults | Public app | Private R | Private O | Private N, N_seq | Private faults | Private app |
|---|---|---|---|---|---|---|---|---|---|---|
| H01 Transparent-only send | - | pass | pass | - | pass (2 rows) | - | pass; details incomplete by design: send | pass; details incomplete by design: send | - | pass (2 rows; receipts marked incomplete: 1; rows marked: 0) |
| H02 Several inputs or recipients | - | pass | pass | - | pass (4 rows) | - | pass; details incomplete by design: send | pass; details incomplete by design: send | - | pass (4 rows; receipts marked incomplete: 1; rows marked: 0) |
| H03 Ordinary transparent receive | pass | pass | pass | - | pass (3 rows) | pass | pass | pass | - | pass (3 rows; receipts marked incomplete: 0; rows marked: 0) |
| H04 Retained local transaction | pass | pass | pass | - | - | pass | pass | pass | - | - |
| H05 Shared funding | - | fail (G2) | fail (G2) | - | pass (6 rows) | - | pass; incomplete by design: shared funding | pass; incomplete by design: shared funding | - | pass (6 rows; receipts marked incomplete: 3; rows marked: 3) |
| H06 Self/cross-account transfer | pass | - | pass | - | pass (9 rows, 1 optional) | pass; details incomplete by design: self-transfer, cross-account send | - | pass; details incomplete by design: self-transfer, cross-account send; incomplete by design: cross-account send from Orchard (fee unknown) | - | pass (9 rows, 1 optional; receipts marked incomplete: 5; rows marked: 1) |
| H07 Owned shielding/unshielding | pass | pass | pass | - | pass (5 rows, 1 optional) | pass | pass | pass; incomplete by design: shield, self-unshield | - | pass (4 rows; receipts marked incomplete: 3; rows marked: 2) |
| H08 External transparent unshielding | pass | - | pass | - | pass (2 rows) | pass | - | pass; incomplete by design: unshield to Bob (fee unknown) | - | pass (2 rows; receipts marked incomplete: 2; rows marked: 1) |
| H09 Other mixed-pool transaction | - | - | pass | - | pass (3 rows, 1 optional) | - | - | pass; incomplete by design: mixed-pool send | - | pass (2 rows; receipts marked incomplete: 1; rows marked: 1) |
| H10 TEX/multi-step operation | pass | - | pass | - | pass (3 rows, 1 optional) | pass | - | pass; details incomplete by design: TEX leg 2; incomplete by design: TEX leg 1 | - | pass (4 rows, 2 optional; receipts marked incomplete: 3; rows marked: 1) |
| H11 Swap/gift-card operation | pass | - | pass | - | pass (5 rows) | pass; incomplete by design: gift-card claim | - | pass; incomplete by design: gift-card create (fee unknown), gift-card claim, swap deposit (fee unknown) | - | pass (5 rows; receipts marked incomplete: 5; rows marked: 2) |
| H12 Pending/expired/conflicted | pass (pending, pre-reorg, final) | - | fail (G4) | N_pending: pass | fail (G4): 3 rows missing (7 rows) | pass (pending, pre-reorg, final); details incomplete by design: conflicting spend | - | pass; details incomplete by design: conflicting spend; incomplete by design: pending shield | N_pending: pass | pass (7 rows, 1 optional; receipts marked incomplete: 3; rows marked: 1) |
| H13 Incomplete coverage | - | - | - | N_cut: fail (G5)<br>N_pre: pass<br>N_utxo_fail: pass | - | - | - | - | N_lag: pass<br>N_pir_fail: pass<br>N_pre: pass | - |

**Gate verdicts**
- **Private Rust layer:** all 13 cases pass, in every variant, including N_seq.
- **Public Rust layer:** H01-H04 and H06-H11 pass. H05 (G2), H12 (G4) and H13's N_cut (G5) fail.
- **Negative controls:** in every run, all four make the comparison fail, as required. They are a wrong fee, a wrong input count, an omitted ledger event and a wrong ownership mapping.
- **N_seq:** in both profiles it passes or fails exactly where N does. Adding an account to a synced wallet changes nothing either suite checks.
- **Private app layer:** all 48 rows pass. The unmined H12 receive is optional and is not shown. Private recovery reads mined blocks, and the mempool observer matches shielded outputs only (`rust/src/wallet/sync_engine/mempool.rs`).
- **Public app layer:** 46 of 49 rows pass. The 3 failures are H12 rows the restored wallet does not have (G4).
- **Shared funding (H05) in the app:** the app layer checks that a row exists, that its receipt labels the movement as a net change and shows the whole fee. The Rust layer checks its amount.

## Fee presentation

In private mode the account's own fee is often unknown. The row then shows
the account's movement, which already contains the whole fee, and the
receipt shows that fee once. The private profile derives which presentation
each spend's receipt may have from the chain, not from the app
(`fee_presentations` in `scripts/e2e/transparent_history_profile_private.py`):

- **Fee only ("Network fee").** The row reads "Network fee" with the signed fee
  and no pool. The receipt, titled "Transaction", has one "Network fee" line
  and no "Amount" or "Tx fee" line. Since #839 `4db46f38f` this applies only to
  an established transparent self-transfer whose movement is the whole fee:
  transparent only, with every input the account's. No H01-H13 row has that
  shape now. H06's self-transfer pays an external-scope address of the same
  account, which #870 shows as Sent and Received, as public mode does.
- **Net change.** The receipt labels the amount "Net change (includes network
  fee)" and keeps a "Tx fee" line with the whole fee. This covers:
  - H05's three shared-funding rows and H09's mixed-pool send, where the
    movement is larger than the fee;
  - movements equal to the whole fee in a transaction with shielded
    components: H07's shield and self-unshield, H10's TEX leg 1 and H12's
    pending shield.

  The rows in the second group read "Sent" with the signed fee, no pool, and
  "Details incomplete". They would show as "Shielded" or as a self-move only
  with Enhance evidence (#862, #869), which regtest does not have. The app
  layer checks their title, amount and absent pool.
- **Separate.** The receipt has an "Amount" line and a separate "Tx fee": the
  sends the account funded alone (H01, H02, H06's self-transfer and
  cross-account send, H10's TEX leg 2, H12's conflicting spend), whose
  reconstructed payment excludes the fee.

Rows where the account took part only through shielded notes keep an unknown
fee: H06's cross-account send from Orchard, H08's unshield to Bob, H11's
gift-card create and swap deposit. In the app, a whole fee from the recovered
metadata is shown only for an account that spent (#877).

## Request capture

These are the requests each wallet made, summed over checkpoints and
variants. A request has a transparent subject when it names a transparent
address or a txid to lightwalletd: an address method (`GetAddressUtxosStream`,
`GetTaddressTxids`) or a `GetTransaction`.

The Public and Private columns are the Rust layer of `final2-public-desktop`
and `final3-private-desktop`. Private app is the macOS app's fresh restore in
`final3-private-desktop`, which reaches lightwalletd through a recording
proxy.

| | Public | Private | Private app |
|---|---|---|---|
| lightwalletd requests | 1,005 | 354 | 46 |
| with a transparent subject | 635 (246 `GetAddressUtxosStream`, 79 `GetTaddressTxids`, 310 `GetTransaction`) | 0 | 0 |
| block and tree data (`GetLatestBlock`, `GetBlock`, `GetBlockRange`, `GetTreeState`, `GetSubtreeRoots`) | 344 | 325 | 40 (28, 4, 2, 2, 4) |
| server info and mempool (`GetLightdInfo`, `GetMempoolStream`) | 0 | 0 | 6 (3, 3) |
| `SendTransaction` (the wallet's own transactions) | 26 | 29 | 0 |
| transparent PIR service requests | - | 1,732 (1,208 directory and 36 page queries, the rest catalog, manifest and setup) | 78 (56 directory and 2 page queries, the rest catalog, manifest and setup) |
| privacy violations at the PIR service (Alice's script in a path, header or body, a query string, an unknown route) | - | 0 | 0 |

The private request policy allows only block and tree data, `GetLightdInfo`
and the wallet's own broadcasts; any other method fails the run. Under
`PrivateRequired` the lookup gate withholds every transparent lookup, in every
variant, faults included. The public app layer's own requests are not
captured.

For the private app layer, a request with a transparent subject fails the run,
and other methods are recorded. `GetMempoolStream` streams the whole mempool
and names no address or txid. It falls outside that policy only because the
Rust layer does not use it.

## Product defects

D codes are private-mode defects these runs found; all are fixed. G codes are
public-mode gaps.

**D1, fixed in #839 (`8b0b49572`): a privately recovered send showed as a
receive.**
- **Background.** A transparent-only send the account fully funded is known from the transparent PIR events only. The library reconstructs its exact payment (`AggregatePayment::Exact`, classification `Reconstructed`, whole fee known).
- **Defect.** Vizor's mapper ignored the reconstructed payment, so the debit fell through to its change: a send of 1.25 ZEC showed as "received 1.7499 ZEC".
- **Affected:** H01, H02, the sending side of H06, H10 TEX leg 2 and H12's conflicting spend.
- **Fix.** Such a debit is now one sent row with the reconstructed amount, the transparent pool, the known fee and incomplete details.

**D2, fixed in #839 (`d01b7e6c8`): the whole fee from the recovered metadata
was not shown.**
- **Background.** When the account did not fund a transaction alone, or the transaction has shielded components, the account's fee is unknown. The library's transaction metadata still carries the exact whole fee.
- **Fix.** Vizor keeps the whole fee apart from the account's fee and shows it as the network fee. #877 narrows this to an account that spent.
- **Display only.** Payments and provisional debits are still computed with the account's fee, so a shared fee is never charged to one account.

**D3, fixed (#836's change, on #839's base): a reorged-away receive's detail
failed in private R and O.** Reading the transaction detail failed on a null
`expired_unmined`.

**D4, fixed in #839 (`3d8596949`), then superseded by #870: a privately
recovered self-transfer read as a receive of its gross outputs.**
- **The defect.** H06's self-transfer showed "Received +1.9999 TAZ". In it, A0 spends 2 ZEC of its own transparent funds to its own external address (1.2 ZEC) plus change (0.7999 ZEC); its balance changes by the whole fee.
- **`3d8596949`.** Made it one fee-only "Network fee −0.0001" row.
- **#870 (`7aaed7bcb`).** Keeps a self-payment to an external-scope address as Sent −1.2 plus Received +1.2, both Transparent, as public mode shows it. The fee is a separate "Tx fee", and the receipts mark the details incomplete. The fee-only row remains only for a self-payment to an internal receiver.

Public gaps:
- **G2** (H05 N, O and N_seq), open. A shared-funding transaction shows a payment amount: an attribution the evidence does not support. The pinned library attributes a multi-funder transaction to its first funder. The fix needs wallet-libraries #90 (`TransactionFunding`, open), then the Vizor change in #818's `b7758acca`.
- **G4** (H12 N and N_seq), open. A restored wallet misses an H12 receive and the conflicting spend. In the app it also misses the pending receive. #818's `83eb63d4b` (one transparent address-history discovery for every account kind, with honest coverage) and `632edeef4` (an unmined transparent receive shown as in progress) address it. Neither is on #839.
- **G5** (H13 N_cut), open. With address history streams cut, sync still reports success and current authority. #818's `83eb63d4b` addresses it.
- **G1, G3 and G6**, no longer reproduce on #839 `3d7810c4a`. Not attributed commit by commit; #839 and its base gained #842, #868, #869 and #870 and newer library pins since 2026-10-05.
  - G1: a restored send had an unknown pool and was provisional (H01, H02, H09 N).
  - G3: H06's self-transfer showed as a receive.
  - G6: H09's mixed-pool send split in the app.

#818 is closed. Its closing comment lists which of its changes are on #839
and which are only on its branch.

## Harness defects fixed

Fixed and committed on this branch.
- **`f46de8d84`** (#818 `0139b39da`). The gate failed any case whose checkpoint label contains "fail", so H13 failed even with every variant passing.
- **`1ce5b4745`** (#818 `6d0a7f708`, V9). `detail_outputs_real` checked a received row's own receipts as payments. It now checks only sent rows.
- **`c3514a3bf`** (#818 `6ba005122`, gap 5b). The oracle compared the transparent balance with mined UTXOs only.
- **`54abc239b`.** Under `PrivateRequired` the private profile counts no unmined receive.
- **`0565521d5`.** The runner passes the switch that makes every ephemeral (TEX) address check due to the macOS app. Without it, H10 TEX leg 2 was never found. The mobile layer still lacks it.
- **`5fa6a1f3b` and `35430bec2`** (#818 `fe9582ce7`). N_seq, held to its premise; see How to read the table.
- **`5b6fa1070` and `393da3c7b`.** The expectations follow #839's deliberate presentation changes since 2026-10-05:
  - exact pool labels (#858, #863);
  - the row marker only for an unestablished role or pool (#876);
  - a self-transfer as Sent and Received (#870);
  - fee-only rows only for an established transparent self-transfer (`4db46f38f`).

Unexplained earlier failure: one earlier private run, while a public run
shared the machine, stopped when the oracle crashed deriving H12's pending
checkpoint (`Chain.raw` returned `None` for a txid from zcashd's address
index). The cause is not established. It has not recurred, and it is not
fixed.

## Limits

- **Private: the harness is the publisher.** It builds the shards from zcashd
  with the extraction rules of wallet-pir's filter server and serves them in
  process over loopback HTTP. This qualifies Vizor's private mode against a
  correct publisher, not the production one.
- **Private: mainnet label.** The adapter accepts mainnet maps only, so the
  regtest publication carries mainnet's network label and genesis hash. Every
  block hash from height 1 is the real regtest one.
- **Private: no Enhance PIR or status service on regtest.** A transaction the
  wallet did not build keeps incomplete details, and a shield or self-move the
  account took part in stays a provisional "Sent" net change. On mainnet,
  Enhance could complete some of these rows; these runs do not measure that.
- **Private: N_pre is weak.** Nothing is held, so its snapshot follows the
  first sync.
- **Private app layer: desktop only.** The simulator's app does not inherit
  the runner's environment, which carries the Rust switches.
- **Mobile app layer: not run** in either profile.
- **The receipt check depends on current wording.** It tells a fee-only
  receipt from a net-change one by the "Network fee" and "Net change (includes
  network fee)" wording. #867 (open) relabels a whole-transaction fee, so the
  check needs rework when #867 merges.
- **Debug builds only.** The regtest switches
  (`ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT`, the loopback HTTP transport,
  `ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW`) are not compiled into release builds.
  The app's `ZCASH_E2E_PRIVATE_TRANSPARENT_REGTEST` requires `kDebugMode` and
  the define, so it is constant false in profile and release builds.

## Reproduce

From the repository root, with Docker running:

```bash
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/final2-public-desktop" \
  scripts/e2e/transparent-history-cases.sh --profile public --flutter desktop
TH_OUT_DIR="$PWD/rust/target/transparent-history-cases/final3-private-desktop" \
  scripts/e2e/transparent-history-cases.sh --profile private --flutter desktop
python3 scripts/e2e/test_transparent_history_oracle.py
```

Each run writes:
- `results.json`: the case-by-variant matrix and the negative controls;
- the per-checkpoint `report-*.json` and `observed-*.json`;
- `expected-ui.json` and `flutter-desktop.log`, from the desktop runs;
- `pir-requests.json`, from the private runs.

Without `--flutter`, only the Rust layer runs. Two Rust-only runs can share
the machine, because each builds its own chain on its own ports.

The desktop run builds the macOS app. It needs a local signing team for
`com.keplr.vizor` in the Runner's Debug settings; without one the build fails
before any case runs. Run desktop runs one at a time: each builds and drives the same macOS app.
