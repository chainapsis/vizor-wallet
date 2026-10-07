use super::*;
use zcash_client_backend::data_api::TransactionStatus;

mod settlement;

struct TestBlocks(Vec<CompactBlock>);
impl zcash_client_backend::data_api::chain::BlockSource for TestBlocks {
    type Error = Infallible;
    fn with_blocks<F, E>(
        &self,
        from: Option<BlockHeight>,
        limit: Option<usize>,
        mut f: F,
    ) -> Result<(), zcash_client_backend::data_api::chain::error::Error<E, Self::Error>>
    where
        F: FnMut(
            CompactBlock,
        )
            -> Result<(), zcash_client_backend::data_api::chain::error::Error<E, Self::Error>>,
    {
        for b in self
            .0
            .iter()
            .filter(|b| from.is_none_or(|h| b.height >= u32::from(h) as u64))
            .take(limit.unwrap_or(usize::MAX))
        {
            f(b.clone())?;
        }
        Ok(())
    }
}

impl ClaimFixture {
    async fn legacy_mined_claim(&self) -> (TxId, Vec<u8>) {
        let (url, server, _) = start_card_server(
            self.first.clone(),
            self.second.clone(),
            u32::from(self.height + 1),
            true,
        )
        .await;
        self.check(&url, false).await.unwrap();
        let signed = self.sign(false);
        server.abort();
        let mut db = self.db();
        db.update_chain_tip(self.height + 3).unwrap();
        db.set_transaction_status(signed.0, TransactionStatus::Mined(self.height + 2))
            .unwrap();
        drop(db);
        rusqlite::Connection::open(&self.path)
            .unwrap()
            .execute("DELETE FROM vizor_giftcard_check", [])
            .unwrap();
        signed
    }

    fn cached_height(&self, id: &TxId) -> Option<u32> {
        rusqlite::Connection::open(&self.path)
            .unwrap()
            .query_row(
                "SELECT mined_height FROM transactions WHERE txid=?1",
                [id.as_ref()],
                |r| r.get(0),
            )
            .unwrap()
    }

    fn spend_block(&self, id: Vec<u8>, offset: u32) -> CompactBlock {
        let nf: Vec<u8> = rusqlite::Connection::open(&self.path)
            .unwrap()
            .query_row(
                "SELECT nf FROM ironwood_received_notes WHERE value>0 LIMIT 1",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let mut hash = vec![0; 32];
        hash[..8].copy_from_slice(&(u32::from(self.height) as u64 + offset as u64).to_le_bytes());
        let prev_hash = if offset == 2 {
            self.second.hash.clone()
        } else {
            let mut prev = vec![0; 32];
            prev[..8].copy_from_slice(
                &(u32::from(self.height) as u64 + offset as u64 - 1).to_le_bytes(),
            );
            prev
        };
        CompactBlock {
            height: u32::from(self.height + offset) as u64,
            hash,
            prev_hash,
            vtx: vec![CompactTx {
                txid: id,
                ironwood_actions: vec![CompactOrchardAction {
                    nullifier: nf,
                    ..Default::default()
                }],
                ..Default::default()
            }],
            ..Default::default()
        }
    }
}

#[tokio::test]
async fn legacy_cached_mined_receipt_rebroadcasts_and_recovers_after_expiry() {
    let card = ClaimFixture::new();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 1),
        true,
    )
    .await;
    card.check(&url, false).await.unwrap();
    let (id, raw) = card.sign(false);
    server.abort();

    // A real SDK status observation can learn a receipt ahead of compact scanning.
    // Model a retained pre-observer wallet: the scanned prefix ends at H+1,
    // while a receipt at H+2 subsequently disappears from the chain.
    let mut db = card.db();
    db.update_chain_tip(card.height + 3).unwrap();
    db.set_transaction_status(id, TransactionStatus::Mined(card.height + 2))
        .unwrap();
    drop(db);
    let c = rusqlite::Connection::open(&card.path).unwrap();
    c.execute("DELETE FROM vizor_giftcard_check", []).unwrap();

    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 3),
        true,
    )
    .await;
    let state = card.check(&url, true).await.unwrap();
    assert!(state.complete);
    assert_eq!(state.unspent, 10_010_000);
    assert_eq!(state.anchor_height, u32::from(card.height + 1));
    assert!(calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == &format!("submitted:{}", hex::encode(&raw))));
    assert!(card.quote().is_err());
    // SDK rewind removed the stale receipt without releasing unexpired inputs.
    card.db()
        .set_transaction_status(id, TransactionStatus::NotInMainChain)
        .unwrap();
    let mined: Option<u32> = c
        .query_row(
            "SELECT mined_height FROM transactions WHERE txid=?1",
            [id.as_ref()],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(mined, None);
    server.abort();

    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 41),
        true,
    )
    .await;
    let state = card.check(&url, true).await.unwrap();
    assert!(state.complete && state.has_confirmed_anchor());
    assert_eq!(state.unspent, 10_010_000);
    assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
    assert_eq!(card.raw(&id), raw);
    server.abort();
}

