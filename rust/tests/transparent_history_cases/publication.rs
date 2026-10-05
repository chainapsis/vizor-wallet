//! The private profile's transparent PIR service: a publisher that turns the
//! regtest chain into a real transparent shard set, and an in-process shard
//! server Vizor recovers from over plain HTTP on loopback.
//!
//! Adapted from the adapter's end-to-end fixture
//! (`zakura/pir-transparent/tests/fixture/mod.rs` in wallet-libraries at
//! bdebaffcb), through wallet-pir's public APIs at 648264bb only. Events are
//! extracted from zcashd's verbose blocks with the rules of wallet-pir's
//! `transparent-filter-server/src/extract.rs` (that crate reads the node's
//! RocksDB, so it cannot be reused here): every output script that is a filter
//! element, coinbase outputs included, and every non-coinbase input under the
//! script of the output it consumes, each with the v11 transaction metadata.
//!
//! The publication is one unsealed tail shard, id 0, covering `[1, tip - lag]`
//! and republished with a new revision whenever that range or its terminal
//! block changes, so the H12 reorg republishes cleanly. The adapter accepts
//! only Zcash mainnet maps, so the map, manifest and filter keys carry
//! mainnet's network label and genesis hash, as the adapter's fixture does;
//! every block hash from height 1 is the real regtest one, and shard 0's parent
//! is the real regtest genesis, which the map's shape check never compares to
//! the declared genesis and which lies below every account's floor.
//!
//! One listener serves the whole run, so the origin a companion binds never
//! changes; the publication behind it is swapped. Every request is checked as
//! it arrives: it must take one of the service's routes, carry no query string,
//! and carry none of Alice's scripts (bytes or hex) in its path, headers or
//! body. Only route counts and violations are kept.

use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, OnceLock, PoisonError, RwLock,
    },
};

use axum::{
    body::Body,
    extract::{Request, State},
    http::{Method, StatusCode},
    response::{IntoResponse, Response},
    Router,
};
use regex::Regex;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use tower::ServiceExt as _;
use transparent_events::{
    FeeState, ReceiveEvent, SpendEvent, TransactionMetadata, TransparentEvent, Txid,
};
use transparent_filter::{
    filter_hash, BlockHash, ScriptBytes, SealParameters, ShardMap, ShardMapEntry,
};
use transparent_shard::build::build_shard;
use transparent_shard::layout::{Geometry, RECENT_4K};
use transparent_shard::manifest::{
    ManifestLayout, ManifestOccupancy, ManifestSeal, ShardManifest, TableGeometry, SCHEMA,
};
use transparent_shard_server::service::{router, ServiceConfig, ServiceState};
use transparent_shard_server::shardset::{ShardSet, DEFAULT_RETAIN_REVISIONS};

use crate::chain::rpc_at;

/// The tail shard's geometry: the smallest one a build publishes.
const GEOMETRY: &Geometry = &RECENT_4K;

/// The adapter fixture's seal thresholds. The tail is never sealed.
const SEAL: SealParameters = SealParameters {
    max_scripts: 2_048,
    max_page_rows: 1_024,
    max_txids: 0,
};

/// Every route the service serves a wallet, with its method (the adapter
/// end-to-end test's expression).
const ROUTES: &str = r"^(GET /v1/(filters/shards(/[0-9]+/filter)?|shards/init|shards/[0-9]+/revisions/[0-9a-f]{64}/(manifest|setup/(directory|pages)/[0-9]+))|POST /v1/shards/[0-9]+/revisions/[0-9a-f]{64}/query/(directory|pages))$";

/// Publications kept on disk: the one served and the one before it.
const KEEP_PUBLICATIONS: u32 = 2;

static GLOBAL: OnceLock<Publisher> = OnceLock::new();

/// The run's publisher, once the private profile installed one.
pub fn global() -> Option<&'static Publisher> {
    GLOBAL.get()
}

/// Makes `publisher` the run's publisher. Once per process.
pub fn install(publisher: Publisher) -> &'static Publisher {
    assert!(
        GLOBAL.set(publisher).is_ok(),
        "a transparent PIR publisher is already installed"
    );
    GLOBAL.get().unwrap()
}

