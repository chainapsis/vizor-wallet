//! A deterministic in-memory [`RecoverySource`] for tests.
//!
//! It answers from a configurable set of mined receives and spends, by default
//! with one `Ready` commit per pass. Its revisions use [`FIXTURE_SOURCE`] as
//! their source id. It is untrusted unless [`FixtureSource::trust`] makes it
//! trusted, as the transparent PIR source is, so the coordinator qualifies its
//! revisions only when a test asks for it. Its settlement follows the
//! adapter's `apply_and_acknowledge`: commits apply in order, each in its own
//! wallet transaction, the first refusal stops the batch unacknowledged, and
//! a batch that resolves retired revisions is refused under observed trust
//! before anything applies.

use std::collections::{BTreeSet, HashMap, VecDeque};
use std::future::Future;
use std::sync::{Arc, Mutex};

use transparent::address::TransparentAddress;
use zakura_pir_transparent::{Outcome, WithdrawnCause};
use zcash_client_backend::data_api::transparent_ledger::{
    AddressRange, ChainPoint, PageRequest, PublicationAnchor, ReceiveEvent, RecoveryRevision,
    SpendEvent, TransparentLedgerCommit,
};
use zcash_client_sqlite::AccountUuid;
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerWrite as _;

use super::{
    refusal, ApplyStats, Continuation, RecoverySource, Refusal, Settlement, SourceBatch,
    SourceError, SourceRequest, Trust,
};
use crate::wallet::db::{with_wallet_db_write_lock, WalletDatabase};

pub(crate) const FIXTURE_SOURCE: &[u8] = b"vizor-fixture";
const PAGE: &[u8] = b"fixture-page";

type Hook = Box<dyn FnOnce() + Send>;

/// The fixture's view of the chain and its behavior knobs.
pub(crate) struct FixtureSource {
    state: Mutex<State>,
}

struct State {
    receives: Vec<ReceiveEvent>,
    spends: Vec<SpendEvent>,
    /// Addresses the source cannot check.
    unsupported: BTreeSet<TransparentAddress>,
    /// Local block hashes, to anchor below the target.
    hash: fn(u32) -> BlockHash,
    /// The highest height the source has indexed; `None` keeps up with the target.
    published: Option<BlockHeight>,
    /// Open one page before answering, then complete it on the next call.
    split_pages: bool,
    page_answered: bool,
    /// Answer with two commits, splitting the watched addresses between them.
    split_commits: bool,
    /// Append a malformed commit to every `Ready` batch.
    then_invalid: bool,
    failure: Option<SourceError>,
    /// Answer `Pending` with this continuation instead of `Ready`.
    pending: Option<Continuation>,
    /// Accounts whose publication the source withdraws, and why.
    withdrawn: HashMap<AccountUuid, WithdrawnCause>,
    /// Replaces the continuation of every `Ready` answer.
    next: Option<Continuation>,
    trusted: bool,
    /// Every `Ready` answer resolves retired revisions until one is
    /// acknowledged as reconciled, as the adapter's do.
    retiring: bool,
    /// Run one per call, before answering: a test's concurrent change.
    hooks: VecDeque<Hook>,
    /// Runs at every acknowledgment, before it is answered.
    on_acknowledge: Option<Arc<dyn Fn() + Send + Sync>>,
    revision: Option<RecoveryRevision>,
    /// The account of each call, in order.
    calls: Vec<AccountUuid>,
    /// Accounts whose last answer was a `Ready` batch not yet settled, with
    /// its commits and whether it resolves retired revisions.
    unacknowledged: HashMap<AccountUuid, (Vec<TransparentLedgerCommit<AccountUuid>>, bool)>,
    acknowledged: usize,
    reconciled: usize,
}

impl FixtureSource {
    pub(crate) fn new(hash: fn(u32) -> BlockHash) -> Self {
        Self {
            state: Mutex::new(State {
                receives: Vec::new(),
                spends: Vec::new(),
                unsupported: BTreeSet::new(),
                hash,
                published: None,
                split_pages: false,
                page_answered: false,
                split_commits: false,
                then_invalid: false,
                failure: None,
                pending: None,
                withdrawn: HashMap::new(),
                next: None,
                trusted: false,
                retiring: false,
                hooks: VecDeque::new(),
                on_acknowledge: None,
                revision: None,
                calls: Vec::new(),
                unacknowledged: HashMap::new(),
                acknowledged: 0,
                reconciled: 0,
            }),
        }
    }

    fn with(&self, update: impl FnOnce(&mut State)) -> &Self {
        update(&mut self.state.lock().unwrap());
        self
    }

    pub(crate) fn receive(&self, receive: ReceiveEvent) -> &Self {
        self.with(|state| state.receives.push(receive))
    }

