//! Regression tests for independent status and payload obligations. Exercise
//! public writes, not just queue SQL helpers.
use rusqlite::params;
use zcash_client_backend::data_api::status::TransactionStatusRead;
use zcash_client_backend::data_api::{
    TransactionStatus, WalletRead, WalletWrite,
    enhance_pir::EnhancePirRead,
    testing::{TestBuilder, TestState},
    wallet::decrypt_and_store_transaction,
};
use zcash_primitives::{
    block::BlockHash,
    transaction::{Authorized, TransactionData, TxId, TxVersion},
};
use zcash_protocol::{
    consensus::{BlockHeight, BranchId},
    local_consensus::LocalNetwork,
};

use crate::{
    error::SqliteClientError,
    testing::{
        BlockCache,
        db::{TestDb, TestDbFactory},
    },
};

type State = TestState<BlockCache, TestDb, LocalNetwork>;

fn fixture() -> (State, BlockHeight) {
    let mut st = TestBuilder::new()
        .with_data_store_factory(TestDbFactory::file_backed())
        .with_block_cache(BlockCache::new())
        .with_account_from_sapling_activation(BlockHash([0; 32]))
        .build();
    let (height, _) = st.generate_empty_block();
    st.scan_cached_blocks(height, 1);
    (st, height)
}

fn queue_both(st: &State, txid: TxId, height: BlockHeight, raw: Option<&[u8]>) {
    st.wallet()
        .conn()
        .execute(
            "INSERT INTO transactions (txid, expiry_height, min_observed_height, raw)
         VALUES (?1, 0, ?2, ?3)",
            params![txid.as_ref(), u32::from(height), raw],
        )
        .unwrap();
    for query_type in [0, 1] {
        st.wallet()
            .conn()
            .execute(
                "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, ?2)",
                params![txid.as_ref(), query_type],
            )
            .unwrap();
    }
}

fn queued(st: &State, txid: TxId, query_type: i64) -> bool {
    st.wallet()
        .conn()
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM tx_retrieval_queue WHERE txid = ?1 AND query_type = ?2)",
            params![txid.as_ref(), query_type],
            |row| row.get(0),
        )
        .unwrap()
}

/// Whether `txid` has payload work routed to public transport.
fn payload_pending(st: &State, txid: TxId) -> bool {
    st.wallet()
        .transaction_enhancement_work()
        .unwrap()
        .contains(&crate::testing::public_work(txid))
}

#[test]
fn typed_requests_follow_independent_status_and_payload_lifecycles() {
    let (mut st, height) = fixture();
    let txid = TxId::from_bytes([71; 32]);
    queue_both(&st, txid, height, None);

    assert!(
        st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|work| work.txid() == txid)
    );
    assert!(payload_pending(&st, txid));
    assert!(
        st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|request| request.txid() == txid)
    );
    assert!(payload_pending(&st, txid));

    st.wallet_mut()
        .set_transaction_status(txid, TransactionStatus::Mined(height))
        .unwrap();
    assert!(
        !st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|request| request.txid() == txid)
    );
    assert!(payload_pending(&st, txid));

    st.wallet_mut()
        .notify_transaction_enhancement_not_found(txid)
        .unwrap();
    assert!(!payload_pending(&st, txid));
}

#[test]
fn every_status_preserves_payload_work_even_with_stored_bytes() {
    let (mut st, height) = fixture();
    for (i, status) in [
        TransactionStatus::TxidNotRecognized,
        TransactionStatus::NotInMainChain,
        TransactionStatus::Mined(height),
    ]
    .into_iter()
    .enumerate()
    {
        for (j, raw) in [None, Some(&[42][..])].into_iter().enumerate() {
            let txid = TxId::from_bytes([(i * 2 + j) as u8; 32]);
            queue_both(&st, txid, height, raw);
            st.wallet_mut()
                .set_transaction_status(txid, status)
                .unwrap();
            st.wallet_mut()
                .set_transaction_status(txid, status)
                .unwrap();
            assert!(queued(&st, txid, 1));
            assert!(queued(&st, txid, 0));
            let stored: Option<Vec<u8>> = st
                .wallet()
                .conn()
                .query_row(
                    "SELECT raw FROM transactions WHERE txid = ?1",
                    [txid.as_ref()],
                    |row| row.get(0),
                )
                .unwrap();
            assert_eq!(stored.as_deref(), raw);
        }
    }
}

