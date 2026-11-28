//! Boundary checks for the delegate-mode bridge on a real voting sidecar,
//! with chain answers and proven entries built as the vote chain writes
//! them: one happy path per call, the error and answer mapping, and what
//! Vizor owns (secret handling, the record scope, ballot paging, how the
//! status reads its entry). zcash_voting's own tests cover the rules behind
//! each call.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use zcash_vote_delegate::{
    attest_digest, AttestationWindow, DelegateRegisterFields, DelegateStatus, ProxyDelegateEntry,
};
use zcash_voting::wire::{DelegateAttestationSignature, DelegateEntryStatus};

use super::*;

/// The device time every test runs at.
const NOW: u64 = 1_790_000_000;
/// The round under test, as hex.
const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
/// The handle and proof post the tests' attester answers with.
const HANDLE: &str = "alice";
const PROOF_ID: &str = "1790000000000000000";

/// A sidecar beside a temporary wallet database on mainnet.
struct Device {
    _dir: tempfile::TempDir,
    scope: ApiDelegateModeScope,
}

impl Device {
    /// An empty device.
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        Self {
            _dir: dir,
            scope: ApiDelegateModeScope {
                db_path,
                network: "main".to_owned(),
            },
        }
    }

    /// A new key, recorded as the device's.
    fn holds_new_key(&self) -> Key {
        let key = Key::new();
        record_delegate_key(self.scope(), key.dk(), NOW).unwrap();
        key
    }

    /// The scope, for a call.
    fn scope(&self) -> ApiDelegateModeScope {
        self.scope.clone()
    }

    /// The device's key and entry as its records show them.
    fn held(&self) -> Option<(String, Option<u32>)> {
        device_delegate_key(self.scope())
            .unwrap()
            .map(|held| (held.key.dk, held.delegate_index))
    }

    /// The status with `entry` as the proof.
    fn status(&self, entry: Option<ApiProvenRegistryEntry>) -> Option<DelegateModeStatus> {
        delegate_mode_status(self.scope(), entry).unwrap()
    }
}

/// A delegate key as Dart holds it: the public key and its `zvdsk1…` export.
struct Key(ApiNewDelegateKey);

impl Key {
    /// A freshly created key.
    fn new() -> Self {
        Self(create_delegate_key())
    }

    /// The key, `zvdk1…`.
    fn dk(&self) -> String {
        self.0.key.dk.clone()
    }

    /// The key's 32 bytes.
    fn bytes(&self) -> [u8; 32] {
        DelegateKey::decode(&self.0.key.dk).unwrap().to_bytes()
    }

    /// The key's `zvdsk1…` export.
    fn secret(&self) -> String {
        self.0.secret.clone()
    }
}

/// The active entry `index` of `key`, as the participation reader proves it.
fn entry(index: u32, key: &Key) -> ApiProvenRegistryEntry {
    ApiProvenRegistryEntry {
        delegate_index: index,
        entry: Some(
            ProxyDelegateEntry {
                index,
                dk: DelegateKey::decode(&key.dk()).unwrap(),
                provider: IdentityProvider::X,
                handle: HANDLE.to_owned(),
                proof_id: PROOF_ID.to_owned(),
                status: DelegateStatus::Active,
                status_reason: 0,
                registered_height: 10,
            }
            .encode(),
        ),
    }
}

/// A round that ends tomorrow.
fn running_round() -> ApiDelegateRoundTiming {
    ApiDelegateRoundTiming {
        round_id: ROUND_ID.to_owned(),
        vote_end_time: NOW + 86_400,
    }
}

/// Two questions with two and three options.
fn roster() -> Vec<ApiProposalRosterEntry> {
    vec![
        ApiProposalRosterEntry {
            proposal_id: 1,
            num_options: 2,
        },
        ApiProposalRosterEntry {
            proposal_id: 2,
            num_options: 3,
        },
    ]
}

/// The verifier whose key signs attestations.
fn verifier() -> DelegateSigningKey {
    DelegateSigningKey::from_secret_seed([7; 32])
}

/// The chain's params answer naming [`verifier`] as verifier 1.
fn params() -> Vec<u8> {
    let key = verifier();
    serde_json::to_vec(&serde_json::json!({
        "params": {
            "verifiers": [{
                "verifier_id": 1,
                "pubkey": BASE64.encode(key.delegate_key().to_bytes()),
            }],
            "verifier_threshold": 1,
        }
    }))
    .unwrap()
}

