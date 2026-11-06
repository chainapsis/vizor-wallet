//! A broadcast result's English `message`, as data the app can show in the
//! display language.
//!
//! A result's `message` is [`english`] of its notices, so the two cannot
//! disagree. Dart builds the same sentences from ARB keys, and
//! `test/fixtures/broadcast_notices_en.json` pins Rust and the English ARB
//! copy to the same text. `message` stays Rust's English: logs, endpoint
//! failover and stored Ledger rows from earlier builds read it.

use serde::{Deserialize, Serialize};

/// One sentence of a broadcast result. Which fields are set depends on
/// [`kind`](Self::kind).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BroadcastNotice {
    pub kind: String,
    /// 1-based position of the transaction. For `broadcast_failed`, the
    /// number of transactions already sent.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub index: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total: Option<u32>,
    /// A txid, or the comma-separated txids already sent for
    /// `broadcast_failed`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub txid: Option<String>,
    /// Error text from Rust, a dependency or the server, shown untranslated.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expiry_height: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chain_height: Option<u64>,
}

/// Kinds, one per English sentence. Dart has one ARB key per kind; a kind it
/// does not know makes it show `message` instead.
pub(crate) mod kind {
    /// `detail` is the whole sentence: Rust text with no fixed shape.
    pub const TEXT: &str = "text";
    pub const TRANSACTION_UNKNOWN: &str = "transaction_unknown";
    pub const TRANSACTION_REJECTED: &str = "transaction_rejected";
    pub const ROUTE_UNAVAILABLE: &str = "route_unavailable";
    pub const EXPIRED: &str = "expired";
    pub const BROADCAST_STORAGE_FAILED: &str = "broadcast_storage_failed";
    pub const RESPONSE_UNAVAILABLE: &str = "response_unavailable";
    pub const DATABASE_UNAVAILABLE: &str = "database_unavailable";
    pub const RAW_TRANSACTION_UNAVAILABLE: &str = "raw_transaction_unavailable";
    pub const BROADCAST_FAILED: &str = "broadcast_failed";
    pub const STORED_LOCALLY: &str = "stored_locally";
    pub const STORAGE_FAILED: &str = "storage_failed";
    pub const RETENTION_FAILED: &str = "retention_failed";
    pub const RETRYING_LOCALLY: &str = "retrying_locally";
    pub const TRACKING_FAILED: &str = "tracking_failed";
}

impl BroadcastNotice {
    fn new(kind: &str) -> Self {
        Self {
            kind: kind.to_string(),
            index: None,
            total: None,
            txid: None,
            detail: None,
            expiry_height: None,
            chain_height: None,
        }
    }

    fn with_detail(kind: &str, detail: impl Into<String>) -> Self {
        Self {
            detail: Some(detail.into()),
            ..Self::new(kind)
        }
    }

    fn for_transaction(kind: &str, index: u32, total: u32, detail: impl Into<String>) -> Self {
        Self {
            index: Some(index),
            total: Some(total),
            ..Self::with_detail(kind, detail)
        }
    }

    fn for_txid(kind: &str, txid: impl Into<String>, detail: impl Into<String>) -> Self {
        Self {
            txid: Some(txid.into()),
            ..Self::with_detail(kind, detail)
        }
    }

    pub(crate) fn text(text: impl Into<String>) -> Self {
        Self::with_detail(kind::TEXT, text)
    }

    pub(crate) fn transaction_unknown(index: u32, total: u32, detail: impl Into<String>) -> Self {
        Self::for_transaction(kind::TRANSACTION_UNKNOWN, index, total, detail)
    }

    pub(crate) fn transaction_rejected(index: u32, total: u32, detail: impl Into<String>) -> Self {
        Self::for_transaction(kind::TRANSACTION_REJECTED, index, total, detail)
    }

    pub(crate) fn route_unavailable(index: u32, total: u32, detail: impl Into<String>) -> Self {
        Self::for_transaction(kind::ROUTE_UNAVAILABLE, index, total, detail)
    }

