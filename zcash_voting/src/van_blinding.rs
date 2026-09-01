//! Deterministic governance commitment blinding for locally held voting hotkeys.

#[allow(unused_imports)]
pub(crate) use crate::backend::pasta_curves;

use pasta_curves::{
    group::ff::{FromUniformBytes, PrimeField},
    pallas,
};
use zeroize::Zeroizing;

use crate::types::{Network, NoteInfo, VotingError, VotingHotkey, VotingRoundParams};

const VAN_BLINDING_KEY_DOMAIN: &[u8] = b"zcash_voting/van-blinding-key/v1";
const VAN_BLINDING_DOMAIN: &[u8] = b"zcash_voting/van-blinding/v1";

/// Domain-separated key retained with local delegation inputs.
pub(crate) struct VanBlindingKey(Zeroizing<[u8; 64]>);

impl Clone for VanBlindingKey {
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl VanBlindingKey {
    pub(crate) fn from_hotkey(hotkey: &VotingHotkey) -> Self {
        let hash = blake2b_simd::Params::new()
            .hash_length(64)
            .key(hotkey.stored_secret())
            .hash(VAN_BLINDING_KEY_DOMAIN);
        let mut key = Zeroizing::new([0u8; 64]);
        key.copy_from_slice(hash.as_bytes());
        Self(key)
    }

    /// Derives the canonical blinding for one exact round and real-note bundle.
    pub(crate) fn derive(
        &self,
        network: Network,
        round: &VotingRoundParams,
        bundle_index: u32,
        notes: &[NoteInfo],
    ) -> Result<VanBlinding, VotingError> {
        crate::types::validate_round_params(round)?;
        crate::types::validate_notes(notes)?;

        let mut note_identities = notes
            .iter()
            .map(|note| {
                let commitment: [u8; 32] = note.commitment.as_slice().try_into().map_err(|_| {
                    VotingError::InvalidInput {
                        message: format!(
                            "note commitment must be 32 bytes, got {}",
                            note.commitment.len()
                        ),
                    }
                })?;
                Ok((note.position, commitment, note.value))
            })
            .collect::<Result<Vec<_>, VotingError>>()?;
        note_identities.sort_unstable();

        let round_id =
            hex::decode(&round.vote_round_id).map_err(|error| VotingError::InvalidInput {
                message: format!("vote_round_id is not valid hex: {error}"),
            })?;
        let mut state = blake2b_simd::Params::new()
            .hash_length(64)
            .key(&self.0[..])
            .to_state();
        update_field(&mut state, VAN_BLINDING_DOMAIN);
        update_field(&mut state, &[1]);
        update_field(&mut state, network_label(network));
        update_field(&mut state, &round_id);
        update_field(&mut state, &round.snapshot_height.to_le_bytes());
        update_field(&mut state, &round.ea_pk);
        update_field(&mut state, &round.nc_root);
        update_field(&mut state, &round.nullifier_imt_root);
        update_field(&mut state, &bundle_index.to_le_bytes());
        update_field(&mut state, &(note_identities.len() as u32).to_le_bytes());
        for (position, commitment, value) in note_identities {
            update_field(&mut state, &position.to_le_bytes());
            update_field(&mut state, &commitment);
            update_field(&mut state, &value.to_le_bytes());
        }

        let hash = state.finalize();
        let mut wide = Zeroizing::new([0u8; 64]);
        wide.copy_from_slice(hash.as_bytes());
        let field = pallas::Base::from_uniform_bytes(&wide);
        Ok(VanBlinding(Zeroizing::new(field.to_repr())))
    }
}

/// Canonical Pallas field encoding used as one bundle's VAN blinding.
pub(crate) struct VanBlinding(Zeroizing<[u8; 32]>);

impl VanBlinding {
    #[cfg(test)]
    pub(crate) fn bytes(&self) -> &[u8; 32] {
        &self.0
    }

