use super::*;

use incrementalmerkletree::Position;
use transparent::bundle::{OutPoint, TxOut};
use zcash_client_backend::{data_api::WalletWrite, wallet::WalletTransparentOutput};
use zcash_keys::keys::{ReceiverRequirement, UnifiedSpendingKey};
use zcash_protocol::consensus::BlockHeight;

fn taddr(seed: u8) -> TransparentAddress {
    TransparentAddress::PublicKeyHash([seed; 20])
}

fn balance(value: u64) -> Balance {
    let mut balance = Balance::ZERO;
    balance
        .add_spendable_value(Zatoshis::from_u64(value).unwrap())
        .unwrap();
    balance
}

fn receiver(value: u64, scope: TransparentKeyScope) -> (TransparentKeyOrigin, Balance) {
    (TransparentKeyOrigin::Derived { scope }, balance(value))
}

#[test]
fn active_migration_restricts_ordinary_sends_to_ironwood() {
    let policy = ordinary_send_spend_policy(true);

    assert!(!policy.permits_shielded(ShieldedProtocol::Sapling));
    assert!(!policy.permits_shielded(ShieldedProtocol::Orchard));
    assert!(policy.permits_shielded(ShieldedProtocol::Ironwood));
    assert_eq!(
        ordinary_send_spend_pools(true),
        vec![ShieldedProtocol::Ironwood]
    );
}

#[test]
fn ordinary_send_policy_keeps_all_shielded_pools_without_migration() {
    let policy = ordinary_send_spend_policy(false);

    assert!(policy.permits_shielded(ShieldedProtocol::Sapling));
    assert!(policy.permits_shielded(ShieldedProtocol::Orchard));
    assert!(policy.permits_shielded(ShieldedProtocol::Ironwood));
}

#[test]
fn shield_result_preserves_pending_broadcast_status() {
    let result = CreatedBroadcastResult {
        txids: "abc123".to_string(),
        status: CreatedBroadcastResult::PENDING_BROADCAST,
        broadcasted_count: 0,
        total_count: 1,
        message: Some("Broadcast could not start".to_string()),
    }
    .into_shield_transparent_result(10_000, 90_000);

    assert_eq!(result.txids, "abc123");
    assert_eq!(result.status, CreatedBroadcastResult::PENDING_BROADCAST);
    assert_eq!(result.broadcasted_count, 0);
    assert_eq!(result.total_count, 1);
    assert_eq!(result.message.as_deref(), Some("Broadcast could not start"));
    assert_eq!(result.fee_zatoshi, 10_000);
    assert_eq!(result.shielded_zatoshi, 90_000);
}

#[test]
fn send_proposals_use_v6_after_nu6_3() {
    let network = WalletNetwork::Regtest;
    crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
    let v2_only = SelectedOrchardNoteVersions {
        has_v2: true,
        has_v3: false,
    };

    // Pass-1 ceiling: no explicit version before activation, V6 after.
    let before = proposed_tx_version_for_send(network, TargetHeight::from(1));
    let after = proposed_tx_version_for_send(network, TargetHeight::from(2));
    assert_eq!(before, None);
    assert_eq!(after, Some(TxVersion::V6));

    // The pass-2 decision keys off that ceiling: a V2-only selection with a
    // non-Orchard payment downgrades a post-activation V6 proposal, never a
    // pre-activation one.
    assert!(should_downgrade_send_to_legacy_v5(after, &v2_only, false));
    assert!(!should_downgrade_send_to_legacy_v5(before, &v2_only, false));
}

#[test]
fn v5_downgrade_requires_v6_ceiling_and_v2_only_spends() {
    let versions = |has_v2, has_v3| SelectedOrchardNoteVersions { has_v2, has_v3 };

    // Canonical downgrade case: V6 ceiling, V2-only spends, non-Orchard
    // recipient.
    assert!(should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(true, false),
        false,
    ));
    // Shielded-Orchard recipient: a legacy-V5 build would fail with
    // CrossAddressDisabled, so stay V6 even for V2-only spends.
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(true, false),
        true,
    ));
    // V3-only and mixed selections keep V6 (mixed keeps the V3 change).
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(false, true),
        false,
    ));
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(true, true),
        false,
    ));
    // No Orchard spends at all: nothing to preserve, keep V6.
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &versions(false, false),
        false,
    ));
    // Pre-activation (no pass-1 ceiling) proposals are never rewritten.
    assert!(!should_downgrade_send_to_legacy_v5(
        None,
        &versions(true, false),
        false,
    ));
    assert!(!should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V5),
        &versions(true, false),
        false,
    ));
}

