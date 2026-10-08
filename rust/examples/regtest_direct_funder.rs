//! Offline transaction builder for the direct-Zakura regtest fixture.
//!
//! This is deliberately not a wallet API. It spends a coinbase output mined to
//! one public, test-only key and creates an Ironwood payment to a regtest UA,
//! a pre-NU6.3 Orchard payment, or a transparent payment for native wallet E2E.

use std::{
    convert::Infallible,
    io::{self, Read},
};

use orchard::{keys::SpendAuthorizingKey, Anchor};
use sapling_crypto::{
    bundle::GrothProofBytes,
    circuit,
    keys::EphemeralSecretKey,
    prover::{OutputProver, SpendProver},
    value::{NoteValue, ValueCommitTrapdoor},
    Diversifier, MerklePath, PaymentAddress, ProofGenerationKey, Rseed,
};
use secp256k1::SecretKey;
use serde::{Deserialize, Serialize};
use transparent::{address::TransparentAddress, builder::TransparentSigningSet, bundle::OutPoint};
use voting_crypto_deps::rand::rngs::OsRng;
use zcash_keys::address::Address;
use zcash_primitives::transaction::{
    builder::{BuildConfig, Builder, BundlePadding},
    fees::zip317,
    Transaction,
};
use zcash_protocol::{
    consensus::{BlockHeight, BranchId, NetworkType, NetworkUpgrade, Parameters},
    memo::MemoBytes,
    value::Zatoshis,
};

