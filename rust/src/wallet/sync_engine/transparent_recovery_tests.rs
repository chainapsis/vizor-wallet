use super::*;
use zcash_client_backend::data_api::{
    wallet::decrypt_and_store_transaction, TransactionDataRequest,
};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BranchId;

/// Whether the wallet's routed payload snapshot holds a public request for `txid`.
fn has_public_payload_work(db: &mut WalletDatabase, txid: TxId) -> bool {
    use zcash_client_backend::data_api::{
        enhance_pir::{EnhancePirRead, EnhancementMode, TransactionEnhancementWork},
        PublicTransactionEnhancementRequest,
    };
    db.set_enhancement_mode(EnhancementMode::Standard);
    db.transaction_enhancement_work()
        .unwrap()
        .contains(&TransactionEnhancementWork::Public(
            PublicTransactionEnhancementRequest::new(txid),
        ))
}

#[path = "transparent_recovery_regtest.rs"]
mod regtest;

pub(super) fn legacy_transaction(
    prevout: OutPoint,
    recipient: TransparentAddress,
    value: u64,
) -> Transaction {
    // A pre-Overwinter v1 transparent transaction. These synthetic transactions
    // exercise wallet parsing/storage; the regtest covers consensus validation.
    let mut bytes = 1u32.to_le_bytes().to_vec();
    bytes.push(1);
    bytes.extend_from_slice(prevout.hash());
    bytes.extend_from_slice(&prevout.n().to_le_bytes());
    bytes.push(0);
    bytes.extend_from_slice(&u32::MAX.to_le_bytes());
    bytes.push(1);
    bytes.extend_from_slice(&value.to_le_bytes());
    let script: Script = recipient.script().into();
    bytes.push(script.0 .0.len() as u8);
    bytes.extend_from_slice(&script.0 .0);
    bytes.extend_from_slice(&0u32.to_le_bytes());
    Transaction::read(&bytes[..], BranchId::Sprout).unwrap()
}

pub(super) fn downloaded(
    account: &str,
    tx: &Transaction,
    height: u32,
) -> DownloadedTransparentRefresh {
    DownloadedTransparentRefresh {
        refresh: TransparentRefresh {
            addresses: Vec::new(),
            start_height: BlockHeight::from_u32(0),
            label: "recovery test".into(),
            account_uuid: account.into(),
            completion: None,
        },
        outputs: vec![WalletTransparentOutput::from_parts(
            OutPoint::new(*tx.txid().as_ref(), 0),
            tx.transparent_bundle().unwrap().vout[0].clone(),
            Some(BlockHeight::from_u32(height)),
            None,
            None,
            None,
        )
        .unwrap()],
        observed_at: None,
    }
}

/// Gap 5a (H12 R): an output that a complete UTXO query of its address no
/// longer returns was spent by a transaction the wallet never saw. Reporting
/// each refresh to the library stops counting it as spendable and queues the
/// search for its spend; storing that spend then links it. A refresh is
/// reported only at the wallet's accepted tip and only under the authority
/// that made it: one observed elsewhere, or answered after a policy
/// transition, reports nothing.
#[test]
fn a_utxo_refresh_reports_an_output_spent_by_an_unseen_transaction() {
    use zcash_client_backend::data_api::transparent_ledger::{
        TransparentLedgerMode, TransparentLedgerWrite,
    };
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(path, network, &seed, Some(2_000_000), "absent").unwrap();
    let account = keys::parse_account_uuid(&uuid).unwrap();
    let encoded = keys::software_account_transparent_addresses(network, &seed, 0, 1).unwrap();
    let address = TransparentAddress::decode(&network, &encoded[0]).unwrap();
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    // The wallet accepts `height` as its tip, with a scanned block there.
    let accept = |db: &mut WalletDatabase, height: BlockHeight| -> ChainPoint {
        db.update_chain_tip(height).unwrap();
        let hash = BlockHash([u32::from(height) as u8; 32]);
        // Transparent-only fixture: no shielded witnesses above this block.
        conn.execute(
            "INSERT INTO blocks (height, hash, time, sapling_tree) VALUES (?1, ?2, 0, X'')",
            params![u32::from(height), hash.0.as_slice()],
        )
        .unwrap();
        ChainPoint { height, hash }
    };
    let tip = BlockHeight::from_u32(2_000_100);
    let at_tip = accept(&mut db, tip);
    let gate = TransparentLookupGate::for_wallet(
        enhancement::EnhancementPolicy::current(network)
            .public_transparent_lookups(&db)
            .unwrap(),
        path,
        network,
    )
    .unwrap();
    let refresh = |outputs: Vec<WalletTransparentOutput<AccountUuid>>, observed_at| {
        vec![DownloadedTransparentRefresh {
            refresh: TransparentRefresh {
                addresses: vec![encoded[0].clone()],
                start_height: BlockHeight::from_u32(2_000_000),
                label: "absence test".into(),
                account_uuid: uuid.clone(),
                completion: None,
            },
            outputs,
            observed_at,
        }]
    };
    let spendable = |db: &WalletDatabase| -> Zatoshis {
        db.get_transparent_balances(account, (tip + 2).into(), ConfirmationsPolicy::MIN)
            .unwrap()
            .values()
            .map(|balance| balance.1.spendable_value())
            .sum::<Option<Zatoshis>>()
            .unwrap()
    };
    let searched = |db: &WalletDatabase| {
        db.transaction_data_requests()
            .unwrap()
            .iter()
            .any(|request| {
                matches!(request, TransactionDataRequest::TransactionsInvolvingAddress(r)
                if r.address() == address && r.block_range_end().is_some())
            })
    };
    let report = |gate| UtxoReport { gate, network };

    // The output is returned while it is unspent.
    let funding = legacy_transaction(OutPoint::new([9; 32], 0), address, 1_000_000);
    let returned = downloaded(&uuid, &funding, 2_000_050).outputs;
    assert!(store_transparent_refreshes(
        &mut db,
        Some(report(&gate)),
        &refresh(returned, Some(at_tip))
    )
    .unwrap());
    assert_eq!(spendable(&db), Zatoshis::const_from_u64(1_000_000));

    // The next block arrives, and the output is no longer returned.
    let later = accept(&mut db, tip + 1);

    // Storing a refresh without reporting it, as before, keeps an absent
    // output spendable: nothing tells the library it disappeared.
    store_transparent_refreshes(&mut db, None, &refresh(Vec::new(), Some(later))).unwrap();
    assert_eq!(spendable(&db), Zatoshis::const_from_u64(1_000_000));

    // Nor does a refresh whose provider tip moved during the query, or one
    // observed at a tip the wallet no longer has: it speaks for no state the
    // wallet accepts. Its group is still authorized.
    for observed_at in [None, Some(at_tip)] {
        assert!(store_transparent_refreshes(
            &mut db,
            Some(report(&gate)),
            &refresh(Vec::new(), observed_at)
        )
        .unwrap());
        assert_eq!(spendable(&db), Zatoshis::const_from_u64(1_000_000));
    }

    // A refresh answered after a transition reports nothing either.
    db.apply_transparent_policy(TransparentLedgerMode::PrivateShadow)
        .unwrap();
    assert!(!store_transparent_refreshes(
        &mut db,
        Some(report(&gate)),
        &refresh(Vec::new(), Some(later))
    )
    .unwrap());
    assert_eq!(spendable(&db), Zatoshis::const_from_u64(1_000_000));

    // Reported under current authority at the wallet's tip, the absence stops
    // the output counting and queues the search for its spend.
    let renewed = TransparentLookupGate::for_wallet(
        enhancement::EnhancementPolicy::current(network)
            .public_transparent_lookups(&db)
            .unwrap(),
        path,
        network,
    )
    .unwrap();
    assert!(store_transparent_refreshes(
        &mut db,
        Some(report(&renewed)),
        &refresh(Vec::new(), Some(later))
    )
    .unwrap());
    assert_eq!(spendable(&db), Zatoshis::ZERO);
    assert!(searched(&db), "the unseen spend is searched for");

    // The search finds the spend; storing it links the output.
    let outside = TransparentAddress::PublicKeyHash([77; 20]);
    let spend = legacy_transaction(OutPoint::new(*funding.txid().as_ref(), 0), outside, 990_000);
    decrypt_and_store_transaction(
        &network,
        &mut db,
        &spend,
        Some(BlockHeight::from_u32(2_000_060)),
    )
    .unwrap();
    assert!(!searched(&db));
    assert_eq!(spendable(&db), Zatoshis::ZERO);
}

