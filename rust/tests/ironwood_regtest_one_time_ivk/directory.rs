//! The receiver directory: an indexer that reads the regtest chain the way the live one
//! reads a Zakura node, publishing over the real receiver routes and PIR, served to
//! Vizor over loopback HTTP.

use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, Mutex},
};

use receiver_pir_server::{router_with_publications, Publication, Publications};
use rust_lib_zcash_wallet::wallet::network::WalletNetwork;
use zakura_pir_receiver::{
    receiver_directory::{
        extract::Action,
        snapshot::{Manifest, ProviderSet, Snapshot, PROFILE},
        witness::WitnessSnapshot,
        Payment, Receiver, Record,
    },
    receiver_pir::{server::Server, MIN_ROWS},
};
use zcash_primitives::block::Block;

use super::chain::Stack;

/// One block as the live indexer extracts it (see `receiver-indexer`'s `extract_block`).
struct IndexedBlock {
    hash: [u8; 32],
    /// Every Ironwood note commitment, in tree order.
    commitments: Vec<[u8; 32]>,
    /// Zero-OVK payments outside coinbase, with the receivers the zero OVK recovers.
    payments: Vec<(Receiver, Payment)>,
}

/// The chain's blocks from Ironwood activation, indexed as the live directory indexes
/// them.
pub struct Indexer {
    activation: u32,
    blocks: BTreeMap<u32, IndexedBlock>,
}

impl Indexer {
    /// An empty index for a chain whose Ironwood activates at `activation`.
    pub fn new(activation: u32) -> Self {
        Self {
            activation,
            blocks: BTreeMap::new(),
        }
    }

    /// A publication of every zero-OVK payment through `end`, with NEAR's `sets`, for a
    /// chain whose genesis is `genesis` (internal byte order).
    pub fn publication(
        &mut self,
        stack: &Stack,
        end: u32,
        sets: &[ProviderSet],
        genesis: [u8; 32],
    ) -> Publication {
        self.index_through(stack, end);
        let payments: Vec<&(Receiver, Payment)> =
            self.blocks.values().flat_map(|b| &b.payments).collect();
        let mut totals: BTreeMap<[u8; 43], u32> = BTreeMap::new();
        for (receiver, _) in &payments {
            *totals.entry(*receiver.as_bytes()).or_default() += 1;
        }
        let mut pages: BTreeMap<[u8; 43], u32> = BTreeMap::new();
        let records: Vec<Record> = payments
            .into_iter()
            .map(|(receiver, payment)| {
                let key = *receiver.as_bytes();
                let page = pages.entry(key).or_default();
                let record = Record {
                    receiver: receiver.clone(),
                    page: *page,
                    total: totals[&key],
                    payment: payment.clone(),
                };
                *page += 1;
                record
            })
            .collect();
        let commitments: Vec<[u8; 32]> = self
            .blocks
            .values()
            .flat_map(|b| b.commitments.iter().copied())
            .collect();
        let manifest = Manifest {
            profile: PROFILE.into(),
            genesis,
            start_height: self.activation,
            start_parent: stack.block_hash(self.activation - 1),
            start_position: 0,
            end_height: end,
            end_hash: self.blocks[&end].hash,
            end_position: commitments.len() as u64,
            rows: MIN_ROWS,
            salt: [7; 32],
            records: 0,
            data_sha256: [0; 32],
            filters: Vec::new(),
            filters_sha256: [0; 32],
        };
        let snapshot = Snapshot::build(manifest, &records, sets).expect("a valid publication");
        let positions: BTreeSet<u32> = records
            .iter()
            .map(|r| u32::try_from(r.payment.position).expect("a regtest position"))
            .collect();
        let witnesses = (!commitments.is_empty()).then(|| {
            WitnessSnapshot::build(&snapshot.manifest, &commitments, &positions)
                .expect("witnesses build")
                .encode()
        });
        let server = Server::new(snapshot).expect("the PIR server prepares");
        Publication::new(server, witnesses).expect("a publication")
    }

