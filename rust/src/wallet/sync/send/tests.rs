use super::super::migration;
use super::*;

use incrementalmerkletree::Position;
use rusqlite::params;
use transparent::bundle::{OutPoint, TxOut};
use zcash_client_backend::{data_api::WalletWrite, wallet::WalletTransparentOutput};
use zcash_keys::keys::{ReceiverRequirement, UnifiedSpendingKey};
use zcash_protocol::consensus::BlockHeight;

const MIGRATION_TEST_ACCOUNT: &str = "account-1";
const MIGRATION_TEST_PASSWORD: &[u8] = b"correct horse battery staple";
const MIGRATION_TEST_SALT: &str = "AQIDBAUGBwgJCgsMDQ4PEA==";

#[test]
fn immediate_migration_plan_ignores_zero_value_orchard_notes() {
    let target_height = BlockHeight::from_u32(500);
    let with_padding = immediate_migration_plan_for_values(
        WalletNetwork::Regtest,
        target_height,
        [0, 100_000, 0, 200_000, 0],
    )
    .unwrap()
    .unwrap();
    let without_padding = immediate_migration_plan_for_values(
        WalletNetwork::Regtest,
        target_height,
        [100_000, 200_000],
    )
    .unwrap()
    .unwrap();

    assert_eq!(with_padding, without_padding);
    assert_eq!(with_padding.total_input_zatoshi, 300_000);
    assert_eq!(with_padding.input_note_count, 2);
    assert_eq!(
        with_padding.migrated_zatoshi + with_padding.fee_zatoshi,
        with_padding.total_input_zatoshi
    );
    assert!(
        immediate_migration_plan_for_values(WalletNetwork::Regtest, target_height, [0, 0, 0],)
            .unwrap()
            .is_none()
    );
}

#[test]
fn migration_anchor_uses_latest_checkpoint_before_an_empty_bucket_boundary() {
    let checkpoints = [5_318, 5_450, 5_460, 5_500];

    assert_eq!(
        representative_orchard_checkpoint(&checkpoints, 5_472, 5_400),
        Some(5_460)
    );
}

#[test]
fn migration_anchor_never_uses_a_checkpoint_before_the_prepared_note() {
    let checkpoints = [5_318, 5_399, 5_500];

    assert_eq!(
        representative_orchard_checkpoint(&checkpoints, 5_472, 5_400),
        None
    );
}

#[test]
fn migration_anchor_counts_empty_buckets_with_the_same_root_once() {
    let checkpoints = [5_400, 5_800];

    assert_eq!(
        available_orchard_anchor_candidates(&[5_760, 5_616, 5_472], &checkpoints, 5_300),
        vec![(5_760, 5_400)]
    );
}

#[test]
fn keystone_migration_signing_rejects_more_than_fifty_messages() {
    let messages = (0..=ZCASH_SIGN_BATCH_MAX_MESSAGES)
        .map(|index| KeystoneMigrationMessage {
            id: format!("message-{index}"),
            redacted_pczt: vec![index as u8, 1],
        })
        .collect::<Vec<_>>();

    let error = validate_keystone_migration_messages(&messages).unwrap_err();

    assert!(error.contains("at most 50 PCZTs per round"));
    assert!(error.contains("needs 51"));
}

#[test]
fn deleting_account_discards_only_its_keystone_migration_requests() {
    const DELETED_ACCOUNT: &str = "keystone-delete-account";
    const KEPT_ACCOUNT: &str = "keystone-kept-account";
    let plan = migration::plan_denominations(1_000_000, 10_000, 15_000, 1).unwrap();

    for (request_id, account_uuid) in [
        ("delete-denomination-request", DELETED_ACCOUNT),
        ("keep-denomination-request", KEPT_ACCOUNT),
    ] {
        keystone_denomination_requests().lock().unwrap().insert(
            request_id.to_string(),
            StoredDenominationPczt {
                account_uuid: account_uuid.to_string(),
                network: WalletNetwork::Test,
                state: KeystoneMigrationRequestState::ProofReady,
                proof_error: None,
                split_stages: vec![],
                direct_prepared_refs: vec![],
                total_migratable_zatoshi: plan.total_migratable_zatoshi,
                plan: plan.clone(),
            },
        );
    }
    for (request_id, account_uuid) in [
        ("delete-batch-request", DELETED_ACCOUNT),
        ("keep-batch-request", KEPT_ACCOUNT),
    ] {
        keystone_migration_requests().lock().unwrap().insert(
            request_id.to_string(),
            StoredMigrationPcztBatch {
                account_uuid: account_uuid.to_string(),
                network: WalletNetwork::Test,
                run_id: format!("run-{request_id}"),
                fallback_total_count: 0,
                fallback_migrated_zatoshi: 0,
                recovery_old_txids: vec![],
                state: KeystoneMigrationRequestState::ProofReady,
                proof_error: None,
                messages: vec![],
            },
        );
    }
    for (request_id, account_uuid) in [
        ("delete-single-request", DELETED_ACCOUNT),
        ("keep-single-request", KEPT_ACCOUNT),
    ] {
        keystone_single_qr_migration_requests()
            .lock()
            .unwrap()
            .insert(
                request_id.to_string(),
                StoredSingleQrMigrationPczt {
                    account_uuid: account_uuid.to_string(),
                    network: WalletNetwork::Test,
                    state: KeystoneMigrationRequestState::ProofReady,
                    proof_error: None,
                    split_stages: vec![],
                    direct_prepared_refs: vec![],
                    total_migratable_zatoshi: plan.total_migratable_zatoshi,
                    plan: plan.clone(),
                    child_messages: vec![],
                    approved_schedule: vec![],
                },
            );
    }

    discard_keystone_migration_requests_for_account(DELETED_ACCOUNT, WalletNetwork::Test).unwrap();

    for request_id in [
        "delete-denomination-request",
        "delete-batch-request",
        "delete-single-request",
    ] {
        assert!(keystone_migration_proof_status(request_id).is_err());
    }
    for request_id in [
        "keep-denomination-request",
        "keep-batch-request",
        "keep-single-request",
    ] {
        assert!(keystone_migration_proof_status(request_id).is_ok());
        discard_keystone_migration_request(request_id).unwrap();
    }
}

#[test]
fn foreground_migration_policy_keeps_existing_batch_behavior() {
    assert_eq!(MigrationBroadcastPolicy::FOREGROUND.limit(500), 500);
    assert_eq!(MigrationBroadcastPolicy::FOREGROUND.proof_limit(500), 500);
    assert!(!MigrationBroadcastPolicy::FOREGROUND.should_defer_broadcast(500));
    assert!(!MigrationBroadcastPolicy::FOREGROUND.is_cancelled());
}

#[test]
fn incrementally_persisted_children_can_resume_proving() {
    let run = crate::wallet::sync::migration::ActiveRun {
        run_id: "run-1".to_string(),
        phase: crate::wallet::sync::migration::PHASE_BROADCAST_SCHEDULED.to_string(),
        target_values_zatoshi: vec![100, 200],
        last_error: None,
    };

    assert!(run_may_finalize_presigned_migration_children(&run));
}

#[test]
fn on_open_migration_policy_sends_at_most_one_due_transaction() {
    assert_eq!(MigrationBroadcastPolicy::ONE_FOREGROUND.limit(0), 0);
    assert_eq!(MigrationBroadcastPolicy::ONE_FOREGROUND.limit(1), 1);
    assert_eq!(MigrationBroadcastPolicy::ONE_FOREGROUND.limit(500), 1);
    assert_eq!(
        MigrationBroadcastPolicy::ONE_FOREGROUND.proof_limit(500),
        500
    );
    assert!(!MigrationBroadcastPolicy::ONE_FOREGROUND.should_defer_broadcast(500));
    assert!(!MigrationBroadcastPolicy::ONE_FOREGROUND.is_cancelled());
}

