//! NEAR Intents as the receiver directory's feed sees it: every address a wallet gave it,
//! when, and in which role.

use zakura_one_time_ivk::swap::RESTORE_WATCH_SECS;
use zakura_pir_receiver::receiver_directory::{snapshot::ProviderSet, Receiver};

use super::chain::{DAY, MINUTE};

/// What NEAR was given an address as.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
    /// An X-to-ZEC payout address (an incoming key).
    Payout,
    /// A ZEC-to-X refund address (a refund key).
    Refund,
}

/// NEAR's view of the addresses wallets gave it, and the feed the directory reads.
pub struct Near {
    given: Vec<([u8; 43], i64, Role)>,
    /// When the directory's feed started reading NEAR.
    feed_started: i64,
    /// How long before a publication the feed's last complete read began.
    read_lag: i64,
    deposits: u32,
}

impl Near {
    /// A feed that has been reading NEAR for a month before `now`.
    pub fn new(now: i64) -> Self {
        Self {
            given: Vec::new(),
            feed_started: now - 30 * DAY,
            read_lag: MINUTE,
            deposits: 0,
        }
    }

    /// Records that NEAR was given `receiver` at `at`.
    pub fn give(&mut self, receiver: [u8; 43], at: i64, role: Role) {
        self.given.push((receiver, at, role));
    }

    /// A fresh deposit address on the source chain, for an incoming quote.
    pub fn deposit_address(&mut self) -> String {
        self.deposits += 1;
        format!("near-deposit-{:04}", self.deposits)
    }

    /// The provider sets a publication made at `now` carries: `near-intents/recent`
    /// (addresses given in the day before the last read) and `near-intents/seen`
    /// (addresses given since the feed started), each holding payout and refund
    /// addresses.
    pub fn sets(&self, now: i64) -> Vec<ProviderSet> {
        let until = now - self.read_lag;
        let window = RESTORE_WATCH_SECS;
        let recent = self
            .given
            .iter()
            .filter(|(_, at, _)| *at <= until && *at > until - window)
            .map(|(r, _, _)| *r);
        let seen = self
            .given
            .iter()
            .filter(|(_, at, _)| *at >= self.feed_started && *at <= until)
            .map(|(r, _, _)| *r);
        vec![
            ProviderSet {
                label: "near-intents/recent".into(),
                window_secs: Some(u64::try_from(window).expect("a positive window")),
                since_unix: self.feed_started,
                until_unix: until,
                receivers: dedup(recent),
            },
            ProviderSet {
                label: "near-intents/seen".into(),
                window_secs: None,
                since_unix: self.feed_started,
                until_unix: until,
                receivers: dedup(seen),
            },
        ]
    }
}

/// `receivers` without repeats, in first-seen order.
fn dedup(receivers: impl Iterator<Item = [u8; 43]>) -> Vec<Receiver> {
    let mut out: Vec<[u8; 43]> = Vec::new();
    for receiver in receivers {
        if !out.contains(&receiver) {
            out.push(receiver);
        }
    }
    out.into_iter()
        .map(|r| Receiver::from_bytes(r).expect("a valid receiver"))
        .collect()
}
