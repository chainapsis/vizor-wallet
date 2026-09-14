# Send broadcast outcomes

Read when changing Send/Donation execution, broadcast receipts, or retry after a network result.

- Dart orchestration: [`send_flow.dart`](../../../../lib/src/features/send/services/send_flow.dart)
  (`SendReviewArgs`, `proposeSendTransfer`, `discardSendProposal`, `runSendBroadcast`).
- Rust software execution: [`send.rs`](../../../../rust/src/wallet/sync/send.rs).
- Rust hardware execution: [`pczt.rs`](../../../../rust/src/wallet/sync/pczt.rs).

`runSendBroadcast` returns `succeeded`, `pendingBroadcast`, `failed`, or
`aborted` and whether Rust consumed the proposal. It obtains required Sapling
parameters, signs software sends or finalizes hardware PCZTs, applies endpoint
failover policy, and refreshes wallet state.

After transaction creation, transport or partial-broadcast failures remain
recoverable pending outcomes; they do not permit resending. TEX receipts use
the final dependent transaction; ordinary sends use the first. Expired hardware
transactions fail and require fresh review. Pre-broadcast errors release the
proposal; ambiguous hardware broadcasts may retain input locks until expiry to
prevent conflicting retries.

Software mnemonic bytes come only from the proposal account, pass to Rust, and
are overwritten immediately after execution starts. macOS may use the native
stored-mnemonic path instead. Hardware accounts never enter either branch.

## Verification

- [`send_status_screen_test.dart`](../../../../test/features/send/send_status_screen_test.dart):
  Dart broadcast/status orchestration, TEX receipt selection, and proposal cleanup
  with a fake Rust API.
- [`linux_secret_consumers_test.dart`](../../../../test/core/storage/linux_secret_consumers_test.dart):
  interrupted secret reads block execution and clear mnemonic buffers.

## Related changes

- When changing pre-broadcast cleanup, read [proposal release](proposal-release.md).
- When changing PCZT validation or persistence, read [PCZT finalization](../signing/pczt-finalization.md).
- When changing endpoint failover, read [network route policy](../network/route-policy.md).
- When changing credential acquisition, read [secret sessions](../storage/secret-sessions.md).
