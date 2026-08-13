use std::{cmp::Ordering, process::ExitCode, time::Instant};

use ff::{Field, PrimeField};
use group::Curve;
use incrementalmerkletree::{Hashable, Level};
use orchard::{
    constants::MERKLE_DEPTH_ORCHARD as MERKLE_DEPTH,
    keys::{FullViewingKey, Scope, SpendingKey},
    note::{ExtractedNoteCommitment, Note, NoteVersion, RandomSeed, Rho},
    tree::{MerkleHashOrchard, MerklePath},
    value::NoteValue,
};
use pasta_curves::pallas;
use rand::{rngs::OsRng, RngCore};
use serde::Serialize;
use voting_circuits::{
    delegation::{
        build_delegation_bundle, create_delegation_proof, verify_delegation_proof,
        warm_delegation_keys, DelegationBundle, ImtProvider, RealNoteInput, SpacedLeafImtProvider,
    },
    spend_auth_g_affine,
    vote_proof::{
        build_vote_proof_from_delegation, verify_vote_proof, warm_vote_proof_keys, VoteProofBundle,
    },
    VOTE_COMM_TREE_DEPTH,
};

#[derive(Clone, Copy, Debug)]
enum CircuitKind {
    Zkp1,
    Zkp2,
}

impl CircuitKind {
    fn parse(value: &str) -> Result<Self, String> {
        match value.to_ascii_lowercase().as_str() {
            "zkp1" | "delegation" => Ok(Self::Zkp1),
            "zkp2" | "vote" => Ok(Self::Zkp2),
            _ => Err(format!("unknown circuit {value:?}; expected zkp1 or zkp2")),
        }
    }
}

#[derive(Debug)]
struct Request {
    circuit: CircuitKind,
    samples: u32,
    warmups: u32,
    label: String,
}

#[derive(Debug, Serialize)]
struct TimingSummary {
    median_ms: f64,
    mean_ms: f64,
    min_ms: f64,
    max_ms: f64,
}

#[derive(Debug, Serialize)]
struct BenchmarkReport {
    schema_version: u32,
    label: String,
    circuit: &'static str,
    operation: &'static str,
    k: u32,
    target_os: &'static str,
    target_arch: &'static str,
    available_parallelism: usize,
    samples: u32,
    warmups: u32,
    fixture_setup_ms: f64,
    key_setup_ms: f64,
    warmup_proof_ms: Vec<f64>,
    proof_ms: Vec<f64>,
    proof: TimingSummary,
    verification_ms: Vec<f64>,
    verification: TimingSummary,
    proof_size_bytes: usize,
}

#[derive(Debug, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
enum Output {
    Ok { report: Box<BenchmarkReport> },
    Error { error: String },
}

fn main() -> ExitCode {
    let output = match parse_args().and_then(run_benchmark) {
        Ok(report) => Output::Ok {
            report: Box::new(report),
        },
        Err(error) => Output::Error { error },
    };

    println!(
        "{}",
        serde_json::to_string(&output).expect("benchmark report serializes")
    );

    match output {
        Output::Ok { .. } => ExitCode::SUCCESS,
        Output::Error { .. } => ExitCode::FAILURE,
    }
}

fn parse_args() -> Result<Request, String> {
    let mut circuit = None;
    let mut samples = 5;
    let mut warmups = 1;
    let mut label = "manual".to_owned();
    let mut args = std::env::args().skip(1);

    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--circuit" => {
                circuit = Some(CircuitKind::parse(&next_value(&mut args, "--circuit")?)?);
            }
            "--samples" => {
                samples = parse_u32(next_value(&mut args, "--samples")?, "--samples")?;
            }
            "--warmups" => {
                warmups = parse_u32(next_value(&mut args, "--warmups")?, "--warmups")?;
            }
            "--label" => label = next_value(&mut args, "--label")?,
            "--help" | "-h" => {
                return Err(
                    "usage: voting-proof-benchmark --circuit <zkp1|zkp2> [--samples N] [--warmups N] [--label TEXT]"
                        .to_owned(),
                );
            }
            _ => return Err(format!("unknown argument {argument:?}")),
        }
    }

    let circuit = circuit.ok_or_else(|| "--circuit is required".to_owned())?;
    if samples == 0 || samples > 100 {
        return Err("--samples must be between 1 and 100".to_owned());
    }
    if warmups > 10 {
        return Err("--warmups must be between 0 and 10".to_owned());
    }

    Ok(Request {
        circuit,
        samples,
        warmups,
        label,
    })
}