fn taddr(seed: u8) -> TransparentAddress {
    TransparentAddress::PublicKeyHash([seed; 20])
}

fn balance(value: u64) -> Balance {
    let mut balance = Balance::ZERO;
    balance
        .add_spendable_value(Zatoshis::from_u64(value).unwrap())
        .unwrap();
    balance
}

fn receiver(value: u64, scope: TransparentKeyScope) -> (TransparentKeyOrigin, Balance) {
    (TransparentKeyOrigin::Derived { scope }, balance(value))
}

fn migration_test_plan() -> migration::DenominationPlan {
    migration::DenominationPlan {
        migration_outputs: vec![100_000],
        orchard_change: None,
        split_fee_zatoshi: 10_000,
        migration_fee_zatoshi: 10_000,
        total_input_zatoshi: 120_000,
        total_migratable_zatoshi: 100_000,
    }
}

fn migration_test_note(txid_hex: &str) -> migration::PreparedOrchardNoteRef {
    migration::PreparedOrchardNoteRef {
        txid_hex: txid_hex.to_string(),
        output_index: 0,
        value_zatoshi: 100_000,
        note_version: 2,
        nullifier_hex: None,
    }
}

#[test]
fn missing_orchard_anchor_is_a_retryable_witness_error() {
    assert!(is_orchard_witness_not_ready_error(
        "Read Orchard witnesses: Proposal(AnchorNotFound(BlockHeight(509)))"
    ));
    assert!(!is_orchard_witness_not_ready_error(
        "Read Orchard witnesses: invalid note commitment"
    ));
}

#[test]
fn active_migration_restricts_ordinary_sends_to_ironwood() {
    let policy = ordinary_send_spend_policy(true);

    assert!(!policy.permits_shielded(ShieldedProtocol::Sapling));
    assert!(!policy.permits_shielded(ShieldedProtocol::Orchard));
    assert!(policy.permits_shielded(ShieldedProtocol::Ironwood));
    assert_eq!(
        ordinary_send_spend_pools(true),
        vec![ShieldedProtocol::Ironwood]
    );
}

#[test]
fn ordinary_send_policy_keeps_all_shielded_pools_without_migration() {
    let policy = ordinary_send_spend_policy(false);

    assert!(policy.permits_shielded(ShieldedProtocol::Sapling));
    assert!(policy.permits_shielded(ShieldedProtocol::Orchard));
    assert!(policy.permits_shielded(ShieldedProtocol::Ironwood));
}

fn migration_test_stage(
    input_txid_hex: &str,
    output_txid_hex: &str,
) -> migration::DenominationStageInsert {
    migration::DenominationStageInsert {
        stage_index: 0,
        base_pczt: vec![0xa0],
        sigs: Vec::new(),
        raw_tx: Some(vec![1, 2, 3, 4]),
        expected_txid_hex: output_txid_hex.to_string(),
        target_height: 90,
        expiry_height: 120,
        fee_zatoshi: 10_000,
        status: migration::DenominationStageStatus::Pending,
        inputs: vec![migration::DenominationStageInputRef {
            txid_hex: input_txid_hex.to_string(),
            output_index: 0,
            value_zatoshi: 120_000,
            note_version: 2,
            nullifier_hex: None,
        }],
        outputs: vec![migration::DenominationStageOutputRef {
            output_index: 0,
            value_zatoshi: 100_000,
            note_version: 2,
            kind: migration::DenominationStageOutputKind::Migration,
            part_index: Some(0),
        }],
    }
}

fn create_outbox_receipt_test_run(
    expiry_height: u32,
) -> (tempfile::TempDir, String, String, String) {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let denomination_input_txid = "30".repeat(32);
    let selected_note_txid = "10".repeat(32);
    let pending_txid = "20".repeat(32);
    let selected_note = migration_test_note(&selected_note_txid);
    let run_id = migration::create_run_with_staged_denominations_and_signed_children(
        &db_path,
        MIGRATION_TEST_ACCOUNT,
        WalletNetwork::Test,
        &migration_test_plan(),
        std::slice::from_ref(&selected_note),
        Vec::new(),
        vec![migration_test_stage(
            &denomination_input_txid,
            &selected_note_txid,
        )],
        None,
        migration::PreparationTimingPolicy::Immediate,
        MIGRATION_TEST_PASSWORD,
        MIGRATION_TEST_SALT,
    )
    .unwrap();
    migration::insert_pending_txs(
        &db_path,
        &run_id,
        vec![migration::PendingMigrationTxInsert {
            part_index: 0,
            txid_hex: pending_txid.clone(),
            raw_tx: vec![5, 6, 7, 8],
            target_height: 100,
            anchor_boundary_height: Some(90),
            expiry_height,
            scheduled_height: 100,
            value_zatoshi: 100_000,
            fee_zatoshi: 10_000,
            selected_note: selected_note.clone(),
            metadata: migration::PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: MIGRATION_TEST_ACCOUNT.to_string(),
                selected_note,
            },
        }],
        MIGRATION_TEST_PASSWORD,
        MIGRATION_TEST_SALT,
    )
    .unwrap();
    (temp_dir, db_path, run_id, pending_txid)
}

#[test]
fn parse_txid_hex_accepts_display_order_hex() {
    let txid_hex = "838813428b78712263511ed5c6fb9a108c939038a440b74f72bee6caedf602fd";
    let txid = parse_txid_hex(txid_hex).unwrap();

    assert_eq!(format!("{txid}"), txid_hex);
}

#[test]
fn shield_result_preserves_pending_broadcast_status() {
    let result = CreatedBroadcastResult {
        txids: "abc123".to_string(),
        status: CreatedBroadcastResult::PENDING_BROADCAST,
        broadcasted_count: 0,
        total_count: 1,
        message: Some("Broadcast could not start".to_string()),
    }
    .into_shield_transparent_result(10_000, 90_000);

    assert_eq!(result.txids, "abc123");
    assert_eq!(result.status, CreatedBroadcastResult::PENDING_BROADCAST);
    assert_eq!(result.broadcasted_count, 0);
    assert_eq!(result.total_count, 1);
    assert_eq!(result.message.as_deref(), Some("Broadcast could not start"));
    assert_eq!(result.fee_zatoshi, 10_000);
    assert_eq!(result.shielded_zatoshi, 90_000);
}

#[test]
fn migration_rebuilds_only_after_explicit_server_rejection() {
    assert!(migration_broadcast_failure_requires_rebuild(
        "Broadcast rejected: bad-txns-inputs-spent (code 18)"
    ));
    assert!(!migration_broadcast_failure_requires_rebuild(
        "SendTransaction gRPC failed: connection unavailable"
    ));
}

#[test]
fn unbroadcast_recovery_requires_scheduled_transactions_past_the_safety_window() {
    let scheduled = migration::UnbroadcastMigrationRecoveryCandidate {
        txid_hex: "10".repeat(32),
        status: "scheduled".to_string(),
        scheduled_height: 100,
    };

    assert_eq!(
        validate_unbroadcast_migration_recovery_candidates(std::slice::from_ref(&scheduled), 109,)
            .unwrap_err(),
        "Migration recovery must wait until block 110"
    );
    validate_unbroadcast_migration_recovery_candidates(&[scheduled], 110).unwrap();
}

