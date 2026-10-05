# Transparent history qualification suite (H01–H13)

Vizor layer of `docs/transparent-pir-history-qualification.md` in
zakura-core/wallet-libraries (PR #76). One regtest scenario per case H01–H13,
asserted through Vizor's public Rust API and through the Flutter app on
desktop and mobile. Two expectation profiles:

- **public** (default): transparent discovery through lightwalletd,
  production today. Rust and app layers.
- **private**: `PrivateRequired`, transparent recovery from a transparent PIR
  service the harness publishes from the chain (see "Private profile").
  Rust layer only, debug builds only.

Run it:

```bash
scripts/e2e/transparent-history-cases.sh                    # Rust layer, public
scripts/e2e/transparent-history-cases.sh --profile private  # Rust layer, private
scripts/e2e/transparent-history-cases.sh --flutter desktop  # + macOS app (window hidden)
scripts/e2e/transparent-history-cases.sh --flutter mobile   # + iOS simulator
scripts/e2e/transparent-history-cases.sh --flutter both
```

`TH_PROFILE=private` selects the profile too. Each profile is one test
function (`public_profile_h01_to_h13`, `private_profile_h01_to_h13`); the
runner runs exactly one per process, because the private switches are
process-wide. The two profiles can run at once from separate processes: each
builds its own chain on its own ports.

Requires Docker. The runner builds its own chain (pinned zcashd and
lightwalletd images, own ports and config) and never touches
`scripts/regtest`. Output goes to `rust/target/transparent-history-cases/run-*`
(`TH_OUT_DIR` overrides): `results.json` (case × variant matrix, negative
controls), `report-<checkpoint>.json`, `expected-*.json`, `observed-*.json`,
`manifest.json`, `timings.json`, and the logs; the private profile adds
`pir-requests.json` (requests the transparent PIR service received, by route,
and privacy violations, which fail the run) and the served shard set under
`publication/`. `TH_CASES=H01,H03` narrows a development run; anything short
of H01–H13 fails the gate by design.

The oracle's self-tests need no chain:
`python3 scripts/e2e/test_transparent_history_oracle.py`.

## Pieces

| Piece | Where | Role |
|---|---|---|
| Chain | `chain.rs` | Isolated zcashd + lightwalletd, mining to chosen addresses, JSON-RPC |
| Z | `faucet.rs` | zcashd's wallet as faucet (`z_sendmany` from shielded coinbase, transparent recipients only; zcashd's wallet asserts on Orchard anchors under this load, so it never touches Orchard) |
| S | `signer.rs`, `provers.rs` | Harness transaction builder; signs with runtime-derived transparent keys; broadcasts through lightwalletd |
| V | `vizor.rs` | Vizor's production send / shield / TEX / gift-card paths via `api::*` |
| F | `proxy.rs` | lightwalletd proxy: records every request and its transparent subjects; injects faults |
| P | `publication.rs` | Private profile: transparent PIR publisher (shards from zcashd's blocks) and in-process shard server on one loopback port; checks every request; injects lag and query faults |
| Parties | `keys.rs` | A0/A1 (Alice's two seeds, in Vizor), B, C, D (harness-only keys), F (harness funder: Z pays it, S turns its coins into Alice's Orchard notes) |
| Cases | `cases.rs` | The H01–H13 timeline: builds chain facts, authors intent and shielded attribution |
| Bookkeeping | `report.rs` | Ownership map, case manifest, observations, oracle bridge, Flutter handoff |
| Oracle | `scripts/e2e/transparent_history_oracle.py` | Chain facts and owned ledger from zcashd only; compare; gate; manifest |
| Profiles | `scripts/e2e/transparent_history_profile_public.py`, `transparent_history_profile_private.py` | Everything mode-specific |
| App layer | `integration_test/regtest_transparent_history_cases_test.dart`, `regtest_mobile_transparent_history_cases_test.dart`, `support/transparent_history_cases_flow.dart` | Fresh restore in the app; rows and detail screens |

Variants: **R** is the wallet that built or observed each transaction, **O**
is R's files copied to a new path (a reopen with no in-process state), **N**
is a fresh restore of Alice's seeds. Fault variants: **N_pre** (N's first
sync with every `GetTransaction` held: the pre-enrichment view), **N_cut**
(`GetTaddressTxids` streams cut), **N_utxo_fail** (`GetAddressUtxos*` fail),
**N_pending** (a fresh restore while H12's transactions are unmined). The
private profile replaces N_cut and N_utxo_fail, whose requests it never
makes, with **N_lag** (the publication 60 blocks behind the tip, H12's
activity unpublished) and **N_pir_fail** (every private query answered 500).

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

Cases build the same chain facts in both profiles. The one exception is
H13: its faults are transport faults, so each profile injects its own (see
the fault variants above).

## Private profile

What the run sets, all before the first wallet exists:

- The process switches of a flagged build with private queries on:
  `configure_private_transparent_recovery(true)`,
  `set_enhance_pir_enabled(true)`, `set_enhance_pir_preference_confirmed(true)`.
- `ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT=1`, a debug-build-only switch that
  lets regtest select `PrivateRequired`, gives regtest a transparent PIR
  origin (the override only, never the mainnet service), and lets the
  transparent PIR transport use plain HTTP to exactly `http://127.0.0.1:<port>`
  or `http://[::1]:<port>` (no Tor). Release builds compile none of it and
  never read the switch.
- `VIZOR_TRANSPARENT_PIR_URL` (debug builds only) to the publisher's origin,
  one port for the whole run, so every companion keeps its origin binding.
- Each imported wallet goes through `reconcile_transparent_policy(.., true)`,
  the production toggle-on path, so it requires private recovery before its
  first sync.

Recovery runs as in production: each sync runs it after the scan
(`transparent_followup`). Before each sync the publisher catches up with the
chain (one unsealed tail shard over `[1, tip]`, a new revision whenever the
range or its terminal block changes, so the H12 reorg republishes), so the
publication covers the tip the wallet scans to.

Limits to state with any private result:

- The harness is the publisher, built from zcashd with the extraction rules
  of wallet-pir's filter server. This qualifies Vizor's private mode against a
  correct publisher, not the production publisher.
- The adapter accepts mainnet maps only, so the regtest publication carries
  mainnet's network label and genesis hash (as the adapter's own end-to-end
  fixture does); every block hash from height 1 is the real regtest one.
- Regtest has no Enhance PIR or status service. `EnhancementPolicy.private`
  stays mainnet-only, and under `PrivateRequired` the lookup gate withholds
  the public payload, status and history lanes: zero `GetTransaction` and
  zero address requests (the request policy fails on any), and transactions
  a wallet did not build keep incomplete details. The profile's module docs
  say which rows are exact, which keep exact amount and fee with incomplete
  details, and which are honestly incomplete.
- N_pre is weak here: nothing is held, so its snapshot follows the first sync.
- No app layer: `--flutter` is refused with `--profile private`.

Not covered (future extensions): hardware wallets (Ledger/Speculos variants of
H07 and H10, which exercise the hardware broadcast-authority check; Keystone
has no harness), txid-PIR enrichment tests, real-chain replay, a real NEAR
swap, and CI wiring.
