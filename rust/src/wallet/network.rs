use zcash_protocol::consensus::{BlockHeight, Network, NetworkType, NetworkUpgrade, Parameters};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum WalletNetwork {
    Main,
    Test,
    Regtest,
}

impl WalletNetwork {
    pub fn from_str(network: &str) -> Option<Self> {
        match network {
            "main" => Some(Self::Main),
            "test" => Some(Self::Test),
            "regtest" => Some(Self::Regtest),
            _ => None,
        }
    }
}

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

impl Parameters for WalletNetwork {
    fn network_type(&self) -> NetworkType {
        match self {
            Self::Main => NetworkType::Main,
            Self::Test => NetworkType::Test,
            Self::Regtest => NetworkType::Regtest,
        }
    }

    fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
        match self {
            #[cfg(ironwood_masquerade)]
            Self::Main => ironwood_masquerade_activation_height(nu),
            #[cfg(not(ironwood_masquerade))]
            Self::Main => Network::MainNetwork.activation_height(nu),
            Self::Test => Network::TestNetwork.activation_height(nu),
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

#[cfg(all(test, ironwood_masquerade))]
mod tests {
    use super::*;

    #[test]
    fn masquerade_main_keeps_mainnet_identity_with_test_chain_activation_heights() {
        let network = WalletNetwork::Main;

        assert_eq!(network.network_type(), NetworkType::Main);
        assert_eq!(
            network.activation_height(NetworkUpgrade::Nu6_3),
            Some(BlockHeight::from_u32(5000))
        );
    }
}
