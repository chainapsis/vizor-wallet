//! Synthetic-chain benchmark for the compact-block scan path.
//!
//! Builds a wallet DB the way the app does (one `Derived` bootstrap account
//! plus imported UFVK accounts), generates a mainnet-height chain of compact
//! blocks with real Orchard and Sapling note encryptions, and drives the same
//! per-batch steps `run_sync_impl` runs after a download: the wallet write
//! lock, `queue_stored_transactions`, and `scan_cached_blocks` over a
//! [`MemoryBlockSource`].
//!
//! Two phases are timed separately:
//!
//! - **catch-up**: the chain minus the live tail, in `BATCH_SIZE_FOREGROUND`
//!   batches, as when a wallet opens after being away;
//! - **live**: the tail, one block per sync session, as when the app follows
//!   the tip. Each session reopens the DB, updates the chain tip and reads the
//!   suggested scan ranges before scanning, as a fresh `run_sync_impl` does.
//!
//! Run (release, the numbers are meaningless in debug):
//!
//! ```text
//! cargo test --release --lib scan_bench -- --ignored --nocapture
//! ```
//!
//! Knobs (environment): `VIZOR_BENCH_BLOCKS` (100000), `VIZOR_BENCH_ACCOUNTS`
//! (10), `VIZOR_BENCH_NOTES_PER_ACCOUNT` (100), `VIZOR_BENCH_ORCHARD_PER_BLOCK`
//! (4 unrelated actions), `VIZOR_BENCH_SAPLING_PER_BLOCK` (2 unrelated
//! outputs), `VIZOR_BENCH_LIVE_BLOCKS` (500), `VIZOR_BENCH_START` (3400000,
//! after NU6.1 and before NU7 on mainnet).

use std::time::{Duration, Instant};

use incrementalmerkletree::frontier::Frontier;
use orchard::keys::{FullViewingKey as OrchardFvk, Scope as OrchardScope, SpendingKey};
use orchard::note::{ExtractedNoteCommitment, Nullifier, RandomSeed, Rho};
use orchard::note_encryption::{OrchardDomain, OrchardNoteEncryption};
use orchard::tree::MerkleHashOrchard;
use rand::{rngs::StdRng, Rng, RngCore, SeedableRng};
use sapling_crypto::note_encryption::SaplingDomain;
use secrecy::SecretVec;
use zcash_client_backend::data_api::{
    chain::{scan_cached_blocks_with_cache, ChainState},
    WalletRead, WalletWrite,
};
use zcash_client_backend::proto::compact_formats::{
    ChainMetadata, CompactBlock, CompactOrchardAction, CompactSaplingOutput, CompactTx,
};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_note_encryption::{Domain, NoteEncryption};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use super::block_source::MemoryBlockSource;
use super::enhancement::queue_stored_transactions;
use super::scanning_keys;
use super::BATCH_SIZE_FOREGROUND;
use crate::wallet::db::{
    open_wallet_db_with_timeout, with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT,
};
use crate::wallet::keys::{add_account, init_db_and_create_account};
use crate::wallet::network::WalletNetwork;

const NETWORK: WalletNetwork = WalletNetwork::Main;
const SEED: u64 = 0x5eed_b10c;

type SaplingFrontier =
    Frontier<sapling_crypto::Node, { sapling_crypto::NOTE_COMMITMENT_TREE_DEPTH }>;
type OrchardFrontier = Frontier<MerkleHashOrchard, { orchard::NOTE_COMMITMENT_TREE_DEPTH as u8 }>;

struct Config {
    blocks: u32,
    accounts: usize,
    notes_per_account: usize,
    orchard_per_block: usize,
    sapling_per_block: usize,
    live_blocks: u32,
    start: u32,
}