/// The attester's answer for `key` posted on `provider`, signed by
/// [`verifier`] over ATTEST.
fn attestation(key: &Key, provider: ProxyDelegateProvider) -> DelegateAttestation {
    let window = AttestationWindow {
        not_before: NOW - 300,
        expires_at: NOW + 3_600,
    };
    let fields = DelegateRegisterFields {
        dk: key.bytes(),
        provider: identity_provider(provider),
        handle: HANDLE,
        proof_id: PROOF_ID,
    };
    let chain_id = participation::vote_chain_id("main").unwrap();
    let digest = attest_digest(&chain_id, &fields, &window).unwrap();
    DelegateAttestation {
        key: key.0.key.clone(),
        provider,
        handle: HANDLE.to_owned(),
        proof_id: PROOF_ID.to_owned(),
        attestations: vec![DelegateAttestationSignature {
            verifier_id: 1,
            not_before: window.not_before,
            expires_at: window.expires_at,
            sig: BASE64.encode(verifier().sign_digest(&digest)),
        }],
    }
}

/// The kind of a refused call.
fn kind<T: std::fmt::Debug>(result: Result<T, ApiDelegateModeError>) -> ApiDelegateModeErrorKind {
    result.expect_err("the call is refused").kind
}

/// A node answer of `status` carrying `code` in `codespace`.
fn node_answer(status: u16, code: u32, codespace: &str) -> Vec<u8> {
    let tx_hash = if code == 0 {
        "ab".repeat(32)
    } else {
        String::new()
    };
    serde_json::to_vec(&serde_json::json!({
        "tx_hash": tx_hash,
        "code": code,
        "codespace": codespace,
        "log": format!("status {status}"),
    }))
    .unwrap()
}

/// One ballot page as the REST API encodes it.
fn ballot_page(ballots: &[(u32, &[u32])], next_start_after: u32) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "ballots": ballots
            .iter()
            .map(|(delegate_index, options)| serde_json::json!({
                "vote_round_id": BASE64.encode([1u8; 32]),
                "delegate_index": delegate_index,
                "options": options,
                "height": 12,
            }))
            .collect::<Vec<_>>(),
        "next_start_after": next_start_after,
    }))
    .unwrap()
}

/// Delegate `delegate_index`'s listed ballot of `options`.
fn listed(delegate_index: u32, options: &[u32]) -> ApiChainDelegateBallot {
    ApiChainDelegateBallot {
        delegate_index,
        options: options.to_vec(),
        height: 12,
    }
}

#[test]
fn a_new_key_exports_as_zvdsk_and_imports_back_to_itself() {
    let key = Key::new();
    assert!(key.dk().starts_with("zvdk1") && key.secret().starts_with("zvdsk1"));
    assert_ne!(
        key.dk(),
        Key::new().dk(),
        "each key is drawn from the OS RNG"
    );
    assert_eq!(
        import_delegate_key(format!(" {}\n", key.secret())),
        Some(key.0.key.clone())
    );
    assert_eq!(
        import_delegate_key(key.dk()),
        None,
        "a key is not its export"
    );
    assert_eq!(
        delegate_marker_text(key.dk()).unwrap(),
        format!("zcash-vote-delegate v1 {}", key.dk())
    );
}

#[test]
fn a_device_holds_one_key_until_it_is_forgotten() {
    let device = Device::new();
    assert_eq!(device.held(), None);
    assert_eq!(device.status(None), None);
    let key = device.holds_new_key();
    assert_eq!(device.held(), Some((key.dk(), None)));

    let other = Key::new();
    assert_eq!(
        kind(record_delegate_key(device.scope(), other.dk(), NOW)),
        ApiDelegateModeErrorKind::Other,
        "a device holds one key"
    );
    forget_delegate_key(device.scope()).unwrap();
    assert_eq!(device.held(), None);
    record_delegate_key(device.scope(), other.dk(), NOW).unwrap();
    assert_eq!(device.held(), Some((other.dk(), None)));
}