/// Fabricates a transparent-recipient proposal spending one Orchard note
/// per entry in `versions` (plus a lone Sapling note when `versions` is
/// empty, so the proposal still has a shielded input), mirroring
/// `transparent_recipient_send_max_proposal_spends_shielded_notes`.
fn fabricated_shielded_spend_proposal(
    versions: &[orchard::note::NoteVersion],
) -> Proposal<WalletFeeRule, u32> {
    let network = WalletNetwork::Regtest;
    let orchard_notes = versions
        .iter()
        .enumerate()
        .map(|(index, version)| {
            let sk = orchard::keys::SpendingKey::from_bytes([7 + index as u8; 32]).unwrap();
            let fvk = orchard::keys::FullViewingKey::from(&sk);
            let recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
            let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
            let rseed = (0u8..=255)
                .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
                .expect("test rseed");
            let note = orchard::Note::from_parts(
                recipient,
                orchard::value::NoteValue::from_raw(100_000),
                rho,
                rseed,
                *version,
            )
            .unwrap();
            ReceivedNote::from_parts(
                index as u32,
                TxId::from_bytes([index as u8; 32]),
                0,
                note,
                zip32::Scope::External,
                Position::from(index as u64),
                Some(BlockHeight::from_u32(20)),
                None,
            )
        })
        .collect::<Vec<_>>();
    let sapling_notes = if orchard_notes.is_empty() {
        let spending_key = sapling_crypto::zip32::ExtendedSpendingKey::master(&[7u8; 32]);
        let (_, recipient) = spending_key.default_address();
        let note = sapling_crypto::Note::from_parts(
            recipient,
            sapling_crypto::value::NoteValue::from_raw(100_000),
            sapling_crypto::Rseed::AfterZip212([3u8; 32]),
        );
        vec![ReceivedNote::from_parts(
            100u32,
            TxId::from_bytes([100u8; 32]),
            0,
            note,
            zip32::Scope::External,
            Position::from(0u64),
            Some(BlockHeight::from_u32(20)),
            None,
        )]
    } else {
        vec![]
    };
    let recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

    build_transparent_recipient_send_max_proposal_from_notes(
        network,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        BlockHeight::from_u32(900),
        recipient,
        None,
        ReceivedNotes::new(sapling_notes, orchard_notes, vec![]),
        ConservativeZip317FeeRule,
    )
    .expect("fabricated proposal should build")
}