impl Config {
    fn from_env() -> Self {
        fn var<T: std::str::FromStr>(name: &str, default: T) -> T {
            std::env::var(name)
                .ok()
                .and_then(|raw| raw.parse().ok())
                .unwrap_or(default)
        }
        let blocks = var("VIZOR_BENCH_BLOCKS", 100_000u32);
        Self {
            blocks,
            accounts: var("VIZOR_BENCH_ACCOUNTS", 10),
            notes_per_account: var("VIZOR_BENCH_NOTES_PER_ACCOUNT", 100),
            orchard_per_block: var("VIZOR_BENCH_ORCHARD_PER_BLOCK", 4),
            sapling_per_block: var("VIZOR_BENCH_SAPLING_PER_BLOCK", 2),
            live_blocks: var("VIZOR_BENCH_LIVE_BLOCKS", 500u32).min(blocks),
            start: var("VIZOR_BENCH_START", 3_400_000),
        }
    }
}

/// A wallet-relevant event placed at a block offset.
#[derive(Clone)]
enum Event {
    /// An Orchard output to the note's account.
    Receive { note_id: usize },
    /// Reveals the nullifier of a previously received note.
    Spend { note_id: usize },
}

fn random_nullifier(rng: &mut impl RngCore) -> Nullifier {
    loop {
        let mut bytes = [0u8; 32];
        rng.fill_bytes(&mut bytes);
        if let Some(nf) = Option::from(Nullifier::from_bytes(&bytes)) {
            return nf;
        }
    }
}

fn random_orchard_address(rng: &mut impl RngCore) -> orchard::Address {
    loop {
        let mut bytes = [0u8; 32];
        rng.fill_bytes(&mut bytes);
        if let Some(sk) = Option::<SpendingKey>::from(SpendingKey::from_bytes(bytes)) {
            return OrchardFvk::from(&sk).address_at(0u32, OrchardScope::External);
        }
    }
}

/// Encrypts a V2 Orchard note to `recipient`, revealing `nf_old`.
fn orchard_action(
    rng: &mut impl RngCore,
    nf_old: Nullifier,
    recipient: orchard::Address,
    value: u64,
) -> (CompactOrchardAction, orchard::Note) {
    let rho = Option::from(Rho::from_bytes(&nf_old.to_bytes()))
        .expect("a valid nullifier is a valid rho");
    let rseed = loop {
        let mut bytes = [0u8; 32];
        rng.fill_bytes(&mut bytes);
        if let Some(rseed) = Option::from(RandomSeed::from_bytes(bytes, &rho)) {
            break rseed;
        }
    };
    let note = orchard::Note::from_parts(
        recipient,
        orchard::value::NoteValue::from_raw(value),
        rho,
        rseed,
        orchard::NoteVersion::V2,
    )
    .expect("random rseed was accepted for this rho");
    let encryptor = OrchardNoteEncryption::new(None, note, [0u8; 512]);
    let cmx = ExtractedNoteCommitment::from(note.commitment());
    let action = CompactOrchardAction {
        nullifier: nf_old.to_bytes().to_vec(),
        cmx: cmx.to_bytes().to_vec(),
        ephemeral_key: OrchardDomain::epk_bytes(encryptor.epk()).0.to_vec(),
        ciphertext: encryptor.encrypt_note_plaintext()[..52].to_vec(),
    };
    (action, note)
}

fn sapling_output(
    rng: &mut impl RngCore,
    recipient: &sapling_crypto::PaymentAddress,
) -> CompactSaplingOutput {
    let mut rseed = [0u8; 32];
    rng.fill_bytes(&mut rseed);
    let note = recipient.create_note(
        sapling_crypto::value::NoteValue::from_raw(rng.gen_range(10_000..1_000_000)),
        sapling_crypto::Rseed::AfterZip212(rseed),
    );
    let cmu = note.cmu();
    let encryptor = NoteEncryption::<SaplingDomain>::new(None, note, [0u8; 512]);
    CompactSaplingOutput {
        cmu: cmu.to_bytes().to_vec(),
        ephemeral_key: SaplingDomain::epk_bytes(encryptor.epk()).0.to_vec(),
        ciphertext: encryptor.encrypt_note_plaintext()[..52].to_vec(),
    }
}

fn random_txid(rng: &mut impl RngCore) -> Vec<u8> {
    let mut txid = vec![0u8; 32];
    rng.fill_bytes(&mut txid);
    txid
}

