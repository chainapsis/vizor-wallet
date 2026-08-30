use super::*;

fn share_record(confirmed: bool, submit_at: u64) -> ShareDelegationRecord {
    ShareDelegationRecord {
        round_id: field_hex(1),
        bundle_index: 0,
        proposal_id: 1,
        share_index: 0,
        sent_to_urls: Vec::new(),
        ambiguous_urls: Vec::new(),
        attempting_urls: Vec::new(),
        target_count: 0,
        nullifier: vec![0u8; 32],
        confirmed,
        submit_at,
        created_at: submit_at,
    }
}

// ---- Mock transport -------------------------------------------------

use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

use crate::backend::pasta_curves::{
    group::{ff::PrimeField, Group, GroupEncoding},
    pallas,
};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};

use crate::helper::{
    client::{HelperClient, HelperClientConfig},
    health::{HelperHealth, HELPER_FAILURE_THRESHOLD},
    transport::{HelperFuture, HelperResponse, HelperTransport, HelperTransportError},
    url::canonical_helper_url_list,
};
use crate::wire::VoteShareWire;

fn point_bytes(multiplier: u64) -> Vec<u8> {
    (pallas::Point::generator() * pallas::Scalar::from(multiplier))
        .to_bytes()
        .to_vec()
}

fn field_hex(value: u64) -> String {
    hex::encode(pallas::Base::from(value).to_repr())
}

fn valid_share_json() -> &'static str {
    static JSON: LazyLock<String> = LazyLock::new(|| {
        VoteShareWire {
            vote_round_id: "01".repeat(32),
            shares_hash: BASE64_STANDARD.encode(pallas::Base::from(1).to_repr()),
            proposal_id: 1,
            vote_decision: 0,
            encrypted_share: crate::WireEncryptedShare {
                c1: point_bytes(2),
                c2: point_bytes(3),
                share_index: 0,
            },
            share_index: 0,
            vc_tree_position: 1,
            share_comms: (0..crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT)
                .map(|index| {
                    BASE64_STANDARD.encode(pallas::Base::from(index as u64 + 10).to_repr())
                })
                .collect(),
            primary_blind: BASE64_STANDARD.encode(pallas::Base::from(4).to_repr()),
            submit_at: 0,
        }
        .to_json()
        .unwrap()
    });
    JSON.as_str()
}

type Reply = Result<HelperResponse, HelperTransportError>;

/// Canned per-URL responses plus a call log.
///
/// Missing canned responses fail rather than defaulting, so a test that
/// contacts an unexpected helper fails loudly instead of passing silently.
#[derive(Default)]
struct MockTransport {
    gets: Mutex<HashMap<String, VecDeque<Reply>>>,
    posts: Mutex<HashMap<String, VecDeque<Reply>>>,
    calls: Mutex<Vec<String>>,
    timeouts: Mutex<Vec<(String, Duration)>>,
    post_bodies: Mutex<Vec<(String, Vec<u8>)>>,
    get_delays: Mutex<HashMap<String, VecDeque<Duration>>>,
    post_delays: Mutex<HashMap<String, VecDeque<Duration>>>,
    get_observer: Mutex<Option<Arc<dyn Fn(&str) + Send + Sync>>>,
    post_observer: Mutex<Option<Arc<dyn Fn(&str) + Send + Sync>>>,
}

impl MockTransport {
    fn queue_get(&self, url: &str, reply: Reply) {
        self.gets
            .lock()
            .unwrap()
            .entry(url.to_string())
            .or_default()
            .push_back(reply);
    }

    fn queue_get_after(&self, url: &str, delay: Duration, reply: Reply) {
        self.queue_get(url, reply);
        self.get_delays
            .lock()
            .unwrap()
            .entry(url.to_string())
            .or_default()
            .push_back(delay);
    }

    fn queue_post(&self, url: &str, reply: Reply) {
        self.posts
            .lock()
            .unwrap()
            .entry(url.to_string())
            .or_default()
            .push_back(reply);
    }

    fn queue_post_after(&self, url: &str, delay: Duration, reply: Reply) {
        self.queue_post(url, reply);
        self.post_delays
            .lock()
            .unwrap()
            .entry(url.to_string())
            .or_default()
            .push_back(delay);
    }

