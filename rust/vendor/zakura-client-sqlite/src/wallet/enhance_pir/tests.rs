use super::*;
use crate::testing::{
    BlockCache,
    db::{TestDb, TestDbFactory},
};
use zcash_client_backend::data_api::enhance_pir::EnhanceRecord;
use zcash_client_backend::data_api::enhance_pir::EnhanceRecordParts;
use zcash_client_backend::data_api::{
    TransactionStatus, WalletRead, WalletWrite,
    enhance_pir::{EnhancePirRead, EnhancePirWrite, EnhancementMode},
    testing::{
        AddressType, IronwoodFvk, TestBuilder, TestState, orchard::OrchardPoolTester,
        pool::ShieldedPoolTester,
    },
};
use zcash_client_backend::wallet::IronwoodEnhanceCandidate;
use zcash_primitives::block::BlockHash;
use zcash_protocol::{
    consensus::BlockHeight, local_consensus::LocalNetwork, memo::MemoBytes, value::Zatoshis,
};

type State = TestState<BlockCache, TestDb, LocalNetwork>;

fn fixture() -> (State, crate::TxRef, EnhancePirRequest) {
    fixture_with_factory(TestDbFactory::default())
}

fn fixture_with_factory(factory: TestDbFactory) -> (State, crate::TxRef, EnhancePirRequest) {
    fixture_from_state(state_with_factory(factory))
}

fn fixture_from_state(mut st: State) -> (State, crate::TxRef, EnhancePirRequest) {
    let fvk = IronwoodFvk(OrchardPoolTester::test_account_fvk(&st));
    let (height, _, _) = st.generate_next_block(
        &fvk,
        AddressType::DefaultExternal,
        Zatoshis::const_from_u64(10_000),
    );
    st.scan_cached_blocks(height, 1);
    let tx_ref = st
        .wallet()
        .conn()
        .query_row(
            "SELECT id_tx FROM transactions WHERE mined_height = ?1",
            [u32::from(height)],
            |row| row.get(0).map(crate::TxRef),
        )
        .unwrap();
    let requests = st.wallet().db().query_requests().unwrap();
    assert_eq!(
        requests.len(),
        1,
        "scanning queues work after storing the note"
    );
    let request = requests[0];
    assert!(
        st.wallet()
            .db()
            .pending_memo(request.position())
            .unwrap()
            .is_some()
    );
    (st, tx_ref, request)
}

fn unscanned_state_with_factory(factory: TestDbFactory) -> State {
    let activation = BlockHeight::from_u32(100_000);
    let network = LocalNetwork {
        nu6: Some(activation),
        nu6_1: Some(activation),
        nu6_2: Some(activation),
        nu6_3: Some(activation),
        ..TestBuilder::<(), ()>::DEFAULT_NETWORK
    };
    TestBuilder::new()
        .with_network(network)
        .with_data_store_factory(factory)
        .with_block_cache(BlockCache::new())
        .with_account_from_sapling_activation(BlockHash([0; 32]))
        .build()
}

fn state_with_factory(factory: TestDbFactory) -> State {
    let mut st = unscanned_state_with_factory(factory);
    // Establish a real retained checkpoint before the block the reorg test removes.
    let (empty_height, _) = st.generate_empty_block();
    st.scan_cached_blocks(empty_height, 1);
    st
}

mod discovery;

fn outgoing(st: &State, tx_ref: crate::TxRef, position: u64, index: usize) -> EnhancePirRequest {
    queue_transaction(
        st.wallet().conn(),
        tx_ref,
        &IronwoodEnhancementPlan::Eligible {
            outgoing: vec![IronwoodEnhanceCandidate::from_parts(
                position.into(),
                index,
                [1; 32],
                [2; 32],
                [3; 32],
                [4; 52],
                vec![st.test_account().unwrap().id()],
            )],
        },
    )
    .unwrap();
    requests(st.wallet().conn())
        .unwrap()
        .into_iter()
        .find(|r| u64::from(r.position()) == position)
        .unwrap()
}

fn wire_record(inputs: bool, outputs: bool) -> EnhanceRecord {
    let mut ciphertext = [0; 580];
    ciphertext[..52].copy_from_slice(&[4; 52]);
    EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: (ciphertext)[52..].try_into().unwrap(),
        cv_net: [5; 32],
        out_ciphertext: [6; 80],
        has_transparent_inputs: inputs,
        has_transparent_outputs: outputs,
        metadata: zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
            0,
            Some(0),
        )
        .unwrap(),
    })
}

fn visible(st: &State, request: EnhancePirRequest) -> bool {
    st.wallet()
        .db()
        .transaction_enhancement_work()
        .unwrap()
        .contains(&crate::testing::public_work(request.request_id().txid()))
}

fn validated(
    request: EnhancePirRequest,
    transparent: bool,
    incoming: bool,
    outgoing: IronwoodOutgoingResult<AccountUuid>,
) -> ValidatedIronwoodEnhancement<AccountUuid> {
    ValidatedIronwoodEnhancement::for_testing(
        request,
        transparent,
        incoming.then(MemoBytes::empty),
        outgoing,
        (!transparent).then(Default::default),
    )
}

fn stored_metadata(st: &State, request: EnhancePirRequest) -> StoredIronwoodMetadata {
    st.wallet()
        .conn()
        .query_row(
            "SELECT fee, expiry_height FROM transactions WHERE txid = ?",
            [request.request_id().txid().as_ref()],
            |r| {
                Ok(StoredIronwoodMetadata {
                    fee_zatoshis: r.get(0)?,
                    expiry_height: r.get(1)?,
                })
            },
        )
        .unwrap()
}

fn finish_incoming(st: &mut State, request: EnhancePirRequest) {
    let expected = stored_metadata(st, request);
    let enhancement = ValidatedIronwoodEnhancement::for_testing(
        request,
        false,
        Some(MemoBytes::empty()),
        IronwoodOutgoingResult::NotRequested,
        Some(expected),
    );
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_validated(enhancement)
            .unwrap(),
        EnhancePirStoreResult::Stored,
    );
}

#[test]
fn either_transparent_flag_routes_the_entire_transaction_and_is_sticky() {
    for (inputs, outputs) in [(true, false), (false, true), (true, true)] {
        let (mut st, tx_ref, incoming) = fixture();
        let outgoing = outgoing(&st, tx_ref, 99, 4);
        st.wallet_mut()
            .db_mut()
            .set_enhancement_mode(EnhancementMode::PrivateIronwood);
        assert!(!visible(&st, incoming));
        assert_eq!(
            apply_record(
                st.wallet_mut().db_mut(),
                outgoing,
                &wire_record(inputs, outputs)
            )
            .unwrap(),
            EnhancePirStoreResult::LwdRequired
        );
        assert!(visible(&st, incoming));
        assert!(requests(st.wallet().conn()).unwrap().is_empty());
        assert!(!is_protected(st.wallet().conn(), incoming.request_id().txid()).unwrap());

        // Late false flags and repeated compact scans cannot undo fallback.
        assert_eq!(
            apply_record(
                st.wallet_mut().db_mut(),
                outgoing,
                &wire_record(false, false)
            )
            .unwrap(),
            EnhancePirStoreResult::AlreadyResolved
        );
        queue_transaction(
            st.wallet().conn(),
            tx_ref,
            &IronwoodEnhancementPlan::Eligible { outgoing: vec![] },
        )
        .unwrap();
        assert!(requests(st.wallet().conn()).unwrap().is_empty());
        assert!(visible(&st, incoming));
    }
}

#[test]
fn incoming_authentication_precedes_shape_and_flags_are_not_authenticated() {
    use orchard::note_encryption::IronwoodNoteEncryption;
    use zcash_client_backend::data_api::enhance_pir::EnhanceRecord;

    let (mut st, _, request) = fixture();
    let pending = st
        .wallet()
        .db()
        .pending_memo(request.position())
        .unwrap()
        .unwrap();
    let encryptor = IronwoodNoteEncryption::new(None, pending.note, [7; 512]);
    let ciphertext = encryptor.encrypt_note_plaintext();
    let record = |bytes: [u8; 580]| {
        EnhanceRecord::from_parts(EnhanceRecordParts {
            enc_ciphertext_suffix: (bytes)[52..].try_into().unwrap(),
            cv_net: [0; 32],
            out_ciphertext: [0; 80],
            has_transparent_inputs: true,
            has_transparent_outputs: false,
            metadata: zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
                0,
                Some(0),
            )
            .unwrap(),
        })
    };
    let mut corrupt = ciphertext;
    corrupt[579] ^= 1;
    assert_eq!(
        apply_record(st.wallet_mut().db_mut(), request, &record(corrupt)).unwrap(),
        EnhancePirStoreResult::Rejected
    );
    assert!(is_protected(st.wallet().conn(), request.request_id().txid()).unwrap());
    assert_eq!(
        apply_record(st.wallet_mut().db_mut(), request, &record(ciphertext)).unwrap(),
        EnhancePirStoreResult::LwdRequired
    );
}

