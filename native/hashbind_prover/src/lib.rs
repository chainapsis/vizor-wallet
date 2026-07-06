//! C ABI for on-device zwap hashbind (ProveKit) proving.
//!
//! The b2z/z2b
//! spend-auth scalar `k_a` enters through [`vizor_hashbind_prove`] and never
//! leaves the process — witness generation (vendored hashbind-core) and
//! ProveKit proving (provekit-ffi at the solver's pinned rev) both happen
//! in-memory here. The proof comes back in provekit's `.np` binary format
//! (postcard), which is the encoding the solver's native `ProofEngine`
//! verifies and the §3.3 wire discriminator vs the browser's JSON proofs.
//!
//! Call sequence (Dart side, via dart:ffi):
//!   1. `vizor_hashbind_init(pkp_bytes)` once per process (idempotent).
//!   2. `vizor_hashbind_prove(k_be32)` per order; free the buffer with
//!      `vizor_hashbind_free_buf`.
//!   3. On any nonzero status, `vizor_hashbind_last_error` returns a
//!      UTF-8 diagnostic (never contains key or proof material).
//!
//! Status codes are provekit-ffi's `PKStatus` values plus
//! `VIZOR_STATUS_NOT_INITIALIZED` (100).

mod hashbind_core;

use std::ffi::CString;
use std::os::raw::c_int;
use std::sync::{Mutex, OnceLock};

use provekit_ffi::{
    pk_free_buf, pk_free_verifier, pk_get_last_error, pk_init, pk_load_prover_bytes,
    pk_load_verifier_bytes, pk_prove_json, pk_verify, PKBuf, PKProver, PKVerifier,
};
use zeroize::Zeroize;

/// Returned when `vizor_hashbind_prove` is called before a successful
/// `vizor_hashbind_init`. Distinct from every `PKStatus` value.
pub const VIZOR_STATUS_NOT_INITIALIZED: c_int = 100;

const STATUS_SUCCESS: c_int = 0;
const STATUS_INVALID_INPUT: c_int = 1;
const STATUS_WITNESS_ERROR: c_int = 3;

/// The cached prover handle. `*mut PKProver` is `!Send`, but the handle is
/// only ever created once and then used read-only (`pk_prove_json` clones the
/// underlying scheme per call), so storing the address is sound.
static PROVER: OnceLock<usize> = OnceLock::new();
/// Serializes init so a losing racer can free its extra handle.
static INIT_LOCK: Mutex<()> = Mutex::new(());
static LAST_ERROR: Mutex<String> = Mutex::new(String::new());

fn set_error(msg: impl Into<String>) {
    *LAST_ERROR.lock().unwrap() = msg.into();
}

/// Copies provekit-ffi's last-error string into our slot, prefixed with the
/// failing stage so mixed witness/prover failures stay distinguishable.
fn capture_pk_error(stage: &str) {
    let mut buf = PKBuf::empty();
    // SAFETY: buf is a valid out-pointer for the duration of the call.
    let detail = unsafe {
        if pk_get_last_error(&mut buf) == 0 && !buf.ptr.is_null() {
            let bytes = std::slice::from_raw_parts(buf.ptr, buf.len).to_vec();
            pk_free_buf(buf);
            String::from_utf8_lossy(&bytes).into_owned()
        } else {
            String::from("(no provekit error detail)")
        }
    };
    set_error(format!("{stage}: {detail}"));
}

/// Load the ProveKit prover scheme from `pallas.pkp` bytes. Idempotent:
/// after the first success, later calls return success without reloading.
///
/// # Safety
/// `pkp_ptr` must point to `pkp_len` valid bytes.
#[no_mangle]
pub unsafe extern "C" fn vizor_hashbind_init(pkp_ptr: *const u8, pkp_len: usize) -> c_int {
    if pkp_ptr.is_null() || pkp_len == 0 {
        set_error("init: null/empty proving key buffer");
        return STATUS_INVALID_INPUT;
    }
    let _guard = INIT_LOCK.lock().unwrap();
    if PROVER.get().is_some() {
        return STATUS_SUCCESS;
    }
    pk_init();
    let mut handle: *mut PKProver = std::ptr::null_mut();
    let rc = pk_load_prover_bytes(pkp_ptr, pkp_len, &mut handle);
    if rc != STATUS_SUCCESS {
        capture_pk_error("init: loading prover scheme");
        return rc;
    }
    // Cannot race: INIT_LOCK is held and PROVER was empty above.
    PROVER
        .set(handle as usize)
        .expect("PROVER set twice despite INIT_LOCK");
    STATUS_SUCCESS
}

/// 1 once `vizor_hashbind_init` has succeeded in this process, else 0.
#[no_mangle]
pub extern "C" fn vizor_hashbind_ready() -> c_int {
    PROVER.get().is_some() as c_int
}

