//! Status polling for refund records recovered from authenticated funding memos.
use super::enhancement::transport::RoutedTransport;
use crate::wallet::db::{with_wallet_db_write_lock, WalletDatabase};
use futures::StreamExt;
use std::num::NonZeroU32;
use zcash_client_backend::data_api::{Account as _, AccountSource, WalletRead};

/// A status response decides when a refund key stops scanning, never note
/// ownership or balance. The deadline is the quote request's, as in the app's
/// own quote handling, so a long-finished restored swap closes after its sweep.
fn provider_status(bytes: &[u8]) -> Option<zakura_swap_receiving::lifecycle::Observation> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let refunded_amount = value
        .pointer("/swapDetails/refundedAmount")
        .and_then(|v| v.as_str())
        .and_then(|v| v.parse::<u64>().ok())
        .and_then(|v| zcash_protocol::value::Zatoshis::from_u64(v).ok());
    let deadline = value
        .pointer("/quoteResponse/quoteRequest/deadline")
        .and_then(|v| v.as_str())
        .and_then(|v| {
            time::OffsetDateTime::parse(v, &time::format_description::well_known::Rfc3339).ok()
        })
        .map(|t| t.unix_timestamp());
    zakura_swap_receiving::lifecycle::near_observation(
        zakura_swap_receiving::Purpose::Refund,
        &zakura_swap_receiving::lifecycle::ProviderStatus {
            status: value.get("status")?.as_str()?,
            swap_type: value
                .pointer("/quoteResponse/quoteRequest/swapType")
                .and_then(|v| v.as_str()),
            refunded_amount,
            amount_out: None,
            deadline,
        },
    )
}

pub(super) async fn reconcile(
    db: &mut WalletDatabase,
    should_exit: &impl Fn() -> bool,
) -> Result<(), String> {
    let now = crate::wallet::swap_receiving::receive::now()?;
    let transport = RoutedTransport::new(should_exit);
    for account in db.get_account_ids().map_err(|e| e.to_string())? {
        let details = db
            .get_account(account)
            .map_err(|e| e.to_string())?
            .ok_or("Account disappeared")?;
        if !matches!(details.source(), AccountSource::Derived { .. })
            || crate::wallet::keys::hardware_signer_kind(details.source()).is_some()
        {
            continue;
        }
        let work = with_wallet_db_write_lock("swap_refund.status_due", || {
            db.take_swap_refund_status_checks(account, now, NonZeroU32::new(8).unwrap())
                .map_err(|e| e.to_string())
        })?;
        // Bound restore fan-out without letting one slow request block the others.
        let replies = futures::stream::iter(work)
            .map(|(key, deposit)| {
                let transport = &transport;
                async move {
                    let mut url =
                        url::Url::parse("https://1click.chaindefuser.com/v0/status").unwrap();
                    url.query_pairs_mut()
                        .append_pair("depositAddress", &deposit);
                    let response = tokio::time::timeout(
                        std::time::Duration::from_secs(10),
                        transport.bytes(http::Method::GET, url.as_str(), vec![], 64 * 1024),
                    )
                    .await;
                    let terminal = match response {
                        Ok(Ok(bytes)) => provider_status(&bytes),
                        _ => None,
                    };
                    (key, deposit, terminal)
                }
            })
            .buffer_unordered(4);
        futures::pin_mut!(replies);
        while let Some((key, deposit, terminal)) = replies.next().await {
            if should_exit() {
                return Ok(());
            }
            if let Some(status) = terminal {
                with_wallet_db_write_lock("swap_refund.status", || {
                    db.record_swap_observation(account, key, &deposit, status, now)
                        .map_err(|e| e.to_string())
                })?;
            }
            // Failed or unrecognized responses preserve the pending watch. Do not
            // log the URL: its deposit address identifies the swap to the provider.
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use zakura_swap_receiving::lifecycle::{OperationStatus, ReceiptExpectation};

    #[test]
    fn status_response_yields_refund_expectation_and_deadline() {
        let body = br#"{"status":"SUCCESS","swapDetails":{"refundedAmount":"1500"},
            "quoteResponse":{"quoteRequest":{"swapType":"EXACT_INPUT",
            "deadline":"2026-09-01T12:00:00Z"}}}"#;
        let observation = super::provider_status(body).unwrap();
        assert_eq!(
            observation.status,
            OperationStatus::Terminal(ReceiptExpectation::Positive(Some(
                zcash_protocol::value::Zatoshis::const_from_u64(1500)
            )))
        );
        assert_eq!(observation.deadline, Some(1_788_264_000));
        let pending = br#"{"status":"PENDING_DEPOSIT"}"#;
        let observation = super::provider_status(pending).unwrap();
        assert_eq!(observation.status, OperationStatus::Active);
        assert_eq!(observation.deadline, None);
    }
}
