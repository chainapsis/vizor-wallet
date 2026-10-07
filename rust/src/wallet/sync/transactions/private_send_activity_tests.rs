//! Activity for a freshly restored shielded send with transparent outputs.
//!
//! A sender wallet builds the reported mainnet shape as a real transaction:
//! one Ironwood note of 107,485,000 zatoshis pays 250,000 to a transparent
//! address and returns 107,220,000 as Ironwood change, with a 15,000 fee. Two
//! wallets restored from the same seed then recover it. The private one does
//! what a fresh `PrivateRequired` restore does: compact scanning finds the
//! spend and the change, private transparent recovery covers the account
//! (optionally publishing its receipt of its own transparent output), and
//! Enhance PIR applies the service's records, which assert transparent
//! outputs. The public one stores the full transaction. Vizor's production
//! history read then runs over a copy of each database.

use transparent::{address::TransparentAddress, bundle::OutPoint};
use zcash_client_backend::{
    data_api::{
        enhance_pir::{
            EnhancePirBatchResult, EnhancePirRead as _, EnhancePirWork, EnhancePirWrite as _,
            EnhanceRecord, EnhanceRecordParts, EnhanceTransactionMetadata, EnhancementMode,
            TransactionEnhancementWork,
        },
        testing::{
            orchard::OrchardPoolTester, pool::ShieldedPoolTester, single_output_change_strategy,
            AddressType, IronwoodFvk, TestBuilder,
        },
        transparent_ledger::{ReceiveEvent, TransparentLedgerMode, TransparentLedgerWrite as _},
        wallet::{
            decrypt_and_store_transaction, input_selection::GreedyInputSelector,
            ConfirmationsPolicy,
        },
    },
    fees::StandardFeeRule,
    wallet::OvkPolicy,
    zip321::{Payment, TransactionRequest},
};
use zcash_client_sqlite::testing::{db::TestDbFactory, BlockCache};
use zcash_keys::address::Address;
use zcash_primitives::{block::BlockHash, transaction::Transaction};
use zcash_protocol::{consensus::BlockHeight, ShieldedPool};

use super::private_shielding_tests::{
    cover, external, regtest, revision, scan_unrelated_blocks, set_policy, watch, zat, State,
    NETWORK, NU6_3,
};
use super::*;
use crate::wallet::network::configure_regtest_nu6_3_activation_height;

const SPENT: u64 = 107_485_000;
const CHANGE: u64 = 107_220_000;
const SENT: u64 = 250_000;
const FEE: u64 = 15_000;

/// A wallet holding the account's single compact-scanned Ironwood note of
/// `SPENT`. Every wallet built this way holds the same chain and note: the
/// test builder is deterministic, and `prepare` generates no blocks.
fn funded(prepare: impl FnOnce(&mut State)) -> State {
    configure_regtest_nu6_3_activation_height(NU6_3).unwrap();
    let mut st = TestBuilder::new()
        .with_network(regtest())
        .with_data_store_factory(TestDbFactory::default())
        .with_block_cache(BlockCache::new())
        .with_account_from_sapling_activation(BlockHash([0; 32]))
        .build();
    scan_unrelated_blocks(&mut st, 10);
    prepare(&mut st);
    let fvk = IronwoodFvk(OrchardPoolTester::test_account_fvk(&st));
    let (height, _, _) = st.generate_next_block(&fvk, AddressType::DefaultExternal, zat(SPENT));
    st.scan_cached_blocks(height, 1);
    st
}

fn own_transparent(st: &State) -> TransparentAddress {
    external(&watch(st, st.test_account().unwrap().id()))
}

/// The reported transaction, built by a sender wallet holding the same note:
/// 250,000 to the account's own first external transparent address.
fn reported_transaction() -> Transaction {
    sent_transaction(None, SENT)
}

/// The external send that follows the reported one: 200,000 to a transparent
/// address no wallet account holds.
const EXTERNAL_SENT: u64 = 200_000;

/// A transaction spending the funded note to pay `value` to `to`, or to the
/// account's own first external transparent address.
fn sent_transaction(to: Option<TransparentAddress>, value: u64) -> Transaction {
    let mut st = funded(|st| set_policy(st, TransparentLedgerMode::Public));
    let to = Address::from(to.unwrap_or_else(|| own_transparent(&st)));
    let request = TransactionRequest::new(vec![Payment::without_memo(
        to.to_zcash_address(st.network()),
        zat(value),
    )])
    .unwrap();
    let account = st.test_account().cloned().unwrap();
    let proposal = st
        .propose_transfer(
            account.id(),
            &GreedyInputSelector::new(),
            &single_output_change_strategy(StandardFeeRule::Zip317, None, ShieldedPool::Orchard),
            request,
            ConfirmationsPolicy::MIN,
        )
        .unwrap();
    assert_eq!(
        proposal.steps().head.balance().fee_required(),
        zat(FEE),
        "the reported fee"
    );
    let txid = *st
        .create_proposed_transactions::<std::convert::Infallible, _, std::convert::Infallible, _>(
            account.usk(),
            OvkPolicy::Sender,
            &proposal,
        )
        .unwrap()
        .first();
    st.wallet().get_transaction(txid).unwrap().unwrap()
}