#[test]
fn terminal_status_only_retires_status_work() {
    let (mut st, height) = fixture();
    let txid = TxId::from_bytes([9; 32]);
    queue_both(&st, txid, height, None);
    st.wallet()
        .conn()
        .execute(
            "UPDATE transactions SET expiry_height = ?1 WHERE txid = ?2",
            params![u32::from(height), txid.as_ref()],
        )
        .unwrap();
    st.wallet_mut()
        .set_transaction_status(txid, TransactionStatus::TxidNotRecognized)
        .unwrap();
    assert!(!queued(&st, txid, 0));
    assert!(queued(&st, txid, 1));
    st.wallet_mut()
        .notify_transaction_enhancement_not_found(txid)
        .unwrap();
    assert!(!queued(&st, txid, 1));
}

#[test]
fn explicit_payload_not_found_is_independent_idempotent_and_allows_rediscovery() {
    let (mut st, height) = fixture();
    let txid = TxId::from_bytes([10; 32]);
    queue_both(&st, txid, height, None);
    for _ in 0..2 {
        st.wallet_mut()
            .notify_transaction_enhancement_not_found(txid)
            .unwrap();
        assert!(!queued(&st, txid, 1));
        assert!(queued(&st, txid, 0));
        let status: (Option<u32>, Option<u32>) = st.wallet().conn().query_row(
            "SELECT mined_height, confirmed_unmined_at_height FROM transactions WHERE txid = ?1",
            [txid.as_ref()], |row| Ok((row.get(0)?, row.get(1)?)),
        ).unwrap();
        assert_eq!(status, (None, None));
    }
    let tx = st.wallet().conn().unchecked_transaction().unwrap();
    super::queue_tx_retrieval(&tx, std::iter::once(txid), None).unwrap();
    tx.commit().unwrap();
    assert!(queued(&st, txid, 1));
    st.wallet_mut()
        .set_transaction_status(txid, TransactionStatus::NotInMainChain)
        .unwrap();
    assert!(
        queued(&st, txid, 1),
        "a late status response cannot erase rediscovery"
    );
    // Parent lookup requests need not have a transaction row yet.
    let unknown = TxId::from_bytes([11; 32]);
    let tx = st.wallet().conn().unchecked_transaction().unwrap();
    super::queue_tx_retrieval(&tx, std::iter::once(unknown), None).unwrap();
    tx.commit().unwrap();
    st.wallet_mut()
        .notify_transaction_enhancement_not_found(unknown)
        .unwrap();
    assert!(!queued(&st, unknown, 1));
}

#[test]
fn explicit_payload_not_found_preserves_pir_routes_in_every_feature_build() {
    let (mut st, height) = fixture();
    for route in [0i64, 1] {
        let txid = TxId::from_bytes([20 + route as u8; 32]);
        queue_both(&st, txid, height, None);
        st.wallet()
            .conn()
            .execute(
                "INSERT INTO ironwood_enhance_routing (transaction_id, route)
             SELECT id_tx, ?2 FROM transactions WHERE txid = ?1",
                params![txid.as_ref(), route],
            )
            .unwrap();
        st.wallet_mut()
            .notify_transaction_enhancement_not_found(txid)
            .unwrap();
        assert!(queued(&st, txid, 1));
        assert!(queued(&st, txid, 0));
    }
}

