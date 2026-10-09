use super::*;
use group::{Group, GroupEncoding};
use orchard::{
    keys::{FullViewingKey, OutgoingViewingKey},
    note::{ExtractedNoteCommitment, NoteVersion},
    note_encryption::{IronwoodDomain, IronwoodNoteEncryption},
    value::ValueCommitment,
};
use pasta_curves::pallas;
use prost::Message;
use rand_chacha::{ChaCha20Rng, rand_core::SeedableRng};
use zcash_client_backend::data_api::status::TransactionStatusRead;
use zcash_client_backend::{
    data_api::{
        chain::BlockSource,
        enhance_pir::{
            IronwoodEnhanceDiscoveryFailure, IronwoodEnhanceDiscoveryFailureReason::*,
            IronwoodEnhanceDiscoveryRequest, IronwoodEnhanceDiscoveryResult::*,
        },
        wallet::ConfirmationsPolicy,
    },
    proto::compact_formats::{CompactBlock, CompactOrchardAction, CompactTx},
};
use zcash_note_encryption::Domain;
use zcash_primitives::transaction::builder::DEFAULT_TX_EXPIRY_DELTA;

/// A real V3 encrypted action and its matching PIR record, including authentic OVK ciphertext.
fn encrypted_action(
    nf: [u8; 32],
    recipient: orchard::Address,
    ovk: OutgoingViewingKey,
    value: u64,
) -> (CompactOrchardAction, EnhanceRecord) {
    let rho = Rho::from_bytes(&nf).unwrap();
    let rseed = RandomSeed::from_bytes([7; 32], &rho).unwrap();
    let note = Note::from_parts(
        recipient,
        NoteValue::from_raw(value),
        rho,
        rseed,
        NoteVersion::V3,
    )
    .unwrap();
    let encryptor = IronwoodNoteEncryption::new(Some(ovk), note, [4; 512]);
    let cmx = ExtractedNoteCommitment::from(note.commitment());
    let cv = ValueCommitment::from_bytes(&pallas::Point::generator().to_bytes()).unwrap();
    let mut rng = ChaCha20Rng::from_seed([7; 32]);
    let record = EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: (encryptor.encrypt_note_plaintext())[52..]
            .try_into()
            .unwrap(),
        cv_net: cv.to_bytes(),
        out_ciphertext: encryptor.encrypt_outgoing_plaintext(&cv, &cmx, &mut rng),
        has_transparent_inputs: false,
        has_transparent_outputs: false,
        metadata: zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
            0,
            Some(0),
        )
        .unwrap(),
    });
    (
        CompactOrchardAction {
            nullifier: nf.to_vec(),
            cmx: cmx.to_bytes().to_vec(),
            ephemeral_key: IronwoodDomain::epk_bytes(encryptor.epk()).0.to_vec(),
            ciphertext: encryptor.encrypt_note_plaintext()[..52].to_vec(),
        },
        record,
    )
}

fn cached(st: &State, height: BlockHeight) -> CompactBlock {
    let mut result = None;
    st.cache()
        .with_blocks::<_, SqliteClientError>(Some(height), Some(1), |block| {
            result = Some(block);
            Ok(())
        })
        .unwrap();
    result.unwrap()
}

struct Send {
    st: State,
    funding_height: BlockHeight,
    second_funding: Option<(BlockHeight, AccountUuid)>,
    block: CompactBlock,
    record: EnhanceRecord,
    change_record: Option<EnhanceRecord>,
    dummy_records: Vec<EnhanceRecord>,
    recipient: orchard::Address,
}

impl Send {
    fn new(change: bool) -> Self {
        Self::with_second_funder(change, false)
    }

    fn with_second_funder(change: bool, second_funder: bool) -> Self {
        Self::build(change, second_funder, 0, false, false)
    }

    /// A change-and-recipient send padded with `dummies` zero-value actions whose outgoing
    /// ciphertexts use a foreign OVK, as a builder's padding would.
    fn with_dummies(dummies: u8) -> Self {
        Self::build(true, false, dummies, false, false)
    }

    /// Like [`Self::with_dummies`], but every note is zero-valued, so with a zero fee the
    /// linked spends sum to zero.
    fn with_zero_value_dummies(dummies: u8) -> Self {
        Self::build(true, false, dummies, true, false)
    }

    /// A two-funder send that stays unbalanced until the first funder is deleted: the first
    /// account's 50_000 note pays 30_000 of change plus a 20_000 output encrypted to a foreign
    /// OVK, and the second account's 30_000 note pays the 30_000 recipient.
    fn with_undecryptable_first_funder_output() -> Self {
        Self::build(true, true, 1, false, true)
    }

    fn build(
        change: bool,
        second_funder: bool,
        dummies: u8,
        zero_value: bool,
        hidden_split: bool,
    ) -> Self {
        let (second_funding_value, dummy_value) = if hidden_split {
            (30_000, 20_000)
        } else {
            (10_000, 0)
        };
        let value = |zatoshis: u64| if zero_value { 0 } else { zatoshis };
        let mut st = state_with_factory(TestDbFactory::file_backed());
        st.wallet_mut()
            .db_mut()
            .set_enhancement_mode(EnhancementMode::PrivateIronwood);
        let fvk = IronwoodFvk(OrchardPoolTester::test_account_fvk(&st));
        let second = second_funder.then(|| {
            let (account, usk) = st.create_account_from_test_seed("second funder");
            (
                account,
                IronwoodFvk(usk.to_unified_full_viewing_key().orchard().unwrap().clone()),
            )
        });
        let (funding_height, _, nf) = st.generate_next_block(
            &fvk,
            AddressType::DefaultExternal,
            Zatoshis::const_from_u64(value(50_000)),
        );
        let second_funding = second.as_ref().map(|(account, key)| {
            let (height, _, nf) = st.generate_next_block(
                key,
                AddressType::DefaultExternal,
                Zatoshis::const_from_u64(second_funding_value),
            );
            (height, *account, nf)
        });
        let (height, _) = st.generate_empty_block();
        let mut block = cached(&st, height);
        let other_fvk: FullViewingKey =
            OrchardPoolTester::sk_to_fvk(&OrchardPoolTester::sk(&[0xf5; 32]));
        let recipient = other_fvk.address_at(0u32, Scope::External);
        let mut actions = vec![];
        let mut change_record = None;
        if change {
            let (action, record) = encrypted_action(
                nf.to_bytes(),
                fvk.0.address_at(0u32, Scope::Internal),
                fvk.0.to_ovk(Scope::Internal),
                value(30_000),
            );
            actions.push(action);
            change_record = Some(record);
        }
        let (action, record) = encrypted_action(
            second_funding
                .map(|(_, _, nf)| nf.to_bytes())
                .unwrap_or_else(|| if change { [9; 32] } else { nf.to_bytes() }),
            recipient,
            second
                .as_ref()
                .map_or(&fvk, |(_, key)| key)
                .0
                .to_ovk(Scope::External),
            value(if second_funder {
                30_000
            } else if change {
                20_000
            } else {
                50_000
            }),
        );
        actions.push(action);
        let mut dummy_records = vec![];
        for i in 0..dummies {
            let (action, record) = encrypted_action(
                [0x20 + i; 32],
                recipient,
                other_fvk.to_ovk(Scope::External),
                dummy_value,
            );
            actions.push(action);
            dummy_records.push(record);
        }
        block
            .chain_metadata
            .as_mut()
            .unwrap()
            .ironwood_commitment_tree_size += actions.len() as u32;
        block.vtx = vec![CompactTx {
            txid: vec![42; 32],
            index: 1,
            ironwood_actions: actions,
            ..Default::default()
        }];
        // Only this final block is replaced; its predecessor's cached ChainState is unchanged.
        st.cache()
            .0
            .execute(
                "UPDATE compactblocks SET data = ?1 WHERE height = ?2",
                rusqlite::params![block.encode_to_vec(), u32::from(height)],
            )
            .unwrap();
        Self {
            st,
            funding_height,
            second_funding: second_funding.map(|(height, account, _)| (height, account)),
            block,
            record,
            change_record,
            dummy_records,
            recipient,
        }
    }