const MAX_STDIN_BYTES: usize = 2 * 1024 * 1024;
const SCHEMA_VERSION: u32 = 1;
const COINBASE_MATURITY: u32 = 100;
const MIGRATION_NU6_3_ACTIVATION_HEIGHT: u32 = 500;
const MAX_BATCH_INPUTS: usize = 64;
const MAX_BATCH_PAYMENTS: usize = 500;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct BatchBuildRequest {
    schema_version: u32,
    coinbase_inputs: Vec<CoinbaseInput>,
    target_height: u64,
    recipient_pool: String,
    nu6_3_activation_height: u64,
    payments: Vec<BatchPayment>,
    expiry_height: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CoinbaseInput {
    coinbase_hex: String,
    coinbase_height: u64,
    coinbase_vout: u64,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct BatchPayment {
    recipient_address: String,
    amount_zatoshi: u64,
}

#[derive(Serialize)]
struct CoinbaseInputEvidence {
    coinbase_source_height: u64,
    coinbase_txid: String,
    coinbase_vout: u64,
    input_value_zatoshi: u64,
}

#[derive(Serialize)]
struct BatchBuildResponse {
    schema_version: u32,
    raw_tx_hex: String,
    txid: String,
    fee_zatoshi: u64,
    input_value_zatoshi: u64,
    amount_zatoshi: u64,
    change_zatoshi: u64,
    target_height: u64,
    expiry_height: u64,
    maturity_validated: bool,
    pools: Vec<&'static str>,
    coinbase_inputs: Vec<CoinbaseInputEvidence>,
    payments: Vec<BatchPayment>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct BuildRequest {
    schema_version: u32,
    coinbase_hex: String,
    coinbase_height: u64,
    coinbase_vout: u64,
    target_height: u64,
    recipient_address: String,
    amount_zatoshi: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct OrchardBuildRequest {
    schema_version: u32,
    coinbase_hex: String,
    coinbase_height: u64,
    coinbase_vout: u64,
    target_height: u64,
    recipient_address: String,
    amount_zatoshi: u64,
    nu6_3_activation_height: u64,
}

#[derive(Serialize)]
struct IdentityResponse {
    schema_version: u32,
    miner_address: String,
}

#[derive(Serialize)]
struct BuildResponse {
    schema_version: u32,
    raw_tx_hex: String,
    txid: String,
    fee_zatoshi: u64,
    input_value_zatoshi: u64,
    amount_zatoshi: u64,
    coinbase_source_height: u64,
    coinbase_txid: String,
    coinbase_vout: u64,
    change_zatoshi: u64,
    target_height: u64,
    maturity_validated: bool,
    pools: Vec<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    recipient_output: Option<TransparentOutputEvidence>,
}

#[derive(Serialize)]
struct TransparentOutputEvidence {
    address: String,
    vout: u32,
    script_hex: String,
    amount_zatoshi: u64,
}

#[derive(Clone, Copy)]
enum Recipient {
    Ironwood(orchard::Address),
    Orchard(orchard::Address),
    Transparent(TransparentAddress),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RecipientPool {
    Ironwood,
    Orchard,
    Transparent,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("regtest_direct_funder: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let command = args.next().ok_or_else(|| {
        "usage: regtest_direct_funder <identity|build|build-orchard|build-transparent|build-batch>".to_string()
    })?;
    if args.next().is_some() {
        return Err("unexpected command arguments".to_string());
    }

    let response = match command.as_str() {
        "identity" => serde_json::to_value(IdentityResponse {
            schema_version: SCHEMA_VERSION,
            miner_address: miner_address(),
        })
        .map_err(|error| format!("encode identity: {error}"))?,
        "build" | "build-transparent" => {
            let request = read_request(io::stdin().lock())?;
            let pool = if command == "build-transparent" {
                RecipientPool::Transparent
            } else {
                RecipientPool::Ironwood
            };
            serde_json::to_value(build_transaction(request, pool, regtest_network())?)
                .map_err(|error| format!("encode build result: {error}"))?
        }
        "build-orchard" => {
            let request = read_orchard_request(io::stdin().lock())?;
            serde_json::to_value(build_orchard_transaction(request)?)
                .map_err(|error| format!("encode build result: {error}"))?
        }
        "build-batch" => {
            let bytes = read_request_bytes(&mut io::stdin().lock())?;
            let request = serde_json::from_slice(&bytes)
                .map_err(|error| format!("decode batch request: {error}"))?;
            serde_json::to_value(build_batch_transaction(request)?)
                .map_err(|error| format!("encode batch result: {error}"))?
        }
        _ => return Err(format!("unknown command: {command}")),
    };

    println!(
        "{}",
        serde_json::to_string(&response).map_err(|error| format!("encode response: {error}"))?
    );
    Ok(())
}

fn read_request(mut reader: impl Read) -> Result<BuildRequest, String> {
    let bytes = read_request_bytes(&mut reader)?;
    serde_json::from_slice(&bytes).map_err(|error| format!("decode request: {error}"))
}

fn read_orchard_request(mut reader: impl Read) -> Result<OrchardBuildRequest, String> {
    let bytes = read_request_bytes(&mut reader)?;
    serde_json::from_slice(&bytes).map_err(|error| format!("decode request: {error}"))
}

fn read_request_bytes(reader: &mut impl Read) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    reader
        .by_ref()
        .take((MAX_STDIN_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|error| format!("read request: {error}"))?;
    if bytes.len() > MAX_STDIN_BYTES {
        return Err("request exceeds 2 MiB".to_string());
    }
    Ok(bytes)
}

#[derive(Clone, Copy)]
struct DirectRegtest {
    nu6_3_activation_height: BlockHeight,
}

impl Parameters for DirectRegtest {
    fn network_type(&self) -> NetworkType {
        NetworkType::Regtest
    }

    fn activation_height(&self, upgrade: NetworkUpgrade) -> Option<BlockHeight> {
        match upgrade {
            NetworkUpgrade::Overwinter
            | NetworkUpgrade::Sapling
            | NetworkUpgrade::Blossom
            | NetworkUpgrade::Heartwood
            | NetworkUpgrade::Canopy
            | NetworkUpgrade::Nu5
            | NetworkUpgrade::Nu6
            | NetworkUpgrade::Nu6_1
            | NetworkUpgrade::Nu6_2 => Some(BlockHeight::from_u32(1)),
            NetworkUpgrade::Nu6_3 => Some(self.nu6_3_activation_height),
            NetworkUpgrade::Nu7 => None,
        }
    }
}

fn regtest_network() -> DirectRegtest {
    DirectRegtest {
        nu6_3_activation_height: BlockHeight::from_u32(1),
    }
}

fn migration_network() -> DirectRegtest {
    DirectRegtest {
        nu6_3_activation_height: BlockHeight::from_u32(MIGRATION_NU6_3_ACTIVATION_HEIGHT),
    }
}

fn funding_secret_key() -> SecretKey {
    SecretKey::from_slice(&[1; 32]).expect("the public regtest funding key is valid")
}

fn funding_identity() -> (SecretKey, secp256k1::PublicKey, TransparentAddress) {
    let secret = funding_secret_key();
    let secp = secp256k1::Secp256k1::signing_only();
    let public = secp256k1::PublicKey::from_secret_key(&secp, &secret);
    let address = TransparentAddress::from_pubkey(&public);
    (secret, public, address)
}

fn miner_address() -> String {
    funding_identity()
        .2
        .to_zcash_address(NetworkType::Regtest)
        .to_string()
}

fn checked_height(value: u64, field: &str) -> Result<u32, String> {
    u32::try_from(value).map_err(|_| format!("{field} does not fit u32"))
}

fn checked_target_height(value: u64) -> Result<u32, String> {
    let height = checked_height(value, "target_height")?;
    if height == 0
        || height > u32::MAX - zcash_primitives::transaction::builder::DEFAULT_TX_EXPIRY_DELTA
    {
        return Err("target_height cannot represent the SDK expiry delta".into());
    }
    Ok(height)
}

fn read_coinbase(encoded: &str, branch: BranchId) -> Result<Transaction, String> {
    let raw = hex::decode(encoded).map_err(|error| format!("coinbase_hex is not hex: {error}"))?;
    let mut reader = io::Cursor::new(raw.as_slice());
    let transaction = Transaction::read(&mut reader, branch)
        .map_err(|error| format!("parse coinbase transaction: {error}"))?;
    if reader.position() != raw.len() as u64 {
        return Err("coinbase_hex has trailing bytes".into());
    }
    Ok(transaction)
}

fn validate_maturity(coinbase_height: u32, target_height: u32) -> Result<(), String> {
    if coinbase_height == 0 {
        return Err("coinbase_height must be positive".to_string());
    }
    let mature_height = coinbase_height
        .checked_add(COINBASE_MATURITY)
        .ok_or_else(|| "coinbase maturity height overflow".to_string())?;
    if target_height < mature_height {
        return Err(format!(
            "coinbase output is immature: target {target_height}, minimum {mature_height}"
        ));
    }
    Ok(())
}

fn decode_recipient(encoded: &str) -> Result<orchard::Address, String> {
    match Address::decode(&regtest_network(), encoded) {
        Some(Address::Unified(address)) => address
            .orchard()
            .copied()
            .ok_or_else(|| "recipient UA has no Orchard receiver".to_string()),
        Some(_) => Err("recipient_address must be a regtest Unified Address".to_string()),
        None => Err("recipient_address is not a valid regtest address".to_string()),
    }
}

fn decode_transparent_recipient(encoded: &str) -> Result<TransparentAddress, String> {
    match Address::decode(&regtest_network(), encoded) {
        Some(Address::Transparent(address)) => Ok(address),
        Some(_) => {
            Err("transparent recipient must be a standalone regtest transparent address".into())
        }
        None => Err("recipient_address is not a valid regtest address".into()),
    }
}

fn add_payment(
    builder: &mut Builder<DirectRegtest, ()>,
    recipient: Recipient,
    amount: Zatoshis,
) -> Result<(), String> {
    match recipient {
        Recipient::Ironwood(address) => builder
            .add_ironwood_output::<Infallible>(None, address, amount, MemoBytes::empty())
            .map_err(|error| format!("add Ironwood output: {error}")),
        Recipient::Orchard(address) => builder
            .add_orchard_output::<Infallible>(None, address, amount, MemoBytes::empty())
            .map_err(|error| format!("add Orchard output: {error}")),
        Recipient::Transparent(address) => builder
            .add_transparent_output(&address, amount)
            .map_err(|error| format!("add transparent payment: {error}")),
    }
}

fn build_transaction(
    request: BuildRequest,
    pool: RecipientPool,
    network: DirectRegtest,
) -> Result<BuildResponse, String> {
    if request.schema_version != SCHEMA_VERSION {
        return Err(format!(
            "unsupported schema_version: {}",
            request.schema_version
        ));
    }
    let amount = funding_amount(request.amount_zatoshi)?;

    let coinbase_height = checked_height(request.coinbase_height, "coinbase_height")?;
    let target_height = checked_target_height(request.target_height)?;
    let coinbase_vout = u32::try_from(request.coinbase_vout)
        .map_err(|_| "coinbase_vout does not fit u32".to_string())?;
    validate_maturity(coinbase_height, target_height)?;
    let recipient = match pool {
        RecipientPool::Ironwood => {
            Recipient::Ironwood(decode_recipient(&request.recipient_address)?)
        }
        RecipientPool::Orchard => Recipient::Orchard(decode_recipient(&request.recipient_address)?),
        RecipientPool::Transparent => {
            Recipient::Transparent(decode_transparent_recipient(&request.recipient_address)?)
        }
    };

    let source_branch = BranchId::for_height(&network, BlockHeight::from_u32(coinbase_height));
    let coinbase = read_coinbase(&request.coinbase_hex, source_branch)?;
    let coinbase_txid = coinbase.txid();
    let coinbase_data = coinbase.into_data();
    let transparent = coinbase_data
        .transparent_bundle()
        .ok_or_else(|| "coinbase transaction has no transparent bundle".to_string())?;
    if !transparent.is_coinbase() {
        return Err("coinbase_hex is not a coinbase transaction".to_string());
    }
    let coin = transparent
        .vout
        .get(coinbase_vout as usize)
        .cloned()
        .ok_or_else(|| "coinbase_vout is out of range".to_string())?;

    let (secret, public, miner) = funding_identity();
    if coin.recipient_address() != Some(miner) {
        return Err("coinbase output does not belong to the fixed regtest miner key".to_string());
    }
    let input_value = u64::from(coin.value());
    let outpoint = OutPoint::new(*coinbase_txid.as_ref(), coinbase_vout);
    let fee_rule = zip317::FeeRule::standard();

    let placeholder_change = Zatoshis::const_from_u64(1);
    let mut sizing_builder = new_builder_for(network, target_height, pool);
    sizing_builder
        .add_transparent_p2pkh_input(public, outpoint.clone(), coin.clone())
        .map_err(|error| format!("add transparent input: {error}"))?;
    add_payment(&mut sizing_builder, recipient, amount)?;
    sizing_builder
        .add_transparent_output(&miner, placeholder_change)
        .map_err(|error| format!("add placeholder change: {error}"))?;
    let fee = sizing_builder
        .get_fee(&fee_rule)
        .map_err(|error| format!("calculate ZIP-317 fee: {error}"))?;
    let fee_zatoshi = u64::from(fee);
    let change_zatoshi = input_value
        .checked_sub(request.amount_zatoshi)
        .and_then(|value| value.checked_sub(fee_zatoshi))
        .ok_or_else(|| "coinbase output does not cover amount and fee".to_string())?;
    if change_zatoshi == 0 {
        return Err("coinbase output leaves no transparent change".to_string());
    }
    let change = Zatoshis::from_u64(change_zatoshi)
        .map_err(|_| "transparent change is outside the valid range".to_string())?;

    let mut builder = new_builder_for(network, target_height, pool);
    builder
        .add_transparent_p2pkh_input(public, outpoint, coin)
        .map_err(|error| format!("add transparent input: {error}"))?;
    add_payment(&mut builder, recipient, amount)?;
    builder
        .add_transparent_output(&miner, change)
        .map_err(|error| format!("add transparent change: {error}"))?;
    let final_fee = builder
        .get_fee(&fee_rule)
        .map_err(|error| format!("recalculate ZIP-317 fee: {error}"))?;
    if final_fee != fee {
        return Err("ZIP-317 fee changed after replacing placeholder change".to_string());
    }

    let mut signing_set = TransparentSigningSet::new();
    let signing_public = signing_set.add_key(secret);
    if signing_public != public {
        return Err("fixed signing key identity changed".to_string());
    }
    let result = builder
        .build(
            &signing_set,
            &[],
            &[] as &[SpendAuthorizingKey],
            OsRng,
            &NoSaplingSpendProver,
            &NoSaplingOutputProver,
            &fee_rule,
        )
        .map_err(|error| format!("build transaction: {error}"))?;
    let transaction = result.transaction();
    let mut raw = Vec::new();
    transaction
        .write(&mut raw)
        .map_err(|error| format!("serialize transaction: {error}"))?;

    let recipient_output = if let Recipient::Transparent(address) = recipient {
        let target_branch = BranchId::for_height(&network, BlockHeight::from_u32(target_height));
        let decoded = Transaction::read(&raw[..], target_branch)
            .map_err(|error| format!("reparse transparent funding: {error}"))?;
        if decoded.sapling_bundle().is_some()
            || decoded.orchard_bundle().is_some()
            || decoded.ironwood_bundle().is_some()
        {
            return Err("transparent funding unexpectedly has shielded payloads".into());
        }
        let bundle = decoded
            .transparent_bundle()
            .ok_or("transparent funding has no outputs")?;
        let outputs: Vec<_> = bundle
            .vout
            .iter()
            .enumerate()
            .filter(|(_, output)| {
                output.recipient_address() == Some(address) && output.value() == amount
            })
            .collect();
        if outputs.len() != 1 {
            return Err("transparent funding must have exactly one recipient output".into());
        }
        let (vout, output) = outputs[0];
        Some(TransparentOutputEvidence {
            address: request.recipient_address.clone(),
            vout: u32::try_from(vout).map_err(|_| "recipient vout exceeds u32")?,
            script_hex: hex::encode(&output.script_pubkey().0 .0),
            amount_zatoshi: request.amount_zatoshi,
        })
    } else {
        None
    };

    Ok(BuildResponse {
        schema_version: SCHEMA_VERSION,
        raw_tx_hex: hex::encode(raw),
        txid: transaction.txid().to_string(),
        fee_zatoshi,
        input_value_zatoshi: input_value,
        amount_zatoshi: request.amount_zatoshi,
        coinbase_source_height: request.coinbase_height,
        coinbase_txid: coinbase_txid.to_string(),
        coinbase_vout: request.coinbase_vout,
        change_zatoshi,
        target_height: request.target_height,
        maturity_validated: true,
        pools: match pool {
            RecipientPool::Transparent => vec!["transparent"],
            RecipientPool::Orchard => vec!["transparent", "orchard"],
            RecipientPool::Ironwood => vec!["transparent", "ironwood"],
        },
        recipient_output,
    })
}

fn build_orchard_transaction(request: OrchardBuildRequest) -> Result<BuildResponse, String> {
    let activation_height =
        checked_height(request.nu6_3_activation_height, "nu6_3_activation_height")?;
    if activation_height != MIGRATION_NU6_3_ACTIVATION_HEIGHT {
        return Err(format!(
            "nu6_3_activation_height must be {MIGRATION_NU6_3_ACTIVATION_HEIGHT}"
        ));
    }
    let target_height = checked_height(request.target_height, "target_height")?;
    if target_height >= activation_height {
        return Err("Orchard funding target must be before NU6.3 activation".to_string());
    }
    build_transaction(
        BuildRequest {
            schema_version: request.schema_version,
            coinbase_hex: request.coinbase_hex,
            coinbase_height: request.coinbase_height,
            coinbase_vout: request.coinbase_vout,
            target_height: request.target_height,
            recipient_address: request.recipient_address,
            amount_zatoshi: request.amount_zatoshi,
        },
        RecipientPool::Orchard,
        migration_network(),
    )
}

fn funding_amount(value: u64) -> Result<Zatoshis, String> {
    if value == 0 {
        return Err("amount_zatoshi must be positive".to_string());
    }
    Zatoshis::from_u64(value).map_err(|_| "amount_zatoshi is outside the valid range".to_string())
}

fn build_batch_transaction(request: BatchBuildRequest) -> Result<BatchBuildResponse, String> {
    if request.schema_version != SCHEMA_VERSION
        || request.coinbase_inputs.is_empty()
        || request.coinbase_inputs.len() > MAX_BATCH_INPUTS
        || request.payments.is_empty()
        || request.payments.len() > MAX_BATCH_PAYMENTS
    {
        return Err("batch schema or input/payment count is invalid".into());
    }
    let target = checked_target_height(request.target_height)?;
    let activation = checked_height(request.nu6_3_activation_height, "nu6_3_activation_height")?;
    if ![1, MIGRATION_NU6_3_ACTIVATION_HEIGHT].contains(&activation) {
        return Err("batch activation height must be 1 or 500".into());
    }
    let pool = match request.recipient_pool.as_str() {
        "ironwood" if target >= activation => RecipientPool::Ironwood,
        "orchard" if activation == 500 && target < activation => RecipientPool::Orchard,
        "transparent" => RecipientPool::Transparent,
        _ => return Err("batch recipient pool is not active at target height".into()),
    };
    let expiry = request
        .expiry_height
        .map(|value| checked_height(value, "expiry_height"))
        .transpose()?;
    if expiry.is_some_and(|height| height <= target || height > target.saturating_add(10_000)) {
        return Err("expiry_height must be after target and at most 10000 blocks later".into());
    }
    let network = DirectRegtest {
        nu6_3_activation_height: activation.into(),
    };
    let (secret, public, miner) = funding_identity();
    let mut inputs = Vec::new();
    let mut input_evidence = Vec::new();
    let mut outpoints = std::collections::HashSet::new();
    let mut input_value = 0u64;
    for source in &request.coinbase_inputs {
        let height = checked_height(source.coinbase_height, "coinbase_height")?;
        validate_maturity(height, target)?;
        let vout = checked_height(source.coinbase_vout, "coinbase_vout")?;
        let tx = read_coinbase(
            &source.coinbase_hex,
            BranchId::for_height(&network, height.into()),
        )?;
        let txid = tx.txid();
        let bundle = tx
            .transparent_bundle()
            .ok_or("batch coinbase has no transparent bundle")?;
        if !bundle.is_coinbase() {
            return Err("batch source is not coinbase".into());
        }
        let coin = bundle
            .vout
            .get(vout as usize)
            .cloned()
            .ok_or("batch coinbase vout out of range")?;
        if coin.recipient_address() != Some(miner) || !outpoints.insert((txid.to_string(), vout)) {
            return Err("batch source is not fixed-miner or repeats an outpoint".into());
        }
        let value = u64::from(coin.value());
        input_value = input_value
            .checked_add(value)
            .ok_or("batch input sum overflow")?;
        funding_amount(input_value)?;
        inputs.push((OutPoint::new(*txid.as_ref(), vout), coin));
        input_evidence.push(CoinbaseInputEvidence {
            coinbase_source_height: source.coinbase_height,
            coinbase_txid: txid.to_string(),
            coinbase_vout: source.coinbase_vout,
            input_value_zatoshi: value,
        });
    }
    let mut payments = Vec::new();
    let mut total = 0u64;
    for payment in &request.payments {
        let amount = funding_amount(payment.amount_zatoshi)?;
        total = total
            .checked_add(payment.amount_zatoshi)
            .ok_or("batch payment sum overflow")?;
        funding_amount(total)?;
        let recipient = match pool {
            RecipientPool::Ironwood => {
                Recipient::Ironwood(decode_recipient(&payment.recipient_address)?)
            }
            RecipientPool::Orchard => {
                Recipient::Orchard(decode_recipient(&payment.recipient_address)?)
            }
            RecipientPool::Transparent => {
                Recipient::Transparent(decode_transparent_recipient(&payment.recipient_address)?)
            }
        };
        payments.push((recipient, amount));
    }
    let make_builder = || {
        let builder = new_builder_for(network, target, pool);
        match expiry {
            Some(height) => builder.with_expiry_height(height.into()),
            None => builder,
        }
    };
    let populate =
        |builder: &mut Builder<DirectRegtest, ()>, change: Zatoshis| -> Result<(), String> {
            for (outpoint, coin) in &inputs {
                builder
                    .add_transparent_p2pkh_input(public, outpoint.clone(), coin.clone())
                    .map_err(|error| format!("batch transparent input: {error}"))?;
            }
            for (recipient, amount) in &payments {
                add_payment(builder, *recipient, *amount)?;
            }
            builder
                .add_transparent_output(&miner, change)
                .map_err(|error| format!("batch change: {error}"))
        };
    let fee_rule = zip317::FeeRule::standard();
    let mut sizing = make_builder();
    populate(&mut sizing, Zatoshis::const_from_u64(1))?;
    let fee = sizing
        .get_fee(&fee_rule)
        .map_err(|error| format!("batch fee: {error}"))?;
    let change = input_value
        .checked_sub(total)
        .and_then(|value| value.checked_sub(u64::from(fee)))
        .filter(|value| *value > 0)
        .ok_or("batch inputs do not cover payments, fee and positive change")?;
    let mut builder = make_builder();
    populate(&mut builder, funding_amount(change)?)?;
    if builder
        .get_fee(&fee_rule)
        .map_err(|error| format!("batch final fee: {error}"))?
        != fee
    {
        return Err("batch fee changed after sizing".into());
    }
    let mut signing = TransparentSigningSet::new();
    if signing.add_key(secret) != public {
        return Err("batch signing key identity changed".into());
    }
    let result = builder
        .build(
            &signing,
            &[],
            &[],
            OsRng,
            &NoSaplingSpendProver,
            &NoSaplingOutputProver,
            &fee_rule,
        )
        .map_err(|error| format!("build batch: {error}"))?;
    let tx = result.transaction();
    if tx.sapling_bundle().is_some()
        || (pool != RecipientPool::Orchard && tx.orchard_bundle().is_some())
        || (pool != RecipientPool::Ironwood && tx.ironwood_bundle().is_some())
        || tx.transparent_bundle().map(|bundle| bundle.vin.len()) != Some(inputs.len())
    {
        return Err("batch transaction pool/input evidence differs".into());
    }
    if pool != RecipientPool::Transparent {
        let meta = if pool == RecipientPool::Orchard {
            result.orchard_meta()
        } else {
            result.ironwood_meta()
        };
        let positions: std::collections::HashSet<_> = (0..payments.len())
            .map(|index| {
                meta.output_action_index(index)
                    .ok_or("batch output omitted")
            })
            .collect::<Result<_, _>>()?;
        if positions.len() != payments.len() || meta.output_action_index(payments.len()).is_some() {
            return Err("batch repeated output mapping differs".into());
        }
    } else {
        let bundle = tx
            .transparent_bundle()
            .ok_or("batch transparent outputs omitted")?;
        for (recipient, amount) in &payments {
            let Recipient::Transparent(address) = recipient else {
                unreachable!()
            };
            let expected = payments.iter().filter(|(other, value)| {
                matches!(other, Recipient::Transparent(other_address) if other_address == address) && value == amount
            }).count();
            let actual = bundle
                .vout
                .iter()
                .filter(|output| {
                    output.recipient_address() == Some(*address) && output.value() == *amount
                })
                .count();
            if actual != expected {
                return Err("batch transparent repeated outputs differ".into());
            }
        }
    }
    let mut raw = Vec::new();
    tx.write(&mut raw)
        .map_err(|error| format!("serialize batch: {error}"))?;
    Ok(BatchBuildResponse {
        schema_version: SCHEMA_VERSION,
        raw_tx_hex: hex::encode(raw),
        txid: tx.txid().to_string(),
        fee_zatoshi: u64::from(fee),
        input_value_zatoshi: input_value,
        amount_zatoshi: total,
        change_zatoshi: change,
        target_height: request.target_height,
        expiry_height: u64::from(u32::from(tx.expiry_height())),
        maturity_validated: true,
        pools: match pool {
            RecipientPool::Transparent => vec!["transparent"],
            RecipientPool::Orchard => vec!["transparent", "orchard"],
            RecipientPool::Ironwood => vec!["transparent", "ironwood"],
        },
        coinbase_inputs: input_evidence,
        payments: request.payments,
    })
}

#[cfg(test)]
fn new_builder(target_height: u32) -> Builder<DirectRegtest, ()> {
    new_builder_for(regtest_network(), target_height, RecipientPool::Ironwood)
}

fn new_builder_for(
    network: DirectRegtest,
    target_height: u32,
    pool: RecipientPool,
) -> Builder<DirectRegtest, ()> {
    Builder::new(
        network,
        BlockHeight::from_u32(target_height),
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: (pool == RecipientPool::Orchard).then(Anchor::empty_tree),
            ironwood_anchor: (pool == RecipientPool::Ironwood).then(Anchor::empty_tree),
            orchard_padding: BundlePadding::DEFAULT,
            ironwood_padding: BundlePadding::DEFAULT,
        },
    )
}

struct NoSaplingSpendProver;

impl SpendProver for NoSaplingSpendProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _: ProofGenerationKey,
        _: Diversifier,
        _: Rseed,
        _: NoteValue,
        _: jubjub::Fr,
        _: ValueCommitTrapdoor,
        _: bls12_381::Scalar,
        _: MerklePath,
    ) -> Option<circuit::Spend> {
        panic!("unexpected Sapling spend in direct funder")
    }

    fn create_proof<R: voting_crypto_deps::rand::Rng>(
        &self,
        _: circuit::Spend,
        _: &mut R,
    ) -> Self::Proof {
        panic!("unexpected Sapling spend proof in direct funder")
    }

    fn encode_proof(_: Self::Proof) -> GrothProofBytes {
        panic!("unexpected Sapling spend proof encoding in direct funder")
    }
}

struct NoSaplingOutputProver;

impl OutputProver for NoSaplingOutputProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _: &EphemeralSecretKey,
        _: PaymentAddress,
        _: jubjub::Fr,
        _: NoteValue,
        _: ValueCommitTrapdoor,
    ) -> circuit::Output {
        panic!("unexpected Sapling output in direct funder")
    }

    fn create_proof<R: voting_crypto_deps::rand::Rng>(
        &self,
        _: circuit::Output,
        _: &mut R,
    ) -> Self::Proof {
        panic!("unexpected Sapling output proof in direct funder")
    }

    fn encode_proof(_: Self::Proof) -> GrothProofBytes {
        panic!("unexpected Sapling output proof encoding in direct funder")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn batch_request(count: usize) -> BatchBuildRequest {
        let spending = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
        let recipient = orchard::keys::FullViewingKey::from(&spending)
            .address_at(0u32, orchard::keys::Scope::External);
        let address = Address::Unified(
            zcash_keys::address::UnifiedAddress::from_receivers(Some(recipient), None, None)
                .unwrap(),
        )
        .encode(&migration_network());
        let inputs = (2..=3)
            .map(|height| {
                let bundle = transparent::bundle::Bundle {
                    vin: vec![transparent::bundle::TxIn::from_parts(
                        OutPoint::new([0; 32], u32::MAX),
                        transparent::address::Script::default(),
                        u32::MAX,
                    )],
                    vout: vec![transparent::bundle::TxOut::new(
                        Zatoshis::const_from_u64(625_000_000),
                        funding_identity().2.script().into(),
                    )],
                    authorization: transparent::bundle::Authorized,
                };
                let tx = zcash_primitives::transaction::TransactionData::<
                    zcash_primitives::transaction::Authorized,
                >::from_parts(
                    zcash_primitives::transaction::TxVersion::V5,
                    BranchId::Nu6_2,
                    0,
                    BlockHeight::from_u32(height),
                    Some(bundle),
                    None,
                    None,
                    None,
                )
                .freeze()
                .unwrap();
                let mut raw = Vec::new();
                tx.write(&mut raw).unwrap();
                CoinbaseInput {
                    coinbase_hex: hex::encode(raw),
                    coinbase_height: u64::from(height),
                    coinbase_vout: 0,
                }
            })
            .collect();
        BatchBuildRequest {
            schema_version: 1,
            coinbase_inputs: inputs,
            target_height: 104,
            recipient_pool: "orchard".into(),
            nu6_3_activation_height: 500,
            payments: (0..count)
                .map(|_| BatchPayment {
                    recipient_address: address.clone(),
                    amount_zatoshi: 50_001_000,
                })
                .collect(),
            expiry_height: Some(120),
        }
    }

    #[test]
    fn batch_twenty_notes_spend_multiple_mature_coinbases_with_controlled_expiry() {
        let result = build_batch_transaction(batch_request(20)).unwrap();
        assert_eq!(result.amount_zatoshi, 1_000_020_000);
        assert_eq!(result.input_value_zatoshi, 1_250_000_000);
        assert_eq!(result.coinbase_inputs.len(), 2);
        assert_eq!(result.payments.len(), 20);
        assert_eq!(result.expiry_height, 120);
        assert_eq!(
            result.input_value_zatoshi,
            result.amount_zatoshi + result.fee_zatoshi + result.change_zatoshi
        );
        let raw = hex::decode(result.raw_tx_hex).unwrap();
        let tx = Transaction::read(&raw[..], BranchId::Nu6_2).unwrap();
        assert!(tx.ironwood_bundle().is_none());
        assert!(tx.sapling_bundle().is_none());
        assert_eq!(tx.orchard_bundle().unwrap().actions().len(), 20);
        assert_eq!(tx.transparent_bundle().unwrap().vin.len(), 2);
    }

    #[test]
    fn batch_rejects_bounds_duplicate_inputs_and_expiry_aliases() {
        let mut request = batch_request(501);
        assert!(build_batch_transaction(request)
            .err()
            .unwrap()
            .contains("count"));
        request = batch_request(20);
        request.expiry_height = Some(104);
        assert!(build_batch_transaction(request)
            .err()
            .unwrap()
            .contains("expiry_height"));
        request = batch_request(20);
        request.coinbase_inputs[1].coinbase_hex = request.coinbase_inputs[0].coinbase_hex.clone();
        assert!(build_batch_transaction(request)
            .err()
            .unwrap()
            .contains("repeats"));
        request = batch_request(20);
        request.coinbase_inputs[1].coinbase_height = 5;
        assert!(build_batch_transaction(request)
            .err()
            .unwrap()
            .contains("immature"));
    }

    #[test]
    fn batch_fifty_repeated_notes_preserve_every_output() {
        let mut request = batch_request(50);
        for payment in &mut request.payments {
            payment.amount_zatoshi = 2_000_020;
        }
        let result = build_batch_transaction(request).unwrap();
        assert_eq!(result.amount_zatoshi, 100_001_000);
        assert_eq!(result.payments.len(), 50);
        let raw = hex::decode(result.raw_tx_hex).unwrap();
        let tx = Transaction::read(&raw[..], BranchId::Nu6_2).unwrap();
        assert_eq!(tx.orchard_bundle().unwrap().actions().len(), 50);
    }

    #[test]
    fn batch_schema_rejects_unknown_fields_and_bool_integer_aliases() {
        for value in [
            br#"{"schema_version":true,"coinbase_inputs":[],"target_height":104,"recipient_pool":"orchard","nu6_3_activation_height":500,"payments":[],"expiry_height":120}"#.as_slice(),
            br#"{"schema_version":1,"coinbase_inputs":[],"target_height":104,"recipient_pool":"orchard","nu6_3_activation_height":500,"payments":[],"expiry_height":120,"unexpected":true}"#.as_slice(),
        ] { assert!(serde_json::from_slice::<BatchBuildRequest>(value).is_err()); }
    }

    #[test]
    fn identity_is_stable_regtest_p2pkh() {
        let encoded = miner_address();
        assert_eq!(
            Address::decode(&regtest_network(), &encoded),
            Some(Address::Transparent(funding_identity().2))
        );
    }

    #[test]
    fn transparent_recipient_is_network_checked() {
        let address = funding_identity().2;
        assert_eq!(decode_transparent_recipient(&miner_address()), Ok(address));
        assert!(decode_transparent_recipient(
            &address.to_zcash_address(NetworkType::Main).to_string()
        )
        .is_err());
        assert!(decode_transparent_recipient("uregtest1invalid").is_err());
    }

    #[test]
    fn transparent_payment_has_no_shielded_payload() {
        let (secret, public, miner) = funding_identity();
        let recipient = TransparentAddress::PublicKeyHash([9; 20]);
        let mut builder = new_builder_for(regtest_network(), 104, RecipientPool::Transparent);
        builder
            .add_transparent_p2pkh_input(
                public,
                OutPoint::new([2; 32], 0),
                transparent::bundle::TxOut::new(
                    Zatoshis::const_from_u64(200_000_000),
                    miner.script().into(),
                ),
            )
            .unwrap();
        let amount = Zatoshis::const_from_u64(75_000_000);
        add_payment(&mut builder, Recipient::Transparent(recipient), amount).unwrap();
        builder
            .add_transparent_output(&miner, Zatoshis::const_from_u64(124_990_000))
            .unwrap();
        let fee_rule = zip317::FeeRule::standard();
        assert_eq!(u64::from(builder.get_fee(&fee_rule).unwrap()), 10_000);
        let mut signing = TransparentSigningSet::new();
        signing.add_key(secret);
        let result = builder
            .build(
                &signing,
                &[],
                &[],
                OsRng,
                &NoSaplingSpendProver,
                &NoSaplingOutputProver,
                &fee_rule,
            )
            .unwrap();
        let tx = result.transaction();
        assert!(tx.sapling_bundle().is_none());
        assert!(tx.orchard_bundle().is_none());
        assert!(tx.ironwood_bundle().is_none());
        assert_eq!(
            tx.transparent_bundle()
                .unwrap()
                .vout
                .iter()
                .filter(|output| {
                    output.recipient_address() == Some(recipient) && output.value() == amount
                })
                .count(),
            1
        );
    }

    #[test]
    fn rejects_immature_and_overflowing_heights() {
        assert!(validate_maturity(2, 101).unwrap_err().contains("immature"));
        assert!(validate_maturity(u32::MAX, u32::MAX)
            .unwrap_err()
            .contains("overflow"));
        assert!(checked_height(u64::from(u32::MAX) + 1, "height").is_err());
        assert!(checked_target_height(0).is_err());
        assert!(checked_target_height(u64::from(u32::MAX)).is_err());
        let maximum = u32::MAX - zcash_primitives::transaction::builder::DEFAULT_TX_EXPIRY_DELTA;
        assert_eq!(checked_target_height(u64::from(maximum)).unwrap(), maximum);
    }

    #[test]
    fn coinbase_encoding_must_consume_the_entire_input() {
        let request = batch_request(1);
        let encoded = &request.coinbase_inputs[0].coinbase_hex;
        assert!(read_coinbase(encoded, BranchId::Nu6_2).is_ok());
        assert!(read_coinbase(&format!("{encoded}00"), BranchId::Nu6_2)
            .err()
            .unwrap()
            .contains("trailing bytes"));
    }

    #[test]
    fn request_schema_rejects_unknown_fields() {
        let request = br#"{
            "schema_version":1,
            "coinbase_hex":"00",
            "coinbase_height":2,
            "coinbase_vout":0,
            "target_height":102,
            "recipient_address":"u1",
            "amount_zatoshi":100000000,
            "unexpected":true
        }"#;
        assert!(read_request(&request[..])
            .unwrap_err()
            .contains("unknown field"));
    }

    #[test]
    fn request_is_bounded() {
        let oversized = vec![b' '; MAX_STDIN_BYTES + 1];
        assert_eq!(
            read_request(&oversized[..]).unwrap_err(),
            "request exceeds 2 MiB"
        );
    }

    #[test]
    fn variable_funding_amounts_are_positive_and_money_bounded() {
        for amount in [1, 80_000_000, 140_000_000, 160_000_000, 200_000_000] {
            assert_eq!(u64::from(funding_amount(amount).unwrap()), amount);
        }
        assert!(funding_amount(0).is_err());
        assert!(funding_amount(2_100_000_000_000_001).is_err());
        assert!(funding_amount(u64::MAX).is_err());
    }

    #[test]
    fn nu6_3_external_recipient_uses_ironwood_not_orchard() {
        let spending_key = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
        let recipient = orchard::keys::FullViewingKey::from(&spending_key)
            .address_at(0u32, orchard::keys::Scope::External);
        let amount = Zatoshis::const_from_u64(100_000_000);

        let mut ironwood = new_builder(102);
        assert!(ironwood
            .add_ironwood_output::<Infallible>(None, recipient, amount, MemoBytes::empty())
            .is_ok());

        let mut orchard = new_builder_for(
            migration_network(),
            MIGRATION_NU6_3_ACTIVATION_HEIGHT,
            RecipientPool::Orchard,
        );
        assert!(matches!(
            orchard.add_orchard_output::<Infallible>(None, recipient, amount, MemoBytes::empty()),
            Err(
                zcash_primitives::transaction::builder::Error::OrchardRecipient(
                    orchard::builder::OutputError::CrossAddressDisabled
                )
            )
        ));
    }

    #[test]
    fn migration_profile_selects_pre_and_post_activation_branches() {
        let network = migration_network();
        assert_eq!(
            BranchId::for_height(
                &network,
                BlockHeight::from_u32(MIGRATION_NU6_3_ACTIVATION_HEIGHT - 1)
            ),
            BranchId::Nu6_2
        );
        assert_eq!(
            BranchId::for_height(
                &network,
                BlockHeight::from_u32(MIGRATION_NU6_3_ACTIVATION_HEIGHT)
            ),
            BranchId::Nu6_3
        );
    }

    #[test]
    fn preactivation_orchard_payment_builds_only_an_orchard_bundle() {
        let (secret, public, miner) = funding_identity();
        let spending_key = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
        let recipient = orchard::keys::FullViewingKey::from(&spending_key)
            .address_at(0u32, orchard::keys::Scope::External);
        let target_height = MIGRATION_NU6_3_ACTIVATION_HEIGHT - 1;
        let amount = Zatoshis::const_from_u64(75_000_000);
        let input = transparent::bundle::TxOut::new(
            Zatoshis::const_from_u64(200_000_000),
            miner.script().into(),
        );
        let outpoint = OutPoint::new([3; 32], 0);
        let fee_rule = zip317::FeeRule::standard();

        let mut sizing =
            new_builder_for(migration_network(), target_height, RecipientPool::Orchard);
        sizing
            .add_transparent_p2pkh_input(public, outpoint.clone(), input.clone())
            .unwrap();
        add_payment(&mut sizing, Recipient::Orchard(recipient), amount).unwrap();
        sizing
            .add_transparent_output(&miner, Zatoshis::const_from_u64(1))
            .unwrap();
        let fee = sizing.get_fee(&fee_rule).unwrap();
        let change = Zatoshis::from_u64(200_000_000 - 75_000_000 - u64::from(fee)).unwrap();

        let mut builder =
            new_builder_for(migration_network(), target_height, RecipientPool::Orchard);
        builder
            .add_transparent_p2pkh_input(public, outpoint, input)
            .unwrap();
        add_payment(&mut builder, Recipient::Orchard(recipient), amount).unwrap();
        builder.add_transparent_output(&miner, change).unwrap();
        assert_eq!(builder.get_fee(&fee_rule).unwrap(), fee);
        let mut signing = TransparentSigningSet::new();
        signing.add_key(secret);
        let result = builder
            .build(
                &signing,
                &[],
                &[],
                OsRng,
                &NoSaplingSpendProver,
                &NoSaplingOutputProver,
                &fee_rule,
            )
            .unwrap();
        let tx = result.transaction();
        assert!(tx.transparent_bundle().is_some());
        assert!(tx.sapling_bundle().is_none());
        assert!(tx.orchard_bundle().is_some());
        assert!(tx.ironwood_bundle().is_none());
    }

    #[test]
    fn orchard_request_requires_fixed_activation_and_preactivation_target() {
        let request = |activation, target| OrchardBuildRequest {
            schema_version: SCHEMA_VERSION,
            coinbase_hex: "00".to_string(),
            coinbase_height: 2,
            coinbase_vout: 0,
            target_height: target,
            recipient_address: "uregtest1invalid".to_string(),
            amount_zatoshi: 100_000_000,
            nu6_3_activation_height: activation,
        };
        assert!(build_orchard_transaction(request(499, 102))
            .err()
            .unwrap()
            .contains("must be 500"));
        assert!(build_orchard_transaction(request(500, 500))
            .err()
            .unwrap()
            .contains("before NU6.3"));
    }

    #[test]
    fn orchard_request_schema_is_distinct_and_strict() {
        let request = br#"{
            "schema_version":1,
            "coinbase_hex":"00",
            "coinbase_height":2,
            "coinbase_vout":0,
            "target_height":499,
            "recipient_address":"u1",
            "amount_zatoshi":100000000,
            "nu6_3_activation_height":500,
            "unexpected":true
        }"#;
        assert!(read_orchard_request(&request[..])
            .unwrap_err()
            .contains("unknown field"));
    }
}
