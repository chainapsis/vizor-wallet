//! Private lookups already answered at the current chain tip.
//!
//! A reply that does not decode, or a record the wallet rejects, leaves its
//! work durable, while an honest reply would have completed it. If that
//! leftover counted towards a recovery-only sync restart, a service could
//! tell a forged reply from an honest one by the wallet asking again 30
//! seconds later at the same block. So Enhance work that failed on content is
//! left out of the restart count, and out of every further query, until the
//! chain tip moves: it waits for the next block, which every wallet syncs for
//! anyway.
//! An accepted reorg also starts a fresh allowance, after its database rewind
//! succeeds. A lagging endpoint or a failed rewind leaves this record intact.
//!
//! Private status is stricter, because an honest reply can leave work too:
//! "not found" for an unmined transaction keeps it, "mined" completes it. So
//! every private status txid that got any reply at this tip, honest or not,
//! is left out of the restart count and is not asked again until the next
//! block. No status txid is asked twice at one tip, whatever the reply.
//!
//! Work a reply creates at this tip waits for the next block too. A status
//! reply that makes a transaction mined, or an Enhance record that names more
//! work, adds queries, rediscovery jobs or status lookups that an honest reply
//! of another kind would not have added. Asking them now, or counting them
//! towards a restart, would show the service what its reply said. So every
//! drain point compares the private work before and after it runs, records
//! what appeared as unlocked at this tip, and that work is neither asked nor
//! counted until the next block.
//!
//! Request failures (a refusal, an overload, a transport error) are not
//! recorded and may still bring a restart; the service already knows it
//! refused.
//!
//! The record lives in memory, per wallet. An app restart forgets it, and the
//! first sync after a restart runs at whatever tip it finds, which is public.

use std::collections::{BTreeSet, HashMap};
use std::sync::{LazyLock, Mutex, MutexGuard, PoisonError};

use zcash_client_backend::data_api::enhance_pir::{
    EnhancePirRequest, EnhancePirWork, IronwoodEnhanceDiscoveryRequest, TransactionEnhancementWork,
};
use zcash_client_backend::data_api::status::TransactionStatusWork;
use zcash_primitives::transaction::TxId;

/// The private work that exists at one moment: Enhance queries, rediscovery
/// jobs and status lookups.
#[derive(Clone, Debug, Default)]
pub(crate) struct PrivateWork {
    queries: BTreeSet<EnhancePirRequest>,
    rediscovery: Vec<IronwoodEnhanceDiscoveryRequest>,
    statuses: BTreeSet<TxId>,
}

impl PrivateWork {
    pub(crate) fn new(
        enhancement: impl IntoIterator<Item = TransactionEnhancementWork>,
        status: impl IntoIterator<Item = TransactionStatusWork>,
    ) -> Self {
        let mut work = Self::default();
        for item in enhancement {
            match item {
                TransactionEnhancementWork::Private(EnhancePirWork::Query(request)) => {
                    work.queries.insert(request);
                }
                TransactionEnhancementWork::Private(EnhancePirWork::Rediscover(request)) => {
                    if !work.rediscovery.contains(&request) {
                        work.rediscovery.push(request);
                    }
                }
                _ => {}
            }
        }
        work.statuses = status
            .into_iter()
            .filter(|work| matches!(work, TransactionStatusWork::Private(_)))
            .map(|work| work.txid())
            .collect();
        work
    }

    /// Whether `work` is part of this snapshot; suspended work is never asked.
    pub(crate) fn contains(&self, work: &EnhancePirWork) -> bool {
        match work {
            EnhancePirWork::Query(request) => self.queries.contains(request),
            EnhancePirWork::Rediscover(request) => self.rediscovery.contains(request),
            EnhancePirWork::Suspended(_) => true,
        }
    }

    /// Adds to `self` the work in `after` that is not in `before`.
    fn add_new(&mut self, before: &Self, after: &Self) {
        self.queries
            .extend(after.queries.difference(&before.queries).copied());
        for request in &after.rediscovery {
            if !before.rediscovery.contains(request) && !self.rediscovery.contains(request) {
                self.rediscovery.push(*request);
            }
        }
        self.statuses
            .extend(after.statuses.difference(&before.statuses).copied());
    }
}

#[derive(Default)]
struct AtTip {
    tip: u64,
    /// Enhance requests whose reply failed on content.
    failed: BTreeSet<EnhancePirRequest>,
    /// Private status txids that got a reply.
    answered: BTreeSet<TxId>,
    /// Work that replies created.
    unlocked: PrivateWork,
}

static AT_TIP: LazyLock<Mutex<HashMap<String, AtTip>>> = LazyLock::new(Default::default);

