//! Vizor under test, driven only through `rust_lib_zcash_wallet::api`.
//!
//! - V builder: production send / shield / TEX / gift-card paths.
//! - Variants: R (the DB that built or observed), N (fresh restore of Alice's
//!   seeds), N_seq (the same restore with A0 synced alone before A1 is added,
//!   [`VizorWallet::import_sequential`]), O (R's files copied to a new path: a
//!   reopen with no in-process state keyed by the old path).
//! - Observation: balances, the owned transparent ledger, history rows,
//!   details, and every lightwalletd request (through the proxy).

use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};
use serde::Serialize;

use crate::{chain::Chain, keys::Party, proxy::Proxy};

pub const NET: &str = "regtest";
static FLOW: AtomicU64 = AtomicU64::new(1);

fn flow_id() -> String {
    format!("th-flow-{}", FLOW.fetch_add(1, Ordering::SeqCst))
}

pub fn reverse_hex(hex_str: &str) -> String {
    let mut bytes = hex::decode(hex_str).expect("hex txid");
    bytes.reverse();
    hex::encode(bytes)
}

pub struct Account {
    pub name: &'static str,
    pub uuid: String,
    mnemonic: String,
}

pub struct VizorWallet {
    pub label: String,
    _dir: tempfile::TempDir,
    pub db: String,
    pub proxy: Proxy,
    pub accounts: Vec<Account>,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Row {
    /// Display-order txid (zcashd order).
    pub txid: String,
    pub tx_kind: String,
    pub account_balance_delta: i64,
    pub display_amount: u64,
    pub display_pool: String,
    pub fee: u64,
    pub fee_state: String,
    pub details_complete: bool,
    pub provisional: bool,
    pub mined_height: u64,
    pub expired_unmined: bool,
    pub block_time: u64,
    pub created_time: u64,
    pub is_transparent: bool,
    pub timestamp_source: String,
    pub detail: Option<Detail>,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Detail {
    pub primary_address: Option<String>,
    pub source_address: Option<String>,
    pub source_pool: Option<String>,
    pub outputs: Vec<(Option<String>, u64, String)>,
    pub details_complete: bool,
    pub provisional: bool,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct LedgerEntry {
    pub txid: String,
    pub index: u32,
    pub value: u64,
    pub address: String,
    pub scope: Option<i64>,
    pub child_index: Option<i64>,
    pub receive_mined_height: Option<i64>,
    /// Display-order txids of mined spends, and of every recorded spend.
    pub mined_spenders: Vec<String>,
    pub all_spenders: Vec<String>,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Balance {
    pub availability: String,
    pub transparent_authority: String,
    /// Why private recovery cannot restore transparent authority (`stopped`).
    pub transparent_stop: Option<String>,
    /// Whether the wallet's transparent funds are under private recovery.
    pub transparent_private: bool,
    pub transparent_last_known: Option<u64>,
    pub transparent: u64,
    pub transparent_pending: u64,
    pub transparent_locked: u64,
    pub orchard: u64,
    pub sapling: u64,
    pub spendable: u64,
    pub total: u64,
}

#[derive(Clone, Debug, Serialize)]
pub struct AccountView {
    pub variant: String,
    pub account: String,
    pub balance: Option<Balance>,
    pub balance_error: Option<String>,
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub sync_complete: bool,
    pub ledger: Vec<LedgerEntry>,
    pub addresses: Vec<(i64, i64, String)>,
    pub history: Vec<Row>,
    pub history_error: Option<String>,
}

fn copy_dir(from: &Path, to: &Path) {
    for entry in std::fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        let target = to.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            std::fs::create_dir_all(&target).unwrap();
            copy_dir(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).unwrap();
        }
    }
}

pub fn sapling_params() -> (Option<String>, Option<String>) {
    let dir = std::env::var("REGTEST_SAPLING_PARAMS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(std::env::var("HOME").unwrap()).join(".zcash-params"));
    let spend = dir.join("sapling-spend.params");
    let output = dir.join("sapling-output.params");
    if spend.is_file() && output.is_file() {
        (
            Some(spend.to_string_lossy().into()),
            Some(output.to_string_lossy().into()),
        )
    } else {
        (None, None)
    }
}

impl VizorWallet {
    /// Imports Alice's two seeds (A0 first, A1 as a second seed) at birthday 1.
    /// In the private profile the wallet requires private recovery before its
    /// first sync.
    pub fn import(label: &str, chain: &Chain, a0: &Party, a1: &Party) -> Self {
        Self::import_with(label, chain, a0, a1, crate::report::profile() == "private")
    }

    /// [`Self::import`], raising the transparent policy before the first sync
    /// only when `private`.
    fn import_with(label: &str, chain: &Chain, a0: &Party, a1: &Party, private: bool) -> Self {
        let dir = tempfile::tempdir().expect("wallet dir");
        let db = dir
            .path()
            .join("zcash_wallet.db")
            .to_string_lossy()
            .to_string();
        let first = wallet_api::import_wallet(
            a0.mnemonic.clone(),
            String::new(),
            Some(1),
            NET.into(),
            db.clone(),
            Some(a0.name.into()),
        )
        .expect("import A0");
        let second = wallet_api::add_account(
            db.clone(),
            NET.into(),
            a1.name.into(),
            a1.mnemonic.clone(),
            String::new(),
            Some(1),
        )
        .expect("add A1");
        if private {
            // The production toggle-on path: the wallet durably requires
            // private recovery before its first sync.
            raise_private(&db);
        }
        VizorWallet {
            label: label.into(),
            _dir: dir,
            db,
            proxy: Proxy::start(&chain.lwd_url()),
            accounts: vec![
                Account {
                    name: a0.name,
                    uuid: first.account_uuid,
                    mnemonic: a0.mnemonic.clone(),
                },
                Account {
                    name: a1.name,
                    uuid: second.account_uuid,
                    mnemonic: a1.mnemonic.clone(),
                },
            ],
        }
    }

    /// A fresh restore in the other order users reach: A0 alone is restored
    /// and synced to the tip, and only then is A1 added. Adding an account to
    /// a synced wallet rewinds it, which [`Self::import`] (both seeds before
    /// the first sync) never exercises. Returns the wallet for the caller to
    /// settle.
    ///
    /// Panics, as R's sync does, when A0 alone does not reach a synchronized
    /// wallet (private profile: privately recovered, current transparent
    /// authority), or when adding A1 lowers the private policy: the variant
    /// would not test what it claims.
    pub fn import_sequential(label: &str, chain: &Chain, a0: &Party, a1: &Party) -> Self {
        let dir = tempfile::tempdir().expect("wallet dir");
        let db = dir
            .path()
            .join("zcash_wallet.db")
            .to_string_lossy()
            .to_string();
        let first = wallet_api::import_wallet(
            a0.mnemonic.clone(),
            String::new(),
            Some(1),
            NET.into(),
            db.clone(),
            Some(a0.name.into()),
        )
        .expect("import A0");
        // As in `import`: the wallet requires private recovery before its
        // first sync. Adding A1 must keep it; that is checked below.
        let raised = (crate::report::profile() == "private").then(|| raise_private(&db));
        let mut wallet = VizorWallet {
            label: label.into(),
            _dir: dir,
            db: db.clone(),
            proxy: Proxy::start(&chain.lwd_url()),
            accounts: vec![Account {
                name: a0.name,
                uuid: first.account_uuid,
                mnemonic: a0.mnemonic.clone(),
            }],
        };
        if let Err(e) = wallet.settle_retrying() {
            panic!(
                "{label}: A0's sync alone failed: {e}\n{}",
                chain.container_logs()
            );
        }
        let view = wallet.observe(a0.name);
        assert!(
            view.sync_complete && view.scanned_height == view.chain_tip_height,
            "{label}: A0 is not synchronized before A1 is added (complete {}, scanned {} of {})",
            view.sync_complete,
            view.scanned_height,
            view.chain_tip_height,
        );
        let private = crate::report::profile() == "private";
        if private {
            let balance = view.balance.as_ref();
            assert!(
                balance
                    .is_some_and(|b| b.transparent_private && b.transparent_authority == "current"),
                "{label}: A0 has not recovered privately before A1 is added: {balance:?}",
            );
        }
        let second = wallet_api::add_account(
            db.clone(),
            NET.into(),
            a1.name.into(),
            a1.mnemonic.clone(),
            String::new(),
            Some(1),
        )
        .expect("add A1");
        if let Some(raised) = raised {
            // The wallet already requires private recovery: reconciling again
            // finds the same policy, in the same generation.
            assert_eq!(
                raise_private(&db),
                raised,
                "{label}: adding A1 changed the transparent policy"
            );
        }
        wallet.accounts.push(Account {
            name: a1.name,
            uuid: second.account_uuid,
            mnemonic: a1.mnemonic.clone(),
        });
        wallet
    }

    /// O: copy every file of this wallet to a new directory. Call only while
    /// no Vizor operation runs on it.
    pub fn reopen(&self, label: &str, chain: &Chain) -> Self {
        let dir = tempfile::tempdir().expect("wallet dir");
        copy_dir(Path::new(&self.db).parent().unwrap(), dir.path());
        let db = dir
            .path()
            .join("zcash_wallet.db")
            .to_string_lossy()
            .to_string();
        VizorWallet {
            label: label.into(),
            _dir: dir,
            db,
            proxy: Proxy::start(&chain.lwd_url()),
            accounts: self
                .accounts
                .iter()
                .map(|a| Account {
                    name: a.name,
                    uuid: a.uuid.clone(),
                    mnemonic: a.mnemonic.clone(),
                })
                .collect(),
        }
    }

    pub fn account(&self, name: &str) -> &Account {
        self.accounts
            .iter()
            .find(|a| a.name == name)
            .unwrap_or_else(|| panic!("no account {name}"))
    }

    /// One production sync. The private profile's publication first catches
    /// up with the chain, so it covers the tip the wallet scans to.
    pub fn sync(&self) -> Result<(), String> {
        if let Some(publisher) = crate::publication::global() {
            publisher.catch_up();
        }
        sync_api::run_full_sync_blocking(self.db.clone(), self.proxy.url.clone(), NET.into(), 1)
    }

    fn fingerprint(&self) -> String {
        let mut out = String::new();
        for account in &self.accounts {
            let view = self.observe(account.name);
            out.push_str(&serde_json::to_string(&view.history).unwrap());
            out.push_str(&serde_json::to_string(&view.ledger).unwrap());
        }
        out
    }

    /// Syncs until two consecutive syncs leave history and ledger unchanged
    /// (at most four syncs): production polls repeatedly, and newly extended
    /// gap addresses are only queried on the next pass.
    pub fn settle(&self) -> Result<(), String> {
        self.sync()?;
        let mut last = self.fingerprint();
        for _ in 0..3 {
            self.sync()?;
            let now = self.fingerprint();
            if now == last {
                return Ok(());
            }
            last = now;
        }
        Ok(())
    }

    /// [`Self::settle`], retried twice: a sync can fail with a retryable
    /// error, and production retries on the next pass.
    pub fn settle_retrying(&self) -> Result<(), String> {
        let mut result = self.settle();
        for _ in 0..2 {
            if result.is_ok() {
                break;
            }
            result = self.settle();
        }
        result
    }

    pub fn unified_address(&self, account: &str) -> String {
        wallet_api::get_unified_address(
            self.db.clone(),
            NET.into(),
            Some(self.account(account).uuid.clone()),
        )
        .expect("unified address")
    }

    /// V: production send (propose + execute). Returns display-order txids.
    pub fn send(&self, account: &str, to: &str, zatoshi: u64) -> Vec<String> {
        let account = self.account(account);
        let flow = flow_id();
        let proposal = sync_api::propose_send(
            self.db.clone(),
            NET.into(),
            account.uuid.clone(),
            flow.clone(),
            to.into(),
            zatoshi,
            None,
        )
        .unwrap_or_else(|e| panic!("V propose_send {} -> {to}: {e}", account.name));
        let (spend, output) = if proposal.needs_sapling_params {
            sapling_params()
        } else {
            (None, None)
        };
        let result = sync_api::execute_proposal(
            self.db.clone(),
            self.proxy.url.clone(),
            proposal.proposal_id,
            flow,
            account.mnemonic.as_bytes().to_vec(),
            spend,
            output,
        )
        .unwrap_or_else(|e| panic!("V execute_proposal {} -> {to}: {e}", account.name));
        assert_eq!(
            result.broadcasted_count, result.total_count,
            "V send not fully broadcast: {:?} {:?}",
            result.status, result.message
        );
        result.txids.split(',').map(str::to_string).collect()
    }

    /// V: production shielding of every transparent receiver.
    pub fn shield(&self, account: &str) -> Vec<String> {
        let account = self.account(account);
        let result = sync_api::shield_transparent_balance(
            self.db.clone(),
            self.proxy.url.clone(),
            NET.into(),
            account.uuid.clone(),
            account.mnemonic.as_bytes().to_vec(),
        )
        .unwrap_or_else(|e| panic!("V shield {}: {}", account.name, e.message));
        assert!(
            result.broadcasted_count > 0 && result.broadcasted_count == result.total_count,
            "V shield not broadcast: {} {:?}",
            result.status,
            result.message
        );
        result.txids.split(',').map(str::to_string).collect()
    }

    fn conn(&self) -> rusqlite::Connection {
        rusqlite::Connection::open_with_flags(&self.db, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .expect("open wallet db read-only")
    }

    fn uuid_bytes(&self, account: &str) -> Vec<u8> {
        uuid::Uuid::parse_str(&self.account(account).uuid)
            .unwrap()
            .as_bytes()
            .to_vec()
    }

    fn ledger(&self, account: &str) -> Vec<LedgerEntry> {
        let conn = self.conn();
        let mut statement = conn
            .prepare(
                "SELECT t.txid, o.output_index, o.value_zat, o.address, ad.key_scope,
                        ad.transparent_child_index, t.mined_height, o.id
                 FROM transparent_received_outputs o
                 JOIN transactions t ON t.id_tx = o.transaction_id
                 JOIN accounts a ON a.id = o.account_id
                 LEFT JOIN addresses ad ON ad.id = o.address_id
                 WHERE a.uuid = ?1
                 ORDER BY t.txid, o.output_index",
            )
            .unwrap();
        let rows: Vec<(
            Vec<u8>,
            u32,
            u64,
            String,
            Option<i64>,
            Option<i64>,
            Option<i64>,
            i64,
        )> = statement
            .query_map([self.uuid_bytes(account)], |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get::<_, i64>(2)? as u64,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                    r.get(6)?,
                    r.get(7)?,
                ))
            })
            .unwrap()
            .map(Result::unwrap)
            .collect();
        let mut spends = conn
            .prepare(
                "SELECT st.txid, st.mined_height FROM transparent_received_output_spends s
                 JOIN transactions st ON st.id_tx = s.transaction_id
                 WHERE s.transparent_received_output_id = ?1",
            )
            .unwrap();
        rows.into_iter()
            .map(|(txid, index, value, address, scope, child, mined, id)| {
                let spenders: Vec<(Vec<u8>, Option<i64>)> = spends
                    .query_map([id], |r| Ok((r.get(0)?, r.get(1)?)))
                    .unwrap()
                    .map(Result::unwrap)
                    .collect();
                let display = |bytes: &Vec<u8>| reverse_hex(&hex::encode(bytes));
                LedgerEntry {
                    txid: display(&txid),
                    index,
                    value,
                    address,
                    scope,
                    child_index: child,
                    receive_mined_height: mined,
                    mined_spenders: spenders
                        .iter()
                        .filter(|(_, h)| h.is_some())
                        .map(|(t, _)| display(t))
                        .collect(),
                    all_spenders: spenders.iter().map(|(t, _)| display(t)).collect(),
                }
            })
            .collect()
    }

    fn addresses(&self, account: &str) -> Vec<(i64, i64, String)> {
        let conn = self.conn();
        let mut statement = conn
            .prepare(
                "SELECT ad.key_scope, ad.transparent_child_index, ad.cached_transparent_receiver_address
                 FROM addresses ad JOIN accounts a ON a.id = ad.account_id
                 WHERE a.uuid = ?1 AND ad.cached_transparent_receiver_address IS NOT NULL
                 ORDER BY ad.key_scope, ad.transparent_child_index",
            )
            .unwrap();
        statement
            .query_map([self.uuid_bytes(account)], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?))
            })
            .unwrap()
            .map(Result::unwrap)
            .collect()
    }

    /// `account`'s balance, as [`Self::observe`] reports it.
    pub fn balance(&self, account: &str) -> Result<Balance, String> {
        balance_of(&self.db, &self.account(account).uuid)
    }

    pub fn observe(&self, account: &str) -> AccountView {
        let uuid = self.account(account).uuid.clone();
        let (balance, balance_error) = match self.balance(account) {
            Ok(balance) => (Some(balance), None),
            Err(e) => (None, Some(e)),
        };
        let status = sync_api::get_sync_status(self.db.clone(), NET.into()).ok();
        let (history, history_error) = match sync_api::get_transaction_history(
            self.db.clone(),
            NET.into(),
            Some(500),
            uuid.clone(),
        ) {
            Ok(rows) => (
                rows.into_iter()
                    .map(|t| {
                        let detail = sync_api::get_transaction_detail(
                            self.db.clone(),
                            NET.into(),
                            uuid.clone(),
                            t.txid_hex.clone(),
                            t.tx_kind.clone(),
                        );
                        Row {
                            txid: reverse_hex(&t.txid_hex),
                            tx_kind: t.tx_kind,
                            account_balance_delta: t.account_balance_delta,
                            display_amount: t.display_amount,
                            display_pool: t.display_pool,
                            fee: t.fee,
                            fee_state: match t.fee_state {
                                sync_api::TransactionFeeState::Known => "known",
                                sync_api::TransactionFeeState::Unknown => "unknown",
                                sync_api::TransactionFeeState::NotApplicable => "not_applicable",
                            }
                            .into(),
                            details_complete: t.details_complete,
                            provisional: t.provisional,
                            mined_height: t.mined_height,
                            expired_unmined: t.expired_unmined,
                            timestamp_source: if t.block_time > 0 {
                                "block"
                            } else if t.created_time > 0 {
                                "created"
                            } else {
                                "none"
                            }
                            .into(),
                            block_time: t.block_time,
                            created_time: t.created_time,
                            is_transparent: t.is_transparent,
                            detail: Some(match detail {
                                Ok(d) => Detail {
                                    primary_address: d.primary_address,
                                    source_address: d.source_address,
                                    source_pool: d.source_pool,
                                    outputs: d
                                        .outputs
                                        .into_iter()
                                        .map(|o| (o.address, o.amount_zatoshi, o.pool))
                                        .collect(),
                                    details_complete: d.details_complete,
                                    provisional: d.provisional,
                                    error: None,
                                },
                                Err(e) => Detail {
                                    primary_address: None,
                                    source_address: None,
                                    source_pool: None,
                                    outputs: vec![],
                                    details_complete: false,
                                    provisional: true,
                                    error: Some(e),
                                },
                            }),
                        }
                    })
                    .collect(),
                None,
            ),
            Err(e) => (Vec::new(), Some(e)),
        };
        AccountView {
            variant: self.label.clone(),
            account: account.into(),
            balance,
            balance_error,
            scanned_height: status.as_ref().map(|s| s.scanned_height).unwrap_or(0),
            chain_tip_height: status.as_ref().map(|s| s.chain_tip_height).unwrap_or(0),
            sync_complete: status.as_ref().map(|s| s.is_complete).unwrap_or(false),
            ledger: self.ledger(account),
            addresses: self.addresses(account),
            history,
            history_error,
        }
    }

    pub fn observe_all(&self) -> Vec<AccountView> {
        self.accounts.iter().map(|a| self.observe(a.name)).collect()
    }
}

