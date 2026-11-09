//! Golden Activity rows and receipts over the real wallet schema.
//!
//! Each case rebuilds a scenario that Vizor's history and receipt tests once
//! drove through a stand-in `v_transactions` table. Here the state lives in
//! the migrated wallet's own tables, from which the library derives
//! `v_transactions` and `v_tx_outputs`, or it is built by the library's
//! private recovery. Every assertion reads only what `get_transaction_history`
//! and `get_transaction_detail` return, so the same file runs unchanged
//! against any implementation of those two reads: a case that passes on two
//! implementations shows they give the same Activity rows and receipts.
//!
//! A golden is one line per Activity row (`row_line`) or receipt
//! (`detail_line`). Addresses print as the names `Names` gives them.

use rusqlite::{params, Connection};
use secrecy::SecretVec;
use transparent::{address::TransparentAddress, bundle::OutPoint, keys::TransparentKeyScope};
use zcash_client_backend::data_api::{
    testing::TestBuilder,
    transparent_ledger::{
        ReceiveEvent, SpendEvent, TransactionMetadata, TransparentDetailWrite as _,
        TransparentDisplayFacts, TransparentDisplayOutput, TransparentDisplayProvenance,
        TransparentDisplaySender, TransparentDisplayStore, TransparentLedgerMode,
        TransparentLedgerWrite as _, WatchOrigin, WholeTransactionFee,
    },
};
use zcash_client_sqlite::testing::{db::TestDbFactory, BlockCache};
use zcash_primitives::{
    block::BlockHash,
    transaction::{Transaction, TxId},
};
use zcash_protocol::{
    consensus::{BlockHeight, BranchId},
    value::Zatoshis,
};

use super::private_shielding_tests::{
    commit, cover, external, regtest, revision, scan_unrelated_blocks, set_policy, watch, State,
    NU6_3,
};
use super::*;
use crate::wallet::keys;
use crate::wallet::network::configure_regtest_nu6_3_activation_height;
use zcash_client_backend::data_api::Account as _;

const NETWORK: WalletNetwork = WalletNetwork::Regtest;
/// The scanned chain tip of every wallet built by [`wallet`].
const TIP: u32 = 200;
/// The creation time of the locally built transactions.
const CREATED: &str = "2026-04-28T13:03:00Z";
/// An expiry height the scanned chain has not reached.
const LIVE_EXPIRY: u32 = TIP + 40;
/// An expiry height the scanned chain has passed.
const PASSED_EXPIRY: u32 = 150;
/// The empty memo, as the wallet stores it.
const EMPTY_MEMO: &[u8] = &[0xf6];

// ======================== Rendering ========================

/// Display names for addresses and account UUIDs.
#[derive(Default)]
struct Names(Vec<(String, String)>);

impl Names {
    fn add(&mut self, value: impl Into<String>, name: &str) {
        let value = value.into();
        if !self.0.iter().any(|(v, _)| *v == value) {
            self.0.push((value, name.to_owned()));
        }
    }

    fn name(&self, value: Option<&str>) -> String {
        match value {
            None => "-".to_owned(),
            Some(value) => self
                .0
                .iter()
                .find(|(v, _)| v == value)
                .map(|(_, name)| name.clone())
                .unwrap_or_else(|| format!("?{value}")),
        }
    }
}

/// A transaction's tag: its first txid byte, as `txid(tag)` builds it.
fn tag(txid_hex: &str) -> &str {
    &txid_hex[..2]
}

/// A txid whose bytes are not uniform, so a byte-order mix-up shows.
fn txid(tag: u8) -> [u8; 32] {
    let mut bytes = [tag; 32];
    bytes[31] = 0x5a;
    bytes
}

/// Every transaction's rows read alone ([`get_transaction_rows`], as a
/// receipt reads them) are exactly its rows in the whole `history`, field
/// for field and in order: a receipt shows what Activity lists.
fn assert_rows_read_alone_match(path: &str, account: &str, history: &[TransactionInfo]) {
    let txids: std::collections::BTreeSet<&str> =
        history.iter().map(|row| row.txid_hex.as_str()).collect();
    for txid in txids {
        let alone: Vec<String> = get_transaction_rows(path, NETWORK, account, txid)
            .unwrap()
            .iter()
            .map(full_row)
            .collect();
        let listed: Vec<String> = history
            .iter()
            .filter(|row| row.txid_hex == txid)
            .map(full_row)
            .collect();
        assert_eq!(alone, listed, "rows of {}", tag(txid));
    }
    let unknown = hex::encode([0xee; 32]);
    assert!(get_transaction_rows(path, NETWORK, account, &unknown)
        .unwrap()
        .is_empty());
}

/// Every field of a row, for exact comparison.
fn full_row(r: &TransactionInfo) -> String {
    format!(
        "{} block_time={} created={}",
        row_line(r),
        r.block_time,
        r.created_time
    )
}

fn row_line(r: &TransactionInfo) -> String {
    let parent = match &r.funding_parent_txid {
        Some(parent) => format!(
            " parent={}@{:?}/{:?}",
            tag(parent),
            r.funding_parent_mined_height,
            r.funding_parent_expired
        ),
        None => String::new(),
    };
    format!(
        "{} {} {} pool={}/{} fee={:?}:{} incl={} complete={} prov={} mined={}{} delta={} t={}{}",
        tag(&r.txid_hex),
        r.tx_kind,
        r.display_amount,
        r.display_pool,
        r.activity_pool.as_deref().unwrap_or("-"),
        r.fee_state,
        r.fee,
        u8::from(r.amount_includes_fee),
        u8::from(r.details_complete),
        u8::from(r.provisional),
        r.mined_height,
        if r.expired_unmined { " expired" } else { "" },
        r.account_balance_delta,
        u8::from(r.is_transparent),
        parent,
    )
}

