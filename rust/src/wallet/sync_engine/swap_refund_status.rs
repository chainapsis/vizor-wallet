//! Status polling for refund records recovered from authenticated funding memos.
use super::enhancement::transport::RoutedTransport;
use crate::wallet::db::{with_wallet_db_write_lock, WalletDatabase};
use futures::StreamExt;
use std::num::NonZeroU32;
use zcash_client_backend::data_api::{Account as _, AccountSource, WalletRead};
use zcash_protocol::consensus::BlockHeight;

/// A status response affects scanning deadlines, never note ownership or balance.
fn terminal_status(bytes: &[u8]) -> Option<bool> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    match value.get("status")?.as_str()? {
        "KNOWN_DEPOSIT_TX" | "PENDING_DEPOSIT" | "INCOMPLETE_DEPOSIT" | "PROCESSING" => Some(false),
        "SUCCESS" | "REFUNDED" | "FAILED" => Some(true),
        _ => None,
    }
}

pub(super) async fn reconcile(
    db: &mut WalletDatabase,
    tip: BlockHeight,
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
                        Ok(Ok(bytes)) => terminal_status(&bytes),
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
            if terminal == Some(true) {
                with_wallet_db_write_lock("swap_refund.status", || {
                    db.observe_swap_operation(account, key, &deposit, true, tip)
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
    use super::*;
    #[test]
    fn only_supported_provider_states_change_scanning() {
        for status in [
            "KNOWN_DEPOSIT_TX",
            "PENDING_DEPOSIT",
            "INCOMPLETE_DEPOSIT",
            "PROCESSING",
        ] {
            assert_eq!(
                terminal_status(format!(r#"{{"status":"{status}"}}"#).as_bytes()),
                Some(false)
            );
        }
        for status in ["SUCCESS", "REFUNDED", "FAILED"] {
            assert_eq!(
                terminal_status(format!(r#"{{"status":"{status}"}}"#).as_bytes()),
                Some(true)
            );
        }
        for bytes in [
            b"{}".as_slice(),
            br#"{"status":"CANCELLED"}"#,
            br#"{"status":1}"#,
            b"bad json",
        ] {
            assert_eq!(terminal_status(bytes), None);
        }
    }
}
