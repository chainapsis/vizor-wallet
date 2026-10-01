//! Runtime-generated parties. Keys exist only in this process; fixture files
//! receive addresses and scripts, never mnemonics or spending keys.

use rust_lib_zcash_wallet::{api::wallet as wallet_api, wallet::network::WalletNetwork};
use transparent::{
    address::TransparentAddress,
    keys::{AccountPrivKey, NonHardenedChildIndex, TransparentKeyScope},
};
use zcash_address::ToAddress as _;
use zcash_keys::encoding::AddressCodec as _;

pub const NETWORK: WalletNetwork = WalletNetwork::Regtest;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Scope {
    External,
    Internal,
    Ephemeral,
}

impl Scope {
    pub fn label(self) -> &'static str {
        match self {
            Scope::External => "external",
            Scope::Internal => "internal",
            Scope::Ephemeral => "ephemeral",
        }
    }

    fn key_scope(self) -> TransparentKeyScope {
        match self {
            Scope::External => TransparentKeyScope::EXTERNAL,
            Scope::Internal => TransparentKeyScope::INTERNAL,
            Scope::Ephemeral => TransparentKeyScope::EPHEMERAL,
        }
    }
}

/// One BIP 44 account (`m/44'/1'/0'`) of a runtime mnemonic.
pub struct Party {
    /// Fixture label: `A0`, `A1`, `B`, `C`.
    pub name: &'static str,
    /// `alice`, `bob`, `carol`.
    pub wallet: &'static str,
    pub mnemonic: String,
    account_key: AccountPrivKey,
}

impl Party {
    pub fn generate(name: &'static str, wallet: &'static str) -> Self {
        let mnemonic = wallet_api::generate_mnemonic();
        let seed = bip0039::Mnemonic::<bip0039::English>::from_phrase(&mnemonic)
            .expect("generated mnemonic")
            .to_seed("");
        let account_key = AccountPrivKey::from_seed(&NETWORK, &seed, zip32::AccountId::ZERO)
            .expect("transparent account key");
        Party {
            name,
            wallet,
            mnemonic,
            account_key,
        }
    }

    pub fn secret_key(&self, scope: Scope, index: u32) -> secp256k1::SecretKey {
        self.account_key
            .derive_secret_key(
                scope.key_scope(),
                NonHardenedChildIndex::from_index(index).expect("non-hardened index"),
            )
            .expect("derive transparent secret key")
    }

    pub fn taddr(&self, scope: Scope, index: u32) -> TransparentAddress {
        let secp = secp256k1::Secp256k1::signing_only();
        let pubkey = self.secret_key(scope, index).public_key(&secp);
        TransparentAddress::from_pubkey(&pubkey)
    }

    pub fn address(&self, scope: Scope, index: u32) -> String {
        self.taddr(scope, index).encode(&NETWORK)
    }

    /// Hex of the P2PKH scriptPubKey, the key of the ownership map.
    pub fn script_hex(&self, scope: Scope, index: u32) -> String {
        script_hex(&self.taddr(scope, index))
    }
}

pub fn script_hex(address: &TransparentAddress) -> String {
    let script = transparent::address::Script::from(address.script());
    hex::encode(&script.0 .0)
}

/// ZIP 320 TEX encoding of a P2PKH address.
pub fn tex_address(address: &TransparentAddress) -> String {
    match address {
        TransparentAddress::PublicKeyHash(hash) => zcash_address::ZcashAddress::from_tex(
            zcash_protocol::consensus::NetworkType::Regtest,
            *hash,
        )
        .to_string(),
        TransparentAddress::ScriptHash(_) => panic!("TEX requires a P2PKH address"),
    }
}
