# Linux keyring recovery

Read when changing native keyring serialization, retry/cancel behavior, unknown write outcomes, or secret ownership after a keyring wait.

## Recovery and operation ownership

- Production `enforcesSessionGeneration` is Linux-specific. Its
  [LinuxSecretOperationGuard](../../../../lib/src/core/storage/linux_secret_operation_guard.dart)
  rechecks request liveness before reading provider state, then session generation,
  password availability, pending mutation, and account ownership after keyring
  waits. Other platforms still use their provider-level lifecycle checks.

- [LinuxKeyringCoordinator](../../../../lib/src/core/storage/linux_keyring_coordinator.dart)
  serializes native storage calls. Recovery starts only after a native error.
  Cancel abandons a failed read only when no wallet mutation is pending; it
  cannot cancel an in-flight native keyring prompt. Retry repeats the individual
  storage call, never the enclosing wallet mutation.

- A recognized write error other than `KeyringLocked` leaves its outcome unknown
  and blocks further coordinated storage calls until restart. Never replay it
  as a failed write or present unavailable/corrupt storage as an empty wallet.

## Verification anchors

- Linux recovery and interrupted secret consumers:
  [linux_keyring_coordinator_test.dart](../../../../test/core/storage/linux_keyring_coordinator_test.dart),
  [linux_secret_consumers_test.dart](../../../../test/core/storage/linux_secret_consumers_test.dart).

## Related changes

- When changing platform-independent credential/session ownership, read [secret sessions](../../references/storage/secret-sessions.md).
- When a keyring operation belongs to a wallet mutation, preserve [mutation ordering](../../references/wallet/mutation-barrier.md).
