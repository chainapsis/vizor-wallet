//! Private txid display lookups against the tiered display publication.
//!
//! A stand-in for wallet-pir's `transparent-txid-client`, with its announced
//! API: [`TxidTransport`], [`TxidRequest`], [`TxidReply`],
//! [`TxidDisplayClient::lookup`], [`TxidLookup`] and [`TxidError`]. It follows
//! the reference client in wallet-pir
//! (`transparent-shard-server/examples/support/txdisplay.rs`) over the wallet-pir
//! crates the wallet already depends on, restating the few display-layout
//! constants that exist only on wallet-pir main. Replace this module with the
//! crate's re-export from `zakura-pir-transparent` once the wallet-libraries
//! pin carries it.
//!
//! A lookup is the init document and the map (cached), the shard's manifest
//! and its setup (cached per revision), then a fixed transcript: exactly two
//! directory queries, even when both candidate rows coincide, and exactly
//! `pages` page queries for a paged record. Requests name the tier, shard,
//! revision, table and segment, never the txid or a selected row. Placement
//! comes from the caller's chain; an unknown height sends nothing.
//!
//! Every failure is an error, never `Absent`. A stale revision (409) refreshes
//! the map and retries the lookup once. Nothing here logs.

use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::time::{Duration, Instant};

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use http::Method;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use transparent_events::Txid;
use transparent_native::{NativeScheme, TableProfile};
use transparent_shard::txid::{self as codec, TransparentDisplayRecord};

/// The display shard layout this client reads.
pub(crate) const DISPLAY_SCHEMA: &str = "transparent-txid-display-shard-v1";
/// Domain of the bucket hash.
const BUCKET_DOMAIN: &[u8] = b"transparent-txid-display/bucket/v1";
/// Decoder bound on buckets per shard.
const MAX_BUCKETS: u32 = 64;
/// Payload bytes of one page fragment.
const FRAGMENT_BYTES: u32 = (codec::ROW_BYTES - 4 - 2 - 40) as u32;
/// Directory rows each lookup queries.
const DIRECTORY_CHOICES: u32 = 2;
/// A cached map older than this is refetched before a lookup.
const MAP_TTL: Duration = Duration::from_secs(60);

/// Response bounds by route. Queries are bounded by their exact size.
const INIT_LIMIT: usize = 256 << 10;
const MAP_LIMIT: usize = 4 << 20;
const MANIFEST_LIMIT: usize = 1 << 20;
const SETUP_LIMIT: usize = 1 << 20;
/// Pages one record may span: a 2 MB transaction's outputs, with slack.
const MAX_PAGES: u32 = 1_024;

/// The display geometries this client knows: both tables of a shard have the
/// same row count and 4,096-byte rows.
const GEOMETRIES: &[(&str, u64)] = &[("txid-2k", 2_048), ("txid-4k", 4_096)];

fn geometry_rows(name: &str) -> Option<u64> {
    GEOMETRIES
        .iter()
        .find(|(known, _)| *known == name)
        .map(|(_, rows)| *rows)
}

/// The tier a shard belongs to, which its routes name.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) enum Tier {
    Archive,
    Recent,
}

impl Tier {
    fn as_str(self) -> &'static str {
        match self {
            Tier::Archive => "archive",
            Tier::Recent => "recent",
        }
    }
}

/// One private table of a display shard.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub(crate) enum DisplayTable {
    /// The directory of one bucket.
    Directory(u32),
    /// The shard's overflow pages.
    Pages,
}

impl DisplayTable {
    /// Wire and binding name.
    pub(crate) fn label(self) -> String {
        match self {
            DisplayTable::Directory(bucket) => format!("directory-{bucket}"),
            DisplayTable::Pages => "pages".to_owned(),
        }
    }

    /// The native profile's table name.
    fn kind(self) -> &'static str {
        match self {
            DisplayTable::Directory(_) => "txdirectory",
            DisplayTable::Pages => "txpages",
        }
    }
}

/// One request, as the service routes it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum TxidRoute {
    Init,
    Map,
    Manifest {
        shard_id: u64,
        digest: String,
    },
    Setup {
        tier: Tier,
        shard_id: u64,
        digest: String,
        table: DisplayTable,
        segment: u32,
    },
    Query {
        tier: Tier,
        shard_id: u64,
        digest: String,
        table: DisplayTable,
    },
}