    pub(crate) fn spend(&self, spend: SpendEvent) -> &Self {
        self.with(|state| state.spends.push(spend))
    }

    /// Replaces a publication's facts under a higher provisional lineage.
    pub(crate) fn replace_events(
        &self,
        receives: Vec<ReceiveEvent>,
        spends: Vec<SpendEvent>,
    ) -> &Self {
        self.with(|state| {
            state.receives = receives;
            state.spends = spends;
            if let Some(revision) = &mut state.revision {
                revision.lineage += 1;
                revision.revision = format!("r{}", revision.lineage).into_bytes();
            }
        })
    }

    pub(crate) fn unsupported(&self, address: TransparentAddress) -> &Self {
        self.with(|state| {
            state.unsupported.insert(address);
        })
    }

    /// Answers as a source that has indexed only through `height`: anchored
    /// there, and asking to be retried as the transparent PIR source does
    /// when its publication is behind.
    pub(crate) fn published_through(&self, height: Option<u32>) -> &Self {
        self.with(|state| state.published = height.map(BlockHeight::from_u32))
    }

    /// Follows a reorg: later answers anchor to blocks hashed by `hash`, under
    /// a new revision.
    pub(crate) fn rehash(&self, hash: fn(u32) -> BlockHash) -> &Self {
        self.with(|state| state.hash = hash)
    }

    pub(crate) fn split_pages(&self) -> &Self {
        self.with(|state| state.split_pages = true)
    }

    /// Answers each pass with two commits, splitting the watched addresses
    /// between them.
    pub(crate) fn split_commits(&self) -> &Self {
        self.with(|state| state.split_commits = true)
    }

    /// Appends, or stops appending, a malformed commit to every `Ready` batch.
    pub(crate) fn then_invalid(&self, invalid: bool) -> &Self {
        self.with(|state| state.then_invalid = invalid)
    }

    pub(crate) fn fail(&self, failure: Option<SourceError>) -> &Self {
        self.with(|state| state.failure = failure)
    }

    /// Answers `Pending` with `next` instead of `Ready`, until cleared.
    pub(crate) fn pending(&self, next: Option<Continuation>) -> &Self {
        self.with(|state| state.pending = next)
    }

    /// Withdraws `account`'s publication for `cause`, until cleared.
    pub(crate) fn withdraw(&self, account: AccountUuid, cause: Option<WithdrawnCause>) -> &Self {
        self.with(|state| match cause {
            Some(cause) => {
                state.withdrawn.insert(account, cause);
            }
            None => {
                state.withdrawn.remove(&account);
            }
        })
    }

    /// Replaces the continuation of every `Ready` answer, until cleared.
    pub(crate) fn next(&self, next: Option<Continuation>) -> &Self {
        self.with(|state| state.next = next)
    }

    /// Makes the source trusted: under `PrivateRequired` the coordinator
    /// qualifies each of its revisions as it applies them.
    pub(crate) fn trust(&self) -> &Self {
        self.with(|state| state.trusted = true)
    }

    /// Answers as a publication that retired revisions an earlier batch
    /// exported: every `Ready` answer resolves them until one is acknowledged
    /// as reconciled.
    pub(crate) fn retire(&self) -> &Self {
        self.with(|state| state.retiring = true)
    }

    /// Runs `hook` at the start of a later call, one hook per call in order.
    pub(crate) fn on_call(&self, hook: impl FnOnce() + Send + 'static) -> &Self {
        self.with(|state| state.hooks.push_back(Box::new(hook)))
    }

    /// Runs `hook` at every acknowledgment, before answering it.
    pub(crate) fn on_acknowledge(&self, hook: impl Fn() + Send + Sync + 'static) -> &Self {
        self.with(|state| state.on_acknowledge = Some(Arc::new(hook)))
    }

    pub(crate) fn calls(&self) -> usize {
        self.state.lock().unwrap().calls.len()
    }

    /// The account of each call, in order.
    pub(crate) fn order(&self) -> Vec<AccountUuid> {
        self.state.lock().unwrap().calls.clone()
    }

    pub(crate) fn calls_for(&self, account: AccountUuid) -> usize {
        self.order().into_iter().filter(|a| *a == account).count()
    }

    /// Acknowledgments of `Ready` batches the source accepted.
    pub(crate) fn acknowledged(&self) -> usize {
        self.state.lock().unwrap().acknowledged
    }

    /// Of those, acknowledgments that confirmed trusted reconciliation.
    pub(crate) fn reconciled(&self) -> usize {
        self.state.lock().unwrap().reconciled
    }

