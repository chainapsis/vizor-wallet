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
