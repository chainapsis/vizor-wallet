# Transparent history qualification suite (H01–H13)

Vizor layer of `docs/transparent-pir-history-qualification.md` in
zakura-core/wallet-libraries (PR #76). One regtest scenario per case H01–H13,
asserted through Vizor's public Rust API and through the Flutter app on
desktop and mobile. The suite qualifies **public mode** only (transparent
discovery through lightwalletd, production today).

Run it:

```bash
scripts/e2e/transparent-history-cases.sh                    # Rust layer
scripts/e2e/transparent-history-cases.sh --flutter desktop  # + macOS app (window hidden)
scripts/e2e/transparent-history-cases.sh --flutter mobile   # + iOS simulator
scripts/e2e/transparent-history-cases.sh --flutter both
```

Requires Docker. The runner builds its own chain (pinned zcashd and
lightwalletd images, own ports and config) and never touches
`scripts/regtest`. Output goes to `rust/target/transparent-history-cases/run-*`
(`TH_OUT_DIR` overrides): `results.json` (case × variant matrix, negative
controls), `report-<checkpoint>.json`, `expected-*.json`, `observed-*.json`,
`manifest.json`, `timings.json`, and the logs. `TH_CASES=H01,H03` narrows a
development run; anything short of H01–H13 fails the gate by design.

## Pieces

| Piece | Where | Role |
|---|---|---|
| Chain | `chain.rs` | Isolated zcashd + lightwalletd, mining to chosen addresses, JSON-RPC |
| Z | `faucet.rs` | zcashd's wallet as faucet (`z_sendmany` from shielded coinbase, transparent recipients only; zcashd's wallet asserts on Orchard anchors under this load, so it never touches Orchard) |
| S | `signer.rs`, `provers.rs` | Harness transaction builder; signs with runtime-derived transparent keys; broadcasts through lightwalletd |
| V | `vizor.rs` | Vizor's production send / shield / TEX / gift-card paths via `api::*` |
| F | `proxy.rs` | lightwalletd proxy: records every request and its transparent subjects; injects faults |
| Parties | `keys.rs` | A0/A1 (Alice's two seeds, in Vizor), B, C, D (harness-only keys), F (harness funder: Z pays it, S turns its coins into Alice's Orchard notes) |
| Cases | `cases.rs` | The H01–H13 timeline: builds chain facts, authors intent and shielded attribution |
| Bookkeeping | `report.rs` | Ownership map, case manifest, observations, oracle bridge, Flutter handoff |
| Oracle | `scripts/e2e/transparent_history_oracle.py` | Chain facts and owned ledger from zcashd only; compare; gate; manifest |
| Profile | `scripts/e2e/transparent_history_profile_public.py` | Everything mode-specific |
| App layer | `integration_test/regtest_transparent_history_cases_test.dart`, `regtest_mobile_transparent_history_cases_test.dart`, `support/transparent_history_cases_flow.dart` | Fresh restore in the app; rows and detail screens |

Variants: **R** is the wallet that built or observed each transaction, **O**
is R's files copied to a new path (a reopen with no in-process state), **N**
is a fresh restore of Alice's seeds (both imported before the first sync),
and **N_seq** is the same restore in the order users reach: A0 is restored
and synced alone, and only then is A1 added, which rewinds a synced wallet.
N_seq is held to N's expectations. The app layer restores in N_seq's order.
Fault variants: **N_pre** (N's first
sync with every `GetTransaction` held: the pre-enrichment view), **N_cut**
(`GetTaddressTxids` streams cut), **N_utxo_fail** (`GetAddressUtxos*` fail),
**N_pending** (a fresh restore while H12's transactions are unmined).

## Independence rules

- Expected values come only from zcashd (verbose transactions, prevouts via
  txindex, block headers, the insight address index) and from the authored
  ownership map and case manifest. Nothing reads Vizor, the wallet libraries,
  or the activity mapper to produce an expectation.
- Shielded components the chain cannot attribute are authored from
  construction intent (`Attribution`): either "every shielded component of
  this transaction belongs to account X" or an explicit owned shielded net.
- Expectations are re-derived from the live chain at each checkpoint and never
  regenerated from a run's observations.
- Keys are generated at runtime. Output files hold addresses, scripts, txids
  and public transactions only. Mnemonics reach the Flutter layer only as
  `--dart-define`s, through a 0600 file in the runner's private temp dir that
  is deleted as soon as it is read.
- Negative controls run on every full run: a wrong fee, a wrong input count,
  an omitted ledger event, and a wrong ownership mapping are each injected
  into the expectations and must make `compare` exit nonzero.

## Extension points

Cases are mode-independent: they produce chain facts plus authored intent
(`TxRecord.intent`, a closed vocabulary) and attribution. Everything that
depends on the transparent mode lives in one **expectation profile** module,
`scripts/e2e/transparent_history_profile_<mode>.py`, with four functions:

- `activity(context)`: per (tx, account, variant) expected rows or
  constraints, exact after enrichment and honesty-only for incomplete evidence;
- `account_checks(context)`: owned ledger, UTXO set, balance and coverage
  assertions per checkpoint and variant;
- `request_policy(context, addresses, txids)`: the allowed lightwalletd
  methods and subjects;
- `ui_rows(context)`: the app-layer expectations for a fresh restore.

Adding **private mode** later:

1. Add `transparent_history_profile_private.py`. Its request policy allows
   zero public address, txid and outpoint requests (`PrivateRequired`).
2. Select the mode in `report::PROFILE` and switch Vizor into it in
   `VizorWallet::import` through the production preference, once Vizor
   integrates the TPIR client (wallet-libraries #77, `zakura-pir-transparent`).
3. On regtest, `EnhancementPolicy` must stop requiring `WalletNetwork::Main`
   for private mode (`rust/src/wallet/sync_engine/enhancement/policy.rs`).

No case in `cases.rs` changes.

Not covered (future extensions): hardware wallets (Ledger/Speculos variants of
H07 and H10, which exercise the hardware broadcast-authority check; Keystone
has no harness), txid-PIR enrichment tests, real-chain replay, a real NEAR
swap, and CI wiring.
