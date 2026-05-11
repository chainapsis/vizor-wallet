use rusqlite::Connection;

use crate::VotingError;

const CURRENT_VERSION: u32 = 8;

fn column_exists(conn: &Connection, table: &str, column: &str) -> Result<bool, VotingError> {
    let mut stmt = conn
        .prepare(&format!("PRAGMA table_info({table})"))
        .map_err(|e| VotingError::Internal {
            message: format!("failed to inspect {table} columns: {e}"),
        })?;
    let columns = stmt
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query {table} columns: {e}"),
        })?;

    for name in columns {
        let name = name.map_err(|e| VotingError::Internal {
            message: format!("failed to read {table} column name: {e}"),
        })?;
        if name == column {
            return Ok(true);
        }
    }

    Ok(false)
}

pub fn migrate(conn: &Connection) -> Result<(), VotingError> {
    let version: u32 = conn
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read database version: {}", e),
        })?;

    if version < 1 {
        conn.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("migration 001_init failed: {}", e),
            })?;
        conn.pragma_update(None, "user_version", 1)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    if version < 2 {
        // Add tables for witness caching that were added to 001_init.sql
        // after some DBs had already been created at version 1.
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS cached_tree_state (
                round_id        TEXT PRIMARY KEY REFERENCES rounds(round_id),
                snapshot_height INTEGER NOT NULL,
                tree_state      BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS witnesses (
                round_id        TEXT NOT NULL,
                note_position   INTEGER NOT NULL,
                note_commitment BLOB NOT NULL,
                root            BLOB NOT NULL,
                auth_path       BLOB NOT NULL,
                created_at      INTEGER NOT NULL,
                PRIMARY KEY (round_id, note_position),
                FOREIGN KEY (round_id) REFERENCES rounds(round_id)
            );",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("migration to version 2 failed: {}", e),
        })?;
        conn.pragma_update(None, "user_version", 2)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    if version < 3 {
        // v3: delegation data moved from rounds to bundles table, witnesses
        // gained bundle_index. Drop everything and recreate from 001_init.sql.
        // The drop list must cover every table in 001_init.sql so a fresh DB
        // can chain through later drop-all migrations without colliding on a
        // newer table introduced by a subsequent version.
        conn.execute_batch(
            "DROP TABLE IF EXISTS imt_proofs;
             DROP TABLE IF EXISTS share_delegations;
             DROP TABLE IF EXISTS keystone_signatures;
             DROP TABLE IF EXISTS votes;
             DROP TABLE IF EXISTS witnesses;
             DROP TABLE IF EXISTS proofs;
             DROP TABLE IF EXISTS bundles;
             DROP TABLE IF EXISTS cached_tree_state;
             DROP TABLE IF EXISTS rounds;",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("migration to version 3 failed (drop): {}", e),
        })?;
        conn.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("migration to version 3 failed (create): {}", e),
            })?;
        conn.pragma_update(None, "user_version", 3)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    if version < 4 {
        // v4: add wallet_id column for per-wallet state isolation.
        // Drop everything and recreate from 001_init.sql.
        conn.execute_batch(
            "DROP TABLE IF EXISTS imt_proofs;
             DROP TABLE IF EXISTS share_delegations;
             DROP TABLE IF EXISTS keystone_signatures;
             DROP TABLE IF EXISTS votes;
             DROP TABLE IF EXISTS witnesses;
             DROP TABLE IF EXISTS proofs;
             DROP TABLE IF EXISTS bundles;
             DROP TABLE IF EXISTS cached_tree_state;
             DROP TABLE IF EXISTS rounds;",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("migration to version 4 failed (drop): {}", e),
        })?;
        conn.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("migration to version 4 failed (create): {}", e),
            })?;
        conn.pragma_update(None, "user_version", 4)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    if version < 5 {
        // v5: add share_delegations, keystone_signatures tables; add columns to
        // bundles (delegation_tx_hash) and votes (tx_hash, vc_tree_position,
        // commitment_bundle_json). Drop-all-recreate for pre-production.
        conn.execute_batch(
            "DROP TABLE IF EXISTS imt_proofs;
             DROP TABLE IF EXISTS share_delegations;
             DROP TABLE IF EXISTS keystone_signatures;
             DROP TABLE IF EXISTS votes;
             DROP TABLE IF EXISTS witnesses;
             DROP TABLE IF EXISTS proofs;
             DROP TABLE IF EXISTS bundles;
             DROP TABLE IF EXISTS cached_tree_state;
             DROP TABLE IF EXISTS rounds;",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("migration to version 5 failed (drop): {}", e),
        })?;
        conn.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("migration to version 5 failed (create): {}", e),
            })?;
        conn.pragma_update(None, "user_version", 5)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    if version < 6 {
        // v6: share_delegations schema change: helper_url -> sent_to_urls (JSON array),
        // add submit_at column for share timing tracking.
        // Drop-all-recreate for pre-production.
        conn.execute_batch(
            "DROP TABLE IF EXISTS imt_proofs;
             DROP TABLE IF EXISTS share_delegations;
             DROP TABLE IF EXISTS keystone_signatures;
             DROP TABLE IF EXISTS votes;
             DROP TABLE IF EXISTS witnesses;
             DROP TABLE IF EXISTS proofs;
             DROP TABLE IF EXISTS bundles;
             DROP TABLE IF EXISTS cached_tree_state;
             DROP TABLE IF EXISTS rounds;",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("migration to version 6 failed (drop): {}", e),
        })?;
        conn.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("migration to version 6 failed (create): {}", e),
            })?;
        conn.pragma_update(None, "user_version", 6)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    if version < 7 {
        // v7: add imt_proofs cache table for pre-submit PIR lookup.
        // Drop-all-recreate for pre-production, matching the previous voting DB migrations.
        conn.execute_batch(
            "DROP TABLE IF EXISTS imt_proofs;
             DROP TABLE IF EXISTS share_delegations;
             DROP TABLE IF EXISTS keystone_signatures;
             DROP TABLE IF EXISTS votes;
             DROP TABLE IF EXISTS witnesses;
             DROP TABLE IF EXISTS proofs;
             DROP TABLE IF EXISTS bundles;
             DROP TABLE IF EXISTS cached_tree_state;
             DROP TABLE IF EXISTS rounds;",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("migration to version 7 failed (drop): {}", e),
        })?;
        conn.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("migration to version 7 failed (create): {}", e),
            })?;
        conn.pragma_update(None, "user_version", 7)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    if version < 8 {
        // v8: persist full bundle note identity hashes so later workflow steps
        // can reject same-position note substitutions. Fresh DBs and drop-all
        // migrations already get the column from 001_init.sql, so guard the
        // ALTER for those paths.
        if !column_exists(conn, "bundles", "note_identity_hashes_blob")? {
            conn.execute_batch("ALTER TABLE bundles ADD COLUMN note_identity_hashes_blob BLOB;")
                .map_err(|e| VotingError::Internal {
                    message: format!("migration to version 8 failed: {}", e),
                })?;
        }
        conn.pragma_update(None, "user_version", 8)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update database version: {}", e),
            })?;
    }

    let final_version: u32 = conn
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(|e| VotingError::Internal {
            message: format!("failed to verify database version: {}", e),
        })?;

    if final_version != CURRENT_VERSION {
        return Err(VotingError::Internal {
            message: format!(
                "unexpected database version after migration: expected {}, got {}",
                CURRENT_VERSION, final_version
            ),
        });
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::queries;
    use crate::VotingRoundParams;

    fn v7_schema() -> String {
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
        let conn = Connection::open_in_memory().unwrap();
        migrate(&conn).unwrap();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_VERSION);
    }

    #[test]
    fn test_migrate_idempotent() {
        let conn = Connection::open_in_memory().unwrap();
        migrate(&conn).unwrap();
        migrate(&conn).unwrap();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_VERSION);
    }

    #[test]
    fn test_migrate_from_v7_preserves_existing_bundles() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&v7_schema()).unwrap();
        queries::insert_round(&conn, "wallet", &test_params(), None).unwrap();
        queries::insert_bundle(&conn, "test-round", "wallet", 0, &[1]).unwrap();
        conn.pragma_update(None, "user_version", 7).unwrap();

        migrate(&conn).unwrap();

        let (positions, identity_hashes): (Vec<u8>, Option<Vec<u8>>) = conn
            .query_row(
                "SELECT note_positions_blob, note_identity_hashes_blob FROM bundles
                 WHERE round_id = 'test-round' AND wallet_id = 'wallet' AND bundle_index = 0",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(positions, 1u64.to_le_bytes().to_vec());
        assert_eq!(identity_hashes, None);
    }

    #[test]
    fn test_tables_created() {
        let conn = Connection::open_in_memory().unwrap();
        migrate(&conn).unwrap();

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
        assert!(tables.contains(&"share_delegations".to_string()));
        assert!(tables.contains(&"keystone_signatures".to_string()));
    }

    /// Verify that the bundles table columns exist after migration and can round-trip BLOB data.
    #[test]
    fn test_bundle_data_columns_exist() {
        let conn = Connection::open_in_memory().unwrap();
        migrate(&conn).unwrap();

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
}
