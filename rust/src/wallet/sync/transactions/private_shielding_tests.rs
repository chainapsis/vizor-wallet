//! Activity for transparent-to-Ironwood shieldings recovered only by private queries.
//!
//! Each wallet is built by the library's own private recovery, as a fresh
//! `PrivateRequired` restore builds it: qualified transparent recovery
//! publishes the account's two spends with whole-transaction metadata, compact
//! scanning finds the account's Ironwood output without its memo, and Enhance
//! PIR applies the service's record for that output. Vizor's production
//! history and detail reads then run over a copy of the database, so these
//! tests cover the library result and Vizor's mapping of it together.

use orchard::{
    keys::Diversifier,
    note::{Note, NoteVersion, RandomSeed, Rho},
    note_encryption::IronwoodNoteEncryption,
    value::NoteValue,
};
use transparent::{address::TransparentAddress, bundle::OutPoint, keys::TransparentKeyScope};
use zcash_client_backend::data_api::{
    enhance_pir::{
        EnhancePirBatchResult, EnhancePirRead as _, EnhancePirRequest, EnhancePirStoreResult,
        EnhancePirWork, EnhancePirWrite as _, EnhanceRecord, EnhanceRecordParts,
        EnhanceTransactionMetadata, EnhancementMode, TransactionEnhancementWork,
    },
    testing::{
        orchard::OrchardPoolTester, pool::ShieldedPoolTester, AddressType, IronwoodFvk,
        TestBuilder, TestState,
    },
    transparent_ledger::{
        AddressRange, PublicationAnchor, ReceiveEvent, RecoveryRevision, SpendEvent,
        TransactionMetadata, TransparentLedgerCommit, TransparentLedgerMode,
        TransparentLedgerWrite as _, TransparentWatchSet, WatchOrigin, WholeTransactionFee,
    },
};
use zcash_client_sqlite::testing::{
    db::{TestDb, TestDbFactory},
    BlockCache,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::{consensus::BlockHeight, local_consensus::LocalNetwork, value::Zatoshis};
use zip32::Scope;

use super::*;
use crate::wallet::network::configure_regtest_nu6_3_activation_height;

type State = TestState<BlockCache, TestDb, LocalNetwork>;

const NETWORK: WalletNetwork = WalletNetwork::Regtest;
const NU6_3: u32 = 2;
const FEE: u64 = 20_000;
/// The empty memo a shielding carries.
const MEMO: [u8; 512] = {
    let mut memo = [0; 512];
    memo[0] = 0xf6;
    memo
};

/// Vizor's regtest chain: every upgrade through NU6.2 at height 1, Ironwood
/// at `NU6_3`.
fn regtest() -> LocalNetwork {
    let one = Some(BlockHeight::from_u32(1));
    LocalNetwork {
        overwinter: one,
        sapling: one,
        blossom: one,
        heartwood: one,
        canopy: one,
        nu5: one,
        nu6: one,
        nu6_1: one,
        nu6_2: one,
        nu6_3: Some(BlockHeight::from_u32(NU6_3)),
        nu7: None,
    }
}

fn zat(value: u64) -> Zatoshis {
    Zatoshis::const_from_u64(value)
}

fn scan_unrelated_blocks(st: &mut State, count: usize) {
    let not_ours =
        sapling_crypto::zip32::ExtendedSpendingKey::master(&[]).to_diversifiable_full_viewing_key();
    let (start, _, _) =
        st.generate_next_block(&not_ours, AddressType::DefaultExternal, zat(10_000));
    for _ in 1..count {
        st.generate_next_block(&not_ours, AddressType::DefaultExternal, zat(10_000));
    }
    st.scan_cached_blocks(start, count);
}

fn set_policy(st: &mut State, mode: TransparentLedgerMode) {
    let db = st.wallet_mut().db_mut();
    db.apply_transparent_policy(mode).unwrap();
    db.set_transparent_ledger_mode(mode);
}

fn watch(st: &State, account: AccountUuid) -> TransparentWatchSet<AccountUuid> {
    st.wallet().db().transparent_watch_set(account).unwrap()
}

fn revision() -> RecoveryRevision {
    RecoveryRevision {
        source: b"fixture".to_vec(),
        revision: b"r1".to_vec(),
        lineage: 1,
        sealed: true,
        publication: PublicationAnchor {
            height: BlockHeight::from_u32(10_000_000),
            hash: BlockHash([7; 32]),
        },
    }
}

/// A commit covering every watched address through the watch set's target.
fn commit(ws: &TransparentWatchSet<AccountUuid>) -> TransparentLedgerCommit<AccountUuid> {
    let target = ws.target.unwrap();
    TransparentLedgerCommit {
        context: ws.context().unwrap(),
        revision: revision(),
        anchor: target,
        receives: vec![],
        spends: vec![],
        coverage: ws
            .addresses
            .iter()
            .map(|watched| AddressRange {
                address: watched.address,
                from: watched.required_from,
                through: target.height,
            })
            .collect(),
        unsupported: vec![],
        opened_pages: vec![],
        completed_pages: vec![],
    }
}

fn external(ws: &TransparentWatchSet<AccountUuid>) -> TransparentAddress {
    ws.addresses
        .iter()
        .find(|w| {
            matches!(
                w.origin,
                WatchOrigin::Derived { scope, .. } if scope == TransparentKeyScope::EXTERNAL
            )
        })
        .unwrap()
        .address
}

/// Commits `receives` and repeats the coverage while the address window grows.
fn cover(st: &mut State, account: AccountUuid, receives: Vec<ReceiveEvent>) {
    let mut receives = Some(receives);
    loop {
        let mut c = commit(&watch(st, account));
        c.receives = receives.take().unwrap_or_default();
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

/// A database copy for Vizor's reads, and the recovered transaction.
struct Recovered {
    _dir: tempfile::TempDir,
    path: String,
    account: AccountUuid,
    txid_hex: String,
}

/// Recovers a shielding of `inputs` into `shielded` with a 20,000-zatoshi fee
/// by private queries only, and returns a copy of the resulting wallet. The
/// Enhance PIR record carries the whole fee and reports no transparent output.
fn privately_recovered_shielding(inputs: [u64; 2], shielded: u64) -> Recovered {
    privately_recovered(inputs, shielded, Some(FEE), false)
}

/// Like [`privately_recovered_shielding`], with the Enhance PIR record's fee
/// and transparent-output flag chosen by the caller.
fn privately_recovered(
    inputs: [u64; 2],
    shielded: u64,
    record_fee: Option<u64>,
    transparent_outputs: bool,
) -> Recovered {
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

    // Private transparent recovery finds the two outputs that fund the shielding.
    let ws = watch(&st, account);
    let target = ws.target.unwrap().height;
    let receives =
        [(0x51, inputs[0], 4), (0x52, inputs[1], 3)].map(|(tag, value, depth)| ReceiveEvent {
            metadata: None,
            outpoint: OutPoint::new([tag; 32], 0),
            address: external(&ws),
            value: zat(value),
            coinbase: false,
            mined_height: target - depth,
        });
    cover(&mut st, account, receives.to_vec());
    st.wallet_mut()
        .db_mut()
        .qualify_transparent_revision(&revision())
        .unwrap();
    set_policy(&mut st, TransparentLedgerMode::PrivateRequired);
    st.wallet_mut()
        .db_mut()
        .promote_transparent_account(account)
        .unwrap();
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);

    // Compact scanning finds the shielded output to the account's internal
    // address, without its memo.
    let fvk = OrchardPoolTester::test_account_fvk(&st);
    let (height, _, _) = st.generate_next_block(
        &IronwoodFvk(fvk.clone()),
        AddressType::Internal,
        zat(shielded),
    );
    st.scan_cached_blocks(height, 1);
    scan_unrelated_blocks(&mut st, 2);
    let (tx_ref, txid): (i64, [u8; 32]) = st
        .wallet()
        .conn()
        .query_row(
            "SELECT id_tx, txid FROM transactions WHERE mined_height = ?1",
            [u32::from(height)],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    // The fake block's only transaction occupies the coinbase position.
    st.wallet()
        .conn()
        .execute(
            "UPDATE transactions SET tx_index = 1 WHERE id_tx = ?1",
            [tx_ref],
        )
        .unwrap();

    // Private transparent recovery publishes both owned inputs of the
    // shielding, with its whole-transaction metadata.
    let metadata = TransactionMetadata {
        fee: WholeTransactionFee::Exact(zat(FEE)),
        transparent_input_count: 2,
        has_shielded_components: true,
    };
    let mut c = commit(&watch(&st, account));
    c.spends = receives
        .iter()
        .enumerate()
        .map(|(index, prevout)| SpendEvent {
            metadata: Some(metadata),
            spending_txid: TxId::from_bytes(txid),
            input_index: u32::try_from(index).unwrap(),
            prevout: prevout.outpoint.clone(),
            prevout_address: prevout.address,
            mined_height: height,
        })
        .collect();
    st.wallet_mut()
        .db_mut()
        .apply_transparent_ledger_commit(c)
        .unwrap();

    // Enhance PIR: the only work is the private memo query for the output;
    // PrivateRequired never asks for the transaction publicly.
    let work = st.wallet().transaction_enhancement_work().unwrap();
    assert!(
        !work
            .iter()
            .any(|w| matches!(w, TransactionEnhancementWork::Public(_))),
        "no public GetTransaction under PrivateRequired"
    );
    let requests: Vec<EnhancePirRequest> = work
        .into_iter()
        .filter_map(|w| match w {
            TransactionEnhancementWork::Private(EnhancePirWork::Query(request)) => Some(request),
            _ => None,
        })
        .collect();
    assert_eq!(requests.len(), 1);
    let request = requests[0];

    // The service's record: the authentic ciphertext of the scanned note, its
    // transparent shape flags, and its transaction metadata.
    let (diversifier, value, rho, rseed): ([u8; 11], i64, [u8; 32], [u8; 32]) = st
        .wallet()
        .conn()
        .query_row(
            "SELECT diversifier, value, rho, rseed FROM ironwood_received_notes
             WHERE commitment_tree_position = ?1",
            [u64::from(request.position())],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    let rho = Rho::from_bytes(&rho).unwrap();
    let note = Note::from_parts(
        fvk.address(Diversifier::from_bytes(diversifier), Scope::Internal),
        NoteValue::from_raw(u64::try_from(value).unwrap()),
        rho,
        RandomSeed::from_bytes(rseed, &rho).unwrap(),
        NoteVersion::V3,
    )
    .unwrap();
    let encryptor = IronwoodNoteEncryption::new(None, note, MEMO);
    let record = EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: encryptor.encrypt_note_plaintext()[52..].try_into().unwrap(),
        cv_net: [0; 32],
        out_ciphertext: [0; 80],
        has_transparent_inputs: true,
        has_transparent_outputs: transparent_outputs,
        metadata: EnhanceTransactionMetadata::new(0, record_fee).unwrap(),
    });
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_ironwood_enhance_records(&[(request, record)])
            .unwrap(),
        EnhancePirBatchResult::Committed(vec![EnhancePirStoreResult::PrivateDetailsUnsupported])
    );

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    st.wallet()
        .conn()
        .execute("VACUUM INTO ?1", [&path])
        .unwrap();
    Recovered {
        _dir: dir,
        path,
        account,
        txid_hex: hex::encode(txid),
    }
}

fn history_row(recovered: &Recovered) -> TransactionInfo {
    let rows = get_transaction_history(
        &recovered.path,
        NETWORK,
        None,
        &recovered.account.expose_uuid().to_string(),
    )
    .unwrap();
    let mut matching = rows
        .into_iter()
        .filter(|row| row.txid_hex == recovered.txid_hex)
        .collect::<Vec<_>>();
    assert_eq!(matching.len(), 1, "one Activity row for the shielding");
    matching.remove(0)
}

/// The Activity row and receipt values, without the chain-specific
/// identifiers, as the desktop tests render them.
fn display_values(row: &TransactionInfo, detail: &TransactionDetail) -> serde_json::Value {
    serde_json::json!({
        "transaction": {
            "txKind": row.tx_kind,
            "displayAmount": row.display_amount,
            "displayPool": row.display_pool,
            "accountBalanceDelta": row.account_balance_delta,
            "fee": row.fee,
            "feeState": format!("{:?}", row.fee_state),
            "detailsComplete": row.details_complete,
            "provisional": row.provisional,
            "amountIncludesFee": row.amount_includes_fee,
            "isTransparent": row.is_transparent,
            "expiredUnmined": row.expired_unmined,
        },
        "detail": {
            "txKind": detail.tx_kind,
            "memo": detail.memo,
            "detailsComplete": detail.details_complete,
            "provisional": detail.provisional,
            "outputs": detail.outputs.iter().map(|output| serde_json::json!({
                "amountZatoshi": output.amount_zatoshi,
                "pool": output.pool,
            })).collect::<Vec<_>>(),
        },
    })
}

/// Shared with the desktop Activity and receipt tests, which render exactly
/// these values. Regenerate with `VIZOR_UPDATE_FIXTURES=1`.
const DISPLAY_FIXTURE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../test/fixtures/private_shielding_activity.json"
);

