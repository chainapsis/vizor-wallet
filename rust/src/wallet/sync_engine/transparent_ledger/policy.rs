//! Durable transparent policy transitions.
//!
//! Two paths change a wallet's durable policy: the private-queries setting
//! ([`set_transparent_policy`]) and the coordinator's raise of a wallet whose
//! policy is still weaker than this build selects ([`raise_to_required`]).
//! Both go through the policy fence, so no public lookup authorized under the
//! old policy is sent after the new one applies, and both decide under it, so
//! neither acts on a policy the other is about to change.
//!
//! A raise needs a selection of `PrivateRequired`, which only a build with the
//! development flag makes. Lowering needs an explicit toggle-off and works in
//! every build, so a default build can always return a private wallet to
//! public lookups. Nothing else weakens a wallet: handles adopt a durable
//! `PrivateRequired` instead.

use std::path::Path;
use std::time::Duration;

use zcash_client_backend::data_api::transparent_ledger::{
    AppliedTransparentPolicy, TransparentLedgerMode, TransparentLedgerRead,
};

use super::super::enhancement::select_transparent_mode;
use super::super::lwd::transparent_lookup::apply_transparent_policy_fenced_if;
use super::super::{SyncError, WalletDatabase};
use crate::wallet::db::{open_wallet_db_with_timeout, WALLET_DB_BUSY_TIMEOUT};
use crate::wallet::network::WalletNetwork;

/// How long a transition waits for public lookups in flight before failing
/// without applying anything.
pub(crate) const POLICY_DRAIN: Duration = Duration::from_secs(30);

/// Reconciles the durable policy of the wallet at `db_path` with the
/// private-queries setting, selecting from the arguments rather than the live
/// preference, so a rollback can raise again while the live preference is off.
///
/// - `true` raises to `PrivateRequired` when `build_flag` and `network` select
///   it and the applied policy is weaker. It never lowers, so startup, which
///   only ever passes `true`, cannot demote a wallet. When nothing is
///   selected, the wallet is not opened at all.
/// - `false` lowers to `Public` when the applied policy is anything else, in
///   every build.
///
/// The applied policy is read under the policy fence, so a raise that has
/// already decided to apply commits before this reads it: a toggle-off that
/// waits behind a raise lowers what the raise applied.
///
/// Returns the policy this call applied, or `None` when nothing needed to
/// change. A missing wallet is left missing.
pub(crate) async fn set_transparent_policy(
    db_path: &str,
    network: WalletNetwork,
    private_queries: bool,
    build_flag: bool,
) -> Result<Option<AppliedTransparentPolicy>, SyncError> {
    let target = if !private_queries {
        TransparentLedgerMode::Public
    } else if select_transparent_mode(network, true, build_flag)
        == TransparentLedgerMode::PrivateRequired
    {
        TransparentLedgerMode::PrivateRequired
    } else {
        return Ok(None);
    };
    if !Path::new(db_path).exists() {
        return Ok(None);
    }
    let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)
        .map_err(SyncError::db)?;
    // This handle only reads and applies the policy. The strictest mode reads
    // any durable policy, including one a raise commits after this open.
    db.set_transparent_ledger_mode(TransparentLedgerMode::PrivateRequired);
    let applied =
        apply_transparent_policy_fenced_if(&mut db, db_path, target, POLICY_DRAIN, |db| {
            Ok(applied_policy(db)?.mode != target)
        })
        .await?;
    if let Some(applied) = applied {
        log::info!("transparent policy: applied {:?}", applied.mode);
    }
    Ok(applied)
}

/// Raises the wallet behind `db` to `PrivateRequired` when its durable policy
/// is weaker and `may_raise` holds, both checked again under the fence. The
/// caller passes the live selection and confirmation, so a toggle-off that
/// lands while the raise waits for the fence wins.
///
/// Checking first keeps a raise that would apply nothing from taking the
/// fence of the wallet at `db_path`, which blocks its public lookups while it
/// waits.
///
/// Returns whether this call applied `PrivateRequired`.
pub(super) async fn raise_to_required(
    db: &mut WalletDatabase,
    db_path: &str,
    may_raise: impl Fn() -> bool,
) -> Result<bool, SyncError> {
    let weaker = |db: &WalletDatabase| -> Result<bool, SyncError> {
        Ok(applied_policy(db)?.mode != TransparentLedgerMode::PrivateRequired)
    };
    if !may_raise() || !weaker(db)? {
        return Ok(false);
    }
    let raised = apply_transparent_policy_fenced_if(
        db,
        db_path,
        TransparentLedgerMode::PrivateRequired,
        POLICY_DRAIN,
        |db| Ok(may_raise() && weaker(db)?),
    )
    .await?;
    Ok(raised.is_some())
}

fn applied_policy(db: &WalletDatabase) -> Result<AppliedTransparentPolicy, SyncError> {
    db.applied_transparent_policy()
        .map_err(|error| SyncError::db(format!("applied_transparent_policy: {error}")))
}