fn detail_line(d: &TransactionDetail, names: &Names) -> String {
    let outputs = d
        .outputs
        .iter()
        .map(|o| {
            format!(
                "{}:{}:{}/{}:{}",
                names.name(o.address.as_deref()),
                o.amount_zatoshi,
                o.pool,
                o.activity_pool.as_deref().unwrap_or("-"),
                u8::from(o.uses_orchard_receiver)
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    let view = match &d.transparent_details {
        None => "-".to_owned(),
        Some(TransparentDetailsView::Available {
            rows,
            output_count,
            omissions,
        }) => format!(
            "rows[{}]/{} omit{:?}",
            rows.iter()
                .map(|r| format!(
                    "{}:{}:{}:{}",
                    r.output_index,
                    names.name(r.address.as_deref()),
                    r.amount_zatoshi,
                    u8::from(r.is_own)
                ))
                .collect::<Vec<_>>()
                .join(","),
            output_count,
            omissions
        ),
        Some(TransparentDetailsView::Pending) => "pending".to_owned(),
        Some(TransparentDetailsView::Unavailable) => "unavailable".to_owned(),
        Some(TransparentDetailsView::GaveUp) => "gave-up".to_owned(),
        Some(TransparentDetailsView::NotCovered) => "not-covered".to_owned(),
    };
    format!(
        "{} to={} from={} src={} acct={} memo={:?} complete={} prov={} settled={} delta={} \
         fee={:?} net={:?} outs=[{}] t={}",
        d.tx_kind,
        names.name(d.primary_address.as_deref()),
        names.name(d.source_address.as_deref()),
        d.source_pool.as_deref().unwrap_or("-"),
        names.name(d.source_account_uuid.as_deref()),
        d.memo,
        u8::from(d.details_complete),
        u8::from(d.provisional),
        u8::from(d.effects_settled),
        d.account_balance_delta,
        d.fee,
        d.network_fee,
        outputs,
        view,
    )
}

/// Compares rendered lines with a golden, one trimmed line each.
fn check(what: &str, actual: Vec<String>, golden: &str) {
    let actual = actual
        .iter()
        .map(|line| line.trim())
        .collect::<Vec<_>>()
        .join("\n");
    let golden = golden
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    assert!(
        actual == golden,
        "{what}: golden mismatch\n--- actual ---\n{actual}\n--- golden ---\n{golden}\n"
    );
}

// ======================== Wallet fixture ========================

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Pool {
    Transparent,
    Sapling,
    Orchard,
    Ironwood,
}

impl Pool {
    fn code(self) -> i64 {
        match self {
            Pool::Transparent => 0,
            Pool::Sapling => 2,
            Pool::Orchard => 3,
            Pool::Ironwood => 4,
        }
    }
}

/// Where an owned output was received.
#[derive(Clone, Copy)]
enum Recv {
    /// The account's first external address: its unified address for a
    /// shielded note, that address's transparent receiver otherwise.
    Ext,
    /// Internal (change) scope.
    Int,
    /// The account's `n`th ephemeral (ZIP 320) transparent address.
    Eph(i64),
    /// An external-scope address the wallet did not store.
    Unstored,
}

/// An owned output: its pool and row in that pool's table.
#[derive(Clone, Copy)]
struct Input(Pool, i64);

#[derive(Clone)]
struct Addr {
    id: i64,
    address: String,
}

struct W {
    _dir: tempfile::TempDir,
    path: String,
    conn: Connection,
    a: AccountUuid,
    b: AccountUuid,
    c: AccountUuid,
    names: Names,
    next_funding: u8,
    /// Another wallet's Orchard unified address and transparent address.
    foreign_ua: String,
    foreign_t: String,
}

/// Three software accounts, A, B and C, scanned through [`TIP`].
fn wallet() -> W {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let (a, _) = keys::init_db_and_create_account(
        &path,
        NETWORK,
        &SecretVec::new(vec![1; 32]),
        Some(100),
        "A",
    )
    .unwrap();
    let (b, _) =
        keys::add_account(&path, NETWORK, "B", &SecretVec::new(vec![2; 32]), Some(100)).unwrap();
    let (c, _) =
        keys::add_account(&path, NETWORK, "C", &SecretVec::new(vec![3; 32]), Some(100)).unwrap();
    let conn = Connection::open(&path).unwrap();
    conn.pragma_update(None, "foreign_keys", true).unwrap();
    let birthday: u32 = conn
        .query_row("SELECT MIN(birthday_height) FROM accounts", [], |row| {
            row.get(0)
        })
        .unwrap();
    for height in birthday..=TIP {
        let mut hash = [0; 32];
        hash[..4].copy_from_slice(&height.to_le_bytes());
        conn.execute(
            "INSERT INTO blocks (height, hash, time, sapling_tree,
                 sapling_commitment_tree_size, orchard_commitment_tree_size,
                 ironwood_commitment_tree_size)
             VALUES (?1, ?2, ?3, x'00', 0, 0, 0)",
            params![height, hash.as_slice(), block_time(height)],
        )
        .unwrap();
    }
    conn.execute("DELETE FROM scan_queue", []).unwrap();
    conn.execute(
        "INSERT INTO scan_queue (block_range_start, block_range_end, priority)
         VALUES (?1, ?2, 10)",
        [birthday, TIP + 1],
    )
    .unwrap();
    let foreign_seed = SecretVec::new(vec![9; 32]);
    let mut w = W {
        _dir: dir,
        path,
        conn,
        a: parse_account_uuid(&a).unwrap(),
        b: parse_account_uuid(&b).unwrap(),
        c: parse_account_uuid(&c).unwrap(),
        names: Names::default(),
        next_funding: 0x01,
        foreign_ua: keys::derive_gift_address(NETWORK, &foreign_seed, 0).unwrap(),
        foreign_t: keys::software_account_first_external_transparent_address(
            NETWORK,
            &foreign_seed,
            0,
        )
        .unwrap(),
    };
    for (account, name) in [(w.a, "A"), (w.b, "B"), (w.c, "C")] {
        w.names.add(account.expose_uuid().to_string(), name);
        let ua = w.ua(account).address;
        w.names.add(ua, &format!("{name}.ua"));
        let t = w.ext_t(account).address;
        w.names.add(t, &format!("{name}.t"));
        let int = w.address(account, 1, true, 0).address;
        w.names.add(int, &format!("{name}.int"));
        for n in 0..2 {
            let eph = w.eph(account, n).address;
            w.names.add(eph, &format!("{name}.eph{n}"));
        }
    }
    let (fua, ft) = (w.foreign_ua.clone(), w.foreign_t.clone());
    w.names.add(fua, "F.ua");
    w.names.add(ft, "F.t");
    w
}

/// Block times put the scanned chain on 2026-04-28, five minutes apart.
fn block_time(height: u32) -> u32 {
    1_777_334_400 + height * 300
}

impl W {
    fn id(&self, account: AccountUuid) -> i64 {
        self.conn
            .query_row(
                "SELECT id FROM accounts WHERE uuid = ?1",
                [account.expose_uuid().as_bytes()],
                |row| row.get(0),
            )
            .unwrap()
    }

    fn address(&self, account: AccountUuid, scope: i64, transparent: bool, nth: i64) -> Addr {
        self.conn
            .query_row(
                "SELECT id,
                     CASE WHEN ?3 THEN cached_transparent_receiver_address ELSE address END
                 FROM addresses
                 WHERE account_id = ?1 AND key_scope = ?2
                   AND (NOT ?3 OR cached_transparent_receiver_address IS NOT NULL)
                 ORDER BY diversifier_index_be
                 LIMIT 1 OFFSET ?4",
                params![self.id(account), scope, transparent, nth],
                |row| {
                    Ok(Addr {
                        id: row.get(0)?,
                        address: row.get(1)?,
                    })
                },
            )
            .unwrap_or_else(|e| panic!("no scope {scope} address {nth}: {e}"))
    }

    /// The account's first external unified address.
    fn ua(&self, account: AccountUuid) -> Addr {
        self.address(account, 0, false, 0)
    }

    /// The account's first external transparent receiver.
    fn ext_t(&self, account: AccountUuid) -> Addr {
        self.address(account, 0, true, 0)
    }

    fn eph(&self, account: AccountUuid, n: i64) -> Addr {
        self.address(account, 2, true, n)
    }

    /// Records a transaction. A locally built one has `created`.
    fn tx(&self, tag: u8, mined: Option<u32>, created: Option<&str>, fee: Option<u64>) -> i64 {
        self.conn
            .execute(
                "INSERT INTO transactions (txid, created, mined_height, tx_index,
                     expiry_height, fee, min_observed_height)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    txid(tag),
                    created,
                    mined,
                    mined.map(|_| 1),
                    LIVE_EXPIRY,
                    fee,
                    mined.unwrap_or(TIP),
                ],
            )
            .unwrap();
        self.conn.last_insert_rowid()
    }

    fn set(&self, tag: u8, assignments: &str) {
        self.conn
            .execute(
                &format!("UPDATE transactions SET {assignments} WHERE txid = ?1"),
                [txid(tag)],
            )
            .unwrap();
    }

    /// Records `account`'s receipt of output `index` of `pool` in `tx`.
    #[allow(clippy::too_many_arguments)]
    fn recv(
        &self,
        tx: i64,
        pool: Pool,
        index: u32,
        account: AccountUuid,
        value: u64,
        to: Recv,
        memo: Option<&[u8]>,
    ) -> Input {
        let account_id = self.id(account);
        let (address, scope, change) = match to {
            Recv::Ext if pool == Pool::Transparent => (Some(self.ext_t(account)), 0, false),
            Recv::Ext => (Some(self.ua(account)), 0, false),
            Recv::Int if pool == Pool::Transparent => {
                (Some(self.address(account, 1, true, 0)), 1, true)
            }
            Recv::Int => (None, 1, true),
            Recv::Eph(n) => {
                assert_eq!(pool, Pool::Transparent);
                (Some(self.eph(account, n)), 2, false)
            }
            Recv::Unstored => (None, 0, false),
        };
        let address_id = address.as_ref().map(|a| a.id);
        let memo = memo.map(padded_memo);
        match pool {
            Pool::Transparent => self.conn.execute(
                "INSERT INTO transparent_received_outputs (transaction_id, output_index,
                     account_id, address, script, value_zat, address_id)
                 VALUES (?1, ?2, ?3, ?4, zeroblob(25), ?5, ?6)",
                params![
                    tx,
                    index,
                    account_id,
                    address.expect("a transparent receiver").address,
                    value,
                    address_id
                ],
            ),
            Pool::Sapling => self.conn.execute(
                "INSERT INTO sapling_received_notes (transaction_id, output_index, account_id,
                     diversifier, value, rcm, is_change, memo, recipient_key_scope, address_id)
                 VALUES (?1, ?2, ?3, zeroblob(11), ?4, zeroblob(32), ?5, ?6, ?7, ?8)",
                params![tx, index, account_id, value, change, memo, scope, address_id],
            ),
            Pool::Orchard | Pool::Ironwood => self.conn.execute(
                &format!(
                    "INSERT INTO {}_received_notes (transaction_id, action_index, account_id,
                         diversifier, value, rho, rseed, is_change, memo, recipient_key_scope,
                         address_id, note_version)
                     VALUES (?1, ?2, ?3, zeroblob(11), ?4, zeroblob(32), zeroblob(32), ?5, ?6,
                         ?7, ?8, ?9)",
                    if pool == Pool::Orchard {
                        "orchard"
                    } else {
                        "ironwood"
                    }
                ),
                params![
                    tx,
                    index,
                    account_id,
                    value,
                    change,
                    memo,
                    scope,
                    address_id,
                    if pool == Pool::Orchard { 2 } else { 3 }
                ],
            ),
        }
        .unwrap();
        Input(pool, self.conn.last_insert_rowid())
    }

    /// Records the output `index` of `pool` that `from` created in `tx`, as
    /// the wallet records the outputs of a transaction it built or decrypted
    /// with its outgoing viewing key.
    #[allow(clippy::too_many_arguments)]
    fn sent(
        &self,
        tx: i64,
        pool: Pool,
        index: u32,
        from: AccountUuid,
        to_account: Option<AccountUuid>,
        to_address: Option<&str>,
        value: u64,
        memo: Option<&[u8]>,
    ) {
        self.conn
            .execute(
                "INSERT INTO sent_notes (transaction_id, output_pool, output_index,
                     from_account_id, to_account_id, to_address, value, memo)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![
                    tx,
                    pool.code(),
                    index,
                    self.id(from),
                    to_account.map(|a| self.id(a)),
                    to_address,
                    value,
                    memo.map(padded_memo),
                ],
            )
            .unwrap();
    }

    fn spend(&self, input: Input, tx: i64) {
        let Input(pool, id) = input;
        let (table, column) = match pool {
            Pool::Transparent => (
                "transparent_received_output_spends",
                "transparent_received_output_id",
            ),
            Pool::Sapling => ("sapling_received_note_spends", "sapling_received_note_id"),
            Pool::Orchard => ("orchard_received_note_spends", "orchard_received_note_id"),
            Pool::Ironwood => ("ironwood_received_note_spends", "ironwood_received_note_id"),
        };
        self.conn
            .execute(
                &format!("INSERT INTO {table} ({column}, transaction_id) VALUES (?1, ?2)"),
                params![id, tx],
            )
            .unwrap();
    }

    /// An external receipt of `value` by `account`, mined in its own earlier
    /// transaction, ready to be spent.
    fn fund(&mut self, account: AccountUuid, pool: Pool, value: u64) -> Input {
        let tag = self.next_funding;
        self.next_funding += 1;
        let tx = self.tx(tag, Some(100 + u32::from(tag)), None, None);
        self.recv(tx, pool, 0, account, value, Recv::Ext, None)
    }

    fn history(&self, account: AccountUuid, limit: Option<u32>) -> Vec<TransactionInfo> {
        let account = account.expose_uuid().to_string();
        let history = get_transaction_history(&self.path, NETWORK, limit, &account).unwrap();
        if limit.is_none() {
            assert_rows_read_alone_match(&self.path, &account, &history);
            let index =
                history_pages::index(&self.path, NETWORK, parse_account_uuid(&account).unwrap())
                    .unwrap();
            for batch in index.summaries.chunks(20) {
                let ids: Vec<_> = batch.iter().map(|s| s.txid_hex.clone()).collect();
                let page = history_pages::rows(
                    &self.path,
                    NETWORK,
                    parse_account_uuid(&account).unwrap(),
                    &index.snapshot_id,
                    &ids,
                )
                .unwrap();
                if page.stale {
                    break;
                }
                let expected: Vec<_> = history
                    .iter()
                    .filter(|r| ids.contains(&r.txid_hex))
                    .map(full_row)
                    .collect();
                assert_eq!(
                    page.transactions.iter().map(full_row).collect::<Vec<_>>(),
                    expected,
                    "paged rows agree with unlimited history"
                );
            }
            // The unchanged unlimited path is the oracle for every golden's
            // bounded read, including all fields and intra-transaction rows.
            for limit in [0, 1, 2, 10, u32::MAX] {
                let recent =
                    get_transaction_history(&self.path, NETWORK, Some(limit), &account).unwrap();
                assert_eq!(recent, history[..history.len().min(limit as usize)]);
            }
        }
        history
    }

    /// The Activity rows of the transactions `tags`, in display order.
    fn rows(&self, account: AccountUuid, tags: &[u8]) -> Vec<String> {
        self.history(account, None)
            .iter()
            .filter(|row| {
                tags.iter()
                    .any(|t| tag(&row.txid_hex) == format!("{t:02x}"))
            })
            .map(row_line)
            .collect()
    }

    /// Every Activity row, funding receipts included, in display order.
    fn all_rows(&self, account: AccountUuid, limit: Option<u32>) -> Vec<String> {
        self.history(account, limit).iter().map(row_line).collect()
    }

    fn detail(&self, account: AccountUuid, tag: u8, kind: &str) -> String {
        let detail = get_transaction_detail(
            &self.path,
            NETWORK,
            &account.expose_uuid().to_string(),
            &hex::encode(txid(tag)),
            kind,
        )
        .unwrap();
        detail_line(&detail, &self.names)
    }
}

/// A memo as the wallet stores it: the empty memo as one byte, any other
/// padded to 512 bytes.
fn padded_memo(memo: &[u8]) -> Vec<u8> {
    if memo == EMPTY_MEMO {
        return memo.to_vec();
    }
    let mut padded = memo.to_vec();
    padded.resize(512, 0);
    padded
}

// ======================== TEX funding steps ========================

/// One ZIP 320 send: `funding` moves an Orchard note of `amount + funding_fee`
/// to the account's ephemeral address `eph`, and `send` spends that output to
/// pay another wallet's transparent address `amount - send_fee`. Both are
/// built together, so they share their creation time and expiry.
fn tex_pair(w: &mut W, funding: u8, send: u8, eph: i64, amount: u64, fees: (u64, u64)) {
    let (funding_fee, send_fee) = fees;
    let input = w.fund(w.a, Pool::Orchard, amount + funding_fee);
    let funding_tx = w.tx(funding, None, Some(CREATED), Some(funding_fee));
    w.spend(input, funding_tx);
    let ephemeral = w.recv(
        funding_tx,
        Pool::Transparent,
        0,
        w.a,
        amount,
        Recv::Eph(eph),
        None,
    );
    let eph_address = w.eph(w.a, eph).address;
    w.sent(
        funding_tx,
        Pool::Transparent,
        0,
        w.a,
        Some(w.a),
        Some(&eph_address),
        amount,
        None,
    );
    let send_tx = w.tx(send, None, Some(CREATED), Some(send_fee));
    w.spend(ephemeral, send_tx);
    let to = w.foreign_t.clone();
    w.sent(
        send_tx,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&to),
        amount - send_fee,
        None,
    );
}

/// Exercise the candidate loader with real library reads and record which
/// transactions it asks for. The unlimited production read remains the oracle.
fn recent_batches(w: &W, limit: u32) -> (Vec<TransactionInfo>, Vec<usize>) {
    let conn = open_readonly_conn(&w.path).unwrap();
    let read = conn.unchecked_transaction().unwrap();
    let bases = read_history_bases(&read, &w.path, NETWORK, w.a).unwrap();
    let mut seen = HashSet::new();
    let mut batches = Vec::new();
    let rows = recent_history::assemble_recent_history(
        bases,
        w.a.expose_uuid().as_bytes(),
        limit,
        |batch| {
            batches.push(batch.len());
            for base in batch.iter() {
                assert!(
                    seen.insert(base.txid.clone()),
                    "must not load a transaction twice"
                );
            }
            attach_history_details(&read, &w.path, NETWORK, w.a, batch)?;
            read_history_outputs(
                &read,
                w.a.expose_uuid().as_bytes(),
                batch.iter().map(|b| b.txid.as_slice()),
            )
        },
    )
    .unwrap();
    let all =
        get_transaction_history(&w.path, NETWORK, None, &w.a.expose_uuid().to_string()).unwrap();
    assert_eq!(rows, all[..all.len().min(limit as usize)]);
    (rows, batches)
}

fn recent_receipts(w: &W) {
    for tag in 0x60..0xa0 {
        let tx = w.tx(tag, Some(190), None, None);
        w.recv(tx, Pool::Orchard, 0, w.a, 100_000, Recv::Ext, None);
    }
}

fn hidden_funding(w: &mut W, tag: u8) {
    let input = w.fund(w.a, Pool::Orchard, 1_010_000);
    let tx = w.tx(tag, None, Some(CREATED), Some(10_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Transparent, 0, w.a, 1_000_000, Recv::Eph(0), None);
    let eph = w.eph(w.a, 0).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        Some(w.a),
        Some(&eph),
        1_000_000,
        None,
    );
}

#[test]
fn golden_recent_history_loads_only_latest_receipts() {
    let w = wallet();
    recent_receipts(&w);
    assert_eq!(recent_batches(&w, 10).1, [20]);
    assert!(recent_batches(&w, 0).1.is_empty());
    assert_eq!(recent_batches(&w, u32::MAX).0.len(), 64);
    // A second account has no history, even with the first account populated.
    assert!(w.history(w.b, Some(10)).is_empty());
}

#[test]
fn golden_recent_history_expands_and_reuses_hidden_dependencies() {
    let mut w = wallet();
    recent_receipts(&w);
    for tag in 0xb0..0xdd {
        hidden_funding(&mut w, tag);
    }
    let (rows, batches) = recent_batches(&w, 10);
    assert_eq!(rows.len(), 10);
    // The 45 hidden pending transactions form one dependency group. Expanding
    // through them must neither re-read the group nor stop before visible rows.
    assert!(batches.len() > 1, "{batches:?}");
    assert_eq!(batches[0], 45);
}

