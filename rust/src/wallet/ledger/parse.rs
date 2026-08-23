//! Converts Vizor's canonical PCZT bytes into the compact fields consumed by
//! the Ledger Zcash app's PCZT APDUs.

use std::collections::BTreeMap;

use ff::PrimeField;
use orchard::{bundle::BundleVersion, note::NoteVersion, ValuePool};
use pczt::{
    roles::verifier::{OrchardError, TransparentError, Verifier},
    Pczt,
};
use zcash_primitives::transaction::components::orchard::bundle_version_for_branch;
use zcash_protocol::consensus::BranchId;
use zcash_script::script::Evaluable;

const V6_TX_VERSION: u32 = 6;

#[derive(Debug, Clone)]
pub(super) struct Bip32Derivation {
    pub signing_path: Vec<u32>,
    pub pubkey: [u8; 33],
    pub seed_fingerprint: [u8; 32],
}

#[derive(Debug, Clone)]
pub(super) struct Global {
    pub tx_version: u32,
    pub version_group_id: u32,
    pub consensus_branch_id: u32,
    pub fallback_lock_time: Option<u32>,
    pub expiry_height: u32,
    pub coin_type: u32,
    pub tx_modifiable: u8,
}

#[derive(Debug, Clone)]
pub(super) struct TransparentOutput {
    pub value: u64,
    pub script_pubkey: Vec<u8>,
    pub derivation: Option<Bip32Derivation>,
}

#[derive(Debug, Clone)]
pub(super) struct TransparentInput {
    pub prevout_txid: [u8; 32],
    pub prevout_index: u32,
    pub sequence: Option<u32>,
    pub value: u64,
    pub script_pubkey: Vec<u8>,
    pub sighash_type: u8,
    pub derivation: Bip32Derivation,
}

