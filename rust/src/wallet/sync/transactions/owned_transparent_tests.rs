//! Public/private production history comparisons for recovered owned transfer legs.
use super::private_shielding_tests::{
    cover, regtest, revision, scan_unrelated_blocks, set_policy, watch, zat, State,
};
use super::*;
use crate::wallet::network::configure_regtest_nu6_3_activation_height;
use std::convert::Infallible;
use transparent::{bundle::OutPoint, keys::TransparentKeyScope};
use zcash_client_backend::{
    data_api::{
        testing::{
            orchard::OrchardPoolTester, pool::ShieldedPoolTester, AddressType, IronwoodFvk,
            TestBuilder,
        },
        transparent_ledger::{
            ReceiveEvent, TransactionMetadata, TransparentLedgerWrite as _, WatchOrigin,
            WholeTransactionFee,
        },
        wallet::{decrypt_and_store_transaction, ConfirmationsPolicy},
        AccountPurpose,
    },
    fees::StandardFeeRule,
    wallet::OvkPolicy,
};
use zcash_client_sqlite::testing::{db::TestDbFactory, BlockCache};
use zcash_primitives::block::BlockHash;
use zcash_protocol::ShieldedPool;

fn state(cross: bool) -> (State, Vec<AccountUuid>) {
    configure_regtest_nu6_3_activation_height(2).unwrap();
    let mut st = TestBuilder::new()
        .with_network(regtest())
        .with_data_store_factory(TestDbFactory::default())
        .with_block_cache(BlockCache::new())
        .with_account_from_sapling_activation(BlockHash([0; 32]))
        .build();
    let mut accounts = vec![st.test_account().unwrap().id()];
    if cross {
        let key = zcash_keys::keys::UnifiedSpendingKey::from_seed(
            st.network(),
            &[7; 32],
            zip32::AccountId::ZERO,
        )
        .unwrap()
        .to_unified_full_viewing_key();
        let birthday = st.test_account().unwrap().birthday().clone();
        accounts.push(
            st.wallet_mut()
                .import_account_ufvk("recipient", &key, &birthday, AccountPurpose::ViewOnly, None)
                .unwrap()
                .id(),
        );
    }
    scan_unrelated_blocks(&mut st, 10);
    set_policy(&mut st, TransparentLedgerMode::PrivateShadow);
    let fvk = IronwoodFvk(OrchardPoolTester::test_account_fvk(&st));
    let (height, _, _) = st.generate_next_block(&fvk, AddressType::DefaultExternal, zat(1_000_000));
    st.scan_cached_blocks(height, 1);
    (st, accounts)
}

fn address(st: &State, account: AccountUuid, internal: bool) -> TransparentAddress {
    watch(st, account).addresses.into_iter().find(|a| matches!(a.origin,
        WatchOrigin::Derived { scope, .. } if scope == if internal {TransparentKeyScope::INTERNAL} else {TransparentKeyScope::EXTERNAL}
    )).unwrap().address
}

/// The donor constructs the transaction; two fresh wallets recover the same transaction.
fn pair(cross: bool, internal: bool) -> (State, Vec<AccountUuid>, State, Vec<AccountUuid>, TxId) {
    let (mut donor, donor_accounts) = state(cross);
    let to = address(&donor, donor_accounts[usize::from(cross)], internal);
    let account = donor.test_account().cloned().unwrap();
    let proposal = donor
        .propose_standard_transfer::<Infallible>(
            account.id(),
            StandardFeeRule::Zip317,
            ConfirmationsPolicy::MIN,
            &zcash_keys::address::Address::Transparent(to),
            zat(250_000),
            None,
            None,
            ShieldedPool::Ironwood,
        )
        .unwrap();
    let txid = donor
        .create_proposed_transactions::<Infallible, _, Infallible, _>(
            account.usk(),
            OvkPolicy::Sender,
            &proposal,
        )
        .unwrap()[0];
    let tx = donor.wallet().get_transaction(txid).unwrap().unwrap();
    let index = tx
        .transparent_bundle()
        .unwrap()
        .vout
        .iter()
        .position(|o| o.script_pubkey() == &to.script().into())
        .unwrap() as u32;
    let (mut public, public_accounts) = state(cross);
    let (height, _) = public.generate_next_block_from_tx(1, &tx);
    public.scan_cached_blocks(height, 1);
    let network = *public.network();
    decrypt_and_store_transaction(&network, public.wallet_mut(), &tx, Some(height)).unwrap();
    let (mut private, private_accounts) = state(cross);
    let (height, _) = private.generate_next_block_from_tx(1, &tx);
    private.scan_cached_blocks(height, 1);
    let event = ReceiveEvent {
        outpoint: OutPoint::new(*txid.as_ref(), index),
        address: to,
        value: zat(250_000),
        coinbase: false,
        mined_height: height,
        metadata: Some(TransactionMetadata {
            fee: WholeTransactionFee::Exact(zat(15_000)),
            transparent_input_count: 0,
            has_shielded_components: true,
        }),
    };
    cover(
        &mut private,
        private_accounts[usize::from(cross)],
        vec![event],
    );
    if cross {
        cover(&mut private, private_accounts[0], vec![]);
    }
    private
        .wallet_mut()
        .db_mut()
        .qualify_transparent_revision(&revision())
        .unwrap();
    set_policy(&mut private, TransparentLedgerMode::PrivateRequired);
    for account in &private_accounts {
        private
            .wallet_mut()
            .db_mut()
            .promote_transparent_account(*account)
            .unwrap();
    }
    (public, public_accounts, private, private_accounts, txid)
}