/// One request a lookup sends.
#[derive(Clone, Debug)]
pub(crate) struct TxidRequest {
    pub(crate) route: TxidRoute,
    /// The opaque query body; empty for reads.
    pub(crate) body: Vec<u8>,
    /// Largest successful body this request may receive.
    pub(crate) limit: usize,
}

impl TxidRequest {
    fn read(route: TxidRoute, limit: usize) -> Self {
        Self {
            route,
            body: Vec::new(),
            limit,
        }
    }

    /// Queries post their body; everything else is a read.
    pub(crate) fn method(&self) -> Method {
        match self.route {
            TxidRoute::Query { .. } => Method::POST,
            _ => Method::GET,
        }
    }

    pub(crate) fn path(&self) -> String {
        match &self.route {
            TxidRoute::Init => "/v1/txid/init".to_owned(),
            TxidRoute::Map => "/v1/txid/shards".to_owned(),
            TxidRoute::Manifest { shard_id, digest } => {
                format!("/v1/txid/shards/{shard_id}/revisions/{digest}/manifest")
            }
            TxidRoute::Setup {
                tier,
                shard_id,
                digest,
                table,
                segment,
            } => format!(
                "/v1/txid/{}/shards/{shard_id}/revisions/{digest}/setup/{}/{segment}",
                tier.as_str(),
                table.label()
            ),
            TxidRoute::Query {
                tier,
                shard_id,
                digest,
                table,
            } => format!(
                "/v1/txid/{}/shards/{shard_id}/revisions/{digest}/query/{}",
                tier.as_str(),
                table.label()
            ),
        }
    }

    /// The path with every identifier elided: all a log line may say.
    pub(crate) fn template(&self) -> &'static str {
        match self.route {
            TxidRoute::Init => "/v1/txid/init",
            TxidRoute::Map => "/v1/txid/shards",
            TxidRoute::Manifest { .. } => "/v1/txid/shards/{id}/revisions/{rev}/manifest",
            TxidRoute::Setup { .. } => {
                "/v1/txid/{tier}/shards/{id}/revisions/{rev}/setup/{table}/{segment}"
            }
            TxidRoute::Query { .. } => "/v1/txid/{tier}/shards/{id}/revisions/{rev}/query/{table}",
        }
    }
}

/// A reply as it arrived.
#[derive(Clone, Debug, Default)]
pub(crate) struct TxidReply {
    pub(crate) status: u16,
    pub(crate) retry_after: Option<Duration>,
    /// The `x-txid-map-sha256` header.
    pub(crate) map_sha256: Option<String>,
    /// The body of a success; empty otherwise.
    pub(crate) body: Vec<u8>,
}

/// Why a transport delivered no reply. Carries no URL or body.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum TxidTransportError {
    /// The lookup is stopping: nothing was sent, or the reply is dropped.
    Cancelled,
    /// A successful body exceeded the request's limit.
    TooLarge,
    /// No whole reply within the transport's bound.
    Timeout,
    /// The route or connection failed.
    Failed,
}

/// Sends one request and returns its reply, of whatever status.
pub(crate) trait TxidTransport {
    fn send(&mut self, request: TxidRequest) -> Result<TxidReply, TxidTransportError>;
}

/// What a lookup found.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum TxidLookup {
    /// The record, from the named publication.
    Found {
        record: TransparentDisplayRecord,
        provenance: Provenance,
    },
    /// The publication covers the height but holds no record for the txid.
    Absent,
    /// No published shard covers the height, or the caller has none.
    /// Nothing was queried.
    PlacementUnknown,
    /// The service does not offer a display this client reads.
    Unsupported,
}

/// Which publication answered a lookup.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Provenance {
    pub(crate) map_sha256: String,
    pub(crate) shard_id: u64,
    pub(crate) manifest_digest: String,
    pub(crate) sealed: bool,
}

/// Why a lookup failed. Carries no txid, path, digest or body text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum TxidError {
    /// The service refused for capacity or is down.
    Unavailable { retry_after: Option<Duration> },
    /// The revision stayed stale after a map refresh.
    Stale,
    /// The service refused the request itself.
    Refused,
    /// A reply was malformed or contradicted the publication.
    Protocol(&'static str),
    /// The route or connection failed.
    Transport,
    /// The caller stopped the lookup.
    Cancelled,
}