fn next_value(args: &mut impl Iterator<Item = String>, option: &str) -> Result<String, String> {
    args.next()
        .ok_or_else(|| format!("{option} requires a value"))
}

fn parse_u32(value: String, option: &str) -> Result<u32, String> {
    value
        .parse()
        .map_err(|_| format!("{option} must be an integer, got {value:?}"))
}

fn run_benchmark(request: Request) -> Result<BenchmarkReport, String> {
    match request.circuit {
        CircuitKind::Zkp1 => run_zkp1(&request),
        CircuitKind::Zkp2 => run_zkp2(&request),
    }
}

fn run_zkp1(request: &Request) -> Result<BenchmarkReport, String> {
    let fixture_started = Instant::now();
    let bundle = build_test_delegation_bundle()?;
    let fixture_setup_ms = elapsed_ms(fixture_started);

    let key_started = Instant::now();
    warm_delegation_keys().map_err(|error| format!("ZKP 1 key setup failed: {error}"))?;
    let key_setup_ms = elapsed_ms(key_started);

    let mut warmup_proof_ms = Vec::with_capacity(request.warmups as usize);
    let mut latest_proof = None;
    for _ in 0..request.warmups {
        let started = Instant::now();
        let proof = create_delegation_proof(bundle.circuit.clone(), &bundle.instance)
            .map_err(|error| format!("ZKP 1 warmup proof failed: {error}"))?;
        warmup_proof_ms.push(elapsed_ms(started));
        latest_proof = Some(proof);
    }

    let mut proof_ms = Vec::with_capacity(request.samples as usize);
    for _ in 0..request.samples {
        let started = Instant::now();
        let proof = create_delegation_proof(bundle.circuit.clone(), &bundle.instance)
            .map_err(|error| format!("ZKP 1 proof failed: {error}"))?;
        proof_ms.push(elapsed_ms(started));
        latest_proof = Some(proof);
    }

    let proof = latest_proof.expect("at least one measured proof is required");
    let verification_ms = benchmark_verification(request.samples, || {
        verify_delegation_proof(&proof, &bundle.instance)
    })?;

    Ok(report(
        request,
        "zkp1",
        "create_delegation_proof",
        voting_circuits::delegation::K,
        fixture_setup_ms,
        key_setup_ms,
        warmup_proof_ms,
        proof_ms,
        verification_ms,
        proof.len(),
    ))
}

fn run_zkp2(request: &Request) -> Result<BenchmarkReport, String> {
    let key_started = Instant::now();
    warm_vote_proof_keys().map_err(|error| format!("ZKP 2 key setup failed: {error}"))?;
    let key_setup_ms = elapsed_ms(key_started);

    let mut warmup_proof_ms = Vec::with_capacity(request.warmups as usize);
    let mut latest_bundle = None;
    for _ in 0..request.warmups {
        let started = Instant::now();
        let bundle = build_test_vote_proof_bundle()?;
        warmup_proof_ms.push(elapsed_ms(started));
        latest_bundle = Some(bundle);
    }

    let mut proof_ms = Vec::with_capacity(request.samples as usize);
    for _ in 0..request.samples {
        let started = Instant::now();
        let bundle = build_test_vote_proof_bundle()?;
        proof_ms.push(elapsed_ms(started));
        latest_bundle = Some(bundle);
    }

    let bundle = latest_bundle.expect("at least one measured proof is required");
    let verification_ms = benchmark_verification(request.samples, || {
        verify_vote_proof(&bundle.proof, &bundle.instance)
    })?;

    Ok(report(
        request,
        "zkp2",
        "build_vote_proof_from_delegation",
        voting_circuits::vote_proof::K,
        0.0,
        key_setup_ms,
        warmup_proof_ms,
        proof_ms,
        verification_ms,
        bundle.proof.len(),
    ))
}

