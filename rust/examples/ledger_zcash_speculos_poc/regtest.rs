//! Speculos-only coin-type-1 account export and real signing for the local vote chain.
use super::*;
use rust_lib_zcash_wallet::wallet::ledger;
use sha2::{Digest, Sha256};

pub(super) fn run(args: &[String]) -> Result<(), String> {
    let [command, api_url, input, output] = args else {
        return Err("Usage: regtest-export <api-url> <unused> <account.json> | regtest-sign <api-url> <unsigned.pczt> <signatures.json>".into());
    };
    let client = SpeculosClient::new(api_url)?;
    client.require_supported_zcash_app()?;
    let result = match command.as_str() {
        "regtest-export" => export(&client)?,
        "regtest-sign" => {
            // The raw production signer retains APDU serialization and signature
            // verification, while the product API's mainnet account gate is bypassed.
            env::set_var("VIZOR_LEDGER_SPECULOS_UFVK_API_URL", api_url);
            env::set_var("VIZOR_LEDGER_SPECULOS_SIGNING_API_URL", api_url);
            let pczt = fs::read(input).map_err(|e| e.to_string())?;
            let approval = ApprovalWorker::start(client);
            let signatures = ledger::sign_pczt(&pczt, super::CANARY_MEMO_HASH_SUPPORTED, None);
            let approved = approval.finish()?;
            let signatures = signatures?;
            if !approved {
                return Err("Ledger signing did not show an approval screen".into());
            }
            json!(signatures
                .iter()
                .map(|signature| json!({
                    "pool": match signature.value_pool() {
                        orchard::ValuePool::Orchard => 0,
                        orchard::ValuePool::Ironwood => 1,
                    },
                    "action_index": signature.action_index(),
                    "signature": signature.signature().to_vec(),
                }))
                .collect::<Vec<_>>())
        }
        _ => return Err(format!("Unknown regtest command: {command}")),
    };
    fs::write(
        output,
        serde_json::to_vec_pretty(&result).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())
}

fn export(client: &SpeculosClient) -> Result<Value, String> {
    let mut plan = ledger_build_ufvk_apdu_plan(0)?;
    // Two length-prefixed, three-component paths: m/32'/1'/0' and m/44'/1'/0'.
    for offset in [5, 18] {
        plan.first.data[offset..offset + 4].copy_from_slice(&0x8000_0001u32.to_be_bytes());
    }
    let approval = ApprovalWorker::start(client.clone());
    let first = client.exchange_apdu(&plan.first);
    let approved = approval.finish()?;
    let first = first?;
    if response_status(&first)? != 0x9000 || !approved {
        return Err(format!(
            "Regtest UFVK export failed: {}",
            hex::encode(first)
        ));
    }
    let mut payload = first[..first.len() - 2].to_vec();
    let prefix: [u8; 2] = payload
        .get(..2)
        .ok_or("Missing UFVK length")?
        .try_into()
        .unwrap();
    let expected = 2 + usize::from(u16::from_be_bytes(prefix));
    if expected > 8192 {
        return Err("UFVK response is too large".into());
    }
    while payload.len() < expected {
        let next = client.exchange_apdu(&plan.continuation)?;
        if response_status(&next)? != 0x9000 || next.len() <= 2 {
            return Err("UFVK continuation failed".into());
        }
        payload.extend_from_slice(&next[..next.len() - 2]);
    }
    if payload.len() != expected {
        return Err("UFVK response has trailing bytes".into());
    }
    let ufvk = String::from_utf8(payload[2..].to_vec()).map_err(|e| e.to_string())?;
    let ufvk = UnifiedFullViewingKey::decode(&WalletNetwork::Test, &ufvk)
        .map_err(|e| format!("Invalid testnet UFVK: {e}"))?
        .encode(&WalletNetwork::Regtest);
    let mut fingerprint = Sha256::new();
    fingerprint.update(b"vizor-ledger-account-fingerprint-v1\0");
    fingerprint.update(0u32.to_be_bytes());
    fingerprint.update(ufvk.as_bytes());
    thread::sleep(SPECULOS_UFVK_STATUS_WAIT);
    Ok(
        json!({"ufvk": ufvk, "seed_fingerprint": fingerprint.finalize().to_vec(), "account_index": 0}),
    )
}
