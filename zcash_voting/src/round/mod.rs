//! Round setup and bundle planning API.
//!
//! This module is the stable setup surface for wallet SDKs. It keeps database
//! ownership in [`VotingDb`] while hiding the low-level query helpers that back
//! the SQLite schema.

use std::path::{Path, PathBuf};

use rusqlite::{named_params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::{
    note_bundling::{canonical_note_bundle_plan_for_notes, BundlePolicy},
    storage::{queries, RoundState, VotingDb as InnerVotingDb},
    types::{Network, NoteInfo, VotingError, VotingRoundParams},
};

/// Stable public name for vote-round parameters supplied by the vote chain.
pub type RoundParams = VotingRoundParams;

/// Public database handle for persisted voting state.
pub type VotingDb = InnerVotingDb;

/// Query summary for one voting round in the current wallet scope.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RoundInfo {
    pub round_id: String,
    pub network: Network,
    pub snapshot_height: u64,
    pub hotkey_address: Option<String>,
    pub eligible_weight: Option<u64>,
    pub bundle_count: u32,
    pub created_at: u64,
}

/// Result of idempotently planning or validating note bundles for a round.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BundleLayout {
    pub bundle_count: u32,
    #[serde(rename = "eligible_weight_zatoshi")]
    pub eligible_weight: u64,
    #[serde(default)]
    pub dropped_count: u32,
}

/// Validates that `bundle_index` is in `[0, bundle_count)`.
pub fn validate_bundle_index(
    bundle_count: u32,
    bundle_index: u32,
    bundle_kind: &str,
) -> Result<(), VotingError> {
    if bundle_index < bundle_count {
        Ok(())
    } else {
        Err(VotingError::InvalidInput {
            message: format!(
                "bundle_index {bundle_index} is out of range for {bundle_count} {bundle_kind} bundles"
            ),
        })
    }
}

/// Resolves the human-readable round name used in delegation PCZT metadata.
///
/// An empty `round_name` falls back to [`RoundParams::vote_round_id`].
pub fn delegation_round_name(params: &RoundParams, round_name: &str) -> String {
    if round_name.is_empty() {
        params.vote_round_id.clone()
    } else {
        round_name.to_string()
    }
}

/// Returns the note rows for one bundle index after [`VotingDb::ensure_bundles`].
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when no bundles exist, `bundle_index`
/// is out of range, or note bundling fails.
pub fn bundle_notes_for_index(
    round_note_infos: &[NoteInfo],
    bundle_setup: &BundleLayout,
    bundle_index: u32,
) -> Result<Vec<NoteInfo>, VotingError> {
    bundle_notes_for_index_with_policy(
        round_note_infos,
        bundle_setup,
        bundle_index,
        BundlePolicy::default(),
    )
}

/// Returns the note rows for one bundle index under an explicit bundle policy.
///
/// The policy must match the one used to create or validate `bundle_setup`.
pub fn bundle_notes_for_index_with_policy(
    round_note_infos: &[NoteInfo],
    bundle_setup: &BundleLayout,
    bundle_index: u32,
    policy: BundlePolicy,
) -> Result<Vec<NoteInfo>, VotingError> {
    if bundle_setup.bundle_count == 0 {
        return Err(VotingError::InvalidInput {
            message: "No eligible voting bundles were created for delegation".to_string(),
        });
    }
    if bundle_index >= bundle_setup.bundle_count {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle_index {bundle_index} is out of range for {} delegation bundles",
                bundle_setup.bundle_count
            ),
        });
    }
    note_bundles_with_policy(round_note_infos, policy)?
        .get(bundle_index as usize)
        .cloned()
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!("bundle_index {bundle_index} has no eligible note bundle"),
        })
}

