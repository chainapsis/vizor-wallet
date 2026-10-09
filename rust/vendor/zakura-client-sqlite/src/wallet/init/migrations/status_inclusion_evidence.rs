//! Durable provenance-backed lower bounds for private status observations.
use super::{
    fix_bad_ironwood_change_flagging, ironwood_enhance,
    orchard_ironwood_migration_unsatisfiability, tree_retained_checkpoints,
    v_address_uses_ironwood,
};
use crate::wallet::init::WalletMigrationError;
use schemerz_rusqlite::RusqliteMigration;
use std::collections::HashSet;
use uuid::Uuid;

/// Widens local bounds whose historical rewind handling cannot be established.
pub const MIGRATION_ID: Uuid = Uuid::from_u128(0xb6f3d060_803a_4b17_aecd_6a02d9cb2249);
pub(super) struct Migration;
impl schemerz::Migration<Uuid> for Migration {
    fn id(&self) -> Uuid {
        MIGRATION_ID
    }
    fn dependencies(&self) -> HashSet<Uuid> {
        [
            ironwood_enhance::MIGRATION_ID,
            orchard_ironwood_migration_unsatisfiability::MIGRATION_ID,
            v_address_uses_ironwood::MIGRATION_ID,
            fix_bad_ironwood_change_flagging::MIGRATION_ID,
            tree_retained_checkpoints::MIGRATION_ID,
        ]
        .into_iter()
        .collect()
    }
    fn description(&self) -> &'static str {
        "Widen legacy local status inclusion bounds conservatively after historical rewinds."
    }
}
impl RusqliteMigration for Migration {
    type Error = WalletMigrationError;
    fn up(&self, conn: &rusqlite::Transaction) -> Result<(), Self::Error> {
        // Old code did not preserve the earliest possible inclusion across rewinds. Local
        // target provenance is known, but its historical bound is not; widen it to genesis.
        // Imported transactions (without a local target) keep their observation semantics.
        conn.execute(
            "UPDATE transactions SET min_observed_height = 0 WHERE target_height IS NOT NULL",
            [],
        )?;
        Ok(())
    }
    fn down(&self, _: &rusqlite::Transaction) -> Result<(), Self::Error> {
        Err(WalletMigrationError::CannotRevert(MIGRATION_ID))
    }
}
#[cfg(test)]
mod tests {
    #[test]
    fn migrate() {
        crate::wallet::init::migrations::tests::test_migrate(&[super::MIGRATION_ID]);
    }
    #[test]
    fn legacy_local_bounds_widen_without_changing_schema_or_imports() {
        use schemerz_rusqlite::RusqliteMigration;
        let mut conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch("CREATE TABLE transactions (txid BLOB, target_height INTEGER, min_observed_height INTEGER NOT NULL, expiry_height INTEGER, mined_height INTEGER);
            INSERT INTO transactions VALUES (X'01', 500, 500, 540, NULL), (X'02', NULL, 600, NULL, NULL), (X'03', 400, 450, NULL, NULL);").unwrap();
        let schema: String = conn
            .query_row(
                "SELECT sql FROM sqlite_schema WHERE name = 'transactions'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let tx = conn.transaction().unwrap();
        super::Migration.up(&tx).unwrap();
        tx.commit().unwrap();
        let heights = conn
            .prepare("SELECT min_observed_height FROM transactions ORDER BY txid")
            .unwrap()
            .query_map([], |r| r.get::<_, u32>(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(heights, vec![0, 600, 0]);
        let after: String = conn
            .query_row(
                "SELECT sql FROM sqlite_schema WHERE name = 'transactions'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(schema, after);
        // Widening private coverage must not make unknown-expiry local transactions expire early.
        let live: bool = conn
            .query_row(
                &format!(
                    "SELECT {} FROM transactions t WHERE txid = X'03'",
                    crate::wallet::common::tx_unexpired_condition("t")
                ),
                rusqlite::named_params![":target_height": 401],
                |r| r.get(0),
            )
            .unwrap();
        assert!(live);
    }
}