    fn tx_ref(&self) -> crate::TxRef {
        self.st
            .wallet()
            .conn()
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                [&self.block.vtx[0].txid],
                |row| row.get(0).map(crate::TxRef),
            )
            .unwrap()
    }

    fn queued(&self) -> bool {
        self.st.wallet().conn().query_row("SELECT EXISTS(SELECT 1 FROM tx_retrieval_queue WHERE txid = ?1 AND query_type = ?2)",
            rusqlite::params![&self.block.vtx[0].txid, TxQueryType::Enhancement.code()], |row| row.get(0)).unwrap()
    }

    fn requests(&self) -> Vec<EnhancePirRequest> {
        self.st
            .wallet()
            .db()
            .query_requests()
            .unwrap()
            .into_iter()
            .filter(|r| r.request_id().txid().as_ref().as_slice() == self.block.vtx[0].txid)
            .collect()
    }

    fn scan_send(&mut self) {
        self.st.scan_cached_blocks(self.block.height(), 1);
    }
    fn scan_funding(&mut self) {
        self.st.scan_cached_blocks(self.funding_height, 1);
    }

    fn discovery(&self) -> IronwoodEnhanceDiscoveryRequest {
        let jobs = self.st.wallet().db().discovery_requests().unwrap();
        assert_eq!(jobs.len(), 1);
        jobs[0]
    }

    fn rebuild(&mut self) {
        let request = self.discovery();
        assert_eq!(
            self.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &self.block)
                .unwrap(),
            Rebuilt(1)
        );
        assert!(
            self.st
                .wallet()
                .db()
                .discovery_requests()
                .unwrap()
                .is_empty()
        );
    }
}

#[test]
fn rediscovery_restores_legacy_received_note_compact_context() {
    let mut send = Send::new(true);

    // Model old history scanned before the rc5 upgrade: the received change note exists, but
    // the compact encryption columns added by the migration have no historical values.
    send.scan_send();
    let tx_ref = send.tx_ref();
    send.st
        .wallet()
        .conn()
        .execute(
            "UPDATE ironwood_received_notes
             SET ephemeral_key = NULL, compact_ciphertext = NULL
             WHERE transaction_id = ?",
            [tx_ref.0],
        )
        .unwrap();

    // Scanning only the funding block links its spend and reopens discovery of the send.
    send.scan_funding();
    let discovery = send.discovery();
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(discovery, &send.block)
            .unwrap(),
        Rebuilt(1)
    );

    let incoming = send
        .requests()
        .into_iter()
        .find(|request| request.request_id().output_index() == 0)
        .unwrap();
    assert_eq!(
        apply_record(
            send.st.wallet_mut().db_mut(),
            incoming,
            send.change_record.as_ref().unwrap(),
        )
        .unwrap(),
        EnhancePirStoreResult::Stored
    );
}

/// Recent-first incoming completion must not hide the later sender obligation.
fn cross_account_restore(funding_first: bool) {
    let mut send = Send::new(true);
    let (receiver, usk) = send.st.create_account_from_test_seed("receiver");
    let recipient = usk
        .to_unified_full_viewing_key()
        .orchard()
        .unwrap()
        .address_at(0u32, Scope::External);
    let sender = send.st.test_account().unwrap().id();
    let fvk = OrchardPoolTester::test_account_fvk(&send.st);
    let (action, record) =
        encrypted_action([9; 32], recipient, fvk.to_ovk(Scope::External), 20_000);
    send.block.vtx[0].ironwood_actions[1] = action;
    send.st
        .cache()
        .0
        .execute(
            "UPDATE compactblocks SET data = ?1 WHERE height = ?2",
            rusqlite::params![send.block.encode_to_vec(), u32::from(send.block.height())],
        )
        .unwrap();
    if funding_first {
        send.scan_funding();
    }
    send.scan_send();
    let requests = send.requests();
    assert_eq!(requests.len(), 2);
    for request in &requests {
        if !funding_first || request.request_id().output_index() == 0 {
            finish_incoming(&mut send.st, *request);
        }
    }
    if !funding_first {
        send.scan_funding();
        send.rebuild();
    }
    assert!(
        send.queued(),
        "receiver memo completion must retain sender history work"
    );
    let outgoing = send.requests();
    assert_eq!(
        outgoing.len(),
        1,
        "internal change must not need outgoing recovery"
    );
    assert_eq!(outgoing[0].request_id().output_index(), 1);
    assert_eq!(
        send.st
            .wallet()
            .db()
            .pending_outgoing(outgoing[0].position())
            .unwrap()
            .unwrap()
            .account_ids,
        vec![sender]
    );
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), outgoing[0], &record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    let (from, address, value, memo): (AccountUuid, String, u64, Vec<u8>) = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT a.uuid, sn.to_address, sn.value, sn.memo FROM sent_notes sn
             JOIN accounts a ON a.id = sn.from_account_id
             WHERE sn.transaction_id = ?1 AND sn.output_index = 1",
            [send.tx_ref().0],
            |row| {
                Ok((
                    AccountUuid(row.get(0)?),
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                ))
            },
        )
        .unwrap();
    assert_eq!(from, sender);
    assert_eq!(
        address,
        Receiver::Orchard(recipient)
            .to_zcash_address(send.st.network().network_type())
            .to_string()
    );
    assert_eq!(value, 20_000);
    assert_eq!(memo, vec![4; 512]);
    let (to, value, change, has_memo): (AccountUuid, u64, bool, bool) = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT a.uuid, rn.value, rn.is_change, rn.memo IS NOT NULL
             FROM ironwood_received_notes rn JOIN accounts a ON a.id = rn.account_id
             WHERE rn.transaction_id = ?1 AND rn.action_index = 1",
            [send.tx_ref().0],
            |row| {
                Ok((
                    AccountUuid(row.get(0)?),
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                ))
            },
        )
        .unwrap();
    assert_eq!(
        (to, value, change, has_memo),
        (receiver, 20_000, false, true)
    );
    assert!(!send.queued());
    assert!(send.requests().is_empty());
}

#[test]
fn cross_account_funding_first_restore_preserves_sender_history() {
    cross_account_restore(true);
}

#[test]
fn cross_account_recent_first_restore_preserves_sender_history() {
    cross_account_restore(false);
}

#[test]
fn rescanning_a_send_preserves_pending_and_suspended_outgoing_recovery() {
    for suspend in [false, true] {
        let mut send = Send::new(true);
        send.scan_funding();
        send.scan_send();
        let requests = send.requests();
        let change = *requests
            .iter()
            .find(|r| r.request_id().output_index() == 0)
            .unwrap();
        let outgoing = *requests
            .iter()
            .find(|r| r.request_id().output_index() == 1)
            .unwrap();
        finish_incoming(&mut send.st, change);
        if suspend {
            let mut ciphertext = *send.record.enc_ciphertext_suffix();
            ciphertext[527] ^= 1;
            let corrupt = EnhanceRecord::from_parts(EnhanceRecordParts {
                enc_ciphertext_suffix: ciphertext,
                cv_net: *send.record.cv_net(),
                out_ciphertext: *send.record.out_ciphertext(),
                has_transparent_inputs: false,
                has_transparent_outputs: false,
                metadata:
                    zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
                        0,
                        Some(0),
                    )
                    .unwrap(),
            });
            assert_eq!(
                apply_record(send.st.wallet_mut().db_mut(), outgoing, &corrupt).unwrap(),
                EnhancePirStoreResult::NotRecoverable
            );
        }
        // The mined funding note is now absent from the scanner's unspent nullifier set.
        // Its change output still makes this a wallet transaction on replay.
        send.scan_send();
        assert!(
            send.queued(),
            "rescan must not retire unresolved outgoing history"
        );
        assert!(!visible(&send.st, outgoing));
        send.st
            .wallet_mut()
            .db_mut()
            .set_enhancement_mode(EnhancementMode::Standard);
        assert!(
            visible(&send.st, outgoing),
            "ordinary fallback must survive the rescan"
        );
        send.st
            .wallet_mut()
            .db_mut()
            .set_enhancement_mode(EnhancementMode::PrivateIronwood);
        send.rebuild();
        assert_eq!(send.requests(), vec![outgoing]);
        assert_eq!(
            apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
            EnhancePirStoreResult::Stored
        );
        assert!(!send.queued());
        let (value, memo): (u64, Vec<u8>) = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT value, memo FROM sent_notes WHERE transaction_id = ?1 AND output_index = 1",
                [send.tx_ref().0],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!((value, memo), (20_000, vec![4; 512]));
    }
}

impl Send {
    fn request_at(&self, output_index: u32) -> EnhancePirRequest {
        *self
            .requests()
            .iter()
            .find(|r| r.request_id().output_index() == output_index)
            .unwrap()
    }

    fn apply(
        &mut self,
        request: EnhancePirRequest,
        record: &EnhanceRecord,
    ) -> EnhancePirStoreResult {
        apply_record(self.st.wallet_mut().db_mut(), request, record).unwrap()
    }

    fn suspended_outgoing(&self) -> usize {
        self.st
            .wallet()
            .conn()
            .query_row(
                "SELECT COUNT(*) FROM ironwood_enhance_outgoing_queue
                 WHERE transaction_id = ?1 AND not_recoverable = 1",
                [self.tx_ref().0],
                |row| row.get(0),
            )
            .unwrap()
    }

