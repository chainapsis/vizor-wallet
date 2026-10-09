//! Build-specific API for the upgrade probe: account creation and transaction
//! ingestion.
//!
//! The probe is compiled against both the base tree and the current tree, so
//! API that changed between them lives here. `test-db-upgrade.sh` replaces
//! this file in the base worktree with `compat_<base>.rs` when one exists.

use rust_lib_zcash_wallet::api::wallet;

/// Creates the wallet from `mnemonic`; returns the account UUID.
pub fn import_wallet(mnemonic: &str, network: &str, db_path: &str, name: &str) -> String {
    wallet::import_wallet(
        mnemonic.to_string(),
        String::new(),
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
        String::new(),
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
        "ledger".to_string(),
    )
    .expect("import hardware account");
}

/// Stores `raw` through the build's library ingestion path, as sync and
/// enhancement do; returns its txid. The handle is the one this base's own
/// wallet code opens, unconfigured beyond what that base requires.
pub fn store_transaction(db_path: &str, raw: &[u8], mined_height: u32) -> String {
    use rust_lib_zcash_wallet::wallet::network::WalletNetwork;
    use voting_crypto_deps::rand::rngs::OsRng;
    use zcash_client_backend::data_api::wallet::decrypt_and_store_transaction;
    use zcash_client_sqlite::{util::SystemClock, WalletDb};
    use zcash_primitives::transaction::Transaction;
    use zcash_protocol::consensus::{BlockHeight, BranchId};

    let tx = Transaction::read(raw, BranchId::Sprout).expect("parse transaction");
    let mut db = WalletDb::for_path(db_path, WalletNetwork::Regtest, SystemClock, OsRng)
        .expect("open wallet DB");
    decrypt_and_store_transaction(
        &WalletNetwork::Regtest,
        &mut db,
        &tx,
        Some(BlockHeight::from_u32(mined_height)),
    )
    .expect("old build stores a wallet transaction");
    let txid = tx.txid();
    let bytes: &[u8; 32] = txid.as_ref();
    hex::encode(bytes)
}

/// Preserve the library's diagnostic for the old-reader probe. Older app APIs
/// format the outer migration error and hide whether its cause is an unknown
/// migration or an unrelated failure.
pub fn try_initialize(db_path: &str) -> Result<(), String> {
    use rust_lib_zcash_wallet::wallet::network::WalletNetwork;
    use voting_crypto_deps::rand::rngs::OsRng;
    use zcash_client_sqlite::{util::SystemClock, wallet::init::init_wallet_db, WalletDb};

    let mut db = WalletDb::for_path(db_path, WalletNetwork::Regtest, SystemClock, OsRng)
        .map_err(|error| format!("{error:?}"))?;
    init_wallet_db(&mut db, None).map_err(|error| format!("{error:?}"))
}
