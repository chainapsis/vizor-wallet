//! Invalidation tokens for snapshots actually inspected by Dart. Ordinary scans
//! above a registered snapshot do not write files or invalidate its decision.
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
static LOCK: Mutex<()> = Mutex::new(());
static GENERATION: AtomicU64 = AtomicU64::new(0);

/// Advisory cache failures must not block wallet sync. Each file contains only
/// a snapshot height (filename) and an opaque revision, never wallet notes.
pub fn record(db_path: &str, start_height: u64) {
    if let Err(error) = try_record(db_path, start_height) {
        log::warn!("Voting snapshot cache invalidation failed: {error}");
        let _ = std::fs::remove_file(format!("{db_path}.voting-cache/home-v2.json"));
    }
}

fn try_record(db_path: &str, start_height: u64) -> Result<(), String> {
    let _guard = LOCK.lock().map_err(|_| "Voting snapshot lock")?;
    let root = std::path::PathBuf::from(format!("{db_path}.voting-cache/snapshots"));
    let files = match std::fs::read_dir(&root) {
        Ok(files) => files,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(_) => return Err("Voting snapshot directory".into()),
    };
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "Voting snapshot clock")?
        .as_nanos();
    let revision = format!("{timestamp}-{}", GENERATION.fetch_add(1, Ordering::Relaxed));
    for entry in files {
        let entry = entry.map_err(|_| "Voting snapshot entry")?;
        let Some(height) = entry
            .file_name()
            .to_str()
            .and_then(|s| s.parse::<u64>().ok())
        else {
            continue;
        };
        if height < start_height {
            continue;
        }
        let temp = entry.path().with_extension("pending");
        use std::io::Write;
        let mut file = std::fs::File::create(&temp).map_err(|_| "Voting snapshot create")?;
        file.write_all(revision.as_bytes())
            .and_then(|_| file.sync_all())
            .map_err(|_| "Voting snapshot write")?;
        std::fs::rename(temp, entry.path()).map_err(|_| "Voting snapshot replace")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_registered_affected_snapshots_change_even_after_many_new_blocks() {
        let root = tempfile::tempdir().unwrap();
        let db = root.path().join("wallet.db");
        let db = db.to_str().unwrap();
        let snapshots = std::path::PathBuf::from(format!("{db}.voting-cache/snapshots"));
        try_record(db, 1).unwrap(); // No voting work yet: do not create a cache.
        assert!(!snapshots.exists());
        std::fs::create_dir_all(&snapshots).unwrap();
        let low = snapshots.join("100");
        let high = snapshots.join("200");
        std::fs::write(&low, "").unwrap();
        std::fs::write(&high, "").unwrap();
        try_record(db, 150).unwrap();
        assert_eq!(std::fs::read_to_string(&low).unwrap(), "");
        let high_revision = std::fs::read_to_string(&high).unwrap();
        assert!(!high_revision.is_empty());
        for height in 201..1000 {
            try_record(db, height).unwrap();
        }
        assert_eq!(std::fs::read_to_string(&low).unwrap(), "");
        assert_eq!(std::fs::read_to_string(&high).unwrap(), high_revision);
        try_record(db, 50).unwrap();
        assert!(!std::fs::read_to_string(&low).unwrap().is_empty());
        assert_ne!(std::fs::read_to_string(&high).unwrap(), high_revision);
        assert_eq!(std::fs::read_dir(snapshots).unwrap().count(), 2);
    }
}
