use rust_lib_zcash_wallet::api::wallet::{find_software_account_for_mnemonic, import_wallet};

const BIP39_VECTOR_MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const BIP39_VECTOR_PASSPHRASE: &str = "TREZOR";

#[test]
fn stored_software_secret_matches_only_its_exact_database_account() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap().to_string();
    let imported = import_wallet(
        BIP39_VECTOR_MNEMONIC.to_string(),
        BIP39_VECTOR_PASSPHRASE.to_string(),
        None,
        "main".to_string(),
        db_path.clone(),
        Some("BIP39 vector".to_string()),
    )
    .unwrap();
    let stored_secret = serde_json::json!({
        "version": 1,
        "mnemonic": BIP39_VECTOR_MNEMONIC,
        "bip39Passphrase": BIP39_VECTOR_PASSPHRASE,
    })
    .to_string();
    let wrong_passphrase = serde_json::json!({
        "version": 1,
        "mnemonic": BIP39_VECTOR_MNEMONIC,
        "bip39Passphrase": "trezor",
    })
    .to_string();
    let other_mnemonic =
        "legal winner thank year wave sausage worth useful legal winner thank yellow";

    assert_eq!(
        find_software_account_for_mnemonic(
            stored_secret,
            "main".to_string(),
            db_path.clone(),
            0,
        )
        .unwrap(),
        Some(imported.account_uuid),
    );
    assert_eq!(
        find_software_account_for_mnemonic(
            wrong_passphrase,
            "main".to_string(),
            db_path.clone(),
            0,
        )
        .unwrap(),
        None,
    );
    assert_eq!(
        find_software_account_for_mnemonic(
            other_mnemonic.to_string(),
            "main".to_string(),
            db_path.clone(),
            0,
        )
        .unwrap(),
        None,
    );
    assert!(find_software_account_for_mnemonic(
        "not a valid mnemonic".to_string(),
        "main".to_string(),
        db_path,
        0,
    )
    .is_err());
}
