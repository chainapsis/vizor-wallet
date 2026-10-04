//! Base-tree stand-in for `current.rs`: `test-db-upgrade.sh` copies it over
//! `current.rs` in the base worktree. The base build only runs `create` and
//! `open-old`, which never reach these.

use std::collections::BTreeSet;

use super::ApiSnapshot;

pub fn expected_current_api(_db_path: &str, _base: &ApiSnapshot) -> ApiSnapshot {
    unreachable!("verify runs on the current build")
}

pub fn assert_current_api(_db_path: &str, _api: &ApiSnapshot) {
    unreachable!("verify runs on the current build")
}

pub fn spendable_outputs(
    _db_path: &str,
    _addresses: &BTreeSet<String>,
    _tip: u32,
) -> BTreeSet<(String, u32, u64)> {
    unreachable!("verify runs on the current build")
}