#[test]
fn failed_transaction_rolls_back_payload_completion_and_status() {
    let (mut st, height) = fixture();
    let txid = TxId::from_bytes([30; 32]);
    queue_both(&st, txid, height, None);
    let result: Result<(), SqliteClientError> = st.wallet_mut().db_mut().transactionally(|db| {
        db.notify_transaction_enhancement_not_found(txid)?;
        db.set_transaction_status(txid, TransactionStatus::NotInMainChain)?;
        Err(SqliteClientError::CorruptedData("test rollback".into()))
    });
    assert!(result.is_err());
    assert!(queued(&st, txid, 1));
    assert!(queued(&st, txid, 0));
    let observed: Option<u32> = st
        .wallet()
        .conn()
        .query_row(
            "SELECT confirmed_unmined_at_height FROM transactions WHERE txid = ?1",
            [txid.as_ref()],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(observed, None);
}

#[test]
fn successful_payload_ingestion_preserves_status_in_both_response_orders() {
    for status_first in [false, true] {
        let (mut st, height) = fixture();
        let transaction = TransactionData::<Authorized>::from_parts(
            TxVersion::V5,
            BranchId::Nu5,
            0,
            height,
            None,
            None,
            None,
            None,
        )
        .freeze()
        .unwrap();
        let txid = transaction.txid();
        queue_both(&st, txid, height, None);
        let params = *st.network();
        if status_first {
            st.wallet_mut()
                .set_transaction_status(txid, TransactionStatus::NotInMainChain)
                .unwrap();
            assert!(queued(&st, txid, 1));
        }
        // An irrelevant but valid payload completes enhancement too.
        decrypt_and_store_transaction(&params, st.wallet_mut(), &transaction, None).unwrap();
        if !status_first {
            st.wallet_mut()
                .set_transaction_status(txid, TransactionStatus::NotInMainChain)
                .unwrap();
        }
        assert!(!queued(&st, txid, 1));
        assert!(queued(&st, txid, 0));
    }
}

#[test]
fn rewind_reactivates_mined_status_without_completing_enhancement() {
    let (mut st, prior_height) = fixture();
    let (mined_height, _) = st.generate_empty_block();
    st.scan_cached_blocks(mined_height, 1);
    let txid = TxId::from_bytes([40; 32]);
    queue_both(&st, txid, prior_height, None);
    st.wallet_mut()
        .set_transaction_status(txid, TransactionStatus::Mined(mined_height))
        .unwrap();
    assert!(queued(&st, txid, 0));
    assert!(
        !st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|work| work.txid() == txid)
    );
    st.wallet_mut()
        .db_mut()
        .truncate_to_height(prior_height)
        .unwrap();
    assert!(
        st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|work| work.txid() == txid)
    );
    assert!(payload_pending(&st, txid));
}

/// The routed payload snapshot never carries status work, and status responses and rewinds
/// never change payload routing.
#[cfg(feature = "orchard")]
#[test]
fn routed_enhancement_work_is_independent_of_status_lifecycle() {
    use zcash_client_backend::data_api::enhance_pir::{
        EnhancementMode, TransactionEnhancementWork,
    };

    let (mut st, prior_height) = fixture();
    let (mined_height, _) = st.generate_empty_block();
    st.scan_cached_blocks(mined_height, 1);
    let ordinary = TxId::from_bytes([50; 32]);
    let protected = TxId::from_bytes([51; 32]);
    queue_both(&st, ordinary, prior_height, None);
    queue_both(&st, protected, prior_height, None);
    st.wallet()
        .conn()
        .execute(
            "INSERT INTO ironwood_enhance_routing (transaction_id, route)
             SELECT id_tx, 0 FROM transactions WHERE txid = ?1",
            params![protected.as_ref()],
        )
        .unwrap();
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);

    let public = |st: &State| {
        let mut txids = st
            .wallet()
            .db()
            .transaction_enhancement_work()
            .unwrap()
            .into_iter()
            .map(|work| match work {
                TransactionEnhancementWork::Public(request) => request.txid(),
                TransactionEnhancementWork::Private(work) => {
                    panic!("no private work was queued: {work:?}")
                }
            })
            .collect::<Vec<_>>();
        txids.sort();
        txids
    };
    let statuses = |st: &State| {
        st.wallet()
            .transaction_status_work()
            .unwrap()
            .into_iter()
            .map(|request| request.txid())
            .filter(|txid| [ordinary, protected].contains(txid))
            .count()
    };
    assert_eq!(public(&st), vec![ordinary]);
    assert_eq!(
        statuses(&st),
        2,
        "status routing ignores private protection"
    );

    for txid in [ordinary, protected] {
        st.wallet_mut()
            .set_transaction_status(txid, TransactionStatus::Mined(mined_height))
            .unwrap();
    }
    assert_eq!(statuses(&st), 0);
    assert_eq!(public(&st), vec![ordinary]);

    st.wallet_mut()
        .db_mut()
        .truncate_to_height(prior_height)
        .unwrap();
    assert_eq!(statuses(&st), 2);
    assert_eq!(public(&st), vec![ordinary]);

    st.wallet_mut()
        .notify_transaction_enhancement_not_found(ordinary)
        .unwrap();
    assert!(public(&st).is_empty());
    assert_eq!(statuses(&st), 2);
}

