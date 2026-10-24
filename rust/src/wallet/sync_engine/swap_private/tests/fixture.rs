//! A synthetic Mainnet chain scanned into real app wallets, and a receiver service built
//! from its actual payments with the production snapshot, witness, GCS and PIR code.
use super::super::*;
use orchard::keys::{FullViewingKey, Scope};
use secrecy::SecretVec;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{mpsc, Arc, Mutex},
};
use zakura_one_time_ivk::{KeyId, Purpose};
use zakura_pir_client::receiver::{
    blocks::{BlockFilter, BlockId},
    inventory::{FilterRef, Inventory, Shard},
    session::{Publication, MIN_ROWS},
    shards::{Coverage, ShardFilter},
    snapshot::{Manifest, Snapshot, PROFILE},
    witness, RawRecord,
};
use zakura_pir_publisher::receiver::{
    snapshot::{assign_ordinals, SnapshotPublisherExt as _},
    witness::{payloads, TablePublisherExt as _},
};
use zakura_pir_query_server::receiver::server::{Server, WitnessServer};
use zcash_client_backend::{
    data_api::{
        chain::{BlockSource, ChainState},
        one_time_ivk::restore::{DirectoryPayment, LookupWork, RecoveryStatus},
        testing::{AddressType, IronwoodFvk, TestBuilder, TestState},
        WalletRead, WalletWrite,
    },
    proto::compact_formats::CompactBlock,
};
use zcash_client_sqlite::testing::{
    db::{TestDb, TestDbFactory},
    BlockCache,
};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::{consensus::BlockHeight, local_consensus::LocalNetwork, value::Zatoshis};

pub(super) const NETWORK: WalletNetwork = WalletNetwork::Main;
pub(super) const ORIGIN: &str = "https://receiver.test";

/// Ironwood activation on Mainnet, where the synthetic chain starts.
pub(super) fn activation() -> u32 {
    NETWORK
        .activation_height(NetworkUpgrade::Nu6_3)
        .unwrap()
        .into()
}

/// Turns on the process settings the app applies before recovery can run.
pub(super) fn enable_feature() {
    crate::api::sync::set_enhance_pir_enabled(true);
    crate::api::sync::set_near_swap_privacy_enabled(true);
}

/// The Mainnet upgrade heights as a local network the test chain can mine.
fn local_network() -> LocalNetwork {
    let height = |upgrade| NETWORK.activation_height(upgrade);
    LocalNetwork {
        overwinter: height(NetworkUpgrade::Overwinter),
        sapling: height(NetworkUpgrade::Sapling),
        blossom: height(NetworkUpgrade::Blossom),
        heartwood: height(NetworkUpgrade::Heartwood),
        canopy: height(NetworkUpgrade::Canopy),
        nu5: height(NetworkUpgrade::Nu5),
        nu6: height(NetworkUpgrade::Nu6),
        nu6_1: height(NetworkUpgrade::Nu6_1),
        nu6_2: height(NetworkUpgrade::Nu6_2),
        nu6_3: Some(activation().into()),
        nu7: None,
    }
}

/// The independent chain, its tree state after each block, and every payment the
/// receiver directory indexes.
pub(super) struct Chain {
    st: TestState<BlockCache, TestDb, LocalNetwork>,
    states: BTreeMap<u32, ChainState>,
    records: Vec<RawRecord>,
}

impl Chain {
    /// A chain whose first block is Ironwood's activation block.
    pub(super) fn new() -> Self {
        let below = activation() - 1;
        let st = TestBuilder::new()
            .with_network(local_network())
            .with_data_store_factory(TestDbFactory::default())
            .with_block_cache(BlockCache::new())
            .with_initial_chain_state(|_, _| {
                zcash_client_backend::data_api::testing::InitialChainState {
                    chain_state: ChainState::empty(below.into(), BlockHash([0; 32])),
                    prior_sapling_roots: vec![],
                    prior_orchard_roots: vec![],
                }
            })
            .with_account_having_current_birthday()
            .build();
        let mut chain = Self {
            st,
            states: BTreeMap::from([(below, ChainState::empty(below.into(), BlockHash([0; 32])))]),
            records: Vec::new(),
        };
        chain.mine(1);
        chain
    }

    /// Records the tree state of the block just mined. The chain's own wallet scans it so
    /// [`Self::rewind`] can truncate that wallet with the block cache.
    fn advance(&mut self) -> u32 {
        let block = self.st.latest_cached_block().unwrap();
        let height = u32::from(block.height());
        self.states.insert(height, block.chain_state().clone());
        self.st.scan_cached_blocks(height.into(), 1);
        height
    }

    /// Mines `n` blocks without shielded outputs.
    pub(super) fn mine(&mut self, n: u32) {
        for _ in 0..n {
            self.st.generate_empty_block();
            self.advance();
        }
    }

    /// The latest block.
    pub(super) fn tip(&self) -> u32 {
        *self.states.keys().next_back().unwrap()
    }

    /// The chain state at the end of block `height`.
    pub(super) fn state(&self, height: u32) -> &ChainState {
        &self.states[&height]
    }

    /// The hash of block `height`.
    pub(super) fn hash(&self, height: u32) -> [u8; 32] {
        self.states[&height].block_hash().0
    }

    /// Mines one block paying `value` to `fvk`'s default address with a real Ironwood
    /// note. `indexed` says the receiver directory lists it, as for NEAR's zero-OVK
    /// payouts.
    pub(super) fn pay(&mut self, fvk: &FullViewingKey, value: u64, indexed: bool) -> u32 {
        self.pay_tx(fvk, value, indexed).0
    }

