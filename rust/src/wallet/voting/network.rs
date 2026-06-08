use crate::wallet::network::WalletNetwork;

/// Convert wallet-network enum values to vote-protocol network values.
pub(crate) fn voting_network(network: WalletNetwork) -> zcash_voting::Network {
    match network {
        WalletNetwork::Main => zcash_voting::Network::Mainnet,
        WalletNetwork::Test | WalletNetwork::LocalIronwoodTestnet => zcash_voting::Network::Testnet,
        WalletNetwork::Regtest => zcash_voting::Network::Regtest,
    }
}

/// Convert vote-protocol network enum values back to wallet network values.
pub(crate) fn wallet_network(network: zcash_voting::Network) -> WalletNetwork {
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
            voting_network(WalletNetwork::LocalIronwoodTestnet),
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