/// One extracted block: its height, display hash and indexed events.
struct BlockEvents {
    height: u64,
    hash: String,
    events: Vec<(ScriptBytes, TransparentEvent)>,
}

struct Chainview {
    blocks: Vec<BlockEvents>,
    /// Every output seen, by internal txid and index: value and script.
    /// Outputs of orphaned blocks stay; nothing can name them again.
    prevouts: HashMap<([u8; 32], u32), (u64, Vec<u8>)>,
    lag: u64,
    revision: u32,
    /// The (end, terminal hash) of the publication served.
    published: Option<(u64, String)>,
}

/// What the server shares with its request handler.
struct Shared {
    current: RwLock<Option<Router>>,
    fail_queries: AtomicBool,
    routes: Regex,
    /// Alice's public key hashes, raw and as lower- and upper-case hex.
    watched: RwLock<(HashSet<Vec<u8>>, HashSet<Vec<u8>>)>,
    counts: Mutex<BTreeMap<String, usize>>,
    violations: Mutex<Vec<String>>,
}

pub struct Publisher {
    runtime: tokio::runtime::Runtime,
    rpc_port: u16,
    dir: PathBuf,
    url: String,
    chain: Mutex<Chainview>,
    shared: Arc<Shared>,
}

impl Publisher {
    /// Binds one loopback listener for the whole run and serves nothing until
    /// the first [`catch_up`](Self::catch_up). Publications go under `dir`.
    pub fn start(rpc_port: u16, dir: &Path) -> Self {
        std::fs::create_dir_all(dir).expect("publication dir");
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("publisher runtime");
        let shared = Arc::new(Shared {
            current: RwLock::new(None),
            fail_queries: AtomicBool::new(false),
            routes: Regex::new(ROUTES).unwrap(),
            watched: RwLock::default(),
            counts: Mutex::default(),
            violations: Mutex::default(),
        });
        let app = Router::new().fallback(dispatch).with_state(shared.clone());
        let url = runtime.block_on(async move {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
                .await
                .expect("bind the transparent PIR listener");
            let url = format!("http://{}", listener.local_addr().unwrap());
            tokio::spawn(async move {
                axum::serve(listener, app).await.unwrap();
            });
            url
        });
        eprintln!("[tpir] serving transparent PIR on {url}");
        Publisher {
            runtime,
            rpc_port,
            dir: dir.to_path_buf(),
            url,
            chain: Mutex::new(Chainview {
                blocks: Vec::new(),
                prevouts: HashMap::new(),
                lag: 0,
                revision: 0,
                published: None,
            }),
            shared,
        }
    }

    /// The service origin, stable for the run.
    pub fn url(&self) -> &str {
        &self.url
    }

    /// Alice's scripts, which no request may carry. Each derived script is a
    /// P2PKH script, so a request carrying one carries its public key hash.
    pub fn watch(&self, scripts: &[Vec<u8>]) {
        let hashes: HashSet<Vec<u8>> = scripts
            .iter()
            .map(|script| match script.as_slice() {
                [0x76, 0xa9, 20, hash @ .., 0x88, 0xac] if hash.len() == 20 => hash.to_vec(),
                other => other.to_vec(),
            })
            .collect();
        let hexes = hashes
            .iter()
            .flat_map(|hash| [hex::encode(hash), hex::encode_upper(hash)])
            .map(String::into_bytes)
            .collect();
        *self
            .shared
            .watched
            .write()
            .unwrap_or_else(PoisonError::into_inner) = (hashes, hexes);
    }

