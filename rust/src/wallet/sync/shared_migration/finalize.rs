//! Deferred-anchor proving and transaction extraction for shared migrations.

use anyhow::anyhow;
use zcash_client_backend::data_api::WalletRead;
use zcash_pool_migration_backend::{
    engine::{self, MigrationProver, MigrationState, MigrationTxId, MigrationTxKind},
    wallet::WalletProveError,
};
use zcash_protocol::consensus::BlockHeight;

use super::super::WalletDatabase;

pub(super) fn natural_anchor_height(wallet: &WalletDatabase) -> anyhow::Result<BlockHeight> {
    wallet
        .get_target_and_anchor_heights(std::num::NonZeroU32::MIN)
        .map_err(|e| anyhow!("anchor height lookup failed: {e}"))?
        .map(|(_, anchor)| anchor)
        .ok_or_else(|| anyhow!("the wallet has no anchor height yet; sync first"))
}

pub(super) trait ProveErrorClass {
    fn is_transient(&self) -> bool;
}

impl<TE, NE, RE> ProveErrorClass for WalletProveError<TE, NE, RE> {
    fn is_transient(&self) -> bool {
        matches!(
            self,
            WalletProveError::AnchorNotFound(_)
                | WalletProveError::WitnessNotFound(_)
                | WalletProveError::ChainTipUnknown
                | WalletProveError::IronwoodTreeUnavailable
        )
    }
}

pub(super) fn prove_transaction<P>(
    prover: &mut P,
    state: &mut MigrationState,
    id: MigrationTxId,
    natural_anchor: Option<BlockHeight>,
) -> anyhow::Result<bool>
where
    P: MigrationProver,
    P::Error: ProveErrorClass + std::fmt::Display,
{
    let kind = state
        .transactions()
        .iter()
        .find(|transaction| transaction.id() == id)
        .map(|transaction| transaction.kind())
        .ok_or_else(|| anyhow!("no migration transaction with id {}", u32::from(id)))?;
    let result = match kind {
        MigrationTxKind::Transfer { .. } => engine::prove_transfer(prover, state, id),
        MigrationTxKind::Preparation { .. } => engine::prove_preparation(
            prover,
            state,
            id,
            natural_anchor.ok_or_else(|| anyhow!("preparation transaction has no anchor"))?,
        ),
    };
    match result {
        Ok(()) => Ok(true),
        Err(engine::ProveError::Prover(error)) if error.is_transient() => Ok(false),
        Err(error) => Err(anyhow!("proving migration transaction failed: {error}")),
    }
}

pub(super) fn extract_tx(pczt: pczt::Pczt) -> anyhow::Result<(Vec<u8>, [u8; 32])> {
    let tx = pczt::roles::tx_extractor::TransactionExtractor::new(pczt)
        .extract()
        .map_err(|e| anyhow!("extract migration transaction: {e:?}"))?;
    let txid = *tx.txid().as_ref();
    let mut raw = Vec::new();
    tx.write(&mut raw)
        .map_err(|e| anyhow!("encode migration transaction: {e}"))?;
    Ok((raw, txid))
}