#[test]
fn stale_identity_cannot_change_memos_or_routing() {
    let (mut st, _, request) = fixture();
    for stale in [
        EnhancePirRequest::new(
            request.position(),
            IronwoodEnhanceRequestId::new(TxId::from_bytes([9; 32]), 0),
        ),
        EnhancePirRequest::new(
            request.position(),
            IronwoodEnhanceRequestId::new(request.request_id().txid(), 999),
        ),
        EnhancePirRequest::new(Position::from(999), request.request_id()),
    ] {
        assert_eq!(
            st.wallet_mut()
                .db_mut()
                .apply_validated(validated(
                    stale,
                    true,
                    true,
                    IronwoodOutgoingResult::NotRequested
                ))
                .unwrap(),
            EnhancePirStoreResult::AlreadyResolved
        );
    }
    assert_eq!(requests(st.wallet().conn()).unwrap(), vec![request]);
    assert!(is_protected(st.wallet().conn(), request.request_id().txid()).unwrap());
}

#[test]
fn non_recovery_suspends_work_without_completion_or_public_fallback() {
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);

    assert_eq!(
        apply_record(
            st.wallet_mut().db_mut(),
            outgoing,
            &wire_record(false, false)
        )
        .unwrap(),
        EnhancePirStoreResult::NotRecoverable
    );
    finish_incoming(&mut st, incoming);
    assert!(requests(st.wallet().conn()).unwrap().is_empty());
    assert!(!visible(&st, incoming));
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::Standard);
    assert!(
        visible(&st, incoming),
        "non-recovery is not proven dummy/completion"
    );
    outgoing_requeued(&st, tx_ref);
}

fn outgoing_requeued(st: &State, tx_ref: crate::TxRef) {
    let request = outgoing(st, tx_ref, 99, 4);
    assert!(requests(st.wallet().conn()).unwrap().contains(&request));
}

#[test]
fn completion_retires_only_enhancement_and_survives_replay() {
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    st.wallet()
        .conn()
        .execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (:txid, 0)",
            named_params![":txid": incoming.request_id().txid().as_ref()],
        )
        .unwrap();
    finish_incoming(&mut st, incoming);
    assert!(
        visible(&st, incoming),
        "partial completion retains fallback"
    );
    let fvk = OrchardPoolTester::test_account_fvk(&st);
    let from_account = st.test_account().unwrap().id();
    let expected = stored_metadata(&st, outgoing);
    let complete = || {
        ValidatedIronwoodEnhancement::for_testing(
            outgoing,
            false,
            None,
            IronwoodOutgoingResult::Recovered {
                from_account,
                recipient: fvk.address_at(3u32, Scope::External),
                value: Zatoshis::const_from_u64(123),
                memo: MemoBytes::empty(),
            },
            Some(expected),
        )
    };
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_validated(complete())
            .unwrap(),
        EnhancePirStoreResult::Stored
    );
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_validated(complete())
            .unwrap(),
        EnhancePirStoreResult::AlreadyResolved
    );
    for mode in [EnhancementMode::Standard, EnhancementMode::PrivateIronwood] {
        st.wallet_mut().db_mut().set_enhancement_mode(mode);
        assert!(!visible(&st, incoming));
    }
    let (value, memo): (u64, Vec<u8>) = st
        .wallet()
        .conn()
        .query_row(
            "SELECT value, memo FROM sent_notes WHERE transaction_id = :tx AND output_index = 4",
            named_params![":tx": tx_ref.0],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!((value, memo), (123, vec![0xf6]));
    let statuses: i64 = st
        .wallet()
        .conn()
        .query_row(
            "SELECT COUNT(*) FROM tx_retrieval_queue WHERE query_type = 0",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(statuses, 1);
    queue_transaction(
        st.wallet().conn(),
        tx_ref,
        &IronwoodEnhancementPlan::Eligible {
            outgoing: vec![IronwoodEnhanceCandidate::from_parts(
                99.into(),
                4,
                [1; 32],
                [2; 32],
                [3; 32],
                [4; 52],
                vec![from_account],
            )],
        },
    )
    .unwrap();
    assert!(requests(st.wallet().conn()).unwrap().is_empty());
    assert!(!visible(&st, incoming));
}

#[test]
fn atomic_write_rolls_back_memo_and_routing_on_queue_failure() {
    for transparent in [false, true] {
        let (mut st, tx_ref, incoming) = fixture();
        let _outgoing = outgoing(
            &st,
            tx_ref,
            u64::from(incoming.position()),
            incoming.request_id().output_index() as usize,
        );
        // The same action has incoming and outgoing work. Fail after its first
        // mutation: neither a stored memo nor a routing change may survive.
        st.wallet().conn().execute_batch(
            "CREATE TRIGGER fail_outgoing_update BEFORE UPDATE ON ironwood_enhance_outgoing_queue
             BEGIN SELECT RAISE(ABORT, 'injected failure'); END;
             CREATE TRIGGER fail_outgoing_delete BEFORE DELETE ON ironwood_enhance_outgoing_queue
             BEGIN SELECT RAISE(ABORT, 'injected failure'); END;"
        ).unwrap();
        assert!(
            st.wallet_mut()
                .db_mut()
                .apply_validated(validated(
                    incoming,
                    transparent,
                    true,
                    IronwoodOutgoingResult::NotRecoverable
                ))
                .is_err()
        );
        assert!(
            st.wallet()
                .db()
                .pending_memo(incoming.position())
                .unwrap()
                .is_some()
        );
        assert!(
            st.wallet()
                .db()
                .pending_outgoing(incoming.position())
                .unwrap()
                .is_some()
        );
        assert!(is_protected(st.wallet().conn(), incoming.request_id().txid()).unwrap());
    }
}

#[test]
fn full_data_supersedes_inflight_work() {
    let (mut st, tx_ref, request) = fixture();
    st.wallet()
        .conn()
        .execute(
            "UPDATE transactions SET raw = X'00' WHERE id_tx = :tx",
            named_params![":tx": tx_ref.0],
        )
        .unwrap();
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_validated(validated(
                request,
                true,
                true,
                IronwoodOutgoingResult::NotRequested
            ))
            .unwrap(),
        EnhancePirStoreResult::AlreadyResolved
    );
    assert!(requests(st.wallet().conn()).unwrap().is_empty());
    clear_work(st.wallet().conn(), tx_ref).unwrap();
    assert!(
        pending(
            st.wallet().conn(),
            &TestBuilder::<(), ()>::DEFAULT_NETWORK,
            request.position()
        )
        .unwrap()
        .is_none()
    );
}

