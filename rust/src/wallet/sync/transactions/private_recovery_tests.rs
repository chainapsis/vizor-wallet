//! Activity for transparent transactions recovered only by private queries.
//!
//! Each wallet is built by the library's own private recovery, as a fresh
//! `PrivateRequired` restore builds it: qualified recovery publishes the
//! account's receives and spends with their whole-transaction metadata, and
//! the wallet never holds the transactions themselves. Vizor's production
//! history read then runs over a copy of the database.

use transparent::{address::TransparentAddress, bundle::OutPoint, keys::TransparentKeyScope};
use zcash_client_backend::data_api::{
    testing::TestBuilder,
    transparent_ledger::{
        ReceiveEvent, TransactionMetadata, TransparentLedgerMode, TransparentLedgerWrite as _,
        WatchOrigin, WholeTransactionFee,
    },
};
use zcash_client_sqlite::testing::{db::TestDbFactory, BlockCache};
use zcash_primitives::block::BlockHash;
use zcash_protocol::{consensus::BlockHeight, value::Zatoshis};

use super::private_shielding_tests::{
    commit, cover, external, regtest, revision, scan_unrelated_blocks, set_policy, watch, State,
    NETWORK, NU6_3,
};
use super::*;
use crate::wallet::network::configure_regtest_nu6_3_activation_height;

/// A scanned wallet whose account private recovery may cover.
fn private_wallet() -> (State, AccountUuid) {
    configure_regtest_nu6_3_activation_height(NU6_3).unwrap();
    let mut st = TestBuilder::new()
        .with_network(regtest())
        .with_data_store_factory(TestDbFactory::default())
        .with_block_cache(BlockCache::new())
        .with_account_from_sapling_activation(BlockHash([0; 32]))
        .build();
    scan_unrelated_blocks(&mut st, 10);
    set_policy(&mut st, TransparentLedgerMode::PrivateShadow);
    let account = st.test_account().unwrap().id();
    (st, account)
}

/// Qualifies the recovered evidence and gives the account private authority.
fn promote(st: &mut State, account: AccountUuid) {
    st.wallet_mut()
        .db_mut()
        .qualify_transparent_revision(&revision())
        .unwrap();
    set_policy(st, TransparentLedgerMode::PrivateRequired);
    st.wallet_mut()
        .db_mut()
        .promote_transparent_account(account)
        .unwrap();
}

/// Metadata of a transaction with `inputs` transparent inputs, no shielded
/// components, and an exact `fee`.
fn transparent_only(fee: u64, inputs: u32) -> Option<TransactionMetadata> {
    Some(TransactionMetadata {
        fee: WholeTransactionFee::Exact(Zatoshis::const_from_u64(fee)),
        transparent_input_count: inputs,
        has_shielded_components: false,
    })
}

/// Output `index` of the transaction `[tag; 32]`, paying `value` to `address`.
fn output(
    tag: u8,
    index: u32,
    address: TransparentAddress,
    value: u64,
    mined_height: BlockHeight,
    metadata: Option<TransactionMetadata>,
) -> ReceiveEvent {
    ReceiveEvent {
        metadata,
        outpoint: OutPoint::new([tag; 32], index),
        address,
        value: Zatoshis::const_from_u64(value),
        coinbase: false,
        mined_height,
    }
}

/// The highest watched address the account derived in `scope`.
fn last_derived(
    st: &State,
    account: AccountUuid,
    scope: TransparentKeyScope,
) -> TransparentAddress {
    watch(st, account)
        .addresses
        .into_iter()
        .filter_map(|watched| match watched.origin {
            WatchOrigin::Derived { scope: s, index } if s == scope => {
                Some((index.index(), watched.address))
            }
            _ => None,
        })
        .max_by_key(|(index, _)| *index)
        .map(|(_, address)| address)
        .expect("the account derives addresses in this scope")
}

/// The Activity rows of the transaction `[tag; 32]`, read by Vizor's
/// production history over a copy of the wallet.
fn rows(st: &State, account: AccountUuid, tag: u8) -> Vec<TransactionInfo> {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    st.wallet()
        .conn()
        .execute("VACUUM INTO ?1", [&path])
        .unwrap();
    get_transaction_history(&path, NETWORK, None, &account.expose_uuid().to_string())
        .unwrap()
        .into_iter()
        .filter(|row| row.txid_hex == hex::encode([tag; 32]))
        .collect()
}

/// A receive whose recovered evidence is no longer settled stays a receive
/// with no fee: the whole fee its metadata carries is the sender's. A later
/// recovery run that grows the address window and stops before covering the
/// new addresses leaves the account's coverage unknown.
#[test]
fn an_unsettled_private_receive_never_shows_the_senders_fee() {
    let (mut st, account) = private_wallet();
    let ws = watch(&st, account);
    let target = ws.target.unwrap().height;
    cover(
        &mut st,
        account,
        vec![output(
            0x61,
            0,
            external(&ws),
            5_000_000,
            target - 4,
            transparent_only(10_000, 1),
        )],
    );
    promote(&mut st, account);

    let settled = rows(&st, account, 0x61);
    assert_eq!(settled.len(), 1);
    assert_eq!(settled[0].tx_kind, "received");
    assert_eq!(settled[0].fee_state, TransactionFeeState::NotApplicable);
    assert!(!settled[0].provisional);

    // Activity at the end of the window grows it, and the run stops there.
    let ws = watch(&st, account);
    let mut grow = commit(&ws);
    grow.receives = vec![output(
        0x62,
        0,
        last_derived(&st, account, TransparentKeyScope::EXTERNAL),
        30_000,
        target - 2,
        transparent_only(10_000, 1),
    )];
    assert!(
        st.wallet_mut()
            .db_mut()
            .apply_transparent_ledger_commit(grow)
            .unwrap()
            .window_grew
    );

    let unsettled = rows(&st, account, 0x61);
    assert_eq!(unsettled.len(), 1);
    let row = &unsettled[0];
    assert_eq!(row.tx_kind, "received");
    assert!(row.provisional, "the coverage no longer settles it");
    assert_eq!(row.display_amount, 5_000_000);
    assert_eq!(
        (row.fee_state, row.fee),
        (TransactionFeeState::Unknown, 0),
        "the sender's fee is never shown on a receive"
    );
}

