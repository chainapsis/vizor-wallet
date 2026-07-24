// This is the native Vizor copy of the upstream pool-migration preparation planner.
// Keep its planning behavior aligned with zcash_pool_migration_backend::preparation.

//! Note-preparation transaction planning: how to restructure a wallet's spendable source-pool notes
//! into the exact self-funding notes a migration run needs, using transactions that each stay within
//! the [ZIP 318] action budget.
//!
//! # The problem
//!
//! The [`note_splitting`](super::note_splitting) planner decides the *values* of the self-funding
//! notes to mint. This module decides the *transactions* that mint them. [ZIP 318] requires each
//! note-preparation transaction to be padded to exactly [`PREP_TX_ACTIONS`] Orchard actions (a
//! mobile-proving-time and on-chain-uniformity constraint). Under NU6.3 a bundle's action count is
//! its spends plus its outputs, so one transaction can consume and produce at most
//! [`PREP_TX_ACTIONS`] notes in total (for example 15 spends and one output when consolidating, or
//! one spend and 15 outputs when splitting). A splitting transaction therefore mints MANY funding
//! notes at once, one output per scheduled part (up to [`FUNDING_OUTPUTS_PER_TX`]); the number of
//! funding notes in a preparation transaction is not one. The one-transaction-per-part shape belongs
//! to the phase-2 crossing transfers (each spends a single funding note), not to preparation.
//!
//! A single transaction therefore cannot always turn the wallet's notes into every funding note: a
//! note that must fan out into more outputs than one transaction holds, or a balance spread across
//! more SUB-QUANTUM notes (each below the smallest funding denomination, so too small to fund a
//! crossing on its own; not to be confused with sub-fee "dust") than one transaction can consume,
//! needs **layers**. A layer is a set of
//! transactions with no dependencies between them (buildable, provable, and broadcastable in
//! parallel); a later layer may spend the outputs of an earlier one, but only after they are mined
//! and a boundary passes, so each extra layer extends the preparation phase by roughly one anchor
//! bucket. The planner therefore prefers fewer layers (which dominate the wall-clock) over fewer
//! transactions.
//!
//! # The strategy
//!
//! The planner is a largest-first layered greedy. In each layer it feeds each output transaction from
//! the largest available note it can (one big note funds up to [`FUNDING_OUTPUTS_PER_TX`] funding
//! notes), routes every leftover forward as an intermediate ("feeder") note, and consolidates
//! sub-quantum notes (too small to fund anything on their own) into feeder notes. Once all funding
//! notes are scheduled it consolidates the feeders that no layer spent into a single residual note,
//! matching ZIP 318's "one note per part plus at most one residual note". For a typical wallet (a few
//! notes, a handful of funding notes) this is a single layer; extra layers appear only for a lone
//! large note fanning out into many funding notes, or a sub-quantum-heavy balance.
//!
//! The single-residual goal is only reachable above the fee threshold. When several transactions each
//! strand a remainder smaller than a transaction fee and those remainders together are still worth
//! less than one fee, no consolidation can merge them (its output would be negative), so they remain
//! as multiple sub-fee change notes. The planner therefore guarantees at most one residual note worth a
//! fee; any further residue is sub-fee dust.
//!
//! When a single note can produce every funding note, the planner takes a fan-out fast path: it splits
//! that note through a BALANCED tree (fanning out by [`FUNDING_OUTPUTS_PER_TX`] per layer), so the
//! depth is logarithmic in the funding-note count rather than linear in it. The balanced tree uses more
//! transactions, and so more fee, than a linear feeder chain would; it trades that for fewer layers,
//! which dominate the wall-clock. Every other shape (many notes, mixed sizes, sub-quantum) uses the
//! layered greedy above.
//!
//! This is a pure planner: it works in note *values* (in zatoshi) and does no cryptography or I/O. It
//! reserves a fixed per-transaction fee (the caller passes the ZIP-317 fee of a padded
//! [`PREP_TX_ACTIONS`]-action transaction) out of each transaction's inputs; the builder later
//! absorbs the real fee into the change.
//!
//! [ZIP 318]: https://zips.z.cash/zip-0318

use std::vec::Vec;

use zcash_protocol::value::Zatoshis;

use core::fmt;

