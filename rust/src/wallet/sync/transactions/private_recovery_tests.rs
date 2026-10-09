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
        ReceiveEvent, SpendEvent, TransactionMetadata, TransparentDetailWrite as _,
        TransparentDisplayFacts, TransparentDisplayOutput, TransparentDisplayProvenance,
        TransparentDisplaySender, TransparentDisplayStore, TransparentLedgerMode,
        TransparentLedgerRead as _, TransparentLedgerWrite as _, WatchOrigin, WholeTransactionFee,
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
            (TransactionFeeState::Unknown, 0)
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

/// An address no account of the wallet owns.
fn foreign(byte: u8) -> TransparentAddress {
    TransparentAddress::PublicKeyHash([byte; 20])
}

/// One output of a privately recovered send.
#[derive(Clone, Copy)]
enum Paid {
    /// To someone else.
    Other(u64),
    /// Change to the account's internal address.
    Change(u64),
}

/// A transparent-only send `[tag; 32]`, built by private recovery alone.
///
/// The account's external receive `[tag - 1; 32]:0` of `funding` is input 0;
/// `foreign_input` is a second input from another wallet, which recovery
/// never sees (shared funding). Private recovery publishes the spend with its
/// whole-transaction metadata and the account's own outputs, and the private
/// display service's facts for the transaction are validated and stored as
/// loop 4 stores them. The wallet never holds the transaction itself.
fn private_send(
    tag: u8,
    funding: u64,
    foreign_input: Option<u64>,
    outputs: &[Paid],
    fee: u64,
) -> (State, AccountUuid) {
    let (mut st, account) = private_wallet();
    let ws = watch(&st, account);
    let target = ws.target.unwrap().height;
    let funder = external(&ws);
    let change = last_derived(&st, account, TransparentKeyScope::INTERNAL);
    let inputs = 1 + u32::from(foreign_input.is_some());
    let metadata = transparent_only(fee, inputs);
    let address = |paid: &Paid| match paid {
        Paid::Other(_) => foreign(0x33),
        Paid::Change(_) => change,
    };
    let value = |paid: &Paid| match *paid {
        Paid::Other(v) | Paid::Change(v) => v,
    };
    let mut receives = vec![output(
        tag - 1,
        0,
        funder,
        funding,
        target - 6,
        transparent_only(1_000, 1),
    )];
    for (index, paid) in (0u32..).zip(outputs) {
        if !matches!(paid, Paid::Other(_)) {
            receives.push(output(
                tag,
                index,
                address(paid),
                value(paid),
                target - 4,
                metadata,
            ));
        }
    }
    cover(&mut st, account, receives);
    promote(&mut st, account);

    let mut spend = commit(&watch(&st, account));
    spend.spends = vec![SpendEvent {
        metadata,
        spending_txid: TxId::from_bytes([tag; 32]),
        input_index: 0,
        prevout: OutPoint::new([tag - 1; 32], 0),
        prevout_address: funder,
        mined_height: target - 4,
    }];
    st.wallet_mut()
        .db_mut()
        .apply_transparent_ledger_commit(spend)
        .unwrap();

    // The private display service's facts, as loop 4 stores them.
    let conn = st.wallet().conn();
    conn.execute(
        "INSERT OR IGNORE INTO transparent_detail_work (transaction_id, reasons)
         SELECT id_tx, 1 FROM transactions WHERE txid = ?1",
        [[tag; 32]],
    )
    .unwrap();
    let facts = TransparentDisplayFacts {
        txid: TxId::from_bytes([tag; 32]),
        coinbase: false,
        fee: Zatoshis::const_from_u64(fee),
        input_count: inputs,
        output_count: u32::try_from(outputs.len()).unwrap(),
        shielded_components: false,
        sender: TransparentDisplaySender::Address(funder),
        outputs: outputs
            .iter()
            .take(2)
            .map(|paid| TransparentDisplayOutput {
                value: Zatoshis::const_from_u64(value(paid)),
                address: Some(address(paid)),
            })
            .collect(),
        multiple_source_scripts: foreign_input.is_some(),
        shielded_and_transparent_funding: false,
        provenance: TransparentDisplayProvenance {
            shard_id: 3,
            revision: 0,
            map_sha256: [0xaa; 32],
            looked_up_height: target - 4,
        },
    };
    let generation = st
        .wallet()
        .db()
        .applied_transparent_policy()
        .unwrap()
        .generation;
    let stored = st
        .wallet_mut()
        .db_mut()
        .store_transparent_display(facts, generation, std::time::SystemTime::now())
        .unwrap();
    assert_eq!(stored, TransparentDisplayStore::Stored);
    (st, account)
}