#[test]
fn unbroadcast_recovery_rejects_a_transaction_marked_as_broadcasted() {
    let broadcasted = migration::UnbroadcastMigrationRecoveryCandidate {
        txid_hex: "20".repeat(32),
        status: "broadcasted".to_string(),
        scheduled_height: 100,
    };

    assert_eq!(
        validate_unbroadcast_migration_recovery_candidates(&[broadcasted], 200).unwrap_err(),
        format!(
            "Migration transaction {} was already marked as broadcasted",
            "20".repeat(32)
        )
    );
}

#[test]
fn rejected_outbox_receipt_retires_run_idempotently() {
    let (_temp_dir, db_path, run_id, pending_txid) = create_outbox_receipt_test_run(69_120);

    for _ in 0..2 {
        reconcile_orchard_migration_outbox_receipt(
            &db_path,
            WalletNetwork::Test,
            MIGRATION_TEST_ACCOUNT,
            &run_id,
            &pending_txid,
            "rejected",
            100,
            Some("policy reject"),
            Vec::new(),
            None,
        )
        .unwrap();
    }

    assert!(
        migration::active_migration_run(&db_path, MIGRATION_TEST_ACCOUNT, WalletNetwork::Test,)
            .unwrap()
            .is_none()
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let phase: String = conn
        .query_row(
            "SELECT phase FROM vizor_migration_runs WHERE run_id = ?1",
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(phase, migration::PHASE_FAILED_TERMINAL);
}

#[test]
fn expired_outbox_receipt_marks_parts_for_resign_at_remote_height() {
    let (_temp_dir, db_path, run_id, pending_txid) = create_outbox_receipt_test_run(69_120);

    for _ in 0..2 {
        reconcile_orchard_migration_outbox_receipt(
            &db_path,
            WalletNetwork::Test,
            MIGRATION_TEST_ACCOUNT,
            &run_id,
            &pending_txid,
            "expired",
            69_120,
            None,
            Vec::new(),
            None,
        )
        .unwrap();
    }

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let (phase, status): (String, String) = conn
        .query_row(
            "SELECT r.phase, p.status
             FROM vizor_migration_runs r
             JOIN vizor_migration_pending_txs p ON p.run_id = r.run_id
             WHERE r.run_id = ?1",
            params![run_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(phase, migration::PHASE_READY_TO_MIGRATE);
    assert_eq!(status, "needs_resign");
}

#[test]
fn accepted_outbox_receipt_requires_the_native_raw_transaction() {
    let (_temp_dir, db_path, run_id, pending_txid) = create_outbox_receipt_test_run(69_120);

    let error = reconcile_orchard_migration_outbox_receipt(
        &db_path,
        WalletNetwork::Test,
        MIGRATION_TEST_ACCOUNT,
        &run_id,
        &pending_txid,
        "accepted",
        100,
        None,
        Vec::new(),
        None,
    )
    .unwrap_err();

    assert_eq!(
        error,
        "Accepted migration outbox receipt is missing its raw transaction"
    );
}

#[test]
fn accepted_outbox_receipt_recovers_a_part_marked_for_resign() {
    let (_temp_dir, db_path, run_id, pending_txid) = create_outbox_receipt_test_run(69_120);

    reconcile_orchard_migration_outbox_receipt(
        &db_path,
        WalletNetwork::Test,
        MIGRATION_TEST_ACCOUNT,
        &run_id,
        &pending_txid,
        "expired",
        69_120,
        None,
        Vec::new(),
        None,
    )
    .unwrap();

    migration::apply_accepted_migration_outbox_receipt(
        &db_path,
        MIGRATION_TEST_ACCOUNT,
        WalletNetwork::Test,
        &run_id,
        &pending_txid,
        69_121,
        &[],
    )
    .unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let status: String = conn
        .query_row(
            "SELECT status FROM vizor_migration_pending_txs
             WHERE run_id = ?1 AND txid_hex = ?2",
            params![run_id, pending_txid],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(status, "broadcasted");
}

#[test]
fn send_proposals_use_v6_after_nu6_3() {
    let network = WalletNetwork::Regtest;
    crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
    let v2_only = SelectedOrchardNoteVersions {
        has_v2: true,
        has_v3: false,
    };

    // Pass-1 ceiling: no explicit version before activation, V6 after.
    let before = proposed_tx_version_for_send(network, TargetHeight::from(1));
    let after = proposed_tx_version_for_send(network, TargetHeight::from(2));
    assert_eq!(before, None);
    assert_eq!(after, Some(TxVersion::V6));

    // The pass-2 decision keys off that ceiling: a V2-only selection with a
    // non-Orchard payment downgrades a post-activation V6 proposal, never a
    // pre-activation one.
    assert!(should_downgrade_send_to_legacy_v5(after, &v2_only, false));
    assert!(!should_downgrade_send_to_legacy_v5(before, &v2_only, false));
}

#[test]
fn v5_downgrade_requires_v6_ceiling_and_v2_only_spends() {
    let versions = |has_v2, has_v3| SelectedOrchardNoteVersions { has_v2, has_v3 };

    // Canonical downgrade case: V6 ceiling, V2-only spends, non-Orchard
    // recipient.
    assert!(should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(true, false),
        false,
    ));
    // Shielded-Orchard recipient: a legacy-V5 build would fail with
    // CrossAddressDisabled, so stay V6 even for V2-only spends.
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(true, false),
        true,
    ));
    // V3-only and mixed selections keep V6 (mixed keeps the V3 change).
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(false, true),
        false,
    ));
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(true, true),
        false,
    ));
    // No Orchard spends at all: nothing to preserve, keep V6.
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(false, false),
        false,
    ));
    // Pre-activation (no pass-1 ceiling) proposals are never rewritten.
    assert!(!should_downgrade_send_to_legacy_v5(
        None,
        &versions(true, false),
        false,
    ));
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V5),
        &versions(true, false),
        false,
    ));
}

/// Fabricates a transparent-recipient proposal spending one Orchard note
/// per entry in `versions` (plus a lone Sapling note when `versions` is
/// empty, so the proposal still has a shielded input), mirroring
/// `transparent_recipient_send_max_proposal_spends_shielded_notes`.
fn fabricated_shielded_spend_proposal(
    versions: &[orchard::note::NoteVersion],
) -> Proposal<WalletFeeRule, u32> {
    let network = WalletNetwork::Regtest;
    let orchard_notes = versions
        .iter()
        .enumerate()
        .map(|(index, version)| {
            let sk = orchard::keys::SpendingKey::from_bytes([7 + index as u8; 32]).unwrap();
            let fvk = orchard::keys::FullViewingKey::from(&sk);
            let recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
            let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
            let rseed = (0u8..=255)
                .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
                .expect("test rseed");
            let note = orchard::Note::from_parts(
                recipient,
                orchard::value::NoteValue::from_raw(100_000),
                rho,
                rseed,
                *version,
            )
            .unwrap();
            ReceivedNote::from_parts(
                index as u32,
                TxId::from_bytes([index as u8; 32]),
                0,
                note,
                zip32::Scope::External,
                Position::from(index as u64),
                Some(BlockHeight::from_u32(20)),
                None,
            )
        })
        .collect::<Vec<_>>();
    let sapling_notes = if orchard_notes.is_empty() {
        let spending_key = sapling_crypto::zip32::ExtendedSpendingKey::master(&[7u8; 32]);
        let (_, recipient) = spending_key.default_address();
        let note = sapling_crypto::Note::from_parts(
            recipient,
            sapling_crypto::value::NoteValue::from_raw(100_000),
            sapling_crypto::Rseed::AfterZip212([3u8; 32]),
        );
        vec![ReceivedNote::from_parts(
            100u32,
            TxId::from_bytes([100u8; 32]),
            0,
            note,
            zip32::Scope::External,
            Position::from(0u64),
            Some(BlockHeight::from_u32(20)),
            None,
        )]
    } else {
        vec![]
    };
    let recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

    build_transparent_recipient_send_max_proposal_from_notes(
        network,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        BlockHeight::from_u32(900),
        recipient,
        None,
        ReceivedNotes::new(sapling_notes, orchard_notes, vec![]),
        ConservativeZip317FeeRule,
    )
    .expect("fabricated proposal should build")
}