    fn reported_suspensions(&self) -> usize {
        self.st
            .wallet()
            .db()
            .transaction_enhancement_work()
            .unwrap()
            .into_iter()
            .filter(|work| {
                matches!(
                    work,
                    TransactionEnhancementWork::Private(EnhancePirWork::Suspended(
                        EnhancePirSuspension::OutgoingNotRecoverable(_)
                    ))
                )
            })
            .count()
    }
}

#[test]
fn value_balanced_dummy_outputs_retire_in_either_record_order() {
    for dummies_first in [false, true] {
        let mut send = Send::with_dummies(2);
        send.scan_funding();
        send.scan_send();
        let (change, recipient) = (send.request_at(0), send.request_at(1));
        let dummies = [send.request_at(2), send.request_at(3)];
        let (change_record, record) = (send.change_record.clone().unwrap(), send.record.clone());
        let dummy_records = send.dummy_records.clone();

        let apply_dummies = |send: &mut Send| {
            for (request, record) in dummies.iter().zip(&dummy_records) {
                assert_eq!(
                    send.apply(*request, record),
                    EnhancePirStoreResult::NotRecoverable
                );
            }
        };
        if dummies_first {
            apply_dummies(&mut send);
            assert_eq!(
                send.suspended_outgoing(),
                2,
                "an open real output means the balance cannot yet prove the dummies"
            );
            assert!(send.queued());
        }
        assert_eq!(
            send.apply(change, &change_record),
            EnhancePirStoreResult::Stored
        );
        assert_eq!(
            send.apply(recipient, &record),
            EnhancePirStoreResult::Stored
        );
        if !dummies_first {
            apply_dummies(&mut send);
        }

        assert_eq!(send.suspended_outgoing(), 0);
        assert_eq!(send.reported_suspensions(), 0);
        assert!(send.requests().is_empty());
        assert!(
            !send.queued(),
            "the completed transaction releases its txid request"
        );
        let value: u64 = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT value FROM sent_notes WHERE transaction_id = ?1 AND output_index = 1",
                [send.tx_ref().0],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(value, 20_000);
    }
}

#[test]
fn zero_valued_spends_still_retire_dummies() {
    let mut send = Send::with_zero_value_dummies(1);
    send.scan_funding();
    send.scan_send();
    let (change, recipient, dummy) = (send.request_at(0), send.request_at(1), send.request_at(2));
    let (change_record, record) = (send.change_record.clone().unwrap(), send.record.clone());
    let dummy_record = send.dummy_records[0].clone();

    assert_eq!(
        send.apply(change, &change_record),
        EnhancePirStoreResult::Stored
    );
    assert_eq!(
        send.apply(recipient, &record),
        EnhancePirStoreResult::Stored
    );
    assert_eq!(
        send.apply(dummy, &dummy_record),
        EnhancePirStoreResult::NotRecoverable
    );

    // 0 spent = 0 recovered + 0 fee: a linked spend, not a positive sum, marks it wallet-funded.
    assert_eq!(send.suspended_outgoing(), 0);
    assert!(!send.queued());
}

#[test]
fn deleting_a_funder_reevaluates_a_now_balanced_suspension() {
    let mut send = Send::with_undecryptable_first_funder_output();
    send.scan_funding();
    let (height, _) = send.second_funding.unwrap();
    send.st.scan_cached_blocks(height, 1);
    send.scan_send();
    let (change, recipient, hidden) = (send.request_at(0), send.request_at(1), send.request_at(2));
    let (change_record, record) = (send.change_record.clone().unwrap(), send.record.clone());
    let hidden_record = send.dummy_records[0].clone();

    assert_eq!(
        send.apply(change, &change_record),
        EnhancePirStoreResult::Stored
    );
    assert_eq!(
        send.apply(recipient, &record),
        EnhancePirStoreResult::Stored
    );
    assert_eq!(
        send.apply(hidden, &hidden_record),
        EnhancePirStoreResult::NotRecoverable
    );
    // 80_000 spent, 60_000 recovered: the 20_000 output may be real, so it stays suspended.
    assert_eq!(send.suspended_outgoing(), 1);
    assert!(send.queued());

    // Deleting the first funder removes its spend link and sent notes. The second funder's
    // 30_000 now equals its recovered 30_000 plus the zero fee, and no record will arrive
    // to re-run the rule, so deletion itself must.
    let account_a = send.st.test_account().unwrap().id();
    send.st
        .wallet_mut()
        .db_mut()
        .delete_account(account_a)
        .unwrap();
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    assert_eq!(send.suspended_outgoing(), 0);
    assert_eq!(send.reported_suspensions(), 0);
    assert!(!send.queued());
}

#[test]
fn an_undecryptable_real_output_keeps_every_suspension() {
    let mut send = Send::with_dummies(1);
    send.scan_funding();
    send.scan_send();
    let (change, recipient, dummy) = (send.request_at(0), send.request_at(1), send.request_at(2));
    let change_record = send.change_record.clone().unwrap();
    let dummy_record = send.dummy_records[0].clone();
    // The recipient's outgoing ciphertext fails OVK decryption, like an OVK-discarded payment.
    let mut ciphertext = *send.record.enc_ciphertext_suffix();
    ciphertext[527] ^= 1;
    let corrupt = EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: ciphertext,
        cv_net: *send.record.cv_net(),
        out_ciphertext: *send.record.out_ciphertext(),
        has_transparent_inputs: false,
        has_transparent_outputs: false,
        metadata: zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
            0,
            Some(0),
        )
        .unwrap(),
    });

    assert_eq!(
        send.apply(change, &change_record),
        EnhancePirStoreResult::Stored
    );
    assert_eq!(
        send.apply(recipient, &corrupt),
        EnhancePirStoreResult::NotRecoverable
    );
    assert_eq!(
        send.apply(dummy, &dummy_record),
        EnhancePirStoreResult::NotRecoverable
    );

    // 50_000 spent, 30_000 recovered, fee 0: 20_000 is unaccounted for, so nothing is proven.
    assert_eq!(send.suspended_outgoing(), 2);
    assert_eq!(send.reported_suspensions(), 2);
    assert!(send.queued());
}

#[test]
fn later_funding_account_reopens_suspended_ovk_recovery() {
    let mut send = Send::with_second_funder(true, true);
    send.scan_funding();
    send.scan_send();
    let outgoing = send
        .requests()
        .into_iter()
        .find(|r| r.request_id().output_index() == 1)
        .unwrap();
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
        EnhancePirStoreResult::NotRecoverable
    );
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    let (height, account) = send.second_funding.unwrap();
    send.st.scan_cached_blocks(height, 1);
    send.rebuild();
    let pending = send
        .st
        .wallet()
        .db()
        .pending_outgoing(outgoing.position())
        .unwrap()
        .unwrap();
    assert_eq!(pending.account_ids.len(), 2);
    assert!(pending.account_ids.contains(&account));
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    let from_account: AccountUuid = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT a.uuid FROM sent_notes sn JOIN accounts a ON a.id = sn.from_account_id
         WHERE sn.transaction_id = ?1 AND sn.output_index = 1",
            [send.tx_ref().0],
            |row| row.get(0).map(AccountUuid),
        )
        .unwrap();
    assert_eq!(from_account, account);
}

/// Two discovery jobs at one height: A pays B, and B pays an external recipient.
/// Deleting A retains the first transaction for B, but removes its only funding key.
fn shared_and_independent_jobs() -> Send {
    let mut send = Send::with_second_funder(true, true);
    let (_, account_b) = send.second_funding.unwrap();
    let account = send
        .st
        .wallet()
        .db()
        .get_account(account_b)
        .unwrap()
        .unwrap();
    let key_b = account.ufvk().unwrap().orchard().unwrap();
    let key_a = OrchardPoolTester::test_account_fvk(&send.st);
    let actions = &send.block.vtx[0].ironwood_actions;
    let shared = encrypted_action(
        actions[0].nf().unwrap().to_bytes(),
        key_b.address_at(0u32, Scope::External),
        key_a.to_ovk(Scope::External),
        50_000,
    )
    .0;
    let (independent, record) = encrypted_action(
        actions[1].nf().unwrap().to_bytes(),
        send.recipient,
        key_b.to_ovk(Scope::External),
        10_000,
    );
    send.block.vtx[0].ironwood_actions = vec![shared];
    send.block.vtx.push(CompactTx {
        txid: vec![43; 32],
        index: 2,
        ironwood_actions: vec![independent],
        ..Default::default()
    });
    send.record = record;
    send.st
        .cache()
        .0
        .execute(
            "UPDATE compactblocks SET data = ?1 WHERE height = ?2",
            rusqlite::params![send.block.encode_to_vec(), u32::from(send.block.height())],
        )
        .unwrap();
    send.scan_send();
    send.scan_funding();
    send.st
        .scan_cached_blocks(send.second_funding.unwrap().0, 1);
    send
}

