use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
};

use zcash_pool_migration_backend::engine::MigrationPlan;

type Key = (PathBuf, [u8; 16]);

#[derive(Clone)]
pub(super) struct CachedPlan {
    pub(super) plan: MigrationPlan,
    pub(super) tip: zcash_protocol::consensus::BlockHeight,
}

fn plans() -> &'static Mutex<HashMap<Key, CachedPlan>> {
    static PLANS: OnceLock<Mutex<HashMap<Key, CachedPlan>>> = OnceLock::new();
    PLANS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(super) fn set(
    db_path: PathBuf,
    account: [u8; 16],
    plan: MigrationPlan,
    tip: zcash_protocol::consensus::BlockHeight,
) {
    plans()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert((db_path, account), CachedPlan { plan, tip });
}

pub(super) fn get(db_path: &Path, account: [u8; 16]) -> Option<CachedPlan> {
    plans()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .get(&(db_path.to_path_buf(), account))
        .cloned()
}

pub(super) fn clear(db_path: &Path, account: [u8; 16]) {
    plans()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&(db_path.to_path_buf(), account));
}