/// Fabricates a single-step proposal that spends one V2 Orchard note and
/// pays a recipient in `payment_pool`, so `payment_pools()` reflects the
/// requested recipient pool. Used to exercise
/// [`proposal_has_orchard_payment`] and the recipient-pool guard.
fn fabricated_proposal_with_payment_pool(payment_pool: PoolType) -> Proposal<WalletFeeRule, u32> {
    let network = WalletNetwork::Regtest;
    let sk = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
    let fvk = orchard::keys::FullViewingKey::from(&sk);
    let orchard_recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
    let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
    let rseed = (0u8..=255)
        .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
        .expect("test rseed");
    let note = orchard::Note::from_parts(
        orchard_recipient,
        orchard::value::NoteValue::from_raw(100_000),
        rho,
        rseed,
        orchard::note::NoteVersion::V2,
    )
    .unwrap();
    let received_note = ReceivedNote::from_parts(
        0u32,
        TxId::from_bytes([0u8; 32]),
        0,
        note,
        zip32::Scope::External,
        Position::from(0u64),
        Some(BlockHeight::from_u32(20)),
        None,
    );

    // Recipient address matches the requested payment pool.
    let to = match payment_pool {
        PoolType::Transparent => Address::Transparent(taddr(9)).to_zcash_address(&network),
        PoolType::Shielded(ShieldedProtocol::Orchard) => {
            let ua = zcash_keys::address::UnifiedAddress::from_receivers(
                Some(orchard_recipient),
                None,
                None,
            )
            .expect("UA with an Orchard receiver is valid");
            Address::from(ua).to_zcash_address(&network)
        }
        PoolType::Shielded(ShieldedProtocol::Sapling) => {
            let esk = sapling_crypto::zip32::ExtendedSpendingKey::master(&[9u8; 32]);
            let (_, sapling_recipient) = esk.default_address();
            Address::from(sapling_recipient).to_zcash_address(&network)
        }
        PoolType::Shielded(ShieldedProtocol::Ironwood) => {
            unreachable!("this fixture never requests Ironwood payments")
        }
    };

    // No change: amount + fee must equal the single 100_000-zat input, or
    // `Proposal::single_step` rejects the unbalanced proposal.
    let fee = Zatoshis::const_from_u64(10_000);
    let amount = Zatoshis::const_from_u64(90_000);
    let payment = Payment::new(to, Some(amount), None, None, None, vec![]).unwrap();
    let request = TransactionRequest::new(vec![payment]).unwrap();
    // `ShieldedInputs` wants `ReceivedNote<_, wallet::Note>`; wrap the
    // orchard-typed note through `ReceivedNotes::into_vec` to get that form.
    let notes = ReceivedNotes::new(vec![], vec![received_note], vec![]).into_vec(&RetainAllNotes);
    let shielded_inputs = ShieldedInputs::from_parts(nonempty::NonEmpty::from_vec(notes).unwrap());
    let balance = TransactionBalance::new(vec![], fee).unwrap();

    Proposal::single_step(
        request,
        BTreeMap::from([(0usize, payment_pool)]),
        vec![],
        Some(shielded_inputs),
        BlockHeight::from_u32(900),
        balance,
        ConservativeZip317FeeRule,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        ConfirmationsPolicy::default(),
        false,
        false,
    )
    .expect("fabricated payment-pool proposal should build")
}

#[test]
fn proposal_has_orchard_payment_detects_recipient_pool() {
    // Orchard recipient => Orchard payment.
    assert!(proposal_has_orchard_payment(
        &fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Orchard)),
    ));
    // Transparent recipient (Orchard change is not a payment pool) => none.
    assert!(!proposal_has_orchard_payment(
        &fabricated_proposal_with_payment_pool(PoolType::Transparent),
    ));
    // Sapling recipient => not an Orchard payment.
    assert!(!proposal_has_orchard_payment(
        &fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Sapling)),
    ));
    // Change-only send-max proposal (transparent recipient, Orchard spend)
    // has no Orchard payment pool either.
    assert!(!proposal_has_orchard_payment(
        &fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]),
    ));
}

#[test]
fn orchard_recipient_v2_send_keeps_v6_without_rerun() {
    // V2-only spend paying a shielded-Orchard recipient: must stay V6 (a V5
    // build would fail with CrossAddressDisabled), and the re-proposal
    // closure must never run.
    let pass1 =
        fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Orchard));

    let (_, tx_version) = propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |_| {
        panic!("re-proposal must not run for a shielded-Orchard recipient")
    });

    assert_eq!(tx_version, Some(TxVersion::V6));
}

#[test]
fn transparent_recipient_v2_send_downgrades_to_v5() {
    // Contrast with the Orchard-recipient case: a transparent recipient with
    // the same V2-only spend downgrades to V5.
    let pass1 = fabricated_proposal_with_payment_pool(PoolType::Transparent);
    let rerun = fabricated_proposal_with_payment_pool(PoolType::Transparent);

    let (_, tx_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), move |requested| {
            assert_eq!(requested, Some(TxVersion::V5));
            Ok(rerun)
        });

    assert_eq!(tx_version, Some(TxVersion::V5));
}

#[test]
fn proposal_selected_orchard_note_versions_detects_spent_versions() {
    use orchard::note::NoteVersion;

    let v2_only = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
        NoteVersion::V2,
    ]));
    assert!(v2_only.has_v2 && !v2_only.has_v3);

    let v3_only = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
        NoteVersion::V3,
    ]));
    assert!(!v3_only.has_v2 && v3_only.has_v3);

    let mixed = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
        NoteVersion::V2,
        NoteVersion::V3,
    ]));
    assert!(mixed.has_v2 && mixed.has_v3);

    // Sapling-only selection: no Orchard notes at all.
    let none = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[]));
    assert!(!none.has_v2 && !none.has_v3);
}

#[test]
fn v5_rerun_falls_back_to_v6_proposal_on_failure() {
    let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]);
    let pass1_fee = proposal_fee_zatoshi(&pass1);
    let rerun_calls = std::cell::Cell::new(0);

    let (proposal, tx_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |requested| {
            rerun_calls.set(rerun_calls.get() + 1);
            assert_eq!(requested, Some(TxVersion::V5));
            Err("simulated re-proposal failure".to_string())
        });

    // The failed downgrade keeps the pass-1 proposal under its V6 version.
    assert_eq!(rerun_calls.get(), 1);
    assert_eq!(tx_version, Some(TxVersion::V6));
    assert_eq!(proposal_fee_zatoshi(&proposal), pass1_fee);
}

#[test]
fn v5_rerun_returns_reproposed_v5_proposal_on_success() {
    use orchard::note::NoteVersion;

    let pass1 = fabricated_shielded_spend_proposal(&[NoteVersion::V2]);
    let rerun = fabricated_shielded_spend_proposal(&[NoteVersion::V2, NoteVersion::V2]);

    let (proposal, tx_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), move |_| Ok(rerun));

    assert_eq!(tx_version, Some(TxVersion::V5));
    // The returned proposal is the re-proposed one (two spends, not one).
    let selected: Vec<_> = proposal
        .steps()
        .iter()
        .flat_map(|step| step.shielded_inputs().into_iter())
        .flat_map(|inputs| inputs.notes().iter())
        .collect();
    assert_eq!(selected.len(), 2);
}

