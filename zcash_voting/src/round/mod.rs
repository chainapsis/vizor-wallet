//! Round setup and bundle planning API.
//!
//! This module is the stable setup surface for wallet SDKs. It keeps database
//! ownership in [`VotingDb`] while hiding the low-level query helpers that back
//! the SQLite schema.

use std::path::{Path, PathBuf};

use rusqlite::{named_params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::{
    note_bundling::{canonical_note_bundle_plan_for_notes, BundlePolicy, PrivacyTrim},
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
    /// What the privacy trim removed while planning this round.
    #[serde(default)]
    pub privacy_trim: PrivacyTrim,
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

/// Returns the note rows for one bundle index using the policy authoritative for
/// `round_id`.
///
/// Wallet setup persists the effective policy before this helper is used.
///
/// # Errors
///
/// Returns an error when the round policy cannot be loaded, no bundles exist,
/// `bundle_index` is out of range, or note bundling fails.
pub fn bundle_notes_for_index_for_round(
    round_note_infos: &[NoteInfo],
    bundle_setup: &BundleLayout,
    bundle_index: u32,
    voting_db: &VotingDb,
    round_id: &str,
) -> Result<Vec<NoteInfo>, VotingError> {
    let policy = voting_db.effective_bundle_policy(round_id, BundlePolicy::default())?;
    bundle_notes_for_index_with_policy(round_note_infos, bundle_setup, bundle_index, policy)
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

/// Returns the canonical eligible note bundles under the current default policy.
///
/// This helper does not consult persisted round state. Use
/// [`note_bundles_for_round`] when interpreting an existing round.
///
/// Duplicate nullifiers are collapsed before chunking so each spendable note can
/// appear in at most one bundle.
pub fn note_bundles(notes: &[NoteInfo]) -> Result<Vec<Vec<NoteInfo>>, VotingError> {
    note_bundles_with_policy(notes, BundlePolicy::default())
}

/// Returns the eligible note bundles using the policy authoritative for
/// `round_id`.
///
/// Wallet setup persists the effective policy before this helper is used.
pub fn note_bundles_for_round(
    notes: &[NoteInfo],
    voting_db: &VotingDb,
    round_id: &str,
) -> Result<Vec<Vec<NoteInfo>>, VotingError> {
    let policy = voting_db.effective_bundle_policy(round_id, BundlePolicy::default())?;
    note_bundles_with_policy(notes, policy)
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

    /// Returns the policy a round's bundle plan must be derived with.
    ///
    /// A stored readable policy is authoritative. Rounds with no stored policy,
    /// or whose stored JSON is an unknown/unreadable schema, fall back to
    /// `requested`, with one exception: a round that already has persisted
    /// bundle rows was planned without a readable policy for this binary, so
    /// the trim is disabled for it. Re-deriving those rows under a trimming
    /// policy would plan a smaller bundle count than storage holds and
    /// permanently reject the round. Only the trim is overridden, so the
    /// caller's note capacity and value threshold still apply -- those are
    /// what the persisted rows were planned with.
    pub(crate) fn effective_bundle_policy(
        &self,
        round_id: &str,
        requested: BundlePolicy,
    ) -> Result<BundlePolicy, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        if let Some(stored) = queries::get_round_bundle_policy(&conn, round_id, &wallet_id)? {
            return Ok(stored);
        }
        if queries::get_bundle_count(&conn, round_id, &wallet_id)? > 0 {
            return Ok(requested.with_max_privacy_bundles(None));
        }
        Ok(requested)
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
        // A round's bundle rows must keep re-deriving for the life of the round,
        // so once a plan is persisted its policy becomes authoritative and the
        // caller's is ignored. Otherwise an SDK upgrade that changes the
        // defaults would invalidate bundles that were already signed.
        let policy = self.effective_bundle_policy(round_id, policy)?;
        let plan = canonical_note_bundle_plan_for_notes(notes, policy)?;
        let expected_count = plan.bundles.len() as u32;
        let existing_count = self.get_bundle_count(round_id)?;

        if existing_count == 0 {
            let (bundle_count, eligible_weight) =
                self.persist_bundle_plan(round_id, &plan, policy)?;
            return Ok(BundleLayout {
                bundle_count,
                eligible_weight,
                dropped_count: plan.dropped_count as u32,
                privacy_trim: plan.privacy_trim,
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
        // Record the policy only after it reproduces every persisted bundle.
        // This also replaces unreadable policy JSON with the validated fallback
        // so later passes do not reinterpret the same rows differently.
        queries::set_round_bundle_policy(&conn, round_id, &wallet_id, policy)?;

        Ok(BundleLayout {
            bundle_count: expected_count,
            eligible_weight: plan.eligible_weight,
            dropped_count: plan.dropped_count as u32,
            privacy_trim: plan.privacy_trim,
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

        let policy = self.effective_bundle_policy(round_id, policy)?;
        let plan = canonical_note_bundle_plan_for_notes(notes, policy)?;
        let bundles = plan.bundles;
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
        // Record the policy only after it reproduces the persisted prefix,
        // replacing unreadable policy JSON with the validated fallback.
        let conn = self.conn();
        queries::set_round_bundle_policy(&conn, round_id, &self.wallet_id(), policy)?;
        Ok(BundleLayout {
            bundle_count: stored_count,
            eligible_weight: quantized_bundle_set_weight(stored_bundles)?,
            // `dropped_count` stays 0 here: this view describes the persisted
            // prefix, not the notes planning left out. The privacy trim still
            // reports the raw note value excluded from delegation.
            dropped_count: 0,
            privacy_trim: plan.privacy_trim,
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

    /// Raw stored policy JSON, for assertions that care about the bytes on disk
    /// rather than the decoded policy.
    fn stored_policy_json(db: &VotingDb) -> String {
        db.conn()
            .query_row(
                "SELECT bundle_policy_json FROM rounds WHERE round_id = ?1",
                rusqlite::params![ROUND_ID],
                |row| row.get::<_, String>(0),
            )
            .unwrap()
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
    fn round_aware_helpers_reuse_custom_real_note_capacity() {
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
        let bundles = note_bundles_for_round(&notes, &db, ROUND_ID).unwrap();

        assert_eq!(layout.bundle_count, 3);
        assert_eq!(
            layout.eligible_weight,
            3 * crate::governance::BALLOT_DIVISOR
        );
        assert!(bundles.iter().all(|bundle| bundle.len() == 1));
        assert_eq!(
            bundle_notes_for_index_for_round(&notes, &layout, 2, &db, ROUND_ID,)
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
        let bundle = bundle_notes_for_index_for_round(&notes, &layout, 0, &db, ROUND_ID).unwrap();

        assert_eq!(layout.bundle_count, 1);
        assert_eq!(layout.eligible_weight, crate::governance::BALLOT_DIVISOR);
        assert_eq!(bundle, vec![base_note]);
    }

    #[test]
    fn ensure_bundles_reuses_the_policy_a_round_was_planned_with() {
        // A round's persisted rows must keep re-deriving for the life of the
        // round. Once a plan is stored its policy wins, so a later caller
        // passing a different policy cannot reinterpret rows that may already
        // be signed or submitted.
        let db = test_db("wallet-policy-change");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR),
            note(1, crate::governance::BALLOT_DIVISOR),
            note(2, crate::governance::BALLOT_DIVISOR),
            note(3, crate::governance::BALLOT_DIVISOR),
            note(4, crate::governance::BALLOT_DIVISOR),
            note(5, crate::governance::BALLOT_DIVISOR),
        ];
        let planned = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, BundlePolicy::new(1).unwrap())
            .unwrap();
        assert_eq!(planned.bundle_count, 6);

        let revalidated = db.ensure_bundles(ROUND_ID, &notes).unwrap();

        assert_eq!(revalidated.bundle_count, 6);
        assert_eq!(revalidated.eligible_weight, planned.eligible_weight);
    }

    #[test]
    fn ensure_bundles_rejects_existing_rows_when_the_note_set_changes_shape() {
        // Without a stored policy to fall back on, a note set that plans to a
        // different bundle count must still be refused rather than silently
        // reinterpreting persisted rows.
        let db = test_db("wallet-shape-change");
        let policy = BundlePolicy::new(1).unwrap();
        let notes: Vec<NoteInfo> = (0..6)
            .map(|i| note(i, crate::governance::BALLOT_DIVISOR))
            .collect();
        db.ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();

        let err = db
            .ensure_bundles_with_policy(ROUND_ID, &notes[..3], policy)
            .expect_err("a shorter note set must not reuse six persisted rows");

        assert!(
            err.to_string()
                .contains("existing bundle count 6 does not match planned bundle count 3"),
            "{err}"
        );
    }

    #[test]
    fn ensure_bundles_falls_back_to_the_caller_policy_for_rounds_without_a_stored_one() {
        // Rounds planned before the policy was recorded have a NULL column.
        // Those must keep re-deriving with whatever policy the caller supplies,
        // rather than silently switching to the current default.
        let db = test_db("wallet-legacy-policy");
        let policy = BundlePolicy::new(1).unwrap();
        let notes: Vec<NoteInfo> = (0..6)
            .map(|i| note(i, crate::governance::BALLOT_DIVISOR))
            .collect();
        db.ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();
        db.conn()
            .execute(
                "UPDATE rounds SET bundle_policy_json = NULL WHERE round_id = ?1",
                rusqlite::params![ROUND_ID],
            )
            .unwrap();

        let revalidated = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();

        assert_eq!(revalidated.bundle_count, 6);
        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            Some(policy.with_max_privacy_bundles(None))
        );
        assert_eq!(
            note_bundles_for_round(&notes, &db, ROUND_ID).unwrap().len(),
            6
        );
    }

    #[test]
    fn ensure_bundles_disables_the_privacy_trim_for_rounds_migrated_from_launch() {
        // The v13 -> v14 in-place migration preserves bundle rows but leaves
        // `bundle_policy_json` NULL. Those rows were planned before the trim
        // existed, so re-deriving them under the current default would plan a
        // smaller bundle count and reject the round for the rest of its life --
        // stranding every bundle the voter had not yet submitted.
        let db = test_db("wallet-migrated-launch-round");
        let pre_trim = BundlePolicy::default().with_max_privacy_bundles(None);
        // Value concentrated in three notes plus a dust tail: the shape the
        // trim collapses, and the shape a migrated round can already hold.
        let big = 1_000 * crate::governance::BALLOT_DIVISOR;
        let mut notes: Vec<NoteInfo> = (0..3).map(|i| note(i, big)).collect();
        notes.extend((3..23).map(|i| note(i, big / 500)));
        let planned = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, pre_trim)
            .unwrap();
        assert_eq!(planned.bundle_count, 5);
        db.conn()
            .execute(
                "UPDATE rounds SET bundle_policy_json = NULL WHERE round_id = ?1",
                rusqlite::params![ROUND_ID],
            )
            .unwrap();

        // The upgraded SDK passes its new default, which trims to two bundles.
        assert_eq!(
            crate::note_bundling::chunk_notes_with_policy(&notes, BundlePolicy::default())
                .bundles
                .len(),
            2
        );
        let resumed = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, BundlePolicy::default())
            .unwrap();
        let resumed_bundles = note_bundles_for_round(&notes, &db, ROUND_ID).unwrap();

        assert_eq!(resumed.bundle_count, 5);
        assert!(resumed.privacy_trim.is_empty());
        assert_eq!(resumed_bundles.len(), 5);
        for (bundle_index, expected_notes) in resumed_bundles.iter().enumerate() {
            assert_eq!(
                bundle_notes_for_index_for_round(
                    &notes,
                    &resumed,
                    bundle_index as u32,
                    &db,
                    ROUND_ID,
                )
                .unwrap(),
                expected_notes.clone()
            );
        }
    }

    #[test]
    fn ensure_bundles_with_skipped_suffix_disables_the_trim_for_migrated_rounds() {
        // The delegation path reaches storage through the skipped-suffix
        // variant, which rejects a plan shorter than the persisted rows.
        let db = test_db("wallet-migrated-suffix-round");
        let pre_trim = BundlePolicy::default().with_max_privacy_bundles(None);
        let big = 1_000 * crate::governance::BALLOT_DIVISOR;
        let mut notes: Vec<NoteInfo> = (0..3).map(|i| note(i, big)).collect();
        notes.extend((3..23).map(|i| note(i, big / 500)));
        db.ensure_bundles_with_policy(ROUND_ID, &notes, pre_trim)
            .unwrap();
        db.conn()
            .execute(
                "UPDATE rounds SET bundle_policy_json = NULL WHERE round_id = ?1",
                rusqlite::params![ROUND_ID],
            )
            .unwrap();

        let resumed = db
            .ensure_bundles_with_skipped_suffix_with_policy(
                ROUND_ID,
                &notes,
                BundlePolicy::default(),
            )
            .unwrap();

        assert_eq!(resumed.bundle_count, 5);
    }

    #[test]
    fn ensure_bundles_disables_the_privacy_trim_for_unreadable_future_policy_schema() {
        // A future SDK may persist a higher schema version. Downgrading must
        // not map that to Internal and brick the round; treat it like NULL so
        // existing rows and van_comm_rand stay usable without clear_round.
        // Once a policy validates against those rows it replaces the
        // unreadable value, so the round does not stay undecodable forever.
        let db = test_db("wallet-future-policy-schema");
        let pre_trim = BundlePolicy::default().with_max_privacy_bundles(None);
        let future_policy_json = r#"{"version":2,"policy":{"max_real_notes_per_bundle":2}}"#;
        let big = 1_000 * crate::governance::BALLOT_DIVISOR;
        let mut notes: Vec<NoteInfo> = (0..3).map(|i| note(i, big)).collect();
        notes.extend((3..23).map(|i| note(i, big / 500)));
        let planned = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, pre_trim)
            .unwrap();
        assert_eq!(planned.bundle_count, 5);
        db.conn()
            .execute(
                "UPDATE rounds SET bundle_policy_json = ?1 WHERE round_id = ?2",
                rusqlite::params![future_policy_json, ROUND_ID],
            )
            .unwrap();

        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            None
        );
        assert_eq!(
            db.effective_bundle_policy(ROUND_ID, BundlePolicy::default())
                .unwrap(),
            BundlePolicy::default().with_max_privacy_bundles(None)
        );

        let resumed = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, BundlePolicy::default())
            .unwrap();
        assert_eq!(resumed.bundle_count, 5);
        assert!(resumed.privacy_trim.is_empty());
        // The fallback proved it reproduces the persisted rows, so it replaces
        // the value this binary cannot read.
        assert_ne!(stored_policy_json(&db), future_policy_json);
        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            Some(BundlePolicy::default().with_max_privacy_bundles(None))
        );
    }

    #[test]
    fn ensure_bundles_replaces_unreadable_policy_when_planning_new_rows() {
        // Unreadable JSON on a round with no bundle rows describes nothing. If
        // planning inserted rows but left the value in place, the next call
        // would see "rows exist, no readable policy", disable the trim, and
        // plan a larger count than storage holds -- rejecting the round for
        // good. The note set here is trim-sensitive so that regression bites.
        let db = test_db("wallet-future-policy-without-bundles");
        let future_policy_json = r#"{"version":2,"policy":{"max_real_notes_per_bundle":2}}"#;
        db.conn()
            .execute(
                "UPDATE rounds SET bundle_policy_json = ?1 WHERE round_id = ?2",
                rusqlite::params![future_policy_json, ROUND_ID],
            )
            .unwrap();
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);

        let big = 1_000 * crate::governance::BALLOT_DIVISOR;
        let mut notes: Vec<NoteInfo> = (0..3).map(|i| note(i, big)).collect();
        notes.extend((3..23).map(|i| note(i, big / 500)));

        let planned = db.ensure_bundles(ROUND_ID, &notes).unwrap();

        assert_eq!(planned.bundle_count, 2);
        assert!(!planned.privacy_trim.is_empty());
        assert_ne!(stored_policy_json(&db), future_policy_json);
        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            Some(BundlePolicy::default())
        );

        // The round keeps re-deriving; without the replacement this call plans
        // 5 bundles against 2 persisted rows and fails permanently.
        let resumed = db.ensure_bundles(ROUND_ID, &notes).unwrap();
        assert_eq!(resumed.bundle_count, 2);
    }

    #[test]
    fn ensure_bundles_does_not_store_a_policy_for_an_empty_plan() {
        // Every bundle is sub-ballot, so nothing is persisted. Storing the
        // policy anyway would make it authoritative for a round with no rows,
        // and a retry under a corrected policy could never take effect.
        let db = test_db("wallet-empty-plan-policy");
        let notes: Vec<NoteInfo> = (0..10)
            .map(|i| note(i, crate::governance::BALLOT_DIVISOR / 2))
            .collect();
        let too_narrow = BundlePolicy::new(1).unwrap();

        let empty = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, too_narrow)
            .unwrap();

        assert_eq!(empty.bundle_count, 0);
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);
        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            None
        );

        // The corrected policy is honored because nothing was frozen.
        let retried = db.ensure_bundles(ROUND_ID, &notes).unwrap();

        assert_eq!(retried.bundle_count, 2);
        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            Some(BundlePolicy::default())
        );
    }

    #[test]
    fn bundle_policy_is_stored_exactly_when_bundle_rows_exist() {
        // The invariant both P2 fixes rest on: the column is non-NULL if and
        // only if the round has bundle rows for it to describe.
        let db = test_db("wallet-policy-row-invariant");
        let policy = BundlePolicy::new(1).unwrap();
        let stored = |db: &VotingDb| {
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap()
        };

        // No rows yet.
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);
        assert_eq!(stored(&db), None);

        // A plan that survives no bundles inserts nothing, so it records
        // nothing either.
        let sub_ballot: Vec<NoteInfo> = (0..10)
            .map(|i| note(i, crate::governance::BALLOT_DIVISOR / 2))
            .collect();
        assert_eq!(
            db.ensure_bundles_with_policy(ROUND_ID, &sub_ballot, policy)
                .unwrap()
                .bundle_count,
            0
        );
        assert_eq!(stored(&db), None);

        // Rows created -> policy recorded.
        let notes: Vec<NoteInfo> = (0..6)
            .map(|i| note(i, crate::governance::BALLOT_DIVISOR))
            .collect();
        assert_eq!(
            db.ensure_bundles_with_policy(ROUND_ID, &notes, policy)
                .unwrap()
                .bundle_count,
            6
        );
        assert_eq!(stored(&db), Some(policy));

        // Some rows remain -> policy still describes them.
        db.delete_skipped_bundles(ROUND_ID, 2).unwrap();
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 2);
        assert_eq!(stored(&db), Some(policy));

        // Last row gone -> policy goes with it.
        db.delete_skipped_bundles(ROUND_ID, 0).unwrap();
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);
        assert_eq!(stored(&db), None);
    }

    #[test]
    fn ensure_bundles_still_trims_a_round_with_no_persisted_rows() {
        // The override is scoped to rounds that already have bundle rows. A
        // round planned for the first time after the upgrade must still trim.
        let db = test_db("wallet-fresh-round-trims");
        let big = 1_000 * crate::governance::BALLOT_DIVISOR;
        let mut notes: Vec<NoteInfo> = (0..3).map(|i| note(i, big)).collect();
        notes.extend((3..23).map(|i| note(i, big / 500)));

        let planned = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, BundlePolicy::default())
            .unwrap();

        assert_eq!(planned.bundle_count, 2);
        assert!(!planned.privacy_trim.is_empty());
    }

    #[test]
    fn ensure_bundles_persists_the_privacy_trim_report() {
        let db = test_db("wallet-privacy-trim");
        // Two full-weight notes plus a dust tail that fits inside the 1% budget.
        let big = 1_000 * crate::governance::BALLOT_DIVISOR;
        let mut notes = vec![note(0, big), note(1, big)];
        notes.push(note(2, 2 * big / 99));
        let policy = BundlePolicy::new(1).unwrap();

        let layout = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();

        assert_eq!(layout.bundle_count, 2);
        assert_eq!(layout.privacy_trim.dropped_bundles, 1);
        assert_eq!(layout.privacy_trim.dropped_notes, 1);
        assert!(layout.privacy_trim.dropped_value > 0);
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
    fn delete_skipped_bundles_clears_policy_when_no_rows_remain() {
        // keep_count == 0 removes every bundle row but leaves the rounds row.
        // The stored policy must go with them so a later replan uses the caller.
        let db = test_db("wallet-clear-policy-on-full-skip");
        let notes = vec![
            note(0, crate::governance::BALLOT_DIVISOR),
            note(1, crate::governance::BALLOT_DIVISOR),
        ];
        let policy = BundlePolicy::new(1).unwrap();
        db.ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();
        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            Some(policy)
        );

        db.delete_skipped_bundles(ROUND_ID, 0).unwrap();

        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);
        assert_eq!(
            queries::get_round_bundle_policy(&db.conn(), ROUND_ID, &db.wallet_id()).unwrap(),
            None
        );
        assert_eq!(
            db.effective_bundle_policy(ROUND_ID, BundlePolicy::default())
                .unwrap(),
            BundlePolicy::default()
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
