mod common;

use common::{
    create_wallet, current_tip_height, ensure_regtest_up, exclusive_regtest, fund_wallet,
    get_balance, get_transaction_history, history_txids, import_wallet_with_birthday,
    import_wallet_with_passphrase_and_birthday, list_accounts, mine_blocks, positive_history_count,
    sync_wallet,
};

const BIP39_VECTOR_MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const BIP39_VECTOR_PASSPHRASE: &str = "TREZOR";
const BIP39_VECTOR_REGTEST_UA: &str =
    "uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn";
const BIP39_VECTOR_REGTEST_TADDR: &str = "tmPTcChwqcza88W1mydzwkZ25C9qQm3ugiM";

/// The vector's ZIP 32 account 0 viewing key, derived from the mnemonic and
/// passphrase with bip0039 and zcash_keys directly, not Vizor's key code.
fn vector_ufvk() -> zcash_keys::keys::UnifiedFullViewingKey {
    use rust_lib_zcash_wallet::wallet::network::WalletNetwork;
    let mnemonic =
        bip0039::Mnemonic::<bip0039::English>::from_phrase(BIP39_VECTOR_MNEMONIC).unwrap();
    zcash_keys::keys::UnifiedSpendingKey::from_seed(
        &WalletNetwork::Regtest,
        &mnemonic.to_seed(BIP39_VECTOR_PASSPHRASE),
        zip32::AccountId::ZERO,
    )
    .unwrap()
    .to_unified_full_viewing_key()
}

