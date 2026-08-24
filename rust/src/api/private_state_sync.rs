use std::panic;

use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

use crate::wallet::{keys, private_state_sync};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ApiPrivateStateObjectReference {
    pub protocol_version: u32,
    pub object_id: String,
    pub auth_public_key_base64: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ApiPrivateStateEnvelope {
    pub protocol_version: u32,
    pub object_id: String,
    pub auth_public_key_base64: String,
    pub revision: u64,
    pub previous_hash_base64: Option<String>,
    pub nonce_base64: String,
    pub ciphertext_base64: String,
    pub signature_base64: String,
    pub envelope_hash_base64: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ApiPrivateStateRequestAuthorization {
    pub protocol_version: u32,
    pub object_id: String,
    pub auth_public_key_base64: String,
    pub method: String,
    pub challenge_base64: String,
    pub audience: String,
    pub expires_at_seconds: u64,
    pub content_hash_base64: String,
    pub signature_base64: String,
}

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(error) => {
            let message = error
                .downcast_ref::<&str>()
                .map(|value| (*value).to_string())
                .or_else(|| error.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "Unknown panic".to_string());
            Err(format!("Rust panic: {message}"))
        }
    }
}

fn account_ufvk(
    db_path: &str,
    network: &str,
    account_uuid: &str,
) -> Result<Zeroizing<String>, String> {
    let parsed_network = keys::parse_network(network)?;
    keys::ensure_db_migrated_once(db_path, parsed_network)?;
    keys::get_account_ufvk(db_path, parsed_network, account_uuid).map(Zeroizing::new)
}

pub fn derive_private_state_object_reference(
    db_path: String,
    network: String,
    account_uuid: String,
    namespace: String,
    item_key: String,
) -> Result<ApiPrivateStateObjectReference, String> {
    catch(|| {
        let ufvk = account_ufvk(&db_path, &network, &account_uuid)?;
        private_state_sync::derive_object_reference(&ufvk, &network, &namespace, &item_key)
            .map(Into::into)
    })
}

pub fn seal_private_state_object(
    db_path: String,
    network: String,
    account_uuid: String,
    namespace: String,
    item_key: String,
    revision: u64,
    previous_hash_base64: Option<String>,
    plaintext: Vec<u8>,
) -> Result<ApiPrivateStateEnvelope, String> {
    catch(|| {
        let ufvk = account_ufvk(&db_path, &network, &account_uuid)?;
        private_state_sync::seal_object(
            &ufvk,
            &network,
            &namespace,
            &item_key,
            revision,
            previous_hash_base64.as_deref(),
            Zeroizing::new(plaintext),
        )
        .map(Into::into)
    })
}

pub fn open_private_state_object(
    db_path: String,
    network: String,
    account_uuid: String,
    namespace: String,
    item_key: String,
    envelope: ApiPrivateStateEnvelope,
) -> Result<Vec<u8>, String> {
    catch(|| {
        let ufvk = account_ufvk(&db_path, &network, &account_uuid)?;
        let envelope = private_state_sync::EncryptedObject::from(envelope);
        private_state_sync::open_object(&ufvk, &network, &namespace, &item_key, &envelope)
            .map(|plaintext| plaintext.to_vec())
    })
}

pub fn authorize_private_state_request(
    db_path: String,
    network: String,
    account_uuid: String,
    namespace: String,
    item_key: String,
    method: String,
    challenge_base64: String,
    audience: String,
    expires_at_seconds: u64,
    content_hash_base64: Option<String>,
) -> Result<ApiPrivateStateRequestAuthorization, String> {
    catch(|| {
        let ufvk = account_ufvk(&db_path, &network, &account_uuid)?;
        private_state_sync::authorize_request(
            &ufvk,
            &network,
            &namespace,
            &item_key,
            &method,
            &challenge_base64,
            &audience,
            expires_at_seconds,
            content_hash_base64.as_deref(),
        )
        .map(Into::into)
    })
}

impl From<private_state_sync::ObjectReference> for ApiPrivateStateObjectReference {
    fn from(value: private_state_sync::ObjectReference) -> Self {
        Self {
            protocol_version: value.protocol_version,
            object_id: value.object_id,
            auth_public_key_base64: value.auth_public_key_base64,
        }
    }
}

impl From<private_state_sync::EncryptedObject> for ApiPrivateStateEnvelope {
    fn from(value: private_state_sync::EncryptedObject) -> Self {
        Self {
            protocol_version: value.protocol_version,
            object_id: value.object_id,
            auth_public_key_base64: value.auth_public_key_base64,
            revision: value.revision,
            previous_hash_base64: value.previous_hash_base64,
            nonce_base64: value.nonce_base64,
            ciphertext_base64: value.ciphertext_base64,
            signature_base64: value.signature_base64,
            envelope_hash_base64: value.envelope_hash_base64,
        }
    }
}

impl From<ApiPrivateStateEnvelope> for private_state_sync::EncryptedObject {
    fn from(value: ApiPrivateStateEnvelope) -> Self {
        Self {
            protocol_version: value.protocol_version,
            object_id: value.object_id,
            auth_public_key_base64: value.auth_public_key_base64,
            revision: value.revision,
            previous_hash_base64: value.previous_hash_base64,
            nonce_base64: value.nonce_base64,
            ciphertext_base64: value.ciphertext_base64,
            signature_base64: value.signature_base64,
            envelope_hash_base64: value.envelope_hash_base64,
        }
    }
}

impl From<private_state_sync::RequestAuthorization> for ApiPrivateStateRequestAuthorization {
    fn from(value: private_state_sync::RequestAuthorization) -> Self {
        Self {
            protocol_version: value.protocol_version,
            object_id: value.object_id,
            auth_public_key_base64: value.auth_public_key_base64,
            method: value.method,
            challenge_base64: value.challenge_base64,
            audience: value.audience,
            expires_at_seconds: value.expires_at_seconds,
            content_hash_base64: value.content_hash_base64,
            signature_base64: value.signature_base64,
        }
    }
}
