use super::*;
use orchard::{
    note::{ExtractedNoteCommitment, NoteVersion, RandomSeed, Rho},
    note_encryption::IronwoodDomain,
    value::NoteValue,
};
use std::sync::Arc;
use zcash_client_backend::{
    data_api::WalletWrite,
    proto::compact_formats::{ChainMetadata, CompactBlock, CompactOrchardAction, CompactTx},
};
use zcash_note_encryption::{Domain, NoteEncryption};

async fn start_card_server(
    first: CompactBlock,
    second: CompactBlock,
    tip: u32,
    supports_nullifiers: bool,
) -> (
    String,
    tokio::task::JoinHandle<()>,
    Arc<std::sync::Mutex<Vec<String>>>,
) {
    start_card_server_with_tail(first, second, tip, supports_nullifiers, vec![]).await
}

async fn start_card_server_with_tail(
    first: CompactBlock,
    second: CompactBlock,
    tip: u32,
    supports_nullifiers: bool,
    tail: Vec<CompactBlock>,
) -> (
    String,
    tokio::task::JoinHandle<()>,
    Arc<std::sync::Mutex<Vec<String>>>,
) {
    use bytes::Bytes;
    use http_body_util::{BodyExt, Full};
    use prost::Message;
    use zcash_client_backend::proto::service::{
        BlockId, BlockRange, RawTransaction, SendResponse, TreeState,
    };
    fn generated(
        h: u64,
        first: &CompactBlock,
        second: &CompactBlock,
        tail: &[CompactBlock],
    ) -> CompactBlock {
        if h == first.height {
            return first.clone();
        }
        if h == second.height {
            return second.clone();
        }
        if let Some(block) = tail.iter().find(|b| b.height == h) {
            return block.clone();
        }
        let hash = |height: u64| {
            if let Some(block) = tail.iter().find(|b| b.height == height) {
                return block.hash.clone();
            }
            if height == first.height - 1 {
                return first.prev_hash.clone();
            }
            if height == second.height {
                return second.hash.clone();
            }
            let mut bytes = vec![0u8; 32];
            bytes[..8].copy_from_slice(&height.to_le_bytes());
            bytes
        };
        CompactBlock {
            height: h,
            hash: hash(h),
            prev_hash: hash(h - 1),
            chain_metadata: Some(ChainMetadata {
                ironwood_commitment_tree_size: if h > second.height {
                    second
                        .chain_metadata
                        .as_ref()
                        .unwrap()
                        .ironwood_commitment_tree_size
                } else {
                    0
                },
                ..Default::default()
            }),
            ..Default::default()
        }
    }
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let calls = Arc::new(std::sync::Mutex::new(vec![]));
    let recorded = calls.clone();
    let task = tokio::spawn(async move {
        loop {
            let (stream, _) = listener.accept().await.unwrap();
            let first = first.clone();
            let second = second.clone();
            let calls = recorded.clone();
            let tail = tail.clone();
            tokio::spawn(async move {
                let service = hyper::service::service_fn(
                    move |req: hyper::Request<hyper::body::Incoming>| {
                        let first = first.clone();
                        let second = second.clone();
                        let calls = calls.clone();
                        let tail = tail.clone();
                        async move {
                            let method = req.uri().path().rsplit('/').next().unwrap().to_string();
                            calls.lock().unwrap().push(method.clone());
                            let body = req.into_body().collect().await.unwrap().to_bytes();
                            if method == "GetBlockRangeNullifiers" && !supports_nullifiers {
                                return Ok::<_, Infallible>(
                                    hyper::Response::builder()
                                        .header("content-type", "application/grpc")
                                        .header("grpc-status", "12")
                                        .body(Full::new(Bytes::new()))
                                        .unwrap(),
                                );
                            }
                            let messages = match method.as_str() {
                                "SendTransaction" => {
                                    let tx = RawTransaction::decode(&body[5..]).unwrap();
                                    calls
                                        .lock()
                                        .unwrap()
                                        .push(format!("submitted:{}", hex::encode(tx.data)));
                                    vec![SendResponse::default().encode_to_vec()]
                                }
                                "GetLatestBlock" => vec![BlockId {
                                    height: tip as u64,
                                    hash: vec![],
                                }
                                .encode_to_vec()],
                                "GetTreeState" => {
                                    let id = BlockId::decode(&body[5..]).unwrap();
                                    let mut hash = if id.height == first.height - 1 {
                                        first.prev_hash.clone()
                                    } else {
                                        generated(id.height, &first, &second, &tail).hash
                                    };
                                    hash.reverse();
                                    vec![TreeState {
                                        network: "main".into(),
                                        height: id.height,
                                        hash: hex::encode(hash),
                                        ..Default::default()
                                    }
                                    .encode_to_vec()]
                                }
                                "GetBlock" => vec![generated(
                                    BlockId::decode(&body[5..]).unwrap().height,
                                    &first,
                                    &second,
                                    &tail,
                                )
                                .encode_to_vec()],
                                "GetBlockRange" | "GetBlockRangeNullifiers" => {
                                    let range = BlockRange::decode(&body[5..]).unwrap();
                                    (range.start.unwrap().height..=range.end.unwrap().height)
                                        .map(|h| {
                                            let mut block = generated(h, &first, &second, &tail);
                                            if method == "GetBlockRangeNullifiers" {
                                                for tx in &mut block.vtx {
                                                    for action in &mut tx.ironwood_actions {
                                                        action.cmx.clear();
                                                        action.ephemeral_key.clear();
                                                        action.ciphertext.clear();
                                                    }
                                                }
                                            }
                                            block.encode_to_vec()
                                        })
                                        .collect()
                                }
                                _ => panic!("Unexpected Gift Card RPC: {method}"),
                            };
                            let mut frames = vec![];
                            for message in messages {
                                frames.push(0);
                                frames.extend_from_slice(&(message.len() as u32).to_be_bytes());
                                frames.extend_from_slice(&message);
                            }
                            Ok::<_, Infallible>(
                                hyper::Response::builder()
                                    .header("content-type", "application/grpc")
                                    .header("grpc-status", "0")
                                    .body(Full::new(Bytes::from(frames)))
                                    .unwrap(),
                            )
                        }
                    },
                );
                let _ =
                    hyper::server::conn::http2::Builder::new(hyper_util::rt::TokioExecutor::new())
                        .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
                        .await;
            });
        }
    });
    (url, task, calls)
}

