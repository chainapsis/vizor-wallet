# Vizor zwap swaps: mainnet rollout

Status: the swap engine is mainnet ready. All four directions (b2z, z2b, e2z,
z2e) settle end-to-end on the regtest stack, driven from the app UI through
live settlement. The engine is network-agnostic: the swap FSM, the joint-note
cryptography, and hashbind proving are the same code on every network. Going
live against a deployed mainnet backend is a configuration exercise, described
below.

References: `AGENTS.md`, `lib/src/features/swap/integrations/zwap/`,
`native/hashbind_prover/README.md`.

## 1. What carries over unchanged

- **Swap engine**: order create, joint-note deposit / external deposit, solver
  funding, claim/sweep, status mapping. Chain-parameterized throughout.
- **On-device proving**: the hashbind proof over the spend-auth scalar is
  generated in-process on the phone (`native/hashbind_prover/`). The scalar
  never leaves the device; release builds refuse remote provers by design.
- **Key handling**: the wallet seed and the orderbook bearer token are held in
  memory only, never persisted or logged.
- **Network scoping**: `ZCASH_DEFAULT_NETWORK` already scopes secure-storage
  keys and the wallet DB per network, so mainnet and regtest wallets never
  collide.

## 2. Configuration model

Every endpoint is a build-time define (`ZWAP_ORDERBOOK_URL`,
`ZWAP_INDEXER_URL`, `ZWAP_POOLD_URL`, `ZWAP_EVM_RPC_URL`, `ZWAP_NETWORK`),
defaulting to the local regtest stack. Mainnet builds pass the deployed
endpoints instead; all of them are `https://`.

The per-network chain constants (token contract addresses, timelocks, fee
parameters) live in a network-selected config keyed by `ZWAP_NETWORK`. The
deployed backend config is the source of truth; the app mirrors its values so
both sides always derive identical swap parameters. Populating the mainnet row
of that table is done together with the backend deployment values.

Backend access for partner builds moves to an affiliate API key system, which
is in the works on the zwap side. Keys and the integration details will be
shared once ready; the app's auth path is unchanged by it.

## 3. Multi-chain EVM support

The app supports multiple EVM chains natively. `SwapAsset` carries a chain
dimension, the asset picker exposes each (token, chain) pair as its own entry
(Ethereum and Base today), and the client routes RPC calls per chainId
(`kZwapEvmRpcByChainId`). z2e claims verify the on-chain slot against locally
derived parameters per chain before any reveal.

Adding a chain is additive: one row of config (chainId, RPC URL, token
addresses, HTLC address) taken from the deployed backend, plus an asset entry.
No engine changes.

## 4. Mainnet run lane

```
fvm flutter run \
  --dart-define=VIZOR_FORM_FACTOR=mobile \
  --dart-define=VIZOR_SWAP_BACKEND=zwap \
  --dart-define=ZCASH_DEFAULT_NETWORK=mainnet \
  --dart-define=ZWAP_NETWORK=mainnet \
  --dart-define=ZWAP_ORDERBOOK_URL=https://<orderbook> \
  --dart-define=ZWAP_INDEXER_URL=https://<indexer>/v1 \
  --dart-define=ZWAP_POOLD_URL=https://<poold> \
  --dart-define=ZWAP_EVM_RPC_URL=https://<evm-rpc> \
  -d <device>
```

Release/CI lanes hardcode the same defines, following the existing
`VIZOR_FORM_FACTOR` discipline in `AGENTS.md`.

## 5. Hashbind proving on mainnet

On-device proving ships in this branch and is the default. The proving key is
bundled as an asset and pinned by sha256; proofs are the canonical ProveKit
format the solver's verify engine consumes, validated by a full prove/verify
round trip against the solver fixtures in CI.

For mainnet we align on one detail with the backend deployment: the app's
bundled proving key and the solver's verifying key are generated as a pair, so
the mainnet key pair is produced once at deployment and the app bundle picks up
the matching `pallas.pkp` (checklist in `native/hashbind_prover/README.md`).
Key rotation cadence and distribution are a deployment discussion to have with
the backend team.

## 6. Go-live checklist

1. Fill the mainnet config row from the deployed backend values (token
   addresses, timelocks, fee parameters, chain table).
2. Point the app at the mainnet endpoints and smoke-test quote and
   order-create over TLS (no funds).
3. Bundle the mainnet `pallas.pkp` and round-trip a phone proof against the
   deployed verifying key.
4. Derive BTC claim fees from live feerates instead of the regtest constant,
   and take ZEC fees from `estimate_fee`.
5. Small-value swap per direction. Confirmations are real-time on mainnet, so
   budget accordingly.
6. Ship the run lane into CI with the defines hardcoded.