#[test]
fn deleting_a_funder_does_not_block_another_transaction_in_the_block() {
    let mut send = shared_and_independent_jobs();
    let account_a = send.st.test_account().unwrap().id();
    let request = send.discovery();
    send.st
        .wallet_mut()
        .db_mut()
        .delete_account(account_a)
        .unwrap();
    assert!(
        send.queued(),
        "shared transaction and its enhancement intent survive"
    );
    let suspended = vec![IronwoodEnhanceDiscoveryFailure {
        txid: send.block.vtx[0].txid(),
        reason: NoFundingAccounts,
    }];
    assert_eq!(
        send.st.wallet().db().discovery_suspensions().unwrap(),
        suspended
    );
    let incoming = send.requests()[0];
    finish_incoming(&mut send.st, incoming);
    assert!(
        send.queued(),
        "memo completion must not retire a suspended discovery job"
    );
    assert!(
        !visible(&send.st, incoming),
        "deleting keys is not permission to use LWD"
    );
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(request, &send.block)
            .unwrap(),
        Rebuilt(1)
    );
    let outgoing = send
        .st
        .wallet()
        .db()
        .query_requests()
        .unwrap()
        .into_iter()
        .find(|r| r.request_id().txid() == send.block.vtx[1].txid())
        .unwrap();
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty(),
        "a suspended-only block is not downloaded again"
    );
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(request, &send.block)
            .unwrap(),
        AlreadyResolved
    );
    use crate::testing::db::{test_clock, test_rng};
    let mut reopened = crate::WalletDb::for_path(
        send.st.wallet().data_file_path(),
        *send.st.network(),
        test_clock(),
        test_rng(),
    )
    .unwrap()
    .with_enhancement_mode(zcash_client_backend::data_api::enhance_pir::EnhancementMode::Standard);
    assert_eq!(reopened.discovery_suspensions().unwrap(), suspended);
    assert!(
        reopened
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(incoming.request_id().txid()))
    );
    reopened.set_enhancement_mode(EnhancementMode::PrivateIronwood);
    assert!(
        !reopened
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(incoming.request_id().txid()))
    );
}

#[test]
fn transaction_local_failure_does_not_block_a_valid_sibling() {
    for missing in [false, true] {
        let mut send = shared_and_independent_jobs();
        let request = send.discovery();
        let mut bad = send.block.clone();
        let reason = if missing {
            bad.vtx[0].txid = vec![99; 32];
            TransactionMissing
        } else {
            bad.vtx[0].ironwood_actions[0].ephemeral_key.clear();
            ContextMismatch
        };
        let unresolved = vec![IronwoodEnhanceDiscoveryFailure {
            txid: send.block.vtx[0].txid(),
            reason,
        }];
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &bad)
                .unwrap(),
            Incomplete {
                rebuilt: 1,
                unresolved: unresolved.clone()
            }
        );
        assert!(send.queued());
        assert_eq!(
            send.discovery(),
            request,
            "failed job is retryable, not deleted"
        );
        let healthy = send
            .st
            .wallet()
            .db()
            .query_requests()
            .unwrap()
            .into_iter()
            .find(|r| r.request_id().txid() == send.block.vtx[1].txid())
            .unwrap();
        assert!(!visible(&send.st, healthy));
        assert_eq!(
            apply_record(send.st.wallet_mut().db_mut(), healthy, &send.record).unwrap(),
            EnhancePirStoreResult::Stored
        );
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &bad)
                .unwrap(),
            Incomplete {
                rebuilt: 0,
                unresolved
            }
        );
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &send.block)
                .unwrap(),
            Rebuilt(1)
        );
    }
}

#[test]
fn an_active_orphan_is_suspended_without_blocking_a_valid_sibling() {
    let mut send = shared_and_independent_jobs();
    let account_a = send.st.test_account().unwrap().id();
    let request = send.discovery();
    send.st
        .wallet_mut()
        .db_mut()
        .delete_account(account_a)
        .unwrap();
    // Simulate a job whose deletion cleanup was missed by an older implementation.
    send.st
        .wallet()
        .conn()
        .execute(
            "UPDATE ironwood_enhance_discovery_queue SET suspended = 0",
            [],
        )
        .unwrap();
    let unresolved = vec![IronwoodEnhanceDiscoveryFailure {
        txid: send.block.vtx[0].txid(),
        reason: NoFundingAccounts,
    }];
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(request, &send.block)
            .unwrap(),
        Incomplete {
            rebuilt: 1,
            unresolved: unresolved.clone()
        }
    );
    assert_eq!(
        send.st.wallet().db().discovery_suspensions().unwrap(),
        unresolved
    );
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
}

#[test]
fn a_sql_error_rolls_back_sibling_progress_and_defensive_suspension() {
    for orphaned in [false, true] {
        let mut send = shared_and_independent_jobs();
        let request = send.discovery();
        if orphaned {
            let account_a = send.st.test_account().unwrap().id();
            send.st
                .wallet_mut()
                .db_mut()
                .delete_account(account_a)
                .unwrap();
            send.st
                .wallet()
                .conn()
                .execute(
                    "UPDATE ironwood_enhance_discovery_queue SET suspended = 0",
                    [],
                )
                .unwrap();
        }
        let before = send.st.wallet().db().query_requests().unwrap();
        // The second job fails after the first job has been rebuilt or suspended.
        send.st.wallet().conn().execute_batch(
            "CREATE TRIGGER fail_second_discovery BEFORE DELETE ON ironwood_enhance_discovery_queue
             WHEN (SELECT tx_index FROM transactions WHERE id_tx = OLD.transaction_id) = 2
             BEGIN SELECT RAISE(ABORT, 'injected failure'); END;",
        ).unwrap();
        assert!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &send.block)
                .is_err()
        );
        assert_eq!(send.st.wallet().db().query_requests().unwrap(), before);
        assert!(
            send.st
                .wallet()
                .db()
                .discovery_suspensions()
                .unwrap()
                .is_empty()
        );
        let jobs: i64 = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT COUNT(*) FROM ironwood_enhance_discovery_queue WHERE suspended = 0",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(jobs, 2);
        assert!(send.queued());
        send.st
            .wallet()
            .conn()
            .execute_batch("DROP TRIGGER fail_second_discovery")
            .unwrap();
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &send.block)
                .unwrap(),
            if orphaned {
                Incomplete {
                    rebuilt: 1,
                    unresolved: vec![IronwoodEnhanceDiscoveryFailure {
                        txid: send.block.vtx[0].txid(),
                        reason: NoFundingAccounts,
                    }],
                }
            } else {
                Rebuilt(2)
            }
        );
    }
}

#[test]
fn invalid_block_geometry_or_ordering_rejects_all_jobs_without_mutation() {
    let mut send = shared_and_independent_jobs();
    let request = send.discovery();
    let before = send.st.wallet().db().query_requests().unwrap();
    for kind in 0..4 {
        let mut bad = send.block.clone();
        match kind {
            0 => {
                bad.chain_metadata
                    .as_mut()
                    .unwrap()
                    .ironwood_commitment_tree_size += 1
            }
            1 => bad.vtx.reverse(),
            2 => bad.vtx[1].txid = bad.vtx[0].txid.clone(),
            _ => bad.vtx.pop().map(|_| ()).unwrap(),
        }
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &bad)
                .unwrap(),
            Rejected
        );
        assert_eq!(send.st.wallet().db().query_requests().unwrap(), before);
        let jobs: i64 = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT COUNT(*) FROM ironwood_enhance_discovery_queue",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(jobs, 2);
    }
}

#[test]
fn reconstruction_requires_the_preceding_tree_size() {
    let mut send = Send::new(false);
    send.scan_send();
    send.scan_funding();
    let request = send.discovery();
    let prior_height = u32::from(request.height) - 1;
    let prior_size = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT ironwood_commitment_tree_size FROM blocks WHERE height = ?1",
            [prior_height],
            |row| row.get::<_, u32>(0),
        )
        .unwrap();
    send.st
        .wallet()
        .conn()
        .execute(
            "UPDATE blocks SET ironwood_commitment_tree_size = NULL WHERE height = ?1",
            [prior_height],
        )
        .unwrap();

    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(request, &send.block)
            .unwrap(),
        Rejected
    );
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        send.st.wallet().db().discovery_suspensions().unwrap(),
        vec![IronwoodEnhanceDiscoveryFailure {
            txid: send.block.vtx[0].txid(),
            reason: AnchorUnavailable,
        }]
    );
    assert!(send.requests().is_empty());
    assert!(send.queued());
    send.st
        .wallet()
        .conn()
        .execute(
            "UPDATE blocks SET ironwood_commitment_tree_size = ?1 WHERE height = ?2",
            rusqlite::params![prior_size, prior_height],
        )
        .unwrap();
    assert_eq!(send.discovery(), request);
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_suspensions()
            .unwrap()
            .is_empty()
    );
    send.rebuild();
}

