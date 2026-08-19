use vote_commitment_tree::MerkleHashVote;
use voting_crypto_deps::pasta_curves::Fp;

#[test]
fn voting_circuit_fields_are_tree_fields() {
    let value = voting_circuits::shares_hash_from_comms([Fp::from(7); 16]);
    let tree_hash = MerkleHashVote::from_fp(value);

    assert_eq!(tree_hash.inner(), value);
}
