use diceware_wordlists::Wordlist;
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};
use zcash_multisig::types::ThresholdParams;
use zcash_multisig_sdk::{e2e::DeliveryKeypair, identity::AdmissionKey};

pub struct ApiMultisigBackupPassword {
    pub display_password: String,
    pub canonical_password: String,
    pub checksum: String,
}

pub struct ApiMultisigThresholdParams {
    pub threshold: u16,
    pub participant_count: u16,
}

pub struct ApiMultisigParticipantIdentity {
    pub admission_secret_key: String,
    pub admission_public_key: String,
    pub delivery_secret_key: String,
    pub delivery_public_key: String,
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
}
