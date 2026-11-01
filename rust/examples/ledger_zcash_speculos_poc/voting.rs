//! Synthetic eligible notes, but real SDK delegation setup and signing requests.
//! Do not replace these with a hand-built self-transfer: Ledger must review the
//! SDK's zero-value output to a separate voting hotkey and its authorization memo.

use orchard::{
    keys::Scope,
    note::{NoteVersion, RandomSeed, Rho},
    value::NoteValue,
    Note,
};
use rand::{rngs::OsRng, RngCore};
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_voting::{
    delegate::{
        DelegationKeys, KeystoneSigningRequest, LightwalletdBranchIdProvider,
        PreparedDelegationBundle,
    },
    round::{bundle_notes_for_index_for_round, VotingDb},
    Network, NoopProgressReporter, NoteInfo, VotingHotkey, VotingRoundParams, BUNDLE_NOTE_SLOTS,
};

pub(super) fn signing_requests(
    ufvk: &str,
    seed_fingerprint: &[u8],
) -> Result<Vec<KeystoneSigningRequest>, String> {
    build_requests(ufvk, seed_fingerprint)
        .map_err(|error| format!("Build SDK voting requests: {error}"))
}

fn build_requests(
    ufvk: &str,
    seed_fingerprint: &[u8],
) -> Result<Vec<KeystoneSigningRequest>, Box<dyn std::error::Error>> {
    let network = Network::Mainnet;
    let ufvk = UnifiedFullViewingKey::decode(&network, ufvk)?;
    let fvk = ufvk.orchard().ok_or("Speculos UFVK has no Orchard FVK")?;
    let mut notes = Vec::new();
    for position in 0..2 * BUNDLE_NOTE_SLOTS {
        let note = synthetic_note(fvk, position as u64)?;
        notes.push(NoteInfo::from_orchard_note(
            &note,
            position as u64,
            Scope::External,
            &ufvk,
            &network,
        )?);
    }
    let params = VotingRoundParams {
        vote_round_id: "01".repeat(32),
        // The SDK votes only on NU6.3 snapshots, so this sits before NU7.
        snapshot_height: 3_500_000,
        ea_pk: vec![0xEA; 32],
        nc_root: vec![0xAA; 32],
        nullifier_imt_root: vec![0xBB; 32],
    };
    let db = VotingDb::open(":memory:")?;
    db.set_wallet_id("speculos-ledger-voting");
    db.init_round(network, &params, None)?;
    let layout = db.ensure_bundles(&params.vote_round_id, &notes)?;
    if layout.bundle_count != 2 {
        return Err("SDK fixture must produce two delegation bundles".into());
    }
    let hotkey = VotingHotkey::from_stored_secret(&[0x43; 64], network)?;
    let round_name = "Ledger voting E2E";
    let keys = DelegationKeys::with_voting_hotkey(
        fvk.to_bytes().to_vec(),
        &hotkey,
        seed_fingerprint.try_into()?,
        0,
        round_name.into(),
    )?
    .with_ledger_output_review();
    (0..layout.bundle_count)
        .map(|bundle_index| {
            let prepared = PreparedDelegationBundle {
                round_id: params.vote_round_id.clone(),
                round_params: params.clone(),
                bundle_index,
                layout: layout.clone(),
                bundle_note_infos: bundle_notes_for_index_for_round(
                    &notes,
                    &layout,
                    bundle_index,
                    &db,
                    &params.vote_round_id,
                )?,
                delegation_keys: keys.clone(),
                branch_id_provider: LightwalletdBranchIdProvider::for_height(
                    network,
                    params.snapshot_height,
                )?,
                anchor_tree_state_bytes: Vec::new(),
                network,
                round_name: round_name.into(),
            };
            // This performs the same SDK setup, persistence, memo extraction and
            // redaction as the production hardware-signing boundary. Proof/PIR and
            // chain submission are deliberately outside this device signing test.
            let request = prepared.keystone_request(&db, &NoopProgressReporter)?;
            if request.display_memo.is_empty()
                || request.bundle_count != 2
                || request.bundle_index != bundle_index
            {
                return Err("SDK signing request lost its voting context".into());
            }
            let pczt = pczt::Pczt::parse(&request.pczt_bytes)
                .map_err(|error| format!("Parse SDK governance PCZT: {error:?}"))?;
            let actions = pczt.ironwood().actions();
            if actions.len() != 1 || request.action_index != 0 {
                return Err("SDK fixture must be an unpadded governance action".into());
            }
            let output = actions[0].output();
            if output.value() != &Some(0)
                || output.recipient()
                    == &Some(fvk.address_at(0u32, Scope::Internal).to_raw_address_bytes())
                || output.recipient()
                    == &Some(fvk.address_at(0u32, Scope::External).to_raw_address_bytes())
            {
                return Err("SDK fixture must pay zero to a separate voting hotkey".into());
            }
            Ok(request)
        })
        .collect()
}

/// A distinct note to the account's first external address. Only public
/// constructors are used: a small integer is a canonical rho, and a random
/// seed is redrawn until it is valid for that rho.
fn synthetic_note(
    fvk: &orchard::keys::FullViewingKey,
    position: u64,
) -> Result<Note, Box<dyn std::error::Error>> {
    let mut rho_bytes = [0u8; 32];
    rho_bytes[..8].copy_from_slice(&(position + 1).to_le_bytes());
    let rho = Option::<Rho>::from(Rho::from_bytes(&rho_bytes)).ok_or("invalid synthetic rho")?;
    loop {
        let mut seed = [0u8; 32];
        OsRng.fill_bytes(&mut seed);
        let Some(rseed) = Option::<RandomSeed>::from(RandomSeed::from_bytes(seed, &rho)) else {
            continue;
        };
        if let Some(note) = Option::<Note>::from(Note::from_parts(
            fvk.address_at(0u32, Scope::External),
            NoteValue::from_raw(13_000_000),
            rho,
            rseed,
            NoteVersion::V3,
        )) {
            return Ok(note);
        }
    }
}
