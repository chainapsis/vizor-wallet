//! Chain confirmation parsing and durable submission recording.
//!
//! Wallets submit delegation and cast-vote transactions through their own chain
//! clients. This module owns the common step that turns the confirmed tx events
//! back into voting DB state.

use rusqlite::{named_params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::storage::{queries, VotingDb};
use crate::types::VotingError;
pub use crate::wire::{DelegationConfirmation, VoteConfirmation};

const DELEGATE_VOTE_EVENT: &str = "delegate_vote";
const CAST_VOTE_EVENT: &str = "cast_vote";
const LEAF_INDEX_ATTRIBUTE: &str = "leaf_index";
const ROUND_ID_ATTRIBUTES: [&str; 2] = ["vote_round_id", "round_id"];

/// One chain transaction event returned by a wallet's chain client.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TxEvent {
    /// Event type, for example `delegate_vote` or `cast_vote`.
    #[serde(rename = "type")]
    pub event_type: String,
    /// Event attributes in the order returned by the chain client.
    pub attributes: Vec<TxEventAttribute>,
}

/// One key/value attribute inside a chain transaction event.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TxEventAttribute {
    /// Attribute key.
    pub key: String,
    /// Attribute value.
    pub value: String,
}

/// Parses and records a confirmed delegation transaction in one durable step.
///
/// # Errors
///
/// Returns an error when confirmation parsing fails, the bundle row is missing,
/// the event round id does not match `round_id`, stored confirmation fields
/// conflict, multiple same-round delegation events are present, or the DB
/// transaction cannot commit.
pub fn confirm_delegation_submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
    events: &[TxEvent],
) -> Result<DelegationConfirmation, VotingError> {
    let confirmation = parse_delegation_confirmation_for_round(tx_hash, round_id, events)?;
    record_delegation_confirmation(db, round_id, bundle_index, &confirmation)?;
    Ok(confirmation)
}

/// Records a confirmed delegation transaction atomically.
///
/// Repeated calls with the same tx hash are accepted. If later cast-vote
/// confirmations have already advanced the bundle's current VAN pointer, the
/// delegation replay records the tx hash without rewinding the pointer.
///
/// # Errors
///
/// Returns an error when the bundle row is missing, stored confirmation fields
/// conflict, or the DB transaction cannot commit.
fn record_delegation_confirmation(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    confirmation: &DelegationConfirmation,
) -> Result<(), VotingError> {
    require_tx_hash(&confirmation.tx_hash)?;
    let mut conn = db.conn();
    let wallet_id = db.wallet_id();
    let tx = conn.transaction().map_err(|e| VotingError::Internal {
        message: format!("delegation confirmation transaction failed: {e}"),
    })?;

    let (stored_hash, stored_van_position) =
        load_bundle_confirmation_fields(&tx, round_id, &wallet_id, bundle_index)?;
    check_text_conflict(
        stored_hash.as_deref(),
        &confirmation.tx_hash,
        "delegation tx_hash",
    )?;
    let should_store_van_position =
        delegation_van_position_should_update(stored_van_position, confirmation.van_leaf_position)?;
    queries::store_delegation_tx_hash(
        &tx,
        round_id,
        &wallet_id,
        bundle_index,
        &confirmation.tx_hash,
    )?;
    if should_store_van_position {
        queries::store_van_position(
            &tx,
            round_id,
            &wallet_id,
            bundle_index,
            confirmation.van_leaf_position,
        )?;
    }
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit delegation confirmation transaction failed: {e}"),
    })
}

/// Parses and records a confirmed cast-vote transaction in one durable step.
///
/// # Errors
///
/// Returns an error when confirmation parsing fails, the vote or bundle row is
/// missing, the event round id does not match `round_id`, stored confirmation
/// fields conflict, multiple same-round cast-vote events are present, or the DB
/// transaction cannot commit.
pub fn confirm_vote_submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
    events: &[TxEvent],
) -> Result<VoteConfirmation, VotingError> {
    let confirmation = parse_vote_confirmation_for_round(tx_hash, round_id, events)?;
    record_vote_confirmation(db, round_id, bundle_index, proposal_id, &confirmation)?;
    Ok(confirmation)
}

