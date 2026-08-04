pub(crate) fn send_rejection_is_already_accepted(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("transaction was committed to the best chain")
        || message.contains("already in mempool")
        || message.contains("already have transaction")
        || message.contains("transaction already in block chain")
        || message.contains("transaction is already in state")
        || message.contains("transaction already exists")
        || message.contains("txn-already-known")
        || message.contains("txn-already-in-mempool")
        || message.contains("already known")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_send_messages_are_accepted() {
        for message in [
            "transaction was committed to the best chain",
            "already in mempool",
            "already have transaction",
            "transaction already in block chain",
            "failed to validate tx: WtxId(\"private\"), error: transaction is already in state",
            "transaction already exists",
            "txn-already-known",
            "txn-already-in-mempool",
            "already known",
            "Error: TXN-ALREADY-IN-MEMPOOL from node",
        ] {
            assert!(send_rejection_is_already_accepted(message), "{message}");
        }
    }

    #[test]
    fn unrelated_send_messages_are_not_accepted() {
        for message in [
            "bad-txns-inputs-spent",
            "",
            "mandatory-script-verify-flag-failed",
        ] {
            assert!(!send_rejection_is_already_accepted(message), "{message}");
        }
    }
}