#[test]
fn explicit_mixed_scan_discards_all_work_but_keeps_recovered_data() {
    let (mut st, tx_ref, request) = fixture();
    let _outgoing = outgoing(&st, tx_ref, 99, 4);
    finish_incoming(&mut st, request);
    queue_transaction(
        st.wallet().conn(),
        tx_ref,
        &IronwoodEnhancementPlan::Ineligible,
    )
    .unwrap();
    assert!(visible(&st, request));
    assert!(requests(st.wallet().conn()).unwrap().is_empty());
    let memo: Vec<u8> = st
        .wallet()
        .conn()
        .query_row(
            "SELECT memo FROM ironwood_received_notes WHERE transaction_id = :tx",
            named_params![":tx": tx_ref.0],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(memo, vec![0xf6]);
    queue_transaction(
        st.wallet().conn(),
        tx_ref,
        &IronwoodEnhancementPlan::Eligible { outgoing: vec![] },
    )
    .unwrap();
    assert!(!is_protected(st.wallet().conn(), request.request_id().txid()).unwrap());
}

#[test]
fn reorg_prunes_positions_but_retains_protection_and_lwd_decisions() {
    use crate::testing::db::{test_clock, test_rng};
    for mixed in [false, true] {
        let (mut st, tx_ref, request) = fixture_with_factory(TestDbFactory::file_backed());
        if mixed {
            require_lwd(st.wallet().conn(), tx_ref).unwrap();
        }
        let height: u32 = st
            .wallet()
            .conn()
            .query_row(
                "SELECT mined_height FROM transactions WHERE id_tx = :tx",
                named_params![":tx": tx_ref.0],
                |row| row.get(0),
            )
            .unwrap();
        st.wallet_mut()
            .db_mut()
            .truncate_to_height(BlockHeight::from_u32(height - 1))
            .unwrap();
        assert!(requests(st.wallet().conn()).unwrap().is_empty());
        let route: Option<i64> = st
            .wallet()
            .conn()
            .query_row(
                "SELECT route FROM ironwood_enhance_routing WHERE transaction_id = :tx",
                named_params![":tx": tx_ref.0],
                |row| row.get(0),
            )
            .optional()
            .unwrap();
        assert_eq!(
            route,
            Some(if mixed {
                LWD_REQUIRED
            } else {
                PRIVATE_PROTECTED
            })
        );
        for mode in [EnhancementMode::PrivateIronwood, EnhancementMode::Standard] {
            st.wallet_mut().db_mut().set_enhancement_mode(mode);
            let expected = mixed || mode == EnhancementMode::Standard;
            assert_eq!(visible(&st, request), expected);
            st.wallet_mut()
                .db_mut()
                .transactionally(|db| {
                    assert_eq!(
                        db.transaction_enhancement_work()?
                            .contains(&crate::testing::public_work(request.request_id().txid())),
                        expected
                    );
                    Ok::<_, SqliteClientError>(())
                })
                .unwrap();
            let reopened = crate::WalletDb::for_path(
                st.wallet().data_file_path(),
                *st.network(),
                test_clock(),
                test_rng(),
            )
            .unwrap()
            .with_enhancement_mode(mode);
            assert_eq!(
                reopened
                    .transaction_enhancement_work()
                    .unwrap()
                    .contains(&crate::testing::public_work(request.request_id().txid())),
                expected
            );
        }
        assert_eq!(
            st.wallet_mut()
                .db_mut()
                .apply_validated(validated(
                    request,
                    true,
                    true,
                    IronwoodOutgoingResult::NotRequested
                ))
                .unwrap(),
            EnhancePirStoreResult::AlreadyResolved
        );
    }
}

#[test]
fn reopening_uses_explicit_mode_and_preserves_routes() {
    use crate::testing::db::{test_clock, test_rng};
    let (mut st, tx_ref, request) = fixture_with_factory(TestDbFactory::file_backed());
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);
    let mut reopened = crate::WalletDb::for_path(
        st.wallet().data_file_path(),
        *st.network(),
        test_clock(),
        test_rng(),
    )
    .unwrap()
    .with_enhancement_mode(zcash_client_backend::data_api::enhance_pir::EnhancementMode::Standard);
    assert_eq!(reopened.query_requests().unwrap(), vec![request]);
    assert!(
        reopened
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(request.request_id().txid()))
    );
    reopened.set_enhancement_mode(EnhancementMode::PrivateIronwood);
    assert!(
        !reopened
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(request.request_id().txid()))
    );
    require_lwd(st.wallet().conn(), tx_ref).unwrap();
    assert!(reopened.query_requests().unwrap().is_empty());
    assert!(
        reopened
            .transaction_enhancement_work()
            .unwrap()
            .contains(&crate::testing::public_work(request.request_id().txid()))
    );
}

#[test]
fn status_response_preserves_lwd_fallback_enhancement() {
    let mined_height = BlockHeight::from_u32(100_001);
    for status in [
        TransactionStatus::Mined(mined_height),
        TransactionStatus::NotInMainChain,
        TransactionStatus::TxidNotRecognized,
    ] {
        let (mut st, tx_ref, request) = fixture();
        let txid = request.request_id().txid();
        st.wallet()
            .conn()
            .execute(
                "INSERT INTO tx_retrieval_queue (txid, query_type)
                 VALUES (:txid, :status)
                 ON CONFLICT (txid, query_type) DO NOTHING",
                named_params![
                    ":txid": txid.as_ref(),
                    ":status": TxQueryType::Status.code(),
                ],
            )
            .unwrap();
        require_lwd(st.wallet().conn(), tx_ref).unwrap();
        assert!(
            visible(&st, request),
            "LWD fallback restores Enhancement before the status response"
        );

        st.wallet_mut()
            .set_transaction_status(txid, status)
            .unwrap();

        assert!(
            visible(&st, request),
            "status {status:?} must not erase LWD fallback Enhancement while raw is missing"
        );
        assert!(!is_protected(st.wallet().conn(), txid).unwrap());
        let route: i64 = st
            .wallet()
            .conn()
            .query_row(
                "SELECT route FROM ironwood_enhance_routing WHERE transaction_id = :tx",
                named_params![":tx": tx_ref.0],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(route, LWD_REQUIRED);
        st.wallet_mut()
            .notify_transaction_enhancement_not_found(txid)
            .unwrap();
        assert!(
            visible(&st, request),
            "a missing payload cannot complete PIR-required fallback"
        );
    }
}

#[test]
fn status_and_payload_absence_preserve_private_recovery_work() {
    let (mut st, _, request) = fixture();
    let txid = request.request_id().txid();
    let work = st.wallet().db().query_requests().unwrap();
    for status in [
        TransactionStatus::Mined(BlockHeight::from_u32(100_001)),
        TransactionStatus::NotInMainChain,
        TransactionStatus::TxidNotRecognized,
    ] {
        st.wallet_mut()
            .set_transaction_status(txid, status)
            .unwrap();
        st.wallet_mut()
            .notify_transaction_enhancement_not_found(txid)
            .unwrap();
        assert_eq!(st.wallet().db().query_requests().unwrap(), work);
        assert!(is_protected(st.wallet().conn(), txid).unwrap());
    }
}

#[test]
fn status_response_preserves_ordinary_enhancement() {
    let (mut st, _, request) = fixture();
    let txid = request.request_id().txid();
    // Drop private routing so Enhancement is ordinary LWD intent, not PIR fallback.
    st.wallet()
        .conn()
        .execute("DELETE FROM ironwood_enhance_routing", [])
        .unwrap();
    st.wallet()
        .conn()
        .execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type)
             VALUES (:txid, :enhancement)
             ON CONFLICT (txid, query_type) DO NOTHING",
            named_params![
                ":txid": txid.as_ref(),
                ":enhancement": TxQueryType::Enhancement.code(),
            ],
        )
        .unwrap();
    assert!(visible(&st, request));

    st.wallet_mut()
        .set_transaction_status(txid, TransactionStatus::NotInMainChain)
        .unwrap();

    assert!(
        visible(&st, request),
        "status observation does not complete ordinary payload retrieval"
    );
}

#[test]
fn losing_a_funding_account_cannot_erase_incomplete_outgoing_work() {
    let (mut st, tx_ref, incoming) = fixture();
    let _outgoing = outgoing(&st, tx_ref, 99, 4);
    let tx = st.wallet_mut().conn_mut().transaction().unwrap();
    tx.execute("DELETE FROM ironwood_enhance_outgoing_accounts", [])
        .unwrap();
    crate::wallet::ironwood_hooks::suspend_orphaned_ironwood_enhancement(&tx).unwrap();
    tx.commit().unwrap();
    finish_incoming(&mut st, incoming);
    assert!(requests(st.wallet().conn()).unwrap().is_empty());
    assert!(visible(&st, incoming));
}

#[test]
fn a_response_validated_before_position_reassignment_is_still_rejected() {
    let (mut st, _, request) = fixture();
    let response = validated(request, true, true, IronwoodOutgoingResult::NotRequested);
    st.wallet()
        .conn()
        .execute(
            "UPDATE transactions SET txid = :replacement WHERE txid = :old",
            named_params![":replacement": &[8u8; 32], ":old": request.request_id().txid().as_ref()],
        )
        .unwrap();
    assert_eq!(
        st.wallet_mut().db_mut().apply_validated(response).unwrap(),
        EnhancePirStoreResult::AlreadyResolved
    );
    let replacement = requests(st.wallet().conn()).unwrap()[0];
    assert_eq!(replacement.position(), request.position());
    assert_ne!(replacement.request_id(), request.request_id());
    assert!(is_protected(st.wallet().conn(), replacement.request_id().txid()).unwrap());
}

