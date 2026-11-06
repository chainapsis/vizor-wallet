# Rust-originated text in the UI

Rust returns English text in two ways:

- **Errors.** An FRB function declared `Result<_, String>` throws the message
  as a Dart `String`. A function declared `Result<_, ApiWalletError>` throws
  `ApiWalletError { code, message }`. Its `toString()` is the message, and
  Dart reads the code with `walletErrorCode(error)`
  (`lib/src/core/zcash/wallet_error_code.dart`).
- **Results.** Broadcast and migration results carry a `status` string, which
  works as a code, and an optional English `message`. Broadcast results also
  carry `notices`, the same message as data (below).

Dart either shows that text unchanged or matches English phrases in it to
choose localized copy or a behaviour. This file lists every such site in
`lib/`, excluding generated `lib/src/rust/**` and `lib/l10n/**`.

Rules for new code:

- **Branch on a code or a status, never on message text.** When Rust only has
  text, add a `FailureCode` (`rust/src/wallet/failure.rs`) where the message is
  built. Mirror it in `ApiWalletErrorCode` (`rust/src/api/sync.rs`) and return
  `ApiWalletError` from the FRB function. Keep the English message unchanged:
  logs and the matchers listed below still read it.
- **A function that returns `String` drops any code.** The cause is
  `From<WalletFailure> for String`. Every function between the coded error
  and the FRB boundary must return `WalletFailure`.
- **English text stays only as secondary detail.** Rust text may stay English
  as a detail under a localized headline, and only when it is diagnostic
  (txids, transport status, storage errors).

## Codes

| `ApiWalletErrorCode` | Raised by (Rust) | FRB functions | Dart readers |
| --- | --- | --- | --- |
| `retryAfterRecovery`, `authorityRefused` | `sync/pczt.rs` `retryable_refusal` / `final_refusal` (hardware broadcast authority) | `store_and_broadcast_*`, `extract_and_broadcast_pczt`, Ledger broadcast | `send_flow.dart`, `transparent_shielding_service.dart`, Ledger services |
| `ledgerOperationTerminal` | `ledger/operations.rs` | `ledger_checkpoint_*`, `ledger_broadcast_signed_operation` | `ledger_signed_operation_service.dart` |
| `recoveryIncomplete`, `optOutUnfinished` | `sync/send.rs` shielding refusal | `create_shield_transparent_pczt`, `shield_transparent_balance*` | `friendlyShieldBalanceError` |
| `invalidUr`, `unexpectedUrType`, `urSessionReset` (new) | `wallet/keystone.rs` `decode_ur_part` | `decode_ur_part` | `services/qr_scanner.dart` (skip the frame, reset the session); `isUnexpectedUrTypeError` on the Keystone scan screens below |
| `keystoneBatchSignatureLimit`, `keystoneBatchUnsupportedInput` (new) | `sync/pczt.rs` `prepare_pczt_for_keystone_batch`, `checked_keystone_batch_signature_count` | `prepare_pczt_for_keystone_batch` | `keystoneBatchSigningFriendlyError` (send review, mobile Keystone send, swap desktop and mobile) |
| `paymentLinkBatchNotOneTransaction`, `paymentLinkBatchKeystoneSapling`, `paymentLinkBatchKeystoneSignatureLimit`, `paymentLinkBatchLedgerRecipientLimit`, `paymentLinkBatchLedgerSapling`, `paymentLinkBatchLedgerTooLarge` (new) | `sync/send.rs` `validate_payment_link_batch_proposal` | `estimate_payment_link_batch_fee`, `propose_payment_link_batch` | `PaymentLinkBatchRejected.text` (`payment_links_batch_creation.dart`, `payment_links_screen.dart`) |

`ExecuteProposalResult.broadcastFailureKind` (`rejected` / `unknown`) is a
result code too. `_broadcastStatusMessage` in `send_flow.dart` reads it
instead of matching `broadcast rejected` in the message.

## Matchers switched to a code

None of these changes English or any other locale: the matcher and the code
pick the same copy.

