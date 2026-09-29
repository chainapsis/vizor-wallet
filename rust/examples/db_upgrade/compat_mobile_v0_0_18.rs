//! `mobile/v0.0.18` variant of `compat.rs`: that release has no BIP-39
//! passphrase argument and no hardware signer kind.

use rust_lib_zcash_wallet::api::wallet;

pub fn import_wallet(mnemonic: &str, network: &str, db_path: &str, name: &str) -> String {
    wallet::import_wallet(
        mnemonic.to_string(),
        Some(1),
        network.to_string(),
        db_path.to_string(),
        Some(name.to_string()),
    )
    .expect("import wallet")
    .account_uuid
}

pub fn add_account(db_path: &str, network: &str, name: &str, mnemonic: &str) {
    wallet::add_account(
        db_path.to_string(),
        network.to_string(),
        name.to_string(),
        mnemonic.to_string(),
        Some(1),
    )
    .expect("add imported account");
}

pub fn import_hardware_account(
    db_path: &str,
    network: &str,
    name: &str,
    ufvk: &str,
    seed_fingerprint: Vec<u8>,
) {
    wallet::import_hardware_account(
        db_path.to_string(),
        network.to_string(),
        name.to_string(),
        ufvk.to_string(),
        seed_fingerprint,
        0,
        Some(1),
    )
    .expect("import hardware account");
}
