//! Registry entry keys in the participation reader (contracts-v1 §11.6):
//! key kinds, value rules, and proofs built here as the chain's stores hash
//! them, checked alone and under a signed header. No live chain is involved.

use super::*;
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use ics23::{
    calculate_existence_root, commitment_proof::Proof, CommitmentProof, ExistenceProof, HashOp,
    InnerOp, LeafOp, LengthOp, NonExistenceProof,
};
use prost13::Message as _;
use tendermint::block::signed_header::SignedHeader;
use zcash_vote_delegate::{
    delegate_entry_store_key, DelegateSigningKey, DelegateStatus, IdentityProvider,
    ProxyDelegateEntry,
};
use zcash_voting::proxy::registry::MAX_REGISTRY_ENTRY_BYTES;

/// Entry 1 as the chain writes it.
fn entry_1() -> Vec<u8> {
    ProxyDelegateEntry {
        index: 1,
        dk: DelegateSigningKey::from_secret_seed([1; 32]).delegate_key(),
        provider: IdentityProvider::X,
        handle: "alice".to_owned(),
        proof_id: "1790000000000000000".to_owned(),
        status: DelegateStatus::Active,
        status_reason: 0,
        registered_height: 123_456,
    }
    .encode()
}

/// IAVL version stamped on every node built here.
const VERSION: i64 = 7;

/// `value` as a protobuf varint.
fn varint(mut value: u64) -> Vec<u8> {
    let mut out = Vec::new();
    while value >= 0x80 {
        out.push((value as u8 & 0x7f) | 0x80);
        value >>= 7;
    }
    out.push(value as u8);
    out
}

/// `value` as the zigzag varint IAVL writes for heights, sizes and versions.
fn signed_varint(value: i64) -> Vec<u8> {
    varint(((value << 1) ^ (value >> 63)) as u64)
}

/// The leaf op IAVL and the store tree share, with `prefix`.
fn leaf_op(prefix: Vec<u8>) -> LeafOp {
    LeafOp {
        hash: HashOp::Sha256.into(),
        prehash_key: HashOp::NoHash.into(),
        prehash_value: HashOp::Sha256.into(),
        length: LengthOp::VarProto.into(),
        prefix,
    }
}

/// An existence proof of `key` and `value` under `leaf` along `path`.
fn exists(key: &[u8], value: &[u8], leaf: &LeafOp, path: Vec<InnerOp>) -> ExistenceProof {
    ExistenceProof {
        key: key.to_vec(),
        value: value.to_vec(),
        leaf: Some(leaf.clone()),
        path,
    }
}

/// The hash a leaf or path proves.
fn root_of(proof: &ExistenceProof) -> Vec<u8> {
    calculate_existence_root::<VoteStoreHashes>(proof).unwrap()
}

/// A two-leaf IAVL `vote` store, keys in ascending order.
struct VoteStore {
    left: (Vec<u8>, Vec<u8>),
    right: (Vec<u8>, Vec<u8>),
}

impl VoteStore {
    /// IAVL's leaf op: height 0, size 1, [`VERSION`].
    fn leaf() -> LeafOp {
        leaf_op([vec![0, 2], signed_varint(VERSION)].concat())
    }

    /// The root node's height, size and version, then the left child's length.
    fn inner_prefix() -> Vec<u8> {
        [
            signed_varint(1),
            signed_varint(2),
            signed_varint(VERSION),
            vec![32],
        ]
        .concat()
    }

    /// The hash of the leaf holding `entry`.
    fn leaf_hash(entry: &(Vec<u8>, Vec<u8>)) -> Vec<u8> {
        root_of(&exists(&entry.0, &entry.1, &Self::leaf(), vec![]))
    }

    /// Proves the left leaf.
    fn prove_left(&self) -> ExistenceProof {
        let step = InnerOp {
            hash: HashOp::Sha256.into(),
            prefix: Self::inner_prefix(),
            suffix: [vec![32], Self::leaf_hash(&self.right)].concat(),
        };
        exists(&self.left.0, &self.left.1, &Self::leaf(), vec![step])
    }

    /// Proves the right leaf.
    fn prove_right(&self) -> ExistenceProof {
        let step = InnerOp {
            hash: HashOp::Sha256.into(),
            prefix: [Self::inner_prefix(), Self::leaf_hash(&self.left), vec![32]].concat(),
            suffix: vec![],
        };
        exists(&self.right.0, &self.right.1, &Self::leaf(), vec![step])
    }

