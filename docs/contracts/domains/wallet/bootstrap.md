# Wallet bootstrap

Read when changing first-frame routes, account reconciliation, or startup hydration and blocking failures.

## Startup snapshot

- [`loadAppBootstrap`](../../../../lib/src/app_bootstrap.dart) reconciles stored metadata
  with Rust rows into one snapshot for the router, account, wallet, and sync
  providers. Normal startup awaits it before `runApp`, giving the first frame
  its route and account state.

- The snapshot routes no wallet to `/welcome`, a locked wallet to `/unlock`, and
  an unlocked wallet to `/home`. Locked bootstrap leaves address publication and
  balance/history hydration to unlock.

- Initial balance/history hydration is best-effort, falling back to an empty
  snapshot for the same account. Secure-storage or DB migration failure blocks
  startup; it must not appear as an empty wallet.

## Verification anchors

- Account/session behavior:
  [`account_metadata_session_test.dart`](../../../../test/providers/account_metadata_session_test.dart)

## Related changes

- When restoring data after a locked startup, follow [unlock ordering](lock-unlock.md).
- When changing storage failure/recovery on Linux, read [Linux keyring](../../platforms/linux/keyring.md).