#[test]
fn discovery_waits_for_the_spending_blocks_tree_size() {
    let mut send = Send::new(false);
    send.scan_send();
    send.scan_funding();
    let request = send.discovery();
    send.st
        .wallet()
        .conn()
        .execute(
            "UPDATE blocks SET ironwood_commitment_tree_size = NULL WHERE height = ?1",
            [u32::from(request.height)],
        )
        .unwrap();

    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        send.st.wallet().db().discovery_suspensions().unwrap(),
        vec![IronwoodEnhanceDiscoveryFailure {
            txid: send.block.vtx[0].txid(),
            reason: AnchorUnavailable,
        }]
    );
    assert!(send.queued());
}

#[test]
fn reconstruction_cannot_take_an_outgoing_position_from_another_transaction() {
    let routing_and_discovery = |conn: &Connection| -> Vec<(i64, i64, Option<i64>)> {
        conn.prepare(
            "SELECT r.transaction_id, r.route, q.suspended
             FROM ironwood_enhance_routing r
             LEFT JOIN ironwood_enhance_discovery_queue q ON q.transaction_id = r.transaction_id
             ORDER BY r.transaction_id",
        )
        .unwrap()
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap()
    };
    for (inputs, outputs) in [(false, false), (true, false), (false, true), (true, true)] {
        let mut send = shared_and_independent_jobs();
        if inputs {
            send.block.vtx[1]
                .vin
                .push(zcash_client_backend::proto::compact_formats::CompactTxIn {
                    prevout_txid: vec![8; 32],
                    prevout_index: 0,
                });
        }
        if outputs {
            send.block.vtx[1].vout.push(Default::default());
        }
        let request = send.discovery();
        let end = send
            .block
            .chain_metadata
            .as_ref()
            .unwrap()
            .ironwood_commitment_tree_size;
        let position = end - 1;
        let owner = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                [&send.block.vtx[0].txid],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        send.st
            .wallet()
            .conn()
            .execute(
                "INSERT INTO ironwood_enhance_outgoing_queue (
                 commitment_tree_position, transaction_id, output_index, nullifier, cmx,
                 ephemeral_key, compact_ciphertext
             ) VALUES (?1, ?2, 9, ?3, ?4, ?5, ?6)",
                rusqlite::params![
                    position, owner, [91u8; 32], [92u8; 32], [93u8; 32], [94u8; 52]
                ],
            )
            .unwrap();
        let before = send.st.wallet().db().private_work().unwrap();
        let ordinary_before = send.st.wallet().db().transaction_data_requests().unwrap();
        let routing_before = routing_and_discovery(send.st.wallet().conn());

        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &send.block)
                .unwrap(),
            Rejected,
            "position conflicts must reject even with transparent inputs={inputs}, outputs={outputs}"
        );
        let claimant = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                [&send.block.vtx[1].txid],
                |row| row.get::<_, i64>(0).map(crate::TxRef),
            )
            .unwrap();
        assert!(
            queue_transaction(
                send.st.wallet().conn(),
                claimant,
                &IronwoodEnhancementPlan::Eligible {
                    outgoing: vec![IronwoodEnhanceCandidate::from_parts(
                        u64::from(position).into(),
                        0,
                        [81; 32],
                        [82; 32],
                        [83; 32],
                        [84; 52],
                        vec![],
                    )]
                }
            )
            .is_err(),
            "the queue itself must also refuse cross-transaction replacement"
        );
        let retained_owner = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT transaction_id FROM ironwood_enhance_outgoing_queue
             WHERE commitment_tree_position = ?1",
                [position],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        assert_eq!(retained_owner, owner);
        assert_eq!(send.st.wallet().db().private_work().unwrap(), before);
        assert_eq!(
            send.st.wallet().db().transaction_data_requests().unwrap(),
            ordinary_before
        );
        assert_eq!(
            routing_and_discovery(send.st.wallet().conn()),
            routing_before
        );
        assert_eq!(send.discovery(), request);
        assert!(send.queued());
    }
}

#[test]
fn deleting_one_of_multiple_funders_keeps_discovery_active() {
    let mut send = Send::with_second_funder(true, true);
    send.scan_send();
    send.scan_funding();
    let (height, account_b) = send.second_funding.unwrap();
    send.st.scan_cached_blocks(height, 1);
    let account_a = send.st.test_account().unwrap().id();
    send.st
        .wallet_mut()
        .db_mut()
        .delete_account(account_a)
        .unwrap();
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_suspensions()
            .unwrap()
            .is_empty()
    );
    send.rebuild();
    for request in send.requests() {
        let pending = send
            .st
            .wallet()
            .db()
            .pending_outgoing(request.position())
            .unwrap()
            .unwrap();
        assert_eq!(pending.account_ids, vec![account_b]);
    }
}

#[test]
fn deleting_an_exclusively_owned_transaction_cascades_its_discovery_job() {
    let mut send = Send::new(false);
    send.scan_send();
    send.scan_funding();
    send.discovery();
    let txid = send.block.vtx[0].txid();
    let account = send.st.test_account().unwrap().id();
    send.st
        .wallet_mut()
        .db_mut()
        .transactionally(|db| crate::wallet::queue_tx_status(db.conn.0, txid))
        .unwrap();
    send.st
        .wallet_mut()
        .db_mut()
        .delete_account(account)
        .unwrap();
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_suspensions()
            .unwrap()
            .is_empty()
    );
    let jobs: i64 = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT COUNT(*) FROM ironwood_enhance_discovery_queue",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(jobs, 0);
    assert!(
        !send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM tx_retrieval_queue WHERE txid = ?1)",
                [txid.as_ref()],
                |row| row.get::<_, bool>(0)
            )
            .unwrap()
    );
    for mode in [EnhancementMode::PrivateIronwood, EnhancementMode::Standard] {
        use crate::testing::db::{test_clock, test_rng};
        let reopened = crate::WalletDb::for_path(
            send.st.wallet().data_file_path(),
            *send.st.network(),
            test_clock(),
            test_rng(),
        )
        .unwrap()
        .with_enhancement_mode(mode)
        .with_status_mode(zcash_client_backend::data_api::status::TransactionStatusMode::Public);
        assert!(
            !reopened
                .transaction_enhancement_work()
                .unwrap()
                .contains(&crate::testing::public_work(txid))
        );
        assert!(
            !reopened
                .transaction_status_work()
                .unwrap()
                .iter()
                .any(|work| work.txid() == txid)
        );
    }
}

#[test]
fn linking_another_funder_reactivates_the_existing_suspended_job() {
    let mut send = Send::with_second_funder(true, true);
    let (height, account_b) = send.second_funding.unwrap();
    let account = send
        .st
        .wallet()
        .db()
        .get_account(account_b)
        .unwrap()
        .unwrap();
    let key_b = account.ufvk().unwrap().orchard().unwrap();
    let key_a = OrchardPoolTester::test_account_fvk(&send.st);
    // B receives one output, retaining this transaction when A is deleted, but B's
    // funding note is not scanned until after the discovery job has been suspended.
    send.block.vtx[0].ironwood_actions[0] = encrypted_action(
        send.block.vtx[0].ironwood_actions[0]
            .nf()
            .unwrap()
            .to_bytes(),
        key_b.address_at(0u32, Scope::External),
        key_a.to_ovk(Scope::External),
        30_000,
    )
    .0;
    send.st
        .cache()
        .0
        .execute(
            "UPDATE compactblocks SET data = ?1 WHERE height = ?2",
            rusqlite::params![send.block.encode_to_vec(), u32::from(send.block.height())],
        )
        .unwrap();
    send.scan_send();
    send.scan_funding();
    let tx_ref = send.tx_ref();
    let account_a = send.st.test_account().unwrap().id();
    send.st
        .wallet_mut()
        .db_mut()
        .delete_account(account_a)
        .unwrap();
    assert_eq!(
        send.st.wallet().db().discovery_suspensions().unwrap(),
        vec![IronwoodEnhanceDiscoveryFailure {
            txid: send.block.vtx[0].txid(),
            reason: NoFundingAccounts,
        }]
    );
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );

    send.st.scan_cached_blocks(height, 1);
    assert_eq!(send.tx_ref(), tx_ref);
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_suspensions()
            .unwrap()
            .is_empty()
    );
    send.rebuild();
    let outgoing = send
        .requests()
        .into_iter()
        .find(|r| r.request_id().output_index() == 1)
        .unwrap();
    let pending = send
        .st
        .wallet()
        .db()
        .pending_outgoing(outgoing.position())
        .unwrap()
        .unwrap();
    assert_eq!(pending.account_ids, vec![account_b]);
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
        EnhancePirStoreResult::Stored
    );
}