/// Places `notes_per_account` receives per account at random offsets, and
/// spends about half of them at a later offset. Note ids are
/// `account * notes_per_account + n`. Returns the events and the spend count.
fn plan_events(config: &Config, rng: &mut StdRng) -> (Vec<Vec<Event>>, usize) {
    let mut events = vec![Vec::new(); config.blocks as usize];
    let mut spends = 0;
    for note_id in 0..config.accounts * config.notes_per_account {
        let at = rng.gen_range(0..config.blocks);
        events[at as usize].push(Event::Receive { note_id });
        if rng.gen_bool(0.5) && at + 1 < config.blocks {
            let spend_at = rng.gen_range(at + 1..config.blocks);
            events[spend_at as usize].push(Event::Spend { note_id });
            spends += 1;
        }
    }
    (events, spends)
}

/// Precomputed wallet-owned notes: the receiving action and the nullifier
/// that spends it.
struct OwnedNote {
    action: CompactOrchardAction,
    nullifier: Nullifier,
}

/// Per-block transactions without chain linkage (hashes, metadata), which
/// [`link_chain`] fills in sequentially.
fn generate_block_txs(
    config: &Config,
    offset: u32,
    events: &[Event],
    owned: &[OwnedNote],
    decoy_orchard: &[orchard::Address],
    decoy_sapling: &[sapling_crypto::PaymentAddress],
) -> Vec<CompactTx> {
    let mut rng = StdRng::seed_from_u64(SEED ^ (u64::from(offset) << 8));
    let mut txs = Vec::new();

    for event in events {
        let mut tx = CompactTx {
            txid: random_txid(&mut rng),
            ..Default::default()
        };
        tx.actions.push(match event {
            Event::Receive { note_id, .. } => owned[*note_id].action.clone(),
            Event::Spend { note_id } => {
                let recipient = decoy_orchard[rng.gen_range(0..decoy_orchard.len())];
                let value = rng.gen_range(10_000..1_000_000);
                orchard_action(&mut rng, owned[*note_id].nullifier, recipient, value).0
            }
        });
        // Orchard bundles carry at least two actions.
        let pad_recipient = decoy_orchard[rng.gen_range(0..decoy_orchard.len())];
        let pad_nf = random_nullifier(&mut rng);
        tx.actions
            .push(orchard_action(&mut rng, pad_nf, pad_recipient, 0).0);
        txs.push(tx);
    }

    // Unrelated Orchard traffic in two-action transactions.
    let mut remaining = config.orchard_per_block;
    while remaining > 0 {
        let mut tx = CompactTx {
            txid: random_txid(&mut rng),
            ..Default::default()
        };
        for _ in 0..remaining.min(2) {
            let recipient = decoy_orchard[rng.gen_range(0..decoy_orchard.len())];
            let nf = random_nullifier(&mut rng);
            let value = rng.gen_range(10_000..1_000_000);
            tx.actions
                .push(orchard_action(&mut rng, nf, recipient, value).0);
        }
        remaining = remaining.saturating_sub(2);
        txs.push(tx);
    }

    if config.sapling_per_block > 0 {
        let mut tx = CompactTx {
            txid: random_txid(&mut rng),
            ..Default::default()
        };
        for _ in 0..config.sapling_per_block {
            let recipient = &decoy_sapling[rng.gen_range(0..decoy_sapling.len())];
            tx.outputs.push(sapling_output(&mut rng, recipient));
        }
        txs.push(tx);
    }

    for (index, tx) in txs.iter_mut().enumerate() {
        tx.index = index as u64;
    }
    txs
}

/// The generated chain plus the tree states that precede each scan batch.
struct Chain {
    blocks: Vec<CompactBlock>,
    /// `states[offset]` is the chain state after block `offset - 1`, for every
    /// offset a batch starts at.
    states: std::collections::HashMap<u32, ChainState>,
}

