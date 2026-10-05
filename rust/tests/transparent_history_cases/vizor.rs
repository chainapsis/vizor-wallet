//! Vizor under test, driven only through `rust_lib_zcash_wallet::api`.
//!
//! - V builder: production send / shield / TEX / gift-card paths.
//! - Variants: R (the DB that built or observed), N (fresh restore of Alice's
//!   seeds), O (R's files copied to a new path: a reopen with no in-process
//!   state keyed by the old path).
//! - Observation: balances, the owned transparent ledger, history rows,
//!   details, and every lightwalletd request (through the proxy).

use std::{
    collections::BTreeMap,
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
    pub fn import(label: &str, chain: &Chain, a0: &Party, a1: &Party) -> Self {
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
        if crate::report::profile() == "private" {
            // The production toggle-on path: the wallet durably requires
            // private recovery before its first sync.
            sync_api::reconcile_transparent_policy(db.clone(), NET.into(), true)
                .expect("raise the transparent policy to private recovery");
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
        .unwrap_or_else(|e| panic!("V shield {}: {e}", account.name));
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

    pub fn observe(&self, account: &str) -> AccountView {
        let uuid = self.account(account).uuid.clone();
        let (balance, balance_error) =
            match sync_api::get_balance(self.db.clone(), NET.into(), uuid.clone()) {
                Ok(b) => (
                    Some(Balance {
                        availability: match b.availability {
                            sync_api::WalletBalanceAvailability::Available => "available",
                            sync_api::WalletBalanceAvailability::SummaryUnavailable => {
                                "summary_unavailable"
                            }
                            sync_api::WalletBalanceAvailability::AccountUnavailable => {
                                "account_unavailable"
                            }
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
                                sync_api::TransparentStopReason::Ledger => "ledger",
                                sync_api::TransparentStopReason::LegacyDiscrepancy => {
                                    "legacy_discrepancy"
                                }
                                sync_api::TransparentStopReason::Withdrawn => "withdrawn",
                                sync_api::TransparentStopReason::Stalled => "stalled",
                                sync_api::TransparentStopReason::NotSelected => "not_selected",
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
                    }),
                    None,
                ),
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