/// Records a confirmed cast-vote transaction atomically.
///
/// Repeated calls with the same tx hash and VC tree position are accepted. The
/// bundle's current VAN leaf position advances to the confirmed cast-vote output
/// position, but an older confirmation replay cannot rewind it.
///
/// # Errors
///
/// Returns an error when the vote or bundle row is missing, stored confirmation
/// fields conflict, ballot intent no longer matches the vote, or the DB
/// transaction cannot commit.
fn record_vote_confirmation(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    confirmation: &VoteConfirmation,
) -> Result<(), VotingError> {
    require_tx_hash(&confirmation.tx_hash)?;
    let mut conn = db.conn();
    let wallet_id = db.wallet_id();
    let tx = conn.transaction().map_err(|e| VotingError::Internal {
        message: format!("vote confirmation transaction failed: {e}"),
    })?;

    queries::record_vote_submission(
        &tx,
        round_id,
        &wallet_id,
        bundle_index,
        proposal_id,
        &confirmation.tx_hash,
    )?;
    require_vote_recovery_json(&tx, round_id, &wallet_id, bundle_index, proposal_id)?;
    advance_van_position_in_tx(
        &tx,
        round_id,
        &wallet_id,
        bundle_index,
        confirmation.van_leaf_position,
    )?;
    crate::vote::record_vc_position_with_conn(
        &tx,
        &wallet_id,
        round_id,
        bundle_index,
        proposal_id,
        confirmation.vc_tree_position,
    )?;

    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit vote confirmation transaction failed: {e}"),
    })
}

fn require_vote_recovery_json(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    let recovery_json: Option<Option<String>> = conn
        .query_row(
            "SELECT commitment_bundle_json
             FROM votes
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index
               AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load vote recovery bundle: {e}"),
        })?;

    match recovery_json {
        Some(Some(_)) => Ok(()),
        Some(None) => Err(VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        }),
        None => Err(VotingError::InvalidInput {
            message: format!(
                "vote not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        }),
    }
}

fn parse_delegation_confirmation_for_round(
    tx_hash: &str,
    round_id: &str,
    events: &[TxEvent],
) -> Result<DelegationConfirmation, VotingError> {
    require_tx_hash(tx_hash)?;
    let event = required_event_for_round(events, DELEGATE_VOTE_EVENT, round_id)?;
    let raw_leaf_index = required_attribute(event, DELEGATE_VOTE_EVENT, LEAF_INDEX_ATTRIBUTE)?;
    let van_leaf_position = parse_u32(raw_leaf_index.trim(), "delegate_vote leaf_index")?;
    Ok(DelegationConfirmation {
        tx_hash: tx_hash.to_string(),
        van_leaf_position,
    })
}

fn parse_vote_confirmation_for_round(
    tx_hash: &str,
    round_id: &str,
    events: &[TxEvent],
) -> Result<VoteConfirmation, VotingError> {
    require_tx_hash(tx_hash)?;
    let event = required_event_for_round(events, CAST_VOTE_EVENT, round_id)?;
    let raw_leaf_index = required_attribute(event, CAST_VOTE_EVENT, LEAF_INDEX_ATTRIBUTE)?;
    parse_vote_confirmation_leaf_index(tx_hash, raw_leaf_index)
}

fn parse_vote_confirmation_leaf_index(
    tx_hash: &str,
    raw_leaf_index: &str,
) -> Result<VoteConfirmation, VotingError> {
    let parts = raw_leaf_index.split(',').collect::<Vec<_>>();
    if parts.len() != 2 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "malformed cast_vote leaf_index {raw_leaf_index:?}; expected van_position,vc_position"
            ),
        });
    }

    let van_leaf_position = parse_u32(parts[0].trim(), "cast_vote VAN leaf position")?;
    let vc_tree_position = parse_u64(parts[1].trim(), "cast_vote VC tree position")?;
    Ok(VoteConfirmation {
        tx_hash: tx_hash.to_string(),
        van_leaf_position,
        vc_tree_position,
    })
}