#[tokio::test]
async fn expiry_recovery_does_not_require_permission_to_resubmit() {
    let card = ClaimFixture::new();
    let (id, bytes) = card.legacy_mined_claim().await;
    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 41),
        true,
    )
    .await;
    let state = card.check(&url, false).await.unwrap();
    assert!(state.complete && state.has_confirmed_anchor());
    assert_eq!(card.cached_height(&id), None);
    assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
    assert_eq!(card.raw(&id), bytes);
    assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
    // Metadata recovery does not download or scan the observer-only tail.
    assert!(!calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == "GetBlockRange" || m == "GetTreeState"));
    server.abort();
}

#[tokio::test]
async fn receipts_inside_a_later_scanned_prefix_recover_before_and_after_expiry() {
    let card = ClaimFixture::new();
    let (id, bytes) = card.legacy_mined_claim().await;
    let mut third = card.spend_block(vec![99; 32], 2);
    third.vtx.clear();
    third.chain_metadata = Some(ChainMetadata {
        ironwood_commitment_tree_size: 2,
        ..Default::default()
    });
    let source = TestBlocks(vec![card.first.clone(), card.second.clone(), third]);
    let from = zcash_client_backend::data_api::chain::ChainState::empty(
        card.height - 1,
        BlockHash(card.first.prev_hash.clone().try_into().unwrap()),
    );
    let mut db = card.db();
    db.set_anchor_retention_interval(
        zcash_client_backend::data_api::anchor_retention::AnchorRetentionInterval::custom(
            std::num::NonZeroU32::new(1).unwrap(),
        ),
    );
    zcash_client_backend::data_api::chain::scan_cached_blocks(
        &WalletNetwork::Main,
        &source,
        &mut db,
        card.height,
        &from,
        3,
    )
    .unwrap();
    assert_eq!(
        db.block_max_scanned().unwrap().unwrap().block_height(),
        card.height + 2
    );
    drop(db);
    let checkpoint: u32 = rusqlite::Connection::open(&card.path)
        .unwrap()
        .query_row(
            "SELECT MAX(checkpoint_id) FROM ironwood_tree_checkpoints",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(checkpoint, u32::from(card.height + 2));
    assert_eq!(
        card.cached_height(&id),
        Some(u32::from(card.height + 2)),
        "Scanning the replacement chain does not unmine a status-only receipt"
    );
    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 3),
        true,
    )
    .await;
    card.check(&url, true).await.unwrap();
    assert_eq!(card.cached_height(&id), None);
    assert!(
        card.quote().is_err(),
        "An unexpired signed claim still owns the funding"
    );
    assert!(calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == &format!("submitted:{}", hex::encode(&bytes))));
    server.abort();
    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 41),
        true,
    )
    .await;
    card.check(&url, true).await.unwrap();
    assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
    assert_eq!(card.raw(&id), bytes);
    assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
    server.abort();
}

