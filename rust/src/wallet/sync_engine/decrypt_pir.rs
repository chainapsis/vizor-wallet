use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use chacha20::{
    ChaCha20,
    cipher::{KeyIvInit, StreamCipher, StreamCipherSeek},
};
use zcash_client_backend::data_api::{TransactionStatus, WalletRead, WalletWrite};
use zcash_note_encryption::{Domain as NoteEncryptionDomain, EphemeralKeyBytes};
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;
use zip32::Scope;

use super::{SyncError, WalletDatabase};

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct ReducedOrchardCompactAction {
    pub(super) nf: [u8; 32],
    pub(super) ephemeral_key: [u8; 32],
    pub(super) ciphertext: [u8; 52],
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct OrchardCompactActionDecryption<AccountId> {
    account_id: AccountId,
    action_index: usize,
    note: orchard::Note,
    recipient: orchard::Address,
    cmx: orchard::note::ExtractedNoteCommitment,
}

#[derive(Clone, Debug)]
pub(super) struct PirOrchardCompactAction {
    pub(super) nf: [u8; 32],
    pub(super) ephemeral_key: [u8; 32],
    pub(super) ciphertext: [u8; 52],
}

#[derive(Clone, Debug)]
pub(super) struct PirEnhancementPayload {
    pub(super) mined_height: BlockHeight,
    pub(super) actions: Vec<PirOrchardCompactAction>,
}

#[cfg(test)]
fn test_pir_payload_map() -> &'static Mutex<HashMap<[u8; 32], PirEnhancementPayload>> {
    static MAP: OnceLock<Mutex<HashMap<[u8; 32], PirEnhancementPayload>>> = OnceLock::new();
    MAP.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(test)]
fn set_test_pir_payload(txid: TxId, payload: PirEnhancementPayload) {
    if let Ok(mut map) = test_pir_payload_map().lock() {
        map.insert(*txid.as_ref(), payload);
    }
}

#[cfg(test)]
fn clear_test_pir_payloads() {
    if let Ok(mut map) = test_pir_payload_map().lock() {
        map.clear();
    }
}

fn lookup_pir_payload(txid: TxId) -> Option<PirEnhancementPayload> {
    #[cfg(test)]
    {
        if let Ok(mut map) = test_pir_payload_map().lock() {
            return map.remove(txid.as_ref());
        }
    }

    None
}

fn decrypt_orchard_compact_actions_without_cmx<DbT>(
    data: &DbT,
    actions: &[ReducedOrchardCompactAction],
) -> Result<Vec<OrchardCompactActionDecryption<DbT::AccountId>>, DbT::Error>
where
    DbT: WalletRead,
    DbT::AccountId: Copy + Ord,
{
    let ufvks = data.get_unified_full_viewing_keys()?;
    let mut matches = Vec::new();

    for (action_index, action) in actions.iter().enumerate() {
        for (account, ufvk) in &ufvks {
            let Some(fvk) = ufvk.orchard() else {
                continue;
            };

            let ivk_external =
                orchard::keys::PreparedIncomingViewingKey::new(&fvk.to_ivk(Scope::External));
            let ivk_internal =
                orchard::keys::PreparedIncomingViewingKey::new(&fvk.to_ivk(Scope::Internal));

            let decrypted = try_orchard_compact_note_decryption_without_cmx(action, &ivk_external)
                .or_else(|| try_orchard_compact_note_decryption_without_cmx(action, &ivk_internal));

            if let Some((note, recipient)) = decrypted {
                matches.push(OrchardCompactActionDecryption {
                    account_id: *account,
                    action_index,
                    cmx: note.commitment().into(),
                    note,
                    recipient,
                });
                break;
            }
        }
    }

    Ok(matches)
}

