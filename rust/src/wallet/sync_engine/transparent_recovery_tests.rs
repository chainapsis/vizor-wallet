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
            path, network, &uuid, &internal, 2_000_000, 2_000_000
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
