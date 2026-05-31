pub mod delegation;
pub mod hotkey;
pub mod state;
pub mod vote;

use super::network::WalletNetwork;

pub(crate) fn voting_network(network: WalletNetwork) -> zcash_voting::Network {
    match network {
        WalletNetwork::Main => zcash_voting::Network::Mainnet,
        WalletNetwork::Test => zcash_voting::Network::Testnet,
        WalletNetwork::Regtest => zcash_voting::Network::Regtest,
    }
}

#[cfg(test)]
fn wallet_network(network: zcash_voting::Network) -> WalletNetwork {
    match network {
        zcash_voting::Network::Mainnet => WalletNetwork::Main,
        zcash_voting::Network::Testnet => WalletNetwork::Test,
        zcash_voting::Network::Regtest => WalletNetwork::Regtest,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_wallet_network_to_voting_network() {
        assert_eq!(
            voting_network(WalletNetwork::Main),
            zcash_voting::Network::Mainnet
        );
        assert_eq!(
            voting_network(WalletNetwork::Test),
            zcash_voting::Network::Testnet
        );
        assert_eq!(
            voting_network(WalletNetwork::Regtest),
            zcash_voting::Network::Regtest
        );
    }

    #[test]
    fn converts_voting_network_to_wallet_network() {
        assert_eq!(
            wallet_network(zcash_voting::Network::Mainnet),
            WalletNetwork::Main
        );
        assert_eq!(
            wallet_network(zcash_voting::Network::Testnet),
            WalletNetwork::Test
        );
        assert_eq!(
            wallet_network(zcash_voting::Network::Regtest),
            WalletNetwork::Regtest
        );
    }
}
