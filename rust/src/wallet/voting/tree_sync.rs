pub fn sync_vote_commitment_tree(_voting_db: &zcash_voting::storage::VotingDb) -> ! {
    unimplemented!()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[should_panic(expected = "not implemented")]
    fn sync_vote_commitment_tree_is_explicit_placeholder() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = zcash_voting::storage::VotingDb::open(db_path.to_str().unwrap()).unwrap();

        sync_vote_commitment_tree(&db);
    }
}
