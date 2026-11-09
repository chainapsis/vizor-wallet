//! Bounded Activity reads. Summaries still cover the account; the expensive
//! details and outputs are loaded only for a sorted prefix and its TEX peers.

use std::cmp::Reverse;

use super::*;

/// `load` borrows the caller's existing read transaction, including on every
/// expansion. Each base is loaded once; dependencies may become candidates in
/// a later round without re-reading or re-attaching their history.
pub(super) fn assemble_recent_history(
    mut bases: Vec<TxBase>,
    uuid_bytes: &[u8],
    limit: u32,
    mut load: impl FnMut(&mut [TxBase]) -> Result<HashMap<Vec<u8>, Vec<TxOutput>>, String>,
) -> Result<Vec<TransactionInfo>, String> {
    let limit = limit as usize;
    if limit == 0 || bases.is_empty() {
        return Ok(Vec::new());
    }
    bases.sort_by_cached_key(|base| Reverse(base.history_sort_key()));

    // A TEX matching key also contains an amount learned from details/outputs.
    // Include the entire (created, expiry) group so competing same-amount pairs
    // keep their original insertion-order matching, however far apart in rank.
    let mut peers: HashMap<(&str, i64), Vec<usize>> = HashMap::new();
    for (index, base) in bases.iter().enumerate() {
        if let Some(created) = base.created.as_deref() {
            peers
                .entry((created, base.expiry_key()))
                .or_default()
                .push(index);
        }
    }
    let mut visited_groups = HashSet::new();
    let mut selected = vec![false; bases.len()];
    let mut loaded = Vec::new();
    let mut outputs = HashMap::new();
    let mut candidate_txids = HashSet::new();
    let mut previous_end = 0;
    let mut end = limit.saturating_mul(2).max(20).min(bases.len());
    loop {
        let mut added = Vec::new();
        for index in previous_end..end {
            let base = &bases[index];
            candidate_txids.insert(hex::encode(&base.txid));
            if !selected[index] {
                selected[index] = true;
                added.push(base.clone());
            }
            if let Some(created) = base.created.as_deref() {
                let key = (created, base.expiry_key());
                if visited_groups.insert(key) {
                    for &peer in &peers[&key] {
                        if !selected[peer] {
                            selected[peer] = true;
                            added.push(bases[peer].clone());
                        }
                    }
                }
            }
        }
        if !added.is_empty() {
            outputs.extend(load(&mut added)?);
            loaded.extend(added);
        }
        let mut rows = assemble_history(&loaded, &outputs, uuid_bytes, None);
        let all_loaded = loaded.len() == bases.len();
        if !all_loaded {
            // Peers affect suppression/fees, but do not fill the visible quota.
            rows.retain(|row| candidate_txids.contains(&row.txid_hex));
        }
        if rows.len() >= limit || all_loaded {
            // No unseen base can outrank this prefix: every row inherits its
            // transaction's HistorySortKey. Truncate only after classification.
            rows.truncate(limit);
            return Ok(rows);
        }
        previous_end = end;
        end = end.saturating_mul(2).min(bases.len());
    }
}
