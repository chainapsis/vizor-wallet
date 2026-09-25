//! Wallet-local mapping from source-independent status observations to database
//! state. Routing and public status validation live in wallet-libraries.
use zcash_client_backend::data_api::TransactionStatus;
use zcash_protocol::consensus::BlockHeight;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum TransactionObservation {
    NotFound,
    Mempool,
    Mined(BlockHeight),
    Forked,
}

impl TransactionObservation {
    pub(crate) fn wallet_status(self) -> TransactionStatus {
        match self {
            Self::NotFound => TransactionStatus::TxidNotRecognized,
            Self::Mempool | Self::Forked => TransactionStatus::NotInMainChain,
            Self::Mined(height) => TransactionStatus::Mined(height),
        }
    }
}

impl From<zakura_transaction_status::StatusObservation> for TransactionObservation {
    fn from(observation: zakura_transaction_status::StatusObservation) -> Self {
        use zakura_transaction_status::StatusObservation;
        match observation {
            StatusObservation::NotFound => Self::NotFound,
            StatusObservation::Mempool => Self::Mempool,
            StatusObservation::Mined(height) => Self::Mined(height),
            StatusObservation::Forked => Self::Forked,
        }
    }
}

pub(crate) type LookupError = zakura_transaction_status::StatusError;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn observation_mapping_preserves_absence_and_fork_semantics() {
        assert!(matches!(
            TransactionObservation::NotFound.wallet_status(),
            TransactionStatus::TxidNotRecognized
        ));
        for observation in [
            TransactionObservation::Mempool,
            TransactionObservation::Forked,
        ] {
            assert!(matches!(
                observation.wallet_status(),
                TransactionStatus::NotInMainChain
            ));
        }
        assert!(matches!(
            TransactionObservation::Mined(BlockHeight::from_u32(42)).wallet_status(),
            TransactionStatus::Mined(height) if u32::from(height) == 42
        ));
    }
}