fn required_event_for_round<'a>(
    events: &'a [TxEvent],
    event_type: &str,
    round_id: &str,
) -> Result<&'a TxEvent, VotingError> {
    let mut matching_event: Option<&TxEvent> = None;
    let mut wrong_round: Option<&str> = None;
    let mut saw_event_without_round = false;

    for event in events.iter().filter(|event| event.event_type == event_type) {
        match round_attribute(event) {
            Some(event_round_id) if event_round_id == round_id => {
                if matching_event.is_some() {
                    return Err(VotingError::InvalidInput {
                        message: format!(
                            "ambiguous {event_type} events for round {round_id}; expected exactly one matching event"
                        ),
                    });
                }
                matching_event = Some(event);
            }
            Some(event_round_id) => wrong_round = Some(event_round_id),
            None => saw_event_without_round = true,
        }
    }

    if let Some(event) = matching_event {
        return Ok(event);
    }
    if let Some(event_round_id) = wrong_round {
        return Err(VotingError::InvalidInput {
            message: format!(
                "{event_type} round id mismatch: expected {round_id}, got {event_round_id}"
            ),
        });
    }
    if saw_event_without_round {
        return Err(VotingError::InvalidInput {
            message: format!("{event_type} event is missing vote_round_id or round_id"),
        });
    }
    Err(VotingError::InvalidInput {
        message: format!("missing {event_type} event in transaction events"),
    })
}

fn round_attribute(event: &TxEvent) -> Option<&str> {
    ROUND_ID_ATTRIBUTES
        .iter()
        .find_map(|key| event_attribute(event, key))
}

fn required_attribute<'a>(
    event: &'a TxEvent,
    event_type: &str,
    key: &str,
) -> Result<&'a str, VotingError> {
    event_attribute(event, key).ok_or_else(|| VotingError::InvalidInput {
        message: format!("missing {event_type} {key} in transaction events"),
    })
}

fn event_attribute<'a>(event: &'a TxEvent, key: &str) -> Option<&'a str> {
    event
        .attributes
        .iter()
        .find(|attribute| attribute.key == key)
        .map(|attribute| attribute.value.as_str())
}

fn require_tx_hash(tx_hash: &str) -> Result<(), VotingError> {
    if tx_hash.trim().is_empty() {
        return Err(VotingError::InvalidInput {
            message: "tx_hash must not be empty".to_string(),
        });
    }
    Ok(())
}

fn parse_u32(raw: &str, field: &str) -> Result<u32, VotingError> {
    raw.parse::<u32>().map_err(|_| VotingError::InvalidInput {
        message: format!("{field} must be an unsigned 32-bit integer, got {raw:?}"),
    })
}

fn parse_u64(raw: &str, field: &str) -> Result<u64, VotingError> {
    raw.parse::<u64>().map_err(|_| VotingError::InvalidInput {
        message: format!("{field} must be an unsigned 64-bit integer, got {raw:?}"),
    })
}

fn load_bundle_confirmation_fields(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<(Option<String>, Option<i64>), VotingError> {
    conn.query_row(
        "SELECT delegation_tx_hash, van_leaf_position
         FROM bundles
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
        },
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to load bundle confirmation fields: {e}"),
    })?
    .ok_or_else(|| VotingError::InvalidInput {
        message: format!("bundle not found for round={round_id}, bundle={bundle_index}"),
    })
}

fn delegation_van_position_should_update(
    stored_van_position: Option<i64>,
    van_leaf_position: u32,
) -> Result<bool, VotingError> {
    let requested = i64::from(van_leaf_position);
    match stored_van_position {
        None => Ok(true),
        Some(existing) if existing < 0 => Err(VotingError::InvalidInput {
            message: format!("invalid stored van_leaf_position: {existing}"),
        }),
        Some(existing) if existing < requested => Err(VotingError::InvalidInput {
            message: format!(
                "delegation van_leaf_position conflict: stored {existing}, requested {requested}"
            ),
        }),
        Some(_) => Ok(false),
    }
}

fn advance_van_position_in_tx(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    van_leaf_position: u32,
) -> Result<(), VotingError> {
    let (_, stored_van_position) =
        load_bundle_confirmation_fields(conn, round_id, wallet_id, bundle_index)?;
    if let Some(stored_van_position) = stored_van_position {
        if stored_van_position < 0 {
            return Err(VotingError::InvalidInput {
                message: format!("invalid stored van_leaf_position: {stored_van_position}"),
            });
        }
        if stored_van_position > i64::from(van_leaf_position) {
            return Ok(());
        }
    }
    queries::store_van_position(conn, round_id, wallet_id, bundle_index, van_leaf_position)
}