/// Fabricates a single-step proposal that spends one V2 Orchard note and
/// pays a recipient in `payment_pool`, so `payment_pools()` reflects the
/// requested recipient pool. Used to exercise
/// [`proposal_has_orchard_payment`] and the recipient-pool guard.
fn fabricated_proposal_with_payment_pool(payment_pool: PoolType) -> Proposal<WalletFeeRule, u32> {
    let network = WalletNetwork::Regtest;
    let sk = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
    let fvk = orchard::keys::FullViewingKey::from(&sk);
    let orchard_recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
    let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
    let rseed = (0u8..=255)
        .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
        .expect("test rseed");
    let note = orchard::Note::from_parts(
        orchard_recipient,
        orchard::value::NoteValue::from_raw(100_000),
        rho,
        rseed,
        orchard::note::NoteVersion::V2,
    )
    .unwrap();
    let received_note = ReceivedNote::from_parts(
        0u32,
        TxId::from_bytes([0u8; 32]),
        0,
        note,
        zip32::Scope::External,
        Position::from(0u64),
        Some(BlockHeight::from_u32(20)),
        None,
    );

    // Recipient address matches the requested payment pool.
    let to = match payment_pool {
        PoolType::Transparent => Address::Transparent(taddr(9)).to_zcash_address(&network),
        PoolType::Shielded(ShieldedProtocol::Orchard) => {
            let ua = zcash_keys::address::UnifiedAddress::from_receivers(
                Some(orchard_recipient),
                None,
                None,
            )
            .expect("UA with an Orchard receiver is valid");
            Address::from(ua).to_zcash_address(&network)
        }
        PoolType::Shielded(ShieldedProtocol::Sapling) => {
            let esk = sapling_crypto::zip32::ExtendedSpendingKey::master(&[9u8; 32]);
            let (_, sapling_recipient) = esk.default_address();
            Address::from(sapling_recipient).to_zcash_address(&network)
        }
        PoolType::Shielded(ShieldedProtocol::Ironwood) => {
            unreachable!("this fixture never requests Ironwood payments")
        }
    };

    // No change: amount + fee must equal the single 100_000-zat input, or
    // `Proposal::single_step` rejects the unbalanced proposal.
    let fee = Zatoshis::const_from_u64(10_000);
    let amount = Zatoshis::const_from_u64(90_000);
    let payment = Payment::new(to, Some(amount), None, None, None, vec![]).unwrap();
    let request = TransactionRequest::new(vec![payment]).unwrap();
    // `ShieldedInputs` wants `ReceivedNote<_, wallet::Note>`; wrap the
    // orchard-typed note through `ReceivedNotes::into_vec` to get that form.
    let notes = ReceivedNotes::new(vec![], vec![received_note], vec![]).into_vec(&RetainAllNotes);
    let shielded_inputs = ShieldedInputs::from_parts(nonempty::NonEmpty::from_vec(notes).unwrap());
    let balance = TransactionBalance::new(vec![], fee).unwrap();

    Proposal::single_step(
        request,
        BTreeMap::from([(0usize, payment_pool)]),
        vec![],
        Some(shielded_inputs),
        BlockHeight::from_u32(900),
        balance,
        ConservativeZip317FeeRule,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        ConfirmationsPolicy::default(),
        false,
        false,
    )
    .expect("fabricated payment-pool proposal should build")
}

#[test]
fn proposal_has_orchard_payment_detects_recipient_pool() {
    // Orchard recipient => Orchard payment.
    assert!(proposal_has_orchard_payment(
        &fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Orchard)),
    ));
    // Transparent recipient (Orchard change is not a payment pool) => none.
    assert!(!proposal_has_orchard_payment(
        &fabricated_proposal_with_payment_pool(PoolType::Transparent),
    ));
    // Sapling recipient => not an Orchard payment.
    assert!(!proposal_has_orchard_payment(
        &fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Sapling)),
    ));
    // Change-only send-max proposal (transparent recipient, Orchard spend)
    // has no Orchard payment pool either.
    assert!(!proposal_has_orchard_payment(
        &fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]),
    ));
}

#[test]
fn orchard_recipient_v2_send_keeps_v6_without_rerun() {
    // V2-only spend paying a shielded-Orchard recipient: must stay V6 (a V5
    // build would fail with CrossAddressDisabled), and the re-proposal
    // closure must never run.
    let pass1 =
        fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Orchard));

    let (_, tx_version) = propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |_| {
        panic!("re-proposal must not run for a shielded-Orchard recipient")
    });

    assert_eq!(tx_version, Some(TxVersion::V6));
}

#[test]
fn transparent_recipient_v2_send_downgrades_to_v5() {
    // Contrast with the Orchard-recipient case: a transparent recipient with
    // the same V2-only spend downgrades to V5.
    let pass1 = fabricated_proposal_with_payment_pool(PoolType::Transparent);
    let rerun = fabricated_proposal_with_payment_pool(PoolType::Transparent);

    let (_, tx_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), move |requested| {
            assert_eq!(requested, Some(TxVersion::V5));
            Ok(rerun)
        });

    assert_eq!(tx_version, Some(TxVersion::V5));
}

#[test]
fn proposal_selected_orchard_note_versions_detects_spent_versions() {
    use orchard::note::NoteVersion;

    let v2_only = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
        NoteVersion::V2,
    ]));
    assert!(v2_only.has_v2 && !v2_only.has_v3);

    let v3_only = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
        NoteVersion::V3,
    ]));
    assert!(!v3_only.has_v2 && v3_only.has_v3);

    let mixed = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
        NoteVersion::V2,
        NoteVersion::V3,
    ]));
    assert!(mixed.has_v2 && mixed.has_v3);

    // Sapling-only selection: no Orchard notes at all.
    let none = proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[]));
    assert!(!none.has_v2 && !none.has_v3);
}

