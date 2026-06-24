use std::{
    collections::HashSet,
    path::Path,
    sync::{Mutex, OnceLock},
};

use ::transparent::keys::{IncomingViewingKey as _, NonHardenedChildIndex};
use bip0039::{Count, English, Language, Mnemonic};
use rusqlite::{named_params, OptionalExtension};
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::data_api::{
    chain::ChainState, Account as _, AccountBirthday, AccountPurpose, AccountSource, WalletRead,
    WalletWrite, Zip32Derivation,
};
use zcash_client_sqlite::{error::SqliteClientError, wallet::init::init_wallet_db, AccountUuid};
use zcash_keys::{
    encoding::encode_transparent_address,
    keys::{ReceiverRequirement, UnifiedAddressRequest, UnifiedFullViewingKey, UnifiedSpendingKey},
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkConstants, NetworkUpgrade, Parameters};
use zeroize::Zeroizing;
use zip32::fingerprint::SeedFingerprint;

use crate::wallet::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_db_for_read_with_timeout,
        open_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        ACCOUNT_MUTATION_DB_BUSY_TIMEOUT, READ_DB_BUSY_TIMEOUT, WALLET_DB_BUSY_TIMEOUT,
    },
    network::WalletNetwork,
};

pub(crate) const DUPLICATE_SOFTWARE_ACCOUNT_MESSAGE: &str =
    "This account is already in your wallet.";
const DUPLICATE_KEYSTONE_ACCOUNT_MESSAGE: &str = "This Keystone account is already in your wallet.";
const MIN_MNEMONIC_WORD_COUNT: usize = 12;
const MAX_MNEMONIC_WORD_COUNT: usize = 24;
const MNEMONIC_WORD_COUNT_STEP: usize = 3;
const TRANSPARENT_EXTERNAL_KEY_SCOPE: i64 = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ExternalTransparentAddress {
    pub child_index: u32,
    pub address: String,
    pub has_received: bool,
}

fn map_account_import_error(
    error: SqliteClientError,
    duplicate_message: &str,
    fallback_prefix: &str,
) -> String {
    match error {
        SqliteClientError::AccountCollision(_) => duplicate_message.to_string(),
        other => format!("{fallback_prefix}: {other}"),
    }
}

fn open_wallet_db_for_init(
    db_path: &str,
    network: WalletNetwork,
) -> Result<WalletDatabase, String> {
    open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)
}

fn open_wallet_db_for_mutation(
    db_path: &str,
    network: WalletNetwork,
) -> Result<WalletDatabase, String> {
    open_wallet_db_with_timeout(db_path, network, ACCOUNT_MUTATION_DB_BUSY_TIMEOUT)
}

fn open_wallet_db_for_read(
    db_path: &str,
    network: WalletNetwork,
) -> Result<WalletDatabase, String> {
    open_wallet_db_for_read_with_timeout(db_path, network, READ_DB_BUSY_TIMEOUT)
}

/// Generate a new 24-word BIP-39 mnemonic phrase.
pub fn generate_mnemonic() -> String {
    let mnemonic = Mnemonic::<English>::generate(Count::Words24);
    mnemonic.phrase().to_string()
}

/// Return the BIP-39 English word list used for mnemonic validation.
pub fn mnemonic_word_list() -> Vec<String> {
    English::WORD_LIST
        .iter()
        .map(|word| (*word).to_string())
        .collect()
}

fn is_supported_mnemonic_word_count(count: usize) -> bool {
    count >= MIN_MNEMONIC_WORD_COUNT
        && count <= MAX_MNEMONIC_WORD_COUNT
        && count % MNEMONIC_WORD_COUNT_STEP == 0
}

/// Convert a mnemonic phrase to a 64-byte seed wrapped in SecretVec.
/// The seed is zeroized from memory when the SecretVec is dropped.
pub fn mnemonic_to_seed(phrase: &str) -> Result<SecretVec<u8>, String> {
    let word_count = phrase.split_whitespace().count();
    if !is_supported_mnemonic_word_count(word_count) {
        return Err(
            "Invalid mnemonic word count: expected 12, 15, 18, 21, or 24 words".to_string(),
        );
    }

    let mnemonic =
        Mnemonic::<English>::from_phrase(phrase).map_err(|e| format!("Invalid mnemonic: {e}"))?;
    let seed = Zeroizing::new(mnemonic.to_seed(""));
    drop(mnemonic);
    let secret_seed = SecretVec::new(seed.to_vec());
    drop(seed);
    Ok(secret_seed)
}

/// Convert UTF-8 mnemonic bytes to a 64-byte seed wrapped in SecretVec.
/// The caller remains responsible for zeroizing the input bytes.
pub fn mnemonic_bytes_to_seed(phrase: &[u8]) -> Result<SecretVec<u8>, String> {
    let phrase = std::str::from_utf8(phrase).map_err(|_| "Mnemonic must be valid UTF-8")?;
    mnemonic_to_seed(phrase)
}

/// Parse network string to wallet network enum.
pub fn parse_network(network: &str) -> Result<WalletNetwork, String> {
    WalletNetwork::from_str(network).ok_or_else(|| format!("Unknown network: {network}"))
}

/// Initialize the wallet database schema. Idempotent — safe to call multiple times.
/// Called without seed to avoid SeedNotRelevant errors when only Imported accounts exist.
pub fn ensure_db_initialized(db_path: &str, network: WalletNetwork) -> Result<(), String> {
    with_wallet_db_write_lock("keys.ensure_db_initialized", || {
        let mut db = open_wallet_db_for_init(db_path, network)?;
        init_wallet_db(&mut db, None).map_err(|e| format!("Failed to init wallet DB: {e}"))?;
        Ok(())
    })
}

/// Ensure the wallet DB schema is initialized and migrated once per process.
///
/// This intentionally runs without a seed. Most migrations, including the
/// current zcash_client_sqlite 0.20.x migrations, do not require one; passing an
/// arbitrary seed would be incorrect for Imported-only and multi-seed wallets.
pub fn ensure_db_migrated_once(db_path: &str, network: WalletNetwork) -> Result<(), String> {
    static MIGRATED_DBS: OnceLock<Mutex<HashSet<(String, WalletNetwork)>>> = OnceLock::new();

    let key = (db_path.to_string(), network);
    let migrated_dbs = MIGRATED_DBS.get_or_init(|| Mutex::new(HashSet::new()));
    let mut migrated = match migrated_dbs.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            log::error!("wallet DB migration gate poisoned; continuing");
            poisoned.into_inner()
        }
    };

    if migrated.contains(&key) {
        return Ok(());
    }

    log::info!("wallet DB migration gate: ensuring schema for {db_path}");
    ensure_db_initialized(db_path, network)?;
    migrated.insert(key);
    Ok(())
}

/// Initialize DB with seed for the first account (creates a Derived account).
/// The seed is needed so that seed-requiring migrations can run in the future.
fn ensure_db_initialized_with_seed(
    db_path: &str,
    network: WalletNetwork,
    seed: &SecretVec<u8>,
) -> Result<(), String> {
    with_wallet_db_write_lock("keys.ensure_db_initialized_with_seed", || {
        let mut db = open_wallet_db_for_init(db_path, network)?;
        init_wallet_db(&mut db, Some(SecretVec::new(seed.expose_secret().to_vec())))
            .map_err(|e| format!("Failed to init wallet DB: {e}"))?;
        Ok(())
    })
}