fn try_orchard_compact_note_decryption_without_cmx(
    action: &ReducedOrchardCompactAction,
    ivk: &orchard::keys::PreparedIncomingViewingKey,
) -> Option<(orchard::Note, orchard::Address)> {
    let nullifier = orchard::note::Nullifier::from_bytes(&action.nf).into_option()?;
    let dummy_cmx = orchard::note::ExtractedNoteCommitment::from_bytes(&[0u8; 32]).into_option()?;
    let ephemeral_key = EphemeralKeyBytes(action.ephemeral_key);
    let compact_action = orchard::note_encryption::CompactAction::from_parts(
        nullifier,
        dummy_cmx,
        ephemeral_key.clone(),
        action.ciphertext,
    );
    let domain = orchard::note_encryption::OrchardDomain::for_compact_action(&compact_action);
    let epk = orchard::note_encryption::OrchardDomain::prepare_epk(
        orchard::note_encryption::OrchardDomain::epk(&ephemeral_key)?,
    );
    let shared_secret = orchard::note_encryption::OrchardDomain::ka_agree_dec(ivk, &epk);
    let key = orchard::note_encryption::OrchardDomain::kdf(shared_secret, &ephemeral_key);

    let mut plaintext = action.ciphertext;
    let mut keystream = ChaCha20::new(key.as_ref().into(), [0u8; 12][..].into());
    keystream.seek(64);
    keystream.apply_keystream(&mut plaintext);

    let (note, recipient) = domain.parse_note_plaintext_without_memo_ivk(ivk, &plaintext)?;
    if let Some(derived_esk) = orchard::note_encryption::OrchardDomain::derive_esk(&note) {
        let derived_epk =
            orchard::note_encryption::OrchardDomain::ka_derive_public(&note, &derived_esk);
        let derived_epk_bytes = orchard::note_encryption::OrchardDomain::epk_bytes(&derived_epk);
        if derived_epk_bytes.0 != ephemeral_key.0 {
            return None;
        }
    }

    Some((note, recipient))
}

