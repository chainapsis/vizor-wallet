#![cfg(feature = "test-fixtures")]

use zcash_voting::{
    phases::VotePhase,
    round::{RoundParams, VotingDb},
    share,
    storage::RoundPhase,
    types::{EncryptedShare, Network, NoteInfo},
    vote::{
        insert_recovery_fixture, record_submission, record_vc_position, recover_commit,
        recovery_bundle, serialize_recovery, VoteRecoveryBundle,
    },
    BALLOT_DIVISOR,
};

const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
const WALLET_ID: &str = "downstream-fixture-wallet";

fn round_params(round_id: &str) -> RoundParams {
    RoundParams {
        vote_round_id: round_id.to_string(),
        snapshot_height: 1_000,
        ea_pk: vec![0xEA; 32],
        nc_root: vec![0xAA; 32],
        nullifier_imt_root: vec![0xBB; 32],
    }
}

fn note() -> NoteInfo {
    NoteInfo {
        commitment: vec![0x01; 32],
        nullifier: vec![0x02; 32],
        value: BALLOT_DIVISOR,
        position: 7,
        diversifier: vec![0x03; 11],
        rho: vec![0x04; 32],
        rseed: vec![0x05; 32],
        scope: 0,
        ufvk_str: "uview1fixture".to_string(),
    }
}

fn recovery_fixture() -> VoteRecoveryBundle {
    VoteRecoveryBundle {
        vote_round_id: ROUND_ID.to_string(),
        bundle_index: 0,
        proposal_id: 1,
        vote_decision: 1,
        anchor_height: 123,
        vc_tree_position: 456,
        single_share: false,
        num_options: 3,
        van_nullifier: [0x10; 32],
        vote_authority_note_new: [0x11; 32],
        vote_commitment: [0x12; 32],
        proof: vec![0x13; 96],
        shares_hash: [0x14; 32],
        r_vpk: [0x15; 32],
        alpha_v: [0x16; 32],
        vote_auth_sig: [0x17; 64],
        encrypted_shares: vec![EncryptedShare {
            c1: vec![0x21; 32],
            c2: vec![0x22; 32],
            share_index: 0,
            plaintext_value: 1,
            randomness: vec![0x23; 32],
        }],
        share_blinds: vec![[0x31; 32]],
        share_comms: vec![[0x41; 32]],
        batch: None,
    }
}

fn db_with_bundle() -> VotingDb {
    let db = VotingDb::open_in_memory().unwrap();
    db.set_wallet_id(WALLET_ID);
    db.create_round(Network::Testnet, &round_params(ROUND_ID), None)
        .unwrap();
    db.ensure_bundles(ROUND_ID, &[note()]).unwrap();
    db
}

fn stored_confirmation_fields(db: &VotingDb) -> (Option<String>, Option<i64>) {
    db.conn()
        .query_row(
            "SELECT tx_hash, vc_tree_position FROM votes
             WHERE round_id = ?1 AND wallet_id = ?2
               AND bundle_index = 0 AND proposal_id = 1",
            (ROUND_ID, WALLET_ID),
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
}

#[test]
fn downstream_fixture_seeds_committed_state_and_uses_public_lifecycle() {
    let db = db_with_bundle();
    let fixture = recovery_fixture();

    insert_recovery_fixture(&db, &fixture).unwrap();
    insert_recovery_fixture(&db, &fixture).unwrap();

    assert_eq!(db.get_votes(ROUND_ID).unwrap().len(), 1);
    assert_eq!(
        db.get_round_state(ROUND_ID).unwrap().phase,
        RoundPhase::VoteReady
    );
    assert_eq!(db.vote_phase(ROUND_ID, 0, 1).unwrap(), VotePhase::Committed);
    assert_eq!(stored_confirmation_fields(&db), (None, None));

    let stored = recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().unwrap();
    assert_eq!(
        serialize_recovery(&stored).unwrap(),
        serialize_recovery(&fixture).unwrap()
    );
    assert_eq!(
        recover_commit(&db, ROUND_ID, 0, 1)
            .unwrap()
            .share_payloads
            .len(),
        1
    );

    record_submission(&db, ROUND_ID, 0, 1, "vote-tx").unwrap();
    assert_eq!(db.vote_phase(ROUND_ID, 0, 1).unwrap(), VotePhase::Submitted);

    record_vc_position(&db, ROUND_ID, 0, 1, 789).unwrap();
    assert_eq!(db.vote_phase(ROUND_ID, 0, 1).unwrap(), VotePhase::Confirmed);
    assert_eq!(
        stored_confirmation_fields(&db),
        (Some("vote-tx".to_string()), Some(789))
    );
    assert_eq!(
        recovery_bundle(&db, ROUND_ID, 0, 1)
            .unwrap()
            .unwrap()
            .vc_tree_position,
        789
    );
}

#[test]
fn downstream_fixture_rejects_invalid_or_missing_setup_without_a_vote() {
    let db = db_with_bundle();

    let mut malformed = recovery_fixture();
    malformed.vote_round_id = "not-a-round-id".to_string();
    assert!(insert_recovery_fixture(&db, &malformed).is_err());

    let mut missing_round = recovery_fixture();
    missing_round.vote_round_id =
        "0202020202020202020202020202020202020202020202020202020202020202".to_string();
    assert!(insert_recovery_fixture(&db, &missing_round).is_err());

    let mut missing_bundle = recovery_fixture();
    missing_bundle.bundle_index = 1;
    assert!(insert_recovery_fixture(&db, &missing_bundle).is_err());

    assert!(db.get_votes(ROUND_ID).unwrap().is_empty());
    assert_eq!(
        db.get_round_state(ROUND_ID).unwrap().phase,
        RoundPhase::Initialized
    );
}

#[test]
fn downstream_fixture_does_not_repair_a_submitted_vote() {
    let db = db_with_bundle();
    let fixture = recovery_fixture();
    insert_recovery_fixture(&db, &fixture).unwrap();
    record_submission(&db, ROUND_ID, 0, 1, "vote-tx").unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = NULL
             WHERE round_id = ?1 AND wallet_id = ?2
               AND bundle_index = 0 AND proposal_id = 1",
            (ROUND_ID, WALLET_ID),
        )
        .unwrap();

    let err = insert_recovery_fixture(&db, &fixture).unwrap_err();

    assert!(
        err.to_string().contains("cannot replace submitted vote"),
        "{err}"
    );
    assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    assert_eq!(
        stored_confirmation_fields(&db).0.as_deref(),
        Some("vote-tx")
    );
}

