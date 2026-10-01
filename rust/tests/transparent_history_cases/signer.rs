//! The S builder: a Rust transaction builder that signs with runtime-derived
//! transparent keys and broadcasts through lightwalletd. It builds the shapes
//! Vizor cannot (shared funding, chosen inputs, mixed transparent/Orchard
//! outputs) without going through any Vizor code.

use serde_json::json;
use transparent::{
    address::{Script, TransparentAddress},
    builder::TransparentSigningSet,
    bundle::{OutPoint, TxOut},
};
use voting_crypto_deps::rand::rngs::OsRng;
use zcash_primitives::transaction::{
    builder::{BuildConfig, Builder, BundlePadding},
    fees::zip317::FeeRule,
};
use zcash_protocol::{consensus::BlockHeight, memo::MemoBytes, value::Zatoshis};

use crate::{
    chain::Chain,
    keys::{Party, Scope, NETWORK},
};

/// A spendable transparent output owned by a harness-known key.
#[derive(Clone, Debug)]
pub struct Coin {
    /// Display-order txid.
    pub txid: String,
    pub index: u32,
    pub value: u64,
    pub address: String,
}

pub enum Out {
    T(TransparentAddress, u64),
    Orchard(orchard::Address, u64),
}

pub struct Built {
    pub txid: String,
    pub raw: Vec<u8>,
}

/// The coin created by output `index` of `txid`.
pub fn coin_at(chain: &Chain, txid: &str, index: u32) -> Coin {
    let tx = chain.rpc_ok("getrawtransaction", json!([txid, 1]));
    let vout = &tx["vout"][index as usize];
    Coin {
        txid: txid.to_string(),
        index,
        value: vout["valueZat"].as_u64().unwrap(),
        address: vout["scriptPubKey"]["addresses"][0]
            .as_str()
            .unwrap()
            .to_string(),
    }
}

fn display_to_bytes(txid: &str) -> [u8; 32] {
    let mut bytes: [u8; 32] = hex::decode(txid).unwrap().try_into().unwrap();
    bytes.reverse();
    bytes
}

fn builder(
    target: BlockHeight,
    inputs: &[(Coin, &Party, Scope, u32)],
    outputs: &[Out],
    change: Option<(&TransparentAddress, u64)>,
    signing: &mut TransparentSigningSet,
) -> Builder<rust_lib_zcash_wallet::wallet::network::WalletNetwork, ()> {
    let has_orchard = outputs.iter().any(|o| matches!(o, Out::Orchard(..)));
    let mut builder = Builder::new(
        NETWORK,
        target,
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: has_orchard.then(orchard::Anchor::empty_tree),
            ironwood_anchor: None,
            orchard_padding: BundlePadding::DEFAULT,
            ironwood_padding: BundlePadding::DEFAULT,
        },
    );
    for (coin, party, scope, index) in inputs {
        let address = party.taddr(*scope, *index);
        assert_eq!(
            party.address(*scope, *index),
            coin.address,
            "coin {}:{} is not at the signing key's address",
            coin.txid,
            coin.index
        );
        let pubkey = signing.add_key(party.secret_key(*scope, *index));
        builder
            .add_transparent_p2pkh_input(
                pubkey,
                OutPoint::new(display_to_bytes(&coin.txid), coin.index),
                TxOut::new(
                    Zatoshis::from_u64(coin.value).unwrap(),
                    Script::from(address.script()),
                ),
            )
            .expect("transparent input");
    }
    for output in outputs {
        match output {
            Out::T(address, value) => builder
                .add_transparent_output(address, Zatoshis::from_u64(*value).unwrap())
                .expect("transparent output"),
            Out::Orchard(address, value) => builder
                .add_orchard_output::<std::convert::Infallible>(
                    None,
                    *address,
                    Zatoshis::from_u64(*value).unwrap(),
                    MemoBytes::empty(),
                )
                .expect("orchard output"),
        }
    }
    if let Some((address, value)) = change {
        builder
            .add_transparent_output(address, Zatoshis::from_u64(value).unwrap())
            .expect("change output");
    }
    builder
}

/// Builds and signs a transaction. With `change`, the change output takes the
/// remainder after the ZIP 317 fee; without it, inputs must cover outputs + fee
/// exactly.
pub fn build(
    chain: &Chain,
    inputs: &[(Coin, &Party, Scope, u32)],
    outputs: &[Out],
    change: Option<&TransparentAddress>,
) -> Built {
    let target = BlockHeight::from_u32(chain.tip() as u32 + 1);
    let total_in: u64 = inputs.iter().map(|(c, ..)| c.value).sum();
    let total_out: u64 = outputs
        .iter()
        .map(|o| match o {
            Out::T(_, v) | Out::Orchard(_, v) => *v,
        })
        .sum();
    let fee_rule = FeeRule::standard();
    // ZIP 317 fees depend only on the shape, so a placeholder change value works.
    let fee = {
        let mut signing = TransparentSigningSet::new();
        let probe = builder(
            target,
            inputs,
            outputs,
            change.map(|a| (a, total_in - total_out)),
            &mut signing,
        );
        u64::from(probe.get_fee(&fee_rule).expect("fee"))
    };
    let change_value = change.map(|a| {
        let value = total_in
            .checked_sub(total_out + fee)
            .expect("inputs cover outputs and fee");
        (a, value)
    });
    let mut signing = TransparentSigningSet::new();
    let builder = builder(target, inputs, outputs, change_value, &mut signing);
    let result = builder
        .build(
            &signing,
            &[],
            &[],
            OsRng,
            &crate::provers::NoOpSpendProver,
            &crate::provers::NoOpOutputProver,
            &fee_rule,
        )
        .expect("build transaction");
    let tx = result.transaction();
    let mut raw = Vec::new();
    tx.write(&mut raw).expect("serialize transaction");
    Built {
        txid: tx.txid().to_string(),
        raw,
    }
}

/// Broadcasts through lightwalletd's `SendTransaction`, not through zcashd.
pub fn broadcast(lwd_url: &str, raw: &[u8]) -> Result<(), String> {
    use zcash_client_backend::proto::service::{
        compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction,
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let channel = tonic::transport::Endpoint::from_shared(lwd_url.to_string())
            .map_err(|e| e.to_string())?
            .connect()
            .await
            .map_err(|e| e.to_string())?;
        let response = CompactTxStreamerClient::new(channel)
            .send_transaction(RawTransaction {
                data: raw.to_vec(),
                height: 0,
            })
            .await
            .map_err(|e| e.to_string())?
            .into_inner();
        if response.error_code != 0 {
            return Err(format!(
                "SendTransaction {}: {}",
                response.error_code, response.error_message
            ));
        }
        Ok(())
    })
}

/// Builds, broadcasts through lightwalletd, and waits for zcashd's mempool.
pub fn send(
    chain: &Chain,
    inputs: &[(Coin, &Party, Scope, u32)],
    outputs: &[Out],
    change: Option<&TransparentAddress>,
) -> Built {
    let built = build(chain, inputs, outputs, change);
    broadcast(&chain.lwd_url(), &built.raw)
        .unwrap_or_else(|e| panic!("S broadcast {}: {e}", built.txid));
    chain.wait_mempool(&built.txid);
    built
}

/// Orchard receiver of a unified address.
pub fn orchard_receiver(unified_address: &str) -> orchard::Address {
    match zcash_keys::address::Address::decode(&NETWORK, unified_address) {
        Some(zcash_keys::address::Address::Unified(ua)) => *ua
            .orchard()
            .expect("unified address has an Orchard receiver"),
        _ => panic!("not a unified address: {unified_address}"),
    }
}