| Dart site | Rust text it matched | Now reads |
| --- | --- | --- |
| `services/qr_scanner.dart` `_shouldIgnoreDecodeError` | "Invalid UR: missing type prefix" | `invalidUr` |
| `services/qr_scanner.dart` `_shouldResetScanSessionAfterError` | "UR session reset: …" | `urSessionReset` |
| `keystone_send_scan_screen.dart`, `mobile_keystone_pczt_signing_flow.dart`, `mobile_keystone_shield_screen.dart`, `keystone_scan_qr_screen.dart`, `mobile_keystone_screens.dart`, `keystone_voting_scan_screen.dart`, migration `keystone_signing.dart` `ironwoodMigrationKeystoneScanErrorMessage` | "Unexpected UR type: got …, expected …" | `unexpectedUrType`. Migration still reads the received UR type (`zcash-sign-result`) from the message: it is protocol data, not copy. |
| `keystone/services/keystone_batch_signing.dart` `keystoneBatchSigningFriendlyError` | "Keystone batch signing supports at most 96 …", "… does not support transparent/Sapling transaction inputs" | `keystoneBatchSignatureLimit`, `keystoneBatchUnsupportedInput`. `send_review_screen.dart` now passes the error object, not its string. |
| `send/services/send_flow.dart` `_broadcastStatusMessage` | "Broadcast failed after n/m txs sent (…). Error: Broadcast rejected: …" | `broadcastFailureKind == 'rejected'` |
| `payment_link_service.dart` `PaymentLinkBatchRejected.from` | the "This group " prefix | `paymentLinkBatch*` codes; the six messages are ARB keys with the same English |

Upstream commit `0d3ec376e` (core messages) localized three things that also
come from Rust text:

- the network upgrade hold (`networkUpgradeHoldKind`,
  `networkUpgradeHoldMessage(l10n, …)`);
- the transparent ledger and recovery copy;
- `SyncFailure` copy.

Their matchers are listed below.

## Broadcast results: notices

`ExtractAndBroadcastPcztResult`, `StoreAndBroadcastPcztsResult`,
`ExecuteProposalResult` and the Ledger outbox's results carry
`notices: Vec<BroadcastNotice>` beside `message`. Each notice is one sentence
(`kind` plus `index`, `total`, `txid`, `detail`, `expiry_height`,
`chain_height`), and Rust builds `message` from them
(`wallet/sync/broadcast_notice.rs`), so the two cannot disagree. Dart shows
`broadcastResultText(l10n, notices: …, message: …)`
(`core/zcash/broadcast_notice_text.dart`): the `broadcastNotice*` ARB keys,
or `message` when there are no notices or one has a kind it does not know.

- **English is unchanged.** `test/fixtures/broadcast_notices_en.json` holds
  every kind and each composition. The Rust test checks `english()` against
  it and `test/l10n/broadcast_notice_text_test.dart` checks the English ARB
  copy against it. Rewording a sentence means changing Rust, the ARB key and
  the fixture together.
- **`message` stays.** Logs, endpoint failover
  (`shouldFallbackFromLightwalletdError`), `ledger/operations.rs`
  `acknowledge` for older rows and older builds read it.
- **`detail` stays English.** It is server, transport or Rust text: a gRPC
  status, "Broadcast rejected: … (code n)", a storage error. A `text` notice
  is a whole sentence with no fixed shape (a refusal after a mined round, the
  upgrade hold), shown as Rust wrote it; the hold already has localized copy
  through `networkUpgradeHoldMessage`, which the sites check first.
- **Stored results.** The Ledger outbox stores notices as JSON in a nullable
  `notices` column, added with `ALTER TABLE` by `ensure_table`. Rows written
  before it, and `retryable_error` rows, have none and show `message`.
  `acknowledge` decides "storage failed" from the notices, or from the English
  text for older rows. Swap records store `{type: 'broadcast', notices}` in
  `broadcastNoticeCode` beside the English in `broadcastNotice`
  (`SwapBroadcastMessage`); builds before this one read only the English.
- **Not covered.** The mobile swap Keystone screen classifies a failure
  through `_friendlyError`, and Ledger sends map unknown statuses to their own
  copy; neither shows `message`. `IronwoodMigrationResult` and software
  shielding (`ShieldTransparentResult`) have no notices.

| Dart site | Rust result |
| --- | --- |
| `send_flow.dart` `_pcztBroadcastStatusMessage` (Keystone sends), `_ledgerBroadcastStatusMessage` (Ledger sends) | `StoreAndBroadcastPcztsResult`, Ledger outbox |
| `transparent_shielding_service.dart` `shieldPcztBroadcastStatusMessage`, `keystone_shield_signing_overlay.dart`, `ledger_shield_signing_overlay.dart` | `ExtractAndBroadcastPcztResult`, Ledger outbox |
| `payment_link_keystone_signing_overlay.dart`, `payment_links_screen.dart` `_warnUnsettledHardwareFunding` | Keystone and Ledger Gift Card funding |
| `swap_keystone_signing_overlay.dart` | `ExtractAndBroadcastPcztResult` |
| `swap_state_provider.dart` `_depositBroadcastNotice` | software (`ExecuteProposalResult`) and hardware deposits |

