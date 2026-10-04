//! Input selection from a frozen, genuinely scanned funding prefix. Later
//! spendability is established by the card observer, not the wallet scan queue.
use super::*;
use crate::wallet::sync_engine::gift_card_claim;
use zcash_client_backend::data_api::{wallet::input_selection::InputSelectorError, PoolMeta};

pub(super) struct CardInput<'a> {
    db: &'a WalletDatabase,
    account: AccountUuid,
    state: gift_card_claim::Snapshot,
    notes: Vec<ReceivedNote<ReceivedNoteId, orchard::Note>>,
}
impl<'a> CardInput<'a> {
    pub(super) fn load(
        db: &'a WalletDatabase,
        path: &str,
        account: AccountUuid,
    ) -> Result<Option<Self>, String> {
        let Some(state) = gift_card_claim::snapshot(path)? else {
            return Ok(None);
        };
        if !state.complete || !state.has_confirmed_anchor() {
            return Err("Insufficient balance: Gift Card check or confirmations pending".into());
        }
        if !db
            .anchor_computable(ShieldedPool::Ironwood, state.anchor_height.into())
            .map_err(|e| e.to_string())?
        {
            return Err("Gift Card funding witnesses require another check".into());
        }
        let c = open_readonly_conn(path)?;
        let mut query=c.prepare("SELECT t.txid,n.action_index FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id JOIN vizor_giftcard_check g ON t.txid=g.funding_txid WHERE n.value>0 AND NOT EXISTS(SELECT 1 FROM vizor_giftcard_spends s WHERE s.nf=n.nf)").map_err(|e|e.to_string())?;
        let ids = query
            .query_map([], |r| Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, u16>(1)?)))
            .map_err(|e| e.to_string())?
            .collect::<rusqlite::Result<HashSet<_>>>()
            .map_err(|e| e.to_string())?;
        let target = BlockHeight::from_u32(state.checked_height + 1).into();
        let mut notes = vec![];
        for note in db
            .get_unspent_ironwood_notes_at_historical_height(
                account,
                BlockHeight::from_u32(state.anchor_height),
            )
            .map_err(|e| e.to_string())?
        {
            if ids.contains(&(note.txid().as_ref().to_vec(), note.output_index()))
                && db
                    .get_spendable_note(
                        note.txid(),
                        ShieldedPool::Ironwood,
                        note.output_index() as u32,
                        target,
                        LockFilter::Policy(&LockedInputPolicy::Exclude),
                    )
                    .map_err(|e| e.to_string())?
                    .is_some()
            {
                notes.push(note);
            }
        }
        Ok(Some(Self {
            db,
            account,
            state,
            notes,
        }))
    }
    pub(super) fn propose(
        &self,
        network: WalletNetwork,
        request: TransactionRequest,
    ) -> Result<Proposal<WalletFeeRule, ReceivedNoteId>, String> {
        self.select_proposal(network, request)
            .map_err(|e| format!("Propose Gift Card failed: {e}"))
    }
    fn select_proposal(
        &self,
        network: WalletNetwork,
        request: TransactionRequest,
    ) -> Result<
        Proposal<WalletFeeRule, ReceivedNoteId>,
        InputSelectorError<
            String,
            zcash_client_backend::data_api::wallet::input_selection::GreedyInputSelectorError,
            <WalletFeeRule as FeeRule>::Error,
            ReceivedNoteId,
        >,
    > {
        let (change, selector) = zip317_helper::<Self>(None, false);
        selector.propose_transaction(
            &network,
            self,
            BlockHeight::from_u32(self.state.checked_height + 1).into(),
            BlockHeight::from_u32(self.state.anchor_height),
            &self.db.pool_migration_params(),
            payment_link_claim_confirmations_policy(),
            self.account,
            request,
            &change,
            &SpendPolicy::shielded_pools(vec![ShieldedPool::Ironwood]),
            Some(TxVersion::V6),
        )
    }
    pub(super) fn estimate_max(
        &self,
        network: WalletNetwork,
        to: &str,
        memo: Option<&str>,
    ) -> Result<SendMaxEstimateResult, String> {
        let total = self
            .notes
            .iter()
            .try_fold(0u64, |sum, n| sum.checked_add(n.note().value().inner()))
            .ok_or("Gift Card value overflow")?;
        let mut amount = total;
        // Ask the same selector for its required fee, then quote the largest
        // payment covered by those exact inputs. No guessed claim fee is used.
        for _ in 0..4 {
            if amount == 0 {
                break;
            }
            match self.select_proposal(network, build_send_request(to, amount, memo)?) {
                Ok(proposal) => return summarize_send_max_proposal(&proposal),
                Err(InputSelectorError::InsufficientFunds {
                    available,
                    required,
                }) => {
                    let deficit = u64::from(required).saturating_sub(u64::from(available));
                    if deficit == 0 {
                        break;
                    }
                    amount = amount.saturating_sub(deficit);
                }
                Err(e) => return Err(format!("Gift Card quote failed: {e}")),
            }
        }
        Err("Insufficient balance for Gift Card claim".into())
    }
    fn selected(
        &self,
        account: AccountUuid,
        sources: &[ShieldedPool],
        exclude: &[ReceivedNoteId],
    ) -> ReceivedNotes<ReceivedNoteId> {
        if account != self.account || !sources.contains(&ShieldedPool::Ironwood) {
            return ReceivedNotes::empty();
        }
        ReceivedNotes::new(
            vec![],
            vec![],
            self.notes
                .iter()
                .filter(|n| !exclude.contains(n.internal_note_id()))
                .cloned()
                .collect(),
        )
    }
}
impl InputSource for CardInput<'_> {
    type Error = String;
    type AccountId = AccountUuid;
    type NoteRef = ReceivedNoteId;
    fn anchor_computable(&self, pool: ShieldedPool, height: BlockHeight) -> Result<bool, String> {
        self.db
            .anchor_computable(pool, height)
            .map_err(|e| e.to_string())
    }
    fn get_spendable_note(
        &self,
        id: &TxId,
        pool: ShieldedPool,
        index: u32,
        _: TargetHeight,
        _: LockFilter<'_>,
    ) -> Result<Option<ReceivedNote<ReceivedNoteId, Note>>, String> {
        Ok(if pool == ShieldedPool::Ironwood {
            self.notes
                .iter()
                .find(|n| n.txid() == id && n.output_index() as u32 == index)
                .cloned()
                .map(|n| {
                    n.map_note(|note| Note::Orchard {
                        note,
                        pool: orchard::ValuePool::Ironwood,
                    })
                })
        } else {
            None
        })
    }
    fn select_spendable_notes(
        &self,
        account: AccountUuid,
        _: TargetValue,
        sources: &[ShieldedPool],
        _: TargetHeight,
        _: ConfirmationsPolicy,
        exclude: &[ReceivedNoteId],
        _: LockFilter<'_>,
    ) -> Result<ReceivedNotes<ReceivedNoteId>, String> {
        Ok(self.selected(account, sources, exclude))
    }
    fn select_unspent_notes(
        &self,
        account: AccountUuid,
        sources: &[ShieldedPool],
        _: TargetHeight,
        exclude: &[ReceivedNoteId],
        _: LockFilter<'_>,
    ) -> Result<ReceivedNotes<ReceivedNoteId>, String> {
        Ok(self.selected(account, sources, exclude))
    }
    fn get_account_metadata(
        &self,
        account: AccountUuid,
        _: &NoteFilter,
        _: TargetHeight,
        exclude: &[ReceivedNoteId],
        _: LockFilter<'_>,
    ) -> Result<AccountMeta, String> {
        let selected = self.selected(account, &[ShieldedPool::Ironwood], exclude);
        Ok(AccountMeta::new(
            None,
            None,
            Some(PoolMeta::new(
                selected.ironwood().len(),
                selected.total_value().map_err(|e| e.to_string())?,
            )),
        ))
    }
    fn get_unspent_transparent_output(
        &self,
        _: &OutPoint,
        _: TargetHeight,
    ) -> Result<Option<WalletTransparentOutput<AccountUuid>>, String> {
        Ok(None)
    }
    fn get_spendable_transparent_outputs(
        &self,
        _: &TransparentAddress,
        _: TargetHeight,
        _: ConfirmationsPolicy,
        _: CoinbaseFilter,
        _: LockFilter<'_>,
    ) -> Result<Vec<WalletTransparentOutput<AccountUuid>>, String> {
        Ok(vec![])
    }
}

#[cfg(test)]
mod tests;