    /// The store's root hash.
    fn root(&self) -> Vec<u8> {
        root_of(&self.prove_left())
    }

    /// Proves `key`'s membership when the store holds it, or its absence.
    fn prove(&self, key: &[u8]) -> CommitmentProof {
        let proof = if key == self.left.0 {
            Proof::Exist(self.prove_left())
        } else if key == self.right.0 {
            Proof::Exist(self.prove_right())
        } else {
            // The neighbors around `key`: an edge leaf alone outside the range.
            let (left, right) = if key < self.left.0.as_slice() {
                (None, Some(self.prove_left()))
            } else if key < self.right.0.as_slice() {
                (Some(self.prove_left()), Some(self.prove_right()))
            } else {
                (Some(self.prove_right()), None)
            };
            Proof::Nonexist(NonExistenceProof {
                key: key.to_vec(),
                left,
                right,
            })
        };
        CommitmentProof { proof: Some(proof) }
    }
}

/// The app's multistore: an `acc` store beside `vote`, as a simple merkle
/// tree. Returns each store's proof and the app hash.
fn multistore(vote_root: &[u8]) -> (CommitmentProof, CommitmentProof, Vec<u8>) {
    let leaf = leaf_op(vec![0]);
    let acc_root = [0x5a; 32];
    let acc_leaf = root_of(&exists(b"acc", &acc_root, &leaf, vec![]));
    let vote_leaf = root_of(&exists(b"vote", vote_root, &leaf, vec![]));
    let vote = exists(
        b"vote",
        vote_root,
        &leaf,
        vec![InnerOp {
            hash: HashOp::Sha256.into(),
            prefix: [vec![1], acc_leaf].concat(),
            suffix: vec![],
        }],
    );
    let acc = exists(
        b"acc",
        &acc_root,
        &leaf,
        vec![InnerOp {
            hash: HashOp::Sha256.into(),
            prefix: vec![1],
            suffix: vote_leaf,
        }],
    );
    let app_hash = root_of(&vote);
    let wrap = |proof| CommitmentProof {
        proof: Some(Proof::Exist(proof)),
    };
    (wrap(vote), wrap(acc), app_hash)
}

/// Header height of the main fixture, whose app hash commits `height() - 1`.
/// Read from the fixture so a trust anchor refresh doesn't break these tests.
fn height() -> u64 {
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../tests/fixtures/voting-participation/main.json"
    ))
    .unwrap();
    fixture["commit"]["result"]["signed_header"]["header"]["height"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap()
}

/// An `abci_query` answer for `key` claiming `value`, with `iavl` and the
/// `store` proof of `store_name`, at the height the header commits.
fn answer(
    key: &[u8],
    value: Option<&[u8]>,
    iavl: &CommitmentProof,
    store_name: &[u8],
    store: &CommitmentProof,
) -> serde_json::Value {
    serde_json::json!({"result": {"response": {
        "code": 0,
        "height": (height() - 1).to_string(),
        "key": B64.encode(key),
        "value": value.map(|v| B64.encode(v)),
        "proofOps": {"ops": [
            {"type": "ics23:iavl", "key": B64.encode(key), "data": B64.encode(iavl.encode_to_vec())},
            {"type": "ics23:simple", "key": B64.encode(store_name), "data": B64.encode(store.encode_to_vec())},
        ]},
    }}})
}

/// A store holding entries 1 and 3, answers for entries 1 to 4, and the
/// app hash they prove against.
struct Registry {
    store: VoteStore,
    app_hash: Vec<u8>,
    vote_proof: CommitmentProof,
    acc_proof: CommitmentProof,
}

impl Registry {
    /// Entry 1 holds the vector value, entry 3 a short one.
    fn new() -> Self {
        Self::holding(entry_1(), vec![0x08, 0x03])
    }

    /// Entries 1 and 3 holding `first` and `third`.
    fn holding(first: Vec<u8>, third: Vec<u8>) -> Self {
        let store = VoteStore {
            left: (delegate_entry_store_key(1).to_vec(), first),
            right: (delegate_entry_store_key(3).to_vec(), third),
        };
        let (vote_proof, acc_proof, app_hash) = multistore(&store.root());
        Self {
            store,
            app_hash,
            vote_proof,
            acc_proof,
        }
    }

