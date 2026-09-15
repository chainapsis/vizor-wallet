use super::*;
use zcash_client_backend::data_api::{
    wallet::decrypt_and_store_transaction, TransactionDataRequest,
};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BranchId;

#[path = "transparent_recovery_regtest.rs"]
mod regtest;

fn legacy_transaction(prevout: OutPoint, recipient: TransparentAddress, value: u64) -> Transaction {
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

fn downloaded(account: &str, tx: &Transaction, height: u32) -> DownloadedTransparentRefresh {
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
    }
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
        assert!(db.transaction_data_requests().unwrap().iter().any(
            |request| matches!(request, TransactionDataRequest::Enhancement(id) if id == &tx.txid())
        ));
        // The real enhancement handler feeds the full transaction here.
        decrypt_and_store_transaction(&network, &mut db, &tx, Some(BlockHeight::from_u32(100)))
            .unwrap();
        store_transparent_outputs(&mut db, &batches).unwrap();
        assert!(!db.transaction_data_requests().unwrap().iter().any(
            |request| matches!(request, TransactionDataRequest::Enhancement(id) if id == &tx.txid())
        ), "known transaction bytes must not be fetched again");
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