    fn observe_posts(&self, observer: impl Fn(&str) + Send + Sync + 'static) {
        *self.post_observer.lock().unwrap() = Some(Arc::new(observer));
    }

    fn observe_gets(&self, observer: impl Fn(&str) + Send + Sync + 'static) {
        *self.get_observer.lock().unwrap() = Some(Arc::new(observer));
    }

    fn calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }

    fn call_count(&self, needle: &str) -> usize {
        self.calls()
            .iter()
            .filter(|call| call.contains(needle))
            .count()
    }

    fn posted_submit_at(&self, url: &str) -> u64 {
        self.posted_json(url)["submit_at"].as_u64().unwrap()
    }

    fn posted_json(&self, url: &str) -> serde_json::Value {
        let bodies = self.post_bodies.lock().unwrap();
        let (_, body) = bodies
            .iter()
            .find(|(posted_url, _)| posted_url == url)
            .unwrap_or_else(|| panic!("no POST body recorded for {url}"));
        serde_json::from_slice(body).unwrap()
    }

    fn timeout_for(&self, url: &str) -> Duration {
        self.timeouts
            .lock()
            .unwrap()
            .iter()
            .find(|(requested_url, _)| requested_url == url)
            .map(|(_, timeout)| *timeout)
            .unwrap_or_else(|| panic!("no request recorded for {url}"))
    }

    fn take(
        &self,
        table: &Mutex<HashMap<String, VecDeque<Reply>>>,
        method: &str,
        url: &str,
    ) -> Reply {
        self.calls.lock().unwrap().push(format!("{method} {url}"));
        table
            .lock()
            .unwrap()
            .get_mut(url)
            .and_then(VecDeque::pop_front)
            .unwrap_or_else(|| {
                Err(HelperTransportError::Transport(format!(
                    "no canned {method} response for {url}"
                )))
            })
    }
}

impl HelperTransport for MockTransport {
    fn get<'a>(&'a self, url: &'a str, timeout: Duration) -> HelperFuture<'a> {
        self.timeouts
            .lock()
            .unwrap()
            .push((url.to_string(), timeout));
        if let Some(observer) = self.get_observer.lock().unwrap().as_ref() {
            observer(url);
        }
        let delay = self
            .get_delays
            .lock()
            .unwrap()
            .get_mut(url)
            .and_then(VecDeque::pop_front)
            .unwrap_or_default();
        let reply = self.take(&self.gets, "GET", url);
        Box::pin(async move {
            tokio::time::sleep(delay).await;
            reply
        })
    }

    fn post_json<'a>(&'a self, url: &'a str, body: Vec<u8>, timeout: Duration) -> HelperFuture<'a> {
        self.timeouts
            .lock()
            .unwrap()
            .push((url.to_string(), timeout));
        self.post_bodies
            .lock()
            .unwrap()
            .push((url.to_string(), body));
        if let Some(observer) = self.post_observer.lock().unwrap().as_ref() {
            observer(url);
        }
        let delay = self
            .post_delays
            .lock()
            .unwrap()
            .get_mut(url)
            .and_then(VecDeque::pop_front)
            .unwrap_or_default();
        let reply = self.take(&self.posts, "POST", url);
        Box::pin(async move {
            tokio::time::sleep(delay).await;
            reply
        })
    }
}

