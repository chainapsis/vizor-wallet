use std::sync::Arc;

use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use voting_crypto_deps::pasta_curves::group::ff::PrimeField;

use crate::backend::{orchard, pasta_curves, zcash_client_sqlite, zcash_keys};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_protocol::consensus::Parameters;
use zcash_voting::delegate::ResolveDelegationLwdParams;
use zcash_voting::prelude::{
    export_delegation_capability, gather_delegation_lwd_inputs, import_delegation_capability,
    prepare_delegation_bundle as prepare_bundle_state,
    prepare_delegation_bundle_for_target as prepare_target_bundle_state, spend_auth_signature,
    DelegationCapabilityDigest, DelegationSigningRequest, DelegationSubmission,
    ExportedDelegationCapability, ImportDelegationCapabilityParams, KeystoneSigningRequest,
    Network, NoopProgressReporter, PrepareDelegationBundleForTargetParams,
    PrepareDelegationBundleParams, PreparedDelegationBundle, PreparedDelegationReport,
    PreparedSigner, RoundBoundVotingHotkeyTarget, VotingDb, VotingHotkey, VotingHotkeyTargetV1,
};
use zcash_voting::wire::PirLayout;
use zcash_voting::{
    connect_pir_blocking, BundlePolicy, HyperTransport, PirClientBlocking, VotingRoundParams,
};
use zip32::{fingerprint::SeedFingerprint, AccountId};

/// Inputs for preparing one reusable delegation bundle context.
///
/// `round_params`, `round_name`, and `lightwalletd_url` identify the round and
/// chain anchor. The wallet database supplies eligible notes and account keys
/// for `account_uuid`.
pub struct PrepareRequest<'a> {
    pub account_uuid: &'a str,
    pub lightwalletd_url: &'a str,
    pub network: Network,
    pub round_params: VotingRoundParams,
    pub round_name: &'a str,
    pub voting_hotkey: &'a VotingHotkey,
    pub session_json: Option<&'a str>,
    pub bundle_index: u32,
    pub bundle_policy: BundlePolicy,
}

/// Funds controller inputs for preparing one bundle for a voter's public target.
pub struct PrepareForTargetRequest<'a> {
    pub account_uuid: &'a str,
    pub lightwalletd_url: &'a str,
    pub network: Network,
    pub round_params: VotingRoundParams,
    pub round_name: &'a str,
    pub voting_target: &'a RoundBoundVotingHotkeyTarget,
    pub session_json: Option<&'a str>,
    pub bundle_index: u32,
    pub bundle_policy: BundlePolicy,
}

/// Encodes the public target that the voter sends to the funds controller.
///
/// The voter retains the hotkey secret. Only these canonical, round-bound JSON
/// bytes cross the boundary.
pub fn encode_public_voting_target(
    voting_hotkey: &VotingHotkey,
    vote_chain_id: &str,
    round_params: &VotingRoundParams,
) -> Result<Vec<u8>> {
    let target = voting_hotkey.delegation_target();
    let network = match target.network() {
        Network::Mainnet => "mainnet",
        Network::Testnet => "testnet",
        Network::Regtest => "regtest",
    };
    let target_v1 = VotingHotkeyTargetV1 {
        format_version: 1,
        vote_chain_id: vote_chain_id.to_string(),
        network: network.to_string(),
        vote_round_id: round_params.vote_round_id.clone(),
        address_index: target.address_index(),
        raw_orchard_address: BASE64_STANDARD.encode(target.raw_orchard_address()),
    };

    target_v1
        .validate_for(vote_chain_id, target.network(), round_params)
        .context("validate public voting target")?;
    target_v1
        .to_json()
        .map(String::into_bytes)
        .context("encode public voting target")
}

