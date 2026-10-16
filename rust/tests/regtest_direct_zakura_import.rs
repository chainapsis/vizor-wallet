//! Unix-only because the private funder handoff requires exact 0700/0600 modes.
#![cfg(unix)]

mod common;
#[path = "support/direct_zakura.rs"]
mod direct_zakura;

use direct_zakura::{
    assert_funding_response, fund_wallet, path_string, required_environment, AMOUNT_ZATOSHI,
    NETWORK,
};
use rust_lib_zcash_wallet::api::{simple as simple_api, sync as sync_api, wallet as wallet_api};
use transparent::keys::{AccountPrivKey, IncomingViewingKey, NonHardenedChildIndex};
use zcash_keys::{
    encoding::encode_transparent_address,
    keys::{ReceiverRequirement, UnifiedAddressRequest, UnifiedSpendingKey},
};
use zcash_protocol::consensus::{
    BlockHeight, NetworkConstants, NetworkType, NetworkUpgrade, Parameters,
};

const BIP39_VECTOR_MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const BIP39_VECTOR_PASSPHRASE: &str = "TREZOR";
const BIP39_VECTOR_REGTEST_ORCHARD_UA: &str =
    "uregtest1fvrf9h4dlxpa0yfthy844kut60f06uh7u4kmf0flmh62g4zkqxcaahpjzdq76gjj4tkxsg3j4uqq7un3qpla26ev2rlrlt5r4ua6zfd3";
const BIP39_VECTOR_REGTEST_TADDR: &str = "tmPTcChwqcza88W1mydzwkZ25C9qQm3ugiM";

#[derive(Clone, Copy)]
struct HeightOneRegtest;

impl Parameters for HeightOneRegtest {
    fn network_type(&self) -> NetworkType {
        NetworkType::Regtest
    }

    fn activation_height(&self, upgrade: NetworkUpgrade) -> Option<BlockHeight> {
        if upgrade == NetworkUpgrade::Nu7 {
            None
        } else {
            Some(BlockHeight::from_u32(1))
        }
    }
}

fn independently_derived_addresses(passphrase: &str) -> (String, String) {
    let network = HeightOneRegtest;
    let mnemonic = bip0039::Mnemonic::<bip0039::English>::from_phrase(BIP39_VECTOR_MNEMONIC)
        .expect("valid public BIP39 vector mnemonic");
    let seed = mnemonic.to_seed(passphrase);
    let spending_key = UnifiedSpendingKey::from_seed(&network, &seed, zip32::AccountId::ZERO)
        .expect("derive public BIP39 vector spending key");
    let request = UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
        ReceiverRequirement::Omit,
    )
    .expect("valid current Orchard-only address request");
    let (unified_address, _) = spending_key
        .to_unified_full_viewing_key()
        .default_address(request)
        .expect("derive current public BIP39 vector address");

    let transparent_account = AccountPrivKey::from_seed(&network, &seed, zip32::AccountId::ZERO)
        .expect("derive public BIP44 account key");
    let transparent_address = transparent_account
        .to_account_pubkey()
        .derive_external_ivk()
        .expect("derive public BIP44 external viewing key")
        .derive_address(NonHardenedChildIndex::ZERO)
        .expect("derive public BIP44 address zero");
    (
        unified_address.encode(&network),
        encode_transparent_address(
            &network.b58_pubkey_address_prefix(),
            &network.b58_script_address_prefix(),
            &transparent_address,
        ),
    )
}

#[test]
fn public_bip39_passphrase_vector_matches_regtest_address_goldens() {
    let expected = independently_derived_addresses(BIP39_VECTOR_PASSPHRASE);
    assert_eq!(expected.0, BIP39_VECTOR_REGTEST_ORCHARD_UA);
    assert_eq!(expected.1, BIP39_VECTOR_REGTEST_TADDR);

    let empty = independently_derived_addresses("");
    let wrong = independently_derived_addresses("trezor");
    assert_ne!(empty.0, expected.0);
    assert_ne!(wrong.0, expected.0);
    assert_ne!(empty.0, wrong.0);
    assert_ne!(empty.1, expected.1);
    assert_ne!(wrong.1, expected.1);
}