fn funded_card_blocks(
    usk: &UnifiedSpendingKey,
    height: BlockHeight,
) -> (CompactBlock, CompactBlock) {
    let recipient = usk
        .to_unified_full_viewing_key()
        .orchard()
        .unwrap()
        .address_at(0u32, zip32::Scope::External);
    let mut rho_bytes = [0u8; 32];
    rho_bytes[0] = 1;
    let rho = Rho::from_bytes(&rho_bytes).unwrap();
    let rseed = RandomSeed::from_bytes([3; 32], &rho).unwrap();
    let note = orchard::Note::from_parts(
        recipient,
        NoteValue::from_raw(10_010_000),
        rho,
        rseed,
        NoteVersion::V3,
    )
    .unwrap();
    let encryption = NoteEncryption::<IronwoodDomain>::new(None, note, [0u8; 512]);
    let epk = IronwoodDomain::epk_bytes(encryption.epk());
    let cipher = encryption.encrypt_note_plaintext();
    let txid = vec![2; 32];
    let first = CompactBlock {
        height: u32::from(height) as u64,
        hash: vec![4; 32],
        prev_hash: vec![1; 32],
        time: 1_800_000_000,
        chain_metadata: Some(ChainMetadata {
            ironwood_commitment_tree_size: 1,
            ..Default::default()
        }),
        vtx: vec![CompactTx {
            txid: txid.clone(),
            ironwood_actions: vec![CompactOrchardAction {
                nullifier: rho_bytes.to_vec(),
                cmx: ExtractedNoteCommitment::from(note.commitment())
                    .to_bytes()
                    .to_vec(),
                ephemeral_key: epk.0.to_vec(),
                ciphertext: cipher[..52].to_vec(),
            }],
            ..Default::default()
        }],
        ..Default::default()
    };
    let second = CompactBlock {
        height: u32::from(height + 1) as u64,
        hash: vec![5; 32],
        prev_hash: vec![4; 32],
        time: 1_800_000_075,
        chain_metadata: Some(ChainMetadata {
            ironwood_commitment_tree_size: 1,
            ..Default::default()
        }),
        ..Default::default()
    };
    (first, second)
}