fn private_bound(st: &State, txid: TxId) -> Option<BlockHeight> {
    use zcash_client_backend::data_api::status::TransactionStatusWork;
    match st.wallet().transaction_status_work_for(txid).unwrap() {
        TransactionStatusWork::Private(request) => request.earliest_possible_inclusion(),
        _ => panic!("expected private work"),
    }
}

#[test]
fn status_policy_is_explicit_and_unknown_evidence_stays_private() {
    use zcash_client_backend::data_api::status::{TransactionStatusMode, TransactionStatusWork};
    let (mut st, height) = fixture();
    let discovery = st.wallet().transaction_data_requests().unwrap();
    let imported = TxId::from_bytes([81; 32]);
    let queue_only = TxId::from_bytes([82; 32]);
    queue_both(&st, imported, height, None);
    st.wallet()
        .conn()
        .execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 0)",
            [queue_only.as_ref()],
        )
        .unwrap();
    st.wallet_mut()
        .db_mut()
        .set_status_mode(TransactionStatusMode::Private);
    assert_eq!(private_bound(&st, imported), None);
    assert_eq!(private_bound(&st, queue_only), None);
    let work = st.wallet().transaction_status_work().unwrap();
    assert_eq!(work.len(), 2);
    for item in work {
        assert!(matches!(item, TransactionStatusWork::Private(_)));
        assert_eq!(
            item,
            st.wallet()
                .transaction_status_work_for(item.txid())
                .unwrap()
        );
    }
    assert_eq!(st.wallet().transaction_data_requests().unwrap(), discovery);
    st.wallet_mut()
        .db_mut()
        .transactionally(|db| {
            assert!(matches!(
                db.transaction_status_work_for(imported)?,
                TransactionStatusWork::Private(_)
            ));
            Ok::<_, SqliteClientError>(())
        })
        .unwrap();
    let db = crate::WalletDb::from_connection(st.wallet().conn(), *st.network(), (), ());
    assert!(matches!(
        db.transaction_status_work(),
        Err(SqliteClientError::StatusModeNotConfigured)
    ));
    assert!(matches!(
        db.transaction_status_work_for(imported),
        Err(SqliteClientError::StatusModeNotConfigured)
    ));
    let db = db.with_status_mode(TransactionStatusMode::Private);
    assert_eq!(
        db.transaction_status_work().unwrap(),
        st.wallet().transaction_status_work().unwrap()
    );
}

