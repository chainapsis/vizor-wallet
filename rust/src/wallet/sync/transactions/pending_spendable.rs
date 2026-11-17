//! Which of an account's shielded funds are waiting only on confirmations,
//! and for how many more blocks.
//!
//! The wallet summary reports pending value as totals. The app also says
//! *when* that value can be spent, which needs each waiting note's
//! transaction and depth. This reads them in the summary's own snapshot, with
//! the library's confirmation policy, so the app never has to guess them from
//! the transaction list.

use std::collections::BTreeMap;

use zcash_client_backend::data_api::wallet::TargetHeight;
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid, ExtensionTransaction};
use zcash_primitives::transaction::fees::zip317;
use zcash_protocol::{consensus::BlockHeight, PoolType, ShieldedPool};
use zip32::Scope;

use super::{PendingSpendable, WalletBalance};

/// One of `account`'s unspent notes in a pool's `{pool}_received_notes` table
/// that can still be short of confirmations at `target`, one row per call.
///
/// The transaction is mined above `floor`, or unmined and still able to be
/// mined. A note at or below the marginal fee is uneconomic, which the summary
/// counts apart from pending value. The key scope is the note's own: change
/// has no address row to read one from.
fn waiting_note_sql(pool: &str) -> String {
    format!(
        "SELECT t.txid,
                rn.recipient_key_scope,
                rn.value,
                rn.is_change,
                t.mined_height,
                IFNULL(t.trust_status, 0),
                MAX(tt.mined_height),
                MIN(IFNULL(tt.trust_status, 0))
         FROM {pool}_received_notes rn
         JOIN accounts a ON a.id = rn.account_id
         JOIN transactions t ON t.id_tx = rn.transaction_id
         LEFT OUTER JOIN transparent_received_output_spends ros
             ON ros.transaction_id = t.id_tx
         LEFT OUTER JOIN transparent_received_outputs tro
             ON tro.id = ros.transparent_received_output_id
             AND tro.account_id = a.id
         LEFT OUTER JOIN transactions tt
             ON tt.id_tx = tro.transaction_id
         WHERE a.uuid = :account
           AND rn.value > :uneconomic
           AND (t.mined_height > :floor
                OR (t.mined_height IS NULL
                    AND (t.expiry_height = 0 OR t.expiry_height >= :target)))
           AND rn.id NOT IN (
               SELECT {pool}_received_note_id FROM {pool}_received_note_spends)
         GROUP BY rn.id
         ORDER BY rn.id
         LIMIT 1 OFFSET :offset"
    )
}

/// Whether blocks at or below `floor` are still to be scanned.
///
/// A note's shard must be scanned through before the note can be spent, so
/// until then confirmations are not all it waits on. Blocks above `floor` are
/// the ones a sync at the tip is about to scan.
const UNSCANNED_BELOW_SQL: &str = "
    SELECT EXISTS(
        SELECT 1 FROM scan_queue
        WHERE priority > :scanned AND block_range_start <= :floor)";

/// The scan queue's code for a scanned range; every range still to be scanned
/// has a higher one.
const SCANNED_PRIORITY: i64 = 10;

const POOLS: [(&str, ShieldedPool); 3] = [
    ("sapling", ShieldedPool::Sapling),
    ("orchard", ShieldedPool::Orchard),
    ("ironwood", ShieldedPool::Ironwood),
];

/// `account`'s entries, or none if they claim more than `balance` holds
/// pending: the summary decides what is pending, and an entry it does not
/// back is not shown.
pub(super) fn for_balance(
    ext: &ExtensionTransaction<'_>,
    account: AccountUuid,
    target_height: u32,
    balance: &WalletBalance,
) -> Result<Vec<PendingSpendable>, SqliteClientError> {
    let shielded_pending =
        balance.sapling_pending + balance.orchard_pending + balance.ironwood_pending;
    if shielded_pending == 0 {
        return Ok(Vec::new());
    }
    let entries = read(ext, account, target_height)?;
    let total: u64 = entries.iter().map(|entry| entry.value).sum();
    if total > shielded_pending {
        log::warn!(
            "pending spendable entries total {total} zatoshis but the summary holds \
             {shielded_pending} pending; dropping them"
        );
        return Ok(Vec::new());
    }
    Ok(entries)
}