#[test]
fn pre_sapling_external_and_internal_outputs_survive_retry_and_track_external_spends() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(path, network, &seed, Some(2_000_000), "recovery")
            .unwrap();
    let account = keys::parse_account_uuid(&uuid).unwrap();
    let addresses = keys::software_account_transparent_addresses(network, &seed, 0, 1).unwrap();
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let tip = BlockHeight::from_u32(2_000_100);
    db.update_chain_tip(tip).unwrap();
    for (index, address) in addresses.iter().enumerate() {
        let tip = tip + (index as u32 * 2);
        db.update_chain_tip(tip).unwrap();
        let address = TransparentAddress::decode(&network, address).unwrap();
        let tx = legacy_transaction(OutPoint::new([index as u8 + 1; 32], 0), address, 1_000_000);
        let batches = vec![downloaded(&uuid, &tx, 100)];
        store_transparent_outputs(&mut db, &batches).unwrap();
        store_transparent_outputs(&mut db, &batches).unwrap();
        assert!(has_public_payload_work(&mut db, tx.txid()));
        // The real enhancement handler feeds the full transaction here.
        decrypt_and_store_transaction(&network, &mut db, &tx, Some(BlockHeight::from_u32(100)))
            .unwrap();
        store_transparent_outputs(&mut db, &batches).unwrap();
        assert!(
            !has_public_payload_work(&mut db, tx.txid()),
            "known transaction bytes must not be fetched again"
        );
        let spend_tip = tip + 1;
        db.update_chain_tip(spend_tip).unwrap();
        let request = db
            .transaction_data_requests()
            .unwrap()
            .into_iter()
            .find_map(|request| match request {
                TransactionDataRequest::TransactionsInvolvingAddress(request)
                    if request.address() == address =>
                {
                    Some(request)
                }
                _ => None,
            })
            .expect("recovered output must have a durable spend watch");
        assert_eq!(request.block_range_start(), tip + 1);
        let outside = TransparentAddress::PublicKeyHash([77; 20]);
        let spend = legacy_transaction(OutPoint::new(*tx.txid().as_ref(), 0), outside, 990_000);
        decrypt_and_store_transaction(&network, &mut db, &spend, Some(spend_tip)).unwrap();
        assert!(!db.transaction_data_requests().unwrap().iter().any(|request|
            matches!(request, TransactionDataRequest::TransactionsInvolvingAddress(r) if r.address() == address)));
        let conn = rusqlite::Connection::open(path).unwrap();
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM transparent_received_outputs",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(
            count,
            index as i64 + 1,
            "retry must not create duplicate outputs"
        );
        let balances = db
            .get_transparent_balances(account, (spend_tip + 1).into(), ConfirmationsPolicy::MIN)
            .unwrap();
        assert!(balances
            .values()
            .all(|balance| balance.1.spendable_value() == Zatoshis::ZERO));
    }
}

