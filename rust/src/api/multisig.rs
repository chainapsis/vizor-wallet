use std::future::Future;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use diceware_wordlists::Wordlist;
use rand::rngs::OsRng;
use rand::RngCore;
use serde::Serialize;
use sha2::{Digest, Sha256};
use zcash_multisig::{address::group_address_ua, keys::GroupPublicPackage, types::ThresholdParams};
use zcash_multisig_sdk::{
    backup::{
        decrypt_share_backup, encrypt_share_backup, EncryptedShareBackup, ShareBackupPlaintext,
    },
    client::{ClientError, Coordinator2Client},
    e2e::DeliveryKeypair,
    identity::AdmissionKey,
    types::{
        AdmissionAction, AdmissionChallengeReq, AuthRefreshReq, AuthSessionResp, AuthTokenResp,
        JoinSessionReq, LockSessionReq, ParticipantResp, SessionResp,
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
        let creator = admission.admission_request(
            AdmissionAction::CreateSession,
            &challenge,
            &delivery,
            clean_label(label),
        );
        let created = client
            .create_session(&zcash_multisig_sdk::types::CreateSessionReq { creator })
            .await
            .map_err(client_error)?;

        Ok(map_auth_session(created, identity))
    })
}

pub fn join_multisig_session(
    coordinator_url: String,
    session_id: String,
    admission_secret_key: String,
    delivery_secret_key: String,
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
        let participant = admission.admission_request(
            AdmissionAction::JoinSession {
                session_id: &session_id,
            },
            &challenge,
            &delivery,
            clean_label(label),
        );
        let joined = client
            .join_session(&session_id, &JoinSessionReq { participant })
            .await
            .map_err(client_error)?;

        Ok(map_auth_session(joined, identity))
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
) -> Result<ApiMultisigAuthSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let (admission, delivery, identity) =
            restore_participant_identity(admission_secret_key, delivery_secret_key)?;
        let resumed =
            resume_participant_auth_session(&client, session_id, &admission, &delivery).await?;

        Ok(map_auth_session(resumed, identity))
    })
}

pub fn get_multisig_session(
    coordinator_url: String,
    session_id: String,
    access_token: String,
) -> Result<ApiMultisigSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let session = client
            .get_session(&session_id, &access_token)
            .await
            .map_err(client_error)?;

        Ok(map_session(session))
    })
}

pub fn lock_multisig_session(
    coordinator_url: String,
    session_id: String,
    access_token: String,
    threshold: u16,
) -> Result<ApiMultisigSession, String> {
    block_on(async move {
        let client = Coordinator2Client::new(coordinator_url);
        let session = client
            .lock_session(&session_id, &access_token, &LockSessionReq { threshold })
            .await
            .map_err(client_error)?;

        Ok(map_session(session))
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
        participant: map_participant(value.participant),
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

fn map_session(value: SessionResp) -> ApiMultisigSession {
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
            .map(map_participant)
            .collect(),
        created_at: value.created_at,
        updated_at: value.updated_at,
    }
}

fn map_participant(value: ParticipantResp) -> ApiMultisigParticipant {
    ApiMultisigParticipant {
        participant_id: value.participant_id,
        label: value.label,
        admission_public_key: value.admission_public_key,
        delivery_public_key: value.delivery_public_key,
        joined_at: value.joined_at,
        dkg_completed: value.dkg_completed,
    }
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

fn hash_bytes_b64(value: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(value);
    URL_SAFE_NO_PAD.encode(h.finalize())
}

fn decode_b64(value: &str, label: &str) -> Result<Vec<u8>, String> {
    URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|e| format!("Invalid {label}: {e}"))
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