#[allow(clippy::too_many_arguments)]
fn report(
    request: &Request,
    circuit: &'static str,
    operation: &'static str,
    k: u32,
    fixture_setup_ms: f64,
    key_setup_ms: f64,
    warmup_proof_ms: Vec<f64>,
    proof_ms: Vec<f64>,
    verification_ms: Vec<f64>,
    proof_size_bytes: usize,
) -> BenchmarkReport {
    BenchmarkReport {
        schema_version: 1,
        label: request.label.clone(),
        circuit,
        operation,
        k,
        target_os: std::env::consts::OS,
        target_arch: std::env::consts::ARCH,
        available_parallelism: std::thread::available_parallelism()
            .map(usize::from)
            .unwrap_or(1),
        samples: request.samples,
        warmups: request.warmups,
        fixture_setup_ms,
        key_setup_ms,
        proof: summarize(&proof_ms),
        proof_ms,
        verification: summarize(&verification_ms),
        verification_ms,
        warmup_proof_ms,
        proof_size_bytes,
    }
}

fn benchmark_verification(
    samples: u32,
    mut verify: impl FnMut() -> Result<(), String>,
) -> Result<Vec<f64>, String> {
    let mut timings = Vec::with_capacity(samples as usize);
    for _ in 0..samples {
        let started = Instant::now();
        verify()?;
        timings.push(elapsed_ms(started));
    }
    Ok(timings)
}

fn summarize(values: &[f64]) -> TimingSummary {
    let mut sorted = values.to_vec();
    sorted.sort_by(|left, right| left.partial_cmp(right).unwrap_or(Ordering::Equal));
    let middle = sorted.len() / 2;
    let median_ms = if sorted.len().is_multiple_of(2) {
        (sorted[middle - 1] + sorted[middle]) / 2.0
    } else {
        sorted[middle]
    };

    TimingSummary {
        median_ms,
        mean_ms: sorted.iter().sum::<f64>() / sorted.len() as f64,
        min_ms: sorted[0],
        max_ms: sorted[sorted.len() - 1],
    }
}

fn elapsed_ms(started: Instant) -> f64 {
    started.elapsed().as_secs_f64() * 1_000.0
}

fn build_test_vote_proof_bundle() -> Result<VoteProofBundle, String> {
    let sk = SpendingKey::from_bytes([0x42; 32]).expect("fixed benchmark key is valid");
    let ea_pk = (spend_auth_g_affine() * pallas::Scalar::from(42u64)).to_affine();
    build_vote_proof_from_delegation(
        &sk,
        1,
        12_500_000,
        pallas::Base::from(0xDEAD_u64),
        pallas::Base::from(0xCAFE_u64),
        [pallas::Base::ZERO; VOTE_COMM_TREE_DEPTH],
        0,
        123,
        1,
        1,
        ea_pk,
        pallas::Scalar::from(7u64),
        65_535,
        true,
    )
    .map_err(|error| format!("ZKP 2 proof failed: {error}"))
}

fn build_test_delegation_bundle() -> Result<DelegationBundle, String> {
    let mut rng = OsRng;
    let sk = SpendingKey::from_bytes([7; 32]).expect("fixed benchmark key is valid");
    let fvk: FullViewingKey = (&sk).into();
    let output_recipient = fvk.address_at(1u32, Scope::External);
    let vote_round_id = pallas::Base::random(&mut rng);
    let van_comm_rand = pallas::Base::random(&mut rng);
    let alpha = pallas::Scalar::random(&mut rng);
    let imt = SpacedLeafImtProvider::new();
    let (inputs, nc_root) = make_real_note_inputs(&fvk, &[13_000_000], &imt, &mut rng)?;

    build_delegation_bundle(
        inputs,
        &fvk,
        alpha,
        output_recipient,
        vote_round_id,
        nc_root,
        van_comm_rand,
        &imt,
        &mut rng,
        None,
    )
    .map_err(|error| format!("ZKP 1 fixture failed: {error}"))
}