#[test]
fn rewind_invalidates_external_and_internal_completion_without_changing_birthday() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(path, network, &seed, Some(2_000_000), "rewind").unwrap();
    let external =
        keys::get_external_transparent_receive_addresses_from_db(path, network, Some(&uuid))
            .unwrap();
    let plan = transparent_receive_cache::plan_external_utxo_refresh(
        path, network, &uuid, &external, 2_000_000, 2_000_000, 20, 20,
    )
    .unwrap();
    for batch in &plan {
        transparent_receive_cache::mark_utxo_refresh_batch_complete(
            path,
            network,
            &uuid,
            &batch.child_indices,
            2_000_501,
            batch.next_sweep_offset,
        )
        .unwrap();
    }
    let internal = vec!["internal".to_string()];
    transparent_receive_cache::mark_non_external_utxo_refresh_complete(
        path, network, &uuid, &internal, 2_000_501,
    )
    .unwrap();
    invalidate_transparent_checks_before_rewind(path).unwrap();
    let plan = transparent_receive_cache::plan_external_utxo_refresh(
        path, network, &uuid, &external, 2_000_000, 2_000_000, 20, 20,
    )
    .unwrap();
    assert!(plan.iter().all(|batch| batch.start_height == 0));
    assert_eq!(
        transparent_receive_cache::plan_non_external_utxo_refresh(
            path,
            network,
            &uuid,
            &internal,
            2_000_000,
            2_000_000,
            &std::collections::HashSet::new(),
            1000
        )
        .unwrap()[0]
            .1,
        0
    );
    assert_eq!(
        account_birthday_height(path, keys::parse_account_uuid(&uuid).unwrap()).unwrap(),
        2_000_000
    );
}

#[test]
fn internal_interval_reduces_utxo_frequency_without_suppressing_spend_history() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(path, network, &seed, Some(2_000_000), "budget").unwrap();
    let account = keys::parse_account_uuid(&uuid).unwrap();
    let derived = keys::software_account_transparent_addresses(network, &seed, 0, 180).unwrap();
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let tip = BlockHeight::from_u32(2_000_100);
    db.update_chain_tip(tip).unwrap();
    let receipts: Vec<_> = derived
        .iter()
        .skip(1)
        .step_by(2)
        .enumerate()
        .map(|(i, address)| {
            let recipient = TransparentAddress::decode(&network, address).unwrap();
            legacy_transaction(OutPoint::new([i as u8 + 1; 32], 0), recipient, 1_000_000)
        })
        .collect();
    let downloaded: Vec<_> = receipts
        .iter()
        .map(|tx| downloaded(&uuid, tx, 100))
        .collect();
    store_transparent_outputs(&mut db, &downloaded).unwrap();
    for tx in &receipts {
        decrypt_and_store_transaction(&network, &mut db, tx, Some(BlockHeight::from_u32(100)))
            .unwrap();
    }
    let addresses: Vec<_> = db
        .get_transparent_receivers(account, true, true)
        .unwrap()
        .into_iter()
        .filter(|(_, metadata)| metadata.scope() == Some(TransparentKeyScope::INTERNAL))
        .map(|(address, _)| address.encode(&network))
        .collect();
    let internal: std::collections::HashSet<_> = addresses.iter().cloned().collect();
    let plan = |internal: &std::collections::HashSet<String>, height| {
        transparent_receive_cache::plan_non_external_utxo_refresh(
            path, network, &uuid, &addresses, 2_000_000, 2_000_000, internal, height,
        )
        .unwrap()
    };
    plan(&internal, 2_000_100);
    transparent_receive_cache::mark_non_external_utxo_refresh_complete(
        path, network, &uuid, &addresses, 2_000_101,
    )
    .unwrap();
    db.update_chain_tip(tip + 1).unwrap();
    let requests_before = db.transaction_data_requests().unwrap();
    let histories = requests_before
        .iter()
        // Enhancement skips unbounded requests (including unused ephemeral receivers).
        .filter(|r| {
            matches!(r, TransactionDataRequest::TransactionsInvolvingAddress(req)
            if req.block_range_end().is_some())
        })
        .count();
    assert_eq!(histories, 180);
    let baseline = plan(&std::collections::HashSet::new(), 2_000_101);
    let deferred = plan(&internal, 2_000_101);
    assert_eq!(baseline.len(), 1, "main-shaped all-address UTXO request");
    assert!(
        deferred.is_empty(),
        "internal refresh waits for 20 new blocks"
    );
    assert_eq!(
        plan(&internal, 2_000_120).len(),
        1,
        "one grouped request when due"
    );
    // These receipts are older than every query range: both policies return no
    // UTXOs and leave the same 180 address-history requests to enhancement.
    assert!(baseline
        .iter()
        .chain(&deferred)
        .all(|(_, height)| *height > 100));
    assert_eq!(
        db.transaction_data_requests().unwrap().len(),
        requests_before.len()
    );
    eprintln!("Internal interval: UTXO requests {} -> {}; address-history requests {} -> {}; combined planned requests {} -> {}",
        baseline.len(), deferred.len(), histories, histories, baseline.len()+histories, deferred.len()+histories);
    let queried: std::collections::HashSet<_> = deferred
        .iter()
        .flat_map(|(batch, _)| batch.iter())
        .collect();
    let (index, skipped) = derived
        .iter()
        .skip(1)
        .step_by(2)
        .enumerate()
        .find(|(_, address)| !queried.contains(address))
        .unwrap();
    // A skipped UTXO address still has its independent spend watch.
    assert!(requests_before.iter().any(|r| matches!(r,
        TransactionDataRequest::TransactionsInvolvingAddress(req) if req.address().encode(&network) == *skipped)));
    let spend = legacy_transaction(
        OutPoint::new(*receipts[index].txid().as_ref(), 0),
        TransparentAddress::PublicKeyHash([77; 20]),
        990_000,
    );
    decrypt_and_store_transaction(&network, &mut db, &spend, Some(tip + 1)).unwrap();
    assert!(!db.transaction_data_requests().unwrap().iter().any(|r| matches!(r,
        TransactionDataRequest::TransactionsInvolvingAddress(req) if req.address().encode(&network) == *skipped)));
}

