//! Import the firmware's account export, then fund it on an isolated synthetic chain.
#[path = "support/ironwood_fixture.rs"]
mod ironwood_fixture;
#[path = "support/voting_fixture.rs"]
mod voting_fixture;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use orchard::primitives::redpallas::{Signature, SpendAuth, VerificationKey};
use serde::{Deserialize, Serialize};
use std::{fs, path::Path};
use zcash_voting::round::VotingDb;

use rust_lib_zcash_wallet::{
    api::keystone::{decode_accounts_from_cbor, decode_ur_part},
    wallet::{
        keys::{import_hardware_account, HardwareSignerKind},
        network::WalletNetwork,
    },
};
use std::{
    env,
    io::{self, BufRead},
};
use zcash_address::{ToAddress, ZcashAddress};
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_protocol::consensus::NetworkType;

fn main() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let mode = args.next().ok_or("expected prepare or verify-votes")?;
    let path = args.next().ok_or("expected fixture path")?;
    match mode.as_str() {
        "prepare" => prepare(&path, false),
        "regtest-account" => prepare(&path, true),
        "regtest-sync" => {
            let url = args.next().ok_or("expected lightwalletd URL")?;
            let ironwood: u32 = args
                .next()
                .ok_or("expected NU6.3 height")?
                .parse()
                .map_err(|_| "invalid NU6.3 height")?;
            let nu7: u32 = args
                .next()
                .ok_or("expected NU7 height")?
                .parse()
                .map_err(|_| "invalid NU7 height")?;
            rust_lib_zcash_wallet::wallet::network::configure_regtest_nu6_3_activation_height(
                ironwood,
            )?;
            rust_lib_zcash_wallet::wallet::network::configure_regtest_nu7_activation_height(nu7)?;
            rust_lib_zcash_wallet::api::sync::run_full_sync_blocking(path, url, "regtest".into(), 1)
        }
        "verify-votes" => verify_votes(&path),
        _ => Err("unknown fixture command".into()),
    }
}

fn prepare(path: &str, regtest: bool) -> Result<(), String> {
    let mut export = None;
    for line in io::stdin().lock().lines() {
        let decoded = decode_ur_part(line.map_err(|e| e.to_string())?, "zcash-accounts".into())
            .map_err(|e| format!("Invalid account UR: {e:?}"))?;
        if let Some(data) = decoded.data {
            export = Some(decode_accounts_from_cbor(data)?);
            break;
        }
    }
    let accounts = export.ok_or("Incomplete firmware account export")?;
    let [account] = accounts.as_slice() else {
        return Err("Expected one firmware account".into());
    };
    if regtest {
        let network = WalletNetwork::Regtest;
        let (uuid, funding) = import_hardware_account(
            path,
            network,
            &account.name,
            &account.ufvk,
            &account.seed_fingerprint,
            account.index,
            Some(1),
            HardwareSignerKind::Keystone,
        )?;
        let tex = ZcashAddress::from_tex(NetworkType::Regtest, [0x42; 20]);
        let address = ZcashAddress::from_transparent_p2pkh(NetworkType::Regtest, [0x43; 20]);
        println!(
            "{}",
            serde_json::json!({
                "accountUuid": uuid, "fundingAddress": funding,
                "texAddress": tex.encode(), "address": address.encode(),
            })
        );
        return Ok(());
    }
    let height = ironwood_fixture::funding_height()?;
    let (uuid, _) = import_hardware_account(
        path,
        WalletNetwork::Main,
        &account.name,
        &account.ufvk,
        &account.seed_fingerprint,
        account.index,
        Some(u32::from(height).into()),
        HardwareSignerKind::Keystone,
    )?;
    let ufvk = UnifiedFullViewingKey::decode(&WalletNetwork::Main, &account.ufvk)
        .map_err(|e| e.to_string())?;
    ironwood_fixture::fund_wallet(path, &ufvk, &uuid, height)?;
    let db = VotingDb::open_wallet_sidecar(Path::new(path), &uuid).map_err(|e| e.to_string())?;
    let requests =
        voting_fixture::signing_requests(&account.ufvk, &account.seed_fingerprint, &db, false)?;
    let bundles: Vec<_> = requests
        .into_iter()
        .map(|r| Bundle {
            index: r.bundle_index,
            action: r.action_index,
            memo: r.display_memo,
            pczt: STANDARD.encode(r.redacted_pczt_bytes),
            full_pczt: STANDARD.encode(r.pczt_bytes),
            eligible: r.eligible_weight_zatoshi,
            delegated: r.delegated_weight_zatoshi,
            sighash: STANDARD.encode(r.pczt_sighash),
            rk: STANDARD.encode(r.rk),
        })
        .collect();
    fs::write(
        Path::new(path).with_file_name("voting.json"),
        serde_json::to_vec(&VotingFixture {
            round_id: voting_fixture::round_id(),
            bundles,
        })
        .map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    let address = ZcashAddress::from_transparent_p2pkh(NetworkType::Main, [0x42; 20]).encode();
    let tex = ZcashAddress::from_tex(NetworkType::Main, [0x42; 20]).encode();
    println!(
        "{}",
        serde_json::json!({"accountUuid": uuid, "texAddress": tex, "address": address})
    );
    Ok(())
}

#[derive(Serialize, Deserialize)]
struct VotingFixture {
    round_id: String,
    bundles: Vec<Bundle>,
}

#[derive(Serialize, Deserialize)]
struct Bundle {
    index: u32,
    action: u32,
    memo: String,
    pczt: String,
    full_pczt: String,
    eligible: u64,
    delegated: u64,
    sighash: String,
    rk: String,
}

// Verify the simulator's persisted signatures against the host's original SDK setup.
fn verify_votes(path: &str) -> Result<(), String> {
    let fixture: VotingFixture =
        serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let signatures: std::collections::BTreeMap<u32, String> =
        serde_json::from_reader(io::stdin().lock()).map_err(|e| e.to_string())?;
    if fixture.bundles.len() != 2 || signatures.len() != fixture.bundles.len() {
        return Err("Expected two signed voting bundles".into());
    }
    for bundle in fixture.bundles {
        let key: [u8; 32] = STANDARD
            .decode(bundle.rk)
            .map_err(|e| e.to_string())?
            .try_into()
            .map_err(|_| "Invalid rk length")?;
        let sighash = STANDARD.decode(bundle.sighash).map_err(|e| e.to_string())?;
        let bytes: [u8; 64] = STANDARD
            .decode(
                signatures
                    .get(&bundle.index)
                    .ok_or("Missing bundle signature")?,
            )
            .map_err(|e| e.to_string())?
            .try_into()
            .map_err(|_| "Invalid signature length")?;
        VerificationKey::<SpendAuth>::try_from(key)
            .map_err(|e| format!("Invalid rk: {e:?}"))?
            .verify(&sighash, &Signature::from(bytes))
            .map_err(|_| format!("Invalid signature for bundle {}", bundle.index))?;
    }
    Ok(())
}
