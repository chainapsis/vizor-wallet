//! Private query scheduling follows accepted chain changes, not endpoint lag.

use super::*;
use enhancement::content_failures::{self, PrivateWork};
use zcash_client_backend::data_api::enhance_pir::{
    EnhancePirRequest, EnhancePirWork, IronwoodEnhanceDiscoveryRequest, IronwoodEnhanceRequestId,
    TransactionEnhancementWork,
};
use zcash_client_backend::data_api::status::{
    PrivateTransactionStatusRequest, TransactionStatusWork,
};
use zcash_primitives::transaction::TxId;

struct DeferredWork {
    failed: EnhancePirRequest,
    created: Vec<EnhancePirWork>,
    answered: TxId,
    created_status: TxId,
}

impl DeferredWork {
    fn new() -> Self {
        let answered = TxId::from_bytes([1; 32]);
        Self {
            failed: EnhancePirRequest::new(1u64.into(), IronwoodEnhanceRequestId::new(answered, 0)),
            created: vec![
                EnhancePirWork::Query(EnhancePirRequest::new(
                    2u64.into(),
                    IronwoodEnhanceRequestId::new(answered, 1),
                )),
                EnhancePirWork::Rediscover(IronwoodEnhanceDiscoveryRequest {
                    height: BlockHeight::from_u32(80),
                    block_hash: BlockHash([3; 32]),
                }),
            ],
            answered,
            created_status: TxId::from_bytes([2; 32]),
        }
    }

    fn defer(&self, path: &str, tip: u64) {
        content_failures::at_tip(path, tip);
        content_failures::enhance(path, [self.failed]);
        content_failures::status_answered(path, self.answered);
        let after = PrivateWork::new(
            self.created
                .iter()
                .copied()
                .map(TransactionEnhancementWork::Private),
            [TransactionStatusWork::Private(
                PrivateTransactionStatusRequest::new(self.created_status, None),
            )],
        );
        content_failures::unlocked(path, &PrivateWork::default(), &after);
        transparent_ledger::recovery_ran(path, tip);
        self.assert_eligible(path, tip, false);
    }

    fn assert_eligible(&self, path: &str, tip: u64, expected: bool) {
        assert_eq!(
            transparent_ledger::recovery_due(path, tip),
            expected,
            "transparent recovery"
        );
        assert_eq!(
            content_failures::may_ask(path, &EnhancePirWork::Query(self.failed)),
            expected,
            "failed details"
        );
        for work in &self.created {
            assert_eq!(
                content_failures::may_ask(path, work),
                expected,
                "created details"
            );
        }
        for txid in [self.answered, self.created_status] {
            assert_eq!(
                content_failures::may_ask_status(path, &txid),
                expected,
                "transaction status"
            );
        }
    }
}

#[test]
fn accepted_reorg_reopens_private_work_without_waiting_for_the_old_height() {
    for replacement_tip in [100, 98] {
        let path = format!("accepted-private-recovery-reorg-{replacement_tip}");
        let work = DeferredWork::new();
        work.defer(&path, 100);
        let tip = BlockHeight::from_u32(replacement_tip);
        let requested = confirmed_reorg_rewind_target(tip).unwrap();
        // The same rewind adapter used by confirmed tip reorgs, with a
        // successful database operation. A lower tip here represents an
        // already accepted rewind, not an endpoint's unverified lower tip.
        assert_eq!(
            truncate_wallet_with(&path, requested, tip, Ok).unwrap(),
            requested
        );
        content_failures::at_tip(&path, u64::from(replacement_tip));
        work.assert_eligible(&path, u64::from(replacement_tip), true);

        // Replies on the replacement chain still get only one allowance.
        work.defer(&path, u64::from(replacement_tip));
        content_failures::at_tip(&path, u64::from(replacement_tip));
        work.assert_eligible(&path, u64::from(replacement_tip), false);
        content_failures::at_tip(&path, u64::from(replacement_tip + 1));
        work.assert_eligible(&path, u64::from(replacement_tip + 1), true);
    }
}

