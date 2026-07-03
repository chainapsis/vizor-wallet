use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;
use std::time::{SystemTime, UNIX_EPOCH};

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use diceware_wordlists::Wordlist;
use pczt::roles::low_level_signer::Signer as LowLevelSigner;
use rand::rngs::OsRng;
use rand::RngCore;
use reddsa::frost::redpallas::{
    keys::{dkg as frost_dkg, KeyPackage},
    rerandomized::Randomizer,
    round1::{SigningCommitments, SigningNonces},
    round2::SignatureShare,
    Identifier,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zcash_multisig::{
    address::group_address_ua,
    dkg::{dkg_part1, dkg_part2, dkg_part3, parse_dkg_round1, parse_dkg_round2, DkgRound2Msg},
    injector::inject_orchard_signature,
    keys::{build_group_public_package, GroupPublicPackage},
    signer::{
        aggregate, extract_alpha, make_signing_package, parse_round1_msg, parse_round2_msg,
        public_key_package_from_group_package, round1_commit, round1_msg, round2_msg, round2_sign,
        shielded_sighash, RoundMsg,
    },
    types::ThresholdParams,
};
use zcash_multisig_sdk::{
    backup::{
        decrypt_share_backup, encrypt_share_backup, EncryptedShareBackup, ShareBackupPlaintext,
    },
    client::{ClientError, Coordinator2Client},
    e2e::{
        encrypt_for, generate_invite_secret, open_session_label, seal_session_label,
        vault_delivery_keypair, DeliveryKeypair, E2eContext,
    },
    identity::AdmissionKey,
    types::{
        AdmissionAction, AdmissionChallengeReq, AuthRefreshReq, AuthSessionResp, AuthTokenResp,
        CreateSigningRequestReq, EncryptedMessageReq, JoinSessionReq, LockSessionReq, MessageResp,
        ParticipantResp, SessionResp, SigningRequestResp,
    },
};

use crate::wallet::keys as wallet_keys;

pub struct ApiMultisigBackupPassword {
    pub display_password: String,
    pub canonical_password: String,
    pub checksum: String,
}

pub struct ApiMultisigThresholdParams {
    pub threshold: u16,
    pub participant_count: u16,
}

#[derive(Clone)]
pub struct ApiMultisigParticipantIdentity {
    pub admission_secret_key: String,
    pub admission_public_key: String,
    pub delivery_secret_key: String,
    pub delivery_public_key: String,
}

pub struct ApiMultisigParticipant {
    pub participant_id: String,
    pub label: Option<String>,
    pub admission_public_key: String,
    pub delivery_public_key: String,
    pub joined_at: u64,
    pub dkg_completed: bool,
}

pub struct ApiMultisigAuthSession {
    pub session_id: String,
    pub participant_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub admission_secret_key: String,
    pub admission_public_key: String,
    pub delivery_secret_key: String,
    pub delivery_public_key: String,
    pub access_token_expires_at: u64,
    pub refresh_token_expires_at: u64,
    pub state: String,
    pub participant: ApiMultisigParticipant,
}

pub struct ApiMultisigTokens {
    pub session_id: String,
    pub participant_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub access_token_expires_at: u64,
    pub refresh_token_expires_at: u64,
}

pub struct ApiMultisigAuthUpdate {
    pub session_id: String,
    pub participant_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub admission_public_key: String,
    pub delivery_secret_key: String,
    pub delivery_public_key: String,
    pub access_token_expires_at: u64,
    pub refresh_token_expires_at: u64,
    pub resumed: bool,
}

pub struct ApiMultisigSession {
    pub session_id: String,
    pub state: String,
    pub creator_participant_id: String,
    pub threshold: Option<u16>,
    pub roster_hash: Option<String>,
    pub group_public_package_hash: Option<String>,
    pub participants: Vec<ApiMultisigParticipant>,
    pub created_at: u64,
    pub updated_at: u64,
}

pub struct ApiMultisigCreateAdvance {
    pub session: ApiMultisigSession,
    pub local_state_json: String,
    pub phase: String,
    pub detail: String,
    pub waiting_for_participant_ids: Vec<String>,
    pub round1_count: u32,
    pub round2_count: u32,
    pub dkg_complete_submitted: bool,
    pub key_package_b64: Option<String>,
    pub group_public_package_json: Option<String>,
    pub group_public_package_hash: Option<String>,
}

pub struct ApiMultisigSessionEvents {
    pub cursor: i64,
    pub events: Vec<ApiMultisigSessionEvent>,
}

pub struct ApiMultisigSessionEvent {
    pub cursor: i64,
    pub session_id: String,
    pub kind: String,
    pub actor_participant_id: Option<String>,
    pub payload_json: String,
    pub created_at: u64,
}

pub struct ApiMultisigSigningRequest {
    pub signing_request_id: String,
    pub session_id: String,
    pub requester_participant_id: String,
    pub selected_participant_ids: Vec<String>,
    /// Coordinator-derived progress: selected signers whose Round 1 / Round 2
    /// envelopes were relayed, and participants that posted a broadcast
    /// result. Derived from message metadata server-side.
    pub round1_participant_ids: Vec<String>,
    pub round2_participant_ids: Vec<String>,
    pub broadcast_participant_ids: Vec<String>,
    pub state: String,
    pub created_at: u64,
    pub updated_at: u64,
    pub pczt_hash: String,
}

pub struct ApiMultisigSigningInbox {
    pub cursor: i64,
    pub messages: Vec<ApiMultisigSigningMessage>,
}

pub struct ApiMultisigSigningMessage {
    pub cursor: i64,
    pub message_id: String,
    pub session_id: String,
    pub kind: String,
    pub from_participant_id: String,
    pub to_participant_id: Option<String>,
    pub related_id: Option<String>,
    pub plaintext_json: Option<String>,
    pub decrypt_error: Option<String>,
    pub created_at: u64,
}

pub struct ApiMultisigSigningAdvance {
    pub local_state_json: String,
    pub detail: String,
    pub submitted: bool,
}

pub struct ApiMultisigSignedPczt {
    pub local_state_json: String,
    pub signed_pczt_bytes: Vec<u8>,
}

pub struct ApiPreparedMultisigSigningRequest {
    pub signing_request_id: String,
    pub session_id: String,
    pub requester_participant_id: String,
    pub selected_participant_ids: Vec<String>,
    pub request_json: String,
    pub idempotency_key: String,
    pub pczt_hash: String,
    pub created_at: u64,
}

pub struct ApiMultisigBackupArtifact {
    pub artifact_json: String,
    pub backup_hash: String,
    pub vault_address: String,
}

pub struct ApiMultisigBackupVerification {
    pub backup_hash: String,
    pub vault_address: String,
    pub session_id: String,
    pub participant_id: String,
    pub threshold: u16,
    pub participant_count: u16,
    pub roster_hash: String,
    pub admission_secret_key: String,
    pub admission_public_key: String,
    pub delivery_secret_key: String,
    pub delivery_public_key: String,
    pub key_package_b64: String,
    pub group_public_package_json: String,
    pub group_public_package_hash: String,
}

const MULTISIG_ERROR_MARKER: &str = "zcash_wallet_multisig_error_v1";

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum ApiMultisigErrorKind {
    Unauthorized,
    Forbidden,
    Conflict,
    RateLimited,
    Network,
    Server,
    LocalInvalidState,
    Unsupported,
    Unknown,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ApiMultisigErrorBody {
    marker: &'static str,
    kind: ApiMultisigErrorKind,
    message: String,
    http_status: Option<u16>,
    retry_after_seconds: Option<u64>,
    retryable: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct TxRequestBody {
    version: u8,
    kind: String,
    signing_request_id: String,
    session_id: String,
    requester_participant_id: String,
    selected_participant_ids: Vec<String>,
    pczt_b64: String,
    pczt_hash: String,
    needs_sapling_params: bool,
    amount_zatoshi: String,
    fee_zatoshi: String,
    recipient_address: String,
    memo: Option<String>,
    created_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TxRound1Body {
    version: u8,
    signing_request_id: String,
    pczt_hash: String,
    participant_id: String,
    actions: Vec<TxRoundActionMsg>,
    created_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TxRound2Body {
    version: u8,
    signing_request_id: String,
    pczt_hash: String,
    participant_id: String,
    actions: Vec<TxRoundActionMsg>,
    created_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TxRoundActionMsg {
    action_idx: usize,
    msg: RoundMsg,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LocalSigningState {
    version: u8,
    signing_request_id: String,
    pczt_hash: String,
    #[serde(default)]
    action_indices: Vec<usize>,
    #[serde(default)]
    nonce_b64_by_action: BTreeMap<usize, String>,
    #[serde(default)]
    round1_body_json_b64: Option<String>,
    #[serde(default)]
    round1_sent_to: BTreeSet<String>,
    #[serde(default)]
    round1_sent: bool,
    #[serde(default)]
    round2_body_json_b64: Option<String>,
    #[serde(default)]
    round2_sent_to: BTreeSet<String>,
    #[serde(default)]
    round2_sent: bool,
    #[serde(default)]
    broadcast_result_body_json_b64: Option<String>,
    #[serde(default)]
    broadcast_result_sent_to: BTreeSet<String>,
    #[serde(default)]
    outbound_messages: BTreeMap<String, EncryptedMessageReq>,
    #[serde(default)]
    signed_pczt_b64: Option<String>,
}

impl LocalSigningState {
    fn new(signing_request_id: String, pczt_hash: String) -> Self {
        Self {
            version: 1,
            signing_request_id,
            pczt_hash,
            action_indices: Vec::new(),
            nonce_b64_by_action: BTreeMap::new(),
            round1_body_json_b64: None,
            round1_sent_to: BTreeSet::new(),
            round1_sent: false,
            round2_body_json_b64: None,
            round2_sent_to: BTreeSet::new(),
            round2_sent: false,
            broadcast_result_body_json_b64: None,
            broadcast_result_sent_to: BTreeSet::new(),
            outbound_messages: BTreeMap::new(),
            signed_pczt_b64: None,
        }
    }

    fn sent_to_contains(&self, kind: &str, participant_id: &str) -> bool {
        match kind {
            "tx_round1" => self.round1_sent_to.contains(participant_id),
            "tx_round2" => self.round2_sent_to.contains(participant_id),
            "broadcast_result" => self.broadcast_result_sent_to.contains(participant_id),
            _ => false,
        }
    }

    fn mark_sent_to(&mut self, kind: &str, participant_id: String) {
        match kind {
            "tx_round1" => {
                self.round1_sent_to.insert(participant_id);
            }
            "tx_round2" => {
                self.round2_sent_to.insert(participant_id);
            }
            "broadcast_result" => {
                self.broadcast_result_sent_to.insert(participant_id);
            }
            _ => {}
        }
    }

    fn all_sent_to(&self, kind: &str, recipients: &[ParticipantResp]) -> bool {
        recipients
            .iter()
            .all(|recipient| self.sent_to_contains(kind, &recipient.participant_id))
    }
}

struct SigningInboxMessages {
    round1: BTreeMap<String, TxRound1Body>,
    round2: BTreeMap<String, TxRound2Body>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LocalCreateState {
    version: u8,
    session_id: String,
    participant_id: String,
    #[serde(default)]
    roster_hash: Option<String>,
    #[serde(default)]
    threshold: Option<u16>,
    #[serde(default)]
    inbox_cursor: i64,
    #[serde(default)]
    roster: Vec<LocalRosterParticipant>,
    #[serde(default)]
    broadcast_seed_b64: Option<String>,
    #[serde(default)]
    seed_sent_to: BTreeSet<String>,
    #[serde(default)]
    round1_secret_b64: Option<String>,
    #[serde(default)]
    round1_messages: BTreeMap<String, RoundMsg>,
    #[serde(default)]
    round1_sent_to: BTreeSet<String>,
    #[serde(default)]
    round2_secret_b64: Option<String>,
    #[serde(default)]
    outbound_round2: BTreeMap<String, DkgRound2Msg>,
    #[serde(default)]
    round2_sent_to: BTreeSet<String>,
    #[serde(default)]
    round2_messages: BTreeMap<String, DkgRound2Msg>,
    #[serde(default)]
    outbound_messages: BTreeMap<String, EncryptedMessageReq>,
    #[serde(default)]
    key_package_b64: Option<String>,
    #[serde(default)]
    group_public_package_json: Option<String>,
    #[serde(default)]
    group_public_package_hash: Option<String>,
    #[serde(default)]
    dkg_complete_submitted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LocalRosterParticipant {
    participant_id: String,
    delivery_public_key: String,
    dkg_identifier_hex: String,
}

impl LocalCreateState {
    fn new(session_id: String, participant_id: String) -> Self {
        Self {
            version: 1,
            session_id,
            participant_id,
            roster_hash: None,
            threshold: None,
            inbox_cursor: 0,
            roster: Vec::new(),
            broadcast_seed_b64: None,
            seed_sent_to: BTreeSet::new(),
            round1_secret_b64: None,
            round1_messages: BTreeMap::new(),
            round1_sent_to: BTreeSet::new(),
            round2_secret_b64: None,
            outbound_round2: BTreeMap::new(),
            round2_sent_to: BTreeSet::new(),
            round2_messages: BTreeMap::new(),
            outbound_messages: BTreeMap::new(),
            key_package_b64: None,
            group_public_package_json: None,
            group_public_package_hash: None,
            dkg_complete_submitted: false,
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn validate_multisig_threshold(
    threshold: u16,
    participant_count: u16,
) -> Result<ApiMultisigThresholdParams, String> {
    ThresholdParams::new(threshold, participant_count)
        .map_err(|e| e.to_string())
        .map(|params| ApiMultisigThresholdParams {
            threshold: params.threshold,
            participant_count: params.n,
        })
}

/// Random 32-byte session invite secret (base64url). Shared out-of-band as
/// part of the invite code; never sent to the coordinator. Participant
/// labels are sealed under it so the server only relays opaque strings.
#[flutter_rust_bridge::frb(sync)]
pub fn generate_multisig_invite_secret() -> String {
    generate_invite_secret()
}

#[flutter_rust_bridge::frb(sync)]
pub fn generate_multisig_participant_identity() -> ApiMultisigParticipantIdentity {
    multisig_identity_from_keys(AdmissionKey::generate(), DeliveryKeypair::generate())
}

#[flutter_rust_bridge::frb(sync)]
pub fn restore_multisig_participant_identity(
    admission_secret_key: String,
    delivery_secret_key: String,
) -> Result<ApiMultisigParticipantIdentity, String> {
    let admission = AdmissionKey::from_secret_b64(&admission_secret_key)
        .map_err(|err| format!("Invalid admission secret key: {err}"))?;
    let delivery = DeliveryKeypair::from_secret_b64(&delivery_secret_key)
        .map_err(|err| format!("Invalid delivery secret key: {err}"))?;
    Ok(multisig_identity_from_keys(admission, delivery))
}

#[flutter_rust_bridge::frb(sync)]
pub fn generate_multisig_backup_password() -> ApiMultisigBackupPassword {
    let words = Wordlist::EffLong.get_list();
    let selected = (0..8)
        .map(|_| words[random_word_index(words.len())])
        .collect::<Vec<_>>();
    let canonical_password = selected.join(" ");
    let display_password = selected.join("-");
    let checksum = hex::encode_upper(Sha256::digest(canonical_password.as_bytes()))
        .chars()
        .take(5)
        .collect();
    ApiMultisigBackupPassword {
        display_password,
        canonical_password,
        checksum,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn normalize_multisig_backup_password(
    password: String,
    generated: bool,
) -> Result<String, String> {
    normalize_backup_passphrase(&password, generated)
}

pub fn create_multisig_share_backup(
    network: String,
    session_id: String,
    participant_id: String,
    threshold: u16,
    participant_count: u16,
    roster_hash: String,
    admission_secret_key: String,
    delivery_secret_key: String,
    key_package_b64: String,
    group_public_package_json: String,
    passphrase: String,
) -> Result<ApiMultisigBackupArtifact, String> {
    validate_multisig_threshold(threshold, participant_count)?;
    let identity =
        restore_multisig_participant_identity(admission_secret_key, delivery_secret_key)?;
    let vault_address =
        vault_address_from_group_public_package(&network, &group_public_package_json)?;
    let plaintext = ShareBackupPlaintext {
        version: 2,
        session_id,
        participant_id,
        threshold,
        participant_count,
        roster_hash,
        admission_secret_key: identity.admission_secret_key,
        delivery_secret_key: identity.delivery_secret_key,
        key_package: decode_b64(&key_package_b64, "multisig key package")?,
        group_public_package: group_public_package_json.into_bytes(),
        vault_address: Some(vault_address.clone()),
    };
    let encrypted = encrypt_share_backup(&plaintext, &passphrase)
        .map_err(|e| format!("Failed to encrypt multisig backup: {e}"))?;
    let artifact_json = serde_json::to_string_pretty(&encrypted)
        .map_err(|e| format!("Failed to encode multisig backup: {e}"))?;
    Ok(ApiMultisigBackupArtifact {
        artifact_json,
        backup_hash: encrypted.backup_hash,
        vault_address,
    })
}

pub fn verify_multisig_share_backup(
    network: String,
    artifact_json: String,
    passphrase: String,
    expected_session_id: String,
    expected_participant_id: String,
    expected_threshold: u16,
    expected_participant_count: u16,
    expected_roster_hash: String,
    expected_group_public_package_hash: String,
) -> Result<ApiMultisigBackupVerification, String> {
    let encrypted: EncryptedShareBackup = serde_json::from_str(&artifact_json)
        .map_err(|e| format!("Failed to parse multisig backup file: {e}"))?;
    let ciphertext = decode_b64(&encrypted.ciphertext, "multisig backup ciphertext")?;
    let computed_hash = hash_bytes_b64(&ciphertext);
    if computed_hash != encrypted.backup_hash {
        return Err("Multisig backup file hash does not match its ciphertext.".to_string());
    }

    let plaintext = decrypt_share_backup(&encrypted, &passphrase)
        .map_err(|_| "Backup password did not decrypt this multisig backup.".to_string())?;
    if plaintext.session_id != expected_session_id {
        return Err("Backup belongs to a different multisig session.".to_string());
    }
    if plaintext.participant_id != expected_participant_id {
        return Err("Backup belongs to a different multisig participant.".to_string());
    }
    if plaintext.threshold != expected_threshold {
        return Err("Backup threshold does not match this session.".to_string());
    }
    if plaintext.participant_count != expected_participant_count {
        return Err("Backup participant count does not match this session.".to_string());
    }
    if plaintext.roster_hash != expected_roster_hash {
        return Err("Backup roster does not match this session.".to_string());
    }

    let identity = restore_multisig_participant_identity(
        plaintext.admission_secret_key.clone(),
        plaintext.delivery_secret_key.clone(),
    )?;
    let group_public_package_json = String::from_utf8(plaintext.group_public_package)
        .map_err(|_| "Backup group package is not valid UTF-8.".to_string())?;
    let group: GroupPublicPackage = serde_json::from_str(&group_public_package_json)
        .map_err(|e| format!("Backup group package is invalid: {e}"))?;
    let group_public_package_hash = hash_group_public_package(&group)?;
    if group_public_package_hash != expected_group_public_package_hash {
        return Err("Backup group package does not match this session.".to_string());
    }

    let derived_address =
        vault_address_from_group_public_package(&network, &group_public_package_json)?;
    let backup_address = plaintext
        .vault_address
        .ok_or_else(|| "Backup is missing the multisig vault address.".to_string())?;
    if backup_address != derived_address {
        return Err("Backup vault address does not match the group package.".to_string());
    }

    Ok(ApiMultisigBackupVerification {
        backup_hash: encrypted.backup_hash,
        vault_address: derived_address,
        session_id: plaintext.session_id,
        participant_id: plaintext.participant_id,
        threshold: plaintext.threshold,
        participant_count: plaintext.participant_count,
        roster_hash: plaintext.roster_hash,
        admission_secret_key: identity.admission_secret_key,
        admission_public_key: identity.admission_public_key,
        delivery_secret_key: identity.delivery_secret_key,
        delivery_public_key: identity.delivery_public_key,
        key_package_b64: URL_SAFE_NO_PAD.encode(plaintext.key_package),
        group_public_package_json,
        group_public_package_hash,
    })
}

pub fn create_multisig_session(
    coordinator_url: String,
    admission_secret_key: String,
    delivery_secret_key: String,
    invite_secret: String,
    label: Option<String>,
) -> Result<ApiMultisigAuthSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let challenge = client
            .create_admission_challenge(&AdmissionChallengeReq::CreateSession)
            .await
            .map_err(client_error)?;
        let (admission, delivery, identity) =
            restore_participant_identity(admission_secret_key, delivery_secret_key)?;
        let encrypted_label =
            seal_label(&invite_secret, &identity.admission_public_key, label)?;
        let creator = admission.admission_request(
            AdmissionAction::CreateSession,
            &challenge,
            &delivery,
            encrypted_label,
        );
        let created = client
            .create_session(&zcash_multisig_sdk::types::CreateSessionReq { creator })
            .await
            .map_err(client_error)?;

        Ok(map_auth_session(created, identity, Some(&invite_secret)))
    })
}

pub fn join_multisig_session(
    coordinator_url: String,
    session_id: String,
    admission_secret_key: String,
    delivery_secret_key: String,
    invite_secret: String,
    label: Option<String>,
) -> Result<ApiMultisigAuthSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let challenge = client
            .create_admission_challenge(&AdmissionChallengeReq::JoinSession {
                session_id: session_id.clone(),
            })
            .await
            .map_err(client_error)?;
        let (admission, delivery, identity) =
            restore_participant_identity(admission_secret_key, delivery_secret_key)?;
        let encrypted_label =
            seal_label(&invite_secret, &identity.admission_public_key, label)?;
        let participant = admission.admission_request(
            AdmissionAction::JoinSession {
                session_id: &session_id,
            },
            &challenge,
            &delivery,
            encrypted_label,
        );
        let joined = client
            .join_session(&session_id, &JoinSessionReq { participant })
            .await
            .map_err(client_error)?;

        Ok(map_auth_session(joined, identity, Some(&invite_secret)))
    })
}

pub fn refresh_multisig_auth(
    coordinator_url: String,
    refresh_token: String,
) -> Result<ApiMultisigTokens, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let refreshed = client
            .refresh_auth(&AuthRefreshReq { refresh_token })
            .await
            .map_err(client_error)?;

        Ok(map_tokens(refreshed))
    })
}

pub fn refresh_or_resume_multisig_auth(
    coordinator_url: String,
    session_id: String,
    participant_id: String,
    refresh_token: String,
    admission_secret_key: String,
    delivery_secret_key: String,
) -> Result<ApiMultisigAuthUpdate, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let (admission, delivery, identity) =
            restore_participant_identity(admission_secret_key, delivery_secret_key)?;
        match client.refresh_auth(&AuthRefreshReq { refresh_token }).await {
            Ok(tokens) => {
                ensure_auth_owner(
                    &session_id,
                    &participant_id,
                    &tokens.session_id,
                    &tokens.participant_id,
                )?;
                Ok(map_auth_update_from_tokens(tokens, identity, false))
            }
            Err(err) if refresh_error_allows_resume(&err) => {
                let resumed = resume_participant_auth_session(
                    &client,
                    session_id.clone(),
                    &admission,
                    &delivery,
                )
                .await?;
                ensure_auth_owner(
                    &session_id,
                    &participant_id,
                    &resumed.session_id,
                    &resumed.participant_id,
                )?;
                Ok(map_auth_update_from_session(resumed, identity, true))
            }
            Err(err) => Err(client_error(err)),
        }
    })
}

pub fn resume_multisig_participant(
    coordinator_url: String,
    session_id: String,
    admission_secret_key: String,
    delivery_secret_key: String,
    invite_secret: Option<String>,
) -> Result<ApiMultisigAuthSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let (admission, delivery, identity) =
            restore_participant_identity(admission_secret_key, delivery_secret_key)?;
        let resumed =
            resume_participant_auth_session(&client, session_id, &admission, &delivery).await?;

        Ok(map_auth_session(resumed, identity, invite_secret.as_deref()))
    })
}

