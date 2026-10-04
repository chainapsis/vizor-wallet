use super::*;

#[tokio::test]
async fn settlement_requires_an_uncancelled_contiguous_agreed_observation() {
    for failure in ["cancel", "continuity", "endpoint"] {
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
        let mut spend = card.spend_block(id.as_ref().to_vec(), 3);
        if failure == "continuity" {
            spend.prev_hash = vec![42; 32];
        }
        let (url, primary, calls) = start_card_server_with_tail(
            card.first.clone(),
            card.second.clone(),
            u32::from(card.height + 8),
            failure != "endpoint",
            vec![spend.clone()],
        )
        .await;
        let mut secondary = None;
        let mut fallbacks = vec![];
        if failure == "endpoint" {
            let mut boundary = card.spend_block(vec![99; 32], 8);
            boundary.vtx.clear();
            boundary.hash = vec![77; 32];
            let (fallback, server, _) = start_card_server_with_tail(
                card.first.clone(),
                card.second.clone(),
                u32::from(card.height + 8),
                true,
                vec![spend, boundary],
            )
            .await;
            fallbacks.push(fallback);
            secondary = Some(server);
        }
        let cancel = Arc::new(AtomicBool::new(false));
        let flag = cancel.clone();
        let result = gift_card_claim::run(
            &card.path,
            &url,
            &fallbacks,
            WalletNetwork::Main,
            cancel,
            true,
            move |phase, _, _, _| {
                if failure == "cancel" && phase == "checking" {
                    flag.store(true, Ordering::Relaxed);
                }
            },
        )
        .await;
        assert!(result.is_err(), "{failure} must prevent settlement");
        assert_eq!(card.cached_height(&id), None);
        assert_eq!(card.raw(&id), raw);
        assert!(
            !gift_card_claim::snapshot(&card.path)
                .unwrap()
                .unwrap()
                .complete
        );
        assert!(!calls.lock().unwrap().iter().any(|m| m == "SendTransaction"));
        primary.abort();
        if let Some(server) = secondary {
            server.abort();
        }
    }
}

#[tokio::test]
async fn settled_mixed_claims_record_the_mined_leg_without_rewinding_the_failed_leg() {
    let mut card = ClaimFixture::new();
    card.first.vtx[0]
        .ironwood_actions
        .push(additional_funding_action());
    card.first
        .chain_metadata
        .as_mut()
        .unwrap()
        .ironwood_commitment_tree_size = 2;
    card.second
        .chain_metadata
        .as_mut()
        .unwrap()
        .ironwood_commitment_tree_size = 3;
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 1),
        true,
    )
    .await;
    card.check(&url, false).await.unwrap();
    let (failed, failed_raw) = card.sign(false);
    server.abort();
    let c = rusqlite::Connection::open(&card.path).unwrap();
    let (failed_index, failed_nf): (u16, Vec<u8>) = c.query_row(
        "SELECT n.action_index,n.nf FROM ironwood_received_notes n JOIN v_received_output_spends s ON s.pool=4 AND s.received_output_id=n.id JOIN transactions t ON t.id_tx=s.transaction_id WHERE t.txid=?1",
        [failed.as_ref()], |r| Ok((r.get(0)?, r.get(1)?)),
    ).unwrap();
    let mut db = card.db();
    let notes = db
        .get_unspent_ironwood_notes_at_historical_height(card.account(), card.height)
        .unwrap()
        .into_iter()
        .filter(|n| n.output_index() != failed_index)
        .collect();
    let state = gift_card_claim::snapshot(&card.path).unwrap().unwrap();
    let proposal = CardInput {
        db: &db,
        account: card.account(),
        state,
        notes,
    }
    .propose(
        WalletNetwork::Main,
        build_send_request(&card.address, 10_000_000, None).unwrap(),
    )
    .unwrap();
    let ids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
        &mut db,
        &WalletNetwork::Main,
        &NoOpSpendProver,
        &NoOpOutputProver,
        &wallet::SpendingKeys::from_unified_spending_key(ClaimFixture::usk()),
        OvkPolicy::Discard,
        &proposal,
        Some(card.height + 41),
    )
    .unwrap();
    let mined = ids.head;
    db.update_chain_tip(card.height + 8).unwrap();
    db.set_transaction_status(failed, TransactionStatus::Mined(card.height + 2))
        .unwrap();
    drop(db);
    let mined_raw = card.raw(&mined);
    assert_eq!(card.cached_height(&mined), None);
    let mined_nf: Vec<u8> = c.query_row(
        "SELECT n.nf FROM ironwood_received_notes n JOIN v_received_output_spends s ON s.pool=4 AND s.received_output_id=n.id JOIN transactions t ON t.id_tx=s.transaction_id WHERE t.txid=?1",
        [mined.as_ref()], |r| r.get(0),
    ).unwrap();
    let mut conflict = card.spend_block(vec![99; 32], 2);
    conflict.vtx[0].ironwood_actions[0].nullifier = failed_nf;
    let mut success = card.spend_block(mined.as_ref().to_vec(), 3);
    success.vtx[0].ironwood_actions[0].nullifier = mined_nf;
    let (url, server, calls) = start_card_server_with_tail(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 8),
        true,
        vec![conflict, success],
    )
    .await;
    let state = card.check(&url, true).await.unwrap();
    assert!(state.complete && state.unspent == 0);
    assert_eq!(
        card.cached_height(&failed),
        Some(u32::from(card.height + 2))
    );
    assert_eq!(card.cached_height(&mined), Some(u32::from(card.height + 3)));
    let evidence = gift_card_claim::spend_evidence(&card.path, &format!("{failed},{mined}"))
        .unwrap()
        .unwrap();
    assert_eq!(
        evidence.conflicted_txids,
        vec![hex::encode(failed.as_ref())]
    );
    assert!(!evidence.all_funds_spent_elsewhere);
    assert_eq!(
        gift_card_claim::confirmations(&card.path, &mined.to_string()).unwrap(),
        Some(6)
    );
    assert_eq!(
        gift_card_claim::confirmations(&card.path, &format!("{failed},{mined}")).unwrap(),
        Some(0)
    );
    assert_eq!(card.raw(&failed), failed_raw);
    assert_eq!(card.raw(&mined), mined_raw);
    assert!(card.quote().is_err());
    assert!(!calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == "GetTreeState" || m == "GetBlockRange" || m == "SendTransaction"));
    server.abort();
}