#[test]
fn golden_recent_history_does_not_fill_quota_with_older_tex_peers() {
    let mut w = wallet();
    recent_receipts(&w);
    tex_pair(&mut w, 0xa2, 0xa1, 0, 10_010_000, (40_000, 10_000));
    w.set(
        0xa1,
        "mined_height = 101, tx_index = 1, min_observed_height = 101",
    );
    for tag in 0xb0..0xc3 {
        hidden_funding(&mut w, tag);
    }
    let (rows, batches) = recent_batches(&w, 1);
    assert_eq!(rows[0].tx_kind, "received");
    assert_eq!(rows[0].mined_height, 190);
    assert_eq!(batches[0], 21);
    assert!(batches.len() > 1);
}

#[test]
fn golden_recent_history_keeps_distant_same_amount_tex_pairs() {
    let mut w = wallet();
    recent_receipts(&w);
    tex_pair(&mut w, 0xa8, 0xa7, 0, 10_010_000, (40_000, 10_000));
    tex_pair(&mut w, 0xaa, 0xa9, 1, 10_010_000, (50_000, 10_000));
    for tag in [0xa8, 0xaa] {
        w.set(
            tag,
            "mined_height = 101, tx_index = 1, min_observed_height = 101",
        );
    }
    let (rows, batches) = recent_batches(&w, 1);
    assert_eq!(rows[0].fee, 60_000);
    assert_eq!(rows[0].funding_parent_txid, Some(hex::encode(txid(0xaa))));
    assert_eq!(batches, [22]);
}

/// Was `history_suppresses_funding_step_after_limit_filtering`.
#[test]
fn golden_funding_step_is_hidden_and_paired_after_the_limit() {
    let mut w = wallet();
    tex_pair(&mut w, 0xa2, 0xa1, 0, 10_010_000, (40_000, 10_000));
    check(
        "pending",
        w.all_rows(w.a, Some(1)),
        "a1 sent 10000000 pool=transparent/transparent fee=Known:50000 incl=0 complete=1 prov=0 \
         mined=0 delta=-10010000 t=1 parent=a2@Some(0)/Some(false)",
    );
    w.set(
        0xa2,
        "mined_height = 190, tx_index = 1, min_observed_height = 190",
    );
    check(
        "funding mined",
        w.all_rows(w.a, Some(1)),
        "a1 sent 10000000 pool=transparent/transparent fee=Known:50000 incl=0 complete=1 prov=0 \
         mined=0 delta=-10010000 t=1 parent=a2@Some(190)/Some(false)",
    );
    // Expiry is shared, so both steps expire together.
    w.set(
        0xa2,
        &format!(
            "mined_height = NULL, tx_index = NULL, min_observed_height = {TIP}, \
             expiry_height = {PASSED_EXPIRY}"
        ),
    );
    w.set(0xa1, &format!("expiry_height = {PASSED_EXPIRY}"));
    check(
        "both expired",
        w.all_rows(w.a, Some(1)),
        "a1 sent 10000000 pool=transparent/transparent fee=Known:50000 incl=0 complete=1 prov=0 \
         mined=0 expired delta=-10010000 t=1 parent=a2@Some(0)/Some(true)",
    );
}

/// Was `history_pairs_suppressed_funding_fees_by_transparent_amount`.
#[test]
fn golden_funding_fees_pair_by_transparent_amount() {
    let mut w = wallet();
    tex_pair(&mut w, 0xa4, 0xa3, 0, 10_010_000, (40_000, 10_000));
    tex_pair(&mut w, 0xa6, 0xa5, 1, 20_015_000, (50_000, 15_000));
    check(
        "rows",
        w.rows(w.a, &[0xa3, 0xa4, 0xa5, 0xa6]),
        r#"
            a5 sent 20000000 pool=transparent/transparent fee=Known:65000 incl=0 complete=1 prov=0 mined=0 delta=-20015000 t=1 parent=a6@Some(0)/Some(false)
            a3 sent 10000000 pool=transparent/transparent fee=Known:50000 incl=0 complete=1 prov=0 mined=0 delta=-10010000 t=1 parent=a4@Some(0)/Some(false)
        "#,
    );
}

/// Was `history_pairs_same_amount_funding_fees_by_insert_order`.
#[test]
fn golden_same_amount_funding_fees_pair_by_insert_order() {
    let mut w = wallet();
    tex_pair(&mut w, 0xa8, 0xa7, 0, 10_010_000, (40_000, 10_000));
    tex_pair(&mut w, 0xaa, 0xa9, 1, 10_010_000, (50_000, 10_000));
    check(
        "rows",
        w.rows(w.a, &[0xa7, 0xa8, 0xa9, 0xaa]),
        r#"
            a9 sent 10000000 pool=transparent/transparent fee=Known:60000 incl=0 complete=1 prov=0 mined=0 delta=-10010000 t=1 parent=aa@Some(0)/Some(false)
            a7 sent 10000000 pool=transparent/transparent fee=Known:50000 incl=0 complete=1 prov=0 mined=0 delta=-10010000 t=1 parent=a8@Some(0)/Some(false)
        "#,
    );
}

/// Was `history_omits_unmatched_funding_step`.
#[test]
fn golden_unmatched_funding_step_is_omitted() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 1_010_000);
    let tx = w.tx(0xe6, None, Some(CREATED), Some(10_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Transparent, 0, w.a, 1_000_000, Recv::Eph(0), None);
    let eph = w.eph(w.a, 0).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        Some(w.a),
        Some(&eph),
        1_000_000,
        None,
    );
    check("rows", w.rows(w.a, &[0xe6]), r#""#);
}

/// Was `history_sent_to_transparent_excludes_shielded_change` and
/// `detail_sent_to_transparent_prefers_external_recipient_over_shielded_change`.
#[test]
fn golden_transparent_send_excludes_shielded_change_and_ephemeral_output() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 1_265_000);
    let tx = w.tx(0xc5, Some(190), Some(CREATED), Some(15_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Transparent, 0, w.a, 150_000, Recv::Eph(0), None);
    let eph = w.eph(w.a, 0).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        Some(w.a),
        Some(&eph),
        150_000,
        None,
    );
    w.recv(tx, Pool::Orchard, 0, w.a, 1_000_000, Recv::Int, None);
    w.sent(tx, Pool::Orchard, 0, w.a, Some(w.a), None, 1_000_000, None);
    let to = w.foreign_t.clone();
    w.sent(
        tx,
        Pool::Transparent,
        1,
        w.a,
        None,
        Some(&to),
        100_000,
        None,
    );
    check(
        "rows",
        w.rows(w.a, &[0xc5]),
        r#"
            c5 sent 100000 pool=transparent/transparent fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-115000 t=1
        "#,
    );
    check(
        "sent",
        vec![w.detail(w.a, 0xc5, "sent")],
        r#"
            sent to=F.t from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-115000 fee=Some(15000) net=Some(15000) outs=[F.t:100000:transparent/transparent:0] t=unavailable
        "#,
    );
}

// ======================== Self-sends and other accounts ========================

/// Was `history_splits_same_account_transparent_self_send`.
#[test]
fn golden_transparent_self_send_splits_into_sent_and_received() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Transparent, 18_302_101);
    let tx = w.tx(0xb1, Some(190), Some(CREATED), Some(40_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Transparent, 0, w.a, 18_262_101, Recv::Ext, None);
    let t = w.ext_t(w.a).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        Some(w.a),
        Some(&t),
        18_262_101,
        None,
    );
    check(
        "rows",
        w.rows(w.a, &[0xb1]),
        r#"
            b1 sent 18262101 pool=transparent/transparent fee=Known:40000 incl=0 complete=1 prov=0 mined=190 delta=-40000 t=1
            b1 received 18262101 pool=transparent/transparent fee=Known:40000 incl=0 complete=1 prov=0 mined=190 delta=-40000 t=1
        "#,
    );
}

/// Was `history_splits_same_account_shielded_self_send_and_hides_change`.
#[test]
fn golden_shielded_self_send_splits_and_hides_change() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 17_252_101);
    let tx = w.tx(0xc0, Some(190), Some(CREATED), Some(15_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Orchard, 0, w.a, 1_000_000, Recv::Ext, None);
    let ua = w.ua(w.a).address;
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        Some(&ua),
        1_000_000,
        None,
    );
    w.recv(tx, Pool::Orchard, 1, w.a, 16_237_101, Recv::Int, None);
    w.sent(tx, Pool::Orchard, 1, w.a, Some(w.a), None, 16_237_101, None);
    check(
        "rows",
        w.rows(w.a, &[0xc0]),
        r#"
            c0 sent 1000000 pool=shielded/orchard fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=0
            c0 received 1000000 pool=shielded/orchard fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=0
        "#,
    );
}

/// Was `history_uses_sent_note_when_self_send_key_scope_is_unresolved`: the
/// output reached an address of the account the wallet has no row for.
#[test]
fn golden_self_send_to_an_unstored_address_uses_its_sent_note() {
    let mut w = wallet();
    let unstored = keys::gift_address_variants(NETWORK, &SecretVec::new(vec![1; 32]))
        .unwrap()
        .into_iter()
        .find(|address| {
            w.conn
                .query_row(
                    "SELECT COUNT(*) FROM addresses WHERE address = ?1",
                    [address],
                    |row| row.get::<_, i64>(0),
                )
                .unwrap()
                == 0
        })
        .expect("an address of A the wallet did not store");
    w.names.add(unstored.clone(), "A.unstored");
    let input = w.fund(w.a, Pool::Orchard, 1_015_000);
    let tx = w.tx(0xc7, Some(190), Some(CREATED), Some(15_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Orchard, 0, w.a, 1_000_000, Recv::Unstored, None);
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        Some(&unstored),
        1_000_000,
        None,
    );
    check(
        "rows",
        w.rows(w.a, &[0xc7]),
        r#"
            c7 sent 1000000 pool=shielded/orchard fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=0
            c7 received 1000000 pool=shielded/orchard fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=0
        "#,
    );
}

/// Was `history_preserves_mixed_pool_for_visible_self_outputs`.
#[test]
fn golden_self_send_across_pools_is_mixed() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 6_115_000);
    let tx = w.tx(0xc6, Some(190), Some(CREATED), Some(15_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Transparent, 0, w.a, 100_000, Recv::Ext, None);
    let t = w.ext_t(w.a).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        Some(w.a),
        Some(&t),
        100_000,
        None,
    );
    w.recv(tx, Pool::Orchard, 0, w.a, 1_000_000, Recv::Ext, None);
    let ua = w.ua(w.a).address;
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        Some(&ua),
        1_000_000,
        None,
    );
    w.recv(tx, Pool::Orchard, 1, w.a, 5_000_000, Recv::Int, None);
    w.sent(tx, Pool::Orchard, 1, w.a, Some(w.a), None, 5_000_000, None);
    check(
        "rows",
        w.rows(w.a, &[0xc6]),
        r#"
            c6 sent 1100000 pool=mixed/mixed fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=1
            c6 received 1100000 pool=mixed/mixed fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=1
        "#,
    );
}

/// Was `history_treats_send_to_other_local_account_as_sent` and
/// `history_treats_receive_from_other_local_account_as_received`.
#[test]
fn golden_payment_between_accounts_is_a_send_and_a_receive() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 5_010_000);
    let tx = w.tx(0xb2, Some(190), Some(CREATED), Some(10_000));
    w.spend(input, tx);
    let to = w.ext_t(w.b).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&to),
        5_000_000,
        None,
    );
    w.recv(tx, Pool::Transparent, 0, w.b, 5_000_000, Recv::Ext, None);
    check(
        "A",
        w.rows(w.a, &[0xb2]),
        r#"
            b2 sent 5000000 pool=transparent/transparent fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-5010000 t=1
        "#,
    );
    check(
        "B",
        w.rows(w.b, &[0xb2]),
        r#"
            b2 received 5000000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=190 delta=5000000 t=1
        "#,
    );
    check(
        "receipts",
        vec![w.detail(w.a, 0xb2, "sent"), w.detail(w.b, 0xb2, "received")],
        r#"
            sent to=B.t from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-5010000 fee=Some(10000) net=Some(10000) outs=[B.t:5000000:transparent/transparent:0] t=-
            received to=- from=- src=unknown acct=A memo=None complete=1 prov=0 settled=1 delta=5000000 fee=None net=None outs=[B.t:5000000:transparent/transparent:0] t=unavailable
        "#,
    );
}