#[tokio::test]
async fn receipt_recovery_preserves_retained_reservations_until_their_expiry() {
    let card = ClaimFixture::new();
    let (id, bytes) = card.legacy_mined_claim().await;
    let owner = LockOwner::new([42; 32]);
    let funding = TxId::from_bytes(card.first.vtx[0].txid.clone().try_into().unwrap());
    let outputs = [OutputRef::new(funding, PoolType::IRONWOOD, 0)];
    crate::wallet::sync::proposal_locks::persist(&card.path, owner, &outputs, card.height + 41)
        .unwrap();
    crate::wallet::sync::proposal_locks::mark_retain_until_expiry(&card.path, owner).unwrap();
    card.db()
        .lock_outputs(&outputs, owner, card.height + 41)
        .unwrap();
    let c = rusqlite::Connection::open(&card.path).unwrap();
    c.execute(
        "UPDATE vizor_send_proposal_locks SET session_id=zeroblob(16)",
        [],
    )
    .unwrap();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 3),
        true,
    )
    .await;
    card.check(&url, false).await.unwrap();
    assert_eq!(card.cached_height(&id), None);
    assert_eq!(card.raw(&id), bytes);
    assert!(card.quote().is_err());
    let lock: (Vec<u8>, u32) = c.query_row(
        "SELECT lock_owner,lock_expiry_height FROM ironwood_received_notes WHERE value>0 LIMIT 1",
        [], |r| Ok((r.get(0)?, r.get(1)?)),
    ).unwrap();
    assert_eq!(
        lock,
        (owner.as_bytes().to_vec(), u32::from(card.height + 41))
    );
    let retained: bool = c
        .query_row(
            "SELECT retain_until_expiry FROM vizor_send_proposal_locks",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(retained);
    let history: bool = c
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM vizor_mined_transactions WHERE txid=?1)",
            [id.as_ref()],
            |r| r.get(0),
        )
        .unwrap();
    assert!(history, "Recovery must retain durable mined history");
    server.abort();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
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
async fn observed_mining_and_conflicting_spends_never_relay_or_unlock_funding() {
    for (own, mined_offset, tip_offset) in [
        (true, 2, 3),
        (true, 3, 4),
        (true, 2, 41),
        (false, 2, 41),
        (false, 2, 6),
        (false, 2, 7),
        (true, 3, 8),
    ] {
        let card = ClaimFixture::new();
        let (id, bytes) = card.legacy_mined_claim().await;
        let spender = if own {
            id.as_ref().to_vec()
        } else {
            vec![99; 32]
        };
        let block = card.spend_block(spender, mined_offset);
        let (url, server, calls) = start_card_server_with_tail(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + tip_offset),
            true,
            vec![block],
        )
        .await;
        let state = card.check(&url, true).await.unwrap();
        assert!(state.complete);
        assert_eq!(state.unspent, 0);
        assert_eq!(
            card.db().chain_height().unwrap(),
            Some(card.height + tip_offset)
        );
        assert!(card.quote().is_err());
        assert_eq!(card.raw(&id), bytes);
        assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
        assert_eq!(
            card.cached_height(&id),
            if own {
                Some(u32::from(card.height + mined_offset))
            } else if tip_offset - mined_offset >= 5 {
                // Terminal conflicts are settled by the observer, without
                // clearing the obsolete SDK receipt in a global rewind.
                Some(u32::from(card.height + 2))
            } else {
                None
            }
        );
        if own {
            assert!(
                gift_card_claim::confirmations(&card.path, &id.to_string())
                    .unwrap()
                    .unwrap()
                    > 0
            );
        }
        server.abort();
    }
}

#[tokio::test]
async fn incomplete_or_cancelled_observation_preserves_cached_receipts_and_raw_bytes() {
    for cancel_pass in [false, true] {
        let card = ClaimFixture::new();
        let (id, bytes) = card.legacy_mined_claim().await;
        let tail = if cancel_pass {
            vec![]
        } else {
            let mut broken = card.spend_block(vec![99; 32], 2);
            broken.prev_hash = vec![42; 32];
            vec![broken]
        };
        let (url, server, calls) = start_card_server_with_tail(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + 3),
            true,
            tail,
        )
        .await;
        let cancel = Arc::new(AtomicBool::new(false));
        let flag = cancel.clone();
        let result = gift_card_claim::run(
            &card.path,
            &url,
            &[],
            WalletNetwork::Main,
            cancel,
            true,
            move |phase, _, _, _| {
                if cancel_pass && phase == "checking" {
                    flag.store(true, Ordering::Relaxed);
                }
            },
        )
        .await;
        assert!(result.is_err());
        assert_eq!(card.cached_height(&id), Some(u32::from(card.height + 2)));
        assert_eq!(card.raw(&id), bytes);
        assert!(
            !gift_card_claim::snapshot(&card.path)
                .unwrap()
                .unwrap()
                .complete
        );
        assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
        server.abort();
    }
}

#[tokio::test]
async fn observer_and_configured_endpoint_disagreement_does_not_recover_receipts() {
    let card = ClaimFixture::new();
    let (id, bytes) = card.legacy_mined_claim().await;
    let (url, primary, primary_calls) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 3),
        false,
    )
    .await;
    let mut divergent = card.spend_block(vec![99; 32], 3);
    divergent.hash = vec![77; 32];
    divergent.vtx.clear();
    let (fallback, secondary, secondary_calls) = start_card_server_with_tail(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 3),
        true,
        vec![divergent],
    )
    .await;
    let result = gift_card_claim::run(
        &card.path,
        &url,
        &[fallback],
        WalletNetwork::Main,
        Arc::new(AtomicBool::new(false)),
        true,
        |_, _, _, _| {},
    )
    .await;
    assert!(result.err().unwrap().contains("tip changed"));
    assert_eq!(card.cached_height(&id), Some(u32::from(card.height + 2)));
    assert_eq!(card.raw(&id), bytes);
    assert!(
        !gift_card_claim::snapshot(&card.path)
            .unwrap()
            .unwrap()
            .complete
    );
    for calls in [primary_calls, secondary_calls] {
        assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
    }
    primary.abort();
    secondary.abort();
}