    /// The honest answer for delegate `d`.
    fn answer(&self, d: u32) -> serde_json::Value {
        let key = delegate_entry_store_key(d);
        let value = [&self.store.left, &self.store.right]
            .into_iter()
            .find(|(stored, _)| stored == &key)
            .map(|(_, value)| value.as_slice());
        answer(
            &key,
            value,
            &self.store.prove(&key),
            b"vote",
            &self.vote_proof,
        )
    }

    /// Proves `answer` for `key` as `kind`, under this registry's app hash.
    fn check(
        &self,
        answer: &serde_json::Value,
        kind: &KeyKind,
        key: &[u8],
    ) -> Result<Option<Vec<u8>>, String> {
        let query: Envelope<QueryResult> = serde_json::from_value(answer.clone()).unwrap();
        verify_kind_query(
            &query.result.response,
            kind,
            key,
            &self.app_hash,
            height() - 1,
        )
    }
}

/// The kind of delegate `d`'s registry entry key.
fn entry_kind(d: u32) -> KeyKind {
    KeyKind::Registry(RegistryProofRequest { delegate_index: d })
}

#[test]
fn registry_keys_match_the_shared_vectors_and_refuse_bad_index_lists() {
    // `kv_keys` in zcash_vote_delegate's `proxy_delegation_v1.json`.
    let keys = registry_entry_keys(&[1, 17, 1 << 30]).unwrap();
    assert_eq!(
        keys.iter().map(hex::encode).collect::<Vec<_>>(),
        ["1a0100000001", "1a0100000011", "1a0140000000"]
    );
    assert_eq!(
        registry_entry_keys(&[1, 2, 3, 4, 5, 6, 7, 8])
            .unwrap()
            .len(),
        8
    );
    for indices in [&[][..], &[0], &[2, 2], &[1, 2, 3, 4, 5, 6, 7, 8, 9]] {
        assert!(registry_entry_keys(indices).is_err(), "{indices:?}");
    }
}

#[test]
fn key_kinds_follow_the_exact_key_shapes() {
    let gov = [vec![1, 0], vec![7; 64]].concat();
    assert_eq!(
        ProvenKey::governance_nullifier(&hex::encode(&gov))
            .unwrap()
            .kind,
        KeyKind::GovernanceNullifier
    );
    let entry = ProvenKey::registry(17);
    assert_eq!(entry.bytes, delegate_entry_store_key(17));
    assert_eq!(entry.kind, entry_kind(17));
    for key in [
        vec![],
        gov[..65].to_vec(),
        [gov.clone(), vec![0]].concat(),
        [vec![1, 1], vec![7; 64]].concat(),
        entry.bytes,
    ] {
        assert!(
            ProvenKey::governance_nullifier(&hex::encode(&key)).is_err(),
            "{}",
            hex::encode(&key)
        );
    }
}

#[test]
fn registry_absence_is_proven_between_and_beyond_neighbors() {
    let registry = Registry::new();
    for d in [2, 4, u32::MAX] {
        assert_eq!(
            registry.check(
                &registry.answer(d),
                &entry_kind(d),
                &delegate_entry_store_key(d)
            ),
            Ok(None),
            "entry {d}"
        );
    }
}

