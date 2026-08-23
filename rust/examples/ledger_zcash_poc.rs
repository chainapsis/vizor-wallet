//! Developer CLI for validating the experimental Ledger integration without
//! wiring it into Vizor's production account/send flows.

use std::{env, fs, process};

use rust_lib_zcash_wallet::wallet::ledger;

fn main() {
    if let Err(error) = run() {
        eprintln!("Ledger PoC error: {error}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("version") => {
            let app = ledger::get_device_app()?;
            println!("{} {}", app.name, app.version);
            Ok(())
        }
        Some("ufvk") => {
            let account_index = args
                .next()
                .as_deref()
                .unwrap_or("0")
                .parse::<u32>()
                .map_err(|_| "Account index must be a non-negative integer".to_string())?;
            println!("{}", ledger::get_ufvk(account_index)?);
            Ok(())
        }
        Some("sign") => {
            let path = args
                .next()
                .ok_or("Usage: ledger_zcash_poc sign <pczt-file>")?;
            let pczt = fs::read(&path).map_err(|e| format!("Read {path}: {e}"))?;
            let signatures = ledger::sign_pczt(&pczt)?;
            for signature in signatures {
                let pool = match signature.value_pool() {
                    orchard::ValuePool::Orchard => "orchard",
                    orchard::ValuePool::Ironwood => "ironwood",
                };
                println!(
                    "{pool}:{}:{}",
                    signature.action_index(),
                    hex::encode(signature.signature())
                );
            }
            Ok(())
        }
        _ => Err(
            "Usage: ledger_zcash_poc <version | ufvk [account-index] | sign <pczt-file>>".into(),
        ),
    }
}
