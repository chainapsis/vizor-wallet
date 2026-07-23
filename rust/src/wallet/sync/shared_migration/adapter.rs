//! Vizor's account-scoped adapter for the shared pool-migration engine.
//!
//! The engine's bundled wallet adapter requires a spending key even for read
//! and external-signing operations. Vizor can hold imported Keystone accounts,
//! so this adapter reads the Orchard FVK from the stored UFVK and makes the USK
//! optional. The migration store is scoped to the account in the wallet DB.

use anyhow::anyhow;
use incrementalmerkletree::Position;
use orchard::{
    keys::{FullViewingKey, SpendAuthorizingKey},
    note::Note as OrchardNote,
};
use zcash_client_backend::data_api::{
    wallet::{
        input_selection::{LockFilter, LockedInputPolicy},
        TargetHeight,
    },
    Account, InputSource, WalletRead,
};
use zcash_client_sqlite::{pool_migration::orchard_ironwood::PoolMigrations, AccountUuid};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_pool_migration_backend::{
    build::sign_pczt,
    engine::{
        MigrationBackend, MigrationCrypto, MigrationState, MigrationTxId, MigrationTxState,
        PoolMigrationRead, PoolMigrationWrite,
    },
};
use zcash_protocol::{consensus::BlockHeight, value::Zatoshis, ShieldedPool};

use super::super::WalletDatabase;

type SpendableNote = (OrchardNote, Position, u64);

/// Shared-engine access for one Vizor account.
pub(super) struct Backend<'a> {
    wallet: &'a WalletDatabase,
    account: AccountUuid,
    usk: Option<UnifiedSpendingKey>,
    store: PoolMigrations<&'a mut rusqlite::Connection>,
}

impl<'a> Backend<'a> {
    pub(super) fn new(
        wallet: &'a WalletDatabase,
        account: AccountUuid,
        usk: Option<UnifiedSpendingKey>,
        store_conn: &'a mut rusqlite::Connection,
    ) -> anyhow::Result<Self> {
        Ok(Self {
            wallet,
            account,
            usk,
            store: PoolMigrations::for_account(store_conn, account)
                .map_err(|e| anyhow!("opening the account-scoped migration store failed: {e}"))?,
        })
    }

    fn selection_target(&self) -> anyhow::Result<TargetHeight> {
        let tip = self
            .wallet
            .chain_height()
            .map_err(|e| anyhow!("chain height lookup failed: {e}"))?
            .ok_or_else(|| anyhow!("the wallet has no chain tip yet; sync first"))?;
        Ok(TargetHeight::from(u32::from(tip) + 1))
    }

    fn spendable_orchard_notes(&self) -> anyhow::Result<Vec<SpendableNote>> {
        let received = self
            .wallet
            .select_unspent_notes(
                self.account,
                &[ShieldedPool::Orchard],
                self.selection_target()?,
                &[],
                LockFilter::Policy(&LockedInputPolicy::Exclude),
            )
            .map_err(|e| anyhow!("spendable-note selection failed: {e}"))?;
        let mut notes = received
            .orchard()
            .iter()
            .map(|note| {
                let orchard_note = *note.note();
                (
                    orchard_note,
                    note.note_commitment_tree_position(),
                    orchard_note.value().inner(),
                )
            })
            .collect::<Vec<_>>();
        notes.sort_by_key(|(_, position, _)| *position);
        Ok(notes)
    }

    pub(super) fn stored_orchard_fvk(&self) -> anyhow::Result<FullViewingKey> {
        let account = self
            .wallet
            .get_account(self.account)
            .map_err(|e| anyhow!("account lookup failed: {e}"))?
            .ok_or_else(|| anyhow!("unknown account"))?;
        account
            .ufvk()
            .ok_or_else(|| anyhow!("the account has no unified full viewing key"))?
            .orchard()
            .cloned()
            .ok_or_else(|| anyhow!("the account's viewing key has no Orchard component"))
    }
}

impl MigrationBackend for Backend<'_> {
    type Error = anyhow::Error;

    fn spendable_orchard_note_values(&self) -> Result<Vec<Zatoshis>, Self::Error> {
        self.spendable_orchard_notes()?
            .into_iter()
            .enumerate()
            .map(|(index, (_, _, value))| {
                Zatoshis::from_u64(value)
                    .map_err(|_| anyhow!("spendable note {index} has an out-of-range value"))
            })
            .collect()
    }

    fn chain_tip_height(&self) -> Result<BlockHeight, Self::Error> {
        self.wallet
            .chain_height()
            .map_err(|e| anyhow!("chain height lookup failed: {e}"))?
            .ok_or_else(|| anyhow!("the wallet has no chain tip yet; sync first"))
    }
}

impl MigrationCrypto for Backend<'_> {
    type Error = anyhow::Error;

    fn orchard_fvk(&self) -> Result<FullViewingKey, Self::Error> {
        self.stored_orchard_fvk()
    }

    fn resolve_wallet_note(&self, index: usize) -> Result<OrchardNote, Self::Error> {
        self.spendable_orchard_notes()?
            .get(index)
            .map(|(note, _, _)| *note)
            .ok_or_else(|| anyhow!("no spendable note at index {index}"))
    }

    fn sign(&self, pczt: pczt::Pczt) -> Result<pczt::Pczt, Self::Error> {
        let usk = self
            .usk
            .as_ref()
            .ok_or_else(|| anyhow!("signing requires the account's spending key"))?;
        sign_pczt(pczt, &SpendAuthorizingKey::from(usk.orchard()))
            .map_err(|e| anyhow!("signing the migration failed: {e}"))
    }
}

impl PoolMigrationRead for Backend<'_> {
    type Error = anyhow::Error;

    fn get_migration(&self) -> Result<Option<MigrationState>, Self::Error> {
        self.store
            .get_migration()
            .map_err(|e| anyhow!("migration store read failed: {e}"))
    }
}

impl PoolMigrationWrite for Backend<'_> {
    fn replace_migration(&mut self, state: &MigrationState) -> Result<(), Self::Error> {
        self.store
            .replace_migration(state)
            .map_err(|e| anyhow!("migration store write failed: {e}"))
    }

    fn update_transaction(
        &mut self,
        id: MigrationTxId,
        state: MigrationTxState,
    ) -> Result<(), Self::Error> {
        self.store
            .update_transaction(id, state)
            .map_err(|e| anyhow!("migration store update failed: {e}"))
    }
}