/// One entry per transaction and kind (change or received), ordered by
/// transaction id bytes. None while the wallet still has older blocks to
/// scan.
pub(super) fn read(
    ext: &ExtensionTransaction<'_>,
    account: AccountUuid,
    target_height: u32,
) -> Result<Vec<PendingSpendable>, SqliteClientError> {
    let policy = crate::wallet::confirmations_policy();
    // A note mined at or below this has every confirmation it can need.
    let floor = target_height.saturating_sub(1 + u32::from(policy.untrusted()));
    let unscanned_below: bool = ext.query_row(
        UNSCANNED_BELOW_SQL,
        rusqlite::named_params! { ":scanned": SCANNED_PRIORITY, ":floor": floor },
        |row| row.get(0),
    )?;
    if unscanned_below {
        return Ok(Vec::new());
    }
    let mut entries = BTreeMap::<(Vec<u8>, bool), PendingSpendable>::new();
    for (table, pool) in POOLS {
        let sql = waiting_note_sql(table);
        for offset in 0u32.. {
            let row = ext.query_row(
                &sql,
                rusqlite::named_params! {
                    ":account": account.expose_uuid(),
                    ":uneconomic": u64::from(zip317::MARGINAL_FEE),
                    ":floor": floor,
                    ":target": target_height,
                    ":offset": offset,
                },
                |row| {
                    Ok(WaitingNote {
                        txid: row.get(0)?,
                        pool,
                        scope: row.get(1)?,
                        value: row.get(2)?,
                        is_change: row.get(3)?,
                        mined_height: row.get(4)?,
                        tx_trusted: row.get(5)?,
                        max_shielding_input_height: row.get(6)?,
                        shielding_inputs_trusted: row.get(7)?,
                    })
                },
            );
            let note = match row {
                Ok(note) => note,
                Err(rusqlite::Error::QueryReturnedNoRows) => break,
                Err(error) => return Err(error.into()),
            };
            let blocks = note.blocks_until_spendable(target_height);
            if blocks == 0 {
                continue;
            }
            let confirmations = note
                .mined_height
                .map_or(0, |height| target_height.saturating_sub(height));
            let entry = entries
                .entry((note.txid.clone(), note.is_change))
                .or_insert(PendingSpendable {
                    txid: note.txid,
                    is_change: note.is_change,
                    value: 0,
                    blocks_until_spendable: 0,
                    confirmations,
                });
            entry.value += note.value;
            entry.blocks_until_spendable = entry.blocks_until_spendable.max(blocks);
        }
    }
    Ok(entries.into_values().collect())
}

struct WaitingNote {
    txid: Vec<u8>,
    pool: ShieldedPool,
    scope: Option<i64>,
    value: u64,
    is_change: bool,
    mined_height: Option<u32>,
    tx_trusted: bool,
    max_shielding_input_height: Option<u32>,
    shielding_inputs_trusted: bool,
}

impl WaitingNote {
    /// Blocks after the tip before this note can be spent: the later of the
    /// confirmation policy and the anchor reaching its block.
    fn blocks_until_spendable(&self, target_height: u32) -> u32 {
        let policy = crate::wallet::confirmations_policy();
        let by_policy = policy.confirmations_until_spendable(
            TargetHeight::from(target_height),
            PoolType::Shielded(self.pool),
            match self.scope {
                Some(0) => Some(Scope::External),
                Some(1) => Some(Scope::Internal),
                _ => None,
            },
            self.mined_height.map(BlockHeight::from_u32),
            self.tx_trusted,
            self.max_shielding_input_height.map(BlockHeight::from_u32),
            self.shielding_inputs_trusted,
        );
        by_policy.max(blocks_until_anchored(
            self.mined_height,
            target_height,
            u32::from(policy.trusted()),
        ))
    }
}