#[test]
fn local_creation_evidence_survives_existing_rows_ingestion_reopen_and_rewind() {
    use zcash_client_backend::data_api::{Account, SentTransaction, status::TransactionStatusMode};
    use zcash_protocol::value::Zatoshis;
    let (mut st, prior) = fixture();
    let (height, _) = st.generate_empty_block();
    st.scan_cached_blocks(height, 1);
    st.wallet_mut()
        .db_mut()
        .set_status_mode(TransactionStatusMode::Private);
    let transaction = TransactionData::<Authorized>::from_parts(
        TxVersion::V5,
        BranchId::Nu5,
        0,
        height + 100,
        None,
        None,
        None,
        None,
    )
    .freeze()
    .unwrap();
    let txid = transaction.txid();
    queue_both(&st, txid, height, None);
    assert_eq!(private_bound(&st, txid), None);
    let account = st.test_account().unwrap().id();
    let sent = SentTransaction::new(
        &transaction,
        time::OffsetDateTime::UNIX_EPOCH,
        (height + 1).into(),
        account,
        &[],
        Zatoshis::ZERO,
        #[cfg(feature = "transparent-inputs")]
        &[],
    );
    let result = st.wallet_mut().db_mut().transactionally(|db| {
        db.store_transactions_to_be_sent(&[sent])?;
        Err::<(), _>(SqliteClientError::CorruptedData("rollback".into()))
    });
    assert!(result.is_err());
    assert_eq!(private_bound(&st, txid), None);
    let store = |st: &mut State| {
        st.wallet_mut()
            .store_transactions_to_be_sent(&[SentTransaction::new(
                &transaction,
                time::OffsetDateTime::UNIX_EPOCH,
                (height + 1).into(),
                account,
                &[],
                Zatoshis::ZERO,
                #[cfg(feature = "transparent-inputs")]
                &[],
            )])
            .unwrap();
    };
    store(&mut st);
    assert_eq!(private_bound(&st, txid), Some(height));
    let params = *st.network();
    decrypt_and_store_transaction(&params, st.wallet_mut(), &transaction, None).unwrap();
    assert_eq!(private_bound(&st, txid), Some(height));
    st.wallet_mut()
        .set_transaction_status(txid, TransactionStatus::Mined(height))
        .unwrap();
    st.wallet_mut().db_mut().truncate_to_height(prior).unwrap();
    assert_eq!(private_bound(&st, txid), Some(prior));
    store(&mut st);
    assert_eq!(private_bound(&st, txid), Some(prior));
    let reopened = rusqlite::Connection::open(st.wallet().conn().path().unwrap()).unwrap();
    let db = crate::WalletDb::from_connection(reopened, params, (), ())
        .with_status_mode(TransactionStatusMode::Private);
    assert_eq!(
        db.transaction_status_work_for(txid).unwrap(),
        st.wallet().transaction_status_work_for(txid).unwrap()
    );
}

#[test]
fn outbox_evidence_is_atomic_and_does_not_enqueue_or_raise_bounds() {
    use zcash_client_backend::data_api::status::{TransactionStatusMode, TransactionStatusWrite};
    let (mut st, height) = fixture();
    st.wallet_mut()
        .db_mut()
        .set_status_mode(TransactionStatusMode::Private);
    let txid = TxId::from_bytes([93; 32]);
    let result = st.wallet_mut().db_mut().transactionally(|db| {
        db.record_transaction_created(txid, height)?;
        Err::<(), _>(SqliteClientError::CorruptedData("rollback outbox".into()))
    });
    assert!(result.is_err());
    assert_eq!(private_bound(&st, txid), None);
    st.wallet_mut()
        .db_mut()
        .record_transaction_created(txid, height)
        .unwrap();
    assert_eq!(private_bound(&st, txid), Some(height));
    assert!(!queued(&st, txid, 0));
    assert!(!queued(&st, txid, 1));
    st.wallet_mut()
        .db_mut()
        .record_transaction_created(txid, height - 1)
        .unwrap();
    st.wallet_mut()
        .db_mut()
        .record_transaction_created(txid, height + 50)
        .unwrap();
    assert_eq!(private_bound(&st, txid), Some(height - 1));
}

#[test]
fn sent_creation_without_chain_tip_rolls_back() {
    use zcash_client_backend::data_api::{Account, SentTransaction};
    use zcash_protocol::value::Zatoshis;
    let (mut st, height) = fixture();
    st.wallet()
        .conn()
        .execute("DELETE FROM scan_queue", [])
        .unwrap();
    let transaction = TransactionData::<Authorized>::from_parts(
        TxVersion::V5,
        BranchId::Nu5,
        0,
        height + 100,
        None,
        None,
        None,
        None,
    )
    .freeze()
    .unwrap();
    let account = st.test_account().unwrap().id();
    let result = st
        .wallet_mut()
        .store_transactions_to_be_sent(&[SentTransaction::new(
            &transaction,
            time::OffsetDateTime::UNIX_EPOCH,
            (height + 50).into(),
            account,
            &[],
            Zatoshis::ZERO,
            #[cfg(feature = "transparent-inputs")]
            &[],
        )]);
    assert!(matches!(result, Err(SqliteClientError::ChainHeightUnknown)));
    assert_eq!(
        st.wallet()
            .conn()
            .query_row(
                "SELECT COUNT(*) FROM transactions WHERE txid = ?1",
                [transaction.txid().as_ref()],
                |row| row.get::<_, u32>(0),
            )
            .unwrap(),
        0
    );
}