struct ClaimFixture {
    _directory: tempfile::TempDir,
    path: String,
    uuid: String,
    address: String,
    height: BlockHeight,
    first: CompactBlock,
    second: CompactBlock,
}

impl ClaimFixture {
    fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let path = directory
            .path()
            .join("claim.db")
            .to_str()
            .unwrap()
            .to_string();
        let network = WalletNetwork::Main;
        let height = network
            .activation_height(consensus::NetworkUpgrade::Nu6_3)
            .unwrap()
            + 100;
        let (uuid, address) = crate::wallet::keys::init_db_and_create_account(
            &path,
            network,
            &SecretVec::new(vec![7; 32]),
            Some(u32::from(height) as u64),
            "card",
        )
        .unwrap();
        let (first, mut second) = funded_card_blocks(&Self::usk(), height);
        // The tip must have a different root; an empty replacement alone would
        // not reproduce the original orphaned-anchor defect.
        let other =
            UnifiedSpendingKey::from_seed(&network, &[9; 32], zip32::AccountId::ZERO).unwrap();
        let (other_block, _) = funded_card_blocks(&other, height + 1);
        let mut other_tx = other_block.vtx[0].clone();
        other_tx.txid = vec![8; 32];
        other_tx.ironwood_actions[0].nullifier = vec![9; 32];
        second.vtx.push(other_tx);
        second
            .chain_metadata
            .as_mut()
            .unwrap()
            .ironwood_commitment_tree_size = 2;
        Self {
            _directory: directory,
            path,
            uuid,
            address,
            height,
            first,
            second,
        }
    }

    fn usk() -> UnifiedSpendingKey {
        UnifiedSpendingKey::from_seed(&WalletNetwork::Main, &[7; 32], zip32::AccountId::ZERO)
            .unwrap()
    }

    fn db(&self) -> WalletDatabase {
        open_wallet_db(&self.path, WalletNetwork::Main).unwrap()
    }

    fn account(&self) -> AccountUuid {
        parse_account_uuid(&self.uuid).unwrap()
    }

    async fn check(&self, url: &str, resubmit: bool) -> Result<gift_card_claim::Snapshot, String> {
        gift_card_claim::run(
            &self.path,
            url,
            &[],
            WalletNetwork::Main,
            Arc::new(AtomicBool::new(false)),
            resubmit,
            |_, _, _, _| {},
        )
        .await
    }

    fn quote(&self) -> Result<SendMaxEstimateResult, String> {
        estimate_send_max_for_purpose(
            &self.path,
            WalletNetwork::Main,
            &self.uuid,
            &self.address,
            None,
            SendPurpose::PaymentLinkClaim,
        )
    }

    fn replacement(&self) -> CompactBlock {
        let (_, mut replacement) = funded_card_blocks(&Self::usk(), self.height);
        replacement.hash = vec![6; 32];
        replacement
    }

    fn sign(&self, legacy_tip_anchor: bool) -> (TxId, Vec<u8>) {
        let mut db = self.db();
        let proposal = if legacy_tip_anchor {
            let c = rusqlite::Connection::open(&self.path).unwrap();
            c.execute(
                "UPDATE vizor_giftcard_check SET anchor_height=?1",
                [u32::from(self.height + 1)],
            )
            .unwrap();
            let state = gift_card_claim::snapshot(&self.path).unwrap().unwrap();
            let notes = db
                .get_unspent_ironwood_notes_at_historical_height(self.account(), self.height + 1)
                .unwrap();
            // Model bytes already created by the old binary. Production
            // CardInput::load must reject this unsafe state for new attempts.
            CardInput {
                db: &db,
                account: self.account(),
                state,
                notes,
            }
            .propose(
                WalletNetwork::Main,
                build_send_request(&self.address, 10_000_000, None).unwrap(),
            )
            .unwrap()
        } else {
            CardInput::load(&db, &self.path, self.account())
                .unwrap()
                .unwrap()
                .propose(
                    WalletNetwork::Main,
                    build_send_request(&self.address, 10_000_000, None).unwrap(),
                )
                .unwrap()
        };
        let expected = if legacy_tip_anchor {
            self.height + 1
        } else {
            self.height
        };
        assert_eq!(proposal.steps().head.anchor_height(), Some(expected));
        let ids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &WalletNetwork::Main,
            &NoOpSpendProver,
            &NoOpOutputProver,
            &wallet::SpendingKeys::from_unified_spending_key(Self::usk()),
            OvkPolicy::Discard,
            &proposal,
            Some(self.height + 41),
        )
        .unwrap();
        let id = ids.head;
        (id, self.raw(&id))
    }

    fn raw(&self, id: &TxId) -> Vec<u8> {
        rusqlite::Connection::open(&self.path)
            .unwrap()
            .query_row(
                "SELECT raw FROM transactions WHERE txid=?1",
                [id.as_ref()],
                |r| r.get(0),
            )
            .unwrap()
    }
}