fn check_text_conflict(
    existing: Option<&str>,
    requested: &str,
    field: &str,
) -> Result<(), VotingError> {
    if let Some(existing) = existing {
        if existing != requested {
            return Err(VotingError::InvalidInput {
                message: format!("{field} conflict: stored {existing}, requested {requested}"),
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::round::{RoundParams, VotingDb};
    use crate::storage::queries;

    const ROUND_ID: &str = "1111111111111111111111111111111111111111111111111111111111111111";
    const OTHER_ROUND_ID: &str = "2222222222222222222222222222222222222222222222222222222222222222";
    const WALLET_ID: &str = "wallet-1";

    fn event(event_type: &str, key: &str, value: &str) -> TxEvent {
        event_with_attrs(event_type, &[(key, value)])
    }

    fn event_with_attrs(event_type: &str, attributes: &[(&str, &str)]) -> TxEvent {
        TxEvent {
            event_type: event_type.to_string(),
            attributes: attributes
                .iter()
                .map(|(key, value)| TxEventAttribute {
                    key: key.to_string(),
                    value: value.to_string(),
                })
                .collect(),
        }
    }

    fn test_db() -> VotingDb {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(), None)
            .unwrap();
        db
    }

    fn round_params() -> RoundParams {
        RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![0xEA_u8; 32],
            nc_root: vec![0xAA_u8; 32],
            nullifier_imt_root: vec![0xBB_u8; 32],
        }
    }

    fn insert_bundle(db: &VotingDb, bundle_index: u32) {
        let conn = db.conn();
        conn.execute(
            "INSERT INTO bundles (
                round_id, wallet_id, bundle_index, address_index,
                total_note_value, van_comm_rand, gov_comm, alpha
            ) VALUES (
                :round_id, :wallet_id, :bundle_index, :address_index,
                :total_note_value, :van_comm_rand, :gov_comm, :alpha
            )",
            named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
                ":bundle_index": bundle_index as i64,
                ":address_index": 0_i64,
                ":total_note_value": 100_i64,
                ":van_comm_rand": vec![0x11_u8; 32],
                ":gov_comm": vec![0x12_u8; 32],
                ":alpha": vec![0x14_u8; 32],
            },
        )
        .unwrap();
    }

    fn insert_vote(db: &VotingDb, bundle_index: u32, proposal_id: u32) {
        let conn = db.conn();
        conn.execute(
            "INSERT INTO votes (
                round_id, wallet_id, bundle_index, proposal_id, choice,
                commitment, created_at
            ) VALUES (
                :round_id, :wallet_id, :bundle_index, :proposal_id, :choice,
                :commitment, :created_at
            )",
            named_params! {
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
                ":choice": 2_i64,
                ":commitment": recovery_commitment_bytes(),
                ":created_at": 1_i64,
            },
        )
        .unwrap();
    }

    fn valid_recovery_json(vc_tree_position: u64) -> String {
        recovery_json(vc_tree_position, ROUND_ID, 0, 1, 2)
    }

    fn recovery_json(
        vc_tree_position: u64,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        vote_decision: u32,
    ) -> String {
        serde_json::to_string(&serde_json::json!({
            "format": "zcash_voting_vote_recovery_v1",
            "vote_round_id": round_id,
            "bundle_index": bundle_index,
            "proposal_id": proposal_id,
            "vote_decision": vote_decision,
            "anchor_height": 100,
            "vc_tree_position": vc_tree_position,
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
        .unwrap()
    }

    fn recovery_commitment_bytes() -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "van_nullifier": hex::encode(vec![0x31_u8; 32]),
            "vote_authority_note_new": hex::encode(vec![0x32_u8; 32]),
            "vote_commitment": hex::encode(vec![0x33_u8; 32]),
            "proof": hex::encode(vec![0x34_u8; 8]),
        }))
        .unwrap()
    }

    fn store_recovery_json(db: &VotingDb, bundle_index: u32, proposal_id: u32, json: &str) {
        let conn = db.conn();
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = :json
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index
               AND proposal_id = :proposal_id",
            named_params! {
                ":json": json,
                ":round_id": ROUND_ID,
                ":wallet_id": WALLET_ID,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
        )
        .unwrap();
    }

    #[test]
    fn parses_delegation_leaf_index() {
        let parsed = parse_delegation_confirmation_for_round(
            "tx-1",
            ROUND_ID,
            &[event_with_attrs(
                DELEGATE_VOTE_EVENT,
                &[("round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "42")],
            )],
        )
        .unwrap();

        assert_eq!(
            parsed,
            DelegationConfirmation {
                tx_hash: "tx-1".to_string(),
                van_leaf_position: 42,
            }
        );
    }

    #[test]
    fn parses_cast_vote_leaf_indexes() {
        let parsed = parse_vote_confirmation_for_round(
            "tx-1",
            ROUND_ID,
            &[event_with_attrs(
                CAST_VOTE_EVENT,
                &[("round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "7,789")],
            )],
        )
        .unwrap();

        assert_eq!(
            parsed,
            VoteConfirmation {
                tx_hash: "tx-1".to_string(),
                van_leaf_position: 7,
                vc_tree_position: 789,
            }
        );
    }

    #[test]
    fn malformed_cast_vote_leaf_index_fails() {
        let err = parse_vote_confirmation_for_round(
            "tx-1",
            ROUND_ID,
            &[event_with_attrs(
                CAST_VOTE_EVENT,
                &[("round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "7")],
            )],
        )
        .unwrap_err();

        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }

    #[test]
    fn parser_scans_later_matching_events() {
        let parsed = parse_delegation_confirmation_for_round(
            "tx-1",
            ROUND_ID,
            &[
                TxEvent {
                    event_type: DELEGATE_VOTE_EVENT.to_string(),
                    attributes: vec![],
                },
                event_with_attrs(
                    DELEGATE_VOTE_EVENT,
                    &[("round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "42")],
                ),
            ],
        )
        .unwrap();

        assert_eq!(parsed.van_leaf_position, 42);
    }

    #[test]
    fn tx_event_decodes_chain_json_shape() {
        let events: Vec<TxEvent> = serde_json::from_str(
            r#"[{"type":"delegate_vote","attributes":[{"key":"vote_round_id","value":"1111111111111111111111111111111111111111111111111111111111111111"},{"key":"leaf_index","value":"42"}]}]"#,
        )
        .unwrap();

        assert_eq!(
            parse_delegation_confirmation_for_round("tx-1", ROUND_ID, &events)
                .unwrap()
                .van_leaf_position,
            42
        );
    }

    #[test]
    fn confirm_delegation_uses_event_matching_round_id() {
        let db = test_db();
        insert_bundle(&db, 0);
        let confirmation = confirm_delegation_submission(
            &db,
            ROUND_ID,
            0,
            "tx-1",
            &[
                event_with_attrs(
                    DELEGATE_VOTE_EVENT,
                    &[
                        ("vote_round_id", OTHER_ROUND_ID),
                        (LEAF_INDEX_ATTRIBUTE, "99"),
                    ],
                ),
                event_with_attrs(
                    DELEGATE_VOTE_EVENT,
                    &[("vote_round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "42")],
                ),
            ],
        )
        .unwrap();

        assert_eq!(confirmation.van_leaf_position, 42);
        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).unwrap(),
            42
        );
    }

    #[test]
    fn confirm_delegation_rejects_ambiguous_same_round_events() {
        let db = test_db();
        insert_bundle(&db, 0);
        let err = confirm_delegation_submission(
            &db,
            ROUND_ID,
            0,
            "tx-1",
            &[
                event_with_attrs(
                    DELEGATE_VOTE_EVENT,
                    &[("vote_round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "42")],
                ),
                event_with_attrs(
                    DELEGATE_VOTE_EVENT,
                    &[("vote_round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "43")],
                ),
            ],
        )
        .unwrap_err();

        assert!(err.to_string().contains("ambiguous delegate_vote events"));
        assert_eq!(
            queries::get_delegation_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0)
                .unwrap()
                .as_deref(),
            None
        );
    }

    #[test]
    fn confirm_delegation_rejects_missing_round_id() {
        let db = test_db();
        insert_bundle(&db, 0);
        let err = confirm_delegation_submission(
            &db,
            ROUND_ID,
            0,
            "tx-1",
            &[event(DELEGATE_VOTE_EVENT, LEAF_INDEX_ATTRIBUTE, "42")],
        )
        .unwrap_err();

        assert!(err
            .to_string()
            .contains("missing vote_round_id or round_id"));
        assert_eq!(
            queries::get_delegation_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0)
                .unwrap()
                .as_deref(),
            None
        );
    }

    #[test]
    fn records_delegation_confirmation_idempotently() {
        let db = test_db();
        insert_bundle(&db, 0);
        let confirmation = DelegationConfirmation {
            tx_hash: "tx-1".to_string(),
            van_leaf_position: 42,
        };

        record_delegation_confirmation(&db, ROUND_ID, 0, &confirmation).unwrap();
        record_delegation_confirmation(&db, ROUND_ID, 0, &confirmation).unwrap();

        assert_eq!(
            queries::get_delegation_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0)
                .unwrap()
                .as_deref(),
            Some("tx-1")
        );
        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).unwrap(),
            42
        );
        assert_eq!(
            db.delegation_phase(ROUND_ID, 0).unwrap(),
            crate::phases::DelegationPhase::Confirmed
        );
    }

    #[test]
    fn delegation_confirmation_rejects_conflicting_position() {
        let db = test_db();
        insert_bundle(&db, 0);
        record_delegation_confirmation(
            &db,
            ROUND_ID,
            0,
            &DelegationConfirmation {
                tx_hash: "tx-1".to_string(),
                van_leaf_position: 42,
            },
        )
        .unwrap();

        let err = record_delegation_confirmation(
            &db,
            ROUND_ID,
            0,
            &DelegationConfirmation {
                tx_hash: "tx-1".to_string(),
                van_leaf_position: 43,
            },
        )
        .unwrap_err();

        assert!(err.to_string().contains("van_leaf_position conflict"));
    }

    #[test]
    fn delegation_confirmation_rejects_conflicting_tx_hash() {
        let db = test_db();
        insert_bundle(&db, 0);
        record_delegation_confirmation(
            &db,
            ROUND_ID,
            0,
            &DelegationConfirmation {
                tx_hash: "tx-1".to_string(),
                van_leaf_position: 42,
            },
        )
        .unwrap();

        let err = record_delegation_confirmation(
            &db,
            ROUND_ID,
            0,
            &DelegationConfirmation {
                tx_hash: "tx-2".to_string(),
                van_leaf_position: 42,
            },
        )
        .unwrap_err();

        assert!(err.to_string().contains("delegation tx_hash conflict"));
        assert_eq!(
            queries::get_delegation_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0)
                .unwrap()
                .as_deref(),
            Some("tx-1")
        );
    }

    #[test]
    fn records_vote_confirmation_atomically() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        store_recovery_json(&db, 0, 1, &valid_recovery_json(456));
        let confirmation = VoteConfirmation {
            tx_hash: "tx-1".to_string(),
            van_leaf_position: 7,
            vc_tree_position: 789,
        };

        record_vote_confirmation(&db, ROUND_ID, 0, 1, &confirmation).unwrap();
        record_vote_confirmation(&db, ROUND_ID, 0, 1, &confirmation).unwrap();

        assert_eq!(
            queries::get_vote_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0, 1)
                .unwrap()
                .as_deref(),
            Some("tx-1")
        );
        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).unwrap(),
            7
        );
        assert_eq!(
            db.get_commitment_bundle(ROUND_ID, 0, 1)
                .unwrap()
                .map(|(_, position)| position),
            Some(789)
        );
        assert_eq!(
            db.vote_phase(ROUND_ID, 0, 1).unwrap(),
            crate::phases::VotePhase::Confirmed
        );
        let pos: Option<i64> = db
            .conn()
            .query_row(
                "SELECT vc_tree_position FROM votes
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = 0
                   AND proposal_id = 1",
                named_params! {
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(pos, Some(789));
        assert_eq!(
            crate::vote::recovery_bundle(&db, ROUND_ID, 0, 1)
                .unwrap()
                .unwrap()
                .vc_tree_position,
            789
        );
    }

    #[test]
    fn vote_confirmation_advances_van_after_delegation() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        store_recovery_json(&db, 0, 1, &valid_recovery_json(456));
        record_delegation_confirmation(
            &db,
            ROUND_ID,
            0,
            &DelegationConfirmation {
                tx_hash: "delegation-tx".to_string(),
                van_leaf_position: 7,
            },
        )
        .unwrap();

        record_vote_confirmation(
            &db,
            ROUND_ID,
            0,
            1,
            &VoteConfirmation {
                tx_hash: "vote-tx".to_string(),
                van_leaf_position: 8,
                vc_tree_position: 789,
            },
        )
        .unwrap();

        assert_eq!(
            queries::get_vote_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0, 1)
                .unwrap()
                .as_deref(),
            Some("vote-tx")
        );
        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).unwrap(),
            8
        );
        assert_eq!(
            db.get_commitment_bundle(ROUND_ID, 0, 1)
                .unwrap()
                .map(|(_, position)| position),
            Some(789)
        );
    }

    #[test]
    fn delegation_confirmation_replay_does_not_rewind_after_vote_confirmation() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        store_recovery_json(&db, 0, 1, &valid_recovery_json(456));
        let delegation_confirmation = DelegationConfirmation {
            tx_hash: "delegation-tx".to_string(),
            van_leaf_position: 7,
        };
        record_delegation_confirmation(&db, ROUND_ID, 0, &delegation_confirmation).unwrap();
        record_vote_confirmation(
            &db,
            ROUND_ID,
            0,
            1,
            &VoteConfirmation {
                tx_hash: "vote-tx".to_string(),
                van_leaf_position: 8,
                vc_tree_position: 789,
            },
        )
        .unwrap();

        record_delegation_confirmation(&db, ROUND_ID, 0, &delegation_confirmation).unwrap();

        assert_eq!(
            queries::get_delegation_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0)
                .unwrap()
                .as_deref(),
            Some("delegation-tx")
        );
        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).unwrap(),
            8
        );
    }

    #[test]
    fn vote_confirmation_replay_does_not_rewind_later_van_position() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        insert_vote(&db, 0, 2);
        store_recovery_json(&db, 0, 1, &valid_recovery_json(456));
        store_recovery_json(&db, 0, 2, &recovery_json(457, ROUND_ID, 0, 2, 2));
        record_delegation_confirmation(
            &db,
            ROUND_ID,
            0,
            &DelegationConfirmation {
                tx_hash: "delegation-tx".to_string(),
                van_leaf_position: 7,
            },
        )
        .unwrap();
        let first_confirmation = VoteConfirmation {
            tx_hash: "vote-tx-1".to_string(),
            van_leaf_position: 8,
            vc_tree_position: 789,
        };
        let second_confirmation = VoteConfirmation {
            tx_hash: "vote-tx-2".to_string(),
            van_leaf_position: 9,
            vc_tree_position: 790,
        };

        record_vote_confirmation(&db, ROUND_ID, 0, 1, &first_confirmation).unwrap();
        record_vote_confirmation(&db, ROUND_ID, 0, 2, &second_confirmation).unwrap();
        record_vote_confirmation(&db, ROUND_ID, 0, 1, &first_confirmation).unwrap();

        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).unwrap(),
            9
        );
        assert_eq!(
            db.get_commitment_bundle(ROUND_ID, 0, 1)
                .unwrap()
                .map(|(_, position)| position),
            Some(789)
        );
        assert_eq!(
            db.get_commitment_bundle(ROUND_ID, 0, 2)
                .unwrap()
                .map(|(_, position)| position),
            Some(790)
        );
    }

    #[test]
    fn vote_confirmation_requires_recovery_bundle_and_rolls_back_tx_hash() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);

        let err = record_vote_confirmation(
            &db,
            ROUND_ID,
            0,
            1,
            &VoteConfirmation {
                tx_hash: "vote-tx".to_string(),
                van_leaf_position: 8,
                vc_tree_position: 789,
            },
        )
        .unwrap_err();

        assert!(err.to_string().contains("vote recovery bundle not found"));
        assert_eq!(
            queries::get_vote_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0, 1)
                .unwrap()
                .as_deref(),
            None
        );
    }

    #[test]
    fn vote_confirmation_rolls_back_when_recovery_json_update_fails() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        store_recovery_json(&db, 0, 1, "not valid json");

        let err = record_vote_confirmation(
            &db,
            ROUND_ID,
            0,
            1,
            &VoteConfirmation {
                tx_hash: "vote-tx".to_string(),
                van_leaf_position: 8,
                vc_tree_position: 789,
            },
        )
        .unwrap_err();

        assert!(err.to_string().contains("invalid vote recovery JSON"));
        assert_eq!(
            queries::get_vote_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0, 1)
                .unwrap()
                .as_deref(),
            None
        );
        assert!(queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).is_err());
        let (json, pos): (Option<String>, Option<i64>) = db
            .conn()
            .query_row(
                "SELECT commitment_bundle_json, vc_tree_position FROM votes
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = 0
                   AND proposal_id = 1",
                named_params! {
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(json.as_deref(), Some("not valid json"));
        assert_eq!(pos, None);
    }

    #[test]
    fn vote_confirmation_rolls_back_when_recovery_json_identity_mismatches() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        let recovery_json = recovery_json(456, ROUND_ID, 0, 2, 2);
        store_recovery_json(&db, 0, 1, &recovery_json);

        let err = record_vote_confirmation(
            &db,
            ROUND_ID,
            0,
            1,
            &VoteConfirmation {
                tx_hash: "vote-tx".to_string(),
                van_leaf_position: 8,
                vc_tree_position: 789,
            },
        )
        .unwrap_err();

        assert!(err.to_string().contains("proposal_id mismatch"));
        assert_eq!(
            queries::get_vote_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0, 1)
                .unwrap()
                .as_deref(),
            None
        );
        assert!(queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).is_err());
        let (json, pos): (Option<String>, Option<i64>) = db
            .conn()
            .query_row(
                "SELECT commitment_bundle_json, vc_tree_position FROM votes
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = 0
                   AND proposal_id = 1",
                named_params! {
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(json.as_deref(), Some(recovery_json.as_str()));
        assert_eq!(pos, None);
    }

    #[test]
    fn confirm_vote_rejects_ambiguous_same_round_events() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        let err = confirm_vote_submission(
            &db,
            ROUND_ID,
            0,
            1,
            "tx-1",
            &[
                event_with_attrs(
                    CAST_VOTE_EVENT,
                    &[("vote_round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "7,789")],
                ),
                event_with_attrs(
                    CAST_VOTE_EVENT,
                    &[("vote_round_id", ROUND_ID), (LEAF_INDEX_ATTRIBUTE, "8,790")],
                ),
            ],
        )
        .unwrap_err();

        assert!(err.to_string().contains("ambiguous cast_vote events"));
        assert_eq!(
            queries::get_vote_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0, 1)
                .unwrap()
                .as_deref(),
            None
        );
    }

    #[test]
    fn confirm_vote_rejects_mismatched_round_id_without_writes() {
        let db = test_db();
        insert_bundle(&db, 0);
        insert_vote(&db, 0, 1);
        let recovery_json = valid_recovery_json(456);
        store_recovery_json(&db, 0, 1, &recovery_json);

        let err = confirm_vote_submission(
            &db,
            ROUND_ID,
            0,
            1,
            "vote-tx",
            &[event_with_attrs(
                CAST_VOTE_EVENT,
                &[
                    ("round_id", OTHER_ROUND_ID),
                    (LEAF_INDEX_ATTRIBUTE, "8,789"),
                ],
            )],
        )
        .unwrap_err();

        assert!(err.to_string().contains("round id mismatch"));
        assert_eq!(
            queries::get_vote_tx_hash(&db.conn(), ROUND_ID, WALLET_ID, 0, 1)
                .unwrap()
                .as_deref(),
            None
        );
        assert!(queries::load_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0).is_err());
        let (json, pos): (Option<String>, Option<i64>) = db
            .conn()
            .query_row(
                "SELECT commitment_bundle_json, vc_tree_position FROM votes
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = 0
                   AND proposal_id = 1",
                named_params! {
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(json.as_deref(), Some(recovery_json.as_str()));
        assert_eq!(pos, None);
    }
}