/// Fills in hashes and cumulative tree sizes, and records the frontier
/// preceding each batch start.
fn link_chain(config: &Config, txs: Vec<Vec<CompactTx>>, batch_starts: &[u32]) -> Chain {
    let mut rng = StdRng::seed_from_u64(SEED ^ 0xc4a1);
    let mut sapling = SaplingFrontier::empty();
    let mut orchard = OrchardFrontier::empty();
    let mut prev_hash = [0u8; 32];
    let mut wanted = batch_starts.iter().copied().peekable();
    let mut states = std::collections::HashMap::new();
    let mut blocks = Vec::with_capacity(txs.len());

    for (offset, vtx) in txs.into_iter().enumerate() {
        let offset = offset as u32;
        let height = config.start + offset;
        if wanted.peek() == Some(&offset) {
            wanted.next();
            states.insert(
                offset,
                ChainState::new(
                    BlockHeight::from_u32(height - 1),
                    BlockHash(prev_hash),
                    sapling.clone(),
                    orchard.clone(),
                    OrchardFrontier::empty(),
                ),
            );
        }
        for tx in &vtx {
            for output in &tx.outputs {
                let cmu = sapling_crypto::note::ExtractedNoteCommitment::from_bytes(
                    &output.cmu.clone().try_into().expect("32-byte cmu"),
                )
                .expect("generated cmu is canonical");
                sapling.append(sapling_crypto::Node::from_cmu(&cmu));
            }
            for action in &tx.actions {
                let cmx = ExtractedNoteCommitment::from_bytes(
                    &action.cmx.clone().try_into().expect("32-byte cmx"),
                )
                .expect("generated cmx is canonical");
                orchard.append(MerkleHashOrchard::from_cmx(&cmx));
            }
        }
        let mut hash = [0u8; 32];
        rng.fill_bytes(&mut hash);
        blocks.push(CompactBlock {
            height: u64::from(height),
            hash: hash.to_vec(),
            prev_hash: prev_hash.to_vec(),
            time: 1_700_000_000 + offset * 75,
            vtx,
            chain_metadata: Some(ChainMetadata {
                sapling_commitment_tree_size: frontier_size(&sapling),
                orchard_commitment_tree_size: frontier_size(&orchard),
                ironwood_commitment_tree_size: 0,
            }),
            ..Default::default()
        });
        prev_hash = hash;
    }

    Chain { blocks, states }
}

fn frontier_size<H, const DEPTH: u8>(frontier: &Frontier<H, DEPTH>) -> u32 {
    frontier.value().map_or(0, |f| {
        u32::try_from(u64::from(f.position()) + 1).expect("fits in u32")
    })
}

/// Offsets at which a scan batch starts: `BATCH_SIZE_FOREGROUND` strides
/// through the catch-up range, then one per live block.
fn batch_starts(config: &Config) -> Vec<u32> {
    let catch_up_end = config.blocks - config.live_blocks;
    let mut starts: Vec<u32> = (0..catch_up_end)
        .step_by(BATCH_SIZE_FOREGROUND as usize)
        .collect();
    starts.extend(catch_up_end..config.blocks);
    starts
}

fn account_seed(account: usize) -> SecretVec<u8> {
    let mut rng = StdRng::seed_from_u64(SEED ^ 0xacc0_0000 ^ account as u64);
    let mut seed = vec![0u8; 64];
    rng.fill_bytes(&mut seed);
    SecretVec::new(seed)
}

fn owned_notes(config: &Config, seeds: &[SecretVec<u8>]) -> Vec<OwnedNote> {
    use secrecy::ExposeSecret;

    let fvks: Vec<OrchardFvk> = seeds
        .iter()
        .map(|seed| {
            UnifiedSpendingKey::from_seed(&NETWORK, seed.expose_secret(), zip32::AccountId::ZERO)
                .expect("a 64-byte seed derives a spending key")
                .to_unified_full_viewing_key()
                .orchard()
                .expect("software accounts carry an Orchard key")
                .clone()
        })
        .collect();
    let mut rng = StdRng::seed_from_u64(SEED ^ 0x0e0e);
    (0..config.accounts * config.notes_per_account)
        .map(|note_id| {
            let fvk = &fvks[note_id / config.notes_per_account];
            let recipient = fvk.address_at(0u32, OrchardScope::External);
            let nf_old = random_nullifier(&mut rng);
            let value = rng.gen_range(10_000..1_000_000);
            let (action, note) = orchard_action(&mut rng, nf_old, recipient, value);
            OwnedNote {
                action,
                nullifier: note.nullifier(fvk),
            }
        })
        .collect()
}