#[tokio::test]
async fn one_block_reorg_preserves_quotes_and_rebroadcasts_the_same_signed_claim() {
    for sign in [false, true] {
        let card = ClaimFixture::new();
        let (url, server, _) = start_card_server(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + 1),
            true,
        )
        .await;
        let state = card.check(&url, false).await.unwrap();
        assert_eq!(state.anchor_height, u32::from(card.height));
        assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
        let mut db = card.db();
        let anchor_root = db
            .with_ironwood_tree_mut(|t| t.root_at_checkpoint_id(&card.height))
            .unwrap()
            .unwrap();
        let tip_root = db
            .with_ironwood_tree_mut(|t| t.root_at_checkpoint_id(&(card.height + 1)))
            .unwrap()
            .unwrap();
        assert_ne!(anchor_root, tip_root);
        drop(db);
        let signed = sign.then(|| card.sign(false));
        server.abort();
        let (url, server, calls) = start_card_server(
            card.first.clone(),
            card.replacement(),
            u32::from(card.height + 1),
            true,
        )
        .await;
        let state = card.check(&url, sign).await.unwrap();
        assert!(state.complete);
        assert_eq!(state.anchor_height, u32::from(card.height));
        let mut db = card.db();
        assert_eq!(
            db.with_ironwood_tree_mut(|t| t.root_at_checkpoint_id(&card.height))
                .unwrap()
                .unwrap(),
            anchor_root
        );
        let input = CardInput::load(&db, &card.path, card.account())
            .unwrap()
            .unwrap();
        if let Some((id, bytes)) = signed {
            assert!(
                input.notes.is_empty(),
                "A submitted claim still owns its inputs"
            );
            assert_eq!(card.raw(&id), bytes);
            let calls = calls.lock().unwrap();
            assert_eq!(calls.iter().filter(|m| *m == "SendTransaction").count(), 1);
            assert!(calls.contains(&format!("submitted:{}", hex::encode(bytes))));
        } else {
            assert_eq!(
                input
                    .estimate_max(WalletNetwork::Main, &card.address, None)
                    .unwrap()
                    .amount_zatoshi,
                10_000_000
            );
        }
        assert!(!calls.lock().unwrap().iter().any(|m| m == "GetBlockRange"));
        server.abort();
    }
}

#[tokio::test]
async fn one_confirmation_waits_and_the_next_observation_makes_the_funding_anchor_ready() {
    let card = ClaimFixture::new();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height),
        true,
    )
    .await;
    let state = card.check(&url, false).await.unwrap();
    assert!(!state.has_confirmed_anchor());
    assert!(card.quote().is_err());
    server.abort();
    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 1),
        true,
    )
    .await;
    let state = card.check(&url, false).await.unwrap();
    assert!(state.has_confirmed_anchor());
    assert_eq!(state.anchor_height, u32::from(card.height));
    assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
    assert!(!calls.lock().unwrap().iter().any(|m| m == "GetBlockRange"));
    server.abort();
}

