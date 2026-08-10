//! Local smoke driver for config resolution + PIR nullifier fetch.
//!
//! Invoked by `tests/pir-smoke.sh` / `make pir-smoke` (example target, not part
//! of the default `cargo test` suite). Keeps production HTTPS URL validation
//! unchanged by embedding synthetic `https://` identities in the dummy config
//! documents while fetching those paths from a loopback HTTP base.

use anyhow::{anyhow, bail, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use bytes::Bytes;
use ed25519_dalek::{Signer, SigningKey};
use ff::PrimeField;
use http::{Method, Request};
use http_body_util::{BodyExt, Full};
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::TokioExecutor,
};
use pasta_curves::pallas::Base as Fp;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::Arc;
use zcash_voting::config::{
    resolve_dynamic_voting_config, resolve_static_voting_config, PinnedConfigSource, PirLayout,
};
use zcash_voting::wire::ResolveVotingConfigOptions;
use zcash_voting::{connect_pir, HyperTransport};

type RequestBody = Full<Bytes>;
type HyperClient = Client<HttpsConnector<HttpConnector>, RequestBody>;

const PREPARE_SEED: [u8; 32] = [3u8; 32];
const TRUSTED_KEY_ID: &str = "pir-smoke-k1";
const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";
const ROUND_AUTH_V2_DOMAIN_TAG: &[u8] = b"zcash-shielded-vote:round-auth:v2";

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let Some(command) = args.next() else {
        eprintln!("pir_smoke: skipped (run via `make pir-smoke`)");
        return Ok(());
    };
    match command.as_str() {
        "prepare" => prepare(args.collect()),
        "run" => {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .context("build tokio runtime")?;
            rt.block_on(run(args.collect()))
        }
        other => Err(anyhow!("unknown command {other}; expected prepare|run")),
    }
}

fn prepare(args: Vec<String>) -> Result<()> {
    let mut out_dir = None;
    let mut static_identity_url = None;
    let mut dynamic_identity_url = None;
    let mut pir_identity_url = None;
    let mut print_static_sha256 = false;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--out-dir" => out_dir = Some(required_value("--out-dir", iter.next())?),
            "--static-identity-url" => {
                static_identity_url = Some(required_value("--static-identity-url", iter.next())?)
            }
            "--dynamic-identity-url" => {
                dynamic_identity_url = Some(required_value("--dynamic-identity-url", iter.next())?)
            }
            "--pir-identity-url" => {
                pir_identity_url = Some(required_value("--pir-identity-url", iter.next())?)
            }
            "--print-static-sha256" => print_static_sha256 = true,
            other => bail!("unknown prepare arg: {other}"),
        }
    }

    let out_dir = PathBuf::from(out_dir.ok_or_else(|| anyhow!("prepare requires --out-dir"))?);
    let static_identity_url =
        static_identity_url.ok_or_else(|| anyhow!("prepare requires --static-identity-url"))?;
    let dynamic_identity_url =
        dynamic_identity_url.ok_or_else(|| anyhow!("prepare requires --dynamic-identity-url"))?;
    let pir_identity_url =
        pir_identity_url.ok_or_else(|| anyhow!("prepare requires --pir-identity-url"))?;

    std::fs::create_dir_all(&out_dir).with_context(|| format!("create {}", out_dir.display()))?;

    let signing_key = SigningKey::from_bytes(&PREPARE_SEED);
    let pubkey = signing_key.verifying_key().to_bytes();
    let ea_pk = [7u8; 32];
    // Round-auth v2 preimage: domain tag || round_id bytes || ea_pk
    // || pir_depth (u32 LE) || tier0_layers (u32 LE) || tier1_layers (u32 LE).
    // Layout values must match the pir_layout advertised below.
    let mut preimage = ROUND_AUTH_V2_DOMAIN_TAG.to_vec();
    preimage.extend_from_slice(&hex::decode(ROUND_ID).expect("round id hex"));
    preimage.extend_from_slice(&ea_pk);
    preimage.extend_from_slice(&19u32.to_le_bytes());
    preimage.extend_from_slice(&12u32.to_le_bytes());
    preimage.extend_from_slice(&7u32.to_le_bytes());
    let sig = signing_key.sign(&preimage).to_bytes();

    let static_json = serde_json::json!({
        "static_config_version": 1,
        "dynamic_config_url": dynamic_identity_url,
        "trusted_keys": [{
            "key_id": TRUSTED_KEY_ID,
            "alg": "ed25519",
            "pubkey": BASE64.encode(pubkey),
            "notes": "local pir-smoke harness key"
        }]
    });
    let dynamic_json = serde_json::json!({
        "config_version": 1,
        "vote_servers": [{
            "url": "https://vote.smoke.test",
            "label": "smoke-vote"
        }],
        "pir_endpoints": [{
            "url": pir_identity_url,
            "label": "smoke-pir"
        }],
        "pir_layout": {
            "pir_depth": 19,
            "tier0_layers": 12,
            "tier1_layers": 7
        },
        "supported_versions": {
            "pir": ["v0"],
            "vote_protocol": "v0",
            "tally": "v0",
            "vote_server": "v1"
        },
        "rounds": {
            ROUND_ID: {
                "auth_version": 2,
                "ea_pk": BASE64.encode(ea_pk),
                "signatures": [{
                    "key_id": TRUSTED_KEY_ID,
                    "alg": "ed25519",
                    "sig": BASE64.encode(sig)
                }]
            }
        }
    });

    let static_path = out_dir.join("static-voting-config.json");
    let dynamic_path = out_dir.join("dynamic-voting-config.json");
    let static_bytes = serde_json::to_vec_pretty(&static_json)?;
    let dynamic_bytes = serde_json::to_vec_pretty(&dynamic_json)?;
    std::fs::write(&static_path, &static_bytes)
        .with_context(|| format!("write {}", static_path.display()))?;
    std::fs::write(&dynamic_path, &dynamic_bytes)
        .with_context(|| format!("write {}", dynamic_path.display()))?;

    // Validate the fixtures against the real resolver before serving them.
    let hash = hex::encode(Sha256::digest(&static_bytes));
    let pinned = format!("{static_identity_url}?checksum=sha256:{hash}");
    let resolved_static = resolve_static_voting_config(&pinned, &static_bytes)
        .map_err(|e| anyhow!("prepare static resolve failed: {e}"))?;
    let resolved = resolve_dynamic_voting_config(
        resolved_static,
        &dynamic_bytes,
        ResolveVotingConfigOptions::default(),
    )
    .map_err(|e| anyhow!("prepare dynamic resolve failed: {e}"))?;
    eprintln!(
        "prepared config: layout={} / {} / {}, authenticated_rounds={}",
        resolved.pir_layout.pir_depth,
        resolved.pir_layout.tier0_layers,
        resolved.pir_layout.tier1_layers,
        resolved.authenticated_rounds.len()
    );

    if print_static_sha256 {
        println!("{hash}");
    }
    Ok(())
}