/// The address a wallet issues for the vector's account since 4579a859c: the
/// viewing key's default address for an Orchard-only receiver request. The
/// default address takes the lowest diversifier index valid for every
/// required receiver, so dropping Sapling also moves it to index 0.
fn expected_orchard_only_address() -> String {
    use rust_lib_zcash_wallet::wallet::network::WalletNetwork;
    use zcash_keys::keys::{ReceiverRequirement::*, UnifiedAddressRequest};
    let request = UnifiedAddressRequest::custom(Require, Omit, Omit).unwrap();
    let (address, _) = vector_ufvk().default_address(request).unwrap();
    address.encode(&WalletNetwork::Regtest)
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn bip39_passphrase_import_recovers_funds_sent_to_independently_derived_address() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let historical_birthday = current_tip_height();
    // Fund the independently derived shielded UA so compact-block scanning
    // proves that the imported seed material decrypts the same account. The
    // independently derived BIP44 transparent address is asserted below and
    // exercised separately by the app-level E2E test.
    fund_wallet(BIP39_VECTOR_REGTEST_UA, "1.0");

    let (imported_dir, imported_wallet) = import_wallet_with_passphrase_and_birthday(
        BIP39_VECTOR_MNEMONIC,
        BIP39_VECTOR_PASSPHRASE,
        "Independent BIP39 vector",
        Some(historical_birthday),
    );
    let imported_db = imported_dir.path().join("zcash_wallet.db");

    // Since 4579a859c the issued address is Orchard-only. It is the vector
    // account's address, derived independently, exactly; and the
    // independently derived reference UA (Sapling + Orchard + transparent),
    // funded above, belongs to the same viewing key.
    assert_eq!(
        imported_wallet.unified_address,
        expected_orchard_only_address()
    );
    let Some(zcash_keys::address::Address::Unified(reference)) =
        zcash_keys::address::Address::decode(
            &rust_lib_zcash_wallet::wallet::network::WalletNetwork::Regtest,
            BIP39_VECTOR_REGTEST_UA,
        )
    else {
        panic!("reference UA does not decode");
    };
    assert_eq!(
        vector_ufvk()
            .orchard()
            .unwrap()
            .scope_for_address(reference.orchard().unwrap()),
        Some(orchard::keys::Scope::External)
    );
    // The same mnemonic and birthday always issue the same address.
    let (_again_dir, again) = import_wallet_with_passphrase_and_birthday(
        BIP39_VECTOR_MNEMONIC,
        BIP39_VECTOR_PASSPHRASE,
        "Independent BIP39 vector",
        Some(historical_birthday),
    );
    assert_eq!(again.unified_address, imported_wallet.unified_address);
    let transparent_address = rust_lib_zcash_wallet::api::wallet::get_transparent_receive_address(
        imported_db.to_str().unwrap().to_string(),
        "regtest".to_string(),
        Some(imported_wallet.account_uuid.clone()),
    )
    .unwrap();
    assert_eq!(transparent_address, BIP39_VECTOR_REGTEST_TADDR);

    sync_wallet(&imported_db);

    let balance = get_balance(&imported_db, &imported_wallet.account_uuid);
    assert!(
        balance.spendable >= 100_000_000,
        "passphrase import should recover independently funded balance, got {}",
        balance.spendable,
    );
    let history = get_transaction_history(&imported_db, &imported_wallet.account_uuid);
    assert!(
        history.iter().any(|tx| tx.account_balance_delta > 0),
        "passphrase import should recover the independently funded transaction",
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn import_wallet_with_historical_birthday_recovers_existing_funds() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let historical_birthday = current_tip_height();
    let (_source_dir, source_wallet) = create_wallet("Import Source");

    fund_wallet(&source_wallet.unified_address, "1.4");
    mine_blocks(15);

    let (imported_dir, imported_wallet) = import_wallet_with_birthday(
        &source_wallet.mnemonic,
        "Imported Account",
        Some(historical_birthday),
    );
    let imported_db = imported_dir.path().join("zcash_wallet.db");

    sync_wallet(&imported_db);

    let balance = get_balance(&imported_db, &imported_wallet.account_uuid);
    assert!(
        balance.spendable >= 140_000_000,
        "imported wallet should recover historical funds, got {}",
        balance.spendable
    );

    let accounts = list_accounts(&imported_db);
    assert_eq!(
        accounts.len(),
        1,
        "imported wallet should expose one account"
    );
    assert_eq!(accounts[0].uuid, imported_wallet.account_uuid);

    let history = get_transaction_history(&imported_db, &imported_wallet.account_uuid);
    assert!(
        history.iter().any(|tx| tx.account_balance_delta > 0),
        "imported wallet should show an inbound historical transaction"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn import_wallet_with_future_birthday_does_not_rescan_old_receive() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (_source_dir, source_wallet) = create_wallet("Future Import Source");
    fund_wallet(&source_wallet.unified_address, "1.2");
    mine_blocks(12);
    let future_birthday = current_tip_height();

    let (imported_dir, imported_wallet) = import_wallet_with_birthday(
        &source_wallet.mnemonic,
        "Future Birthday Import",
        Some(future_birthday),
    );
    let imported_db = imported_dir.path().join("zcash_wallet.db");

    sync_wallet(&imported_db);
    let before_balance = get_balance(&imported_db, &imported_wallet.account_uuid);
    assert_eq!(
        before_balance.spendable, 0,
        "future birthday import should not recover funds that predate its birthday"
    );

    fund_wallet(&imported_wallet.unified_address, "0.8");
    sync_wallet(&imported_db);

    let after_balance = get_balance(&imported_db, &imported_wallet.account_uuid);
    assert!(
        after_balance.spendable >= 80_000_000,
        "future birthday import should still see post-birthday receives, got {}",
        after_balance.spendable
    );

    let history = get_transaction_history(&imported_db, &imported_wallet.account_uuid);
    assert_eq!(
        positive_history_count(&history),
        1,
        "future birthday import should only record the post-birthday receive"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn import_wallet_then_receive_new_funds_after_sync_updates_correctly() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let historical_birthday = current_tip_height();
    let (_source_dir, source_wallet) = create_wallet("Incremental Import Source");
    fund_wallet(&source_wallet.unified_address, "1.1");
    mine_blocks(12);

    let (imported_dir, imported_wallet) = import_wallet_with_birthday(
        &source_wallet.mnemonic,
        "Incremental Import",
        Some(historical_birthday),
    );
    let imported_db = imported_dir.path().join("zcash_wallet.db");

    sync_wallet(&imported_db);
    let before_history = get_transaction_history(&imported_db, &imported_wallet.account_uuid);
    let before_txids = history_txids(&before_history);
    let before_positive = positive_history_count(&before_history);
    let before_balance = get_balance(&imported_db, &imported_wallet.account_uuid);

    fund_wallet(&imported_wallet.unified_address, "0.9");
    sync_wallet(&imported_db);

    let after_history = get_transaction_history(&imported_db, &imported_wallet.account_uuid);
    let after_txids = history_txids(&after_history);
    let after_positive = positive_history_count(&after_history);
    let after_balance = get_balance(&imported_db, &imported_wallet.account_uuid);

    assert!(
        before_txids.iter().all(|txid| after_txids.contains(txid)),
        "incremental import sync should preserve previously recovered history"
    );
    assert_eq!(
        after_positive,
        before_positive + 1,
        "incremental import sync should add exactly one new inbound transaction"
    );
    assert!(
        after_balance.spendable >= before_balance.spendable + 90_000_000,
        "incremental import sync should add new funds on top of historical balance"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn same_mnemonic_imported_into_fresh_db_matches_original_ua_and_balance() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (_source_dir, source_wallet) = create_wallet("Deterministic Source");
    fund_wallet(&source_wallet.unified_address, "1.3");
    mine_blocks(12);

    let (imported_dir, imported_wallet) =
        import_wallet_with_birthday(&source_wallet.mnemonic, "Deterministic Import", Some(1));
    let imported_db = imported_dir.path().join("zcash_wallet.db");
    sync_wallet(&imported_db);

    assert_eq!(
        imported_wallet.unified_address, source_wallet.unified_address,
        "fresh import should derive the same unified address from the same mnemonic"
    );

    let imported_balance = get_balance(&imported_db, &imported_wallet.account_uuid);
    assert!(
        imported_balance.spendable >= 130_000_000,
        "fresh import should recover the same funded balance, got {}",
        imported_balance.spendable
    );
}