pub fn get_multisig_session(
    coordinator_url: String,
    session_id: String,
    access_token: String,
    invite_secret: Option<String>,
) -> Result<ApiMultisigSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let session = client
            .get_session(&session_id, &access_token)
            .await
            .map_err(client_error)?;

        Ok(map_session(session, invite_secret.as_deref()))
    })
}

pub fn lock_multisig_session(
    coordinator_url: String,
    session_id: String,
    access_token: String,
    threshold: u16,
    invite_secret: Option<String>,
) -> Result<ApiMultisigSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let session = client
            .lock_session(&session_id, &access_token, &LockSessionReq { threshold })
            .await
            .map_err(client_error)?;

        Ok(map_session(session, invite_secret.as_deref()))
    })
}

pub fn advance_multisig_create(
    coordinator_url: String,
    session_id: String,
    participant_id: String,
    access_token: String,
    admission_secret_key: String,
    delivery_secret_key: String,
    invite_secret: Option<String>,
    local_state_json: Option<String>,
) -> Result<ApiMultisigCreateAdvance, String> {
    block_on(async move {
        // Shadows the free function so every progress return below decrypts
        // participant labels with this call's invite secret.
        let create_progress = |session, state, detail, waiting| {
            create_progress_with(session, state, detail, waiting, invite_secret.as_deref())
        };
        let client = Coordinator2Client::new(coordinator_url);
        let mut session = client
            .get_session(&session_id, &access_token)
            .await
            .map_err(client_error)?;

        let mut state = parse_create_state(local_state_json, &session_id, &participant_id)?;
        if session.state.as_str() != "request_create" {
            return create_progress(
                session,
                state,
                session_state_phase("Session is not in create stage."),
                Vec::new(),
            );
        }

        sync_locked_roster(&mut state, &session)?;
        let roster_hash = state
            .roster_hash
            .clone()
            .ok_or_else(|| "Locked session is missing roster hash.".to_string())?;
        let threshold = state
            .threshold
            .ok_or_else(|| "Locked session is missing threshold.".to_string())?;
        let delivery = DeliveryKeypair::from_secret_b64(&delivery_secret_key)
            .map_err(|err| format!("Invalid delivery secret key: {err}"))?;
        let seed_issuer = seed_issuer_participant_id(&session)?;

        if let Some(progress) = poll_create_inbox(
            &client,
            &access_token,
            &mut state,
            &delivery,
            &roster_hash,
            &seed_issuer,
        )
        .await?
        {
            return create_progress(session, state, progress, Vec::new());
        }

        if state.broadcast_seed_b64.is_none() {
            if participant_id == seed_issuer {
                let mut seed = [0u8; 32];
                OsRng.fill_bytes(&mut seed);
                state.broadcast_seed_b64 = Some(URL_SAFE_NO_PAD.encode(seed));
            } else {
                return create_progress(
                    session,
                    state,
                    "Waiting for the shared DKG seed.".to_string(),
                    vec![seed_issuer],
                );
            }
        }

        if participant_id == seed_issuer {
            let seed = decode_b64_32(
                state
                    .broadcast_seed_b64
                    .as_deref()
                    .ok_or_else(|| "Missing broadcast seed.".to_string())?,
                "broadcast seed",
            )?;
            for recipient in state.roster.clone() {
                if recipient.participant_id == participant_id
                    || state.seed_sent_to.contains(&recipient.participant_id)
                {
                    continue;
                }
                if let Err(e) = post_create_message_with_outbox(
                    &mut state,
                    &client,
                    &access_token,
                    &roster_hash,
                    &participant_id,
                    &recipient,
                    "dkg_broadcast_seed",
                    &seed,
                )
                .await
                {
                    return create_progress(
                        session,
                        state,
                        format!("Network error while sending DKG seed: {e}"),
                        vec![recipient.participant_id],
                    );
                }
                state.seed_sent_to.insert(recipient.participant_id);
            }
        }

        ensure_dkg_round1(&mut state, &participant_id, threshold)?;
        for recipient in state.roster.clone() {
            if recipient.participant_id == participant_id
                || state.round1_sent_to.contains(&recipient.participant_id)
            {
                continue;
            }
            let own_round1 = state
                .round1_messages
                .get(&participant_id)
                .ok_or_else(|| "Missing local DKG round1 message.".to_string())?;
            let payload = serde_json::to_vec(own_round1).map_err(|e| e.to_string())?;
            if let Err(e) = post_create_message_with_outbox(
                &mut state,
                &client,
                &access_token,
                &roster_hash,
                &participant_id,
                &recipient,
                "dkg_round1",
                &payload,
            )
            .await
            {
                return create_progress(
                    session,
                    state,
                    format!("Network error while sending DKG round 1: {e}"),
                    vec![recipient.participant_id],
                );
            }
            state.round1_sent_to.insert(recipient.participant_id);
        }

        let missing_round1 = missing_round1_participants(&state);
        if !missing_round1.is_empty() {
            return create_progress(
                session,
                state,
                "Waiting for DKG round 1 messages.".to_string(),
                missing_round1,
            );
        }

        ensure_dkg_round2(&mut state)?;
        for recipient in state.roster.clone() {
            if recipient.participant_id == participant_id
                || state.round2_sent_to.contains(&recipient.participant_id)
            {
                continue;
            }
            let msg = state
                .outbound_round2
                .get(&recipient.participant_id)
                .ok_or_else(|| "Missing outbound DKG round 2 message.".to_string())?;
            let payload = serde_json::to_vec(msg).map_err(|e| e.to_string())?;
            if let Err(e) = post_create_message_with_outbox(
                &mut state,
                &client,
                &access_token,
                &roster_hash,
                &participant_id,
                &recipient,
                "dkg_round2",
                &payload,
            )
            .await
            {
                return create_progress(
                    session,
                    state,
                    format!("Network error while sending DKG round 2: {e}"),
                    vec![recipient.participant_id],
                );
            }
            state.round2_sent_to.insert(recipient.participant_id);
        }

        let missing_round2 = missing_round2_participants(&state, &participant_id);
        if !missing_round2.is_empty() {
            return create_progress(
                session,
                state,
                "Waiting for DKG round 2 messages.".to_string(),
                missing_round2,
            );
        }

        ensure_dkg_finalized(&mut state)?;
        if !state.dkg_complete_submitted {
            let admission = AdmissionKey::from_secret_b64(&admission_secret_key)
                .map_err(|err| format!("Invalid admission secret key: {err}"))?;
            let group_hash = state
                .group_public_package_hash
                .clone()
                .ok_or_else(|| "Missing group public package hash.".to_string())?;
            let req = admission.dkg_complete_request(
                &session_id,
                &participant_id,
                roster_hash,
                group_hash,
            );
            match client
                .mark_dkg_complete(&session_id, &access_token, &req)
                .await
            {
                Ok(updated) => {
                    session = updated;
                    state.dkg_complete_submitted = true;
                }
                Err(e) => {
                    return create_progress(
                        session,
                        state,
                        format!(
                            "Network error while submitting DKG completion: {}",
                            client_error(e)
                        ),
                        Vec::new(),
                    );
                }
            }
        }

        let waiting = session
            .participants
            .iter()
            .filter(|participant| !participant.dkg_completed)
            .map(|participant| participant.participant_id.clone())
            .collect();
        create_progress(
            session,
            state,
            "Your create step is complete.".to_string(),
            waiting,
        )
    })
}

