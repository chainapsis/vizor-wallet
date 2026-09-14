# Shielding

Read when changing Shield Balance eligibility, execution, or recovery.

Shield Balance moves an account's transparent funds into shielded funds from
Home, using software credentials or Keystone. It has its own eligibility and
execution path; ordinary recipient-based transfers belong to [Send](../send/index.md).

- `get_shield_transparent_status` in [send.rs](../../../../rust/src/wallet/sync/send.rs)
  dry-runs the account's real shielding proposal to return eligibility, fee,
  and shielded amount. A positive displayed transparent balance alone does not
  make shielding available. Home and the execution service consume account-scoped
  status; Rust rebuilds the proposal for execution.
- [transparent_shielding_service.dart](../../../../lib/src/features/home/services/transparent_shielding_service.dart)
  owns software execution and returns the txids and broadcast status. Pending
  and partial broadcasts remain queued for recovery; Home directs users to
  Activity rather than offering a fresh conflicting send. A later balance-refresh
  failure does not turn an existing broadcast result into shielding failure.
- Hardware shielding retains full-PCZT signing for transparent inputs; ordinary
  Send's compact batch protocol is not interchangeable. See
  [hardware signing](../../references/signing/pczt-protocol-selection.md),
  [desktop shielding](../../../../lib/src/features/home/widgets/keystone_shield_signing_overlay.dart),
  and [mobile shielding](../../../../lib/src/features/home/screens/mobile/mobile_keystone_shield_screen.dart).
- Software credential access follows the shared
  platform-specific storage boundaries,
  including Linux ownership checks after keyring waits.

## Verification

- [Shielding result messages](../../../../test/features/home/home_shield_balance_message_test.dart)
  pin pending/partial recovery copy; [Rust send tests](../../../../rust/src/wallet/sync/send/tests.rs)
  cover shielding source selection and broadcast-result conversion.

## Related changes

- When changing PCZT proofs or finalization, read [PCZT finalization](../../references/signing/pczt-finalization.md).
- When changing Linux delayed credential use, read [Linux keyring ownership](../../platforms/linux/keyring.md).
- When changing Apple credential access, read [Apple Keychain](../../platforms/apple/keychain.md).