fn make_birthday(network: WalletNetwork, birthday_height: Option<u64>) -> AccountBirthday {
    match birthday_height {
        Some(h) => {
            let height = BlockHeight::from_u32(h as u32);
            let chain_state = ChainState::empty(height - 1, BlockHash([0u8; 32]));
            AccountBirthday::from_parts(chain_state, None)
        }
        None => {
            let sapling_height = network
                .activation_height(NetworkUpgrade::Sapling)
                .expect("Sapling activation height must be known");
            let chain_state = ChainState::empty(sapling_height - 1, BlockHash([0u8; 32]));
            AccountBirthday::from_parts(chain_state, None)
        }
    }
}

fn zip32_account_id(account_index: u32) -> Result<zip32::AccountId, String> {
    zip32::AccountId::try_from(account_index)
        .map_err(|_| format!("Invalid ZIP32 account index: {account_index}"))
}

fn unified_spending_key_for_account(
    network: WalletNetwork,
    seed: &SecretVec<u8>,
    account_index: u32,
) -> Result<UnifiedSpendingKey, String> {
    let account_id = zip32_account_id(account_index)?;
    UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), account_id)
        .map_err(|e| format!("USK derivation failed for account {account_index}: {e:?}"))
}

fn software_account_ufvk(
    network: WalletNetwork,
    seed: &SecretVec<u8>,
    account_index: u32,
) -> Result<UnifiedFullViewingKey, String> {
    Ok(
        unified_spending_key_for_account(network, seed, account_index)?
            .to_unified_full_viewing_key(),
    )
}

/// Return the transparent receiver at `m/44'/coin_type'/account'/0/0`.
pub fn software_account_first_external_transparent_address(
    network: WalletNetwork,
    seed: &SecretVec<u8>,
    account_index: u32,
) -> Result<String, String> {
    let ufvk = software_account_ufvk(network, seed, account_index)?;
    let transparent_key = ufvk
        .transparent()
        .ok_or("Software account does not have a transparent key")?;
    let external_ivk = transparent_key
        .derive_external_ivk()
        .map_err(|e| format!("Failed to derive transparent external IVK: {e}"))?;
    let taddr = external_ivk
        .derive_address(NonHardenedChildIndex::ZERO)
        .map_err(|e| format!("Failed to derive transparent address index 0: {e}"))?;

    Ok(encode_transparent_address(
        &network.b58_pubkey_address_prefix(),
        &network.b58_script_address_prefix(),
        &taddr,
    ))
}

/// Return the standard transparent receivers for `account'` across the first
/// external and internal BIP44 address indexes.
pub fn software_account_transparent_addresses(
    network: WalletNetwork,
    seed: &SecretVec<u8>,
    account_index: u32,
    address_count_per_scope: u32,
) -> Result<Vec<String>, String> {
    let ufvk = software_account_ufvk(network, seed, account_index)?;
    let transparent_key = ufvk
        .transparent()
        .ok_or("Software account does not have a transparent key")?;
    let external_ivk = transparent_key
        .derive_external_ivk()
        .map_err(|e| format!("Failed to derive transparent external IVK: {e}"))?;
    let internal_ivk = transparent_key
        .derive_internal_ivk()
        .map_err(|e| format!("Failed to derive transparent internal IVK: {e}"))?;

    let mut addresses = Vec::with_capacity(address_count_per_scope as usize * 2);
    for i in 0..address_count_per_scope {
        let child_index = NonHardenedChildIndex::from_index(i)
            .ok_or_else(|| format!("Invalid transparent address index: {i}"))?;
        let external_taddr = external_ivk
            .derive_address(child_index)
            .map_err(|e| format!("Failed to derive transparent external address {i}: {e}"))?;
        addresses.push(encode_transparent_address(
            &network.b58_pubkey_address_prefix(),
            &network.b58_script_address_prefix(),
            &external_taddr,
        ));

        let internal_taddr = internal_ivk
            .derive_address(child_index)
            .map_err(|e| format!("Failed to derive transparent internal address {i}: {e}"))?;
        addresses.push(encode_transparent_address(
            &network.b58_pubkey_address_prefix(),
            &network.b58_script_address_prefix(),
            &internal_taddr,
        ));
    }

    Ok(addresses)
}

fn import_ufvk_account(
    db_path: &str,
    network: WalletNetwork,
    name: &str,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
    account_index: u32,
) -> Result<(String, String), String> {
    let birthday = make_birthday(network, birthday_height);
    let seed_fp = SeedFingerprint::from_seed(seed.expose_secret())
        .ok_or("Invalid seed length for fingerprint")?;
    let account_id = zip32_account_id(account_index)?;
    let ufvk = software_account_ufvk(network, seed, account_index)?;
    let derivation = Zip32Derivation::new(seed_fp, account_id);
    let purpose = AccountPurpose::Spending {
        derivation: Some(derivation),
    };
    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    let account_id = with_wallet_db_write_lock("keys.import_ufvk_account", || {
        let mut db = open_wallet_db_for_mutation(db_path, network)?;
        let account = db
            .import_account_ufvk(name, &ufvk, &birthday, purpose, None)
            .map_err(|e| {
                map_account_import_error(
                    e,
                    DUPLICATE_SOFTWARE_ACCOUNT_MESSAGE,
                    "Failed to import account",
                )
            })?;
        Ok::<_, String>(account.id())
    })?;

    Ok((account_id.expose_uuid().to_string(), ua.encode(&network)))
}

/// Add an additional account (from a different seed) to the wallet database.
/// Uses import_account_ufvk with AccountPurpose::Spending so that accounts from
/// different seeds can coexist in the same DB (create_account enforces single-seed).
/// The first account should be created via init_db_and_create_account (Derived).
pub fn add_account(
    db_path: &str,
    network: WalletNetwork,
    name: &str,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
) -> Result<(String, String), String> {
    add_account_at_index(db_path, network, name, seed, birthday_height, 0)
}

/// Add a software account for a specific ZIP32 account index as an imported UFVK.
pub fn add_account_at_index(
    db_path: &str,
    network: WalletNetwork,
    name: &str,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
    account_index: u32,
) -> Result<(String, String), String> {
    import_ufvk_account(db_path, network, name, seed, birthday_height, account_index)
}