impl TxidError {
    /// The variant, for logs.
    pub(crate) fn name(&self) -> &'static str {
        match self {
            TxidError::Unavailable { .. } => "unavailable",
            TxidError::Stale => "stale",
            TxidError::Refused => "refused",
            TxidError::Protocol(_) => "protocol",
            TxidError::Transport => "transport",
            TxidError::Cancelled => "cancelled",
        }
    }
}

fn protocol(what: &'static str) -> TxidError {
    TxidError::Protocol(what)
}

// ---- wire documents -------------------------------------------------------

#[derive(Deserialize)]
struct InitTable {
    rows: u64,
    row_bytes: u32,
    scheme: NativeScheme,
    setup_seed: u64,
}

#[derive(Deserialize)]
struct InitGeometry {
    name: String,
    txdirectory: InitTable,
    txpages: InitTable,
}

#[derive(Deserialize)]
struct InitDocument {
    schema: String,
    codec: String,
    bucket_domain: String,
    native_schema: String,
    geometries: Vec<InitGeometry>,
}

struct Init {
    supported: bool,
    geometries: HashMap<String, InitGeometry>,
}

#[derive(Clone, Deserialize)]
struct WireSeal {
    n_archive: u32,
    n_recent: u32,
}

#[derive(Clone, Deserialize)]
struct MapEntry {
    shard_id: u64,
    start_height: u64,
    end_height: u64,
    terminal_block_hash: String,
    geometry: String,
    n_buckets: u32,
    directory_segments: Vec<u32>,
    page_segments: u32,
    manifest_digest: String,
    revision: u32,
    sealed: bool,
}

impl MapEntry {
    fn tier(&self) -> Tier {
        if self.sealed {
            Tier::Archive
        } else {
            Tier::Recent
        }
    }
}

#[derive(Deserialize)]
struct DisplayMap {
    schema: String,
    network: String,
    seal: WireSeal,
    start_height: u64,
    first_shard_id: u64,
    shards: Vec<MapEntry>,
}

impl DisplayMap {
    fn check_shape(&self, network: &str) -> Result<(), TxidError> {
        if self.network != network {
            return Err(protocol("map network"));
        }
        let first = self.shards.first().ok_or(protocol("empty map"))?;
        if first.start_height != self.start_height || first.shard_id != self.first_shard_id {
            return Err(protocol("map start"));
        }
        let mut previous_end = None;
        for (index, shard) in self.shards.iter().enumerate() {
            let buckets = if shard.sealed {
                self.seal.n_archive
            } else {
                self.seal.n_recent
            };
            if shard.shard_id != self.first_shard_id + index as u64
                || shard.end_height < shard.start_height
                || previous_end.is_some_and(|end: u64| shard.start_height != end + 1)
                || geometry_rows(&shard.geometry).is_none()
                || shard.n_buckets == 0
                || shard.n_buckets > MAX_BUCKETS
                || shard.n_buckets != buckets
                || shard.directory_segments.len() != shard.n_buckets as usize
                || shard.directory_segments.contains(&0)
                || shard.page_segments == 0
                || !is_digest(&shard.manifest_digest)
                || (!shard.sealed && index + 1 != self.shards.len())
            {
                return Err(protocol("map shard"));
            }
            previous_end = Some(shard.end_height);
        }
        Ok(())
    }

    fn shard_for_height(&self, height: u64) -> Option<&MapEntry> {
        self.shards
            .iter()
            .find(|shard| (shard.start_height..=shard.end_height).contains(&height))
    }
}

#[derive(Deserialize, PartialEq, Eq)]
struct WireLayout {
    codec: String,
    inline_bytes: u32,
    row_bytes: u32,
    fragment_bytes: u32,
    directory_choices: u32,
    bucket_domain: String,
}

#[derive(Deserialize)]
struct WireTable {
    rows: u64,
    row_bytes: u32,
}

#[derive(Deserialize)]
struct WireBucket {
    bucket: u32,
    directory_segments: Vec<WireTable>,
}

#[derive(Deserialize)]
struct Manifest {
    schema: String,
    shard_id: u64,
    start_height: u64,
    end_height: u64,
    terminal_block_hash: String,
    sealed: bool,
    revision: u32,
    geometry: String,
    n_buckets: u32,
    layout: WireLayout,
    buckets: Vec<WireBucket>,
    page_segments: Vec<WireTable>,
}