/// Parses and independently validates the target on the funds controller.
///
/// The returned opaque value is local to the controller and is the value passed
/// to [`prepare_delegation_bundle_for_public_target`].
pub fn validate_public_voting_target(
    target_json: &[u8],
    expected_chain_id: &str,
    expected_network: Network,
    expected_round_params: &VotingRoundParams,
) -> Result<RoundBoundVotingHotkeyTarget> {
    let target_json = std::str::from_utf8(target_json).context("decode public target UTF-8")?;
    VotingHotkeyTargetV1::from_json(target_json)
        .context("parse public voting target")?
        .validate_for(expected_chain_id, expected_network, expected_round_params)
        .context("validate public voting target context")
}

/// Resolves lightwalletd and wallet inputs for later delegation operations.
///
/// This is the only example entry point that touches lightwalletd. The returned
/// context is plain data that can be reused by precompute, software signing, and
/// Keystone flows.
///
/// # Errors
///
/// Returns an error if lightwalletd inputs cannot be resolved, wallet note
/// selection fails, the wallet is not synced to the snapshot, or bundle rows
/// cannot be created or validated.
pub async fn prepare_delegation_bundle<C, P, CL, R>(
    voting_db: &VotingDb,
    wallet_db: &zcash_client_sqlite::WalletDb<C, P, CL, R>,
    request: PrepareRequest<'_>,
) -> Result<PreparedDelegationBundle>
where
    C: std::borrow::Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let lwd_inputs = gather_delegation_lwd_inputs(ResolveDelegationLwdParams {
        lightwalletd_url: request.lightwalletd_url,
        network: request.network,
        round_params: request.round_params,
        round_name: request.round_name,
    })
    .await
    .context("gather delegation lightwalletd inputs")?;

    prepare_bundle_state(
        voting_db,
        wallet_db,
        PrepareDelegationBundleParams {
            lwd: lwd_inputs,
            session_json: request.session_json,
            account_uuid: request.account_uuid,
            voting_hotkey: request.voting_hotkey,
            bundle_index: request.bundle_index,
            bundle_policy: request.bundle_policy,
        },
    )
    .context("prepare delegation bundle with witnesses")
}

/// Prepares a funds controller delegation bundle for a voter-owned hotkey.
///
/// The request contains only the validated public target. The voter retains the
/// voting hotkey secret, while the funds controller retains this target with
/// its durable delegation job until the round closes.
pub async fn prepare_delegation_bundle_for_public_target<C, P, CL, R>(
    voting_db: &VotingDb,
    wallet_db: &zcash_client_sqlite::WalletDb<C, P, CL, R>,
    request: PrepareForTargetRequest<'_>,
) -> Result<PreparedDelegationBundle>
where
    C: std::borrow::Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let lwd_inputs = gather_delegation_lwd_inputs(ResolveDelegationLwdParams {
        lightwalletd_url: request.lightwalletd_url,
        network: request.network,
        round_params: request.round_params,
        round_name: request.round_name,
    })
    .await
    .context("gather public target delegation lightwalletd inputs")?;

    prepare_target_bundle_state(
        voting_db,
        wallet_db,
        PrepareDelegationBundleForTargetParams {
            lwd: lwd_inputs,
            session_json: request.session_json,
            account_uuid: request.account_uuid,
            voting_target: request.voting_target,
            bundle_index: request.bundle_index,
            bundle_policy: request.bundle_policy,
        },
    )
    .context("prepare delegation bundle for public target")
}

/// Exports the canonical package a funds controller stores before broadcast.
///
/// `signed_delegation_txs` are the exact vote-chain transaction bytes retained
/// in the funds controller's durable outbox. It may deliver the package while
/// broadcasting. The returned opaque value binds the canonical bytes to the
/// typed digest used to verify the voter's delivery acknowledgement.
pub fn export_delegation_capability_package(
    voting_db: &VotingDb,
    voting_target: &RoundBoundVotingHotkeyTarget,
    signed_delegation_txs: &[Vec<u8>],
) -> Result<ExportedDelegationCapability> {
    export_delegation_capability(voting_db, voting_target, signed_delegation_txs)
        .context("export delegation capability")
}

