#[cfg(test)]
use std::cell::Cell;
#[cfg(not(test))]
use std::sync::atomic::{AtomicU32, Ordering};
use zcash_protocol::consensus::{BlockHeight, Network, NetworkType, NetworkUpgrade, Parameters};

// Keep ordinary regtest builds Orchard-only unless an Ironwood E2E explicitly
// configures a controlled activation height.
const DEFAULT_REGTEST_NU6_3_ACTIVATION_HEIGHT: u32 = u32::MAX;
#[cfg(not(test))]
static REGTEST_NU6_3_ACTIVATION_HEIGHT: AtomicU32 =
    AtomicU32::new(DEFAULT_REGTEST_NU6_3_ACTIVATION_HEIGHT);

#[cfg(test)]
thread_local! {
    static REGTEST_NU6_3_ACTIVATION_HEIGHT: Cell<u32> =
        const { Cell::new(DEFAULT_REGTEST_NU6_3_ACTIVATION_HEIGHT) };
}

pub fn configure_regtest_nu6_3_activation_height(height: u32) -> Result<(), String> {
    if height < 2 {
        return Err("Regtest NU6.3 activation height must be at least 2".to_string());
    }
    #[cfg(not(test))]
    REGTEST_NU6_3_ACTIVATION_HEIGHT.store(height, Ordering::SeqCst);
    #[cfg(test)]
    REGTEST_NU6_3_ACTIVATION_HEIGHT.set(height);
    Ok(())
}

fn regtest_nu6_3_activation_height() -> BlockHeight {
    #[cfg(not(test))]
    let height = REGTEST_NU6_3_ACTIVATION_HEIGHT.load(Ordering::SeqCst);
    #[cfg(test)]
    let height = REGTEST_NU6_3_ACTIVATION_HEIGHT.get();
    BlockHeight::from_u32(height)
}

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
                | NetworkUpgrade::Nu6_2 => Some(BlockHeight::from_u32(1)),
                NetworkUpgrade::Nu6_3 => Some(regtest_nu6_3_activation_height()),
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
