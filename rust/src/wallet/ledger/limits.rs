//! Ledger Zcash app constraints shared by USB and Bluetooth signing.
//!
//! The supported 3.9.3 and 3.9.4 apps have the same record/review limits.
//! Actions are bounded **per pool**; reviewed shielded payments are bounded
//! **across both pools**, excluding change. These are independent budgets.
//! See `docs/ledger/limitations.md` for capabilities and enforcement points.
//!
//! Source: LedgerHQ/app-zcash 3.9.4, `1a0f6495458ecb77abf97c8cff25b0a1a344daaa`,
//! `src/consts.rs` and `src/parser/pczt.rs`. A version bump is not evidence
//! that these limits or the Orchard-to-Ironwood restriction have changed.

pub(crate) const MAX_TRANSPARENT_INPUTS: usize = 32;
pub(crate) const MAX_TRANSPARENT_OUTPUTS: usize = 10;
pub(crate) const MAX_SHIELDED_ACTIONS_PER_POOL: usize = 32;

/// Payments shown on the device, across Orchard and Ironwood. Internal
/// change is not displayed and does not consume this review budget.
pub(crate) const MAX_EXTERNAL_SHIELDED_OUTPUTS: usize = 4;

pub(super) fn ensure_count(label: &str, count: usize, maximum: usize) -> Result<(), String> {
    if count > maximum {
        Err(format!(
            "ledger_capacity: Ledger supports at most {maximum} {label}; found {count}"
        ))
    } else {
        Ok(())
    }
}

pub(crate) fn validate_external_shielded_outputs(
    orchard_outputs: usize,
    ironwood_outputs: usize,
) -> Result<(), String> {
    let count = orchard_outputs
        .checked_add(ironwood_outputs)
        .ok_or("ledger_capacity: Shielded output count overflow")?;
    ensure_count(
        "external shielded outputs per transaction",
        count,
        MAX_EXTERNAL_SHIELDED_OUTPUTS,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shielded_review_budget_is_independent_of_action_capacity() {
        validate_external_shielded_outputs(2, 2).unwrap();
        validate_external_shielded_outputs(4, 0).unwrap();
        assert!(validate_external_shielded_outputs(3, 2)
            .unwrap_err()
            .contains("at most 4"));
        assert_eq!(MAX_SHIELDED_ACTIONS_PER_POOL, 32);
    }
}