#[test]
fn v3_only_spends_keep_v6_without_rerun() {
    let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V3]);

    let (_, tx_version) = propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |_| {
        panic!("re-proposal must not run for a V3-only selection")
    });

    assert_eq!(tx_version, Some(TxVersion::V6));
}

// `estimate_send_max` deliberately quotes at the pass-1 V6 ceiling and does
// NOT apply the V2->V5 downgrade, so the quoted max is always realizable by
// `propose_send` (whose pass-1 is hard-gated at V6). A cheaper V5-priced max
// would over-quote for V2-only wallets and fail `propose_send` with
// InsufficientFunds. This test pins that policy: the same V2-only
// transparent-recipient max proposal that send-max builds *would* be
// downgraded by the shared decision, and the value send-max returns is the
// V6-ceiling summary, unchanged by any downgrade.
#[test]
fn estimate_send_max_stays_at_v6_ceiling_for_v2_only_spends() {
    // The pass-1 proposal send-max builds for a V2-only spend to a
    // transparent recipient.
    let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]);

    // The shared decision WOULD downgrade this (V6 ceiling, V2-only spends,
    // transparent recipient), confirming send-max is intentionally opting
    // out rather than the case being ineligible.
    assert!(should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &proposal_selected_orchard_note_versions(&pass1),
        proposal_has_orchard_payment(&pass1),
    ));

    // The value send-max returns is the V6-ceiling summary. Running the
    // shared downgrade helper here (as the removed code did) would have
    // produced a different, V5-priced result; send-max must return the
    // undowngraded V6 summary instead.
    let v6_summary = summarize_send_max_proposal(&pass1).unwrap();
    let (downgraded, downgraded_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |tx_version| {
            assert_eq!(tx_version, Some(TxVersion::V5));
            // Stand in for a cheaper V5 re-proposal so the two paths differ.
            Ok(fabricated_shielded_spend_proposal(&[
                orchard::note::NoteVersion::V2,
                orchard::note::NoteVersion::V2,
            ]))
        });
    // Sanity: the downgrade path really does diverge from what send-max
    // returns (different selection/amount), so the assertion below is
    // meaningful rather than vacuous.
    assert_eq!(downgraded_version, Some(TxVersion::V5));
    assert_ne!(
        summarize_send_max_proposal(&downgraded)
            .unwrap()
            .amount_zatoshi,
        v6_summary.amount_zatoshi,
    );
}

#[test]
fn keystone_transparent_shielding_pczt_targets_ironwood() {
    crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let network = WalletNetwork::Regtest;
    let mnemonic = crate::wallet::keys::generate_mnemonic();
    let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
    let (account_uuid, _) =
        crate::wallet::keys::init_db_and_create_account(db_path, network, &seed, Some(1), "shield")
            .unwrap();
    let account_id = parse_account_uuid(&account_uuid).unwrap();

    let mut db = open_wallet_db(db_path, network).unwrap();
    let tip = BlockHeight::from_u32(120);
    db.update_chain_tip(tip).unwrap();
    // Shielding now derives the target/anchor heights from scan progress
    // (shard-tree checkpoints) rather than the raw chain tip; checkpoint
    // the empty Orchard tree at the tip to stand in for a scan.
    {
        type CheckpointError = WalletError<
            (),
            commitment_tree::Error,
            (),
            <ConservativeZip317FeeRule as FeeRule>::Error,
            (),
            ReceivedNoteId,
        >;
        let result: Result<_, CheckpointError> =
            db.with_sapling_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
        assert!(result.unwrap(), "checkpointing the empty Sapling tree");
        let result: Result<_, CheckpointError> =
            db.with_orchard_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
        assert!(result.unwrap(), "checkpointing the empty Orchard tree");
        let result: Result<_, CheckpointError> =
            db.with_ironwood_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
        result.unwrap();
    }

    let ua_request = zcash_keys::keys::UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
    )
    .unwrap();
    // Use the account's existing default address (no allocation) so the test
    // setup doesn't trip the transparent gap limit on a fresh account.
    let ua = db
        .get_last_generated_address_matching(account_id, ua_request)
        .unwrap()
        .unwrap();
    let taddr = *ua.transparent().unwrap();
    let outpoint = OutPoint::new([42u8; 32], 0);
    let txout = TxOut::new(Zatoshis::const_from_u64(1_000_000), taddr.script().into());
    let utxo =
        WalletTransparentOutput::from_parts(outpoint, txout, Some(tip), None, None, None).unwrap();
    db.put_received_transparent_utxo(&utxo).unwrap();
    drop(db);

    let result = create_shield_transparent_pczt(db_path, network, &account_uuid).unwrap();
    let pczt = pczt::Pczt::parse(&result.pczt_bytes).unwrap();

    assert_eq!(
        *pczt.global().tx_version(),
        zcash_protocol::constants::V6_TX_VERSION
    );
    assert!(!pczt.ironwood().actions().is_empty());
    assert!(pczt.orchard().actions().is_empty());
    assert_eq!(result.needs_sapling_params, false);
    assert!(result.fee_zatoshi > 0);
    assert!(result.shielded_zatoshi > 0);
}

#[test]
fn split_broadcast_result_preserves_status_and_migrated_amount() {
    let result = migration_result_from_split_broadcast(
        CreatedBroadcastResult {
            txids: "abc123,def456".to_string(),
            status: CreatedBroadcastResult::PARTIAL_BROADCAST,
            broadcasted_count: 1,
            total_count: 2,
            message: Some("Only one transaction broadcast".to_string()),
        },
        7,
        20_000,
        180_000,
    );

    assert_eq!(result.txids, "abc123,def456");
    assert_eq!(result.status, CreatedBroadcastResult::PARTIAL_BROADCAST);
    assert_eq!(result.broadcasted_count, 1);
    assert_eq!(result.total_count, 7);
    assert_eq!(
        result.message.as_deref(),
        Some("Only one transaction broadcast")
    );
    assert_eq!(result.fee_zatoshi, 20_000);
    assert_eq!(result.migrated_zatoshi, 180_000);
}