async fn run(args: Vec<String>) -> Result<()> {
    let mut fetch_base = None;
    let mut static_source = None;
    let mut pir_url = None;
    let mut present_nf = None;
    let mut absent_nf = None;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--fetch-base" => fetch_base = Some(required_value("--fetch-base", iter.next())?),
            "--static-source" => {
                static_source = Some(required_value("--static-source", iter.next())?)
            }
            "--pir-url" => pir_url = Some(required_value("--pir-url", iter.next())?),
            "--present-nf" => present_nf = Some(required_value("--present-nf", iter.next())?),
            "--absent-nf" => absent_nf = Some(required_value("--absent-nf", iter.next())?),
            other => bail!("unknown run arg: {other}"),
        }
    }

    let fetch_base = fetch_base.ok_or_else(|| anyhow!("run requires --fetch-base"))?;
    let static_source = static_source.ok_or_else(|| anyhow!("run requires --static-source"))?;
    let pir_url = pir_url.ok_or_else(|| anyhow!("run requires --pir-url"))?;
    let present_nf = parse_nf(&present_nf.ok_or_else(|| anyhow!("run requires --present-nf"))?)?;
    let absent_nf = parse_nf(&absent_nf.ok_or_else(|| anyhow!("run requires --absent-nf"))?)?;

    let fetcher = LoopbackHttpsIdentityFetcher::new(fetch_base.trim_end_matches('/').to_string());
    let pinned = PinnedConfigSource::parse(&static_source)
        .map_err(|e| anyhow!("parse static source failed: {e}"))?;
    let static_bytes = fetcher.fetch_identity_url(&pinned.url).await?;
    let resolved_static = resolve_static_voting_config(&static_source, &static_bytes)
        .map_err(|e| anyhow!("resolve static config failed: {e}"))?;
    let dynamic_bytes = fetcher
        .fetch_identity_url(&resolved_static.dynamic_config_url)
        .await?;
    let resolved = resolve_dynamic_voting_config(
        resolved_static,
        &dynamic_bytes,
        ResolveVotingConfigOptions::default(),
    )
    .map_err(|e| anyhow!("resolve dynamic config failed: {e}"))?;

    println!(
        "resolved pir_layout: depth={} tier0={} tier1={}",
        resolved.pir_layout.pir_depth,
        resolved.pir_layout.tier0_layers,
        resolved.pir_layout.tier1_layers
    );
    println!(
        "resolved pir_endpoints: {}",
        resolved
            .pir_endpoints
            .iter()
            .map(|e| e.url.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    );
    assert_eq!(
        resolved.pir_layout,
        PirLayout {
            pir_depth: 19,
            tier0_layers: 12,
            tier1_layers: 7,
        }
    );

    // Connect uses the real local PIR HTTP endpoint; config still advertised
    // a synthetic HTTPS identity that passed resolver validation. Prefer the
    // async connector here because this driver already owns a Tokio runtime.
    let client = connect_pir(
        resolved.pir_layout,
        &pir_url,
        Arc::new(HyperTransport::new()),
    )
    .await
    .map_err(|e| anyhow!("connect_pir failed: {e}"))?;
    println!("connected to PIR at {pir_url}");

    println!(
        "querying ABSENT nullifier {}",
        hex::encode(absent_nf.to_repr())
    );
    let proof = client
        .fetch_proof(absent_nf)
        .await
        .map_err(|e| anyhow!("absent nullifier fetch failed: {e}"))?;
    if !proof.verify(absent_nf) {
        bail!("absent nullifier proof failed local verification");
    }
    println!(
        "ABSENT ok: leaf_pos={} root={}",
        proof.leaf_pos,
        hex::encode(proof.root.to_repr())
    );

    println!(
        "querying PRESENT nullifier {}",
        hex::encode(present_nf.to_repr())
    );
    match client.fetch_proof(present_nf).await {
        Ok(proof) => {
            if proof.verify(present_nf) {
                bail!("PRESENT nullifier unexpectedly produced a verifying exclusion proof");
            }
            bail!("PRESENT nullifier returned a proof that failed verify (expected fetch error)");
        }
        Err(err) => {
            println!("PRESENT rejected as expected: {err}");
        }
    }

    println!("pir_smoke: PASS");
    Ok(())
}

