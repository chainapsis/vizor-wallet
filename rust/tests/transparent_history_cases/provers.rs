//! Sapling provers for transactions without a Sapling bundle. The S builder
//! never adds Sapling spends or outputs, so these must never be called.

use sapling_crypto::{
    bundle::GrothProofBytes,
    circuit,
    keys::EphemeralSecretKey,
    prover::{OutputProver, SpendProver},
    value::{NoteValue, ValueCommitTrapdoor},
    Diversifier, MerklePath, PaymentAddress, ProofGenerationKey, Rseed,
};

pub struct NoOpSpendProver;

impl SpendProver for NoOpSpendProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _proof_generation_key: ProofGenerationKey,
        _diversifier: Diversifier,
        _rseed: Rseed,
        _value: NoteValue,
        _alpha: jubjub::Fr,
        _rcv: ValueCommitTrapdoor,
        _anchor: bls12_381::Scalar,
        _merkle_path: MerklePath,
    ) -> Option<circuit::Spend> {
        panic!("S builder never adds Sapling spends");
    }

    fn create_proof<R: voting_crypto_deps::rand::Rng>(
        &self,
        _circuit: circuit::Spend,
        _rng: &mut R,
    ) -> Self::Proof {
        panic!("S builder never adds Sapling spends");
    }

    fn encode_proof(proof: Self::Proof) -> GrothProofBytes {
        proof
    }
}

pub struct NoOpOutputProver;

impl OutputProver for NoOpOutputProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _esk: &EphemeralSecretKey,
        _payment_address: PaymentAddress,
        _rcm: jubjub::Fr,
        _value: NoteValue,
        _rcv: ValueCommitTrapdoor,
    ) -> circuit::Output {
        panic!("S builder never adds Sapling outputs");
    }

    fn create_proof<R: voting_crypto_deps::rand::Rng>(
        &self,
        _circuit: circuit::Output,
        _rng: &mut R,
    ) -> Self::Proof {
        panic!("S builder never adds Sapling outputs");
    }

    fn encode_proof(proof: Self::Proof) -> GrothProofBytes {
        proof
    }
}