impl Manifest {
    /// Whether this manifest is the one `entry` names, with this build's
    /// layout.
    fn matches(&self, entry: &MapEntry) -> bool {
        let rows = geometry_rows(&self.geometry);
        let layout = WireLayout {
            codec: codec::CODEC.to_owned(),
            inline_bytes: codec::INLINE_BYTES as u32,
            row_bytes: codec::ROW_BYTES as u32,
            fragment_bytes: FRAGMENT_BYTES,
            directory_choices: DIRECTORY_CHOICES,
            bucket_domain: String::from_utf8_lossy(BUCKET_DOMAIN).into_owned(),
        };
        let table_ok = |table: &WireTable| {
            Some(table.rows) == rows && table.row_bytes == codec::ROW_BYTES as u32
        };
        self.schema == DISPLAY_SCHEMA
            && self.layout == layout
            && self.shard_id == entry.shard_id
            && self.start_height == entry.start_height
            && self.end_height == entry.end_height
            && self.terminal_block_hash == entry.terminal_block_hash
            && self.sealed == entry.sealed
            && self.revision == entry.revision
            && self.geometry == entry.geometry
            && self.n_buckets == entry.n_buckets
            && self.buckets.len() == entry.n_buckets as usize
            && self.buckets.iter().enumerate().all(|(index, bucket)| {
                bucket.bucket == index as u32
                    && bucket.directory_segments.len() == entry.directory_segments[index] as usize
                    && bucket.directory_segments.iter().all(table_ok)
            })
            && self.page_segments.len() == entry.page_segments as usize
            && self.page_segments.iter().all(table_ok)
    }
}

struct CachedMap {
    map: DisplayMap,
    sha256: String,
    fetched: Instant,
}

struct Setup {
    public_params: Vec<u8>,
    epoch: [u8; 8],
}

// ---- the client -----------------------------------------------------------

/// Display lookups against one origin, with the public documents and derived
/// native profiles cached across lookups. Process-wide per origin: see
/// [`super::source`].
pub(crate) struct TxidDisplayClient {
    network: String,
    init: Option<Arc<Init>>,
    map: Option<CachedMap>,
    manifests: HashMap<String, Arc<Manifest>>,
    setups: HashMap<(String, DisplayTable, u32), Arc<Setup>>,
    profiles: HashMap<(String, &'static str), Arc<TableProfile>>,
    /// Private queries the last lookup sent.
    last_queries: u32,
}

/// Where a lookup's queries go, once placement and the manifest are known.
struct Located {
    entry: MapEntry,
    rows: u64,
    bucket: u32,
    map_sha256: String,
}

impl TxidDisplayClient {
    /// A client for a publication of `network` (`main`, `test`).
    pub(crate) fn new(network: &str) -> Self {
        Self {
            network: network.to_owned(),
            init: None,
            map: None,
            manifests: HashMap::new(),
            setups: HashMap::new(),
            profiles: HashMap::new(),
            last_queries: 0,
        }
    }

    /// Private queries the last lookup sent.
    pub(crate) fn last_queries(&self) -> u32 {
        self.last_queries
    }

    /// The digest of the map the client holds.
    pub(crate) fn map_sha256(&self) -> Option<&str> {
        self.map.as_ref().map(|cached| cached.sha256.as_str())
    }

    /// Looks up `txid` (protocol byte order), mined at `mined_height` on the
    /// caller's chain. `cancel` is checked before every request; the transport
    /// checks its own.
    pub(crate) fn lookup(
        &mut self,
        transport: &mut impl TxidTransport,
        txid: [u8; 32],
        mined_height: Option<u64>,
        cancel: &dyn Fn() -> bool,
    ) -> Result<TxidLookup, TxidError> {
        self.last_queries = 0;
        let Some(height) = mined_height else {
            return Ok(TxidLookup::PlacementUnknown);
        };
        match self.attempt(transport, Txid(txid), height, false, cancel) {
            Err(TxidError::Stale) => self.attempt(transport, Txid(txid), height, true, cancel),
            result => result,
        }
    }

