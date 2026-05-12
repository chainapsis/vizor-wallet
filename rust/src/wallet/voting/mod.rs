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
pub mod workflow;

impl WalletNetwork {
    /// Returns the network identifier used by shielded-voting services.
    ///
    /// Mainnet maps to `1`; testnet and regtest map to `0` so local and test
    /// voting workflows share the non-mainnet voting namespace.
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
