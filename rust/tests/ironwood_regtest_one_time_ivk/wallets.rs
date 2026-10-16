//! The wallets: Vizor's, driven only through its API and sync engine, and a payer
//! standing in for NEAR's treasury, which builds zero-OVK payments with the wallet library.

use std::{convert::Infallible, rc::Rc};

use rust_lib_zcash_wallet::{
    api::{
        one_time_ivk::{self as swap_api, ReceiveDeposit, SwapProviderStatus},
        sync as sync_api, wallet as wallet_api,
    },
    wallet::{
        keys::{mnemonic_bytes_to_seed, parse_account_uuid},
        network::WalletNetwork,
    },
};
use secrecy::ExposeSecret as _;
use tempfile::TempDir;
// The store's RNG, as Vizor opens it (see `wallet::db`).
use voting_crypto_deps::rand::rngs::OsRng;
#[allow(deprecated)]
use zcash_client_backend::zip321::{Payment, TransactionRequest};
use zcash_client_backend::{
    data_api::{
        transparent_ledger::TransparentLedgerMode,
        wallet::{
            create_proposed_transactions,
            input_selection::{GreedyInputSelector, SpendPolicy},
            propose_transfer, ConfirmationsPolicy, SpendingKeys,
        },
        WalletCommitmentTrees, WalletRead as _,
    },
    fees::{standard::SingleOutputChangeStrategy, DustOutputPolicy, StandardFeeRule},
    wallet::OvkPolicy,
};
use zcash_client_sqlite::{util::SystemClock, WalletDb};
use zcash_keys::{
    address::{Address, UnifiedAddress},
    keys::UnifiedSpendingKey,
};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::{value::Zatoshis, ShieldedPool};

use super::{
    chain::{Stack, NETWORK},
    near::{Near, Role},
};

/// One software account of a Vizor wallet.
pub struct Wallet {
    pub name: String,
    /// The wallet's directory, shared by every account of its database.
    _dir: Rc<TempDir>,
    pub db: String,
    pub account: String,
    pub address: String,
    pub mnemonic: String,
}

/// An incoming swap whose deposit instructions the app showed.
pub struct IncomingSwap {
    pub address: String,
    pub receiver: [u8; 43],
    pub deposit: String,
    pub memo: Option<String>,
}

/// A ZEC-to-X swap quoted with a refund address.
pub struct RefundSwap {
    pub index: u64,
    pub address: String,
    pub deposit: String,
}

impl Wallet {
    /// Imports `mnemonic` into a new Vizor wallet whose birthday is `birthday`.
    pub fn import(name: &str, mnemonic: &str, birthday: u32) -> Self {
        let dir = tempfile::tempdir().expect("a wallet directory");
        let db = dir
            .path()
            .join("zcash_wallet.db")
            .to_str()
            .expect("a UTF-8 path")
            .to_owned();
        let imported = wallet_api::import_wallet(
            mnemonic.to_owned(),
            String::new(),
            Some(u64::from(birthday)),
            NETWORK.into(),
            db.clone(),
            Some(name.to_owned()),
            // Restored, as every wallet the scenarios import may hold swap history.
            false,
        )
        .unwrap_or_else(|e| panic!("import {name}: {e}"));
        Self {
            name: name.to_owned(),
            _dir: Rc::new(dir),
            db,
            account: imported.account_uuid,
            address: imported.unified_address,
            mnemonic: mnemonic.to_owned(),
        }
    }

    /// Adds another software account from `mnemonic` to this wallet's database, as the
    /// app's add-account flow does (an imported account with its derivation recorded).
    pub fn add_account(&self, name: &str, mnemonic: &str, birthday: u32) -> Wallet {
        let added = wallet_api::add_account(
            self.db.clone(),
            NETWORK.into(),
            name.to_owned(),
            mnemonic.to_owned(),
            String::new(),
            Some(u64::from(birthday)),
        )
        .unwrap_or_else(|e| panic!("add {name}: {e}"));
        Wallet {
            name: name.to_owned(),
            _dir: Rc::clone(&self._dir),
            db: self.db.clone(),
            account: added.account_uuid,
            address: added.unified_address,
            mnemonic: mnemonic.to_owned(),
        }
    }

