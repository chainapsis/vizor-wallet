use zcash_client_backend::proto::service::SendResponse;

pub(super) fn send_response_rejection_error(resp: &SendResponse) -> Option<String> {
    if resp.error_code == 0 || send_rejection_is_already_accepted(&resp.error_message) {
        return None;
    }

    Some(format!(
        "Broadcast rejected: {} (code {})",
        resp.error_message, resp.error_code
    ))
}

pub(super) fn send_rejection_is_already_accepted(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("transaction was committed to the best chain")
        || message.contains("already in mempool")
        || message.contains("already have transaction")
        || message.contains("transaction already in block chain")
        || message.contains("transaction is already in state")
        || message.contains("txn-already-in-mempool")
        || message.contains("already known")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn send_response(error_code: i32, error_message: &str) -> SendResponse {
        SendResponse {
            error_code,
            error_message: error_message.to_string(),
        }
    }

    #[test]
    fn send_response_success_is_accepted_even_when_message_contains_txid() {
        let resp = send_response(
            0,
            "838813428b78712263511ed5c6fb9a108c939038a440b74f72bee6caedf602fd",
        );

        assert_eq!(send_response_rejection_error(&resp), None);
    }

    #[test]
    fn duplicate_send_responses_are_accepted() {
        for message in [
            "transaction was committed to the best chain",
            "already in mempool",
            "already have transaction",
            "transaction already in block chain",
            "failed to validate tx: WtxId(\"private\"), error: transaction is already in state",
            "txn-already-in-mempool",
            "already known",
            "Error: TXN-ALREADY-IN-MEMPOOL from node",
        ] {
            let resp = send_response(-25, message);

            assert_eq!(send_response_rejection_error(&resp), None, "{message}");
        }
    }

    #[test]
    fn unrelated_send_rejections_remain_fatal() {
        for message in [
            "bad-txns-inputs-spent",
            "",
            "mandatory-script-verify-flag-failed",
        ] {
            let resp = send_response(18, message);

            assert_eq!(
                send_response_rejection_error(&resp),
                Some(format!("Broadcast rejected: {message} (code 18)")),
                "{message}"
            );
        }
    }
}
