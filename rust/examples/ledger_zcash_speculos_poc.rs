//! Developer harness for exercising Vizor's production Ledger PCZT serializer
//! and finalizer against a Zcash app running in Speculos.

use std::{
    env, fs,
    io::{Read, Write},
    net::TcpStream,
    path::PathBuf,
    process,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::Duration,
};

use rust_lib_zcash_wallet::api::ledger::{
    ledger_build_pczt_full_signing_apdu_plan, ledger_build_ufvk_apdu_plan, ledger_export_account,
    ledger_finalize_mobile_pczt_full_signing, ledger_parse_mobile_ufvk_responses,
    ledger_sign_pczt_full, LedgerApduCommand,
};
use rust_lib_zcash_wallet::{api::wallet::import_hardware_account, wallet::network::WalletNetwork};
use serde_json::{json, Value};
use transparent::{
    address::TransparentAddress,
    bundle::{OutPoint, TxOut},
    keys::{NonHardenedChildIndex, TransparentKeyScope},
};
use url::Url;
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_primitives::transaction::{
    builder::{BuildConfig, Builder, BundlePadding, PcztResult},
    fees::zip317,
};
use zcash_protocol::{
    consensus::{BlockHeight, NetworkType, NetworkUpgrade, Parameters},
    value::Zatoshis,
};

use pczt::roles::{creator::Creator, io_finalizer::IoFinalizer, updater::Updater};
use voting_crypto_deps::rand::rngs::OsRng;

const DEFAULT_API_URL: &str = "http://127.0.0.1:5000";
const APDU_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const API_TIMEOUT: Duration = Duration::from_secs(3);

