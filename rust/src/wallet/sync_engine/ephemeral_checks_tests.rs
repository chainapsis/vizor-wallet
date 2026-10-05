use super::*;
use std::cell::Cell;
use std::time::{Duration, SystemTime};

use zcash_client_backend::{
    data_api::{
        wallet::{decrypt_and_store_transaction, ConfirmationsPolicy},
        TransactionDataRequest,
    },
    proto::service::RawTransaction,
};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BranchId;

const TIP: u32 = 2_000_100;
const FIRST_LEG_EXPIRY: u32 = TIP - 10;

fn legacy_transaction(prevout: OutPoint, recipient: TransparentAddress, value: u64) -> Transaction {
    // Pre-Overwinter v1 transparent transaction, as in the recovery tests.
    let mut bytes = 1u32.to_le_bytes().to_vec();
    push_transparent_bundle(&mut bytes, prevout, recipient, value);
    bytes.extend_from_slice(&0u32.to_le_bytes());
    Transaction::read(&bytes[..], BranchId::Sprout).unwrap()
}

/// A v4 transparent transaction, which unlike v1 carries an expiry height.
fn expiring_transaction(
    prevout: OutPoint,
    recipient: TransparentAddress,
    value: u64,
    expiry: u32,
) -> Transaction {
    let mut bytes = (4u32 | 1 << 31).to_le_bytes().to_vec();
    bytes.extend_from_slice(&0x892F_2085u32.to_le_bytes());
    push_transparent_bundle(&mut bytes, prevout, recipient, value);
    bytes.extend_from_slice(&0u32.to_le_bytes());
    bytes.extend_from_slice(&expiry.to_le_bytes());
    bytes.extend_from_slice(&0i64.to_le_bytes());
    // No Sapling spends, Sapling outputs, or JoinSplits.
    bytes.extend_from_slice(&[0, 0, 0]);
    Transaction::read(&bytes[..], BranchId::Sapling).unwrap()
}

fn push_transparent_bundle(
    bytes: &mut Vec<u8>,
    prevout: OutPoint,
    recipient: TransparentAddress,
    value: u64,
) {
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
}

fn history(txs: Vec<RawTransaction>) -> ephemeral_checks::History {
    futures::stream::iter(txs.into_iter().map(Ok)).boxed()
}

fn raw(tx: &Transaction, height: u32) -> RawTransaction {
    let mut data = Vec::new();
    tx.write(&mut data).unwrap();
    RawTransaction {
        data,
        height: u64::from(height),
    }
}

struct Wallet {
    _dir: tempfile::TempDir,
    path: String,
    network: WalletNetwork,
    db: WalletDatabase,
    ephemeral: Vec<TransparentAddress>,
}

fn wallet() -> Wallet {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_string();
    let network = WalletNetwork::Main;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    keys::init_db_and_create_account(&path, network, &seed, Some(2_000_000), "ephemeral").unwrap();
    let mut db = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.update_chain_tip(BlockHeight::from_u32(TIP)).unwrap();
    let conn = rusqlite::Connection::open(&path).unwrap();
    let ephemeral = conn
        .prepare(
            "SELECT cached_transparent_receiver_address FROM addresses
             WHERE key_scope = 2 ORDER BY transparent_child_index",
        )
        .unwrap()
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .map(|a| TransparentAddress::decode(&network, &a.unwrap()).unwrap())
        .collect::<Vec<_>>();
    assert!(
        ephemeral.len() >= 2,
        "account creation reserves ephemeral addresses"
    );
    Wallet {
        _dir: dir,
        path,
        network,
        db,
        ephemeral,
    }
}

impl Wallet {
    /// Records the first leg of a ZIP 320 pair funding `address`.
    fn use_address(&mut self, address: TransparentAddress, n: u8) {
        let tx = legacy_transaction(OutPoint::new([n; 32], 0), address, 50_000);
        decrypt_and_store_transaction(
            &self.network,
            &mut self.db,
            &tx,
            Some(BlockHeight::from_u32(TIP - 50)),
        )
        .unwrap();
    }