/// The exact number of Orchard actions in every note-preparation transaction ([ZIP 318]): each is
/// padded up to this count, so no preparation transaction is distinguishable from another by its
/// action count, and one transaction handles at most this many notes in total (spends plus outputs).
///
/// [ZIP 318]: https://zips.z.cash/zip-0318
pub const PREP_TX_ACTIONS: usize = 16;

/// The most funding (or feeder) outputs one transaction produces from a single input: the action
/// budget less that one input and one change/feeder slot (`16 - 1 - 1`).
pub const FUNDING_OUTPUTS_PER_TX: usize = PREP_TX_ACTIONS - 2;

/// The most notes one transaction consolidates: the action budget less the single output it produces
/// (`16 - 1`).
pub const CONSOLIDATION_INPUTS_PER_TX: usize = PREP_TX_ACTIONS - 1;

/// A note a preparation transaction spends: either one of the wallet's original spendable notes, or a
/// note an earlier layer produced. Each variant carries the note's `value` (in zatoshi).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrepInput {
    /// The wallet note at this `index` in the caller-supplied `available` slice, worth `value`.
    Wallet { index: usize, value: Zatoshis },
    /// The `output`-th output of the `transaction`-th transaction of an earlier `layer`, worth
    /// `value`.
    Prior {
        layer: usize,
        transaction: usize,
        output: usize,
        value: Zatoshis,
    },
}

impl PrepInput {
    /// The note value this input carries.
    pub fn value(&self) -> Zatoshis {
        match self {
            PrepInput::Wallet { value, .. } | PrepInput::Prior { value, .. } => *value,
        }
    }
}

/// A note a preparation transaction produces.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrepOutput {
    /// A final self-funding note: one of the requested funding values.
    Funding(Zatoshis),
    /// An intermediate ("feeder") note, spent by a later layer to route value forward.
    Intermediate(Zatoshis),
    /// Leftover value returned to the source pool.
    Change(Zatoshis),
}

impl PrepOutput {
    /// The note value this output carries.
    pub fn value(&self) -> Zatoshis {
        match self {
            PrepOutput::Funding(v) | PrepOutput::Intermediate(v) | PrepOutput::Change(v) => *v,
        }
    }

    /// Reconstruct an output from its stored `role` (the [`AsRef<str>`](AsRef) discriminant) and its
    /// value, so a persistence backend can round-trip it through typed columns rather than a blob.
    pub fn from_role(role: &str, value: Zatoshis) -> Result<Self, ParsePrepOutputError> {
        Ok(match role {
            "funding" => PrepOutput::Funding(value),
            "intermediate" => PrepOutput::Intermediate(value),
            "change" => PrepOutput::Change(value),
            _ => return Err(ParsePrepOutputError),
        })
    }
}

impl AsRef<str> for PrepOutput {
    /// The stable lowercase wire name of this output's role, as a store persists it (paired with
    /// [`value`](Self::value)); parsed back with [`from_role`](Self::from_role).
    fn as_ref(&self) -> &str {
        match self {
            PrepOutput::Funding(_) => "funding",
            PrepOutput::Intermediate(_) => "intermediate",
            PrepOutput::Change(_) => "change",
        }
    }
}

/// The error returned when a string does not name a [`PrepOutput`] role (its
/// [`from_role`](PrepOutput::from_role) constructor).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ParsePrepOutputError;

impl fmt::Display for ParsePrepOutputError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("unrecognized preparation output role")
    }
}

/// One note-preparation transaction: a same-pool send-to-self, padded at build time to
/// [`PREP_TX_ACTIONS`] actions. Its logical action count (`inputs.len() + outputs.len()`) never
/// exceeds that budget.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PrepTransaction {
    inputs: Vec<PrepInput>,
    outputs: Vec<PrepOutput>,
}

impl PrepTransaction {
    /// Construct a transaction from its spent and produced notes. Used to reconstruct a persisted plan
    /// (the inverse of [`inputs`](Self::inputs) plus [`outputs`](Self::outputs)); the caller supplies
    /// parts a valid plan could have produced.
    pub fn from_parts(inputs: Vec<PrepInput>, outputs: Vec<PrepOutput>) -> Self {
        PrepTransaction { inputs, outputs }
    }

    /// The notes this transaction spends.
    pub fn inputs(&self) -> &[PrepInput] {
        &self.inputs
    }