#[test]
fn address_history_real_utxo_queue_coalesces_and_advances_after_storage() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(path, network, &seed, Some(2_000_000), "history").unwrap();
    let address =
        keys::software_account_transparent_addresses(network, &seed, 0, 1).unwrap()[0].clone();
    let address = TransparentAddress::decode(&network, &address).unwrap();
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let tip = BlockHeight::from_u32(2_000_100);
    db.update_chain_tip(tip).unwrap();
    let mut receipts = Vec::new();
    for index in 1..=10 {
        let tx = legacy_transaction(OutPoint::new([index; 32], 0), address, 1_000_000);
        store_transparent_outputs(&mut db, &[downloaded(&uuid, &tx, 100)]).unwrap();
        decrypt_and_store_transaction(&network, &mut db, &tx, Some(BlockHeight::from_u32(100)))
            .unwrap();
        receipts.push(tx);
    }
    db.update_chain_tip(tip + 1).unwrap();
    let requests = db.transaction_data_requests().unwrap();
    let count = requests.iter().filter(|r| matches!(r, TransactionDataRequest::TransactionsInvolvingAddress(r) if r.address() == address && r.block_range_end().is_some())).count();
    assert_eq!(
        count, 10,
        "real backend emits one overlapping range per receipt"
    );
    let planned = address_history::plan(&requests);
    assert_eq!(planned.len(), 1);
    assert_eq!(planned[0].len(), 1, "ten network requests become one");
    // Planning has no completion side effect; cancellation can retry the same range.
    assert_eq!(
        address_history::plan(&db.transaction_data_requests().unwrap()),
        planned
    );
    let spend = legacy_transaction(
        OutPoint::new(*receipts[0].txid().as_ref(), 0),
        TransparentAddress::PublicKeyHash([77; 20]),
        990_000,
    );
    decrypt_and_store_transaction(&network, &mut db, &spend, Some(tip + 1)).unwrap();
    let req = planned[0][0].clone();
    db.notify_address_checked(req.clone(), req.block_range_end().unwrap() - 1)
        .unwrap();
    assert!(address_history::plan(&db.transaction_data_requests().unwrap()).is_empty());
    db.update_chain_tip(tip + 2).unwrap();
    let requests = db.transaction_data_requests().unwrap();
    let remaining = requests.iter().filter(|r| matches!(r, TransactionDataRequest::TransactionsInvolvingAddress(r) if r.address() == address && r.block_range_end().is_some())).count();
    assert_eq!(remaining, 9, "the spent output is no longer watched");
    let next = address_history::plan(&requests);
    assert_eq!(next[0][0].block_range_start(), tip + 2);
}

#[tokio::test]
async fn checkpoint_drains_parent_payload_discovered_by_address_history() {
    use bytes::Bytes;
    use http_body_util::{BodyExt, Full};
    use hyper::service::service_fn;
    use prost::Message;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };
    use zcash_client_backend::proto::service::{RawTransaction, TxFilter};

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Regtest;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(path, network, &seed, Some(100), "history").unwrap();
    let address =
        keys::software_account_transparent_addresses(network, &seed, 0, 1).unwrap()[0].clone();
    let address = TransparentAddress::decode(&network, &address).unwrap();
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let receipt = legacy_transaction(OutPoint::new([1; 32], 0), address, 1_000_000);
    store_transparent_outputs(&mut db, &[downloaded(&uuid, &receipt, 100)]).unwrap();
    decrypt_and_store_transaction(
        &network,
        &mut db,
        &receipt,
        Some(BlockHeight::from_u32(100)),
    )
    .unwrap();
    db.update_chain_tip(BlockHeight::from_u32(200)).unwrap();
    assert!(!address_history::plan(&db.transaction_data_requests().unwrap()).is_empty());

    let parent_txid = [9u8; 32];
    let discovered = legacy_transaction(OutPoint::new(parent_txid, 0), address, 900_000);
    let mut discovered_bytes = Vec::new();
    discovered.write(&mut discovered_bytes).unwrap();
    let parent_calls = Arc::new(AtomicUsize::new(0));
    let parent_calls_for_server = parent_calls.clone();
    let history_calls = Arc::new(AtomicUsize::new(0));
    let history_calls_for_server = history_calls.clone();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let endpoint = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let io = hyper_util::rt::TokioIo::new(stream);
        let service = service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
            let discovered_bytes = discovered_bytes.clone();
            let parent_calls = parent_calls_for_server.clone();
            let history_calls = history_calls_for_server.clone();
            async move {
                let path = request.uri().path().to_owned();
                if path.ends_with("/GetTaddressTxids") {
                    history_calls.fetch_add(1, Ordering::SeqCst);
                    let raw = RawTransaction {
                        data: discovered_bytes,
                        height: 150,
                    };
                    let message = raw.encode_to_vec();
                    let mut frame = vec![0];
                    frame.extend_from_slice(&(message.len() as u32).to_be_bytes());
                    frame.extend_from_slice(&message);
                    return Ok::<_, std::convert::Infallible>(
                        hyper::Response::builder()
                            .header("content-type", "application/grpc")
                            .header("grpc-status", "0")
                            .body(Full::new(Bytes::from(frame)))
                            .unwrap(),
                    );
                }
                assert!(path.ends_with("/GetTransaction"));
                let body = request.into_body().collect().await.unwrap().to_bytes();
                let filter = TxFilter::decode(&body[5..]).unwrap();
                if filter.hash == parent_txid {
                    parent_calls.fetch_add(1, Ordering::SeqCst);
                }
                Ok(hyper::Response::builder()
                    .header("content-type", "application/grpc")
                    .header("grpc-status", "5")
                    .header("grpc-message", "not found")
                    .body(Full::new(Bytes::new()))
                    .unwrap())
            }
        });
        hyper::server::conn::http2::Builder::new(hyper_util::rt::TokioExecutor::new())
            .serve_connection(io, service)
            .await
            .unwrap();
    });

    let channel = tonic::transport::Endpoint::from_shared(format!("http://{endpoint}"))
        .unwrap()
        .connect()
        .await
        .unwrap();
    let mut client = CompactTxStreamerClient::new(channel);
    let _ = rustls::crypto::ring::default_provider().install_default();
    let mut enhancement = enhancement::EnhancementSession::new(network, path);
    assert!(!enhancement
        .run_checkpoint(&mut db, &mut client, None, &|| false)
        .await
        .unwrap());
    server.abort();

    assert_eq!(
        parent_calls.load(Ordering::SeqCst),
        1,
        "only routed payload recovery queries the parent; fee completion stays local"
    );
}