    pub(crate) fn expired(txid: impl Into<String>, expiry_height: u32, chain_height: u64) -> Self {
        Self {
            txid: Some(txid.into()),
            expiry_height: Some(expiry_height),
            chain_height: Some(chain_height),
            ..Self::new(kind::EXPIRED)
        }
    }

    pub(crate) fn broadcast_storage_failed(
        txid: impl Into<String>,
        detail: impl Into<String>,
    ) -> Self {
        Self::for_txid(kind::BROADCAST_STORAGE_FAILED, txid, detail)
    }

    pub(crate) fn response_unavailable(txid: impl Into<String>, detail: impl Into<String>) -> Self {
        Self::for_txid(kind::RESPONSE_UNAVAILABLE, txid, detail)
    }

    pub(crate) fn database_unavailable(detail: impl Into<String>) -> Self {
        Self::with_detail(kind::DATABASE_UNAVAILABLE, detail)
    }

    pub(crate) fn raw_transaction_unavailable(
        txid: impl Into<String>,
        detail: impl Into<String>,
    ) -> Self {
        Self::for_txid(kind::RAW_TRANSACTION_UNAVAILABLE, txid, detail)
    }

    pub(crate) fn broadcast_failed(
        sent: u32,
        total: u32,
        sent_txids: impl Into<String>,
        detail: impl Into<String>,
    ) -> Self {
        Self {
            txid: Some(sent_txids.into()),
            ..Self::for_transaction(kind::BROADCAST_FAILED, sent, total, detail)
        }
    }

    pub(crate) fn stored_locally() -> Self {
        Self::new(kind::STORED_LOCALLY)
    }

    pub(crate) fn storage_failed(detail: impl Into<String>) -> Self {
        Self::with_detail(kind::STORAGE_FAILED, detail)
    }

    pub(crate) fn retention_failed(detail: impl Into<String>) -> Self {
        Self::with_detail(kind::RETENTION_FAILED, detail)
    }

    pub(crate) fn retrying_locally() -> Self {
        Self::new(kind::RETRYING_LOCALLY)
    }

    pub(crate) fn tracking_failed(detail: impl Into<String>) -> Self {
        Self::with_detail(kind::TRACKING_FAILED, detail)
    }

    /// The English sentence. Every Dart ARB key for a kind has this text as
    /// its English value.
    pub(crate) fn sentence(&self) -> String {
        let index = self.index.unwrap_or_default();
        let total = self.total.unwrap_or_default();
        let txid = self.txid.as_deref().unwrap_or_default();
        let detail = self.detail.as_deref().unwrap_or_default();
        match self.kind.as_str() {
            kind::TRANSACTION_UNKNOWN => {
                format!("Transaction {index} of {total} has an unknown broadcast result: {detail}")
            }
            kind::TRANSACTION_REJECTED => {
                format!("Transaction {index} of {total} was rejected and was not stored: {detail}")
            }
            kind::ROUTE_UNAVAILABLE => format!(
                "Failed to open the broadcast route for transaction {index} of {total}; it was not stored: {detail}"
            ),
            kind::EXPIRED => format!(
                "Hardware signing request expired before broadcast: txid={txid}, \
                 expiry height {}, current chain height {}. \
                 Start the signing flow again so Vizor can build a fresh transaction.",
                self.expiry_height.unwrap_or_default(),
                self.chain_height.unwrap_or_default(),
            ),
            kind::BROADCAST_STORAGE_FAILED => format!(
                "Broadcast succeeded (txid={txid}) but local storage failed. {detail}. \
                 The transaction is on the network; check an explorer to confirm, and do not \
                 attempt to send again until the next sync reconciles your balance."
            ),
            kind::RESPONSE_UNAVAILABLE => format!(
                "Broadcast response was unavailable for txid={txid} ({detail}). The transaction may \
                 already be on the network. Do not send again until sync or an explorer confirms \
                 whether this transaction was accepted."
            ),
            kind::DATABASE_UNAVAILABLE => {
                format!("Failed to open DB for broadcast after local transaction creation: {detail}")
            }
            kind::RAW_TRANSACTION_UNAVAILABLE => {
                format!("Failed to get raw tx for {txid} after local transaction creation: {detail}")
            }
            kind::BROADCAST_FAILED => {
                format!("Broadcast failed after {index}/{total} txs sent ({txid}). Error: {detail}")
            }
            kind::STORED_LOCALLY => {
                "The accepted-or-ambiguous transaction prefix was stored locally for recovery."
                    .to_string()
            }
            kind::STORAGE_FAILED => format!(
                "A transaction may already be on the network, but local storage failed: {detail}. \
                 Do not send again until sync or an explorer confirms the result."
            ),
            kind::RETENTION_FAILED => {
                format!("Proposal input-lock retention also failed: {detail}.")
            }
            kind::RETRYING_LOCALLY => {
                "It was stored locally and will retry automatically during sync until it is \
                 confirmed or expires."
                    .to_string()
            }
            kind::TRACKING_FAILED => format!(
                "Local tracking also failed: {detail}. Check an explorer before retrying this send."
            ),
            _ => detail.to_string(),
        }
    }
}