/// Returns the canonical eligible note bundles for a round note set.
///
/// This is the read-only counterpart to [`VotingDb::ensure_bundles`]. Wallets
/// that need to operate on one bundle after setup can use this instead of
/// depending on the lower-level chunking internals.
///
/// Duplicate nullifiers are collapsed before chunking so each spendable note can
/// appear in at most one bundle.
pub fn note_bundles(notes: &[NoteInfo]) -> Result<Vec<Vec<NoteInfo>>, VotingError> {
    note_bundles_with_policy(notes, BundlePolicy::default())
}

/// Returns the eligible note bundles for a round note set under an explicit policy.
pub fn note_bundles_with_policy(
    notes: &[NoteInfo],
    policy: BundlePolicy,
) -> Result<Vec<Vec<NoteInfo>>, VotingError> {
    Ok(canonical_note_bundle_plan_for_notes(notes, policy)?.bundles)
}

/// Returns the unquantized zatoshi value for a bundle.
///
/// The sum is checked so caller-visible bundle reports cannot silently wrap on
/// malformed or unexpectedly large note sets.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] if summing note values overflows `u64`.
pub fn raw_bundle_weight(notes: &[NoteInfo]) -> Result<u64, VotingError> {
    notes.iter().try_fold(0u64, |acc, note| {
        acc.checked_add(note.value)
            .ok_or_else(|| VotingError::InvalidInput {
                message: "delegation bundle weight overflows u64".to_string(),
            })
    })
}

/// Returns the bundle voting weight rounded down to the ballot divisor.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] if summing note values overflows `u64`.
pub fn quantized_bundle_weight(notes: &[NoteInfo]) -> Result<u64, VotingError> {
    let raw = raw_bundle_weight(notes)?;
    Ok((raw / crate::governance::BALLOT_DIVISOR) * crate::governance::BALLOT_DIVISOR)
}

/// Returns the quantized voting weight for a set of persisted bundles.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] if any bundle sum or the final set sum
/// overflows `u64`.
pub fn quantized_bundle_set_weight(bundles: &[Vec<NoteInfo>]) -> Result<u64, VotingError> {
    bundles.iter().try_fold(0u64, |acc, bundle| {
        let weight = quantized_bundle_weight(bundle)?;
        acc.checked_add(weight)
            .ok_or_else(|| VotingError::InvalidInput {
                message: "delegation bundle set weight overflows u64".to_string(),
            })
    })
}

impl VotingDb {
    /// Returns the sidecar voting DB path for a wallet DB path.
    ///
    /// The sidecar lives next to the wallet DB with a `.voting` suffix so
    /// voting migrations cannot affect the wallet DB `user_version`.
    pub fn wallet_sidecar_path(wallet_db_path: &Path) -> PathBuf {
        let mut sidecar = wallet_db_path.as_os_str().to_os_string();
        sidecar.push(".voting");
        PathBuf::from(sidecar)
    }

    /// Opens the voting sidecar database for `wallet_db_path` and binds `wallet_id`.
    pub fn open_wallet_sidecar(
        wallet_db_path: &Path,
        wallet_id: &str,
    ) -> Result<Self, VotingError> {
        let sidecar_path = Self::wallet_sidecar_path(wallet_db_path);
        let db = Self::open_path(&sidecar_path)?;
        db.set_wallet_id(wallet_id);
        Ok(db)
    }

    /// Opens or creates a voting database at `path` and runs migrations.
    ///
    /// Call [`VotingDb::set_wallet_id`] before performing wallet-scoped round
    /// operations. Passing `:memory:` is supported through the legacy string
    /// API; prefer [`VotingDb::open_in_memory`] for in-memory tests.
    pub fn open_path(path: &Path) -> Result<Self, VotingError> {
        Self::open(path.to_str().ok_or_else(|| VotingError::InvalidInput {
            message: "voting database path is not valid UTF-8".to_string(),
        })?)
    }

    /// Opens a fresh in-memory voting database for tests and examples.
    pub fn open_in_memory() -> Result<Self, VotingError> {
        Self::open(":memory:")
    }