fn make_real_note_inputs(
    fvk: &FullViewingKey,
    values: &[u64],
    imt_provider: &impl ImtProvider,
    rng: &mut impl RngCore,
) -> Result<(Vec<RealNoteInput>, pallas::Base), String> {
    if !(1..=4).contains(&values.len()) {
        return Err("ZKP 1 fixture requires one to four notes".to_owned());
    }

    let recipient = fvk.address_at(0u32, Scope::External);
    let notes: Vec<_> = values
        .iter()
        .copied()
        .map(|value| make_note(recipient, NoteValue::from_raw(value), rng))
        .collect();

    let empty_leaf = MerkleHashOrchard::empty_leaf();
    let mut leaves = [empty_leaf; 4];
    for (index, note) in notes.iter().enumerate() {
        let cmx = ExtractedNoteCommitment::from(note.commitment());
        leaves[index] = MerkleHashOrchard::from_cmx(&cmx);
    }

    let level_one = [
        MerkleHashOrchard::combine(Level::from(0), &leaves[0], &leaves[1]),
        MerkleHashOrchard::combine(Level::from(0), &leaves[2], &leaves[3]),
    ];
    let mut current = MerkleHashOrchard::combine(Level::from(1), &level_one[0], &level_one[1]);
    for level in 2..MERKLE_DEPTH {
        let sibling = MerkleHashOrchard::empty_root(Level::from(level as u8));
        current = MerkleHashOrchard::combine(Level::from(level as u8), &current, &sibling);
    }
    let nc_root = pallas::Base::from_repr(current.to_bytes())
        .into_option()
        .ok_or_else(|| "ZKP 1 fixture produced an invalid Merkle root".to_owned())?;

    let mut inputs = Vec::with_capacity(notes.len());
    for (index, note) in notes.into_iter().enumerate() {
        let mut auth_path = [MerkleHashOrchard::empty_leaf(); MERKLE_DEPTH];
        auth_path[0] = leaves[index ^ 1];
        auth_path[1] = level_one[1 - (index >> 1)];
        for (level, node) in auth_path.iter_mut().enumerate().skip(2) {
            *node = MerkleHashOrchard::empty_root(Level::from(level as u8));
        }
        let merkle_path = MerklePath::from_parts(index as u32, auth_path);
        let nullifier = pallas::Base::from_repr(note.nullifier(fvk).to_bytes())
            .into_option()
            .ok_or_else(|| "ZKP 1 fixture produced an invalid nullifier".to_owned())?;
        let imt_proof = imt_provider
            .non_membership_proof(nullifier)
            .map_err(|error| format!("ZKP 1 IMT fixture failed: {error}"))?;

        inputs.push(RealNoteInput {
            note,
            fvk: fvk.clone(),
            merkle_path,
            imt_proof,
            scope: Scope::External,
        });
    }

    Ok((inputs, nc_root))
}

fn make_note(recipient: orchard::Address, value: NoteValue, rng: &mut impl RngCore) -> Note {
    loop {
        let mut rho_bytes = [0u8; 32];
        rng.fill_bytes(&mut rho_bytes);
        let Some(rho) = Rho::from_bytes(&rho_bytes).into_option() else {
            continue;
        };
        let mut rseed_bytes = [0u8; 32];
        rng.fill_bytes(&mut rseed_bytes);
        let Some(rseed) = RandomSeed::from_bytes(rseed_bytes, &rho).into_option() else {
            continue;
        };
        let Some(note) =
            Note::from_parts(recipient, value, rho, rseed, NoteVersion::V3).into_option()
        else {
            continue;
        };
        return note;
    }
}