    /// A second device holding a copy of this wallet's database as it is now, as a restore
    /// of the app's files from a backup would.
    pub fn copy_device(&self, name: &str) -> Wallet {
        let dir = tempfile::tempdir().expect("a wallet directory");
        let db = dir
            .path()
            .join("zcash_wallet.db")
            .to_str()
            .expect("a UTF-8 path")
            .to_owned();
        self.read_only()
            .execute("VACUUM INTO ?1", [&db])
            .expect("a copy of the wallet database");
        Wallet {
            name: name.to_owned(),
            _dir: Rc::new(dir),
            db,
            account: self.account.clone(),
            address: self.address.clone(),
            mnemonic: self.mnemonic.clone(),
        }
    }

    /// One foreground sync, as the app runs it: scanning, the follow-ups, then the one
    /// restore sweep run the receiver directory gets per sync.
    pub fn sync(&self, stack: &Stack) {
        sync_api::run_full_sync_blocking(
            self.db.clone(),
            stack.lightwalletd_url(),
            NETWORK.into(),
            1,
        )
        .unwrap_or_else(|e| panic!("{} syncs: {e}", self.name));
    }

    /// Syncs until no queued range is waiting to rescan, as later polls would. A sync
    /// that activates one-time keys queues their rescan for the next sync, and until it
    /// runs the wallet treats its newest notes as unspendable.
    pub fn sync_settled(&self, stack: &Stack) {
        for _ in 0..4 {
            self.sync(stack);
            let pending: i64 = self
                .read_only()
                .query_row(
                    "SELECT COUNT(*) FROM scan_queue WHERE priority > 10",
                    [],
                    |r| r.get(0),
                )
                .expect("the scan queue reads");
            if pending == 0 {
                return;
            }
        }
        panic!("{} still has ranges to rescan after four syncs", self.name);
    }

    /// Every zatoshi the wallet holds, spendable or not.
    pub fn total(&self) -> u64 {
        sync_api::get_balance(self.db.clone(), NETWORK.into(), self.account.clone())
            .unwrap_or_else(|e| panic!("{} balance: {e}", self.name))
            .total
    }