/// A database copy for Vizor's reads, and the recovered transaction.
struct Restored {
    _dir: tempfile::TempDir,
    path: String,
    account: AccountUuid,
    txid_hex: String,
}

/// Mines `tx` in a restored wallet's chain and compact-scans it. `recover`
/// then runs the restore's own recovery; the result is copied for Vizor.
fn restore(
    tx: &Transaction,
    prepare: impl FnOnce(&mut State),
    recover: impl FnOnce(&mut State, BlockHeight),
) -> Restored {
    let mut st = funded(prepare);
    let account = st.test_account().unwrap().id();
    let (height, _) = st.generate_next_block_from_tx(1, tx);
    st.scan_cached_blocks(height, 1);
    scan_unrelated_blocks(&mut st, 2);
    recover(&mut st, height);

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    st.wallet()
        .conn()
        .execute("VACUUM INTO ?1", [&path])
        .unwrap();
    Restored {
        _dir: dir,
        path,
        account,
        txid_hex: hex::encode(tx.txid().as_ref()),
    }
}

/// The service's record for one Ironwood action of `tx`: its ciphertexts and
/// value commitment, the assertion of transparent outputs, and the fee.
fn record(tx: &Transaction, index: u32) -> EnhanceRecord {
    let action = &tx.ironwood_bundle().unwrap().actions()[usize::try_from(index).unwrap()];
    let note = action.encrypted_note();
    EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: note.enc_ciphertext[52..].try_into().unwrap(),
        cv_net: action.cv_net().to_bytes(),
        out_ciphertext: note.out_ciphertext,
        has_transparent_inputs: false,
        has_transparent_outputs: true,
        metadata: EnhanceTransactionMetadata::new(u32::from(tx.expiry_height()), Some(FEE))
            .unwrap(),
    })
}

/// A fresh private restore. With `own_output`, private transparent recovery
/// publishes the account's receipt of the transaction's transparent output.
fn privately_restored(tx: &Transaction, own_output: bool) -> Restored {
    restore(
        tx,
        |st| set_policy(st, TransparentLedgerMode::PrivateShadow),
        |st, height| {
            let account = st.test_account().unwrap().id();
            let receives = if own_output {
                let vout = &tx.transparent_bundle().unwrap().vout;
                let index = vout.iter().position(|o| o.value() == zat(SENT)).unwrap();
                vec![ReceiveEvent {
                    metadata: None,
                    outpoint: OutPoint::new(tx.txid().into(), u32::try_from(index).unwrap()),
                    address: own_transparent(st),
                    value: zat(SENT),
                    coinbase: false,
                    mined_height: height,
                }]
            } else {
                vec![]
            };
            cover(st, account, receives);
            st.wallet_mut()
                .db_mut()
                .qualify_transparent_revision(&revision())
                .unwrap();
            set_policy(st, TransparentLedgerMode::PrivateRequired);
            st.wallet_mut()
                .db_mut()
                .promote_transparent_account(account)
                .unwrap();
            st.wallet_mut()
                .db_mut()
                .set_enhancement_mode(EnhancementMode::PrivateIronwood);

            let records: Vec<_> = st
                .wallet()
                .transaction_enhancement_work()
                .unwrap()
                .into_iter()
                .filter_map(|work| match work {
                    TransactionEnhancementWork::Private(EnhancePirWork::Query(request))
                        if request.request_id().txid() == tx.txid() =>
                    {
                        Some((request, record(tx, request.request_id().output_index())))
                    }
                    TransactionEnhancementWork::Public(_) => {
                        panic!("no public GetTransaction under PrivateRequired")
                    }
                    _ => None,
                })
                .collect();
            assert!(!records.is_empty());
            assert!(matches!(
                st.wallet_mut()
                    .db_mut()
                    .apply_ironwood_enhance_records(&records)
                    .unwrap(),
                EnhancePirBatchResult::Committed(_)
            ));
            let raw: bool = st
                .wallet()
                .conn()
                .query_row(
                    "SELECT raw IS NOT NULL FROM transactions WHERE txid = ?1",
                    [tx.txid().as_ref()],
                    |row| row.get(0),
                )
                .unwrap();
            assert!(!raw, "private recovery never stores the full transaction");
        },
    )
}