#[test]
fn rescanning_removes_outgoing_jobs_now_covered_by_incoming_decryption() {
    let (st, tx_ref, request) = fixture();
    outgoing(
        &st,
        tx_ref,
        u64::from(request.position()),
        request.request_id().output_index() as usize,
    );
    assert!(
        pending_outgoing(st.wallet().conn(), request.position())
            .unwrap()
            .is_some()
    );
    queue_transaction(
        st.wallet().conn(),
        tx_ref,
        &IronwoodEnhancementPlan::Eligible { outgoing: vec![] },
    )
    .unwrap();
    assert!(
        pending_outgoing(st.wallet().conn(), request.position())
            .unwrap()
            .is_none()
    );
    assert_eq!(requests(st.wallet().conn()).unwrap(), vec![request]);
}

#[test]
fn a_mixed_spend_without_received_ironwood_notes_is_sticky() {
    use zcash_client_backend::wallet::WalletSpend;
    use zcash_protocol::consensus::TxIndex;
    let (st, _, original) = fixture();
    let txid = TxId::from_bytes([7; 32]);
    let tx_ref = st
        .wallet()
        .conn()
        .query_row(
            "INSERT INTO transactions (txid, mined_height, min_observed_height)
         VALUES (:txid, 100001, 100001) RETURNING id_tx",
            named_params![":txid": txid.as_ref()],
            |row| row.get(0).map(crate::TxRef),
        )
        .unwrap();
    let pending = st
        .wallet()
        .db()
        .pending_memo(original.position())
        .unwrap()
        .unwrap();
    let nf = orchard::note::Nullifier::from_bytes(&pending.note.rho().to_bytes()).unwrap();
    let scanned = WalletTx::new(
        txid,
        TxIndex::from(0u16),
        vec![],
        vec![],
        vec![],
        vec![],
        vec![],
        vec![WalletSpend::from_parts(
            0,
            nf,
            st.test_account().unwrap().id(),
        )],
        vec![],
    )
    .with_ironwood_enhancement_plan(IronwoodEnhancementPlan::Ineligible);
    queue_scanned(st.wallet().conn(), tx_ref, &scanned).unwrap();
    let provisional = scanned
        .with_ironwood_enhancement_plan(IronwoodEnhancementPlan::Eligible { outgoing: vec![] });
    queue_scanned(st.wallet().conn(), tx_ref, &provisional).unwrap();
    let route: i64 = st
        .wallet()
        .conn()
        .query_row(
            "SELECT route FROM ironwood_enhance_routing WHERE transaction_id = :tx",
            named_params![":tx": tx_ref.0],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(route, LWD_REQUIRED);
}

// Test projections keep individual queue assertions readable while exercising the single
// application read API. These helpers are not part of the production wallet interface.
fn requests(conn: &Connection) -> Result<Vec<EnhancePirRequest>, SqliteClientError> {
    Ok(work(conn)?
        .into_iter()
        .filter_map(|work| match work {
            EnhancePirWork::Query(request) => Some(request),
            _ => None,
        })
        .collect())
}

fn apply_record<Db: EnhancePirWrite>(
    db: &mut Db,
    request: EnhancePirRequest,
    record: &EnhanceRecord,
) -> Result<EnhancePirStoreResult, Db::Error> {
    db.apply_ironwood_enhance_record(request, record)
}

impl<C: std::borrow::Borrow<Connection>, P: Parameters, CL, R> crate::WalletDb<C, P, CL, R> {
    /// Mode-independent contents of the private queues, for storage assertions.
    fn private_work(&self) -> Result<Vec<EnhancePirWork>, SqliteClientError> {
        work(self.conn.borrow())
    }
    fn query_requests(&self) -> Result<Vec<EnhancePirRequest>, SqliteClientError> {
        Ok(self
            .private_work()?
            .into_iter()
            .filter_map(|work| match work {
                EnhancePirWork::Query(request) => Some(request),
                _ => None,
            })
            .collect())
    }
    fn discovery_requests(
        &self,
    ) -> Result<Vec<IronwoodEnhanceDiscoveryRequest>, SqliteClientError> {
        Ok(self
            .private_work()?
            .into_iter()
            .filter_map(|work| match work {
                EnhancePirWork::Rediscover(request) => Some(request),
                _ => None,
            })
            .collect())
    }
    fn discovery_suspensions(
        &self,
    ) -> Result<Vec<IronwoodEnhanceDiscoveryFailure>, SqliteClientError> {
        Ok(self
            .private_work()?
            .into_iter()
            .filter_map(|work| match work {
                EnhancePirWork::Suspended(EnhancePirSuspension::Discovery(failure)) => {
                    Some(failure)
                }
                _ => None,
            })
            .collect())
    }
    fn pending_memo(
        &self,
        position: Position,
    ) -> Result<Option<PendingIronwoodMemo<AccountUuid>>, SqliteClientError> {
        pending(self.conn.borrow(), &self.params, position)
    }
    fn pending_outgoing(
        &self,
        position: Position,
    ) -> Result<Option<PendingIronwoodOutgoing<AccountUuid>>, SqliteClientError> {
        pending_outgoing(self.conn.borrow(), position)
    }
}

impl<C: std::borrow::BorrowMut<Connection>, P: Parameters, CL: crate::util::Clock, R: rand::Rng>
    crate::WalletDb<C, P, CL, R>
{
    fn apply_validated(
        &mut self,
        enhancement: ValidatedIronwoodEnhancement<AccountUuid>,
    ) -> Result<EnhancePirStoreResult, SqliteClientError> {
        self.transactionally(|wdb| apply(wdb.conn.0, wdb.params, enhancement))
    }
}

#[test]
fn unified_work_preserves_both_suspension_kinds_across_reopen() {
    use crate::testing::db::{test_clock, test_rng};

    let (mut st, tx_ref, incoming) = fixture_with_factory(TestDbFactory::file_backed());
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_ironwood_enhance_record(outgoing, &wire_record(false, false))
            .unwrap(),
        EnhancePirStoreResult::NotRecoverable,
    );
    // This incoming-only fixture has no durable spending associations.
    super::discovery::queue(st.wallet().conn(), tx_ref).unwrap();
    let suspended = vec![
        EnhancePirWork::Suspended(EnhancePirSuspension::Discovery(
            IronwoodEnhanceDiscoveryFailure {
                txid: incoming.request_id().txid(),
                reason: IronwoodEnhanceDiscoveryFailureReason::NoFundingAccounts,
            },
        )),
        EnhancePirWork::Suspended(EnhancePirSuspension::OutgoingNotRecoverable(outgoing)),
    ];
    let expected = std::iter::once(EnhancePirWork::Query(incoming))
        .chain(suspended.iter().copied())
        .collect::<Vec<_>>();
    assert_eq!(st.wallet().db().private_work().unwrap(), expected);
    finish_incoming(&mut st, incoming);

    for mode in [EnhancementMode::PrivateIronwood, EnhancementMode::Standard] {
        let mut reopened = crate::WalletDb::for_path(
            st.wallet().data_file_path(),
            *st.network(),
            test_clock(),
            test_rng(),
        )
        .unwrap()
        .with_enhancement_mode(mode);
        assert_eq!(reopened.private_work().unwrap(), suspended);
        let exposes = |db: &crate::WalletDb<_, _, _, _>| {
            db.transaction_enhancement_work()
                .unwrap()
                .contains(&crate::testing::public_work(incoming.request_id().txid()))
        };
        assert_eq!(exposes(&reopened), mode == EnhancementMode::Standard);
        let inherited = reopened
            .transactionally(|db| -> Result<_, SqliteClientError> {
                Ok(db
                    .transaction_enhancement_work()?
                    .contains(&crate::testing::public_work(incoming.request_id().txid())))
            })
            .unwrap();
        assert_eq!(inherited, mode == EnhancementMode::Standard);
    }
}