fn json_status(status: &str) -> Reply {
    Ok(HelperResponse::json(
        200,
        format!(r#"{{"status":"{status}"}}"#).into_bytes(),
    ))
}

fn http_status(status: u16) -> Reply {
    Ok(HelperResponse::json(status, b"{}".to_vec()))
}

fn helper(index: usize) -> String {
    format!("https://helper-{index}.example")
}

fn helpers(count: usize) -> Vec<String> {
    (1..=count).map(helper).collect()
}

fn client_with(transport: Arc<MockTransport>) -> HelperClient {
    HelperClient::new(transport, HelperHealth::default())
}

fn never_cancel() -> impl Fn() -> bool {
    || false
}

// ---- Durable end-to-end passes ---------------------------------------

use crate::{
    round::RoundParams,
    storage::queries,
    types::{EncryptedShare, NoteInfo},
    vote::{serialize_recovery, VoteRecoveryBundle},
};

const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
const WALLET_ID: &str = "wallet";
/// Base submission time every timing fixture is anchored to.
const SUBMIT_AT: u64 = 1_000;
/// Far enough out that the overdue threshold clamps to its maximum.
const VOTE_END: u64 = 1_000_000;

fn field_bytes(value: u8) -> [u8; 32] {
    let mut bytes = [0u8; 32];
    bytes[0] = value;
    bytes
}

fn note(position: u64) -> NoteInfo {
    NoteInfo {
        commitment: vec![0x01; 32],
        nullifier: vec![0x02; 32],
        value: crate::governance::BALLOT_DIVISOR,
        position,
        diversifier: vec![0x03; 11],
        rho: vec![0x04; 32],
        rseed: vec![0x05; 32],
        scope: 0,
        ufvk_str: "uview1test".to_string(),
    }
}

fn recovery_bundle_fixture() -> VoteRecoveryBundle {
    VoteRecoveryBundle {
        vote_round_id: ROUND_ID.to_string(),
        bundle_index: 0,
        proposal_id: 1,
        vote_decision: 2,
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
        encrypted_shares: vec![
            EncryptedShare {
                c1: point_bytes(1),
                c2: point_bytes(2),
                share_index: 0,
                plaintext_value: 5,
                randomness: vec![0x23; 32],
            },
            EncryptedShare {
                c1: point_bytes(3),
                c2: point_bytes(4),
                share_index: 1,
                plaintext_value: 6,
                randomness: vec![0x33; 32],
            },
        ],
        share_blinds: vec![field_bytes(1), field_bytes(2)],
        share_comms: (0..crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT)
            .map(|index| field_bytes(index as u8 + 10))
            .collect(),
        batch: None,
    }
}

/// Builds a round holding one recoverable vote and one recorded share.
fn db_with_share(sent_to_urls: &[String]) -> VotingDb {
    db_with_delivery(sent_to_urls, &[], sent_to_urls.len())
}

fn db_with_delivery(
    sent_to_urls: &[String],
    ambiguous_urls: &[String],
    target_count: usize,
) -> VotingDb {
    db_with_delivery_for_wallet(WALLET_ID, sent_to_urls, ambiguous_urls, target_count)
}

fn db_with_delivery_for_wallet(
    wallet_id: &str,
    sent_to_urls: &[String],
    ambiguous_urls: &[String],
    target_count: usize,
) -> VotingDb {
    let db = VotingDb::open_in_memory().unwrap();
    db.set_wallet_id(wallet_id);
    seed_recoverable_vote_for_wallet(&db, wallet_id);
    let submission = ShareSubmissionReport {
        accepted_urls: sent_to_urls.to_vec(),
        ambiguous_urls: ambiguous_urls.to_vec(),
        target_count,
    };
    share::record_delivery(
        &db,
        &share::ShareDeliveryRecordParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            submission: &submission,
            submit_at: SUBMIT_AT,
        },
    )
    .unwrap();
    db
}

fn db_with_recoverable_vote() -> VotingDb {
    let db = VotingDb::open_in_memory().unwrap();
    db.set_wallet_id(WALLET_ID);
    seed_recoverable_vote(&db);
    db
}

fn db_with_unique_recoverable_vote() -> VotingDb {
    static NEXT_WALLET_ID: AtomicU64 = AtomicU64::new(1);

    let wallet_id = format!(
        "share-tracking-test-{}",
        NEXT_WALLET_ID.fetch_add(1, Ordering::Relaxed)
    );
    let db = VotingDb::open_in_memory().unwrap();
    db.set_wallet_id(&wallet_id);
    seed_recoverable_vote_for_wallet(&db, &wallet_id);
    db
}

fn db_with_round_and_bundle() -> VotingDb {
    let db = VotingDb::open_in_memory().unwrap();
    db.set_wallet_id(WALLET_ID);
    seed_round_and_bundle(&db);
    db
}

fn seed_round_and_bundle(db: &VotingDb) {
    db.create_round(
        crate::Network::Testnet,
        &RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 1000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        },
        None,
    )
    .unwrap();
    db.ensure_bundles(ROUND_ID, &[note(0)]).unwrap();
}