    /// Creates a voting round for the current wallet.
    ///
    /// The round id comes from `params.vote_round_id`. This call persists the
    /// round parameters and is idempotent only at the caller layer; inserting an
    /// already-existing `(wallet_id, round_id)` pair returns an error from the
    /// underlying SQLite constraint.
    pub fn create_round(
        &self,
        network: Network,
        params: &RoundParams,
        session_json: Option<&str>,
    ) -> Result<(), VotingError> {
        crate::types::validate_round_params(params)?;
        self.init_round(network, params, session_json)
    }

    /// Ensures a round exists for `params`, initializing it when absent.
    ///
    /// Existing rounds are left unchanged. `session_json` is stored only on the
    /// first insert.
    pub fn ensure_round(
        &self,
        network: Network,
        params: &RoundParams,
        session_json: Option<&str>,
    ) -> Result<(), VotingError> {
        crate::types::validate_round_params(params)?;
        if self.has_round(&params.vote_round_id)? {
            let conn = self.conn();
            let wallet_id = self.wallet_id();
            let stored_network =
                queries::load_round_network(&conn, &params.vote_round_id, &wallet_id)?;
            if stored_network != network {
                return Err(VotingError::InvalidInput {
                    message: format!(
                        "round {} exists for network {:?}, not {:?}",
                        params.vote_round_id, stored_network, network
                    ),
                });
            }
            return Ok(());
        }
        self.init_round(network, params, session_json)
    }

    /// Ensures a round exists and returns its persisted state.
    ///
    /// Existing rounds are returned unchanged. Missing rounds are initialized
    /// with `session_json` and then reloaded.
    pub fn ensure_round_state(
        &self,
        network: Network,
        params: &RoundParams,
        session_json: Option<&str>,
    ) -> Result<RoundState, VotingError> {
        self.ensure_round(network, params, session_json)?;
        self.get_round_state(&params.vote_round_id)
    }