fn at_tips() -> MutexGuard<'static, HashMap<String, AtTip>> {
    AT_TIP.lock().unwrap_or_else(PoisonError::into_inner)
}

/// The wallet at `db_path` has reached chain tip `tip`: what was recorded
/// below it is forgotten, so that work is counted, and asked, again.
pub(crate) fn at_tip(db_path: &str, tip: u64) {
    let mut at_tips = at_tips();
    let entry = at_tips.entry(db_path.to_owned()).or_default();
    if tip > entry.tip {
        *entry = AtTip {
            tip,
            ..AtTip::default()
        };
    }
}

/// Starts an allowance at the replacement chain's tip after a successful
/// reorg rewind, even when its height is no greater than the old tip.
/// This changes scheduling only; the wallet's content-failure limits remain.
pub(in crate::wallet::sync_engine) fn after_reorg(db_path: &str, tip: u64) {
    at_tips().insert(
        db_path.to_owned(),
        AtTip {
            tip,
            ..AtTip::default()
        },
    );
}

/// Records Enhance requests whose reply failed on content.
pub(crate) fn enhance(db_path: &str, requests: impl IntoIterator<Item = EnhancePirRequest>) {
    at_tips()
        .entry(db_path.to_owned())
        .or_default()
        .failed
        .extend(requests);
}

/// Records a transaction whose private status lookup got a reply, of any
/// content, at the current tip.
pub(crate) fn status_answered(db_path: &str, txid: TxId) {
    at_tips()
        .entry(db_path.to_owned())
        .or_default()
        .answered
        .insert(txid);
}

/// Records the work in `after` that was not in `before` as created by the
/// replies of the drain point between them.
pub(crate) fn unlocked(db_path: &str, before: &PrivateWork, after: &PrivateWork) {
    at_tips()
        .entry(db_path.to_owned())
        .or_default()
        .unlocked
        .add_new(before, after);
}

/// Whether private Enhance `work` may be asked, or counted towards a restart,
/// at the current tip: it neither failed on content nor was created by a
/// reply here.
pub(crate) fn may_ask(db_path: &str, work: &EnhancePirWork) -> bool {
    let at_tips = at_tips();
    let Some(at_tip) = at_tips.get(db_path) else {
        return true;
    };
    match work {
        EnhancePirWork::Query(request) => {
            !at_tip.failed.contains(request) && !at_tip.unlocked.contains(work)
        }
        EnhancePirWork::Rediscover(_) => !at_tip.unlocked.contains(work),
        EnhancePirWork::Suspended(_) => true,
    }
}

/// Whether the transaction's private status lookup may be asked, or counted
/// towards a restart, at the current tip: it got no reply here and no reply
/// here created it.
pub(crate) fn may_ask_status(db_path: &str, txid: &TxId) -> bool {
    at_tips().get(db_path).is_none_or(|at_tip| {
        !at_tip.answered.contains(txid) && !at_tip.unlocked.statuses.contains(txid)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::data_api::enhance_pir::IronwoodEnhanceRequestId;
    use zcash_client_backend::data_api::status::PrivateTransactionStatusRequest;

    /// Reply-created queries still wait for the next block without a timer.
    #[test]
    fn a_query_a_reply_created_waits_for_the_next_block() {
        let path = "query-created-by-a-reply";
        let request = EnhancePirRequest::new(
            42.into(),
            IronwoodEnhanceRequestId::new(TxId::from_bytes([0x43; 32]), 0),
        );
        let query = EnhancePirWork::Query(request);
        let after = PrivateWork::new([TransactionEnhancementWork::Private(query)], []);
        at_tip(path, 10);
        unlocked(path, &PrivateWork::default(), &after);
        assert!(!may_ask(path, &query));
        at_tip(path, 10);
        assert!(!may_ask(path, &query));
        at_tip(path, 11);
        assert!(may_ask(path, &query));
    }

    /// A status lookup that a reply created at this tip is neither asked nor
    /// counted until the next block, like an Enhance query.
    #[test]
    fn a_status_lookup_a_reply_created_waits_for_the_next_block() {
        let path = "status-lookup-created-by-a-reply";
        let txid = TxId::from_bytes([0x42; 32]);
        at_tip(path, 10);
        let after = PrivateWork::new(
            [],
            [TransactionStatusWork::Private(
                PrivateTransactionStatusRequest::new(txid, None),
            )],
        );
        unlocked(path, &PrivateWork::default(), &after);
        assert!(!may_ask_status(path, &txid));
        at_tip(path, 11);
        assert!(may_ask_status(path, &txid));
    }
}