#[derive(Debug, Clone)]
pub(super) struct ShieldedAction {
    pub cv_net: [u8; 32],
    pub nullifier: [u8; 32],
    pub rk: [u8; 32],
    pub spend_recipient: [u8; 43],
    pub spend_value: u64,
    pub spend_rho: [u8; 32],
    pub spend_rseed: [u8; 32],
    pub alpha: [u8; 32],
    pub signing_path: Vec<u32>,
    pub seed_fingerprint: [u8; 32],
    pub cmx: [u8; 32],
    pub ephemeral_key: [u8; 32],
    pub enc_ciphertext: Vec<u8>,
    pub out_ciphertext: Vec<u8>,
    pub recipient: [u8; 43],
    pub value: u64,
    pub rseed: [u8; 32],
    pub rcv: [u8; 32],
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ShieldedDerivation {
    signing_path: Vec<u32>,
    seed_fingerprint: [u8; 32],
}

#[derive(Debug, Clone)]
pub(super) struct ShieldedBundle {
    pub actions: Vec<ShieldedAction>,
    pub flags: u8,
    pub value_balance: i128,
    pub anchor: [u8; 32],
}

#[derive(Debug, Clone)]
pub(super) struct IronwoodAction {
    pub action: ShieldedAction,
    pub note_plaintext_version: u8,
}

#[derive(Debug, Clone)]
pub(super) struct IronwoodBundle {
    pub actions: Vec<IronwoodAction>,
    pub flags: u8,
    pub value_balance: i128,
    pub anchor: [u8; 32],
}

#[derive(Debug, Clone)]
pub(super) struct ParsedPczt {
    pub global: Global,
    pub transparent_inputs: Vec<TransparentInput>,
    pub transparent_outputs: Vec<TransparentOutput>,
    pub orchard_bundle: Option<ShieldedBundle>,
    pub ironwood_bundle: Option<IronwoodBundle>,
}

pub(super) fn parse_pczt(bytes: &[u8]) -> Result<ParsedPczt, String> {
    let pczt = Pczt::parse(bytes).map_err(|e| format!("PCZT parse failed: {e:?}"))?;

    if !pczt.sapling().spends().is_empty() || !pczt.sapling().outputs().is_empty() {
        return Err("Ledger PoC does not support Sapling spends or outputs".into());
    }

    let global = parse_global(&pczt)?;
    let branch = BranchId::try_from(global.consensus_branch_id).map_err(|_| {
        format!(
            "Unrecognized consensus branch id {:#010x}",
            global.consensus_branch_id
        )
    })?;
    let shielded_derivation =
        fallback_shielded_derivation(&pczt, global.coin_type, global.tx_version >= V6_TX_VERSION)?;

    let mut transparent_inputs = Vec::new();
    let mut transparent_outputs = Vec::new();
    let mut orchard_bundle = None;
    let mut ironwood_bundle = None;

    let verifier = Verifier::new(pczt)
        .with_transparent::<String, _>(|bundle| {
            for input in bundle.inputs() {
                transparent_inputs
                    .push(convert_transparent_input(input).map_err(TransparentError::Custom)?);
            }
            for output in bundle.outputs() {
                transparent_outputs
                    .push(convert_transparent_output(output).map_err(TransparentError::Custom)?);
            }
            Ok(())
        })
        .map_err(map_transparent_error)?;

    let verifier = verifier
        .with_orchard::<String, _>(|bundle| {
            orchard_bundle = convert_shielded_bundle(
                bundle,
                branch,
                ValuePool::Orchard,
                shielded_derivation.as_ref(),
            )
            .map_err(OrchardError::Custom)?;
            Ok(())
        })
        .map_err(|e| map_orchard_error("Orchard", e))?;

    if global.tx_version >= V6_TX_VERSION {
        verifier
            .with_ironwood::<String, _>(|bundle| {
                ironwood_bundle =
                    convert_ironwood_bundle(bundle, branch, shielded_derivation.as_ref())
                        .map_err(OrchardError::Custom)?;
                Ok(())
            })
            .map_err(|e| map_orchard_error("Ironwood", e))?;
    }

    Ok(ParsedPczt {
        global,
        transparent_inputs,
        transparent_outputs,
        orchard_bundle,
        ironwood_bundle,
    })
}

fn convert_transparent_input(input: &transparent::pczt::Input) -> Result<TransparentInput, String> {
    let prevout_txid = (*input.prevout_txid()).into();
    let sighash_type = input.sighash_type().encode();
    if sighash_type != 0x01 {
        return Err(format!(
            "Ledger supports only SIGHASH_ALL (0x01) for transparent inputs; found {sighash_type:#04x}"
        ));
    }

    Ok(TransparentInput {
        prevout_txid,
        prevout_index: *input.prevout_index(),
        sequence: *input.sequence(),
        value: input.value().into_u64(),
        script_pubkey: input.script_pubkey().to_bytes(),
        sighash_type,
        derivation: required_single_derivation(input.bip32_derivation())?,
    })
}

fn parse_global(pczt: &Pczt) -> Result<Global, String> {
    let global = pczt.global();
    let json =
        serde_json::to_value(global).map_err(|e| format!("Serialize PCZT global fields: {e}"))?;

    let read_u32 = |name: &str| {
        json.get(name)
            .and_then(serde_json::Value::as_u64)
            .and_then(|value| u32::try_from(value).ok())
            .ok_or_else(|| format!("PCZT global.{name} is missing or invalid"))
    };

    let fallback_lock_time = match json.get("fallback_lock_time") {
        None | Some(serde_json::Value::Null) => None,
        Some(value) => Some(
            value
                .as_u64()
                .and_then(|value| u32::try_from(value).ok())
                .ok_or("PCZT global.fallback_lock_time is invalid")?,
        ),
    };

    let tx_modifiable = json
        .get("tx_modifiable")
        .and_then(serde_json::Value::as_u64)
        .and_then(|value| u8::try_from(value).ok())
        .ok_or("PCZT global.tx_modifiable is missing or invalid")?;

    Ok(Global {
        tx_version: *global.tx_version(),
        version_group_id: *global.version_group_id(),
        consensus_branch_id: *global.consensus_branch_id(),
        fallback_lock_time,
        expiry_height: *global.expiry_height(),
        coin_type: read_u32("coin_type")?,
        tx_modifiable,
    })
}

fn convert_transparent_output(
    output: &transparent::pczt::Output,
) -> Result<TransparentOutput, String> {
    Ok(TransparentOutput {
        value: output.value().into_u64(),
        script_pubkey: output.script_pubkey().to_bytes(),
        derivation: single_derivation(output.bip32_derivation())?,
    })
}

fn single_derivation(
    map: &BTreeMap<[u8; 33], transparent::pczt::Bip32Derivation>,
) -> Result<Option<Bip32Derivation>, String> {
    match map.len() {
        0 => Ok(None),
        1 => {
            let (pubkey, derivation) = map.iter().next().expect("one derivation");
            convert_derivation(pubkey, derivation).map(Some)
        }
        count => Err(format!(
            "Ledger supports at most one BIP-32 derivation per transparent output; found {count}"
        )),
    }
}

fn required_single_derivation(
    map: &BTreeMap<[u8; 33], transparent::pczt::Bip32Derivation>,
) -> Result<Bip32Derivation, String> {
    if map.len() != 1 {
        return Err(format!(
            "Ledger requires exactly one BIP-32 derivation per transparent input; found {}",
            map.len()
        ));
    }
    let (pubkey, derivation) = map.iter().next().expect("one derivation");
    convert_derivation(pubkey, derivation)
}

fn convert_derivation(
    pubkey: &[u8; 33],
    derivation: &transparent::pczt::Bip32Derivation,
) -> Result<Bip32Derivation, String> {
    secp256k1::PublicKey::from_slice(pubkey)
        .map_err(|_| "Ledger BIP-32 derivation contains an invalid secp256k1 pubkey")?;
    Ok(Bip32Derivation {
        signing_path: derivation
            .derivation_path()
            .iter()
            .copied()
            .map(u32::from)
            .collect(),
        pubkey: *pubkey,
        seed_fingerprint: *derivation.seed_fingerprint(),
    })
}

fn bundle_version_for(branch: BranchId, pool: ValuePool) -> Result<BundleVersion, String> {
    bundle_version_for_branch(branch, pool)
        .ok_or_else(|| format!("No {pool:?} bundle version for branch {branch:?}"))
}

fn fallback_shielded_derivation(
    pczt: &Pczt,
    coin_type: u32,
    include_ironwood: bool,
) -> Result<Option<ShieldedDerivation>, String> {
    let mut shielded = None;
    let mut transparent = None;

    let verifier = Verifier::new(pczt.clone())
        .with_transparent::<String, _>(|bundle| {
            transparent = bundle
                .inputs()
                .iter()
                .find_map(|input| shielded_derivation_from_transparent(input, coin_type));
            Ok(())
        })
        .map_err(map_transparent_error)?;
    let verifier = verifier
        .with_orchard::<String, _>(|bundle| {
            shielded = bundle.actions().iter().find_map(|action| {
                action
                    .spend()
                    .zip32_derivation()
                    .as_ref()
                    .or_else(|| action.output().zip32_derivation().as_ref())
                    .map(convert_shielded_derivation)
            });
            Ok(())
        })
        .map_err(|e| map_orchard_error("Orchard", e))?;

    if include_ironwood && shielded.is_none() {
        verifier
            .with_ironwood::<String, _>(|bundle| {
                shielded = bundle.actions().iter().find_map(|action| {
                    action
                        .spend()
                        .zip32_derivation()
                        .as_ref()
                        .or_else(|| action.output().zip32_derivation().as_ref())
                        .map(convert_shielded_derivation)
                });
                Ok(())
            })
            .map_err(|e| map_orchard_error("Ironwood", e))?;
    }

    Ok(shielded.or(transparent))
}

fn shielded_derivation_from_transparent(
    input: &transparent::pczt::Input,
    coin_type: u32,
) -> Option<ShieldedDerivation> {
    if input.bip32_derivation().len() != 1 {
        return None;
    }
    let derivation = input
        .bip32_derivation()
        .values()
        .next()
        .expect("one transparent derivation");
    let path = derivation
        .derivation_path()
        .iter()
        .copied()
        .map(u32::from)
        .collect::<Vec<_>>();
    let expected_coin_type = 0x8000_0000 | coin_type;
    let account = path
        .get(2)
        .copied()
        .filter(|account| account & 0x8000_0000 != 0)?;
    if path.get(1).copied() != Some(expected_coin_type) {
        return None;
    }

    Some(ShieldedDerivation {
        signing_path: vec![0x8000_0020, expected_coin_type, account],
        seed_fingerprint: *derivation.seed_fingerprint(),
    })
}

fn convert_shielded_derivation(derivation: &orchard::pczt::Zip32Derivation) -> ShieldedDerivation {
    ShieldedDerivation {
        signing_path: derivation
            .derivation_path()
            .iter()
            .map(|component| component.index())
            .collect(),
        seed_fingerprint: *derivation.seed_fingerprint(),
    }
}

fn required_shielded_derivation(
    spend_value: u64,
    derivation: Option<&orchard::pczt::Zip32Derivation>,
    fallback: Option<&ShieldedDerivation>,
) -> Result<ShieldedDerivation, String> {
    match derivation {
        Some(derivation) => Ok(convert_shielded_derivation(derivation)),
        None if spend_value == 0 => fallback.cloned().ok_or_else(|| {
            "Shielded padding spend has no account derivation available for Ledger".into()
        }),
        None => Err("Shielded real spend is missing ZIP-32 derivation".into()),
    }
}

fn convert_shielded_bundle(
    bundle: &orchard::pczt::Bundle,
    branch: BranchId,
    pool: ValuePool,
    fallback_derivation: Option<&ShieldedDerivation>,
) -> Result<Option<ShieldedBundle>, String> {
    if bundle.actions().is_empty() {
        return Ok(None);
    }

    let bundle_version = bundle_version_for(branch, pool)?;
    let actions = bundle
        .actions()
        .iter()
        .map(|action| convert_shielded_action(action, fallback_derivation))
        .collect::<Result<Vec<_>, _>>()?;
    let (magnitude, sign) = bundle.value_sum().magnitude_sign();
    let value_balance = if matches!(sign, orchard::value::Sign::Negative) {
        -(magnitude as i128)
    } else {
        magnitude as i128
    };

    Ok(Some(ShieldedBundle {
        actions,
        flags: bundle
            .flags()
            .to_byte(bundle_version)
            .ok_or_else(|| format!("Bundle flags are invalid for {bundle_version:?}"))?,
        value_balance,
        anchor: bundle.anchor().to_bytes(),
    }))
}

fn convert_ironwood_bundle(
    bundle: &orchard::pczt::Bundle,
    branch: BranchId,
    fallback_derivation: Option<&ShieldedDerivation>,
) -> Result<Option<IronwoodBundle>, String> {
    let Some(shared) =
        convert_shielded_bundle(bundle, branch, ValuePool::Ironwood, fallback_derivation)?
    else {
        return Ok(None);
    };
    let note_plaintext_version =
        match bundle_version_for(branch, ValuePool::Ironwood)?.note_version() {
            NoteVersion::V2 => 0x02,
            NoteVersion::V3 => 0x03,
        };

    Ok(Some(IronwoodBundle {
        actions: shared
            .actions
            .into_iter()
            .map(|action| IronwoodAction {
                action,
                note_plaintext_version,
            })
            .collect(),
        flags: shared.flags,
        value_balance: shared.value_balance,
        anchor: shared.anchor,
    }))
}

fn convert_shielded_action(
    action: &orchard::pczt::Action,
    fallback_derivation: Option<&ShieldedDerivation>,
) -> Result<ShieldedAction, String> {
    let spend = action.spend();
    let output = action.output();
    let spend_value = spend
        .value()
        .map(|value| value.inner())
        .ok_or("Shielded spend is missing its value")?;
    let derivation = required_shielded_derivation(
        spend_value,
        spend.zip32_derivation().as_ref(),
        fallback_derivation,
    )?;
    let encrypted_note = output.encrypted_note();

    Ok(ShieldedAction {
        cv_net: action.cv_net().to_bytes(),
        nullifier: spend.nullifier().to_bytes(),
        rk: spend.rk().into(),
        spend_recipient: spend
            .recipient()
            .map(|recipient| recipient.to_raw_address_bytes())
            .ok_or("Shielded spend is missing its recipient")?,
        spend_value,
        spend_rho: spend
            .rho()
            .map(|rho| rho.to_bytes())
            .ok_or("Shielded spend is missing rho")?,
        spend_rseed: spend
            .rseed()
            .map(|rseed| *rseed.as_bytes())
            .ok_or("Shielded spend is missing rseed")?,
        alpha: spend
            .alpha()
            .map(|alpha| alpha.to_repr())
            .ok_or("Shielded spend is missing alpha")?,
        signing_path: derivation.signing_path,
        seed_fingerprint: derivation.seed_fingerprint,
        cmx: output.cmx().to_bytes(),
        ephemeral_key: encrypted_note.epk_bytes,
        enc_ciphertext: encrypted_note.enc_ciphertext.to_vec(),
        out_ciphertext: encrypted_note.out_ciphertext.to_vec(),
        recipient: output
            .recipient()
            .map(|recipient| recipient.to_raw_address_bytes())
            .ok_or("Shielded output is missing its recipient")?,
        value: output
            .value()
            .map(|value| value.inner())
            .ok_or("Shielded output is missing its value")?,
        rseed: output
            .rseed()
            .map(|rseed| *rseed.as_bytes())
            .ok_or("Shielded output is missing rseed")?,
        rcv: action
            .rcv()
            .as_ref()
            .map(|rcv| rcv.to_bytes())
            .ok_or("Shielded action is missing rcv")?,
    })
}

fn map_transparent_error(error: TransparentError<String>) -> String {
    match error {
        TransparentError::Custom(message) => message,
        other => format!("Transparent bundle is invalid: {other:?}"),
    }
}

fn map_orchard_error(pool: &str, error: OrchardError<String>) -> String {
    match error {
        OrchardError::Custom(message) => message,
        other => format!("{pool} bundle is invalid: {other:?}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn derivation() -> transparent::pczt::Bip32Derivation {
        transparent::pczt::Bip32Derivation::parse(
            [0x11; 32],
            vec![0x8000_002c, 0x8000_0085, 0x8000_0000, 0, 0],
        )
        .unwrap()
    }

    fn valid_pubkey() -> [u8; 33] {
        hex::decode("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
            .unwrap()
            .try_into()
            .unwrap()
    }

    fn shielded_derivation() -> ShieldedDerivation {
        ShieldedDerivation {
            signing_path: vec![0x8000_0020, 0x8000_0085, 0x8000_0000],
            seed_fingerprint: [0x22; 32],
        }
    }

    #[test]
    fn bundle_version_tracks_pool_and_branch() {
        assert_eq!(
            bundle_version_for(BranchId::Nu6_2, ValuePool::Orchard).unwrap(),
            BundleVersion::orchard_v2()
        );
        assert_eq!(
            bundle_version_for(BranchId::Nu6_3, ValuePool::Orchard).unwrap(),
            BundleVersion::orchard_v3()
        );
        assert_eq!(
            bundle_version_for(BranchId::Nu6_3, ValuePool::Ironwood).unwrap(),
            BundleVersion::ironwood_v3()
        );
    }

    #[test]
    fn rejects_invalid_pczt() {
        assert!(parse_pczt(b"PCZT").is_err());
    }

    #[test]
    fn transparent_input_requires_exactly_one_derivation() {
        let missing = BTreeMap::new();
        assert!(required_single_derivation(&missing)
            .unwrap_err()
            .contains("exactly one"));

        let mut multiple = BTreeMap::new();
        multiple.insert(valid_pubkey(), derivation());
        let mut second = valid_pubkey();
        second[0] = 3;
        multiple.insert(second, derivation());
        assert!(required_single_derivation(&multiple)
            .unwrap_err()
            .contains("exactly one"));
    }

    #[test]
    fn transparent_derivation_rejects_malformed_pubkey() {
        let mut malformed = BTreeMap::new();
        malformed.insert([0x04; 33], derivation());
        assert!(required_single_derivation(&malformed)
            .unwrap_err()
            .contains("invalid secp256k1 pubkey"));
    }

    #[test]
    fn shielded_padding_spend_reuses_account_derivation() {
        let fallback = shielded_derivation();

        assert_eq!(
            required_shielded_derivation(0, None, Some(&fallback)).unwrap(),
            fallback
        );
    }

    #[test]
    fn shielded_real_spend_still_requires_its_own_derivation() {
        let error =
            required_shielded_derivation(1, None, Some(&shielded_derivation())).unwrap_err();

        assert!(error.contains("real spend is missing ZIP-32 derivation"));
    }
}