fn additional_funding_action() -> CompactOrchardAction {
    let recipient = ClaimFixture::usk()
        .to_unified_full_viewing_key()
        .orchard()
        .unwrap()
        .address_at(0u32, zip32::Scope::External);
    let rho = Rho::from_bytes(&[2; 32]).unwrap();
    let note = orchard::Note::from_parts(
        recipient,
        NoteValue::from_raw(10_010_000),
        rho,
        RandomSeed::from_bytes([4; 32], &rho).unwrap(),
        NoteVersion::V3,
    )
    .unwrap();
    let encryption = NoteEncryption::<IronwoodDomain>::new(None, note, [0u8; 512]);
    CompactOrchardAction {
        nullifier: vec![2; 32],
        cmx: ExtractedNoteCommitment::from(note.commitment())
            .to_bytes()
            .to_vec(),
        ephemeral_key: IronwoodDomain::epk_bytes(encryption.epk()).0.to_vec(),
        ciphertext: encryption.encrypt_note_plaintext()[..52].to_vec(),
    }
}

#[tokio::test]
async fn missing_boundary_does_not_relay_an_orphaned_signed_anchor() {
    let card = ClaimFixture::new();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 1),
        true,
    )
    .await;
    card.check(&url, false).await.unwrap();
    let (id, raw) = card.sign(true);
    server.abort();
    let c = rusqlite::Connection::open(&card.path).unwrap();
    c.pragma_update(None, "foreign_keys", false).unwrap();
    c.execute(
        "DELETE FROM blocks WHERE height=?1",
        [u32::from(card.height + 1)],
    )
    .unwrap();
    let (url, server, calls) = start_card_server(
        card.first.clone(),
        card.replacement(),
        u32::from(card.height + 3),
        true,
    )
    .await;
    let state = card.check(&url, true).await.unwrap();
    assert!(state.complete);
    assert_eq!(state.anchor_height, u32::from(card.height + 3));
    assert_eq!(card.raw(&id), raw);
    assert!(card.quote().is_err());
    assert!(!calls
        .lock()
        .unwrap()
        .iter()
        .any(|call| call == "SendTransaction"));
    server.abort();
    let (url, server, _) = start_card_server(
        card.first.clone(),
        card.replacement(),
        u32::from(card.height + 41),
        true,
    )
    .await;
    assert!(card.check(&url, true).await.unwrap().complete);
    assert_eq!(card.quote().unwrap().amount_zatoshi, 10_000_000);
    server.abort();
}

