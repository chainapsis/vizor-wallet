use rusqlite::Connection;

use crate::VotingError;

const CURRENT_VERSION: u32 = 17;

/// Schema version that `001_init.sql` produces, and the oldest version that can
/// be upgraded in place.
///
/// Databases below this predate launch, so no user state is worth preserving
/// and they are reset. At or above it, round state must survive: a wallet that
/// upgrades between submitting a delegation and casting its vote cannot
/// re-create the randomly sampled `van_comm_rand` that ZKP #2 needs, and the
/// deterministic governance nullifiers are already spent on chain, so its
/// voting weight for that round would be lost with no way to recover it.
const LAUNCH_VERSION: u32 = 13;

/// In-place upgrades applied in order, oldest first.
///
/// Entry `(from, sql)` moves a database from `user_version == from` to
/// `from + 1`, and the entries must form an unbroken chain from
/// [`LAUNCH_VERSION`] to [`CURRENT_VERSION`]. Every statement here MUST preserve
/// existing rows; `001_init.sql` is updated alongside so a fresh database and a
/// migrated one end up with the same schema.
const INCREMENTAL_MIGRATIONS: &[(u32, &str)] = &[
    (13, "ALTER TABLE rounds ADD COLUMN bundle_policy_json TEXT;"),
    // v15 replaces the bundle-scoped `imt_proofs` table with the bundle- and
    // round-independent `pir_proof_cache`. Existing proofs are carried over
    // (their network comes from the owning round) so an upgrade mid-round does
    // not refetch anything, then the old table is dropped.
    (
        14,
        "CREATE TABLE pir_proof_cache (
    wallet_id   TEXT NOT NULL DEFAULT '',
    network     TEXT NOT NULL CHECK (network IN ('mainnet','testnet','regtest')),
    nullifier   BLOB NOT NULL,
    root        BLOB NOT NULL,
    nf_bounds   BLOB NOT NULL,
    leaf_pos    INTEGER NOT NULL,
    path        BLOB NOT NULL,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    PRIMARY KEY (wallet_id, network, root, nullifier)
);
INSERT OR IGNORE INTO pir_proof_cache
    (wallet_id, network, nullifier, root, nf_bounds, leaf_pos, path, created_at, updated_at)
SELECT i.wallet_id, r.network, i.nullifier, i.root, i.nf_bounds, i.leaf_pos, i.path, i.created_at, i.created_at
FROM imt_proofs i
JOIN rounds r ON r.round_id = i.round_id AND r.wallet_id = i.wallet_id;
DROP TABLE imt_proofs;",
    ),
    (
        15,
        "ALTER TABLE share_delegations ADD COLUMN ambiguous_urls TEXT NOT NULL DEFAULT '[]';
ALTER TABLE share_delegations ADD COLUMN attempting_urls TEXT NOT NULL DEFAULT '[]';
ALTER TABLE share_delegations ADD COLUMN target_count INTEGER NOT NULL DEFAULT 0;",
    ),
    (
        16,
        "-- v3.1.0-rc.13 singleton recovery JSON predates atomic-batch metadata.
-- Normalize those released rows before plans can bind to their exact bytes so
-- confirmation reserialization changes only the VC tree position.
UPDATE votes
   SET commitment_bundle_json = json_set(
           json_set(
               json_set(commitment_bundle_json, '$.batch_digest', NULL),
               '$.batch_index', NULL
           ),
           '$.batch_size', NULL
       )
 WHERE CASE
           WHEN json_valid(commitment_bundle_json) THEN
               json_extract(commitment_bundle_json, '$.format') = 'zcash_voting_vote_recovery_v1'
               AND json_type(commitment_bundle_json, '$.batch_digest') IS NULL
               AND json_type(commitment_bundle_json, '$.batch_index') IS NULL
               AND json_type(commitment_bundle_json, '$.batch_size') IS NULL
           ELSE 0
       END;
CREATE TABLE helper_share_plans (
    round_id                    TEXT NOT NULL,
    wallet_id                   TEXT NOT NULL DEFAULT '',
    bundle_index                INTEGER NOT NULL,
    proposal_id                 INTEGER NOT NULL,
    commitment_bundle_json      TEXT NOT NULL,
    configured_server_urls_json TEXT NOT NULL,
    share_plans_json            TEXT NOT NULL,
    format_version              INTEGER NOT NULL CHECK (format_version = 1),
    placement_guarantee         TEXT NOT NULL CHECK (placement_guarantee IN ('strict','legacy_best_effort')),
    created_at                  INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, bundle_index, proposal_id),
    FOREIGN KEY (round_id, wallet_id, bundle_index, proposal_id)
        REFERENCES votes(round_id, wallet_id, bundle_index, proposal_id) ON DELETE CASCADE
);
CREATE TRIGGER clear_helper_share_plan_on_vote_generation_change
AFTER UPDATE OF commitment_bundle_json ON votes
WHEN OLD.commitment_bundle_json IS NOT NEW.commitment_bundle_json
BEGIN
    -- Confirmation is the one non-generational recovery update: it fills the
    -- VC tree position in both the vote column and the otherwise-identical
    -- recovery JSON. Advance only a plan bound to the exact OLD snapshot and
    -- only when replacing that one JSON field produces the exact NEW bytes.
    UPDATE helper_share_plans
       SET commitment_bundle_json = NEW.commitment_bundle_json
     WHERE round_id = NEW.round_id AND wallet_id = NEW.wallet_id
       AND bundle_index = NEW.bundle_index AND proposal_id = NEW.proposal_id
       AND commitment_bundle_json = OLD.commitment_bundle_json
       AND OLD.vc_tree_position IS NULL
       AND NEW.vc_tree_position IS NOT NULL
       AND json_set(
               OLD.commitment_bundle_json,
               '$.vc_tree_position',
               NEW.vc_tree_position
           ) = NEW.commitment_bundle_json;
    DELETE FROM helper_share_plans
     WHERE round_id = NEW.round_id AND wallet_id = NEW.wallet_id
       AND bundle_index = NEW.bundle_index AND proposal_id = NEW.proposal_id
       AND commitment_bundle_json IS NOT NEW.commitment_bundle_json;