    /// Loads one round summary for the current wallet.
    ///
    /// Returns `Ok(None)` when the round does not exist. Other database errors
    /// are returned as [`VotingError::Internal`].
    pub fn round(&self, round_id: &str) -> Result<Option<RoundInfo>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let row = conn
            .query_row(
                "SELECT network, snapshot_height, created_at
                 FROM rounds
                 WHERE round_id = :round_id AND wallet_id = :wallet_id",
                named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to load round {round_id}: {e}"),
            })?;

        let Some((network, snapshot_height, created_at)) = row else {
            return Ok(None);
        };
        let network = queries::network_from_storage(&network)?;

        let bundle_count = queries::get_bundle_count(&conn, round_id, &wallet_id)?;
        let eligible_weight = round_eligible_weight(&conn, round_id, &wallet_id)?;

        Ok(Some(RoundInfo {
            round_id: round_id.to_string(),
            network,
            snapshot_height: snapshot_height as u64,
            hotkey_address: None,
            eligible_weight,
            bundle_count,
            created_at: created_at as u64,
        }))
    }

    /// Lists all rounds for the current wallet in newest-first order.
    pub fn rounds(&self) -> Result<Vec<RoundInfo>, VotingError> {
        self.list_rounds()?
            .into_iter()
            .map(|summary| {
                self.round(&summary.round_id)?
                    .ok_or_else(|| VotingError::Internal {
                        message: format!("round disappeared while listing: {}", summary.round_id),
                    })
            })
            .collect()
    }

    /// Deletes all persisted state for one round in the current wallet scope.
    pub fn delete_round(&self, round_id: &str) -> Result<(), VotingError> {
        self.clear_round(round_id)
    }

    /// Creates bundle rows for `notes`, or validates existing bundle rows.
    ///
    /// The note ordering, duplicate-nullifier handling, and weight quantization
    /// are the canonical library policy. On first call, surviving bundles are
    /// persisted. On later calls, the same notes must reproduce the stored
    /// bundle identities.
    pub fn ensure_bundles(
        &self,
        round_id: &str,
        notes: &[NoteInfo],
    ) -> Result<BundleLayout, VotingError> {
        self.ensure_bundles_with_policy(round_id, notes, BundlePolicy::default())
    }

    /// Creates bundle rows for `notes`, or validates existing rows under `policy`.
    ///
    /// The note ordering, duplicate-nullifier handling, and weight quantization
    /// are controlled by `policy`. On first call, surviving bundles are
    /// persisted. On later calls, the same notes and policy must reproduce the
    /// stored bundle identities.
    pub fn ensure_bundles_with_policy(
        &self,
        round_id: &str,
        notes: &[NoteInfo],
        policy: BundlePolicy,
    ) -> Result<BundleLayout, VotingError> {
        let plan = canonical_note_bundle_plan_for_notes(notes, policy)?;
        let expected_count = plan.bundles.len() as u32;
        let existing_count = self.get_bundle_count(round_id)?;

        if existing_count == 0 {
            let (bundle_count, eligible_weight) = self.persist_bundle_plan(round_id, &plan)?;
            return Ok(BundleLayout {
                bundle_count,
                eligible_weight,
                dropped_count: plan.dropped_count as u32,
            });
        }

        if existing_count != expected_count {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "existing bundle count {existing_count} does not match planned bundle count {expected_count}"
                ),
            });
        }

        let conn = self.conn();
        let wallet_id = self.wallet_id();
        for (bundle_index, bundle_notes) in plan.bundles.iter().enumerate() {
            queries::require_bundle_notes(
                &conn,
                round_id,
                &wallet_id,
                bundle_index as u32,
                bundle_notes,
            )?;
        }

        Ok(BundleLayout {
            bundle_count: expected_count,
            eligible_weight: plan.eligible_weight,
            dropped_count: plan.dropped_count as u32,
        })
    }

    /// Creates bundle rows or validates a persisted prefix of bundle rows.
    ///
    /// This variant supports Keystone recovery flows where the user intentionally
    /// skips unsigned trailing bundles. Existing rows must still match the
    /// current note selection prefix exactly.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] if `notes` are invalid, if the
    /// current note selection has fewer bundles than storage, if persisted
    /// bundle note identities do not match, or if bundle weight calculation
    /// overflows. Database failures are returned as [`VotingError::Internal`].
    pub fn ensure_bundles_with_skipped_suffix(
        &self,
        round_id: &str,
        notes: &[NoteInfo],
    ) -> Result<BundleLayout, VotingError> {
        self.ensure_bundles_with_skipped_suffix_with_policy(
            round_id,
            notes,
            BundlePolicy::default(),
        )
    }

    /// Creates bundle rows or validates a persisted prefix under `policy`.
    ///
    /// This variant supports Keystone recovery flows where the user intentionally
    /// skips unsigned trailing bundles. Existing rows must still match the
    /// current note selection prefix exactly under the supplied policy.
    pub fn ensure_bundles_with_skipped_suffix_with_policy(
        &self,
        round_id: &str,
        notes: &[NoteInfo],
        policy: BundlePolicy,
    ) -> Result<BundleLayout, VotingError> {
        crate::types::validate_notes_for_round(notes)?;
        let stored_count = self.get_bundle_count(round_id)?;
        if stored_count == 0 {
            return self.ensure_bundles_with_policy(round_id, notes, policy);
        }

        let bundles = note_bundles_with_policy(notes, policy)?;
        if bundles.len() < stored_count as usize {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "current note selection produces {} delegation bundles, but {stored_count} bundle rows are already persisted for round {round_id}",
                    bundles.len()
                ),
            });
        }

        let stored_bundles = &bundles[..stored_count as usize];
        validate_persisted_bundle_notes(self, round_id, stored_bundles)?;
        Ok(BundleLayout {
            bundle_count: stored_count,
            eligible_weight: quantized_bundle_set_weight(stored_bundles)?,
            dropped_count: 0,
        })
    }
}