    /// [`Self::pay`], also returning the paying transaction's ID in internal byte order.
    pub(super) fn pay_tx(
        &mut self,
        fvk: &FullViewingKey,
        value: u64,
        indexed: bool,
    ) -> (u32, [u8; 32]) {
        let (height, _, _) = self.st.generate_next_block(
            &IronwoodFvk(fvk.clone()),
            AddressType::DefaultExternal,
            Zatoshis::const_from_u64(value),
        );
        let height = u32::from(height);
        self.advance();
        let record = self.record(height, fvk);
        let txid = record.payment.txid;
        if indexed {
            self.records.push(record);
        }
        (height, txid)
    }

    /// Drops every block above `height`, as a reorg does before the replacement branch is
    /// mined. Later blocks get fresh hashes, so wallets see a different chain.
    pub(super) fn rewind(&mut self, height: u32) {
        self.st.truncate_to_height(height.into());
        self.states.split_off(&(height + 1));
        self.records.retain(|r| r.payment.height <= height);
    }

    /// The hash of block `height` if the chain has it.
    pub(super) fn hash_at(&self, height: u32) -> Option<[u8; 32]> {
        self.states.get(&height).map(|s| s.block_hash().0)
    }

    /// Mines a block holding only `tx`, which an app wallet built and broadcast.
    pub(super) fn mine_tx(&mut self, tx: &Transaction) -> u32 {
        self.st.generate_next_block_from_tx(1, tx);
        self.advance()
    }

    /// Mines a block holding only `tx`, an app-built payment to `fvk`, and lists that
    /// payment in the receiver directory as NEAR's payouts are. Returns its height and
    /// the transaction ID in internal byte order. Mining the same `tx` again after a
    /// rewind moves the same receipt to a new block.
    pub(super) fn mine_indexed_tx(
        &mut self,
        tx: &Transaction,
        fvk: &FullViewingKey,
    ) -> (u32, [u8; 32]) {
        let height = self.mine_tx(tx);
        let record = self.record(height, fvk);
        let txid = record.payment.txid;
        self.records.push(record);
        (height, txid)
    }

    /// The cached compact block at `height`.
    fn block(&self, height: u32) -> CompactBlock {
        let mut found = None;
        self.st
            .cache()
            .with_blocks::<_, ()>(Some(height.into()), Some(1), |block| {
                found = Some(block);
                Ok(())
            })
            .unwrap();
        found.unwrap()
    }

    /// The directory record of the output in block `height` that `fvk` can decrypt.
    fn record(&self, height: u32, fvk: &FullViewingKey) -> RawRecord {
        use orchard::note_encryption::{CompactAction, IronwoodDomain};
        use zcash_note_encryption::try_compact_note_decryption;
        let block = self.block(height);
        let ivk = fvk.to_ivk(Scope::External).prepare();
        let mut position = self.states[&(height - 1)].final_ironwood_tree().tree_size();
        for tx in &block.vtx {
            for (action_index, compact) in tx.ironwood_actions.iter().enumerate() {
                let action = CompactAction::try_from(compact).unwrap();
                let domain = IronwoodDomain::for_compact_action(&action);
                if try_compact_note_decryption(&domain, &ivk, &action).is_some() {
                    return RawRecord {
                        receiver: fvk.address_at(0u32, Scope::External).to_raw_address_bytes(),
                        page: 0,
                        total: 1,
                        payment: DirectoryPayment {
                            height,
                            block_hash: block.hash().0,
                            txid: *tx.txid().as_ref(),
                            // Fake blocks have no coinbase, and the directory refuses index 0.
                            tx_index: u32::try_from(tx.index).unwrap().max(1),
                            action_index: action_index as u32,
                            position,
                            action_nullifier: compact.nullifier.as_slice().try_into().unwrap(),
                            cmx: compact.cmx.as_slice().try_into().unwrap(),
                            ephemeral_key: compact.ephemeral_key.as_slice().try_into().unwrap(),
                            ciphertext_prefix: compact.ciphertext.as_slice().try_into().unwrap(),
                        },
                        ordinal: 0,
                    };
                }
                position += 1;
            }
        }
        panic!("no output in block {height} pays the key");
    }

    /// Every Ironwood note commitment, in tree order.
    fn commitments(&self) -> Vec<[u8; 32]> {
        let mut commitments = Vec::new();
        self.st
            .cache()
            .with_blocks::<_, ()>(Some(activation().into()), None, |block| {
                for tx in &block.vtx {
                    for action in &tx.ironwood_actions {
                        commitments.push(action.cmx.as_slice().try_into().unwrap());
                    }
                }
                Ok(())
            })
            .unwrap();
        commitments
    }
}

/// Which receiver route a request used, for holds and byte counts. Payment and witness
/// queries share a route, so `witness` names a query to a witness session.
fn route_class(route: &str, witness: bool) -> &'static str {
    match route {
        "inventory" => "inventory",
        "block-filters/head" => "head",
        "query" if witness => "witness",
        "query" => "query",
        _ if route.starts_with("inventory/") => "chunk",
        _ if route.starts_with("shard-filters/") => "shard-filter",
        _ if route.starts_with("block-filters/") => "filters",
        _ if route.starts_with("public/") => "public",
        _ => panic!("unexpected receiver route {route}"),
    }
}