#[test]
fn downstream_fixture_does_not_reset_a_recorded_position() {
    let db = db_with_bundle();
    let fixture = recovery_fixture();
    insert_recovery_fixture(&db, &fixture).unwrap();
    record_vc_position(&db, ROUND_ID, 0, 1, 789).unwrap();

    let err = insert_recovery_fixture(&db, &fixture).unwrap_err();

    assert!(
        err.to_string().contains("cannot replace confirmed vote"),
        "{err}"
    );
    assert_eq!(stored_confirmation_fields(&db), (None, Some(789)));
    assert_eq!(
        recovery_bundle(&db, ROUND_ID, 0, 1)
            .unwrap()
            .unwrap()
            .vc_tree_position,
        789
    );
}

#[test]
fn downstream_fixture_replacement_clears_stale_share_tracking() {
    let db = db_with_bundle();
    let mut fixture = recovery_fixture();
    fixture.share_blinds[0] = [0x01; 32];
    insert_recovery_fixture(&db, &fixture).unwrap();
    share::record(
        &db,
        ROUND_ID,
        0,
        1,
        0,
        &["https://helper.example".to_string()],
        99,
    )
    .unwrap();
    share::confirm(&db, ROUND_ID, 0, 1, 0).unwrap();

    insert_recovery_fixture(&db, &fixture).unwrap();
    let tracked = share::list(&db, ROUND_ID).unwrap();
    assert_eq!(tracked.len(), 1);
    assert!(tracked[0].confirmed);

    let mut replacement = fixture.clone();
    replacement.share_blinds[0] = [0x02; 32];
    insert_recovery_fixture(&db, &replacement).unwrap();

    assert!(share::list(&db, ROUND_ID).unwrap().is_empty());
    assert_eq!(
        recovery_bundle(&db, ROUND_ID, 0, 1)
            .unwrap()
            .unwrap()
            .share_blinds,
        replacement.share_blinds
    );
}

#[test]
fn downstream_fixture_rolls_back_when_recovery_storage_fails() {
    let db = db_with_bundle();
    db.conn()
        .execute_batch(
            "CREATE TRIGGER reject_fixture_recovery
             BEFORE UPDATE OF commitment_bundle_json ON votes
             WHEN NEW.commitment_bundle_json IS NOT NULL
             BEGIN
                 SELECT RAISE(ABORT, 'fixture recovery rejected');
             END;",
        )
        .unwrap();

    let err = insert_recovery_fixture(&db, &recovery_fixture()).unwrap_err();

    assert!(
        err.to_string()
            .contains("failed to store vote recovery bundle"),
        "{err}"
    );
    assert!(db.get_votes(ROUND_ID).unwrap().is_empty());
    assert_eq!(
        db.get_round_state(ROUND_ID).unwrap().phase,
        RoundPhase::Initialized
    );
}