#[test]
fn v5_rerun_falls_back_to_v6_proposal_on_failure() {
    let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]);
    let pass1_fee = proposal_fee_zatoshi(&pass1);
    let rerun_calls = std::cell::Cell::new(0);

    let (proposal, tx_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |requested| {
            rerun_calls.set(rerun_calls.get() + 1);
            assert_eq!(requested, Some(TxVersion::V5));
            Err("simulated re-proposal failure".to_string())
        });

    // The failed downgrade keeps the pass-1 proposal under its V6 version.
    assert_eq!(rerun_calls.get(), 1);
    assert_eq!(tx_version, Some(TxVersion::V6));
    assert_eq!(proposal_fee_zatoshi(&proposal), pass1_fee);
}

#[test]
fn v5_rerun_returns_reproposed_v5_proposal_on_success() {
    use orchard::note::NoteVersion;

    let pass1 = fabricated_shielded_spend_proposal(&[NoteVersion::V2]);
    let rerun = fabricated_shielded_spend_proposal(&[NoteVersion::V2, NoteVersion::V2]);

    let (proposal, tx_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), move |_| Ok(rerun));

    assert_eq!(tx_version, Some(TxVersion::V5));
    // The returned proposal is the re-proposed one (two spends, not one).
    let selected: Vec<_> = proposal
        .steps()
        .iter()
        .flat_map(|step| step.shielded_inputs().into_iter())
        .flat_map(|inputs| inputs.notes().iter())
        .collect();
    assert_eq!(selected.len(), 2);
}

#[test]
fn v3_only_spends_keep_v6_without_rerun() {
    let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V3]);

    let (_, tx_version) = propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |_| {
        panic!("re-proposal must not run for a V3-only selection")
    });

    assert_eq!(tx_version, Some(TxVersion::V6));
}

// `estimate_send_max` deliberately quotes at the pass-1 V6 ceiling and does
// NOT apply the V2->V5 downgrade, so the quoted max is always realizable by
// `propose_send` (whose pass-1 is hard-gated at V6). A cheaper V5-priced max
// would over-quote for V2-only wallets and fail `propose_send` with
// InsufficientFunds. This test pins that policy: the same V2-only
// transparent-recipient max proposal that send-max builds *would* be
// downgraded by the shared decision, and the value send-max returns is the
// V6-ceiling summary, unchanged by any downgrade.
#[test]
fn estimate_send_max_stays_at_v6_ceiling_for_v2_only_spends() {
    // The pass-1 proposal send-max builds for a V2-only spend to a
    // transparent recipient.
    let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]);

    // The shared decision WOULD downgrade this (V6 ceiling, V2-only spends,
    // transparent recipient), confirming send-max is intentionally opting
    // out rather than the case being ineligible.
    assert!(should_downgrade_send_to_legacy_v5(
        Some(TxVersion::V6),
        &proposal_selected_orchard_note_versions(&pass1),
        proposal_has_orchard_payment(&pass1),
    ));

    // The value send-max returns is the V6-ceiling summary. Running the
    // shared downgrade helper here (as the removed code did) would have
    // produced a different, V5-priced result; send-max must return the
    // undowngraded V6 summary instead.
    let v6_summary = summarize_send_max_proposal(&pass1).unwrap();
    let (downgraded, downgraded_version) =
        propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |tx_version| {
            assert_eq!(tx_version, Some(TxVersion::V5));
            // Stand in for a cheaper V5 re-proposal so the two paths differ.
            Ok(fabricated_shielded_spend_proposal(&[
                orchard::note::NoteVersion::V2,
                orchard::note::NoteVersion::V2,
            ]))
        });
    // Sanity: the downgrade path really does diverge from what send-max
    // returns (different selection/amount), so the assertion below is
    // meaningful rather than vacuous.
    assert_eq!(downgraded_version, Some(TxVersion::V5));
    assert_ne!(
        summarize_send_max_proposal(&downgraded)
            .unwrap()
            .amount_zatoshi,
        v6_summary.amount_zatoshi,
    );
}

