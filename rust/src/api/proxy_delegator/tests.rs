//! Boundary checks for the delegator bridge on a real voting sidecar: one
//! happy path per call, the view mapping, and what Vizor owns (the
//! pending-round scan). zcash_voting's own tests cover the rules behind
//! each call.

use zcash_vote_delegate::DelegateSigningKey;
use zcash_voting::governance::BALLOT_DIVISOR;
use zcash_voting::session::Decision;
use zcash_voting::storage::queries;
use zcash_voting::types::Network;
use zcash_voting::wire::{ProxyDelegateChoice, VotingRoundParams};

use super::*;

/// The round under test.
const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
/// The account whose sidecar is seeded.
const ACCOUNT: &str = "550e8400-e29b-41d4-a716-446655440000";
/// The round's vote end.
const VOTE_END: u64 = 100_000;
/// The round's proposal ids.
const ROSTER: [u32; 1] = [1];

/// A sidecar beside a temporary wallet database whose round has bundles
/// `0, 1, …` holding `weights` whole ballots each, with every [`ROSTER`]
/// proposal answered.
struct Sidecar {
    _dir: tempfile::TempDir,
    db_path: String,
}

impl Sidecar {
    /// Seeds the round and its bundles.
    fn with_bundle_weights(weights: &[u64]) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let db = db::open_voting_db(&db_path, ACCOUNT).unwrap();
        {
            let conn = db.conn();
            queries::insert_round(
                &conn,
                ACCOUNT,
                Network::Testnet,
                &VotingRoundParams {
                    vote_round_id: ROUND_ID.to_owned(),
                    snapshot_height: 1_000,
                    ea_pk: vec![0xEA; 32],
                    nc_root: vec![0xAA; 32],
                    nullifier_imt_root: vec![0xBB; 32],
                },
                None,
            )
            .unwrap();
            for (bundle_index, _) in weights.iter().enumerate() {
                queries::insert_bundle(&conn, ROUND_ID, ACCOUNT, bundle_index as u32, &[]).unwrap();
            }
        }
        for proposal_id in ROSTER {
            db.set_ballot_intent(ROUND_ID, proposal_id, Decision::Skipped, 2)
                .unwrap();
        }
        let sidecar = Self { _dir: dir, db_path };
        for (bundle_index, &ballots) in weights.iter().enumerate() {
            sidecar.set_bundle_ballots(bundle_index as u32, ballots);
        }
        sidecar
    }

    /// Stores `ballots` whole ballots, plus a remainder planning drops, as
    /// `bundle_index`'s note total.
    fn set_bundle_ballots(&self, bundle_index: u32, ballots: u64) {
        let db = db::open_voting_db(&self.db_path, ACCOUNT).unwrap();
        let total = (ballots * BALLOT_DIVISOR + BALLOT_DIVISOR - 1) as i64;
        db.conn()
            .execute(
                "UPDATE bundles SET total_note_value = ?1
                  WHERE round_id = ?2 AND wallet_id = ?3 AND bundle_index = ?4",
                (total, ROUND_ID, ACCOUNT, bundle_index),
            )
            .unwrap();
    }

    /// [`preview_proxy_allocation`] of [`request`] at [`early`].
    fn preview(&self) -> Result<ProxyAllocationPreview, ProxyDelegationError> {
        preview_proxy_allocation(self.db_path.clone(), ACCOUNT.to_owned(), request(), early())
    }

    /// [`commit_proxy_allocation`] of [`request`] at [`early`].
    fn commit(
        &self,
        confirmed: &ProxyAllocationPreview,
        checks: Vec<DelegateCheck>,
    ) -> Result<(), ProxyDelegationError> {
        commit_proxy_allocation(
            self.db_path.clone(),
            ACCOUNT.to_owned(),
            request(),
            confirmed.clone(),
            checks,
            early(),
            ROSTER.to_vec(),
        )
    }

    /// [`proxy_allocation_status`] from `pages` in `phase`.
    fn status(
        &self,
        pages: &[&[u8]],
        phase: ApiProxyRoundPhase,
    ) -> Result<Option<ApiProxyAllocationStatus>, ProxyDelegationError> {
        proxy_allocation_status(
            self.db_path.clone(),
            ACCOUNT.to_owned(),
            ROUND_ID.to_owned(),
            pages.iter().map(|page| page.to_vec()).collect(),
            phase,
        )
    }

    /// [`proxy_delegation_progress`] from an empty ballot list.
    fn progress(&self) -> Result<Option<ApiProxyDelegationProgress>, ProxyDelegationError> {
        proxy_delegation_progress(
            self.db_path.clone(),
            ACCOUNT.to_owned(),
            ROUND_ID.to_owned(),
            vec![b"{}".to_vec()],
            ApiProxyRoundPhase::Active,
        )
    }
}

