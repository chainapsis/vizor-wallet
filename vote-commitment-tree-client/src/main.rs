//! CLI for syncing and verifying the vote commitment tree against a Zally chain node.
//!
//! Commands:
//! - `sync`    — Sync the tree from a chain node, print status
//! - `witness` — Sync and generate a Merkle witness for a leaf position
//! - `verify`  — Verify a witness against a root and leaf
//! - `status`  — Fetch and display the chain's current tree state

use std::{process, sync::Arc};

use bytes::Bytes;
use clap::{Parser, Subcommand};
use ff::PrimeField;
use http_body_util::{BodyExt, Empty};
use hyper::Request;
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::TokioExecutor,
};
use pasta_curves::Fp;

use vote_commitment_tree::{MerklePath, TreeClient, TreeSyncApi};
use vote_commitment_tree_client::http_sync_api::HttpTreeSyncApi;
use vote_commitment_tree_client::transport::{Transport, TransportError, TransportResponse};

// ---------------------------------------------------------------------------
// CLI definition
// ---------------------------------------------------------------------------

#[derive(Parser)]
#[command(name = "vote-tree-cli")]
#[command(about = "Sync, witness, and verify the Zally vote commitment tree")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Sync the full tree from a chain node, verify roots, print status.
    Sync {
        /// Chain REST API base URL (e.g. http://localhost:1317).
        #[arg(long, default_value = "http://localhost:1317")]
        node: String,

        /// Hex-encoded voting round identifier.
        #[arg(long)]
        round: String,

        /// Leaf positions to mark for future witness generation (comma-separated).
        #[arg(long, value_delimiter = ',')]
        mark: Vec<u64>,
    },

    /// Sync and generate a Merkle witness for a specific leaf position.
    Witness {
        /// Chain REST API base URL.
        #[arg(long, default_value = "http://localhost:1317")]
        node: String,

        /// Hex-encoded voting round identifier.
        #[arg(long)]
        round: String,

        /// Leaf position (index) to generate a witness for.
        #[arg(long)]
        position: u64,

        /// Anchor height (checkpoint) for the witness.
        /// Defaults to the latest synced height.
        #[arg(long)]
        anchor_height: Option<u32>,
    },

    /// Verify a Merkle witness offline (no network required).
    Verify {
        /// Leaf value as 64 hex characters (32 bytes LE Pallas Fp).
        #[arg(long)]
        leaf: String,

        /// Merkle path as hex (MERKLE_PATH_BYTES bytes).
        #[arg(long)]
        witness: String,

        /// Expected root as 64 hex characters (32 bytes LE Pallas Fp).
        #[arg(long)]
        root: String,
    },

    /// Fetch and display the chain's current tree state (no local sync).
    Status {
        /// Chain REST API base URL.
        #[arg(long, default_value = "http://localhost:1317")]
        node: String,

        /// Hex-encoded voting round identifier.
        #[arg(long)]
        round: String,
    },
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Parse a 64-char hex string into a Pallas Fp field element.
fn parse_fp_hex(hex_str: &str, label: &str) -> Fp {
    let bytes = hex::decode(hex_str).unwrap_or_else(|e| {
        eprintln!("error: invalid hex for {}: {}", label, e);
        process::exit(1);
    });
    if bytes.len() != 32 {
        eprintln!(
            "error: {} must be exactly 32 bytes (64 hex chars), got {}",
            label,
            bytes.len()
        );
        process::exit(1);
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Option::from(Fp::from_repr(arr)).unwrap_or_else(|| {
        eprintln!("error: {} is not a canonical Pallas Fp encoding", label);
        process::exit(1);
    })
}

/// Print a field element as hex.
fn fp_hex(fp: &Fp) -> String {
    hex::encode(fp.to_repr())
}

type RequestBody = Empty<Bytes>;
type HyperClient = Client<HttpsConnector<HttpConnector>, RequestBody>;

struct CliHyperTransport {
    runtime: tokio::runtime::Runtime,
    client: HyperClient,
}

impl CliHyperTransport {
    fn new() -> Result<Self, TransportError> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| TransportError::Request(e.to_string()))?;
        let mut connector = HttpConnector::new();
        connector.enforce_http(false);
        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_or_http()
            .enable_http1()
            .enable_http2()
            .wrap_connector(connector);
        let client = Client::builder(TokioExecutor::new()).build(https);

        Ok(Self { runtime, client })
    }
}

impl Transport for CliHyperTransport {
    fn get(&self, url: &str) -> Result<TransportResponse, TransportError> {
        self.runtime.block_on(async {
            let request = Request::builder()
                .method("GET")
                .uri(url)
                .body(Empty::<Bytes>::new())
                .map_err(|e| TransportError::Request(e.to_string()))?;
            let response = self
                .client
                .request(request)
                .await
                .map_err(|e| TransportError::Request(e.to_string()))?;
            let status = response.status().as_u16();
            let body = response
                .into_body()
                .collect()
                .await
                .map_err(|e| TransportError::Request(e.to_string()))?
                .to_bytes()
                .to_vec();

            Ok(TransportResponse { status, body })
        })
    }
}