fn validate_persisted_bundle_notes(
    db: &VotingDb,
    round_id: &str,
    bundles: &[Vec<NoteInfo>],
) -> Result<(), VotingError> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    for (bundle_index, bundle_notes) in bundles.iter().enumerate() {
        queries::require_bundle_notes(
            &conn,
            round_id,
            &wallet_id,
            bundle_index as u32,
            bundle_notes,
        )?;
    }
    Ok(())
}

fn round_eligible_weight(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Option<u64>, VotingError> {
    let total: Option<i64> = conn
        .query_row(
            "SELECT SUM((total_note_value / :ballot_divisor) * :ballot_divisor)
             FROM bundles
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":ballot_divisor": crate::governance::BALLOT_DIVISOR as i64,
            },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to calculate round eligible weight: {e}"),
        })?;

    Ok(total.map(|v| v as u64))
}

#[cfg(test)]
mod tests {
    use super::*;

    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";

    fn test_db(wallet_id: &str) -> VotingDb {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(wallet_id);
        db.create_round(Network::Testnet, &round_params(), None)
            .unwrap();
        db
    }

    #[test]
    fn wallet_sidecar_path_appends_voting_suffix() {
        let path = std::path::Path::new("/tmp/wallet.sqlite");
        assert_eq!(
            VotingDb::wallet_sidecar_path(path),
            std::path::PathBuf::from("/tmp/wallet.sqlite.voting")
        );
    }

    #[test]
    fn open_wallet_sidecar_opens_schema_and_sets_wallet_id() {
        let wallet_path = std::env::temp_dir().join(format!(
            "zcash-voting-sidecar-{}.sqlite",
            std::process::id()
        ));
        let sidecar = VotingDb::wallet_sidecar_path(&wallet_path);
        if sidecar.exists() {
            std::fs::remove_file(&sidecar).ok();
        }

        let db = VotingDb::open_wallet_sidecar(&wallet_path, "wallet-sidecar").unwrap();

        assert_eq!(db.wallet_id(), "wallet-sidecar");
        assert!(db.list_rounds().unwrap().is_empty());
        assert!(sidecar.exists());

        std::fs::remove_file(sidecar).ok();
    }

    fn round_params() -> RoundParams {
        RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 1000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    #[test]
    fn ensure_round_rejects_existing_round_network_mismatch() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("wallet-network");
        let params = round_params();

        db.ensure_round(Network::Testnet, &params, None).unwrap();
        let err = db
            .ensure_round(Network::Mainnet, &params, None)
            .expect_err("existing round cannot be rebound to another network");

        assert!(err.to_string().contains("exists for network"), "{err}");
    }

    fn note(position: u64, value: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![position as u8; 32],
            nullifier: vec![position as u8 + 1; 32],
            value,
            position,
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    #[test]
    fn validate_bundle_index_rejects_out_of_range() {
        assert!(validate_bundle_index(2, 0, "voting").is_ok());
        assert!(validate_bundle_index(2, 1, "voting").is_ok());

        let err = validate_bundle_index(2, 2, "voting").unwrap_err();
        assert!(err.to_string().contains("out of range"), "{err}");

        let err = validate_bundle_index(0, 0, "delegation").unwrap_err();
        assert!(err.to_string().contains("0 delegation bundles"), "{err}");
    }

    #[test]
    fn ensure_bundles_creates_and_validates_idempotently() {
        let db = test_db("wallet-a");
        let notes = vec![note(0, crate::governance::BALLOT_DIVISOR)];

        let created = db.ensure_bundles(ROUND_ID, &notes).unwrap();
        let reused = db.ensure_bundles(ROUND_ID, &notes).unwrap();

        assert_eq!(created.bundle_count, 1);
        assert_eq!(created.eligible_weight, crate::governance::BALLOT_DIVISOR);
        assert_eq!(reused, created);
    }

    #[test]
    fn ensure_bundles_uses_custom_real_note_capacity() {
        let db = test_db("wallet-policy");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR),
            note(1, crate::governance::BALLOT_DIVISOR),
            note(2, crate::governance::BALLOT_DIVISOR),
        ];
        let policy = BundlePolicy::new(1).unwrap();