/// Was `history_mixed_pool_payment_excludes_the_accounts_own_output` (H09).
#[test]
fn golden_mixed_pool_payment_excludes_the_accounts_own_output() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Transparent, 200_000_000);
    let tx = w.tx(0xc9, Some(190), None, Some(15_000));
    w.spend(input, tx);
    let to = w.foreign_t.clone();
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&to),
        129_985_000,
        None,
    );
    w.recv(tx, Pool::Orchard, 0, w.a, 70_000_000, Recv::Ext, None);
    let ua = w.ua(w.a).address;
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        Some(&ua),
        70_000_000,
        None,
    );
    check(
        "rows",
        w.rows(w.a, &[0xc9]),
        r#"
            c9 sent 129985000 pool=transparent/transparent fee=Known:15000 incl=0 complete=0 prov=0 mined=190 delta=-130000000 t=1
            c9 received 70000000 pool=shielded/orchard fee=Known:15000 incl=0 complete=0 prov=0 mined=190 delta=-130000000 t=0
        "#,
    );
    check(
        "sent",
        vec![w.detail(w.a, 0xc9, "sent")],
        r#"
            sent to=F.t from=- src=- acct=- memo=None complete=0 prov=0 settled=1 delta=-130000000 fee=Some(15000) net=Some(15000) outs=[F.t:129985000:transparent/transparent:0] t=unavailable
        "#,
    );
}

/// Was `history_mixed_pool_payment_to_another_account_stays_sent`.
#[test]
fn golden_mixed_pool_payment_to_another_account_stays_sent() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Transparent, 200_000_000);
    let tx = w.tx(0xca, Some(190), None, Some(15_000));
    w.spend(input, tx);
    let to = w.foreign_t.clone();
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&to),
        129_985_000,
        None,
    );
    let ua = w.ua(w.b).address;
    w.sent(tx, Pool::Orchard, 0, w.a, None, Some(&ua), 70_000_000, None);
    w.recv(tx, Pool::Orchard, 0, w.b, 70_000_000, Recv::Ext, None);
    check(
        "A",
        w.rows(w.a, &[0xca]),
        r#"
            ca sent 199985000 pool=mixed/mixed fee=Known:15000 incl=0 complete=0 prov=0 mined=190 delta=-200000000 t=1
        "#,
    );
    check(
        "B",
        w.rows(w.b, &[0xca]),
        r#"
            ca received 70000000 pool=shielded/orchard fee=NotApplicable:0 incl=0 complete=0 prov=0 mined=190 delta=70000000 t=0
        "#,
    );
}

/// Was `history_exposes_activity_pools_without_changing_legacy_grouping`.
#[test]
fn golden_activity_pools_of_self_sends() {
    let cases: &[&[Pool]] = &[
        &[Pool::Transparent],
        &[Pool::Sapling],
        &[Pool::Orchard],
        &[Pool::Ironwood],
        &[Pool::Sapling, Pool::Orchard],
        &[Pool::Orchard, Pool::Ironwood],
        &[Pool::Transparent, Pool::Sapling],
        &[Pool::Transparent, Pool::Ironwood],
    ];
    let mut lines = vec![];
    for pools in cases {
        let mut w = wallet();
        let amount = pools.len() as u64 * 100_000;
        let input = w.fund(w.a, Pool::Orchard, amount + 10_000);
        let tx = w.tx(0xb0, Some(190), Some(CREATED), Some(10_000));
        w.spend(input, tx);
        for &pool in *pools {
            w.recv(tx, pool, 0, w.a, 100_000, Recv::Ext, None);
            let address = if pool == Pool::Transparent {
                w.ext_t(w.a).address
            } else {
                w.ua(w.a).address
            };
            w.sent(tx, pool, 0, w.a, Some(w.a), Some(&address), 100_000, None);
        }
        lines.push(format!("{pools:?}"));
        lines.extend(w.rows(w.a, &[0xb0]));
    }
    check(
        "pools",
        lines,
        r#"
            [Transparent]
            b0 sent 100000 pool=transparent/transparent fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=1
            b0 received 100000 pool=transparent/transparent fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=1
            [Sapling]
            b0 sent 100000 pool=shielded/sapling fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            b0 received 100000 pool=shielded/sapling fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            [Orchard]
            b0 sent 100000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            b0 received 100000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            [Ironwood]
            b0 migration 100000 pool=ironwood/- fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            [Sapling, Orchard]
            b0 sent 200000 pool=shielded/mixed fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            b0 received 200000 pool=shielded/mixed fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            [Orchard, Ironwood]
            b0 sent 100000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            b0 received 100000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            [Transparent, Sapling]
            b0 sent 200000 pool=mixed/mixed fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=1
            b0 received 200000 pool=mixed/mixed fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=1
            [Transparent, Ironwood]
            b0 sent 100000 pool=transparent/transparent fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=1
            b0 received 100000 pool=transparent/transparent fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=1
        "#,
    );
}

// ======================== Migrations, change and shielding ========================

/// Was `history_classifies_pool_4_internal_transition_as_migration`, and the
/// expired case of `classify_expired_internal_ironwood_transition_as_failed_migration`.
#[test]
fn golden_orchard_to_ironwood_transition_is_a_migration() {
    let mut lines = vec![];
    for expired in [false, true] {
        let mut w = wallet();
        let input = w.fund(w.a, Pool::Orchard, 625_000_000);
        let tx = w.tx(0xb5, None, Some("2026-06-08T22:45:02Z"), Some(20_000));
        w.spend(input, tx);
        w.recv(tx, Pool::Ironwood, 0, w.a, 624_980_000, Recv::Int, None);
        w.sent(
            tx,
            Pool::Ironwood,
            0,
            w.a,
            Some(w.a),
            None,
            624_980_000,
            None,
        );
        if expired {
            w.set(0xb5, &format!("expiry_height = {PASSED_EXPIRY}"));
        }
        lines.extend(w.rows(w.a, &[0xb5]));
    }
    check(
        "rows",
        lines,
        r#"
            b5 migration 624980000 pool=ironwood/- fee=Known:20000 incl=0 complete=1 prov=0 mined=0 delta=-20000 t=0
            b5 migration 624980000 pool=ironwood/- fee=Known:20000 incl=0 complete=1 prov=0 mined=0 expired delta=-20000 t=0
        "#,
    );
}

/// Was `history_hides_change_only_internal_tx`.
#[test]
fn golden_change_only_transaction_is_hidden() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 17_252_102);
    let tx = w.tx(0xc3, Some(190), Some(CREATED), Some(10_000));
    w.spend(input, tx);
    for (index, value) in [(0, 7_242_102), (1, 10_000_000)] {
        w.recv(tx, Pool::Orchard, index, w.a, value, Recv::Int, None);
        w.sent(tx, Pool::Orchard, index, w.a, Some(w.a), None, value, None);
    }
    check("rows", w.rows(w.a, &[0xc3]), r#""#);
}

/// Was `detail_hides_change_only_outputs_and_empty_memos`.
#[test]
fn golden_change_only_receipt_lists_no_outputs_or_empty_memo() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 1_010_000);
    let tx = w.tx(0xd4, Some(190), Some(CREATED), Some(10_000));
    w.spend(input, tx);
    w.recv(
        tx,
        Pool::Orchard,
        0,
        w.a,
        1_000_000,
        Recv::Int,
        Some(EMPTY_MEMO),
    );
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        None,
        1_000_000,
        Some(EMPTY_MEMO),
    );
    check(
        "sent",
        vec![w.detail(w.a, 0xd4, "sent")],
        r#"
            sent to=- from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[] t=-
        "#,
    );
}

/// Was `history_keeps_shielding_tx_as_single_shielded_row` and
/// `detail_shielding_row_has_no_primary_address`.
#[test]
fn golden_shielding_is_one_shielded_row_without_a_recipient() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Transparent, 10_010_000);
    let tx = w.tx(0xc4, Some(190), Some(CREATED), Some(10_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Orchard, 0, w.a, 10_000_000, Recv::Int, None);
    w.sent(tx, Pool::Orchard, 0, w.a, Some(w.a), None, 10_000_000, None);
    check(
        "rows",
        w.rows(w.a, &[0xc4]),
        r#"
            c4 shielded 10000000 pool=shielded/- fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
        "#,
    );
    check(
        "shielded",
        vec![w.detail(w.a, 0xc4, "shielded")],
        r#"
            shielded to=- from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[-:10000000:shielded/orchard:1] t=unavailable
        "#,
    );
}

/// Was `local_history_with_incomplete_effects_stays_provisional_until_scanned`:
/// a local send pays the account's own external address, and scanning has not
/// found that receipt yet.
#[test]
fn golden_local_send_stays_provisional_until_its_receipt_is_scanned() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 200_000);
    let tx = w.tx(0xf1, None, Some(CREATED), Some(10_000));
    w.spend(input, tx);
    let to = w.foreign_ua.clone();
    w.sent(tx, Pool::Orchard, 0, w.a, None, Some(&to), 50_000, None);
    let ua = w.ua(w.a).address;
    w.sent(
        tx,
        Pool::Orchard,
        1,
        w.a,
        Some(w.a),
        Some(&ua),
        140_000,
        None,
    );
    check(
        "unscanned",
        w.rows(w.a, &[0xf1]),
        r#"
            f1 sent 190000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=1 mined=0 delta=-200000 t=0
        "#,
    );
    w.recv(tx, Pool::Orchard, 1, w.a, 140_000, Recv::Ext, None);
    w.set(
        0xf1,
        "mined_height = 199, tx_index = 1, min_observed_height = 199",
    );
    check(
        "scanned",
        w.rows(w.a, &[0xf1]),
        r#"
            f1 sent 50000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=199 delta=-60000 t=0
            f1 received 140000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=199 delta=-60000 t=0
        "#,
    );
}

// ======================== Zero-value memo payments ========================

/// Was `history_shows_zero_value_receipt_and_its_memo`.
#[test]
fn golden_zero_value_receipt_shows_its_memo() {
    let mut lines = vec![];
    for (mined, kind) in [(Some(190), "received"), (None, "receiving")] {
        let w = wallet();
        let tx = w.tx(0xe1, mined, None, None);
        w.recv(
            tx,
            Pool::Orchard,
            0,
            w.a,
            0,
            Recv::Ext,
            Some(b"memo-only payment"),
        );
        lines.extend(w.rows(w.a, &[0xe1]));
        lines.push(w.detail(w.a, 0xe1, kind));
    }
    check(
        "rows and receipts",
        lines,
        r#"
            e1 received 0 pool=shielded/orchard fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=190 delta=0 t=0
            received to=- from=- src=unknown acct=- memo=Some("memo-only payment") complete=1 prov=0 settled=1 delta=0 fee=None net=None outs=[A.ua:0:shielded/orchard:1] t=-
            e1 receiving 0 pool=shielded/orchard fee=Unknown:0 incl=0 complete=0 prov=1 mined=0 delta=0 t=0
            receiving to=- from=- src=unknown acct=- memo=Some("memo-only payment") complete=0 prov=1 settled=0 delta=0 fee=None net=None outs=[A.ua:0:shielded/orchard:1] t=-
        "#,
    );
}

/// Was `history_shows_zero_value_receipt_without_text_memo`.
#[test]
fn golden_zero_value_receipt_without_a_text_memo() {
    let mut lines = vec![];
    for (pool, memo) in [
        (Pool::Orchard, None),
        (Pool::Orchard, Some(&[0xff_u8][..])),
        (Pool::Transparent, None),
    ] {
        let w = wallet();
        let tx = w.tx(0xe2, Some(190), None, None);
        w.recv(tx, pool, 0, w.a, 0, Recv::Ext, memo);
        lines.extend(w.rows(w.a, &[0xe2]));
        lines.push(w.detail(w.a, 0xe2, "received"));
    }
    check(
        "rows and receipts",
        lines,
        r#"
            e2 received 0 pool=shielded/orchard fee=NotApplicable:0 incl=0 complete=0 prov=0 mined=190 delta=0 t=0
            received to=- from=- src=unknown acct=- memo=None complete=0 prov=0 settled=1 delta=0 fee=None net=None outs=[A.ua:0:shielded/orchard:1] t=-
            e2 received 0 pool=shielded/orchard fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=190 delta=0 t=0
            received to=- from=- src=unknown acct=- memo=None complete=1 prov=0 settled=1 delta=0 fee=None net=None outs=[A.ua:0:shielded/orchard:1] t=-
            e2 received 0 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=190 delta=0 t=1
            received to=- from=- src=unknown acct=- memo=None complete=1 prov=0 settled=1 delta=0 fee=None net=None outs=[A.t:0:transparent/transparent:0] t=unavailable
        "#,
    );
}

/// Was `history_shows_zero_value_send_and_its_memo`.
#[test]
fn golden_zero_value_send_shows_its_memo() {
    let mut lines = vec![];
    for with_change in [true, false] {
        let mut w = wallet();
        let input = w.fund(
            w.a,
            Pool::Orchard,
            if with_change { 100_000 } else { 10_000 },
        );
        let tx = w.tx(0xe3, Some(190), Some("2026-09-29T09:00:00Z"), Some(10_000));
        w.spend(input, tx);
        let to = w.foreign_ua.clone();
        w.sent(
            tx,
            Pool::Orchard,
            0,
            w.a,
            None,
            Some(&to),
            0,
            Some(b"memo-only payment"),
        );
        if with_change {
            w.recv(tx, Pool::Orchard, 1, w.a, 90_000, Recv::Int, None);
            w.sent(tx, Pool::Orchard, 1, w.a, Some(w.a), None, 90_000, None);
        }
        lines.extend(w.rows(w.a, &[0xe3]));
        lines.push(w.detail(w.a, 0xe3, "sent"));
    }
    check(
        "rows and receipts",
        lines,
        r#"
            e3 sent 0 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            sent to=F.ua from=- src=- acct=- memo=Some("memo-only payment") complete=1 prov=0 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[F.ua:0:shielded/orchard:1] t=-
            e3 sent 0 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            sent to=F.ua from=- src=- acct=- memo=Some("memo-only payment") complete=1 prov=0 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[F.ua:0:shielded/orchard:1] t=-
        "#,
    );
}