#[test]
fn status_evidence_rewind_uses_rescan_floor_even_without_scanned_suffix() {
    use std::collections::HashSet;
    use zcash_client_backend::data_api::{
        chain::ChainState,
        status::{TransactionStatusMode, TransactionStatusWrite},
    };
    let (mut st, floor) = fixture();
    let tip = floor + 100;
    st.wallet_mut().update_chain_tip(tip).unwrap();
    st.wallet_mut()
        .db_mut()
        .set_status_mode(TransactionStatusMode::Private);
    let local = TxId::from_bytes([94; 32]);
    let imported = TxId::from_bytes([95; 32]);
    st.wallet_mut()
        .db_mut()
        .record_transaction_created(local, tip)
        .unwrap();
    queue_both(&st, imported, tip, None);
    st.wallet_mut()
        .rewind_to_chain_state(ChainState::empty(floor, BlockHash([0; 32])), HashSet::new())
        .unwrap();
    assert_eq!(private_bound(&st, local), Some(floor));
    assert_eq!(private_bound(&st, imported), None);
    st.wallet_mut()
        .rewind_to_chain_state(
            ChainState::empty(floor + 1, BlockHash([0; 32])),
            HashSet::new(),
        )
        .unwrap();
    assert_eq!(private_bound(&st, local), Some(floor));
}

#[test]
fn status_evidence_truncation_uses_rescan_floor_below_retained_checkpoint() {
    use zcash_client_backend::data_api::status::{TransactionStatusMode, TransactionStatusWrite};
    let (mut st, floor) = fixture();
    let (checkpoint, _) = st.generate_empty_block();
    st.scan_cached_blocks(checkpoint, 1);
    st.wallet_mut()
        .db_mut()
        .set_status_mode(TransactionStatusMode::Private);
    let txid = TxId::from_bytes([96; 32]);
    st.wallet_mut()
        .db_mut()
        .record_transaction_created(txid, checkpoint)
        .unwrap();
    let params = *st.network();
    let mut conn = rusqlite::Connection::open(st.wallet().conn().path().unwrap()).unwrap();
    let tx = conn.transaction().unwrap();
    super::truncate_to_height_internal(
        &tx,
        &params,
        #[cfg(feature = "transparent-inputs")]
        &crate::GapLimits::default(),
        checkpoint,
        floor,
    )
    .unwrap();
    tx.commit().unwrap();
    assert_eq!(private_bound(&st, txid), Some(floor));
}