/// The balance of the account `uuid` in the wallet at `db`, as
/// [`VizorWallet::observe`] reports it.
pub fn balance_of(db: &str, uuid: &str) -> Result<Balance, String> {
    sync_api::get_balance(db.to_owned(), NET.into(), uuid.to_owned()).map(|b| Balance {
        availability: match b.availability {
            sync_api::WalletBalanceAvailability::Available => "available",
            sync_api::WalletBalanceAvailability::SummaryUnavailable => "summary_unavailable",
            sync_api::WalletBalanceAvailability::AccountUnavailable => "account_unavailable",
        }
        .into(),
        transparent_authority: match b.transparent_authority {
            sync_api::TransparentBalanceAuthority::Current => "current",
            sync_api::TransparentBalanceAuthority::LastKnown => "last_known",
            sync_api::TransparentBalanceAuthority::Unavailable => "unavailable",
            sync_api::TransparentBalanceAuthority::Stopped => "stopped",
        }
        .into(),
        transparent_stop: b.transparent_stop.map(|reason| {
            match reason {
                sync_api::TransparentStopReason::Quarantined => "quarantined",
                sync_api::TransparentStopReason::LegacyDiscrepancy => "legacy_discrepancy",
                sync_api::TransparentStopReason::Withdrawn => "withdrawn",
                sync_api::TransparentStopReason::Stalled => "stalled",
                sync_api::TransparentStopReason::OptOutUnfinished => "opt_out_unfinished",
            }
            .into()
        }),
        transparent_private: b.transparent_private,
        transparent_last_known: b.transparent_last_known,
        transparent: b.transparent,
        transparent_pending: b.transparent_pending,
        transparent_locked: b.transparent_locked,
        orchard: b.orchard,
        sapling: b.sapling,
        spendable: b.spendable,
        total: b.total,
    })
}