    /// Records a first leg that spends a wallet output. The backend then holds
    /// its ephemeral output until it is seen unspent past the leg's expiry.
    fn fund_first_leg(&mut self, address: TransparentAddress) -> Transaction {
        let external = self.external_address();
        let funding = legacy_transaction(OutPoint::new([7; 32], 0), external, 60_000);
        decrypt_and_store_transaction(
            &self.network,
            &mut self.db,
            &funding,
            Some(BlockHeight::from_u32(TIP - 60)),
        )
        .unwrap();
        let first_leg = expiring_transaction(
            OutPoint::new(*funding.txid().as_ref(), 0),
            address,
            50_000,
            FIRST_LEG_EXPIRY,
        );
        decrypt_and_store_transaction(
            &self.network,
            &mut self.db,
            &first_leg,
            Some(BlockHeight::from_u32(TIP - 50)),
        )
        .unwrap();
        first_leg
    }

    /// Records a second leg spending `first_leg`'s ephemeral output.
    fn store_second_leg(&mut self, first_leg: &Transaction, mined: Option<u32>, expiry: u32) {
        let recipient = TransparentAddress::PublicKeyHash([0x42; 20]);
        let second_leg = expiring_transaction(
            OutPoint::new(*first_leg.txid().as_ref(), 0),
            recipient,
            40_000,
            expiry,
        );
        decrypt_and_store_transaction(
            &self.network,
            &mut self.db,
            &second_leg,
            mined.map(BlockHeight::from_u32),
        )
        .unwrap();
    }

    fn external_address(&self) -> TransparentAddress {
        let conn = rusqlite::Connection::open(&self.path).unwrap();
        let address: String = conn
            .query_row(
                "SELECT cached_transparent_receiver_address FROM addresses
                 WHERE key_scope = 0 AND cached_transparent_receiver_address IS NOT NULL
                 ORDER BY transparent_child_index LIMIT 1",
                [],
                |row| row.get(0),
            )
            .unwrap();
        TransparentAddress::decode(&self.network, &address).unwrap()
    }

    fn spendable_value(&self, address: &TransparentAddress) -> u64 {
        let account = self.db.get_account_ids().unwrap()[0];
        self.db
            .get_transparent_balances(
                account,
                BlockHeight::from_u32(TIP + 1).into(),
                ConfirmationsPolicy::MIN,
            )
            .unwrap()
            .get(address)
            .map_or(0, |(_, balance)| u64::from(balance.spendable_value()))
    }

    fn set_check_time(&self, address: &TransparentAddress, at: SystemTime) {
        let secs = at.duration_since(SystemTime::UNIX_EPOCH).unwrap().as_secs() as i64;
        let conn = rusqlite::Connection::open(&self.path).unwrap();
        let changed = conn
            .execute(
                "UPDATE addresses SET transparent_receiver_next_check_time = ?1
                 WHERE cached_transparent_receiver_address = ?2",
                rusqlite::params![secs, address.encode(&self.network)],
            )
            .unwrap();
        assert_eq!(changed, 1);
    }

    fn request_at(&self, address: &TransparentAddress) -> Option<SystemTime> {
        self.db
            .transaction_data_requests()
            .unwrap()
            .into_iter()
            .find_map(|r| match r {
                TransactionDataRequest::TransactionsInvolvingAddress(req)
                    if req.block_range_end().is_none() && req.address() == *address =>
                {
                    Some(req.request_at())
                }
                _ => None,
            })
            .expect("ephemeral check request queued")
    }

    fn received_value(&self, address: &TransparentAddress) -> i64 {
        let conn = rusqlite::Connection::open(&self.path).unwrap();
        conn.query_row(
            "SELECT COALESCE(SUM(tro.value_zat), 0) FROM transparent_received_outputs tro
             JOIN addresses a ON a.id = tro.address_id
             WHERE a.cached_transparent_receiver_address = ?1",
            [address.encode(&self.network)],
            |row| row.get(0),
        )
        .unwrap()
    }