#[test]
#[ignore = "requires Unix, direct Zakura/lightwalletd, and an independent external funder"]
fn historical_bip39_passphrase_import_recovers_exact_ironwood_funding_from_direct_zakura() {
    let environment = required_environment();
    let expected_addresses = independently_derived_addresses(BIP39_VECTOR_PASSPHRASE);
    assert_eq!(expected_addresses.0, BIP39_VECTOR_REGTEST_ORCHARD_UA);
    assert_eq!(expected_addresses.1, BIP39_VECTOR_REGTEST_TADDR);

    simple_api::configure_regtest_ironwood_activation_height(1)
        .expect("configure wallet NU6.3 activation height");
    let initial_chain =
        wallet_api::get_chain_upgrade_status(environment.lightwalletd_url.clone(), NETWORK.into())
            .expect("query initial direct Zakura chain status");
    assert_eq!(initial_chain.tip_height, environment.initial_tip_height);
    assert_eq!(initial_chain.nu6_3_activation_height, Some(1));
    assert!(initial_chain.ironwood_active_at_tip);

    let response = fund_wallet(&environment, &expected_addresses.0);
    let history_txid = assert_funding_response(&response, environment.initial_tip_height);

    let tempdir = common::wallet_tempdir();
    let db_path = tempdir.path().join("zcash_wallet.db");
    assert!(!db_path.exists(), "historical import DB must start absent");
    let db = path_string(&db_path);
    let imported = wallet_api::import_software_wallet_with_account_discovery(
        BIP39_VECTOR_MNEMONIC.into(),
        BIP39_VECTOR_PASSPHRASE.into(),
        Some(2),
        NETWORK.into(),
        db.clone(),
        Some("Historical BIP39 vector".into()),
        true,
        1,
        vec![],
    )
    .expect("restore public BIP39 vector with account discovery");
    assert!(imported.did_import_primary_account);
    assert_eq!(imported.accounts.len(), 1);
    let account = &imported.accounts[0];
    assert_eq!(account.zip32_account_index, 0);
    assert!(account.is_seed_anchor);
    assert_eq!(account.unified_address, BIP39_VECTOR_REGTEST_ORCHARD_UA);

    let accounts = wallet_api::list_accounts(db.clone(), NETWORK.into())
        .expect("list restored historical accounts");
    assert_eq!(accounts.len(), 1);
    assert_eq!(accounts[0].uuid, account.account_uuid);
    assert_eq!(accounts[0].birthday_height, 2);
    assert_eq!(accounts[0].zip32_account_index, Some(0));
    assert!(accounts[0].is_seed_anchor);
    assert_eq!(accounts[0].name, "Historical BIP39 vector");
    assert_eq!(accounts[0].unified_address, BIP39_VECTOR_REGTEST_ORCHARD_UA);
    assert_eq!(
        wallet_api::get_transparent_receive_address(
            db.clone(),
            NETWORK.into(),
            Some(account.account_uuid.clone()),
        )
        .expect("derive restored BIP44 transparent address"),
        BIP39_VECTOR_REGTEST_TADDR
    );

    sync_api::run_full_sync_blocking(
        db.clone(),
        environment.lightwalletd_url.clone(),
        NETWORK.into(),
        1,
    )
    .expect("sync historical BIP39 import against direct Zakura");
    let status = sync_api::get_sync_status(db.clone(), NETWORK.into())
        .expect("read historical import sync status");
    assert!(status.is_complete);
    assert!(!status.is_syncing);
    assert_eq!(status.chain_tip_height, response.final_tip_height);
    assert_eq!(status.scanned_height, response.final_tip_height);

    let balance = sync_api::get_balance(db.clone(), NETWORK.into(), account.account_uuid.clone())
        .expect("read historical import balance");
    assert!(matches!(
        balance.availability,
        sync_api::WalletBalanceAvailability::Available
    ));
    assert_eq!(balance.ironwood, AMOUNT_ZATOSHI);
    assert_eq!(balance.spendable, AMOUNT_ZATOSHI);
    assert_eq!(balance.total, AMOUNT_ZATOSHI);
    assert_eq!(
        [
            balance.transparent,
            balance.sapling,
            balance.orchard,
            balance.transparent_locked,
            balance.sapling_locked,
            balance.orchard_locked,
            balance.ironwood_locked,
            balance.transparent_pending,
            balance.sapling_pending,
            balance.orchard_pending,
            balance.ironwood_pending,
            balance.change_pending_confirmation,
            balance.value_pending_spendability,
            balance.uneconomic_value,
            balance.locked,
        ],
        [0; 15]
    );
    let history = sync_api::get_transaction_history(
        db.clone(),
        NETWORK.into(),
        Some(20),
        account.account_uuid.clone(),
    )
    .expect("read historical import transaction history");
    assert_eq!(history.len(), 1);
    let received = &history[0];
    assert_eq!(received.txid_hex, history_txid);
    assert_eq!(received.mined_height, response.mined_height);
    assert_eq!(received.account_balance_delta, AMOUNT_ZATOSHI as i64);
    assert_eq!(received.display_amount, AMOUNT_ZATOSHI);
    assert_eq!(received.tx_kind, "received");
    assert_eq!(received.display_pool, "ironwood");
    assert!(!received.expired_unmined);

    let wrong_dir = common::wallet_tempdir();
    let wrong_db_path = wrong_dir.path().join("zcash_wallet.db");
    assert!(
        !wrong_db_path.exists(),
        "wrong-passphrase control DB must start absent"
    );
    let wrong_db = path_string(&wrong_db_path);
    let wrong = wallet_api::import_software_wallet_with_account_discovery(
        BIP39_VECTOR_MNEMONIC.into(),
        "trezor".into(),
        Some(2),
        NETWORK.into(),
        wrong_db.clone(),
        Some("Wrong passphrase control".into()),
        true,
        1,
        vec![],
    )
    .expect("restore wrong-passphrase negative control");
    assert_eq!(wrong.accounts.len(), 1);
    assert_ne!(
        wrong.accounts[0].unified_address,
        BIP39_VECTOR_REGTEST_ORCHARD_UA
    );
    sync_api::run_full_sync_blocking(
        wrong_db.clone(),
        environment.lightwalletd_url,
        NETWORK.into(),
        1,
    )
    .expect("sync wrong-passphrase negative control");
    let wrong_status = sync_api::get_sync_status(wrong_db.clone(), NETWORK.into())
        .expect("read wrong-passphrase sync status");
    assert!(wrong_status.is_complete);
    assert!(!wrong_status.is_syncing);
    assert_eq!(wrong_status.chain_tip_height, response.final_tip_height);
    assert_eq!(wrong_status.scanned_height, response.final_tip_height);
    let wrong_balance = sync_api::get_balance(
        wrong_db.clone(),
        NETWORK.into(),
        wrong.accounts[0].account_uuid.clone(),
    )
    .expect("read wrong-passphrase balance");
    assert!(matches!(
        wrong_balance.availability,
        sync_api::WalletBalanceAvailability::Available
    ));
    assert_eq!(wrong_balance.total, 0);
    assert!(sync_api::get_transaction_history(
        wrong_db,
        NETWORK.into(),
        Some(20),
        wrong.accounts[0].account_uuid.clone(),
    )
    .expect("read wrong-passphrase history")
    .is_empty());
}