fn main() {
    if let Err(error) = run() {
        eprintln!("Ledger Speculos PoC error: {error}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args
        .iter()
        .any(|arg| matches!(arg.as_str(), "--help" | "-h"))
    {
        println!("{}", usage());
        return Ok(());
    }
    let config = Config::parse(args)?;
    if config.desktop_smoke {
        return run_desktop_smoke(config);
    }
    if config.prepare_fixture {
        return run_prepare_fixture(config);
    }
    if config.smoke {
        return run_smoke(config);
    }
    run_file(config)
}

fn run_desktop_smoke(config: Config) -> Result<(), String> {
    if config.network != "main" {
        return Err("Speculos desktop smoke mode currently supports mainnet only".into());
    }
    let client = SpeculosClient::new(&config.api_url)?;
    let signing_api_url = config.signing_api_url.as_deref().ok_or(
        "Desktop smoke mode requires --signing-api-url for the configured signing instance",
    )?;
    let signing_client = SpeculosClient::new(signing_api_url)?;

    let approval = config
        .auto_approve
        .then(|| ApprovalWorker::start(client.clone()));
    let export_result = ledger_export_account(0, config.network.clone());
    let automated_ufvk_review = approval
        .map(ApprovalWorker::finish)
        .transpose()?
        .unwrap_or(false);
    let export = export_result.map_err(|error| format!("Desktop UFVK export failed: {error}"))?;

    let temp_dir =
        tempfile::tempdir().map_err(|error| format!("Create desktop smoke directory: {error}"))?;
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().into_owned();
    let account = import_hardware_account(
        db_path.clone(),
        config.network.clone(),
        "Speculos Ledger".into(),
        export.ufvk.clone(),
        export.seed_fingerprint.clone(),
        export.account_index,
        None,
        "ledger".into(),
    )?;
    let pczt = transparent_smoke_pczt(&export.ufvk, &export.seed_fingerprint)?;
    let approval = config
        .auto_approve
        .then(|| ApprovalWorker::start(signing_client));
    let signed_result =
        ledger_sign_pczt_full(db_path, account.account_uuid, pczt.clone(), config.network);
    let automated_signing_review = approval
        .map(ApprovalWorker::finish)
        .transpose()?
        .unwrap_or(false);
    let signed = signed_result.map_err(|error| format!("Desktop signing failed: {error}"))?;
    if signed == pczt {
        return Err("Desktop Ledger transport returned the unsigned PCZT unchanged".into());
    }
    if let Some(output_path) = config.output_path {
        fs::write(&output_path, &signed)
            .map_err(|error| format!("Write {}: {error}", output_path.display()))?;
        println!("signed_pczt={}", output_path.display());
    }
    println!("automated_ufvk_review={automated_ufvk_review}");
    println!("automated_signing_review={automated_signing_review}");
    println!("speculos_desktop_smoke=passed");
    Ok(())
}

fn run_prepare_fixture(config: Config) -> Result<(), String> {
    if config.network != "main" {
        return Err("Speculos fixture preparation currently supports mainnet only".into());
    }
    let db_path = config.db_path.ok_or_else(usage)?;
    let pczt_path = config.pczt_path.ok_or_else(usage)?;
    let metadata_path = config.metadata_path.ok_or_else(usage)?;
    let client = SpeculosClient::new(&config.api_url)?;
    let (export, automated_review) =
        export_account_from_speculos(&client, &config.network, config.auto_approve)?;
    let account = import_hardware_account(
        db_path.clone(),
        config.network.clone(),
        "Speculos Ledger".into(),
        export.ufvk.clone(),
        export.seed_fingerprint.clone(),
        export.account_index,
        None,
        "ledger".into(),
    )?;
    let pczt = transparent_smoke_pczt(&export.ufvk, &export.seed_fingerprint)?;
    fs::write(&pczt_path, &pczt)
        .map_err(|error| format!("Write {}: {error}", pczt_path.display()))?;
    let metadata = json!({
        "accountUuid": account.account_uuid,
        "ufvk": export.ufvk,
        "seedFingerprint": hex::encode(export.seed_fingerprint),
        "accountIndex": export.account_index,
        "dbPath": db_path,
        "pcztPath": pczt_path,
    });
    fs::write(&metadata_path, metadata.to_string())
        .map_err(|error| format!("Write {}: {error}", metadata_path.display()))?;
    println!("automated_ufvk_review={automated_review}");
    println!("fixture_metadata={}", metadata_path.display());
    println!("fixture_pczt={}", pczt_path.display());
    println!("speculos_fixture=prepared");
    Ok(())
}

fn run_file(config: Config) -> Result<(), String> {
    let db_path = config.db_path.ok_or_else(usage)?;
    let account_uuid = config.account_uuid.ok_or_else(usage)?;
    let pczt_path = config.pczt_path.ok_or_else(usage)?;
    let output_path = config
        .output_path
        .unwrap_or_else(|| pczt_path.with_extension("signed.pczt"));
    let pczt =
        fs::read(&pczt_path).map_err(|error| format!("Read {}: {error}", pczt_path.display()))?;
    let plan = ledger_build_pczt_full_signing_apdu_plan(
        db_path.clone(),
        account_uuid.clone(),
        pczt.clone(),
        config.network.clone(),
    )?;
    if plan.commands.is_empty() {
        return Err("Vizor produced an empty Ledger signing plan".into());
    }

    let client = SpeculosClient::new(&config.api_url)?;
    let (responses, automated_review) =
        exchange_signing_plan(&client, &plan.commands, config.auto_approve)?;

    let signed = ledger_finalize_mobile_pczt_full_signing(
        db_path,
        account_uuid,
        pczt.clone(),
        config.network,
        responses,
    )?;
    if signed == pczt {
        return Err("Vizor finalizer returned the unsigned PCZT unchanged".into());
    }
    fs::write(&output_path, &signed)
        .map_err(|error| format!("Write {}: {error}", output_path.display()))?;
    println!("automated_review={automated_review}");
    println!("signed_pczt={}", output_path.display());
    Ok(())
}

fn run_smoke(config: Config) -> Result<(), String> {
    if config.network != "main" {
        return Err("Speculos smoke mode currently supports mainnet only".into());
    }
    let client = SpeculosClient::new(&config.api_url)?;
    let signing_api_url = config.signing_api_url.as_deref().ok_or(
        "Smoke mode requires --signing-api-url for a fresh Speculos instance using the same seed",
    )?;
    let signing_client = SpeculosClient::new(signing_api_url)?;
    let (export, automated_ufvk_review) =
        export_account_from_speculos(&client, &config.network, config.auto_approve)?;

    let temp_dir =
        tempfile::tempdir().map_err(|error| format!("Create smoke directory: {error}"))?;
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().into_owned();
    let account = import_hardware_account(
        db_path.clone(),
        config.network.clone(),
        "Speculos Ledger".into(),
        export.ufvk.clone(),
        export.seed_fingerprint.clone(),
        export.account_index,
        None,
        "ledger".into(),
    )?;
    let pczt = transparent_smoke_pczt(&export.ufvk, &export.seed_fingerprint)?;
    let plan = ledger_build_pczt_full_signing_apdu_plan(
        db_path.clone(),
        account.account_uuid.clone(),
        pczt.clone(),
        config.network.clone(),
    )?;
    let (responses, automated_signing_review) =
        exchange_signing_plan(&signing_client, &plan.commands, config.auto_approve)?;
    let signed = ledger_finalize_mobile_pczt_full_signing(
        db_path,
        account.account_uuid,
        pczt.clone(),
        config.network,
        responses,
    )?;
    if signed == pczt {
        return Err("Vizor finalizer returned the smoke PCZT unchanged".into());
    }
    if let Some(output_path) = config.output_path {
        fs::write(&output_path, &signed)
            .map_err(|error| format!("Write {}: {error}", output_path.display()))?;
        println!("signed_pczt={}", output_path.display());
    }
    println!("automated_ufvk_review={automated_ufvk_review}");
    println!("automated_signing_review={automated_signing_review}");
    println!("speculos_smoke=passed");
    Ok(())
}

fn export_account_from_speculos(
    client: &SpeculosClient,
    network: &str,
    auto_approve: bool,
) -> Result<
    (
        rust_lib_zcash_wallet::api::ledger::LedgerAccountExport,
        bool,
    ),
    String,
> {
    let ufvk_plan = ledger_build_ufvk_apdu_plan(0)?;
    let approval = auto_approve.then(|| ApprovalWorker::start(client.clone()));
    let first = client.exchange_apdu(&ufvk_plan.first);
    let automated_review = approval
        .map(ApprovalWorker::finish)
        .transpose()?
        .unwrap_or(false);
    let first = first.map_err(|error| format!("UFVK first APDU failed: {error}"))?;
    println!("ufvk_apdu=1 status={:#06x}", response_status(&first)?);
    let first_payload = first
        .get(..first.len().saturating_sub(2))
        .ok_or("UFVK first response is missing a status word")?;
    let declared_len = first_payload
        .get(..2)
        .map(|prefix| 2 + u16::from_be_bytes([prefix[0], prefix[1]]) as usize)
        .ok_or("UFVK first response is missing its length prefix")?;
    let mut ufvk_responses = vec![first];
    while ufvk_responses
        .iter()
        .map(|response| response.len().saturating_sub(2))
        .sum::<usize>()
        < declared_len
    {
        let continuation = client
            .exchange_apdu(&ufvk_plan.continuation)
            .map_err(|error| format!("UFVK continuation APDU failed: {error}"))?;
        println!(
            "ufvk_apdu={} status={:#06x}",
            ufvk_responses.len() + 1,
            response_status(&continuation)?
        );
        if continuation.len() <= 2 {
            return Err("UFVK continuation ended before the declared length".into());
        }
        ufvk_responses.push(continuation);
    }
    let export = ledger_parse_mobile_ufvk_responses(0, network.to_string(), ufvk_responses)?;
    Ok((export, automated_review))
}

fn exchange_signing_plan(
    client: &SpeculosClient,
    commands: &[LedgerApduCommand],
    auto_approve: bool,
) -> Result<(Vec<Vec<u8>>, bool), String> {
    let mut responses = Vec::with_capacity(commands.len());
    let mut automated_review = false;
    for (index, command) in commands.iter().enumerate() {
        let finishes_pczt = matches!(command.ins, 0x56 | 0x58) && command.p2 == 0x01;
        let approval = if finishes_pczt && auto_approve {
            Some(ApprovalWorker::start(client.clone()))
        } else {
            None
        };
        println!(
            "sending_apdu={}/{} ins={:#04x} p1={:#04x} p2={:#04x} data_len={}",
            index + 1,
            commands.len(),
            command.ins,
            command.p1,
            command.p2,
            command.data.len()
        );
        std::io::stdout()
            .flush()
            .map_err(|error| format!("Flush APDU progress: {error}"))?;
        let response = client.exchange_apdu(command);
        let approval_result = approval.map(ApprovalWorker::finish).transpose()?;
        automated_review |= approval_result.unwrap_or(false);
        let response = response.map_err(|error| {
            format!(
                "APDU {}/{} (INS {:#04x}) failed: {error}",
                index + 1,
                commands.len(),
                command.ins
            )
        })?;
        let status = response_status(&response)?;
        println!(
            "apdu={}/{} ins={:#04x} p1={:#04x} p2={:#04x} data_len={} status={:#06x}",
            index + 1,
            commands.len(),
            command.ins,
            command.p1,
            command.p2,
            command.data.len(),
            status
        );
        if status != 0x9000 {
            return Err(format!(
                "Speculos rejected APDU {}/{} (INS {:#04x}) with status {:#06x}",
                index + 1,
                commands.len(),
                command.ins,
                status
            ));
        }
        responses.push(response);
    }
    Ok((responses, automated_review))
}

#[derive(Clone, Copy, Debug)]
struct PreIronwoodMainNetwork;

impl Parameters for PreIronwoodMainNetwork {
    fn network_type(&self) -> NetworkType {
        NetworkType::Main
    }

    fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
        match nu {
            NetworkUpgrade::Nu6_3 => None,
            _ => Some(BlockHeight::from_u32(1)),
        }
    }
}

fn transparent_smoke_pczt(ufvk: &str, seed_fingerprint: &[u8]) -> Result<Vec<u8>, String> {
    let ufvk = UnifiedFullViewingKey::decode(&WalletNetwork::Main, ufvk)
        .map_err(|error| format!("Decode Speculos UFVK for smoke fixture: {error}"))?;
    let account_pubkey = ufvk
        .transparent()
        .ok_or("Speculos UFVK has no transparent account public key")?;
    let child_index = NonHardenedChildIndex::ZERO;
    let pubkey = account_pubkey
        .derive_address_pubkey(TransparentKeyScope::EXTERNAL, child_index)
        .map_err(|error| format!("Derive Speculos transparent public key: {error}"))?;
    let pubkey_bytes = pubkey.serialize();
    let address = TransparentAddress::from_pubkey(&pubkey);

    let mut builder = Builder::new(
        PreIronwoodMainNetwork,
        100.into(),
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: None,
            ironwood_anchor: None,
            orchard_padding: BundlePadding::DEFAULT,
            ironwood_padding: BundlePadding::DEFAULT,
        },
    );
    builder
        .add_transparent_p2pkh_input(
            pubkey,
            OutPoint::new([1; 32], 0),
            TxOut::new(Zatoshis::const_from_u64(1_000_000), address.script().into()),
        )
        .map_err(|error| format!("Add smoke transparent input: {error}"))?;
    builder
        .add_transparent_output(&address, Zatoshis::const_from_u64(990_000))
        .map_err(|error| format!("Add smoke transparent output: {error}"))?;
    let PcztResult { pczt_parts, .. } = builder
        .build_for_pczt(OsRng, &zip317::FeeRule::standard())
        .map_err(|error| format!("Build smoke PCZT: {error}"))?;
    let pczt = IoFinalizer::new(
        Creator::build_from_parts(pczt_parts).ok_or("Create smoke PCZT from builder parts")?,
    )
    .finalize_io()
    .map_err(|error| format!("Finalize smoke PCZT IO: {error:?}"))?;

    let fingerprint: [u8; 32] = seed_fingerprint
        .try_into()
        .map_err(|_| "Speculos Ledger fingerprint must be 32 bytes")?;
    let derivation = transparent::pczt::Bip32Derivation::parse(
        fingerprint,
        vec![0x8000_002c, 0x8000_0085, 0x8000_0000, 0, 0],
    )
    .map_err(|error| format!("Build smoke BIP32 derivation: {error:?}"))?;
    let pczt = Updater::new(pczt)
        .update_transparent_with(|mut bundle| {
            bundle.update_input_with(0, |mut input| {
                input.set_bip32_derivation(pubkey_bytes, derivation);
                Ok(())
            })
        })
        .map_err(|error| format!("Attach smoke Ledger derivation: {error:?}"))?
        .finish();
    pczt.serialize()
        .map_err(|error| format!("Serialize smoke PCZT: {error:?}"))
}

