//! Ironwood enhancement bookkeeping invoked from upstream wallet operations.
//!
//! The Ironwood enhancement queues are created by schema migrations in every build, so the
//! invariants maintained here hold whenever Orchard storage is enabled. Each hook
//! runs on the caller's connection, inside the caller's transaction.

use rusqlite::{Connection, named_params};
use zcash_protocol::consensus::BlockHeight;

#[cfg(feature = "orchard")]
use {zcash_client_backend::wallet::CompactEncryptionFields, zcash_protocol::ShieldedPool};

use crate::{TxRef, error::SqliteClientError};

/// Preserve incomplete enhancement jobs after funding accounts are removed. This
/// maintains durable database invariants even in builds without PIR support.
/// The caller's transaction makes the queue updates atomic with account deletion.
pub(crate) fn suspend_orphaned_ironwood_enhancement(
    conn: &rusqlite::Transaction<'_>,
) -> Result<(), SqliteClientError> {
    conn.execute("UPDATE ironwood_enhance_metadata_queue AS q SET commitment_tree_position = NULL,
        output_index = NULL WHERE q.compact_bound = 0 AND q.commitment_tree_position IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM ironwood_received_notes rn WHERE rn.transaction_id = q.transaction_id
            AND rn.action_index = q.output_index AND rn.commitment_tree_position = q.commitment_tree_position)", [])?;
    conn.execute(
        "UPDATE ironwood_enhance_outgoing_queue SET not_recoverable = 1
         WHERE NOT EXISTS (SELECT 1 FROM ironwood_enhance_outgoing_accounts a
             WHERE a.commitment_tree_position = ironwood_enhance_outgoing_queue.commitment_tree_position)",
        [],
    )?;
    conn.execute(
        "UPDATE ironwood_enhance_discovery_queue SET suspended = 1
         WHERE NOT EXISTS (
             SELECT 1 FROM ironwood_received_note_spends s
             JOIN ironwood_received_notes rn ON rn.id = s.ironwood_received_note_id
             WHERE s.transaction_id = ironwood_enhance_discovery_queue.transaction_id
               AND rn.nf IS NOT NULL)",
        [],
    )?;
    Ok(())
}

/// Runs during truncation to `truncation_height`, before transactions above it are un-mined.
pub(crate) fn truncate_before_unmine(
    conn: &rusqlite::Transaction,
    truncation_height: BlockHeight,
) -> Result<(), SqliteClientError> {
    // Routing is durable policy, including while unmined. Preserve reconstruction
    // intent before dropping position claims: retained spend links may be replayed
    // without being newly inserted. Discovery derives its anchor from current mined
    // metadata, so these obligations remain inactive until the transaction is re-mined.
    // This SQL also runs in builds without PIR support.
    conn.execute(
        "INSERT INTO ironwood_enhance_discovery_queue (transaction_id, suspended)
         SELECT t.id_tx, NOT EXISTS (
             SELECT 1 FROM ironwood_received_note_spends s
             JOIN ironwood_received_notes rn ON rn.id = s.ironwood_received_note_id
             WHERE s.transaction_id = t.id_tx AND rn.nf IS NOT NULL
         )
         FROM transactions t
         JOIN ironwood_enhance_routing r ON r.transaction_id = t.id_tx
         WHERE t.mined_height > :height AND t.raw IS NULL AND r.route = 0
           AND (
             EXISTS (SELECT 1 FROM ironwood_enhance_discovery_queue WHERE transaction_id = t.id_tx)
             OR EXISTS (SELECT 1 FROM ironwood_enhance_outgoing_queue WHERE transaction_id = t.id_tx)
             OR EXISTS (SELECT 1 FROM ironwood_received_note_spends WHERE transaction_id = t.id_tx)
           )
         ON CONFLICT(transaction_id) DO UPDATE SET suspended = excluded.suspended",
        named_params![":height": u32::from(truncation_height)],
    )?;
    conn.execute(
        "DELETE FROM ironwood_enhance_outgoing_queue
         WHERE transaction_id IN (
             SELECT id_tx FROM transactions WHERE mined_height > :height
         )",
        named_params![":height": u32::from(truncation_height)],
    )?;

    conn.execute(
        "UPDATE ironwood_enhance_metadata_queue SET commitment_tree_position = NULL,
        output_index = NULL, compact_bound = 0
        WHERE transaction_id IN (SELECT id_tx FROM transactions WHERE mined_height > :height)",
        named_params![":height": u32::from(truncation_height)],
    )?;
    Ok(())
}