/// Private coverage is real; shielded financial rows are synthetic compact-scan
/// facts. No construction record, raw payload, or sent-note attribution exists.
#[test]
fn settled_mixed_activity_does_not_inherit_incomplete_payment_details() {
    for (owned_receipt, outgoing) in [(250_000, 250_000), (0, 200_000)] {
        let (mut st, account) = private_wallet();
        let ws = watch(&st, account);
        let target = ws.target.unwrap().height;
        let metadata = Some(TransactionMetadata {
            fee: WholeTransactionFee::Exact(Zatoshis::const_from_u64(15_000)),
            transparent_input_count: 0,
            has_shielded_components: true,
        });
        cover(
            &mut st,
            account,
            if owned_receipt == 0 {
                vec![]
            } else {
                vec![output(
                    0x71,
                    0,
                    external(&ws),
                    owned_receipt,
                    target - 4,
                    metadata,
                )]
            },
        );
        promote(&mut st, account);
        let conn = st.wallet().conn();
        let account_id: i64 = conn
            .query_row(
                "SELECT id FROM accounts WHERE uuid = ?1",
                [account.expose_uuid().as_bytes()],
                |r| r.get(0),
            )
            .unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index, fee)
            VALUES (?1, ?2, ?2, 0, 15000)
            ON CONFLICT(txid) DO UPDATE SET fee = 15000",
            rusqlite::params![[0x71u8; 32], u32::from(target - 4)],
        )
        .unwrap();
        let tx: i64 = conn
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                [[0x71u8; 32]],
                |r| r.get(0),
            )
            .unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index) VALUES (?1, ?2, ?2, 0)",
            rusqlite::params![[0x70u8; 32], u32::from(target - 5)],
        )
        .unwrap();
        let funding = conn.last_insert_rowid();
        for (transaction, value, change) in [
            (funding, 1_000_000 + outgoing + 15_000, false),
            (tx, 1_000_000, true),
        ] {
            conn.execute(
                "INSERT INTO ironwood_received_notes (transaction_id, action_index,
                account_id, diversifier, value, rho, rseed, is_change, note_version)
                VALUES (?1, 0, ?2, zeroblob(11), ?3, zeroblob(32), zeroblob(32), ?4, 3)",
                rusqlite::params![transaction, account_id, value, change],
            )
            .unwrap();
        }
        conn.execute(
            "INSERT INTO ironwood_received_note_spends (ironwood_received_note_id, transaction_id)
            SELECT id, ?1 FROM ironwood_received_notes WHERE transaction_id = ?2",
            [tx, funding],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO ironwood_enhance_routing (transaction_id, route, has_transparent_outputs)
            VALUES (?1, 2, 1)",
            [tx],
        )
        .unwrap();

        let settled = rows(&st, account, 0x71);
        assert_eq!(settled.len(), if owned_receipt == 0 { 1 } else { 2 });
        assert_eq!(settled[0].tx_kind, "sent");
        assert_eq!(settled[0].display_amount, outgoing);
        if owned_receipt != 0 {
            assert_eq!(settled[1].tx_kind, "received");
            assert_eq!(settled[1].display_amount, owned_receipt);
        }
        assert!(settled
            .iter()
            .all(|row| !row.provisional && !row.details_complete));
        assert!(settled.iter().all(|row| row.display_pool == "transparent"));
        assert!(settled
            .iter()
            .all(|row| row.account_balance_delta
                == -(outgoing as i64) - 15_000 + owned_receipt as i64));
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        conn.execute("VACUUM INTO ?1", [&path]).unwrap();
        let detail = get_transaction_detail(
            &path,
            NETWORK,
            &account.expose_uuid().to_string(),
            &hex::encode([0x71; 32]),
            "sent",
        )
        .unwrap();
        assert!(detail.provisional);
        assert!(!detail.details_complete);
        assert!(detail.primary_address.is_none());
        assert!(
            detail.outputs.is_empty(),
            "no recipient attribution is invented"
        );
        assert_eq!(
            (settled[0].fee_state, settled[0].fee),
            (TransactionFeeState::Known, 15_000)
        );
        assert!(!settled[0].amount_includes_fee);

        // Growing the recovery window withdraws settled coverage, even though
        // the shielded residual is still available. The warning must return.
        let ws = watch(&st, account);
        let mut grow = commit(&ws);
        grow.receives = vec![output(
            0x72,
            0,
            last_derived(&st, account, TransparentKeyScope::EXTERNAL),
            30_000,
            target - 2,
            transparent_only(10_000, 1),
        )];
        assert!(
            st.wallet_mut()
                .db_mut()
                .apply_transparent_ledger_commit(grow)
                .unwrap()
                .window_grew
        );
        assert!(rows(&st, account, 0x71).iter().all(|row| row.provisional));
    }
}