/// Generates the chain on all cores; returns it with the receive and spend
/// counts the scan must find.
fn generate_chain(config: &Config, seeds: &[SecretVec<u8>]) -> (Chain, usize, usize) {
    let mut rng = StdRng::seed_from_u64(SEED);
    let (events, spends) = plan_events(config, &mut rng);
    let owned = owned_notes(config, seeds);
    let decoy_orchard: Vec<_> = (0..64).map(|_| random_orchard_address(&mut rng)).collect();
    let decoy_sapling: Vec<_> = (0..64)
        .map(|_| {
            let mut seed = [0u8; 32];
            rng.fill_bytes(&mut seed);
            sapling_crypto::zip32::ExtendedSpendingKey::master(&seed)
                .default_address()
                .1
        })
        .collect();

    let threads = std::thread::available_parallelism().map_or(4, |n| n.get());
    let chunk = (config.blocks as usize).div_ceil(threads);
    let txs: Vec<Vec<CompactTx>> = std::thread::scope(|scope| {
        let handles: Vec<_> = events
            .chunks(chunk)
            .enumerate()
            .map(|(i, block_events)| {
                let (owned, decoy_orchard, decoy_sapling) =
                    (&owned, &decoy_orchard, &decoy_sapling);
                scope.spawn(move || {
                    block_events
                        .iter()
                        .enumerate()
                        .map(|(j, events)| {
                            let offset = (i * chunk + j) as u32;
                            generate_block_txs(
                                config,
                                offset,
                                events,
                                owned,
                                decoy_orchard,
                                decoy_sapling,
                            )
                        })
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        handles
            .into_iter()
            .flat_map(|handle| handle.join().expect("generator thread panicked"))
            .collect()
    });

    let chain = link_chain(config, txs, &batch_starts(config));
    (chain, owned.len(), spends)
}

#[derive(Default)]
struct PhaseStats {
    sessions: u32,
    blocks: u64,
    open_and_ranges: Duration,
    queue: Duration,
    scan: Duration,
    slowest_scan: Duration,
    received: usize,
    spent: usize,
}

impl PhaseStats {
    fn report(&self, name: &str, actions_per_block: f64) {
        let total = self.open_and_ranges + self.queue + self.scan;
        let secs = total.as_secs_f64().max(f64::EPSILON);
        println!(
            "[scan_bench] {name}: {} blocks in {} sessions, {:.2}s total \
             ({:.0} blocks/s, {:.0} outputs/s)\n\
             [scan_bench]   open+tip+ranges {:.3}s | queue_stored_transactions {:.3}s | \
             scan_cached_blocks {:.3}s (slowest {:.1} ms, mean {:.2} ms/session)\n\
             [scan_bench]   found {} received, {} spent",
            self.blocks,
            self.sessions,
            secs,
            self.blocks as f64 / secs,
            self.blocks as f64 * actions_per_block / secs,
            self.open_and_ranges.as_secs_f64(),
            self.queue.as_secs_f64(),
            self.scan.as_secs_f64(),
            self.slowest_scan.as_secs_f64() * 1e3,
            self.scan.as_secs_f64() * 1e3 / f64::from(self.sessions.max(1)),
            self.received,
            self.spent,
        );
    }
}

/// Scans `chain.blocks[from..to]` as one session of `batch`-block batches.
/// A live session reopens the DB and recomputes the scan queue first, as a
/// new `run_sync_impl` does.
fn scan_session(
    db_path: &str,
    config: &Config,
    chain: &Chain,
    from: u32,
    to: u32,
    stats: &mut PhaseStats,
) {
    let t = Instant::now();
    let mut db = open_wallet_db_with_timeout(db_path, NETWORK, SYNC_DB_BUSY_TIMEOUT)
        .expect("open bench wallet DB");
    with_wallet_db_write_lock("scan_bench.update_chain_tip", || {
        db.update_chain_tip(BlockHeight::from_u32(config.start + to - 1))
    })
    .expect("update chain tip");
    let ranges = db.suggest_scan_ranges().expect("suggest scan ranges");
    assert!(!ranges.is_empty(), "the session has blocks to scan");
    stats.open_and_ranges += t.elapsed();
    stats.sessions += 1;

    let mut start = from;
    while start < to {
        let end = (start + BATCH_SIZE_FOREGROUND).min(to);
        let source = MemoryBlockSource::new(chain.blocks[start as usize..end as usize].to_vec());
        let from_state = &chain.states[&start];

        let summary = with_wallet_db_write_lock("scan_bench.scan", || {
            let t = Instant::now();
            queue_stored_transactions(db_path, &source).expect("queue stored transactions");
            stats.queue += t.elapsed();

            let t = Instant::now();
            let summary = scanning_keys::with_cache(db_path, |keys| {
                scan_cached_blocks_with_cache(
                    &NETWORK,
                    &source,
                    &mut db,
                    BlockHeight::from_u32(config.start + start),
                    from_state,
                    (end - start) as usize,
                    keys,
                )
            })
            .expect("scan synthetic blocks");
            let elapsed = t.elapsed();
            stats.scan += elapsed;
            stats.slowest_scan = stats.slowest_scan.max(elapsed);
            summary
        });
        stats.blocks += u64::from(end - start);
        stats.received += summary.received_orchard_note_count();
        stats.spent += summary.spent_orchard_note_count();
        start = end;
    }
}

#[test]
#[ignore = "benchmark: cargo test --release --lib scan_bench -- --ignored --nocapture"]
fn scan_bench() {
    let config = Config::from_env();
    assert!(config.notes_per_account > 0 && config.accounts > 0);
    println!(
        "[scan_bench] {} blocks from {}, {} accounts x {} notes, {} Orchard + {} Sapling \
         unrelated outputs per block, live tail {} blocks",
        config.blocks,
        config.start,
        config.accounts,
        config.notes_per_account,
        config.orchard_per_block,
        config.sapling_per_block,
        config.live_blocks,
    );

    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("bench_wallet.db");
    let db_path = db_path.to_str().expect("utf-8 temp path");

    let seeds: Vec<_> = (0..config.accounts).map(account_seed).collect();
    let birthday = Some(u64::from(config.start));
    init_db_and_create_account(db_path, NETWORK, &seeds[0], birthday, "bench 0")
        .expect("create bootstrap account");
    for (i, seed) in seeds.iter().enumerate().skip(1) {
        add_account(db_path, NETWORK, &format!("bench {i}"), seed, birthday)
            .expect("import account");
    }

    let t = Instant::now();
    let (chain, expected_receives, expected_spends) = generate_chain(&config, &seeds);
    let outputs: usize = chain
        .blocks
        .iter()
        .flat_map(|b| &b.vtx)
        .map(|tx| tx.actions.len() + tx.outputs.len())
        .sum();
    let outputs_per_block = outputs as f64 / f64::from(config.blocks);
    println!(
        "[scan_bench] generated {outputs} shielded outputs in {:.1}s (not timed below)",
        t.elapsed().as_secs_f64()
    );

    let catch_up_end = config.blocks - config.live_blocks;
    let mut catch_up = PhaseStats::default();
    if catch_up_end > 0 {
        scan_session(db_path, &config, &chain, 0, catch_up_end, &mut catch_up);
        catch_up.report("catch-up", outputs_per_block);
    }

    let mut live = PhaseStats::default();
    for offset in catch_up_end..config.blocks {
        scan_session(db_path, &config, &chain, offset, offset + 1, &mut live);
    }
    if config.live_blocks > 0 {
        live.report("live (1 block/session)", outputs_per_block);
    }

    assert_eq!(catch_up.received + live.received, expected_receives);
    assert_eq!(catch_up.spent + live.spent, expected_spends);
}
