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
                | NetworkUpgrade::Nu6_2 => Some(BlockHeight::from_u32(1)),
            },
        }
    }
}