/// A request the service holds until the test releases it.
struct Hold {
    class: &'static str,
    nth: usize,
    arrived: mpsc::Sender<()>,
    release: Arc<tokio::sync::Semaphore>,
}

/// The test's side of a held request: wait for it to arrive, then release it.
pub(super) struct Held {
    arrived: mpsc::Receiver<()>,
    release: Arc<tokio::sync::Semaphore>,
}

impl Held {
    /// Blocks until the worker has sent the held request.
    pub(super) fn wait(&self) {
        self.arrived
            .recv_timeout(Duration::from_secs(30))
            .expect("the held request arrived");
    }

    /// Waits up to `timeout` for the held request, returning whether it arrived.
    pub(super) fn try_wait(&self, timeout: Duration) -> bool {
        self.arrived.recv_timeout(timeout).is_ok()
    }

    /// Lets the held response go.
    pub(super) fn release(&self) {
        self.release.add_permits(1);
    }
}

/// One immutable publication: an inventory of shards with real encrypted PIR over the
/// indexed payments and their companion witness tables, sealed shards' filters and a
/// rolling block filter suffix. Counts every request and response body.
pub(super) struct Service {
    inventory: Inventory,
    payments: Vec<Server>,
    witnesses: Vec<WitnessServer>,
    shard_filters: Vec<([u8; 32], Vec<u8>)>,
    head: Head,
    filters: Vec<BlockFilter>,
    requests: Mutex<Vec<(&'static str, String, usize, usize)>>,
    holds: Mutex<Vec<Hold>>,
    /// How long each request of a class takes to answer.
    delays: Mutex<BTreeMap<&'static str, Duration>>,
    trace: Mutex<Trace>,
    /// A protocol the head names instead of the supported one, as a newer service would.
    protocol: Mutex<Option<String>>,
}

/// Which address and history page each encrypted payment query read, for one account.
#[derive(Default)]
struct Trace {
    wallet: Option<(String, AccountUuid)>,
    /// The work item and page of the previous query, to number pages within a step.
    previous: Option<(LookupWork, u32)>,
    pages: Vec<(bool, u64, u32)>,
}

impl Service {
    /// Publishes payments mined through `pir_end` as one recent tier, and filters for
    /// blocks `first` through `filter_tip`. Each filter lists the receivers paid in its
    /// block plus `extra` hits.
    pub(super) fn publish(
        chain: &Chain,
        pir_end: u32,
        first: u32,
        filter_tip: u32,
        extra: &[(u32, [u8; 43])],
    ) -> Arc<Self> {
        Self::publish_shards(chain, &[], pir_end, first, filter_tip, extra)
    }

    /// [`Self::publish`] of everything mined through the chain tip, with filters from
    /// activation and no extra hits.
    pub(super) fn at_tip(chain: &Chain) -> Arc<Self> {
        Self::publish(chain, chain.tip(), activation(), chain.tip(), &[])
    }