## English matchers kept

Each one maps Rust text to localized copy or to a behaviour, so ko/zh show
localized copy. They stay because the Rust function returns `String`, or the
text comes from a dependency. If the Rust message is reworded, the matcher
silently stops matching.

| Dart site | Phrase(s) | Rust source | Why it stays |
| --- | --- | --- | --- |
| `core/zcash/network_upgrade_hold.dart` `networkUpgradeHoldKind` (37 callers) | `this close to the network upgrade`, `drawn before the network upgrade` | `wallet/network_upgrade.rs` `START_HOLD_MESSAGE`, `SEND_HOLD_MESSAGE`, `STALE_SCHEDULE_MESSAGE`; also inside broadcast results (`expired`) and migration results | Raised by many `String` functions (`propose_send`, `create_pczt_from_proposal`, `migrate_*`) and carried in result messages |
| `core/zcash/transparent_ledger_errors.dart` | `this build cannot operate on this wallet's transparent funds`, `transparent funds are unavailable` | librustzcash `zcash_client_sqlite::error` `TransparentLedgerIncompatible`, `TransparentAuthorityUnavailable` | Library errors reach Vizor as text. Vizor's own shielding refusal is already coded. |
| `send_flow.dart` `friendlyProposeSendError`, `friendlyBroadcastError`, `paymentRequestCheckIssueFor`; `send_screen.dart`, `mobile_send_screen.dart`, `donation_screen.dart`, `payment_request_precheck.dart`, `swap_failure_policy.dart`, `swap_state_provider.dart` `useMaxZecAmount`, `swap_max_amount_estimator.dart` | `insufficient`, `insufficientfunds`, `insufficient balance` | librustzcash `input_selection.rs` "Insufficient balance (have …, need … including fee)", wrapped "Propose failed: …" (`sync/send.rs`); Vizor "Insufficient shielded balance to cover fee" | `propose_send`, `estimate_fee`, `estimate_send_max` and `execute_proposal` return `String`; the library error is formatted in `propose_request` |
| same send sites | `grpc connect failed`, `connection refused`, `dns error`, `tls error` | `sync_engine/lwd.rs` "gRPC connect failed: {tonic}", tonic/hyper text | Transport text from dependencies |
| same | `broadcast failed after` + `txs sent`, `broadcast rejected` | `sync/send.rs` `CreatedBroadcastResult`, `sync/broadcast.rs` "Broadcast rejected: {msg} (code {n})" | Thrown by `String` functions |
| same, `send_review_screen.dart`, swap Keystone `_friendlyError`, `rpc_endpoint_failover_provider.dart` | `proposal not found`, `send flow mismatch` | `sync/send.rs` "Proposal not found (expired or already executed)", `sync/mod.rs` "Send flow mismatch" | Raised by shared proposal-store helpers that `String` functions call |
| `friendlyProposeSendError`, `mobile_send_screen.dart` `_estimateReviewFee`, `payment_request_precheck.dart` | `wallet must sync` | `sync/send.rs` "Wallet must sync before …" (13 sites) | `String` functions |
| shielding `friendlyShieldBalanceError`, Keystone/Ledger shield `_friendlyError` | `mnemonic`, `sync`, `insufficient`, `threshold`, `too small`, `no transparent funds`, `broadcast`, `sendtransaction`, `sapling`, `download`, `extract`, `pczt` | `sync/send.rs` "No transparent funds available to shield above the fee threshold", "Wallet must sync before shielding …", PCZT extraction errors | Broad keyword buckets over many messages |
| swap and Gift Card Keystone `_friendlyError` | `does not support tex`, `sapling`, `download`, `proposal not found`, `broadcast`, `sendtransaction`, `pczt`, `signature` | Dart `UnsupportedError` (TEX); Rust PCZT and broadcast errors | As above |
| migration `immediate_review.dart`, `mobile_ironwood_migration_review.dart`, `transfer_status.dart`, `keystone_signing.dart` | `plan changed`, `mnemonic`, `sync`, `broadcast`, `sendtransaction`, `proof` + `not ready`, `request` + `not found`, `batch result request id` + `does not match` | `sync/send.rs` "Immediate migration plan changed …", `ironwood_migration.rs` "… proofs are not ready", `keystone_requests.rs`, `api/keystone.rs` | Migration FRB functions return `String` |
| `providers/sync_failure.dart` `classifySyncFailure` | `network:`, `db:`, `parse:`, `chain continuity broken`, `private status coverage incomplete`, `tor connection failed`, database-locked phrases, transport phrases | `sync_engine/error.rs` `SyncError` Display, `sync_engine/lwd.rs`, `network_privacy.rs`, SQLite | Stream errors arrive as text (`sink.add_error(String)`) |
| `rpc_endpoint_failover_provider.dart` `shouldFallbackFromLightwalletdError`, failover in send/shield/swap | transport phrases, deny-list phrases | copy of `sync_engine/error.rs` `is_endpoint_failover_candidate_message` | Behaviour (endpoint failover) on dependency text; no copy |
| `receive_address_provider.dart` `_isDatabaseLockedError` | `database is locked`, `sqlite_busy`, … | SQLite via rusqlite | Behaviour (retry) |
| `account_provider.dart` `isWalletLinkDuplicateImportError`, `onboarding_error_messages.dart` | `account corresponding to the data provided` + `already exists in the wallet` | librustzcash `zcash_client_sqlite/src/error.rs`; `keys.rs` duplicate texts | `String` import functions |
| `app_bootstrap.dart` `_walletDbMigrationFailureMessage` | `seed is required`, `not relevant to any derived accounts` | librustzcash `wallet/init.rs` through `ensure_wallet_db_migrated` | `String` function; the screen words it by failure kind |
| `payment_link_service.dart` `PaymentLinkBatchRejected.from` | prefix `This group ` | `sync/send.rs` `validate_payment_link_batch_proposal` | See raw display below |
| `transparent_shielding_service.dart` `postBroadcastShieldErrorMessage`, `keystone_shield_signing_overlay.dart` `_postBroadcastErrorMessage` | `broadcast succeeded` | Only in `ExtractAndBroadcastPcztResult.message`, never in an error | Dead: no error carries the phrase |