    /// Republishes when the chain moved: drops cached blocks the best chain
    /// no longer holds (a reorg), extracts new ones, and serves `[1, tip -
    /// lag]` under a new revision. A no-op when that range and its terminal
    /// block are unchanged.
    pub fn catch_up(&self) {
        let mut chain = self.chain.lock().unwrap_or_else(PoisonError::into_inner);
        let tip = self.rpc("getblockcount", json!([])).as_u64().unwrap();
        while let Some(last) = chain.blocks.last() {
            if last.height <= tip && self.block_hash(last.height) == last.hash {
                break;
            }
            chain.blocks.pop();
        }
        let from = chain.blocks.last().map_or(1, |b| b.height + 1);
        for height in from..=tip {
            let hash = self.block_hash(height);
            let block = self.rpc("getblock", json!([hash, 2]));
            let events = block_events(&block, height as u32, &mut chain.prevouts);
            chain.blocks.push(BlockEvents {
                height,
                hash,
                events,
            });
        }
        let end = tip.saturating_sub(chain.lag).max(1);
        let terminal = chain.blocks[end as usize - 1].hash.clone();
        if chain.published.as_ref() == Some(&(end, terminal.clone())) {
            return;
        }
        chain.revision += 1;
        let revision = chain.revision;
        let events: Vec<_> = chain
            .blocks
            .iter()
            .take_while(|b| b.height <= end)
            .flat_map(|b| b.events.iter().cloned())
            .collect();
        let hashes: Vec<String> = std::iter::once(self.block_hash(0))
            .chain(chain.blocks.iter().map(|b| b.hash.clone()))
            .collect();
        let dir = self.dir.join(format!("publication-{revision}"));
        publish(&dir, end, revision, &events, |height| {
            BlockHash::from_display_hex(&hashes[height as usize]).expect("a block hash")
        });
        let set = ShardSet::open(&dir, DEFAULT_RETAIN_REVISIONS).expect("a verified shard set");
        let app = self.runtime.block_on(async move {
            router(ServiceState::build(set, ServiceConfig::default()).expect("a shard service"))
        });
        *self
            .shared
            .current
            .write()
            .unwrap_or_else(PoisonError::into_inner) = Some(app);
        chain.published = Some((end, terminal));
        if revision > KEEP_PUBLICATIONS {
            let _ = std::fs::remove_dir_all(
                self.dir
                    .join(format!("publication-{}", revision - KEEP_PUBLICATIONS)),
            );
        }
        eprintln!(
            "[tpir] publication {revision}: [1, {end}], {} events, tip {tip}",
            events.len()
        );
    }

    /// Publishes only through `tip - blocks` from the next
    /// [`catch_up`](Self::catch_up) on (H13, private profile).
    pub fn set_lag(&self, blocks: u64) {
        self.chain
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .lag = blocks;
    }

    /// Answers every private query with a 500 while set (H13, private
    /// profile). Not a 503: that is a capacity refusal the wallet waits on.
    pub fn fail_queries(&self, fail: bool) {
        self.shared.fail_queries.store(fail, Ordering::SeqCst);
    }

    /// Every privacy violation seen: an unknown route, a query string, or a
    /// watched script in a request. Includes a missing positive control: no
    /// private query at all, or a script the check would not have caught.
    pub fn privacy_violations(&self) -> Vec<String> {
        let mut violations = self
            .shared
            .violations
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        let counts = self.route_counts();
        if !counts.keys().any(|route| route.starts_with("POST ")) {
            violations.push("no private query reached the service".into());
        }
        let watched = self
            .shared
            .watched
            .read()
            .unwrap_or_else(PoisonError::into_inner);
        match watched.0.iter().next() {
            Some(probe) => {
                let script = [&[0x76, 0xa9, 20][..], probe, &[0x88, 0xac]].concat();
                if !carries(&watched, &script)
                    || !carries(
                        &watched,
                        format!("/{}", hex::encode_upper(probe)).as_bytes(),
                    )
                {
                    violations.push("the script check would miss a watched script".into());
                }
            }
            None => violations.push("no watched script to check requests against".into()),
        }
        violations
    }

    /// Requests received, by method and route template.
    pub fn route_counts(&self) -> BTreeMap<String, usize> {
        self.shared
            .counts
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }

    fn rpc(&self, method: &str, params: Value) -> Value {
        rpc_at(self.rpc_port, method, params).unwrap_or_else(|e| panic!("publisher {e}"))
    }

    fn block_hash(&self, height: u64) -> String {
        self.rpc("getblockhash", json!([height]))
            .as_str()
            .unwrap()
            .to_string()
    }
}

fn carries(watched: &(HashSet<Vec<u8>>, HashSet<Vec<u8>>), bytes: &[u8]) -> bool {
    bytes.windows(20).any(|window| watched.0.contains(window))
        || bytes.windows(40).any(|window| watched.1.contains(window))
}

