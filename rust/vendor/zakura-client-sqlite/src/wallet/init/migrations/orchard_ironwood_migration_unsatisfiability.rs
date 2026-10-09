//! Renames the pool-migration transfer ordinal from `tx_id` to `transfer_id`, adds the
//! `unsatisfiable_at`, `unsatisfiable_kind`, and `broadcast_failure_at` columns to
//! `orchard_ironwood_migration_transactions`, creates the
//! `orchard_ironwood_migration_spend_nullifiers` table and backfills the nullifier cache into it
//! for existing rows, restores the erased `txid` of every `mined` row, and adds the
//! `replan_threshold` column to `orchard_ironwood_migrations`.
//!
//! The rename removes a collision between two similarly spelled columns of
//! `orchard_ironwood_migration_transactions` that name unrelated things: the transaction's ordinal
//! WITHIN its migration (a `MigrationTransferId`, and the second half of the table's primary key,
//! which the dependency edges reference), and `txid`, the consensus transaction ID the transaction
//! was broadcast under. `transfer_id` names the first unambiguously, and the dependency table's two
//! columns follow it to `transfer_id` and `depends_on_transfer_id`, so no reader has to hold the
//! distinction in mind to read a query.
//!
//! `tx_id` is what [`orchard_ironwood_migration_tables`] creates, and — since that migration is
//! published — is what it will always create, from a frozen copy of the text a released build ran.
//! That is what makes EVERY step here unconditional: a database arrives at this migration in the
//! shape some released build created, whether that was an earlier release or the frozen copy a
//! moment ago, so both paths leave the same schema text behind.
//!
//! `unsatisfiable_at` records the height of the chain state a spent-input observation rests on,
//! when a migration transaction has been determined UNSATISFIABLE — its inputs can never again
//! all exist unspent on chain — and is `NULL` while no such determination stands. A rewind below
//! that height invalidates the observation itself, which is what reorg truncation clears the mark
//! by comparing against.
//!
//! `unsatisfiable_kind` records WHICH observation that was, as the wire name of an
//! `UnsatisfiableKind` (`inputs_spent`, `inputs_invalidated`, `anchor_invalidated`, or
//! `inherited` for a mark that arrived through the dependency closure rather than from anything
//! observed about the transaction itself). It is the mark's companion, not an independent
//! record: the two columns are `NULL` together or non-`NULL` together, and the store rejects a
//! row where they disagree. Existing rows need no backfill — a pre-existing database has no
//! `unsatisfiable_at` column either, so no mark can predate this one.
//!
//! `broadcast_failure_at` records the chain tip an application observed from a node that REJECTED
//! a broadcast of the transaction, and is `NULL` while no rejection stands unadjudicated. It is
//! testimony from another observer rather than an observation of this wallet's own, which is why
//! it is a separate column from the mark: it withholds the transaction from the broadcast queue
//! until the wallet has scanned to that tip and the engine can decide the question against
//! evidence. Existing rows need no backfill for the same reason the kind does not — a database
//! predating these columns recorded no such report.
//!
//! `orchard_ironwood_migration_spend_nullifiers` caches the nullifiers of each transaction's REAL
//! spends — the deferred-witness actions; the padded dummy spends carry their own witnesses (ZIP
//! 374) — one 32-byte row per nullifier, ordered by its position in the transaction's action
//! order. The cache is derivable from a not-yet-proven stored PCZT, but the pool-migration state
//! machine reads it through the store precisely so it never has to parse a PCZT (in the engine
//! crate, `pczt` parsing is `orchard`-gated while the state machine is feature-free). Existing
//! rows therefore must satisfy the same invariant the store's write path maintains, so this
//! migration derives the cache for them by parsing each row's stored PCZT — using the base `pczt`
//! data model, which needs no protocol feature. A stored PCZT that does not parse is corrupt state
//! and fails the migration, matching how the store's read paths reject data they cannot
//! reconstruct. So does a not-yet-`mined` row whose PCZT parses but yields NO real spends: that is
//! the shape of a PROVEN PCZT (proving installs the
//! deferred witnesses), from which the cache can no longer be reconstructed. A `mined` row with
//! such bytes is exempt and keeps an empty cache — hard-failing it would block every wallet
//! whose migration already completed, for no benefit while the row stays mined. The exemption
//! carries a residual hazard: mined-ness is chain-derived and revocable, so a chain rewind that
//! demotes such a row returns it to the watched set with an empty cache, which satisfiability
//! consumers must treat as loud corruption (the real spends were never identifiable), never as
//! a transaction with no inputs to observe.
//!
//! `txid` changes meaning: it is now every row's id, recorded when the transaction is BUILT,
//! rather than a value that appeared only once the transaction was broadcast. Two groups of rows
//! therefore need filling. Rows that never reached `broadcast` never had one; and `mined` rows lost
//! theirs to a published release, whose two store write paths bound the column through one accessor
//! that answered `None` for `mined`. The reconstructing reader now requires the column on every
//! row, so without this repair a wallet with a migration in any state could stop reading its store
//! back. See [`backfill_txids`]: the id is DERIVED from each row's own stored PCZT, which works
//! whatever the row's lifecycle state and needs no other evidence to survive.
//!
//! `replan_threshold` is the integer percent of planned transfer value, unsatisfiable, above which
//! a migration is re-planned immediately rather than after satisfiable work drains — stamped on
//! `orchard_ironwood_migrations` at commit. A migration committed before this column existed
//! carries no such stamp, so it backfills to the same default the store's `CREATE TABLE` and this
//! `ADD COLUMN` share (`ReplanThreshold::DEFAULT`'s percent), which is the policy every migration
//! committed before this migration was, in fact, evaluated under.
//!
//! [`orchard_ironwood_migration_tables`]: super::orchard_ironwood_migration_tables