/// Validates and atomically imports a package for a voter hotkey.
///
/// Return this digest only after the call succeeds durably. The funds controller
/// compares it to its outbox digest as a delivery receipt and keeps redelivering
/// the same package through round close when needed.
pub fn import_delegation_capability_package(
    voting_db: &VotingDb,
    capability_json: &[u8],
    voting_hotkey: &VotingHotkey,
    expected_chain_id: &str,
    expected_network: Network,
    expected_round_params: &VotingRoundParams,
    session_json: Option<&str>,
) -> Result<DelegationCapabilityDigest> {
    import_delegation_capability(
        voting_db,
        capability_json,
        ImportDelegationCapabilityParams {
            voting_hotkey,
            expected_chain_id,
            expected_network,
            expected_round_params,
            session_json,
        },
    )
    .context("import delegation capability")
}

/// Precomputes persistent artifacts needed to later prove one delegation bundle.
///
/// This stores note witnesses and PIR-backed nullifier data for the prepared
/// bundle. It does not build a PCZT, prove, sign, or submit a delegation.
///
/// `pir_layout` is the dynamic config's layout used for the PIR handshake.
/// `pir_server_url` is the selected exact-height snapshot endpoint (typically
/// after snapshot selection). Endpoint membership against the resolved config
/// is the caller's responsibility when using these example helpers.
///
/// # Errors
///
/// Returns an error if the layout handshake fails, the PIR server cannot be
/// reached, witnesses cannot be generated, or precompute state cannot be
/// persisted.
pub fn precompute_delegation_bundle<C, P, CL, R>(
    voting_db: &VotingDb,
    wallet_db: &zcash_client_sqlite::WalletDb<C, P, CL, R>,
    prepared: &PreparedDelegationBundle,
    pir_layout: PirLayout,
    pir_server_url: &str,
) -> Result<PreparedDelegationReport>
where
    C: std::borrow::Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let pir_client = connect_pir(pir_layout, pir_server_url)?;
    prepared
        .precompute(voting_db, wallet_db, &pir_client)
        .context("precompute delegation bundle")
}

/// Proves one precomputed delegation bundle and signs it in wallet-owned code.
///
/// The returned `DelegationSubmission` contains the chain-ready fields for the
/// selected bundle. The function expects the target bundle's witnesses,
/// padded-note secrets, and PIR rows to have been warmed by
/// `precompute_delegation_bundle`.
///
/// # Errors
///
/// Returns an error if setup/proof generation fails, PIR access fails, signing
/// fails, or submission fields cannot be assembled.
pub fn prove_and_submit_delegation_bundle(
    voting_db: &VotingDb,
    prepared: &PreparedDelegationBundle,
    pir_layout: PirLayout,
    pir_server_url: &str,
    seed: &[u8],
) -> Result<DelegationSubmission> {
    let progress = NoopProgressReporter;
    let delegation_setup = prepared
        .setup(voting_db, &progress)
        .context("setup delegation bundle")?;
    let signing_request = prepared
        .signing_request(voting_db)
        .context("load delegation signing request")?;
    let (sig, sighash) = example_sign_delegation_request(seed, signing_request)?;

    let pir_client = connect_pir(pir_layout, pir_server_url)?;
    prepared
        .prove(voting_db, &pir_client, &progress)
        .context("prove delegation bundle")?;

    prepared
        .signed_bundle(
            voting_db,
            delegation_setup.pczt_bytes,
            PreparedSigner::signature(sig, sighash),
        )
        .map(|bundle| bundle.submission)
        .context("assemble signed delegation submission")
}

/// Builds TX1, the redacted Keystone signing transaction for one bundle.
///
/// TX1 is a consensus-shaped Zcash PCZT used to obtain a ZIP-244 SpendAuth
/// signature. It is not the vote-chain delegation submission and must never be
/// broadcast to the Zcash network. The returned request includes signer-facing
/// redacted PCZT bytes, display metadata, bundle weights, and the local setup
/// needed to verify and submit the later signed PCZT.
///
/// # Errors
///
/// Returns an error if PCZT setup fails, redaction fails, or bundle weight
/// cannot be calculated.
pub fn build_keystone_delegation_request(
    voting_db: &VotingDb,
    prepared: &PreparedDelegationBundle,
) -> Result<KeystoneSigningRequest> {
    // Build the full governance PCZT. The signer only receives the redacted
    // bytes, but the complete setup is needed for later proof/submission checks.
    let progress = NoopProgressReporter;
    prepared
        .keystone_request(voting_db, &progress)
        .context("build Keystone delegation request")
}