    /// The notes this transaction produces.
    pub fn outputs(&self) -> &[PrepOutput] {
        &self.outputs
    }

    /// The logical Orchard action count before padding (`inputs + outputs`).
    pub fn action_count(&self) -> usize {
        self.inputs.len() + self.outputs.len()
    }
}

/// A schedule of note-preparation transactions grouped into sequential layers. Every transaction in a
/// layer is independent of the others in that layer; a transaction may spend a [`PrepInput::Prior`]
/// output only from a strictly earlier layer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreparationPlan {
    layers: Vec<Vec<PrepTransaction>>,
    /// Wallet notes (by their index in `available`) already equal to a funding value, used directly as
    /// that funding note with no preparation transaction, paired with that value.
    direct_funding: Vec<(usize, Zatoshis)>,
}

impl PreparationPlan {
    /// Reconstruct a plan from its parts: the layers in dependency order (see [`layers`](Self::layers))
    /// and the direct-funding notes (see [`direct_funding_notes`](Self::direct_funding_notes)). Used by
    /// a store to round-trip a persisted plan; the caller supplies parts a valid plan could have
    /// produced (no validation beyond what the accessors expose is done here).
    pub fn from_parts(
        layers: Vec<Vec<PrepTransaction>>,
        direct_funding: Vec<(usize, Zatoshis)>,
    ) -> Self {
        PreparationPlan {
            layers,
            direct_funding,
        }
    }

    /// The layers, in dependency order (later layers may spend earlier layers' outputs).
    pub fn layers(&self) -> &[Vec<PrepTransaction>] {
        &self.layers
    }

    /// The number of sequential layers (the depth that governs the preparation phase's duration).
    pub fn layer_count(&self) -> usize {
        self.layers.len()
    }

    /// The total number of preparation transactions across all layers.
    pub fn transaction_count(&self) -> usize {
        self.layers.iter().map(Vec::len).sum()
    }

    /// An iterator over every output of every transaction, in plan (layer then transaction) order.
    fn all_outputs(&self) -> impl Iterator<Item = &PrepOutput> {
        self.layers
            .iter()
            .flatten()
            .flat_map(PrepTransaction::outputs)
    }

    /// Wallet notes (by their index in the caller's `available` slice) already equal to a funding
    /// value, used directly as that funding note with no preparation transaction, each paired with
    /// that value. The caller must leave these notes unspent by preparation.
    pub fn direct_funding_notes(&self) -> &[(usize, Zatoshis)] {
        &self.direct_funding
    }

    /// The values of the self-funding notes this plan mints, both the [`PrepOutput::Funding`] outputs
    /// its transactions create and the wallet notes used directly (see
    /// [`direct_funding_notes`](Self::direct_funding_notes)): the notes the migration transfers will
    /// each spend.
    pub fn funding_notes(&self) -> Vec<Zatoshis> {
        let mut out: Vec<Zatoshis> = self
            .all_outputs()
            .filter_map(|o| match o {
                PrepOutput::Funding(v) => Some(*v),
                _ => None,
            })
            .collect();
        out.extend(self.direct_funding.iter().map(|&(_, v)| v));
        out
    }

    /// The values of the residual notes this plan leaves in the source pool (its
    /// [`PrepOutput::Change`] outputs): at most one worth a fee, plus any sub-fee dust.
    pub fn residual_notes(&self) -> Vec<Zatoshis> {
        self.all_outputs()
            .filter_map(|o| match o {
                PrepOutput::Change(v) => Some(*v),
                _ => None,
            })
            .collect()
    }

    /// The number of residual notes this plan leaves (see
    /// [`residual_notes`](Self::residual_notes)).
    pub fn residual_count(&self) -> usize {
        self.residual_notes().len()
    }
}

/// Why a preparation plan could not be produced.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrepError {
    /// The available notes cannot fund every requested funding note plus the per-transaction fees.
    InsufficientFunds,
    /// The total of the available (or requested funding) note values exceeds the maximum money
    /// supply, so no consistent plan exists.
    BalanceInvalid,
}

impl fmt::Display for PrepError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PrepError::InsufficientFunds => {
                f.write_str("available notes cannot fund the requested notes plus preparation fees")
            }
            PrepError::BalanceInvalid => {
                f.write_str("the note values exceed the maximum money supply in total")
            }
        }
    }
}