/// The same chain restored publicly: the full transaction is stored.
fn publicly_restored(tx: &Transaction) -> Restored {
    restore(
        tx,
        |st| set_policy(st, TransparentLedgerMode::Public),
        |st, height| {
            let network = *st.network();
            decrypt_and_store_transaction(&network, st.wallet_mut(), tx, Some(height)).unwrap();
        },
    )
}

/// The transaction's Activity rows, sends first.
fn activity(restored: &Restored) -> Vec<TransactionInfo> {
    let mut rows: Vec<_> = get_transaction_history(
        &restored.path,
        NETWORK,
        None,
        &restored.account.expose_uuid().to_string(),
    )
    .unwrap()
    .into_iter()
    .filter(|row| row.txid_hex == restored.txid_hex)
    .collect();
    rows.sort_by_key(|row| row.tx_kind != "sent");
    rows
}

/// The rendered values of a row, without chain-specific identifiers.
fn display_values(row: &TransactionInfo) -> serde_json::Value {
    serde_json::json!({
        "txKind": row.tx_kind,
        "displayAmount": row.display_amount,
        "displayPool": row.display_pool,
        "activityPool": row.activity_pool,
        "accountBalanceDelta": row.account_balance_delta,
        "fee": row.fee,
        "feeState": format!("{:?}", row.fee_state),
        "detailsComplete": row.details_complete,
        "provisional": row.provisional,
        "amountIncludesFee": row.amount_includes_fee,
        "isTransparent": row.is_transparent,
        "expiredUnmined": row.expired_unmined,
    })
}

/// What the desktop Activity rows show: kind, amount and pool label.
fn shown(row: &TransactionInfo) -> (&str, u64, &str) {
    (
        &row.tx_kind,
        row.display_amount,
        row.activity_pool.as_deref().unwrap_or(&row.display_pool),
    )
}

/// Shared with the desktop Activity tests, which render exactly these values.
/// Regenerate with `VIZOR_UPDATE_FIXTURES=1`.
const DISPLAY_FIXTURE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../test/fixtures/private_send_activity.json"
);

/// The reported transaction: privately recovered Activity shows the same
/// sent amount, title and pool as the public restore (Sent 250,000 from a
/// transparent output), the 15,000 network fee beside it, and the account's
/// receipt of its own transparent output where private recovery found it.
/// The private rows stay provisional with incomplete details.
#[test]
fn a_privately_restored_send_shows_the_public_sent_amount() {
    let tx = reported_transaction();
    let public = activity(&publicly_restored(&tx));
    assert_eq!(
        public.iter().map(shown).collect::<Vec<_>>(),
        vec![
            ("sent", SENT, "transparent"),
            ("received", SENT, "transparent")
        ]
    );
    assert!(public
        .iter()
        .all(|row| row.fee_state == TransactionFeeState::Known && row.fee == FEE));

    let owned_restore = privately_restored(&tx, true);
    let owned = activity(&owned_restore);
    let without_transparent = activity(&privately_restored(&tx, false));
    assert_eq!(
        owned.iter().map(shown).collect::<Vec<_>>(),
        public.iter().map(shown).collect::<Vec<_>>(),
        "a known receipt keeps its receive row"
    );
    assert_eq!(
        without_transparent.iter().map(shown).collect::<Vec<_>>(),
        vec![shown(&public[0])],
        "the send alone, with no transparent rows"
    );
    for row in owned.iter().chain(&without_transparent) {
        assert_eq!(row.fee_state, TransactionFeeState::Known);
        assert_eq!(row.fee, FEE, "the whole network fee is shown");
        assert!(!row.amount_includes_fee, "the amount excludes the fee");
        assert!(row.provisional, "attribution is not completed");
        assert!(!row.details_complete, "recipients stay unknown");
    }
    assert_eq!(owned[0].account_balance_delta, -(FEE as i64));
    assert_eq!(
        without_transparent[0].account_balance_delta,
        -((SPENT - CHANGE) as i64)
    );
    let detail = get_transaction_detail(
        &owned_restore.path,
        NETWORK,
        &owned_restore.account.expose_uuid().to_string(),
        &owned_restore.txid_hex,
        "sent",
    )
    .unwrap();
    assert!(detail.outputs.is_empty(), "no recipient is claimed");
    assert!(!detail.details_complete);

    let displayed = serde_json::json!({
        "public": public.iter().map(display_values).collect::<Vec<_>>(),
        "private": owned.iter().map(display_values).collect::<Vec<_>>(),
        "privateWithoutTransparentRows":
            without_transparent.iter().map(display_values).collect::<Vec<_>>(),
    });
    if std::env::var_os("VIZOR_UPDATE_FIXTURES").is_some() {
        std::fs::write(
            DISPLAY_FIXTURE,
            serde_json::to_string_pretty(&displayed).unwrap() + "\n",
        )
        .unwrap();
    }
    let fixture: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(DISPLAY_FIXTURE).unwrap()).unwrap();
    assert_eq!(displayed, fixture, "desktop fixture is stale");
}