    async fn check(
        &mut self,
        now: SystemTime,
        response: Vec<RawTransaction>,
        fetched: &Cell<Vec<(String, u64, u64)>>,
    ) -> bool {
        let mut changed = false;
        ephemeral_checks::run_with(
            &mut self.db,
            &self.path.clone(),
            self.network,
            BlockHeight::from_u32(TIP),
            now,
            &|| false,
            &mut changed,
            |address, start, end| {
                let mut calls = fetched.take();
                calls.push((address, start, end));
                fetched.set(calls);
                async move { Ok(history(response)) }
            },
        )
        .await
        .unwrap();
        changed
    }
}

#[tokio::test(flavor = "current_thread")]
async fn first_pass_schedules_without_querying() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    w.use_address(used, 1);
    assert_eq!(w.request_at(&used), None);

    let fetched = Cell::new(Vec::new());
    let now = SystemTime::now();
    assert!(!w.check(now, Vec::new(), &fetched).await);

    assert!(fetched.take().is_empty());
    let scheduled = w.request_at(&used).expect("scheduled after the pass");
    assert!(scheduled >= now && scheduled <= now + Duration::from_secs(10 * 24 * 3600));
}

#[tokio::test(flavor = "current_thread")]
async fn due_used_address_is_queried_stored_and_rescheduled() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    w.use_address(used, 1);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    let returned = legacy_transaction(OutPoint::new([9; 32], 0), used, 70_000);
    let fetched = Cell::new(Vec::new());
    assert!(w.check(now, vec![raw(&returned, TIP - 5)], &fetched).await);

    let calls = fetched.take();
    assert_eq!(calls.len(), 1, "one address per pass");
    assert_eq!(calls[0].0, used.encode(&w.network));
    assert_eq!(calls[0].2, u64::from(TIP));
    assert_eq!(w.received_value(&used), 50_000 + 70_000);
    assert!(w.request_at(&used).expect("rescheduled") > now);
}

#[tokio::test(flavor = "current_thread")]
async fn known_history_is_not_reported_as_new() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    w.use_address(used, 1);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    let first_leg = legacy_transaction(OutPoint::new([1; 32], 0), used, 50_000);
    let fetched = Cell::new(Vec::new());
    assert!(
        !w.check(now, vec![raw(&first_leg, TIP - 50)], &fetched)
            .await
    );
    assert_eq!(fetched.take().len(), 1);
    assert_eq!(w.received_value(&used), 50_000);
}

#[tokio::test(flavor = "current_thread")]
async fn never_used_addresses_are_not_queried() {
    let mut w = wallet();
    let unused = w.ephemeral[1];
    let now = SystemTime::now();
    // Give the unused address a due schedule directly.
    w.set_check_time(&unused, now - Duration::from_secs(60));

    let fetched = Cell::new(Vec::new());
    assert!(!w.check(now, Vec::new(), &fetched).await);
    assert!(fetched.take().is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn unmined_first_leg_addresses_are_not_queried() {
    let mut w = wallet();
    let stale = w.ephemeral[0];
    // A first leg stored at creation whose broadcast never mined.
    let tx = legacy_transaction(OutPoint::new([1; 32], 0), stale, 50_000);
    decrypt_and_store_transaction(&w.network, &mut w.db, &tx, None).unwrap();
    let now = SystemTime::now();
    w.set_check_time(&stale, now - Duration::from_secs(60));
    assert!(
        w.request_at(&stale).is_some(),
        "the backend still queues it"
    );

    let fetched = Cell::new(Vec::new());
    assert!(!w.check(now, Vec::new(), &fetched).await);
    assert!(fetched.take().is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn remaining_overdue_address_keeps_its_slot() {
    let mut w = wallet();
    let (a, b) = (w.ephemeral[0], w.ephemeral[1]);
    w.use_address(a, 1);
    w.use_address(b, 2);
    let now = SystemTime::now();
    w.set_check_time(&a, now - Duration::from_secs(120));
    w.set_check_time(&b, now - Duration::from_secs(60));

    let fetched = Cell::new(Vec::new());
    w.check(now, Vec::new(), &fetched).await;
    let calls = fetched.take();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].0, a.encode(&w.network), "earliest due first");
    // Rescheduling would push `b` into the future and skip its check.
    assert!(w.request_at(&b).unwrap() <= now);

    w.check(now, Vec::new(), &fetched).await;
    let calls = fetched.take();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].0, b.encode(&w.network));
    assert!(w.request_at(&a).unwrap() > now);
    assert!(w.request_at(&b).unwrap() > now);
}