/// `path` with shard ids, revisions and segments elided.
fn template(path: &str) -> String {
    static REVISION: OnceLock<Regex> = OnceLock::new();
    static NUMBER: OnceLock<Regex> = OnceLock::new();
    let path = REVISION
        .get_or_init(|| Regex::new(r"[0-9a-f]{64}").unwrap())
        .replace_all(path, "{rev}");
    NUMBER
        .get_or_init(|| Regex::new(r"/[0-9]+(/|$)").unwrap())
        .replace_all(&path, "/{n}$1")
        .into_owned()
}

/// Checks and counts one request, applies the armed fault, then hands it to
/// the publication being served.
async fn dispatch(State(shared): State<Arc<Shared>>, request: Request) -> Response {
    let (parts, body) = request.into_parts();
    let body = axum::body::to_bytes(body, usize::MAX)
        .await
        .unwrap_or_default();
    let path = parts.uri.path().to_owned();
    let line = format!("{} {path}", parts.method);
    {
        let mut problems = Vec::new();
        if !shared.routes.is_match(&line) {
            problems.push(format!("unexpected route {}", template(&line)));
        }
        if parts.uri.query().is_some() {
            problems.push(format!("a query string on {}", template(&line)));
        }
        let watched = shared
            .watched
            .read()
            .unwrap_or_else(PoisonError::into_inner);
        if carries(&watched, path.as_bytes()) {
            problems.push(format!(
                "a watched script in the path of {}",
                template(&line)
            ));
        }
        if carries(&watched, &body) {
            problems.push(format!(
                "a watched script in the body of {}",
                template(&line)
            ));
        }
        if parts.headers.iter().any(|(name, value)| {
            carries(&watched, name.as_str().as_bytes()) || carries(&watched, value.as_bytes())
        }) {
            problems.push(format!(
                "a watched script in a header of {}",
                template(&line)
            ));
        }
        *shared
            .counts
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .entry(template(&line))
            .or_default() += 1;
        shared
            .violations
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .extend(problems);
    }
    if parts.method == Method::POST
        && path.contains("/query/")
        && shared.fail_queries.load(Ordering::SeqCst)
    {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }
    let current = shared
        .current
        .read()
        .unwrap_or_else(PoisonError::into_inner)
        .clone();
    match current {
        Some(app) => match app
            .oneshot(Request::from_parts(parts, Body::from(body)))
            .await
        {
            Ok(response) => response,
            Err(never) => match never {},
        },
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

fn zat(value: &Value) -> i64 {
    value
        .as_i64()
        .unwrap_or_else(|| panic!("an integer zatoshi amount, got {value}"))
}

fn internal(display_hex: &str) -> [u8; 32] {
    let mut bytes: [u8; 32] = hex::decode(display_hex)
        .expect("hex txid")
        .try_into()
        .expect("32-byte txid");
    bytes.reverse();
    bytes
}

/// Every indexed event of one verbose (`getblock <hash> 2`) block at `height`,
/// recording its outputs in `prevouts` first so same-block spends resolve.
fn block_events(
    block: &Value,
    height: u32,
    prevouts: &mut HashMap<([u8; 32], u32), (u64, Vec<u8>)>,
) -> Vec<(ScriptBytes, TransparentEvent)> {
    let transactions = block["tx"].as_array().expect("a verbose block");
    for tx in transactions {
        let txid = internal(tx["txid"].as_str().unwrap());
        for vout in tx["vout"].as_array().unwrap() {
            let script = hex::decode(vout["scriptPubKey"]["hex"].as_str().unwrap()).unwrap();
            prevouts.insert(
                (txid, vout["n"].as_u64().unwrap() as u32),
                (zat(&vout["valueZat"]) as u64, script),
            );
        }
    }
    let mut events = Vec::new();
    for (transaction_index, tx) in transactions.iter().enumerate() {
        let txid = Txid(internal(tx["txid"].as_str().unwrap()));
        let transaction_index = u16::try_from(transaction_index).expect("a u16 transaction index");
        let vin = tx["vin"].as_array().unwrap();
        let vout = tx["vout"].as_array().unwrap();
        let coinbase = vin.iter().any(|input| input.get("coinbase").is_some());
        // (input index, spent outpoint, its value and script)
        let spent: Vec<(u32, ([u8; 32], u32), (u64, Vec<u8>))> = vin
            .iter()
            .enumerate()
            .filter(|(_, input)| input.get("coinbase").is_none())
            .map(|(index, input)| {
                let outpoint = (
                    internal(input["txid"].as_str().unwrap()),
                    input["vout"].as_u64().unwrap() as u32,
                );
                let prevout = prevouts
                    .get(&outpoint)
                    .cloned()
                    .unwrap_or_else(|| panic!("previous output of {} is unknown", tx["txid"]));
                (index as u32, outpoint, prevout)
            })
            .collect();
        let empty = vec![];
        let orchard = &tx["orchard"];
        let has_shielded_components = [
            &tx["vShieldedSpend"],
            &tx["vShieldedOutput"],
            &orchard["actions"],
            &tx["vjoinsplit"],
        ]
        .iter()
        .any(|list| !list.as_array().unwrap_or(&empty).is_empty());
        let fee = if coinbase {
            FeeState::NotApplicable
        } else {
            let sprout: i64 = tx["vjoinsplit"]
                .as_array()
                .unwrap_or(&empty)
                .iter()
                .map(|js| zat(&js["vpub_newZat"]) - zat(&js["vpub_oldZat"]))
                .sum();
            let fee = spent
                .iter()
                .map(|(_, _, (value, _))| *value as i64)
                .sum::<i64>()
                - vout.iter().map(|o| zat(&o["valueZat"])).sum::<i64>()
                + tx.get("valueBalanceZat").map_or(0, zat)
                + orchard.get("valueBalanceZat").map_or(0, zat)
                + sprout;
            FeeState::Exact(u64::try_from(fee).expect("a non-negative fee"))
        };
        let metadata = TransactionMetadata {
            fee,
            transparent_input_count: spent.len() as u32,
            has_shielded_components,
        };
        metadata
            .validate(coinbase)
            .expect("valid transaction metadata");
        for output in vout {
            let script = ScriptBytes::new(
                hex::decode(output["scriptPubKey"]["hex"].as_str().unwrap()).unwrap(),
            );
            if !script.is_filter_element() {
                continue;
            }
            events.push((
                script,
                TransparentEvent::Receive(ReceiveEvent {
                    metadata: Some(metadata),
                    height,
                    txid,
                    transaction_index,
                    output_index: output["n"].as_u64().unwrap() as u32,
                    value: zat(&output["valueZat"]) as u64,
                    coinbase,
                }),
            ));
        }
        for (input_index, (spent_txid, spent_index), (_, script)) in spent {
            let script = ScriptBytes::new(script);
            if !script.is_filter_element() {
                continue;
            }
            events.push((
                script,
                TransparentEvent::Spend(SpendEvent {
                    metadata: Some(metadata),
                    height,
                    spending_txid: txid,
                    transaction_index,
                    input_index,
                    spent_txid: Txid(spent_txid),
                    spent_output_index: spent_index,
                }),
            ));
        }
    }
    events
}

/// Writes a publishable set of one unsealed tail shard, id 0, over `[1, end]`
/// at `revision` to `dir`: one directory per manifest digest and the map in
/// `shards.json`, labelled for mainnet (see the module docs). `hash` gives the
/// block hash at a height.
fn publish(
    dir: &Path,
    end: u64,
    revision: u32,
    events: &[(ScriptBytes, TransparentEvent)],
    hash: impl Fn(u64) -> BlockHash,
) {
    let genesis = BlockHash::from_display_hex(transparent_filter::MAINNET_GENESIS_DISPLAY)
        .expect("mainnet's genesis hash");
    let (shard_id, start) = (0u64, 1u64);
    let built = build_shard(
        shard_id,
        start,
        end,
        genesis,
        hash(end),
        transparent_filter::RANGE_PROFILE,
        GEOMETRY,
        events,
    )
    .expect("a buildable shard");
    let segments = |tables: &[Vec<u8>], rows: u64, row_bytes: usize| -> Vec<TableGeometry> {
        tables
            .iter()
            .map(|segment| TableGeometry {
                rows,
                row_bytes: row_bytes as u32,
                sha256: hex::encode(Sha256::digest(segment)),
            })
            .collect()
    };
    let manifest = ShardManifest {
        schema: SCHEMA.to_string(),
        profile: transparent_filter::RANGE_PROFILE.to_string(),
        geometry: GEOMETRY.name.to_string(),
        network: transparent_filter::NETWORK.to_string(),
        genesis_hash: transparent_filter::MAINNET_GENESIS_DISPLAY.to_string(),
        shard_id,
        start_height: start,
        end_height: end,
        parent_block_hash: hash(start - 1).to_display_hex(),
        terminal_block_hash: hash(end).to_display_hex(),
        tag_salt_counter: built.tag_salt_counter,
        parent_manifest_digest: String::new(),
        sealed: false,
        revision,
        supersedes: String::new(),
        seal: ManifestSeal {
            scripts_target: SEAL.max_scripts,
            scripts_capacity: SEAL.max_scripts * 2,
            page_rows_target: SEAL.max_page_rows,
            page_rows_capacity: SEAL.max_page_rows * 2,
        },
        layout: ManifestLayout {
            max_script_bytes: transparent_shard::MAX_SCRIPT_BYTES as u32,
            inline_events: transparent_shard::INLINE_EVENTS,
            events_per_page: transparent_shard::EVENTS_PER_PAGE,
            page_row_header_bytes: transparent_shard::PAGE_ROW_HEADER_BYTES as u32,
            page_entry_header_bytes: transparent_shard::PAGE_ENTRY_HEADER_BYTES as u32,
            directory_choices: transparent_shard::build::DIRECTORY_CHOICES as u32,
        },
        filter_hash: filter_hash(built.filter.as_slice()).to_display_hex(),
        directory_segments: segments(
            &built.directory,
            GEOMETRY.directory_rows,
            GEOMETRY.directory_row_bytes,
        ),
        page_segments: segments(&built.pages, GEOMETRY.page_rows, GEOMETRY.page_row_bytes),
        occupancy: ManifestOccupancy {
            scripts: built.scripts,
            page_rows: built.page_rows,
            fragments: built.fragments,
            events: built.events,
            blocks: end - start + 1,
            txids: 0,
            excluded_scripts: built.excluded_scripts,
        },
        txid_display: None,
        directory_choice: None,
    };
    let digest = manifest.digest();
    let shard_dir = dir.join(&digest);
    std::fs::create_dir_all(&shard_dir).unwrap();
    std::fs::write(shard_dir.join("manifest.json"), manifest.canonical_bytes()).unwrap();
    std::fs::write(shard_dir.join("filter.bin"), built.filter.as_slice()).unwrap();
    for (index, segment) in built.directory.iter().enumerate() {
        std::fs::write(shard_dir.join(format!("directory.{index}.bin")), segment).unwrap();
    }
    for (index, segment) in built.pages.iter().enumerate() {
        std::fs::write(shard_dir.join(format!("pages.{index}.bin")), segment).unwrap();
    }
    let map = ShardMap {
        genesis_hash: transparent_filter::MAINNET_GENESIS_DISPLAY.to_string(),
        network: transparent_filter::NETWORK.to_string(),
        profile: transparent_filter::RANGE_PROFILE.to_string(),
        range_envelope_version: transparent_filter::RANGE_ENVELOPE_VERSION,
        start_height: start,
        seal: [(GEOMETRY.name.to_string(), SEAL)].into_iter().collect(),
        shards: vec![ShardMapEntry {
            shard_id,
            geometry: GEOMETRY.name.to_string(),
            start_height: start,
            end_height: end,
            parent_block_hash: manifest.parent_block_hash.clone(),
            terminal_block_hash: manifest.terminal_block_hash.clone(),
            filter_hash: manifest.filter_hash.clone(),
            scripts: built.scripts,
            page_rows: built.page_rows,
            txids: 0,
            directory_segments: built.directory_segments(),
            page_segments: built.page_segments(),
            txid_segments: None,
            manifest_digest: digest,
            revision,
            sealed: false,
        }],
    };
    map.check_shape().expect("a well-formed map");
    std::fs::write(dir.join("shards.json"), serde_json::to_vec(&map).unwrap()).unwrap();
}
