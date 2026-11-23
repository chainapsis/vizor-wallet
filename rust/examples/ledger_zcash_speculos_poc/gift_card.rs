//! Synthetic, fully scanned Ironwood funds for the Gift Card UI journey.
//! No chain or real funds are used; proposal selection and PCZT creation stay real.

#[path = "../support/ironwood_fixture.rs"]
mod ironwood_fixture;

use rust_lib_zcash_wallet::wallet::network::WalletNetwork;
use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::data_api::{
    chain::ChainState, Account as _, AccountBirthday, AccountPurpose, WalletWrite, Zip32Derivation,
};
use zcash_client_sqlite::{util::SystemClock, wallet::init::init_wallet_db, WalletDb};
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_primitives::block::BlockHash;
use zip32::fingerprint::SeedFingerprint;

pub(super) fn prepare_wallet(path: &str, ufvk: &str, fingerprint: &[u8]) -> Result<String, String> {
    let network = WalletNetwork::Main;
    let ufvk = UnifiedFullViewingKey::decode(&network, ufvk).map_err(|e| e.to_string())?;
    let height = ironwood_fixture::funding_height()?;
    let prior = ChainState::empty(height - 1, BlockHash([0; 32]));
    let mut db =
        WalletDb::for_path(path, network, SystemClock, OsRng).map_err(|e| e.to_string())?;
    init_wallet_db(&mut db, None).map_err(|e| e.to_string())?;
    let fingerprint: [u8; 32] = fingerprint.try_into().map_err(|_| "Invalid fingerprint")?;
    let account = db
        .import_account_ufvk(
            "Speculos Ledger Gift Cards",
            &ufvk,
            &AccountBirthday::from_parts(prior, None),
            AccountPurpose::Spending {
                derivation: Some(Zip32Derivation::new(
                    SeedFingerprint::from_bytes(fingerprint),
                    zip32::AccountId::ZERO,
                )),
            },
            Some("vizor.hardware.ledger.v1"),
        )
        .map_err(|e| e.to_string())?;
    let account_uuid = account.id().expose_uuid().to_string();

    drop(db);
    ironwood_fixture::fund_wallet(path, &ufvk, &account_uuid, height)?;
    println!("gift_card_fixture=5_000_000 spendable Ironwood zatoshi");
    Ok(account_uuid)
}
