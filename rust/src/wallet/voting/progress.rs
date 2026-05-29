use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, OnceLock,
    },
};

type AccountKey = (String, String);
type RoundKey = (String, String, String);

static ACCOUNT_CANCEL_EPOCHS: OnceLock<Mutex<HashMap<AccountKey, u64>>> = OnceLock::new();
static ROUND_CANCEL_EPOCHS: OnceLock<Mutex<HashMap<RoundKey, u64>>> = OnceLock::new();

fn account_epochs() -> &'static Mutex<HashMap<AccountKey, u64>> {
    ACCOUNT_CANCEL_EPOCHS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn round_epochs() -> &'static Mutex<HashMap<RoundKey, u64>> {
    ROUND_CANCEL_EPOCHS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Cancellation handle for long-running voting work.
///
/// `spawn_blocking` proof generation cannot be force-killed safely, but callers
/// can invalidate work before it starts, at upstream progress callbacks, and
/// before any late result is persisted or returned to Dart.
#[derive(Clone)]
pub struct VotingWorkCancellation {
    account_key: AccountKey,
    round_key: Option<RoundKey>,
    account_epoch: u64,
    round_epoch: u64,
    local_cancelled: Arc<AtomicBool>,
}

impl VotingWorkCancellation {
    pub fn start(db_path: &str, wallet_id: &str, round_id: Option<&str>) -> Result<Self, String> {
        let account_key = (db_path.to_string(), wallet_id.to_string());
        let account_epoch = account_epochs()
            .lock()
            .map_err(|e| format!("voting cancellation account lock poisoned: {e}"))?
            .get(&account_key)
            .copied()
            .unwrap_or(0);

        let round_key = round_id
            .filter(|round_id| !round_id.is_empty())
            .map(|round_id| {
                (
                    db_path.to_string(),
                    wallet_id.to_string(),
                    round_id.to_string(),
                )
            });
        let round_epoch = if let Some(round_key) = &round_key {
            round_epochs()
                .lock()
                .map_err(|e| format!("voting cancellation round lock poisoned: {e}"))?
                .get(round_key)
                .copied()
                .unwrap_or(0)
        } else {
            0
        };

        Ok(Self {
            account_key,
            round_key,
            account_epoch,
            round_epoch,
            local_cancelled: Arc::new(AtomicBool::new(false)),
        })
    }

    pub fn cancel_local(&self) {
        self.local_cancelled.store(true, Ordering::SeqCst);
    }

    pub fn check(&self) -> Result<(), String> {
        if self.local_cancelled.load(Ordering::SeqCst) {
            return Err("Voting work cancelled".to_string());
        }

        let current_account_epoch = account_epochs()
            .lock()
            .map_err(|e| format!("voting cancellation account lock poisoned: {e}"))?
            .get(&self.account_key)
            .copied()
            .unwrap_or(0);
        if current_account_epoch != self.account_epoch {
            return Err("Voting work cancelled".to_string());
        }

        if let Some(round_key) = &self.round_key {
            let current_round_epoch = round_epochs()
                .lock()
                .map_err(|e| format!("voting cancellation round lock poisoned: {e}"))?
                .get(round_key)
                .copied()
                .unwrap_or(0);
            if current_round_epoch != self.round_epoch {
                return Err("Voting work cancelled".to_string());
            }
        }

        Ok(())
    }
}

impl zcash_voting::Cancellation for VotingWorkCancellation {
    fn is_cancelled(&self) -> bool {
        self.check().is_err()
    }
}

pub fn cancel_voting_work(
    db_path: &str,
    wallet_id: &str,
    round_id: Option<&str>,
) -> Result<(), String> {
    if let Some(round_id) = round_id.filter(|round_id| !round_id.is_empty()) {
        let round_key = (
            db_path.to_string(),
            wallet_id.to_string(),
            round_id.to_string(),
        );
        let mut epochs = round_epochs()
            .lock()
            .map_err(|e| format!("voting cancellation round lock poisoned: {e}"))?;
        let epoch = epochs.entry(round_key).or_insert(0);
        *epoch = epoch.saturating_add(1);
    } else {
        let account_key = (db_path.to_string(), wallet_id.to_string());
        let mut epochs = account_epochs()
            .lock()
            .map_err(|e| format!("voting cancellation account lock poisoned: {e}"))?;
        let epoch = epochs.entry(account_key).or_insert(0);
        *epoch = epoch.saturating_add(1);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_voting::Cancellation;

    #[test]
    fn cancellation_epoch_invalidates_existing_round_work() {
        let work =
            VotingWorkCancellation::start("/tmp/voting-progress.sqlite", "account", Some("round"))
                .unwrap();
        assert!(work.check().is_ok());

        cancel_voting_work("/tmp/voting-progress.sqlite", "account", Some("round")).unwrap();
        assert!(work.check().unwrap_err().contains("cancelled"));
        assert!(work.is_cancelled());
    }
}