fn read(
    st: &State,
    account: AccountUuid,
    txid: TxId,
) -> (Vec<TransactionInfo>, Vec<TransactionDetail>) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    st.wallet()
        .conn()
        .execute("VACUUM INTO ?1", [path.to_str().unwrap()])
        .unwrap();
    let rows = get_transaction_history(
        path.to_str().unwrap(),
        WalletNetwork::Regtest,
        None,
        &account.expose_uuid().to_string(),
    )
    .unwrap()
    .into_iter()
    .filter(|r| r.txid_hex == hex::encode(txid.as_ref()))
    .collect::<Vec<_>>();
    let details = rows
        .iter()
        .map(|r| {
            get_transaction_detail(
                path.to_str().unwrap(),
                WalletNetwork::Regtest,
                &account.expose_uuid().to_string(),
                &r.txid_hex,
                &r.tx_kind,
            )
            .unwrap()
        })
        .collect();
    (rows, details)
}

/// Compare production balances: PrivateRequired intentionally omits transparent
/// funds from the shielded summary; Vizor reads them from the private ledger.
fn balance(st: &State, account: AccountUuid) -> Vec<u64> {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    st.wallet()
        .conn()
        .execute("VACUUM INTO ?1", [path.to_str().unwrap()])
        .unwrap();
    let b = get_wallet_balance(
        path.to_str().unwrap(),
        WalletNetwork::Regtest,
        &account.expose_uuid().to_string(),
    )
    .unwrap();
    assert_eq!(b.availability, WalletBalanceAvailability::Available);
    assert_eq!(
        b.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    vec![
        b.transparent,
        b.sapling,
        b.orchard,
        b.ironwood,
        b.transparent_locked,
        b.sapling_locked,
        b.orchard_locked,
        b.ironwood_locked,
        b.transparent_pending,
        b.sapling_pending,
        b.orchard_pending,
        b.ironwood_pending,
        b.uneconomic_value,
    ]
}

#[test]
fn owned_transparent_public_private_activity_and_receipts_match() {
    for (cross, internal) in [(false, false), (true, false), (true, true), (false, true)] {
        let (public, pa, private, qa, txid) = pair(cross, internal);
        for (p, q) in pa.iter().zip(&qa) {
            let public_balance = balance(&public, *p);
            let private_balance = balance(&private, *q);
            assert_eq!(
                private_balance, public_balance,
                "cross={cross}, internal={internal}, account={p:?}"
            );
            let (expected, public_details) = read(&public, *p, txid);
            let (actual, private_details) = read(&private, *q, txid);
            assert_eq!(balance(&private, *q), private_balance);
            assert_eq!(balance(&public, *p), public_balance);
            let presentation = |rows: &[TransactionInfo]| {
                rows.iter()
                    .map(|r| {
                        (
                            r.tx_kind.clone(),
                            r.display_amount,
                            r.display_pool.clone(),
                            r.activity_pool.clone(),
                            r.is_transparent,
                            r.account_balance_delta,
                        )
                    })
                    .collect::<Vec<_>>()
            };
            if internal && !cross {
                // Change stays hidden. Without complete payment evidence private
                // recovery may retain its unresolved movement fallback.
                assert!(actual.iter().all(|r| r.display_pool == "unknown"));
                assert!(private_details.iter().all(|d| d.outputs.is_empty()));
            } else {
                assert_eq!(presentation(&actual), presentation(&expected));
                assert_eq!(actual.len(), if cross { 1 } else { 2 });
            }
            for (actual, expected) in private_details.iter().zip(&public_details) {
                assert_eq!(actual.tx_kind, expected.tx_kind);
                assert_eq!(
                    actual
                        .outputs
                        .iter()
                        .map(|o| (&o.address, o.amount_zatoshi, &o.pool))
                        .collect::<Vec<_>>(),
                    expected
                        .outputs
                        .iter()
                        .map(|o| (&o.address, o.amount_zatoshi, &o.pool))
                        .collect::<Vec<_>>()
                );
                if !actual.outputs.is_empty() {
                    assert_eq!(actual.inferred_attribution, Some(true));
                    assert!(!actual.details_complete);
                }
            }
            if !(internal && !cross) {
                assert!(actual
                    .iter()
                    .all(|r| r.display_amount == 250_000 && !r.amount_includes_fee));
            }
        }
        if !cross && !internal {
            let (rows, _) = read(&private, qa[0], txid);
            assert_eq!(
                rows.iter().map(|r| r.tx_kind.as_str()).collect::<Vec<_>>(),
                vec!["sent", "received"]
            );
            assert!(rows.iter().all(
                |r| r.account_balance_delta == -15_000 && r.inferred_attribution == Some(true)
            ));
        }
        let transparent_sent: i64 = private
            .wallet()
            .conn()
            .query_row(
                "SELECT COUNT(*) FROM sent_notes WHERE output_pool = 0",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(transparent_sent, 0);
    }
}

/// Exports a fabricated private wallet for the opt-in native integration check.
/// Production-wallet files and keys are never consulted.
#[test]
fn owned_transparent_native_fixture() {
    let Ok(directory) = std::env::var("VIZOR_OWNED_TRANSFER_FIXTURE_DIR") else {
        return;
    };
    let path = std::path::Path::new(&directory);
    std::fs::create_dir_all(path).unwrap();
    let (_, _, private, accounts, txid) = pair(false, false);
    let db = path.join("wallet.db");
    assert!(!db.exists(), "native fixture destination must be fresh");
    private
        .wallet()
        .conn()
        .execute("VACUUM INTO ?1", [db.to_str().unwrap()])
        .unwrap();
    std::fs::write(
        path.join("identity.json"),
        serde_json::json!({
            "account": accounts[0].expose_uuid().to_string(), "txid": hex::encode(txid.as_ref())
        })
        .to_string(),
    )
    .unwrap();
}

#[test]
fn owned_transparent_production_reads_refresh_and_withdraw_atomically() {
    let (_, _, mut private, accounts, txid) = pair(true, false);
    let sender = accounts[0];
    let recipient = accounts[1];
    let initial = read(&private, sender, txid).0;
    assert_eq!(initial.len(), 1);
    assert_eq!(initial[0].display_amount, 250_000);
    let tx_ref: i64 = private
        .wallet()
        .conn()
        .query_row(
            "SELECT id_tx FROM transactions WHERE txid = ?1",
            [txid.as_ref()],
            |r| r.get(0),
        )
        .unwrap();
    // A delayed compact spend relationship arrives after the transparent output.
    private
        .wallet()
        .conn()
        .execute(
            "DELETE FROM ironwood_received_note_spends WHERE transaction_id = ?1",
            [tx_ref],
        )
        .unwrap();
    let first = read(&private, recipient, txid).0;
    assert!(first.iter().all(|r| r.inferred_attribution != Some(true)));
    let height = private
        .wallet()
        .conn()
        .query_row::<u32, _, _>(
            "SELECT mined_height FROM transactions WHERE id_tx = ?1",
            [tx_ref],
            |r| r.get(0),
        )
        .unwrap();
    private.scan_cached_blocks(height.into(), 1);
    assert_eq!(read(&private, sender, txid).0[0].display_amount, 250_000);
    assert_eq!(
        read(&private, recipient, txid).0[0].inferred_attribution,
        Some(true)
    );
    private.wallet().conn().execute("DELETE FROM tpir_coverage WHERE account_id = (SELECT id FROM accounts WHERE uuid = ?1)", [recipient.expose_uuid()]).unwrap();
    let unsettled = read(&private, sender, txid).0;
    assert_eq!(unsettled.len(), 1);
    assert_eq!(unsettled[0].display_amount, 265_000);
    assert_eq!(unsettled[0].inferred_attribution, Some(false));
    assert_ne!(
        initial[0].relationship_signature,
        unsettled[0].relationship_signature
    );
    assert_eq!(
        unsettled[0].account_balance_delta,
        initial[0].account_balance_delta
    );
    cover(&mut private, recipient, vec![]);
    assert_eq!(read(&private, sender, txid).0[0].display_amount, 250_000);
    let birthday = private.test_account().unwrap().birthday().clone();
    let output_index: u32 = private
        .wallet()
        .conn()
        .query_row(
            "SELECT output_index FROM transparent_received_outputs WHERE transaction_id = ?1",
            [tx_ref],
            |r| r.get(0),
        )
        .unwrap();
    private.wallet_mut().delete_account(recipient).unwrap();
    let withdrawn = read(&private, sender, txid).0;
    assert!(withdrawn
        .iter()
        .all(|r| r.inferred_attribution == Some(false)));
    assert!(read(&private, sender, txid)
        .1
        .iter()
        .all(|d| d.outputs.is_empty()));
    let network = *private.network();
    let key =
        zcash_keys::keys::UnifiedSpendingKey::from_seed(&network, &[7; 32], zip32::AccountId::ZERO)
            .unwrap()
            .to_unified_full_viewing_key();
    let imported = private
        .wallet_mut()
        .import_account_ufvk(
            "later recipient",
            &key,
            &birthday,
            AccountPurpose::ViewOnly,
            None,
        )
        .unwrap()
        .id();
    // Import schedules historical shielded scanning; settle it before asking
    // private transparent recovery to cover the current transaction height.
    let start = birthday.height();
    private.scan_cached_blocks(
        start,
        usize::try_from(height - u32::from(start) + 1).unwrap(),
    );
    let to = address(&private, imported, false);
    let event = ReceiveEvent {
        outpoint: OutPoint::new(*txid.as_ref(), output_index),
        address: to,
        value: zat(250_000),
        coinbase: false,
        mined_height: height.into(),
        metadata: Some(TransactionMetadata {
            fee: WholeTransactionFee::Exact(zat(15_000)),
            transparent_input_count: 0,
            has_shielded_components: true,
        }),
    };
    cover(&mut private, imported, vec![event]);
    cover(&mut private, sender, vec![]);
    private
        .wallet_mut()
        .db_mut()
        .promote_transparent_account(imported)
        .unwrap();
    let restored = read(&private, sender, txid).0;
    assert_eq!(
        restored[0].display_amount,
        250_000,
        "{:?}",
        private
            .wallet()
            .db()
            .transaction_history_details(sender, &[txid])
            .unwrap()
    );
    assert_eq!(restored[0].inferred_attribution, Some(true));
    assert_ne!(
        restored[0].relationship_signature,
        initial[0].relationship_signature
    );
    assert_eq!(read(&private, imported, txid).0.len(), 1);
    private.truncate_to_height(zcash_protocol::consensus::BlockHeight::from_u32(height) - 1);
    assert!(read(&private, sender, txid)
        .0
        .iter()
        .all(|r| r.inferred_attribution != Some(true)));
}

#[test]
fn owned_transparent_overlay_reuses_scopes_and_canonical_outputs() {
    let a = vec![1; 16];
    let b = vec![2; 16];
    for cross in [false, true] {
        for scope in [Some(0), Some(1), Some(2), None] {
            let mut base = super::tests::tx_base_for_history();
            let output = TxOutput {
                txid: base.txid.clone(),
                output_pool: 0,
                output_index: 0,
                from_account_uuid: Some(a.clone()),
                to_account_uuid: Some(if cross { b.clone() } else { a.clone() }),
                to_address: Some("synthetic-transparent-receiver".into()),
                sent_to_address: None,
                transparent_receiver_address: None,
                to_key_scope: scope,
                value: 250_000,
                memo: None,
                note_version: None,
                inferred_attribution: true,
            };
            base.display_outputs = vec![output.clone()];
            let mut outputs = vec![];
            overlay_owned_outputs(&base, &mut outputs);
            overlay_owned_outputs(&base, &mut outputs);
            assert_eq!(outputs.len(), 1);
            assert_eq!(outputs[0].to_key_scope, scope);
            let summary = summarize_activity_outputs(&base, &outputs, &a);
            assert_eq!(
                summary.sent.output_count,
                usize::from(cross || scope == Some(0))
            );
            assert_eq!(
                summary.received.output_count,
                usize::from(!cross && scope == Some(0))
            );
            if cross {
                assert_eq!(
                    summarize_activity_outputs(&base, &outputs, &b)
                        .received
                        .amount,
                    250_000
                );
                assert!(detail_includes_output(&base, &outputs[0], &b, "received"));
            }
            let mut canonical = output.clone();
            canonical.inferred_attribution = false;
            canonical.value = 123;
            let mut outputs = vec![canonical];
            overlay_owned_outputs(&base, &mut outputs);
            assert_eq!(outputs.len(), 1);
            assert_eq!(outputs[0].value, 123);
            assert!(!outputs[0].inferred_attribution);
        }
    }
}