/// The receipt detail of `[tag; 32]` as `tx_kind`, read by Vizor's
/// production detail read over a copy of the wallet.
fn detail(st: &State, account: AccountUuid, tag: u8, tx_kind: &str) -> TransactionDetail {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    st.wallet()
        .conn()
        .execute("VACUUM INTO ?1", [&path])
        .unwrap();
    get_transaction_detail(
        &path,
        NETWORK,
        &account.expose_uuid().to_string(),
        &hex::encode([tag; 32]),
        tx_kind,
    )
    .unwrap()
}

/// Withdraws the account's settled coverage, as a later recovery run that
/// grows the address window and stops before covering the new addresses does.
fn unsettle(st: &mut State, account: AccountUuid) {
    let ws = watch(st, account);
    let target = ws.target.unwrap().height;
    let mut grow = commit(&ws);
    grow.receives = vec![output(
        0x0f,
        0,
        last_derived(st, account, TransparentKeyScope::EXTERNAL),
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
}

/// What a receipt shows of a row and its detail: the row's kind, amount,
/// amount kind (`amount_includes_fee`), fee, and completeness, and the
/// detail's recipient and completeness.
#[derive(Debug, PartialEq, Eq)]
struct Shown {
    kind: String,
    amount: u64,
    includes_fee: bool,
    fee: (TransactionFeeState, u64),
    row: (bool, bool),
    recipient: Option<String>,
    detail: (bool, bool),
}

fn shown(row: &TransactionInfo, detail: &TransactionDetail) -> Shown {
    Shown {
        kind: row.tx_kind.clone(),
        amount: row.display_amount,
        includes_fee: row.amount_includes_fee,
        fee: (row.fee_state, row.fee),
        row: (row.details_complete, row.provisional),
        recipient: detail.primary_address.clone(),
        detail: (detail.details_complete, detail.provisional),
    }
}

/// The only payee the transparent details name, and the account's own
/// output, as the detail lists them.
fn listed(detail: &TransactionDetail) -> (Option<String>, Option<String>) {
    let Some(TransparentDetailsView::Available { rows, .. }) = &detail.transparent_details else {
        panic!("the stored facts are available");
    };
    let address = |own: bool| {
        rows.iter()
            .find(|row| row.is_own == own)
            .and_then(|row| row.address.clone())
    };
    (address(false), address(true))
}

/// Private sends whose display facts account for the account's balance: one
/// with change, one without, and one that pays nobody else. Each names its
/// recipient, but only a settled one is complete: when the recovered coverage
/// stops settling the transaction, its receipt and row are provisional again,
/// whatever the balance identity says.
#[test]
fn private_sends_complete_only_once_their_effects_settle() {
    for (case, tag, outputs, payment) in [
        (
            "change",
            0x82,
            vec![Paid::Other(600_000), Paid::Change(390_000)],
            600_000,
        ),
        ("no change", 0x84, vec![Paid::Other(990_000)], 990_000),
        // Zero external payment: everything but the fee returns as change, so
        // the account's balance moved by the fee only, which is the whole
        // amount. (A return to a visible external address is a self-payment
        // shown as a send and a receive instead.)
        ("fee only", 0x86, vec![Paid::Change(990_000)], 10_000),
    ] {
        let (mut st, account) = private_send(tag, 1_000_000, None, &outputs, 10_000);
        let row = rows(&st, account, tag);
        assert_eq!(
            row.iter().map(|r| r.tx_kind.as_str()).collect::<Vec<_>>(),
            ["sent"],
            "{case}: one Activity row"
        );
        let settled = detail(&st, account, tag, "sent");
        let (payee, own) = listed(&settled);
        let recipient = if case == "fee only" { own } else { payee };
        assert!(recipient.is_some(), "{case}");
        assert!(settled.effects_settled, "{case}");
        assert_eq!(
            shown(&row[0], &settled),
            Shown {
                kind: "sent".to_owned(),
                amount: payment,
                includes_fee: case == "fee only",
                fee: (TransactionFeeState::Known, 10_000),
                row: (false, false),
                recipient: recipient.clone(),
                detail: (true, false),
            },
            "{case}: settled"
        );

        unsettle(&mut st, account);
        let row = rows(&st, account, tag);
        let unsettled = detail(&st, account, tag, "sent");
        assert!(!unsettled.effects_settled, "{case}");
        assert_eq!(
            unsettled.account_balance_delta,
            -(i64::try_from(payment).unwrap() + if case == "fee only" { 0 } else { 10_000 }),
            "{case}"
        );
        // Unsettled, the library no longer reconstructs the payment: the row
        // is the account's whole debit, a net change that keeps the fee whose
        // share is unknown.
        assert_eq!(
            shown(&row[0], &unsettled),
            Shown {
                kind: "sent".to_owned(),
                amount: unsettled.account_balance_delta.unsigned_abs(),
                includes_fee: true,
                fee: (TransactionFeeState::Unknown, 0),
                row: (false, true),
                // The facts still name the payee; nothing settles it.
                recipient,
                detail: (false, true),
            },
            "{case}: unsettled"
        );
    }
}

/// A send another wallet helped fund: the account's balance identity can
/// hold while the other funder pays an output the account cannot see, so
/// neither its row nor its receipt is ever complete, settled or not, and
/// its amount is a balance change that keeps the unattributed fee. The
/// second shape moves the account's balance by exactly zero.
#[test]
fn shared_funding_keeps_a_private_send_incomplete() {
    for (case, tag, foreign_input, outputs, delta) in [
        (
            "payment",
            0x92,
            600_000,
            vec![Paid::Other(1_000_000), Paid::Change(90_000)],
            -410_000,
        ),
        (
            "zero net movement",
            0x94,
            20_000,
            vec![Paid::Change(500_000), Paid::Other(10_000)],
            0,
        ),
    ] {
        let (mut st, account) = private_send(tag, 500_000, Some(foreign_input), &outputs, 10_000);
        for settled in [true, false] {
            if !settled {
                unsettle(&mut st, account);
            }
            let rows = rows(&st, account, tag);
            let sent = rows.iter().find(|row| row.tx_kind == "sent");
            let detail = detail(&st, account, tag, "sent");
            let Some(TransparentDetailsView::Available { omissions, .. }) =
                &detail.transparent_details
            else {
                panic!("{case}: the stored facts are available");
            };
            assert_eq!(omissions, &["shared_funding"], "{case}");
            assert_eq!(detail.account_balance_delta, delta, "{case}");
            assert_eq!(detail.primary_address, None, "{case}, settled={settled}");
            assert!(
                !detail.details_complete && detail.provisional,
                "{case}, settled={settled}"
            );
            assert_eq!(detail.network_fee, Some(10_000), "{case}: the whole fee");
            match sent {
                Some(row) => {
                    assert!(row.amount_includes_fee, "{case}: a net change");
                    assert_eq!(row.fee_state, TransactionFeeState::Unknown, "{case}");
                    assert!(
                        !row.details_complete && row.provisional,
                        "{case}, settled={settled}"
                    );
                    assert_eq!(row.display_amount, delta.unsigned_abs(), "{case}");
                }
                None => assert_eq!(delta, 0, "{case}: only a zero movement has no debit"),
            }
        }
    }
}

/// One transaction spends transparent inputs of two accounts of the same
/// wallet, both recovered privately: account A funds input 0 and receives the
/// change, account B funds input 1. Each account's view is shared funding: it
/// funded one of two inputs. Neither receipt names the payee or claims the
/// whole payment, the whole fee stays the separate network fee, and each
/// account's movement is its own share.
#[test]
fn inputs_of_two_accounts_keep_each_receipt_shared() {
    const TAG: u8 = 0xa2;
    const FEE: u64 = 10_000;
    const PAYMENT: u64 = 1_000_000;
    configure_regtest_nu6_3_activation_height(NU6_3).unwrap();
    let mut st = TestBuilder::new()
        .with_network(regtest())
        .with_data_store_factory(TestDbFactory::default())
        .with_block_cache(BlockCache::new())
        .with_account_from_sapling_activation(BlockHash([0; 32]))
        .build();
    let a = st.test_account().unwrap().id();
    // Every account is created before anything is scanned.
    let (b, _) = st.create_account_from_test_seed("second");
    scan_unrelated_blocks(&mut st, 10);
    set_policy(&mut st, TransparentLedgerMode::PrivateShadow);

    let target = watch(&st, a).target.unwrap().height;
    let funder_a = external(&watch(&st, a));
    let funder_b = external(&watch(&st, b));
    let change_a = last_derived(&st, a, TransparentKeyScope::INTERNAL);
    let metadata = transparent_only(FEE, 2);
    let (input_a, input_b, change) = (600_000, 500_000, 90_000);
    cover(
        &mut st,
        a,
        vec![
            output(
                TAG - 1,
                0,
                funder_a,
                input_a,
                target - 6,
                transparent_only(1_000, 1),
            ),
            output(TAG, 1, change_a, change, target - 4, metadata),
        ],
    );
    cover(
        &mut st,
        b,
        vec![output(
            TAG - 2,
            0,
            funder_b,
            input_b,
            target - 6,
            transparent_only(1_000, 1),
        )],
    );
    st.wallet_mut()
        .db_mut()
        .qualify_transparent_revision(&revision())
        .unwrap();
    set_policy(&mut st, TransparentLedgerMode::PrivateRequired);
    for account in [a, b] {
        st.wallet_mut()
            .db_mut()
            .promote_transparent_account(account)
            .unwrap();
    }
    for (account, input_index, prevout_tag, funder) in
        [(a, 0, TAG - 1, funder_a), (b, 1, TAG - 2, funder_b)]
    {
        let mut spend = commit(&watch(&st, account));
        spend.spends = vec![SpendEvent {
            metadata,
            spending_txid: TxId::from_bytes([TAG; 32]),
            input_index,
            prevout: OutPoint::new([prevout_tag; 32], 0),
            prevout_address: funder,
            mined_height: target - 4,
        }];
        st.wallet_mut()
            .db_mut()
            .apply_transparent_ledger_commit(spend)
            .unwrap();
    }

    // The private display service's facts, as loop 4 stores them: two
    // source scripts, a payment to someone else and A's change.
    st.wallet()
        .conn()
        .execute(
            "INSERT OR IGNORE INTO transparent_detail_work (transaction_id, reasons)
             SELECT id_tx, 1 FROM transactions WHERE txid = ?1",
            [[TAG; 32]],
        )
        .unwrap();
    let facts = TransparentDisplayFacts {
        txid: TxId::from_bytes([TAG; 32]),
        coinbase: false,
        fee: Zatoshis::const_from_u64(FEE),
        input_count: 2,
        output_count: 2,
        shielded_components: false,
        sender: TransparentDisplaySender::Address(funder_a),
        outputs: vec![
            TransparentDisplayOutput {
                value: Zatoshis::const_from_u64(PAYMENT),
                address: Some(foreign(0x33)),
            },
            TransparentDisplayOutput {
                value: Zatoshis::const_from_u64(change),
                address: Some(change_a),
            },
        ],
        multiple_source_scripts: true,
        shielded_and_transparent_funding: false,
        provenance: TransparentDisplayProvenance {
            shard_id: 3,
            revision: 0,
            map_sha256: [0xaa; 32],
            looked_up_height: target - 4,
        },
    };
    let generation = st
        .wallet()
        .db()
        .applied_transparent_policy()
        .unwrap()
        .generation;
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .store_transparent_display(facts, generation, std::time::SystemTime::now())
            .unwrap(),
        TransparentDisplayStore::Stored
    );

    for (name, account, share) in [
        ("A", a, -(input_a as i64) + change as i64),
        ("B", b, -(input_b as i64)),
    ] {
        let rows = rows(&st, account, TAG);
        let sent = rows
            .iter()
            .find(|row| row.tx_kind == "sent")
            .unwrap_or_else(|| panic!("{name}: a debit row"));
        assert!(
            rows.iter().all(|row| row.display_amount != PAYMENT),
            "{name}: no row claims the whole payment"
        );
        assert_eq!(sent.account_balance_delta, share, "{name}");
        assert_eq!(sent.display_amount, share.unsigned_abs(), "{name}");
        assert!(sent.amount_includes_fee, "{name}: a net change");
        assert_eq!(
            (sent.fee_state, sent.fee),
            (TransactionFeeState::Unknown, 0),
            "{name}: the whole fee is not the account's"
        );
        assert!(
            !sent.details_complete && sent.provisional,
            "{name}: shared attribution stays provisional"
        );

        let detail = detail(&st, account, TAG, "sent");
        let Some(TransparentDetailsView::Available { omissions, .. }) = &detail.transparent_details
        else {
            panic!("{name}: the stored facts are available");
        };
        assert_eq!(omissions, &["shared_funding"], "{name}");
        assert_eq!(detail.account_balance_delta, share, "{name}");
        assert_eq!(detail.primary_address, None, "{name}: no recipient");
        assert!(
            !detail.details_complete && detail.provisional,
            "{name}: shared attribution stays incomplete"
        );
        assert_eq!(
            detail.network_fee,
            Some(FEE),
            "{name}: the whole fee, separately"
        );
    }
}