    /// The mined receives and spends a complete recovery through `height`
    /// must hold, ordered as the library reports them.
    pub(crate) fn expected(&self, height: u32) -> (Vec<ReceiveEvent>, Vec<SpendEvent>) {
        let state = self.state.lock().unwrap();
        let height = BlockHeight::from_u32(height);
        let mut receives: Vec<_> = state
            .receives
            .iter()
            .filter(|r| r.mined_height <= height)
            .cloned()
            .collect();
        receives.sort_by_key(|r| (*r.outpoint.hash(), r.outpoint.n()));
        let mut spends: Vec<_> = state
            .spends
            .iter()
            .filter(|s| s.mined_height <= height)
            .cloned()
            .collect();
        spends.sort_by_key(|s| (*s.spending_txid.as_ref(), s.input_index));
        (receives, spends)
    }
}

impl RecoverySource for FixtureSource {
    fn trusted(&self) -> bool {
        self.state.lock().unwrap().trusted
    }

    fn recover(
        &self,
        request: SourceRequest<'_>,
    ) -> impl Future<Output = Result<SourceBatch, SourceError>> + Send {
        let hook = {
            let mut state = self.state.lock().unwrap();
            state.calls.push(request.account);
            state.hooks.pop_front()
        };
        if let Some(hook) = hook {
            hook();
        }
        std::future::ready(self.state.lock().unwrap().answer(&request))
    }

    fn apply(
        &self,
        account: AccountUuid,
        db: &mut WalletDatabase,
        trust: Trust,
    ) -> impl Future<Output = Settlement> + Send {
        let parked = self.state.lock().unwrap().unacknowledged.remove(&account);
        let mut stats = ApplyStats::default();
        let Some((commits, retired)) = parked else {
            return std::future::ready(Settlement::Refused {
                stats,
                refusal: Refusal::Skip,
            });
        };
        if retired && trust == Trust::Observed {
            return std::future::ready(Settlement::Refused {
                stats,
                refusal: Refusal::Unreconciled,
            });
        }
        for commit in commits {
            let applied =
                with_wallet_db_write_lock("sync_engine.transparent_ledger.commit", || match trust {
                    Trust::Trusted => db.qualify_and_apply_transparent_ledger_commit(commit),
                    Trust::Observed => db.apply_transparent_ledger_commit(commit),
                });
            match applied {
                Ok(outcome) => {
                    stats.applied += 1;
                    stats.qualified += usize::from(trust == Trust::Trusted);
                    stats.window_grew |= outcome.window_grew;
                }
                Err(error) => {
                    return std::future::ready(match refusal(&error) {
                        Some(refusal) => Settlement::Refused { stats, refusal },
                        None => Settlement::Failed {
                            stats,
                            error: error.to_string(),
                        },
                    });
                }
            }
        }
        let hook = self.state.lock().unwrap().on_acknowledge.clone();
        if let Some(hook) = hook {
            hook();
        }
        let mut state = self.state.lock().unwrap();
        state.acknowledged += 1;
        state.reconciled += usize::from(retired);
        // Trusted commits resolved the retirements.
        if retired {
            state.retiring = false;
        }
        std::future::ready(Settlement::Acknowledged(stats))
    }
}