    /// [`Self::publish`], with history before the recent tier split into sealed shards
    /// ending at each of `sealed`, each with its receiver filter. Every witness table is
    /// built at `pir_end`.
    pub(super) fn publish_shards(
        chain: &Chain,
        sealed: &[u32],
        pir_end: u32,
        first: u32,
        filter_tip: u32,
        extra: &[(u32, [u8; 43])],
    ) -> Arc<Self> {
        let tree_size = chain.state(pir_end).final_ironwood_tree().tree_size();
        let commitments = chain.commitments();
        let (mut payments, mut witnesses, mut shard_filters, mut shards) =
            (vec![], vec![], vec![], vec![]);
        let (mut start, mut parent, mut position) = (activation(), chain.hash(activation() - 1), 0);
        let ends = sealed
            .iter()
            .map(|end| (*end, true))
            .chain([(pir_end, false)]);
        for (end, is_sealed) in ends {
            let end_position = chain.state(end).final_ironwood_tree().tree_size();
            let mut records: Vec<RawRecord> = chain
                .records
                .iter()
                .filter(|r| (start..=end).contains(&r.payment.height))
                .cloned()
                .collect();
            let mut totals = BTreeMap::new();
            for r in &records {
                *totals.entry(r.receiver).or_insert(0u32) += 1;
            }
            let mut pages = BTreeMap::new();
            for r in &mut records {
                let page = pages.entry(r.receiver).or_insert(0u32);
                r.page = *page;
                r.total = totals[&r.receiver];
                *page += 1;
            }
            assign_ordinals(&mut records);
            let snapshot = Snapshot::build(
                Manifest {
                    profile: PROFILE.into(),
                    history_revision: 0,
                    genesis: MAINNET_GENESIS,
                    start_height: start,
                    start_parent: parent,
                    start_position: position,
                    end_height: end,
                    end_hash: chain.hash(end),
                    end_position,
                    rows: MIN_ROWS,
                    salt: [5; 32],
                    records: 0,
                    data_sha256: [0; 32],
                },
                &records,
            )
            .unwrap();
            let mut positions: Vec<_> = records.iter().map(|r| r.payment.position).collect();
            positions.sort_unstable();
            let table = witness::Table::build(
                witness::Manifest {
                    profile: witness::PROFILE.into(),
                    genesis: MAINNET_GENESIS,
                    history_revision: 0,
                    payments: snapshot.manifest.revision().unwrap(),
                    payloads: 0,
                    rows: MIN_ROWS,
                    tree_height: pir_end,
                    tree_hash: chain.hash(pir_end),
                    tree_size,
                    data_sha256: [0; 32],
                },
                &payloads(&commitments[..tree_size as usize], &positions).unwrap(),
            )
            .unwrap();
            let server = Server::new(snapshot).unwrap();
            let witness_server = WitnessServer::new(table, &server).unwrap();
            let segment = Publication {
                payments: server.manifest().clone(),
                witnesses: witness_server.manifest().clone(),
            };
            payments.push(server);
            witnesses.push(witness_server);
            let filter = is_sealed.then(|| {
                let filter = ShardFilter::build(
                    MAINNET_GENESIS,
                    0,
                    Coverage {
                        start_height: start,
                        end_height: end,
                        end_hash: chain.hash(end),
                    },
                    records.iter().map(|r| &r.receiver),
                )
                .unwrap();
                shard_filters.push((filter.digest(), filter.bytes().to_vec()));
                FilterRef {
                    digest: filter.digest(),
                    bytes: filter.bytes().len() as u32,
                    receivers: filter.receivers() as u32,
                }
            });
            shards.push(Shard {
                index: 0,
                sealed: is_sealed,
                start_height: start,
                start_parent: parent,
                start_position: position,
                end_height: end,
                end_hash: chain.hash(end),
                end_position,
                segments: vec![segment],
                filter,
            });
            (start, parent, position) = (end + 1, chain.hash(end), end_position);
        }
        let filters = (first..=filter_tip)
            .map(|height| {
                let hits: Vec<[u8; 43]> = chain
                    .records
                    .iter()
                    .filter(|r| r.payment.height == height)
                    .map(|r| r.receiver)
                    .chain(extra.iter().filter(|(h, _)| *h == height).map(|(_, r)| *r))
                    .collect();
                BlockFilter::build(
                    &MAINNET_GENESIS,
                    BlockId {
                        height,
                        hash: chain.hash(height),
                    },
                    chain.hash(height - 1),
                    &hits,
                )
                .unwrap()
            })
            .collect();
        Arc::new(Self {
            inventory: Inventory::build(MAINNET_GENESIS, 0, shards).unwrap(),
            payments,
            witnesses,
            shard_filters,
            head: Head {
                genesis: MAINNET_GENESIS,
                revision: 0,
                first,
                tip: BlockId {
                    height: filter_tip,
                    hash: chain.hash(filter_tip),
                },
            },
            filters,
            requests: Mutex::new(Vec::new()),
            holds: Mutex::new(Vec::new()),
            delays: Mutex::new(BTreeMap::new()),
            trace: Mutex::new(Trace::default()),
            protocol: Mutex::new(None),
        })
    }

    /// Makes the head name `protocol`, which this client does not support.
    pub(super) fn serve_protocol(&self, protocol: &str) {
        *self.protocol.lock().unwrap() = Some(protocol.into());
    }

    /// Makes the head name the supported protocol again.
    pub(super) fn serve_supported(&self) {
        *self.protocol.lock().unwrap() = None;
    }

    /// The published inventory.
    pub(super) fn inventory(&self) -> &Inventory {
        &self.inventory
    }

    /// Holds the `nth` (zero-based) request of `class` until released.
    pub(super) fn hold(&self, class: &'static str, nth: usize) -> Held {
        let (arrived, waiting) = mpsc::channel();
        let release = Arc::new(tokio::sync::Semaphore::new(0));
        self.holds.lock().unwrap().push(Hold {
            class,
            nth,
            arrived,
            release: release.clone(),
        });
        Held {
            arrived: waiting,
            release,
        }
    }

    /// Answers every later request of `class` only after `delay`, as a slow route would.
    pub(super) fn delay(&self, class: &'static str, delay: Duration) {
        self.delays.lock().unwrap().insert(class, delay);
    }

    /// Records the address and page of every later payment query for `account` of
    /// `wallet`. Queries are encrypted, so each one is attributed to the lookup the worker
    /// just read: the first due item this publication can answer, which the worker cannot
    /// change before its request. Only for single-account rounds without concurrent writers.
    pub(super) fn trace(&self, wallet: &Wallet, account: &Account) {
        self.trace.lock().unwrap().wallet = Some((wallet.path.clone(), account.id));
    }

    /// The traced queries as (is a receive key, index, page), in request order.
    pub(super) fn traced(&self) -> Vec<(bool, u64, u32)> {
        self.trace.lock().unwrap().pages.clone()
    }

    /// Attributes one payment query to the lookup in flight (see [`Self::trace`]).
    fn record_query(&self) {
        let mut trace = self.trace.lock().unwrap();
        let Some((path, account)) = trace.wallet.clone() else {
            return;
        };
        let db =
            open_existing_wallet_db_with_timeout(&path, NETWORK, WALLET_DB_BUSY_TIMEOUT).unwrap();
        let end = BlockHeight::from(self.inventory.head().end_height);
        let work = db
            .one_time_recovery(account, one_time_ivk::now().unwrap())
            .unwrap()
            .lookups
            .into_iter()
            .find(|work| work.through <= end)
            .expect("a query is sent only for a due lookup");
        let page = match (&trace.previous, &work.cursor) {
            (Some((previous, page)), _) if *previous == work => page + 1,
            // A cursor from another inventory is never resumed.
            (_, Some(cursor)) if cursor.inventory == self.inventory.head().inventory => {
                cursor.last.as_ref().map_or(0, |last| last.page + 1)
            }
            _ => 0,
        };
        trace.pages.push((
            work.work.key.purpose() == Purpose::Receive,
            work.work.key.index(),
            page,
        ));
        trace.previous = Some((work, page));
    }