pub fn prepare_multisig_signing_request(
    coordinator_url: String,
    session_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    request_seed: String,
    selected_participant_ids: Vec<String>,
    pczt_bytes: Vec<u8>,
    needs_sapling_params: bool,
    amount_zatoshi: String,
    fee_zatoshi: String,
    recipient_address: String,
    memo: Option<String>,
) -> Result<ApiPreparedMultisigSigningRequest, String> {
    block_on(async move {
        prepare_multisig_signing_request_inner(
            coordinator_url,
            session_id,
            participant_id,
            access_token,
            roster_hash,
            request_seed,
            selected_participant_ids,
            pczt_bytes,
            needs_sapling_params,
            amount_zatoshi,
            fee_zatoshi,
            recipient_address,
            memo,
        )
        .await
    })
}

pub fn submit_prepared_multisig_signing_request(
    coordinator_url: String,
    session_id: String,
    access_token: String,
    pczt_hash: String,
    request_json: String,
    idempotency_key: String,
) -> Result<ApiMultisigSigningRequest, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let req: CreateSigningRequestReq =
            serde_json::from_str(&request_json).map_err(|e| e.to_string())?;
        let signing = client
            .create_signing_request_with_idempotency(
                &session_id,
                &access_token,
                &idempotency_key,
                &req,
            )
            .await
            .map_err(client_error)?;

        Ok(map_signing_request(signing, pczt_hash))
    })
}

#[allow(clippy::too_many_arguments)]
async fn prepare_multisig_signing_request_inner(
    coordinator_url: String,
    session_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    request_seed: String,
    selected_participant_ids: Vec<String>,
    pczt_bytes: Vec<u8>,
    needs_sapling_params: bool,
    amount_zatoshi: String,
    fee_zatoshi: String,
    recipient_address: String,
    memo: Option<String>,
) -> Result<ApiPreparedMultisigSigningRequest, String> {
    let selected = normalize_selected_participants(selected_participant_ids)?;
    if !selected.iter().any(|value| value == &participant_id) {
        return Err("Requester must be included in selected signers.".to_string());
    }
    if pczt_bytes.is_empty() {
        return Err("PCZT is empty.".to_string());
    }

    let client = Coordinator2Client::new(coordinator_url);
    let session = client
        .get_session(&session_id, &access_token)
        .await
        .map_err(client_error)?;
    if session.state.as_str() != "ready" {
        return Err("Multisig session is not ready.".to_string());
    }

    let participants_by_id: BTreeMap<String, ParticipantResp> = session
        .participants
        .into_iter()
        .map(|participant| (participant.participant_id.clone(), participant))
        .collect();
    for selected_id in &selected {
        if !participants_by_id.contains_key(selected_id) {
            return Err(format!(
                "Selected signer is not in this session: {selected_id}"
            ));
        }
    }

    let signing_request_id =
        stable_id("sign", &[&session_id, &participant_id, request_seed.trim()]);
    let pczt_hash = hash_bytes_b64(&pczt_bytes);
    let created_at = unix_now_secs();
    let body = TxRequestBody {
        version: 1,
        kind: "tx_request".to_string(),
        signing_request_id: signing_request_id.clone(),
        session_id: session_id.clone(),
        requester_participant_id: participant_id.clone(),
        selected_participant_ids: selected.clone(),
        pczt_b64: URL_SAFE_NO_PAD.encode(&pczt_bytes),
        pczt_hash: pczt_hash.clone(),
        needs_sapling_params,
        amount_zatoshi,
        fee_zatoshi,
        recipient_address,
        memo: memo.filter(|value| !value.trim().is_empty()),
        created_at,
    };
    let body_json = serde_json::to_vec(&body).map_err(|e| e.to_string())?;

    let encrypted_bodies = participants_by_id
        .values()
        .map(|participant| {
            let ctx = E2eContext {
                session_id: &session_id,
                roster_hash: Some(&roster_hash),
                kind: "tx_request",
                from_participant_id: &participant_id,
                to_participant_id: Some(&participant.participant_id),
                related_id: Some(&signing_request_id),
            };
            encrypt_for(&participant.delivery_public_key, &ctx, &body_json)
                .map_err(|e| e.to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;

    let req = CreateSigningRequestReq {
        signing_request_id: signing_request_id.clone(),
        selected_participant_ids: selected.clone(),
        encrypted_bodies,
    };
    let request_json = serde_json::to_string(&req).map_err(|e| e.to_string())?;
    let idempotency_key = idempotency_key("signing-create", &[&signing_request_id]);

    Ok(ApiPreparedMultisigSigningRequest {
        signing_request_id,
        session_id,
        requester_participant_id: participant_id,
        selected_participant_ids: selected,
        request_json,
        idempotency_key,
        pczt_hash,
        created_at,
    })
}

/// Publishes the local participant's label for the finalized vault as a
/// broadcast message encrypted to the group-derived metadata keypair. The
/// coordinator relays ciphertext only. Safe to call repeatedly: the
/// idempotency key is stable and a same-key replay (or the 409 produced by
/// a re-encrypted retry) counts as already published.
pub fn post_multisig_vault_label(
    coordinator_url: String,
    session_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    group_public_package_json: String,
    label: String,
) -> Result<(), String> {
    block_on(async move {
        let label = label.trim();
        if label.is_empty() {
            return Err("Label is empty.".to_string());
        }
        let vault = vault_delivery_keypair(group_public_package_json.as_bytes())
            .map_err(|e| format!("Invalid group public package: {e}"))?;
        let ctx = E2eContext {
            session_id: &session_id,
            roster_hash: Some(&roster_hash),
            kind: "vault_label",
            from_participant_id: &participant_id,
            to_participant_id: None,
            related_id: None,
        };
        let body = serde_json::json!({ "version": 1, "label": label });
        let body_json = serde_json::to_vec(&body).map_err(|e| e.to_string())?;
        let envelope = encrypt_for(&vault.public_key_b64(), &ctx, &body_json)
            .map_err(|e| e.to_string())?;
        let key = idempotency_key("vault-label", &[&session_id, &participant_id]);
        let client = Coordinator2Client::new(coordinator_url);
        match client
            .post_message_with_idempotency(&session_id, &access_token, &key, &envelope)
            .await
        {
            Ok(_) => Ok(()),
            Err(err) => {
                let text = client_error(err);
                // A retry re-encrypts with a fresh nonce, so the stable key
                // conflicts with the stored request hash — the label is
                // already published.
                if text.contains("reused with a different request") {
                    Ok(())
                } else {
                    Err(text)
                }
            }
        }
    })
}

pub fn get_multisig_signing_request(
    coordinator_url: String,
    signing_request_id: String,
    access_token: String,
    pczt_hash: String,
) -> Result<ApiMultisigSigningRequest, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let signing = client
            .get_signing_request(&signing_request_id, &access_token)
            .await
            .map_err(client_error)?;
        Ok(map_signing_request(signing, pczt_hash))
    })
}