    fn attempt(
        &mut self,
        transport: &mut impl TxidTransport,
        txid: Txid,
        height: u64,
        refresh: bool,
        cancel: &dyn Fn() -> bool,
    ) -> Result<TxidLookup, TxidError> {
        let init = self.init(transport, cancel)?;
        if !init.supported {
            return Ok(TxidLookup::Unsupported);
        }
        let stale = self.map.as_ref().is_none_or(|cached| {
            refresh
                || cached.fetched.elapsed() >= MAP_TTL
                || cached.map.shards.last().is_some_and(|last| height > last.end_height)
        });
        if stale {
            self.fetch_map(transport, cancel)?;
        }
        let cached = self.map.as_ref().ok_or(protocol("map"))?;
        let Some(entry) = cached.map.shard_for_height(height).cloned() else {
            return Ok(TxidLookup::PlacementUnknown);
        };
        let Some(rows) = geometry_rows(&entry.geometry) else {
            return Ok(TxidLookup::Unsupported);
        };
        if !init.geometries.contains_key(&entry.geometry) {
            return Ok(TxidLookup::Unsupported);
        }
        let located = Located {
            bucket: bucket(&txid, entry.n_buckets),
            map_sha256: cached.sha256.clone(),
            entry,
            rows,
        };
        let manifest = self.manifest(transport, &located.entry, cancel)?;

        // Directory phase: exactly two queries, whether or not they coincide.
        let table = DisplayTable::Directory(located.bucket);
        let segments = located.entry.directory_segments[located.bucket as usize];
        let candidates = candidate_rows(
            &txid,
            located.entry.shard_id,
            located.bucket,
            located.rows,
        );
        let decoded = self.queries(
            transport, &init, &located, table, segments, &candidates, cancel,
        )?;
        let directory: Vec<Vec<u8>> = decoded.into_values().collect();
        let Some(found) =
            codec::find_directory(&directory, txid).map_err(|_| protocol("directory"))?
        else {
            return Ok(TxidLookup::Absent);
        };
        let provenance = Provenance {
            map_sha256: located.map_sha256.clone(),
            shard_id: located.entry.shard_id,
            manifest_digest: located.entry.manifest_digest.clone(),
            sealed: located.entry.sealed,
        };
        if found.pages == 0 {
            let record = codec::assemble(&found, &[]).map_err(|_| protocol("record"))?;
            return checked(record, txid, provenance);
        }

        // Page phase: exactly `pages` queries, one per page of the extent.
        let page_segments = manifest.page_segments.len() as u64;
        let first = u64::from(found.first_page)
            .checked_sub(1)
            .ok_or(protocol("page locator"))?;
        let end = first + u64::from(found.pages);
        if found.pages > MAX_PAGES || end > page_segments * located.rows {
            return Err(protocol("page extent"));
        }
        let pages: Vec<u64> = (first..end).collect();
        let selected: Vec<u64> = pages.iter().map(|page| page % located.rows).collect();
        let decoded = self.queries(
            transport,
            &init,
            &located,
            DisplayTable::Pages,
            page_segments as u32,
            &selected,
            cancel,
        )?;
        let mut page_rows = Vec::with_capacity(pages.len());
        for page in pages {
            let key = ((page / located.rows) as usize, page % located.rows);
            page_rows.push(decoded.get(&key).cloned().ok_or(protocol("page row"))?);
        }
        let record = codec::assemble(&found, &page_rows).map_err(|_| protocol("record"))?;
        checked(record, txid, provenance)
    }

    fn init(
        &mut self,
        transport: &mut impl TxidTransport,
        cancel: &dyn Fn() -> bool,
    ) -> Result<Arc<Init>, TxidError> {
        if let Some(init) = &self.init {
            return Ok(init.clone());
        }
        let reply = send(
            transport,
            TxidRequest::read(TxidRoute::Init, INIT_LIMIT),
            cancel,
        )?;
        let document: InitDocument =
            serde_json::from_slice(&reply.body).map_err(|_| protocol("init"))?;
        let supported = document.schema == DISPLAY_SCHEMA
            && document.codec == codec::CODEC
            && document.bucket_domain.as_bytes() == BUCKET_DOMAIN
            && document.native_schema == transparent_shard::SCHEMA;
        let init = Arc::new(Init {
            supported,
            geometries: document
                .geometries
                .into_iter()
                .map(|geometry| (geometry.name.clone(), geometry))
                .collect(),
        });
        self.init = Some(init.clone());
        Ok(init)
    }