    /// The status and body for one request, as the receiver service answers it.
    fn answer(&self, class: &str, route: &str, body: &[u8]) -> Result<Vec<u8>, session::Error> {
        let gone = || session::Error::Revision;
        Ok(match class {
            "inventory" => {
                let mut head = self.inventory.head().clone();
                if let Some(protocol) = self.protocol.lock().unwrap().clone() {
                    head.protocol = protocol;
                }
                serde_json::to_vec(&head).unwrap()
            }
            "chunk" => {
                let (id, chunk) = route
                    .strip_prefix("inventory/")
                    .unwrap()
                    .split_once('/')
                    .unwrap();
                if id != hex::encode(self.inventory.head().inventory) {
                    return Err(gone());
                }
                let chunks = self.inventory.chunks().unwrap();
                serde_json::to_vec(&chunks[chunk.parse::<usize>().unwrap()]).unwrap()
            }
            "shard-filter" => {
                let digest = route.strip_prefix("shard-filters/").unwrap();
                self.shard_filters
                    .iter()
                    .find(|(d, _)| hex::encode(d) == digest)
                    .map(|(_, f)| f.clone())
                    .ok_or_else(|| session::Error::Transport("HTTP 404".into()))?
            }
            "head" => serde_json::to_vec(&self.head).unwrap(),
            "filters" => {
                let range = route.strip_prefix("block-filters/0/").unwrap();
                let (from, count) = range.split_once('/').unwrap();
                let from: u32 = from.parse().unwrap();
                let count: usize = count.parse().unwrap();
                if from < self.head.first {
                    return Err(gone());
                }
                Batch::new(
                    MAINNET_GENESIS,
                    0,
                    self.filters
                        .iter()
                        .filter(|f| f.block().height >= from)
                        .take(count)
                        .cloned()
                        .collect(),
                )
                .unwrap()
                .encode()
                .unwrap()
            }
            "public" => {
                let id = route.strip_prefix("public/").unwrap();
                self.payments
                    .iter()
                    .find(|p| hex::encode(p.id()) == id)
                    .map(|p| p.public().to_vec())
                    .or_else(|| {
                        self.witnesses
                            .iter()
                            .find(|w| hex::encode(w.id()) == id)
                            .map(|w| w.public().to_vec())
                    })
                    .ok_or_else(gone)?
            }
            "witness" => self.witness_server(body).unwrap().respond(body).unwrap(),
            _ => {
                let session = body.get(4..36);
                self.payments
                    .iter()
                    .find(|p| session == Some(&p.id()[..]))
                    .ok_or_else(gone)?
                    .respond(body)
                    .unwrap()
            }
        })
    }

    /// The witness session `body` queries, if any.
    fn witness_server(&self, body: &[u8]) -> Option<&WitnessServer> {
        let session = body.get(4..36)?;
        self.witnesses.iter().find(|w| session == &w.id()[..])
    }

    /// Answers one request, after any hold on it is released.
    async fn reply(&self, url: &str, body: &[u8], limit: usize) -> Result<Vec<u8>, session::Error> {
        let route = url.split("/v1/receiver/").nth(1).unwrap().to_owned();
        let class = route_class(&route, self.witness_server(body).is_some());
        if class == "query" {
            self.record_query();
        }
        let (index, gate) = {
            // Counted and recorded under one lock, so concurrent requests of a class get
            // distinct indexes and never share a hold.
            let mut requests = self.requests.lock().unwrap();
            let seen = requests.iter().filter(|(c, ..)| *c == class).count();
            requests.push((class, route.clone(), body.len(), 0));
            let index = requests.len() - 1;
            drop(requests);
            let holds = self.holds.lock().unwrap();
            let gate = holds
                .iter()
                .find(|h| h.class == class && h.nth == seen)
                .map(|h| {
                    let _ = h.arrived.send(());
                    h.release.clone()
                });
            (index, gate)
        };
        if let Some(gate) = gate {
            gate.acquire().await.unwrap().forget();
        }
        let delay = self.delays.lock().unwrap().get(class).copied();
        if let Some(delay) = delay {
            tokio::time::sleep(delay).await;
        }
        let response = self.answer(class, &route, body)?;
        if response.len() > limit {
            return Err(session::Error::Transport("response over its limit".into()));
        }
        self.requests.lock().unwrap()[index].3 = response.len();
        Ok(response)
    }

    /// The number of requests of `class`.
    pub(super) fn count(&self, class: &str) -> usize {
        self.requests
            .lock()
            .unwrap()
            .iter()
            .filter(|(c, ..)| *c == class)
            .count()
    }

    /// Encrypted payment lookups, excluding setup, witness reads and filters.
    pub(super) fn queries(&self) -> usize {
        self.count("query")
    }

    /// The filter routes requested, as `from/count`.
    pub(super) fn filter_requests(&self) -> Vec<String> {
        self.requests
            .lock()
            .unwrap()
            .iter()
            .filter(|(c, ..)| *c == "filters")
            .map(|(_, r, ..)| r.trim_start_matches("block-filters/0/").to_owned())
            .collect()
    }

    /// The (request, response) body sizes of every request of `class`, in order.
    pub(super) fn requests_of(&self, class: &str) -> Vec<(usize, usize)> {
        self.requests
            .lock()
            .unwrap()
            .iter()
            .filter(|(c, ..)| *c == class)
            .map(|(_, _, req, resp)| (*req, *resp))
            .collect()
    }