fn public_rewind_fixture(corrupt_cache: bool) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let birthday = 2_000_000;
    let tip = 2_000_500;
    let target = 2_000_100;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(path, network, &seed, Some(birthday), "public rewind")
            .unwrap();
    let account = keys::parse_account_uuid(&uuid).unwrap();
    let addresses = keys::software_account_transparent_addresses(network, &seed, 0, 1).unwrap();
    let internal = vec![addresses[1].clone()];
    let internal_set = internal.iter().cloned().collect();
    let external =
        keys::get_external_transparent_receive_addresses_from_db(path, network, Some(&uuid))
            .unwrap();
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.update_chain_tip(BlockHeight::from_u32(tip)).unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    // Transparent-only fixture: no shielded witnesses above these block markers.
    for height in [target, tip] {
        conn.execute(
            "INSERT INTO blocks (height, hash, time, sapling_tree) VALUES (?1, ?2, 0, X'')",
            params![height, [height as u8; 32].as_slice()],
        )
        .unwrap();
    }
    let batches: Vec<_> = addresses
        .iter()
        .enumerate()
        .map(|(index, address)| {
            let tx = legacy_transaction(
                OutPoint::new([index as u8 + 1; 32], 0),
                TransparentAddress::decode(&network, address).unwrap(),
                1_000_000,
            );
            downloaded(&uuid, &tx, 2_000_200)
        })
        .collect();
    store_transparent_outputs(&mut db, &batches).unwrap();
    let planned = transparent_receive_cache::plan_external_utxo_refresh(
        path, network, &uuid, &external, birthday, birthday, 20, 20,
    )
    .unwrap();
    for batch in planned {
        transparent_receive_cache::mark_utxo_refresh_batch_complete(
            path,
            network,
            &uuid,
            &batch.child_indices,
            u64::from(tip) + 1,
            batch.next_sweep_offset,
        )
        .unwrap();
    }
    transparent_receive_cache::mark_non_external_utxo_refresh_complete(
        path,
        network,
        &uuid,
        &internal,
        u64::from(tip) + 1,
    )
    .unwrap();
    assert!(transparent_receive_cache::plan_non_external_utxo_refresh(
        path,
        network,
        &uuid,
        &internal,
        birthday,
        birthday,
        &internal_set,
        tip.into()
    )
    .unwrap()
    .is_empty());
    drop(db);
    if corrupt_cache {
        std::fs::write(
            transparent_receive_cache::sidecar_path(path),
            b"corrupt receive cache",
        )
        .unwrap();
    }
    let result = crate::wallet::sync::rewind_to_height(path, network, target.into());
    if corrupt_cache {
        assert!(
            result.is_err(),
            "cache invalidation must fail before truncation"
        );
        let mined: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM transactions WHERE mined_height=2000200",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(
            mined, 2,
            "SQLite must remain untouched after invalidation failure"
        );
        let max_block: u32 = conn
            .query_row("SELECT MAX(height) FROM blocks", [], |r| r.get(0))
            .unwrap();
        assert_eq!(max_block, tip);
        return;
    }
    assert_eq!(result.unwrap(), u64::from(target));
    assert_eq!(account_birthday_height(path, account).unwrap(), birthday);
    let plans = transparent_receive_cache::plan_external_utxo_refresh(
        path, network, &uuid, &external, birthday, birthday, 20, 20,
    )
    .unwrap();
    assert!(plans.iter().all(|batch| batch.start_height == 0));
    let internal_plan = transparent_receive_cache::plan_non_external_utxo_refresh(
        path,
        network,
        &uuid,
        &internal,
        birthday,
        birthday,
        &internal_set,
        tip.into(),
    )
    .unwrap();
    assert_eq!(internal_plan, vec![(internal, 0)]);
    let mined: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM transactions WHERE mined_height=2000200",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(mined, 0, "rewind actually unmined the transparent receipts");
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.update_chain_tip(BlockHeight::from_u32(tip)).unwrap();
    // Replayed UTXO responses restore mined state without duplicate outputs.
    store_transparent_outputs(&mut db, &batches).unwrap();
    store_transparent_outputs(&mut db, &batches).unwrap();
    let counts: (i64,i64) = conn.query_row("SELECT COUNT(*), COUNT(t.mined_height) FROM transparent_received_outputs u JOIN transactions t ON t.id_tx=u.transaction_id", [], |r| Ok((r.get(0)?,r.get(1)?))).unwrap();
    assert_eq!(counts, (2, 2));
}

#[test]
fn public_rewind_invalidates_checks_and_recovers_outputs_without_duplicates() {
    public_rewind_fixture(false);
}

#[test]
fn public_rewind_cache_failure_leaves_sqlite_unchanged() {
    public_rewind_fixture(true);
}