#[tokio::test]
async fn settled_funding_preserves_a_later_top_up_spend_receipt() {
    let mut card = ClaimFixture::new();
    // Add a distinct, decryptable top-up in H+1. A later ordinary SDK send
    // spends this note alone, rather than the first Gift Card funding.
    card.second.vtx = vec![CompactTx {
        txid: vec![7; 32],
        ironwood_actions: vec![additional_funding_action()],
        ..Default::default()
    }];
    let (stale_claim, _) = card.legacy_mined_claim().await;
    let mut db = card.db();
    let notes = db
        .get_unspent_ironwood_notes_at_historical_height(card.account(), card.height + 1)
        .unwrap()
        .into_iter()
        .filter(|note| note.txid().as_ref() == &[7u8; 32])
        .collect();
    let proposal = CardInput {
        db: &db,
        account: card.account(),
        notes,
        state: gift_card_claim::Snapshot {
            funding_height: u32::from(card.height + 1),
            anchor_height: u32::from(card.height + 1),
            checked_height: u32::from(card.height + 3),
            ..Default::default()
        },
    }
    .propose(
        WalletNetwork::Main,
        build_send_request(&card.address, 10_000_000, None).unwrap(),
    )
    .unwrap();
    let ids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
        &mut db,
        &WalletNetwork::Main,
        &NoOpSpendProver,
        &NoOpOutputProver,
        &wallet::SpendingKeys::from_unified_spending_key(ClaimFixture::usk()),
        OvkPolicy::Discard,
        &proposal,
        Some(card.height + 601),
    )
    .unwrap();
    let unrelated = ids.head;
    db.update_chain_tip(card.height + 600).unwrap();
    db.set_transaction_status(unrelated, TransactionStatus::Mined(card.height + 550))
        .unwrap();
    drop(db);
    let unrelated_raw = card.raw(&unrelated);
    let c = rusqlite::Connection::open(&card.path).unwrap();
    let unrelated_nf: Vec<u8> = c.query_row(
        "SELECT n.nf FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id WHERE t.txid=?1",
        [&[7u8; 32][..]], |row| row.get(0),
    ).unwrap();
    assert_eq!(
        card.cached_height(&unrelated),
        Some(u32::from(card.height + 550))
    );
    let mut later = card.spend_block(unrelated.as_ref().to_vec(), 550);
    later.vtx[0].ironwood_actions[0].nullifier = unrelated_nf;
    let (url, server, calls) = start_card_server_with_tail(
        card.first.clone(),
        card.second.clone(),
        u32::from(card.height + 600),
        true,
        vec![card.spend_block(vec![99; 32], 2), later],
    )
    .await;
    let state = card.check(&url, false).await.unwrap();
    assert!(state.complete);
    assert_eq!(state.checked_height, u32::from(card.height + 499));
    assert_eq!(card.db().chain_height().unwrap(), Some(card.height + 600));
    assert_eq!(
        card.cached_height(&stale_claim),
        Some(u32::from(card.height + 2))
    );
    let evidence = gift_card_claim::spend_evidence(&card.path, &stale_claim.to_string())
        .unwrap()
        .unwrap();
    assert!(evidence.all_funds_spent_elsewhere);
    assert!(evidence
        .conflicted_txids
        .iter()
        .any(|id| id == &hex::encode(stale_claim.as_ref())));
    assert_eq!(
        gift_card_claim::confirmations(&card.path, &stale_claim.to_string()).unwrap(),
        Some(0)
    );
    assert_eq!(
        card.cached_height(&unrelated),
        Some(u32::from(card.height + 550))
    );
    assert!(!calls
        .lock()
        .unwrap()
        .iter()
        .any(|m| m == "GetTreeState" || m == "GetBlockRange" || m == "SendTransaction"));
    assert_eq!(card.raw(&unrelated), unrelated_raw);
    server.abort();
}
