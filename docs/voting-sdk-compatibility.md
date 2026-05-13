# Voting SDK Compatibility Notes

Vizor adapts the Swift SDK and zodl iOS coinholder polling model to a
Flutter/Riverpod app with Flutter Rust Bridge. The goal is compatibility at
the durable state, REST, and wire-format boundaries, not a direct port of
Swift's C FFI or TCA architecture.

## Vizor Adaptations

- Rust voting work lives behind `rust/src/api/voting.rs` FRB functions instead
  of Swift's `VotingRustBackend` C FFI wrapper.
- Dart owns vote-server REST, config loading, endorser calls, PIR endpoint
  selection, and UI state orchestration.
- Rust owns wallet DB reads, note selection, delegation, vote commitment
  construction, tree sync, recovery/share tracking, and all cryptographic work
  through `zcash_voting`.
- Voting hotkeys are stored in Flutter secure storage as encrypted per-account,
  per-round bytes under `zcash_account_voting_hotkey_{accountUuid}_{roundId}`.
- The UI follows zodl's product flow, but uses Vizor desktop components and
  Riverpod providers: Settings -> polls -> proposal choices -> review ->
  status -> results.

## Compatibility Checklist

- Network IDs remain `0 = test/regtest` and `1 = mainnet`.
- `bundle_index` is the durable key for delegation, voting, share submission,
  and recovery.
- Local workflow state uses `zcash_voting::storage::VotingDb`; Vizor does not
  maintain a parallel `voting_round_state` table.
- PIR endpoint resolution fails closed unless `/root.height` exactly matches
  the round snapshot height. Optional `/root.network_id` and `/root.round_id`
  fields are not trusted as protocol identity; the round configuration
  authenticates the snapshot height used for endpoint selection.
- REST calls remain under `/shielded-vote/v1/*`.
- Encrypted-share payloads use Swift-compatible snake_case field names:
  `shares_hash`, `proposal_id`, `vote_decision`, `enc_share`,
  `tree_position`, `all_enc_shares`, `share_comms`, and `primary_blind`.
- Wire encrypted share fields stay `c1`, `c2`, and `share_index`.
- Share nullifiers are computed through `zcash_voting`, not Dart.
- Hotkey derivation is exposed as a thin Rust API and uses the same underlying
  `zcash_voting` hotkey implementation as delegation.

## Upstream Observations

- PIR mismatch semantics are important enough to document in the shared SDK
  surface: clients should reject ahead, behind, malformed, and unreachable
  endpoints instead of accepting `>= snapshot`.
- Network ID constants should remain centralized. Repeating `0/1` mappings in
  application code risks silent cross-platform drift.
- Share delegation recovery is easiest to reason about when treated as a
  bundle/proposal/share-index loop over `VotingDb` rows, matching zodl iOS.
- PCZT broadcast/store ordering should remain asserted in shared Rust where
  possible. Vizor preserves the existing wallet invariant that broadcast
  succeeds before local persistence is treated as final.

## Assumptions Made

- The vote server accepts JSON byte arrays for Swift-compatible `Codable`
  `[UInt8]` fields.
- A successful helper-server `submitShare` response means the server accepted
  the share even when it does not return a stable `share_id`.
- Share submission follows the zodl iOS timing model: outside the last-moment
  buffer, each share samples `submit_at` uniformly before `vote_end_time -
  last_moment_buffer`; inside the buffer it submits immediately with
  `submit_at = 0` and single-share vote-commitment mode.
- Share recovery also follows zodl's timing model. Status polling waits until
  `submit_at + 10s` for delayed shares or `created_at + 10s` for immediate
  shares. Overdue shares are retried only after
  `max(30s, min(1h, remaining_window / 4))`, and retry requests use
  `submit_at = 0` without rewriting the original stored `submit_at`.
- The current FRB voting surface's vote commitment builder stores the
  commitment bundle recovery state needed for subsequent share retry.
- Round status payloads may use `proposals` or `questions`; the Flutter view
  parser accepts both until the service schema is locked.

## Ambiguities To Resolve

- Whether helper servers require byte arrays, base64 strings, or hex strings
  for every share payload field in production.
- Whether the app should submit shares immediately after vote commitment
  construction or wait for an on-chain cast-vote confirmation event before
  reveal, as zodl iOS does in parts of its recovery path.
- Whether single-share last-moment mode should be surfaced in the Dart UI from
  round metadata, and which metadata field is authoritative.
- Whether `prepare_voting_round` should be called explicitly from Dart before
  setup, or whether setup/delegation APIs should remain the round initialization
  boundary.
- Whether the results endpoint shape is finalized as per-proposal entries or a
  round-level aggregate map.
