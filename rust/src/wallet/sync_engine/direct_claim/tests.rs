use super::super::block_source::MemoryBlockSource;
use super::*;
use crate::wallet::{keys, payment_link_claim_confirmations_policy, sync::SendPurpose};
use secrecy::ExposeSecret;
use zcash_client_backend::{
    data_api::{chain::ChainState, scanning::ScanPriority},
    proto::compact_formats::{ChainMetadata, CompactBlock, CompactTx},
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{NetworkUpgrade, Parameters};

#[test]
fn funding_block_builds_a_real_claim_quote_while_historical_gaps_remain_unscanned() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("gift.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let funding_height = network.activation_height(NetworkUpgrade::Nu6_3).unwrap() + 200;
    let phrase = crate::api::wallet::generate_software_account("main".into())
        .unwrap()
        .mnemonic;
    assert_eq!(phrase.split_whitespace().count(), 12);
    let seed = keys::mnemonic_to_seed(&phrase).unwrap();
    let (account, address) =
        keys::init_db_and_create_account(path, network, &seed, None, "Gift").unwrap();
    assert_eq!(
        keys::list_accounts(path, network).unwrap()[0].birthday_height,
        u32::from(network.activation_height(NetworkUpgrade::Sapling).unwrap())
    );
    let sk = orchard::keys::SpendingKey::from_zip32_seed(
        seed.expose_secret(),
        133,
        zip32::AccountId::ZERO,
    )
    .unwrap();
    let fvk = orchard::keys::FullViewingKey::from(&sk);
    let recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
    let version = orchard::bundle::BundleVersion::ironwood_v3();
    let mut builder = orchard::builder::Builder::new(
        orchard::builder::BundleType::DEFAULT,
        version,
        version.default_flags(),
        orchard::Anchor::empty_tree(),
    )
    .unwrap();
    builder
        .add_output(
            None,
            recipient,
            orchard::value::NoteValue::from_raw(50_010_000),
            [0; 512],
        )
        .unwrap();
    let (bundle, _) = builder
        .build::<i64>(&mut voting_crypto_deps::rand::rngs::OsRng)
        .unwrap()
        .unwrap();
    let id = TxId::from_bytes([9; 32]);
    let actions = bundle.actions().iter().map(Into::into).collect::<Vec<_>>();
    let source = MemoryBlockSource::new(vec![CompactBlock {
        height: u64::from(u32::from(funding_height)),
        hash: vec![1; 32],
        prev_hash: vec![0; 32],
        time: 1_780_000_000,
        vtx: vec![CompactTx {
            index: 1,
            txid: id.as_ref().to_vec(),
            ironwood_actions: actions.clone(),
            ..Default::default()
        }],
        chain_metadata: Some(ChainMetadata {
            sapling_commitment_tree_size: 0,
            orchard_commitment_tree_size: 0,
            ironwood_commitment_tree_size: actions.len() as u32,
        }),
        ..Default::default()
    }]);
    let tip = funding_height + 5_000;
    let mut db = open_db(path, network).unwrap();
    db.update_chain_tip(tip).unwrap();
    scan_cached_blocks(
        &network,
        &source,
        &mut db,
        funding_height,
        &ChainState::empty(funding_height - 1, BlockHash([0; 32])),
        1,
    )
    .unwrap();
    validate_funding_witnesses(&mut db, id, funding_height, tip).unwrap();
    assert!(db
        .suggest_scan_ranges()
        .unwrap()
        .iter()
        .any(|r| r.priority() > ScanPriority::Scanned
            && r.block_range().contains(&(funding_height + 1))));
    // The normal SDK still requires scanning. Only the known funding tx's
    // verified witness is allowed through the event-card input source.
    let regular = db
        .select_spendable_notes(
            crate::wallet::keys::parse_account_uuid(&account).unwrap(),
            zcash_client_backend::data_api::TargetValue::AllFunds(
                zcash_client_backend::data_api::MaxSpendMode::MaxSpendable,
            ),
            &[ShieldedPool::Ironwood],
            (tip + 1).into(),
            payment_link_claim_confirmations_policy(),
            &[],
            LockFilter::Policy(&LockedInputPolicy::Exclude),
        )
        .unwrap();
    assert!(regular.ironwood().is_empty());
    assert_eq!(
        discover_funding(path, u32::from(funding_height), 50_010_000, &[id]).unwrap(),
        id
    );
    assert!(discover_funding(path, u32::from(funding_height), 50_010_001, &[id]).is_err());
    assert!(discover_funding(path, u32::from(funding_height), 50_010_000, &[]).is_err());
    save_resolution(path, u32::from(funding_height), 50_010_000, id).unwrap();
    clear(path).unwrap();
    assert_eq!(
        resolved_funding(path, u32::from(funding_height), 50_010_000).unwrap(),
        Some(id)
    );
    assert!(
        resolved_funding(path, u32::from(funding_height), 50_010_001)
            .unwrap()
            .is_none()
    );
    drop(db);
    let conn = open_wallet_raw_conn_with_timeout(path, READ_DB_BUSY_TIMEOUT).unwrap();
    // Use the SDK's real scanned-note schema and prove all locator modes read
    // the same output without opening the deliberately unreachable endpoint.
    conn.execute(
        "UPDATE ironwood_received_notes SET memo=?1 WHERE value>0",
        [b"Gift from the funding output".as_slice()],
    )
    .unwrap();
    let rt = tokio::runtime::Runtime::new().unwrap();
    let display_id = id.to_string();
    for (txid, height) in [
        (None, None),
        (Some(display_id.as_str()), None),
        (None, Some(u32::from(funding_height))),
    ] {
        assert_eq!(
            rt.block_on(super::super::gift_message::read(
                path,
                "http://127.0.0.1:9",
                network,
                &account,
                50_010_000,
                txid,
                height
            ))
            .unwrap()
            .as_deref(),
            Some("Gift from the funding output")
        );
    }
    conn.execute_batch(
        "CREATE TABLE vizor_gift_direct_claim (id INTEGER PRIMARY KEY,
        funding_txid TEXT, funding_height INTEGER, tip_height INTEGER);",
    )
    .unwrap();
    conn.execute(
        "INSERT INTO vizor_gift_direct_claim VALUES(1, ?1, ?2, ?3)",
        rusqlite::params![id.to_string(), u32::from(funding_height), u32::from(tip)],
    )
    .unwrap();
    drop(conn);
    let quote = crate::wallet::sync::estimate_send_max_for_purpose(
        path,
        network,
        &account,
        &address,
        None,
        SendPurpose::PaymentLinkClaim,
    )
    .unwrap();
    assert_eq!(quote.amount_zatoshi, 50_000_000);
    assert_eq!(quote.fee_zatoshi, 10_000);
    assert!(crate::api::sync::run_payment_link_claim_sync(
        "invalid-locator".into(),
        path.into(),
        "http://127.0.0.1:9".into(),
        "main".into(),
        false,
        Some(id.to_string()),
        Some(u32::from(funding_height)),
        Some(50_010_000)
    )
    .is_err());
    assert!(
        load(path).unwrap().is_none(),
        "invalid refresh must clear the old quote"
    );
}