#[test]
fn scheduled_storage_failure_after_acceptance_leaves_tx_scheduled() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let denomination_input_txid =
        "303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f";
    let selected_note_txid = "101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f";
    let pending_txid = "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f";
    let selected_note = migration_test_note(selected_note_txid);
    let plan = migration_test_plan();
    let run_id = migration::create_run_with_staged_denominations_and_signed_children(
        &db_path,
        MIGRATION_TEST_ACCOUNT,
        WalletNetwork::Test,
        &plan,
        &[selected_note.clone()],
        Vec::new(),
        vec![migration_test_stage(
            denomination_input_txid,
            selected_note_txid,
        )],
        None,
        migration::PreparationTimingPolicy::Immediate,
        MIGRATION_TEST_PASSWORD,
        MIGRATION_TEST_SALT,
    )
    .unwrap();
    migration::insert_pending_txs(
        &db_path,
        &run_id,
        vec![migration::PendingMigrationTxInsert {
            part_index: 0,
            txid_hex: pending_txid.to_string(),
            raw_tx: vec![5, 6, 7, 8],
            target_height: 100,
            anchor_boundary_height: None,
            expiry_height: 69_120,
            scheduled_height: 100,
            value_zatoshi: 100_000,
            fee_zatoshi: 10_000,
            selected_note: selected_note.clone(),
            metadata: migration::PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: MIGRATION_TEST_ACCOUNT.to_string(),
                selected_note,
            },
        }],
        MIGRATION_TEST_PASSWORD,
        MIGRATION_TEST_SALT,
    )
    .unwrap();
    let pending = migration::DuePendingMigrationTx {
        txid_hex: pending_txid.to_string(),
        raw_tx: vec![5, 6, 7, 8],
    };

    let result = record_accepted_scheduled_migration_tx(
        &db_path,
        WalletNetwork::Test,
        &run_id,
        &pending,
        1,
        100_000,
        |_db_path, _network, _raw_tx| Err("db busy".to_string()),
    )
    .unwrap()
    .unwrap();

    assert_eq!(result.txids, pending_txid);
    assert_eq!(result.status, migration::PHASE_BROADCAST_SCHEDULED);
    assert_eq!(result.broadcasted_count, 0);
    assert_eq!(result.total_count, 1);
    assert_eq!(result.fee_zatoshi, 10_000);
    assert_eq!(result.migrated_zatoshi, 100_000);
    let message = result.message.as_deref().unwrap();
    assert!(message.contains("accepted by lightwalletd"));
    assert!(message.contains("Vizor will retry"));
    assert_eq!(
        migration::scheduled_pending_count(&db_path, &run_id).unwrap(),
        1
    );
    assert_eq!(
        migration::pending_totals_for_run(&db_path, &run_id)
            .unwrap()
            .broadcasted_count,
        0
    );
    let active =
        migration::active_migration_run(&db_path, MIGRATION_TEST_ACCOUNT, WalletNetwork::Test)
            .unwrap()
            .unwrap();
    assert_eq!(active.phase, migration::PHASE_BROADCAST_SCHEDULED);
    assert_eq!(active.last_error.as_deref(), Some(message));

    let result = record_accepted_scheduled_migration_tx(
        &db_path,
        WalletNetwork::Test,
        &run_id,
        &pending,
        1,
        100_000,
        |_db_path, _network, _raw_tx| Ok(()),
    )
    .unwrap();

    assert!(result.is_none());
    assert_eq!(
        migration::scheduled_pending_count(&db_path, &run_id).unwrap(),
        0
    );
    assert_eq!(
        migration::pending_totals_for_run(&db_path, &run_id)
            .unwrap()
            .broadcasted_count,
        1
    );
    let active =
        migration::active_migration_run(&db_path, MIGRATION_TEST_ACCOUNT, WalletNetwork::Test)
            .unwrap()
            .unwrap();
    assert_eq!(
        active.phase,
        migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS
    );
    assert_eq!(active.last_error, None);
}

#[test]
fn migration_child_bundle_shape_and_fee_are_two_plus_one() {
    let orchard_actions = orchard::builder::BundleType::DEFAULT
        .num_actions(
            orchard::bundle::BundleVersion::orchard_v3().default_flags(),
            1,
            0,
        )
        .unwrap();
    let ironwood_actions = orchard::builder::BundleType::UNPADDED
        .num_actions(
            orchard::bundle::BundleVersion::ironwood_v3().default_flags(),
            0,
            1,
        )
        .unwrap();

    assert_eq!(orchard_actions, MIGRATION_ORCHARD_ACTION_COUNT);
    assert_eq!(ironwood_actions, MIGRATION_IRONWOOD_ACTION_COUNT);

    let fee = ConservativeZip317FeeRule
        .fee_required(
            &WalletNetwork::Regtest,
            BlockHeight::from_u32(120),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            orchard_actions,
            ironwood_actions,
        )
        .unwrap();
    assert_eq!(u64::from(fee), 15_000);
}

#[test]
fn conservative_zip317_fee_rule_clamps_known_transparent_inputs_to_p2pkh_size() {
    let network = WalletNetwork::Regtest;
    let height = BlockHeight::from_u32(1_000);
    let undersized_inputs = vec![
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
    ];
    let standard_inputs = vec![
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
    ];

    let conservative_fee = ConservativeZip317FeeRule
        .fee_required(
            &network,
            height,
            undersized_inputs.clone(),
            std::iter::empty::<usize>(),
            0,
            0,
            0,
            0,
        )
        .unwrap();
    let standard_p2pkh_fee = StandardFeeRule::Zip317
        .fee_required(
            &network,
            height,
            standard_inputs,
            std::iter::empty::<usize>(),
            0,
            0,
            0,
            0,
        )
        .unwrap();
    let standard_undersized_fee = StandardFeeRule::Zip317
        .fee_required(
            &network,
            height,
            undersized_inputs,
            std::iter::empty::<usize>(),
            0,
            0,
            0,
            0,
        )
        .unwrap();

    assert_eq!(conservative_fee, standard_p2pkh_fee);
    assert_eq!(u64::from(conservative_fee), 15_000);
    assert_eq!(u64::from(standard_undersized_fee), 10_000);
}

/// Builds a real IO-finalized v6 Orchard split PCZT, shared by the version and
/// signer-redaction tests below. Every action's spend is wallet-controlled (the
/// real spend plus the fabricated zero-value spend paired with the change
/// output), so all of them carry the wallet `fvk` on the wire and are signable
/// with the returned spending key.
fn built_v6_split_pczt() -> (BuiltPczt, orchard::keys::SpendingKey) {
    crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
    let network = WalletNetwork::Regtest;
    let target_height = 120;
    let sk = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
    let fvk = orchard::keys::FullViewingKey::from(&sk);
    let recipient_scope = orchard::keys::Scope::Internal;
    let recipient = fvk.address_at(0u32, recipient_scope);
    let internal_ovk = Some(fvk.to_ovk(recipient_scope));
    let memo = MemoBytes::empty();
    let output_value = 100_000;
    let fee_rule = ConservativeZip317FeeRule;

    let build_builder = |input_value| {
        let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
        let rseed = (0u8..=255)
            .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
            .expect("test rseed");
        let note = orchard::Note::from_parts(
            recipient,
            orchard::value::NoteValue::from_raw(input_value),
            rho,
            rseed,
            orchard::note::NoteVersion::V2,
        )
        .unwrap();
        let merkle_path = dummy_orchard_merkle_path().unwrap();
        let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
        let orchard_anchor = merkle_path.root(cmx);

        make_orchard_split_builder_with_type(
            network,
            target_height,
            orchard_anchor,
            &[(note, merkle_path)],
            &fvk,
            internal_ovk.clone(),
            recipient,
            &[output_value],
            &memo,
            orchard::builder::BundleType::DEFAULT,
        )
    };

    let fee = build_builder(1_000_000)
        .unwrap()
        .get_fee(&fee_rule)
        .unwrap();
    let builder = build_builder(output_value + u64::from(fee)).unwrap();
    let build_result = builder.build_for_pczt(rand_core::OsRng, &fee_rule).unwrap();

    assert_eq!(build_result.pczt_parts.version, TxVersion::V6);
    let built_pczt = pczt_from_build_result(build_result, network, None, 1, 1).unwrap();
    (built_pczt, sk)
}

#[test]
fn orchard_denomination_split_pczt_uses_v6_for_change_outputs() {
    let (built_pczt, _sk) = built_v6_split_pczt();
    crate::wallet::sync::pczt::redact_pczt_for_signer(&built_pczt.bytes).unwrap();
}

