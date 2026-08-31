use zcash_voting::{
    backend::pasta_curves::{
        group::{ff::PrimeField, Group, GroupEncoding},
        pallas,
    },
    round::{RoundParams, VotingDb},
    types::{EncryptedShare, Network, NoteInfo},
    vote::{insert_recovery_fixture, record_vc_position, CommittedVote, VoteRecoveryBundle},
    BALLOT_DIVISOR,
};

pub const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
pub const WALLET_ID: &str = "adversarial-helper-wallet";
pub const BUNDLE_INDEX: u32 = 0;
pub const PROPOSAL_ID: u32 = 1;
pub const SHARE_COUNT: usize = 16;
pub const VC_TREE_POSITION: u64 = 789;

pub fn db_with_confirmed_committed_vote() -> VotingDb {
    db_with_confirmed_recovery(recovery_fixture())
}

fn db_with_confirmed_recovery(recovery: VoteRecoveryBundle) -> VotingDb {
    let db = VotingDb::open_in_memory().unwrap();
    db.set_wallet_id(WALLET_ID);
    db.create_round(
        Network::Testnet,
        &RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 1_000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        },
        None,
    )
    .unwrap();
    db.ensure_bundles(ROUND_ID, &[note()]).unwrap();
    // Keep this adversarial fixture's committed vote delayed: a higher eligible
    // bundle owns the round-immediate designation even though it is not yet
    // committed in these transport-focused tests.
    db.conn()
        .execute(
            "INSERT INTO bundles (round_id, wallet_id, bundle_index)
             VALUES (?1, ?2, 1)",
            rusqlite::params![ROUND_ID, WALLET_ID],
        )
        .unwrap();
    db.set_ballot_intent(
        ROUND_ID,
        PROPOSAL_ID,
        zcash_voting::session::Decision::Choice(recovery.vote_decision),
        recovery.num_options,
    )
    .unwrap();
    insert_recovery_fixture(&db, &recovery).unwrap();
    record_vc_position(&db, ROUND_ID, BUNDLE_INDEX, PROPOSAL_ID, VC_TREE_POSITION).unwrap();
    db
}

pub fn committed_vote(db: &VotingDb) -> CommittedVote {
    CommittedVote::recover(db, ROUND_ID, BUNDLE_INDEX, PROPOSAL_ID).unwrap()
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
        ufvk_str: "uview1adversarial".to_string(),
    }
}

fn recovery_fixture() -> VoteRecoveryBundle {
    VoteRecoveryBundle {
        vote_round_id: ROUND_ID.to_string(),
        bundle_index: BUNDLE_INDEX,
        proposal_id: PROPOSAL_ID,
        vote_decision: 1,
        anchor_height: 123,
        vc_tree_position: 456,
        single_share: false,
        num_options: 3,
        van_nullifier: [0x10; 32],
        vote_authority_note_new: [0x11; 32],
        vote_commitment: [0x12; 32],
        proof: vec![0x13; 96],
        shares_hash: field_bytes(99),
        r_vpk: [0x15; 32],
        alpha_v: [0x16; 32],
        vote_auth_sig: [0x17; 64],
        encrypted_shares: (0..SHARE_COUNT)
            .map(|index| EncryptedShare {
                c1: point_bytes(index as u64 + 1),
                c2: point_bytes(index as u64 + 101),
                share_index: index as u32,
                plaintext_value: index as u64 + 1,
                randomness: vec![index as u8 + 1; 32],
            })
            .collect(),
        share_blinds: (0..SHARE_COUNT)
            .map(|index| field_bytes(index as u64 + 1))
            .collect(),
        share_comms: (0..SHARE_COUNT)
            .map(|index| field_bytes(index as u64 + 201))
            .collect(),
        batch: None,
    }
}

fn point_bytes(multiplier: u64) -> Vec<u8> {
    (pallas::Point::generator() * pallas::Scalar::from(multiplier))
        .to_bytes()
        .to_vec()
}

fn field_bytes(value: u64) -> [u8; 32] {
    pallas::Base::from(value).to_repr()
}