/// Import a hardware wallet account using a UFVK string (no seed/mnemonic needed).
/// The UFVK is obtained from the hardware device. Seed fingerprint and zip32 index
/// are provided by the device for Zip32Derivation metadata.
///
/// Hardware accounts may be the first account in the wallet. If no `Derived`
/// account exists yet, this can leave the wallet DB containing only `Imported`
/// accounts. Callers accept the future seed-requiring migration recovery
/// tradeoff for Keystone-first onboarding.
pub fn import_hardware_account(
    db_path: &str,
    network: WalletNetwork,
    name: &str,
    ufvk_string: &str,
    seed_fingerprint_bytes: &[u8],
    zip32_index: u32,
    birthday_height: Option<u64>,
) -> Result<(String, String), String> {
    // Ensure DB is initialized (without seed — hardware wallet has no local seed)
    ensure_db_migrated_once(db_path, network)?;

    let birthday = make_birthday(network, birthday_height);

    // Parse UFVK from string
    let ufvk = zcash_keys::keys::UnifiedFullViewingKey::decode(&network, ufvk_string)
        .map_err(|e| format!("Failed to parse UFVK: {e}"))?;

    // Build seed fingerprint from bytes
    let fp_bytes: [u8; 32] = seed_fingerprint_bytes
        .try_into()
        .map_err(|_| "Seed fingerprint must be 32 bytes")?;
    let seed_fp = SeedFingerprint::from_bytes(fp_bytes);
    let account_index =
        zip32::AccountId::try_from(zip32_index).map_err(|_| "Invalid zip32 account index")?;

    let derivation = Zip32Derivation::new(seed_fp, account_index);
    let purpose = AccountPurpose::Spending {
        derivation: Some(derivation),
    };

    let account_id = with_wallet_db_write_lock("keys.import_hardware_account", || {
        let mut db = open_wallet_db_for_mutation(db_path, network)?;

        let account = db
            .import_account_ufvk(name, &ufvk, &birthday, purpose, None)
            .map_err(|e| {
                map_account_import_error(
                    e,
                    DUPLICATE_KEYSTONE_ACCOUNT_MESSAGE,
                    "Failed to import hardware account",
                )
            })?;
        Ok::<_, String>(account.id())
    })?;
    // Hardware wallets (Keystone) have Orchard + transparent but no Sapling,
    // so use Orchard-only address request instead of the standard shielded request.
    let (ua, _di) = ufvk
        .default_address(orchard_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    let uuid_str = account_id.expose_uuid().to_string();
    let addr_str: String = ua.encode(&network);
    log::info!(
        "Imported hardware account: uuid={}, address={}",
        uuid_str,
        addr_str
    );
    Ok((uuid_str, addr_str))
}

/// Init DB + create first account as Derived (so seed relevance checks pass on future migrations).
/// Returns (account_uuid, unified_address).
pub fn init_db_and_create_account(
    db_path: &str,
    network: WalletNetwork,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
    name: &str,
) -> Result<(String, String), String> {
    ensure_db_initialized_with_seed(db_path, network, seed)?;

    let birthday = make_birthday(network, birthday_height);

    let (account_id, usk) = with_wallet_db_write_lock("keys.create_account", || {
        let mut db = open_wallet_db_for_mutation(db_path, network)?;

        // First account uses create_account (Derived) — ensures at least one Derived account
        // exists for future init_wallet_db seed relevance checks.
        db.create_account(name, seed, &birthday, None)
            .map_err(|e| format!("Failed to create account: {e}"))
    })?;

    let ufvk = usk.to_unified_full_viewing_key();
    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    let uuid_str = account_id.expose_uuid().to_string();
    Ok((uuid_str, ua.encode(&network)))
}

/// Import a same-seed software account for a specific ZIP32 account index as a
/// derived account. This is used only after the first seed-anchor account has
/// initialized the wallet DB with the same seed.
pub fn import_derived_account_at_index(
    db_path: &str,
    network: WalletNetwork,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
    name: &str,
    account_index: u32,
) -> Result<(String, String), String> {
    let birthday = make_birthday(network, birthday_height);
    let account_id = zip32_account_id(account_index)?;
    let ufvk = software_account_ufvk(network, seed, account_index)?;
    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    let account = with_wallet_db_write_lock("keys.import_derived_account_at_index", || {
        let mut db = open_wallet_db_for_mutation(db_path, network)?;
        db.import_account_hd(name, seed, account_id, &birthday, None)
            .map(|(account, _usk)| account)
            .map_err(|e| format!("Failed to import derived account: {e}"))
    })?;

    Ok((account.id().expose_uuid().to_string(), ua.encode(&network)))
}

pub struct AccountInfo {
    pub uuid: String,
    pub name: String,
    pub unified_address: String,
    pub is_seed_anchor: bool,
    pub is_hardware: bool,
}

pub struct SoftwareSeedAccountState {
    pub account_indices: HashSet<u32>,
    pub has_derived_account: bool,
}

impl SoftwareSeedAccountState {
    pub fn is_empty(&self) -> bool {
        self.account_indices.is_empty()
    }

    pub fn contains(&self, account_index: u32) -> bool {
        self.account_indices.contains(&account_index)
    }
}

pub fn existing_software_seed_account_state(
    db_path: &str,
    network: WalletNetwork,
    seed: &SecretVec<u8>,
) -> Result<SoftwareSeedAccountState, String> {
    let seed_fp = SeedFingerprint::from_seed(seed.expose_secret())
        .ok_or("Invalid seed length for fingerprint")?;
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_ids = db
        .get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;

    let mut account_indices = HashSet::new();
    let mut has_derived_account = false;
    for id in account_ids {
        let account = db
            .get_account(id)
            .map_err(|e| format!("Failed to get account: {e}"))?
            .ok_or_else(|| format!("Account not found: {}", id.expose_uuid()))?;
        let Some(derivation) = account.source().key_derivation() else {
            continue;
        };
        if derivation.seed_fingerprint() != &seed_fp {
            continue;
        }

        account_indices.insert(u32::from(derivation.account_index()));
        if matches!(account.source(), AccountSource::Derived { .. }) {
            has_derived_account = true;
        }
    }

    Ok(SoftwareSeedAccountState {
        account_indices,
        has_derived_account,
    })
}

/// List all accounts in the wallet database.
pub fn list_accounts(db_path: &str, network: WalletNetwork) -> Result<Vec<AccountInfo>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;

    let account_ids = db
        .get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;

    let mut accounts = Vec::new();
    for id in account_ids {
        let account = db
            .get_account(id)
            .map_err(|e| format!("Failed to get account: {e}"))?
            .ok_or_else(|| format!("Account not found: {}", id.expose_uuid()))?;

        let (address, is_hardware) = match account.ufvk() {
            Some(ufvk) => (
                current_receive_address(&db, network, id, ufvk)?,
                is_keystone_style_ufvk(ufvk),
            ),
            None => (String::new(), false),
        };

        accounts.push(AccountInfo {
            uuid: id.expose_uuid().to_string(),
            name: account.name().unwrap_or("").to_string(),
            unified_address: address,
            is_seed_anchor: matches!(account.source(), AccountSource::Derived { .. }),
            is_hardware,
        });
    }

    Ok(accounts)
}

pub fn list_account_uuids_from_db(db_path: &str) -> Result<Vec<String>, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))?;
    let mut stmt = conn
        .prepare("SELECT uuid FROM accounts ORDER BY id ASC")
        .map_err(|e| format!("Failed to prepare account UUID query: {e}"))?;
    let rows = stmt
        .query_map([], |row| row.get::<_, Vec<u8>>(0))
        .map_err(|e| format!("Failed to list account UUIDs: {e}"))?;

    let mut uuids = Vec::new();
    for row in rows {
        let bytes = row.map_err(|e| format!("Failed to read account UUID: {e}"))?;
        let uuid = uuid::Uuid::from_slice(&bytes)
            .map_err(|e| format!("Invalid account UUID bytes in DB: {e}"))?;
        uuids.push(uuid.to_string());
    }
    Ok(uuids)
}