impl core::error::Error for PrepError {}

/// Convert a planner-internal value to [`Zatoshis`]. Infallible by construction:
/// [`plan_preparation`] validates the available and funding totals at entry, and the affordability
/// checks bound every note the plan mints by the validated available total.
fn zat(value: u64) -> Zatoshis {
    Zatoshis::from_u64(value).expect("planner values are bounded by the validated totals")
}

/// Plan the note-preparation transactions that mint `funding` (the self-funding note values, in
/// zatoshi) from `available` (the wallet's spendable source-pool note values, in zatoshi), reserving
/// `fee_per_tx` zatoshi for each transaction (the ZIP-317 fee of a padded [`PREP_TX_ACTIONS`]-action
/// transaction).
///
/// Returns an empty plan when `funding` is empty, and [`PrepError::InsufficientFunds`] when the
/// available value cannot cover the funding notes plus the per-transaction fees.
pub fn plan_preparation(
    available: &[Zatoshis],
    funding: &[Zatoshis],
    fee_per_tx: Zatoshis,
) -> Result<PreparationPlan, PrepError> {
    // Validate once that the available and requested totals are representable amounts. Combined
    // with the affordability checks below (a note is only ever minted out of value the available
    // notes actually carry), every value the plan constructs is bounded by the validated available
    // total, which is what makes the internal [`zat`] conversions infallible.
    let _: Zatoshis = available
        .iter()
        .copied()
        .sum::<Option<Zatoshis>>()
        .ok_or(PrepError::BalanceInvalid)?;
    let _: Zatoshis = funding
        .iter()
        .copied()
        .sum::<Option<Zatoshis>>()
        .ok_or(PrepError::BalanceInvalid)?;
    // The partition arithmetic below runs in the u64 domain.
    let available: Vec<u64> = available.iter().map(|&v| u64::from(v)).collect();
    let fee_per_tx = u64::from(fee_per_tx);

    // Funding values still to produce, largest first (so `last()` is the smallest).
    let mut remaining: Vec<u64> = funding
        .iter()
        .map(|&v| u64::from(v))
        .filter(|&v| v > 0)
        .collect();
    remaining.sort_unstable_by(|a, b| b.cmp(a));

    // Exact-match pass: a wallet note already equal to a funding value IS that funding note, so it is
    // used directly, with no preparation transaction and no fee. The matched notes are removed from
    // both the funding still to produce and the notes available to spend.
    let mut used = vec![false; available.len()];
    let mut direct_funding: Vec<(usize, Zatoshis)> = Vec::new();
    remaining.retain(|&f| {
        match available
            .iter()
            .enumerate()
            .position(|(i, &v)| !used[i] && v == f)
        {
            Some(i) => {
                used[i] = true;
                direct_funding.push((i, zat(f)));
                false
            }
            None => true,
        }
    });

    let mut layers: Vec<Vec<PrepTransaction>> = Vec::new();
    if remaining.is_empty() {
        return Ok(PreparationPlan {
            layers,
            direct_funding,
        });
    }

    // Fan-out fast path: when a single wallet note can produce every remaining funding note, split it
    // through a balanced tree (depth logarithmic in the note count) rather than the linear feeder chain
    // the layered loop below would build for a lone large note. Only that case takes this path;
    // everything else (many notes, mixed sizes, sub-quantum) falls through to the layered greedy
    // unchanged.
    // Trade-off: the balanced tree uses more transactions (fees) than the chain, buying fewer layers.
    if let Some((idx, big)) = available
        .iter()
        .enumerate()
        .filter(|(i, _)| !used[*i])
        .map(|(i, &v)| (i, v))
        .max_by_key(|&(_, v)| v)
    {
        if big >= subtree_cost(&remaining, fee_per_tx).1 {
            build_split(
                PrepInput::Wallet {
                    index: idx,
                    value: zat(big),
                },
                big,
                &remaining,
                fee_per_tx,
                0,
                &mut layers,
            );
            remaining.clear();
        }
    }

    // The notes available to spend in the current layer (layer 0: the wallet's own notes not already
    // used directly as funding notes).
    let mut current: Vec<PrepInput> = available
        .iter()
        .enumerate()
        .filter(|(i, _)| !used[*i])
        .map(|(i, &v)| PrepInput::Wallet {
            index: i,
            value: zat(v),
        })
        .collect();

    while !remaining.is_empty() {
        if current.is_empty() {
            return Err(PrepError::InsufficientFunds);
        }
        // Largest notes first.
        current.sort_unstable_by_key(|n| core::cmp::Reverse(u64::from(n.value())));

        // Pass 1: assign funding to the notes that can fund at least the smallest remaining note.
        // `partial` holds a note, the funding values it will mint, and its leftover budget; the rest
        // go to `consolidatable` to be combined into feeder notes.
        let mut partial: Vec<(PrepInput, Vec<u64>, u64)> = Vec::new();
        let mut consolidatable: Vec<PrepInput> = Vec::new();

        for input in current.drain(..) {
            if remaining.is_empty() {
                // Everything is already scheduled; this note stays unspent in the wallet.
                continue;
            }
            let value = u64::from(input.value());
            let smallest = *remaining.last().expect("remaining is non-empty");
            if value <= fee_per_tx || value - fee_per_tx < smallest {
                consolidatable.push(input);
                continue;
            }
            let budget = value - fee_per_tx;
            let mut assigned = Vec::new();
            let mut used = 0u64;
            let mut i = 0;
            while i < remaining.len() && assigned.len() < FUNDING_OUTPUTS_PER_TX {
                if used + remaining[i] <= budget {
                    used += remaining[i];
                    assigned.push(remaining.remove(i));
                } else {
                    i += 1;
                }
            }
            // `value - fee_per_tx >= smallest` guarantees at least the smallest note was assignable.
            debug_assert!(!assigned.is_empty());
            partial.push((input, assigned, budget - used));
        }

        // Pass 2: mint the funding notes, routing every leftover forward as a feeder so a later layer
        // reuses it rather than scattering change.
        let mut txs: Vec<PrepTransaction> = Vec::new();
        let mut next: Vec<PrepInput> = Vec::new();
        for (input, assigned, leftover) in partial {
            let mut outputs: Vec<PrepOutput> = assigned
                .into_iter()
                .map(|v| PrepOutput::Funding(zat(v)))
                .collect();
            if leftover > 0 {
                next.push(PrepInput::Prior {
                    layer: layers.len(),
                    transaction: txs.len(),
                    output: outputs.len(),
                    value: zat(leftover),
                });
                outputs.push(PrepOutput::Intermediate(zat(leftover)));
            }
            txs.push(PrepTransaction {
                inputs: vec![input],
                outputs,
            });
        }

        // Consolidate notes too small to fund anything into feeders for a later layer.
        consolidate(
            consolidatable,
            layers.len(),
            fee_per_tx,
            &mut txs,
            &mut next,
        );

        if txs.is_empty() {
            // No note in this layer could fund or usefully consolidate: the balance is insufficient.
            return Err(PrepError::InsufficientFunds);
        }
        layers.push(txs);
        current = next;
    }

    // The funding notes are all scheduled. Consolidate every leftover feeder that no layer spends into
    // a single residual note (ZIP 318 prepares one note per part plus at most one residual note), for
    // as long as that is worth a transaction; a remainder too small to pay a fee is left as change.
    loop {
        let pool = unconsumed_feeders(&layers);
        if pool.len() <= 1 {
            break;
        }
        let mut txs: Vec<PrepTransaction> = Vec::new();
        let mut next: Vec<PrepInput> = Vec::new();
        consolidate(pool, layers.len(), fee_per_tx, &mut txs, &mut next);
        if txs.is_empty() {
            break; // the remainder is sub-fee dust; leave it as change
        }
        layers.push(txs);
    }
    let _ = current; // the residual pool is recomputed above, so the last `next` is unused

    // Relabel any feeder note that no later layer ends up spending as source-pool change, so the plan
    // has no dangling intermediates and value is conserved end to end.
    let mut spent: Vec<(usize, usize, usize)> = Vec::new();
    for layer in &layers {
        for tx in layer {
            for input in &tx.inputs {
                if let PrepInput::Prior {
                    layer,
                    transaction,
                    output,
                    ..
                } = input
                {
                    spent.push((*layer, *transaction, *output));
                }
            }
        }
    }
    for (li, layer) in layers.iter_mut().enumerate() {
        for (ti, tx) in layer.iter_mut().enumerate() {
            for (oi, out) in tx.outputs.iter_mut().enumerate() {
                if let PrepOutput::Intermediate(v) = *out {
                    if !spent.contains(&(li, ti, oi)) {
                        *out = PrepOutput::Change(v);
                    }
                }
            }
        }
    }

    Ok(PreparationPlan {
        layers,
        direct_funding,
    })
}