#[test]
fn payload_enumeration_requires_mode_even_without_a_chain_tip() {
    use crate::testing::db::{test_clock, test_rng};
    let file = tempfile::NamedTempFile::new().unwrap();
    for mut db in [
        crate::WalletDb::from_connection(
            rusqlite::Connection::open_in_memory().unwrap(),
            TestBuilder::<(), ()>::DEFAULT_NETWORK,
            test_clock(),
            test_rng(),
        ),
        crate::WalletDb::for_path(
            file.path(),
            TestBuilder::<(), ()>::DEFAULT_NETWORK,
            test_clock(),
            test_rng(),
        )
        .unwrap(),
    ] {
        crate::wallet::init::WalletMigrator::new()
            .init_or_migrate(&mut db)
            .unwrap();
        assert!(db.transaction_data_requests().unwrap().is_empty());
        assert!(matches!(
            db.transaction_enhancement_work(),
            Err(SqliteClientError::EnhancementModeNotConfigured)
        ));
        db.transactionally(|tx| {
            assert!(tx.transaction_data_requests()?.is_empty());
            assert!(matches!(
                tx.transaction_enhancement_work(),
                Err(SqliteClientError::EnhancementModeNotConfigured)
            ));
            Ok::<_, SqliteClientError>(())
        })
        .unwrap();
        for mode in [EnhancementMode::Standard, EnhancementMode::PrivateIronwood] {
            db.set_enhancement_mode(mode);
            assert!(db.transaction_data_requests().unwrap().is_empty());
            assert!(db.transaction_enhancement_work().unwrap().is_empty());
            db.transactionally(|tx| {
                assert_eq!(tx.enhancement_mode, Some(mode));
                assert!(tx.transaction_data_requests()?.is_empty());
                assert!(tx.transaction_enhancement_work()?.is_empty());
                Ok::<_, SqliteClientError>(())
            })
            .unwrap();
        }
    }
}

#[test]
fn reopening_requires_mode_before_enumerating_persisted_work() {
    use crate::testing::db::{test_clock, test_rng};
    let (st, _, _) = fixture_with_factory(TestDbFactory::file_backed());
    let expected = st
        .wallet()
        .db()
        .private_work()
        .unwrap()
        .into_iter()
        .map(TransactionEnhancementWork::Private)
        .collect::<Vec<_>>();
    assert!(!expected.is_empty());
    let db = crate::WalletDb::for_path(
        st.wallet().data_file_path(),
        *st.network(),
        test_clock(),
        test_rng(),
    )
    .unwrap();
    // Status and transparent-history work does not depend on payload routing.
    assert!(db.transaction_data_requests().is_ok());
    assert!(matches!(
        db.transaction_enhancement_work(),
        Err(SqliteClientError::EnhancementModeNotConfigured)
    ));
    let db = db.with_enhancement_mode(EnhancementMode::PrivateIronwood);
    assert_eq!(db.transaction_enhancement_work().unwrap(), expected);
}