#[test]
fn scan_enhancement_restores_shared_send_after_account_reimport() {
    use zcash_client_backend::proto::compact_formats::CompactBlock;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let network = WalletNetwork::Main;
    let sender_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let recipient_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (sender, _) =
        keys::init_db_and_create_account(path, network, &sender_seed, Some(2_000_000), "sender")
            .unwrap();
    keys::add_account(path, network, "recipient", &recipient_seed, Some(2_000_000)).unwrap();
    let address = |seed: &secrecy::SecretVec<u8>| {
        TransparentAddress::decode(
            &network,
            &keys::software_account_transparent_addresses(network, seed, 0, 1).unwrap()[0],
        )
        .unwrap()
    };
    let funding = legacy_transaction(OutPoint::new([42; 32], 0), address(&sender_seed), 1_000_000);
    let payment = legacy_transaction(
        OutPoint::new(*funding.txid().as_ref(), 0),
        address(&recipient_seed),
        900_000,
    );
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.update_chain_tip(BlockHeight::from_u32(2_000_100))
        .unwrap();
    store_transparent_outputs(&mut db, &[downloaded(&sender, &funding, 2_000_001)]).unwrap();
    decrypt_and_store_transaction(&network, &mut db, &funding, Some(2_000_001u32.into())).unwrap();
    decrypt_and_store_transaction(&network, &mut db, &payment, Some(2_000_010u32.into())).unwrap();
    drop(db);

    let sent_amount = |uuid: &str| -> i64 {
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.query_row(
            "SELECT COALESCE(SUM(s.value), 0) FROM sent_notes s
             JOIN accounts a ON a.id=s.from_account_id
             JOIN transactions t ON t.id_tx=s.transaction_id
             WHERE a.uuid=?1 AND t.txid=?2",
            rusqlite::params![
                uuid::Uuid::parse_str(uuid).unwrap().as_bytes().as_slice(),
                payment.txid().as_ref()
            ],
            |row| row.get(0),
        )
        .unwrap()
    };
    assert_eq!(sent_amount(&sender), 900_000);
    keys::delete_account(path, network, &sender).unwrap();
    let (reimported, _) =
        keys::add_account(path, network, "sender again", &sender_seed, Some(2_000_000)).unwrap();
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    // Rescanning first rediscovers the sender's funding input. The shared
    // payment's raw bytes survived deletion, but its sender metadata did not.
    store_transparent_outputs(&mut db, &[downloaded(&reimported, &funding, 2_000_001)]).unwrap();
    decrypt_and_store_transaction(&network, &mut db, &funding, Some(2_000_001u32.into())).unwrap();
    assert_eq!(sent_amount(&reimported), 0);
    assert!(!has_public_payload_work(&mut db, payment.txid()));

    let blocks = super::block_source::MemoryBlockSource::new(vec![CompactBlock {
        height: 2_000_010,
        // Transparent-only payments are absent from shielded compact data.
        vtx: vec![],
        ..Default::default()
    }]);
    with_wallet_db_write_lock("test.scan_enhancement", || {
        enhancement::queue_stored_transactions(path, &blocks)
    })
    .unwrap();
    assert!(has_public_payload_work(&mut db, payment.txid()));
    // The existing enhancement handler performs this operation after scanning.
    decrypt_and_store_transaction(&network, &mut db, &payment, Some(2_000_010u32.into())).unwrap();
    assert_eq!(sent_amount(&reimported), 900_000);
    assert!(!has_public_payload_work(&mut db, payment.txid()));
}

/// Phase 2 privacy boundaries: under a private transparent policy no inventoried
/// sync lane sends a transparent address, outpoint, or txid to lightwalletd.
mod private_transparent_policy {
    use super::*;
    use crate::wallet::sync_engine::test_lwd::{
        transition_on_first, transition_on_first_dispatch, CapturingLwd,
    };
    use zcash_client_backend::data_api::transparent_ledger::{
        TransparentLedgerMode, TransparentLedgerRead, TransparentLedgerWrite,
    };

    /// A wallet with a transparent receipt whose address history, parent
    /// payload, and status work are all queued as public follow-on work.
    struct Fixture {
        _dir: tempfile::TempDir,
        path: String,
        network: WalletNetwork,
        db: WalletDatabase,
        history_tx: Vec<u8>,
    }

    fn fixture() -> Fixture {
        fixture_with_receipts(1)
    }

    /// Like [`fixture`], with receipts to the first `receipts` external
    /// addresses, so address history plans that many independent addresses.
    fn fixture_with_receipts(receipts: usize) -> Fixture {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let network = WalletNetwork::Regtest;
        let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
        let (uuid, _) =
            keys::init_db_and_create_account(&path, network, &seed, Some(100), "policy").unwrap();
        let addresses: Vec<_> =
            keys::software_account_transparent_addresses(network, &seed, 0, receipts as u32)
                .unwrap()
                .iter()
                .take(receipts)
                .map(|address| TransparentAddress::decode(&network, address).unwrap())
                .collect();
        assert_eq!(addresses.len(), receipts);
        let address = addresses[0];
        let mut db = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
        for (index, recipient) in addresses.iter().enumerate() {
            let receipt = legacy_transaction(
                OutPoint::new([index as u8 + 1; 32], 0),
                *recipient,
                1_000_000,
            );
            store_transparent_outputs(&mut db, &[downloaded(&uuid, &receipt, 100)]).unwrap();
            decrypt_and_store_transaction(
                &network,
                &mut db,
                &receipt,
                Some(BlockHeight::from_u32(100)),
            )
            .unwrap();
        }
        db.update_chain_tip(BlockHeight::from_u32(200)).unwrap();
        assert!(!address_history::plan(&db.transaction_data_requests().unwrap()).is_empty());
        let discovered = legacy_transaction(OutPoint::new([9; 32], 0), address, 900_000);
        let mut history_tx = Vec::new();
        discovered.write(&mut history_tx).unwrap();
        Fixture {
            _dir: dir,
            path,
            network,
            db,
            history_tx,
        }
    }

    impl Fixture {
        /// Applies `mode` durably through a second connection, as a setting
        /// transition or a newer build would.
        fn apply(&self, mode: TransparentLedgerMode) {
            let mut other =
                open_wallet_db_with_timeout(&self.path, self.network, SYNC_DB_BUSY_TIMEOUT)
                    .unwrap();
            other.apply_transparent_policy(mode).unwrap();
        }

