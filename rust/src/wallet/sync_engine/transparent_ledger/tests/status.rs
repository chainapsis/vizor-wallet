//! What the balance read reports about private transparent authority: whether
//! the wallet is durably private, and why recovery has stopped.

use std::time::Duration;

use zakura_pir_transparent::WithdrawnCause;

use super::*;
use crate::wallet::db::open_wallet_db_for_read_with_timeout;
use crate::wallet::sync::{
    get_shield_transparent_status, read_wallet_balances, TransparentStopReason,
};

/// The phrase of the shielding refusal for a wallet this build does not
/// recover; the app matches it.
const NOT_SELECTED: &str = "turn off private queries";
/// The phrase of the shielding refusal while recovery may still complete.
const INCOMPLETE: &str = "transparent funds are unavailable";

fn shield_reason(wallet: &Wallet, uuid: &str) -> String {
    let status = get_shield_transparent_status(&wallet.path, NETWORK, uuid).unwrap();
    assert!(!status.can_shield);
    status.reason
}

#[tokio::test]
async fn a_private_database_in_a_flag_off_build_is_stopped_not_selected() {
    // Recovered and promoted in a build with the development flag.
    let mut wallet = wallet();
    let mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    let current = balance(&wallet, &wallet.uuid);
    assert_eq!(
        current.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert!(current.transparent_private);

    // Reopened in a build without it, which selects `Public`. The private
    // ledger still covers the tip, so the amount is still current.
    drop(mode);
    let still = balance(&wallet, &wallet.uuid);
    assert_eq!(
        still.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!((still.transparent, still.transparent_stop), (VALUE, None));

    // Once the chain moves, nothing in this build recovers the account: it
    // is stopped, not awaiting recovery, and keeps its last-known amount.
    scan(&wallet.path, wallet.birthday, TIP + 1, TIP + 1, 0);
    let stopped = balance(&wallet, &wallet.uuid);
    assert_eq!(
        stopped.transparent_authority,
        TransparentBalanceAuthority::Stopped
    );
    assert_eq!(
        stopped.transparent_stop,
        Some(TransparentStopReason::NotSelected)
    );
    assert_eq!(stopped.transparent_last_known, Some(VALUE));
    assert_eq!(stopped.transparent, 0, "nothing is spendable");
    assert!(stopped.transparent_private);
    let reason = shield_reason(&wallet, &wallet.uuid);
    assert!(reason.contains(NOT_SELECTED), "{reason}");
    assert!(!reason.to_lowercase().contains(INCOMPLETE), "{reason}");

    // A build that selects private recovery is only waiting for its next run.
    {
        let _flag = test_mode::set(&wallet.path, TransparentLedgerMode::PrivateRequired);
        let waiting = balance(&wallet, &wallet.uuid);
        assert_eq!(
            waiting.transparent_authority,
            TransparentBalanceAuthority::LastKnown
        );
        assert_eq!(waiting.transparent_stop, None);
        assert_eq!(waiting.transparent_last_known, Some(VALUE));
        let reason = shield_reason(&wallet, &wallet.uuid);
        assert!(reason.contains(INCOMPLETE), "{reason}");
    }

    // Turning private queries off lowers the wallet in this build too.
    set_transparent_policy(&wallet.path, NETWORK, false, false)
        .await
        .unwrap()
        .unwrap();
    let public = balance(&wallet, &wallet.uuid);
    assert_eq!(public.transparent_stop, None);
    assert!(!public.transparent_private);
    assert_ne!(
        public.transparent_authority,
        TransparentBalanceAuthority::Stopped
    );
}

#[tokio::test]
async fn held_accounts_report_their_stop_reason() {
    let mut wallet = wallet();
    let (other_uuid, other) = add_account(&wallet);
    let ledger = import_ledger(&wallet);
    let _mode = activate(&mut wallet).await;
    let stop = |uuid: &str| {
        let balance = get_wallet_balance(&wallet.path, NETWORK, uuid).unwrap();
        assert!(balance.transparent_private);
        assert_eq!(balance.transparent, 0);
        match balance.transparent_stop {
            Some(_) => assert_eq!(
                balance.transparent_authority,
                TransparentBalanceAuthority::Stopped
            ),
            None => assert_ne!(
                balance.transparent_authority,
                TransparentBalanceAuthority::Stopped
            ),
        }
        balance.transparent_stop
    };
    let ledger_uuid = ledger.expose_uuid().to_string();

    // Not yet recovered: recovery may still restore authority.
    assert_eq!(stop(&wallet.uuid), None);
    // Ledger accounts are paused under `PrivateRequired`.
    assert_eq!(stop(&ledger_uuid), Some(TransparentStopReason::Ledger));

    for (cause, reason) in [
        (
            HoldCause::Withdrawn(WithdrawnCause::Equivocation),
            TransparentStopReason::Withdrawn,
        ),
        (
            HoldCause::LegacyDiscrepancy,
            TransparentStopReason::LegacyDiscrepancy,
        ),
        (HoldCause::Stalled, TransparentStopReason::Stalled),
    ] {
        set_hold(&wallet.path, wallet.account, cause, Instant::now());
        assert_eq!(stop(&wallet.uuid), Some(reason), "{cause:?}");
        // Only the held account stops.
        assert_eq!(stop(&other_uuid), None);
    }

    // A hold that ended no longer stops the account.
    let ended = Instant::now()
        .checked_sub(HOLD + Duration::from_secs(1))
        .unwrap();
    set_hold(&wallet.path, wallet.account, HoldCause::Stalled, ended);
    assert_eq!(stop(&wallet.uuid), None);

    // Quarantine outranks a hold: nothing lifts it.
    set_hold(&wallet.path, other, HoldCause::Stalled, Instant::now());
    quarantine(&wallet.path, other);
    assert_eq!(stop(&other_uuid), Some(TransparentStopReason::Quarantined));

    // An account with current authority is never stopped, held or not.
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    set_hold(
        &wallet.path,
        wallet.account,
        HoldCause::Stalled,
        Instant::now(),
    );
    let current = balance(&wallet, &wallet.uuid);
    assert_eq!(
        current.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(current.transparent_stop, None);
}

#[tokio::test]
async fn the_balance_read_adopts_inside_its_transaction() {
    let wallet = wallet();
    // A read handle opened while the wallet is public.
    let mut db =
        open_wallet_db_for_read_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let read = |db: &mut WalletDatabase| {
        read_wallet_balances(db, &wallet.path, NETWORK, &[wallet.account])
            .unwrap()
            .pop()
            .unwrap()
    };
    let public = read(&mut db);
    assert!(!public.transparent_private);
    assert_eq!(public.transparent_stop, None);

    // Another connection, such as a newer build, requires private recovery.
    apply_policy(&wallet.path, TransparentLedgerMode::PrivateRequired);
    assert!(
        matches!(
            db.transparent_ledger_mode(),
            Err(SqliteClientError::TransparentLedgerPolicyConflict { .. })
        ),
        "the handle itself is now weaker than the wallet"
    );

    // The read adopts the stricter policy in the transaction it reads in,
    // instead of failing or reporting suppressed funds as current.
    let private = read(&mut db);
    assert!(private.transparent_private);
    assert_eq!(
        private.transparent_authority,
        TransparentBalanceAuthority::Stopped
    );
    assert_eq!(
        private.transparent_stop,
        Some(TransparentStopReason::NotSelected)
    );
    assert_eq!(private.transparent, 0);
}
