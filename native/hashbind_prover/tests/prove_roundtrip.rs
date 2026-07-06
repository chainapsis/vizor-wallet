//! Gate tests for the on-device hashbind prover.
//!
//! Fast tests run in the default lane. The full prove+verify round-trip is
//! `#[ignore]`d because ProveKit proving is minutes-slow without
//! optimization — run it release:
//!
//!   cargo test --release -- --ignored --nocapture

use vizor_hashbind_prover::*;

use provekit_ffi::PKBuf;

/// Same fixture scalar as the proxy's solverd-v2 `native_cross_arch` test,
/// so results are directly comparable with the measured portability matrix.
fn fixture_scalar() -> [u8; 32] {
    let tail = hex::decode("523556789abcdef23456543c").unwrap();
    let mut k = [0u8; 32];
    k[32 - tail.len()..].copy_from_slice(&tail);
    k
}

fn last_error() -> String {
    let mut buf = PKBuf::empty();
    unsafe {
        assert_eq!(vizor_hashbind_last_error(&mut buf), 0);
        let s = String::from_utf8_lossy(std::slice::from_raw_parts(buf.ptr, buf.len)).into_owned();
        vizor_hashbind_free_buf(buf);
        s
    }
}

/// The vendored hashbind_core must emit byte-identical inputs.json to the
/// proxy repo's hashbind-core crate (fixtures/hashbind_inputs_golden.json is
/// generated from that crate for the fixture scalar). Drift here means the
/// witness math changed and the proof would stop cross-verifying.
#[test]
fn inputs_json_matches_proxy_golden() {
    let golden = include_str!("../fixtures/hashbind_inputs_golden.json");
    // Access the vendored module through a prove-path call is not possible
    // (module is private); regenerate through the same entry the prover uses.
    let ours = vizor_hashbind_prover::test_support::generate_inputs_json(&fixture_scalar());
    assert_eq!(ours, golden, "vendored hashbind_core drifted from proxy");
}

#[test]
fn prove_without_init_reports_not_initialized() {
    // Runs in its own test binary process only if the ignored round-trip has
    // not initialized the global prover first; ordering with the round-trip
    // test does not matter because init happens there too — so only assert
    // when the prover is not yet ready.
    if vizor_hashbind_ready() == 1 {
        return;
    }
    let k = fixture_scalar();
    let mut out = PKBuf::empty();
    let rc = unsafe { vizor_hashbind_prove(k.as_ptr(), k.len(), &mut out) };
    assert_eq!(rc, VIZOR_STATUS_NOT_INITIALIZED);
    assert!(last_error().contains("not initialized"));
}

#[test]
fn rejects_bad_scalar_length() {
    let mut out = PKBuf::empty();
    let rc = unsafe { vizor_hashbind_prove([0u8; 16].as_ptr(), 16, &mut out) };
    assert_eq!(rc, 1);
    assert!(last_error().contains("32 bytes"));
}

/// Full round-trip: init from the solver's pallas.pkp, prove the fixture
/// scalar, verify against the solver's pallas.pkv, and reject a tampered
/// proof. Passing this is the spec's cross-verify acceptance gate (§6.1) —
/// the fixtures are byte-identical to the keys the solver loads.
#[test]
#[ignore = "minutes-slow in debug; run: cargo test --release -- --ignored --nocapture"]
fn prove_verify_roundtrip_and_tamper_reject() {
    // pkp reuses the app's bundled asset (byte-identical to the solver key,
    // sha256 pinned in zwap_hashbind_native.dart) so the repo carries one copy,
    // not two. pkv has no app-side consumer, so it stays a test fixture.
    let pkp =
        std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/../../assets/zwap/pallas.pkp")).unwrap();
    let pkv = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/fixtures/pallas.pkv")).unwrap();

    let t = std::time::Instant::now();
    let rc = unsafe { vizor_hashbind_init(pkp.as_ptr(), pkp.len()) };
    assert_eq!(rc, 0, "init failed: {}", last_error());
    println!("pk_load_prover: {:?}", t.elapsed());

    let k = fixture_scalar();
    let mut proof = PKBuf::empty();
    let t = std::time::Instant::now();
    let rc = unsafe { vizor_hashbind_prove(k.as_ptr(), k.len(), &mut proof) };
    assert_eq!(rc, 0, "prove failed: {}", last_error());
    println!("prove: {:?} ({} proof bytes)", t.elapsed(), proof.len);

    let proof_bytes = unsafe { std::slice::from_raw_parts(proof.ptr, proof.len).to_vec() };
    unsafe { vizor_hashbind_free_buf(proof) };

    let t = std::time::Instant::now();
    let rc = unsafe {
        vizor_hashbind_verify(pkv.as_ptr(), pkv.len(), proof_bytes.as_ptr(), proof_bytes.len())
    };
    assert_eq!(rc, 0, "verify failed: {}", last_error());
    println!("verify (incl. pkv load): {:?}", t.elapsed());

    // Tamper one byte mid-proof — must not verify.
    let mut tampered = proof_bytes.clone();
    let mid = tampered.len() / 2;
    tampered[mid] ^= 0x01;
    let rc = unsafe {
        vizor_hashbind_verify(pkv.as_ptr(), pkv.len(), tampered.as_ptr(), tampered.len())
    };
    assert_ne!(rc, 0, "tampered proof unexpectedly verified");
}