#[test]
fn mutated_registry_proofs_are_rejected() {
    let registry = Registry::new();
    let key = |d| delegate_entry_store_key(d).to_vec();
    let check = |answer: &serde_json::Value, d| registry.check(answer, &entry_kind(d), &key(d));

    // Wrong key: another entry's honest answer, or its proof relabelled.
    assert!(check(&registry.answer(1), 2).is_err());
    let mut relabelled = registry.answer(1);
    for path in [
        "/result/response/key",
        "/result/response/proofOps/ops/0/key",
    ] {
        *relabelled.pointer_mut(path).unwrap() = B64.encode(key(2)).into();
    }
    assert!(check(&relabelled, 2).is_err());

    // Wrong store: the vote root claimed for `acc`, or `acc`'s own proof.
    let mut wrong_name = registry.answer(1);
    *wrong_name
        .pointer_mut("/result/response/proofOps/ops/1/key")
        .unwrap() = B64.encode(b"acc").into();
    assert!(check(&wrong_name, 1).is_err());
    let iavl = registry.store.prove(&key(1));
    let acc = answer(
        &key(1),
        Some(&entry_1()),
        &iavl,
        b"vote",
        &registry.acc_proof,
    );
    assert!(check(&acc, 1).is_err());

    // A membership claim with a tampered value, or a claim of absence for a
    // present entry.
    let mut tampered = entry_1();
    *tampered.last_mut().unwrap() ^= 1;
    let mut lying = registry.answer(1);
    *lying.pointer_mut("/result/response/value").unwrap() = B64.encode(&tampered).into();
    assert!(check(&lying, 1).is_err());
    let mut hidden = registry.answer(1);
    *hidden.pointer_mut("/result/response/value").unwrap() = serde_json::Value::Null;
    assert!(check(&hidden, 1).is_err());

    // A claim of presence for an absent entry, or a stale height.
    let mut invented = registry.answer(2);
    *invented.pointer_mut("/result/response/value").unwrap() = B64.encode([8, 2]).into();
    assert!(check(&invented, 2).is_err());
    let mut stale = registry.answer(1);
    *stale.pointer_mut("/result/response/height").unwrap() = (height() - 2).to_string().into();
    assert!(check(&stale, 1).is_err());
}

#[test]
fn the_value_rule_holds_even_for_a_valid_proof() {
    // The proofs are sound; only the kind's value rule refuses them.
    let oversized = Registry::holding(vec![9; MAX_REGISTRY_ENTRY_BYTES + 1], vec![8]);
    assert!(oversized
        .check(
            &oversized.answer(1),
            &entry_kind(1),
            &delegate_entry_store_key(1)
        )
        .is_err());
    let largest = Registry::holding(vec![9; MAX_REGISTRY_ENTRY_BYTES], vec![8]);
    assert!(largest
        .check(
            &largest.answer(1),
            &entry_kind(1),
            &delegate_entry_store_key(1)
        )
        .is_ok());
    // An entry proven under the governance rule, which admits only `[1]`.
    let registry = Registry::new();
    assert!(registry
        .check(
            &registry.answer(1),
            &KeyKind::GovernanceNullifier,
            &delegate_entry_store_key(1)
        )
        .is_err());
}

/// Test validators with ids and powers; each id seeds its signing key.
fn validators(powers: &[(u8, u64)]) -> validator::Set {
    let validators = powers
        .iter()
        .map(|(id, power)| {
            let key = ed25519_consensus::SigningKey::from([*id; 32]);
            validator::Info::new(
                tendermint::PublicKey::from_raw_ed25519(&key.verification_key().to_bytes())
                    .unwrap(),
                (*power).try_into().unwrap(),
            )
        })
        .collect();
    checked_validator_set(&ValidatorsResult { validators }).unwrap()
}

/// The main fixture's header committing `app_hash`, signed by every member
/// of `set`, with the time it was signed at.
fn signed_header(set: &validator::Set, app_hash: &[u8]) -> (SignedHeader, i64) {
    use tendermint::{
        block::CommitSig,
        vote::{Type, Vote},
    };
    let fixture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../tests/fixtures/voting-participation/main.json"
    ))
    .unwrap();
    let mut header: SignedHeader =
        serde_json::from_value(fixture["commit"]["result"]["signed_header"].clone()).unwrap();
    header.header.app_hash = tendermint::AppHash::try_from(app_hash.to_vec()).unwrap();
    header.header.validators_hash = set.hash();
    header.commit.block_id.hash = header.header.hash();
    header.commit.signatures = set
        .validators()
        .iter()
        .enumerate()
        .map(|(index, validator)| {
            let key = (1..=u8::MAX)
                .map(|id| ed25519_consensus::SigningKey::from([id; 32]))
                .find(|key| {
                    tendermint::PublicKey::from_raw_ed25519(&key.verification_key().to_bytes())
                        .unwrap()
                        == validator.pub_key
                })
                .unwrap();
            let vote = Vote {
                vote_type: Type::Precommit,
                height: header.commit.height,
                round: header.commit.round,
                block_id: Some(header.commit.block_id),
                timestamp: Some(header.header.time),
                validator_address: validator.address,
                validator_index: index.try_into().unwrap(),
                signature: None,
                extension: vec![],
                extension_signature: None,
            };
            let bytes = vote.into_signable_vec(header.header.chain_id.clone());
            CommitSig::BlockIdFlagCommit {
                validator_address: validator.address,
                timestamp: header.header.time,
                signature: Some(
                    tendermint::Signature::try_from(key.sign(&bytes).to_bytes().to_vec()).unwrap(),
                ),
            }
        })
        .collect();
    let now = header.header.time.unix_timestamp();
    (header, now)
}