#[tokio::test]
async fn cached_tip_anchors_are_lowered_only_when_no_signed_attempt_owns_the_funding() {
    for cache in ["legacy", "observer", "signed"] {
        let card = ClaimFixture::new();
        let (url, server, calls) = start_card_server(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + 1),
            true,
        )
        .await;
        card.check(&url, false).await.unwrap();
        let signed = (cache == "signed").then(|| card.sign(true));
        let c = rusqlite::Connection::open(&card.path).unwrap();
        if cache == "legacy" {
            c.execute("DELETE FROM vizor_giftcard_check", []).unwrap();
        } else {
            c.execute(
                "UPDATE vizor_giftcard_check SET anchor_height=?1",
                [u32::from(card.height + 1)],
            )
            .unwrap();
        }
        if cache == "observer" {
            assert!(
                card.quote().is_err(),
                "Unchecked/unsafe anchors cannot make a new quote"
            );
        }
        calls.lock().unwrap().clear();
        let state = card.check(&url, cache == "signed").await.unwrap();
        assert!(state.complete);
        if let Some((id, bytes)) = signed {
            assert_eq!(state.anchor_height, u32::from(card.height + 1));
            assert_eq!(card.raw(&id), bytes);
            assert!(card.quote().is_err());
            assert!(calls
                .lock()
                .unwrap()
                .contains(&format!("submitted:{}", hex::encode(bytes))));
        } else {
            assert_eq!(state.anchor_height, u32::from(card.height));
            assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
        }
        assert!(!calls.lock().unwrap().iter().any(|m| m == "GetBlockRange"));
        server.abort();
    }
}

#[tokio::test]
async fn a_legacy_signed_tip_anchor_keeps_reorg_detection_and_recovers_only_after_expiry() {
    let card = ClaimFixture::new();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 1),
        true,
    )
    .await;
    card.check(&url, false).await.unwrap();
    let (id, bytes) = card.sign(true);
    // A successful check must not lower a signed attempt's observation boundary.
    assert_eq!(
        card.check(&url, false).await.unwrap().anchor_height,
        u32::from(card.height + 1)
    );
    server.abort();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.replacement(),
        u32::from(card.height + 1),
        true,
    )
    .await;
    let error = card.check(&url, false).await.err().unwrap();
    assert!(error.contains("anchor changed"), "{error}");
    assert_eq!(card.raw(&id), bytes);
    card.check(&url, false).await.unwrap();
    let db = card.db();
    let notes = db
        .get_unspent_ironwood_notes_at_historical_height(card.account(), card.height + 1)
        .unwrap();
    assert!(!notes.is_empty());
    for note in notes {
        assert!(db
            .get_spendable_note(
                note.txid(),
                ShieldedPool::Ironwood,
                note.output_index() as u32,
                (card.height + 2).into(),
                LockFilter::Policy(&LockedInputPolicy::Exclude)
            )
            .unwrap()
            .is_none());
    }
    drop(db);
    assert!(card.quote().is_err());
    server.abort();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.replacement(),
        u32::from(card.height + 41),
        true,
    )
    .await;
    card.check(&url, false).await.unwrap();
    assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
    assert_eq!(card.raw(&id), bytes);
    server.abort();
}

#[tokio::test]
async fn missing_checkpoint_note_position_and_boundary_block_are_rebuilt_within_the_check() {
    for missing in ["checkpoint", "position", "block"] {
        let card = ClaimFixture::new();
        let (url, server, calls) = start_card_server(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + 1),
            true,
        )
        .await;
        card.check(&url, false).await.unwrap();
        let c = rusqlite::Connection::open(&card.path).unwrap();
        match missing {
            "checkpoint" => {
                c.execute(
                    "DELETE FROM ironwood_tree_checkpoints WHERE checkpoint_id=?1",
                    [u32::from(card.height)],
                )
                .unwrap();
                assert!(card.quote().err().unwrap().contains("another check"));
            }
            "position" => {
                c.execute(
                    "UPDATE ironwood_received_notes SET commitment_tree_position=NULL",
                    [],
                )
                .unwrap();
            }
            "block" => {
                // Model a damaged legacy cache, including its missing block
                // row. Normal SDK writes preserve this foreign key.
                c.pragma_update(None, "foreign_keys", false).unwrap();
                c.execute(
                    "DELETE FROM blocks WHERE height=?1",
                    [u32::from(card.height)],
                )
                .unwrap();
            }
            _ => unreachable!(),
        }
        calls.lock().unwrap().clear();
        let state = card.check(&url, false).await.unwrap();
        assert!(state.complete && state.has_confirmed_anchor());
        assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
        assert!(calls.lock().unwrap().iter().any(|m| m == "GetBlockRange"));
        server.abort();
    }
}