/// Was `history_splits_zero_value_memo_to_self`.
#[test]
fn golden_zero_value_memo_to_self_splits() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 100_000);
    let tx = w.tx(0xe4, Some(190), Some("2026-09-29T09:00:00Z"), Some(10_000));
    w.spend(input, tx);
    w.recv(
        tx,
        Pool::Orchard,
        0,
        w.a,
        0,
        Recv::Ext,
        Some(b"note to self"),
    );
    let ua = w.ua(w.a).address;
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        Some(&ua),
        0,
        Some(b"note to self"),
    );
    w.recv(tx, Pool::Orchard, 1, w.a, 90_000, Recv::Int, None);
    w.sent(tx, Pool::Orchard, 1, w.a, Some(w.a), None, 90_000, None);
    check(
        "rows",
        w.rows(w.a, &[0xe4]),
        r#"
            e4 sent 0 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
            e4 received 0 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-10000 t=0
        "#,
    );
}

/// Was `history_keeps_unenhanced_zero_value_change_unknown`: before
/// enhancement the zero-value change has no sent note, like an external
/// receipt.
#[test]
fn golden_unenhanced_zero_value_change_stays_unknown() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 100_000);
    let tx = w.tx(0xe5, Some(190), None, None);
    w.spend(input, tx);
    w.recv(tx, Pool::Orchard, 0, w.a, 0, Recv::Int, None);
    check(
        "rows",
        w.rows(w.a, &[0xe5]),
        r#"
            e5 sent 100000 pool=unknown/- fee=Unknown:0 incl=0 complete=0 prov=1 mined=190 delta=-100000 t=0
        "#,
    );
}

// ======================== Receipts ========================

/// Was `detail_sent_row_returns_recipient_address_and_memo`.
#[test]
fn golden_sent_receipt_names_recipient_and_memo_in_each_pool() {
    let mut lines = vec![];
    for pool in [Pool::Sapling, Pool::Orchard, Pool::Ironwood] {
        let mut w = wallet();
        let input = w.fund(w.a, Pool::Orchard, 1_010_000);
        let tx = w.tx(0xd1, Some(190), Some("2026-04-28T17:00:00Z"), Some(10_000));
        w.spend(input, tx);
        let to = w.foreign_ua.clone();
        w.sent(
            tx,
            pool,
            0,
            w.a,
            None,
            Some(&to),
            1_000_000,
            Some(b"hello from activity"),
        );
        lines.extend(w.rows(w.a, &[0xd1]));
        lines.push(w.detail(w.a, 0xd1, "sent"));
    }
    check(
        "rows and receipts",
        lines,
        r#"
            d1 sent 1000000 pool=shielded/sapling fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-1010000 t=0
            sent to=F.ua from=- src=- acct=- memo=Some("hello from activity") complete=1 prov=0 settled=1 delta=-1010000 fee=Some(10000) net=Some(10000) outs=[F.ua:1000000:shielded/sapling:0] t=-
            d1 sent 1000000 pool=shielded/orchard fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-1010000 t=0
            sent to=F.ua from=- src=- acct=- memo=Some("hello from activity") complete=1 prov=0 settled=1 delta=-1010000 fee=Some(10000) net=Some(10000) outs=[F.ua:1000000:shielded/orchard:1] t=-
            d1 sent 1000000 pool=ironwood/ironwood fee=Known:10000 incl=0 complete=1 prov=0 mined=190 delta=-1010000 t=0
            sent to=F.ua from=- src=- acct=- memo=Some("hello from activity") complete=1 prov=0 settled=1 delta=-1010000 fee=Some(10000) net=Some(10000) outs=[F.ua:1000000:ironwood/ironwood:1] t=-
        "#,
    );
}

/// Was `detail_sent_to_own_transparent_receiver_uses_sent_note_address`.
#[test]
fn golden_payment_to_own_transparent_receiver_names_it() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 6_980_000);
    let tx = w.tx(0xd8, None, Some("2026-05-15T06:11:44Z"), Some(15_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Transparent, 0, w.a, 1_200_000, Recv::Ext, None);
    let t = w.ext_t(w.a).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&t),
        1_200_000,
        None,
    );
    w.recv(
        tx,
        Pool::Orchard,
        0,
        w.a,
        5_765_000,
        Recv::Int,
        Some(EMPTY_MEMO),
    );
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        None,
        5_765_000,
        Some(EMPTY_MEMO),
    );
    check(
        "rows",
        w.rows(w.a, &[0xd8]),
        r#"
            d8 sent 1200000 pool=transparent/transparent fee=Known:15000 incl=0 complete=1 prov=0 mined=0 delta=-15000 t=1
            d8 receiving 1200000 pool=transparent/transparent fee=Known:15000 incl=0 complete=1 prov=0 mined=0 delta=-15000 t=1
        "#,
    );
    check(
        "sent",
        vec![w.detail(w.a, 0xd8, "sent")],
        r#"
            sent to=A.t from=- src=- acct=- memo=None complete=1 prov=0 settled=0 delta=-15000 fee=Some(15000) net=Some(15000) outs=[A.t:1200000:transparent/transparent:0] t=unavailable
        "#,
    );
}

/// Was `detail_sent_to_transparent_pool_prefers_cached_transparent_receiver`:
/// the payment was addressed to the unified address whose transparent
/// receiver took it.
#[test]
fn golden_transparent_payment_to_a_unified_address_names_its_receiver() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 18_990_000);
    let tx = w.tx(0xd9, Some(190), Some("2026-05-14T13:14:15Z"), Some(15_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Transparent, 0, w.a, 11_000_000, Recv::Ext, None);
    let ua = w.ua(w.a).address;
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&ua),
        11_000_000,
        None,
    );
    w.recv(
        tx,
        Pool::Orchard,
        0,
        w.a,
        7_975_000,
        Recv::Int,
        Some(EMPTY_MEMO),
    );
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        None,
        7_975_000,
        Some(EMPTY_MEMO),
    );
    check(
        "rows",
        w.rows(w.a, &[0xd9]),
        r#"
            d9 sent 11000000 pool=transparent/transparent fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=1
            d9 received 11000000 pool=transparent/transparent fee=Known:15000 incl=0 complete=1 prov=0 mined=190 delta=-15000 t=1
        "#,
    );
    check(
        "sent",
        vec![w.detail(w.a, 0xd9, "sent")],
        r#"
            sent to=A.t from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-15000 fee=Some(15000) net=Some(15000) outs=[A.t:11000000:transparent/transparent:0] t=unavailable
        "#,
    );
}

/// Was `detail_separates_same_account_self_send_by_kind`.
#[test]
fn golden_self_send_receipts_separate_by_kind() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 1_510_000);
    let tx = w.tx(0xd3, Some(190), Some("2026-04-28T17:02:00Z"), Some(10_000));
    w.spend(input, tx);
    w.recv(
        tx,
        Pool::Orchard,
        0,
        w.a,
        1_000_000,
        Recv::Ext,
        Some(b"self memo"),
    );
    let ua = w.ua(w.a).address;
    w.sent(
        tx,
        Pool::Orchard,
        0,
        w.a,
        Some(w.a),
        Some(&ua),
        1_000_000,
        Some(b"self memo"),
    );
    w.recv(tx, Pool::Orchard, 1, w.a, 500_000, Recv::Int, None);
    w.sent(tx, Pool::Orchard, 1, w.a, Some(w.a), None, 500_000, None);
    check(
        "receipts",
        vec![w.detail(w.a, 0xd3, "sent"), w.detail(w.a, 0xd3, "received")],
        r#"
            sent to=A.ua from=- src=- acct=- memo=Some("self memo") complete=1 prov=0 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[A.ua:1000000:shielded/orchard:1] t=-
            received to=- from=- src=unknown acct=A memo=Some("self memo") complete=1 prov=0 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[A.ua:1000000:shielded/orchard:1] t=-
        "#,
    );
}

/// Was `detail_received_row_does_not_invent_from_address` and
/// `detail_receiving_row_uses_received_outputs`.
#[test]
fn golden_receipt_of_a_shielded_receive_names_no_sender() {
    let mut lines = vec![];
    for (mined, kind, memo) in [
        (Some(190), "received", &b"incoming memo"[..]),
        (None, "receiving", &b"pending incoming memo"[..]),
    ] {
        let w = wallet();
        let tx = w.tx(0xd2, mined, None, None);
        w.recv(tx, Pool::Orchard, 0, w.a, 2_000_000, Recv::Ext, Some(memo));
        lines.extend(w.rows(w.a, &[0xd2]));
        lines.push(w.detail(w.a, 0xd2, kind));
    }
    check(
        "rows and receipts",
        lines,
        r#"
            d2 received 2000000 pool=shielded/orchard fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=190 delta=2000000 t=0
            received to=- from=- src=unknown acct=- memo=Some("incoming memo") complete=1 prov=0 settled=1 delta=2000000 fee=None net=None outs=[A.ua:2000000:shielded/orchard:1] t=-
            d2 receiving 2000000 pool=shielded/orchard fee=Unknown:0 incl=0 complete=0 prov=1 mined=0 delta=2000000 t=0
            receiving to=- from=- src=unknown acct=- memo=Some("pending incoming memo") complete=0 prov=1 settled=0 delta=2000000 fee=None net=None outs=[A.ua:2000000:shielded/orchard:1] t=-
        "#,
    );
}

/// Was `detail_received_transparent_output_surfaces_bare_t_address`.
#[test]
fn golden_transparent_receive_lists_the_bare_transparent_address() {
    let w = wallet();
    let tx = w.tx(0xd3, Some(190), None, None);
    w.recv(tx, Pool::Transparent, 0, w.a, 2_000_000, Recv::Ext, None);
    check(
        "received",
        vec![w.detail(w.a, 0xd3, "received")],
        r#"
            received to=- from=- src=unknown acct=- memo=None complete=1 prov=0 settled=1 delta=2000000 fee=None net=None outs=[A.t:2000000:transparent/transparent:0] t=unavailable
        "#,
    );
}

/// Was `detail_received_row_names_the_recorded_sending_account` and
/// `detail_received_row_needs_one_recorded_sender_for_every_output`: A
/// receives a transparent output from B and, in the second and third cases, an
/// Orchard output with no recorded sender or from C.
#[test]
fn golden_receive_names_one_recorded_sending_account() {
    let mut lines = vec![];
    for second in [None, Some(None), Some(Some(()))] {
        let mut w = wallet();
        let from_b = w.fund(w.b, Pool::Orchard, 1_010_000);
        let tx = w.tx(0xd3, Some(190), None, Some(10_000));
        w.spend(from_b, tx);
        let t = w.ext_t(w.a).address;
        w.sent(
            tx,
            Pool::Transparent,
            0,
            w.b,
            None,
            Some(&t),
            1_000_000,
            None,
        );
        w.recv(tx, Pool::Transparent, 0, w.a, 1_000_000, Recv::Ext, None);
        if let Some(from_c) = second {
            w.recv(tx, Pool::Orchard, 0, w.a, 1_000_000, Recv::Ext, None);
            if from_c.is_some() {
                let input = w.fund(w.c, Pool::Orchard, 1_000_000);
                w.spend(input, tx);
                let ua = w.ua(w.a).address;
                w.sent(tx, Pool::Orchard, 0, w.c, None, Some(&ua), 1_000_000, None);
            }
        }
        lines.extend(w.rows(w.a, &[0xd3]));
        lines.push(w.detail(w.a, 0xd3, "received"));
    }
    check(
        "rows and receipts",
        lines,
        r#"
            d3 received 1000000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=190 delta=1000000 t=1
            received to=- from=- src=unknown acct=B memo=None complete=1 prov=0 settled=1 delta=1000000 fee=None net=None outs=[A.t:1000000:transparent/transparent:0] t=unavailable
            d3 received 2000000 pool=mixed/mixed fee=NotApplicable:0 incl=0 complete=0 prov=0 mined=190 delta=2000000 t=1
            received to=- from=- src=unknown acct=- memo=None complete=0 prov=0 settled=1 delta=2000000 fee=None net=None outs=[A.t:1000000:transparent/transparent:0,A.ua:1000000:shielded/orchard:1] t=unavailable
            d3 received 2000000 pool=mixed/mixed fee=NotApplicable:0 incl=0 complete=0 prov=0 mined=190 delta=2000000 t=1
            received to=- from=- src=unknown acct=- memo=None complete=0 prov=0 settled=1 delta=2000000 fee=None net=None outs=[A.t:1000000:transparent/transparent:0,A.ua:1000000:shielded/orchard:1] t=unavailable
        "#,
    );
}