## Stays English by design (secondary detail)

| Dart site | Rust source | Shown as |
| --- | --- | --- |
| `home_screen.dart` shield notice `shieldBalanceErrorDetails` | shielding errors | Detail under the localized `friendlyShieldBalanceError` headline |
| `receive_screen.dart` renew-address, shielded and transparent address load errors | `get_next_available_address`, `get_unified_address`, `get_transparent_receive_address` | Detail inside `commonErrorWithDetails` |
| `onboarding_error_messages.dart` `onboardingSubmitErrorMessage`, errors other than the three duplicates | create/import FRB functions in `api/wallet.rs` | Detail under `onboardingSubmitFailed` |
| migration `keystone_signing.dart` `ironwoodMigrationKeystoneProofFailureMessage` | `keystone_migration_proof_status`, `keystone_requests.rs` `proof_error` | Detail under `migrationKeystoneProofFailed` |
| `voting_config_error_text.dart` `votingConfigSourceErrorText` (desktop panel, mobile sheet) | `resolve_static_voting_config` / `resolve_voting_config_from_attempts` (`VotingErrorView`) | Detail under `votingConfigLoadFailed`, as `kind: message` |
| `mobile_ironwood_migration_review.dart` Fast migration warning | `IronwoodMigrationResult.message` ("The Immediate migration broadcast response was unavailable …") | Line under the localized `migrationMobileFastSubmittedBody` |
| Logs, `rpc_endpoint_failover_provider.dart` `lastFailure`, `NetworkPrivacyState.error` | various | Not displayed |

## Not Rust text

These matchers read Dart or HTTP text, not Rust:

- `swap_failure_policy.dart` 1Click matchers (NEAR HTTP response)
- `payment_links_screen.dart` `_showError(error.toString())` (Dart exceptions)
- `account_remove_modal.dart`, `account_edit_sheets.dart`
- `secure_storage_diagnostics.dart`
- `payment_request_precheck.dart` "wallet sync is still finishing" (`sync_provider.dart`)
- the endpoint `FormatException`s that `sync_failure.dart` reads
- `ironwood_migration_service.dart` credential recovery

## Follow-ups

1. **Codes for the `String` paths:** start with `propose_send`, `estimate_fee`
   and `estimate_send_max`, adding `InsufficientFunds`, `ProposalExpired`
   (proposal store) and `WalletNotSynced`. `propose_request` and the
   proposal-store helpers must then return `WalletFailure`.
2. **Raw-display rows** above.