/// Split `n` notes into consolidation batches of at most [`CONSOLIDATION_INPUTS_PER_TX`], never
/// leaving a batch of one (which would waste a fee without reducing the note count). Assumes `n >= 2`.
fn consolidation_batch_sizes(mut n: usize) -> Vec<usize> {
    let max = CONSOLIDATION_INPUTS_PER_TX;
    let mut sizes = Vec::new();
    while n > 0 {
        let take = if n <= max {
            n
        } else if n - max == 1 {
            max - 1 // leave 2 for the final batch rather than a lone note
        } else {
            max
        };
        sizes.push(take);
        n -= take;
    }
    sizes
}

/// Consolidate `pool` into feeder notes: append one consolidation transaction per batch (of at most
/// [`CONSOLIDATION_INPUTS_PER_TX`] inputs) to `txs` in layer `layer`, with its feeder pushed to
/// `next`. Returns any notes whose batch could not cover the fee (too small to consolidate).
fn consolidate(
    mut pool: Vec<PrepInput>,
    layer: usize,
    fee: u64,
    txs: &mut Vec<PrepTransaction>,
    next: &mut Vec<PrepInput>,
) -> Vec<PrepInput> {
    if pool.len() < 2 {
        return pool;
    }
    pool.sort_unstable_by_key(|n| core::cmp::Reverse(u64::from(n.value())));
    let mut leftover = Vec::new();
    for size in consolidation_batch_sizes(pool.len()) {
        let batch: Vec<PrepInput> = pool.drain(..size).collect();
        let sum: u64 = batch.iter().map(|n| u64::from(n.value())).sum();
        if sum <= fee {
            leftover.extend(batch); // too small to pay a fee; leave unspent
            continue;
        }
        let feeder = sum - fee;
        next.push(PrepInput::Prior {
            layer,
            transaction: txs.len(),
            output: 0,
            value: zat(feeder),
        });
        txs.push(PrepTransaction {
            inputs: batch,
            outputs: vec![PrepOutput::Intermediate(zat(feeder))],
        });
    }
    leftover
}