#[test]
fn pir_recovers_history_and_backfills_without_losing_a_stored_memo() {
    use orchard::note_encryption::IronwoodNoteEncryption;
    use zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata;
    let (mut st, tx_ref, request) = fixture();
    let note = st
        .wallet()
        .db()
        .pending_memo(request.position())
        .unwrap()
        .unwrap()
        .note;
    let encryptor = IronwoodNoteEncryption::new(None, note, [7; 512]);
    let record = EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: (encryptor.encrypt_note_plaintext())[52..]
            .try_into()
            .unwrap(),
        cv_net: [0; 32],
        out_ciphertext: [0; 80],
        has_transparent_inputs: false,
        has_transparent_outputs: false,
        metadata: EnhanceTransactionMetadata::new(123_456, Some(12_345)).unwrap(),
    });
    // A response conflicting with a previously stored history assertion must
    // leave this action's work pending.
    st.wallet().conn().execute(
        "UPDATE ironwood_enhance_routing SET history_expiry_height = 123457 WHERE transaction_id = ?",
        [tx_ref.0],
    ).unwrap();
    assert_eq!(
        apply_record(st.wallet_mut().db_mut(), request, &record).unwrap(),
        EnhancePirStoreResult::Rejected
    );
    assert_eq!(st.wallet().db().query_requests().unwrap(), vec![request]);
    st.wallet().conn().execute(
        "UPDATE ironwood_enhance_routing SET history_expiry_height = NULL WHERE transaction_id = ?",
        [tx_ref.0],
    ).unwrap();
    assert_eq!(
        apply_record(st.wallet_mut().db_mut(), request, &record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    let history = || {
        st.wallet()
            .conn()
            .query_row(
                "SELECT fee, expiry_height, raw FROM transactions WHERE id_tx = ?",
                [tx_ref.0],
                |r| {
                    Ok((
                        r.get::<_, u64>(0)?,
                        r.get::<_, Option<u32>>(1)?,
                        r.get::<_, Option<Vec<u8>>>(2)?,
                    ))
                },
            )
            .unwrap()
    };
    assert_eq!(history(), (12_345, None, None));
    assert_eq!(
        st.wallet()
            .conn()
            .query_row(
                "SELECT expiry_height FROM v_transactions WHERE txid = ?",
                [request.request_id().txid().as_ref()],
                |r| r.get::<_, Option<u32>>(0),
            )
            .unwrap(),
        Some(123_456),
    );
    assert!(
        st.wallet()
            .db()
            .get_transaction(request.request_id().txid())
            .unwrap()
            .is_none()
    );
    assert!(st.wallet().db().query_requests().unwrap().is_empty());
    // Simulate private completion with a retained memo but missing metadata.
    st.wallet()
        .conn()
        .execute(
            "UPDATE transactions SET fee = NULL, expiry_height = NULL WHERE id_tx = ?",
            [tx_ref.0],
        )
        .unwrap();
    queue_transaction(
        st.wallet().conn(),
        tx_ref,
        &IronwoodEnhancementPlan::Eligible { outgoing: vec![] },
    )
    .unwrap();
    assert!(
        st.wallet()
            .db()
            .pending_memo(request.position())
            .unwrap()
            .is_none()
    );
    assert_eq!(st.wallet().db().query_requests().unwrap(), vec![request]);
    assert_eq!(
        apply_record(st.wallet_mut().db_mut(), request, &record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    assert!(st.wallet().db().query_requests().unwrap().is_empty());
    let memo: Vec<u8> = st
        .wallet()
        .conn()
        .query_row(
            "SELECT memo FROM ironwood_received_notes WHERE transaction_id = ?",
            [tx_ref.0],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(memo, vec![7; 512]);
}

#[test]
fn pir_conflicting_metadata_rolls_back_the_entire_response() {
    use orchard::note_encryption::IronwoodNoteEncryption;
    use zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata;
    let (mut st, tx_ref, request) = fixture();
    let note = st
        .wallet()
        .db()
        .pending_memo(request.position())
        .unwrap()
        .unwrap()
        .note;
    let encryptor = IronwoodNoteEncryption::new(None, note, [8; 512]);
    let record = EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: (encryptor.encrypt_note_plaintext())[52..]
            .try_into()
            .unwrap(),
        cv_net: [0; 32],
        out_ciphertext: [0; 80],
        has_transparent_inputs: false,
        has_transparent_outputs: false,
        metadata: EnhanceTransactionMetadata::new(0, Some(20)).unwrap(),
    });
    st.wallet()
        .conn()
        .execute(
            "UPDATE transactions SET fee = 10 WHERE id_tx = ?",
            [tx_ref.0],
        )
        .unwrap();
    assert_eq!(
        apply_record(st.wallet_mut().db_mut(), request, &record).unwrap(),
        EnhancePirStoreResult::Rejected
    );
    assert!(
        st.wallet()
            .db()
            .pending_memo(request.position())
            .unwrap()
            .is_some()
    );
    let values: (u64, Option<u32>) = st
        .wallet()
        .conn()
        .query_row(
            "SELECT fee, expiry_height FROM transactions WHERE id_tx = ?",
            [tx_ref.0],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(values, (10, None));
}

#[test]
fn metadata_compare_and_apply_rejects_changed_snapshot_without_retiring_work() {
    for (fee, expiry) in [(Some(0u64), None), (None, Some(0u32)), (Some(0), Some(0))] {
        let (mut st, tx_ref, request) = fixture();
        let captured = stored_metadata(&st, request);
        assert_eq!(captured, StoredIronwoodMetadata::default());
        // Another writer fills the same proposed values after the snapshot was captured.
        st.wallet()
            .conn()
            .execute(
                "UPDATE transactions SET fee = ?1, expiry_height = ?2 WHERE id_tx = ?3",
                rusqlite::params![fee, expiry, tx_ref.0],
            )
            .unwrap();
        let concurrent = stored_metadata(&st, request);
        let response = ValidatedIronwoodEnhancement::for_testing(
            request,
            false,
            Some(MemoBytes::empty()),
            IronwoodOutgoingResult::NotRequested,
            Some(captured),
        );
        assert_eq!(
            st.wallet_mut().db_mut().apply_validated(response).unwrap(),
            EnhancePirStoreResult::Rejected
        );
        assert_eq!(stored_metadata(&st, request), concurrent);
        assert_eq!(
            st.wallet().conn().query_row(
                "SELECT history_expiry_height FROM ironwood_enhance_routing WHERE transaction_id = ?",
                [tx_ref.0],
                |row| row.get::<_, Option<u32>>(0),
            ).unwrap(),
            None,
        );
        assert!(requests(st.wallet().conn()).unwrap().contains(&request));
        assert!(
            pending(
                st.wallet().conn(),
                &TestBuilder::<(), ()>::DEFAULT_NETWORK,
                request.position()
            )
            .unwrap()
            .is_some()
        );
        // A fresh validation snapshot can complete the still-pending action.
        finish_incoming(&mut st, request);
    }
}

#[test]
fn metadata_compare_and_apply_requires_a_compatible_snapshot() {
    for expected in [
        None,
        Some(StoredIronwoodMetadata {
            fee_zatoshis: Some(1),
            expiry_height: None,
        }),
    ] {
        let (mut st, _, request) = fixture();
        let before = stored_metadata(&st, request);
        let response = ValidatedIronwoodEnhancement::for_testing(
            request,
            false,
            Some(MemoBytes::empty()),
            IronwoodOutgoingResult::NotRequested,
            expected,
        );
        assert_eq!(
            st.wallet_mut().db_mut().apply_validated(response).unwrap(),
            EnhancePirStoreResult::Rejected
        );
        assert_eq!(stored_metadata(&st, request), before);
        assert!(requests(st.wallet().conn()).unwrap().contains(&request));
    }
}

#[test]
fn metadata_fill_rolls_back_when_later_memo_write_fails() {
    let (mut st, tx_ref, request) = fixture();
    let before = stored_metadata(&st, request);
    st.wallet().conn().execute_batch(
        "CREATE TRIGGER fail_memo_after_metadata BEFORE UPDATE OF memo ON ironwood_received_notes
         BEGIN SELECT RAISE(FAIL, 'memo write failed'); END;",
    ).unwrap();
    let response = ValidatedIronwoodEnhancement::for_testing(
        request,
        false,
        Some(MemoBytes::empty()),
        IronwoodOutgoingResult::NotRequested,
        Some(before),
    );
    assert!(st.wallet_mut().db_mut().apply_validated(response).is_err());
    assert_eq!(stored_metadata(&st, request), before);
    assert_eq!(
        st.wallet().conn().query_row(
            "SELECT history_expiry_height FROM ironwood_enhance_routing WHERE transaction_id = ?",
            [tx_ref.0],
            |row| row.get::<_, Option<u32>>(0),
        ).unwrap(),
        None,
    );
    assert!(requests(st.wallet().conn()).unwrap().contains(&request));
    assert!(
        pending(
            st.wallet().conn(),
            &TestBuilder::<(), ()>::DEFAULT_NETWORK,
            request.position()
        )
        .unwrap()
        .is_some()
    );
    let metadata_jobs: u64 = st
        .wallet()
        .conn()
        .query_row(
            "SELECT COUNT(*) FROM ironwood_enhance_metadata_queue",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        metadata_jobs, 1,
        "metadata queue deletion must roll back too"
    );
}

#[test]
fn identical_anchor_suspensions_are_deduplicated() {
    let (st, tx_ref, request) = fixture();
    let conn = st.wallet().conn();
    conn.execute(
        "INSERT INTO ironwood_enhance_discovery_queue (transaction_id) VALUES (?)",
        [tx_ref.0],
    )
    .unwrap();
    conn.execute("UPDATE ironwood_enhance_metadata_queue SET commitment_tree_position = NULL, output_index = NULL, compact_bound = 0 WHERE transaction_id = ?", [tx_ref.0]).unwrap();
    conn.execute("UPDATE blocks SET ironwood_commitment_tree_size = NULL", [])
        .unwrap();
    let anchor = EnhancePirWork::Suspended(EnhancePirSuspension::Discovery(
        IronwoodEnhanceDiscoveryFailure {
            txid: request.request_id().txid(),
            reason: IronwoodEnhanceDiscoveryFailureReason::AnchorUnavailable,
        },
    ));
    assert_eq!(
        work(conn)
            .unwrap()
            .iter()
            .filter(|item| **item == anchor)
            .count(),
        1
    );
    conn.execute(
        "UPDATE ironwood_enhance_discovery_queue SET suspended = 1",
        [],
    )
    .unwrap();
    let items = work(conn).unwrap();
    assert!(items.contains(&anchor));
    assert!(
        items.contains(&EnhancePirWork::Suspended(EnhancePirSuspension::Discovery(
            IronwoodEnhanceDiscoveryFailure {
                txid: request.request_id().txid(),
                reason: IronwoodEnhanceDiscoveryFailureReason::NoFundingAccounts
            }
        )))
    );
}

#[test]
fn response_application_retries_after_another_connection_rolls_back() {
    use orchard::note_encryption::IronwoodNoteEncryption;
    let (mut st, tx_ref, request) = fixture_with_factory(TestDbFactory::file_backed());
    let note = st
        .wallet()
        .db()
        .pending_memo(request.position())
        .unwrap()
        .unwrap()
        .note;
    let encryptor = IronwoodNoteEncryption::new(None, note, [8; 512]);
    let record = EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: (encryptor.encrypt_note_plaintext())[52..]
            .try_into()
            .unwrap(),
        cv_net: [0; 32],
        out_ciphertext: [0; 80],
        has_transparent_inputs: false,
        has_transparent_outputs: false,
        metadata: zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
            0,
            Some(20),
        )
        .unwrap(),
    });
    let mut competing = Connection::open(st.wallet().data_file_path()).unwrap();
    st.wallet()
        .conn()
        .busy_timeout(std::time::Duration::ZERO)
        .unwrap();
    let tx = competing
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .unwrap();
    tx.execute(
        "UPDATE transactions SET fee = 99 WHERE id_tx = ?",
        [tx_ref.0],
    )
    .unwrap();
    let before = work(st.wallet().conn()).unwrap();
    let err = apply_record(st.wallet_mut().db_mut(), request, &record).unwrap_err();
    assert!(
        matches!(err, SqliteClientError::DbError(rusqlite::Error::SqliteFailure(e, _)) if e.code == rusqlite::ErrorCode::DatabaseBusy)
    );
    assert_eq!(work(st.wallet().conn()).unwrap(), before);
    assert!(
        st.wallet()
            .db()
            .pending_memo(request.position())
            .unwrap()
            .is_some()
    );
    tx.rollback().unwrap();
    assert_eq!(
        apply_record(st.wallet_mut().db_mut(), request, &record).unwrap(),
        EnhancePirStoreResult::Stored
    );
    assert!(work(st.wallet().conn()).unwrap().is_empty());
    assert_eq!(
        competing
            .query_row(
                "SELECT fee FROM transactions WHERE id_tx = ?",
                [tx_ref.0],
                |r| r.get::<_, u64>(0)
            )
            .unwrap(),
        20
    );
}

fn authentic_incoming_record(st: &State, request: EnhancePirRequest) -> EnhanceRecord {
    let pending = st
        .wallet()
        .db()
        .pending_memo(request.position())
        .unwrap()
        .unwrap();
    let encryptor =
        orchard::note_encryption::IronwoodNoteEncryption::new(None, pending.note, [7; 512]);
    EnhanceRecord::from_parts(EnhanceRecordParts {
        enc_ciphertext_suffix: encryptor.encrypt_note_plaintext()[52..].try_into().unwrap(),
        cv_net: [0; 32],
        out_ciphertext: [0; 80],
        has_transparent_inputs: false,
        has_transparent_outputs: false,
        metadata: zcash_client_backend::data_api::enhance_pir::EnhanceTransactionMetadata::new(
            0,
            Some(0),
        )
        .unwrap(),
    })
}

#[test]
fn batch_commits_across_rows_preserves_duplicates_and_ignores_stale_metadata() {
    use zcash_client_backend::data_api::enhance_pir::EnhancePirBatchResult as Batch;
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);
    let record = authentic_incoming_record(&st, incoming);
    let stale = EnhancePirRequest::new(100.into(), incoming.request_id());
    let result = st
        .wallet_mut()
        .db_mut()
        .apply_ironwood_enhance_records(&[
            (incoming, record.clone()),
            (outgoing, wire_record(false, false)),
            (incoming, record),
            (stale, wire_record(true, true)),
        ])
        .unwrap();
    assert_eq!(
        result,
        Batch::Committed(vec![
            EnhancePirStoreResult::Stored,
            EnhancePirStoreResult::NotRecoverable,
            EnhancePirStoreResult::Stored,
            EnhancePirStoreResult::AlreadyResolved
        ])
    );
    assert!(requests(st.wallet().conn()).unwrap().is_empty());
    assert!(!visible(&st, incoming));
}