/// Was `detail_received_row_recovers_transparent_source_from_raw_tx`. The
/// stored transaction pays one of its outputs to a transparent script A
/// imported, and its input names the sender.
#[test]
fn golden_receive_names_the_sender_of_the_raw_transaction() {
    let mut w = wallet();
    let raw = hex::decode(
        "0400008085202f8901aee37187e843da597683c26c01457f5fd3b1a038996ef74dc8d60d483aaf395a000000006b483045022100874c70db77ea9e93f75cc83a9e141e17c8eb97588e29fe4e307631fdde4f162a02203493df62d648cd86a1189eaf9bcafc652bc14c5df02519d9e45e25b32aaffb5b012102106a2dcaaac2ae3b24358a03f4264e05db420c5b090399bc23885fa02fef7716ffffffff02764e1900000000001976a914fb451987556f7a19b726966ee6cff917e0bb3bfb88ac560ca400000000001976a9141634f5ff0b8f6603a17570436d6c12a91f4b1fed88ac00000000000000000000000000000000000000",
    )
    .unwrap();
    let parsed = Transaction::read(&raw[..], BranchId::Sapling).unwrap();
    let raw_txid: [u8; 32] = *parsed.txid().as_ref();
    let sender = {
        let pubkey =
            hex::decode("02106a2dcaaac2ae3b24358a03f4264e05db420c5b090399bc23885fa02fef7716")
                .unwrap();
        let address = TransparentAddress::PublicKeyHash(transparent::util::hash160::hash(&pubkey));
        zcash_keys::encoding::encode_transparent_address_p(&NETWORK, &address)
    };
    w.names.add(sender, "sender");
    let receiver_script =
        hex::decode("76a914fb451987556f7a19b726966ee6cff917e0bb3bfb88ac").unwrap();
    let receiver = zcash_keys::encoding::encode_transparent_address_p(
        &NETWORK,
        &TransparentAddress::PublicKeyHash(receiver_script[3..23].try_into().unwrap()),
    );
    w.names.add(receiver.clone(), "A.imported");
    let account_id = w.id(w.a);
    w.conn
        .execute(
            "INSERT INTO addresses (account_id, key_scope, address,
                 cached_transparent_receiver_address, receiver_flags,
                 imported_transparent_receiver_script)
             VALUES (?1, -1, ?2, ?2, 1, ?3)",
            params![account_id, receiver, receiver_script],
        )
        .unwrap();
    let address_id = w.conn.last_insert_rowid();
    w.conn
        .execute(
            "INSERT INTO transactions (txid, mined_height, tx_index, raw, min_observed_height)
             VALUES (?1, 190, 1, ?2, 190)",
            params![raw_txid, raw],
        )
        .unwrap();
    let tx = w.conn.last_insert_rowid();
    w.conn
        .execute(
            "INSERT INTO transparent_received_outputs (transaction_id, output_index,
                 account_id, address, script, value_zat, address_id)
             VALUES (?1, 0, ?2, ?3, ?4, 1658486, ?5)",
            params![tx, account_id, receiver, receiver_script, address_id],
        )
        .unwrap();
    let rows = w.history(w.a, None);
    let row = rows
        .iter()
        .find(|row| row.txid_hex == hex::encode(raw_txid))
        .expect("the receive has a row");
    let detail = get_transaction_detail(
        &w.path,
        NETWORK,
        &w.a.expose_uuid().to_string(),
        &hex::encode(raw_txid),
        "received",
    )
    .unwrap();
    check(
        "row and receipt",
        vec![row_line(row), detail_line(&detail, &w.names)],
        r#"
             1d received 1658486 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=190 delta=1658486 t=1
            received to=- from=sender src=transparent acct=- memo=None complete=1 prov=0 settled=1 delta=1658486 fee=None net=None outs=[A.imported:1658486:transparent/transparent:0] t=rows[0:A.imported:1658486:1,1:sender:10751062:0]/2 omit[]
        "#,
    );
}

// ======================== Order and limits ========================

/// Was `history_sorts_by_display_timestamp_before_limit`.
#[test]
fn golden_rows_sort_by_display_time_before_the_limit() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 10_010_000);
    let older_failed = w.tx(0xc1, None, Some("2026-04-28T13:04:00Z"), Some(10_000));
    w.set(0xc1, &format!("expiry_height = {PASSED_EXPIRY}"));
    w.spend(input, older_failed);
    let to = w.foreign_t.clone();
    w.sent(
        older_failed,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&to),
        10_000_000,
        None,
    );
    let input = w.fund(w.a, Pool::Transparent, 17_040_000);
    let newer = w.tx(0xc2, Some(199), Some("2026-04-28T16:32:00Z"), Some(40_000));
    w.spend(input, newer);
    w.recv(
        newer,
        Pool::Transparent,
        0,
        w.a,
        17_000_000,
        Recv::Ext,
        None,
    );
    let t = w.ext_t(w.a).address;
    w.sent(
        newer,
        Pool::Transparent,
        0,
        w.a,
        Some(w.a),
        Some(&t),
        17_000_000,
        None,
    );
    check(
        "all",
        w.all_rows(w.a, None),
        r#"
            c2 sent 17000000 pool=transparent/transparent fee=Known:40000 incl=0 complete=1 prov=0 mined=199 delta=-40000 t=1
            c2 received 17000000 pool=transparent/transparent fee=Known:40000 incl=0 complete=1 prov=0 mined=199 delta=-40000 t=1
            c1 sent 10000000 pool=transparent/transparent fee=Known:10000 incl=0 complete=1 prov=0 mined=0 expired delta=-10010000 t=1
            02 received 17040000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=102 delta=17040000 t=1
            01 received 10010000 pool=shielded/orchard fee=NotApplicable:0 incl=0 complete=0 prov=0 mined=101 delta=10010000 t=0
        "#,
    );
    check(
        "limited",
        w.all_rows(w.a, Some(1)),
        r#"
            c2 sent 17000000 pool=transparent/transparent fee=Known:40000 incl=0 complete=1 prov=0 mined=199 delta=-40000 t=1
        "#,
    );
}

/// Was `history_prioritizes_unmined_receiving_rows`.
#[test]
fn golden_unmined_receive_comes_first() {
    let w = wallet();
    let confirmed = w.tx(0xe1, Some(199), Some("2026-04-28T16:32:00Z"), None);
    w.recv(confirmed, Pool::Orchard, 0, w.a, 1_000_000, Recv::Ext, None);
    let pending = w.tx(0xe2, None, None, None);
    w.recv(pending, Pool::Orchard, 0, w.a, 2_000_000, Recv::Ext, None);
    check(
        "limited",
        w.all_rows(w.a, Some(1)),
        r#"
            e2 receiving 2000000 pool=shielded/orchard fee=Unknown:0 incl=0 complete=0 prov=1 mined=0 delta=2000000 t=0
        "#,
    );
}

/// Was `history_prioritizes_active_unmined_sent_rows`.
#[test]
fn golden_unmined_send_comes_first() {
    let mut w = wallet();
    let confirmed = w.tx(0xe3, Some(199), Some("2026-04-28T16:32:00Z"), None);
    w.recv(confirmed, Pool::Orchard, 0, w.a, 1_000_000, Recv::Ext, None);
    let input = w.fund(w.a, Pool::Orchard, 1_010_000);
    let pending = w.tx(0xe4, None, None, Some(10_000));
    w.spend(input, pending);
    let to = w.foreign_ua.clone();
    w.sent(
        pending,
        Pool::Orchard,
        0,
        w.a,
        None,
        Some(&to),
        1_000_000,
        None,
    );
    check(
        "limited",
        w.all_rows(w.a, Some(1)),
        r#"
            e4 sent 1000000 pool=shielded/orchard fee=Known:10000 incl=0 complete=0 prov=1 mined=0 delta=-1010000 t=0
        "#,
    );
}

/// Was `history_accepts_unmined_tx_with_null_tx_index`.
#[test]
fn golden_unmined_send_without_a_block_position() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 10_010_000);
    let tx = w.tx(0xd1, None, Some("2026-04-28T13:04:00Z"), Some(10_000));
    w.spend(input, tx);
    let to = w.foreign_t.clone();
    w.sent(
        tx,
        Pool::Transparent,
        0,
        w.a,
        None,
        Some(&to),
        10_000_000,
        None,
    );
    check(
        "rows",
        w.rows(w.a, &[0xd1]),
        r#"
            d1 sent 10000000 pool=transparent/transparent fee=Known:10000 incl=0 complete=1 prov=0 mined=0 delta=-10010000 t=1
        "#,
    );
}

/// Was `history_shows_unmined_sent_when_output_metadata_missing`: only the
/// change of an unmined send is known.
#[test]
fn golden_unmined_send_without_output_metadata() {
    let mut w = wallet();
    let input = w.fund(w.a, Pool::Orchard, 10_010_000);
    let tx = w.tx(0xd2, None, Some("2026-04-28T13:04:00Z"), Some(10_000));
    w.spend(input, tx);
    w.recv(tx, Pool::Orchard, 0, w.a, 9_000_000, Recv::Int, None);
    check(
        "rows",
        w.rows(w.a, &[0xd2]),
        r#"
            d2 sent 1000000 pool=unknown/- fee=Known:10000 incl=0 complete=0 prov=1 mined=0 delta=-1010000 t=0
        "#,
    );
}

// ======================== Private recovery ========================
//
// Transparent transactions the account knows only from qualified private
// recovery: the library publishes the account's receives and spends with
// whole-transaction metadata, and the private display service's facts are
// validated and stored as loop 4 stores them. The wallet never holds the
// transaction itself.

/// An output of a privately recovered transaction.
#[derive(Clone, Copy)]
enum To {
    /// Another wallet's address.
    Foreign(u8),
    /// The account's internal (change) address.
    Change,
    /// The account's external address.
    Own,
}

struct Private {
    tag: u8,
    /// The account's earlier receipt of this value, spent as input 0.
    funding: Option<u64>,
    /// Inputs of other wallets, which recovery never sees.
    foreign_inputs: u32,
    outputs: Vec<(To, u64)>,
    fee: Option<u64>,
    shielded: bool,
    sender: Option<u8>,
    coinbase: bool,
    shielded_and_transparent_funding: bool,
    /// The account's Orchard note of this value, spent by the transaction.
    shielded_spend: Option<u64>,
}

impl Private {
    fn send(tag: u8, funding: u64, outputs: Vec<(To, u64)>, fee: u64) -> Self {
        Private {
            tag,
            funding: Some(funding),
            foreign_inputs: 0,
            outputs,
            fee: Some(fee),
            shielded: false,
            sender: None,
            coinbase: false,
            shielded_and_transparent_funding: false,
            shielded_spend: None,
        }
    }

    fn receive(tag: u8, outputs: Vec<(To, u64)>) -> Self {
        Private {
            tag,
            funding: None,
            foreign_inputs: 1,
            outputs,
            fee: Some(10_000),
            shielded: false,
            sender: Some(0x44),
            coinbase: false,
            shielded_and_transparent_funding: false,
            shielded_spend: None,
        }
    }
}

struct Recovered {
    st: State,
    account: AccountUuid,
    names: Names,
}

fn foreign(byte: u8) -> TransparentAddress {
    TransparentAddress::PublicKeyHash([byte; 20])
}

fn encode(address: &TransparentAddress) -> String {
    zcash_keys::encoding::encode_transparent_address_p(&NETWORK, address)
}

fn last_derived_entry(
    st: &State,
    account: AccountUuid,
    scope: TransparentKeyScope,
) -> (u32, TransparentAddress) {
    watch(st, account)
        .addresses
        .into_iter()
        .filter_map(|watched| match watched.origin {
            WatchOrigin::Derived { scope: s, index } if s == scope => {
                Some((index.index(), watched.address))
            }
            _ => None,
        })
        .max_by_key(|(index, _)| *index)
        .unwrap()
}

fn last_derived(
    st: &State,
    account: AccountUuid,
    scope: TransparentKeyScope,
) -> TransparentAddress {
    last_derived_entry(st, account, scope).1
}

fn last_derived_index(st: &State, account: AccountUuid, scope: TransparentKeyScope) -> u32 {
    last_derived_entry(st, account, scope).0
}

fn event(
    tag: u8,
    index: u32,
    address: TransparentAddress,
    value: u64,
    mined_height: BlockHeight,
    metadata: Option<TransactionMetadata>,
    coinbase: bool,
) -> ReceiveEvent {
    ReceiveEvent {
        metadata,
        outpoint: OutPoint::new(txid(tag), index),
        address,
        value: Zatoshis::const_from_u64(value),
        coinbase,
        mined_height,
    }
}

