//! Input selection from a frozen, genuinely scanned funding prefix. Later
//! spendability is established by the card observer, not the wallet scan queue.
use super::*;
use crate::wallet::sync_engine::gift_card_claim;
use zcash_client_backend::data_api::{wallet::input_selection::InputSelectorError, PoolMeta};

pub(super) struct CardInput<'a> {
    db: &'a WalletDatabase,
    account: AccountUuid,
    state: gift_card_claim::Snapshot,
    notes: Vec<ReceivedNote<ReceivedNoteId, orchard::Note>>,
}
impl<'a> CardInput<'a> {
    pub(super) fn load(
        db: &'a WalletDatabase,
        path: &str,
        account: AccountUuid,
    ) -> Result<Option<Self>, String> {
        let Some(state) = gift_card_claim::snapshot(path)? else {
            return Ok(None);
        };
        if !state.complete || state.checked_height.saturating_sub(state.funding_height) + 1 < 2 {
            return Err("Insufficient balance: Gift Card check or confirmations pending".into());
        }
        let c = open_readonly_conn(path)?;
        let mut query=c.prepare("SELECT t.txid,n.action_index FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id JOIN vizor_giftcard_check g ON t.txid=g.funding_txid WHERE n.value>0 AND NOT EXISTS(SELECT 1 FROM vizor_giftcard_spends s WHERE s.nf=n.nf)").map_err(|e|e.to_string())?;
        let ids = query
            .query_map([], |r| Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, u16>(1)?)))
            .map_err(|e| e.to_string())?
            .collect::<rusqlite::Result<HashSet<_>>>()
            .map_err(|e| e.to_string())?;
        let target = BlockHeight::from_u32(state.checked_height + 1).into();
        let mut notes = vec![];
        for note in db
            .get_unspent_ironwood_notes_at_historical_height(
                account,
                BlockHeight::from_u32(state.anchor_height),
            )
            .map_err(|e| e.to_string())?
        {
            if ids.contains(&(note.txid().as_ref().to_vec(), note.output_index()))
                && db
                    .get_spendable_note(
                        note.txid(),
                        ShieldedPool::Ironwood,
                        note.output_index() as u32,
                        target,
                        LockFilter::Policy(&LockedInputPolicy::Exclude),
                    )
                    .map_err(|e| e.to_string())?
                    .is_some()
            {
                notes.push(note);
            }
        }
        Ok(Some(Self {
            db,
            account,
            state,
            notes,
        }))
    }
    pub(super) fn propose(
        &self,
        network: WalletNetwork,
        request: TransactionRequest,
    ) -> Result<Proposal<WalletFeeRule, ReceivedNoteId>, String> {
        self.select_proposal(network, request)
            .map_err(|e| format!("Propose Gift Card failed: {e}"))
    }
    fn select_proposal(
        &self,
        network: WalletNetwork,
        request: TransactionRequest,
    ) -> Result<
        Proposal<WalletFeeRule, ReceivedNoteId>,
        InputSelectorError<
            String,
            zcash_client_backend::data_api::wallet::input_selection::GreedyInputSelectorError,
            <WalletFeeRule as FeeRule>::Error,
            ReceivedNoteId,
        >,
    > {
        let (change, selector) = zip317_helper::<Self>(None, false);
        selector.propose_transaction(
            &network,
            self,
            BlockHeight::from_u32(self.state.checked_height + 1).into(),
            BlockHeight::from_u32(self.state.anchor_height),
            &self.db.pool_migration_params(),
            payment_link_claim_confirmations_policy(),
            self.account,
            request,
            &change,
            &SpendPolicy::shielded_pools(vec![ShieldedPool::Ironwood]),
            Some(TxVersion::V6),
        )
    }
    pub(super) fn estimate_max(
        &self,
        network: WalletNetwork,
        to: &str,
        memo: Option<&str>,
    ) -> Result<SendMaxEstimateResult, String> {
        let total = self
            .notes
            .iter()
            .try_fold(0u64, |sum, n| sum.checked_add(n.note().value().inner()))
            .ok_or("Gift Card value overflow")?;
        let mut amount = total;
        // Ask the same selector for its required fee, then quote the largest
        // payment covered by those exact inputs. No guessed claim fee is used.
        for _ in 0..4 {
            if amount == 0 {
                break;
            }
            match self.select_proposal(network, build_send_request(to, amount, memo)?) {
                Ok(proposal) => return summarize_send_max_proposal(&proposal),
                Err(InputSelectorError::InsufficientFunds {
                    available,
                    required,
                }) => {
                    let deficit = u64::from(required).saturating_sub(u64::from(available));
                    if deficit == 0 {
                        break;
                    }
                    amount = amount.saturating_sub(deficit);
                }
                Err(e) => return Err(format!("Gift Card quote failed: {e}")),
            }
        }
        Err("Insufficient balance for Gift Card claim".into())
    }
    fn selected(
        &self,
        account: AccountUuid,
        sources: &[ShieldedPool],
        exclude: &[ReceivedNoteId],
    ) -> ReceivedNotes<ReceivedNoteId> {
        if account != self.account || !sources.contains(&ShieldedPool::Ironwood) {
            return ReceivedNotes::empty();
        }
        ReceivedNotes::new(
            vec![],
            vec![],
            self.notes
                .iter()
                .filter(|n| !exclude.contains(n.internal_note_id()))
                .cloned()
                .collect(),
        )
    }
}
impl InputSource for CardInput<'_> {
    type Error = String;
    type AccountId = AccountUuid;
    type NoteRef = ReceivedNoteId;
    fn anchor_computable(&self, pool: ShieldedPool, height: BlockHeight) -> Result<bool, String> {
        self.db
            .anchor_computable(pool, height)
            .map_err(|e| e.to_string())
    }
    fn get_spendable_note(
        &self,
        id: &TxId,
        pool: ShieldedPool,
        index: u32,
        _: TargetHeight,
        _: LockFilter<'_>,
    ) -> Result<Option<ReceivedNote<ReceivedNoteId, Note>>, String> {
        Ok(if pool == ShieldedPool::Ironwood {
            self.notes
                .iter()
                .find(|n| n.txid() == id && n.output_index() as u32 == index)
                .cloned()
                .map(|n| {
                    n.map_note(|note| Note::Orchard {
                        note,
                        pool: orchard::ValuePool::Ironwood,
                    })
                })
        } else {
            None
        })
    }
    fn select_spendable_notes(
        &self,
        account: AccountUuid,
        _: TargetValue,
        sources: &[ShieldedPool],
        _: TargetHeight,
        _: ConfirmationsPolicy,
        exclude: &[ReceivedNoteId],
        _: LockFilter<'_>,
    ) -> Result<ReceivedNotes<ReceivedNoteId>, String> {
        Ok(self.selected(account, sources, exclude))
    }
    fn select_unspent_notes(
        &self,
        account: AccountUuid,
        sources: &[ShieldedPool],
        _: TargetHeight,
        exclude: &[ReceivedNoteId],
        _: LockFilter<'_>,
    ) -> Result<ReceivedNotes<ReceivedNoteId>, String> {
        Ok(self.selected(account, sources, exclude))
    }
    fn get_account_metadata(
        &self,
        account: AccountUuid,
        _: &NoteFilter,
        _: TargetHeight,
        exclude: &[ReceivedNoteId],
        _: LockFilter<'_>,
    ) -> Result<AccountMeta, String> {
        let selected = self.selected(account, &[ShieldedPool::Ironwood], exclude);
        Ok(AccountMeta::new(
            None,
            None,
            Some(PoolMeta::new(
                selected.ironwood().len(),
                selected.total_value().map_err(|e| e.to_string())?,
            )),
        ))
    }
    fn get_unspent_transparent_output(
        &self,
        _: &OutPoint,
        _: TargetHeight,
    ) -> Result<Option<WalletTransparentOutput<AccountUuid>>, String> {
        Ok(None)
    }
    fn get_spendable_transparent_outputs(
        &self,
        _: &TransparentAddress,
        _: TargetHeight,
        _: ConfirmationsPolicy,
        _: CoinbaseFilter,
        _: LockFilter<'_>,
    ) -> Result<Vec<WalletTransparentOutput<AccountUuid>>, String> {
        Ok(vec![])
    }
}