#[test]
fn batch_rejection_and_sql_failure_roll_back_all_effects() {
    use zcash_client_backend::data_api::enhance_pir::{
        EnhancePirBatchRejection as Reason, EnhancePirBatchResult as Batch,
    };
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    let valid = authentic_incoming_record(&st, incoming);
    let before = requests(st.wallet().conn()).unwrap();
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_ironwood_enhance_records(&[
                (outgoing, wire_record(false, false)),
                (incoming, wire_record(false, false)),
            ])
            .unwrap(),
        Batch::Rejected {
            index: Some(1),
            reason: Reason::RecordRejected
        }
    );
    assert_eq!(requests(st.wallet().conn()).unwrap(), before);
    // The first action stores its memo before the second action hits this trigger.
    st.wallet()
        .conn()
        .execute_batch(
            "CREATE TEMP TRIGGER fail_batch_second_action
        BEFORE UPDATE OF not_recoverable ON ironwood_enhance_outgoing_queue
        BEGIN SELECT RAISE(ABORT, 'batch failure'); END;",
        )
        .unwrap();
    assert!(
        st.wallet_mut()
            .db_mut()
            .apply_ironwood_enhance_records(&[
                (incoming, valid.clone()),
                (outgoing, wire_record(false, false)),
            ])
            .is_err()
    );
    assert_eq!(requests(st.wallet().conn()).unwrap(), before);
    assert!(
        st.wallet()
            .db()
            .pending_memo(incoming.position())
            .unwrap()
            .is_some()
    );
    let fee: Option<u64> = st
        .wallet()
        .conn()
        .query_row(
            "SELECT fee FROM transactions WHERE id_tx = ?",
            [tx_ref.0],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(fee, None);
    st.wallet()
        .conn()
        .execute_batch("DROP TRIGGER fail_batch_second_action")
        .unwrap();
    // A commit-time rejection also rolls back an earlier action, not just SQL errors.
    st.wallet()
        .conn()
        .execute_batch(
            "CREATE TEMP TRIGGER conflict_batch_second_action
        AFTER UPDATE OF memo ON ironwood_received_notes BEGIN
        UPDATE ironwood_enhance_routing SET history_expiry_height = 1; END;",
        )
        .unwrap();
    assert!(matches!(
        st.wallet_mut()
            .db_mut()
            .apply_ironwood_enhance_records(&[
                (incoming, valid),
                (outgoing, wire_record(false, false)),
            ])
            .unwrap(),
        Batch::Rejected { .. }
    ));
    assert_eq!(requests(st.wallet().conn()).unwrap(), before);
    assert!(
        st.wallet()
            .db()
            .pending_memo(incoming.position())
            .unwrap()
            .is_some()
    );
}

#[test]
fn batch_rejects_shape_duplicates_and_metadata_conflicts_without_mutation() {
    use zcash_client_backend::data_api::enhance_pir::{
        EnhancePirBatchRejection as Reason, EnhancePirBatchResult as Batch,
    };
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    let valid = authentic_incoming_record(&st, incoming);
    let before = requests(st.wallet().conn()).unwrap();
    assert_eq!(
        st.wallet_mut()
            .db_mut()
            .apply_ironwood_enhance_records(&[])
            .unwrap(),
        Batch::Rejected {
            index: None,
            reason: Reason::Empty
        }
    );
    let other = EnhancePirRequest::new(
        100.into(),
        IronwoodEnhanceRequestId::new(TxId::from_bytes([55; 32]), 0),
    );
    for (items, reason) in [
        (
            vec![(incoming, valid.clone()), (other, valid.clone())],
            Reason::MixedTxid,
        ),
        (
            vec![
                (incoming, valid.clone()),
                (incoming, wire_record(false, false)),
            ],
            Reason::ConflictingDuplicate,
        ),
        (
            vec![
                (incoming, valid.clone()),
                (outgoing, wire_record(true, false)),
            ],
            Reason::MetadataConflict,
        ),
    ] {
        assert_eq!(
            st.wallet_mut()
                .db_mut()
                .apply_ironwood_enhance_records(&items)
                .unwrap(),
            Batch::Rejected {
                index: Some(1),
                reason
            }
        );
        assert_eq!(requests(st.wallet().conn()).unwrap(), before);
    }
    for offset in [641, 645] {
        let mut bytes = *wire_record(false, false).as_bytes();
        bytes[offset] = 1;
        assert_eq!(
            st.wallet_mut()
                .db_mut()
                .apply_ironwood_enhance_records(&[
                    (incoming, valid.clone()),
                    (outgoing, EnhanceRecord::from_bytes(bytes).unwrap()),
                ])
                .unwrap(),
            Batch::Rejected {
                index: Some(1),
                reason: Reason::MetadataConflict
            }
        );
        assert_eq!(requests(st.wallet().conn()).unwrap(), before);
    }
}

#[test]
fn batch_transparent_routing_is_order_independent_and_sticky() {
    use zcash_client_backend::data_api::enhance_pir::EnhancePirBatchResult as Batch;
    for reverse in [false, true] {
        let (mut st, tx_ref, incoming) = fixture();
        st.wallet_mut()
            .db_mut()
            .set_enhancement_mode(EnhancementMode::PrivateIronwood);
        queue_transaction(
            st.wallet().conn(),
            tx_ref,
            &IronwoodEnhancementPlan::Eligible {
                outgoing: [(98, 3), (99, 4)]
                    .map(|(position, index)| {
                        IronwoodEnhanceCandidate::from_parts(
                            position.into(),
                            index,
                            [1; 32],
                            [2; 32],
                            [3; 32],
                            [4; 52],
                            vec![st.test_account().unwrap().id()],
                        )
                    })
                    .to_vec(),
            },
        )
        .unwrap();
        let a = EnhancePirRequest::new(
            98.into(),
            IronwoodEnhanceRequestId::new(incoming.request_id().txid(), 3),
        );
        let b = EnhancePirRequest::new(
            99.into(),
            IronwoodEnhanceRequestId::new(incoming.request_id().txid(), 4),
        );
        let mut items = vec![(a, wire_record(true, false)), (b, wire_record(true, false))];
        if reverse {
            items.reverse();
        }
        assert_eq!(
            st.wallet_mut()
                .db_mut()
                .apply_ironwood_enhance_records(&items)
                .unwrap(),
            Batch::Committed(vec![EnhancePirStoreResult::LwdRequired; 2])
        );
        assert!(visible(&st, incoming));
        assert!(requests(st.wallet().conn()).unwrap().is_empty());
        assert_eq!(
            apply_record(st.wallet_mut().db_mut(), a, &wire_record(false, false)).unwrap(),
            EnhancePirStoreResult::AlreadyResolved
        );
        assert!(visible(&st, incoming));
    }
}

#[test]
fn scan_persists_compact_fields_and_rescan_preserves_them() {
    let (mut st, tx_ref, incoming) = fixture();
    let before = st
        .wallet()
        .db()
        .pending_memo(incoming.position())
        .unwrap()
        .unwrap();
    let height: u32 = st
        .wallet()
        .conn()
        .query_row(
            "SELECT mined_height FROM transactions WHERE id_tx = ?",
            [tx_ref.0],
            |r| r.get(0),
        )
        .unwrap();
    st.scan_cached_blocks(BlockHeight::from_u32(height), 1);
    let after = st
        .wallet()
        .db()
        .pending_memo(incoming.position())
        .unwrap()
        .unwrap();
    assert_eq!(before.ephemeral_key, after.ephemeral_key);
    assert_eq!(before.compact_ciphertext, after.compact_ciphertext);
    // A received-output update without compact context must not erase scan data.
    let output = zcash_client_backend::wallet::WalletOrchardOutput::from_parts(
        incoming.request_id().output_index() as usize,
        zcash_note_encryption::EphemeralKeyBytes(after.ephemeral_key),
        (after.note, orchard::ValuePool::Ironwood),
        false,
        incoming.position(),
        None,
        after.account_id,
        Some(after.scope),
    );
    let tx = st.wallet().conn().unchecked_transaction().unwrap();
    super::super::orchard::put_received_note(
        &tx,
        st.network(),
        ShieldedPool::Ironwood,
        &output,
        tx_ref,
        Some(BlockHeight::from_u32(height)),
        None,
    )
    .unwrap();
    tx.commit().unwrap();
    let updated = st
        .wallet()
        .db()
        .pending_memo(incoming.position())
        .unwrap()
        .unwrap();
    assert_eq!(updated.ephemeral_key, before.ephemeral_key);
    assert_eq!(updated.compact_ciphertext, before.compact_ciphertext);

    assert!(
        st.wallet()
            .conn()
            .execute(
                "UPDATE ironwood_received_notes SET ephemeral_key = zeroblob(31)",
                []
            )
            .is_err()
    );
    assert!(
        st.wallet()
            .conn()
            .execute(
                "UPDATE ironwood_received_notes SET ephemeral_key = NULL",
                []
            )
            .is_err()
    );
    st.wallet()
        .conn()
        .execute(
            "UPDATE ironwood_received_notes SET ephemeral_key = NULL, compact_ciphertext = NULL",
            [],
        )
        .unwrap();
    assert!(st.wallet().db().pending_memo(incoming.position()).is_err());
}

