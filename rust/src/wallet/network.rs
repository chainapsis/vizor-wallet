use zcash_protocol::consensus::{BlockHeight, Network, NetworkType, NetworkUpgrade, Parameters};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum WalletNetwork {
    Main,
    Test,
    LocalIronwoodTestnet,
    Regtest,
}

impl WalletNetwork {
    pub fn from_str(network: &str) -> Option<Self> {
        match network {
            "main" => Some(Self::Main),
            "test" => Some(Self::Test),
            "local_ironwood_testnet" => Some(Self::LocalIronwoodTestnet),
            "regtest" => Some(Self::Regtest),
            _ => None,
        }
    }
}

/// Activation heights for the Ironwood mainnet-masquerade test chain (opt-in `--cfg
/// ironwood_masquerade`, default OFF). The chain derives/encodes as mainnet (coin type 133',
/// `u1`/`uview1`) so a normal-mode Keystone works, but it activates the network upgrades at the
/// test chain's LOW heights, not real mainnet's. Without this override, `WalletNetwork::Main` uses
/// `Network::MainNetwork` heights (Orchard ~1,687,104), so a sync against this low-height chain
/// (tip ~11k) computes "Orchard not active yet → 0 blocks to scan" and the sync fatals with
/// "wallet summary unavailable". Heights mirror the chain's `getblockchaininfo` upgrades.
#[cfg(ironwood_masquerade)]
fn ironwood_masquerade_activation_height(nu: NetworkUpgrade) -> Option<BlockHeight> {
    let height = match nu {
        NetworkUpgrade::Overwinter
        | NetworkUpgrade::Sapling
        | NetworkUpgrade::Blossom
        | NetworkUpgrade::Heartwood
        | NetworkUpgrade::Canopy => 1,
        NetworkUpgrade::Nu5 => 2,
        NetworkUpgrade::Nu6 => 3,
        NetworkUpgrade::Nu6_1 => 4,
        NetworkUpgrade::Nu6_2 => 5,
        NetworkUpgrade::Nu6_3 => 5000,
    };
    Some(BlockHeight::from_u32(height))
}

fn local_ironwood_testnet_activation_height(nu: NetworkUpgrade) -> Option<BlockHeight> {
    let height = match nu {
        NetworkUpgrade::Overwinter
        | NetworkUpgrade::Sapling
        | NetworkUpgrade::Blossom
        | NetworkUpgrade::Heartwood
        | NetworkUpgrade::Canopy
        | NetworkUpgrade::Nu5 => 1,
        NetworkUpgrade::Nu6 => 2,
        NetworkUpgrade::Nu6_1 => 3,
        NetworkUpgrade::Nu6_2 => 4,
        NetworkUpgrade::Nu6_3 => 120,
    };

    Some(BlockHeight::from_u32(height))
}

impl Parameters for WalletNetwork {
    fn network_type(&self) -> NetworkType {
        match self {
            Self::Main => NetworkType::Main,
            Self::Test | Self::LocalIronwoodTestnet => NetworkType::Test,
            Self::Regtest => NetworkType::Regtest,
        }
    }

    fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
        match self {
            // Mainnet-masquerade test build (`--cfg ironwood_masquerade`): keep Main's mainnet
            // identity (133'/u1) but use the test chain's low activation heights so sync works.
            #[cfg(ironwood_masquerade)]
            Self::Main => ironwood_masquerade_activation_height(nu),
            #[cfg(not(ironwood_masquerade))]
            Self::Main => Network::MainNetwork.activation_height(nu),
            Self::Test => Network::TestNetwork.activation_height(nu),
            Self::LocalIronwoodTestnet => local_ironwood_testnet_activation_height(nu),
            Self::Regtest => match nu {
                NetworkUpgrade::Overwinter
                | NetworkUpgrade::Sapling
                | NetworkUpgrade::Blossom
                | NetworkUpgrade::Heartwood
                | NetworkUpgrade::Canopy
                | NetworkUpgrade::Nu5
                | NetworkUpgrade::Nu6
                | NetworkUpgrade::Nu6_1
                | NetworkUpgrade::Nu6_2
                | NetworkUpgrade::Nu6_3 => Some(BlockHeight::from_u32(1)),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_ironwood_testnet_keeps_testnet_identity_with_local_activation_heights() {
        let network = WalletNetwork::LocalIronwoodTestnet;

        assert_eq!(network.network_type(), NetworkType::Test);
        assert_eq!(
            network.activation_height(NetworkUpgrade::Nu5),
            Some(BlockHeight::from_u32(1))
        );
        assert_eq!(
            network.activation_height(NetworkUpgrade::Nu6_3),
            Some(BlockHeight::from_u32(120))
        );
    }
}