pub(super) fn try_apply_orchard_pir_enhancement(
    db: &mut WalletDatabase,
    txid: TxId,
) -> Result<bool, SyncError> {
    let Some(payload) = lookup_pir_payload(txid) else {
        return Ok(false);
    };

    let reduced_actions = payload
        .actions
        .iter()
        .map(|action| ReducedOrchardCompactAction {
            nf: action.nf,
            ephemeral_key: action.ephemeral_key,
            ciphertext: action.ciphertext,
        })
        .collect::<Vec<_>>();
    if reduced_actions.is_empty() {
        log::warn!(
            "sync: PIR payload for {} had no Orchard compact actions; falling back to lwd",
            txid
        );
        return Ok(false);
    }

    let decrypted = decrypt_orchard_compact_actions_without_cmx(db, &reduced_actions)
        .map_err(|e| SyncError::db(format!("decrypt_orchard_compact_actions_without_cmx: {e}")))?;
    if decrypted.is_empty() {
        log::warn!(
            "sync: PIR payload for {} did not decrypt to any tracked Orchard account; falling back to lwd",
            txid
        );
        return Ok(false);
    }

    if let Err(e) = db.set_transaction_status(txid, TransactionStatus::Mined(payload.mined_height)) {
        log::warn!(
            "sync: failed to apply PIR-derived mined status for {}: {e}; falling back to lwd",
            txid
        );
        return Ok(false);
    }

    log::debug!(
        "sync: PIR payload for {} decrypted {} Orchard compact actions and recomputed cmx commitments",
        txid,
        decrypted.len()
    );

    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use orchard::{
        keys::{PreparedIncomingViewingKey, SpendingKey},
        note::{ExtractedNoteCommitment, Nullifier, RandomSeed, Rho},
        note_encryption::{OrchardDomain, OrchardNoteEncryption},
        value::NoteValue,
    };
    use zip32::{AccountId, Scope};

    fn sample_compact_action() -> (
        ReducedOrchardCompactAction,
        PreparedIncomingViewingKey,
        ExtractedNoteCommitment,
    ) {
        let sk = SpendingKey::from_zip32_seed(&[7u8; 32], 1, AccountId::ZERO).unwrap();
        let fvk = orchard::keys::FullViewingKey::from(&sk);
        let ivk = PreparedIncomingViewingKey::new(&fvk.to_ivk(Scope::External));
        let recipient = fvk.address_at(0u32, Scope::External);

        let rho_bytes = (0u8..=u8::MAX)
            .find_map(|b| {
                let candidate = [b; 32];
                let rho_valid = Rho::from_bytes(&candidate).into_option().is_some();
                let nullifier_valid = Nullifier::from_bytes(&candidate).into_option().is_some();
                if rho_valid && nullifier_valid {
                    Some(candidate)
                } else {
                    None
                }
            })
            .expect("should find valid rho/nullifier bytes");
        let rho = Rho::from_bytes(&rho_bytes)
            .into_option()
            .expect("rho bytes should parse");

        let rseed = (0u8..=u8::MAX)
            .find_map(|b| {
                let candidate = [b; 32];
                RandomSeed::from_bytes(candidate, &rho).into_option()
            })
            .expect("should find valid random seed bytes");

        let note = orchard::Note::from_parts(recipient, NoteValue::from_raw(40_000), rho, rseed)
            .into_option()
            .expect("note should parse");
        let expected_cmx = ExtractedNoteCommitment::from(note.commitment());
        let encryptor = OrchardNoteEncryption::new(None, note, [0u8; 512]);
        let enc_ciphertext = encryptor.encrypt_note_plaintext();
        let enc_ciphertext_bytes: &[u8] = enc_ciphertext.as_ref();
        let ephemeral_key = OrchardDomain::epk_bytes(encryptor.epk());

        (
            ReducedOrchardCompactAction {
                nf: rho_bytes,
                ephemeral_key: ephemeral_key.0,
                ciphertext: enc_ciphertext_bytes[..52]
                    .try_into()
                    .expect("compact ciphertext is 52 bytes"),
            },
            ivk,
            expected_cmx,
        )
    }

    #[test]
    fn decrypt_without_cmx_recomputes_expected_commitment() {
        let (action, ivk, expected_cmx) = sample_compact_action();

        let (decrypted_note, _) = try_orchard_compact_note_decryption_without_cmx(&action, &ivk)
            .expect("action should decrypt");

        assert_eq!(
            ExtractedNoteCommitment::from(decrypted_note.commitment()),
            expected_cmx
        );
    }

    #[test]
    fn decrypt_without_cmx_rejects_tampered_ephemeral_key() {
        let (mut action, ivk, _) = sample_compact_action();
        action.ephemeral_key[0] ^= 0x01;

        assert!(try_orchard_compact_note_decryption_without_cmx(&action, &ivk).is_none());
    }

    #[test]
    fn pir_compact_action_payload_uses_reduced_field_sizes() {
        let action = PirOrchardCompactAction {
            nf: [0x11; 32],
            ephemeral_key: [0x33; 32],
            ciphertext: [0x44; 52],
        };

        assert_eq!(action.nf.len(), 32);
        assert_eq!(action.ephemeral_key.len(), 32);
        assert_eq!(action.ciphertext.len(), 52);
    }

    #[test]
    fn pir_payload_lookup_is_single_use() {
        clear_test_pir_payloads();
        let txid = TxId::from_bytes([0xAB; 32]);
        let payload = PirEnhancementPayload {
            mined_height: BlockHeight::from_u32(12),
            actions: vec![PirOrchardCompactAction {
                nf: [1; 32],
                ephemeral_key: [3; 32],
                ciphertext: [4; 52],
            }],
        };

        set_test_pir_payload(txid, payload.clone());

        let first = lookup_pir_payload(txid).expect("payload should be present");
        assert_eq!(u32::from(first.mined_height), 12);
        assert_eq!(first.actions.len(), 1);

        assert!(
            lookup_pir_payload(txid).is_none(),
            "payload should be consumed after first lookup"
        );
    }
}