#[test]
fn the_lookup_by_key_reads_the_entry_index_or_none() {
    let key = Key::new();
    let hex_key = hex::encode(key.bytes());
    assert_eq!(
        delegate_by_key_path(key.dk()).unwrap(),
        format!("/shielded-vote/v1/delegates/by-key/{hex_key}")
    );
    let answer = |status: u16, body: &str| {
        parse_delegate_by_key_answer(key.dk(), status, body.as_bytes().to_vec())
    };
    assert_eq!(
        answer(200, r#"{"delegate":{"index":17}}"#).unwrap(),
        Some(17)
    );
    assert_eq!(
        answer(
            404,
            &format!(r#"{{"error":"delegate key {hex_key} was never registered"}}"#)
        )
        .unwrap(),
        None
    );
    assert_eq!(
        kind(answer(404, "404 page not found")),
        ApiDelegateModeErrorKind::ChainAnswer
    );
}

#[test]
fn an_attester_answer_is_an_attestation_for_the_key() {
    let key = Key::new();
    let request = delegate_attest_request(
        ProxyDelegateProvider::X,
        "https://x.com/alice/status/1790000000000000000".to_owned(),
        key.dk(),
    )
    .unwrap();
    assert_eq!(request.path, "/v1/attest");
    let body: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
    assert_eq!(
        (&body["provider"], &body["dk"]),
        (&1.into(), &key.dk().into())
    );

    let attested = attestation(&key, ProxyDelegateProvider::X);
    let answer = serde_json::json!({
        "provider": 1,
        "handle": HANDLE,
        "proof_id": PROOF_ID,
        "attestations": [{
            "verifier_id": 1,
            "not_before": attested.attestations[0].not_before,
            "expires_at": attested.attestations[0].expires_at,
            "sig": attested.attestations[0].sig,
        }],
    });
    assert_eq!(
        parse_delegate_attest_answer(key.dk(), 200, serde_json::to_vec(&answer).unwrap()).unwrap(),
        attested
    );
    assert_eq!(
        parse_delegate_attest_answer("zvdk1nope".to_owned(), 200, Vec::new())
            .unwrap_err()
            .error,
        DelegateVerifierError::Unknown,
        "a key that does not decode"
    );
}

#[test]
fn a_registration_is_stored_before_posting_and_settles_from_the_proven_entry() {
    let device = Device::new();
    let key = device.holds_new_key();
    let attested = attestation(&key, ProxyDelegateProvider::X);
    let prepare = |secret: String| {
        prepare_delegate_register_op(
            device.scope(),
            attested.clone(),
            ProxyDelegateProvider::X,
            Some(params()),
            secret,
            NOW,
        )
    };

    assert_eq!(
        kind(prepare(key.dk())),
        ApiDelegateModeErrorKind::Other,
        "a secret is a zvdsk1 export"
    );

    let op = prepare(key.secret()).unwrap();
    assert_eq!(op.kind, ApiDelegateOpKind::Register);
    assert_eq!((op.delegate_index, op.dk.clone()), (0, key.dk()));
    assert_eq!(
        pending_delegate_register_op(device.scope()).unwrap(),
        Some(op),
        "the stored op is resent byte for byte"
    );
    let pending = device.status(None).unwrap();
    assert_eq!(pending.key, key.0.key);
    assert!(pending.entry.is_none() && pending.registration_pending);

    assert_eq!(delegate_op_path(), "/shielded-vote/v1/delegate-op");
    let answer = |status: u16, body: Vec<u8>| {
        parse_delegate_op_answer(ApiDelegateOpKind::Register, status, body)
    };
    let accepted = answer(200, node_answer(200, 0, "vote"));
    assert_eq!(accepted.kind, ApiDelegateOpAnswerKind::Accepted);
    assert_eq!(accepted.tx_hash, Some("AB".repeat(32)));
    assert_eq!(
        answer(422, node_answer(422, 61, "vote")).kind,
        ApiDelegateOpAnswerKind::AlreadyApplied
    );
    let taken = answer(422, node_answer(422, 62, "vote"));
    assert_eq!(taken.kind, ApiDelegateOpAnswerKind::Rejected);
    assert_eq!(
        (taken.codespace.as_deref(), taken.code),
        (Some("vote"), Some(62)),
        "the handle already has a live entry"
    );
    assert_eq!(
        answer(400, br#"{"error":"bad"}"#.to_vec()).kind,
        ApiDelegateOpAnswerKind::RequestRefused
    );
    assert_eq!(
        answer(503, b"down".to_vec()).kind,
        ApiDelegateOpAnswerKind::NoVerdict
    );

    // The lookup by key trails the proof by a block: an entry proven absent
    // leaves the registration pending.
    let absent = ApiProvenRegistryEntry {
        delegate_index: 17,
        entry: None,
    };
    assert!(device.status(Some(absent)).unwrap().registration_pending);

    let registered = device.status(Some(entry(17, &key))).unwrap();
    assert!(!registered.registration_pending);
    let view = registered.entry.unwrap();
    assert_eq!(
        (view.delegate_index, view.handle.as_str(), view.status),
        (17, HANDLE, DelegateEntryStatus::Active)
    );
    assert_eq!(device.held(), Some((key.dk(), Some(17))));
}

#[test]
fn the_status_takes_only_the_device_key_s_proven_entry() {
    let device = Device::new();
    let key = device.holds_new_key();
    let status = |entry| delegate_mode_status(device.scope(), Some(entry));
    assert_eq!(
        kind(status(entry(17, &Key::new()))),
        ApiDelegateModeErrorKind::EntryUnverifiable,
        "another key's entry"
    );
    assert_eq!(
        kind(status(ApiProvenRegistryEntry {
            delegate_index: 17,
            entry: Some(vec![0xFF]),
        })),
        ApiDelegateModeErrorKind::EntryUnverifiable,
        "bytes that are not an entry"
    );
    assert_eq!(device.held(), Some((key.dk(), None)));
}

#[test]
fn a_round_view_reads_the_ballot_and_the_count() {
    let device = Device::new();
    let held = device.holds_new_key();
    let account = entry(17, &held);
    let view = |entry: Option<ApiProvenRegistryEntry>,
                ballot: Option<ApiChainDelegateBallot>,
                count: Option<Vec<u8>>| {
        delegate_round_view(device.scope(), running_round(), entry, ballot, count, NOW)
    };

    let running = view(
        Some(account.clone()),
        None,
        Some(37u64.to_be_bytes().to_vec()),
    )
    .unwrap();
    assert_eq!(running.round_id, ROUND_ID);
    assert_eq!(running.vote_end_time, NOW + 86_400);
    assert_eq!(running.revealed_shares, 37);
    assert_eq!(running.ballot.kind, ApiDelegateBallotKind::NoBallotYet);
    assert_eq!(running.ballot_block, None);

    let submitted = view(Some(account), Some(listed(17, &[1, 2])), None).unwrap();
    assert_eq!(submitted.revealed_shares, 0, "an absent count is 0");
    assert_eq!(submitted.ballot.kind, ApiDelegateBallotKind::Submitted);
    assert_eq!(submitted.ballot.options, vec![1, 2]);
}

#[test]
fn ballot_pages_chain_by_their_last_delegate() {
    let page = |start_after, body: &[u8], index| {
        delegate_ballot_page(ROUND_ID.to_owned(), start_after, body.to_vec(), index)
    };
    assert_eq!(
        delegate_ballots_page_path(ROUND_ID.to_owned(), 0).unwrap(),
        format!("/shielded-vote/v1/delegate-ballots/{ROUND_ID}?start_after=0&limit=1000")
    );
    let first = ballot_page(&[(2, &[0, 1]), (5, &[1, 1])], 5);
    let last = ballot_page(&[(9, &[1, 0])], 0);
    assert_eq!(
        page(0, &first, Some(9)).unwrap(),
        ApiDelegateBallotSearch {
            next_start_after: Some(5),
            ballot: None,
        }
    );
    assert_eq!(
        page(5, &last, Some(9)).unwrap(),
        ApiDelegateBallotSearch {
            next_start_after: None,
            ballot: Some(listed(9, &[1, 0])),
        }
    );
    assert_eq!(page(5, &last, None).unwrap().ballot, None);
    assert_eq!(page(0, b"{}", None).unwrap().next_start_after, None);
    for (start_after, body, why) in [
        (
            0,
            ballot_page(&[(2, &[0])], 7),
            "continues after another delegate",
        ),
        (
            9,
            last.clone(),
            "repeats a delegate at or below start_after",
        ),
        (0, b"not json".to_vec(), "does not parse"),
    ] {
        assert_eq!(
            kind(page(start_after, &body, None)),
            ApiDelegateModeErrorKind::ChainAnswer,
            "a page that {why}"
        );
    }
    assert_eq!(
        kind(delegate_ballot_page("01".to_owned(), 0, first, None)),
        ApiDelegateModeErrorKind::Other,
        "a round id that is not 32 bytes"
    );
    assert_eq!(
        delegate_pool_share_count_key(ROUND_ID.to_owned(), 17).unwrap(),
        format!("0b{ROUND_ID}0000000000000011")
    );
}

#[test]
fn a_ballot_is_signed_once_stored_before_posting_and_resent_unchanged() {
    let device = Device::new();
    let held = device.holds_new_key();
    let preflight = |chain_ballot: Option<ApiChainDelegateBallot>, options: Vec<u32>| {
        delegate_ballot_preflight(
            device.scope(),
            ROUND_ID.to_owned(),
            17,
            chain_ballot,
            options,
        )
        .unwrap()
    };

    assert!(!preflight(None, vec![1, 2]).already_submitted);
    let op = sign_delegate_ballot(
        device.scope(),
        running_round(),
        entry(17, &held),
        roster(),
        vec![1, 2],
        held.secret(),
        NOW,
    )
    .unwrap();
    assert_eq!(op.kind, ApiDelegateOpKind::Ballot);
    assert_eq!((op.delegate_index, op.dk.clone()), (17, held.dk()));
    let stored = stored_delegate_ballot(device.scope(), ROUND_ID.to_owned(), 17)
        .unwrap()
        .unwrap();
    assert_eq!(stored.options, vec![1, 2]);
    assert_eq!(stored.op, op, "a retry posts the stored op unchanged");

    let local = preflight(None, vec![0, 0]);
    assert!(local.already_submitted && !local.same_options);
    assert_eq!(local.options, vec![1, 2]);

    assert_eq!(
        parse_delegate_op_answer(ApiDelegateOpKind::Ballot, 422, node_answer(422, 57, "vote"),)
            .kind,
        ApiDelegateOpAnswerKind::AlreadyApplied
    );
    let existing = |chain_ballot: Option<ApiChainDelegateBallot>| {
        existing_delegate_ballot_result(device.scope(), ROUND_ID.to_owned(), 17, chain_ballot)
            .unwrap()
    };
    assert_eq!(existing(None), None, "the list does not show it yet");
    assert_eq!(
        existing(Some(listed(17, &[1, 2]))).unwrap().kind,
        ApiBallotSubmitKind::AlreadyAccepted
    );
    let different = existing(Some(listed(17, &[0, 0]))).unwrap();
    assert_eq!(different.kind, ApiBallotSubmitKind::Rejected);
    assert_eq!(different.code, Some(57));
}

#[test]
fn retire_is_one_op_that_counts_on_code_55() {
    let device = Device::new();
    let held = device.holds_new_key();
    let op = build_delegate_retire_op(device.scope(), entry(17, &held), held.secret()).unwrap();
    assert_eq!(op.kind, ApiDelegateOpKind::Retire);
    assert_eq!((op.delegate_index, op.dk.clone()), (17, held.dk()));

    let answer = |code| {
        parse_delegate_op_answer(
            ApiDelegateOpKind::Retire,
            422,
            node_answer(422, code, "vote"),
        )
    };
    assert_eq!(answer(55).kind, ApiDelegateOpAnswerKind::AlreadyApplied);
    let suspended = answer(54);
    assert_eq!(suspended.kind, ApiDelegateOpAnswerKind::Rejected);
    assert_eq!(suspended.code, Some(54));
}

#[test]
fn delegate_mode_keeps_its_records_in_its_own_scope() {
    let device = Device::new();
    let key = device.holds_new_key();
    let account = db::open_voting_db(
        &device.scope.db_path,
        "550e8400-e29b-41d4-a716-446655440000",
    )
    .unwrap();
    let chain = delegate_chain(&device.scope).unwrap();
    assert_eq!(
        delegate::device_delegate_key(&account, &chain).unwrap(),
        None,
        "an account scope sees no delegate key"
    );
    let own = db::open_voting_db(&device.scope.db_path, DELEGATE_MODE_WALLET_ID).unwrap();
    assert_eq!(
        delegate::device_delegate_key(&own, &chain)
            .unwrap()
            .unwrap()
            .dk
            .encode(),
        key.dk()
    );
    let testnet = ApiDelegateModeScope {
        network: "test".to_owned(),
        ..device.scope()
    };
    assert_eq!(
        device_delegate_key(testnet).unwrap(),
        None,
        "records are per network"
    );
}