        let layout = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();
        let bundles = note_bundles_with_policy(&notes, policy).unwrap();

        assert_eq!(layout.bundle_count, 3);
        assert_eq!(
            layout.eligible_weight,
            3 * crate::governance::BALLOT_DIVISOR
        );
        assert!(bundles.iter().all(|bundle| bundle.len() == 1));
        assert_eq!(
            bundle_notes_for_index_with_policy(&notes, &layout, 2, policy)
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn note_bundles_deduplicates_duplicate_nullifiers() {
        let base_note = note(0, crate::governance::BALLOT_DIVISOR);
        let notes = vec![base_note.clone(); crate::governance::BUNDLE_NOTE_SLOTS];

        let bundles = note_bundles(&notes).unwrap();

        assert_eq!(bundles, vec![vec![base_note]]);
    }

    #[test]
    fn ensure_bundles_persists_canonical_deduplicated_notes() {
        let db = test_db("wallet-duplicate-nullifiers");
        let base_note = note(0, crate::governance::BALLOT_DIVISOR);
        let notes = vec![base_note.clone(); crate::governance::BUNDLE_NOTE_SLOTS];

        let layout = db.ensure_bundles(ROUND_ID, &notes).unwrap();
        let bundle = bundle_notes_for_index(&notes, &layout, 0).unwrap();

        assert_eq!(layout.bundle_count, 1);
        assert_eq!(layout.eligible_weight, crate::governance::BALLOT_DIVISOR);
        assert_eq!(bundle, vec![base_note]);
    }

    #[test]
    fn ensure_bundles_rejects_existing_rows_when_policy_changes_shape() {
        let db = test_db("wallet-policy-change");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR),
            note(1, crate::governance::BALLOT_DIVISOR),
            note(2, crate::governance::BALLOT_DIVISOR),
            note(3, crate::governance::BALLOT_DIVISOR),
            note(4, crate::governance::BALLOT_DIVISOR),
            note(5, crate::governance::BALLOT_DIVISOR),
        ];
        db.ensure_bundles_with_policy(ROUND_ID, &notes, BundlePolicy::new(1).unwrap())
            .unwrap();

        let err = db
            .ensure_bundles(ROUND_ID, &notes)
            .expect_err("default policy must not reuse policy-1 rows");