#[derive(Debug)]
struct Config {
    desktop_smoke: bool,
    prepare_fixture: bool,
    smoke: bool,
    db_path: Option<String>,
    account_uuid: Option<String>,
    pczt_path: Option<PathBuf>,
    output_path: Option<PathBuf>,
    metadata_path: Option<PathBuf>,
    network: String,
    api_url: String,
    signing_api_url: Option<String>,
    auto_approve: bool,
}

impl Config {
    fn parse(args: impl IntoIterator<Item = String>) -> Result<Self, String> {
        let mut db_path = None;
        let mut account_uuid = None;
        let mut pczt_path = None;
        let mut output_path = None;
        let mut metadata_path = None;
        let mut network = "main".to_string();
        let mut api_url = DEFAULT_API_URL.to_string();
        let mut signing_api_url = None;
        let mut auto_approve = true;
        let mut smoke = false;
        let mut desktop_smoke = false;
        let mut prepare_fixture = false;
        let mut args = args.into_iter();

        while let Some(arg) = args.next() {
            let value = |args: &mut dyn Iterator<Item = String>| {
                args.next()
                    .ok_or_else(|| format!("Missing value for {arg}"))
            };
            match arg.as_str() {
                "--db-path" => db_path = Some(value(&mut args)?),
                "--account-uuid" => account_uuid = Some(value(&mut args)?),
                "--pczt" => pczt_path = Some(PathBuf::from(value(&mut args)?)),
                "--output" => output_path = Some(PathBuf::from(value(&mut args)?)),
                "--metadata" => metadata_path = Some(PathBuf::from(value(&mut args)?)),
                "--network" => network = value(&mut args)?,
                "--api-url" => api_url = value(&mut args)?,
                "--signing-api-url" => signing_api_url = Some(value(&mut args)?),
                "--manual-review" => auto_approve = false,
                "smoke" => smoke = true,
                "desktop-smoke" => desktop_smoke = true,
                "prepare-fixture" => prepare_fixture = true,
                _ => return Err(format!("Unknown argument: {arg}\n\n{}", usage())),
            }
        }

        if prepare_fixture {
            if db_path.is_none() || pczt_path.is_none() || metadata_path.is_none() {
                return Err(usage());
            }
        } else if !smoke
            && !desktop_smoke
            && (db_path.is_none() || account_uuid.is_none() || pczt_path.is_none())
        {
            return Err(usage());
        }
        Ok(Self {
            desktop_smoke,
            prepare_fixture,
            smoke,
            db_path,
            account_uuid,
            pczt_path,
            output_path,
            metadata_path,
            network,
            api_url,
            signing_api_url,
            auto_approve,
        })
    }
}