impl State {
    fn answer(&mut self, request: &SourceRequest<'_>) -> Result<SourceBatch, SourceError> {
        if let Some(failure) = &self.failure {
            return Err(failure.clone());
        }
        if let Some(cause) = self.withdrawn.get(&request.account) {
            return Ok(SourceBatch::Withdrawn(*cause));
        }
        if let Some(next) = self.pending {
            return Ok(SourceBatch::Pending { next });
        }
        let watch = request.watch;
        let context = watch
            .context()
            .expect("the coordinator asks only with a local target");
        let target = context.target;
        let anchor = match self.published {
            Some(height) if height < target.height => ChainPoint {
                height,
                hash: (self.hash)(height.into()),
            },
            _ => target,
        };
        let behind_by = u32::from(target.height) - u32::from(anchor.height);
        let mut next = if behind_by > 0 {
            super::pir::continuation(Outcome::Behind)
        } else {
            Continuation::Complete
        };
        let revision = self.revision_at(anchor);
        let mut commit = TransparentLedgerCommit {
            context,
            revision: revision.clone(),
            anchor,
            receives: Vec::new(),
            spends: Vec::new(),
            coverage: Vec::new(),
            unsupported: Vec::new(),
            opened_pages: Vec::new(),
            completed_pages: Vec::new(),
        };
        let own_page = watch
            .pending_pages
            .iter()
            .any(|page| page.revision == revision && page.request.page == PAGE);
        if own_page {
            commit.completed_pages.push(PAGE.to_vec());
            self.page_answered = true;
        } else if self.split_pages && !self.page_answered {
            // Retrieval started but not finished: no facts for these
            // addresses yet, and the next pass resumes the page.
            commit.opened_pages.push(PageRequest {
                page: PAGE.to_vec(),
                addresses: watch.addresses.iter().map(|a| a.address).collect(),
                from: watch
                    .addresses
                    .iter()
                    .map(|a| a.required_from)
                    .min()
                    .unwrap_or(anchor.height)
                    .min(anchor.height),
                through: anchor.height,
            });
            self.unacknowledged
                .insert(request.account, (vec![commit], self.retiring));
            return Ok(SourceBatch::Ready {
                next: self.next.unwrap_or(Continuation::More),
                behind_by,
            });
        }

        let watched: BTreeSet<_> = watch.addresses.iter().map(|a| a.address).collect();
        commit.receives = self
            .receives
            .iter()
            .filter(|r| watched.contains(&r.address) && r.mined_height <= anchor.height)
            .cloned()
            .collect();
        commit.spends = self
            .spends
            .iter()
            .filter(|s| watched.contains(&s.prevout_address) && s.mined_height <= anchor.height)
            .cloned()
            .collect();
        for watched in &watch.addresses {
            if watched.required_from > anchor.height {
                continue;
            }
            let range = AddressRange {
                address: watched.address,
                from: watched.required_from,
                through: anchor.height,
            };
            if self.unsupported.contains(&watched.address) {
                commit.unsupported.push(range);
            } else {
                commit.coverage.push(range);
            }
        }
        let mut commits = if self.split_commits {
            split(commit)
        } else {
            vec![commit]
        };
        if self.then_invalid {
            let malformed = invalid(&commits);
            commits.push(malformed);
        }
        if let Some(fixed) = self.next {
            next = fixed;
        }
        self.unacknowledged
            .insert(request.account, (commits, self.retiring));
        Ok(SourceBatch::Ready { next, behind_by })
    }

    /// One provisional revision per publication; a new publication replaces
    /// the previous revision with a higher lineage.
    fn revision_at(&mut self, anchor: ChainPoint) -> RecoveryRevision {
        let publication = PublicationAnchor {
            height: anchor.height,
            hash: anchor.hash,
        };
        match &self.revision {
            Some(revision) if revision.publication == publication => revision.clone(),
            previous => {
                let lineage = previous.as_ref().map_or(1, |r| r.lineage + 1);
                let revision = RecoveryRevision {
                    source: FIXTURE_SOURCE.to_vec(),
                    revision: format!("r{lineage}").into_bytes(),
                    lineage,
                    sealed: false,
                    publication,
                };
                self.revision = Some(revision.clone());
                revision
            }
        }
    }
}

/// `commit` as two commits of its revision: the first holds the facts of the
/// first half of its addresses and its pages, the second the rest.
fn split(
    commit: TransparentLedgerCommit<AccountUuid>,
) -> Vec<TransparentLedgerCommit<AccountUuid>> {
    let addresses: Vec<_> = commit
        .coverage
        .iter()
        .chain(&commit.unsupported)
        .map(|range| range.address)
        .collect();
    let first: BTreeSet<_> = addresses[..addresses.len() / 2].iter().copied().collect();
    let in_first = |address: &TransparentAddress| first.contains(address);
    let mut rest = TransparentLedgerCommit {
        opened_pages: Vec::new(),
        completed_pages: Vec::new(),
        ..commit.clone()
    };
    let mut head = commit;
    head.receives.retain(|r| in_first(&r.address));
    head.spends.retain(|s| in_first(&s.prevout_address));
    head.coverage.retain(|r| in_first(&r.address));
    head.unsupported.retain(|r| in_first(&r.address));
    rest.receives.retain(|r| !in_first(&r.address));
    rest.spends.retain(|s| !in_first(&s.prevout_address));
    rest.coverage.retain(|r| !in_first(&r.address));
    rest.unsupported.retain(|r| !in_first(&r.address));
    vec![head, rest]
}

/// A commit of the same revision as `batch` that the library refuses as
/// malformed: its one range ends before it starts.
fn invalid(batch: &[TransparentLedgerCommit<AccountUuid>]) -> TransparentLedgerCommit<AccountUuid> {
    let like = &batch[0];
    let address = batch
        .iter()
        .flat_map(|commit| commit.coverage.iter().chain(&commit.unsupported))
        .map(|range| range.address)
        .next()
        .expect("a fixture batch covers an address");
    TransparentLedgerCommit {
        receives: Vec::new(),
        spends: Vec::new(),
        coverage: vec![AddressRange {
            address,
            from: like.anchor.height,
            through: like.anchor.height - 1,
        }],
        unsupported: Vec::new(),
        opened_pages: Vec::new(),
        completed_pages: Vec::new(),
        ..like.clone()
    }
}
