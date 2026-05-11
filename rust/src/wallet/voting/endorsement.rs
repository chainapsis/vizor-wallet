pub fn prepare_endorsement(_voting_db: &zcash_voting::storage::VotingDb) -> ! {
    unimplemented!()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[should_panic(expected = "not implemented")]
    fn prepare_endorsement_is_explicit_placeholder() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = zcash_voting::storage::VotingDb::open(db_path.to_str().unwrap()).unwrap();

        prepare_endorsement(&db);
    }
}
