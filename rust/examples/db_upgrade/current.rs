//! Checks that only the current build can run: API that older builds lack.
//! `test-db-upgrade.sh` replaces this file in the base worktree with
//! `current_stub.rs`, which keeps the same signatures.

use std::{collections::BTreeSet, num::NonZeroU32};

use rust_lib_zcash_wallet::{
    api::sync,
    wallet::{legacy_rollback, network::WalletNetwork},
};
use transparent::address::TransparentAddress;
use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::data_api::{
    transparent_ledger::TransparentLedgerMode,
    wallet::{
        input_selection::{LockFilter, LockedInputPolicy},
        ConfirmationsPolicy, TargetHeight,
    },
    CoinbaseFilter, InputSource,
};
use zcash_client_sqlite::{util::SystemClock, WalletDb};
use zcash_keys::encoding::AddressCodec as _;
use zcash_protocol::consensus::BlockHeight;

use super::{ApiSnapshot, HistoryRow, NETWORK};

/// Runs the downgrade handover through Vizor's entry point.
pub fn prepare_rollback(db_path: &str) {
    legacy_rollback::prepare_for_legacy_build(db_path, WalletNetwork::Regtest)
        .expect("prepare the wallet for an older build");
}

/// `base`, as the current build should report it. Two documented history
/// rules (`enhancement/README.md`, "History completeness") may change what an
/// older build showed, and only in exactly these ways:
///
/// - A debit whose payment details are incomplete is provisional. When no
///   payment is visible either, it is one `sent` row for the net debit less
///   any known fee, with pool `unknown` and no receive of its change. Older
///   builds showed it as a receive of its change.
/// - `fee` is the account's fee, and 0 unless `fee_state` is `Known`. Older
///   builds showed the transaction's fee on every row, including the receive
///   of an account that spent nothing, whose fee is `NotApplicable` once its
///   effects are settled and `Unknown` before. Such a receive (a positive
///   account delta) may therefore lose the base's fee. Every other fee the
///   base showed must stay `Known` and equal.
///
/// A third history rule (gap 1 and H09, fixed in this build) applies to the
/// send the base build stored itself (`old_build_send`): older builds counted
/// a send's movement once per receiving wallet account, and counted the
/// funding account's own output as paid. The funding account's row is
/// therefore the probe's own construction: its movement is
/// `OLD_BUILD_PAYMENT_ZAT - MINED_VALUE_ZAT`, and when other accounts are
/// paid its payment is `OLD_BUILD_PAYMENT_ZAT` to each of them (a lone
/// account's self-transfer keeps showing its own output).
///
/// One documented balance rule applies too (`sync_engine/address_discovery.rs`,
/// "Coverage"): a public account's transparent funds are current only once
/// its address-history discovery has run. Upgrading never runs it; the first
/// sync does. So every upgraded account reads its transparent funds as
/// `LastKnown`, exactly the base build's transparent total, with nothing
/// transparent spendable, locked, or pending. This function asserts that
/// authority and amount, and expects the zeroed transparent fields.
pub fn expected_current_api(
    db_path: &str,
    base: &ApiSnapshot,
    old_build_send: Option<&super::OldBuildSend>,
) -> ApiSnapshot {
    let mut expected = base.clone();
    for account in &mut expected.accounts {
        if let Some(send) = old_build_send {
            let movement = super::OLD_BUILD_PAYMENT_ZAT as i64 - super::MINED_VALUE_ZAT;
            for row in &mut account.history {
                if row.txid_hex == send.txid_hex && row.account_balance_delta < 0 {
                    row.account_balance_delta = movement;
                    // A self-transfer (one account) still shows its own
                    // output; once others are paid, only they count.
                    if row.tx_kind == "sent" && send.recipients > 1 {
                        row.display_amount =
                            super::OLD_BUILD_PAYMENT_ZAT * send.recipients.saturating_sub(1);
                    }
                }
            }
        }
        let balance = sync::get_balance(
            db_path.to_string(),
            NETWORK.to_string(),
            account.uuid.clone(),
        )
        .expect("read balance");
        let base_total = account.balance.transparent
            + account.balance.transparent_locked
            + account.balance.transparent_pending;
        assert!(
            matches!(
                balance.transparent_authority,
                sync::TransparentBalanceAuthority::LastKnown
            ),
            "an upgraded public wallet reads transparent funds as current before discovery"
        );
        assert_eq!(
            balance.transparent_last_known,
            Some(base_total),
            "upgrade changed the account's transparent total"
        );
        // The account totals carry no transparent funds while they are only
        // last known.
        account.balance.locked -= account.balance.transparent_locked;
        account.balance.total -= base_total;
        // Transparent pending value is change or value pending spendability;
        // together those two account totals lose exactly that much.
        let base_pending = account.balance.change_pending_confirmation
            + account.balance.value_pending_spendability;
        assert_eq!(
            base_pending
                - (balance.change_pending_confirmation + balance.value_pending_spendability),
            account.balance.transparent_pending,
            "pending totals changed by more than the transparent pending value"
        );
        account.balance.change_pending_confirmation = balance.change_pending_confirmation;
        account.balance.value_pending_spendability = balance.value_pending_spendability;
        account.balance.transparent = 0;
        account.balance.transparent_locked = 0;
        account.balance.transparent_pending = 0;
        let current = sync::get_transaction_history(
            db_path.to_string(),
            NETWORK.to_string(),
            None,
            account.uuid.clone(),
        )
        .expect("read history");
        let mut seen = BTreeSet::new();
        for row in &current {
            if !row.provisional
                || row.details_complete
                || row.account_balance_delta >= 0
                || !seen.insert(row.txid_hex.clone())
            {
                continue;
            }
            let base_rows: Vec<HistoryRow> = account
                .history
                .iter()
                .filter(|base_row| base_row.txid_hex == row.txid_hex)
                .cloned()
                .collect();
            // A visible payment keeps its rows.
            if base_rows.iter().any(|base_row| base_row.tx_kind == "sent") {
                continue;
            }
            let Some(first) = base_rows.first() else {
                continue;
            };
            let known_fee = match row.fee_state {
                sync::TransactionFeeState::Known => first.fee,
                _ => 0,
            };
            let debit = first.account_balance_delta.unsigned_abs() - known_fee;
            let provisional = HistoryRow {
                txid_hex: first.txid_hex.clone(),
                mined_height: first.mined_height,
                expired_unmined: first.expired_unmined,
                account_balance_delta: first.account_balance_delta,
                fee: known_fee,
                block_time: first.block_time,
                is_transparent: false,
                tx_kind: if debit > 0 { "sent" } else { "unknown" }.to_string(),
                display_amount: debit,
                display_pool: "unknown".to_string(),
                created_time: first.created_time,
            };
            println!(
                "  provisional debit {}: base showed {:?}",
                row.txid_hex,
                base_rows
                    .iter()
                    .map(|base_row| (&base_row.tx_kind, base_row.display_amount))
                    .collect::<Vec<_>>()
            );
            let at = account
                .history
                .iter()
                .position(|base_row| base_row.txid_hex == row.txid_hex)
                .unwrap();
            account
                .history
                .retain(|base_row| base_row.txid_hex != row.txid_hex);
            account.history.insert(at, provisional);
        }
        for expected_row in &mut account.history {
            let receive = expected_row.account_balance_delta > 0
                && matches!(expected_row.tx_kind.as_str(), "received" | "receiving");
            let unattributed = current.iter().any(|row| {
                row.txid_hex == expected_row.txid_hex
                    && row.tx_kind == expected_row.tx_kind
                    && !matches!(row.fee_state, sync::TransactionFeeState::Known)
            });
            if receive && unattributed && expected_row.fee != 0 {
                println!(
                    "  receive without the transaction fee {} {}: base showed {}",
                    expected_row.txid_hex, expected_row.tx_kind, expected_row.fee
                );
                expected_row.fee = 0;
            }
        }
    }
    expected
}