    pub(crate) fn field(&self) -> pallas::Base {
        Option::<pallas::Base>::from(pallas::Base::from_repr(*self.0))
            .expect("VanBlinding is constructed from a Pallas field element")
    }
}

fn update_field(state: &mut blake2b_simd::State, field: &[u8]) {
    state.update(&(field.len() as u64).to_le_bytes());
    state.update(field);
}

fn network_label(network: Network) -> &'static [u8] {
    match network {
        Network::Mainnet => b"mainnet",
        Network::Testnet => b"testnet",
        Network::Regtest => b"regtest",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn round() -> VotingRoundParams {
        VotingRoundParams {
            vote_round_id: "01".repeat(32),
            snapshot_height: 42,
            ea_pk: vec![0x02; 32],
            nc_root: vec![0x03; 32],
            nullifier_imt_root: vec![0x04; 32],
        }
    }

    fn note(position: u64, value: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![position as u8 + 1; 32],
            nullifier: vec![position as u8 + 11; 32],
            value,
            position,
            diversifier: vec![0x05; 11],
            rho: vec![0x06; 32],
            rseed: vec![0x07; 32],
            scope: 0,
            ufvk_str: String::new(),
        }
    }

    #[test]
    fn van_blinding_has_a_stable_test_vector() {
        let hotkey = VotingHotkey::from_stored_secret(&[0x42; 64], Network::Regtest).unwrap();
        let key = VanBlindingKey::from_hotkey(&hotkey);
        let blinding = key
            .derive(
                Network::Regtest,
                &round(),
                3,
                &[note(9, 13_000_000), note(2, 25_000_000)],
            )
            .unwrap();

        assert_eq!(
            hex::encode(blinding.bytes()),
            "0e50d0295e8d991c23b21631dde5fa903d2924f7853e56fd84d07bfe88162430"
        );
    }

    #[test]
    fn van_blinding_binds_every_recovery_identity_input() {
        let hotkey = VotingHotkey::from_stored_secret(&[0x42; 64], Network::Regtest).unwrap();
        let other_hotkey = VotingHotkey::from_stored_secret(&[0x43; 64], Network::Regtest).unwrap();
        let key = VanBlindingKey::from_hotkey(&hotkey);
        let notes = vec![note(2, 13_000_000), note(9, 25_000_000)];
        let expected = key.derive(Network::Regtest, &round(), 3, &notes).unwrap();

        let mut reversed = notes.clone();
        reversed.reverse();
        assert_eq!(
            expected.bytes(),
            key.derive(Network::Regtest, &round(), 3, &reversed)
                .unwrap()
                .bytes(),
            "caller note order must not affect the bundle identity"
        );
        assert_ne!(
            expected.bytes(),
            key.derive(Network::Regtest, &round(), 4, &notes)
                .unwrap()
                .bytes()
        );
        assert_ne!(
            expected.bytes(),
            key.derive(Network::Testnet, &round(), 3, &notes)
                .unwrap()
                .bytes()
        );

        let mut changed_round = round();
        changed_round.nullifier_imt_root[0] ^= 1;
        assert_ne!(
            expected.bytes(),
            key.derive(Network::Regtest, &changed_round, 3, &notes)
                .unwrap()
                .bytes()
        );

        for mutate in [
            |note: &mut NoteInfo| note.position += 1,
            |note: &mut NoteInfo| note.commitment[0] ^= 1,
            |note: &mut NoteInfo| note.value += 1,
        ] {
            let mut changed_notes = notes.clone();
            mutate(&mut changed_notes[0]);
            assert_ne!(
                expected.bytes(),
                key.derive(Network::Regtest, &round(), 3, &changed_notes)
                    .unwrap()
                    .bytes()
            );
        }

        assert_ne!(
            expected.bytes(),
            VanBlindingKey::from_hotkey(&other_hotkey)
                .derive(Network::Regtest, &round(), 3, &notes)
                .unwrap()
                .bytes()
        );
    }
}