/// Prove knowledge of the 32-byte big-endian spend-auth scalar `k_a`.
///
/// Writes the proof (provekit `.np` binary format) into `out_proof`; the
/// caller frees it with `vizor_hashbind_free_buf`. The scalar must be
/// nonzero and at most 252 bits (the circuit's bound); the wallet only
/// passes scalars pre-narrowed by `zwapFindSafeSwapId`.
///
/// # Safety
/// `k_be_ptr` must point to `k_be_len` (== 32) valid bytes; `out_proof`
/// must be a valid, non-null pointer.
#[no_mangle]
pub unsafe extern "C" fn vizor_hashbind_prove(
    k_be_ptr: *const u8,
    k_be_len: usize,
    out_proof: *mut PKBuf,
) -> c_int {
    if out_proof.is_null() {
        set_error("prove: null output buffer");
        return STATUS_INVALID_INPUT;
    }
    *out_proof = PKBuf::empty();
    if k_be_ptr.is_null() || k_be_len != 32 {
        set_error("prove: scalar must be exactly 32 bytes");
        return STATUS_INVALID_INPUT;
    }
    let Some(&handle) = PROVER.get() else {
        set_error("prove: prover not initialized (call vizor_hashbind_init)");
        return VIZOR_STATUS_NOT_INITIALIZED;
    };

    let mut k = [0u8; 32];
    k.copy_from_slice(std::slice::from_raw_parts(k_be_ptr, k_be_len));
    let inputs = hashbind_core::generate_inputs_json(&k);
    k.zeroize();
    let mut inputs = match inputs {
        Ok(json) => json,
        Err(e) => {
            // hashbind-core errors describe bounds ("nonzero", "252 bits"),
            // never the scalar value itself.
            set_error(format!("prove: witness generation: {e:#}"));
            return STATUS_WITNESS_ERROR;
        }
    };
    let c_inputs = match CString::new(inputs.as_str()) {
        Ok(c) => c,
        Err(_) => {
            inputs.zeroize();
            set_error("prove: witness JSON contained NUL");
            return STATUS_WITNESS_ERROR;
        }
    };
    inputs.zeroize();

    let rc = pk_prove_json(handle as *const PKProver, c_inputs.as_ptr(), out_proof);
    // The inputs JSON embeds the raw scalar — scrub it before releasing.
    c_inputs.into_bytes().zeroize();
    if rc != STATUS_SUCCESS {
        capture_pk_error("prove: provekit");
    }
    rc
}

/// Verify a proof from `vizor_hashbind_prove` against `pallas.pkv` bytes.
/// Loads the verifier per call — this is a test/self-check entry point, not
/// a hot path. Returns 0 when the proof verifies.
///
/// # Safety
/// Both pointers must reference buffers of the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn vizor_hashbind_verify(
    pkv_ptr: *const u8,
    pkv_len: usize,
    proof_ptr: *const u8,
    proof_len: usize,
) -> c_int {
    if pkv_ptr.is_null() || pkv_len == 0 || proof_ptr.is_null() || proof_len == 0 {
        set_error("verify: null/empty buffer");
        return STATUS_INVALID_INPUT;
    }
    pk_init();
    let mut verifier: *mut PKVerifier = std::ptr::null_mut();
    let rc = pk_load_verifier_bytes(pkv_ptr, pkv_len, &mut verifier);
    if rc != STATUS_SUCCESS {
        capture_pk_error("verify: loading verifier scheme");
        return rc;
    }
    let rc = pk_verify(verifier, proof_ptr, proof_len);
    if rc != STATUS_SUCCESS {
        capture_pk_error("verify: provekit");
    }
    pk_free_verifier(verifier);
    rc
}

/// Copy the last error message (UTF-8, no key material) into `out`.
/// Free with `vizor_hashbind_free_buf`.
///
/// # Safety
/// `out` must be a valid, non-null pointer.
#[no_mangle]
pub unsafe extern "C" fn vizor_hashbind_last_error(out: *mut PKBuf) -> c_int {
    if out.is_null() {
        return STATUS_INVALID_INPUT;
    }
    *out = PKBuf::from_vec(LAST_ERROR.lock().unwrap().clone().into_bytes());
    STATUS_SUCCESS
}

/// Free a buffer returned by this library.
///
/// # Safety
/// `buf` must have come from this library and not been freed already.
#[no_mangle]
pub unsafe extern "C" fn vizor_hashbind_free_buf(buf: PKBuf) {
    pk_free_buf(buf);
}

/// Rust-test access to the vendored witness generator (the C surface never
/// exposes witness JSON). Not part of the cdylib ABI.
pub mod test_support {
    pub fn generate_inputs_json(k_be32: &[u8; 32]) -> String {
        crate::hashbind_core::generate_inputs_json(k_be32).expect("fixture scalar is valid")
    }
}