    fn fetch_map(
        &mut self,
        transport: &mut impl TxidTransport,
        cancel: &dyn Fn() -> bool,
    ) -> Result<(), TxidError> {
        let reply = send(
            transport,
            TxidRequest::read(TxidRoute::Map, MAP_LIMIT),
            cancel,
        )?;
        let sha256 = hex::encode(Sha256::digest(&reply.body));
        if reply
            .map_sha256
            .as_deref()
            .is_some_and(|header| header != sha256)
        {
            return Err(protocol("map digest header"));
        }
        let map: DisplayMap = serde_json::from_slice(&reply.body).map_err(|_| protocol("map"))?;
        if map.schema != DISPLAY_SCHEMA {
            // A publication this client cannot read is not a failure of it.
            self.map = None;
            return Err(protocol("map schema"));
        }
        map.check_shape(&self.network)?;
        self.map = Some(CachedMap {
            map,
            sha256,
            fetched: Instant::now(),
        });
        Ok(())
    }

    fn manifest(
        &mut self,
        transport: &mut impl TxidTransport,
        entry: &MapEntry,
        cancel: &dyn Fn() -> bool,
    ) -> Result<Arc<Manifest>, TxidError> {
        if let Some(manifest) = self.manifests.get(&entry.manifest_digest) {
            return Ok(manifest.clone());
        }
        let reply = send(
            transport,
            TxidRequest::read(
                TxidRoute::Manifest {
                    shard_id: entry.shard_id,
                    digest: entry.manifest_digest.clone(),
                },
                MANIFEST_LIMIT,
            ),
            cancel,
        )?;
        if hex::encode(Sha256::digest(&reply.body)) != entry.manifest_digest {
            return Err(protocol("manifest digest"));
        }
        let manifest: Manifest =
            serde_json::from_slice(&reply.body).map_err(|_| protocol("manifest"))?;
        if !manifest.matches(entry) {
            return Err(protocol("manifest placement"));
        }
        let manifest = Arc::new(manifest);
        // Revisions of the recent shard come and go; keep only the current set.
        if self.manifests.len() > 64 {
            self.manifests.clear();
            self.setups.clear();
        }
        self.manifests
            .insert(entry.manifest_digest.clone(), manifest.clone());
        Ok(manifest)
    }

    /// The native profile of `table` at the located geometry, checked against
    /// what the service declared.
    fn profile(
        &mut self,
        init: &Init,
        located: &Located,
        table: DisplayTable,
    ) -> Result<Arc<TableProfile>, TxidError> {
        let geometry = located.entry.geometry.clone();
        let key = (geometry.clone(), table.kind());
        let profile = match self.profiles.get(&key) {
            Some(profile) => profile.clone(),
            None => {
                // The native profile is the history kind's: history schema
                // and the table name. Only the binding is display-specific.
                let profile = Arc::new(
                    TableProfile::new(
                        transparent_shard::SCHEMA,
                        &geometry,
                        table.kind(),
                        located.rows,
                        codec::ROW_BYTES as u32,
                    )
                    .map_err(|_| protocol("native profile"))?,
                );
                self.profiles.insert(key, profile.clone());
                profile
            }
        };
        let served = init
            .geometries
            .get(&geometry)
            .map(|declared| match table {
                DisplayTable::Pages => &declared.txpages,
                DisplayTable::Directory(_) => &declared.txdirectory,
            })
            .ok_or(protocol("init geometry"))?;
        if served.scheme != profile.scheme
            || served.rows != located.rows
            || served.row_bytes != codec::ROW_BYTES as u32
            || served.setup_seed != setup_seed(&geometry, table.kind())
        {
            return Err(protocol("served parameters"));
        }
        Ok(profile)
    }

