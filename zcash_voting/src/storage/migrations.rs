use rusqlite::Connection;

use crate::VotingError;

const CURRENT_VERSION: u32 = 11;

const RESET_SQL: &str = "DROP TABLE IF EXISTS ballot_intent;
DROP TABLE IF EXISTS imt_proofs;
DROP TABLE IF EXISTS share_delegations;
DROP TABLE IF EXISTS keystone_signatures;
DROP TABLE IF EXISTS votes;
DROP TABLE IF EXISTS witnesses;
DROP TABLE IF EXISTS proofs;
DROP TABLE IF EXISTS bundles;
DROP TABLE IF EXISTS cached_tree_state;
DROP TABLE IF EXISTS rounds;";

pub fn migrate(conn: &mut Connection) -> Result<(), VotingError> {
    let version: u32 = conn
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read database version: {}", e),
        })?;

    if version > CURRENT_VERSION {
        return Err(VotingError::Internal {
            message: format!(
                "unsupported newer database version: expected at most {}, got {}",
                CURRENT_VERSION, version
            ),
        });
    }

    if version < CURRENT_VERSION {
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("failed to start database migration transaction: {}", e),
        })?;
        tx.execute_batch(RESET_SQL)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to reset pre-launch database schema: {}", e),
            })?;
        tx.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("failed to create launch database schema: {}", e),
            })?;
        tx.pragma_update(None, "user_version", CURRENT_VERSION)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("failed to commit database migration: {}", e),
        })?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::queries;
    use crate::VotingRoundParams;

    fn pre_v8_schema() -> String {
        include_str!("migrations/001_init.sql").replace("    note_identity_hashes_blob BLOB,\n", "")
    }

    fn test_params() -> VotingRoundParams {
        VotingRoundParams {
            vote_round_id: "test-round".to_string(),
            snapshot_height: 1000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    #[test]
    fn test_migrate_fresh_database() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_VERSION);
    }

    #[test]
    fn test_migrate_idempotent() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        migrate(&mut conn).unwrap();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_VERSION);
    }

    #[test]
    fn test_migrate_from_prelaunch_version_resets_existing_state() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(include_str!("migrations/001_init.sql"))
            .unwrap();
        queries::insert_round(&conn, "wallet", &test_params(), None).unwrap();
        queries::insert_bundle(&conn, "test-round", "wallet", 0, &[1]).unwrap();
        conn.pragma_update(None, "user_version", 8).unwrap();

        migrate(&mut conn).unwrap();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_VERSION);

        let round_count: u32 = conn
            .query_row(
                "SELECT COUNT(*) FROM rounds WHERE round_id = 'test-round'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(round_count, 0);
    }

    #[test]
    fn test_migrate_from_pre_v8_schema_recreates_current_schema() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&pre_v8_schema()).unwrap();
        conn.pragma_update(None, "user_version", 7).unwrap();

        migrate(&mut conn).unwrap();

        let columns = table_columns(&conn, "bundles");
        assert!(columns.contains(&"note_identity_hashes_blob".to_string()));
    }

    #[test]
    fn test_migrate_rejects_newer_database_version() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.pragma_update(None, "user_version", CURRENT_VERSION + 1)
            .unwrap();

        let err = migrate(&mut conn).unwrap_err();
        assert!(
            err.to_string()
                .contains("unsupported newer database version"),
            "{err}"
        );
    }

    #[test]
    fn test_tables_created() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();

        let tables: Vec<String> = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            .unwrap()
            .query_map([], |row| row.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();

        assert!(tables.contains(&"rounds".to_string()));
        assert!(tables.contains(&"bundles".to_string()));
        assert!(tables.contains(&"cached_tree_state".to_string()));
        assert!(tables.contains(&"proofs".to_string()));
        assert!(tables.contains(&"votes".to_string()));
        assert!(tables.contains(&"imt_proofs".to_string()));
        assert!(tables.contains(&"share_delegations".to_string()));
        assert!(tables.contains(&"keystone_signatures".to_string()));
        assert!(tables.contains(&"ballot_intent".to_string()));
    }

    /// Verify that the bundles table columns exist after migration and can round-trip BLOB data.
    #[test]
    fn test_bundle_data_columns_exist() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();

        // Insert a round first
        conn.execute(
            "INSERT INTO rounds (round_id, wallet_id, snapshot_height, ea_pk, nc_root, nullifier_imt_root, phase, created_at) VALUES ('test', 'w1', 1, X'00', X'00', X'00', 0, 0)",
            [],
        ).unwrap();

        // Insert a bundle row using all nullable BLOB columns.
        conn.execute(
            "INSERT INTO bundles (round_id, wallet_id, bundle_index, van_comm_rand, dummy_nullifiers, rho_signed, padded_note_data, nf_signed, cmx_new, alpha, rseed_signed, rseed_output) VALUES ('test', 'w1', 0, X'AA', X'BB', X'CC', X'DD', X'EE', X'FF', X'11', X'22', X'33')",
            [],
        ).unwrap();

        // Verify van_comm_rand round-trips (the VAN blinding factor)
        let rand: Vec<u8> = conn
            .query_row(
                "SELECT van_comm_rand FROM bundles WHERE round_id = 'test' AND bundle_index = 0",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(rand, vec![0xAA]);

        // Verify dummy_nullifiers round-trips
        let dummies: Vec<u8> = conn
            .query_row(
                "SELECT dummy_nullifiers FROM bundles WHERE round_id = 'test' AND bundle_index = 0",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(dummies, vec![0xBB]);
    }

    fn table_columns(conn: &Connection, table: &str) -> Vec<String> {
        conn.prepare(&format!("PRAGMA table_info({table})"))
            .unwrap()
            .query_map([], |row| row.get(1))
            .unwrap()
            .collect::<Result<Vec<String>, _>>()
            .unwrap()
    }
}