#[test]
fn padded_denomination_split_builds_exactly_sixteen_actions() {
    crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
    let network = WalletNetwork::Regtest;
    let target_height = 120;
    let usk = UnifiedSpendingKey::from_seed(&network, &[9; 32], zip32::AccountId::ZERO).unwrap();
    let fvk = orchard::keys::FullViewingKey::from(usk.orchard());
    let recipient_scope = orchard::keys::Scope::Internal;
    let recipient = fvk.address_at(0u32, recipient_scope);
    let internal_ovk = Some(fvk.to_ovk(recipient_scope));
    let memo = MemoBytes::empty();
    let outputs = vec![100_000u64; 10];
    let fee_rule = ConservativeZip317FeeRule;
    let bundle_type = orchard::builder::BundleType::Transactional {
        bundle_required: false,
        pad_to_minimum: Some(16),
    };

    let build_builder = |input_value| {
        let rho = orchard::note::Rho::from_bytes(&[2; 32]).unwrap();
        let rseed = (0u8..=255)
            .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
            .expect("test rseed");
        let note = orchard::Note::from_parts(
            recipient,
            orchard::value::NoteValue::from_raw(input_value),
            rho,
            rseed,
            orchard::note::NoteVersion::V2,
        )
        .unwrap();
        let merkle_path = dummy_orchard_merkle_path().unwrap();
        let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
        let anchor = merkle_path.root(cmx);
        make_orchard_split_builder_with_type(
            network,
            target_height,
            anchor,
            &[(note, merkle_path)],
            &fvk,
            internal_ovk.clone(),
            recipient,
            &outputs,
            &memo,
            bundle_type,
        )
    };

    let fee = build_builder(2_000_000)
        .unwrap()
        .get_fee(&fee_rule)
        .unwrap();
    assert_eq!(u64::from(fee), 80_000);
    let input_value = outputs.iter().sum::<u64>() + u64::from(fee);
    let build_result = build_builder(input_value)
        .unwrap()
        .build_for_pczt(rand_core::OsRng, &fee_rule)
        .unwrap();
    assert_eq!(
        build_result
            .pczt_parts
            .orchard
            .as_ref()
            .unwrap()
            .actions()
            .len(),
        16
    );
    let built = pczt_from_build_result(build_result, network, None, 1, outputs.len()).unwrap();
    assert_eq!(
        pczt::Pczt::parse(&built.bytes)
            .unwrap()
            .orchard()
            .actions()
            .len(),
        16
    );
    assert_eq!(built.orchard_spend_action_indices.len(), 11);

    let signed = sign_orchard_migration_pczt_with_usk(
        &built.bytes,
        &built.orchard_spend_action_indices,
        &usk,
    )
    .unwrap();
    let sigs = crate::wallet::sync::pczt::extract_required_compact_sigs_from_signed_pczt(
        &built.bytes,
        &signed,
    )
    .unwrap();
    assert_eq!(sigs.len(), 11);
    crate::wallet::sync::pczt::preflight_orchard_spend_auth_signatures(&built.bytes, &sigs)
        .unwrap();
}

#[test]
fn transparent_recipient_send_max_proposal_spends_shielded_notes() {
    let network = WalletNetwork::Regtest;
    let input_value = 60_000u64;
    let spending_key = sapling_crypto::zip32::ExtendedSpendingKey::master(&[7u8; 32]);
    let (_, recipient) = spending_key.default_address();
    let note = sapling_crypto::Note::from_parts(
        recipient,
        sapling_crypto::value::NoteValue::from_raw(input_value),
        sapling_crypto::Rseed::AfterZip212([3u8; 32]),
    );
    let received_note = ReceivedNote::from_parts(
        1u32,
        TxId::from_bytes([4u8; 32]),
        0,
        note,
        zip32::Scope::External,
        Position::from(0u64),
        Some(BlockHeight::from_u32(20)),
        None,
    );
    let recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

    let proposal = build_transparent_recipient_send_max_proposal_from_notes(
        network,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        BlockHeight::from_u32(900),
        recipient,
        None,
        ReceivedNotes::new(vec![received_note], vec![], vec![]),
        ConservativeZip317FeeRule,
    )
    .expect("transparent-recipient send-max should build from shielded notes");

    let step = proposal.steps().iter().next().unwrap();
    assert_eq!(step.payment_pools().get(&0), Some(&PoolType::TRANSPARENT));
    assert_eq!(step.transparent_inputs().len(), 0);
    assert_eq!(step.shielded_inputs().unwrap().notes().len(), 1);

    let estimate = summarize_send_max_proposal(&proposal).unwrap();
    assert_eq!(estimate.amount_zatoshi + estimate.fee_zatoshi, input_value);
    assert!(estimate.fee_zatoshi > 0);
    assert!(estimate.needs_sapling_params);
}

#[test]
fn transparent_recipient_send_max_supports_ironwood_only_inputs() {
    let network = WalletNetwork::Regtest;
    let input_value = 100_000u64;
    let spending_key = orchard::keys::SpendingKey::from_bytes([17; 32]).unwrap();
    let fvk = orchard::keys::FullViewingKey::from(&spending_key);
    let recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
    let rho = orchard::note::Rho::from_bytes(&[3; 32]).unwrap();
    let rseed = (0u8..=255)
        .find_map(|byte| orchard::note::RandomSeed::from_bytes([byte; 32], &rho).into_option())
        .unwrap();
    let note = orchard::Note::from_parts(
        recipient,
        orchard::value::NoteValue::from_raw(input_value),
        rho,
        rseed,
        orchard::note::NoteVersion::V3,
    )
    .unwrap();
    let received_note = ReceivedNote::from_parts(
        1u32,
        TxId::from_bytes([5u8; 32]),
        0,
        note,
        zip32::Scope::External,
        Position::from(0u64),
        Some(BlockHeight::from_u32(20)),
        None,
    );
    let transparent_recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

    let proposal = build_transparent_recipient_send_max_proposal_from_notes(
        network,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        BlockHeight::from_u32(900),
        transparent_recipient,
        None,
        ReceivedNotes::new(vec![], vec![], vec![received_note]),
        ConservativeZip317FeeRule,
    )
    .expect("transparent-recipient send-max should build from Ironwood notes");

    let step = proposal.steps().iter().next().unwrap();
    assert_eq!(step.payment_pools().get(&0), Some(&PoolType::TRANSPARENT));
    assert_eq!(step.shielded_inputs().unwrap().notes().len(), 1);
    let estimate = summarize_send_max_proposal(&proposal).unwrap();
    assert_eq!(estimate.amount_zatoshi + estimate.fee_zatoshi, input_value);
    assert!(!estimate.needs_sapling_params);
}