    fn setup(
        &mut self,
        transport: &mut impl TxidTransport,
        located: &Located,
        table: DisplayTable,
        segment: u32,
        segments: u32,
        scheme: &NativeScheme,
        cancel: &dyn Fn() -> bool,
    ) -> Result<Arc<Setup>, TxidError> {
        let entry = &located.entry;
        let key = (entry.manifest_digest.clone(), table, segment);
        if let Some(setup) = self.setups.get(&key) {
            return Ok(setup.clone());
        }
        let reply = send(
            transport,
            TxidRequest::read(
                TxidRoute::Setup {
                    tier: entry.tier(),
                    shard_id: entry.shard_id,
                    digest: entry.manifest_digest.clone(),
                    table,
                    segment,
                },
                SETUP_LIMIT,
            ),
            cancel,
        )?;
        let document: serde_json::Value =
            serde_json::from_slice(&reply.body).map_err(|_| protocol("setup"))?;
        let bucket = match table {
            DisplayTable::Directory(bucket) => serde_json::json!(bucket),
            DisplayTable::Pages => serde_json::Value::Null,
        };
        if document["manifest_digest"] != *entry.manifest_digest
            || document["shard_id"] != entry.shard_id
            || document["table"] != table.label()
            || document["bucket"] != bucket
            || document["segment"] != segment
            || document["segments"] != segments
            || document["geometry"] != *entry.geometry
        {
            return Err(protocol("setup identity"));
        }
        let public_params = B64
            .decode(
                document["public_params"]
                    .as_str()
                    .ok_or(protocol("setup params"))?,
            )
            .map_err(|_| protocol("setup params"))?;
        if public_params.len() != scheme.public_bytes
            || document["public_params_sha256"] != hex::encode(Sha256::digest(&public_params))
        {
            return Err(protocol("setup digest"));
        }
        let epoch: [u8; 8] = hex::decode(
            document["public_params_epoch"]
                .as_str()
                .ok_or(protocol("setup epoch"))?,
        )
        .ok()
        .and_then(|bytes| bytes.try_into().ok())
        .ok_or(protocol("setup epoch"))?;
        let setup = Arc::new(Setup {
            public_params,
            epoch,
        });
        self.setups.insert(key, setup.clone());
        Ok(setup)
    }