#[test]
fn restoring_a_funding_key_and_rescanning_reactivates_suspended_discovery() {
    use zcash_client_backend::data_api::AccountPurpose;
    for funding_b_first in [false, true] {
        let mut send = shared_and_independent_jobs();
        let account_a = send.st.test_account().unwrap().id();
        let key = send
            .st
            .wallet()
            .db()
            .get_account(account_a)
            .unwrap()
            .unwrap()
            .ufvk()
            .unwrap()
            .clone();
        let birthday = send.st.test_account().unwrap().birthday().clone();
        send.st
            .wallet_mut()
            .db_mut()
            .delete_account(account_a)
            .unwrap();
        assert_eq!(
            send.st.wallet().db().discovery_suspensions().unwrap().len(),
            1
        );
        send.st
            .wallet_mut()
            .db_mut()
            .import_account_ufvk(
                "restored A",
                &key,
                &birthday,
                AccountPurpose::Spending { derivation: None },
                None,
            )
            .unwrap();
        // Import rewinds while retaining routing and reconstruction for both sends. Exercise both
        // direct scan-time recovery and rediscovery of this retained link, alongside A's
        // newly restored funding note. A's funding always arrives after the send block.
        if funding_b_first {
            send.st
                .scan_cached_blocks(send.second_funding.unwrap().0, 1);
        }
        send.scan_send();
        send.scan_funding();
        if !funding_b_first {
            send.st
                .scan_cached_blocks(send.second_funding.unwrap().0, 1);
        }
        assert!(
            send.st
                .wallet()
                .db()
                .discovery_suspensions()
                .unwrap()
                .is_empty()
        );
        let request = send.discovery();
        let txid: [u8; 32] = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT t.txid FROM ironwood_enhance_discovery_queue q
         JOIN transactions t ON t.id_tx = q.transaction_id WHERE t.txid = ?1",
                [&send.block.vtx[0].txid],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(txid.as_slice(), send.block.vtx[0].txid);
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &send.block)
                .unwrap(),
            Rebuilt(2)
        );
        assert!(
            send.st
                .wallet()
                .db()
                .discovery_requests()
                .unwrap()
                .is_empty()
        );
        let outgoing = send
            .st
            .wallet()
            .db()
            .query_requests()
            .unwrap()
            .into_iter()
            .find(|r| r.request_id().txid() == send.block.vtx[1].txid())
            .unwrap();
        assert_eq!(
            apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
            EnhancePirStoreResult::Stored
        );
    }
}

#[test]
fn suspension_failure_rolls_back_account_deletion() {
    let mut send = shared_and_independent_jobs();
    let account_a = send.st.test_account().unwrap().id();
    send.st.wallet().conn().execute_batch("CREATE TRIGGER fail_suspend BEFORE UPDATE OF suspended ON ironwood_enhance_discovery_queue
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END;").unwrap();
    assert!(
        send.st
            .wallet_mut()
            .db_mut()
            .delete_account(account_a)
            .is_err()
    );
    assert!(
        send.st
            .wallet()
            .db()
            .get_account(account_a)
            .unwrap()
            .is_some()
    );
    assert_eq!(
        super::super::discovery::funding(send.st.wallet().conn(), send.tx_ref())
            .unwrap()
            .len(),
        1
    );
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_suspensions()
            .unwrap()
            .is_empty()
    );
}

#[test]
fn retro_link_and_discovery_enqueue_roll_back_together() {
    let mut send = Send::new(true);
    send.scan_send();
    let change = send.requests()[0];
    finish_incoming(&mut send.st, change);
    send.st
        .wallet()
        .conn()
        .execute_batch(
            "CREATE TRIGGER fail_discovery_insert BEFORE INSERT ON ironwood_enhance_discovery_queue
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END;",
        )
        .unwrap();
    assert!(
        send.st
            .try_scan_cached_blocks(send.funding_height, 1)
            .is_err()
    );
    assert!(!send.queued());
    let links: i64 = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT COUNT(*) FROM ironwood_received_note_spends WHERE transaction_id = ?1",
            [send.tx_ref().0],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(links, 0);
    send.st
        .wallet()
        .conn()
        .execute_batch("DROP TRIGGER fail_discovery_insert")
        .unwrap();
    send.scan_funding();
    send.rebuild();
}

#[test]
fn mixed_compact_shape_discovered_without_change_uses_lwd() {
    use zcash_client_backend::proto::compact_formats::{CompactSaplingSpend, CompactTxIn, TxOut};
    for pool in 0..4 {
        let mut send = Send::new(false);
        let tx = &mut send.block.vtx[0];
        match pool {
            0 => tx.vin.push(CompactTxIn {
                prevout_txid: vec![8; 32],
                prevout_index: 0,
            }),
            1 => tx.vout.push(TxOut::default()),
            2 => tx.spends.push(CompactSaplingSpend { nf: vec![8; 32] }),
            _ => {
                tx.actions.push(tx.ironwood_actions[0].clone());
                send.block
                    .chain_metadata
                    .as_mut()
                    .unwrap()
                    .orchard_commitment_tree_size += 1;
            }
        }
        send.st
            .cache()
            .0
            .execute(
                "UPDATE compactblocks SET data = ?1 WHERE height = ?2",
                rusqlite::params![send.block.encode_to_vec(), u32::from(send.block.height())],
            )
            .unwrap();
        send.scan_send();
        send.scan_funding();
        send.rebuild();
        let request = EnhancePirRequest::new(
            1.into(),
            IronwoodEnhanceRequestId::new(send.block.vtx[0].txid(), 0),
        );
        assert!(visible(&send.st, request));
        assert!(send.requests().is_empty());
        assert!(!is_protected(send.st.wallet().conn(), request.request_id().txid()).unwrap());
    }
}