    /// Indexes the chain through `end`, reindexing from the lowest block a reorg replaced.
    fn index_through(&mut self, stack: &Stack, end: u32) {
        self.blocks.split_off(&(end + 1));
        // Reorgs replace the top of the chain, so check down from the top.
        let mut stale = None;
        for (height, block) in self.blocks.iter().rev() {
            if stack.block_hash(*height) == block.hash {
                break;
            }
            stale = Some(*height);
        }
        if let Some(height) = stale {
            self.blocks.split_off(&height);
        }
        let mut position: u64 = self
            .blocks
            .values()
            .map(|b| b.commitments.len() as u64)
            .sum();
        let next = self
            .blocks
            .keys()
            .next_back()
            .map_or(self.activation, |h| h + 1);
        for height in next..=end {
            let raw = stack.raw_block(height);
            let (header, transactions) = Block::read(&raw[..], &WalletNetwork::Regtest)
                .expect("a block parses")
                .into_parts();
            let mut indexed = IndexedBlock {
                hash: header.hash().0,
                commitments: Vec::new(),
                payments: Vec::new(),
            };
            for (tx_index, tx) in transactions.iter().enumerate() {
                let coinbase = tx.transparent_bundle().is_some_and(|b| b.is_coinbase());
                let Some(bundle) = tx.ironwood_bundle() else {
                    continue;
                };
                for (action_index, a) in bundle.actions().iter().enumerate() {
                    let cmx = a.cmx().to_bytes();
                    indexed.commitments.push(cmx);
                    if !coinbase {
                        let note = a.encrypted_note();
                        let action = Action {
                            cv: a.cv_net().to_bytes(),
                            nullifier: a.nullifier().to_bytes(),
                            cmx,
                            ephemeral_key: note.epk_bytes,
                            enc_ciphertext: note.enc_ciphertext,
                            out_ciphertext: note.out_ciphertext,
                        };
                        if let Some(receiver) =
                            action.recover_receiver().expect("a well-formed action")
                        {
                            let payment = Payment {
                                height,
                                block_hash: indexed.hash,
                                txid: *tx.txid().as_ref(),
                                tx_index: u32::try_from(tx_index).expect("fits"),
                                action_index: u32::try_from(action_index).expect("fits"),
                                position,
                                action_nullifier: action.nullifier,
                                cmx,
                                ephemeral_key: action.ephemeral_key,
                                ciphertext_prefix: note.enc_ciphertext[..52]
                                    .try_into()
                                    .expect("a fixed prefix"),
                            };
                            indexed.payments.push((receiver, payment));
                        }
                    }
                    position += 1;
                }
            }
            self.blocks.insert(height, indexed);
        }
    }

    /// The note commitment tree position of every zero-OVK payment to `receiver`, in chain
    /// order.
    pub fn positions(&self, receiver: &[u8; 43]) -> Vec<u64> {
        self.blocks
            .values()
            .flat_map(|b| &b.payments)
            .filter(|(r, _)| r.as_bytes() == receiver)
            .map(|(_, p)| p.position)
            .collect()
    }

    /// The Ironwood note commitment tree's size after `height`, once indexed.
    pub fn tree_size(&mut self, stack: &Stack, height: u32) -> u64 {
        self.index_through(stack, height);
        self.blocks
            .values()
            .map(|b| b.commitments.len() as u64)
            .sum()
    }
}

/// The receiver the zero OVK recovers from each of `tx`'s Ironwood actions, in order.
pub fn zero_ovk_receivers(
    tx: &zcash_primitives::transaction::Transaction,
) -> Vec<Option<[u8; 43]>> {
    tx.ironwood_bundle()
        .map(|bundle| {
            bundle
                .actions()
                .iter()
                .map(|a| {
                    let note = a.encrypted_note();
                    Action {
                        cv: a.cv_net().to_bytes(),
                        nullifier: a.nullifier().to_bytes(),
                        cmx: a.cmx().to_bytes(),
                        ephemeral_key: note.epk_bytes,
                        enc_ciphertext: note.enc_ciphertext,
                        out_ciphertext: note.out_ciphertext,
                    }
                    .recover_receiver()
                    .expect("a well-formed action")
                    .map(|r| *r.as_bytes())
                })
                .collect()
        })
        .unwrap_or_default()
}

/// The directory's HTTP service on the loopback interface, which Vizor reaches through
/// its debug-only loopback transport (see `swap_private`).
pub struct DirectoryServer {
    publications: Publications,
    requests: Arc<Mutex<Vec<String>>>,
    origin: String,
    _runtime: tokio::runtime::Runtime,
}

impl DirectoryServer {
    /// Serves no publication yet.
    pub fn start() -> Self {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("the directory runtime");
        let publications = Publications::default();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let log = requests.clone();
        let router =
            router_with_publications(publications.clone()).layer(axum::middleware::from_fn(
                move |request: axum::extract::Request, next: axum::middleware::Next| {
                    let log = log.clone();
                    async move {
                        log.lock().unwrap().push(format!(
                            "{} {}",
                            request.method(),
                            request.uri().path()
                        ));
                        next.run(request).await
                    }
                },
            ));
        let listener = runtime
            .block_on(tokio::net::TcpListener::bind("127.0.0.1:0"))
            .expect("a loopback port");
        let origin = format!("http://{}", listener.local_addr().expect("an address"));
        runtime.spawn(async move {
            axum::serve(listener, router)
                .await
                .expect("the directory serves")
        });
        Self {
            publications,
            requests,
            origin,
            _runtime: runtime,
        }
    }

    /// The plaintext loopback origin Vizor is pointed at.
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// Replaces the served publication. The live indexer waits out the previous
    /// revision's one-minute grace for sessions still using it. These tests sync one
    /// wallet at a time, so no session spans a publish, and revoking first, as the indexer
    /// does after a reorg, lets the new revision in at once.
    pub fn publish(&self, publication: Publication) {
        self.publications.revoke();
        let epoch = self.publications.epoch();
        assert!(
            self.publications.publish(publication, epoch),
            "the publication swaps in"
        );
    }

    /// Encrypted lookups served so far.
    pub fn lookups(&self) -> usize {
        self.requests
            .lock()
            .unwrap()
            .iter()
            .filter(|r| *r == "POST /v1/receiver/query")
            .count()
    }
}