/// What a harness-asserted variant found ([`VizorWallet::import_toggled`]):
/// `problems` fail the variant; `notes` are what it measured.
#[derive(Default)]
pub struct Findings {
    pub problems: Vec<String>,
    pub notes: Vec<String>,
}

/// At most `limit` of `items`, then how many more, for one-line messages.
fn sample<'a>(items: impl IntoIterator<Item = &'a String>, limit: usize) -> String {
    let items: Vec<&String> = items.into_iter().collect();
    let mut shown: Vec<String> = items.iter().take(limit).map(|s| s.to_string()).collect();
    if items.len() > limit {
        shown.push(format!("... {} more", items.len() - limit));
    }
    shown.join("; ")
}

impl VizorWallet {
    /// The wallet's transparent facts, by content and never by row id, for
    /// diffing a wallet against itself across policy changes: each received
    /// transparent output (account, outpoint, value, address, the receiving
    /// transaction's mined height), each recorded spend of one, and each
    /// transaction with its mined height.
    pub fn transparent_facts(&self) -> BTreeSet<String> {
        let conn = self.conn();
        let names: BTreeMap<Vec<u8>, &str> = self
            .accounts
            .iter()
            .map(|a| (self.uuid_bytes(a.name), a.name))
            .collect();
        let display = |bytes: &Vec<u8>| reverse_hex(&hex::encode(bytes));
        let mut facts = BTreeSet::new();
        let mut outputs = conn
            .prepare(
                "SELECT a.uuid, t.txid, o.output_index, o.value_zat, o.address, t.mined_height
                 FROM transparent_received_outputs o
                 JOIN transactions t ON t.id_tx = o.transaction_id
                 JOIN accounts a ON a.id = o.account_id",
            )
            .unwrap();
        let rows = outputs
            .query_map([], |r| {
                Ok((
                    r.get::<_, Vec<u8>>(0)?,
                    r.get::<_, Vec<u8>>(1)?,
                    r.get::<_, i64>(2)?,
                    r.get::<_, i64>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, Option<i64>>(5)?,
                ))
            })
            .unwrap();
        for row in rows {
            let (account, txid, index, value, address, mined) = row.unwrap();
            facts.insert(format!(
                "output {} {}:{index} {value} {address} mined={mined:?}",
                names.get(&account).copied().unwrap_or("?"),
                display(&txid),
            ));
        }
        let mut spends = conn
            .prepare(
                "SELECT t.txid, o.output_index, st.txid
                 FROM transparent_received_output_spends s
                 JOIN transparent_received_outputs o ON o.id = s.transparent_received_output_id
                 JOIN transactions t ON t.id_tx = o.transaction_id
                 JOIN transactions st ON st.id_tx = s.transaction_id",
            )
            .unwrap();
        let rows = spends
            .query_map([], |r| {
                Ok((
                    r.get::<_, Vec<u8>>(0)?,
                    r.get::<_, i64>(1)?,
                    r.get::<_, Vec<u8>>(2)?,
                ))
            })
            .unwrap();
        for row in rows {
            let (txid, index, spender) = row.unwrap();
            facts.insert(format!(
                "spend {}:{index} by {}",
                display(&txid),
                display(&spender)
            ));
        }
        let mut transactions = conn
            .prepare("SELECT txid, mined_height FROM transactions")
            .unwrap();
        let rows = transactions
            .query_map([], |r| {
                Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, Option<i64>>(1)?))
            })
            .unwrap();
        for row in rows {
            let (txid, mined) = row.unwrap();
            facts.insert(format!("tx {} mined={mined:?}", display(&txid)));
        }
        facts
    }

    /// Checks that every account's transparent balance has `authority` and
    /// `private` (whether the wallet durably requires private recovery) at
    /// `step`, and returns the balances read.
    fn expect_authority(
        &self,
        step: &str,
        authority: &str,
        private: bool,
        findings: &mut Findings,
    ) -> BTreeMap<&'static str, Balance> {
        let mut balances = BTreeMap::new();
        for account in &self.accounts {
            match self.balance(account.name) {
                Ok(b) => {
                    if b.transparent_authority != authority || b.transparent_private != private {
                        findings.problems.push(format!(
                            "{step}: {} transparent authority {} (stop {:?}, private {}), expected {authority} (private {private})",
                            account.name, b.transparent_authority, b.transparent_stop, b.transparent_private,
                        ));
                    }
                    balances.insert(account.name, b);
                }
                Err(e) => findings
                    .problems
                    .push(format!("{step}: {} balance unavailable: {e}", account.name)),
            }
        }
        balances
    }

    /// N_toggle: a fresh restore of Alice's seeds with private queries off
    /// builds public history; the production toggle then raises it to private
    /// recovery (`reconcile_transparent_policy(.., true)`), private recovery
    /// runs to the tip, and the toggle lowers it again (`false`), after which
    /// public discovery runs. Returns the wallet, in public mode, with what
    /// the run found:
    ///
    /// - each transparent balance has no current authority right after the
    ///   raise (`last_known`, keeping the public amount as the last known
    ///   one), and after the lowering either none or exactly the public
    ///   amount from before the raise (the library restores the public
    ///   evidence it kept); current authority once the next mode has synced;
    /// - the per-wallet proxy sees transparent-subject requests while public,
    ///   none from the raise until the lowering, and some again after it;
    /// - lowering forgets only facts that private recovery alone found: every
    ///   fact the public wallet held before the raise survives the
    ///   forgetting, and once public lookups ran the wallet holds exactly the
    ///   facts it held before the raise.
    ///
    /// Switches the process-wide private-queries preference while it runs and
    /// turns it back on before returning: call only while no other wallet
    /// syncs, in the private profile.
    pub fn import_toggled(label: &str, chain: &Chain, a0: &Party, a1: &Party) -> (Self, Findings) {
        let mut findings = Findings::default();
        sync_api::set_enhance_pir_enabled(false);
        let wallet = Self::import_with(label, chain, a0, a1, false);
        let settle = |step: &str, findings: &mut Findings| {
            if let Err(e) = wallet.settle_retrying() {
                findings.problems.push(format!("{step}: sync failed: {e}"));
            }
        };
        let requests = |step: &str, findings: &mut Findings| {
            let requests = wallet.proxy.take_requests();
            let named = crate::proxy::transparent_subject_count(&requests);
            findings.notes.push(format!(
                "{step}: {} lightwalletd requests, {named} with a transparent subject",
                requests.len()
            ));
            named
        };

        // Public history.
        settle("public", &mut findings);
        let public = wallet.expect_authority("public, settled", "current", false, &mut findings);
        if requests("public", &mut findings) == 0 {
            findings
                .problems
                .push("public: no request named a transparent subject (positive control)".into());
        }
        let before = wallet.transparent_facts();

        // Raise.
        sync_api::set_enhance_pir_enabled(true);
        let raised =
            match sync_api::reconcile_transparent_policy(wallet.db.clone(), NET.into(), true) {
                Ok(Some(applied))
                    if applied.mode == sync_api::ApiTransparentLedgerMode::PrivateRequired =>
                {
                    Some(applied)
                }
                other => {
                    findings
                        .problems
                        .push(format!("raise: the policy was not raised: {other:?}"));
                    None
                }
            };
        let at_raise =
            wallet.expect_authority("raised, before a sync", "last_known", true, &mut findings);
        for (account, b) in &at_raise {
            let was = public.get(account).map(|p| p.transparent);
            if b.transparent_last_known != was {
                findings.problems.push(format!(
                    "raised, before a sync: {account} last known {:?}, the public balance was {was:?}",
                    b.transparent_last_known
                ));
            }
        }
        settle("private", &mut findings);
        wallet.expect_authority("raised, settled", "current", true, &mut findings);
        let named = requests("from the raise to the lowering", &mut findings);
        if named > 0 {
            findings.problems.push(format!(
                "from the raise to the lowering: {named} requests named a transparent subject"
            ));
        }
        let private = wallet.transparent_facts();

        // Lower.
        sync_api::set_enhance_pir_enabled(false);
        match sync_api::reconcile_transparent_policy(wallet.db.clone(), NET.into(), false) {
            Ok(Some(applied))
                if applied.mode == sync_api::ApiTransparentLedgerMode::Public
                    && raised.is_none_or(|r| applied.generation > r.generation) => {}
            other => findings.problems.push(format!(
                "lower: the policy was not lowered past the raise: {other:?}"
            )),
        }
        let forgotten = wallet.transparent_facts();
        // Lowering restores the public evidence the raise kept, so the
        // library may report it as current at once. It must then be exactly
        // the public amount from before the raise, never a privately
        // recovered one.
        for account in &wallet.accounts {
            let was = public.get(account.name).map(|p| p.transparent);
            match wallet.balance(account.name) {
                Ok(b) if !b.transparent_private
                    && (b.transparent_authority == "last_known"
                        || (b.transparent_authority == "current" && Some(b.transparent) == was)) =>
                {
                    findings.notes.push(format!(
                        "lowered, before a sync: {} transparent authority {} ({} zatoshis; {:?} before the raise)",
                        account.name, b.transparent_authority, b.transparent, was
                    ));
                }
                other => findings.problems.push(format!(
                    "lowered, before a sync: {} is neither last known nor the public amount from before the raise ({was:?}): {other:?}",
                    account.name
                )),
            }
        }
        let named = requests("lowered, before a sync", &mut findings);
        if named > 0 {
            findings.problems.push(format!(
                "lowered, before a sync: {named} requests named a transparent subject"
            ));
        }
        settle("public again", &mut findings);
        wallet.expect_authority("lowered, settled", "current", false, &mut findings);
        if requests("after the lowering", &mut findings) == 0 {
            findings.problems.push(
                "after the lowering: no request named a transparent subject; public lookups did not resume"
                    .into(),
            );
        }
        let rebuilt = wallet.transparent_facts();
        sync_api::set_enhance_pir_enabled(true);

        // What forgetting removed, and what public lookups rebuilt.
        let private_only: BTreeSet<&String> = private.difference(&before).collect();
        let removed: BTreeSet<&String> = private.difference(&forgotten).collect();
        let lost: Vec<&String> = removed
            .iter()
            .copied()
            .filter(|f| before.contains(*f))
            .collect();
        findings.notes.push(format!(
            "facts: {} public; {} after private recovery, {} of them found by it alone; {} removed by the lowering, {} of them found by private recovery alone; {} after public lookups",
            before.len(),
            private.len(),
            private_only.len(),
            removed.len(),
            removed.iter().filter(|f| private_only.contains(*f)).count(),
            rebuilt.len(),
        ));
        if !private_only.is_empty() {
            findings.notes.push(format!(
                "found by private recovery alone: {}",
                sample(private_only.iter().copied(), 6)
            ));
        }
        if !lost.is_empty() {
            findings.problems.push(format!(
                "lowering removed {} facts the public wallet held: {}",
                lost.len(),
                sample(lost, 5)
            ));
        }
        let missing: Vec<&String> = before.difference(&rebuilt).collect();
        if !missing.is_empty() {
            findings.problems.push(format!(
                "public lookups did not rebuild {} facts: {}",
                missing.len(),
                sample(missing, 5)
            ));
        }
        let extra: Vec<&String> = rebuilt.difference(&before).collect();
        if !extra.is_empty() {
            findings.problems.push(format!(
                "after the lowering the wallet holds {} facts the public wallet lacked: {}",
                extra.len(),
                sample(extra, 5)
            ));
        }
        (wallet, findings)
    }

    /// N_discover: imports `party`'s seed as onboarding's recovery-phrase
    /// import does, account 0 and the higher ZIP 32 accounts `indices`
    /// discovery found (each named by `name_of`), then raises the wallet to
    /// private recovery. Uses `proxy`, which already recorded the discovery's
    /// lightwalletd requests, if any.
    pub fn import_discovered(
        label: &str,
        proxy: Proxy,
        party: &Party,
        indices: &[u32],
        name_of: impl Fn(u32) -> &'static str,
    ) -> Result<Self, String> {
        let dir = tempfile::tempdir().expect("wallet dir");
        let db = dir
            .path()
            .join("zcash_wallet.db")
            .to_string_lossy()
            .to_string();
        let imported = wallet_api::import_software_wallet_with_account_discovery(
            party.mnemonic.clone(),
            String::new(),
            Some(1),
            NET.into(),
            db.clone(),
            Some(name_of(0).into()),
            true,
            1,
            indices.to_vec(),
        )?;
        raise_private(&db);
        Ok(VizorWallet {
            label: label.into(),
            _dir: dir,
            db,
            proxy,
            accounts: imported
                .accounts
                .into_iter()
                .map(|a| Account {
                    name: name_of(a.zip32_account_index),
                    uuid: a.account_uuid,
                    mnemonic: party.mnemonic.clone(),
                })
                .collect(),
        })
    }
}