/// Builds `spec` by private recovery alone.
fn recover(spec: &Private) -> Recovered {
    configure_regtest_nu6_3_activation_height(NU6_3).unwrap();
    let mut st = TestBuilder::new()
        .with_network(regtest())
        .with_data_store_factory(TestDbFactory::default())
        .with_block_cache(BlockCache::new())
        .with_account_from_sapling_activation(BlockHash([0; 32]))
        .build();
    scan_unrelated_blocks(&mut st, 10);
    set_policy(&mut st, TransparentLedgerMode::PrivateRequired);
    let account = st.test_account().unwrap().id();
    let ws = watch(&st, account);
    let target = ws.target.unwrap().height;
    let funder = external(&ws);
    let change = last_derived(&st, account, TransparentKeyScope::INTERNAL);
    let mut names = Names::default();
    names.add(encode(&funder), "own");
    names.add(encode(&change), "change");
    for (to, _) in &spec.outputs {
        if let To::Foreign(byte) = to {
            names.add(encode(&foreign(*byte)), &format!("F{byte:02x}"));
        }
    }
    if let Some(byte) = spec.sender {
        names.add(encode(&foreign(byte)), &format!("F{byte:02x}"));
    }
    let address = |to: To| match to {
        To::Foreign(byte) => foreign(byte),
        To::Change => change,
        To::Own => funder,
    };
    let inputs = u32::from(spec.funding.is_some()) + spec.foreign_inputs;
    let metadata = Some(TransactionMetadata {
        fee: match spec.fee {
            _ if spec.coinbase => WholeTransactionFee::NotApplicable,
            Some(fee) => WholeTransactionFee::Exact(Zatoshis::const_from_u64(fee)),
            None => WholeTransactionFee::Unknown,
        },
        transparent_input_count: inputs,
        has_shielded_components: spec.shielded,
    });
    let mut receives = vec![];
    if let Some(funding) = spec.funding {
        receives.push(event(
            spec.tag - 1,
            0,
            funder,
            funding,
            target - 6,
            Some(TransactionMetadata {
                fee: WholeTransactionFee::Exact(Zatoshis::const_from_u64(1_000)),
                transparent_input_count: 1,
                has_shielded_components: false,
            }),
            false,
        ));
    }
    for (index, (to, value)) in (0u32..).zip(&spec.outputs) {
        if !matches!(to, To::Foreign(_)) {
            receives.push(event(
                spec.tag,
                index,
                address(*to),
                *value,
                target - 4,
                metadata,
                spec.coinbase,
            ));
        }
    }
    cover(&mut st, account, receives);
    st.wallet_mut()
        .db_mut()
        .qualify_transparent_revision(&revision())
        .unwrap();
    set_policy(&mut st, TransparentLedgerMode::PrivateRequired);
    st.wallet_mut()
        .db_mut()
        .activate_transparent_ledger(account)
        .unwrap();
    if spec.funding.is_some() {
        let mut spend = commit(&watch(&st, account));
        spend.spends = vec![SpendEvent {
            metadata,
            spending_txid: TxId::from_bytes(txid(spec.tag)),
            input_index: 0,
            prevout: OutPoint::new(txid(spec.tag - 1), 0),
            prevout_address: funder,
            mined_height: target - 4,
        }];
        st.wallet_mut()
            .db_mut()
            .apply_transparent_ledger_commit(spend)
            .unwrap();
    }
    if let Some(value) = spec.shielded_spend {
        let conn = st.wallet().conn();
        let account_id: i64 = conn
            .query_row(
                "SELECT id FROM accounts WHERE uuid = ?1",
                [account.expose_uuid().as_bytes()],
                |r| r.get(0),
            )
            .unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index)
             VALUES (?1, ?2, ?2, 0)",
            params![txid(spec.tag - 2), u32::from(target - 6)],
        )
        .unwrap();
        let funding = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO orchard_received_notes (transaction_id, action_index, account_id,
                 diversifier, value, rho, rseed, is_change, note_version)
             VALUES (?1, 0, ?2, zeroblob(11), ?3, zeroblob(32), zeroblob(32), 0, 2)",
            params![funding, account_id, value],
        )
        .unwrap();
        let note = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO orchard_received_note_spends (orchard_received_note_id, transaction_id)
             SELECT ?1, id_tx FROM transactions WHERE txid = ?2",
            params![note, txid(spec.tag)],
        )
        .unwrap();
    }

    let conn = st.wallet().conn();
    conn.execute(
        "INSERT OR IGNORE INTO transparent_detail_work (transaction_id, reasons)
         SELECT id_tx, 1 FROM transactions WHERE txid = ?1",
        [txid(spec.tag)],
    )
    .unwrap();
    let facts = TransparentDisplayFacts {
        txid: TxId::from_bytes(txid(spec.tag)),
        coinbase: spec.coinbase,
        fee: Zatoshis::const_from_u64(if spec.coinbase {
            0
        } else {
            spec.fee.unwrap_or(10_000)
        }),
        input_count: inputs,
        output_count: u32::try_from(spec.outputs.len()).unwrap(),
        shielded_components: spec.shielded,
        sender: if spec.funding.is_some() {
            TransparentDisplaySender::Address(funder)
        } else if let Some(byte) = spec.sender {
            TransparentDisplaySender::Address(foreign(byte))
        } else {
            TransparentDisplaySender::Absent
        },
        outputs: spec
            .outputs
            .iter()
            .take(2)
            .map(|(to, value)| TransparentDisplayOutput {
                value: Zatoshis::const_from_u64(*value),
                address: Some(address(*to)),
            })
            .collect(),
        multiple_source_scripts: inputs > 1,
        shielded_and_transparent_funding: spec.shielded_and_transparent_funding,
        provenance: TransparentDisplayProvenance {
            shard_id: 3,
            revision: 0,
            map_sha256: [0xaa; 32],
            looked_up_height: target - 4,
        },
    };
    let generation = st
        .wallet()
        .db()
        .applied_transparent_policy()
        .unwrap()
        .generation;
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .store_transparent_display(facts, generation, std::time::SystemTime::now())
            .unwrap(),
        TransparentDisplayStore::Stored,
        "tag {:02x}",
        spec.tag
    );
    Recovered { st, account, names }
}

impl Recovered {
    /// A copy of the wallet for Vizor's reads.
    fn copy(&self) -> (tempfile::TempDir, String) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        self.st
            .wallet()
            .conn()
            .execute("VACUUM INTO ?1", [&path])
            .unwrap();
        (dir, path)
    }

    /// The Activity rows of `tag`, then its receipt as each kind in `kinds`.
    fn shown(&self, tag: u8, kinds: &[&str]) -> Vec<String> {
        let (_dir, path) = self.copy();
        let account = self.account.expose_uuid().to_string();
        let history = get_transaction_history(&path, NETWORK, None, &account).unwrap();
        assert_rows_read_alone_match(&path, &account, &history);
        let mut lines: Vec<String> = history
            .iter()
            .filter(|row| row.txid_hex == hex::encode(txid(tag)))
            .map(row_line)
            .collect();
        for kind in kinds {
            let detail =
                get_transaction_detail(&path, NETWORK, &account, &hex::encode(txid(tag)), kind)
                    .unwrap();
            lines.push(detail_line(&detail, &self.names));
        }
        lines
    }

    /// Withdraws the account's settled coverage, as a later recovery run
    /// that grows the address window and stops before covering it does.
    ///
    /// While the account was restoring, its recovery already checked a fixed
    /// window of addresses (every external index below 50), so growing the
    /// window into those addresses withdraws nothing: the wallet has already
    /// looked there. Activity at the last address grows the window by one gap
    /// at a time, so it is repeated, each run covering what the last one
    /// added, until the window reaches addresses the restore never checked.
    fn unsettle(&mut self) {
        const RESTORE_EXTERNAL_END: u32 = 50;
        for output in 0.. {
            let ws = watch(&self.st, self.account);
            let target = ws.target.unwrap().height;
            let mut grow = commit(&ws);
            grow.receives = vec![event(
                0x0f,
                output,
                last_derived(&self.st, self.account, TransparentKeyScope::EXTERNAL),
                30_000,
                target - 2,
                Some(TransactionMetadata {
                    fee: WholeTransactionFee::Exact(Zatoshis::const_from_u64(10_000)),
                    transparent_input_count: 1,
                    has_shielded_components: false,
                }),
                false,
            )];
            assert!(
                self.st
                    .wallet_mut()
                    .db_mut()
                    .apply_transparent_ledger_commit(grow)
                    .unwrap()
                    .window_grew
            );
            if last_derived_index(&self.st, self.account, TransparentKeyScope::EXTERNAL)
                >= RESTORE_EXTERNAL_END
            {
                break;
            }
        }
    }
}

/// Was `display_recipient_names_the_only_payee_of_a_private_send`.
#[test]
fn golden_private_send_names_only_its_only_payee() {
    let cases = [
        // A payment, and one with transparent change.
        Private::send(0x12, 60_000, vec![(To::Foreign(0x33), 50_000)], 10_000),
        Private::send(
            0x14,
            67_000,
            vec![(To::Foreign(0x33), 50_000), (To::Change, 7_000)],
            10_000,
        ),
        // Everything but the fee back to the account.
        Private::send(0x16, 1_000_000, vec![(To::Change, 990_000)], 10_000),
        // Value the listed outputs do not account for went to an unseen
        // shielded payee.
        Private {
            shielded: true,
            ..Private::send(0x18, 60_000, vec![(To::Change, 7_000)], 10_000)
        },
        // Two payees.
        Private::send(
            0x1a,
            60_000,
            vec![(To::Foreign(0x33), 25_000), (To::Foreign(0x34), 25_000)],
            10_000,
        ),
        // More outputs than the two the facts list.
        Private::send(
            0x1c,
            60_000,
            vec![
                (To::Foreign(0x33), 30_000),
                (To::Foreign(0x34), 10_000),
                (To::Foreign(0x35), 10_000),
            ],
            10_000,
        ),
        // A whole fee the recovery could not establish.
        Private {
            fee: None,
            ..Private::send(0x1e, 60_000, vec![(To::Foreign(0x33), 50_000)], 10_000)
        },
    ];
    let mut lines = vec![];
    for spec in &cases {
        let mut recovered = recover(spec);
        lines.push(format!("settled {:02x}", spec.tag));
        lines.extend(recovered.shown(spec.tag, &["sent"]));
        recovered.unsettle();
        lines.push(format!("unsettled {:02x}", spec.tag));
        lines.extend(recovered.shown(spec.tag, &["sent"]));
    }
    check(
        "sends",
        lines,
        r#"
            settled 12
            12 sent 50000 pool=transparent/- fee=Known:10000 incl=0 complete=0 prov=0 mined=6 delta=-60000 t=1
            sent to=F33 from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:50000:0]/1 omit[]
            unsettled 12
            12 sent 60000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-60000 t=0
            sent to=F33 from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:50000:0]/1 omit[]
            settled 14
            14 sent 50000 pool=transparent/- fee=Known:10000 incl=0 complete=0 prov=0 mined=6 delta=-60000 t=1
            sent to=F33 from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:50000:0,1:change:7000:1]/2 omit[]
            unsettled 14
            14 sent 60000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-60000 t=0
            sent to=F33 from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:50000:0,1:change:7000:1]/2 omit[]
            settled 16
            16 sent 10000 pool=transparent/- fee=Known:10000 incl=1 complete=0 prov=0 mined=6 delta=-10000 t=1
            sent to=change from=- src=- acct=- memo=None complete=1 prov=0 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:change:990000:1]/1 omit[]
            unsettled 16
            16 sent 10000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-10000 t=0
            sent to=change from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-10000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:change:990000:1]/1 omit[]
            settled 18
            18 sent 53000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-53000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-53000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:change:7000:1]/1 omit[]
            unsettled 18
            18 sent 53000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-53000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-53000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:change:7000:1]/1 omit[]
            settled 1a
            1a sent 50000 pool=transparent/- fee=Known:10000 incl=0 complete=0 prov=0 mined=6 delta=-60000 t=1
            sent to=- from=- src=- acct=- memo=None complete=0 prov=0 settled=1 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:25000:0,1:F34:25000:0]/2 omit[]
            unsettled 1a
            1a sent 60000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-60000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:25000:0,1:F34:25000:0]/2 omit[]
            settled 1c
            1c sent 50000 pool=transparent/- fee=Known:10000 incl=0 complete=0 prov=0 mined=6 delta=-60000 t=1
            sent to=- from=- src=- acct=- memo=None complete=0 prov=0 settled=1 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:30000:0,1:F34:10000:0]/3 omit["more_than_two_outputs"]
            unsettled 1c
            1c sent 60000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-60000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-60000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:30000:0,1:F34:10000:0]/3 omit["more_than_two_outputs"]
            settled 1e
            1e sent 60000 pool=unknown/- fee=Unknown:0 incl=0 complete=0 prov=1 mined=6 delta=-60000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-60000 fee=None net=None outs=[] t=rows[0:F33:50000:0]/1 omit[]
            unsettled 1e
            1e sent 60000 pool=unknown/- fee=Unknown:0 incl=0 complete=0 prov=1 mined=6 delta=-60000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-60000 fee=None net=None outs=[] t=rows[0:F33:50000:0]/1 omit[]
        "#,
    );
}

