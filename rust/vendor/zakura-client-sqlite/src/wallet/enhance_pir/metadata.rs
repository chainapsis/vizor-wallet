//! Transaction metadata work survives action completion and uses the same private queries.
use super::*;
use zcash_client_backend::wallet::IronwoodEnhanceCandidate;

pub(super) fn queue(
    conn: &Connection,
    tx_ref: crate::TxRef,
    candidates: &[IronwoodEnhanceCandidate<AccountUuid>],
) -> Result<(), SqliteClientError> {
    // Private responses must supply a fee. Expiry is deliberately not persisted,
    // so an unknown expiry must not reopen successfully completed enhancement.
    conn.execute("INSERT INTO ironwood_enhance_metadata_queue (transaction_id)
        SELECT id_tx FROM transactions WHERE id_tx = :tx AND raw IS NULL AND mined_height IS NOT NULL
        AND fee IS NULL ON CONFLICT(transaction_id) DO NOTHING",
        named_params![":tx": tx_ref.0])?;
    let note: Option<(u64, u32)> = conn
        .query_row(
            "SELECT commitment_tree_position, action_index FROM ironwood_received_notes
         WHERE transaction_id = ? AND note_version = 3 AND commitment_tree_position IS NOT NULL
         ORDER BY action_index LIMIT 1",
            [tx_ref.0],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    if let Some((position, index)) = note {
        conn.execute(
            "UPDATE ironwood_enhance_metadata_queue SET commitment_tree_position = :position,
            output_index = :index, compact_bound = 0 WHERE transaction_id = :tx",
            named_params![":position": position, ":index": index, ":tx": tx_ref.0],
        )?;
    } else if let Some(candidate) = candidates.iter().min_by_key(|c| c.output_index()) {
        bind(
            conn,
            tx_ref,
            u64::from(candidate.position()),
            candidate.output_index() as u32,
        )?;
    }
    conn.execute("INSERT INTO tx_retrieval_queue (txid, query_type)
        SELECT t.txid, :enhancement FROM transactions t JOIN ironwood_enhance_metadata_queue q ON q.transaction_id = t.id_tx
        WHERE t.id_tx = :tx ON CONFLICT(txid, query_type) DO NOTHING",
        named_params![":tx": tx_ref.0, ":enhancement": TxQueryType::Enhancement.code()])?;
    Ok(())
}

pub(super) fn bind(
    conn: &Connection,
    tx_ref: crate::TxRef,
    position: u64,
    index: u32,
) -> Result<(), SqliteClientError> {
    conn.execute(
        "UPDATE ironwood_enhance_metadata_queue SET commitment_tree_position = :position,
        output_index = :index, compact_bound = 1 WHERE transaction_id = :tx",
        named_params![":position": position, ":index": index, ":tx": tx_ref.0],
    )?;
    Ok(())
}

pub(super) fn pending<P: Parameters>(
    conn: &Connection,
    params: &P,
    position: Position,
) -> Result<Option<PendingIronwoodMetadata<AccountUuid>>, SqliteClientError> {
    if let Some(note) = super::pending_note(conn, params, position, true)? {
        return Ok(Some(PendingIronwoodMetadata::Incoming(note)));
    }
    conn.query_row(
        concat!(
            "SELECT t.txid, q.output_index
        FROM ironwood_enhance_metadata_queue q JOIN transactions t ON t.id_tx = q.transaction_id
        ",
            active_private_tx!(),
            "
        AND q.commitment_tree_position = ? AND q.compact_bound = 1"
        ),
        [u64::from(position)],
        |r| {
            Ok(PendingIronwoodMetadata::Compact(
                IronwoodEnhanceRequestId::new(TxId::from_bytes(r.get(0)?), r.get(1)?),
            ))
        },
    )
    .optional()
    .map_err(Into::into)
}