fn required_value(flag: &str, value: Option<String>) -> Result<String> {
    value.ok_or_else(|| anyhow!("missing value for {flag}"))
}

fn parse_nf(hex_str: &str) -> Result<Fp> {
    let bytes = hex::decode(hex_str.trim()).context("decode nullifier hex")?;
    if bytes.len() != 32 {
        bail!("nullifier hex must decode to 32 bytes, got {}", bytes.len());
    }
    let mut repr = [0u8; 32];
    repr.copy_from_slice(&bytes);
    Option::<Fp>::from(Fp::from_repr(repr))
        .ok_or_else(|| anyhow!("nullifier bytes are not a canonical field element"))
}

/// Fetches config bytes from a loopback HTTP origin while callers keep the
/// synthetic HTTPS identity URLs required by the production resolver.
struct LoopbackHttpsIdentityFetcher {
    client: HyperClient,
    fetch_base: String,
}

impl LoopbackHttpsIdentityFetcher {
    fn new(fetch_base: String) -> Self {
        let mut connector = HttpConnector::new();
        connector.enforce_http(false);
        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_or_http()
            .enable_http1()
            .enable_http2()
            .wrap_connector(connector);
        let client = Client::builder(TokioExecutor::new()).build(https);
        Self { client, fetch_base }
    }

    async fn fetch_identity_url(&self, identity_url: &str) -> Result<Vec<u8>> {
        let path = identity_path(identity_url)?;
        let url = format!("{}{path}", self.fetch_base);
        let request = Request::builder()
            .method(Method::GET)
            .uri(&url)
            .header("Cache-Control", "no-cache")
            .header("Pragma", "no-cache")
            .body(Full::new(Bytes::new()))
            .context("build config request")?;
        let response = self
            .client
            .request(request)
            .await
            .with_context(|| format!("send config request to {url}"))?;
        if !response.status().is_success() {
            bail!("config fetch {url} returned HTTP {}", response.status());
        }
        Ok(response
            .into_body()
            .collect()
            .await
            .context("read config response body")?
            .to_bytes()
            .to_vec())
    }
}

fn identity_path(identity_url: &str) -> Result<String> {
    let rest = identity_url
        .strip_prefix("https://")
        .ok_or_else(|| anyhow!("identity URL must be https: {identity_url}"))?;
    let path = rest
        .find('/')
        .map(|idx| &rest[idx..])
        .ok_or_else(|| anyhow!("identity URL missing path: {identity_url}"))?;
    let path = path.split(['?', '#']).next().unwrap_or(path);
    if path.is_empty() || path == "/" {
        bail!("identity URL path must not be empty: {identity_url}");
    }
    Ok(path.to_string())
}