#[tokio::test]
async fn legacy_scan_gaps_do_not_hide_or_prematurely_adopt_funding() {
    for cached_funding in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("legacy-claim.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Main;
        let height = network
            .activation_height(consensus::NetworkUpgrade::Nu6_3)
            .unwrap()
            + 300;
        let birthday = height - 200;
        let seed = SecretVec::new(vec![7; 32]);
        let (uuid, address) = crate::wallet::keys::init_db_and_create_account(
            path,
            network,
            &seed,
            Some(u32::from(birthday) as u64),
            "card",
        )
        .unwrap();
        let usk =
            UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32::AccountId::ZERO)
                .unwrap();
        let (first, second) = funded_card_blocks(&usk, height);
        let (url, server, calls) =
            start_card_server(first, second.clone(), u32::from(height + 1), true).await;
        if cached_funding {
            // Create genuine funding notes/witnesses, then model a legacy
            // cache with only the later scanned range remaining.
            gift_card_claim::run(
                path,
                &url,
                &[],
                network,
                Arc::new(AtomicBool::new(false)),
                false,
                |_, _, _, _| {},
            )
            .await
            .unwrap();
        }
        let c = rusqlite::Connection::open(path).unwrap();
        if cached_funding {
            c.execute("DELETE FROM blocks WHERE height < ?1", [u32::from(height)])
                .unwrap();
            c.execute("DELETE FROM vizor_giftcard_check", []).unwrap();
            c.execute("DELETE FROM scan_queue", []).unwrap();
            c.execute("INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(?1,?2,10),(?2,?3,0)", rusqlite::params![u32::from(birthday),u32::from(height),u32::from(height + 2)]).unwrap();
        } else {
            // Recent blocks can be scanned before the birthday history.
            c.execute(
                "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(?1,?2,0,X'000000')",
                rusqlite::params![u32::from(height + 1), second.hash],
            )
            .unwrap();
        }
        // Never delete local transaction recovery material while repairing
        // a legacy cache. Submission is intentionally disabled in this test.
        c.execute(
            "INSERT INTO transactions(txid,created,raw,min_observed_height) VALUES(?1,'legacy',X'01',0)",
            [vec![9u8; 32]],
        )
        .unwrap();
        calls.lock().unwrap().clear();
        let discovered = gift_card_claim::run(
            path,
            &url,
            &[],
            network,
            Arc::new(AtomicBool::new(false)),
            false,
            |_, _, _, _| {},
        )
        .await
        .unwrap();
        server.abort();
        assert_eq!(discovered.funding_height, u32::from(height));
        assert_eq!(discovered.unspent, 10_010_000);
        assert!(discovered.complete);
        assert!(
            calls
                .lock()
                .unwrap()
                .iter()
                .filter(|m| *m == "GetBlockRange")
                .count()
                >= 3,
            "Discovery must fill the birthday prefix before adopting cached funding"
        );
        let db = open_wallet_db(path, network).unwrap();
        assert!(db.block_fully_scanned().unwrap().unwrap().block_height() >= height);
        let input = CardInput::load(&db, path, parse_account_uuid(&uuid).unwrap())
            .unwrap()
            .unwrap();
        assert_eq!(
            input
                .estimate_max(network, &address, None)
                .unwrap()
                .amount_zatoshi,
            10_000_000
        );
        let raw: Vec<u8> = c
            .query_row(
                "SELECT raw FROM transactions WHERE txid=?1",
                [vec![9u8; 32]],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(raw, [1]);
    }
}