#[test]
fn rc5_wallet_upgrades_and_scans_private_ironwood_work() {
    use crate::wallet::init::{WalletMigrator, migrations::V_ZAKURA_0_1_0_RC5};

    let mut st = unscanned_state_with_factory(TestDbFactory::at_migrations(V_ZAKURA_0_1_0_RC5));
    assert!(
        st.wallet()
            .conn()
            .prepare("SELECT ephemeral_key FROM ironwood_received_notes")
            .is_err()
    );
    WalletMigrator::new()
        .init_or_migrate(st.wallet_mut().db_mut())
        .unwrap();
    // A second initialization must not repeat ALTER TABLE or reset wallet state.
    WalletMigrator::new()
        .init_or_migrate(st.wallet_mut().db_mut())
        .unwrap();
    let (mut st, _, incoming) = fixture_from_state(st);
    assert!(
        st.wallet()
            .db()
            .pending_memo(incoming.position())
            .unwrap()
            .is_some()
    );
    let (empty_height, _) = st.generate_empty_block();
    st.scan_cached_blocks(empty_height, 1);
    assert!(
        st.wallet()
            .db()
            .query_requests()
            .unwrap()
            .contains(&incoming)
    );
}

/// Splits a routed snapshot and asserts that no transaction appears under both transports.
fn routed(st: &State) -> (Vec<TxId>, Vec<EnhancePirWork>) {
    let mut public = vec![];
    let mut private = vec![];
    for work in st.wallet().db().transaction_enhancement_work().unwrap() {
        match work {
            TransactionEnhancementWork::Public(request) => public.push(request.txid()),
            TransactionEnhancementWork::Private(work) => private.push(work),
        }
    }
    for work in &private {
        let txid = match work {
            EnhancePirWork::Query(request)
            | EnhancePirWork::Suspended(EnhancePirSuspension::OutgoingNotRecoverable(request)) => {
                Some(request.request_id().txid())
            }
            EnhancePirWork::Suspended(EnhancePirSuspension::Discovery(failure)) => {
                Some(failure.txid)
            }
            EnhancePirWork::Rediscover(_) => None,
        };
        assert!(
            txid.is_none_or(|txid| !public.contains(&txid)),
            "{txid:?} is routed to both transports"
        );
    }
    public.sort();
    (public, private)
}

/// Inserts an unmined transaction with ordinary enhancement and status intent, and an optional
/// transaction-wide route.
fn queue_ordinary(st: &State, txid: TxId, route: Option<i64>) {
    let conn = st.wallet().conn();
    conn.execute(
        "INSERT INTO transactions (txid, expiry_height, min_observed_height) VALUES (:txid, 0, 1)",
        named_params![":txid": txid.as_ref()],
    )
    .unwrap();
    for query_type in [TxQueryType::Status, TxQueryType::Enhancement] {
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (:txid, :query_type)",
            named_params![":txid": txid.as_ref(), ":query_type": query_type.code()],
        )
        .unwrap();
    }
    if let Some(route) = route {
        conn.execute(
            "INSERT INTO ironwood_enhance_routing (transaction_id, route)
             SELECT id_tx, :route FROM transactions WHERE txid = :txid",
            named_params![":txid": txid.as_ref(), ":route": route],
        )
        .unwrap();
    }
}

#[test]
fn routed_work_partitions_each_transaction_to_one_transport() {
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    let protected = incoming.request_id().txid();
    let unclassified = TxId::from_bytes([0xa1; 32]);
    let lwd_required = TxId::from_bytes([0xa2; 32]);
    let protected_idle = TxId::from_bytes([0xa3; 32]);
    queue_ordinary(&st, unclassified, None);
    queue_ordinary(&st, lwd_required, Some(LWD_REQUIRED));
    queue_ordinary(&st, protected_idle, Some(PRIVATE_PROTECTED));

    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::Standard);
    let (public, private) = routed(&st);
    let mut all = vec![protected, unclassified, lwd_required, protected_idle];
    all.sort();
    assert_eq!(public, all, "standard mode routes every payload publicly");
    assert!(private.is_empty(), "standard mode never schedules PIR");

    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);
    let (public, private) = routed(&st);
    let mut ordinary = vec![unclassified, lwd_required];
    ordinary.sort();
    assert_eq!(
        public, ordinary,
        "protected transactions, even without queued PIR work, are never public"
    );
    let mut queries = vec![
        EnhancePirWork::Query(incoming),
        EnhancePirWork::Query(outgoing),
    ];
    queries.sort_by_key(|work| match work {
        EnhancePirWork::Query(request) => request.position(),
        _ => unreachable!(),
    });
    assert_eq!(private, queries);

    // Private queries are actionable before public requests in the snapshot order.
    let kinds = st
        .wallet()
        .db()
        .transaction_enhancement_work()
        .unwrap()
        .into_iter()
        .map(|work| matches!(work, TransactionEnhancementWork::Public(_)))
        .collect::<Vec<_>>();
    assert!(kinds.is_sorted(), "{kinds:?}");
}

#[test]
fn transparent_flag_moves_the_whole_transaction_to_public_work() {
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    let txid = incoming.request_id().txid();
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);
    assert_eq!(routed(&st).0, vec![]);

    assert_eq!(
        apply_record(
            st.wallet_mut().db_mut(),
            outgoing,
            &wire_record(true, false)
        )
        .unwrap(),
        EnhancePirStoreResult::LwdRequired
    );
    assert_eq!(routed(&st), (vec![txid], vec![]));

    // A later false flag cannot restore private routing.
    assert_eq!(
        apply_record(
            st.wallet_mut().db_mut(),
            outgoing,
            &wire_record(false, false)
        )
        .unwrap(),
        EnhancePirStoreResult::AlreadyResolved
    );
    assert_eq!(routed(&st), (vec![txid], vec![]));
}

#[test]
fn private_suspensions_are_never_routed_publicly() {
    let (mut st, tx_ref, incoming) = fixture();
    let outgoing = outgoing(&st, tx_ref, 99, 4);
    let txid = incoming.request_id().txid();
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);
    assert_eq!(
        apply_record(
            st.wallet_mut().db_mut(),
            outgoing,
            &wire_record(false, false)
        )
        .unwrap(),
        EnhancePirStoreResult::NotRecoverable
    );
    finish_incoming(&mut st, incoming);
    // This incoming-only fixture has no durable spending associations.
    super::discovery::queue(st.wallet().conn(), tx_ref).unwrap();

    assert_eq!(
        routed(&st),
        (
            vec![],
            vec![
                EnhancePirWork::Suspended(EnhancePirSuspension::Discovery(
                    IronwoodEnhanceDiscoveryFailure {
                        txid,
                        reason: IronwoodEnhanceDiscoveryFailureReason::NoFundingAccounts,
                    },
                )),
                EnhancePirWork::Suspended(EnhancePirSuspension::OutgoingNotRecoverable(outgoing)),
            ]
        )
    );

    // Leaving private mode exposes the outstanding ordinary obligation instead.
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::Standard);
    assert_eq!(routed(&st), (vec![txid], vec![]));
}

#[test]
fn private_completion_leaves_no_payload_work_in_either_mode() {
    let (mut st, _, incoming) = fixture();
    st.wallet_mut()
        .db_mut()
        .set_enhancement_mode(EnhancementMode::PrivateIronwood);
    assert_eq!(routed(&st), (vec![], vec![EnhancePirWork::Query(incoming)]));
    finish_incoming(&mut st, incoming);
    for mode in [EnhancementMode::PrivateIronwood, EnhancementMode::Standard] {
        st.wallet_mut().db_mut().set_enhancement_mode(mode);
        assert_eq!(routed(&st), (vec![], vec![]), "{mode:?}");
    }
}