/// Every intermediate ("feeder") output that no transaction spends, as [`PrepInput`] references (each
/// carrying its value).
fn unconsumed_feeders(layers: &[Vec<PrepTransaction>]) -> Vec<PrepInput> {
    let mut spent: Vec<(usize, usize, usize)> = Vec::new();
    for layer in layers {
        for tx in layer {
            for input in &tx.inputs {
                if let PrepInput::Prior {
                    layer,
                    transaction,
                    output,
                    ..
                } = input
                {
                    spent.push((*layer, *transaction, *output));
                }
            }
        }
    }
    let mut out = Vec::new();
    for (li, layer) in layers.iter().enumerate() {
        for (ti, tx) in layer.iter().enumerate() {
            for (oi, output) in tx.outputs.iter().enumerate() {
                if let PrepOutput::Intermediate(v) = output {
                    if !spent.contains(&(li, ti, oi)) {
                        out.push(PrepInput::Prior {
                            layer: li,
                            transaction: ti,
                            output: oi,
                            value: *v,
                        });
                    }
                }
            }
        }
    }
    out
}

/// The most funding notes a balanced split subtree of the given `depth` can produce: each level fans
/// out by [`FUNDING_OUTPUTS_PER_TX`] (one input, the rest outputs), so a depth-`d` subtree holds up to
/// `FUNDING_OUTPUTS_PER_TX^d` funding notes (a depth-1 leaf holds one full transaction of them).
fn subtree_capacity(depth: usize) -> usize {
    FUNDING_OUTPUTS_PER_TX.pow(depth as u32)
}

/// The fewest balanced-split layers that produce `n` funding notes from one source note (the depth `d`
/// with `subtree_capacity(d) >= n`). Zero for `n == 0`.
fn split_depth(n: usize) -> usize {
    if n == 0 {
        return 0;
    }
    let mut depth = 1;
    while subtree_capacity(depth) < n {
        depth += 1;
    }
    depth
}