        fn queued_follow_on_work(&self) -> i64 {
            rusqlite::Connection::open(&self.path)
                .unwrap()
                .query_row("SELECT COUNT(*) FROM tx_retrieval_queue", [], |row| {
                    row.get(0)
                })
                .unwrap()
        }

        fn private_required_session(&self) -> enhancement::EnhancementSession {
            let policy = enhancement::EnhancementPolicy::current(self.network)
                .with_transparent_mode(TransparentLedgerMode::PrivateRequired);
            enhancement::EnhancementSession::with_policy(self.network, &self.path, policy)
        }
    }

    #[tokio::test]
    async fn checkpoint_withholds_work_queued_before_private_transition() {
        let mut f = fixture();
        let queued = f.queued_follow_on_work();
        assert!(queued > 0, "fixture queues public follow-on work");
        f.apply(TransparentLedgerMode::PrivateRequired);
        let mut lwd = CapturingLwd::start(f.history_tx.clone()).await;

        let mut session = f.private_required_session();
        assert!(!session
            .run_checkpoint(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap());
        assert!(!session
            .run_payload_recovery(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap());

        assert_eq!(lwd.requests(), Vec::<String>::new());
        assert_eq!(
            f.queued_follow_on_work(),
            queued,
            "withheld work stays durable"
        );
    }

    #[tokio::test]
    async fn restoring_public_policy_releases_withheld_work() {
        let mut f = fixture();
        f.apply(TransparentLedgerMode::PrivateRequired);
        let mut lwd = CapturingLwd::start(f.history_tx.clone()).await;
        f.private_required_session()
            .run_checkpoint(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap();
        assert!(lwd.requests().is_empty());

        f.apply(TransparentLedgerMode::Public);
        enhancement::EnhancementSession::new(f.network, &f.path)
            .run_checkpoint(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap();
        let requests = lwd.requests();
        assert!(
            requests
                .iter()
                .any(|path| path.ends_with("/GetTaddressTxids")),
            "address history resumes: {requests:?}"
        );
        assert!(
            requests
                .iter()
                .any(|path| path.ends_with("/GetTransaction")),
            "parent and payload lookups resume: {requests:?}"
        );
    }

    async fn refresh(
        f: &mut Fixture,
        lwd: &mut CapturingLwd,
    ) -> Result<TransparentRefreshSummary, SyncError> {
        let mut received = false;
        let summary = refresh_utxos(
            &mut lwd.client,
            &f.path,
            &mut f.db,
            f.network,
            enhancement::EnhancementPolicy::current(f.network),
            BlockHeight::from_u32(200),
            TransparentAccountSelection::All,
            None,
            &mut received,
            None,
            &|| false,
        )
        .await;
        assert!(!received);
        summary
    }

    #[tokio::test]
    async fn utxo_refresh_is_withheld_without_advancing_query_height() {
        let mut f = fixture();
        let accounts = f.db.get_account_ids().unwrap();
        let before = f.db.utxo_query_height(accounts[0]).unwrap();
        f.apply(TransparentLedgerMode::PrivateRequired);
        let mut lwd = CapturingLwd::start(f.history_tx.clone()).await;

        // A Public handle opened before the transition cannot operate on the
        // stricter wallet, so the refresh fails closed.
        assert!(refresh(&mut f, &mut lwd).await.is_err());
        // A handle opened after it adopts the durable policy, so the refresh
        // is withheld: it succeeds, sends nothing, and reports no balance.
        f.db = open_wallet_db_with_timeout(&f.path, f.network, SYNC_DB_BUSY_TIMEOUT).unwrap();
        assert!(refresh(&mut f, &mut lwd).await.unwrap().withheld);

        assert_eq!(lwd.requests(), Vec::<String>::new());
        assert_eq!(f.db.utxo_query_height(accounts[0]).unwrap(), before);
    }

    /// Starts a lightwalletd on which the first `rpc` request makes another
    /// connection apply `PrivateShadow`. That mode keeps public authority, so
    /// only the new generation revokes lookups captured before it.
    async fn transitioning_lwd(f: &Fixture, rpc: &'static str) -> CapturingLwd {
        CapturingLwd::start_with(
            f.history_tx.clone(),
            0,
            transition_on_first(
                rpc,
                &f.path,
                f.network,
                TransparentLedgerMode::PrivateShadow,
            ),
        )
        .await
    }

    /// Requests recorded after the first `rpc` request.
    fn requests_after_first(lwd: &CapturingLwd, rpc: &str) -> Vec<String> {
        lwd.requests()
            .into_iter()
            .skip_while(|path| !path.ends_with(rpc))
            .skip(1)
            .collect()
    }

    #[tokio::test]
    async fn transition_during_address_history_withholds_later_reads() {
        let mut f = fixture();
        let unchecked = address_history::plan(&f.db.transaction_data_requests().unwrap());
        let address = unchecked[0][0].address();
        let start = unchecked[0][0].block_range_start();
        let mut lwd = transitioning_lwd(&f, "/GetTaddressTxids").await;

        enhancement::EnhancementSession::new(f.network, &f.path)
            .run_checkpoint(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap();

        // Later operations, such as payload recovery, resolve lookups afresh
        // under the new generation; this lane must not reuse its stale ones.
        assert_eq!(lwd.count("/GetTaddressTxids"), 1);
        // The in-flight range is not acknowledged; it is retried from its start.
        let unchecked = address_history::plan(&f.db.transaction_data_requests().unwrap());
        assert!(unchecked
            .iter()
            .any(|group| group[0].address() == address && group[0].block_range_start() == start));
    }

    /// An empty range answered after the transition is not acknowledged.
    #[tokio::test]
    async fn transition_during_empty_address_history_withholds_acknowledgement() {
        let mut f = fixture();
        let unchecked = address_history::plan(&f.db.transaction_data_requests().unwrap());
        let (address, start) = (
            unchecked[0][0].address(),
            unchecked[0][0].block_range_start(),
        );
        f.history_tx.clear();
        let mut lwd = transitioning_lwd(&f, "/GetTaddressTxids").await;

        enhancement::EnhancementSession::new(f.network, &f.path)
            .run_checkpoint(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap();

        assert_eq!(lwd.count("/GetTaddressTxids"), 1);
        let unchecked = address_history::plan(&f.db.transaction_data_requests().unwrap());
        assert!(unchecked
            .iter()
            .any(|group| group[0].address() == address && group[0].block_range_start() == start));
    }

    /// The initial fill opens up to `MAX_ADDRESS_STREAMS` addresses in one poll.
    /// A transition landing between two of those opens stops every later one.
    #[tokio::test]
    async fn transition_during_address_history_fill_withholds_later_addresses() {
        let mut f = fixture_with_receipts(6);
        let planned = address_history::plan(&f.db.transaction_data_requests().unwrap()).len();
        assert!(planned > 4, "more addresses than one fill: {planned}");
        let mut lwd = CapturingLwd::start(f.history_tx.clone()).await;
        let _transition =
            transition_on_first_dispatch(&f.path, f.network, TransparentLedgerMode::PrivateShadow);

        enhancement::EnhancementSession::new(f.network, &f.path)
            .run_checkpoint(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap();

        // The authorized open may even be cancelled before it reaches the
        // wire, since the lane stops at the first withheld open.
        assert!(
            lwd.count("/GetTaddressTxids") <= 1,
            "no open is sent after the transition, even within the fill"
        );
    }

    #[tokio::test]
    async fn transition_during_public_payloads_withholds_later_requests() {
        let mut f = fixture();
        with_wallet_db_write_lock("test.queue_tx_retrieval", || {
            f.db.transactionally(|db| {
                db.queue_tx_retrieval(
                    [0x31, 0x32].map(|b| TxId::from_bytes([b; 32])).into_iter(),
                    None,
                )
            })
        })
        .unwrap();
        let queued = f.queued_follow_on_work();
        let mut lwd = transitioning_lwd(&f, "/GetTransaction").await;

        enhancement::EnhancementSession::new(f.network, &f.path)
            .run_payload_recovery(&mut f.db, &mut lwd.client, None, &|| false)
            .await
            .unwrap();

        assert_eq!(lwd.count("/GetTransaction"), 1);
        // The NotFound answered after the transition does not retire its request.
        assert_eq!(f.queued_follow_on_work(), queued);
        assert_eq!(
            requests_after_first(&lwd, "/GetTransaction"),
            Vec::<String>::new()
        );
    }

    /// A UTXO group starts up to four RPCs in one poll. A transition landing
    /// between two of them stops every later RPC and commits nothing.
    #[tokio::test]
    async fn transition_during_utxo_refresh_withholds_every_later_rpc() {
        let three_accounts = || {
            let f = fixture();
            for name in ["second", "third"] {
                let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
                keys::add_account(&f.path, f.network, name, &seed, Some(100)).unwrap();
            }
            f
        };
        let mut unrevoked = three_accounts();
        let mut lwd = CapturingLwd::start(unrevoked.history_tx.clone()).await;
        refresh(&mut unrevoked, &mut lwd).await.unwrap();
        let planned = lwd.count("/GetAddressUtxosStream");
        assert!(
            planned > MAX_CONCURRENT_TRANSPARENT_UTXO_STREAMS,
            "the fixture plans more than one group: {planned}"
        );

        let mut f = three_accounts();
        let mut lwd = CapturingLwd::start(f.history_tx.clone()).await;
        let _transition =
            transition_on_first_dispatch(&f.path, f.network, TransparentLedgerMode::PrivateShadow);
        refresh(&mut f, &mut lwd).await.unwrap();

        assert_eq!(lwd.count("/GetAddressUtxosStream"), 1);

        // The withheld group advanced no metadata, so a later pass under the
        // new generation re-covers every planned batch.
        let mut lwd = CapturingLwd::start(f.history_tx.clone()).await;
        refresh(&mut f, &mut lwd).await.unwrap();
        assert_eq!(lwd.count("/GetAddressUtxosStream"), planned);
    }

    #[test]
    fn another_connections_transition_revokes_captured_lookups() {
        let f = fixture();
        let policy = enhancement::EnhancementPolicy::current(f.network);
        let lookups = policy.public_transparent_lookups(&f.db).unwrap();
        assert!(lookups.still_allowed(&f.db).unwrap());

        // PrivateShadow keeps public authority, but a new generation still
        // revokes lookups captured under the old one.
        f.apply(TransparentLedgerMode::PrivateShadow);
        assert!(!lookups.still_allowed(&f.db).unwrap());
        let renewed = policy.public_transparent_lookups(&f.db).unwrap();
        assert!(renewed.still_allowed(&f.db).unwrap());

        // PrivateRequired revokes it too; this build's Public handle then fails
        // closed rather than resolving any authority.
        f.apply(TransparentLedgerMode::PrivateRequired);
        assert!(!matches!(renewed.still_allowed(&f.db), Ok(true)));
        assert!(!matches!(
            policy.public_transparent_lookups(&f.db),
            Ok(lookups) if lookups.is_allowed()
        ));
    }

    #[test]
    fn unconfigured_handle_fails_closed() {
        let f = fixture();
        let conn = rusqlite::Connection::open(&f.path).unwrap();
        let db: WalletDatabase = zcash_client_sqlite::WalletDb::from_connection(
            conn,
            f.network,
            zcash_client_sqlite::util::SystemClock,
            voting_crypto_deps::rand::rngs::OsRng,
        );
        assert!(db.applied_transparent_policy().is_err());
        assert!(enhancement::EnhancementPolicy::current(f.network)
            .public_transparent_lookups(&db)
            .is_err());
    }
}