#[test]
fn keystone_transparent_shielding_pczt_targets_ironwood() {
    crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let network = WalletNetwork::Regtest;
    let mnemonic = crate::wallet::keys::generate_mnemonic();
    let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
    let (account_uuid, _) =
        crate::wallet::keys::init_db_and_create_account(db_path, network, &seed, Some(1), "shield")
            .unwrap();
    let account_id = parse_account_uuid(&account_uuid).unwrap();

    let mut db = open_wallet_db(db_path, network).unwrap();
    let tip = BlockHeight::from_u32(120);
    db.update_chain_tip(tip).unwrap();
    // Shielding now derives the target/anchor heights from scan progress
    // (shard-tree checkpoints) rather than the raw chain tip; checkpoint
    // the empty Orchard tree at the tip to stand in for a scan.
    {
        type CheckpointError = WalletError<
            (),
            commitment_tree::Error,
            (),
            <ConservativeZip317FeeRule as FeeRule>::Error,
            (),
            ReceivedNoteId,
        >;
        let result: Result<_, CheckpointError> =
            db.with_sapling_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
        assert!(result.unwrap(), "checkpointing the empty Sapling tree");
        let result: Result<_, CheckpointError> =
            db.with_orchard_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
        assert!(result.unwrap(), "checkpointing the empty Orchard tree");
        let result: Result<_, CheckpointError> =
            db.with_ironwood_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
        result.unwrap();
    }

    let ua_request = zcash_keys::keys::UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
    )
    .unwrap();
    // Use the account's existing default address (no allocation) so the test
    // setup doesn't trip the transparent gap limit on a fresh account.
    let ua = db
        .get_last_generated_address_matching(account_id, ua_request)
        .unwrap()
        .unwrap();
    let taddr = *ua.transparent().unwrap();
    let outpoint = OutPoint::new([42u8; 32], 0);
    let txout = TxOut::new(Zatoshis::const_from_u64(1_000_000), taddr.script().into());
    let utxo =
        WalletTransparentOutput::from_parts(outpoint, txout, Some(tip), None, None, None).unwrap();
    db.put_received_transparent_utxo(&utxo).unwrap();
    drop(db);

    let result = create_shield_transparent_pczt(db_path, network, &account_uuid).unwrap();
    let pczt = pczt::Pczt::parse(&result.pczt_bytes).unwrap();

    assert_eq!(
        *pczt.global().tx_version(),
        zcash_protocol::constants::V6_TX_VERSION
    );
    assert!(!pczt.ironwood().actions().is_empty());
    assert!(pczt.orchard().actions().is_empty());
    assert_eq!(result.needs_sapling_params, false);
    assert!(result.fee_zatoshi > 0);
    assert!(result.shielded_zatoshi > 0);
}

#[test]
fn conservative_zip317_fee_rule_clamps_known_transparent_inputs_to_p2pkh_size() {
    let network = WalletNetwork::Regtest;
    let height = BlockHeight::from_u32(1_000);
    let undersized_inputs = vec![
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
    ];
    let standard_inputs = vec![
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
        TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
    ];

    let conservative_fee = ConservativeZip317FeeRule
        .fee_required(
            &network,
            height,
            undersized_inputs.clone(),
            std::iter::empty::<usize>(),
            0,
            0,
            0,
            0,
        )
        .unwrap();
    let standard_p2pkh_fee = StandardFeeRule::Zip317
        .fee_required(
            &network,
            height,
            standard_inputs,
            std::iter::empty::<usize>(),
            0,
            0,
            0,
            0,
        )
        .unwrap();
    let standard_undersized_fee = StandardFeeRule::Zip317
        .fee_required(
            &network,
            height,
            undersized_inputs,
            std::iter::empty::<usize>(),
            0,
            0,
            0,
            0,
        )
        .unwrap();

    assert_eq!(conservative_fee, standard_p2pkh_fee);
    assert_eq!(u64::from(conservative_fee), 15_000);
    assert_eq!(u64::from(standard_undersized_fee), 10_000);
}