/// Delete an account from the wallet database.
pub fn delete_account(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<(), String> {
    let account_id = parse_account_uuid(account_uuid)?;
    with_wallet_db_write_lock("keys.delete_account", || {
        let db = open_wallet_db_for_mutation(db_path, network)?;
        let target = db
            .get_account(account_id)
            .map_err(|e| format!("Failed to load account: {e}"))?
            .ok_or_else(|| format!("Account not found: {}", account_id.expose_uuid()))?;
        let account_ids = db
            .get_account_ids()
            .map_err(|e| format!("Failed to list accounts: {e}"))?;

        if matches!(target.source(), AccountSource::Derived { .. }) {
            let mut has_remaining_accounts = false;
            let mut has_other_seed_anchor = false;
            for id in &account_ids {
                if *id == account_id {
                    continue;
                }
                has_remaining_accounts = true;
                let account = db
                    .get_account(*id)
                    .map_err(|e| format!("Failed to load account: {e}"))?
                    .ok_or_else(|| format!("Account not found: {}", id.expose_uuid()))?;
                if matches!(account.source(), AccountSource::Derived { .. }) {
                    has_other_seed_anchor = true;
                    break;
                }
            }

            if has_remaining_accounts && !has_other_seed_anchor {
                return Err(
                    "The last seed anchor account cannot be removed while other accounts remain."
                        .into(),
                );
            }
        }

        // zcash_client_sqlite 0.19.5 has a named-parameter bug in
        // wallet::delete_account: the sent_notes rewrite binds `:address`
        // while the SQL expects `:to_address`. Keep this local copy aligned
        // with upstream except for that binding until the dependency is fixed.
        drop(db);
        delete_account_rows(db_path, account_id)
    })
}

fn delete_account_rows(db_path: &str, account_id: AccountUuid) -> Result<(), String> {
    let mut conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    conn.busy_timeout(ACCOUNT_MUTATION_DB_BUSY_TIMEOUT)
        .map_err(|e| format!("Failed to configure wallet DB busy timeout: {e}"))?;
    rusqlite::vtab::array::load_module(&conn)
        .map_err(|e| format!("Failed to load SQLite array module: {e}"))?;
    conn.execute("PRAGMA foreign_keys = ON", [])
        .map_err(|e| format!("Failed to enable SQLite foreign keys: {e}"))?;

    let tx = conn
        .transaction()
        .map_err(|e| format!("Failed to begin account delete transaction: {e}"))?;
    let account_uuid = account_id.expose_uuid();
    let account_uuid_bytes = account_uuid.as_bytes().as_slice();

    {
        let mut to_account_tx = tx
            .prepare(
                r#"
                SELECT
                    sn.id AS sent_note_id,
                    COALESCE(addresses.address, addresses.cached_transparent_receiver_address) AS to_address
                FROM sent_notes sn
                JOIN v_received_outputs ro ON ro.sent_note_id = sn.id
                JOIN addresses ON addresses.id = ro.address_id
                JOIN accounts ta ON ta.id = sn.to_account_id
                WHERE ta.uuid = :account_uuid
                "#,
            )
            .map_err(|e| format!("Failed to prepare sent note rewrite query: {e}"))?;

        let mut update_sent_note = tx
            .prepare(
                r#"
                UPDATE sent_notes
                SET to_address = :to_address, to_account_id = NULL
                WHERE id = :sent_note_id
                "#,
            )
            .map_err(|e| format!("Failed to prepare sent note rewrite update: {e}"))?;

        let mut rows = to_account_tx
            .query(named_params![":account_uuid": account_uuid_bytes])
            .map_err(|e| format!("Failed to query sent notes for account deletion: {e}"))?;
        while let Some(row) = rows
            .next()
            .map_err(|e| format!("Failed to read sent notes for account deletion: {e}"))?
        {
            if let Some(address) = row
                .get::<_, Option<String>>("to_address")
                .map_err(|e| format!("Failed to read sent note destination address: {e}"))?
            {
                update_sent_note
                    .execute(named_params![
                        ":sent_note_id": row
                            .get::<_, i64>("sent_note_id")
                            .map_err(|e| format!("Failed to read sent note id: {e}"))?,
                        ":to_address": address,
                    ])
                    .map_err(|e| format!("Failed to rewrite sent note destination: {e}"))?;
            }
        }
    }

    tx.execute(
        r#"
        WITH account_transactions AS (
            SELECT ro.transaction_id
            FROM v_received_outputs ro
            JOIN accounts a ON a.id = ro.account_id
            WHERE a.uuid = :account_uuid
            UNION
            SELECT ros.transaction_id
            FROM v_received_output_spends ros
            JOIN accounts sa ON sa.id = ros.account_id
            WHERE sa.uuid = :account_uuid
        ),
        non_account_transactions AS (
            SELECT ro.transaction_id
            FROM v_received_outputs ro
            JOIN accounts a ON a.id = ro.account_id
            WHERE a.uuid != :account_uuid
            UNION
            SELECT ros.transaction_id
            FROM v_received_output_spends ros
            JOIN accounts sa ON sa.id = ros.account_id
            WHERE sa.uuid != :account_uuid
        )
        DELETE FROM transactions WHERE id_tx IN (
            SELECT transaction_id FROM account_transactions
            EXCEPT
            SELECT transaction_id FROM non_account_transactions
        )
        "#,
        named_params![":account_uuid": account_uuid_bytes],
    )
    .map_err(|e| format!("Failed to delete account-only transactions: {e}"))?;

    tx.execute(
        "DELETE FROM accounts WHERE uuid = :account_uuid",
        named_params![":account_uuid": account_uuid_bytes],
    )
    .map_err(|e| format!("Failed to delete account: {e}"))?;

    tx.commit()
        .map_err(|e| format!("Failed to commit account deletion: {e}"))
}

/// Parse an account UUID string into AccountUuid.
pub fn parse_account_uuid(s: &str) -> Result<AccountUuid, String> {
    let uuid = uuid::Uuid::parse_str(s).map_err(|e| format!("Invalid account UUID: {e}"))?;
    Ok(AccountUuid::from_uuid(uuid))
}

/// Resolve account_id: if uuid provided, parse it; otherwise take first account.
fn resolve_account_id(
    db: &WalletDatabase,
    account_uuid: Option<&str>,
) -> Result<AccountUuid, String> {
    match account_uuid {
        Some(uuid_str) => parse_account_uuid(uuid_str),
        None => {
            let ids = db
                .get_account_ids()
                .map_err(|e| format!("Failed to list accounts: {e}"))?;
            ids.into_iter()
                .next()
                .ok_or_else(|| "No accounts found in wallet".to_string())
        }
    }
}

fn resolve_account_uuid_bytes_for_read(
    conn: &rusqlite::Connection,
    account_uuid: Option<&str>,
) -> Result<Vec<u8>, String> {
    match account_uuid {
        Some(uuid_str) => {
            let account_id = parse_account_uuid(uuid_str)?;
            Ok(account_id.expose_uuid().as_bytes().to_vec())
        }
        None => conn
            .query_row(
                "SELECT uuid FROM accounts ORDER BY id ASC LIMIT 1",
                [],
                |row| row.get::<_, Vec<u8>>(0),
            )
            .optional()
            .map_err(|e| format!("Failed to resolve first account: {e}"))?
            .ok_or_else(|| "No accounts found in wallet".to_string()),
    }
}

/// Get the Unified Address from an existing wallet database.
pub fn get_address_from_db(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: Option<&str>,
) -> Result<String, String> {
    let db = open_wallet_db_for_read(db_path, network)?;

    let account_id = resolve_account_id(&db, account_uuid)?;

    let account = db
        .get_account(account_id)
        .map_err(|e| format!("Failed to get account: {e}"))?
        .ok_or("Account not found")?;

    let ufvk = account.ufvk().ok_or("Account does not have a UFVK")?;

    current_receive_address(&db, network, account_id, ufvk)
}

fn current_receive_address(
    db: &WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    ufvk: &UnifiedFullViewingKey,
) -> Result<String, String> {
    let address = match ufvk.default_address(shielded_address_request()) {
        Ok((default, _)) => {
            let last = db
                .get_last_generated_address_matching(account_id, shielded_address_request())
                .map_err(|e| format!("Failed to get last generated shielded address: {e}"))?;
            last.unwrap_or(default)
        }
        Err(shielded_err) => {
            let (default, _) =
                ufvk.default_address(orchard_address_request())
                    .map_err(|orchard_err| {
                        format!(
                            "Failed to derive shielded address: {shielded_err}; \
                         orchard fallback failed: {orchard_err}"
                        )
                    })?;
            let last = db
                .get_last_generated_address_matching(account_id, orchard_address_request())
                .map_err(|e| format!("Failed to get last generated orchard address: {e}"))?;
            last.unwrap_or(default)
        }
    };

    Ok(address.encode(&network))
}

fn is_keystone_style_ufvk(ufvk: &UnifiedFullViewingKey) -> bool {
    ufvk.orchard().is_some() && ufvk.sapling().is_none()
}

/// Returns the standard shielded address request (Orchard + Sapling, no transparent).
/// This matches the behavior of zodl/Zashi wallets.
fn shielded_address_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require, // Orchard
        ReceiverRequirement::Require, // Sapling
        ReceiverRequirement::Omit,    // Transparent
    )
    .expect("valid receiver requirements")
}