#[cfg(test)]
mod tests {
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
        use bytes::Bytes;
        use http_body_util::{BodyExt, Full};
        use prost::Message;
        use zcash_client_backend::proto::service::{BlockId, BlockRange, TreeState};
        fn generated(h: u64, first: &CompactBlock, second: &CompactBlock) -> CompactBlock {
            if h == first.height {
                return first.clone();
            }
            if h == second.height {
                return second.clone();
            }
            let hash = |height: u64| {
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
                    ironwood_commitment_tree_size: u32::from(h > first.height),
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
                tokio::spawn(async move {
                    let service = hyper::service::service_fn(
                        move |req: hyper::Request<hyper::body::Incoming>| {
                            let first = first.clone();
                            let second = second.clone();
                            let calls = calls.clone();
                            async move {
                                let method =
                                    req.uri().path().rsplit('/').next().unwrap().to_string();
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
                                            generated(id.height, &first, &second).hash
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
                                    )
                                    .encode_to_vec()],
                                    "GetBlockRange" | "GetBlockRangeNullifiers" => {
                                        let range = BlockRange::decode(&body[5..]).unwrap();
                                        (range.start.unwrap().height..=range.end.unwrap().height)
                                            .map(|h| {
                                                let mut block = generated(h, &first, &second);
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
                    let _ = hyper::server::conn::http2::Builder::new(
                        hyper_util::rt::TokioExecutor::new(),
                    )
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
            let usk = UnifiedSpendingKey::from_seed(
                &network,
                seed.expose_secret(),
                zip32::AccountId::ZERO,
            )
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
        let usk =
            UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32::AccountId::ZERO)
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
        assert_eq!(proposal.steps().head.anchor_height(), Some(height + 1));
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
}