#[test]
fn transparent_recipient_send_max_proposal_spends_shielded_notes() {
    let network = WalletNetwork::Regtest;
    let input_value = 60_000u64;
    let spending_key = sapling_crypto::zip32::ExtendedSpendingKey::master(&[7u8; 32]);
    let (_, recipient) = spending_key.default_address();
    let note = sapling_crypto::Note::from_parts(
        recipient,
        sapling_crypto::value::NoteValue::from_raw(input_value),
        sapling_crypto::Rseed::AfterZip212([3u8; 32]),
    );
    let received_note = ReceivedNote::from_parts(
        1u32,
        TxId::from_bytes([4u8; 32]),
        0,
        note,
        zip32::Scope::External,
        Position::from(0u64),
        Some(BlockHeight::from_u32(20)),
        None,
    );
    let recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

    let proposal = build_transparent_recipient_send_max_proposal_from_notes(
        network,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        BlockHeight::from_u32(900),
        recipient,
        None,
        ReceivedNotes::new(vec![received_note], vec![], vec![]),
        ConservativeZip317FeeRule,
    )
    .expect("transparent-recipient send-max should build from shielded notes");

    let step = proposal.steps().iter().next().unwrap();
    assert_eq!(step.payment_pools().get(&0), Some(&PoolType::TRANSPARENT));
    assert_eq!(step.transparent_inputs().len(), 0);
    assert_eq!(step.shielded_inputs().unwrap().notes().len(), 1);

    let estimate = summarize_send_max_proposal(&proposal).unwrap();
    assert_eq!(estimate.amount_zatoshi + estimate.fee_zatoshi, input_value);
    assert!(estimate.fee_zatoshi > 0);
    assert!(estimate.needs_sapling_params);
}

#[test]
fn transparent_recipient_send_max_supports_ironwood_only_inputs() {
    let network = WalletNetwork::Regtest;
    let input_value = 100_000u64;
    let spending_key = orchard::keys::SpendingKey::from_bytes([17; 32]).unwrap();
    let fvk = orchard::keys::FullViewingKey::from(&spending_key);
    let recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
    let rho = orchard::note::Rho::from_bytes(&[3; 32]).unwrap();
    let rseed = (0u8..=255)
        .find_map(|byte| orchard::note::RandomSeed::from_bytes([byte; 32], &rho).into_option())
        .unwrap();
    let note = orchard::Note::from_parts(
        recipient,
        orchard::value::NoteValue::from_raw(input_value),
        rho,
        rseed,
        orchard::note::NoteVersion::V3,
    )
    .unwrap();
    let received_note = ReceivedNote::from_parts(
        1u32,
        TxId::from_bytes([5u8; 32]),
        0,
        note,
        zip32::Scope::External,
        Position::from(0u64),
        Some(BlockHeight::from_u32(20)),
        None,
    );
    let transparent_recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

    let proposal = build_transparent_recipient_send_max_proposal_from_notes(
        network,
        TargetHeight::from(BlockHeight::from_u32(1_000)),
        BlockHeight::from_u32(900),
        transparent_recipient,
        None,
        ReceivedNotes::new(vec![], vec![], vec![received_note]),
        ConservativeZip317FeeRule,
    )
    .expect("transparent-recipient send-max should build from Ironwood notes");

    let step = proposal.steps().iter().next().unwrap();
    assert_eq!(step.payment_pools().get(&0), Some(&PoolType::TRANSPARENT));
    assert_eq!(step.shielded_inputs().unwrap().notes().len(), 1);
    let estimate = summarize_send_max_proposal(&proposal).unwrap();
    assert_eq!(estimate.amount_zatoshi + estimate.fee_zatoshi, input_value);
    assert!(!estimate.needs_sapling_params);
}

