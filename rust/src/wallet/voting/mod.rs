use crate::wallet::network::WalletNetwork;

pub mod bundle;
pub mod delegation;
pub mod hotkey;
pub mod progress;
pub mod recovery;
pub mod state;
pub mod tree_sync;
pub mod vote;
pub mod workflow;

fn voting_network(network: WalletNetwork) -> zcash_voting::Network {
    match network {
        WalletNetwork::Main => zcash_voting::Network::Mainnet,
        WalletNetwork::Test => zcash_voting::Network::Testnet,
        WalletNetwork::Regtest => zcash_voting::Network::Regtest,
    }
}