fn usage() -> String {
    let prepare = "Usage:\n  ledger_zcash_speculos_poc desktop-smoke --api-url <ufvk-speculos-api> --signing-api-url <signing-speculos-api> [--output <signed-pczt>] [--manual-review]\n\n  ledger_zcash_speculos_poc prepare-fixture --db-path <wallet-db> --pczt <unsigned-pczt> --metadata <fixture-json> [--api-url http://127.0.0.1:5000] [--manual-review]\n\nDesktop-smoke exercises the production macOS Ledger transport selected by the VIZOR_LEDGER_SPECULOS_* environment variables. Prepare-fixture exports account 0, writes a persistent test database plus unsigned transparent PCZT, and records their paths and account metadata as JSON.";
    format!("{prepare}\n\n{}", format!(
        "Usage:\n  ledger_zcash_speculos_poc smoke --signing-api-url <fresh-speculos-api> [--api-url {DEFAULT_API_URL}] [--output <signed-pczt>] [--manual-review]\n\n  ledger_zcash_speculos_poc \\\n  --db-path <wallet-db> --account-uuid <ledger-account-uuid> --pczt <unsigned-pczt> \\\n  [--output <signed-pczt>] [--network main] [--api-url {DEFAULT_API_URL}] [--manual-review]\n\n\
Smoke mode exports account 0 from Speculos, imports it into a temporary mainnet DB,\n\
builds a transparent PCZT for that key, and exercises Vizor plan, transport, and finalize.\n\
The signing API must be a fresh instance using the same deterministic seed because the\n\
Zcash app does not accept PCZT initialization in the post-UFVK Speculos session.\n\n\
For file mode, the wallet database must contain the selected Ledger account imported\n\
from the same Speculos seed. Start Zcash 3.9.2 with its REST API exposed, then run:\n\
  cargo run --example ledger_zcash_speculos_poc -- <arguments>\n\n\
By default the harness navigates Nano S+/Nano X review screens with the Speculos\n\
/events and /button APIs. Pass --manual-review to use the Speculos UI instead."
    ))
}