        assert!(
            err.to_string()
                .contains("existing bundle count 6 does not match planned bundle count 2"),
            "{err}"
        );
    }

    #[test]
    fn ensure_bundles_rejects_changed_existing_bundle_identity() {
        let db = test_db("wallet-b");
        db.ensure_bundles(ROUND_ID, &[note(0, crate::governance::BALLOT_DIVISOR)])
            .unwrap();

        let mut substituted = note(0, crate::governance::BALLOT_DIVISOR);
        substituted.nullifier[0] ^= 0x01;

        let err = db.ensure_bundles(ROUND_ID, &[substituted]).unwrap_err();

        assert!(err.to_string().contains("note identity mismatch"), "{err}");
    }

    #[test]
    fn round_reports_bundle_count_and_quantized_weight() {
        let db = test_db("wallet-c");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR + 1),
            note(1, crate::governance::BALLOT_DIVISOR),
            note(2, 1),
            note(3, 1),
            note(4, 1),
            note(5, crate::governance::BALLOT_DIVISOR),
        ];
        let layout = db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.conn()
            .execute(
                "UPDATE bundles
                 SET total_note_value = ?1
                 WHERE round_id = ?2 AND wallet_id = ?3 AND bundle_index = 0",
                rusqlite::params![layout.eligible_weight as i64 + 1, ROUND_ID, "wallet-c"],
            )
            .unwrap();

        let round = db.round(ROUND_ID).unwrap().unwrap();

        assert_eq!(round.bundle_count, layout.bundle_count);
        assert_eq!(round.eligible_weight, Some(layout.eligible_weight));
    }

    #[test]
    fn ensure_bundles_with_skipped_suffix_accepts_persisted_prefix() {
        let db = test_db("wallet-d");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR),
            note(1, crate::governance::BALLOT_DIVISOR),
            note(2, crate::governance::BALLOT_DIVISOR),
            note(3, crate::governance::BALLOT_DIVISOR),
            note(4, crate::governance::BALLOT_DIVISOR),
            note(5, crate::governance::BALLOT_DIVISOR),
        ];
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.delete_skipped_bundles(ROUND_ID, 1).unwrap();

        let reused = db
            .ensure_bundles_with_skipped_suffix(ROUND_ID, &notes)
            .unwrap();

        assert_eq!(reused.bundle_count, 1);
        assert_eq!(
            reused.eligible_weight,
            5 * crate::governance::BALLOT_DIVISOR
        );
    }

    #[test]
    fn ensure_bundles_with_skipped_suffix_uses_custom_policy() {
        let db = test_db("wallet-policy-skip");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR),
            note(1, crate::governance::BALLOT_DIVISOR),
            note(2, crate::governance::BALLOT_DIVISOR),
        ];
        let policy = BundlePolicy::new(1).unwrap();
        db.ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();
        db.delete_skipped_bundles(ROUND_ID, 2).unwrap();

        let reused = db
            .ensure_bundles_with_skipped_suffix_with_policy(ROUND_ID, &notes, policy)
            .unwrap();

        assert_eq!(reused.bundle_count, 2);
        assert_eq!(
            reused.eligible_weight,
            2 * crate::governance::BALLOT_DIVISOR
        );
    }

    #[test]
    fn ensure_bundles_with_skipped_suffix_rejects_missing_stored_bundle() {
        let db = test_db("wallet-e");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR),
            note(1, crate::governance::BALLOT_DIVISOR),
            note(2, crate::governance::BALLOT_DIVISOR),
            note(3, crate::governance::BALLOT_DIVISOR),
            note(4, crate::governance::BALLOT_DIVISOR),
            note(5, crate::governance::BALLOT_DIVISOR),
        ];
        db.ensure_bundles(ROUND_ID, &notes).unwrap();

        let err = db
            .ensure_bundles_with_skipped_suffix(
                ROUND_ID,
                &[note(0, crate::governance::BALLOT_DIVISOR)],
            )
            .unwrap_err()
            .to_string();

        assert!(
            err.contains("current note selection produces 1 delegation bundles"),
            "{err}"
        );
    }

    #[test]
    fn bundle_weight_helpers_quantize_and_check_sets() {
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR + 1),
            note(1, crate::governance::BALLOT_DIVISOR / 2),
        ];

        assert_eq!(
            raw_bundle_weight(&notes).unwrap(),
            crate::governance::BALLOT_DIVISOR + 1 + crate::governance::BALLOT_DIVISOR / 2
        );
        assert_eq!(
            quantized_bundle_weight(&notes).unwrap(),
            crate::governance::BALLOT_DIVISOR
        );
        assert_eq!(
            quantized_bundle_set_weight(&[notes]).unwrap(),
            crate::governance::BALLOT_DIVISOR
        );
    }

    #[test]
    fn bundle_weight_helpers_reject_overflow() {
        let err = raw_bundle_weight(&[note(0, u64::MAX), note(1, 1)])
            .unwrap_err()
            .to_string();

        assert!(err.contains("delegation bundle weight overflows u64"));

        let near_max =
            (u64::MAX / crate::governance::BALLOT_DIVISOR) * crate::governance::BALLOT_DIVISOR;
        let err = quantized_bundle_set_weight(&[vec![note(0, near_max)], vec![note(1, near_max)]])
            .unwrap_err()
            .to_string();

        assert!(err.contains("delegation bundle set weight overflows u64"));
    }
}