#[tokio::test]
async fn a_lagging_legacy_endpoint_preserves_sdk_tip_receipts_and_signed_bytes() {
    for lost_tip in [false, true] {
        let card = ClaimFixture::new();
        let (id, bytes) = card.legacy_mined_claim().await;
        if lost_tip {
            rusqlite::Connection::open(&card.path)
                .unwrap()
                .execute("DELETE FROM scan_queue", [])
                .unwrap();
        }
        let known_tip = card.db().chain_height().unwrap();
        let (url, server, calls) = start_card_server(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + if lost_tip { 1 } else { 2 }),
            true,
        )
        .await;
        assert!(card
            .check(&url, true)
            .await
            .err()
            .unwrap()
            .contains("endpoint is behind"));
        assert_eq!(card.db().chain_height().unwrap(), known_tip);
        assert_eq!(card.cached_height(&id), Some(u32::from(card.height + 2)));
        assert_eq!(card.raw(&id), bytes);
        assert!(gift_card_claim::snapshot(&card.path).unwrap().is_none());
        assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
        server.abort();
        // A caught-up endpoint can perform the normal recovery on retry.
        let (url, server, calls) = start_card_server(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + 3),
            true,
        )
        .await;
        card.check(&url, true).await.unwrap();
        assert_eq!(card.cached_height(&id), None);
        assert!(calls
            .lock()
            .unwrap()
            .iter()
            .any(|m| m == &format!("submitted:{}", hex::encode(&bytes))));
        server.abort();
    }
}

#[tokio::test]
async fn a_rediscovered_orphaned_proof_anchor_is_not_rebroadcast_before_expiry() {
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
    server.abort();
    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.replacement(),
        u32::from(card.height + 1),
        true,
    )
    .await;
    assert!(card
        .check(&url, true)
        .await
        .err()
        .unwrap()
        .contains("anchor changed"));
    card.check(&url, true).await.unwrap();
    assert!(card.quote().is_err());
    assert_eq!(card.raw(&id), bytes);
    assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
    server.abort();
}

#[tokio::test]
async fn a_rewind_checkpoint_hole_uses_bounded_rediscovery_without_revoking_the_claim() {
    let card = ClaimFixture::new();
    let (id, bytes) = card.legacy_mined_claim().await;
    let c = rusqlite::Connection::open(&card.path).unwrap();
    c.execute(
        "INSERT INTO ironwood_tree_checkpoints(checkpoint_id,position) SELECT ?1,position FROM ironwood_tree_checkpoints WHERE checkpoint_id=?2",
        rusqlite::params![u32::from(card.height + 2),u32::from(card.height + 1)],
    ).unwrap();
    c.execute(
        "DELETE FROM ironwood_tree_checkpoints WHERE checkpoint_id=?1",
        [u32::from(card.height + 1)],
    )
    .unwrap();
    // Model a hole between older and newer checkpoints: the SDK cannot use
    // H+1 and would rewind to H. Keep the signed observation boundary at H+1.
    c.execute(
        "INSERT INTO vizor_giftcard_check VALUES(1,?1,?2,?3,0,0)",
        rusqlite::params![
            u32::from(card.height),
            card.first.vtx[0].txid,
            u32::from(card.height + 1)
        ],
    )
    .unwrap();
    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 3),
        true,
    )
    .await;
    assert!(card.check(&url, true).await.unwrap().complete);
    assert_eq!(card.cached_height(&id), None);
    assert_eq!(card.raw(&id), bytes);
    assert!(
        card.quote().is_err(),
        "Rediscovery must retain the unexpired attempt"
    );
    let boundary: bool = c
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM blocks WHERE height=?1)",
            [u32::from(card.height + 1)],
            |r| r.get(0),
        )
        .unwrap();
    assert!(boundary, "Rediscovery must restore the funding prefix");
    let calls = calls.lock().unwrap();
    assert_eq!(
        calls.iter().filter(|m| *m == "GetTreeState").count(),
        2,
        "One birthday rewind and one discovery batch rebuild the cache"
    );
    assert!(calls
        .iter()
        .any(|m| m == &format!("submitted:{}", hex::encode(&bytes))));
    server.abort();
}
