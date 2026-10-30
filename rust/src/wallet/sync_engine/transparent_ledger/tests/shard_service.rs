//! A real transparent shard service in process: wallet-libraries' test
//! publisher writes shards for a synthetic mainnet chain, and wallet-pir's
//! shard server answers the requests a test transport hands it, so a test
//! reaches real filters and real PIR without a network.
//!
//! The publisher and server are `zakura_pir_client::transparent::testing::service`;
//! this module adds the events the coordinator tests publish and plugs the
//! server into the transport's request observer. Every shard has the smallest
//! published geometry; a publication may declare re-cuts of an earlier one. Block hashes follow the coordinator
//! tests' main chain (`main_hash`), so a wallet scanned with those tests'
//! `scan` agrees with every shard boundary the service publishes inside its
//! scanned range.

use bytes::Bytes;
use http_body_util::Full;
use transparent::address::TransparentAddress;
use zakura_pir_client::transparent::testing::events::{
    ReceiveEvent, SpendEvent, TransparentEvent, Txid,
};
use zakura_pir_client::transparent::testing::filter::{BlockHash, Recut, ScriptBytes, ShardMap};
use zakura_pir_client::transparent::testing::service::{publish, superseded, InProcess, SEAL};

pub(super) use zakura_pir_client::transparent::testing::service::ShardSpec;

use crate::wallet::sync_engine::enhancement::{ObservedRequest, RequestObserver};

/// The pay-to-public-key-hash script of `address`.
pub(super) fn script(address: TransparentAddress) -> ScriptBytes {
    match address {
        TransparentAddress::PublicKeyHash(hash) => {
            ScriptBytes::new([&[0x76, 0xa9, 20][..], &hash, &[0x88, 0xac]].concat())
        }
        TransparentAddress::ScriptHash(_) => panic!("derived addresses pay to public key hashes"),
    }
}

/// The txid of the transaction tagged `tag`.
pub(super) fn tagged(tag: u64) -> Txid {
    let mut txid = [0u8; 32];
    txid[..8].copy_from_slice(&tag.to_le_bytes());
    txid[31] = 0x77;
    Txid(txid)
}

/// A receive of [`RECEIVED`] zatoshis at `height` in the transaction tagged
/// `tag`, its output 0.
pub(super) fn receive(height: u64, tag: u64) -> TransparentEvent {
    TransparentEvent::Receive(ReceiveEvent {
        metadata: None,
        height: height as u32,
        txid: tagged(tag),
        transaction_index: 1,
        output_index: 0,
        value: RECEIVED,
        coinbase: false,
    })
}

/// What every [`receive`] pays.
pub(super) const RECEIVED: u64 = 50_000;

/// A spend at `height`, in the transaction tagged `tag`, of output 0 of the
/// transaction tagged `spent`.
pub(super) fn spend(height: u64, tag: u64, spent: u64) -> TransparentEvent {
    TransparentEvent::Spend(SpendEvent {
        metadata: None,
        height: height as u32,
        spending_txid: tagged(tag),
        transaction_index: 1,
        input_index: 0,
        spent_txid: tagged(spent),
        spent_output_index: 0,
    })
}

/// Receives to scripts no account derives, spread over `[start, end]`, so that
/// a test's scripts are not alone in a shard.
pub(super) fn noise(start: u64, end: u64, salt: u32) -> Vec<(ScriptBytes, TransparentEvent)> {
    (0..40u32)
        .map(|n| {
            let tag = salt * 1_000 + n;
            let mut bytes = vec![0x76, 0xa9, 20];
            bytes.extend_from_slice(&tag.to_le_bytes());
            bytes.extend_from_slice(&[0xee; 16]);
            bytes.extend_from_slice(&[0x88, 0xac]);
            let height = start + u64::from(n * 7) % (end - start + 1);
            (
                ScriptBytes::new(bytes),
                receive(height, u64::from(tag) + 100_000),
            )
        })
        .collect()
}

/// The block hash at `height` on the coordinator tests' chain `fork`
/// (`chain_hash`; fork 0 is `main_hash`).
fn synthetic(height: u64, fork: u8) -> BlockHash {
    let mut bytes = [0u8; 32];
    bytes[..4].copy_from_slice(&(height as u32).to_le_bytes());
    bytes[4] = fork;
    bytes[31] = 1;
    BlockHash::from_internal_bytes(bytes)
}

/// A shard service serving one publication, answering in process.
pub(super) struct ShardService {
    service: InProcess,
    /// The map published, for a later revision to supersede its entries.
    map: ShardMap,
    _dir: tempfile::TempDir,
}

impl ShardService {
    /// Publishes `shards`, numbered from zero, and serves them.
    pub(super) fn publish(shards: &[ShardSpec]) -> Self {
        Self::publish_forked(shards, u64::MAX)
    }

    /// Like [`Self::publish`], but on chain fork 1 from `fork_from` up: every
    /// block hash the publication names at or above it differs from the main
    /// chain's.
    pub(super) fn publish_forked(shards: &[ShardSpec], fork_from: u64) -> Self {
        Self::publish_with(shards, fork_from, vec![])
    }

    /// Publishes `shards` as a re-cut of `earlier`'s publication from
    /// `from_height` up: the map declares, as epoch 1, every shard `earlier`
    /// published at or above that height superseded, exactly as published.
    pub(super) fn publish_recut(shards: &[ShardSpec], earlier: &Self, from_height: u64) -> Self {
        let recut = Recut {
            epoch: 1,
            from_height,
            superseded: earlier
                .map
                .shards
                .iter()
                .filter(|entry| entry.end_height >= from_height)
                .map(superseded)
                .collect(),
        };
        Self::publish_with(shards, u64::MAX, vec![recut])
    }

    fn publish_with(shards: &[ShardSpec], fork_from: u64, recuts: Vec<Recut>) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let map = publish(
            dir.path(),
            shards,
            SEAL,
            |height| synthetic(height, u8::from(height >= fork_from)),
            recuts,
        );
        Self {
            service: InProcess::serve(dir.path()),
            map,
            _dir: dir,
        }
    }

    /// The manifest digest this service publishes for shard `shard_id`.
    pub(super) fn digest(&self, shard_id: usize) -> String {
        self.map.shards[shard_id].manifest_digest.clone()
    }

    /// An observer answering every request with the service's own reply.
    pub(super) fn observer(&self) -> RequestObserver {
        self.observer_with(|_, _, _| {})
    }

    /// Like [`Self::observer`], but `tamper` may rewrite each reply's status,
    /// headers and body before the wallet reads it: a misbehaving service
    /// in front of real data.
    pub(super) fn observer_with(
        &self,
        tamper: impl Fn(&ObservedRequest, &mut http::response::Parts, &mut Vec<u8>)
            + Send
            + Sync
            + 'static,
    ) -> RequestObserver {
        let service = self.service.clone();
        RequestObserver::answering(move |observed| {
            let request = http::Request::builder()
                .method(observed.method.clone())
                .uri(observed.path.clone())
                .body(observed.body.clone())
                .unwrap();
            let (mut parts, mut body) = service.answer(request).into_parts();
            tamper(observed, &mut parts, &mut body);
            http::Response::from_parts(parts, Full::new(Bytes::from(body)))
        })
    }
}