/// Was `display_details_complete_a_receive_they_account_for`.
#[test]
fn golden_private_receive_completes_when_its_details_account_for_it() {
    let cases = [
        // From another wallet's address, the account paying nothing.
        Private::receive(
            0x22,
            vec![(To::Own, 1_000_000), (To::Foreign(0x55), 300_000)],
        ),
        // An owned output past the two the facts list.
        Private::receive(
            0x24,
            vec![
                (To::Own, 1_000_000),
                (To::Foreign(0x55), 300_000),
                (To::Change, 500_000),
            ],
        ),
        // The receive leg of an unshielding to the account's own address.
        Private {
            foreign_inputs: 0,
            shielded: true,
            sender: None,
            fee: Some(15_000),
            shielded_spend: Some(1_015_000),
            ..Private::receive(0x26, vec![(To::Own, 1_000_000)])
        },
    ];
    let mut lines = vec![];
    for spec in &cases {
        let mut recovered = recover(spec);
        lines.push(format!("settled {:02x}", spec.tag));
        lines.extend(recovered.shown(spec.tag, &["received"]));
        recovered.unsettle();
        lines.push(format!("unsettled {:02x}", spec.tag));
        lines.extend(recovered.shown(spec.tag, &["received"]));
    }
    check(
        "receives",
        lines,
        r#"
            settled 22
            22 received 1000000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=6 delta=1000000 t=1
            received to=- from=F44 src=transparent acct=- memo=None complete=1 prov=0 settled=1 delta=1000000 fee=None net=None outs=[own:1000000:transparent/transparent:0] t=rows[0:own:1000000:1,1:F55:300000:0]/2 omit[]
            unsettled 22
            22 received 1000000 pool=transparent/transparent fee=Unknown:0 incl=0 complete=0 prov=1 mined=6 delta=1000000 t=1
            received to=- from=F44 src=transparent acct=- memo=None complete=0 prov=1 settled=0 delta=1000000 fee=None net=None outs=[own:1000000:transparent/transparent:0] t=rows[0:own:1000000:1,1:F55:300000:0]/2 omit[]
            settled 24
            24 received 1500000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=6 delta=1500000 t=1
            received to=- from=F44 src=transparent acct=- memo=None complete=1 prov=0 settled=1 delta=1500000 fee=None net=None outs=[own:1000000:transparent/transparent:0,change:500000:transparent/transparent:0] t=rows[0:own:1000000:1,1:F55:300000:0]/3 omit["more_than_two_outputs"]
            unsettled 24
            24 received 1500000 pool=transparent/transparent fee=Unknown:0 incl=0 complete=0 prov=1 mined=6 delta=1500000 t=1
            received to=- from=F44 src=transparent acct=- memo=None complete=0 prov=1 settled=0 delta=1500000 fee=None net=None outs=[own:1000000:transparent/transparent:0,change:500000:transparent/transparent:0] t=rows[0:own:1000000:1,1:F55:300000:0]/3 omit["more_than_two_outputs"]
            settled 26
            26 sent 15000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-15000 t=0
            received to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-15000 fee=Some(15000) net=Some(15000) outs=[] t=rows[0:own:1000000:1]/1 omit[]
            unsettled 26
            26 sent 15000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-15000 t=0
            received to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=0 delta=-15000 fee=Some(15000) net=Some(15000) outs=[] t=rows[0:own:1000000:1]/1 omit[]
        "#,
    );
}

/// Was `display_facts_show_a_shielded_source_only_when_conclusive` and
/// `display_source_pool_only_fills_an_unknown_receive_source`: the receipt's
/// source for each kind of funding the facts describe.
#[test]
fn golden_private_receive_source() {
    let cases = [
        // Funded only from the shielded pools.
        Private {
            foreign_inputs: 0,
            shielded: true,
            sender: None,
            ..Private::receive(0x32, vec![(To::Own, 1_000_000)])
        },
        // A coinbase output.
        Private {
            foreign_inputs: 0,
            sender: None,
            coinbase: true,
            ..Private::receive(0x34, vec![(To::Own, 1_000_000)])
        },
        // A transparent input, with a shielded component too.
        Private {
            shielded: true,
            ..Private::receive(0x36, vec![(To::Own, 1_000_000)])
        },
        // A transparent input only.
        Private::receive(0x38, vec![(To::Own, 1_000_000)]),
    ];
    let mut lines = vec![];
    for spec in &cases {
        lines.push(format!("{:02x}", spec.tag));
        lines.extend(recover(spec).shown(spec.tag, &["received"]));
    }
    check(
        "sources",
        lines,
        r#"
            32
            32 received 1000000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=6 delta=1000000 t=1
            received to=- from=- src=shielded acct=- memo=None complete=1 prov=0 settled=1 delta=1000000 fee=None net=None outs=[own:1000000:transparent/transparent:0] t=rows[0:own:1000000:1]/1 omit[]
            34
            34 received 1000000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=6 delta=1000000 t=1
            received to=- from=- src=unknown acct=- memo=None complete=1 prov=0 settled=1 delta=1000000 fee=None net=None outs=[own:1000000:transparent/transparent:0] t=rows[0:own:1000000:1]/1 omit[]
            36
            36 received 1000000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=6 delta=1000000 t=1
            received to=- from=F44 src=transparent acct=- memo=None complete=1 prov=0 settled=1 delta=1000000 fee=None net=None outs=[own:1000000:transparent/transparent:0] t=rows[0:own:1000000:1]/1 omit[]
            38
            38 received 1000000 pool=transparent/transparent fee=NotApplicable:0 incl=0 complete=1 prov=0 mined=6 delta=1000000 t=1
            received to=- from=F44 src=transparent acct=- memo=None complete=1 prov=0 settled=1 delta=1000000 fee=None net=None outs=[own:1000000:transparent/transparent:0] t=rows[0:own:1000000:1]/1 omit[]
        "#,
    );
}

/// Was `shared_or_mixed_funding_keeps_receipt_attribution_incomplete` and
/// `receipt_carries_network_fee_without_promoting_account_attribution`.
#[test]
fn golden_shared_or_mixed_funding_keeps_receipts_incomplete() {
    let cases = [
        // Another wallet funds a second input.
        Private {
            foreign_inputs: 1,
            ..Private::send(0x42, 110_000, vec![(To::Foreign(0x33), 150_000)], 10_000)
        },
        // The account's change returns to its own external address.
        Private {
            foreign_inputs: 1,
            ..Private::send(
                0x44,
                110_000,
                vec![(To::Own, 100_000), (To::Foreign(0x33), 50_000)],
                10_000,
            )
        },
        // The shielded pools fund part of it too.
        Private {
            shielded: true,
            shielded_and_transparent_funding: true,
            ..Private::send(
                0x46,
                110_000,
                vec![(To::Own, 100_000), (To::Foreign(0x33), 50_000)],
                10_000,
            )
        },
    ];
    let mut lines = vec![];
    for spec in &cases {
        lines.push(format!("{:02x}", spec.tag));
        let recovered = recover(spec);
        lines.extend(recovered.shown(spec.tag, &["sent", "received"]));
    }
    check(
        "shared",
        lines,
        r#"
            42
            42 sent 110000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-110000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-110000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:150000:0]/1 omit["shared_funding"]
            received to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-110000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:F33:150000:0]/1 omit["shared_funding"]
            44
            44 sent 10000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-10000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:own:100000:1,1:F33:50000:0]/2 omit["shared_funding"]
            received to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:own:100000:1,1:F33:50000:0]/2 omit["shared_funding"]
            46
            46 sent 10000 pool=unknown/- fee=Unknown:0 incl=1 complete=0 prov=1 mined=6 delta=-10000 t=0
            sent to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:own:100000:1,1:F33:50000:0]/2 omit["shielded_and_transparent_funding"]
            received to=- from=- src=- acct=- memo=None complete=0 prov=1 settled=1 delta=-10000 fee=Some(10000) net=Some(10000) outs=[] t=rows[0:own:100000:1,1:F33:50000:0]/2 omit["shielded_and_transparent_funding"]
        "#,
    );
}

#[test]
fn golden_activity_pages_reuse_and_invalidate_local_snapshots() {
    let w = wallet();
    recent_receipts(&w);
    let expected =
        get_transaction_history(&w.path, NETWORK, None, &w.a.expose_uuid().to_string()).unwrap();
    // Cache eviction by concurrent tests is a legitimate stale response. Retry
    // from a fresh index, exactly as a client does after invalidation.
    let mut verified = false;
    for _ in 0..100 {
        let index = history_pages::index(&w.path, NETWORK, w.a).unwrap();
        let mut actual = Vec::new();
        let mut stale = false;
        for batch in index.summaries.chunks(20) {
            let ids: Vec<_> = batch.iter().map(|s| s.txid_hex.clone()).collect();
            let page =
                history_pages::rows(&w.path, NETWORK, w.a, &index.snapshot_id, &ids).unwrap();
            if page.stale {
                stale = true;
                break;
            }
            actual.extend(page.transactions);
        }
        if stale {
            continue;
        }
        assert_eq!(actual, expected);
        // A writer using another connection invalidates this index. No old
        // details may be returned under its token after the commit.
        w.conn
            .execute(
                "UPDATE transactions SET fee = 12345 WHERE txid = ?1",
                [txid(0x60).as_slice()],
            )
            .unwrap();
        let page = history_pages::rows(
            &w.path,
            NETWORK,
            w.a,
            &index.snapshot_id,
            &[hex::encode(txid(0x60))],
        )
        .unwrap();
        assert!(page.stale);
        verified = true;
        break;
    }
    assert!(
        verified,
        "snapshot repeatedly evicted by concurrent fixtures"
    );
    let index = history_pages::index(&w.path, NETWORK, w.a).unwrap();
    assert!(history_pages::rows(
        &w.path,
        NETWORK,
        w.a,
        &index.snapshot_id,
        &vec![hex::encode(txid(0x60)); 21]
    )
    .is_err());
    history_pages::evict_db(&w.path);
    // A reset can remove the physical database immediately after eviction,
    // including on platforms that reject deletion of open SQLite files.
    drop(w.conn);
    std::fs::remove_file(&w.path).unwrap();
}

#[test]
fn golden_activity_page_continues_across_unrelated_sync_writes() {
    let w = wallet();
    recent_receipts(&w);
    let mut verified = false;
    for attempt in 0..100 {
        let index = history_pages::index(&w.path, NETWORK, w.a).unwrap();
        let mut evicted = false;
        for n in 0..5 {
            w.conn
                .execute(
                    "UPDATE accounts SET name = ?1 WHERE uuid = ?2",
                    params![
                        format!("renamed-{attempt}-{n}"),
                        w.a.expose_uuid().as_bytes()
                    ],
                )
                .unwrap();
            let page = history_pages::rows(
                &w.path,
                NETWORK,
                w.a,
                &index.snapshot_id,
                &[hex::encode(txid(0x60))],
            )
            .unwrap();
            if page.stale {
                evicted = true;
                break;
            }
            assert_eq!(page.transactions.len(), 1);
        }
        // Another fixture can evict the bounded LRU. An implementation that
        // rejects every commit never completes even one of these attempts.
        if evicted {
            continue;
        }
        assert!(
            history_pages::rows(&w.path, NETWORK, w.a, &index.snapshot_id, &[])
                .unwrap()
                .stale,
            "a continued page cannot certify an older Dart detail buffer"
        );
        let refreshed = history_pages::index(&w.path, NETWORK, w.a).unwrap();
        assert_ne!(
            refreshed.snapshot_id, index.snapshot_id,
            "explicit refresh must replace cached Dart detail facts too"
        );
        w.conn
            .execute(
                "UPDATE accounts SET name = 'again' WHERE uuid = ?1",
                [w.a.expose_uuid().as_bytes()],
            )
            .unwrap();
        assert!(
            history_pages::rows(&w.path, NETWORK, w.a, &refreshed.snapshot_id, &[])
                .unwrap()
                .stale
        );
        verified = true;
        break;
    }
    assert!(
        verified,
        "unrelated commits repeatedly invalidated the page"
    );
}

#[test]
fn golden_activity_page_rereads_detail_only_enrichment() {
    let w = wallet();
    let tx = w.tx(0xe2, Some(190), None, None);
    w.recv(tx, Pool::Orchard, 0, w.a, 0, Recv::Ext, None);
    let mut verified = false;
    for _ in 0..100 {
        w.conn
            .execute(
                "UPDATE orchard_received_notes SET memo = NULL WHERE transaction_id = ?1",
                [tx],
            )
            .unwrap();
        let index = history_pages::index(&w.path, NETWORK, w.a).unwrap();
        let ids = [hex::encode(txid(0xe2))];
        let before = history_pages::rows(&w.path, NETWORK, w.a, &index.snapshot_id, &ids).unwrap();
        if before.stale {
            continue;
        }
        assert!(!before.transactions[0].details_complete);
        w.conn
            .execute(
                "UPDATE orchard_received_notes SET memo = ?1 WHERE transaction_id = ?2",
                params![padded_memo(b"enriched memo"), tx],
            )
            .unwrap();
        let after = history_pages::rows(&w.path, NETWORK, w.a, &index.snapshot_id, &ids).unwrap();
        if after.stale {
            continue;
        }
        assert!(
            after.transactions[0].details_complete,
            "same summary must not retain the pre-enrichment detail cache"
        );
        assert_ne!(
            history_pages::index(&w.path, NETWORK, w.a)
                .unwrap()
                .snapshot_id,
            index.snapshot_id
        );
        verified = true;
        break;
    }
    assert!(verified, "detail enrichment never produced a coherent page");
}