fn http_api(node: &str, round: &str) -> HttpTreeSyncApi {
    let transport = CliHyperTransport::new().unwrap_or_else(|e| {
        eprintln!("error: failed to create HTTP transport: {}", e);
        process::exit(1);
    });
    HttpTreeSyncApi::new(node, round, Arc::new(transport))
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

fn cmd_sync(node: &str, round: &str, mark_positions: &[u64]) {
    let api = http_api(node, round);

    // Fetch remote state first for display.
    let remote_state = api.get_tree_state().unwrap_or_else(|e| {
        eprintln!("error: failed to fetch tree state: {}", e);
        process::exit(1);
    });

    println!("Remote tree state:");
    println!("  height:     {}", remote_state.height);
    println!("  next_index: {}", remote_state.next_index);
    println!("  root:       {}", fp_hex(&remote_state.root));
    println!();

    if remote_state.height == 0 {
        println!("Tree is empty, nothing to sync.");
        return;
    }

    let mut client = TreeClient::empty();
    for &pos in mark_positions {
        client.mark_position(pos);
    }

    println!("Syncing from genesis to height {}...", remote_state.height);
    client.sync(&api).unwrap_or_else(|e| {
        eprintln!("error: sync failed: {}", e);
        process::exit(1);
    });

    println!("Sync complete.");
    println!("  leaves synced:     {}", client.size());
    println!("  last synced height: {:?}", client.last_synced_height());
    println!("  local root:        {}", fp_hex(&client.root()));

    if client.root() == remote_state.root {
        println!("  root match:        OK");
    } else {
        eprintln!("  root match:        MISMATCH");
        process::exit(1);
    }
}

fn cmd_witness(node: &str, round: &str, position: u64, anchor_height: Option<u32>) {
    let api = http_api(node, round);

    let remote_state = api.get_tree_state().unwrap_or_else(|e| {
        eprintln!("error: failed to fetch tree state: {}", e);
        process::exit(1);
    });

    if remote_state.height == 0 {
        eprintln!("error: tree is empty, no witnesses to generate");
        process::exit(1);
    }

    let mut client = TreeClient::empty();
    client.mark_position(position);

    println!("Syncing to height {}...", remote_state.height);
    client.sync(&api).unwrap_or_else(|e| {
        eprintln!("error: sync failed: {}", e);
        process::exit(1);
    });

    let anchor = anchor_height.unwrap_or_else(|| {
        client
            .last_synced_height()
            .expect("must have synced at least one block")
    });

    println!(
        "Generating witness for position {} at anchor height {}...",
        position, anchor
    );
    match client.witness(position, anchor) {
        Some(path) => {
            let path_bytes = path.to_bytes();
            println!("Witness (hex): {}", hex::encode(&path_bytes));
            println!("Witness size:  {} bytes", path_bytes.len());

            // Also print the root this witness is valid against.
            if let Some(root) = client.root_at_height(anchor) {
                println!("Anchor root:   {}", fp_hex(&root));
            }
        }
        None => {
            eprintln!("error: could not generate witness (position not marked or invalid anchor)");
            process::exit(1);
        }
    }
}

fn cmd_verify(leaf_hex: &str, witness_hex: &str, root_hex: &str) {
    let leaf = parse_fp_hex(leaf_hex, "leaf");
    let root = parse_fp_hex(root_hex, "root");

    let witness_bytes = hex::decode(witness_hex).unwrap_or_else(|e| {
        eprintln!("error: invalid hex for witness: {}", e);
        process::exit(1);
    });

    let path = MerklePath::from_bytes(&witness_bytes).unwrap_or_else(|| {
        eprintln!(
            "error: could not parse witness bytes (expected {} bytes)",
            vote_commitment_tree::MERKLE_PATH_BYTES
        );
        process::exit(1);
    });

    if path.verify(leaf, root) {
        println!("Verification: PASS");
        println!("  leaf:     {}", fp_hex(&leaf));
        println!("  root:     {}", fp_hex(&root));
        println!("  position: {}", path.position());
    } else {
        println!("Verification: FAIL");
        println!("  leaf:     {}", fp_hex(&leaf));
        println!("  root:     {}", fp_hex(&root));
        println!("  position: {}", path.position());
        process::exit(1);
    }
}

fn cmd_status(node: &str, round: &str) {
    let api = http_api(node, round);

    let state = api.get_tree_state().unwrap_or_else(|e| {
        eprintln!("error: failed to fetch tree state: {}", e);
        process::exit(1);
    });

    println!("Chain tree state:");
    println!("  height:     {}", state.height);
    println!("  next_index: {}", state.next_index);
    println!("  root:       {}", fp_hex(&state.root));

    if state.next_index == 0 {
        println!("  status:     empty (no leaves)");
    } else {
        println!("  status:     {} leaves committed", state.next_index);
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() {
    let cli = Cli::parse();

    match &cli.command {
        Command::Sync { node, round, mark } => cmd_sync(node, round, mark),
        Command::Witness {
            node,
            round,
            position,
            anchor_height,
        } => cmd_witness(node, round, *position, *anchor_height),
        Command::Verify {
            leaf,
            witness,
            root,
        } => cmd_verify(leaf, witness, root),
        Command::Status { node, round } => cmd_status(node, round),
    }
}
