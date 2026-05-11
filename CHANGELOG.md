# Changelog
All notable changes to this workspace will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this workspace adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

# 0.5.8

## Added
- `VotingDb::setup_bundles` now persists bundle note identity hashes, and
  `VotingDb::build_governance_pczt`, `VotingDb::precompute_delegation_pir`,
  and `VotingDb::build_and_prove_delegation` reject same-position note
  substitutions for bundles set up under 0.5.8 or later. Bundles persisted by
  earlier releases retain the prior position-only check until they are
  re-setup.

## Fixed
- Delegation proof storage now checks proof-derived public inputs against the
  PCZT-derived values stored during `VotingDb::build_governance_pczt`, and
  stores the proof, public inputs, and round phase atomically.
- `VotingDb::setup_bundles` now persists all bundle rows in a single
  transaction.
- Avoided dropping the Hyper/Tokio transport runtime from inside an active Tokio
  context.

# 0.5.7

## Fixed
- `VotingDb::mark_vote_submitted` now returns an error when no persisted vote
  row matches the requested round, wallet, bundle, and proposal instead of
  treating a zero-row update as success.

# 0.5.6

## Added
- Added a `test-fixtures` feature exposing `VotingDb::insert_vote_fixture`, so
  downstream FFI tests can create vote rows through `VotingDb` instead of
  depending on SQLite schema internals.

# 0.5.5

## Fixed
- Keystone delegation submissions now reject a supplied sighash unless it matches
  the PCZT sighash stored for the bundle.

# 0.5.4

## Fixed
- Delegation submission signing now derives the sender spending key from the
  caller's ZIP-32 `account_index` instead of always using account 0.

# 0.5.3

## Fixed
- **`zcash_voting` `network_id` convention** now matches the wallet SDK everywhere
  (`zkp1::build_and_prove_delegation`, PIR `precompute_delegation_pir` padded
  nullifiers, `zkp2::derive_spending_key`, `vote_commitment::sign_cast_vote`, and
  storage helpers that take `network_id`): **0 = testnet, 1 = mainnet**. The
  padded-nullifier path had previously used the inverse mapping, so `NoteInfo`
  from the SDK could disagree with PIR precompute vs proof generation.

## Changed
- Bumped the `zcash_voting` crate version to `0.5.3`. Direct callers who flipped
  `network_id` to compensate for the old bug should pass the SDK value unchanged
  after upgrading.

# 0.5.2

## Changed
- Reissued the tree-sync transport release from the merged `main` history.
- Confirmed the Hyper/Rustls tree-sync transport against production vote-chain
  endpoints for non-empty rounds.

# 0.5.1

## Changed
- Moved vote commitment tree sync onto the injected transport boundary and
  provided a direct Hyper/Rustls transport from `zcash_voting`.
- Removed `reqwest` from `vote-commitment-tree-client`'s library path.

# 0.5.0

## Changed
- Made `client-pir` transport-agnostic. `zcash_voting` no longer pulls
  `reqwest`; callers must provide a `pir_client::Transport`.
- Added transport-aware PIR precompute/proving entry points so SDKs can provide
  their own HTTP stack.
- Consolidated PIR proof validation and client transport under the single
  `client-pir` feature.
- Added a direct Hyper/Rustls PIR transport under `client-pir` for consumers
  that do not provide their own transport.

# 0.4.1

## Added
- Split the `zcash_voting` network-facing `client` feature into granular
  `client-pir` and `client-tree-sync` features. The existing `client` feature
  remains as a backwards-compatible aggregate of both.
- Made the PIR proof conversion/validation helper available to downstream
  consumers so SDK FFI layers can validate PIR `ImtProofData` without
  enabling vote-commitment-tree sync.

## Changed
- Bumped the `zcash_voting` crate version to `0.4.1` for the additive feature
  split.