#[test]
fn retro_link_reopens_retired_enhancement_and_recovers_recipient_privately() {
    for memo_first in [true, false] {
        let mut send = Send::new(true);
        send.scan_send();
        let change = send.requests()[0];
        assert_eq!(send.requests().len(), 1);
        if memo_first {
            finish_incoming(&mut send.st, change);
            assert!(
                !send.queued(),
                "reproduce retirement before the spend is linkable"
            );
        }
        send.scan_funding();
        send.discovery();
        assert!(
            send.queued(),
            "retro-link must restore already-retired intent"
        );
        assert!(!visible(&send.st, change));
        if !memo_first {
            finish_incoming(&mut send.st, change);
        }
        assert!(
            send.queued(),
            "discovery blocks retirement even with no PIR requests"
        );
        assert!(send.requests().is_empty());

        // Mode changes and process restarts must not lose the obligation.
        use crate::testing::db::{test_clock, test_rng};
        let mut reopened = crate::WalletDb::for_path(
            send.st.wallet().data_file_path(),
            *send.st.network(),
            test_clock(),
            test_rng(),
        )
        .unwrap()
        .with_enhancement_mode(
            zcash_client_backend::data_api::enhance_pir::EnhancementMode::Standard,
        );
        assert_eq!(
            reopened.discovery_requests().unwrap(),
            vec![send.discovery()]
        );
        assert!(
            reopened
                .transaction_enhancement_work()
                .unwrap()
                .contains(&crate::testing::public_work(change.request_id().txid()))
        );
        reopened.set_enhancement_mode(EnhancementMode::PrivateIronwood);
        assert!(
            !reopened
                .transaction_enhancement_work()
                .unwrap()
                .contains(&crate::testing::public_work(change.request_id().txid()))
        );

        send.rebuild();
        let outgoing = send.requests()[0];
        assert_eq!(outgoing.request_id().output_index(), 1);
        assert_eq!(u64::from(outgoing.position()), 2);
        let account = send.st.test_account().unwrap().id();
        assert_eq!(
            send.st
                .wallet()
                .db()
                .pending_outgoing(outgoing.position())
                .unwrap()
                .unwrap()
                .account_ids,
            vec![account]
        );
        assert_eq!(
            apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
            EnhancePirStoreResult::Stored
        );
        assert!(!send.queued());
        assert!(send.requests().is_empty());
        let value: u64 = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT value FROM sent_notes WHERE transaction_id = ?1 AND output_index = 1",
                [send.tx_ref().0],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(value, 20_000);
        let stored_address: String = send
            .st
            .wallet()
            .conn()
            .query_row(
                "SELECT to_address FROM sent_notes WHERE transaction_id = ?1 AND output_index = 1",
                [send.tx_ref().0],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(
            stored_address,
            Receiver::Orchard(send.recipient)
                .to_zcash_address(send.st.network().network_type())
                .to_string()
        );
        assert!(is_protected(send.st.wallet().conn(), change.request_id().txid()).unwrap());
        // A replay with the now-spent nullifier omitted must reopen discovery, not lose data.
        send.scan_send();
        send.rebuild();
        assert!(!send.queued());
    }
}

#[test]
fn retro_link_discovers_a_send_without_any_received_output() {
    let mut send = Send::new(false);
    send.scan_send();
    assert!(send.requests().is_empty());
    send.scan_funding();
    assert!(send.queued());
    send.rebuild();
    assert_eq!(send.requests().len(), 1);
    let outgoing = send.requests()[0];
    assert!(!visible(&send.st, outgoing));
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    assert!(!send.queued());
}

#[test]
fn funding_first_stays_private_without_discovery_and_repeated_funding_scan_is_inert() {
    let mut send = Send::new(true);
    send.scan_funding();
    send.scan_send();
    assert_eq!(send.requests().len(), 2);
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    send.scan_funding();
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    for request in send.requests() {
        assert!(!visible(&send.st, request));
    }
}

#[test]
fn malformed_or_stale_discovery_never_falls_back_or_clears_work() {
    let mut send = Send::new(true);
    send.scan_send();
    send.scan_funding();
    let request = send.discovery();
    for kind in 0..9 {
        let mut bad = send.block.clone();
        match kind {
            0 => bad.hash = vec![8; 32],
            1 => bad.height = u64::MAX,
            2 => bad.chain_metadata = None,
            3 => bad.vtx.clear(),
            4 => bad.vtx[0].ironwood_actions[1].ephemeral_key.clear(),
            5 => bad.vtx[0].index += 1,
            6 => bad.vtx[0].txid = vec![8; 32],
            7 => bad.vtx[0].ironwood_actions[0].nullifier = vec![8; 32],
            _ => bad.vtx[0].ironwood_actions.pop().map(|_| ()).unwrap(),
        }
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &bad)
                .unwrap(),
            match kind {
                4 | 5 | 7 => Incomplete {
                    rebuilt: 0,
                    unresolved: vec![IronwoodEnhanceDiscoveryFailure {
                        txid: send.block.vtx[0].txid(),
                        reason: ContextMismatch,
                    }]
                },
                6 => Incomplete {
                    rebuilt: 0,
                    unresolved: vec![IronwoodEnhanceDiscoveryFailure {
                        txid: send.block.vtx[0].txid(),
                        reason: TransactionMissing,
                    }]
                },
                _ => Rejected,
            },
            "case {kind}"
        );
        assert_eq!(send.discovery(), request);
        assert!(send.queued());
    }
    let stale = IronwoodEnhanceDiscoveryRequest {
        block_hash: BlockHash([8; 32]),
        ..request
    };
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(stale, &send.block)
            .unwrap(),
        AlreadyResolved
    );
    send.rebuild();
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(request, &send.block)
            .unwrap(),
        AlreadyResolved
    );
}

#[test]
fn discovery_commit_is_atomic_and_mixed_routing_is_sticky() {
    let mut send = Send::new(true);
    send.scan_send();
    send.scan_funding();
    let request = send.discovery();
    send.st
        .wallet()
        .conn()
        .execute_batch(
            "CREATE TRIGGER fail_discovery_delete BEFORE DELETE ON ironwood_enhance_discovery_queue
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END;",
        )
        .unwrap();
    assert!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(request, &send.block)
            .is_err()
    );
    assert_eq!(
        send.requests().len(),
        1,
        "outgoing insert rolls back with job deletion"
    );
    assert_eq!(send.discovery(), request);
    send.st
        .wallet()
        .conn()
        .execute_batch("DROP TRIGGER fail_discovery_delete")
        .unwrap();
    send.rebuild();
    let outgoing = send
        .requests()
        .into_iter()
        .find(|r| r.request_id().output_index() == 1)
        .unwrap();
    let mixed = EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: *send.record.enc_ciphertext_suffix(),
        cv_net: *send.record.cv_net(),
        out_ciphertext: *send.record.out_ciphertext(),
        has_transparent_inputs: true,
        has_transparent_outputs: false,
        metadata: zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
            0,
            Some(0),
        )
        .unwrap(),
    });
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), outgoing, &mixed).unwrap(),
        EnhancePirStoreResult::LwdRequired
    );
    send.scan_funding();
    send.scan_send();
    assert!(
        send.st
            .wallet()
            .db()
            .discovery_requests()
            .unwrap()
            .is_empty()
    );
    assert!(visible(&send.st, outgoing));
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(request, &send.block)
            .unwrap(),
        AlreadyResolved
    );
}

#[test]
fn rewind_and_full_data_clear_discovery() {
    for full_data in [false, true] {
        let mut send = Send::new(true);
        send.scan_send();
        send.scan_funding();
        let request = send.discovery();
        if full_data {
            send.st
                .wallet()
                .conn()
                .execute(
                    "UPDATE transactions SET raw = X'00' WHERE id_tx = ?1",
                    [send.tx_ref().0],
                )
                .unwrap();
            clear_work(send.st.wallet().conn(), send.tx_ref()).unwrap();
            super::super::discovery::queue(send.st.wallet().conn(), send.tx_ref()).unwrap();
        } else {
            send.st
                .wallet_mut()
                .db_mut()
                .truncate_to_height(send.funding_height)
                .unwrap();
        }
        assert!(
            send.st
                .wallet()
                .db()
                .discovery_requests()
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            send.st
                .wallet_mut()
                .db_mut()
                .rebuild_ironwood_enhancement(request, &send.block)
                .unwrap(),
            AlreadyResolved
        );
    }
}

#[test]
fn rewind_preserves_discovery_for_existing_spend_links() {
    for change in [false, true] {
        for funding_first in [false, true] {
            let mut send = Send::new(change);
            send.scan_funding();
            send.scan_send();
            let txid = send.block.vtx[0].txid();
            let tx_ref = send.tx_ref();
            // Rewind both funding and spending blocks, retaining their spend link.
            send.st
                .wallet_mut()
                .db_mut()
                .truncate_to_height(send.funding_height - 1)
                .unwrap();
            assert!(send.requests().is_empty());
            assert!(
                send.st
                    .wallet()
                    .db()
                    .discovery_requests()
                    .unwrap()
                    .is_empty()
            );
            assert!(is_protected(send.st.wallet().conn(), txid).unwrap());
            assert!(
                !send
                    .st
                    .wallet()
                    .db()
                    .transaction_enhancement_work()
                    .unwrap()
                    .contains(&crate::testing::public_work(txid))
            );
            assert!(send.st.wallet().conn().query_row(
                "SELECT EXISTS(SELECT 1 FROM ironwood_enhance_discovery_queue WHERE transaction_id = ?1)",
                [tx_ref.0], |row| row.get::<_, bool>(0)).unwrap());
            if funding_first {
                send.scan_funding();
                send.scan_send();
            } else {
                send.scan_send();
                send.scan_funding();
            }
            send.rebuild();
            let outgoing = send
                .requests()
                .into_iter()
                .find(|r| r.request_id().output_index() == u32::from(change))
                .unwrap();
            assert_eq!(
                apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
                EnhancePirStoreResult::Stored
            );
            assert!(is_protected(send.st.wallet().conn(), txid).unwrap());
            send.scan_funding();
            assert!(
                send.st
                    .wallet()
                    .db()
                    .discovery_requests()
                    .unwrap()
                    .is_empty()
            );
        }
    }
}