pub fn get_multisig_signing_inbox(
    coordinator_url: String,
    session_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    delivery_secret_key: String,
    group_public_package_json: Option<String>,
    after: i64,
) -> Result<ApiMultisigSigningInbox, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let delivery = DeliveryKeypair::from_secret_b64(&delivery_secret_key)
            .map_err(|e| format!("Invalid delivery secret key: {e}"))?;
        // Broadcast vault metadata (participant labels) is encrypted to the
        // keypair every member derives from the group public package.
        let vault = match group_public_package_json.as_deref() {
            Some(json) => Some(
                vault_delivery_keypair(json.as_bytes())
                    .map_err(|e| format!("Invalid group public package: {e}"))?,
            ),
            None => None,
        };
        let inbox = client
            .inbox(&session_id, &access_token, after)
            .await
            .map_err(client_error)?;
        let messages = inbox
            .messages
            .into_iter()
            .filter(|message| {
                matches!(
                    message.kind.as_str(),
                    "tx_request" | "tx_round1" | "tx_round2" | "broadcast_result"
                        | "vault_label"
                )
            })
            .map(|message| {
                let keypair = if message.kind == "vault_label" {
                    vault.as_ref()
                } else {
                    Some(&delivery)
                };
                let (plaintext_json, decrypt_error) = match keypair
                    .ok_or_else(|| "Vault metadata key unavailable.".to_string())
                    .and_then(|keypair| {
                        decrypt_signing_message(
                            &session_id,
                            &participant_id,
                            &roster_hash,
                            keypair,
                            &message,
                        )
                    }) {
                    Ok(bytes) => match String::from_utf8(bytes) {
                        Ok(value) => (Some(value), None),
                        Err(e) => (None, Some(format!("Message is not UTF-8 JSON: {e}"))),
                    },
                    Err(e) => (None, Some(e)),
                };
                ApiMultisigSigningMessage {
                    cursor: message.cursor,
                    message_id: message.message_id,
                    session_id: message.session_id,
                    kind: message.kind,
                    from_participant_id: message.from_participant_id,
                    to_participant_id: message.to_participant_id,
                    related_id: message.related_id,
                    plaintext_json,
                    decrypt_error,
                    created_at: message.created_at,
                }
            })
            .collect();
        Ok(ApiMultisigSigningInbox {
            cursor: inbox.cursor,
            messages,
        })
    })
}

pub fn get_multisig_session_events(
    coordinator_url: String,
    session_id: String,
    access_token: String,
    after: i64,
) -> Result<ApiMultisigSessionEvents, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let events = client
            .events(&session_id, &access_token, after)
            .await
            .map_err(client_error)?;
        let mapped = events
            .events
            .into_iter()
            .map(|event| ApiMultisigSessionEvent {
                cursor: event.cursor,
                session_id: event.session_id,
                kind: event.kind,
                actor_participant_id: event.actor_participant_id,
                payload_json: event.payload_json,
                created_at: event.created_at,
            })
            .collect();
        Ok(ApiMultisigSessionEvents {
            cursor: events.cursor,
            events: mapped,
        })
    })
}