#[test]
fn batch_signer_redaction_compacts_and_preserves_signable_spends() {
    use pczt::roles::redactor::Redactor;
    use pczt::roles::signer::Signer;

    let (built_pczt, _) = built_v6_split_pczt();
    let request_bytes = built_pczt.bytes.clone();
    let request = pczt::Pczt::parse(&request_bytes).unwrap();
    let mut has_unsigned_zero_value_spend = false;
    pczt::roles::verifier::Verifier::new(request.clone())
        .with_orchard::<Infallible, _>(|bundle| {
            has_unsigned_zero_value_spend = bundle.actions().iter().any(|action| {
                action
                    .spend()
                    .value()
                    .as_ref()
                    .is_some_and(|value| value.inner() == 0)
                    && action.spend().spend_auth_sig().is_none()
            });
            Ok(())
        })
        .unwrap();
    assert!(has_unsigned_zero_value_spend);

    let standard = crate::wallet::sync::pczt::redact_pczt_for_signer(&request_bytes).unwrap();
    let batch = crate::wallet::sync::pczt::redact_pczt_for_batch_signer(&request_bytes).unwrap();
    assert_eq!(batch, built_pczt.redacted_bytes);

    let batch_parsed = pczt::Pczt::parse(&batch).unwrap();
    for index in 0..batch_parsed.orchard().actions().len() {
        let without_alpha = Redactor::new(batch_parsed.clone())
            .redact_orchard_with(|mut r| {
                r.redact_action(index, |mut ar| ar.clear_spend_alpha());
            })
            .finish()
            .serialize()
            .unwrap();
        assert_ne!(
            without_alpha, batch,
            "every wallet-controlled split spend must retain alpha",
        );
    }

    // The batch redaction additionally applies the compact-format elisions
    // (cv_net, decryptable ciphertexts as memo plaintext, bundle bsk and
    // anchor), so it must be meaningfully smaller than the standard signer
    // redaction.
    assert!(
        batch.len() + 1_000 < standard.len(),
        "batch redaction should elide compact-format fields ({} vs {} bytes)",
        batch.len(),
        standard.len(),
    );
    // The v6 sighash does not commit to anchors.
    assert!(batch_parsed.orchard().anchor().is_none());
    // Every action sheds `cv_net`. A ciphertext rides as stripped memo
    // plaintext whenever the wire note fields can decrypt it; only a
    // dummy output's randomized ciphertext may fail that swap and stay
    // encrypted on the wire.
    for action in batch_parsed.orchard().actions() {
        assert!(action.cv_net().is_none());
        assert!(action.output().cmx().is_none());
        if matches!(
            action.output().enc_ciphertext(),
            pczt::orchard::EncCiphertext::Encrypted(_)
        ) {
            assert_eq!(*action.output().value(), Some(0));
        }
    }
    assert!(
        batch_parsed.orchard().actions().iter().any(|action| {
            matches!(
                action.output().enc_ciphertext(),
                pczt::orchard::EncCiphertext::MemoPlaintext(_)
            )
        }),
        "at least the real split output's ciphertext must ride as memo plaintext",
    );

    // The compact-format contract: resolving the elided fields reproduces
    // the original values byte-identically.
    let mut refilled = batch_parsed;
    refilled.resolve_fields().unwrap();
    for (reb, orig) in refilled
        .orchard()
        .actions()
        .iter()
        .zip(request.orchard().actions().iter())
    {
        assert_eq!(reb.cv_net(), orig.cv_net());
        assert_eq!(reb.output().cmx(), orig.output().cmx());
        assert_eq!(
            reb.output().enc_ciphertext(),
            orig.output().enc_ciphertext()
        );
    }
    assert_eq!(
        Signer::new(refilled).unwrap().shielded_sighash(),
        Signer::new(request).unwrap().shielded_sighash(),
    );

    // Guard that the fvk clear is not vacuous: re-clearing the fvk on the batch
    // redaction changes nothing (it was already cleared), while the standard
    // redaction still carries the wire fvks.
    let clear_fvks = |bytes: &[u8]| {
        let parsed = pczt::Pczt::parse(bytes).unwrap();
        Redactor::new(parsed)
            .redact_orchard_with(|mut r| {
                r.redact_actions(|mut ar| {
                    ar.clear_spend_fvk();
                });
            })
            .redact_ironwood_with(|mut r| {
                r.redact_actions(|mut ar| {
                    ar.clear_spend_fvk();
                });
            })
            .finish()
            .serialize()
            .unwrap()
    };
    assert_eq!(
        clear_fvks(&batch),
        batch,
        "batch redaction must already have cleared the wire spend fvks",
    );
    assert_ne!(
        clear_fvks(&standard),
        standard,
        "standard redaction must retain the wire spend fvks",
    );
}

#[test]
#[ignore = "slow librustzcash transaction-construction regression (~100s); run explicitly when touching shielding transaction construction"]
fn many_utxo_shielding_builds_with_conservative_zip317_fee() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let network = WalletNetwork::Regtest;
    let mnemonic = crate::wallet::keys::generate_mnemonic();
    let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
    let (account_uuid, _) =
        crate::wallet::keys::init_db_and_create_account(db_path, network, &seed, Some(1), "repro")
            .unwrap();
    let account_id = parse_account_uuid(&account_uuid).unwrap();

    let mut db = open_wallet_db(db_path, network).unwrap();
    let tip = BlockHeight::from_u32(1_000);
    db.update_chain_tip(tip).unwrap();

    let ua_request = zcash_keys::keys::UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
    )
    .unwrap();
    // Use the account's existing default address (no allocation) so the test
    // setup doesn't trip the transparent gap limit on a fresh account.
    let ua = db
        .get_last_generated_address_matching(account_id, ua_request)
        .unwrap()
        .unwrap();
    let taddr = *ua.transparent().unwrap();
    let value = Zatoshis::const_from_u64(1_000_000);

    for i in 0..322u32 {
        let mut txid = [0u8; 32];
        txid[..4].copy_from_slice(&i.to_le_bytes());
        txid[4..8].copy_from_slice(&0xfeed_beefu32.to_le_bytes());
        let outpoint = OutPoint::new(txid, 0);
        let txout = TxOut::new(value, taddr.script().into());
        let utxo =
            WalletTransparentOutput::from_parts(outpoint, txout, Some(tip), None, None, None)
                .unwrap();
        db.put_received_transparent_utxo(&utxo).unwrap();
    }

    let shielding_threshold = Zatoshis::const_from_u64(SHIELDING_THRESHOLD_ZATOSHI);
    let (proposal, selected_value) =
        build_shielding_proposal(&mut db, network, account_id, shielding_threshold).unwrap();
    assert_eq!(u64::from(selected_value), 322_000_000);

    let seed = SecretVec::new(seed.expose_secret().to_vec());
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32::AccountId::ZERO)
        .unwrap();
    let spend_prover = NoOpSpendProver;
    let output_prover = NoOpOutputProver;
    let txids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
        &mut db,
        &network,
        &spend_prover,
        &output_prover,
        &wallet::SpendingKeys::from_unified_spending_key(usk),
        OvkPolicy::Sender,
        &proposal,
    )
    .expect("many-UTXO shielding should build without a fee/change mismatch");
    let change_values = proposal
        .steps()
        .iter()
        .flat_map(|step| step.balance().proposed_change().iter())
        .map(|change| u64::from(change.value()).to_string())
        .collect::<Vec<_>>()
        .join(",");
    eprintln!(
            "repro fixed: utxos=322 selected={} proposal_fee={} proposed_shielded={} change_values=[{}] txids={:?}",
            u64::from(selected_value),
            proposal_fee_zatoshi(&proposal),
            proposal_shielded_zatoshi(&proposal),
            change_values,
            txids,
        );

    assert_eq!(txids.len(), 1);
    assert_eq!(proposal_fee_zatoshi(&proposal), 1_630_000);
    assert_eq!(proposal_shielded_zatoshi(&proposal), 320_370_000);
}

#[test]
fn selects_fragmented_non_ephemeral_sources_by_aggregate_threshold() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(60_000, TransparentKeyScope::EXTERNAL));
    receivers.insert(taddr(2), receiver(50_000, TransparentKeyScope::INTERNAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

    assert_eq!(addresses.len(), 2);
    assert_eq!(u64::from(total), 110_000);
}

#[test]
fn rejects_non_ephemeral_sources_below_aggregate_threshold() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(40_000, TransparentKeyScope::EXTERNAL));
    receivers.insert(taddr(2), receiver(50_000, TransparentKeyScope::INTERNAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let err = select_shielding_sources(receivers, threshold).unwrap_err();

    assert!(err.contains("No transparent funds available"));
}

#[test]
fn selects_largest_ephemeral_source_only() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(110_000, TransparentKeyScope::EPHEMERAL));
    receivers.insert(taddr(2), receiver(150_000, TransparentKeyScope::EPHEMERAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

    assert_eq!(addresses, vec![taddr(2)]);
    assert_eq!(u64::from(total), 150_000);
}

#[test]
fn prefers_non_ephemeral_sources_over_ephemeral_sources() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(140_000, TransparentKeyScope::EPHEMERAL));
    receivers.insert(taddr(2), receiver(120_000, TransparentKeyScope::EXTERNAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

    assert_eq!(addresses, vec![taddr(2)]);
    assert_eq!(u64::from(total), 120_000);
}