use std::collections::HashSet;

use rusqlite::named_params;
use schemerz_rusqlite::RusqliteMigration;
use uuid::Uuid;

use super::orchard_ironwood_migration_anchor_interval;
use crate::wallet::init::WalletMigrationError;

/// Renames `tx_id` to `transfer_id`, adds the `unsatisfiable_at`, `unsatisfiable_kind`, and
/// `broadcast_failure_at` columns to `orchard_ironwood_migration_transactions` and the
/// `replan_threshold` column to `orchard_ironwood_migrations`, and caches each transaction's
/// real-spend nullifiers in a table of their own.
pub const MIGRATION_ID: Uuid = Uuid::from_u128(0xd334a9fa_b9dc_46bd_9b31_1fba6aa47f55);

const DEPENDENCIES: &[Uuid] = &[orchard_ironwood_migration_anchor_interval::MIGRATION_ID];

/// The nullifier-cache table this migration introduces, which no published migration creates.
///
/// It is written out here rather than sourced from the store's DDL builders for the reason every
/// migration's DDL is: what a migration does to a database must not follow an evolving definition.
/// The two texts are held equal by `canonical_pool_migration_ddl_matches_the_migration_path`
/// (through `verify_schema`, which pins the same shape to the migration path).
const CREATE_SPEND_NULLIFIERS_SQL: &str = "CREATE TABLE orchard_ironwood_migration_spend_nullifiers (
    migration_id INTEGER NOT NULL,
    transfer_id INTEGER NOT NULL,
    ordinal INTEGER NOT NULL,
    nullifier BLOB NOT NULL CHECK (length(nullifier) = 32),
    PRIMARY KEY (migration_id, transfer_id, ordinal),
    FOREIGN KEY (migration_id, transfer_id)
        REFERENCES orchard_ironwood_migration_transactions(migration_id, transfer_id) ON DELETE CASCADE
);";

pub(super) struct Migration;

impl schemerz::Migration<Uuid> for Migration {
    fn id(&self) -> Uuid {
        MIGRATION_ID
    }

    fn dependencies(&self) -> HashSet<Uuid> {
        DEPENDENCIES.iter().copied().collect()
    }