/// Runs during truncation, after transactions above the truncation height have been un-mined.
pub(crate) fn truncate_after_unmine(conn: &rusqlite::Transaction) -> Result<(), SqliteClientError> {
    // Dequeue memo retrievals for the notes we just un-mined. Their commitment tree positions are
    // deliberately retained (received notes are never deleted here, because they may hold memo
    // data that cannot be recovered), but a retained position is no longer authoritative: it may
    // be reassigned to a different note by the rescan this truncation schedules. Querying it
    // would spend a PIR request on a position the wallet no longer owns. Whatever remains
    // completable is re-queued by that rescan.
    conn.execute_batch(
        "DELETE FROM ironwood_memo_retrieval_queue
         WHERE received_note_id IN (
             SELECT rn.id FROM ironwood_received_notes rn
             JOIN transactions t ON t.id_tx = rn.transaction_id
             WHERE t.mined_height IS NULL
         )",
    )?;
    Ok(())
}

/// Full transaction storage supersedes private queues without erasing recovered data.
pub(crate) fn clear_ironwood_enhancement_work(
    conn: &Connection,
    tx_ref: TxRef,
) -> Result<(), SqliteClientError> {
    conn.execute(
        "DELETE FROM ironwood_enhance_metadata_queue WHERE transaction_id = :tx",
        named_params![":tx": tx_ref.0],
    )?;
    conn.execute(
        "DELETE FROM ironwood_enhance_discovery_queue WHERE transaction_id = :tx",
        named_params![":tx": tx_ref.0],
    )?;
    conn.execute(
        "DELETE FROM ironwood_memo_retrieval_queue
         WHERE received_note_id IN (
             SELECT id FROM ironwood_received_notes WHERE transaction_id = :tx)",
        named_params![":tx": tx_ref.0],
    )?;
    conn.execute(
        "DELETE FROM ironwood_enhance_outgoing_queue WHERE transaction_id = :tx",
        named_params![":tx": tx_ref.0],
    )?;
    Ok(())
}

/// Records the compact encryption fields of a received Ironwood note, when the output carries
/// them. Notes in other pools are left untouched.
#[cfg(feature = "orchard")]
pub(crate) fn put_received_note_encryption_fields(
    conn: &rusqlite::Transaction,
    shielded_pool: ShieldedPool,
    received_note_id: i64,
    fields: Option<CompactEncryptionFields>,
) -> Result<(), SqliteClientError> {
    if shielded_pool == ShieldedPool::Ironwood
        && let Some(fields) = fields
    {
        conn.execute(
            "UPDATE ironwood_received_notes SET ephemeral_key = :epk,
             compact_ciphertext = :ciphertext WHERE id = :id",
            named_params![":epk": fields.ephemeral_key.as_slice(),
                ":ciphertext": fields.compact_ciphertext.as_slice(), ":id": received_note_id],
        )?;
    }
    Ok(())
}

/// Runs after a received note's spend link to `spent_in` has been recorded; `inserted` is the
/// number of rows the link insertion wrote.
#[cfg(feature = "orchard")]
pub(crate) fn put_received_note_spend(
    conn: &rusqlite::Transaction,
    shielded_pool: ShieldedPool,
    spent_in: TxRef,
    inserted: usize,
) -> Result<(), SqliteClientError> {
    if shielded_pool == ShieldedPool::Ironwood
        && (inserted != 0
            || conn.query_row(
                "SELECT NOT EXISTS(SELECT 1 FROM ironwood_enhance_routing
                 WHERE transaction_id = :tx)",
                named_params![":tx": spent_in.0],
                |row| row.get::<_, bool>(0),
            )?)
    {
        // New links and unclassified history need reconstruction. Rewinds preserve
        // protected transactions' discovery obligations separately, so replaying
        // an existing link must not reopen ordinarily completed work.
        super::enhance_pir::discovery::queue(conn, spent_in)?;
    }
    Ok(())
}