    /// Request plus response body bytes over every route.
    pub(super) fn bytes(&self) -> usize {
        self.requests
            .lock()
            .unwrap()
            .iter()
            .map(|(_, _, req, resp)| req + resp)
            .sum()
    }

    /// Request and response bytes per route class, for the evidence log.
    pub(super) fn report(&self, label: &str) -> String {
        let mut by: BTreeMap<&str, (usize, usize, usize)> = BTreeMap::new();
        for (class, _, req, resp) in self.requests.lock().unwrap().iter() {
            let e = by.entry(class).or_default();
            e.0 += 1;
            e.1 += req;
            e.2 += resp;
        }
        let parts: Vec<_> = by
            .iter()
            .map(|(c, (n, req, resp))| format!("{c}: {n} requests, {req} up, {resp} down"))
            .collect();
        let line = format!(
            "{label}: {}; total {} bytes",
            parts.join("; "),
            self.bytes()
        );
        println!("receiver bytes {line}");
        line
    }
}

impl Transport for Service {
    /// Returns a bounded encoded public resource.
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, session::Error> {
        self.reply(url, &[], limit).await
    }
    /// Evaluates a real encrypted query without exposing its receiver to the fixture.
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, session::Error> {
        self.reply(url, &body, limit).await
    }
}

/// A software account and the seed the app keeps for it in secure storage.
#[derive(Clone)]
pub(super) struct Account {
    pub(super) id: AccountUuid,
    pub(super) uuid: String,
    seed: Vec<u8>,
}

impl Account {
    /// The seed the app would read from secure storage to sign.
    pub(super) fn seed(&self) -> SecretVec<u8> {
        SecretVec::new(self.seed.clone())
    }

    /// The account's Orchard key, which its ordinary Ironwood receivers and one-time
    /// keys derive from.
    pub(super) fn parent(&self) -> FullViewingKey {
        let usk = zcash_keys::keys::UnifiedSpendingKey::from_seed(
            &NETWORK,
            &self.seed,
            zip32::AccountId::ZERO,
        )
        .unwrap();
        FullViewingKey::from(usk.orchard())
    }

    /// One-time key `index` for `purpose`, derived without registering it.
    pub(super) fn key(&self, purpose: Purpose, index: u64) -> FullViewingKey {
        KeyId::new(purpose, index).derive(&self.parent()).unwrap()
    }

    /// The receiver bytes of one-time key `index` for `purpose`.
    pub(super) fn receiver(&self, purpose: Purpose, index: u64) -> [u8; 43] {
        self.key(purpose, index)
            .address_at(0u32, Scope::External)
            .to_raw_address_bytes()
    }
}

/// An app wallet database, scanned like ordinary sync from the shared chain.
pub(super) struct Wallet {
    _dir: tempfile::TempDir,
    pub(super) path: String,
    pub(super) accounts: Vec<Account>,
    scanned: u32,
    birthday: u32,
}

impl Wallet {
    /// Creates the app's first software account from `seed` with the given birthday.
    pub(super) fn new(seed: u8, birthday: u32) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let seed = vec![seed; 32];
        let (uuid, _) = crate::wallet::keys::init_db_and_create_account(
            &path,
            NETWORK,
            &SecretVec::new(seed.clone()),
            Some(u64::from(birthday)),
            "Recovery",
        )
        .unwrap();
        Self {
            _dir: dir,
            path,
            accounts: vec![Account {
                id: crate::wallet::keys::parse_account_uuid(&uuid).unwrap(),
                uuid,
                seed,
            }],
            scanned: birthday - 1,
            birthday,
        }
    }

    /// Adds another software account from a different seed, as the app's add flow does.
    pub(super) fn add_account(&mut self, seed: u8, birthday: u32) -> Account {
        let seed = vec![seed; 32];
        let (uuid, _) = crate::wallet::keys::add_account(
            &self.path,
            NETWORK,
            "Second",
            &SecretVec::new(seed.clone()),
            Some(u64::from(birthday)),
        )
        .unwrap();
        let account = Account {
            id: crate::wallet::keys::parse_account_uuid(&uuid).unwrap(),
            uuid,
            seed,
        };
        self.accounts.push(account.clone());
        account
    }

    /// Deletes `account` through the app's per-account delete path.
    pub(super) fn delete_account(&mut self, account: &Account) {
        crate::wallet::keys::delete_account(&self.path, NETWORK, &account.uuid).unwrap();
        self.accounts.retain(|a| a.id != account.id);
    }

    /// Imports a spending account with ZIP 32 metadata but no Orchard key, as an
    /// unbackfilled hardware import can be.
    pub(super) fn import_without_orchard(
        &self,
        seed: u8,
        birthday: u32,
        chain: &Chain,
    ) -> AccountUuid {
        use zcash_client_backend::data_api::{
            Account as _, AccountBirthday, AccountPurpose, Zip32Derivation,
        };
        let seed = [seed; 32];
        let usk = zcash_keys::keys::UnifiedSpendingKey::from_seed(
            &NETWORK,
            &seed,
            zip32::AccountId::ZERO,
        )
        .unwrap();
        let ufvk = zcash_keys::keys::UnifiedFullViewingKey::new(
            Some(usk.transparent().to_account_pubkey()),
            Some(usk.sapling().to_diversifiable_full_viewing_key()),
            None,
        )
        .unwrap();
        self.db()
            .import_account_ufvk(
                "No Orchard",
                &ufvk,
                &AccountBirthday::from_parts(chain.state(birthday - 1).clone(), None),
                AccountPurpose::Spending {
                    derivation: Some(Zip32Derivation::new(
                        zip32::fingerprint::SeedFingerprint::from_seed(&seed).unwrap(),
                        zip32::AccountId::ZERO,
                    )),
                },
                None,
            )
            .unwrap()
            .id()
    }

