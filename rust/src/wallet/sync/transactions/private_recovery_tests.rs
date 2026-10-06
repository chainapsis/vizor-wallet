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
        ReceiveEvent, SpendEvent, TransactionMetadata, TransparentLedgerMode,
        TransparentLedgerWrite as _, WatchOrigin, WholeTransactionFee,
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

/// The account's watched address at `index` in `scope`.
fn derived(
    st: &State,
    account: AccountUuid,
    scope: TransparentKeyScope,
    index: u32,
) -> TransparentAddress {
    watch(st, account)
        .addresses
        .into_iter()
        .find_map(|watched| match watched.origin {
            WatchOrigin::Derived { scope: s, index: i } if s == scope && i.index() == index => {
                Some(watched.address)
            }
            _ => None,
        })
        .expect("the address is watched")
}

/// The spend of `prevout` by input `input_index` of the transaction `[tag; 32]`.
fn spend(
    tag: u8,
    input_index: u32,
    prevout: &ReceiveEvent,
    mined_height: BlockHeight,
    metadata: Option<TransactionMetadata>,
) -> SpendEvent {
    SpendEvent {
        metadata,
        spending_txid: TxId::from_bytes([tag; 32]),
        input_index,
        prevout: prevout.outpoint.clone(),
        prevout_address: prevout.address,
        mined_height,
    }
}

/// Publishes `receives` and `spends`, repeating the coverage while the
/// address window grows, as a recovery run does before it finishes.
fn publish(
    st: &mut State,
    account: AccountUuid,
    receives: Vec<ReceiveEvent>,
    spends: Vec<SpendEvent>,
) {
    let mut events = Some((receives, spends));
    loop {
        let mut c = commit(&watch(st, account));
        if let Some((receives, spends)) = events.take() {
            c.receives = receives;
            c.spends = spends;
        }
        if !st
            .wallet_mut()
            .db_mut()
            .apply_transparent_ledger_commit(c)
            .unwrap()
            .window_grew
        {
            break;
        }
    }
}

/// A copy of the wallet for Vizor's production reads.
struct Snapshot {
    _dir: tempfile::TempDir,
    path: String,
    account: String,
}

impl Snapshot {
    fn of(st: &State, account: AccountUuid) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        st.wallet()
            .conn()
            .execute("VACUUM INTO ?1", [&path])
            .unwrap();
        Self {
            _dir: dir,
            path,
            account: account.expose_uuid().to_string(),
        }
    }

    /// The Activity rows of the transaction `[tag; 32]`.
    fn rows(&self, tag: u8) -> Vec<TransactionInfo> {
        get_transaction_history(&self.path, NETWORK, None, &self.account)
            .unwrap()
            .into_iter()
            .filter(|row| row.txid_hex == hex::encode([tag; 32]))
            .collect()
    }
}

/// The Activity rows of the transaction `[tag; 32]`, read by Vizor's
/// production history over a copy of the wallet.
fn rows(st: &State, account: AccountUuid, tag: u8) -> Vec<TransactionInfo> {
    Snapshot::of(st, account).rows(tag)
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

/// Private recovery of a TEX send funded from transparent funds (H10 shape):
/// the funding step moves a coin to the account's ephemeral address, keeping
/// change, and the send spends that output to a recipient outside the
/// wallet. Activity shows one send of the payment with both legs' fees, as
/// public history may group them, and no row for the funding step. Without
/// the send, the step still shows its fee.
#[test]
fn a_privately_recovered_tex_send_folds_its_funding_step() {
    const COIN: u64 = 2_000_000;
    const TO_EPHEMERAL: u64 = 1_010_000;
    const STEP_FEE: u64 = 15_000;
    const SEND_FEE: u64 = 10_000;
    let recover = |with_send: bool| {
        let (mut st, account) = private_wallet();
        let ws = watch(&st, account);
        let target = ws.target.unwrap().height;
        let funding = output(0x81, 0, external(&ws), COIN, target - 8, None);
        cover(&mut st, account, vec![funding.clone()]);
        promote(&mut st, account);

        let step = transparent_only(STEP_FEE, 1);
        let ephemeral = output(
            0x82,
            0,
            derived(&st, account, TransparentKeyScope::EPHEMERAL, 0),
            TO_EPHEMERAL,
            target - 5,
            step,
        );
        let change = output(
            0x82,
            1,
            derived(&st, account, TransparentKeyScope::INTERNAL, 0),
            COIN - TO_EPHEMERAL - STEP_FEE,
            target - 5,
            step,
        );
        let mut spends = vec![spend(0x82, 0, &funding, target - 5, step)];
        if with_send {
            spends.push(spend(
                0x83,
                0,
                &ephemeral,
                target - 4,
                transparent_only(SEND_FEE, 1),
            ));
        }
        publish(&mut st, account, vec![ephemeral, change], spends);
        let snapshot = Snapshot::of(&st, account);
        let shape = |tag| {
            snapshot
                .rows(tag)
                .into_iter()
                .map(|row| {
                    (
                        row.tx_kind,
                        row.display_amount,
                        row.display_pool,
                        row.fee_state,
                        row.fee,
                        row.amount_is_net_change,
                    )
                })
                .collect::<Vec<_>>()
        };
        (shape(0x82), shape(0x83))
    };

    let (step, send) = recover(true);
    assert_eq!(step, [], "the funding step folds into the send");
    assert_eq!(
        send,
        [(
            "sent".into(),
            TO_EPHEMERAL - SEND_FEE,
            "transparent".into(),
            TransactionFeeState::Known,
            STEP_FEE + SEND_FEE,
            false
        )]
    );

    // Unlinked, the step is #839's zero-payment self-transfer row: its fee
    // alone, which Activity shows as "Network fee" with no pool.
    let (step, send) = recover(false);
    assert_eq!(
        step,
        [(
            "sent".into(),
            STEP_FEE,
            "transparent".into(),
            TransactionFeeState::Known,
            STEP_FEE,
            true
        )],
        "the step's fee alone, never a receipt of its intermediate output"
    );
    assert_eq!(send, []);
}