#[derive(Clone)]
struct SpeculosClient {
    host: String,
    port: u16,
    base_path: String,
}

impl SpeculosClient {
    fn new(api_url: &str) -> Result<Self, String> {
        let url =
            Url::parse(api_url).map_err(|error| format!("Invalid Speculos API URL: {error}"))?;
        if url.scheme() != "http" {
            return Err("Speculos API URL must use http".into());
        }
        if url.query().is_some() || url.fragment().is_some() {
            return Err("Speculos API URL must not contain a query or fragment".into());
        }
        let host = url
            .host_str()
            .ok_or("Speculos API URL is missing a host")?
            .to_string();
        let port = url
            .port_or_known_default()
            .ok_or("Speculos API URL is missing a port")?;
        let base_path = url.path().trim_end_matches('/').to_string();
        Ok(Self {
            host,
            port,
            base_path,
        })
    }

    fn exchange_apdu(&self, command: &LedgerApduCommand) -> Result<Vec<u8>, String> {
        let data = serialize_apdu(command)?;
        let response = self.request_json(
            "POST",
            "/apdu",
            Some(&json!({ "data": hex::encode(data) })),
            APDU_TIMEOUT,
        )?;
        let data = response
            .get("data")
            .and_then(Value::as_str)
            .ok_or("Speculos /apdu response is missing string field 'data'")?;
        hex::decode(data).map_err(|error| format!("Decode Speculos APDU response: {error}"))
    }