/// A timing well before the round's last-moment window.
fn early() -> ApiProxyRoundTiming {
    ApiProxyRoundTiming {
        now_seconds: 10,
        ceremony_start_seconds: Some(0),
        vote_end_time_seconds: Some(VOTE_END),
    }
}

/// Delegate `index`'s key, derived from a fixed seed.
fn delegate_key(index: u32) -> String {
    DelegateSigningKey::from_secret_seed([index as u8; 32])
        .delegate_key()
        .encode()
}

/// Delegates 3 and 4 with half and a quarter of the weight, keeping the
/// rest.
fn request() -> ProxyAllocationRequest {
    let choice = |delegate_index: u32, percent_bps: u16| ProxyDelegateChoice {
        delegate_index,
        percent_bps,
        provider: ProxyDelegateProvider::X,
        handle: format!("delegate{delegate_index}"),
        dk: delegate_key(delegate_index),
    };
    ProxyAllocationRequest {
        round_id: ROUND_ID.to_owned(),
        choices: vec![choice(3, 5_000), choice(4, 2_500)],
    }
}

/// Verdicts allowing both choices of [`request`].
fn allowed() -> Vec<DelegateCheck> {
    vec![DelegateCheck::Ok; 2]
}

/// One delegate ballot page as the REST API encodes it.
fn ballot_page(ballots: &[(u32, &[u32])], next_start_after: u32) -> Vec<u8> {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
    let round = BASE64.encode(hex::decode(ROUND_ID).unwrap());
    serde_json::to_vec(&serde_json::json!({
        "ballots": ballots
            .iter()
            .map(|(delegate_index, options)| serde_json::json!({
                "vote_round_id": round,
                "delegate_index": delegate_index,
                "options": options,
                "height": 12,
            }))
            .collect::<Vec<_>>(),
        "next_start_after": next_start_after,
    }))
    .unwrap()
}

#[test]
fn a_previewed_plan_commits_once_and_reads_back_as_preparing() {
    let sidecar = Sidecar::with_bundle_weights(&[100, 50]);
    assert_eq!(
        sidecar
            .status(&[b"{}"], ApiProxyRoundPhase::Active)
            .unwrap(),
        None,
        "nothing is committed yet"
    );
    let preview = sidecar.preview().unwrap();
    let delegated: Vec<_> = preview
        .delegations
        .iter()
        .map(|delegation| (delegation.delegate_index, delegation.ballots))
        .collect();
    assert_eq!(delegated, vec![(3, 75), (4, 38)]);
    assert_eq!(preview.kept_ballots, 37);
    assert!(!preview.single_share);

    sidecar.commit(&preview, allowed()).unwrap();

    let status = sidecar
        .status(&[b"{}"], ApiProxyRoundPhase::Active)
        .unwrap()
        .unwrap();
    assert_eq!(status.kept_ballots, 37);
    let views: Vec<_> = status
        .delegations
        .iter()
        .map(|view| {
            (
                view.delegate_index,
                view.handle.as_str(),
                view.ballots,
                view.stage,
            )
        })
        .collect();
    assert_eq!(
        views,
        vec![
            (3, "delegate3", 75, ProxyDelegationStage::Preparing),
            (4, "delegate4", 38, ProxyDelegationStage::Preparing),
        ]
    );
    let progress = sidecar.progress().unwrap().unwrap();
    assert_eq!(progress.delegations, status.delegations);
}