/// Blocks before the anchor can reach a note mined at `mined_height`, or in
/// the next block when unmined.
///
/// A spend is anchored `trusted` blocks below the tip, and a note above the
/// anchor has no witness there. That holds change one block longer than
/// the policy's count alone.
fn blocks_until_anchored(mined_height: Option<u32>, target_height: u32, trusted: u32) -> u32 {
    let anchor = target_height.saturating_sub(1 + trusted);
    mined_height.unwrap_or(target_height).saturating_sub(anchor)
}

#[cfg(test)]
mod tests {
    use zcash_client_backend::data_api::{
        testing::{
            orchard::OrchardPoolTester, pool::ShieldedPoolTester, AddressType, IronwoodFvk,
            TestBuilder,
        },
        Account as _, WalletRead as _,
    };
    use zcash_client_sqlite::testing::{db::TestDbFactory, BlockCache};
    use zcash_primitives::block::BlockHash;

    use super::super::private_shielding_tests::{
        regtest, scan_unrelated_blocks, zat, State, NU6_3,
    };
    use super::*;
    use crate::wallet::network::configure_regtest_nu6_3_activation_height;

    const VALUE: u64 = 130_000_000;

    #[test]
    fn the_anchor_holds_change_one_block_past_the_policy() {
        // Tip 100, target 101, anchor 98.
        assert_eq!(blocks_until_anchored(Some(100), 101, 2), 2);
        assert_eq!(blocks_until_anchored(Some(99), 101, 2), 1);
        assert_eq!(blocks_until_anchored(Some(98), 101, 2), 0);
        assert_eq!(blocks_until_anchored(None, 101, 2), 3);
    }

    fn wallet() -> State {
        configure_regtest_nu6_3_activation_height(NU6_3).unwrap();
        let mut st = TestBuilder::new()
            .with_network(regtest())
            .with_data_store_factory(TestDbFactory::default())
            .with_block_cache(BlockCache::new())
            .with_account_from_sapling_activation(BlockHash([0; 32]))
            .build();
        scan_unrelated_blocks(&mut st, 10);
        st
    }

    /// The account's entries and its shielded (spendable, pending) balance,
    /// read in one snapshot as the app's balance read does.
    fn snapshot(st: &mut State) -> (Vec<PendingSpendable>, u64, u64) {
        let account = st.test_account().unwrap().id();
        st.wallet_mut()
            .db_mut()
            .transactionally_with_extension(|db, ext| {
                let summary = db
                    .get_wallet_summary(crate::wallet::confirmations_policy())?
                    .expect("a scanned wallet has a summary");
                let target = u32::from(summary.chain_tip_height()) + 1;
                let balance = &summary.account_balances()[&account];
                let pools = [
                    balance.sapling_balance(),
                    balance.orchard_balance(),
                    balance.ironwood_balance(),
                ];
                let spendable = pools.iter().map(|p| u64::from(p.spendable_value())).sum();
                let pending = pools
                    .iter()
                    .map(|p| {
                        u64::from(p.change_pending_confirmation())
                            + u64::from(p.value_pending_spendability())
                    })
                    .sum();
                Ok::<_, SqliteClientError>((read(ext, account, target)?, spendable, pending))
            })
            .unwrap()
    }

    fn mine_empty(st: &mut State) {
        let (height, _) = st.generate_empty_block();
        st.scan_cached_blocks(height, 1);
    }

    /// Receives `VALUE` at `address_type` and follows it block by block: at
    /// every depth the entries account for all pending value, and the funds
    /// turn spendable exactly when the entry's block count runs out.
    fn follows_the_summary(address_type: AddressType, blocks_at_first_confirmation: u32) {
        let mut st = wallet();
        let fvk = OrchardPoolTester::test_account_fvk(&st);
        let (height, _, _) =
            st.generate_next_block(&IronwoodFvk(fvk.clone()), address_type, zat(VALUE));
        st.scan_cached_blocks(height, 1);

        let mut expected = blocks_at_first_confirmation;
        let mut confirmations = 1;
        loop {
            let (entries, spendable, pending) = snapshot(&mut st);
            let total: u64 = entries.iter().map(|entry| entry.value).sum();
            assert_eq!(
                total, pending,
                "entries explain all pending value at {confirmations} confirmations"
            );
            if expected == 0 {
                assert!(entries.is_empty(), "nothing waits once spendable");
                assert_eq!(spendable, VALUE, "spendable when the count runs out");
                break;
            }
            assert_eq!(spendable, 0, "not spendable while an entry waits");
            assert_eq!(entries.len(), 1);
            assert_eq!(entries[0].value, VALUE);
            assert_eq!(entries[0].blocks_until_spendable, expected);
            assert_eq!(entries[0].confirmations, confirmations);
            mine_empty(&mut st);
            expected -= 1;
            confirmations += 1;
        }
    }