/// N_restart's child process: syncs the wallet at `TH_RESTART_DB` through
/// `TH_RESTART_LWD` as a freshly started process that never set the
/// private-queries preference, and writes each account's balance
/// (`TH_RESTART_ACCOUNTS`, `name=uuid` pairs) and every sync's result to
/// `TH_RESTART_OUT`. Does nothing without `TH_RESTART_DB`.
pub fn restart_child() {
    let Ok(db) = std::env::var("TH_RESTART_DB") else {
        eprintln!("[restart] no TH_RESTART_DB: nothing to do");
        return;
    };
    let lwd = std::env::var("TH_RESTART_LWD").expect("TH_RESTART_LWD");
    let out = std::env::var("TH_RESTART_OUT").expect("TH_RESTART_OUT");
    let accounts: Vec<(String, String)> = std::env::var("TH_RESTART_ACCOUNTS")
        .expect("TH_RESTART_ACCOUNTS")
        .split(',')
        .map(|pair| {
            let (name, uuid) = pair.split_once('=').expect("name=uuid");
            (name.to_string(), uuid.to_string())
        })
        .collect();
    let _ = rustls::crypto::ring::default_provider().install_default();
    // As production polls: several syncs, so any later-pass lookup shows.
    let syncs: Vec<Option<String>> = (0..3)
        .map(|_| sync_api::run_full_sync_blocking(db.clone(), lwd.clone(), NET.into(), 1).err())
        .collect();
    let balances: BTreeMap<String, serde_json::Value> = accounts
        .into_iter()
        .map(|(name, uuid)| {
            let value = match balance_of(&db, &uuid) {
                Ok(b) => serde_json::to_value(b).unwrap(),
                Err(e) => serde_json::json!({ "error": e }),
            };
            (name, value)
        })
        .collect();
    std::fs::write(
        &out,
        serde_json::to_vec_pretty(&serde_json::json!({ "syncs": syncs, "balances": balances }))
            .unwrap(),
    )
    .expect("write the restart child's result");
}