/// Returns an Orchard-only address request for hardware wallets.
/// Keystone UFVKs typically contain Orchard + transparent but no Sapling.
fn orchard_address_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require, // Orchard
        ReceiverRequirement::Omit,    // Sapling (not available on Keystone)
        ReceiverRequirement::Omit,    // Transparent
    )
    .expect("valid receiver requirements")
}

/// Get the transparent address from an existing wallet database.
pub fn get_transparent_address_from_db(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: Option<&str>,
) -> Result<String, String> {
    let db = open_wallet_db_for_read(db_path, network)?;

    let account_id = resolve_account_id(&db, account_uuid)?;

    let current_ua = db
        .get_last_generated_address_matching(account_id, UnifiedAddressRequest::AllAvailableKeys)
        .map_err(|e| format!("Failed to get current generated address: {e}"))?
        .ok_or_else(|| "No tracked transparent address available".to_string())?;
    let taddr = current_ua.transparent().ok_or_else(|| {
        "Current generated address does not include a transparent receiver".to_string()
    })?;

    Ok(encode_transparent_address(
        &network.b58_pubkey_address_prefix(),
        &network.b58_script_address_prefix(),
        taddr,
    ))
}

/// Get the first external transparent receive address that has no received output.
///
/// zcash_client_sqlite pre-generates external transparent gap-limit rows for
/// each account. This function intentionally reads those rows without calling
/// get_next_available_address, so displaying receive UI does not reserve or
/// expose a new address.
pub fn get_transparent_receive_address_from_db(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: Option<&str>,
) -> Result<String, String> {
    let addresses =
        get_external_transparent_receive_addresses_from_db(db_path, network, account_uuid)?;
    first_unused_external_transparent_address(&addresses)
        .ok_or_else(|| "No unused external transparent receive address available".to_string())
}

pub(crate) fn get_external_transparent_receive_addresses_from_db(
    db_path: &str,
    _network: WalletNetwork,
    account_uuid: Option<&str>,
) -> Result<Vec<ExternalTransparentAddress>, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))?;
    let account_uuid_bytes = resolve_account_uuid_bytes_for_read(&conn, account_uuid)?;

    let mut stmt = conn
        .prepare(
            r#"
            SELECT a.transparent_child_index,
                   a.cached_transparent_receiver_address,
                   EXISTS (
                       SELECT 1
                       FROM transparent_received_outputs tro
                       WHERE tro.address_id = a.id
                   ) AS has_received
            FROM addresses a
            JOIN accounts acct ON acct.id = a.account_id
            WHERE acct.uuid = :account_uuid
              AND a.key_scope = :external_scope
              AND a.transparent_child_index IS NOT NULL
              AND a.cached_transparent_receiver_address IS NOT NULL
            ORDER BY a.transparent_child_index ASC
            "#,
        )
        .map_err(|e| format!("Failed to prepare external transparent address query: {e}"))?;

    let rows = stmt
        .query_map(
            named_params! {
                ":account_uuid": account_uuid_bytes.as_slice(),
                ":external_scope": TRANSPARENT_EXTERNAL_KEY_SCOPE,
            },
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)? != 0,
                ))
            },
        )
        .map_err(|e| format!("Failed to get external transparent addresses: {e}"))?;

    let mut addresses = Vec::new();
    for row in rows {
        let (child_index, address, has_received) =
            row.map_err(|e| format!("Failed to read external transparent address: {e}"))?;
        let child_index = u32::try_from(child_index)
            .map_err(|e| format!("Invalid transparent child index {child_index}: {e}"))?;
        addresses.push(ExternalTransparentAddress {
            child_index,
            address,
            has_received,
        });
    }

    Ok(addresses)
}

pub fn get_recent_transparent_receive_addresses_from_db(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: Option<&str>,
    limit: u32,
) -> Result<Vec<String>, String> {
    if limit == 0 {
        return Ok(Vec::new());
    }
    let addresses =
        get_external_transparent_receive_addresses_from_db(db_path, network, account_uuid)?;
    Ok(recent_external_transparent_addresses(
        &addresses,
        limit.min(100) as usize,
    ))
}

pub(crate) fn first_unused_external_transparent_address(
    addresses: &[ExternalTransparentAddress],
) -> Option<String> {
    addresses
        .iter()
        .filter(|address| !address.has_received)
        .min_by_key(|address| address.child_index)
        .map(|address| address.address.clone())
}

pub(crate) fn recent_external_transparent_addresses(
    addresses: &[ExternalTransparentAddress],
    limit: usize,
) -> Vec<String> {
    if limit == 0 {
        return Vec::new();
    }

    let Some(latest_index) = addresses
        .iter()
        .filter(|address| !address.has_received)
        .map(|address| address.child_index)
        .min()
        .or_else(|| addresses.iter().map(|address| address.child_index).max())
    else {
        return Vec::new();
    };

    let mut recent = addresses
        .iter()
        .filter(|address| address.child_index <= latest_index)
        .collect::<Vec<_>>();
    recent.sort_by_key(|address| std::cmp::Reverse(address.child_index));
    recent
        .into_iter()
        .take(limit)
        .map(|address| address.address.clone())
        .collect()
}