    /// The first account.
    pub(super) fn account(&self) -> &Account {
        &self.accounts[0]
    }

    /// A fresh handle on the app database.
    pub(super) fn db(&self) -> WalletDatabase {
        open_existing_wallet_db_with_timeout(&self.path, NETWORK, WALLET_DB_BUSY_TIMEOUT).unwrap()
    }

    /// Ordinary sync: scans every new block, without the recovery worker, filters or PIR.
    pub(super) fn scan(&mut self, chain: &Chain) {
        self.try_scan(chain).unwrap();
    }

    /// [`Self::scan`], returning the wallet's error when it refuses the blocks.
    fn try_scan(&mut self, chain: &Chain) -> Result<(), String> {
        let tip = chain.tip();
        if tip <= self.scanned {
            return Ok(());
        }
        let mut db = self.db();
        db.update_chain_tip(tip.into()).unwrap();
        zcash_client_backend::data_api::chain::scan_cached_blocks(
            &NETWORK,
            chain.st.cache(),
            &mut db,
            BlockHeight::from(self.scanned + 1),
            chain.state(self.scanned),
            (tip - self.scanned) as usize,
        )
        .map_err(|e| format!("scan from {}: {e:?}", self.scanned + 1))?;
        self.scanned = tip;
        Ok(())
    }

    /// Ordinary sync that follows reorgs: rewinds below the highest scanned block still on
    /// `chain` through the app's reorg path, scans to the tip, and stamps new blocks with
    /// the current time so quote deadlines can pass. Returns the height it rewound to, or
    /// the app's error when the wallet refuses the rewind or the new blocks.
    pub(super) fn sync(&mut self, chain: &Chain) -> Result<Option<u32>, String> {
        let tip = chain.tip();
        let mut db = self.db();
        // Adding an account rewinds the wallet to that account's birthday.
        let stored: Option<u32> = rusqlite::Connection::open(&self.path)
            .unwrap()
            .query_row("SELECT MAX(height) FROM blocks", [], |r| r.get(0))
            .unwrap();
        self.scanned = self.scanned.min(stored.unwrap_or(self.birthday - 1));
        let mut fork = self.scanned;
        while fork >= self.birthday {
            let local = db.block_metadata(fork.into()).unwrap();
            if local.is_some_and(|b| Some(b.block_hash().0) == chain.hash_at(fork)) {
                break;
            }
            fork -= 1;
        }
        let mut rewound = None;
        if fork < self.scanned {
            let actual = super::super::super::truncate_wallet_to_height(
                &self.path,
                &mut db,
                fork.into(),
                tip.into(),
                "scenario.rewind",
            )
            .map_err(|e| format!("{e:?}"))?;
            self.scanned = u32::from(actual).min(fork).max(self.birthday - 1);
            rewound = Some(self.scanned);
        }
        drop(db);
        self.try_scan(chain)?;
        rusqlite::Connection::open(&self.path)
            .unwrap()
            .execute(
                "UPDATE blocks SET time = ?1 WHERE time = 0",
                [one_time_ivk::now().unwrap()],
            )
            .unwrap();
        Ok(rewound)
    }

    /// The last block ordinary sync scanned.
    pub(super) fn scanned(&self) -> u32 {
        u32::from(
            self.db()
                .block_fully_scanned()
                .unwrap()
                .unwrap()
                .block_height(),
        )
    }

    /// The durable queue and progress of `account`.
    pub(super) fn state(&self, account: &Account) -> RecoveryStatus {
        self.db()
            .one_time_recovery(account.id, one_time_ivk::now().unwrap())
            .unwrap()
    }

    /// Every one-time key of `account` with an unfinished queued lookup, as
    /// (is a receive key, index). The status API returns only a bounded batch.
    pub(super) fn queued(&self, account: &Account) -> BTreeSet<(bool, u64)> {
        let conn = rusqlite::Connection::open(&self.path).unwrap();
        let mut statement = conn
            .prepare(
                "SELECT k.purpose, k.key_index FROM ironwood_one_time_lookups l
                 JOIN ironwood_one_time_keys k ON k.id = l.one_time_key_id
                 JOIN accounts a ON a.id = k.account_id
                 WHERE a.uuid = ?1 AND l.target_height IS NOT NULL AND l.reasons != 0
                   AND l.read_complete = 0",
            )
            .unwrap();
        let rows = statement
            .query_map([account.id.expose_uuid().as_bytes()], |r| {
                Ok((
                    r.get::<_, u8>(0)? == 1,
                    u64::from_be_bytes(r.get::<_, [u8; 8]>(1)?),
                ))
            })
            .unwrap();
        rows.collect::<Result<_, _>>().unwrap()
    }

    /// Runs one worker round against `service`, as `recover` does, with a 45 second budget.
    pub(super) fn recover(&self, service: &Service) -> Result<Round, RecoveryError> {
        self.recover_with(service, None, Duration::from_secs(45))
    }

