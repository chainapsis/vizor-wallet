//! UFVK-derived cryptographic object primitives for private history sync.
//!
//! This module deliberately contains no transport or feature-specific schema.
//! The server can verify that the holder of an object's derived authentication
//! key authorized opaque bytes. Only a client with the UFVK can authenticate,
//! decrypt, and validate the plaintext document.

use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng, Payload},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

const PROTOCOL_VERSION: u32 = 1;
const ROOT_SALT: &[u8] = b"Vizor private state sync root v1";
const OBJECT_ID_DOMAIN: &[u8] = b"Vizor private state object ID v1";
const ENVELOPE_DOMAIN: &[u8] = b"Vizor private state envelope v1";
const REQUEST_DOMAIN: &[u8] = b"Vizor private state request v1";
const ENVELOPE_HASH_DOMAIN: &[u8] = b"Vizor private state envelope hash v1";
const SERVICE_REALM: &str = "vizor-private-state-sync";
const MAX_ITEM_KEY_BYTES: usize = 512;
const MAX_AUDIENCE_BYTES: usize = 512;
const MAX_PLAINTEXT_BYTES: usize = 256 * 1024;
const MIN_CHALLENGE_BYTES: usize = 16;
const MAX_CHALLENGE_BYTES: usize = 128;
const SHA256_LEN: usize = 32;
const AES_NONCE_LEN: usize = 12;
const AES_GCM_TAG_LEN: usize = 16;
const ED25519_PUBLIC_KEY_LEN: usize = 32;
const ED25519_SIGNATURE_LEN: usize = 64;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ObjectReference {
    pub protocol_version: u32,
    pub object_id: String,
    pub auth_public_key_base64: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct EncryptedObject {
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RequestAuthorization {
    pub protocol_version: u32,
    pub object_id: String,
    pub auth_public_key_base64: String,
    pub method: String,
    pub challenge_base64: String,
    pub audience: String,
    pub expires_at_seconds: u64,
    /// Hash of the canonical request content. For PUT this is the signed
    /// envelope hash; GET and DELETE use SHA-256 of the empty byte string.
    pub content_hash_base64: String,
    pub signature_base64: String,
}

struct ObjectKeys {
    encryption_key: Zeroizing<[u8; 32]>,
    signing_key: SigningKey,
}

struct VerifiedEnvelope {
    reference: ObjectReference,
    previous_hash: Option<Vec<u8>>,
    nonce: Vec<u8>,
    ciphertext: Vec<u8>,
}

impl ObjectKeys {
    fn derive(ufvk: &str, network: &str, namespace: &str, item_key: &str) -> Result<Self, String> {
        validate_context(ufvk, network, namespace, item_key)?;
        let hkdf = Hkdf::<Sha256>::new(Some(ROOT_SALT), ufvk.as_bytes());
        let context = object_context(network, namespace, item_key)?;

        let mut encryption_key = Zeroizing::new([0u8; 32]);
        hkdf.expand(&role_info(b"encryption", &context), encryption_key.as_mut())
            .map_err(|_| "Failed to derive private-state encryption key".to_string())?;

        let mut signing_seed = Zeroizing::new([0u8; 32]);
        hkdf.expand(
            &role_info(b"authentication", &context),
            signing_seed.as_mut(),
        )
        .map_err(|_| "Failed to derive private-state authentication key".to_string())?;
        let signing_key = SigningKey::from_bytes(&signing_seed);

        Ok(Self {
            encryption_key,
            signing_key,
        })
    }

    fn reference(&self) -> ObjectReference {
        let public_key = self.signing_key.verifying_key().to_bytes();
        let mut hasher = Sha256::new();
        hasher.update(OBJECT_ID_DOMAIN);
        hasher.update(public_key);
        ObjectReference {
            protocol_version: PROTOCOL_VERSION,
            object_id: URL_SAFE_NO_PAD.encode(hasher.finalize()),
            auth_public_key_base64: URL_SAFE_NO_PAD.encode(public_key),
        }
    }
}

pub fn derive_object_reference(
    ufvk: &str,
    network: &str,
    namespace: &str,
    item_key: &str,
) -> Result<ObjectReference, String> {
    Ok(ObjectKeys::derive(ufvk, network, namespace, item_key)?.reference())
}

/// Validates that an opaque object ID is the self-certifying identifier for
/// the supplied authentication public key.
pub fn verify_object_reference(reference: &ObjectReference) -> Result<(), String> {
    if reference.protocol_version != PROTOCOL_VERSION {
        return Err("Unsupported private-state object version".to_string());
    }
    let public_key_bytes = decode_exact(
        &reference.auth_public_key_base64,
        ED25519_PUBLIC_KEY_LEN,
        "public key",
    )?;
    let public_key: [u8; ED25519_PUBLIC_KEY_LEN] = public_key_bytes
        .try_into()
        .map_err(|_| "Invalid private-state public key".to_string())?;
    VerifyingKey::from_bytes(&public_key)
        .map_err(|_| "Invalid private-state public key".to_string())?;
    if reference.object_id != reference_from_public_key(public_key).object_id {
        return Err("Private-state object ID does not match public key".to_string());
    }
    Ok(())
}

pub fn seal_object(
    ufvk: &str,
    network: &str,
    namespace: &str,
    item_key: &str,
    revision: u64,
    previous_hash_base64: Option<&str>,
    plaintext: Zeroizing<Vec<u8>>,
) -> Result<EncryptedObject, String> {
    validate_revision(revision, previous_hash_base64)?;
    if plaintext.len() > MAX_PLAINTEXT_BYTES {
        return Err(format!(
            "Private-state plaintext exceeds {MAX_PLAINTEXT_BYTES} bytes"
        ));
    }
    let keys = ObjectKeys::derive(ufvk, network, namespace, item_key)?;
    let reference = keys.reference();
    let previous_hash = decode_optional_hash(previous_hash_base64)?;
    let aad = envelope_aad(&reference, revision, previous_hash.as_deref());
    let cipher = Aes256Gcm::new_from_slice(keys.encryption_key.as_slice())
        .map_err(|_| "Failed to initialize private-state cipher".to_string())?;
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(
            &nonce,
            Payload {
                msg: plaintext.as_slice(),
                aad: &aad,
            },
        )
        .map_err(|_| "Failed to encrypt private-state object".to_string())?;
    drop(plaintext);

    let unsigned = canonical_envelope(
        &reference,
        revision,
        previous_hash.as_deref(),
        nonce.as_slice(),
        &ciphertext,
    );
    let signature = keys.signing_key.sign(&unsigned).to_bytes();
    let envelope_hash = hash_signed_envelope(&unsigned, &signature);
    Ok(EncryptedObject {
        protocol_version: PROTOCOL_VERSION,
        object_id: reference.object_id,
        auth_public_key_base64: reference.auth_public_key_base64,
        revision,
        previous_hash_base64: previous_hash.map(|value| URL_SAFE_NO_PAD.encode(value)),
        nonce_base64: URL_SAFE_NO_PAD.encode(nonce),
        ciphertext_base64: URL_SAFE_NO_PAD.encode(ciphertext),
        signature_base64: URL_SAFE_NO_PAD.encode(signature),
        envelope_hash_base64: URL_SAFE_NO_PAD.encode(envelope_hash),
    })
}

pub fn open_object(
    ufvk: &str,
    network: &str,
    namespace: &str,
    item_key: &str,
    envelope: &EncryptedObject,
) -> Result<Zeroizing<Vec<u8>>, String> {
    let verified = verify_encrypted_object_inner(envelope)?;
    let keys = ObjectKeys::derive(ufvk, network, namespace, item_key)?;
    let expected_reference = keys.reference();
    if verified.reference != expected_reference {
        return Err("Private-state object does not belong to the requested key".to_string());
    }

    let aad = envelope_aad(
        &expected_reference,
        envelope.revision,
        verified.previous_hash.as_deref(),
    );
    let cipher = Aes256Gcm::new_from_slice(keys.encryption_key.as_slice())
        .map_err(|_| "Failed to initialize private-state cipher".to_string())?;
    cipher
        .decrypt(
            Nonce::from_slice(&verified.nonce),
            Payload {
                msg: &verified.ciphertext,
                aad: &aad,
            },
        )
        .map(Zeroizing::new)
        .map_err(|_| "Private-state object authentication failed".to_string())
}

/// Verifies the self-certifying object ID, public key, envelope signature,
/// revision shape, and envelope hash without possessing the UFVK or decrypting
/// the ciphertext. This proves owner authorization of opaque bytes, not that
/// the bytes decrypt to a meaningful document.
pub fn verify_encrypted_object(envelope: &EncryptedObject) -> Result<(), String> {
    verify_encrypted_object_inner(envelope).map(|_| ())
}

/// Server-side verification for one PUT request.
///
/// Challenge freshness, single-use, expiry relative to the server clock, and
/// expected audience are deployment state and must be checked by the caller.
pub fn verify_authorized_put(
    envelope: &EncryptedObject,
    authorization: &RequestAuthorization,
) -> Result<(), String> {
    verify_encrypted_object(envelope)?;
    verify_request_authorization(authorization)?;
    if authorization.method != "PUT"
        || authorization.object_id != envelope.object_id
        || authorization.auth_public_key_base64 != envelope.auth_public_key_base64
        || authorization.content_hash_base64 != envelope.envelope_hash_base64
    {
        return Err("Private-state PUT authorization does not match envelope".to_string());
    }
    Ok(())
}

/// Server-side verification for an atomic PUT transition.
///
/// The caller must read [current] and write [envelope] in the same atomic CAS
/// transaction. Verifying only the request signature and an independently
/// supplied CAS precondition is insufficient: an attacker could replay an old,
/// validly signed envelope while replacing that unsigned precondition with the
/// latest stored version.
pub fn verify_authorized_put_transition(
    envelope: &EncryptedObject,
    authorization: &RequestAuthorization,
    current: Option<&EncryptedObject>,
) -> Result<(), String> {
    verify_authorized_put(envelope, authorization)?;
    match current {
        None => {
            if envelope.revision != 1 || envelope.previous_hash_base64.is_some() {
                return Err("Private-state object creation must start at revision 1".to_string());
            }
        }
        Some(current) => {
            verify_encrypted_object(current)?;
            if current.object_id != envelope.object_id
                || current.auth_public_key_base64 != envelope.auth_public_key_base64
            {
                return Err("Private-state PUT does not continue the stored object".to_string());
            }
            let next_revision = current
                .revision
                .checked_add(1)
                .ok_or_else(|| "Private-state revision overflow".to_string())?;
            if envelope.revision != next_revision
                || envelope.previous_hash_base64.as_deref()
                    != Some(current.envelope_hash_base64.as_str())
            {
                return Err(
                    "Private-state PUT is not the direct successor of the stored object"
                        .to_string(),
                );
            }
        }
    }
    Ok(())
}

fn verify_encrypted_object_inner(envelope: &EncryptedObject) -> Result<VerifiedEnvelope, String> {
    if envelope.protocol_version != PROTOCOL_VERSION {
        return Err(format!(
            "Unsupported private-state protocol version: {}",
            envelope.protocol_version
        ));
    }
    validate_revision(envelope.revision, envelope.previous_hash_base64.as_deref())?;
    let public_key_bytes = decode_exact(
        &envelope.auth_public_key_base64,
        ED25519_PUBLIC_KEY_LEN,
        "public key",
    )?;
    let public_key_array: [u8; ED25519_PUBLIC_KEY_LEN] = public_key_bytes
        .try_into()
        .map_err(|_| "Invalid private-state public key".to_string())?;
    let verifying_key = VerifyingKey::from_bytes(&public_key_array)
        .map_err(|_| "Invalid private-state public key".to_string())?;
    let reference = reference_from_public_key(public_key_array);
    if envelope.object_id != reference.object_id
        || envelope.auth_public_key_base64 != reference.auth_public_key_base64
    {
        return Err("Private-state object ID does not match public key".to_string());
    }

    let previous_hash = decode_optional_hash(envelope.previous_hash_base64.as_deref())?;
    let nonce = decode_exact(&envelope.nonce_base64, AES_NONCE_LEN, "nonce")?;
    let ciphertext = decode_bounded(
        &envelope.ciphertext_base64,
        MAX_PLAINTEXT_BYTES + AES_GCM_TAG_LEN,
        "ciphertext",
    )?;
    if ciphertext.len() < AES_GCM_TAG_LEN {
        return Err(format!(
            "Private-state ciphertext must include a {AES_GCM_TAG_LEN}-byte authentication tag"
        ));
    }
    let signature_bytes = decode_exact(
        &envelope.signature_base64,
        ED25519_SIGNATURE_LEN,
        "signature",
    )?;
    let supplied_hash = decode_exact(&envelope.envelope_hash_base64, SHA256_LEN, "envelope hash")?;
    let unsigned = canonical_envelope(
        &reference,
        envelope.revision,
        previous_hash.as_deref(),
        &nonce,
        &ciphertext,
    );
    let signature = Signature::from_slice(&signature_bytes)
        .map_err(|_| "Invalid private-state signature encoding".to_string())?;
    verifying_key
        .verify(&unsigned, &signature)
        .map_err(|_| "Private-state envelope signature verification failed".to_string())?;
    let expected_hash = hash_signed_envelope(&unsigned, &signature_bytes);
    if supplied_hash.as_slice() != expected_hash {
        return Err("Private-state envelope hash mismatch".to_string());
    }
    Ok(VerifiedEnvelope {
        reference,
        previous_hash,
        nonce,
        ciphertext,
    })
}

pub fn authorize_request(
    ufvk: &str,
    network: &str,
    namespace: &str,
    item_key: &str,
    method: &str,
    challenge_base64: &str,
    audience: &str,
    expires_at_seconds: u64,
    content_hash_base64: Option<&str>,
) -> Result<RequestAuthorization, String> {
    let method = validate_method(method)?;
    validate_audience(audience)?;
    if expires_at_seconds == 0 {
        return Err("Private-state request expiry must be nonzero".to_string());
    }
    let challenge = decode_bounded(challenge_base64, MAX_CHALLENGE_BYTES, "challenge")?;
    if challenge.len() < MIN_CHALLENGE_BYTES {
        return Err(format!(
            "Private-state challenge must be at least {MIN_CHALLENGE_BYTES} bytes"
        ));
    }
    let content_hash = match (method, content_hash_base64) {
        ("PUT", Some(value)) => decode_exact(value, SHA256_LEN, "content hash")?,
        ("PUT", None) => {
            return Err("Private-state PUT authorization requires an envelope hash".to_string())
        }
        ("GET" | "DELETE", Some(_)) => {
            return Err(format!(
                "Private-state {method} authorization must not include a content hash"
            ))
        }
        ("GET" | "DELETE", None) => Sha256::digest([]).to_vec(),
        _ => unreachable!("method was validated"),
    };
    let keys = ObjectKeys::derive(ufvk, network, namespace, item_key)?;
    let reference = keys.reference();
    let signed = canonical_request(
        &reference,
        method,
        &challenge,
        audience,
        expires_at_seconds,
        &content_hash,
    );
    let signature = keys.signing_key.sign(&signed).to_bytes();
    Ok(RequestAuthorization {
        protocol_version: PROTOCOL_VERSION,
        object_id: reference.object_id,
        auth_public_key_base64: reference.auth_public_key_base64,
        method: method.to_string(),
        challenge_base64: URL_SAFE_NO_PAD.encode(challenge),
        audience: audience.to_string(),
        expires_at_seconds,
        content_hash_base64: URL_SAFE_NO_PAD.encode(content_hash),
        signature_base64: URL_SAFE_NO_PAD.encode(signature),
    })
}

/// Server-side verification primitive. It proves authorization of opaque
/// bytes, not that those bytes decrypt to a meaningful document.
pub fn verify_request_authorization(authorization: &RequestAuthorization) -> Result<(), String> {
    if authorization.protocol_version != PROTOCOL_VERSION {
        return Err("Unsupported private-state request version".to_string());
    }
    let method = validate_method(&authorization.method)?;
    validate_audience(&authorization.audience)?;
    if authorization.expires_at_seconds == 0 {
        return Err("Private-state request expiry must be nonzero".to_string());
    }
    let public_key_bytes = decode_exact(
        &authorization.auth_public_key_base64,
        ED25519_PUBLIC_KEY_LEN,
        "public key",
    )?;
    let public_key_array: [u8; ED25519_PUBLIC_KEY_LEN] = public_key_bytes
        .try_into()
        .map_err(|_| "Invalid private-state public key".to_string())?;
    let verifying_key = VerifyingKey::from_bytes(&public_key_array)
        .map_err(|_| "Invalid private-state public key".to_string())?;
    let expected_reference = reference_from_public_key(public_key_array);
    if authorization.object_id != expected_reference.object_id {
        return Err("Private-state object ID does not match public key".to_string());
    }
    let challenge = decode_bounded(
        &authorization.challenge_base64,
        MAX_CHALLENGE_BYTES,
        "challenge",
    )?;
    if challenge.len() < MIN_CHALLENGE_BYTES {
        return Err("Private-state challenge is too short".to_string());
    }
    let content_hash = decode_exact(
        &authorization.content_hash_base64,
        SHA256_LEN,
        "content hash",
    )?;
    let signature_bytes = decode_exact(
        &authorization.signature_base64,
        ED25519_SIGNATURE_LEN,
        "signature",
    )?;
    let signature = Signature::from_slice(&signature_bytes)
        .map_err(|_| "Invalid private-state request signature".to_string())?;
    let signed = canonical_request(
        &expected_reference,
        method,
        &challenge,
        &authorization.audience,
        authorization.expires_at_seconds,
        &content_hash,
    );
    verifying_key
        .verify(&signed, &signature)
        .map_err(|_| "Private-state request signature verification failed".to_string())
}

fn reference_from_public_key(public_key: [u8; ED25519_PUBLIC_KEY_LEN]) -> ObjectReference {
    let mut hasher = Sha256::new();
    hasher.update(OBJECT_ID_DOMAIN);
    hasher.update(public_key);
    ObjectReference {
        protocol_version: PROTOCOL_VERSION,
        object_id: URL_SAFE_NO_PAD.encode(hasher.finalize()),
        auth_public_key_base64: URL_SAFE_NO_PAD.encode(public_key),
    }
}

fn validate_context(
    ufvk: &str,
    network: &str,
    namespace: &str,
    item_key: &str,
) -> Result<(), String> {
    if ufvk.is_empty() {
        return Err("UFVK must not be empty".to_string());
    }
    if !matches!(network, "main" | "test" | "regtest") {
        return Err(format!("Unsupported private-state network: {network}"));
    }
    if !matches!(
        namespace,
        "voting-completion" | "swap-history" | "pay-history"
    ) {
        return Err(format!("Unsupported private-state namespace: {namespace}"));
    }
    if item_key.is_empty() || item_key.len() > MAX_ITEM_KEY_BYTES {
        return Err(format!(
            "Private-state item key must contain 1 to {MAX_ITEM_KEY_BYTES} UTF-8 bytes"
        ));
    }
    Ok(())
}

fn validate_revision(revision: u64, previous_hash: Option<&str>) -> Result<(), String> {
    match (revision, previous_hash) {
        (0, _) => Err("Private-state revision must start at 1".to_string()),
        (1, None) => Ok(()),
        (1, Some(_)) => Err("Private-state revision 1 must not have a previous hash".to_string()),
        (_, Some(_)) => Ok(()),
        (_, None) => Err("Private-state revisions after 1 require a previous hash".to_string()),
    }
}

fn validate_method(method: &str) -> Result<&str, String> {
    match method {
        "GET" | "PUT" | "DELETE" => Ok(method),
        _ => Err(format!("Unsupported private-state method: {method}")),
    }
}

fn validate_audience(audience: &str) -> Result<(), String> {
    if audience.is_empty() || audience.len() > MAX_AUDIENCE_BYTES {
        return Err(format!(
            "Private-state audience must contain 1 to {MAX_AUDIENCE_BYTES} UTF-8 bytes"
        ));
    }
    Ok(())
}

fn object_context(network: &str, namespace: &str, item_key: &str) -> Result<Vec<u8>, String> {
    let mut encoded = Vec::new();
    push_u32(&mut encoded, PROTOCOL_VERSION);
    push_string(&mut encoded, SERVICE_REALM)?;
    push_string(&mut encoded, network)?;
    push_string(&mut encoded, namespace)?;
    push_string(&mut encoded, item_key)?;
    Ok(encoded)
}

fn role_info(role: &[u8], context: &[u8]) -> Vec<u8> {
    let mut info = Vec::with_capacity(role.len() + context.len() + 8);
    push_bytes(&mut info, role).expect("role labels fit in u32");
    info.extend_from_slice(context);
    info
}

fn envelope_aad(
    reference: &ObjectReference,
    revision: u64,
    previous_hash: Option<&[u8]>,
) -> Vec<u8> {
    let mut encoded = Vec::new();
    encoded.extend_from_slice(ENVELOPE_DOMAIN);
    push_u32(&mut encoded, PROTOCOL_VERSION);
    push_string(&mut encoded, &reference.object_id).expect("object ID length is bounded");
    push_u64(&mut encoded, revision);
    push_optional_bytes(&mut encoded, previous_hash).expect("hash length is bounded");
    encoded
}

fn canonical_envelope(
    reference: &ObjectReference,
    revision: u64,
    previous_hash: Option<&[u8]>,
    nonce: &[u8],
    ciphertext: &[u8],
) -> Vec<u8> {
    let mut encoded = envelope_aad(reference, revision, previous_hash);
    push_string(&mut encoded, &reference.auth_public_key_base64)
        .expect("public key length is bounded");
    push_bytes(&mut encoded, nonce).expect("nonce length is bounded");
    push_bytes(&mut encoded, ciphertext).expect("ciphertext size is bounded");
    encoded
}

fn hash_signed_envelope(unsigned: &[u8], signature: &[u8]) -> [u8; SHA256_LEN] {
    let mut hasher = Sha256::new();
    hasher.update(ENVELOPE_HASH_DOMAIN);
    hasher.update(unsigned);
    hasher.update(signature);
    hasher.finalize().into()
}

fn canonical_request(
    reference: &ObjectReference,
    method: &str,
    challenge: &[u8],
    audience: &str,
    expires_at_seconds: u64,
    content_hash: &[u8],
) -> Vec<u8> {
    let mut encoded = Vec::new();
    encoded.extend_from_slice(REQUEST_DOMAIN);
    push_u32(&mut encoded, PROTOCOL_VERSION);
    push_string(&mut encoded, method).expect("method length is bounded");
    push_string(&mut encoded, &reference.object_id).expect("object ID length is bounded");
    push_bytes(&mut encoded, challenge).expect("challenge length is bounded");
    push_string(&mut encoded, audience).expect("audience length was validated");
    push_u64(&mut encoded, expires_at_seconds);
    push_bytes(&mut encoded, content_hash).expect("content hash length is bounded");
    encoded
}

fn decode_optional_hash(value: Option<&str>) -> Result<Option<Vec<u8>>, String> {
    value
        .map(|encoded| decode_exact(encoded, SHA256_LEN, "previous hash"))
        .transpose()
}

fn decode_exact(value: &str, expected: usize, label: &str) -> Result<Vec<u8>, String> {
    let expected_encoded = base64url_unpadded_len(expected)?;
    if value.len() != expected_encoded {
        return Err(format!(
            "Invalid private-state {label} encoded length: expected {expected_encoded}, got {}",
            value.len()
        ));
    }
    let decoded = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| format!("Invalid private-state {label} base64url"))?;
    if decoded.len() != expected {
        return Err(format!(
            "Invalid private-state {label} length: expected {expected}, got {}",
            decoded.len()
        ));
    }
    Ok(decoded)
}

fn decode_bounded(value: &str, max: usize, label: &str) -> Result<Vec<u8>, String> {
    let max_encoded = base64url_unpadded_len(max)?;
    if value.len() > max_encoded {
        return Err(format!(
            "Private-state {label} encoded value exceeds {max_encoded} bytes"
        ));
    }
    let decoded = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| format!("Invalid private-state {label} base64url"))?;
    if decoded.len() > max {
        return Err(format!("Private-state {label} exceeds {max} bytes"));
    }
    Ok(decoded)
}