#[tokio::test(flavor = "current_thread")]
async fn a_failing_address_is_deferred_behind_the_others() {
    let mut w = wallet();
    let (a, b) = (w.ephemeral[0], w.ephemeral[1]);
    w.use_address(a, 1);
    w.use_address(b, 2);
    let now = SystemTime::now();
    w.set_check_time(&a, now - Duration::from_secs(120));
    w.set_check_time(&b, now - Duration::from_secs(60));

    let path = w.path.clone();
    let mut changed = false;
    let result = ephemeral_checks::run_with(
        &mut w.db,
        &path,
        w.network,
        BlockHeight::from_u32(TIP),
        now,
        &|| false,
        &mut changed,
        |_, _, _| async { Err(SyncError::net("unavailable")) },
    )
    .await;
    assert!(result.is_err());
    assert!(!changed);
    assert!(w.request_at(&a).unwrap() > now, "failed address deferred");
    assert!(w.request_at(&b).unwrap() <= now, "next address stays due");
}

#[tokio::test(flavor = "current_thread")]
async fn exit_abandons_a_stalled_fetch_and_keeps_the_address_due() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    w.use_address(used, 1);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    // Exit is requested once the fetch has started.
    let polls = Cell::new(0);
    let should_exit = || {
        polls.set(polls.get() + 1);
        polls.get() > 1
    };
    let path = w.path.clone();
    let mut changed = false;
    let result = tokio::time::timeout(
        Duration::from_secs(5),
        ephemeral_checks::run_with(
            &mut w.db,
            &path,
            w.network,
            BlockHeight::from_u32(TIP),
            now,
            &should_exit,
            &mut changed,
            |_, _, _| std::future::pending::<Result<ephemeral_checks::History, SyncError>>(),
        ),
    )
    .await
    .expect("exit must not wait for the fetch");
    result.unwrap();
    assert!(!changed, "an exit reports nothing");
    assert!(
        w.request_at(&used).unwrap() <= now,
        "stays due for the next sync"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn each_transaction_is_stored_as_it_arrives() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    w.use_address(used, 1);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    // The stream stalls after one transaction, and exit follows.
    let returned = legacy_transaction(OutPoint::new([9; 32], 0), used, 70_000);
    let stalled = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let signal = stalled.clone();
    let stream = futures::stream::iter([Ok(raw(&returned, TIP - 5))])
        .chain(futures::stream::once(async move {
            signal.store(true, std::sync::atomic::Ordering::SeqCst);
            std::future::pending::<Result<RawTransaction, SyncError>>().await
        }))
        .boxed();
    let path = w.path.clone();
    let mut changed = false;
    let result = tokio::time::timeout(
        Duration::from_secs(5),
        ephemeral_checks::run_with(
            &mut w.db,
            &path,
            w.network,
            BlockHeight::from_u32(TIP),
            now,
            &|| stalled.load(std::sync::atomic::Ordering::SeqCst),
            &mut changed,
            move |_, _, _| async move { Ok(stream) },
        ),
    )
    .await
    .expect("exit must not wait for the stream");
    result.unwrap();
    assert!(!changed, "an exit reports nothing");
    assert_eq!(w.received_value(&used), 50_000 + 70_000);
    assert!(
        w.request_at(&used).unwrap() <= now,
        "stays due for the next sync"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_newly_recognized_output_in_a_known_transaction_is_reported() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    w.use_address(used, 1);
    // A stored transaction whose output to the address was not recognized.
    let returned = legacy_transaction(OutPoint::new([9; 32], 0), used, 70_000);
    decrypt_and_store_transaction(
        &w.network,
        &mut w.db,
        &returned,
        Some(BlockHeight::from_u32(TIP - 5)),
    )
    .unwrap();
    rusqlite::Connection::open(&w.path)
        .unwrap()
        .execute(
            "DELETE FROM transparent_received_outputs WHERE transaction_id =
                 (SELECT id_tx FROM transactions WHERE txid = ?1)",
            [returned.txid().as_ref().to_vec()],
        )
        .unwrap();
    assert_eq!(w.received_value(&used), 50_000);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    let fetched = Cell::new(Vec::new());
    assert!(w.check(now, vec![raw(&returned, TIP - 5)], &fetched).await);
    assert_eq!(w.received_value(&used), 50_000 + 70_000);
}

#[tokio::test(flavor = "current_thread")]
async fn transactions_stored_before_a_stream_error_are_reported() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    w.use_address(used, 1);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    let returned = legacy_transaction(OutPoint::new([9; 32], 0), used, 70_000);
    let stream = futures::stream::iter([
        Ok(raw(&returned, TIP - 5)),
        Err(SyncError::net("stream dropped")),
    ])
    .boxed();
    let path = w.path.clone();
    let mut changed = false;
    let result = ephemeral_checks::run_with(
        &mut w.db,
        &path,
        w.network,
        BlockHeight::from_u32(TIP),
        now,
        &|| false,
        &mut changed,
        move |_, _, _| async move { Ok(stream) },
    )
    .await;
    assert!(result.is_err());
    assert!(changed, "the stored transaction still needs a refresh");
    assert_eq!(w.received_value(&used), 50_000 + 70_000);
    assert!(
        w.request_at(&used).unwrap() > now,
        "failed address deferred"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_check_that_makes_a_first_leg_output_spendable_is_reported() {
    // The second leg was rejected, so the wallet never stored it.
    let mut w = wallet();
    let used = w.ephemeral[0];
    let first_leg = w.fund_first_leg(used);
    assert_eq!(w.spendable_value(&used), 0);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    let fetched = Cell::new(Vec::new());
    assert!(
        w.check(now, vec![raw(&first_leg, TIP - 50)], &fetched)
            .await
    );
    assert_eq!(w.spendable_value(&used), 50_000);
}

#[tokio::test(flavor = "current_thread")]
async fn a_first_leg_output_whose_stored_second_leg_expired_becomes_spendable() {
    let mut w = wallet();
    let used = w.ephemeral[0];
    let first_leg = w.fund_first_leg(used);
    w.store_second_leg(&first_leg, None, FIRST_LEG_EXPIRY);
    assert_eq!(w.spendable_value(&used), 0);
    let now = SystemTime::now();
    w.set_check_time(&used, now - Duration::from_secs(60));

    let fetched = Cell::new(Vec::new());
    assert!(
        w.check(now, vec![raw(&first_leg, TIP - 50)], &fetched)
            .await
    );
    assert_eq!(w.spendable_value(&used), 50_000);
}

#[tokio::test(flavor = "current_thread")]
async fn a_first_leg_output_a_second_leg_spent_or_can_still_spend_stays_unspendable() {
    for (mined, expiry) in [
        (None, TIP + 10),
        (None, 0),
        (Some(TIP - 40), FIRST_LEG_EXPIRY),
    ] {
        let mut w = wallet();
        let used = w.ephemeral[0];
        let first_leg = w.fund_first_leg(used);
        w.store_second_leg(&first_leg, mined, expiry);
        let now = SystemTime::now();
        w.set_check_time(&used, now - Duration::from_secs(60));

        let fetched = Cell::new(Vec::new());
        assert!(
            !w.check(now, vec![raw(&first_leg, TIP - 50)], &fetched)
                .await,
            "{mined:?} {expiry}"
        );
        assert_eq!(w.spendable_value(&used), 0, "{mined:?} {expiry}");
    }
}
