//! A deterministic in-memory [`RecoverySource`] for tests.
//!
//! It answers from a configurable set of mined receives and spends. Its revisions use
//! [`FIXTURE_SOURCE`] as their source id. Only the library's test-only hook
//! can qualify one ([`FixtureSource::qualified_in`]), so a fixture revision can
//! never qualify a production account.

use std::collections::{BTreeSet, VecDeque};
use std::future::Future;
use std::sync::Mutex;

use transparent::address::TransparentAddress;
use zcash_client_backend::data_api::transparent_ledger::{
    AddressRange, ChainPoint, PageRequest, PublicationAnchor, ReceiveEvent, RecoveryRevision,
    SpendEvent,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use super::{RecoverySource, SourceBounds, SourceError, SourceRequest, SourceResult};
use crate::wallet::{
    db::{open_wallet_db_with_timeout, with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

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
    failure: Option<SourceError>,
    /// Run one per call, before answering: a test's concurrent change.
    hooks: VecDeque<Hook>,
    revision: Option<RecoveryRevision>,
    /// The wallet in which each new revision is qualified, as a verifier would.
    qualify_in: Option<(String, WalletNetwork)>,
    calls: usize,
    bounds: Option<SourceBounds>,
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
                failure: None,
                hooks: VecDeque::new(),
                revision: None,
                qualify_in: None,
                calls: 0,
                bounds: None,
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

    /// Answers as a source that has indexed only through `height`.
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

    pub(crate) fn fail(&self, failure: Option<SourceError>) -> &Self {
        self.with(|state| state.failure = failure)
    }

    /// Runs `hook` at the start of a later call, one hook per call in order.
    pub(crate) fn on_call(&self, hook: impl FnOnce() + Send + 'static) -> &Self {
        self.with(|state| state.hooks.push_back(Box::new(hook)))
    }

    /// Qualifies each new revision in the wallet at `path` before answering
    /// with it, through the library's test-only hook.
    pub(crate) fn qualified_in(&self, path: &str, network: WalletNetwork) -> &Self {
        self.with(|state| state.qualify_in = Some((path.to_owned(), network)))
    }

    pub(crate) fn calls(&self) -> usize {
        self.state.lock().unwrap().calls
    }

    /// The bounds of the latest call.
    pub(crate) fn bounds(&self) -> Option<SourceBounds> {
        self.state.lock().unwrap().bounds
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
    fn recover(
        &self,
        request: SourceRequest<'_>,
    ) -> impl Future<Output = Result<SourceResult, SourceError>> + Send {
        let hook = {
            let mut state = self.state.lock().unwrap();
            state.calls += 1;
            state.bounds = Some(request.bounds);
            state.hooks.pop_front()
        };
        if let Some(hook) = hook {
            hook();
        }
        std::future::ready(self.state.lock().unwrap().answer(request))
    }
}

impl State {
    fn answer(&mut self, request: SourceRequest<'_>) -> Result<SourceResult, SourceError> {
        if let Some(failure) = &self.failure {
            return Err(failure.clone());
        }
        let anchor = match self.published {
            Some(height) if height < request.target.height => ChainPoint {
                height,
                hash: (self.hash)(height.into()),
            },
            _ => request.target,
        };
        let revision = self.revision_at(anchor);
        let mut result = SourceResult {
            revision: revision.clone(),
            anchor,
            receives: Vec::new(),
            spends: Vec::new(),
            coverage: Vec::new(),
            unsupported: Vec::new(),
            opened_pages: Vec::new(),
            completed_pages: Vec::new(),
        };
        let own_page = request
            .pending_pages
            .iter()
            .any(|page| page.revision == revision && page.request.page == PAGE);
        if own_page {
            result.completed_pages.push(PAGE.to_vec());
            self.page_answered = true;
        } else if self.split_pages && !self.page_answered {
            // Retrieval started but not finished: no facts for these addresses yet.
            result.opened_pages.push(PageRequest {
                page: PAGE.to_vec(),
                addresses: request.addresses.iter().map(|a| a.address).collect(),
                from: request
                    .addresses
                    .iter()
                    .map(|a| a.required_from)
                    .min()
                    .unwrap_or(anchor.height)
                    .min(anchor.height),
                through: anchor.height,
            });
            return Ok(result);
        }

        let watched: BTreeSet<_> = request.addresses.iter().map(|a| a.address).collect();
        result.receives = self
            .receives
            .iter()
            .filter(|r| watched.contains(&r.address) && r.mined_height <= anchor.height)
            .cloned()
            .collect();
        result.spends = self
            .spends
            .iter()
            .filter(|s| watched.contains(&s.prevout_address) && s.mined_height <= anchor.height)
            .cloned()
            .collect();
        for watched in request.addresses {
            if watched.required_from > anchor.height {
                continue;
            }
            let range = AddressRange {
                address: watched.address,
                from: watched.required_from,
                through: anchor.height,
            };
            if self.unsupported.contains(&watched.address) {
                result.unsupported.push(range);
            } else {
                result.coverage.push(range);
            }
        }
        Ok(result)
    }

    /// One provisional revision per publication; a new publication replaces
    /// the previous revision with a higher lineage.
    fn revision_at(&mut self, anchor: ChainPoint) -> RecoveryRevision {
        let publication = PublicationAnchor {
            height: anchor.height,
            hash: anchor.hash,
        };
        let revision = match &self.revision {
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
        };
        // Replacements may advance lineage without changing the publication
        // anchor. Every returned revision still needs trusted qualification.
        if let Some((path, network)) = &self.qualify_in {
            let mut db = open_wallet_db_with_timeout(path, *network, SYNC_DB_BUSY_TIMEOUT)
                .expect("open fixture wallet");
            with_wallet_db_write_lock("test.transparent_ledger.qualify", || {
                db.qualify_transparent_revision(&revision)
            })
            .expect("qualify fixture revision");
        }
        revision
    }
}