#[tokio::test]
async fn creates_signed_ironwood_claim_with_a_historical_witness_and_unscanned_tail() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("claim.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let height = network
        .activation_height(consensus::NetworkUpgrade::Nu6_3)
        .unwrap()
        + 100;
    let seed = SecretVec::new(vec![7; 32]);
    let (uuid, address) = crate::wallet::keys::init_db_and_create_account(
        path,
        network,
        &seed,
        Some(u32::from(height) as u64),
        "card",
    )
    .unwrap();
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32::AccountId::ZERO)
        .unwrap();
    let (first, second) = funded_card_blocks(&usk, height);
    // A fresh receiver starts with no scanned notes, then discovers its
    // first funding and builds the witness from only these two blocks.
    let (url, server, initial_calls) =
        start_card_server(first.clone(), second.clone(), u32::from(height + 1), true).await;
    let discovered = gift_card_claim::run(
        path,
        &url,
        &[],
        network,
        Arc::new(AtomicBool::new(false)),
        false,
        |_, _, _, _| {},
    )
    .await
    .unwrap();
    server.abort();
    assert_eq!(discovered.funding_height, u32::from(height));
    assert_eq!(discovered.unspent, 10_010_000);
    assert!(initial_calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == "GetBlockRange"));
    let mut db = open_wallet_db(path, network).unwrap();
    let c = rusqlite::Connection::open(path).unwrap();
    let live = height + 100_000;
    let (url, server, calls) =
        start_card_server(first.clone(), second.clone(), u32::from(live), true).await;
    let checked = gift_card_claim::run(
        path,
        &url,
        &[],
        network,
        Arc::new(AtomicBool::new(false)),
        false,
        |_, _, _, _| {},
    )
    .await
    .unwrap();
    // Unsupported default RPC first uses a capable fallback, then proves
    // the full-Ironwood compact-block path when no fallback is available.
    let (unsupported_url, unsupported_server, unsupported_calls) =
        start_card_server(first, second, u32::from(live), false).await;
    let via_fallback = gift_card_claim::run(
        path,
        &unsupported_url,
        &[url.clone()],
        network,
        Arc::new(AtomicBool::new(false)),
        false,
        |_, _, _, _| {},
    )
    .await
    .unwrap();
    assert!(via_fallback.complete);
    assert!(!unsupported_calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == "GetBlockRange"));
    let via_compact = gift_card_claim::run(
        path,
        &unsupported_url,
        &[],
        network,
        Arc::new(AtomicBool::new(false)),
        false,
        |_, _, _, _| {},
    )
    .await
    .unwrap();
    assert!(via_compact.complete);
    assert!(unsupported_calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == "GetBlockRange"));
    unsupported_server.abort();
    server.abort();
    assert!(checked.complete);
    assert_eq!(checked.checked_height, u32::from(live));
    assert_eq!(checked.unspent, 10_010_000);
    assert_eq!(
        c.query_row("SELECT COUNT(*) FROM blocks", [], |r| r.get::<_, u32>(0))
            .unwrap(),
        2
    );
    let calls = calls.lock().unwrap();
    assert!(calls.iter().any(|m| m == "GetBlockRangeNullifiers"));
    assert!(!calls
        .iter()
        .any(|m| m == "GetTransaction" || m == "GetSubtreeRoots" || m == "GetTreeState"));
    drop(calls);
    db.update_chain_tip(live).unwrap();
    assert!(db
        .suggest_scan_ranges()
        .unwrap()
        .iter()
        .any(|r| r.block_range().end > height + 2));
    let source = CardInput::load(&db, path, parse_account_uuid(&uuid).unwrap())
        .unwrap()
        .unwrap();
    let quote = source.estimate_max(network, &address, None).unwrap();
    assert_eq!(quote.amount_zatoshi, 10_000_000);
    let proposal = source
        .propose(
            network,
            build_send_request(&address, 10_000_000, None).unwrap(),
        )
        .unwrap();
    assert_eq!(proposal.steps().head.anchor_height(), Some(height));
    assert_eq!(u32::from(proposal.min_target_height()), u32::from(live + 1));
    // Build real proofs/signatures via the same SDK path as execute_proposal.
    let ids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
        &mut db,
        &network,
        &NoOpSpendProver,
        &NoOpOutputProver,
        &wallet::SpendingKeys::from_unified_spending_key(usk),
        OvkPolicy::Discard,
        &proposal,
        Some(live + 40),
    )
    .unwrap();
    assert_eq!(ids.len(), 1);
    let raw: Vec<u8> = c
        .query_row(
            "SELECT raw FROM transactions WHERE txid=?1",
            [ids.head.as_ref()],
            |r| r.get(0),
        )
        .unwrap();
    assert!(!raw.is_empty());

    c.execute(
        "INSERT INTO vizor_giftcard_mined VALUES(?1,?2)",
        rusqlite::params![ids.head.as_ref(), u32::from(live - 5)],
    )
    .unwrap();
    assert_eq!(
        gift_card_claim::confirmations(path, &ids.head.to_string()).unwrap(),
        Some(6)
    );
    let pending = CardInput::load(&db, path, parse_account_uuid(&uuid).unwrap())
        .unwrap()
        .unwrap();
    assert!(
        pending.notes.is_empty(),
        "A durable pending claim must lock its inputs"
    );
    assert!(pending.estimate_max(network, &address, None).is_err());
}

mod recovery;