    fn description(&self) -> &'static str {
        "Renames the pool-migration transfer ordinal from tx_id to transfer_id, adds the \
         unsatisfiable_at, unsatisfiable_kind, and broadcast_failure_at columns to \
         orchard_ironwood_migration_transactions and the replan_threshold column to \
         orchard_ironwood_migrations, and caches each transaction's real-spend nullifiers in the \
         orchard_ironwood_migration_spend_nullifiers table."
    }
}

/// The transaction id of a PCZT stored by the pool-migration engine.
///
/// Inlined from what was `zcash_pool_migration::pczt_txid`: this migration is
/// the only thing here that needed it, and the engine itself is not part of
/// this fork.
#[cfg(feature = "orchard")]
fn stored_pczt_txid(bytes: &[u8]) -> Result<::zcash_protocol::TxId, &'static str> {
    use ::zcash_primitives::transaction::txid::{TxIdDigester, to_txid};

    let pczt = pczt::Pczt::parse(bytes).map_err(|_| "the stored bytes do not parse as a PCZT")?;
    let tx_data = pczt
        .into_effects()
        .map_err(|_| "the PCZT's effects do not assemble into transaction data")?;
    let digests = tx_data.digest(TxIdDigester);

    Ok(to_txid(
        tx_data.version(),
        tx_data.consensus_branch_id(),
        &digests,
    ))
}

/// The nullifiers of the REAL spends of the PCZT serialized in `pczt_bytes`: the Orchard actions
/// whose spend carries no Merkle witness (ZIP 374 defers the real spends' witnesses to proving
/// time, while the padding dummies keep their arbitrary witnesses), in action order. A PCZT that
/// does not parse is corrupt state and yields [`WalletMigrationError::CorruptedData`].
///
/// The witness filter is the real-spend RULE, not a defensive skip: `witness` is a genuinely
/// optional PCZT field, and in an unproven migration PCZT it is exactly the padding dummies that
/// have it. Dropping the filter would fold the dummies' nullifiers — which correspond to no note
/// this wallet holds — into the cache, and the satisfiability oracle would then ask the wallet
/// about notes it has never seen and answer `NotYetSatisfiable` forever. `zcash_pool_migration`'s
/// `pczt_spends` module is the canonical statement of the rule and pins it with a proptest over
/// builder-produced PCZTs; this is its feature-free mirror, because a wallet schema migration must
/// run in a build without this crate's `orchard` feature.
fn real_spend_nullifiers(pczt_bytes: &[u8]) -> Result<Vec<[u8; 32]>, WalletMigrationError> {
    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| {
        WalletMigrationError::CorruptedData(format!(
            "stored pool-migration PCZT does not parse: {e:?}"
        ))
    })?;
    Ok(pczt
        .orchard()
        .actions()
        .iter()
        .filter(|action| action.spend().witness().is_none())
        .map(|action| *action.spend().nullifier())
        .collect())
}

/// Fills the `txid` column of every transaction row that lacks one.
///
/// A row's txid is now recorded from the moment the transaction is BUILT, not from the moment it
/// is broadcast, so every row must carry one. Rows written before this migration carry a txid only
/// if they reached `broadcast` or `mined` — and a published release erased even those for `mined`
/// rows (see the module docs) — so the rest are filled here.
///
/// The value is DERIVED from the stored PCZT rather than looked up: a transaction's id commits to
/// effecting data only, so it is fixed from the moment the PCZT is prepared and is the same before
/// signing, after signing, and after proving. Deriving it therefore works for every row whatever
/// its lifecycle state, and — unlike recovering a mined row's id by matching its spends against the
/// wallet's own records — does not depend on the wallet still holding evidence of the spend.
#[cfg(feature = "orchard")]
fn backfill_txids(conn: &rusqlite::Transaction) -> Result<(), WalletMigrationError> {
    let rows: Vec<(i64, u32, Vec<u8>)> = {
        let mut stmt = conn.prepare(
            "SELECT migration_id, transfer_id, pczt
               FROM orchard_ironwood_migration_transactions
              WHERE txid IS NULL",
        )?;
        let mapped = stmt.query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get::<_, Vec<u8>>(2)?))
        })?;
        mapped.collect::<Result<_, _>>()?
    };

    for (migration_id, transfer_id, pczt_bytes) in rows {
        let txid = stored_pczt_txid(&pczt_bytes).map_err(|e| {
            WalletMigrationError::CorruptedData(format!(
                "pool-migration transaction (migration {migration_id}, transfer {transfer_id}) \
                 stores a PCZT whose transaction id cannot be derived: {e}"
            ))
        })?;
        conn.execute(
            "UPDATE orchard_ironwood_migration_transactions
                SET txid = :txid
              WHERE migration_id = :migration_id AND transfer_id = :transfer_id",
            named_params! {
                ":txid": hex::encode(txid.as_ref()),
                ":migration_id": migration_id,
                ":transfer_id": transfer_id,
            },
        )?;
    }
    Ok(())
}