    #[test]
    fn a_receipt_waits_for_its_sixth_confirmation() {
        follows_the_summary(AddressType::DefaultExternal, 5);
    }

    #[test]
    fn internal_funds_wait_for_their_third_confirmation() {
        follows_the_summary(AddressType::Internal, 2);
    }

    /// A wallet holding one receipt of `VALUE` at its first confirmation.
    fn wallet_with_a_new_receipt() -> State {
        let mut st = wallet();
        let fvk = OrchardPoolTester::test_account_fvk(&st);
        let (height, _, _) = st.generate_next_block(
            &IronwoodFvk(fvk.clone()),
            AddressType::DefaultExternal,
            zat(VALUE),
        );
        st.scan_cached_blocks(height, 1);
        st
    }

    #[test]
    fn nothing_is_stated_while_older_blocks_are_unscanned() {
        let mut st = wallet_with_a_new_receipt();
        assert_eq!(snapshot(&mut st).0.len(), 1);

        st.wallet()
            .conn()
            .execute(
                "UPDATE scan_queue SET priority = 20
                 WHERE block_range_start = (SELECT MIN(block_range_start) FROM scan_queue)",
                [],
            )
            .unwrap();

        let (entries, spendable, _) = snapshot(&mut st);
        assert!(entries.is_empty());
        assert_eq!(spendable, 0);
    }

    #[test]
    fn entries_the_summary_does_not_back_are_dropped() {
        let mut st = wallet_with_a_new_receipt();
        let account = st.test_account().unwrap().id();
        let target = u32::from(st.wallet().chain_height().unwrap().unwrap()) + 1;
        let mut backed_by = |pending: u64| {
            let mut balance = WalletBalance::unavailable(
                super::super::WalletBalanceAvailability::SummaryUnavailable,
                false,
            );
            balance.ironwood_pending = pending;
            st.wallet_mut()
                .db_mut()
                .transactionally_with_extension(|_, ext| {
                    for_balance(ext, account, target, &balance)
                })
                .unwrap()
        };

        assert_eq!(backed_by(VALUE).len(), 1);
        assert!(backed_by(VALUE - 1).is_empty());
        assert!(backed_by(0).is_empty());
    }

    #[test]
    fn an_unmined_receipt_waits_until_it_expires() {
        let mut st = wallet_with_a_new_receipt();
        let target = u32::from(st.wallet().chain_height().unwrap().unwrap()) + 1;
        let unmine = |st: &State, expiry: u32| {
            st.wallet()
                .conn()
                .execute(
                    "UPDATE transactions
                     SET mined_height = NULL, block = NULL, expiry_height = ?1",
                    [expiry],
                )
                .unwrap();
        };

        unmine(&st, target);
        let (entries, _, pending) = snapshot(&mut st);
        assert_eq!(pending, VALUE);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].value, VALUE);
        assert_eq!(entries[0].blocks_until_spendable, 6);
        assert_eq!(entries[0].confirmations, 0);

        unmine(&st, target - 1);
        let (entries, _, pending) = snapshot(&mut st);
        assert_eq!(pending, 0);
        assert!(entries.is_empty());
    }

    #[test]
    fn an_uneconomic_receipt_is_not_an_entry() {
        let mut st = wallet();
        let fvk = OrchardPoolTester::test_account_fvk(&st);
        let (height, _, _) = st.generate_next_block(
            &IronwoodFvk(fvk.clone()),
            AddressType::DefaultExternal,
            zat(u64::from(zip317::MARGINAL_FEE)),
        );
        st.scan_cached_blocks(height, 1);

        let (entries, _, pending) = snapshot(&mut st);
        assert!(entries.is_empty());
        assert_eq!(pending, 0);
    }
}