/// A transparent address no wallet account holds.
fn foreign_transparent() -> TransparentAddress {
    TransparentAddress::PublicKeyHash([7; 20])
}

/// The neighbouring external send of the reported wallet (public Activity:
/// Sent 0.002 ZEC; private before the fix: Sent 0.00215 ZEC including the
/// fee) takes the same inference: privately it shows the public Sent amount,
/// pool and fee, and no receive row, since no owned output exists.
#[test]
fn a_privately_restored_external_send_shows_the_public_sent_amount() {
    let tx = sent_transaction(Some(foreign_transparent()), EXTERNAL_SENT);
    let public = activity(&publicly_restored(&tx));
    assert_eq!(
        public.iter().map(shown).collect::<Vec<_>>(),
        vec![("sent", EXTERNAL_SENT, "transparent")]
    );
    let private = activity(&privately_restored(&tx, false));
    assert_eq!(
        private.iter().map(shown).collect::<Vec<_>>(),
        public.iter().map(shown).collect::<Vec<_>>()
    );
    let row = &private[0];
    assert_eq!((row.fee_state, row.fee), (TransactionFeeState::Known, FEE));
    assert_eq!(
        (public[0].fee_state, public[0].fee),
        (TransactionFeeState::Known, FEE)
    );
    assert!(!row.amount_includes_fee);
    assert!(row.provisional);
    assert!(!row.details_complete);
    assert_eq!(row.account_balance_delta, -((EXTERNAL_SENT + FEE) as i64));
}

/// Opt-in, read-only diagnostic of the Activity rows Vizor's production
/// history read produces for selected transactions of a local wallet
/// snapshot. The snapshot is copied before it is read, and only the selected
/// rows' display values are printed: no addresses, keys, or memos.
///
/// ```sh
/// VIZOR_ACTIVITY_PARITY_DB=/path/wallet.db VIZOR_ACTIVITY_PARITY_ACCOUNT=<account uuid> \
/// VIZOR_ACTIVITY_PARITY_TXID=<txid hex>[,<txid hex>...] [VIZOR_ACTIVITY_PARITY_NETWORK=main] \
/// cargo test --lib activity_parity_diagnostic -- --ignored --nocapture
/// ```
#[test]
#[ignore = "reads the local wallet snapshot named by VIZOR_ACTIVITY_PARITY_DB"]
fn activity_parity_diagnostic() {
    let path = std::env::var("VIZOR_ACTIVITY_PARITY_DB").expect("VIZOR_ACTIVITY_PARITY_DB");
    let account =
        std::env::var("VIZOR_ACTIVITY_PARITY_ACCOUNT").expect("VIZOR_ACTIVITY_PARITY_ACCOUNT");
    let txids: Vec<String> = std::env::var("VIZOR_ACTIVITY_PARITY_TXID")
        .expect("VIZOR_ACTIVITY_PARITY_TXID")
        .split(',')
        .map(|txid| txid.trim().to_lowercase())
        .filter(|txid| !txid.is_empty())
        .collect();
    assert!(!txids.is_empty(), "select at least one transaction");
    let network = WalletNetwork::from_str(
        &std::env::var("VIZOR_ACTIVITY_PARITY_NETWORK").unwrap_or_else(|_| "main".to_owned()),
    )
    .expect("VIZOR_ACTIVITY_PARITY_NETWORK is main, test, or regtest");
    {
        let dir = tempfile::tempdir().unwrap();
        let copy = dir.path().join("snapshot.db");
        rusqlite::Connection::open_with_flags(&path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .unwrap()
            .execute("VACUUM INTO ?1", [copy.to_str().unwrap()])
            .unwrap();
        let rows = get_transaction_history(copy.to_str().unwrap(), network, None, &account)
            .unwrap_or_else(|e| panic!("history read failed: {e}"));
        for row in rows.iter().filter(|row| txids.contains(&row.txid_hex)) {
            println!(
                "{} kind={} displayAmount={} displayPool={} activityPool={:?} fee={} \
                 feeState={:?} amountIncludesFee={} provisional={} detailsComplete={} \
                 isTransparent={} mined={} expiredUnmined={}",
                row.txid_hex,
                row.tx_kind,
                row.display_amount,
                row.display_pool,
                row.activity_pool,
                row.fee,
                row.fee_state,
                row.amount_includes_fee,
                row.provisional,
                row.details_complete,
                row.is_transparent,
                row.mined_height > 0,
                row.expired_unmined,
            );
        }
    }
}
