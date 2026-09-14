# Voting session ownership

Use when changing captured account/round context, background job ownership, or secret hotkeys.

Implementation: [voting_submission_job_provider.dart](../../../../lib/src/providers/voting/voting_submission_job_provider.dart).

Implementation: [voting_session_provider.dart](../../../../lib/src/providers/voting/voting_session_provider.dart). Protocol internals: [Rust voting guide](../../../../rust/src/wallet/voting/README.md).

- The SDK owns durable bundle/vote/share phases and restart planning; Vizor
  orchestrates its APIs. Do not duplicate workflow tables or derive recovery
  from screen state. Pass every round proposal ID to `loadRoundPlan` and
  propagate planner failures.
- Context includes wallet DB, network, source, account UUID, and round. Actions
  use their captured context. On account change, the foreground session advances
  its generation and reloads; stale results cannot update the new UI.
- Background submissions have separate keys, stay pinned to their original
  account, and do not follow the foreground account listener. Account switching
  or screen disposal must preserve their active work.
- Dart stores random per-account/per-round secret hotkeys. Losing one after hotkey-bound
  artifacts exist is a recovery error: regeneration or seed derivation cannot
  recover old voting rights. Software delegation SpendAuth signing needs the
  wallet seed; hotkey generation and later vote signing do not. Hardware delegates
  through the device signer.

## Verification

- [Voting providers](../../../../test/providers/voting/voting_providers_test.dart):
  account changes, pinned submissions, partial signing, participation and drain.
  For casting, start with `each bundle confirms a proposal before proving the
  next one`, `proposal wave serializes broadcasts and overlaps confirmations`,
  `vote tree sync runs before each proposal`, and `a failed bundle chain stops
  at that bundle only`. These use fake chain/Rust responses.