/// The fields older builds do not have: an unrecorded fee is unknown rather
/// than zero. Transparent authority is checked by `expected_current_api`.
pub fn assert_current_api(db_path: &str, api: &ApiSnapshot) {
    for account in &api.accounts {
        let history = sync::get_transaction_history(
            db_path.to_string(),
            NETWORK.to_string(),
            None,
            account.uuid.clone(),
        )
        .expect("read history");
        for row in history {
            match row.fee_state {
                sync::TransactionFeeState::Known => {}
                sync::TransactionFeeState::Unknown | sync::TransactionFeeState::NotApplicable => {
                    assert_eq!(
                        row.fee, 0,
                        "{} reports a fee it does not know",
                        row.txid_hex
                    )
                }
            }
            println!(
                "  {} {} fee_state={} details_complete={} provisional={}",
                row.txid_hex,
                row.tx_kind,
                fee_state_name(&row.fee_state),
                row.details_complete,
                row.provisional
            );
        }
    }
}

fn fee_state_name(state: &sync::TransactionFeeState) -> &'static str {
    match state {
        sync::TransactionFeeState::Known => "known",
        sync::TransactionFeeState::Unknown => "unknown",
        sync::TransactionFeeState::NotApplicable => "not-applicable",
    }
}

/// Unlocked transparent outputs at `addresses` that the production handle
/// mode (`Public`) would select as inputs for a transaction mined after
/// `tip`, under Vizor's confirmation policy, as `(txid, index, value)`.
pub fn spendable_outputs(
    db_path: &str,
    addresses: &BTreeSet<String>,
    tip: u32,
) -> BTreeSet<(String, u32, u64)> {
    let db = WalletDb::for_path(db_path, WalletNetwork::Regtest, SystemClock, OsRng)
        .expect("open wallet DB")
        .with_transparent_ledger_mode(TransparentLedgerMode::Public);
    // Vizor's spend policy: 3 trusted, 6 untrusted confirmations.
    let policy = ConfirmationsPolicy::new(
        NonZeroU32::new(3).unwrap(),
        NonZeroU32::new(6).unwrap(),
        true,
    )
    .unwrap();
    let mut spendable = BTreeSet::new();
    for encoded in addresses {
        let address = TransparentAddress::decode(&WalletNetwork::Regtest, encoded)
            .expect("decode transparent address");
        for output in db
            .get_spendable_transparent_outputs(
                &address,
                TargetHeight::from(BlockHeight::from_u32(tip + 1)),
                policy,
                CoinbaseFilter::AllTransparentOutputs,
                LockFilter::Policy(&LockedInputPolicy::Exclude),
            )
            .expect("select transparent outputs")
        {
            let outpoint = output.outpoint();
            let txid: &[u8; 32] = outpoint.txid().as_ref();
            spendable.insert((
                hex::encode(txid),
                outpoint.n(),
                u64::from(output.txout().value()),
            ));
        }
    }
    spendable
}