#[test]
#[ignore = "slow librustzcash transaction-construction regression (~100s); run explicitly when touching shielding transaction construction"]
fn many_utxo_shielding_builds_with_conservative_zip317_fee() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let network = WalletNetwork::Regtest;
    let mnemonic = crate::wallet::keys::generate_mnemonic();
    let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
    let (account_uuid, _) =
        crate::wallet::keys::init_db_and_create_account(db_path, network, &seed, Some(1), "repro")
            .unwrap();
    let account_id = parse_account_uuid(&account_uuid).unwrap();

    let mut db = open_wallet_db(db_path, network).unwrap();
    let tip = BlockHeight::from_u32(1_000);
    db.update_chain_tip(tip).unwrap();

    let ua_request = zcash_keys::keys::UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
    )
    .unwrap();
    // Use the account's existing default address (no allocation) so the test
    // setup doesn't trip the transparent gap limit on a fresh account.
    let ua = db
        .get_last_generated_address_matching(account_id, ua_request)
        .unwrap()
        .unwrap();
    let taddr = *ua.transparent().unwrap();
    let value = Zatoshis::const_from_u64(1_000_000);

    for i in 0..322u32 {
        let mut txid = [0u8; 32];
        txid[..4].copy_from_slice(&i.to_le_bytes());
        txid[4..8].copy_from_slice(&0xfeed_beefu32.to_le_bytes());
        let outpoint = OutPoint::new(txid, 0);
        let txout = TxOut::new(value, taddr.script().into());
        let utxo =
            WalletTransparentOutput::from_parts(outpoint, txout, Some(tip), None, None, None)
                .unwrap();
        db.put_received_transparent_utxo(&utxo).unwrap();
    }

    let shielding_threshold = Zatoshis::const_from_u64(SHIELDING_THRESHOLD_ZATOSHI);
    let (proposal, selected_value) =
        build_shielding_proposal(&mut db, network, account_id, shielding_threshold).unwrap();
    assert_eq!(u64::from(selected_value), 322_000_000);

    let seed = SecretVec::new(seed.expose_secret().to_vec());
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32::AccountId::ZERO)
        .unwrap();
    let spend_prover = NoOpSpendProver;
    let output_prover = NoOpOutputProver;
    let txids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
        &mut db,
        &network,
        &spend_prover,
        &output_prover,
        &wallet::SpendingKeys::from_unified_spending_key(usk),
        OvkPolicy::Sender,
        &proposal,
        None,
    )
    .expect("many-UTXO shielding should build without a fee/change mismatch");
    let change_values = proposal
        .steps()
        .iter()
        .flat_map(|step| step.balance().proposed_change().iter())
        .map(|change| u64::from(change.value()).to_string())
        .collect::<Vec<_>>()
        .join(",");
    eprintln!(
            "repro fixed: utxos=322 selected={} proposal_fee={} proposed_shielded={} change_values=[{}] txids={:?}",
            u64::from(selected_value),
            proposal_fee_zatoshi(&proposal),
            proposal_shielded_zatoshi(&proposal),
            change_values,
            txids,
        );

    assert_eq!(txids.len(), 1);
    assert_eq!(proposal_fee_zatoshi(&proposal), 1_630_000);
    assert_eq!(proposal_shielded_zatoshi(&proposal), 320_370_000);
}

#[test]
fn selects_fragmented_non_ephemeral_sources_by_aggregate_threshold() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(60_000, TransparentKeyScope::EXTERNAL));
    receivers.insert(taddr(2), receiver(50_000, TransparentKeyScope::INTERNAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

    assert_eq!(addresses.len(), 2);
    assert_eq!(u64::from(total), 110_000);
}

#[test]
fn rejects_non_ephemeral_sources_below_aggregate_threshold() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(40_000, TransparentKeyScope::EXTERNAL));
    receivers.insert(taddr(2), receiver(50_000, TransparentKeyScope::INTERNAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let err = select_shielding_sources(receivers, threshold).unwrap_err();

    assert!(err.contains("No transparent funds available"));
}

#[test]
fn selects_largest_ephemeral_source_only() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(110_000, TransparentKeyScope::EPHEMERAL));
    receivers.insert(taddr(2), receiver(150_000, TransparentKeyScope::EPHEMERAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

    assert_eq!(addresses, vec![taddr(2)]);
    assert_eq!(u64::from(total), 150_000);
}

#[test]
fn prefers_non_ephemeral_sources_over_ephemeral_sources() {
    let mut receivers = HashMap::new();
    receivers.insert(taddr(1), receiver(140_000, TransparentKeyScope::EPHEMERAL));
    receivers.insert(taddr(2), receiver(120_000, TransparentKeyScope::EXTERNAL));

    let threshold = Zatoshis::from_u64(100_000).unwrap();
    let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

    assert_eq!(addresses, vec![taddr(2)]);
    assert_eq!(u64::from(total), 120_000);
}
