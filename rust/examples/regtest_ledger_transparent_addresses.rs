use rust_lib_zcash_wallet::wallet::{keys::mnemonic_to_seed, network::WalletNetwork};
use secrecy::ExposeSecret;
use serde_json::json;
use transparent::keys::{IncomingViewingKey, NonHardenedChildIndex};
use zcash_keys::{
    encoding::AddressCodec as _,
    keys::{UnifiedAddressRequest, UnifiedSpendingKey},
};

fn main() {
    let mnemonic = std::env::args()
        .nth(1)
        .expect("usage: cargo run --example regtest_ledger_transparent_addresses -- <mnemonic>");

    let network = WalletNetwork::Regtest;
    let seed = mnemonic_to_seed(&mnemonic).expect("mnemonic seed");
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32::AccountId::ZERO)
        .expect("derive account 0 USK");
    let ufvk = usk.to_unified_full_viewing_key();
    let transparent = ufvk.transparent().expect("transparent FVK");
    let external = transparent
        .derive_external_ivk()
        .expect("derive external transparent IVK");
    let internal = transparent
        .derive_internal_ivk()
        .expect("derive internal transparent IVK");
    let (software_receive_ua, _) = ufvk
        .default_address(UnifiedAddressRequest::AllAvailableKeys)
        .expect("derive software receive UA");
    let software_receive_transparent = software_receive_ua
        .transparent()
        .expect("software receive UA has transparent receiver")
        .encode(&network);

    println!(
        "{}",
        json!({
            "softwareReceiveTransparent": software_receive_transparent,
            "external0": external_address(&external, 0, network),
            "external19": external_address(&external, 19, network),
            "external39": external_address(&external, 39, network),
            "internal19": internal_address(&internal, 19, network),
            "internal39": internal_address(&internal, 39, network),
        })
    );
}

fn external_address(ivk: &impl IncomingViewingKey, index: u32, network: WalletNetwork) -> String {
    ivk.derive_address(NonHardenedChildIndex::from_index(index).expect("valid index"))
        .expect("derive external address")
        .encode(&network)
}

fn internal_address(ivk: &impl IncomingViewingKey, index: u32, network: WalletNetwork) -> String {
    ivk.derive_address(NonHardenedChildIndex::from_index(index).expect("valid index"))
        .expect("derive internal address")
        .encode(&network)
}