impl RusqliteMigration for Migration {
    type Error = WalletMigrationError;

    fn up(&self, transaction: &rusqlite::Transaction) -> Result<(), Self::Error> {
        // Every step below is UNCONDITIONAL, because every database reaching this migration
        // arrives in the same shape: the one a released build created. A wallet whose tables were
        // created by an earlier release has that shape because that release created it, and one
        // whose tables are created on the way here has it because
        // `orchard_ironwood_migration_tables` is published and creates them from a frozen copy of
        // the text a released build ran. Fresh and upgraded wallets therefore travel the identical
        // path, which is what lets the created and repaired schemas be one text — and what makes
        // an `ADD COLUMN` here safe, since adding a column that already exists is an error rather
        // than a no-op.
        //
        // The rename runs first, so every statement below — and every store query written against
        // the schema this migration leaves behind — speaks `transfer_id`.
        //
        // SQLite rewrites the stored schema for each rename: the transactions table's own
        // definition and primary key, the dependency table's foreign key into it, and (were there
        // one) any index naming the column. Only the schema text changes; no row is rewritten, and
        // the `ON DELETE CASCADE` from the transactions table to its dependency edges survives
        // because it is the same constraint under a new column name.
        transaction.execute_batch(
            "ALTER TABLE orchard_ironwood_migration_transactions
                RENAME COLUMN tx_id TO transfer_id;
             ALTER TABLE orchard_ironwood_migration_transaction_deps
                RENAME COLUMN tx_id TO transfer_id;
             ALTER TABLE orchard_ironwood_migration_transaction_deps
                RENAME COLUMN depends_on_tx_id TO depends_on_transfer_id;",
        )?;

        // The nullifier cache's own table, created here because no published migration creates it.
        // Its foreign key names the renamed ordinal, so it follows the rename above.
        transaction.execute_batch(CREATE_SPEND_NULLIFIERS_SQL)?;

        // `unsatisfiable_kind` and `broadcast_failure_at` need no backfill and no default: a
        // database that lacked `unsatisfiable_at` carried neither a mark nor a broadcast-failure
        // report, so every existing row is correctly unmarked and unreported with all three
        // columns `NULL`.
        //
        // They are added in the order the store's `CREATE TABLE` lists them, which is where SQLite
        // puts them: `ADD COLUMN` splices a definition in after the last column of the stored
        // text and before the table constraints, so the repaired schema names its columns in the
        // same order the created one does, `PRIMARY KEY` clause and all.
        transaction.execute_batch(
            "ALTER TABLE orchard_ironwood_migration_transactions
                ADD COLUMN unsatisfiable_at INTEGER;
             ALTER TABLE orchard_ironwood_migration_transactions
                ADD COLUMN unsatisfiable_kind TEXT;
             ALTER TABLE orchard_ironwood_migration_transactions
                ADD COLUMN broadcast_failure_at INTEGER;",
        )?;

        // Backfill the nullifier cache for every existing row from its stored PCZT. No non-`mined`
        // row is left without one: a transaction that HAS real spends but caches none would read
        // as "no inputs to observe" to the unsatisfiability machinery, silently exempting the
        // transaction from detection.
        let rows: Vec<(i64, u32, Vec<u8>, String)> = {
            let mut stmt = transaction.prepare(
                "SELECT migration_id, transfer_id, pczt, state
                   FROM orchard_ironwood_migration_transactions",
            )?;
            let mapped = stmt.query_map([], |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get::<_, Vec<u8>>(2)?,
                    row.get(3)?,
                ))
            })?;
            mapped.collect::<Result<_, _>>()?
        };
        for (migration_id, transfer_id, pczt_bytes, state) in rows {
            let spend_nullifiers = real_spend_nullifiers(&pczt_bytes)?;
            // An empty extraction means the stored bytes are a PROVEN PCZT: every built migration
            // PCZT defers at least one real spend's witness, and proving is what installs them
            // all. The cache cannot be reconstructed from such bytes, which is fatal for any row
            // the unsatisfiability machinery still watches. A `mined` row alone is exempt and
            // keeps an empty cache — hard-failing it would block every completed-migration wallet
            // for no benefit — at the cost that a chain rewind demoting the row leaves it watched
            // with an empty cache, which downstream satisfiability machinery must treat as loud
            // corruption rather than vacuous satisfiability.
            if spend_nullifiers.is_empty() && state != "mined" {
                return Err(WalletMigrationError::CorruptedData(format!(
                    "pool-migration transaction (migration {migration_id}, transfer \
                     {transfer_id}, state '{state}') stores a PCZT whose real spends are no \
                     longer identifiable (proven bytes, or deeper corruption); this state was \
                     persisted before the nullifier cache existed, and the migration cannot \
                     be resumed: the remaining balance must be re-planned"
                )));
            }
            // The cache is an ordered list, so each nullifier is stored under the position it was
            // extracted at — the action order the store reads it back in.
            for (ordinal, nullifier) in spend_nullifiers.iter().enumerate() {
                transaction.execute(
                    "INSERT INTO orchard_ironwood_migration_spend_nullifiers (
                        migration_id, transfer_id, ordinal, nullifier
                     )
                     VALUES (:migration_id, :transfer_id, :ordinal, :nullifier)",
                    named_params! {
                        ":migration_id": migration_id,
                        ":transfer_id": transfer_id,
                        ":ordinal": ordinal as u64,
                        ":nullifier": nullifier,
                    },
                )?;
            }
        }

        #[cfg(feature = "orchard")]
        backfill_txids(transaction)?;

        // `replan_threshold` lives on the other table (`orchard_ironwood_migrations`), which no
        // released build ever gave it. Its `DEFAULT` matches the one carried by the store's
        // `CREATE TABLE` (`ReplanThreshold::DEFAULT`'s percent), so the created and repaired
        // schemas agree on their stored text. SQLite's `ADD COLUMN ... DEFAULT` itself backfills
        // every existing row to that value — the policy every migration committed before this
        // column existed was, in fact, evaluated under; the store always binds the column
        // explicitly on write, so no FUTURE insert ever falls back to it.
        transaction.execute_batch(
            "ALTER TABLE orchard_ironwood_migrations
                ADD COLUMN replan_threshold INTEGER NOT NULL DEFAULT 20;",
        )?;

        Ok(())
    }

    fn down(&self, _transaction: &rusqlite::Transaction) -> Result<(), Self::Error> {
        Err(WalletMigrationError::CannotRevert(MIGRATION_ID))
    }
}