    /// Value in one-time-key notes no mined transaction spends, read from the wallet's
    /// database.
    pub fn unspent_one_time_value(&self) -> u64 {
        self.read_only()
            .query_row(
                "SELECT COALESCE(SUM(n.value), 0) FROM ironwood_received_notes n
             WHERE n.one_time_key_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM ironwood_received_note_spends s
                   JOIN transactions t ON t.id_tx = s.transaction_id
                   WHERE s.ironwood_received_note_id = n.id AND t.mined_height IS NOT NULL)",
                [],
                |r| r.get::<_, i64>(0),
            )
            .map(|v| u64::try_from(v).expect("a nonnegative value"))
            .expect("the one-time-key note value")
    }

    /// How many one-time-key notes the wallet's database holds, spent or not.
    pub fn one_time_notes(&self) -> u64 {
        self.read_only()
            .query_row(
                "SELECT COUNT(*) FROM ironwood_received_notes WHERE one_time_key_id IS NOT NULL",
                [],
                |r| r.get::<_, i64>(0),
            )
            .map(|v| u64::try_from(v).expect("a nonnegative count"))
            .expect("the one-time-key note count")
    }

    /// Whether the wallet's early restore accepted its publication, so the restore scan
    /// itself looked for the account's one-time payments.
    pub fn early_restore_accepted(&self) -> bool {
        self.read_only()
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM ironwood_one_time_restores WHERE state = 1)",
                [],
                |r| r.get(0),
            )
            .expect("the early restore state")
    }

    /// The wallet's early restore, if it began one: the publication's last height and its
    /// state, 0 until the scan stores that block, then 1 if it matched or 2 if it did not.
    pub fn early_restore(&self) -> Option<(u32, u8)> {
        use rusqlite::OptionalExtension as _;
        self.read_only()
            .query_row(
                "SELECT anchor_height, state FROM ironwood_one_time_restores",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .expect("the early restore")
    }

    /// Whether the key behind one-time `receiver` stopped scanning.
    pub fn key_closed(&self, receiver: &[u8; 43]) -> bool {
        self.read_only()
            .query_row(
                "SELECT closed_at IS NOT NULL FROM ironwood_one_time_keys WHERE receiver = ?1",
                [&receiver[..]],
                |r| r.get(0),
            )
            .expect("a stored one-time key")
    }

    /// A read-only connection to the wallet's database.
    fn read_only(&self) -> rusqlite::Connection {
        rusqlite::Connection::open_with_flags(&self.db, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .expect("the wallet database")
    }

    /// Sends everything the wallet can spend to `to` with the app's send-max flow, which
    /// spends every note it holds, and returns the amount and the broadcast txid.
    pub fn send_max(&self, stack: &Stack, to: &str) -> (u64, String) {
        let estimate = sync_api::estimate_send_max(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            to.into(),
            None,
        )
        .unwrap_or_else(|e| panic!("{} estimates its maximum send: {e}", self.name));
        let flow = format!("send-max-{}", self.name);
        let proposal = sync_api::propose_send(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            flow.clone(),
            to.into(),
            estimate.amount_zatoshi,
            None,
        )
        .unwrap_or_else(|e| panic!("{} proposes its maximum send: {e}", self.name));
        let result = sync_api::execute_proposal(
            self.db.clone(),
            stack.lightwalletd_url(),
            proposal.proposal_id,
            flow,
            self.mnemonic.as_bytes().to_vec(),
            None,
            None,
        )
        .unwrap_or_else(|e| panic!("{} sends its maximum: {e}", self.name));
        assert_eq!(result.status, "broadcasted", "{:?}", result.message);
        (estimate.amount_zatoshi, txid_in(&result.txids))
    }

    /// Quotes an incoming swap as the app does: reserves an address, records the request,
    /// NEAR accepts it with a deadline `deadline_in` seconds away, and the app shows the
    /// deposit instructions. Fails only if the address cannot be reserved yet.
    pub fn quote_incoming(
        &self,
        stack: &Stack,
        near: &mut Near,
        deadline_in: i64,
    ) -> Result<IncomingSwap, String> {
        self.quote_incoming_to(stack, near, deadline_in, None)
    }

    /// [`Self::quote_incoming`], with NEAR's deposit instructions given as `deposit`
    /// (address and memo) instead of a fresh address without a memo.
    pub fn quote_incoming_to(
        &self,
        stack: &Stack,
        near: &mut Near,
        deadline_in: i64,
        deposit: Option<(&str, &str)>,
    ) -> Result<IncomingSwap, String> {
        let reserved = swap_api::reserve_swap_address(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            true,
            u64::from(stack.tip()),
        )
        .map_err(|e| e.message)?;
        let index = reserved.reservation_index.expect("an incoming reservation");
        let now = stack.now();
        let deadline = now + deadline_in;
        let request = swap_api::begin_receive_quote(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            index,
            deadline,
        )
        .unwrap_or_else(|e| panic!("{} begins a quote: {e}", self.name));
        let receiver = receiver_of(&reserved.address);
        near.give(receiver, now, Role::Payout);
        let deposit = match deposit {
            Some((address, memo)) => ReceiveDeposit {
                address: address.to_owned(),
                memo: Some(memo.to_owned()),
                deadline_seconds: deadline,
            },
            None => ReceiveDeposit {
                address: near.deposit_address(),
                memo: None,
                deadline_seconds: deadline,
            },
        };
        swap_api::finish_receive_quote(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            request.clone(),
            Some(deposit),
        )
        .unwrap_or_else(|e| panic!("{} records the accepted quote: {e}", self.name));
        let shown = swap_api::start_receive_quote(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            request,
        )
        .unwrap_or_else(|e| panic!("{} shows the quote: {e}", self.name));
        Ok(IncomingSwap {
            address: reserved.address,
            receiver,
            deposit: shown.address,
            memo: shown.memo,
        })
    }

    /// Records NEAR's `status` for an incoming swap, as the app's status poll does.
    pub fn observe_incoming(
        &self,
        stack: &Stack,
        swap: &IncomingSwap,
        status: &str,
        amount_out: u64,
    ) {
        swap_api::observe_swap_status(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            true,
            swap.deposit.clone(),
            swap.memo.clone(),
            SwapProviderStatus {
                status: status.into(),
                swap_type: Some("EXACT_INPUT".into()),
                refunded_amount: None,
                amount_out: Some(amount_out.to_string()),
            },
            false,
            stack.now(),
        )
        .unwrap_or_else(|e| panic!("{} records {status}: {e}", self.name));
    }

    /// Quotes a ZEC-to-X swap with a refund address, as the app does: reserves the refund
    /// key, then records NEAR's ZEC deposit address for it. Fails only if the key cannot
    /// be reserved yet.
    pub fn quote_refund(
        &self,
        stack: &Stack,
        near: &mut Near,
        deadline_in: i64,
    ) -> Result<RefundSwap, String> {
        let reserved = swap_api::reserve_swap_address(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            false,
            u64::from(stack.tip()),
        )
        .map_err(|e| e.message)?;
        let index = reserved.refund_index.expect("a refund index");
        let deposit = zec_deposit_address(&receiver_of(&reserved.address));
        swap_api::record_swap_refund_quote(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            index,
            deposit.clone(),
            stack.now() + deadline_in,
        )
        .unwrap_or_else(|e| panic!("{} records the refund quote: {e}", self.name));
        near.give(receiver_of(&reserved.address), stack.now(), Role::Refund);
        Ok(RefundSwap {
            index,
            address: reserved.address,
            deposit,
        })
    }

    /// Funds a ZEC-to-X swap through Vizor's send flow, which puts the refund memo on its
    /// Ironwood change, and broadcasts it. Returns the fee and the txid.
    pub fn fund_swap(&self, stack: &Stack, swap: &RefundSwap, amount: u64) -> (u64, String) {
        let flow = format!("fund-swap-{}", swap.index);
        let proposal = sync_api::propose_swap_funding(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            flow.clone(),
            swap.deposit.clone(),
            amount,
            swap.index,
        )
        .unwrap_or_else(|e| panic!("{} proposes the swap deposit: {e}", self.name));
        let result = sync_api::execute_proposal(
            self.db.clone(),
            stack.lightwalletd_url(),
            proposal.proposal_id,
            flow,
            self.mnemonic.as_bytes().to_vec(),
            None,
            None,
        )
        .unwrap_or_else(|e| panic!("{} sends the swap deposit: {e}", self.name));
        assert_eq!(result.status, "broadcasted", "{:?}", result.message);
        (proposal.fee_zatoshi, txid_in(&result.txids))
    }

    /// Funds a ZEC-to-X swap with everything the wallet holds, so the funding change, which
    /// still carries the refund memo, is worth nothing. Returns the deposit, the fee and the
    /// txid.
    pub fn fund_swap_with_everything(
        &self,
        stack: &Stack,
        swap: &RefundSwap,
    ) -> (u64, u64, String) {
        let total = self.total();
        let fee_for = |amount: u64| {
            sync_api::estimate_swap_funding_fee(
                self.db.clone(),
                NETWORK.into(),
                self.account.clone(),
                swap.deposit.clone(),
                amount,
            )
            .unwrap_or_else(|e| panic!("{} estimates the swap fee: {e}", self.name))
        };
        let fee = fee_for(total / 2);
        let amount = total - fee;
        assert_eq!(
            fee_for(amount),
            fee,
            "the fee does not depend on the deposit"
        );
        let (paid, txid) = self.fund_swap(stack, swap, amount);
        assert_eq!(paid, fee, "the proposal pays the estimated fee");
        (amount, fee, txid)
    }

    /// The indices of every refund key the wallet holds.
    pub fn refund_key_indices(&self) -> Vec<u64> {
        let conn = self.read_only();
        let mut statement = conn
            .prepare("SELECT key_index FROM ironwood_one_time_keys WHERE purpose = 0")
            .expect("the refund key query");
        let indices = statement
            .query_map([], |r| r.get::<_, Vec<u8>>(0))
            .expect("refund keys")
            .map(|index| u64::from_be_bytes(index.expect("an index").try_into().expect("8 bytes")))
            .collect();
        indices
    }

    /// Records NEAR's `status` for a ZEC-to-X swap's refund side.
    pub fn observe_refund(&self, stack: &Stack, swap: &RefundSwap, status: &str, refunded: u64) {
        swap_api::observe_swap_status(
            self.db.clone(),
            NETWORK.into(),
            self.account.clone(),
            false,
            swap.deposit.clone(),
            None,
            SwapProviderStatus {
                status: status.into(),
                swap_type: Some("EXACT_INPUT".into()),
                refunded_amount: Some(refunded.to_string()),
                amount_out: None,
            },
            true,
            stack.now(),
        )
        .unwrap_or_else(|e| panic!("{} records {status}: {e}", self.name));
    }

    /// Queues Check swap history for the next sync.
    pub fn check_swap_history(&self) {
        swap_api::recheck_swap_history(self.db.clone(), NETWORK.into())
            .unwrap_or_else(|e| panic!("{} checks swap history: {e}", self.name));
    }
}

/// The payer standing in for NEAR: a Vizor-synced wallet whose payments the test builds
/// with the wallet library, with the zero OVK for payouts and refunds as NEAR's are.
pub struct Payer {
    pub wallet: Wallet,
    usk: UnifiedSpendingKey,
}

impl Payer {
    /// The payer for `wallet`, with the spending key of its first account.
    pub fn new(wallet: Wallet) -> Self {
        let seed = mnemonic_bytes_to_seed(wallet.mnemonic.as_bytes()).expect("a seed");
        let usk = UnifiedSpendingKey::from_seed(
            &WalletNetwork::Regtest,
            seed.expose_secret(),
            zip32::AccountId::ZERO,
        )
        .expect("a spending key");
        Self { wallet, usk }
    }

    /// `count` of the payer's own addresses, at diversifier indices from 1.
    pub fn own_addresses(&self, count: u32) -> Vec<String> {
        let ufvk = self.usk.to_unified_full_viewing_key();
        let fvk = ufvk.orchard().expect("an Orchard key");
        (1..=count)
            .map(|i| encode(fvk.address_at(i, orchard::keys::Scope::External)))
            .collect()
    }

    /// Builds one transaction paying `outputs` with `ovk`, from shielded notes with one
    /// confirmation, after [`Wallet::sync_settled`]. The wallet stores it as sent; nothing
    /// broadcasts it until the payer's next sync resubmits it.
    pub fn build(&self, stack: &Stack, outputs: &[(&str, u64)], ovk: OvkPolicy) -> Transaction {
        self.wallet.sync_settled(stack);
        self.build_unsynced(outputs, ovk)
    }

    /// [`Self::build`] without the sync, so a transaction built earlier stays unsent.
    pub fn build_unsynced(&self, outputs: &[(&str, u64)], ovk: OvkPolicy) -> Transaction {
        self.build_in(&self.wallet.db, outputs, ovk)
    }

    /// Builds in a copy of the payer's wallet, which never learns of the transaction until
    /// a sync finds it mined, so one not broadcast leaves nothing behind to resubmit.
    pub fn build_detached(
        &self,
        stack: &Stack,
        outputs: &[(&str, u64)],
        ovk: OvkPolicy,
    ) -> Transaction {
        self.wallet.sync_settled(stack);
        let dir = tempfile::tempdir().expect("a directory for the copy");
        let copy = dir.path().join("detached.db");
        rusqlite::Connection::open(&self.wallet.db)
            .expect("the payer's wallet opens")
            .execute("VACUUM INTO ?1", [copy.to_str().expect("a UTF-8 path")])
            .expect("the wallet copies");
        self.build_in(copy.to_str().expect("a UTF-8 path"), outputs, ovk)
    }

    /// Builds one transaction paying `outputs` with `ovk` in the wallet at `db_path`.
    fn build_in(&self, db_path: &str, outputs: &[(&str, u64)], ovk: OvkPolicy) -> Transaction {
        let conn = rusqlite::Connection::open(db_path).expect("the payer's wallet opens");
        // As Vizor configures its connections (see `wallet::db`).
        conn.busy_timeout(std::time::Duration::from_secs(30))
            .expect("a busy timeout");
        rusqlite::vtab::array::load_module(&conn).expect("the rarray module");
        let mut db = WalletDb::from_connection(conn, WalletNetwork::Regtest, SystemClock, OsRng)
            .with_transparent_ledger_mode(TransparentLedgerMode::Public);
        let account = parse_account_uuid(&self.wallet.account).expect("an account UUID");
        #[allow(deprecated)]
        let request = TransactionRequest::new(
            outputs
                .iter()
                .map(|(address, value)| {
                    Payment::without_memo(
                        address.parse().expect("an address"),
                        Zatoshis::from_u64(*value).expect("a value"),
                    )
                })
                .collect(),
        )
        .expect("a payment request");
        type Db = WalletDb<rusqlite::Connection, WalletNetwork, SystemClock, OsRng>;
        let strategy = SingleOutputChangeStrategy::<Db>::new(
            StandardFeeRule::Zip317,
            None,
            ShieldedPool::Ironwood,
            DustOutputPolicy::default(),
        );
        let policy =
            SpendPolicy::shielded_pools(vec![ShieldedPool::Orchard, ShieldedPool::Ironwood]);
        let proposal = propose_transfer::<_, _, _, _, <Db as WalletCommitmentTrees>::Error>(
            &mut db,
            &WalletNetwork::Regtest,
            account,
            &GreedyInputSelector::new(),
            &strategy,
            request,
            ConfirmationsPolicy::MIN,
            &policy,
            None,
            None,
        )
        .unwrap_or_else(|e| panic!("the payer proposes: {e}"));
        let prover = LocalTxProver::bundled();
        let txids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &WalletNetwork::Regtest,
            &prover,
            &prover,
            &SpendingKeys::from_unified_spending_key(self.usk.clone()),
            ovk,
            &proposal,
            None,
        )
        .unwrap_or_else(|e| panic!("the payer builds: {e}"));
        db.get_transaction(*txids.first())
            .expect("the stored transaction reads")
            .expect("the payer stored its transaction")
    }

    /// Builds and broadcasts one transaction paying `outputs` with `ovk`.
    pub fn pay(&self, stack: &Stack, outputs: &[(&str, u64)], ovk: OvkPolicy) -> TxId {
        let tx = self.build(stack, outputs, ovk);
        broadcast(stack, &tx);
        tx.txid()
    }
}