pub fn submit_multisig_signing_round1(
    coordinator_url: String,
    session_id: String,
    signing_request_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    selected_participant_ids: Vec<String>,
    pczt_bytes: Vec<u8>,
    key_package_b64: String,
    local_state_json: Option<String>,
) -> Result<ApiMultisigSigningAdvance, String> {
    block_on(async move {
        let selected = normalize_selected_participants(selected_participant_ids)?;
        ensure_selected_signer(&selected, &participant_id)?;
        let pczt_hash = hash_bytes_b64(&pczt_bytes);
        let mut state = parse_signing_state(local_state_json, &signing_request_id, &pczt_hash)?;
        if state.round1_sent {
            return signing_advance(state, "Round 1 was already submitted.");
        }

        let body_json = if let Some(existing) = &state.round1_body_json_b64 {
            decode_b64(existing, "round1 body JSON")?
        } else {
            let pczt = pczt::Pczt::parse(&pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
            let action_indices = unsigned_orchard_action_indices(&pczt)?;
            if action_indices.is_empty() {
                return Err("PCZT has no unsigned Orchard spend actions.".to_string());
            }
            state.action_indices = action_indices.clone();

            let key_package = parse_key_package_b64(&key_package_b64)?;
            let signer_id = *key_package.identifier();
            let mut actions = Vec::new();
            state.nonce_b64_by_action.clear();
            for action_idx in action_indices {
                let round1 = round1_commit(&key_package);
                let msg = round1_msg(&signer_id, &round1.commitments).map_err(|e| e.to_string())?;
                let nonce_bytes = round1
                    .nonces
                    .serialize()
                    .map_err(|e| format!("SigningNonces::serialize: {e:?}"))?;
                state
                    .nonce_b64_by_action
                    .insert(action_idx, URL_SAFE_NO_PAD.encode(nonce_bytes));
                actions.push(TxRoundActionMsg { action_idx, msg });
            }

            let body = TxRound1Body {
                version: 1,
                signing_request_id: signing_request_id.clone(),
                pczt_hash: pczt_hash.clone(),
                participant_id: participant_id.clone(),
                actions,
                created_at: unix_now_secs(),
            };
            let body_json = serde_json::to_vec(&body).map_err(|e| e.to_string())?;
            state.round1_body_json_b64 = Some(URL_SAFE_NO_PAD.encode(&body_json));
            body_json
        };
        let client = Coordinator2Client::new(coordinator_url);
        let recipients = signing_recipients(&client, &session_id, &access_token, &selected).await?;
        if let Err(e) = post_signing_body_to_selected(
            &mut state,
            &client,
            &session_id,
            &signing_request_id,
            &access_token,
            &roster_hash,
            &participant_id,
            &recipients,
            "tx_round1",
            &body_json,
        )
        .await
        {
            return signing_advance_with_submission(
                state,
                &format!("Network error while submitting Round 1: {e}"),
                false,
            );
        }

        state.round1_sent = state.all_sent_to("tx_round1", &recipients);
        signing_advance(state, "Round 1 submitted.")
    })
}

pub fn submit_multisig_signing_round2(
    coordinator_url: String,
    session_id: String,
    signing_request_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    delivery_secret_key: String,
    selected_participant_ids: Vec<String>,
    pczt_bytes: Vec<u8>,
    key_package_b64: String,
    local_state_json: Option<String>,
) -> Result<ApiMultisigSigningAdvance, String> {
    block_on(async move {
        let selected = normalize_selected_participants(selected_participant_ids)?;
        ensure_selected_signer(&selected, &participant_id)?;
        let pczt_hash = hash_bytes_b64(&pczt_bytes);
        let mut state = parse_signing_state(local_state_json, &signing_request_id, &pczt_hash)?;
        if state.round2_sent {
            return signing_advance(state, "Round 2 was already submitted.");
        }
        if !state.round1_sent {
            return Err("Submit Round 1 before Round 2.".to_string());
        }

        let client = Coordinator2Client::new(coordinator_url);
        let body_json = if let Some(existing) = &state.round2_body_json_b64 {
            decode_b64(existing, "round2 body JSON")?
        } else {
            let delivery = DeliveryKeypair::from_secret_b64(&delivery_secret_key)
                .map_err(|e| format!("Invalid delivery secret key: {e}"))?;
            let inbox = collect_signing_inbox(
                &client,
                &session_id,
                &signing_request_id,
                &participant_id,
                &access_token,
                &roster_hash,
                &pczt_hash,
                &delivery,
            )
            .await?;
            ensure_round1_ready(&inbox, &selected)?;

            let pczt = pczt::Pczt::parse(&pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
            let sighash = shielded_sighash(&pczt).map_err(|e| e.to_string())?;
            let key_package = parse_key_package_b64(&key_package_b64)?;
            let signer_id = *key_package.identifier();
            let mut actions = Vec::new();
            let action_indices = state_action_indices(&mut state, &pczt)?;

            for action_idx in action_indices {
                let commitments = round1_commitments_for_action(&inbox.round1, action_idx)?;
                let signing_package = make_signing_package(&sighash, commitments);
                let nonce_b64 = state
                    .nonce_b64_by_action
                    .get(&action_idx)
                    .ok_or_else(|| format!("Missing local nonce for action {action_idx}."))?;
                let nonce_bytes = decode_b64(nonce_b64, "signing nonce")?;
                let nonces = SigningNonces::deserialize(&nonce_bytes)
                    .map_err(|e| format!("SigningNonces::deserialize: {e:?}"))?;
                let alpha = extract_alpha(&pczt, action_idx).map_err(|e| e.to_string())?;
                let randomizer = Randomizer::from_scalar(alpha);
                let share = round2_sign(&signing_package, &nonces, &key_package, randomizer)
                    .map_err(|e| e.to_string())?;
                actions.push(TxRoundActionMsg {
                    action_idx,
                    msg: round2_msg(&signer_id, &share),
                });
            }

            let body = TxRound2Body {
                version: 1,
                signing_request_id: signing_request_id.clone(),
                pczt_hash: pczt_hash.clone(),
                participant_id: participant_id.clone(),
                actions,
                created_at: unix_now_secs(),
            };
            let body_json = serde_json::to_vec(&body).map_err(|e| e.to_string())?;
            state.round2_body_json_b64 = Some(URL_SAFE_NO_PAD.encode(&body_json));
            body_json
        };
        let recipients = signing_recipients(&client, &session_id, &access_token, &selected).await?;
        if let Err(e) = post_signing_body_to_selected(
            &mut state,
            &client,
            &session_id,
            &signing_request_id,
            &access_token,
            &roster_hash,
            &participant_id,
            &recipients,
            "tx_round2",
            &body_json,
        )
        .await
        {
            return signing_advance_with_submission(
                state,
                &format!("Network error while submitting Round 2: {e}"),
                false,
            );
        }

        state.round2_sent = state.all_sent_to("tx_round2", &recipients);
        signing_advance(state, "Round 2 submitted.")
    })
}

pub fn aggregate_multisig_signed_pczt(
    coordinator_url: String,
    session_id: String,
    signing_request_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    delivery_secret_key: String,
    selected_participant_ids: Vec<String>,
    pczt_bytes: Vec<u8>,
    group_public_package_json: String,
    local_state_json: Option<String>,
) -> Result<ApiMultisigSignedPczt, String> {
    block_on(async move {
        let selected = normalize_selected_participants(selected_participant_ids)?;
        ensure_selected_signer(&selected, &participant_id)?;
        let pczt_hash = hash_bytes_b64(&pczt_bytes);
        let mut state = parse_signing_state(local_state_json, &signing_request_id, &pczt_hash)?;
        if let Some(existing) = &state.signed_pczt_b64 {
            return Ok(ApiMultisigSignedPczt {
                local_state_json: serde_json::to_string(&state).map_err(|e| e.to_string())?,
                signed_pczt_bytes: decode_b64(existing, "signed PCZT")?,
            });
        }

        let client = Coordinator2Client::new(coordinator_url);
        let delivery = DeliveryKeypair::from_secret_b64(&delivery_secret_key)
            .map_err(|e| format!("Invalid delivery secret key: {e}"))?;
        let inbox = collect_signing_inbox(
            &client,
            &session_id,
            &signing_request_id,
            &participant_id,
            &access_token,
            &roster_hash,
            &pczt_hash,
            &delivery,
        )
        .await?;
        ensure_round1_ready(&inbox, &selected)?;
        ensure_round2_ready(&inbox, &selected)?;

        let mut pczt = pczt::Pczt::parse(&pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
        let sighash = shielded_sighash(&pczt).map_err(|e| e.to_string())?;
        let group: GroupPublicPackage =
            serde_json::from_str(&group_public_package_json).map_err(|e| e.to_string())?;
        let public_package =
            public_key_package_from_group_package(&group).map_err(|e| e.to_string())?;
        let action_indices = state_action_indices(&mut state, &pczt)?;

        for action_idx in action_indices {
            let commitments = round1_commitments_for_action(&inbox.round1, action_idx)?;
            let signing_package = make_signing_package(&sighash, commitments);
            let shares = round2_shares_for_action(&inbox.round2, action_idx)?;
            let alpha = extract_alpha(&pczt, action_idx).map_err(|e| e.to_string())?;
            let randomizer = Randomizer::from_scalar(alpha);
            let signature = aggregate(&signing_package, &shares, &public_package, randomizer)
                .map_err(|e| e.to_string())?;
            let sig_vec = signature
                .serialize()
                .map_err(|e| format!("Signature::serialize: {e:?}"))?;
            let sig_bytes: [u8; 64] = sig_vec
                .as_slice()
                .try_into()
                .map_err(|_| "Aggregated signature is not 64 bytes.".to_string())?;
            pczt =
                inject_orchard_signature(pczt, action_idx, sig_bytes).map_err(|e| e.to_string())?;
        }

        let signed_pczt_bytes = pczt.serialize();
        state.signed_pczt_b64 = Some(URL_SAFE_NO_PAD.encode(&signed_pczt_bytes));
        Ok(ApiMultisigSignedPczt {
            local_state_json: serde_json::to_string(&state).map_err(|e| e.to_string())?,
            signed_pczt_bytes,
        })
    })
}

pub fn post_multisig_broadcast_result(
    coordinator_url: String,
    session_id: String,
    signing_request_id: String,
    participant_id: String,
    access_token: String,
    roster_hash: String,
    selected_participant_ids: Vec<String>,
    pczt_hash: String,
    txid: String,
    local_state_json: Option<String>,
) -> Result<ApiMultisigSigningAdvance, String> {
    block_on(async move {
        let _selected = normalize_selected_participants(selected_participant_ids)?;
        let mut state = parse_signing_state(local_state_json, &signing_request_id, &pczt_hash)?;
        let client = Coordinator2Client::new(coordinator_url);
        let recipients = session_recipients(&client, &session_id, &access_token).await?;
        if state.all_sent_to("broadcast_result", &recipients) {
            return signing_advance(state, "Broadcast result was already submitted.");
        }
        let related_id = signing_request_id.clone();
        let body_json = if let Some(existing) = &state.broadcast_result_body_json_b64 {
            decode_b64(existing, "broadcast result body JSON")?
        } else {
            let body = serde_json::json!({
                "version": 1,
                "signingRequestId": signing_request_id,
                "txid": txid,
                "createdAt": unix_now_secs(),
            });
            let body_json = serde_json::to_vec(&body).map_err(|e| e.to_string())?;
            state.broadcast_result_body_json_b64 = Some(URL_SAFE_NO_PAD.encode(&body_json));
            body_json
        };
        if let Err(e) = post_signing_body_to_selected(
            &mut state,
            &client,
            &session_id,
            &related_id,
            &access_token,
            &roster_hash,
            &participant_id,
            &recipients,
            "broadcast_result",
            &body_json,
        )
        .await
        {
            return signing_advance_with_submission(
                state,
                &format!("Network error while submitting broadcast result: {e}"),
                false,
            );
        }
        signing_advance(state, "Broadcast result submitted.")
    })
}

fn block_on<T, F>(future: F) -> Result<T, String>
where
    F: Future<Output = Result<T, String>>,
{
    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
    rt.block_on(future)
}

fn structured_multisig_error(
    kind: ApiMultisigErrorKind,
    message: impl Into<String>,
    http_status: Option<u16>,
    retryable: bool,
) -> String {
    let message = message.into();
    serde_json::to_string(&ApiMultisigErrorBody {
        marker: MULTISIG_ERROR_MARKER,
        kind,
        message: message.clone(),
        http_status,
        retry_after_seconds: None,
        retryable,
    })
    .unwrap_or(message)
}

fn client_error(err: ClientError) -> String {
    match err {
        ClientError::Status { status, body } => {
            let status_code = status.as_u16();
            let (kind, retryable) = classify_client_status(status_code);
            let message = if body.trim().is_empty() {
                format!("server returned {status_code}")
            } else {
                body
            };
            structured_multisig_error(kind, message, Some(status_code), retryable)
        }
        ClientError::Http(err) => structured_multisig_error(
            ApiMultisigErrorKind::Network,
            format!("http request failed: {err}"),
            None,
            true,
        ),
        ClientError::WebSocket(err) => structured_multisig_error(
            ApiMultisigErrorKind::Network,
            format!("websocket failed: {err}"),
            None,
            true,
        ),
        ClientError::SignalDecode(err) => structured_multisig_error(
            ApiMultisigErrorKind::Unsupported,
            format!("websocket signal decode failed: {err}"),
            None,
            false,
        ),
        ClientError::UnsupportedWebSocketUrl => structured_multisig_error(
            ApiMultisigErrorKind::Unsupported,
            "unsupported websocket base URL",
            None,
            false,
        ),
    }
}

fn classify_client_status(status_code: u16) -> (ApiMultisigErrorKind, bool) {
    match status_code {
        401 => (ApiMultisigErrorKind::Unauthorized, true),
        403 => (ApiMultisigErrorKind::Forbidden, false),
        409 => (ApiMultisigErrorKind::Conflict, true),
        429 => (ApiMultisigErrorKind::RateLimited, true),
        500..=599 => (ApiMultisigErrorKind::Server, true),
        400..=499 => (ApiMultisigErrorKind::LocalInvalidState, false),
        _ => (ApiMultisigErrorKind::Unknown, false),
    }
}

fn random_word_index(len: usize) -> usize {
    let len = len as u32;
    let zone = u32::MAX - (u32::MAX % len);
    loop {
        let value = OsRng.next_u32();
        if value < zone {
            return (value % len) as usize;
        }
    }
}

fn multisig_identity_from_keys(
    admission: AdmissionKey,
    delivery: DeliveryKeypair,
) -> ApiMultisigParticipantIdentity {
    ApiMultisigParticipantIdentity {
        admission_secret_key: admission.secret_key_b64(),
        admission_public_key: admission.public_key_b64(),
        delivery_secret_key: delivery.secret_key_b64(),
        delivery_public_key: delivery.public_key_b64(),
    }
}

fn restore_participant_identity(
    admission_secret_key: String,
    delivery_secret_key: String,
) -> Result<
    (
        AdmissionKey,
        DeliveryKeypair,
        ApiMultisigParticipantIdentity,
    ),
    String,
> {
    let admission = AdmissionKey::from_secret_b64(&admission_secret_key)
        .map_err(|err| format!("Invalid admission secret key: {err}"))?;
    let delivery = DeliveryKeypair::from_secret_b64(&delivery_secret_key)
        .map_err(|err| format!("Invalid delivery secret key: {err}"))?;
    let identity = multisig_identity_from_keys(admission.clone(), delivery.clone());
    Ok((admission, delivery, identity))
}

fn normalize_backup_passphrase(password: &str, generated: bool) -> Result<String, String> {
    if generated {
        let normalized = password
            .replace('-', " ")
            .split_whitespace()
            .map(str::to_ascii_lowercase)
            .collect::<Vec<_>>();
        if normalized.len() != 8 {
            return Err("Generated backup password must contain exactly 8 words.".to_string());
        }
        let words = Wordlist::EffLong.get_list();
        for word in &normalized {
            if !words.contains(&word.as_str()) {
                return Err(format!(
                    "Generated backup password contains an unknown word: {word}"
                ));
            }
        }
        return Ok(normalized.join(" "));
    }

    let trimmed = password.trim();
    if trimmed.len() < 16 {
        return Err("Backup password must be at least 16 characters.".to_string());
    }
    if !trimmed
        .bytes()
        .all(|byte| byte == b' ' || (0x21..=0x7e).contains(&byte))
    {
        return Err("Use only English letters, numbers, symbols, and spaces.".to_string());
    }
    Ok(trimmed.to_string())
}

fn clean_label(label: Option<String>) -> Option<String> {
    label
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

async fn resume_participant_auth_session(
    client: &Coordinator2Client,
    session_id: String,
    admission: &AdmissionKey,
    delivery: &DeliveryKeypair,
) -> Result<AuthSessionResp, String> {
    let challenge = client
        .create_admission_challenge(&AdmissionChallengeReq::ResumeParticipant {
            session_id: session_id.clone(),
        })
        .await
        .map_err(client_error)?;
    let req = admission.resume_request(session_id, delivery, &challenge);
    client.resume_participant(&req).await.map_err(client_error)
}

fn refresh_error_allows_resume(err: &ClientError) -> bool {
    match err {
        ClientError::Status { status, .. } => status_code_allows_resume(status.as_u16()),
        ClientError::Http(_)
        | ClientError::WebSocket(_)
        | ClientError::SignalDecode(_)
        | ClientError::UnsupportedWebSocketUrl => false,
    }
}

fn status_code_allows_resume(status_code: u16) -> bool {
    status_code == 401
}

fn ensure_auth_owner(
    expected_session_id: &str,
    expected_participant_id: &str,
    returned_session_id: &str,
    returned_participant_id: &str,
) -> Result<(), String> {
    if returned_session_id != expected_session_id
        || returned_participant_id != expected_participant_id
    {
        return Err("Multisig auth response belongs to a different session.".to_string());
    }
    Ok(())
}

fn map_auth_session(
    value: AuthSessionResp,
    identity: ApiMultisigParticipantIdentity,
    invite_secret: Option<&str>,
) -> ApiMultisigAuthSession {
    ApiMultisigAuthSession {
        session_id: value.session_id,
        participant_id: value.participant_id,
        access_token: value.access_token,
        refresh_token: value.refresh_token,
        admission_secret_key: identity.admission_secret_key,
        admission_public_key: identity.admission_public_key,
        delivery_secret_key: identity.delivery_secret_key,
        delivery_public_key: identity.delivery_public_key,
        access_token_expires_at: value.access_token_expires_at,
        refresh_token_expires_at: value.refresh_token_expires_at,
        state: value.state.as_str().to_string(),
        participant: map_participant(value.participant, invite_secret),
    }
}

fn map_auth_update_from_tokens(
    value: AuthTokenResp,
    identity: ApiMultisigParticipantIdentity,
    resumed: bool,
) -> ApiMultisigAuthUpdate {
    ApiMultisigAuthUpdate {
        session_id: value.session_id,
        participant_id: value.participant_id,
        access_token: value.access_token,
        refresh_token: value.refresh_token,
        admission_public_key: identity.admission_public_key,
        delivery_secret_key: identity.delivery_secret_key,
        delivery_public_key: identity.delivery_public_key,
        access_token_expires_at: value.access_token_expires_at,
        refresh_token_expires_at: value.refresh_token_expires_at,
        resumed,
    }
}

fn map_auth_update_from_session(
    value: AuthSessionResp,
    identity: ApiMultisigParticipantIdentity,
    resumed: bool,
) -> ApiMultisigAuthUpdate {
    ApiMultisigAuthUpdate {
        session_id: value.session_id,
        participant_id: value.participant_id,
        access_token: value.access_token,
        refresh_token: value.refresh_token,
        admission_public_key: identity.admission_public_key,
        delivery_secret_key: identity.delivery_secret_key,
        delivery_public_key: identity.delivery_public_key,
        access_token_expires_at: value.access_token_expires_at,
        refresh_token_expires_at: value.refresh_token_expires_at,
        resumed,
    }
}

fn map_tokens(value: AuthTokenResp) -> ApiMultisigTokens {
    ApiMultisigTokens {
        session_id: value.session_id,
        participant_id: value.participant_id,
        access_token: value.access_token,
        refresh_token: value.refresh_token,
        access_token_expires_at: value.access_token_expires_at,
        refresh_token_expires_at: value.refresh_token_expires_at,
    }
}

fn map_session(value: SessionResp, invite_secret: Option<&str>) -> ApiMultisigSession {
    ApiMultisigSession {
        session_id: value.session_id,
        state: value.state.as_str().to_string(),
        creator_participant_id: value.creator_participant_id,
        threshold: value.threshold,
        roster_hash: value.roster_hash,
        group_public_package_hash: value.group_public_package_hash,
        participants: value
            .participants
            .into_iter()
            .map(|participant| map_participant(participant, invite_secret))
            .collect(),
        created_at: value.created_at,
        updated_at: value.updated_at,
    }
}

fn map_signing_request(value: SigningRequestResp, pczt_hash: String) -> ApiMultisigSigningRequest {
    ApiMultisigSigningRequest {
        signing_request_id: value.signing_request_id,
        session_id: value.session_id,
        requester_participant_id: value.requester_participant_id,
        selected_participant_ids: value.selected_participant_ids,
        round1_participant_ids: value.round1_participant_ids,
        round2_participant_ids: value.round2_participant_ids,
        broadcast_participant_ids: value.broadcast_participant_ids,
        state: value.state.as_str().to_string(),
        created_at: value.created_at,
        updated_at: value.updated_at,
        pczt_hash,
    }
}

fn map_participant(
    value: ParticipantResp,
    invite_secret: Option<&str>,
) -> ApiMultisigParticipant {
    // The coordinator only relays a sealed label; without the invite secret
    // (or when the seal does not verify for this participant's admission
    // key) the participant simply has no label and the UI falls back to the
    // short participant id.
    let label = match (invite_secret, value.encrypted_label.as_deref()) {
        (Some(secret), Some(sealed)) => {
            open_session_label(secret, &value.admission_public_key, sealed).ok()
        }
        _ => None,
    };
    ApiMultisigParticipant {
        participant_id: value.participant_id,
        label,
        admission_public_key: value.admission_public_key,
        delivery_public_key: value.delivery_public_key,
        joined_at: value.joined_at,
        dkg_completed: value.dkg_completed,
    }
}

fn seal_label(
    invite_secret: &str,
    admission_public_key: &str,
    label: Option<String>,
) -> Result<Option<String>, String> {
    match clean_label(label) {
        Some(label) => seal_session_label(invite_secret, admission_public_key, &label)
            .map(Some)
            .map_err(|e| format!("Failed to seal label: {e}")),
        None => Ok(None),
    }
}

fn parse_signing_state(
    local_state_json: Option<String>,
    signing_request_id: &str,
    pczt_hash: &str,
) -> Result<LocalSigningState, String> {
    let Some(raw) = local_state_json.filter(|value| !value.trim().is_empty()) else {
        return Ok(LocalSigningState::new(
            signing_request_id.to_string(),
            pczt_hash.to_string(),
        ));
    };
    let mut state: LocalSigningState = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if state.signing_request_id != signing_request_id || state.pczt_hash != pczt_hash {
        return Ok(LocalSigningState::new(
            signing_request_id.to_string(),
            pczt_hash.to_string(),
        ));
    }
    state.version = 1;
    Ok(state)
}

fn signing_advance(
    state: LocalSigningState,
    detail: &str,
) -> Result<ApiMultisigSigningAdvance, String> {
    signing_advance_with_submission(state, detail, true)
}

fn signing_advance_with_submission(
    state: LocalSigningState,
    detail: &str,
    submitted: bool,
) -> Result<ApiMultisigSigningAdvance, String> {
    Ok(ApiMultisigSigningAdvance {
        local_state_json: serde_json::to_string(&state).map_err(|e| e.to_string())?,
        detail: detail.to_string(),
        submitted,
    })
}

fn ensure_selected_signer(selected: &[String], participant_id: &str) -> Result<(), String> {
    if selected.iter().any(|entry| entry == participant_id) {
        Ok(())
    } else {
        Err("Local participant is not selected for this signing request.".to_string())
    }
}

fn parse_key_package_b64(value: &str) -> Result<KeyPackage, String> {
    let bytes = decode_b64(value, "key package")?;
    KeyPackage::deserialize(&bytes).map_err(|e| format!("KeyPackage::deserialize: {e:?}"))
}

fn unsigned_orchard_action_indices(pczt: &pczt::Pczt) -> Result<Vec<usize>, String> {
    let mut out = Vec::new();
    let _consumed = LowLevelSigner::new(pczt.clone())
        .sign_orchard_with(
            |_pczt, bundle, _tx_modifiable| -> Result<(), orchard::pczt::ParseError> {
                for (idx, action) in bundle.actions().iter().enumerate() {
                    if action.spend().spend_auth_sig().is_none() {
                        out.push(idx);
                    }
                }
                Ok(())
            },
        )
        .map_err(|e| format!("sign_orchard_with (unsigned actions): {e:?}"))?;
    Ok(out)
}

fn state_action_indices(
    state: &mut LocalSigningState,
    pczt: &pczt::Pczt,
) -> Result<Vec<usize>, String> {
    if state.action_indices.is_empty() {
        state.action_indices = unsigned_orchard_action_indices(pczt)?;
    }
    if state.action_indices.is_empty() {
        return Err("PCZT has no unsigned Orchard spend actions.".to_string());
    }
    Ok(state.action_indices.clone())
}

async fn signing_recipients(
    client: &Coordinator2Client,
    session_id: &str,
    access_token: &str,
    selected: &[String],
) -> Result<Vec<ParticipantResp>, String> {
    let session = client
        .get_session(session_id, access_token)
        .await
        .map_err(client_error)?;
    let participants_by_id: BTreeMap<String, ParticipantResp> = session
        .participants
        .into_iter()
        .map(|participant| (participant.participant_id.clone(), participant))
        .collect();
    selected
        .iter()
        .map(|participant_id| {
            participants_by_id
                .get(participant_id)
                .cloned()
                .ok_or_else(|| format!("Selected signer is not in this session: {participant_id}"))
        })
        .collect()
}

async fn session_recipients(
    client: &Coordinator2Client,
    session_id: &str,
    access_token: &str,
) -> Result<Vec<ParticipantResp>, String> {
    let session = client
        .get_session(session_id, access_token)
        .await
        .map_err(client_error)?;
    if session.participants.is_empty() {
        return Err("Multisig session has no participants.".to_string());
    }
    Ok(session.participants)
}

#[allow(clippy::too_many_arguments)]
async fn post_signing_body_to_selected(
    state: &mut LocalSigningState,
    client: &Coordinator2Client,
    session_id: &str,
    signing_request_id: &str,
    access_token: &str,
    roster_hash: &str,
    from_participant_id: &str,
    recipients: &[ParticipantResp],
    kind: &str,
    body_json: &[u8],
) -> Result<(), String> {
    for recipient in recipients {
        if state.sent_to_contains(kind, &recipient.participant_id) {
            continue;
        }
        let idempotency_key = idempotency_key(
            "signing-message",
            &[
                signing_request_id,
                kind,
                from_participant_id,
                &recipient.participant_id,
            ],
        );
        let envelope = if let Some(envelope) = state.outbound_messages.get(&idempotency_key) {
            envelope.clone()
        } else {
            let ctx = E2eContext {
                session_id,
                roster_hash: Some(roster_hash),
                kind,
                from_participant_id,
                to_participant_id: Some(&recipient.participant_id),
                related_id: Some(signing_request_id),
            };
            let envelope = encrypt_for(&recipient.delivery_public_key, &ctx, body_json)
                .map_err(|e| e.to_string())?;
            state
                .outbound_messages
                .insert(idempotency_key.clone(), envelope.clone());
            envelope
        };
        client
            .post_signing_message_with_idempotency(
                signing_request_id,
                access_token,
                &idempotency_key,
                &envelope,
            )
            .await
            .map_err(client_error)?;
        state.outbound_messages.remove(&idempotency_key);
        state.mark_sent_to(kind, recipient.participant_id.clone());
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn collect_signing_inbox(
    client: &Coordinator2Client,
    session_id: &str,
    signing_request_id: &str,
    participant_id: &str,
    access_token: &str,
    roster_hash: &str,
    expected_pczt_hash: &str,
    delivery: &DeliveryKeypair,
) -> Result<SigningInboxMessages, String> {
    let inbox = client
        .inbox(session_id, access_token, 0)
        .await
        .map_err(client_error)?;
    let mut out = SigningInboxMessages {
        round1: BTreeMap::new(),
        round2: BTreeMap::new(),
    };
    for message in inbox.messages {
        if message.related_id.as_deref() != Some(signing_request_id) {
            continue;
        }
        if !matches!(
            message.kind.as_str(),
            "tx_round1" | "tx_round2" | "broadcast_result"
        ) {
            continue;
        }
        let plaintext =
            decrypt_signing_message(session_id, participant_id, roster_hash, delivery, &message)?;
        match message.kind.as_str() {
            "tx_round1" => {
                let body: TxRound1Body =
                    serde_json::from_slice(&plaintext).map_err(|e| e.to_string())?;
                if body.signing_request_id != signing_request_id
                    || body.pczt_hash != expected_pczt_hash
                {
                    return Err("Received Round 1 message for another signing request.".to_string());
                }
                if body.participant_id != message.from_participant_id {
                    return Err("Received Round 1 message with mismatched sender.".to_string());
                }
                insert_unique_round1(&mut out.round1, message.from_participant_id, body)?;
            }
            "tx_round2" => {
                let body: TxRound2Body =
                    serde_json::from_slice(&plaintext).map_err(|e| e.to_string())?;
                if body.signing_request_id != signing_request_id
                    || body.pczt_hash != expected_pczt_hash
                {
                    return Err("Received Round 2 message for another signing request.".to_string());
                }
                if body.participant_id != message.from_participant_id {
                    return Err("Received Round 2 message with mismatched sender.".to_string());
                }
                insert_unique_round2(&mut out.round2, message.from_participant_id, body)?;
            }
            "broadcast_result" => {}
            _ => {}
        }
    }
    Ok(out)
}

fn insert_unique_round1(
    map: &mut BTreeMap<String, TxRound1Body>,
    participant_id: String,
    body: TxRound1Body,
) -> Result<(), String> {
    if let Some(existing) = map.get(&participant_id) {
        if serde_json::to_vec(existing).map_err(|e| e.to_string())?
            != serde_json::to_vec(&body).map_err(|e| e.to_string())?
        {
            return Err(format!(
                "Conflicting Round 1 message from {participant_id}."
            ));
        }
        return Ok(());
    }
    map.insert(participant_id, body);
    Ok(())
}

fn insert_unique_round2(
    map: &mut BTreeMap<String, TxRound2Body>,
    participant_id: String,
    body: TxRound2Body,
) -> Result<(), String> {
    if let Some(existing) = map.get(&participant_id) {
        if serde_json::to_vec(existing).map_err(|e| e.to_string())?
            != serde_json::to_vec(&body).map_err(|e| e.to_string())?
        {
            return Err(format!(
                "Conflicting Round 2 message from {participant_id}."
            ));
        }
        return Ok(());
    }
    map.insert(participant_id, body);
    Ok(())
}

fn ensure_round1_ready(inbox: &SigningInboxMessages, selected: &[String]) -> Result<(), String> {
    let missing = selected
        .iter()
        .filter(|participant_id| !inbox.round1.contains_key(*participant_id))
        .cloned()
        .collect::<Vec<_>>();
    if missing.is_empty() {
        Ok(())
    } else {
        Err(format!("Waiting for Round 1 from: {}", missing.join(", ")))
    }
}

fn ensure_round2_ready(inbox: &SigningInboxMessages, selected: &[String]) -> Result<(), String> {
    let missing = selected
        .iter()
        .filter(|participant_id| !inbox.round2.contains_key(*participant_id))
        .cloned()
        .collect::<Vec<_>>();
    if missing.is_empty() {
        Ok(())
    } else {
        Err(format!("Waiting for Round 2 from: {}", missing.join(", ")))
    }
}

fn round1_commitments_for_action(
    round1: &BTreeMap<String, TxRound1Body>,
    action_idx: usize,
) -> Result<BTreeMap<Identifier, SigningCommitments>, String> {
    let mut commitments = BTreeMap::new();
    for body in round1.values() {
        let msg = round_action_msg(&body.actions, action_idx, "Round 1")?;
        let (identifier, commitment) = parse_round1_msg(msg).map_err(|e| e.to_string())?;
        commitments.insert(identifier, commitment);
    }
    Ok(commitments)
}

fn round2_shares_for_action(
    round2: &BTreeMap<String, TxRound2Body>,
    action_idx: usize,
) -> Result<BTreeMap<Identifier, SignatureShare>, String> {
    let mut shares = BTreeMap::new();
    for body in round2.values() {
        let msg = round_action_msg(&body.actions, action_idx, "Round 2")?;
        let (identifier, share) = parse_round2_msg(msg).map_err(|e| e.to_string())?;
        shares.insert(identifier, share);
    }
    Ok(shares)
}

fn round_action_msg<'a>(
    actions: &'a [TxRoundActionMsg],
    action_idx: usize,
    label: &str,
) -> Result<&'a RoundMsg, String> {
    actions
        .iter()
        .find(|action| action.action_idx == action_idx)
        .map(|action| &action.msg)
        .ok_or_else(|| format!("{label} message is missing action {action_idx}."))
}

fn parse_create_state(
    local_state_json: Option<String>,
    session_id: &str,
    participant_id: &str,
) -> Result<LocalCreateState, String> {
    let Some(raw) = local_state_json.filter(|value| !value.trim().is_empty()) else {
        return Ok(LocalCreateState::new(
            session_id.to_string(),
            participant_id.to_string(),
        ));
    };
    let mut state: LocalCreateState = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if state.session_id != session_id || state.participant_id != participant_id {
        return Ok(LocalCreateState::new(
            session_id.to_string(),
            participant_id.to_string(),
        ));
    }
    state.version = 1;
    Ok(state)
}

fn sync_locked_roster(state: &mut LocalCreateState, session: &SessionResp) -> Result<(), String> {
    let roster_hash = session
        .roster_hash
        .clone()
        .ok_or_else(|| "Session roster is not locked.".to_string())?;
    let threshold = session
        .threshold
        .ok_or_else(|| "Session threshold is not locked.".to_string())?;
    if state
        .roster_hash
        .as_deref()
        .is_some_and(|value| value != roster_hash)
    {
        return Err("Stored create state belongs to a different roster.".to_string());
    }

    let mut participants = session.participants.clone();
    participants.sort_by(|a, b| {
        a.joined_at
            .cmp(&b.joined_at)
            .then_with(|| a.participant_id.cmp(&b.participant_id))
    });
    if participants.len() < 2 {
        return Err("DKG requires at least two participants.".to_string());
    }
    if participants.len() > u8::MAX as usize {
        return Err("Too many participants for this DKG identifier mapping.".to_string());
    }
    if !participants
        .iter()
        .any(|participant| participant.participant_id == state.participant_id)
    {
        return Err("Local participant is not in the locked roster.".to_string());
    }

    state.roster_hash = Some(roster_hash);
    state.threshold = Some(threshold);
    state.roster = participants
        .iter()
        .enumerate()
        .map(|(idx, participant)| {
            let identifier = dkg_identifier((idx + 1) as u8)?;
            Ok(LocalRosterParticipant {
                participant_id: participant.participant_id.clone(),
                delivery_public_key: participant.delivery_public_key.clone(),
                dkg_identifier_hex: hex::encode(identifier.serialize()),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(())
}

async fn poll_create_inbox(
    client: &Coordinator2Client,
    access_token: &str,
    state: &mut LocalCreateState,
    delivery: &DeliveryKeypair,
    roster_hash: &str,
    seed_issuer: &str,
) -> Result<Option<String>, String> {
    let inbox = client
        .inbox(&state.session_id, access_token, state.inbox_cursor)
        .await
        .map_err(client_error)?;
    let mut cursor = state.inbox_cursor;
    for message in inbox.messages {
        if !matches!(
            message.kind.as_str(),
            "dkg_broadcast_seed" | "dkg_round1" | "dkg_round2"
        ) {
            cursor = message.cursor;
            continue;
        }
        let plaintext = decrypt_create_message(state, delivery, roster_hash, &message)?;
        match message.kind.as_str() {
            "dkg_broadcast_seed" => {
                if message.from_participant_id != seed_issuer {
                    return Ok(Some(
                        "Received DKG seed from an unexpected participant.".to_string(),
                    ));
                }
                if plaintext.len() != 32 {
                    return Ok(Some("Received invalid DKG seed.".to_string()));
                }
                let seed_b64 = URL_SAFE_NO_PAD.encode(&plaintext);
                if let Some(existing) = &state.broadcast_seed_b64 {
                    if existing != &seed_b64 {
                        return Ok(Some("Received conflicting DKG seed.".to_string()));
                    }
                } else {
                    state.broadcast_seed_b64 = Some(seed_b64);
                }
            }
            "dkg_round1" => {
                let msg: RoundMsg =
                    serde_json::from_slice(&plaintext).map_err(|e| e.to_string())?;
                let sender = roster_entry(state, &message.from_participant_id)?;
                if msg.identifier_hex != sender.dkg_identifier_hex {
                    return Ok(Some(
                        "Received DKG round 1 with an unexpected identifier.".to_string(),
                    ));
                }
                if let Some(existing) = state.round1_messages.get(&message.from_participant_id) {
                    if serde_json::to_vec(existing).map_err(|e| e.to_string())?
                        != serde_json::to_vec(&msg).map_err(|e| e.to_string())?
                    {
                        return Ok(Some(
                            "Received conflicting DKG round 1 message.".to_string(),
                        ));
                    }
                } else {
                    state
                        .round1_messages
                        .insert(message.from_participant_id.clone(), msg);
                }
            }
            "dkg_round2" => {
                let msg: DkgRound2Msg =
                    serde_json::from_slice(&plaintext).map_err(|e| e.to_string())?;
                let sender = roster_entry(state, &message.from_participant_id)?;
                if msg.sender_hex != sender.dkg_identifier_hex {
                    return Ok(Some(
                        "Received DKG round 2 with an unexpected sender.".to_string(),
                    ));
                }
                let own = own_roster_entry(state)?;
                if msg.target_hex != own.dkg_identifier_hex {
                    return Ok(Some(
                        "Received DKG round 2 message for another participant.".to_string(),
                    ));
                }
                if let Some(existing) = state.round2_messages.get(&message.from_participant_id) {
                    if serde_json::to_vec(existing).map_err(|e| e.to_string())?
                        != serde_json::to_vec(&msg).map_err(|e| e.to_string())?
                    {
                        return Ok(Some(
                            "Received conflicting DKG round 2 message.".to_string(),
                        ));
                    }
                } else {
                    state
                        .round2_messages
                        .insert(message.from_participant_id.clone(), msg);
                }
            }
            _ => {}
        }
        cursor = message.cursor;
    }
    state.inbox_cursor = inbox.cursor.max(cursor);
    Ok(None)
}

fn seed_issuer_participant_id(session: &SessionResp) -> Result<String, String> {
    if session
        .participants
        .iter()
        .any(|participant| participant.participant_id == session.creator_participant_id)
    {
        return Ok(session.creator_participant_id.clone());
    }
    session
        .participants
        .iter()
        .min_by(|a, b| {
            a.joined_at
                .cmp(&b.joined_at)
                .then_with(|| a.participant_id.cmp(&b.participant_id))
        })
        .map(|participant| participant.participant_id.clone())
        .ok_or_else(|| "Session has no participants.".to_string())
}

fn ensure_dkg_round1(
    state: &mut LocalCreateState,
    participant_id: &str,
    threshold: u16,
) -> Result<(), String> {
    if state.round1_secret_b64.is_some() && state.round1_messages.contains_key(participant_id) {
        return Ok(());
    }
    let own = own_roster_entry(state)?;
    let identifier = identifier_from_hex(&own.dkg_identifier_hex)?;
    let (secret, msg) =
        dkg_part1(identifier, state.roster.len() as u16, threshold).map_err(|e| e.to_string())?;
    let secret_bytes = secret
        .serialize()
        .map_err(|e| format!("round1 secret serialize: {e:?}"))?;
    state.round1_secret_b64 = Some(URL_SAFE_NO_PAD.encode(secret_bytes));
    state
        .round1_messages
        .insert(participant_id.to_string(), msg);
    Ok(())
}

fn ensure_dkg_round2(state: &mut LocalCreateState) -> Result<(), String> {
    if state.round2_secret_b64.is_some() && !state.outbound_round2.is_empty() {
        return Ok(());
    }
    let own = own_roster_entry(state)?;
    let own_id = identifier_from_hex(&own.dkg_identifier_hex)?;
    let all_round1 = all_dkg_round1_packages(state)?;
    let others = without_identifier(&all_round1, own_id);
    let secret_bytes = decode_b64(
        state
            .round1_secret_b64
            .as_deref()
            .ok_or_else(|| "Missing local DKG round1 secret.".to_string())?,
        "round1 secret",
    )?;
    let secret = frost_dkg::round1::SecretPackage::deserialize(&secret_bytes)
        .map_err(|e| format!("round1 secret deserialize: {e:?}"))?;
    let (round2_secret, msgs) = dkg_part2(secret, &others).map_err(|e| e.to_string())?;
    let secret_bytes = round2_secret
        .serialize()
        .map_err(|e| format!("round2 secret serialize: {e:?}"))?;
    state.round2_secret_b64 = Some(URL_SAFE_NO_PAD.encode(secret_bytes));
    let participant_by_hex: BTreeMap<String, String> = state
        .roster
        .iter()
        .map(|participant| {
            (
                participant.dkg_identifier_hex.clone(),
                participant.participant_id.clone(),
            )
        })
        .collect();
    state.outbound_round2.clear();
    for msg in msgs {
        let target = participant_by_hex
            .get(&msg.target_hex)
            .ok_or_else(|| "DKG round 2 target is not in roster.".to_string())?;
        state.outbound_round2.insert(target.clone(), msg);
    }
    Ok(())
}

fn ensure_dkg_finalized(state: &mut LocalCreateState) -> Result<(), String> {
    if state.key_package_b64.is_some()
        && state.group_public_package_json.is_some()
        && state.group_public_package_hash.is_some()
    {
        return Ok(());
    }
    let own = own_roster_entry(state)?;
    let own_id = identifier_from_hex(&own.dkg_identifier_hex)?;
    let all_round1 = all_dkg_round1_packages(state)?;
    let others_round1 = without_identifier(&all_round1, own_id);
    let round2_secret_bytes = decode_b64(
        state
            .round2_secret_b64
            .as_deref()
            .ok_or_else(|| "Missing local DKG round2 secret.".to_string())?,
        "round2 secret",
    )?;
    let round2_secret = frost_dkg::round2::SecretPackage::deserialize(&round2_secret_bytes)
        .map_err(|e| format!("round2 secret deserialize: {e:?}"))?;
    let mut round2_packages = BTreeMap::new();
    for msg in state.round2_messages.values() {
        let (sender, package) = parse_dkg_round2(msg).map_err(|e| e.to_string())?;
        round2_packages.insert(sender, package);
    }
    let (key_package, public_package) =
        dkg_part3(&round2_secret, &others_round1, &round2_packages).map_err(|e| e.to_string())?;
    if key_package.identifier().serialize()
        != identifier_from_hex(&own.dkg_identifier_hex)?.serialize()
    {
        return Err("Final DKG key package belongs to another participant.".to_string());
    }
    let seed = decode_b64_32(
        state
            .broadcast_seed_b64
            .as_deref()
            .ok_or_else(|| "Missing broadcast seed.".to_string())?,
        "broadcast seed",
    )?;
    let group = build_group_public_package(
        &public_package,
        ThresholdParams::new(
            state
                .threshold
                .ok_or_else(|| "Missing threshold.".to_string())?,
            state.roster.len() as u16,
        )
        .map_err(|e| e.to_string())?,
        seed,
    )
    .map_err(|e| e.to_string())?;
    let group_json = serde_json::to_string(&group).map_err(|e| e.to_string())?;
    let group_hash = hash_group_public_package(&group)?;
    let key_package_bytes = key_package
        .serialize()
        .map_err(|e| format!("key package serialize: {e:?}"))?;
    state.key_package_b64 = Some(URL_SAFE_NO_PAD.encode(key_package_bytes));
    state.group_public_package_json = Some(group_json);
    state.group_public_package_hash = Some(group_hash);
    Ok(())
}

fn all_dkg_round1_packages(
    state: &LocalCreateState,
) -> Result<BTreeMap<Identifier, frost_dkg::round1::Package>, String> {
    state
        .round1_messages
        .values()
        .map(|msg| parse_dkg_round1(msg).map_err(|e| e.to_string()))
        .collect()
}

fn without_identifier<T: Clone>(
    map: &BTreeMap<Identifier, T>,
    own: Identifier,
) -> BTreeMap<Identifier, T> {
    map.iter()
        .filter(|(identifier, _)| **identifier != own)
        .map(|(identifier, value)| (*identifier, value.clone()))
        .collect()
}

fn missing_round1_participants(state: &LocalCreateState) -> Vec<String> {
    state
        .roster
        .iter()
        .filter(|participant| {
            !state
                .round1_messages
                .contains_key(&participant.participant_id)
        })
        .map(|participant| participant.participant_id.clone())
        .collect()
}

fn missing_round2_participants(state: &LocalCreateState, participant_id: &str) -> Vec<String> {
    state
        .roster
        .iter()
        .filter(|participant| participant.participant_id != participant_id)
        .filter(|participant| {
            !state
                .round2_messages
                .contains_key(&participant.participant_id)
        })
        .map(|participant| participant.participant_id.clone())
        .collect()
}

fn own_roster_entry(state: &LocalCreateState) -> Result<LocalRosterParticipant, String> {
    roster_entry(state, &state.participant_id)
}

fn roster_entry(
    state: &LocalCreateState,
    participant_id: &str,
) -> Result<LocalRosterParticipant, String> {
    state
        .roster
        .iter()
        .find(|participant| participant.participant_id == participant_id)
        .cloned()
        .ok_or_else(|| "Participant is missing from roster.".to_string())
}

async fn post_create_message_with_outbox(
    state: &mut LocalCreateState,
    client: &Coordinator2Client,
    access_token: &str,
    roster_hash: &str,
    from_participant_id: &str,
    recipient: &LocalRosterParticipant,
    kind: &str,
    plaintext: &[u8],
) -> Result<(), String> {
    let key = idempotency_key(
        "session-message",
        &[
            &state.session_id,
            kind,
            from_participant_id,
            &recipient.participant_id,
        ],
    );
    let envelope = if let Some(envelope) = state.outbound_messages.get(&key) {
        envelope.clone()
    } else {
        let ctx = E2eContext {
            session_id: &state.session_id,
            roster_hash: Some(roster_hash),
            kind,
            from_participant_id,
            to_participant_id: Some(&recipient.participant_id),
            related_id: None,
        };
        let envelope = encrypt_for(&recipient.delivery_public_key, &ctx, plaintext)
            .map_err(|e| e.to_string())?;
        state
            .outbound_messages
            .insert(key.clone(), envelope.clone());
        envelope
    };
    client
        .post_message_with_idempotency(&state.session_id, access_token, &key, &envelope)
        .await
        .map_err(client_error)?;
    state.outbound_messages.remove(&key);
    Ok(())
}

fn decrypt_create_message(
    state: &LocalCreateState,
    delivery: &DeliveryKeypair,
    roster_hash: &str,
    message: &MessageResp,
) -> Result<Vec<u8>, String> {
    if message.session_id != state.session_id {
        return Err("Message belongs to another session.".to_string());
    }
    if message
        .to_participant_id
        .as_deref()
        .is_some_and(|target| target != state.participant_id)
    {
        return Err("Message is addressed to another participant.".to_string());
    }
    let ctx = E2eContext {
        session_id: &message.session_id,
        roster_hash: Some(roster_hash),
        kind: &message.kind,
        from_participant_id: &message.from_participant_id,
        to_participant_id: message.to_participant_id.as_deref(),
        related_id: message.related_id.as_deref(),
    };
    delivery
        .decrypt(
            &ctx,
            &message.ephemeral_public_key,
            &message.nonce,
            &message.ciphertext,
        )
        .map_err(|_| "Failed to decrypt multisig DKG message.".to_string())
}

fn decrypt_signing_message(
    session_id: &str,
    participant_id: &str,
    roster_hash: &str,
    delivery: &DeliveryKeypair,
    message: &MessageResp,
) -> Result<Vec<u8>, String> {
    if message.session_id != session_id {
        return Err("Message belongs to another session.".to_string());
    }
    if message
        .to_participant_id
        .as_deref()
        .is_some_and(|target| target != participant_id)
    {
        return Err("Message is addressed to another participant.".to_string());
    }
    let ctx = E2eContext {
        session_id: &message.session_id,
        roster_hash: Some(roster_hash),
        kind: &message.kind,
        from_participant_id: &message.from_participant_id,
        to_participant_id: message.to_participant_id.as_deref(),
        related_id: message.related_id.as_deref(),
    };
    delivery
        .decrypt(
            &ctx,
            &message.ephemeral_public_key,
            &message.nonce,
            &message.ciphertext,
        )
        .map_err(|_| "Failed to decrypt multisig signing message.".to_string())
}

fn vault_address_from_group_public_package(
    network: &str,
    group_public_package_json: &str,
) -> Result<String, String> {
    let wallet_network = wallet_keys::parse_network(network)?;
    let group: GroupPublicPackage = serde_json::from_str(group_public_package_json)
        .map_err(|e| format!("Failed to parse multisig group public package: {e}"))?;
    group_address_ua(&group, &wallet_network)
        .map_err(|e| format!("Failed to derive multisig vault address: {e}"))
}

fn hash_group_public_package(value: &impl Serialize) -> Result<String, String> {
    let body = serde_json::to_vec(value).map_err(|e| e.to_string())?;
    let mut h = Sha256::new();
    h.update(b"zcash-wallet/multisig/group-public-package/v1\0");
    h.update(body);
    Ok(URL_SAFE_NO_PAD.encode(h.finalize()))
}

fn dkg_identifier(index: u8) -> Result<Identifier, String> {
    let mut bytes = [0u8; 32];
    bytes[0] = index;
    Identifier::deserialize(&bytes).map_err(|e| format!("identifier deserialize: {e:?}"))
}

fn identifier_from_hex(value: &str) -> Result<Identifier, String> {
    let bytes = hex::decode(value).map_err(|e| format!("identifier hex decode: {e}"))?;
    Identifier::deserialize(&bytes).map_err(|e| format!("identifier deserialize: {e:?}"))
}

fn hash_bytes_b64(value: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(value);
    URL_SAFE_NO_PAD.encode(h.finalize())
}

fn stable_id(prefix: &str, parts: &[&str]) -> String {
    format!("{prefix}_{}", stable_hash(parts))
}

fn idempotency_key(scope: &str, parts: &[&str]) -> String {
    format!("vz1:{scope}:{}", stable_hash(parts))
}

fn stable_hash(parts: &[&str]) -> String {
    let mut h = Sha256::new();
    h.update(b"zcash-wallet/multisig/idempotency/v1\0");
    for part in parts {
        h.update((part.len() as u32).to_be_bytes());
        h.update(part.as_bytes());
    }
    URL_SAFE_NO_PAD.encode(h.finalize())
}

fn normalize_selected_participants(mut values: Vec<String>) -> Result<Vec<String>, String> {
    for value in &mut values {
        *value = value.trim().to_string();
    }
    values.retain(|value| !value.is_empty());
    values.sort();
    values.dedup();
    if values.is_empty() {
        return Err("Select at least one signer.".to_string());
    }
    Ok(values)
}

fn unix_now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn decode_b64(value: &str, label: &str) -> Result<Vec<u8>, String> {
    URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|e| format!("Invalid {label}: {e}"))
}

fn decode_b64_32(value: &str, label: &str) -> Result<[u8; 32], String> {
    decode_b64(value, label)?
        .try_into()
        .map_err(|_| format!("Invalid {label}: expected 32 bytes"))
}

fn session_state_phase(message: &str) -> String {
    message.to_string()
}

fn create_progress_with(
    session: SessionResp,
    state: LocalCreateState,
    detail: String,
    waiting_for_participant_ids: Vec<String>,
    invite_secret: Option<&str>,
) -> Result<ApiMultisigCreateAdvance, String> {
    let phase = if session.state.as_str() != "request_create" {
        session.state.as_str().to_string()
    } else if state.dkg_complete_submitted
        || session
            .participants
            .iter()
            .find(|participant| participant.participant_id == state.participant_id)
            .is_some_and(|participant| participant.dkg_completed)
    {
        "dkg_complete".to_string()
    } else if state.broadcast_seed_b64.is_none() {
        "waiting_for_seed".to_string()
    } else if state.round1_messages.len() < state.roster.len() {
        "waiting_for_round1".to_string()
    } else if state.round2_messages.len() + 1 < state.roster.len() {
        "waiting_for_round2".to_string()
    } else if state.group_public_package_hash.is_some() {
        "finalized".to_string()
    } else {
        "in_progress".to_string()
    };
    let local_state_json = serde_json::to_string(&state).map_err(|e| e.to_string())?;
    Ok(ApiMultisigCreateAdvance {
        session: map_session(session, invite_secret),
        local_state_json,
        phase,
        detail,
        waiting_for_participant_ids,
        round1_count: state.round1_messages.len() as u32,
        round2_count: state.round2_messages.len() as u32,
        dkg_complete_submitted: state.dkg_complete_submitted,
        key_package_b64: state.key_package_b64,
        group_public_package_json: state.group_public_package_json,
        group_public_package_hash: state.group_public_package_hash,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn threshold_validation_uses_multisig_core_rules() {
        let params = validate_multisig_threshold(2, 3).unwrap();
        assert_eq!(params.threshold, 2);
        assert_eq!(params.participant_count, 3);

        assert!(validate_multisig_threshold(1, 3).is_err());
        assert!(validate_multisig_threshold(3, 2).is_err());
    }

    #[test]
    fn generated_identity_restores_from_local_secrets() {
        let identity = generate_multisig_participant_identity();
        let restored = restore_multisig_participant_identity(
            identity.admission_secret_key.clone(),
            identity.delivery_secret_key.clone(),
        )
        .unwrap();

        assert_eq!(identity.admission_public_key, restored.admission_public_key);
        assert_eq!(identity.delivery_public_key, restored.delivery_public_key);
        assert_eq!(identity.admission_secret_key, restored.admission_secret_key);
        assert_eq!(identity.delivery_secret_key, restored.delivery_secret_key);
        assert!(!identity.admission_public_key.is_empty());
        assert!(!identity.delivery_public_key.is_empty());
        assert!(restore_multisig_participant_identity(
            "not-base64".to_string(),
            identity.delivery_secret_key
        )
        .is_err());
    }

    #[test]
    fn generated_backup_password_normalizes_and_checksums() {
        let password = generate_multisig_backup_password();
        assert_eq!(
            normalize_multisig_backup_password(password.display_password.clone(), true).unwrap(),
            password.canonical_password
        );
        assert_eq!(password.canonical_password.split_whitespace().count(), 8);
        assert_eq!(password.checksum.len(), 5);
    }

    #[test]
    fn custom_backup_password_policy_is_ascii_and_long_enough() {
        assert!(normalize_multisig_backup_password("short".to_string(), false).is_err());
        assert!(normalize_multisig_backup_password(
            "\u{be44}\u{bc00}\u{bc88}\u{d638}".to_string(),
            false
        )
        .is_err());
        assert_eq!(
            normalize_multisig_backup_password("  correct horse battery  ".to_string(), false)
                .unwrap(),
            "correct horse battery"
        );
    }

    #[test]
    fn refresh_resume_is_limited_to_unauthorized_status() {
        assert!(status_code_allows_resume(401));
        assert!(!status_code_allows_resume(400));
        assert!(!status_code_allows_resume(409));
        assert!(!status_code_allows_resume(429));
        assert!(!status_code_allows_resume(500));
        assert!(!status_code_allows_resume(503));
    }

    #[test]
    fn coordinator_status_errors_are_classified() {
        assert_eq!(
            classify_client_status(401),
            (ApiMultisigErrorKind::Unauthorized, true)
        );
        assert_eq!(
            classify_client_status(409),
            (ApiMultisigErrorKind::Conflict, true)
        );
        assert_eq!(
            classify_client_status(429),
            (ApiMultisigErrorKind::RateLimited, true)
        );
        assert_eq!(
            classify_client_status(503),
            (ApiMultisigErrorKind::Server, true)
        );
        assert_eq!(
            classify_client_status(403),
            (ApiMultisigErrorKind::Forbidden, false)
        );
    }

    #[test]
    fn structured_errors_preserve_status_and_retryability() {
        let raw = structured_multisig_error(
            ApiMultisigErrorKind::Unauthorized,
            "expired",
            Some(401),
            true,
        );
        let decoded: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(decoded["marker"], MULTISIG_ERROR_MARKER);
        assert_eq!(decoded["kind"], "unauthorized");
        assert_eq!(decoded["message"], "expired");
        assert_eq!(decoded["httpStatus"], 401);
        assert_eq!(decoded["retryable"], true);
    }

    #[test]
    fn share_backup_roundtrips_identity_and_material_without_mnemonic() {
        let temp_dir = tempfile::tempdir().unwrap();
        let params = ThresholdParams::new(2, 3).unwrap();
        let group = zcash_multisig::keys::gen_keys(params, temp_dir.path()).unwrap();
        let group_public_package_json = serde_json::to_string(&group).unwrap();
        let group_public_package_hash = hash_group_public_package(&group).unwrap();
        let identity = generate_multisig_participant_identity();
        let key_package_b64 = URL_SAFE_NO_PAD.encode([1, 2, 3, 4]);
        let passphrase = "correct horse battery".to_string();

        let artifact = create_multisig_share_backup(
            "regtest".to_string(),
            "sess-1".to_string(),
            "part-1".to_string(),
            2,
            3,
            "roster-hash".to_string(),
            identity.admission_secret_key.clone(),
            identity.delivery_secret_key.clone(),
            key_package_b64.clone(),
            group_public_package_json.clone(),
            passphrase.clone(),
        )
        .unwrap();

        let verified = verify_multisig_share_backup(
            "regtest".to_string(),
            artifact.artifact_json,
            passphrase,
            "sess-1".to_string(),
            "part-1".to_string(),
            2,
            3,
            "roster-hash".to_string(),
            group_public_package_hash.clone(),
        )
        .unwrap();

        assert_eq!(verified.backup_hash, artifact.backup_hash);
        assert_eq!(verified.vault_address, artifact.vault_address);
        assert_eq!(verified.admission_secret_key, identity.admission_secret_key);
        assert_eq!(verified.admission_public_key, identity.admission_public_key);
        assert_eq!(verified.delivery_secret_key, identity.delivery_secret_key);
        assert_eq!(verified.delivery_public_key, identity.delivery_public_key);
        assert_eq!(verified.key_package_b64, key_package_b64);
        assert_eq!(
            verified.group_public_package_json,
            group_public_package_json
        );
        assert_eq!(
            verified.group_public_package_hash,
            group_public_package_hash
        );
    }
}