#[test]
fn a_committed_allocation_owes_work() {
    let pending = |db_path: &str, accounts: &[&str]| {
        list_pending_proxy_rounds(
            db_path.to_owned(),
            accounts
                .iter()
                .map(|account| (*account).to_owned())
                .collect(),
        )
        .unwrap()
    };
    let empty = tempfile::tempdir().unwrap();
    let no_wallet = empty.path().join("wallet.db");
    let no_wallet = no_wallet.to_str().unwrap();
    assert!(pending(no_wallet, &[ACCOUNT]).is_empty());
    assert!(
        !VotingDb::wallet_sidecar_path(Path::new(no_wallet)).exists(),
        "no sidecar is created"
    );

    let sidecar = Sidecar::with_bundle_weights(&[100, 50]);
    assert!(
        pending(&sidecar.db_path, &[ACCOUNT]).is_empty(),
        "a round without an allocation owes nothing"
    );
    let preview = sidecar.preview().unwrap();
    sidecar.commit(&preview, allowed()).unwrap();
    assert_eq!(
        pending(&sidecar.db_path, &["", "another-account", ACCOUNT]),
        vec![ApiPendingProxyRound {
            account_uuid: ACCOUNT.to_owned(),
            round_id: ROUND_ID.to_owned(),
        }]
    );
}

#[test]
fn each_delegate_s_ballot_reads_from_the_whole_round_list() {
    let sidecar = Sidecar::with_bundle_weights(&[100, 50]);
    let preview = sidecar.preview().unwrap();
    sidecar.commit(&preview, allowed()).unwrap();
    let first = ballot_page(&[(1, &[0, 1]), (3, &[1, 2])], 3);
    let last = ballot_page(&[(9, &[0, 0])], 0);
    let ballots = |status: ApiProxyAllocationStatus| -> Vec<_> {
        status
            .delegations
            .into_iter()
            .map(|view| (view.delegate_index, view.ballot))
            .collect()
    };

    let active = sidecar
        .status(&[&first, &last], ApiProxyRoundPhase::Active)
        .unwrap()
        .unwrap();
    assert_eq!(
        ballots(active),
        vec![
            (
                3,
                ApiDelegateBallotView {
                    kind: ApiDelegateBallotKind::Submitted,
                    options: vec![1, 2],
                }
            ),
            (
                4,
                ApiDelegateBallotView {
                    kind: ApiDelegateBallotKind::NoBallotYet,
                    options: Vec::new(),
                }
            ),
        ]
    );
}

#[cfg(not(feature = "unstable-proxy-delegation"))]
#[test]
fn availability_is_unsupported_while_zcash_voting_is_dormant() {
    let sidecar = Sidecar::with_bundle_weights(&[100, 50]);
    let chain = ApiProxyChainAnswers {
        protocol_capabilities: br#"{"proxy_delegation_version":1}"#.to_vec(),
        vote_round: br#"{"round":{"proxy_delegation":{"enabled":true}}}"#.to_vec(),
        proxy_delegation_params: Some(br#"{"params":{}}"#.to_vec()),
    };
    let availability = proxy_delegation_availability(
        sidecar.db_path.clone(),
        ACCOUNT.to_owned(),
        ROUND_ID.to_owned(),
        chain,
        ApiGovNullifierProof::Unspent,
        early(),
    );
    assert!(!zcash_voting::proxy::PROXY_DELEGATION_ENABLED);
    assert_eq!(
        availability.unwrap(),
        ApiProxyAvailability {
            kind: ApiProxyAvailabilityKind::Unsupported,
            used_elsewhere: false,
        }
    );
}