/// The two reported mainnet shapes: shielding 0.0018 and 0.004 ZEC with a
/// 0.0002 ZEC network fee.
#[test]
fn a_privately_recovered_shielding_shows_as_shielded_with_the_network_fee() {
    let mut displayed = vec![];
    for (inputs, shielded) in [([120_000, 80_000], 180_000), ([300_000, 120_000], 400_000)] {
        let recovered = privately_recovered_shielding(inputs, shielded);

        let row = history_row(&recovered);
        assert_eq!(row.tx_kind, "shielded");
        assert_eq!(row.display_amount, shielded);
        assert_eq!(row.account_balance_delta, -(FEE as i64));
        assert_eq!(row.fee_state, TransactionFeeState::Known);
        assert_eq!(row.fee, FEE);
        assert!(row.details_complete);
        assert!(!row.provisional);
        assert!(
            !row.amount_includes_fee,
            "the shielding amount excludes the fee"
        );

        let detail = get_transaction_detail(
            &recovered.path,
            NETWORK,
            &recovered.account.expose_uuid().to_string(),
            &recovered.txid_hex,
            "shielded",
        )
        .unwrap();
        assert_eq!(detail.tx_kind, "shielded");
        assert!(detail.details_complete);
        assert!(!detail.provisional);
        assert_eq!(
            detail
                .outputs
                .iter()
                .map(|output| output.amount_zatoshi)
                .sum::<u64>(),
            shielded
        );
        displayed.push(display_values(&row, &detail));
    }

    let displayed = serde_json::Value::Array(displayed);
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

/// The library's provisional result for the same owned effects, as Vizor shows
/// it: never a shielding, never complete. Both are the library's evidence
/// gates, not display choices.
fn assert_not_a_shielding(recovered: &Recovered) {
    let row = history_row(recovered);
    assert_ne!(row.tx_kind, "shielded");
    assert!(row.provisional);
    assert!(!row.details_complete);
    assert_eq!(row.account_balance_delta, -(FEE as i64));
    let detail = get_transaction_detail(
        &recovered.path,
        NETWORK,
        &recovered.account.expose_uuid().to_string(),
        &recovered.txid_hex,
        &row.tx_kind,
    )
    .unwrap();
    assert_ne!(detail.tx_kind, "shielded");
    assert!(detail.provisional);
    assert!(!detail.details_complete);
}

/// The Enhance publisher reports no fee for a transaction with transparent
/// data, so its records recover the memo and shape but not the fee the library
/// cross-checks: the history stays provisional, and Vizor keeps showing its
/// provisional fallback rather than a shielding.
#[test]
fn a_shielding_whose_enhance_record_carries_no_fee_is_not_shown_as_shielded() {
    assert_not_a_shielding(&privately_recovered(
        [120_000, 80_000],
        180_000,
        None,
        false,
    ));
}

/// A record reporting transparent outputs: the account's side balances as a
/// shielding would, but value left through a transparent output, so it is not
/// one.
#[test]
fn a_transaction_with_transparent_outputs_is_not_shown_as_shielded() {
    assert_not_a_shielding(&privately_recovered(
        [120_000, 80_000],
        180_000,
        Some(FEE),
        true,
    ));
}