/// Proves a bundle and assembles a submission from a Keystone-signed PCZT.
///
/// This function does not rebuild the governance PCZT. It extracts Keystone's
/// SpendAuth signature from `signed_pczt_bytes` and pairs it with the original
/// setup sighash from `keystone_request`.
///
/// # Errors
///
/// Returns an error if proof generation fails, PIR access fails, the signature
/// cannot be extracted, or submission fields cannot be assembled.
pub fn prove_and_submit_keystone_delegation_bundle(
    voting_db: &VotingDb,
    prepared: &PreparedDelegationBundle,
    pir_layout: PirLayout,
    pir_server_url: &str,
    keystone_request: &KeystoneSigningRequest,
    signed_pczt_bytes: &[u8],
) -> Result<DelegationSubmission> {
    // Generate the proof using warmed witnesses and PIR rows, without
    // rebuilding the PCZT that Keystone already signed.
    let progress = NoopProgressReporter;
    let pir_client = connect_pir(pir_layout, pir_server_url)?;
    prepared
        .prove(voting_db, &pir_client, &progress)
        .context("prove delegation bundle")?;

    // Pair Keystone's SpendAuth signature with the original setup sighash.
    let action_index = usize::try_from(keystone_request.action_index)
        .context("Keystone action index does not fit usize")?;
    let sig = spend_auth_signature(signed_pczt_bytes, action_index)
        .context("extract Keystone SpendAuth signature")?;
    let signer = PreparedSigner::signature_from_bytes(&sig, &keystone_request.pczt_sighash)
        .context("validate Keystone signature fields")?;

    prepared
        .signed_bundle(voting_db, Vec::new(), signer)
        .map(|bundle| bundle.submission)
        .context("assemble Keystone-signed delegation submission")
}

fn example_sign_delegation_request(
    seed: &[u8],
    request: DelegationSigningRequest,
) -> Result<([u8; 64], [u8; 32])> {
    // This is example-only signing code. Production wallets should keep their
    // own seed storage and signing boundary, then return only the signature.
    // Real wallet integrations should route to the seed identified by
    // request.seed_fingerprint before signing. This example verifies that the
    // already selected seed matches the request.
    let seed_fingerprint = SeedFingerprint::from_seed(seed)
        .ok_or_else(|| anyhow::anyhow!("wallet seed length is not valid for ZIP-32"))?;
    if seed_fingerprint.to_bytes() != request.seed_fingerprint {
        return Err(anyhow::anyhow!(
            "wallet seed fingerprint does not match delegation signing request"
        ));
    }

    let account = AccountId::try_from(request.account_index)
        .map_err(|_| anyhow::anyhow!("invalid account_index {}", request.account_index))?;
    let usk = UnifiedSpendingKey::from_seed(&request.network, seed, account)
        .context("derive account unified spending key")?;
    let sk = *usk.orchard();
    let ask = orchard::keys::SpendAuthorizingKey::from(&sk);
    let alpha = Option::<pasta_curves::pallas::Scalar>::from(
        pasta_curves::pallas::Scalar::from_repr(request.alpha),
    )
    .ok_or_else(|| anyhow::anyhow!("delegation alpha is not a valid Pallas scalar"))?;
    let rsk = ask.randomize(&alpha);
    let mut rng = voting_crypto_deps::rand::rngs::OsRng;
    let sig = rsk.sign(&mut rng, &request.sighash);
    Ok(((&sig).into(), request.sighash))
}

fn connect_pir(pir_layout: PirLayout, pir_server_url: &str) -> Result<PirClientBlocking> {
    connect_pir_blocking(pir_layout, pir_server_url, Arc::new(HyperTransport::new()))
        .context("connect to PIR server")
}