fn base64url_unpadded_len(decoded_len: usize) -> Result<usize, String> {
    decoded_len
        .checked_mul(4)
        .and_then(|value| value.checked_add(2))
        .map(|value| value / 3)
        .ok_or_else(|| "Private-state base64url length overflow".to_string())
}

fn push_string(target: &mut Vec<u8>, value: &str) -> Result<(), String> {
    push_bytes(target, value.as_bytes())
}

fn push_bytes(target: &mut Vec<u8>, value: &[u8]) -> Result<(), String> {
    let length = u32::try_from(value.len())
        .map_err(|_| "Private-state canonical field is too large".to_string())?;
    push_u32(target, length);
    target.extend_from_slice(value);
    Ok(())
}

fn push_optional_bytes(target: &mut Vec<u8>, value: Option<&[u8]>) -> Result<(), String> {
    match value {
        Some(bytes) => {
            target.push(1);
            push_bytes(target, bytes)
        }
        None => {
            target.push(0);
            Ok(())
        }
    }
}

fn push_u32(target: &mut Vec<u8>, value: u32) {
    target.extend_from_slice(&value.to_be_bytes());
}

fn push_u64(target: &mut Vec<u8>, value: u64) {
    target.extend_from_slice(&value.to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    const UFVK: &str = "uview-test-vector-not-a-real-exported-key";
    const NETWORK: &str = "main";
    const NAMESPACE: &str = "voting-completion";
    const ITEM: &str = "round-42";

    #[test]
    fn object_reference_is_deterministic_and_domain_separated() {
        let reference = derive_object_reference(UFVK, NETWORK, NAMESPACE, ITEM).unwrap();
        let same = derive_object_reference(UFVK, NETWORK, NAMESPACE, ITEM).unwrap();
        let other_item = derive_object_reference(UFVK, NETWORK, NAMESPACE, "round-43").unwrap();
        let other_namespace = derive_object_reference(UFVK, NETWORK, "swap-history", ITEM).unwrap();
        let other_network = derive_object_reference(UFVK, "test", NAMESPACE, ITEM).unwrap();

        assert_eq!(reference, same);
        // Protocol compatibility vector. Changing either value makes existing
        // remote objects undiscoverable and requires a versioned migration.
        assert_eq!(
            reference.object_id,
            "X9KDVZLSoTGKVU6DmKJZS3pL_r7nlxXKTOxtGAbPU54"
        );
        assert_eq!(
            reference.auth_public_key_base64,
            "XtqGRxVAxCuQE8ceBi_W1MZjTRhPLDCPgzZOWdqO1l0"
        );
        assert_ne!(reference.object_id, other_item.object_id);
        assert_ne!(reference.object_id, other_namespace.object_id);
        assert_ne!(reference.object_id, other_network.object_id);
        verify_object_reference(&reference).unwrap();

        let mut tampered = reference;
        tampered.object_id = URL_SAFE_NO_PAD.encode([0u8; 32]);
        assert!(verify_object_reference(&tampered).is_err());
    }

    #[test]
    fn envelope_round_trip_binds_revision_and_object_key() {
        let clear = b"{\"completed\":true,\"choice\":1}".to_vec();
        let envelope = seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            1,
            None,
            Zeroizing::new(clear.clone()),
        )
        .unwrap();

        assert_eq!(
            open_object(UFVK, NETWORK, NAMESPACE, ITEM, &envelope)
                .unwrap()
                .as_slice(),
            clear
        );
        assert!(open_object(UFVK, NETWORK, NAMESPACE, "round-43", &envelope).is_err());

        let mut changed_revision = envelope.clone();
        changed_revision.revision = 2;
        changed_revision.previous_hash_base64 = Some(URL_SAFE_NO_PAD.encode([7u8; 32]));
        assert!(open_object(UFVK, NETWORK, NAMESPACE, ITEM, &changed_revision).is_err());
    }

    #[test]
    fn envelope_rejects_tampering_and_chains_revisions() {
        let first = seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            1,
            None,
            Zeroizing::new(b"first".to_vec()),
        )
        .unwrap();
        let second = seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            2,
            Some(&first.envelope_hash_base64),
            Zeroizing::new(b"second".to_vec()),
        )
        .unwrap();
        assert_eq!(
            open_object(UFVK, NETWORK, NAMESPACE, ITEM, &second)
                .unwrap()
                .as_slice(),
            b"second"
        );

        let mut tampered = second;
        tampered.ciphertext_base64 = URL_SAFE_NO_PAD.encode(b"not ciphertext");
        assert!(open_object(UFVK, NETWORK, NAMESPACE, ITEM, &tampered).is_err());
    }

    #[test]
    fn server_verifies_authorized_ciphertext_without_ufvk() {
        let envelope = seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            1,
            None,
            Zeroizing::new(b"opaque payload".to_vec()),
        )
        .unwrap();
        let authorization = authorize_request(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            "PUT",
            &URL_SAFE_NO_PAD.encode([9u8; 32]),
            "https://sync.vizor.example/v1",
            1_800_000_000,
            Some(&envelope.envelope_hash_base64),
        )
        .unwrap();

        verify_authorized_put(&envelope, &authorization).unwrap();

        let mut mismatched = authorization;
        mismatched.content_hash_base64 = URL_SAFE_NO_PAD.encode([4u8; 32]);
        assert!(verify_authorized_put(&envelope, &mismatched).is_err());

        let mut impossible = envelope;
        impossible.ciphertext_base64 = String::new();
        let error = verify_encrypted_object(&impossible).unwrap_err();
        assert!(error.contains("authentication tag"));
    }

    #[test]
    fn server_rejects_signed_rollback_replay_and_non_successor_creation() {
        let first = seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            1,
            None,
            Zeroizing::new(b"first".to_vec()),
        )
        .unwrap();
        let second = seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            2,
            Some(&first.envelope_hash_base64),
            Zeroizing::new(b"second".to_vec()),
        )
        .unwrap();
        let third = seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            3,
            Some(&second.envelope_hash_base64),
            Zeroizing::new(b"third".to_vec()),
        )
        .unwrap();
        let authorize = |envelope: &EncryptedObject| {
            authorize_request(
                UFVK,
                NETWORK,
                NAMESPACE,
                ITEM,
                "PUT",
                &URL_SAFE_NO_PAD.encode([9u8; 32]),
                "https://sync.vizor.example/v1",
                1_800_000_000,
                Some(&envelope.envelope_hash_base64),
            )
            .unwrap()
        };

        verify_authorized_put_transition(&first, &authorize(&first), None).unwrap();
        verify_authorized_put_transition(&second, &authorize(&second), Some(&first)).unwrap();
        verify_authorized_put_transition(&third, &authorize(&third), Some(&second)).unwrap();

        assert!(
            verify_authorized_put_transition(&second, &authorize(&second), Some(&third)).is_err()
        );
        assert!(verify_authorized_put_transition(&second, &authorize(&second), None).is_err());
    }

    #[test]
    fn request_authorization_is_self_certifying_and_binds_fields() {
        let challenge = URL_SAFE_NO_PAD.encode([9u8; 32]);
        let content_hash = URL_SAFE_NO_PAD.encode([3u8; 32]);
        let authorization = authorize_request(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            "PUT",
            &challenge,
            "https://sync.vizor.example/v1",
            1_800_000_000,
            Some(&content_hash),
        )
        .unwrap();
        verify_request_authorization(&authorization).unwrap();

        let mut tampered = authorization.clone();
        tampered.method = "GET".to_string();
        assert!(verify_request_authorization(&tampered).is_err());

        let mut tampered = authorization;
        tampered.object_id = URL_SAFE_NO_PAD.encode([0u8; 32]);
        assert!(verify_request_authorization(&tampered).is_err());
    }

    #[test]
    fn revision_invariants_are_enforced() {
        let clear = || Zeroizing::new(b"payload".to_vec());
        assert!(seal_object(UFVK, NETWORK, NAMESPACE, ITEM, 0, None, clear()).is_err());
        assert!(seal_object(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            1,
            Some(&URL_SAFE_NO_PAD.encode([0u8; 32])),
            clear(),
        )
        .is_err());
        assert!(seal_object(UFVK, NETWORK, NAMESPACE, ITEM, 2, None, clear()).is_err());
    }

    #[test]
    fn put_authorization_requires_content_hash() {
        let challenge = URL_SAFE_NO_PAD.encode([9u8; 32]);
        assert!(authorize_request(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            "PUT",
            &challenge,
            "https://sync.vizor.example/v1",
            1_800_000_000,
            None,
        )
        .is_err());
        assert!(authorize_request(
            UFVK,
            NETWORK,
            NAMESPACE,
            ITEM,
            "GET",
            &challenge,
            "https://sync.vizor.example/v1",
            1_800_000_000,
            Some(&URL_SAFE_NO_PAD.encode([3u8; 32])),
        )
        .is_err());
    }

    #[test]
    fn oversized_base64_is_rejected_before_decode() {
        let oversized = "A".repeat(base64url_unpadded_len(32).unwrap() + 1);
        let error = decode_exact(&oversized, 32, "test value").unwrap_err();
        assert!(error.contains("encoded length"));

        let oversized = "A".repeat(base64url_unpadded_len(64).unwrap() + 1);
        let error = decode_bounded(&oversized, 64, "test value").unwrap_err();
        assert!(error.contains("encoded value exceeds"));
    }
}
