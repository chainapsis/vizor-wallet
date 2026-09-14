# Voting deletion and reset participation

Use when changing background-work registration, drain, or account-scoped cleanup.

Implementation: [voting_share_tracking_registry_provider.dart](../../../../lib/src/providers/voting/voting_share_tracking_registry_provider.dart), [wallet_mutation_guard.dart](../../../../lib/src/providers/wallet_mutation_guard.dart).

Implementation: [voting_session_provider.dart](../../../../lib/src/providers/voting/voting_session_provider.dart). Protocol internals: [Rust voting guide](../../../../rust/src/wallet/voting/README.md).

- Register wallet-side voting state/secure-storage work before its first async
  step. If `beginBackgroundWork` rejects a lease while quiesced, do not start it.
- Account deletion/reset blocks new work and drains existing leases/tracking
  before deleting data. Timer cancellation is not draining. Preserve migration
  quiescence and foreground sync pause order in the
  [mutation barrier](../../references/wallet/mutation-barrier.md).
- Lock/account/network/source changes invalidate async results. Cache deletion
  differs from durable recovery deletion; account deletion and full reset also
  have distinct cleanup scopes.

## Verification

- [Mutation guard](../../../../test/providers/wallet_mutation_guard_test.dart):
  destructive drain before sync pause and mutation/failure recovery.

## Related changes

For cleanup-scope changes, read [account deletion](../accounts/delete.md) or
[wallet reset](../wallet/reset.md), according to the operation being changed.