#[test]
fn account_deletion_preserves_shared_intent_and_rolls_back_cleanup() {
    let mut send = shared_and_independent_jobs();
    let account = send.st.test_account().unwrap().id();
    let funding: (i64, Vec<u8>) = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT id_tx, txid FROM transactions WHERE mined_height = ?1",
            [u32::from(send.funding_height)],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    let shared_txid = send.block.vtx[0].txid();
    send.st
        .wallet()
        .conn()
        .execute(
            "UPDATE tx_retrieval_queue SET dependent_transaction_id = ?1 WHERE txid = ?2",
            rusqlite::params![funding.0, shared_txid.as_ref()],
        )
        .unwrap();
    send.st
        .wallet()
        .conn()
        .execute_batch(
            "CREATE TRIGGER fail_transaction_delete BEFORE DELETE ON transactions
         BEGIN SELECT RAISE(ABORT, 'injected deletion failure'); END;",
        )
        .unwrap();
    assert!(
        send.st
            .wallet_mut()
            .db_mut()
            .delete_account(account)
            .is_err()
    );
    assert!(
        send.st
            .wallet()
            .conn()
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM tx_retrieval_queue WHERE txid = ?1)",
                [&funding.1],
                |row| row.get::<_, bool>(0)
            )
            .unwrap()
    );
    assert_eq!(
        send.st
            .wallet()
            .conn()
            .query_row(
                "SELECT dependent_transaction_id FROM tx_retrieval_queue WHERE txid = ?1",
                [shared_txid.as_ref()],
                |row| row.get::<_, i64>(0)
            )
            .unwrap(),
        funding.0
    );
    send.st
        .wallet()
        .conn()
        .execute_batch("DROP TRIGGER fail_transaction_delete")
        .unwrap();
    send.st
        .wallet_mut()
        .db_mut()
        .delete_account(account)
        .unwrap();
    let dependency: Option<i64> = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT dependent_transaction_id FROM tx_retrieval_queue WHERE txid = ?1",
            [shared_txid.as_ref()],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(dependency, None);
    assert!(is_protected(send.st.wallet().conn(), shared_txid).unwrap());
    assert!(
        !send
            .st
            .wallet()
            .db()
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(shared_txid))
    );
    send.st
        .wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::Standard);
    assert!(
        send.st
            .wallet()
            .db()
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(shared_txid))
    );
}

#[test]
fn rewind_of_completed_private_send_preserves_completion_after_reconstruction() {
    for change in [false, true] {
        let mut send = Send::new(change);
        send.scan_funding();
        send.scan_send();
        if change {
            let incoming = send
                .requests()
                .into_iter()
                .find(|r| r.request_id().output_index() == 0)
                .unwrap();
            finish_incoming(&mut send.st, incoming);
        }
        let outgoing = send
            .requests()
            .into_iter()
            .find(|r| r.request_id().output_index() == u32::from(change))
            .unwrap();
        assert_eq!(
            apply_record(send.st.wallet_mut().db_mut(), outgoing, &send.record).unwrap(),
            EnhancePirStoreResult::Stored
        );
        assert!(!send.queued());
        send.st
            .wallet_mut()
            .db_mut()
            .truncate_to_height(send.funding_height - 1)
            .unwrap();
        assert!(!send.queued(), "rewinding must not create ordinary intent");
        send.scan_send();
        send.scan_funding();
        send.rebuild();
        assert!(send.requests().is_empty());
        assert!(!send.queued());
        assert!(is_protected(send.st.wallet().conn(), send.block.vtx[0].txid()).unwrap());
        send.scan_funding();
        assert!(
            send.st
                .wallet()
                .db()
                .discovery_requests()
                .unwrap()
                .is_empty()
        );
    }
}

#[test]
fn rewind_failure_rolls_back_discovery_and_position_cleanup() {
    let mut send = Send::new(false);
    send.scan_funding();
    send.scan_send();
    let before = send.st.wallet().db().private_work().unwrap();
    let txid = send.block.vtx[0].txid();
    send.st
        .wallet()
        .conn()
        .execute_batch(
            "CREATE TRIGGER fail_unmine BEFORE UPDATE OF mined_height ON transactions
         WHEN NEW.mined_height IS NULL
         BEGIN SELECT RAISE(ABORT, 'injected rewind failure'); END;",
        )
        .unwrap();
    assert!(
        send.st
            .wallet_mut()
            .db_mut()
            .truncate_to_height(send.funding_height - 1)
            .is_err()
    );
    assert_eq!(send.st.wallet().db().private_work().unwrap(), before);
    assert!(is_protected(send.st.wallet().conn(), txid).unwrap());
    assert!(send.queued());
    assert!(
        !send
            .st
            .wallet()
            .db()
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(txid))
    );
}

#[test]
fn metadata_backfill_rediscovers_completed_outgoing_only_history() {
    let mut send = Send::new(false);
    send.scan_funding();
    send.scan_send();
    let request = send.requests()[0];
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), request, &send.record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    let tx_ref = send.tx_ref();
    send.st
        .wallet()
        .conn()
        .execute(
            "UPDATE transactions SET fee = NULL, expiry_height = NULL WHERE id_tx = ?",
            [tx_ref.0],
        )
        .unwrap();
    send.st
        .wallet()
        .conn()
        .execute(
            "INSERT INTO ironwood_enhance_metadata_queue (transaction_id) VALUES (?)",
            [tx_ref.0],
        )
        .unwrap();
    let discovery = send.discovery();
    assert_eq!(
        send.st
            .wallet_mut()
            .db_mut()
            .rebuild_ironwood_enhancement(discovery, &send.block)
            .unwrap(),
        Rebuilt(1)
    );
    assert_eq!(send.requests(), vec![request]);
    assert_eq!(
        apply_record(send.st.wallet_mut().db_mut(), request, &send.record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    assert!(send.requests().is_empty());
    let values: (u64, Option<u32>, Option<Vec<u8>>) = send
        .st
        .wallet()
        .conn()
        .query_row(
            "SELECT fee, expiry_height, raw FROM transactions WHERE id_tx = ?",
            [tx_ref.0],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .unwrap();
    assert_eq!(values, (0, None, None));
}

/// Change only unauthenticated expiry, keeping the encrypted action valid.
fn with_expiry(record: &EnhanceRecord, expiry: u32) -> EnhanceRecord {
    let mut bytes = *record.as_bytes();
    bytes[641..645].copy_from_slice(&expiry.to_le_bytes());
    EnhanceRecord::from_bytes(bytes).unwrap()
}

#[test]
fn pir_expiry_does_not_pin_notes_across_reorg_or_reopen_completed_work() {
    for expiry in [0, 1, 499_999_999] {
        let mut send = Send::new(false);
        send.scan_funding();
        send.scan_send();
        let account = send.st.test_account().unwrap().id();
        let request = send.requests()[0];
        let record = with_expiry(&send.record, expiry);
        assert_eq!(
            apply_record(send.st.wallet_mut().db_mut(), request, &record).unwrap(),
            EnhancePirStoreResult::Stored
        );
        assert_eq!(
            stored_metadata(&send.st, request),
            StoredIronwoodMetadata {
                fee_zatoshis: Some(0),
                expiry_height: None,
            }
        );
        assert_eq!(
            send.st
                .wallet()
                .conn()
                .query_row(
                    "SELECT expiry_height FROM v_transactions WHERE txid = ?",
                    [request.request_id().txid().as_ref()],
                    |row| row.get::<_, Option<u32>>(0),
                )
                .unwrap(),
            Some(expiry),
        );
        assert_eq!(
            send.st
                .get_spendable_balance(account, ConfirmationsPolicy::MIN),
            Zatoshis::ZERO
        );
        assert!(send.requests().is_empty());
        send.scan_send();
        assert!(
            send.requests().is_empty(),
            "unknown expiry must not reopen enhancement"
        );
        assert!(!send.queued());

        send.st
            .wallet_mut()
            .db_mut()
            .truncate_to_height(send.funding_height)
            .unwrap();
        for _ in 0..=DEFAULT_TX_EXPIRY_DELTA {
            let (height, _) = send.st.generate_empty_block();
            send.st.scan_cached_blocks(height, 1);
        }
        assert_eq!(
            send.st
                .get_spendable_balance(account, ConfirmationsPolicy::MIN),
            Zatoshis::const_from_u64(50_000),
            "unmined spend must age out regardless of PIR expiry"
        );
    }
}

#[test]
fn rediscovery_is_routed_privately_and_can_change_the_next_route() {
    let mut send = Send::new(true);
    send.scan_send();
    let change = send.requests()[0];
    finish_incoming(&mut send.st, change);
    send.scan_funding();
    let job = send.discovery();
    let txid = change.request_id().txid();
    let queries_for = |private: &[EnhancePirWork]| {
        private
            .iter()
            .filter(|work| {
                matches!(work, EnhancePirWork::Query(request) if request.request_id().txid() == txid)
            })
            .count()
    };

    let (public, private) = routed(&send.st);
    assert!(
        !public.contains(&txid),
        "pending rediscovery never falls back"
    );
    assert!(private.contains(&EnhancePirWork::Rediscover(job)));
    assert_eq!(queries_for(&private), 0);

    send.st
        .wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::Standard);
    let (public, private) = routed(&send.st);
    assert!(public.contains(&txid));
    assert!(private.is_empty());
    send.st
        .wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);

    // Reconstruction replaces the discovery job with a private outgoing query.
    send.rebuild();
    let (public, private) = routed(&send.st);
    assert!(!public.contains(&txid));
    assert!(!private.contains(&EnhancePirWork::Rediscover(job)));
    assert_eq!(queries_for(&private), 1);
}