    fn current_screen_text(&self) -> Result<String, String> {
        let response =
            self.request_json("GET", "/events?currentscreenonly=true", None, API_TIMEOUT)?;
        let events = response
            .get("events")
            .and_then(Value::as_array)
            .ok_or("Speculos /events response is missing array field 'events'")?;
        Ok(events
            .iter()
            .filter_map(|event| event.get("text").and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join(" "))
    }

    fn press_button(&self, button: &str) -> Result<(), String> {
        self.request_json(
            "POST",
            &format!("/button/{button}"),
            Some(&json!({ "action": "press-and-release" })),
            API_TIMEOUT,
        )?;
        Ok(())
    }

    fn request_json(
        &self,
        method: &str,
        path: &str,
        body: Option<&Value>,
        timeout: Duration,
    ) -> Result<Value, String> {
        let body = body.map(Value::to_string).unwrap_or_default();
        let path = format!("{}{}", self.base_path, path);
        let mut stream = TcpStream::connect((self.host.as_str(), self.port))
            .map_err(|error| format!("Connect to Speculos API: {error}"))?;
        stream
            .set_read_timeout(Some(timeout))
            .map_err(|error| format!("Set Speculos read timeout: {error}"))?;
        stream
            .set_write_timeout(Some(API_TIMEOUT))
            .map_err(|error| format!("Set Speculos write timeout: {error}"))?;
        write!(
            stream,
            "{method} {path} HTTP/1.1\r\nHost: {}:{}\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            self.host,
            self.port,
            body.len(),
            body
        )
        .map_err(|error| format!("Write Speculos HTTP request: {error}"))?;

        let response = read_http_response(&mut stream)?;
        parse_http_json_response(&response)
    }
}

struct ApprovalWorker {
    done: Arc<AtomicBool>,
    handle: thread::JoinHandle<Result<bool, String>>,
}

impl ApprovalWorker {
    fn start(client: SpeculosClient) -> Self {
        let done = Arc::new(AtomicBool::new(false));
        let worker_done = Arc::clone(&done);
        let handle = thread::spawn(move || automate_approval(&client, &worker_done));
        Self { done, handle }
    }