fn seed_recoverable_vote(db: &VotingDb) {
    seed_recoverable_vote_for_wallet(db, WALLET_ID);
}

fn seed_recoverable_vote_for_wallet(db: &VotingDb, wallet_id: &str) {
    seed_round_and_bundle(db);
    queries::store_vote(&db.conn(), ROUND_ID, wallet_id, 0, 1, 2, &[0xCA; 32]).unwrap();
    let json = serialize_recovery(&recovery_bundle_fixture()).unwrap();
    db.conn()
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::named_params! {
                ":json": json,
                ":pos": 456i64,
                ":round_id": ROUND_ID,
                ":wallet_id": wallet_id,
            },
        )
        .unwrap();
}

fn only_share(db: &VotingDb) -> ShareDelegationRecord {
    share::list(db, ROUND_ID)
        .unwrap()
        .into_iter()
        .next()
        .unwrap()
}

fn initial_submission<'a>(servers: &'a [String]) -> InitialShareSubmissionParams<'a> {
    InitialShareSubmissionParams {
        round_id: ROUND_ID,
        bundle_index: 0,
        proposal_id: 1,
        share_index: 0,
        share_wire_json: valid_share_json(),
        planned_servers: servers,
        fallback_servers: &[],
        target_count: 1,
        submit_at: SUBMIT_AT,
        now_seconds: SUBMIT_AT + 1,
    }
}

fn share_id_of(db: &VotingDb) -> String {
    hex::encode(only_share(db).nullifier)
}

fn share_id_at(db: &VotingDb, share_index: u32) -> String {
    let share = share::list(db, ROUND_ID)
        .unwrap()
        .into_iter()
        .find(|share| share.share_index == share_index)
        .unwrap_or_else(|| panic!("share {share_index} not found"));
    hex::encode(share.nullifier)
}

fn zero_bytes(len: usize) -> Vec<u8> {
    vec![0u8; len]
}

fn preserve_server_order(len: usize) -> Vec<u8> {
    let shuffle_steps = len / std::mem::size_of::<u64>();
    (1..=shuffle_steps)
        .rev()
        .flat_map(|index| (index as u64).to_le_bytes())
        .collect()
}

fn preserve_two_server_order(len: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; len];
    if !bytes.is_empty() {
        bytes[0] = 1;
    }
    bytes
}

fn params<'a>(
    configured: &'a [String],
    now_seconds: u64,
    random_bytes: &'a (dyn Fn(usize) -> Vec<u8> + Send + Sync),
) -> ShareTrackingParams<'a> {
    ShareTrackingParams {
        round_id: ROUND_ID,
        configured_server_urls: configured,
        now_seconds,
        vote_end_time_seconds: Some(VOTE_END),
        policy: ShareTimingPolicy::default(),
        random_bytes,
    }
}

/// Ready for a status check but not yet overdue.
fn ready_not_overdue() -> u64 {
    SUBMIT_AT + ShareTimingPolicy::default().status_check_grace_seconds + 1
}

/// Past the (clamped) overdue threshold, so retry is also armed.
fn overdue() -> u64 {
    SUBMIT_AT + ShareTimingPolicy::default().max_overdue_threshold_seconds + 1
}

async fn submit_initial_share_to_candidates(
    client: &HelperClient,
    share_wire_json: &str,
    candidate_servers: &[String],
    target_count: usize,
    now_seconds: u64,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> ShareSubmissionReport {
    // These helpers are invoked by tests that run concurrently. Give each
    // short-lived database a distinct wallet so the production per-share lock
    // does not serialize otherwise unrelated test cases.
    let db = db_with_unique_recoverable_vote();
    let candidates = canonical_helper_url_list(candidate_servers)
        .expect("test candidate URLs must canonicalize");
    submit_share_to_helpers(
        &db,
        client,
        &InitialShareSubmissionParams {
            round_id: ROUND_ID,
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            share_wire_json,
            planned_servers: &candidates,
            fallback_servers: &[],
            target_count,
            submit_at: SUBMIT_AT,
            now_seconds,
        },
        cancel,
    )
    .await
    .unwrap()
}

mod confirmation;
mod initial_delivery;
mod recovery;
mod timing_policy;