/// A result's `message`: its notices' sentences, one space apart. None when
/// there are none.
pub(crate) fn english(notices: &[BroadcastNotice]) -> Option<String> {
    if notices.is_empty() {
        return None;
    }
    Some(
        notices
            .iter()
            .map(BroadcastNotice::sentence)
            .collect::<Vec<_>>()
            .join(" "),
    )
}

/// Notices stored in a text column, as JSON. An empty list is stored as NULL.
pub(crate) fn notices_to_json(notices: &[BroadcastNotice]) -> Result<Option<String>, String> {
    if notices.is_empty() {
        return Ok(None);
    }
    serde_json::to_string(notices)
        .map(Some)
        .map_err(|error| format!("Encode broadcast notices: {error}"))
}

/// Reads [`notices_to_json`]. Unreadable JSON yields no notices, so the app
/// shows the stored `message` instead.
pub(crate) fn notices_from_json(json: Option<&str>) -> Vec<BroadcastNotice> {
    json.and_then(|json| serde_json::from_str(json).ok())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Deserialize)]
    struct Fixture {
        notices: Vec<BroadcastNotice>,
        message: String,
    }

    /// The same file pins the English ARB copy in
    /// `test/l10n/broadcast_notice_text_test.dart`.
    #[test]
    fn english_matches_the_shared_fixture() {
        let fixtures: Vec<Fixture> = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../test/fixtures/broadcast_notices_en.json"
        )))
        .unwrap();
        let mut kinds = std::collections::BTreeSet::new();
        for fixture in &fixtures {
            assert_eq!(
                english(&fixture.notices).as_deref(),
                Some(fixture.message.as_str())
            );
            kinds.extend(fixture.notices.iter().map(|notice| notice.kind.clone()));
        }
        let all = [
            kind::TEXT,
            kind::TRANSACTION_UNKNOWN,
            kind::TRANSACTION_REJECTED,
            kind::ROUTE_UNAVAILABLE,
            kind::EXPIRED,
            kind::BROADCAST_STORAGE_FAILED,
            kind::RESPONSE_UNAVAILABLE,
            kind::DATABASE_UNAVAILABLE,
            kind::RAW_TRANSACTION_UNAVAILABLE,
            kind::BROADCAST_FAILED,
            kind::STORED_LOCALLY,
            kind::STORAGE_FAILED,
            kind::RETENTION_FAILED,
            kind::RETRYING_LOCALLY,
            kind::TRACKING_FAILED,
        ];
        for kind in all {
            assert!(kinds.contains(kind), "fixture misses {kind}");
        }
    }

    #[test]
    fn json_round_trips_and_tolerates_bad_rows() {
        let notices = vec![
            BroadcastNotice::transaction_unknown(2, 3, "deadline"),
            BroadcastNotice::stored_locally(),
        ];
        let json = notices_to_json(&notices).unwrap();
        assert_eq!(notices_from_json(json.as_deref()), notices);
        assert_eq!(notices_to_json(&[]).unwrap(), None);
        assert!(notices_from_json(None).is_empty());
        assert!(notices_from_json(Some("not json")).is_empty());
    }
}