#[test]
fn txid_wire_and_display_byte_orders_round_trip() {
    let id = TxId::from_bytes(std::array::from_fn(|i| i as u8));
    assert_eq!(parse_txid(&id.to_string()).unwrap(), id);
    assert!(parse_txid("bad").is_err());
}

#[test]
fn failed_and_cancelled_refreshes_invalidate_cached_preparation() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("gift.db");
    let path = path.to_str().unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    conn.execute_batch(
        "CREATE TABLE vizor_gift_direct_claim (
        id INTEGER PRIMARY KEY, funding_txid TEXT, funding_height INTEGER, tip_height INTEGER);",
    )
    .unwrap();
    let id = TxId::from_bytes([7; 32]);
    let runtime = tokio::runtime::Runtime::new().unwrap();
    for cancelled in [false, true] {
        conn.execute(
            "INSERT INTO vizor_gift_direct_claim VALUES (1, ?1, 100, 102)",
            [id.to_string()],
        )
        .unwrap();
        assert!(load(path).unwrap().is_some());
        assert!(runtime
            .block_on(prepare(
                path,
                "http://127.0.0.1:9",
                WalletNetwork::Main,
                FundingLocator::Txid(&id.to_string()),
                Arc::new(AtomicBool::new(cancelled)),
                false
            ))
            .is_err());
        assert!(load(path).unwrap().is_none());
    }
}

#[test]
fn height_discovery_rejects_ambiguous_and_split_funding() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("discovery.db");
    let path = path.to_str().unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    conn.execute_batch(
        "CREATE TABLE transactions (id_tx INTEGER, txid BLOB, mined_height INTEGER);
        CREATE TABLE sapling_received_notes (transaction_id INTEGER, value INTEGER);
        CREATE TABLE orchard_received_notes (transaction_id INTEGER, value INTEGER);
        CREATE TABLE ironwood_received_notes (transaction_id INTEGER, value INTEGER);",
    )
    .unwrap();
    let a = TxId::from_bytes([1; 32]);
    let b = TxId::from_bytes([2; 32]);
    for (index, id) in [(1, a), (2, b)] {
        conn.execute(
            "INSERT INTO transactions VALUES(?1, ?2, 500)",
            rusqlite::params![index, id.as_ref()],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes VALUES(?1, 50010000)",
            [index],
        )
        .unwrap();
    }
    assert!(discover_funding(path, 500, 50_010_000, &[a, b])
        .unwrap_err()
        .contains("ambiguous"));
    assert_eq!(discover_funding(path, 500, 50_010_000, &[a]).unwrap(), a);
    // Padding is not a second positive input. A split positive payment is.
    conn.execute_batch(
        "DELETE FROM orchard_received_notes WHERE transaction_id=2;
        INSERT INTO sapling_received_notes VALUES(1, 0);",
    )
    .unwrap();
    assert_eq!(discover_funding(path, 500, 50_010_000, &[a, b]).unwrap(), a);
    conn.execute_batch(
        "DELETE FROM orchard_received_notes;
        INSERT INTO orchard_received_notes VALUES(1, 25005000);
        INSERT INTO ironwood_received_notes VALUES(1, 25005000);",
    )
    .unwrap();
    assert!(discover_funding(path, 500, 50_010_000, &[a, b]).is_err());
}