    /// Runs one worker round, optionally manual, under the given overall budget.
    pub(super) fn recover_with(
        &self,
        service: &Service,
        manual: Option<Option<u64>>,
        budget: Duration,
    ) -> Result<Round, RecoveryError> {
        run_worker(&self.path, service, manual, budget)
    }

    /// Starts a worker round on its own thread, as the app schedules it beside sync.
    pub(super) fn spawn(
        &self,
        service: &Arc<Service>,
        manual: Option<Option<u64>>,
        budget: Duration,
    ) -> std::thread::JoinHandle<Result<Round, RecoveryError>> {
        let path = self.path.clone();
        let service = service.clone();
        std::thread::spawn(move || run_worker(&path, &*service, manual, budget))
    }

    /// Mined, unspent value of `account`'s one-time-key notes.
    pub(super) fn one_time_unspent(&self, account: &Account) -> u64 {
        self.one_time_value(account, true)
    }

    /// Value of every one-time-key note `account` has admitted, spent or not.
    pub(super) fn one_time_received(&self, account: &Account) -> u64 {
        self.one_time_value(account, false)
    }

    /// Sums `account`'s mined one-time-key notes, optionally excluding spent ones.
    fn one_time_value(&self, account: &Account, unspent: bool) -> u64 {
        let conn = rusqlite::Connection::open(&self.path).unwrap();
        conn.query_row(
            "SELECT COALESCE(SUM(n.value), 0) FROM ironwood_received_notes n
             JOIN transactions r ON r.id_tx = n.transaction_id
             JOIN accounts a ON a.id = n.account_id
             WHERE a.uuid = ?1 AND n.one_time_key_id IS NOT NULL AND r.mined_height IS NOT NULL
               AND (?2 = 0 OR NOT EXISTS(SELECT 1 FROM ironwood_received_note_spends s
                   JOIN transactions t ON t.id_tx = s.transaction_id
                   WHERE s.ironwood_received_note_id = n.id
                     AND (t.mined_height IS NOT NULL OR t.expiry_height = 0
                          OR t.expiry_height > (SELECT MAX(height) FROM blocks))))",
            rusqlite::params![account.id.expose_uuid().as_bytes(), unspent],
            |r| r.get::<_, i64>(0),
        )
        .map(|v| v as u64)
        .unwrap()
    }

    /// Each refund-key receipt of `account` as its nullifier and whether a mined
    /// transaction spends it.
    pub(super) fn refund_receipts(&self, account: &Account) -> Vec<([u8; 32], bool)> {
        let conn = rusqlite::Connection::open(&self.path).unwrap();
        let mut statement = conn
            .prepare(
                "SELECT n.nf, EXISTS(SELECT 1 FROM ironwood_received_note_spends s
                     JOIN transactions t ON t.id_tx = s.transaction_id
                     WHERE s.ironwood_received_note_id = n.id AND t.mined_height IS NOT NULL)
                 FROM ironwood_received_notes n
                 JOIN ironwood_one_time_keys k ON k.id = n.one_time_key_id
                 JOIN accounts a ON a.id = n.account_id
                 WHERE a.uuid = ?1 AND k.purpose = 0 ORDER BY n.id",
            )
            .unwrap();
        let rows = statement
            .query_map([account.id.expose_uuid().as_bytes()], |r| {
                Ok((r.get::<_, [u8; 32]>(0)?, r.get::<_, bool>(1)?))
            })
            .unwrap();
        rows.collect::<Result<_, _>>().unwrap()
    }

    /// The app's spendable plus pending total for `account`, as the home screen reads it.
    pub(super) fn balance(&self, account: &Account) -> u64 {
        crate::api::sync::get_balance(self.path.clone(), "main".into(), account.uuid.clone())
            .unwrap()
            .total
    }

    /// The app's transaction history for `account`.
    pub(super) fn history(&self, account: &Account) -> Vec<crate::api::sync::TransactionInfo> {
        crate::api::sync::get_transaction_history(
            self.path.clone(),
            "main".into(),
            None,
            account.uuid.clone(),
        )
        .unwrap()
    }

    /// The newest transaction the app built and stored, with its raw bytes.
    pub(super) fn last_built(&self) -> (Transaction, Vec<u8>) {
        let conn = rusqlite::Connection::open(&self.path).unwrap();
        let raw: Vec<u8> = conn
            .query_row(
                "SELECT raw FROM transactions WHERE raw IS NOT NULL ORDER BY id_tx DESC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .unwrap();
        let branch = zcash_protocol::consensus::BranchId::for_height(
            &NETWORK,
            BlockHeight::from(self.scanned + 1),
        );
        (Transaction::read(&raw[..], branch).unwrap(), raw)
    }
}

/// Runs `recover_with_transport` over `transport` with the generation the production entry
/// point captures and the wallet's own descriptor store, ending it at `budget` as
/// `recover` does.
pub(super) fn run_worker<T: Transport>(
    path: &str,
    transport: &T,
    manual: Option<Option<u64>>,
    budget: Duration,
) -> Result<Round, RecoveryError> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let generation = CANCEL.load(Ordering::SeqCst);
            let deadline = tokio::time::Instant::now() + budget;
            tokio::time::timeout_at(
                deadline,
                recover_with_transport(
                    path,
                    NETWORK,
                    manual,
                    ORIGIN,
                    transport,
                    &DescriptorTable::new(path, generation),
                    generation,
                    deadline,
                ),
            )
            .await
            .map_err(|_| RecoveryError::from("Swap recovery round timed out."))?
        })
}