#[test]
fn failed_reorg_rewinds_preserve_private_suppression() {
    for safe in [None, Some(99), Some(100)] {
        let path = format!("failed-private-recovery-reorg-{safe:?}");
        let work = DeferredWork::new();
        work.defer(&path, 100);
        let tip = BlockHeight::from_u32(100);
        let result = truncate_wallet_with(&path, BlockHeight::from_u32(98), tip, |height| {
            Err(SqliteClientError::RequestedRewindInvalid {
                requested_height: height,
                safe_rewind_height: safe.map(BlockHeight::from_u32),
            })
        });
        assert!(result.is_err());
        work.assert_eligible(&path, 100, false);
    }
    let path = "invalid-successful-private-recovery-rewind";
    let work = DeferredWork::new();
    work.defer(path, 100);
    let tip = BlockHeight::from_u32(100);
    assert!(truncate_wallet_with(path, BlockHeight::from_u32(99), tip, |_| Ok(tip)).is_err());
    work.assert_eligible(path, 100, false);
}

#[test]
fn safe_reorg_rewind_reopens_only_its_wallets_private_work() {
    let path = "safe-private-recovery-reorg";
    let other = "unaffected-private-recovery-wallet";
    let work = DeferredWork::new();
    work.defer(path, 100);
    work.defer(other, 100);
    let mut calls = 0;
    let actual = truncate_wallet_with(
        path,
        BlockHeight::from_u32(98),
        BlockHeight::from_u32(100),
        |height| {
            calls += 1;
            if calls == 1 {
                // Before the fallback succeeds, nothing is eligible.
                work.assert_eligible(path, 100, false);
                Err(SqliteClientError::RequestedRewindInvalid {
                    requested_height: height,
                    safe_rewind_height: Some(BlockHeight::from_u32(99)),
                })
            } else {
                work.assert_eligible(path, 100, false);
                Ok(height)
            }
        },
    )
    .unwrap();
    assert_eq!(actual, BlockHeight::from_u32(99));
    assert_eq!(calls, 2);
    work.assert_eligible(path, 100, true);
    work.assert_eligible(other, 100, false);
}

#[test]
fn lower_or_unchanged_endpoint_tips_do_not_reopen_private_work() {
    let path = "lagging-private-recovery-endpoint";
    let work = DeferredWork::new();
    work.defer(path, 100);
    let hash = BlockHash([4; 32]);
    assert_eq!(
        classify_refreshed_tip(100, Some(hash), 99, &[5; 32]).unwrap(),
        RefreshedTipRelation::ServerBehind,
    );
    content_failures::at_tip(path, 99);
    work.assert_eligible(path, 99, false);
    assert_eq!(
        classify_refreshed_tip(100, Some(hash), 100, &hash.0).unwrap(),
        RefreshedTipRelation::Unchanged,
    );
    content_failures::at_tip(path, 100);
    work.assert_eligible(path, 100, false);
}

#[test]
fn reorg_scheduling_reset_preserves_the_wallets_content_failure_limit() {
    use zcash_client_backend::data_api::enhance_pir::{
        EnhancePirRead, EnhancePirSuspension, EnhancePirWrite, EnhancementMode,
    };

    let (_dir, path, request) =
        crate::wallet::sync::private_shielding_tests::wallet_with_a_private_memo_query();
    let mut db =
        open_wallet_db_with_timeout(&path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.set_enhancement_mode(EnhancementMode::PrivateIronwood);
    for _ in 0..3 {
        db.record_ironwood_enhance_unreadable(&[request]).unwrap();
    }
    let suspended = TransactionEnhancementWork::Private(EnhancePirWork::Suspended(
        EnhancePirSuspension::Rejected(request),
    ));
    assert!(db
        .transaction_enhancement_work()
        .unwrap()
        .contains(&suspended));
    // Isolate the scheduling effect from the library's separate handling of
    // requests whose positions actually change during a database rewind.
    truncate_wallet_with(
        &path,
        BlockHeight::from_u32(99),
        BlockHeight::from_u32(100),
        Ok,
    )
    .unwrap();
    assert!(db
        .transaction_enhancement_work()
        .unwrap()
        .contains(&suspended));
}