/// A gift card held by the harness: an Orchard-only account outside Alice's wallet.
pub struct GiftCard {
    pub mnemonic: String,
    pub address: String,
}

impl GiftCard {
    pub fn generate() -> Self {
        let card = wallet_api::generate_software_account(NET.into()).expect("gift card account");
        GiftCard {
            mnemonic: card.mnemonic,
            address: card.unified_address,
        }
    }

    /// Claims `amount` into `to_ua` through Vizor's claim path, from a
    /// separate claim DB, as the app does. Returns the claim txid.
    pub fn claim(&self, chain: &Chain, birthday: u64, to_ua: &str, amount: u64) -> String {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("claim.db").to_string_lossy().to_string();
        let account = wallet_api::import_wallet(
            self.mnemonic.clone(),
            String::new(),
            Some(birthday),
            NET.into(),
            db.clone(),
            Some("card".into()),
        )
        .expect("import gift card");
        sync_api::run_payment_link_claim_sync(
            format!("th-claim-{}", FLOW.fetch_add(1, Ordering::SeqCst)),
            db.clone(),
            chain.lwd_url(),
            NET.into(),
            false,
        )
        .expect("claim sync");
        let flow = flow_id();
        let proposal = sync_api::propose_payment_link_claim(
            db.clone(),
            NET.into(),
            account.account_uuid,
            flow.clone(),
            to_ua.into(),
            amount,
        )
        .expect("propose claim");
        let result = sync_api::execute_proposal(
            db,
            chain.lwd_url(),
            proposal.proposal_id,
            flow,
            self.mnemonic.as_bytes().to_vec(),
            None,
            None,
        )
        .expect("execute claim");
        result.txids.split(',').next().unwrap().to_string()
    }
}

/// Collects every view of every wallet under one checkpoint label.
#[derive(Serialize)]
pub struct Observation {
    pub checkpoint: String,
    pub tip: u64,
    pub tip_hash: String,
    pub views: Vec<AccountView>,
    pub requests: BTreeMap<String, Vec<crate::proxy::RequestRecord>>,
    pub sync_results: BTreeMap<String, Option<String>>,
}

/// Raises the wallet at `db` to private recovery through the production
/// toggle-on path, and returns the policy that results. Panics unless it is
/// `PrivateRequired`.
fn raise_private(db: &str) -> sync_api::ApiAppliedTransparentPolicy {
    let applied = sync_api::reconcile_transparent_policy(db.to_owned(), NET.into(), true)
        .expect("raise the transparent policy to private recovery")
        .expect("a wallet exists");
    assert_eq!(
        applied.mode,
        sync_api::ApiTransparentLedgerMode::PrivateRequired,
        "the policy was not raised; is ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT set in a debug build?"
    );
    applied
}