    fn finish(self) -> Result<bool, String> {
        self.done.store(true, Ordering::SeqCst);
        self.handle
            .join()
            .map_err(|_| "Speculos approval worker panicked".to_string())?
    }
}

fn automate_approval(client: &SpeculosClient, done: &AtomicBool) -> Result<bool, String> {
    let mut review_started = false;
    while !done.load(Ordering::SeqCst) {
        let screen = client.current_screen_text()?;
        let normalized = screen.to_ascii_lowercase();
        if normalized.contains("review")
            || normalized.contains("export")
            || normalized.contains("viewing key")
        {
            review_started = true;
        }
        if review_started {
            if normalized.contains("approve")
                || normalized.contains("accept")
                || normalized.contains("confirm")
                || normalized.contains("sign transaction")
            {
                client.press_button("both")?;
                return Ok(true);
            }
            client.press_button(if normalized.contains("cancel") {
                "left"
            } else {
                "right"
            })?;
        }
        thread::sleep(Duration::from_millis(150));
    }
    Ok(false)
}

fn serialize_apdu(command: &LedgerApduCommand) -> Result<Vec<u8>, String> {
    let len = u8::try_from(command.data.len()).map_err(|_| {
        format!(
            "Ledger APDU payload exceeds 255 bytes: {}",
            command.data.len()
        )
    })?;
    let mut bytes = Vec::with_capacity(command.data.len() + 5);
    bytes.extend_from_slice(&[command.cla, command.ins, command.p1, command.p2, len]);
    bytes.extend_from_slice(&command.data);
    Ok(bytes)
}

fn response_status(response: &[u8]) -> Result<u16, String> {
    if response.len() < 2 {
        return Err("Speculos APDU response is too short to contain a status word".into());
    }
    Ok(u16::from_be_bytes([
        response[response.len() - 2],
        response[response.len() - 1],
    ]))
}

fn parse_http_json_response(response: &[u8]) -> Result<Value, String> {
    let separator = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .ok_or("Speculos HTTP response is missing a header terminator")?;
    let headers = std::str::from_utf8(&response[..separator])
        .map_err(|_| "Speculos HTTP response headers are not UTF-8")?;
    let status = headers
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|value| value.parse::<u16>().ok())
        .ok_or("Speculos HTTP response has an invalid status line")?;
    let raw_body = &response[separator + 4..];
    let chunked = headers.lines().any(|line| {
        line.to_ascii_lowercase()
            .starts_with("transfer-encoding: chunked")
    });
    let decoded_body = chunked.then(|| decode_chunked_body(raw_body)).transpose()?;
    let body = decoded_body.as_deref().unwrap_or(raw_body);
    if !(200..300).contains(&status) {
        return Err(format!(
            "Speculos API returned HTTP {status}: {}",
            String::from_utf8_lossy(body).trim()
        ));
    }
    if body.is_empty() {
        return Ok(Value::Null);
    }
    serde_json::from_slice(body).map_err(|error| format!("Decode Speculos JSON response: {error}"))
}

fn read_http_response(stream: &mut TcpStream) -> Result<Vec<u8>, String> {
    let mut response = Vec::new();
    let mut buffer = [0u8; 8192];
    loop {
        let read = stream
            .read(&mut buffer)
            .map_err(|error| format!("Read Speculos HTTP response: {error}"))?;
        if read == 0 {
            if response.is_empty() {
                return Err("Speculos HTTP response ended before headers".into());
            }
            return Ok(response);
        }
        response.extend_from_slice(&buffer[..read]);
        if http_response_complete(&response)? {
            return Ok(response);
        }
    }
}

fn http_response_complete(response: &[u8]) -> Result<bool, String> {
    let Some(separator) = response.windows(4).position(|window| window == b"\r\n\r\n") else {
        return Ok(false);
    };
    let headers = std::str::from_utf8(&response[..separator])
        .map_err(|_| "Speculos HTTP response headers are not UTF-8")?;
    let body = &response[separator + 4..];
    if headers.lines().any(|line| {
        line.to_ascii_lowercase()
            .starts_with("transfer-encoding: chunked")
    }) {
        return chunked_body_complete(body);
    }
    if let Some(length) = headers.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        name.eq_ignore_ascii_case("content-length")
            .then(|| value.trim().parse::<usize>().ok())
            .flatten()
    }) {
        return Ok(body.len() >= length);
    }
    Ok(false)
}

fn chunked_body_complete(mut body: &[u8]) -> Result<bool, String> {
    loop {
        let Some(line_end) = body.windows(2).position(|window| window == b"\r\n") else {
            return Ok(false);
        };
        let size_text = std::str::from_utf8(&body[..line_end])
            .map_err(|_| "Speculos chunk size is not UTF-8")?;
        let size = usize::from_str_radix(size_text.split(';').next().unwrap_or_default(), 16)
            .map_err(|_| "Speculos chunk size is not hexadecimal")?;
        body = &body[line_end + 2..];
        if size == 0 {
            return Ok(body.len() >= 2 && &body[..2] == b"\r\n");
        }
        if body.len() < size + 2 {
            return Ok(false);
        }
        if &body[size..size + 2] != b"\r\n" {
            return Err("Speculos chunked response has an invalid chunk terminator".into());
        }
        body = &body[size + 2..];
    }
}