/// Validate that a wallet database exists and has at least one account.
pub fn wallet_exists(db_path: &str) -> bool {
    Path::new(db_path).exists()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_mnemonic_is_24_words() {
        let phrase = generate_mnemonic();
        let words: Vec<&str> = phrase.split_whitespace().collect();
        assert_eq!(words.len(), 24);
    }

    #[test]
    fn test_mnemonic_to_seed_roundtrip() {
        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        assert_eq!(seed.expose_secret().len(), 64);
    }

    #[test]
    fn test_mnemonic_to_seed_accepts_supported_word_counts() {
        for count in [
            Count::Words12,
            Count::Words15,
            Count::Words18,
            Count::Words21,
            Count::Words24,
        ] {
            let phrase = Mnemonic::<English>::generate(count).phrase().to_string();
            let seed = mnemonic_to_seed(&phrase).unwrap();
            assert_eq!(seed.expose_secret().len(), 64);
        }
    }

    #[test]
    fn test_mnemonic_to_seed_rejects_unsupported_word_counts() {
        for count in [11, 13, 25] {
            let phrase = std::iter::repeat("abandon")
                .take(count)
                .collect::<Vec<_>>()
                .join(" ");
            let error = match mnemonic_to_seed(&phrase) {
                Ok(_) => panic!("unsupported mnemonic word count should be rejected"),
                Err(error) => error,
            };
            assert!(error.contains("expected 12, 15, 18, 21, or 24 words"));
        }
    }

    #[test]
    fn test_invalid_mnemonic() {
        let result = mnemonic_to_seed("invalid words here");
        assert!(result.is_err());
    }

    #[test]
    fn test_parse_network() {
        assert!(matches!(parse_network("main"), Ok(WalletNetwork::Main)));
        assert!(matches!(parse_network("test"), Ok(WalletNetwork::Test)));
        assert!(matches!(
            parse_network("regtest"),
            Ok(WalletNetwork::Regtest)
        ));
        assert!(parse_network("invalid").is_err());
    }

    #[test]
    fn test_create_wallet_and_get_address() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let (_uuid, address) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();

        // Mainnet unified addresses start with "u1"
        assert!(
            address.starts_with("u1"),
            "Expected u1 prefix, got: {address}"
        );

        // Verify we can read the address back
        let address2 = get_address_from_db(db_path_str, WalletNetwork::Main, None).unwrap();
        assert_eq!(address, address2);
    }

    #[test]
    fn test_software_first_external_transparent_address_uses_zip32_account_index() {
        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let account_0 =
            software_account_first_external_transparent_address(WalletNetwork::Main, &seed, 0)
                .unwrap();
        let account_1 =
            software_account_first_external_transparent_address(WalletNetwork::Main, &seed, 1)
                .unwrap();

        assert!(account_0.starts_with("t1"));
        assert!(account_1.starts_with("t1"));
        assert_ne!(account_0, account_1);
    }

    #[test]
    fn test_software_transparent_address_preview_range_includes_first_external_address() {
        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let first_external =
            software_account_first_external_transparent_address(WalletNetwork::Main, &seed, 1)
                .unwrap();
        let addresses =
            software_account_transparent_addresses(WalletNetwork::Main, &seed, 1, 2).unwrap();

        assert_eq!(addresses.len(), 4);
        assert_eq!(addresses[0], first_external);
        assert!(addresses.iter().all(|address| address.starts_with("t1")));
        assert_eq!(
            addresses.iter().collect::<HashSet<_>>().len(),
            addresses.len()
        );
    }

    #[test]
    fn test_import_derived_account_at_index_records_zip32_index() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "first").unwrap();
        let (uuid, _address) = import_derived_account_at_index(
            db_path_str,
            WalletNetwork::Main,
            &seed,
            None,
            "third",
            2,
        )
        .unwrap();

        let listed_account = list_accounts(db_path_str, WalletNetwork::Main)
            .unwrap()
            .into_iter()
            .find(|account| account.uuid == uuid)
            .unwrap();
        assert!(listed_account.is_seed_anchor);

        let account_id = parse_account_uuid(&uuid).unwrap();
        let db = open_wallet_db_for_read(db_path_str, WalletNetwork::Main).unwrap();
        let account = db.get_account(account_id).unwrap().unwrap();
        let derivation = account.source().key_derivation().unwrap();
        assert_eq!(u32::from(derivation.account_index()), 2);
    }

    #[test]
    fn test_get_address_returns_last_generated_receive_address() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let (uuid, default_address) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();

        crate::wallet::sync::update_chain_tip(db_path_str, WalletNetwork::Main, 2_500_000).unwrap();
        let renewed_address = crate::wallet::sync::get_next_available_address(
            db_path_str,
            WalletNetwork::Main,
            &uuid,
            crate::wallet::sync::AddressRequestKind::Shielded,
        )
        .unwrap();

        assert_ne!(default_address, renewed_address);
        assert_eq!(
            renewed_address,
            get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap()
        );
        assert_eq!(
            renewed_address,
            list_accounts(db_path_str, WalletNetwork::Main)
                .unwrap()
                .into_iter()
                .find(|account| account.uuid == uuid)
                .unwrap()
                .unified_address
        );
    }

    #[test]
    fn test_get_transparent_receive_address_returns_first_unused_external_address() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        let (uuid, _) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();

        let conn = rusqlite::Connection::open(db_path_str).unwrap();
        let (_, first_external, exposed_before) = external_transparent_address_row(&conn, &uuid, 0);

        let receive_address =
            get_transparent_receive_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid))
                .unwrap();
        let (_, _, exposed_after) = external_transparent_address_row(&conn, &uuid, 0);

        assert_eq!(receive_address, first_external);
        assert_eq!(exposed_after, exposed_before);
    }

    #[test]
    fn test_get_transparent_receive_address_skips_received_external_address() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        let (uuid, _) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();

        let conn = rusqlite::Connection::open(db_path_str).unwrap();
        conn.execute("PRAGMA foreign_keys = ON", []).unwrap();
        let (first_id, first_external, _) = external_transparent_address_row(&conn, &uuid, 0);
        let (_, second_external, second_exposed_before) =
            external_transparent_address_row(&conn, &uuid, 1);

        mark_transparent_address_received(&conn, &uuid, first_id, &first_external, 1);

        let receive_address =
            get_transparent_receive_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid))
                .unwrap();
        let (_, _, second_exposed_after) = external_transparent_address_row(&conn, &uuid, 1);

        assert_eq!(receive_address, second_external);
        assert_eq!(second_exposed_after, second_exposed_before);
    }

    #[test]
    fn test_get_recent_transparent_receive_addresses_walks_down_from_current_receive() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        let (uuid, _) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();

        let conn = rusqlite::Connection::open(db_path_str).unwrap();
        conn.execute("PRAGMA foreign_keys = ON", []).unwrap();
        let rows = external_transparent_address_rows(&conn, &uuid);
        assert!(rows.len() >= 4);

        mark_transparent_address_received(&conn, &uuid, rows[0].0, &rows[0].1, 1);
        mark_transparent_address_received(&conn, &uuid, rows[1].0, &rows[1].1, 2);

        let recent = get_recent_transparent_receive_addresses_from_db(
            db_path_str,
            WalletNetwork::Main,
            Some(&uuid),
            3,
        )
        .unwrap();

        assert_eq!(
            recent,
            vec![rows[2].1.clone(), rows[1].1.clone(), rows[0].1.clone()]
        );
    }

    #[test]
    fn test_get_recent_transparent_receive_addresses_honors_limit() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        let (uuid, _) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();

        let conn = rusqlite::Connection::open(db_path_str).unwrap();
        conn.execute("PRAGMA foreign_keys = ON", []).unwrap();
        let rows = external_transparent_address_rows(&conn, &uuid);
        assert!(rows.len() >= 4);
        mark_transparent_address_received(&conn, &uuid, rows[0].0, &rows[0].1, 1);
        mark_transparent_address_received(&conn, &uuid, rows[1].0, &rows[1].1, 2);
        mark_transparent_address_received(&conn, &uuid, rows[2].0, &rows[2].1, 3);

        let recent = get_recent_transparent_receive_addresses_from_db(
            db_path_str,
            WalletNetwork::Main,
            Some(&uuid),
            2,
        )
        .unwrap();

        assert_eq!(recent, vec![rows[3].1.clone(), rows[2].1.clone()]);
    }

    #[test]
    fn test_get_transparent_receive_address_does_not_return_internal_or_ephemeral() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        let (uuid, _) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();

        let conn = rusqlite::Connection::open(db_path_str).unwrap();
        conn.execute("PRAGMA foreign_keys = ON", []).unwrap();
        let account_id = account_row_id(&conn, &uuid);
        let non_external_count: i64 = conn
            .query_row(
                r#"
                SELECT COUNT(*)
                FROM addresses
                WHERE account_id = ?1
                  AND key_scope IN (1, 2)
                  AND cached_transparent_receiver_address IS NOT NULL
                "#,
                rusqlite::params![account_id],
                |row| row.get(0),
            )
            .unwrap();
        assert!(non_external_count > 0);

        let external_rows = external_transparent_address_rows(&conn, &uuid);
        assert!(!external_rows.is_empty());
        for (index, (address_id, address)) in external_rows.iter().enumerate() {
            mark_transparent_address_received(&conn, &uuid, *address_id, address, index as u32);
        }

        let error =
            get_transparent_receive_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid))
                .unwrap_err();
        assert!(error.contains("No unused external transparent receive address available"));
    }

    #[test]
    fn test_get_next_available_address_rotates_keystone_style_imported_account() {
        use zcash_address::unified::{Encoding, Fvk, Ufvk};
        use zcash_protocol::consensus::NetworkType;

        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        let account_index = zip32::AccountId::ZERO;
        let usk = UnifiedSpendingKey::from_seed(
            &WalletNetwork::Main,
            seed.expose_secret(),
            account_index,
        )
        .unwrap();
        let full_ufvk = usk.to_unified_full_viewing_key();
        let orchard_fvk = full_ufvk.orchard().unwrap().to_bytes();
        let transparent_fvk = full_ufvk
            .transparent()
            .unwrap()
            .serialize()
            .try_into()
            .unwrap();
        let keystone_style_ufvk =
            Ufvk::try_from_items(vec![Fvk::Orchard(orchard_fvk), Fvk::P2pkh(transparent_fvk)])
                .unwrap()
                .encode(&NetworkType::Main);
        let seed_fingerprint = SeedFingerprint::from_seed(seed.expose_secret())
            .unwrap()
            .to_bytes();

        let (uuid, default_address) = import_hardware_account(
            db_path_str,
            WalletNetwork::Main,
            "Keystone",
            &keystone_style_ufvk,
            &seed_fingerprint,
            u32::from(account_index),
            None,
        )
        .unwrap();
        let listed_account = list_accounts(db_path_str, WalletNetwork::Main)
            .unwrap()
            .into_iter()
            .find(|account| account.uuid == uuid)
            .unwrap();
        assert!(listed_account.is_hardware);

        crate::wallet::sync::update_chain_tip(db_path_str, WalletNetwork::Main, 2_500_000).unwrap();
        let shielded_error = crate::wallet::sync::get_next_available_address(
            db_path_str,
            WalletNetwork::Main,
            &uuid,
            crate::wallet::sync::AddressRequestKind::Shielded,
        )
        .unwrap_err();
        assert!(shielded_error.contains("Sapling"));

        let renewed_address = crate::wallet::sync::get_next_available_address(
            db_path_str,
            WalletNetwork::Main,
            &uuid,
            crate::wallet::sync::AddressRequestKind::Orchard,
        )
        .unwrap();

        assert_ne!(default_address, renewed_address);
        assert_eq!(
            renewed_address,
            get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap()
        );

        let za = zcash_address::ZcashAddress::try_from_encoded(&renewed_address).unwrap();
        let debug = format!("{:?}", za);
        assert!(debug.contains("Orchard"));
        assert!(!debug.contains("Sapling"));
        assert!(!debug.contains("P2pkh"));
    }

    #[test]
    fn test_add_account_duplicate_seed_returns_user_message() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "first").unwrap();

        let error = add_account(db_path_str, WalletNetwork::Main, "duplicate", &seed, None)
            .expect_err("duplicate seed import should fail");

        assert_eq!(error, DUPLICATE_SOFTWARE_ACCOUNT_MESSAGE);
    }

    #[test]
    fn test_import_hardware_duplicate_ufvk_returns_user_message() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        let account_index = zip32::AccountId::ZERO;
        let usk = UnifiedSpendingKey::from_seed(
            &WalletNetwork::Main,
            seed.expose_secret(),
            account_index,
        )
        .unwrap();
        let ufvk = usk.to_unified_full_viewing_key();
        let ufvk_string = ufvk.encode(&WalletNetwork::Main);
        let seed_fingerprint = SeedFingerprint::from_seed(seed.expose_secret())
            .unwrap()
            .to_bytes();

        import_hardware_account(
            db_path_str,
            WalletNetwork::Main,
            "Keystone",
            &ufvk_string,
            &seed_fingerprint,
            u32::from(account_index),
            None,
        )
        .unwrap();

        let error = import_hardware_account(
            db_path_str,
            WalletNetwork::Main,
            "Keystone",
            &ufvk_string,
            &seed_fingerprint,
            u32::from(account_index),
            None,
        )
        .expect_err("duplicate Keystone UFVK import should fail");

        assert_eq!(error, DUPLICATE_KEYSTONE_ACCOUNT_MESSAGE);
    }

    #[test]
    fn test_delete_account_removes_account_from_wallet_db() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let first_phrase = generate_mnemonic();
        let first_seed = mnemonic_to_seed(&first_phrase).unwrap();
        init_db_and_create_account(db_path_str, WalletNetwork::Main, &first_seed, None, "first")
            .unwrap();

        let second_phrase = generate_mnemonic();
        let second_seed = mnemonic_to_seed(&second_phrase).unwrap();
        let (second_uuid, _) = add_account(
            db_path_str,
            WalletNetwork::Main,
            "second",
            &second_seed,
            None,
        )
        .unwrap();

        assert_eq!(
            list_accounts(db_path_str, WalletNetwork::Main)
                .unwrap()
                .len(),
            2
        );
        let accounts_before_delete = list_accounts(db_path_str, WalletNetwork::Main).unwrap();
        assert!(accounts_before_delete
            .iter()
            .any(|account| account.name == "first" && account.is_seed_anchor));
        assert!(accounts_before_delete
            .iter()
            .any(|account| account.name == "second" && !account.is_seed_anchor));

        delete_account(db_path_str, WalletNetwork::Main, &second_uuid).unwrap();

        let accounts = list_accounts(db_path_str, WalletNetwork::Main).unwrap();
        assert_eq!(accounts.len(), 1);
        assert!(accounts.iter().all(|account| account.uuid != second_uuid));
    }

    #[test]
    fn test_delete_account_handles_internal_sent_note_to_deleted_account() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let first_phrase = generate_mnemonic();
        let first_seed = mnemonic_to_seed(&first_phrase).unwrap();
        let (first_uuid, _) = init_db_and_create_account(
            db_path_str,
            WalletNetwork::Main,
            &first_seed,
            None,
            "first",
        )
        .unwrap();

        let second_phrase = generate_mnemonic();
        let second_seed = mnemonic_to_seed(&second_phrase).unwrap();
        let (second_uuid, _) = add_account(
            db_path_str,
            WalletNetwork::Main,
            "second",
            &second_seed,
            None,
        )
        .unwrap();

        seed_internal_sent_note_to_account(db_path_str, &first_uuid, &second_uuid);

        delete_account(db_path_str, WalletNetwork::Main, &second_uuid).unwrap();

        let accounts = list_accounts(db_path_str, WalletNetwork::Main).unwrap();
        assert_eq!(accounts.len(), 1);
        assert!(accounts.iter().all(|account| account.uuid != second_uuid));
        assert_internal_sent_note_rewritten(db_path_str);
    }

    #[test]
    fn test_delete_account_rejects_last_seed_anchor_with_remaining_accounts() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let first_phrase = generate_mnemonic();
        let first_seed = mnemonic_to_seed(&first_phrase).unwrap();
        let (first_uuid, _) = init_db_and_create_account(
            db_path_str,
            WalletNetwork::Main,
            &first_seed,
            None,
            "first",
        )
        .unwrap();

        let second_phrase = generate_mnemonic();
        let second_seed = mnemonic_to_seed(&second_phrase).unwrap();
        add_account(
            db_path_str,
            WalletNetwork::Main,
            "second",
            &second_seed,
            None,
        )
        .unwrap();

        let error = delete_account(db_path_str, WalletNetwork::Main, &first_uuid).unwrap_err();
        assert!(error.contains("last seed anchor account cannot be removed"));

        let accounts = list_accounts(db_path_str, WalletNetwork::Main).unwrap();
        assert_eq!(accounts.len(), 2);
        assert!(accounts.iter().any(|account| account.uuid == first_uuid));
    }

    fn seed_internal_sent_note_to_account(db_path: &str, from_uuid: &str, to_uuid: &str) {
        let conn = rusqlite::Connection::open(db_path).unwrap();
        conn.execute("PRAGMA foreign_keys = ON", []).unwrap();

        let from_account_id = account_row_id(&conn, from_uuid);
        let to_account_id = account_row_id(&conn, to_uuid);
        let funding_txid = vec![0xCD_u8; 32];
        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height)
             VALUES (?1, ?2, ?2)",
            rusqlite::params![funding_txid, 9_i64],
        )
        .unwrap();
        let funding_transaction_id = conn.last_insert_rowid();

        conn.execute(
            "INSERT INTO sapling_received_notes (
                 transaction_id, output_index, account_id, diversifier, value,
                 rcm, is_change
             ) VALUES (?1, 0, ?2, x'01', 2000, x'01', 0)",
            rusqlite::params![funding_transaction_id, from_account_id],
        )
        .unwrap();
        let from_received_note_id = conn.last_insert_rowid();

        let txid = vec![0xAB_u8; 32];
        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height)
             VALUES (?1, ?2, ?2)",
            rusqlite::params![txid, 10_i64],
        )
        .unwrap();
        let transaction_id = conn.last_insert_rowid();

        conn.execute(
            "INSERT INTO sapling_received_note_spends (
                 sapling_received_note_id, transaction_id
             ) VALUES (?1, ?2)",
            rusqlite::params![from_received_note_id, transaction_id],
        )
        .unwrap();

        conn.execute(
            "INSERT INTO addresses (account_id, key_scope, address, receiver_flags)
             VALUES (?1, -1, ?2, 0)",
            rusqlite::params![to_account_id, "u1internalrecipient"],
        )
        .unwrap();
        let address_id = conn.last_insert_rowid();

        conn.execute(
            "INSERT INTO sapling_received_notes (
                 transaction_id, output_index, account_id, diversifier, value,
                 rcm, is_change, address_id
             ) VALUES (?1, 0, ?2, x'00', 1000, x'00', 0, ?3)",
            rusqlite::params![transaction_id, to_account_id, address_id],
        )
        .unwrap();

        conn.execute(
            "INSERT INTO sent_notes (
                 transaction_id, output_pool, output_index, from_account_id,
                 to_account_id, value
             ) VALUES (?1, 2, 0, ?2, ?3, 1000)",
            rusqlite::params![transaction_id, from_account_id, to_account_id],
        )
        .unwrap();
    }

    fn assert_internal_sent_note_rewritten(db_path: &str) {
        let conn = rusqlite::Connection::open(db_path).unwrap();
        let sent_note_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM sent_notes", [], |row| row.get(0))
            .unwrap();
        assert_eq!(sent_note_count, 1);

        let (to_address, to_account_id): (Option<String>, Option<i64>) = conn
            .query_row(
                "SELECT to_address, to_account_id FROM sent_notes",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(to_address.as_deref(), Some("u1internalrecipient"));
        assert_eq!(to_account_id, None);
    }

    fn account_row_id(conn: &rusqlite::Connection, account_uuid: &str) -> i64 {
        let uuid = uuid::Uuid::parse_str(account_uuid).unwrap();
        conn.query_row(
            "SELECT id FROM accounts WHERE uuid = ?1",
            rusqlite::params![uuid.as_bytes().as_slice()],
            |row| row.get(0),
        )
        .unwrap()
    }

    fn external_transparent_address_row(
        conn: &rusqlite::Connection,
        account_uuid: &str,
        child_index: i64,
    ) -> (i64, String, Option<i64>) {
        let account_id = account_row_id(conn, account_uuid);
        conn.query_row(
            r#"
            SELECT id, cached_transparent_receiver_address, exposed_at_height
            FROM addresses
            WHERE account_id = ?1
              AND key_scope = ?2
              AND transparent_child_index = ?3
              AND cached_transparent_receiver_address IS NOT NULL
            "#,
            rusqlite::params![account_id, TRANSPARENT_EXTERNAL_KEY_SCOPE, child_index],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap()
    }

    fn external_transparent_address_rows(
        conn: &rusqlite::Connection,
        account_uuid: &str,
    ) -> Vec<(i64, String)> {
        let account_id = account_row_id(conn, account_uuid);
        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, cached_transparent_receiver_address
                FROM addresses
                WHERE account_id = ?1
                  AND key_scope = ?2
                  AND transparent_child_index IS NOT NULL
                  AND cached_transparent_receiver_address IS NOT NULL
                ORDER BY transparent_child_index ASC
                "#,
            )
            .unwrap();
        stmt.query_map(
            rusqlite::params![account_id, TRANSPARENT_EXTERNAL_KEY_SCOPE],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
        .map(Result::unwrap)
        .collect()
    }

    fn mark_transparent_address_received(
        conn: &rusqlite::Connection,
        account_uuid: &str,
        address_id: i64,
        address: &str,
        tx_suffix: u32,
    ) {
        let account_id = account_row_id(conn, account_uuid);
        let mut txid = vec![0_u8; 32];
        txid[0] = 0xAB;
        txid[28..32].copy_from_slice(&tx_suffix.to_be_bytes());
        let height = 10_i64 + i64::from(tx_suffix);

        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height)
             VALUES (?1, ?2, ?2)",
            rusqlite::params![txid, height],
        )
        .unwrap();
        let transaction_id = conn.last_insert_rowid();

        conn.execute(
            "INSERT INTO transparent_received_outputs (
                 transaction_id, output_index, account_id, address, script,
                 value_zat, max_observed_unspent_height, address_id
             ) VALUES (?1, 0, ?2, ?3, x'51', 1000, ?4, ?5)",
            rusqlite::params![transaction_id, account_id, address, height, address_id],
        )
        .unwrap();
    }

    #[test]
    fn test_create_testnet_wallet() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let (_, address) =
            init_db_and_create_account(db_path_str, WalletNetwork::Test, &seed, None, "test")
                .unwrap();

        assert!(
            address.starts_with("utest1"),
            "Expected utest1 prefix, got: {address}"
        );
    }

    #[test]
    fn test_deterministic_address_from_same_seed() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
        let seed = mnemonic_to_seed(phrase).unwrap();

        let temp1 = tempfile::tempdir().unwrap();
        let db1 = temp1.path().join("wallet.db");
        let (_, addr1) = init_db_and_create_account(
            db1.to_str().unwrap(),
            WalletNetwork::Main,
            &seed,
            None,
            "test",
        )
        .unwrap();

        let temp2 = tempfile::tempdir().unwrap();
        let db2 = temp2.path().join("wallet.db");
        let (_, addr2) = init_db_and_create_account(
            db2.to_str().unwrap(),
            WalletNetwork::Main,
            &seed,
            None,
            "test",
        )
        .unwrap();

        assert_eq!(addr1, addr2, "Same seed should produce same address");
    }

    #[test]
    fn test_shielded_address_has_sapling_and_orchard_only() {
        // Verify our address uses Sapling+Orchard receivers (no transparent),
        // matching zodl/Zashi wallet behavior.
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let (_, address) =
            init_db_and_create_account(db_path_str, WalletNetwork::Main, &seed, None, "test")
                .unwrap();
        let listed_account = list_accounts(db_path_str, WalletNetwork::Main)
            .unwrap()
            .into_iter()
            .next()
            .unwrap();
        assert!(!listed_account.is_hardware);

        // Decode and verify receiver types
        let za = zcash_address::ZcashAddress::try_from_encoded(&address).unwrap();
        let debug = format!("{:?}", za);
        assert!(
            debug.contains("Sapling"),
            "UA should contain Sapling receiver"
        );
        assert!(
            debug.contains("Orchard"),
            "UA should contain Orchard receiver"
        );
        assert!(
            !debug.contains("P2pkh"),
            "UA should NOT contain transparent receiver"
        );
    }
}