#[cfg(test)]
mod tests {
    use rusqlite::{Connection, named_params};

    use super::*;
    use crate::wallet::init::migrations::tests::test_migrate;

    #[test]
    fn migrate() {
        test_migrate(&[MIGRATION_ID]);
    }

    /// The pool-migration tables exactly as the released `orchard_ironwood_migration_tables`
    /// creates them — the ONE state every database reaches this migration in, whether an earlier
    /// release created them or its frozen copy of that release's text just did.
    ///
    /// Every fixture below builds on this rather than hand-writing a schema: what this migration
    /// repairs is defined by what that text creates, so a fixture that stated the shape
    /// independently could drift from the thing under test.
    fn create_released_tables(conn: &Connection) {
        conn.execute_batch(super::super::orchard_ironwood_migration_tables::CREATE_TABLES_SQL)
            .unwrap();
    }

    /// Whether `orchard_ironwood_migration_transactions` names its transfer ordinal `column`.
    fn transactions_has_column(conn: &Connection, column: &str) -> bool {
        conn.query_row(
            "SELECT EXISTS (
                SELECT 1 FROM pragma_table_info('orchard_ironwood_migration_transactions')
                WHERE name = :column_name
             )",
            named_params![":column_name": column],
            |row| row.get::<_, bool>(0),
        )
        .unwrap()
    }

    /// Whether the transactions table carries the three columns this migration adds.
    fn has_columns(conn: &Connection) -> bool {
        conn.query_row(
            "SELECT (
                SELECT COUNT(*) FROM pragma_table_info('orchard_ironwood_migration_transactions')
                WHERE name IN ('unsatisfiable_at', 'unsatisfiable_kind', 'broadcast_failure_at')
             ) = 3",
            [],
            |row| row.get::<_, bool>(0),
        )
        .unwrap()
    }

    /// The nullifiers cached for the transfer `transfer_id`, in stored `ordinal` order.
    fn cached_nullifiers(conn: &Connection, transfer_id: u32) -> Vec<Vec<u8>> {
        let mut stmt = conn
            .prepare(
                "SELECT nullifier FROM orchard_ironwood_migration_spend_nullifiers
                  WHERE transfer_id = :transfer_id
                  ORDER BY ordinal",
            )
            .unwrap();
        let rows = stmt
            .query_map(named_params![":transfer_id": transfer_id], |row| {
                row.get::<_, Vec<u8>>(0)
            })
            .unwrap();
        rows.collect::<Result<_, _>>().unwrap()
    }

    fn has_replan_threshold_column(conn: &Connection) -> bool {
        conn.query_row(
            "SELECT EXISTS (
                SELECT 1 FROM pragma_table_info('orchard_ironwood_migrations')
                WHERE name = 'replan_threshold'
             )",
            [],
            |row| row.get::<_, bool>(0),
        )
        .unwrap()
    }

    /// The parent rows a stored transfer hangs off: the `accounts` row the released schema's
    /// `orchard_ironwood_migrations.account_id` references, and the committed migration whose id
    /// every fixture transfer names. The pool-migration tables are foreign-keyed all the way up to
    /// `accounts`, so a fixture that skipped these would be testing a shape no wallet has.
    fn insert_parent_migration(conn: &Connection) {
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY, uuid BLOB NOT NULL);
             INSERT INTO accounts (id, uuid) VALUES (1, X'5A');
             INSERT INTO orchard_ironwood_migrations (
                id, account_id, status, note_split_fee_buffer, note_split_prep_fees,
                note_split_total_input, note_split_total_migratable
             )
             VALUES (1, 1, 'committed', 0, 0, 0, 0);",
        )
        .unwrap();
    }

    /// Insert a released-shape transactions row carrying `pczt`, a transfer in the given `state`
    /// (the other columns are immaterial to the backfill), under the migration
    /// [`insert_parent_migration`] records. Addressed by `tx_id`, the name the row is stored under
    /// until `up` renames it.
    fn insert_transfer_row(conn: &Connection, tx_id: u32, pczt: &[u8], state: &str) {
        conn.execute(
            "INSERT INTO orchard_ironwood_migration_transactions (
                migration_id, tx_id, kind, kind_crossing, pczt, scheduled_height, expiry_height,
                state
             )
             VALUES (1, :tx_id, 'transfer', 0, :pczt, 200, 240, :state)",
            named_params![":tx_id": tx_id, ":pczt": pczt, ":state": state],
        )
        .unwrap();
    }

    /// The released schema carries none of what this migration adds and names its transfer ordinal
    /// `tx_id`, so `up` renames the ordinal and adds every column unconditionally — which is only
    /// safe because this is the single shape a database can arrive in (an `ADD COLUMN` that is
    /// already there fails with "duplicate column name", and a rename of a column that is already
    /// renamed fails too). Empty tables need no backfill, so the cache table is created and stays
    /// empty.
    #[test]
    fn renames_and_adds_the_columns_on_the_released_schema() {
        let mut conn = Connection::open_in_memory().unwrap();
        create_released_tables(&conn);
        assert!(!has_columns(&conn));
        assert!(!has_replan_threshold_column(&conn));
        assert!(transactions_has_column(&conn, "tx_id"));

        let tx = conn.transaction().unwrap();
        RusqliteMigration::up(&Migration, &tx).unwrap();
        tx.commit().unwrap();

        assert!(has_columns(&conn));
        assert!(has_replan_threshold_column(&conn));
        assert!(transactions_has_column(&conn, "transfer_id"));
        assert!(!transactions_has_column(&conn, "tx_id"));
        assert!(
            cached_nullifiers(&conn, 0).is_empty(),
            "the cache table exists and is empty, like the table it hangs off",
        );
    }

    /// A stored PCZT that does not parse is corrupt state: the migration surfaces
    /// [`WalletMigrationError::CorruptedData`] rather than leaving the row's nullifier cache
    /// silently empty (which would exempt the transaction from unsatisfiability detection).
    #[test]
    fn an_unparseable_stored_pczt_fails_the_migration() {
        let mut conn = Connection::open_in_memory().unwrap();
        create_released_tables(&conn);
        insert_parent_migration(&conn);
        insert_transfer_row(&conn, 0, &[1, 2, 3], "signed");

        let tx = conn.transaction().unwrap();
        let result = RusqliteMigration::up(&Migration, &tx);
        assert!(matches!(
            result,
            Err(WalletMigrationError::CorruptedData(_))
        ));
    }

    /// The upgrade path with data: an existing `orchard_ironwood_migrations` row is backfilled
    /// with `ReplanThreshold::DEFAULT`'s percent — the policy every migration committed before this
    /// column existed was, in fact, evaluated under.
    #[test]
    fn backfills_replan_threshold_to_the_default_for_existing_rows() {
        let mut conn = Connection::open_in_memory().unwrap();
        create_released_tables(&conn);
        insert_parent_migration(&conn);

        let tx = conn.transaction().unwrap();
        RusqliteMigration::up(&Migration, &tx).unwrap();
        tx.commit().unwrap();

        let replan_threshold: u32 = conn
            .query_row(
                "SELECT replan_threshold FROM orchard_ironwood_migrations",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(
            replan_threshold,
            // The pool-migration engine's `ReplanThreshold::DEFAULT`, which this fork no
            // longer carries: the migration writes the same literal.
            20,
        );
    }

    fn create_wallet_tables(conn: &Connection) {
        conn.execute_batch(
            "CREATE TABLE accounts (
                id INTEGER PRIMARY KEY,
                uuid BLOB NOT NULL
             );
             CREATE TABLE transactions (
                id_tx INTEGER PRIMARY KEY,
                txid BLOB NOT NULL UNIQUE,
                mined_height INTEGER
             );
             CREATE TABLE orchard_received_notes (
                id INTEGER PRIMARY KEY,
                nf BLOB
             );
             CREATE TABLE orchard_received_note_spends (
                orchard_received_note_id INTEGER NOT NULL,
                transaction_id INTEGER NOT NULL
             );",
        )
        .unwrap();
    }

    /// A row whose stored PCZT cannot yield a transaction id fails the migration, naming the row,
    /// rather than leaving a store that reads back as corrupt ever after.
    ///
    /// This is now the ONLY way the txid backfill can fail. Its predecessor recovered a mined
    /// row's id by matching the transaction's spends against the wallet's own records, and so
    /// failed whenever the wallet no longer held that evidence; deriving the id from the stored
    /// bytes has no such dependency, and succeeds for every row whose PCZT parses.
    #[cfg(feature = "orchard")]
    #[test]
    fn an_underivable_txid_fails_the_migration() {
        let mut conn = Connection::open_in_memory().unwrap();
        create_wallet_tables(&conn);
        create_released_tables(&conn);
        insert_parent_migration(&conn);
        insert_transfer_row(&conn, 0, b"not a pczt", "signed");

        let tx = conn.transaction().unwrap();
        assert!(matches!(
            RusqliteMigration::up(&Migration, &tx),
            Err(WalletMigrationError::CorruptedData(_)),
        ));
    }
}
