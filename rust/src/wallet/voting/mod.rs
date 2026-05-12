use crate::wallet::network::WalletNetwork;

pub mod bundle;
pub mod delegation;
pub mod endpoint_validation;
pub mod hotkey;
pub mod recovery;
pub mod state;
pub mod tree_sync;
pub mod types;
pub mod vote;

impl WalletNetwork {
    pub fn voting_id(&self) -> u8 {
        match self {
            WalletNetwork::Main => 1,
            WalletNetwork::Test | WalletNetwork::Regtest => 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn voting_id_mapping() {
        assert_eq!(WalletNetwork::Main.voting_id(), 1);
        assert_eq!(WalletNetwork::Test.voting_id(), 0);
        assert_eq!(WalletNetwork::Regtest.voting_id(), 0);
    }
}