    /// One query per row in `rows`, in order, each across every segment of
    /// `table`. Returns the decoded rows by (segment, row).
    #[allow(clippy::too_many_arguments)]
    fn queries(
        &mut self,
        transport: &mut impl TxidTransport,
        init: &Init,
        located: &Located,
        table: DisplayTable,
        segments: u32,
        rows: &[u64],
        cancel: &dyn Fn() -> bool,
    ) -> Result<BTreeMap<(usize, u64), Vec<u8>>, TxidError> {
        let profile = self.profile(init, located, table)?;
        let mut setups = Vec::with_capacity(segments as usize);
        for segment in 0..segments {
            setups.push(self.setup(
                transport,
                located,
                table,
                segment,
                segments,
                &profile.scheme,
                cancel,
            )?);
        }
        let entry = &located.entry;
        let binding = transparent_shard::manifest::query_binding_for_schema(
            DISPLAY_SCHEMA,
            &entry.manifest_digest,
            &table.label(),
        );
        let stride = 16 + profile.scheme.response_bytes;
        let mut decoded = BTreeMap::new();
        for &row in rows {
            let (secret, upload) = profile
                .prepare(usize::try_from(row).map_err(|_| protocol("row"))?)
                .map_err(|_| protocol("prepare"))?;
            let mut body = binding.to_vec();
            body.extend(upload);
            let reply = send(
                transport,
                TxidRequest {
                    route: TxidRoute::Query {
                        tier: entry.tier(),
                        shard_id: entry.shard_id,
                        digest: entry.manifest_digest.clone(),
                        table,
                    },
                    body,
                    limit: setups.len() * stride,
                },
                cancel,
            )?;
            self.last_queries += 1;
            if reply.body.len() != setups.len() * stride {
                return Err(protocol("response length"));
            }
            for (segment, (frame, setup)) in reply
                .body
                .chunks_exact(stride)
                .zip(setups.iter())
                .enumerate()
            {
                if frame[..8] != binding || frame[8..16] != setup.epoch {
                    return Err(protocol("response binding"));
                }
                let plain = profile
                    .decode(&secret, &setup.public_params, &frame[16..])
                    .map_err(|_| protocol("decode"))?;
                decoded.insert((segment, row), plain);
            }
        }
        Ok(decoded)
    }
}

/// Sends `request` unless the lookup is stopping, and turns a non-success
/// status into the error the lookup reports.
fn send(
    transport: &mut impl TxidTransport,
    request: TxidRequest,
    cancel: &dyn Fn() -> bool,
) -> Result<TxidReply, TxidError> {
    if cancel() {
        return Err(TxidError::Cancelled);
    }
    let reply = transport.send(request).map_err(|error| match error {
        TxidTransportError::Cancelled => TxidError::Cancelled,
        TxidTransportError::TooLarge => protocol("oversized reply"),
        TxidTransportError::Timeout | TxidTransportError::Failed => TxidError::Transport,
    })?;
    if cancel() {
        return Err(TxidError::Cancelled);
    }
    match reply.status {
        200 => Ok(reply),
        409 => Err(TxidError::Stale),
        429 | 500..=599 => Err(TxidError::Unavailable {
            retry_after: reply.retry_after,
        }),
        _ => Err(TxidError::Refused),
    }
}

fn checked(
    record: TransparentDisplayRecord,
    txid: Txid,
    provenance: Provenance,
) -> Result<TxidLookup, TxidError> {
    if record.txid != txid {
        return Err(protocol("assembled another transaction"));
    }
    Ok(TxidLookup::Found { record, provenance })
}

fn is_digest(text: &str) -> bool {
    text.len() == 64 && text.bytes().all(|byte| byte.is_ascii_hexdigit())
}

/// The bucket `txid` belongs to among `n_buckets`.
fn bucket(txid: &Txid, n_buckets: u32) -> u32 {
    let digest = Sha256::new()
        .chain_update(BUCKET_DOMAIN)
        .chain_update(txid.0)
        .finalize();
    (u64::from_le_bytes(digest[..8].try_into().expect("eight bytes")) % u64::from(n_buckets)) as u32
}

/// The two candidate directory rows of `txid` inside its bucket's table.
fn candidate_rows(txid: &Txid, shard_id: u64, bucket: u32, rows: u64) -> [u64; 2] {
    std::array::from_fn(|choice| {
        let digest = Sha256::new()
            .chain_update(DISPLAY_SCHEMA)
            .chain_update(b"/directory/")
            .chain_update([choice as u8])
            .chain_update(shard_id.to_le_bytes())
            .chain_update(bucket.to_le_bytes())
            .chain_update(txid.0)
            .finalize();
        u64::from_le_bytes(digest[..8].try_into().expect("eight bytes")) % rows
    })
}

/// The published seed a table's public query setup derives from.
fn setup_seed(geometry: &str, kind: &str) -> u64 {
    let digest = Sha256::new()
        .chain_update(transparent_shard::SCHEMA.as_bytes())
        .chain_update(b"/setup-seed\0")
        .chain_update(geometry.as_bytes())
        .chain_update(b"\0")
        .chain_update(kind.as_bytes())
        .finalize();
    u64::from_le_bytes(digest[..8].try_into().expect("eight bytes"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn setup_seeds_match_the_live_init_document() {
        // Published by https://transparent-pir.valargroup.dev/v1/txid/init.
        assert_eq!(setup_seed("txid-2k", "txdirectory"), 6316083992602350090);
        assert_eq!(setup_seed("txid-2k", "txpages"), 7075523661426028053);
    }

    #[test]
    fn routes_name_no_txid_and_templates_elide_identifiers() {
        let digest = "ab".repeat(32);
        let query = TxidRequest {
            route: TxidRoute::Query {
                tier: Tier::Recent,
                shard_id: 13,
                digest: digest.clone(),
                table: DisplayTable::Directory(0),
            },
            body: vec![1, 2, 3],
            limit: 10,
        };
        assert_eq!(query.method(), Method::POST);
        assert_eq!(
            query.path(),
            format!("/v1/txid/recent/shards/13/revisions/{digest}/query/directory-0")
        );
        assert!(!query.template().contains("13"));
        assert!(!query.template().contains(&digest));
        let setup = TxidRequest::read(
            TxidRoute::Setup {
                tier: Tier::Archive,
                shard_id: 2,
                digest: digest.clone(),
                table: DisplayTable::Pages,
                segment: 0,
            },
            10,
        );
        assert_eq!(
            setup.path(),
            format!("/v1/txid/archive/shards/2/revisions/{digest}/setup/pages/0")
        );
        assert_eq!(setup.method(), Method::GET);
    }

    #[test]
    fn candidate_rows_depend_on_shard_and_stay_in_range() {
        let txid = Txid([9; 32]);
        let rows = candidate_rows(&txid, 3, bucket(&txid, 1), 2048);
        assert!(rows.iter().all(|row| *row < 2048));
        assert_ne!(rows, candidate_rows(&txid, 4, 0, 2048));
        assert_eq!(bucket(&txid, 1), 0);
    }
}
