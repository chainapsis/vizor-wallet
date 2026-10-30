//! Failures whose kind decides what the caller does next.
//!
//! Most wallet errors are messages for a person. A few also tell the caller
//! how to proceed: keep a signed transaction and retry it, discard a Ledger
//! operation, or point the user at the Private queries toggle. Those carry a
//! [`FailureCode`] beside the message, so rewording a message never changes
//! retry behavior. The API layer passes the code to Dart as a typed field.

use std::fmt;

/// What a caller should do about a failure, beyond showing its message.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FailureCode {
    /// Nothing was sent, and the signed transaction and its proposal are
    /// kept: private recovery is catching up, or the wallet was too busy.
    /// The same signatures can be sent again later.
    RetryAfterRecovery,
    /// Transparent broadcast authority refused the transaction for good
    /// before anything was sent. Retrying cannot succeed.
    AuthorityRefused,
    /// A Ledger operation can never go through, so retrying is pointless.
    /// From a broadcast: the outbox has already discarded the operation and
    /// released its inputs. From a checkpoint: the operation ID already holds
    /// a different signed transaction, which stays saved untouched.
    LedgerOperationTerminal,
    /// Private recovery has not yet covered the transparent funds. Shielded
    /// funds stay available.
    RecoveryIncomplete,
    /// The wallet still requires private recovery while Private queries is
    /// off: turning it off did not finish. Turning it off again lowers the
    /// policy.
    OptOutUnfinished,
}

/// An error message, and what the caller should do about it when that is
/// more than showing the message.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WalletFailure {
    pub code: Option<FailureCode>,
    pub message: String,
}

impl WalletFailure {
    pub fn coded(code: FailureCode, message: impl Into<String>) -> Self {
        Self {
            code: Some(code),
            message: message.into(),
        }
    }
}

impl From<String> for WalletFailure {
    fn from(message: String) -> Self {
        Self {
            code: None,
            message,
        }
    }
}

impl From<&str> for WalletFailure {
    fn from(message: &str) -> Self {
        message.to_owned().into()
    }
}

/// For callers that only show the message. The code is dropped, so a path
/// whose callers act on the code returns [`WalletFailure`] all the way out.
impl From<WalletFailure> for String {
    fn from(failure: WalletFailure) -> Self {
        failure.message
    }
}

impl fmt::Display for WalletFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}