/// The zero OVK NEAR pays with, which lets the receiver directory list its payments.
pub fn zero_ovk() -> OvkPolicy {
    OvkPolicy::custom_from_common_bytes(&[0; 32])
}

/// Broadcasts `tx` through the node.
pub fn broadcast(stack: &Stack, tx: &Transaction) {
    let mut bytes = Vec::new();
    tx.write(&mut bytes).expect("the transaction encodes");
    stack.send_raw(&bytes);
}

/// The raw receiver of a swap address, which carries only an Ironwood receiver.
pub fn receiver_of(address: &str) -> [u8; 43] {
    match Address::decode(&WalletNetwork::Regtest, address).expect("a regtest address") {
        Address::Unified(ua) => ua
            .orchard()
            .expect("an Ironwood receiver")
            .to_raw_address_bytes(),
        other => panic!("not a unified address: {other:?}"),
    }
}

/// `address` as a unified address with no other receiver.
fn encode(address: orchard::Address) -> String {
    Address::Unified(UnifiedAddress::from_receivers(Some(address), None, None).expect("an address"))
        .encode(&WalletNetwork::Regtest)
}

/// The one txid in Vizor's broadcast result.
fn txid_in(txids: &str) -> String {
    txids
        .split(|c: char| !c.is_ascii_hexdigit())
        .find(|part| part.len() == 64)
        .unwrap_or_else(|| panic!("a txid in {txids:?}"))
        .to_owned()
}

/// NEAR's ZEC deposit for a quote whose refund goes to `receiver`: a P2PKH address on
/// regtest, as 1Click deposits are, and a different one for each quote, so two
/// accounts' swaps never share one.
fn zec_deposit_address(receiver: &[u8; 43]) -> String {
    let hash: [u8; 20] = receiver[11..31].try_into().expect("20 bytes");
    Address::Transparent(transparent::address::TransparentAddress::PublicKeyHash(
        hash,
    ))
    .encode(&WalletNetwork::Regtest)
}