#[test]
fn expiry_dormancy_preserves_obligations_and_reactivates_after_rewind() {
    use zcash_client_backend::data_api::status::TransactionStatusMode;

    for mode in [
        TransactionStatusMode::Public,
        TransactionStatusMode::Private,
    ] {
        let (mut st, height) = fixture();
        st.wallet_mut().db_mut().set_status_mode(mode);
        let unknown = TxId::from_bytes([201; 32]);
        let legacy = TxId::from_bytes([202; 32]);
        let never = TxId::from_bytes([203; 32]);
        let unknown_expiry = TxId::from_bytes([204; 32]);
        let large_expiry = TxId::from_bytes([205; 32]);
        let missing = TxId::from_bytes([206; 32]);
        for txid in [unknown, legacy, never, unknown_expiry, large_expiry] {
            queue_both(&st, txid, height, None);
        }
        // Place the boundary one block above the current contiguous scan height.
        let expiry = u32::from(height) + 1 - crate::PRUNING_DEPTH;
        st.wallet()
            .conn()
            .execute(
                "UPDATE transactions SET expiry_height = ?1 WHERE txid IN (?2, ?3)",
                params![expiry, unknown.as_ref(), legacy.as_ref()],
            )
            .unwrap();
        st.wallet().conn().execute(
            "UPDATE transactions SET target_height = ?1, min_observed_height = 0 WHERE txid = ?2",
            params![u32::from(height), legacy.as_ref()],
        ).unwrap();
        st.wallet()
            .conn()
            .execute(
                "UPDATE transactions SET expiry_height = NULL WHERE txid = ?1",
                [unknown_expiry.as_ref()],
            )
            .unwrap();
        st.wallet()
            .conn()
            .execute(
                "UPDATE transactions SET expiry_height = ?1 WHERE txid = ?2",
                params![u32::MAX, large_expiry.as_ref()],
            )
            .unwrap();
        st.wallet()
            .conn()
            .execute(
                "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 0)",
                [missing.as_ref()],
            )
            .unwrap();
        let active = |st: &State, txid| {
            st.wallet()
                .transaction_status_work()
                .unwrap()
                .iter()
                .any(|work| work.txid() == txid)
        };
        let evidence = [unknown, legacy, never]
            .map(|txid| st.wallet().transaction_status_work_for(txid).unwrap());
        assert!(active(&st, unknown));
        assert!(active(&st, legacy));
        for _ in 0..2 {
            let (next, _) = st.generate_empty_block();
            st.scan_cached_blocks(next, 1);
            for txid in [unknown, legacy] {
                assert!(!active(&st, txid));
                assert!(queued(&st, txid, 0));
                assert!(payload_pending(&st, txid));
                let confirmed: Option<u32> = st
                    .wallet()
                    .conn()
                    .query_row(
                        "SELECT confirmed_unmined_at_height FROM transactions WHERE txid = ?1",
                        [txid.as_ref()],
                        |row| row.get(0),
                    )
                    .unwrap();
                assert_eq!(confirmed, None);
            }
            for txid in [never, unknown_expiry, large_expiry, missing] {
                assert!(active(&st, txid));
            }
        }
        for (txid, expected) in [unknown, legacy, never].into_iter().zip(evidence) {
            assert_eq!(
                st.wallet().transaction_status_work_for(txid).unwrap(),
                expected
            );
        }
        let reopened = rusqlite::Connection::open(st.wallet().conn().path().unwrap()).unwrap();
        let db = crate::WalletDb::from_connection(reopened, *st.network(), (), ())
            .with_status_mode(mode);
        assert_eq!(
            db.transaction_status_work().unwrap(),
            st.wallet().transaction_status_work().unwrap()
        );
        st.wallet_mut().db_mut().truncate_to_height(height).unwrap();
        assert!(active(&st, unknown));
        assert!(active(&st, legacy));
        assert!(queued(&st, unknown, 0));
        assert!(payload_pending(&st, unknown));
    }
}

#[test]
fn expiry_dormancy_requires_contiguous_scanning() {
    let (mut st, height) = fixture();
    let txid = TxId::from_bytes([207; 32]);
    queue_both(&st, txid, height, None);
    st.wallet()
        .conn()
        .execute(
            "UPDATE transactions SET expiry_height = ?1 WHERE txid = ?2",
            params![u32::from(height) + 1 - crate::PRUNING_DEPTH, txid.as_ref()],
        )
        .unwrap();
    let (gap, _) = st.generate_empty_block();
    let (later, _) = st.generate_empty_block();
    st.scan_cached_blocks(later, 1);
    assert_eq!(
        super::fully_scanned_height(st.wallet().conn()).unwrap(),
        Some(height)
    );
    assert!(
        st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|w| w.txid() == txid)
    );
    st.scan_cached_blocks(gap, 1);
    assert!(
        !st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|w| w.txid() == txid)
    );
    // With no established scan progress, even an old expiry must stay actionable.
    st.wallet()
        .conn()
        .execute(
            "UPDATE scan_queue SET priority = ?1",
            [super::priority_code(&super::ScanPriority::Historic)],
        )
        .unwrap();
    assert_eq!(
        super::fully_scanned_height(st.wallet().conn()).unwrap(),
        None
    );
    assert!(
        st.wallet()
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|w| w.txid() == txid)
    );
}