/// Group sizes for splitting `len` targets into `g` contiguous groups as evenly as possible (the first
/// `len % g` groups get one extra).
fn even_group_sizes(len: usize, g: usize) -> Vec<usize> {
    let base = len / g;
    let extra = len % g;
    (0..g).map(|i| base + usize::from(i < extra)).collect()
}

/// The transaction count and the value a single source note must carry to produce exactly `targets`
/// (the funding notes) through a balanced split tree: each transaction costs one `fee`, and the tree
/// fans out by [`FUNDING_OUTPUTS_PER_TX`] until each leaf holds at most that many funding notes.
fn subtree_cost(targets: &[u64], fee: u64) -> (u64, u64) {
    let depth = split_depth(targets.len());
    if depth <= 1 {
        return (1, targets.iter().sum::<u64>() + fee);
    }
    let child_cap = subtree_capacity(depth - 1);
    let g = targets.len().div_ceil(child_cap);
    let mut start = 0;
    let mut txs = 1u64;
    let mut value = fee;
    for size in even_group_sizes(targets.len(), g) {
        let (t, v) = subtree_cost(&targets[start..start + size], fee);
        txs += t;
        value += v;
        start += size;
    }
    (txs, value)
}

/// Build a balanced split of `source` (a note reference worth `source_value`) into the funding notes
/// `targets`, appending transactions to `layers` from `layer` downwards. Each transaction funds up to
/// [`FUNDING_OUTPUTS_PER_TX`] notes directly at a leaf, or fans out into up to that many feeder notes
/// (one per child subtree) at an internal node, so the depth is [`split_depth`] of the target count
/// rather than linear in it. Only the top call (the whole source note) carries a leftover; it is
/// emitted as an intermediate feeder so the residual pass merges it. The internal feeders are exact.
fn build_split(
    source: PrepInput,
    source_value: u64,
    targets: &[u64],
    fee: u64,
    layer: usize,
    layers: &mut Vec<Vec<PrepTransaction>>,
) {
    while layers.len() <= layer {
        layers.push(Vec::new());
    }
    let tx_index = layers[layer].len();
    let depth = split_depth(targets.len());

    if depth <= 1 {
        // Leaf: fund every target directly, with any leftover as an intermediate (residual) note.
        let mut outputs: Vec<PrepOutput> = targets
            .iter()
            .map(|&v| PrepOutput::Funding(zat(v)))
            .collect();
        let spent: u64 = targets.iter().sum();
        let leftover = source_value - fee - spent;
        if leftover > 0 {
            outputs.push(PrepOutput::Intermediate(zat(leftover)));
        }
        layers[layer].push(PrepTransaction {
            inputs: vec![source],
            outputs,
        });
        return;
    }

    // Internal node: fan out into one feeder per child subtree.
    let child_cap = subtree_capacity(depth - 1);
    let g = targets.len().div_ceil(child_cap);
    let sizes = even_group_sizes(targets.len(), g);

    let mut groups: Vec<(usize, usize)> = Vec::new(); // (start, size)
    let mut child_values: Vec<u64> = Vec::new();
    let mut start = 0;
    for size in sizes {
        child_values.push(subtree_cost(&targets[start..start + size], fee).1);
        groups.push((start, size));
        start += size;
    }

    let mut outputs: Vec<PrepOutput> = child_values
        .iter()
        .map(|&v| PrepOutput::Intermediate(zat(v)))
        .collect();
    let spent: u64 = child_values.iter().sum();
    let leftover = source_value - fee - spent;
    if leftover > 0 {
        outputs.push(PrepOutput::Intermediate(zat(leftover)));
    }
    layers[layer].push(PrepTransaction {
        inputs: vec![source],
        outputs,
    });

    for (output, ((gstart, gsize), &cv)) in groups.iter().zip(child_values.iter()).enumerate() {
        let child = PrepInput::Prior {
            layer,
            transaction: tx_index,
            output,
            value: zat(cv),
        };
        build_split(
            child,
            cv,
            &targets[*gstart..*gstart + *gsize],
            fee,
            layer + 1,
            layers,
        );
    }
}