END;",
    ),
];

const RESET_SQL: &str = "DROP TABLE IF EXISTS pir_proof_cache;
DROP TABLE IF EXISTS ballot_intent;
DROP TABLE IF EXISTS imt_proofs;
DROP TABLE IF EXISTS helper_share_plans;
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

    if version == CURRENT_VERSION {
        return Ok(());
    }

    let tx = conn.transaction().map_err(|e| VotingError::Internal {
        message: format!("failed to start database migration transaction: {}", e),
    })?;

    if version < LAUNCH_VERSION {
        tx.execute_batch(RESET_SQL)
            .map_err(|e| VotingError::Internal {
                message: format!("failed to reset pre-launch database schema: {}", e),
            })?;
        tx.execute_batch(include_str!("migrations/001_init.sql"))
            .map_err(|e| VotingError::Internal {
                message: format!("failed to create launch database schema: {}", e),
            })?;
    } else {
        // Launched databases hold delegation state that cannot be rebuilt, so
        // they are upgraded in place rather than recreated.
        let mut upgraded = version;
        for (from, sql) in INCREMENTAL_MIGRATIONS {
            if *from < upgraded {
                continue;
            }
            tx.execute_batch(sql).map_err(|e| VotingError::Internal {
                message: format!(
                    "failed to upgrade database schema from version {} to {}: {}",
                    from,
                    from + 1,
                    e
                ),
            })?;
            upgraded = from + 1;
        }
        if upgraded != CURRENT_VERSION {
            return Err(VotingError::Internal {
                message: format!(
                    "no upgrade path from database version {} to {}: incremental migrations stop at {}",
                    version, CURRENT_VERSION, upgraded
                ),
            });
        }
    }

    tx.pragma_update(None, "user_version", CURRENT_VERSION)
        .map_err(|e| VotingError::Internal {
            message: format!("failed to update database version: {}", e),
        })?;
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("failed to commit database migration: {}", e),
    })?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::queries;
    use crate::VotingRoundParams;
    use rusqlite::OptionalExtension;

    fn pre_v8_schema() -> String {
        include_str!("migrations/001_init.sql").replace("    note_identity_hashes_blob BLOB,\n", "")
    }

    /// Strips the `pir_proof_cache` table (added at version 15) from a schema.
    fn without_pir_proof_cache(schema: &str) -> String {
        let start = schema
            .find("CREATE TABLE pir_proof_cache")
            .expect("schema must contain the table added at version 15");
        let end = start
            + schema[start..]
                .find(");")
                .expect("pir_proof_cache DDL must be terminated")
            + ");".len();
        format!("{}{}", &schema[..start], &schema[end..])
    }

    /// Strips helper-delivery columns added at version 16.
    fn without_durable_ambiguous_deliveries(schema: &str) -> String {
        schema
            .replace("    ambiguous_urls  TEXT NOT NULL DEFAULT '[]',\n", "")
            .replace("    attempting_urls TEXT NOT NULL DEFAULT '[]',\n", "")
            .replace("    target_count    INTEGER NOT NULL DEFAULT 0,\n", "")
    }

    /// Strips the helper plan table and trigger added at version 17.
    fn without_helper_share_plans(schema: &str) -> String {
        let start = schema
            .find("CREATE TABLE helper_share_plans")
            .expect("schema must contain the table added at version 17");
        let next = schema[start..]
            .find("CREATE TABLE share_delegations")
            .expect("helper plan DDL must precede share delegations");
        format!("{}{}", &schema[..start], &schema[start + next..])
    }

    fn v16_schema() -> String {
        without_helper_share_plans(include_str!("migrations/001_init.sql"))
    }

    fn v15_schema() -> String {
        without_durable_ambiguous_deliveries(&v16_schema())
    }

    /// The bundle-scoped `imt_proofs` table that version 15 replaced with
    /// `pir_proof_cache`, exactly as `001_init.sql` created it through v14.
    const V14_IMT_PROOFS_SQL: &str = "CREATE TABLE imt_proofs (
    round_id       TEXT NOT NULL,
    wallet_id      TEXT NOT NULL DEFAULT '',
    bundle_index   INTEGER NOT NULL,
    nullifier      BLOB NOT NULL,
    root           BLOB NOT NULL,
    nf_bounds      BLOB NOT NULL,
    leaf_pos       INTEGER NOT NULL,
    path           BLOB NOT NULL,
    created_at     INTEGER NOT NULL,
    PRIMARY KEY (round_id, wallet_id, bundle_index, nullifier),
    FOREIGN KEY (round_id, wallet_id, bundle_index) REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);";

    /// The version-14 schema: no `pir_proof_cache` yet, `imt_proofs` still present.
    fn v14_schema() -> String {
        let v16 = v16_schema();
        let schema = without_durable_ambiguous_deliveries(&v16);
        format!(
            "{}\n{}\n",
            without_pir_proof_cache(&schema),
            V14_IMT_PROOFS_SQL
        )
    }

    /// The launch schema, before `bundle_policy_json` and `pir_proof_cache` were added.
    fn launch_schema() -> String {
        let schema = v14_schema();
        let stripped = schema.replace("    bundle_policy_json  TEXT,\n", "");
        assert_ne!(
            stripped, schema,
            "launch_schema must actually drop the column added at version 14"
        );
        stripped
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
        queries::insert_round(
            &conn,
            "wallet",
            crate::Network::Testnet,
            &test_params(),
            None,
        )
        .unwrap();
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
    fn migrate_from_launch_version_preserves_delegation_state() {
        // The case this migration exists for: a wallet that already submitted a
        // delegation upgrades before voting. `van_comm_rand` is sampled randomly
        // and its governance nullifiers are spent on chain, so losing the row
        // would cost that round's voting weight permanently.
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&launch_schema()).unwrap();
        queries::insert_round(
            &conn,
            "wallet",
            crate::Network::Testnet,
            &test_params(),
            None,
        )
        .unwrap();
        queries::insert_bundle(&conn, "test-round", "wallet", 0, &[1]).unwrap();
        conn.execute(
            "UPDATE bundles SET van_comm_rand = ?1, gov_comm = ?2
             WHERE round_id = 'test-round' AND wallet_id = 'wallet' AND bundle_index = 0",
            rusqlite::params![vec![0xAB_u8; 32], vec![0xCD_u8; 32]],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO share_delegations
             (round_id, wallet_id, bundle_index, proposal_id, share_index, sent_to_urls, nullifier, confirmed, submit_at, created_at)
             VALUES ('test-round', 'wallet', 0, 1, 0, '[\"https://helper.example\"]', X'01', 0, 100, 90)",
            [],
        )
        .unwrap();
        conn.pragma_update(None, "user_version", LAUNCH_VERSION)
            .unwrap();

        migrate(&mut conn).unwrap();

        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_VERSION);

        let (van_comm_rand, gov_comm): (Vec<u8>, Vec<u8>) = conn
            .query_row(
                "SELECT van_comm_rand, gov_comm FROM bundles
                 WHERE round_id = 'test-round' AND wallet_id = 'wallet' AND bundle_index = 0",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(van_comm_rand, vec![0xAB; 32]);
        assert_eq!(gov_comm, vec![0xCD; 32]);

        // The round survives and gains the new column, unset.
        let stored_policy: Option<String> = conn
            .query_row(
                "SELECT bundle_policy_json FROM rounds WHERE round_id = 'test-round'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert!(stored_policy.is_none());

        let delivery: (String, String, String, u32) = conn
            .query_row(
                "SELECT sent_to_urls, ambiguous_urls, attempting_urls, target_count
                 FROM share_delegations WHERE round_id = 'test-round' AND wallet_id = 'wallet'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!(delivery.0, "[\"https://helper.example\"]");
        assert_eq!(delivery.1, "[]");
        assert_eq!(delivery.2, "[]");
        assert_eq!(delivery.3, 0);
    }

    #[test]
    fn migrate_from_launch_version_matches_a_fresh_schema() {
        // A migrated database and a fresh one must be indistinguishable,
        // otherwise later queries work on only one of them.
        let mut migrated = Connection::open_in_memory().unwrap();
        migrated.execute_batch(&launch_schema()).unwrap();
        migrated
            .pragma_update(None, "user_version", LAUNCH_VERSION)
            .unwrap();
        migrate(&mut migrated).unwrap();

        let mut fresh = Connection::open_in_memory().unwrap();
        migrate(&mut fresh).unwrap();

        for table in [
            "rounds",
            "bundles",
            "votes",
            "helper_share_plans",
            "share_delegations",
            "pir_proof_cache",
        ] {
            assert_eq!(
                table_columns(&migrated, table),
                table_columns(&fresh, table),
                "column mismatch in {table}"
            );
        }
        assert_eq!(
            schema_sql(
                &migrated,
                "trigger",
                "clear_helper_share_plan_on_vote_generation_change"
            ),
            schema_sql(
                &fresh,
                "trigger",
                "clear_helper_share_plan_on_vote_generation_change"
            ),
            "migrated and fresh schemas must install the same plan lifecycle trigger"
        );
    }

    #[test]
    fn migrate_v16_to_v17_installs_plan_lifecycle_invariants() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&v16_schema()).unwrap();
        conn.pragma_update(None, "user_version", 16).unwrap();

        migrate(&mut conn).unwrap();

        assert_eq!(
            conn.pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
                .unwrap(),
            CURRENT_VERSION
        );
        assert_helper_plan_lifecycle(&conn);
    }

    #[test]
    fn migrate_v15_recovery_json_preserves_plan_only_through_confirmation() {
        const ROUND_ID: &str = "1111111111111111111111111111111111111111111111111111111111111111";
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&v15_schema()).unwrap();
        let mut params = test_params();
        params.vote_round_id = ROUND_ID.to_string();
        queries::insert_round(&conn, "wallet", crate::Network::Testnet, &params, None).unwrap();
        queries::insert_bundle(&conn, ROUND_ID, "wallet", 0, &[1]).unwrap();
        queries::store_vote(&conn, ROUND_ID, "wallet", 0, 1, 2, &[0xCA; 32]).unwrap();
        queries::store_vote(&conn, ROUND_ID, "wallet", 0, 2, 1, &[0xCB; 32]).unwrap();

        let released_json = released_singleton_recovery_json(ROUND_ID);
        assert!(!released_json.contains("\"batch_digest\""));
        let batch_json = r#"{"format":"zcash_voting_vote_batch_recovery_v1","batch_digest":[1],"batch_index":0,"batch_size":1}"#;
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = ?1
             WHERE round_id = ?2 AND wallet_id = 'wallet'
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::params![released_json, ROUND_ID],
        )
        .unwrap();
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = ?1
             WHERE round_id = ?2 AND wallet_id = 'wallet'
               AND bundle_index = 0 AND proposal_id = 2",
            rusqlite::params![batch_json, ROUND_ID],
        )
        .unwrap();
        conn.pragma_update(None, "user_version", 15).unwrap();

        migrate(&mut conn).unwrap();

        let normalized =
            crate::vote::serialize_recovery(&crate::vote::parse_recovery(&released_json).unwrap())
                .unwrap();
        let stored: String = conn
            .query_row(
                "SELECT commitment_bundle_json FROM votes
                 WHERE round_id = ?1 AND wallet_id = 'wallet'
                   AND bundle_index = 0 AND proposal_id = 1",
                [ROUND_ID],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(stored, normalized);
        assert!(stored.contains("\"batch_digest\":null"));
        let stored_batch: String = conn
            .query_row(
                "SELECT commitment_bundle_json FROM votes
                 WHERE round_id = ?1 AND wallet_id = 'wallet'
                   AND bundle_index = 0 AND proposal_id = 2",
                [ROUND_ID],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(stored_batch, batch_json);
        insert_helper_plan_for_round(&conn, ROUND_ID, &stored);

        let mut confirmed =
            crate::vote::parse_recovery(&stored).expect("normalized recovery must remain valid");
        confirmed.vc_tree_position = 789;
        let confirmed_json = crate::vote::serialize_recovery(&confirmed).unwrap();
        conn.execute(
            "UPDATE votes
                SET commitment_bundle_json = ?1, vc_tree_position = 789
              WHERE round_id = ?2 AND wallet_id = 'wallet'
                AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::params![confirmed_json, ROUND_ID],
        )
        .unwrap();
        assert_eq!(
            stored_plan_snapshot_for_round(&conn, ROUND_ID).as_deref(),
            Some(confirmed_json.as_str())
        );

        let replacement_json =
            confirmed_json.replacen("\"vote_decision\":2", "\"vote_decision\":1", 1);
        assert_ne!(replacement_json, confirmed_json);
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = ?1
             WHERE round_id = ?2 AND wallet_id = 'wallet'
               AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::params![replacement_json, ROUND_ID],
        )
        .unwrap();
        assert_eq!(stored_plan_snapshot_for_round(&conn, ROUND_ID), None);
    }

    #[test]
    fn fresh_schema_enforces_plan_lifecycle_invariants() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();

        assert_helper_plan_lifecycle(&conn);
    }

    #[test]
    fn migrate_from_v14_creates_pir_proof_cache_and_preserves_state() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&v14_schema()).unwrap();
        queries::insert_round(
            &conn,
            "wallet",
            crate::Network::Testnet,
            &test_params(),
            None,
        )
        .unwrap();
        queries::insert_bundle(&conn, "test-round", "wallet", 0, &[1]).unwrap();
        // A cached proof from the old bundle-scoped table; v15 must carry it
        // over so an upgrade mid-round does not refetch from the PIR server.
        conn.execute(
            "INSERT INTO imt_proofs (round_id, wallet_id, bundle_index, nullifier, root, nf_bounds, leaf_pos, path, created_at)
             VALUES ('test-round', 'wallet', 0, X'01', X'02', X'03', 7, X'04', 42)",
            [],
        )
        .unwrap();
        conn.pragma_update(None, "user_version", 14).unwrap();

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
        assert_eq!(round_count, 1);

        // The old proof row was migrated, keyed by the round's network, with
        // updated_at seeded from created_at.
        let migrated_row: (String, Vec<u8>, i64, i64, i64) = conn
            .query_row(
                "SELECT network, root, leaf_pos, created_at, updated_at
                 FROM pir_proof_cache WHERE wallet_id = 'wallet' AND nullifier = X'01'",
                [],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    ))
                },
            )
            .unwrap();
        assert_eq!(migrated_row, ("testnet".to_string(), vec![0x02], 7, 42, 42));

        // The old table is gone...
        assert!(!table_names(&conn).contains(&"imt_proofs".to_string()));

        // ...and the new one is usable.
        conn.execute(
            "INSERT INTO pir_proof_cache (wallet_id, network, nullifier, root, nf_bounds, leaf_pos, path, created_at, updated_at)
             VALUES ('wallet', 'testnet', X'05', X'02', X'03', 0, X'04', 0, 0)",
            [],
        )
        .unwrap();
    }

    #[test]
    fn incremental_migrations_form_an_unbroken_chain_to_current() {
        let mut expected = LAUNCH_VERSION;
        for (from, _) in INCREMENTAL_MIGRATIONS {
            assert_eq!(
                *from, expected,
                "incremental migrations must be ordered and contiguous"
            );
            expected = from + 1;
        }
        assert_eq!(
            expected, CURRENT_VERSION,
            "every version from LAUNCH_VERSION to CURRENT_VERSION needs a migration step"
        );
    }

    #[test]
    fn test_migrate_from_pre_v8_schema_recreates_current_schema() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&pre_v8_schema()).unwrap();
        conn.pragma_update(None, "user_version", 7).unwrap();

        migrate(&mut conn).unwrap();

        let columns = table_columns(&conn, "bundles");
        assert!(columns.contains(&"note_identity_hashes_blob".to_string()));
        assert!(columns.contains(&"tx1_effects".to_string()));
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
        // Replaced by pir_proof_cache at v15.
        assert!(!tables.contains(&"imt_proofs".to_string()));
        assert!(tables.contains(&"share_delegations".to_string()));
        assert!(tables.contains(&"helper_share_plans".to_string()));
        assert!(tables.contains(&"keystone_signatures".to_string()));
        assert!(tables.contains(&"ballot_intent".to_string()));
        assert!(tables.contains(&"pir_proof_cache".to_string()));

        let round_columns = table_columns(&conn, "rounds");
        assert!(round_columns.contains(&"network".to_string()));
    }

    /// Verify that the bundles table columns exist after migration and can round-trip BLOB data.
    #[test]
    fn test_bundle_data_columns_exist() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();

        // Insert a round first
        conn.execute(
            "INSERT INTO rounds (round_id, wallet_id, network, snapshot_height, ea_pk, nc_root, nullifier_imt_root, phase, created_at) VALUES ('test', 'w1', 'testnet', 1, X'00', X'00', X'00', 0, 0)",
            [],
        ).unwrap();

        // Insert a bundle row using the delegation BLOB columns.
        conn.execute(
            "INSERT INTO bundles (round_id, wallet_id, bundle_index, van_comm_rand, dummy_nullifiers, rho_signed, padded_note_data, nf_signed, cmx_new, alpha, rseed_signed, rseed_output, tx1_effects) VALUES ('test', 'w1', 0, X'AA', X'BB', X'CC', X'DD', X'EE', X'FF', X'11', X'22', X'33', X'44')",
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

        let tx1_effects: Vec<u8> = conn
            .query_row(
                "SELECT tx1_effects FROM bundles WHERE round_id = 'test' AND bundle_index = 0",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(tx1_effects, vec![0x44]);
    }

    fn table_columns(conn: &Connection, table: &str) -> Vec<String> {
        conn.prepare(&format!("PRAGMA table_info({table})"))
            .unwrap()
            .query_map([], |row| row.get(1))
            .unwrap()
            .collect::<Result<Vec<String>, _>>()
            .unwrap()
    }

    fn table_names(conn: &Connection) -> Vec<String> {
        conn.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            .unwrap()
            .query_map([], |row| row.get(0))
            .unwrap()
            .collect::<Result<Vec<String>, _>>()
            .unwrap()
    }

    fn schema_sql(conn: &Connection, object_type: &str, name: &str) -> String {
        conn.query_row(
            "SELECT sql FROM sqlite_master WHERE type = ?1 AND name = ?2",
            rusqlite::params![object_type, name],
            |row| row.get(0),
        )
        .unwrap()
    }

    fn assert_helper_plan_lifecycle(conn: &Connection) {
        conn.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        queries::insert_round(
            conn,
            "wallet",
            crate::Network::Testnet,
            &test_params(),
            None,
        )
        .unwrap();
        queries::insert_bundle(conn, "test-round", "wallet", 0, &[1]).unwrap();
        queries::store_vote(conn, "test-round", "wallet", 0, 1, 0, &[0xCA; 32]).unwrap();
        let before = r#"{"vc_tree_position":0,"marker":"same"}"#;
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = ?1
             WHERE round_id = 'test-round' AND wallet_id = 'wallet'
               AND bundle_index = 0 AND proposal_id = 1",
            [before],
        )
        .unwrap();
        insert_helper_plan(conn, before);

        let confirmed = r#"{"vc_tree_position":7,"marker":"same"}"#;
        conn.execute(
            "UPDATE votes
                SET commitment_bundle_json = ?1, vc_tree_position = 7
              WHERE round_id = 'test-round' AND wallet_id = 'wallet'
                AND bundle_index = 0 AND proposal_id = 1",
            [confirmed],
        )
        .unwrap();
        assert_eq!(stored_plan_snapshot(conn).as_deref(), Some(confirmed));

        // A non-confirmation recovery-material change is a new generation,
        // even when it retains the already-confirmed VC position.
        let replacement = r#"{"vc_tree_position":7,"marker":"replacement"}"#;
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = ?1
             WHERE round_id = 'test-round' AND wallet_id = 'wallet'
               AND bundle_index = 0 AND proposal_id = 1",
            [replacement],
        )
        .unwrap();
        assert_eq!(stored_plan_snapshot(conn), None);

        insert_helper_plan(conn, replacement);
        conn.execute(
            "DELETE FROM votes
             WHERE round_id = 'test-round' AND wallet_id = 'wallet'
               AND bundle_index = 0 AND proposal_id = 1",
            [],
        )
        .unwrap();
        assert_eq!(stored_plan_snapshot(conn), None);
    }

    fn insert_helper_plan(conn: &Connection, snapshot: &str) {
        insert_helper_plan_for_round(conn, "test-round", snapshot);
    }

    fn insert_helper_plan_for_round(conn: &Connection, round_id: &str, snapshot: &str) {
        conn.execute(
            "INSERT INTO helper_share_plans
             (round_id, wallet_id, bundle_index, proposal_id,
              commitment_bundle_json, configured_server_urls_json,
              share_plans_json, format_version, placement_guarantee, created_at)
             VALUES (?1, 'wallet', 0, 1, ?2, '[\"https://helper.example\"]',
                     '[]', 1, 'strict', 1)",
            rusqlite::params![round_id, snapshot],
        )
        .unwrap();
    }

    fn released_singleton_recovery_json(round_id: &str) -> String {
        let released_shape = serde_json::to_string(&serde_json::json!({
            "format": "zcash_voting_vote_recovery_v1",
            "vote_round_id": round_id,
            "bundle_index": 0,
            "proposal_id": 1,
            "vote_decision": 2,
            "anchor_height": 100,
            "vc_tree_position": 0,
            "single_share": false,
            "num_options": 3,
            "van_nullifier": vec![0x31_u8; 32],
            "vote_authority_note_new": vec![0x32_u8; 32],
            "vote_commitment": vec![0x33_u8; 32],
            "proof": vec![0x34_u8; 8],
            "shares_hash": vec![0x35_u8; 32],
            "r_vpk": vec![0x36_u8; 32],
            "alpha_v": vec![0x37_u8; 32],
            "vote_auth_sig": vec![0x38_u8; 64],
            "encrypted_shares": [],
            "share_blinds": [],
            "share_comms": [],
        }))
        .unwrap();
        let canonical_with_batch_nulls =
            crate::vote::serialize_recovery(&crate::vote::parse_recovery(&released_shape).unwrap())
                .unwrap();
        canonical_with_batch_nulls
            .strip_suffix(",\"batch_digest\":null,\"batch_index\":null,\"batch_size\":null}")
            .map(|prefix| format!("{prefix}}}"))
            .expect("current singleton recovery must append nullable batch metadata")
    }

    fn stored_plan_snapshot(conn: &Connection) -> Option<String> {
        stored_plan_snapshot_for_round(conn, "test-round")
    }

    fn stored_plan_snapshot_for_round(conn: &Connection, round_id: &str) -> Option<String> {
        conn.query_row(
            "SELECT commitment_bundle_json FROM helper_share_plans
             WHERE round_id = ?1 AND wallet_id = 'wallet'
               AND bundle_index = 0 AND proposal_id = 1",
            [round_id],
            |row| row.get(0),
        )
        .optional()
        .unwrap()
    }
}