fn decode_chunked_body(mut body: &[u8]) -> Result<Vec<u8>, String> {
    let mut decoded = Vec::new();
    loop {
        let line_end = body
            .windows(2)
            .position(|window| window == b"\r\n")
            .ok_or("Speculos chunked response is missing a size terminator")?;
        let size_text = std::str::from_utf8(&body[..line_end])
            .map_err(|_| "Speculos chunk size is not UTF-8")?;
        let size = usize::from_str_radix(size_text.split(';').next().unwrap_or_default(), 16)
            .map_err(|_| "Speculos chunk size is not hexadecimal")?;
        body = &body[line_end + 2..];
        if size == 0 {
            return Ok(decoded);
        }
        if body.len() < size + 2 || &body[size..size + 2] != b"\r\n" {
            return Err("Speculos chunked response ended mid-chunk".into());
        }
        decoded.extend_from_slice(&body[..size]);
        body = &body[size + 2..];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_short_apdu_like_ledger_transport() {
        let command = LedgerApduCommand {
            cla: 0xe0,
            ins: 0x58,
            p1: 0x80,
            p2: 0x01,
            data: vec![0xaa, 0xbb],
        };
        assert_eq!(
            serialize_apdu(&command).unwrap(),
            vec![0xe0, 0x58, 0x80, 0x01, 0x02, 0xaa, 0xbb]
        );
    }

    #[test]
    fn parses_status_bearing_speculos_response() {
        let response =
            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"data\":\"01029000\"}";
        let body = parse_http_json_response(response).unwrap();
        let bytes = hex::decode(body["data"].as_str().unwrap()).unwrap();
        assert_eq!(response_status(&bytes).unwrap(), 0x9000);
    }

    #[test]
    fn parses_chunked_speculos_response() {
        let response = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n14\r\n{\"data\": \"01029000\"}\r\n0\r\n\r\n";
        let body = parse_http_json_response(response).unwrap();
        assert_eq!(body["data"], "01029000");
        assert!(http_response_complete(response).unwrap());
    }

    #[test]
    fn rejects_non_success_http_response() {
        let response = b"HTTP/1.1 500 Error\r\n\r\nnot ready";
        assert!(parse_http_json_response(response)
            .unwrap_err()
            .contains("HTTP 500"));
    }

    #[test]
    fn parses_fixture_preparation_paths() {
        let config = Config::parse([
            "prepare-fixture".into(),
            "--db-path".into(),
            "/tmp/ledger-wallet.db".into(),
            "--pczt".into(),
            "/tmp/ledger-unsigned.pczt".into(),
            "--metadata".into(),
            "/tmp/ledger-fixture.json".into(),
        ])
        .unwrap();

        assert!(config.prepare_fixture);
        assert_eq!(config.db_path.as_deref(), Some("/tmp/ledger-wallet.db"));
        assert_eq!(
            config.pczt_path.as_deref(),
            Some(std::path::Path::new("/tmp/ledger-unsigned.pczt"))
        );
        assert_eq!(
            config.metadata_path.as_deref(),
            Some(std::path::Path::new("/tmp/ledger-fixture.json"))
        );
    }

    #[test]
    fn fixture_preparation_requires_metadata_path() {
        let error = Config::parse([
            "prepare-fixture".into(),
            "--db-path".into(),
            "/tmp/ledger-wallet.db".into(),
            "--pczt".into(),
            "/tmp/ledger-unsigned.pczt".into(),
        ])
        .unwrap_err();

        assert!(error.contains("--metadata"));
    }

    #[test]
    fn parses_desktop_smoke_without_file_fixture_arguments() {
        let config = Config::parse([
            "desktop-smoke".into(),
            "--api-url".into(),
            "http://127.0.0.1:5004".into(),
            "--signing-api-url".into(),
            "http://127.0.0.1:5005".into(),
        ])
        .unwrap();

        assert!(config.desktop_smoke);
        assert_eq!(config.account_uuid, None);
        assert_eq!(config.pczt_path, None);
    }
}