/// Evidence for `answers` under a header committing `app_hash`, signed by
/// `set`.
fn evidence(
    set: &validator::Set,
    app_hash: &[u8],
    answers: Vec<serde_json::Value>,
) -> (String, i64) {
    let (header, now) = signed_header(set, app_hash);
    let evidence = serde_json::json!({
        "commit": {"result": {"signed_header": header}},
        "validators": {"result": {"validators": set.validators()}},
        "queries": answers,
    });
    (evidence.to_string(), now)
}

/// [`verify_evidence`] trusting `set` on `zvote-1`.
fn verify_trusting(
    set: &validator::Set,
    keys: &[ProvenKey],
    evidence: &str,
    now: i64,
) -> Result<Vec<Option<Vec<u8>>>, String> {
    verify_evidence(keys, evidence, |commit, validators| {
        verify_header_with_trust(
            commit,
            &checked_validator_set(validators)?,
            "zvote-1",
            set,
            now,
        )
    })
}

#[test]
fn registry_entries_verify_under_a_signed_header() {
    let set = validators(&[(1, 1), (2, 1), (3, 1)]);
    let registry = Registry::new();
    let keys = [1, 2, 3].map(ProvenKey::registry);
    let answers = vec![registry.answer(1), registry.answer(2), registry.answer(3)];
    let (good, now) = evidence(&set, &registry.app_hash, answers.clone());
    assert_eq!(
        verify_trusting(&set, &keys, &good, now),
        Ok(vec![Some(entry_1()), None, Some(vec![0x08, 0x03])])
    );

    // Answers out of order, one missing, or under another app hash.
    let mut reordered = answers.clone();
    reordered.swap(0, 2);
    let (bad, _) = evidence(&set, &registry.app_hash, reordered);
    assert!(verify_trusting(&set, &keys, &bad, now).is_err());
    let (short, _) = evidence(&set, &registry.app_hash, answers[..2].to_vec());
    assert!(verify_trusting(&set, &keys, &short, now).is_err());
    let (other, _) = evidence(&set, &[0x11; 32], answers);
    assert!(verify_trusting(&set, &keys, &other, now).is_err());

    // The public entry point keeps the bundled anchors, which never signed
    // these headers.
    for network in ["main", "test", "regtest"] {
        assert!(verify_registry_entries(&[1, 2, 3], network, &good, now).is_err());
    }
}

#[test]
fn each_key_keeps_its_own_rule_within_one_evidence() {
    let gov = [vec![1, 0], vec![7; 64]].concat();
    let store = VoteStore {
        left: (gov.clone(), vec![1]),
        right: (delegate_entry_store_key(1).to_vec(), entry_1()),
    };
    let (vote_proof, _, app_hash) = multistore(&store.root());
    let answer_for = |key: &[u8], value: Option<&[u8]>| {
        answer(key, value, &store.prove(key), b"vote", &vote_proof)
    };
    let entry = entry_1();
    let answers = vec![
        answer_for(&gov, Some(&[1])),
        answer_for(&delegate_entry_store_key(1), Some(&entry)),
        answer_for(&delegate_entry_store_key(2), None),
    ];
    let set = validators(&[(1, 1), (2, 1), (3, 1)]);
    let (good, now) = evidence(&set, &app_hash, answers);
    let gov_key = ProvenKey {
        kind: KeyKind::GovernanceNullifier,
        bytes: gov,
    };
    assert_eq!(
        verify_trusting(
            &set,
            &[gov_key, ProvenKey::registry(1), ProvenKey::registry(2)],
            &good,
            now
        ),
        Ok(vec![Some(vec![1]), Some(entry), None])
    );
    // The governance-nullifier entry point refuses registry keys outright.
    assert!(verify(
        &[hex::encode(delegate_entry_store_key(1))],
        "main",
        &good,
        now
    )
    .is_err());
}
