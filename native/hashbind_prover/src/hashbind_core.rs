// VENDORED — do not edit.
//
// Verbatim copy of shielded-zwap-e2z-proxy rust/hashbind-core/src/lib.rs
// (the single source of truth for zwap hashbind witness math, consumed by
// solverd-v2 and the browser FE's hashbind-inputs-wasm). Vendored because
// the proxy repo is not a publishable cargo dependency; the golden-fixture
// test in ../tests/prove_roundtrip.rs (inputs_json_matches_proxy_golden)
// fails if this copy ever drifts from the upstream inputs.json emission.
//
// Upstream file header follows.

//! Pallas hash-binding circuit witness/hint math — the single source of
//! truth for generating the Noir ABI inputs of `packages/zwap-circuits`.
//!
//! Consumed by:
//! - `zwap-solverd-v2` (`proof/hashbind_witness.rs`): converts
//!   [`HashbindWitness`] into a `noirc_abi::InputMap` for native witness
//!   execution / the wasm sidecar.
//! - `hashbind-inputs-wasm`: wasm-bindgen wrapper that emits the
//!   `inputs.json` text for the browser prover (`noir_js.execute`).
//!
//! There is intentionally NO TypeScript port of this math — the browser
//! gets it via the wasm wrapper, so the comb/limb/inverse logic can never
//! drift between solver and FE.
//!
//! The circuit (see `packages/zwap-circuits/src/main.nr`) constrains a
//! 252-bit scalar `k`: `SHA256(k_be32)` is the public digest output and
//! `k·G` must equal the public Pallas point given as 85-bit limbs. All the
//! Brillig hints (RCB adds, modular-mul quotients, the final
//! projective→affine check) are supplied as private witnesses, computed
//! here.

use std::sync::OnceLock;

use anyhow::{Context, Result, ensure};
use num_bigint::BigUint;
use num_traits::{One, ToPrimitive, Zero};

const PALLAS_P_HEX: &str = "40000000000000000000000000000000224698fc094cf91b992d30ed00000001";
// Generator used by zwap-circuits pallas_nr: Orchard SpendAuthG
// = pallas hash_to_curve("z.cash:Orchard")(b"G"), sec1 03375523b3….
// MUST match BOTH gen_pallas_tables.py (the circuit's baked comb tables)
// AND the protocol's DLEq base (packages/crypto pallas-dleq G_PALLAS,
// protocol-core pallas_dleq::spend_auth_g): the hash-binding proof's
// public point is compared against the DLEq Pallas key, so a different
// base makes the binding unsatisfiable for every real key.
const GEN_X_HEX: &str = "375523b328f1d6063b8d187c3e5f445f0c7f0ce37b70a10c8d1a7284b875c963";
const GEN_Y_HEX: &str = "1ad0357fdf1a66db7b10bcfcfed624fbdfc914fec005bdd84ce33e817b0c3bc9";

pub const HASH_BINDING_SCALAR_BITS: u64 = 252;
pub const LIMB_BITS: usize = 85;
const WINDOW: usize = 7;
const N_WINDOWS: usize = 36;
const ENTRIES: usize = 1 << WINDOW;

pub type Limbs = [u128; 3];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AffinePoint {
    pub x: BigUint,
    pub y: BigUint,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ProjectivePoint {
    x: BigUint,
    y: BigUint,
    z: BigUint,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectiveLimbs {
    pub x: Limbs,
    pub y: Limbs,
    pub z: Limbs,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MulHint {
    pub z: Limbs,
    pub k: Limbs,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AddSubHint {
    pub z: Limbs,
    pub q: BigUint,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RcbHint {
    pub muls: Vec<MulHint>,
    pub b3_muls: Vec<AddSubHint>,
    pub triple: AddSubHint,
    pub adds: Vec<AddSubHint>,
    pub subs: Vec<AddSubHint>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CheckHints {
    pub zinv_mul: MulHint,
    pub px_z_mul: MulHint,
    pub py_z_mul: MulHint,
    pub dx_sub: AddSubHint,
    pub dy_sub: AddSubHint,
}

/// The complete private+public input set for one hash-binding proof.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HashbindWitness {
    pub scalar: BigUint,
    pub z_inv_limbs: Limbs,
    pub px_limbs: Limbs,
    pub py_limbs: Limbs,
    pub check_hints: CheckHints,
    pub rcb_hints: Vec<RcbHint>,
}

/// Compute all circuit inputs for the 32-byte big-endian scalar.
///
/// The scalar must be nonzero and at most 252 bits — the circuit's
/// top-byte assert enforces the same bound in-proof.
pub fn generate_witness(scalar_be: &[u8; 32]) -> Result<HashbindWitness> {
    let scalar = BigUint::from_bytes_be(scalar_be);
    ensure!(!scalar.is_zero(), "hash-binding scalar must be nonzero");
    ensure!(
        scalar.bits() <= HASH_BINDING_SCALAR_BITS,
        "hash-binding scalar has {} bits; expected at most {}",
        scalar.bits(),
        HASH_BINDING_SCALAR_BITS
    );

    let affine = scalar_mul_affine(&scalar).context("computing public Pallas point")?;
    let mut rcb_hints = Vec::with_capacity(N_WINDOWS - 1);
    let acc = comb_projective(&scalar, &mut rcb_hints).context("computing Pallas comb hints")?;
    ensure!(
        rcb_hints.len() == N_WINDOWS - 1,
        "expected {} RCB hints, generated {}",
        N_WINDOWS - 1,
        rcb_hints.len()
    );

    let acc_x = from_limbs(&acc.x);
    let acc_y = from_limbs(&acc.y);
    let acc_z = from_limbs(&acc.z);
    let z_inv = mod_inv(&acc_z).context("inverting final projective z")?;
    ensure!(
        mod_mul(&acc_x, &z_inv) == affine.x,
        "generated witness x-coordinate sanity check failed"
    );
    ensure!(
        mod_mul(&acc_y, &z_inv) == affine.y,
        "generated witness y-coordinate sanity check failed"
    );

    let z_inv_limbs = limbs(&z_inv);
    let px_limbs = limbs(&affine.x);
    let py_limbs = limbs(&affine.y);
    let check_hints = build_check_hints(&acc, &z_inv_limbs, &px_limbs, &py_limbs);

    Ok(HashbindWitness {
        scalar,
        z_inv_limbs,
        px_limbs,
        py_limbs,
        check_hints,
        rcb_hints,
    })
}

// ---------------------------------------------------------------------------
// inputs.json emission
// ---------------------------------------------------------------------------

/// Serialize a witness to the `inputs.json` text consumed by the prover
/// (`noir_js.execute` in the browser / the wasm-runner sidecar).
///
/// Field encoding matches `noirc_abi`'s JSON encoder exactly
/// (`format_field_string`): lowercase hex, leading zeros trimmed, padded
/// to even length, `"0x00"` for zero — so the output is byte-compatible
/// with `input_map_to_json(generate_input_map(k))` on the solver
/// (asserted by solverd-v2's `core_json_matches_input_map_json` test).
pub fn witness_to_inputs_json(w: &HashbindWitness) -> String {
    let v = witness_to_json_value(w);
    serde_json::to_string(&v).expect("witness JSON serialization cannot fail")
}

/// Same as [`witness_to_inputs_json`] but as a `serde_json::Value`.
pub fn witness_to_json_value(w: &HashbindWitness) -> serde_json::Value {
    use serde_json::json;
    json!({
        "scalar": field_str(&w.scalar),
        "z_inv_limbs": limbs_json(&w.z_inv_limbs),
        "px_limbs": limbs_json(&w.px_limbs),
        "py_limbs": limbs_json(&w.py_limbs),
        "check_hints": {
            "zinv_mul": mul_hint_json(&w.check_hints.zinv_mul),
            "px_z_mul": mul_hint_json(&w.check_hints.px_z_mul),
            "py_z_mul": mul_hint_json(&w.check_hints.py_z_mul),
            "dx_sub": addsub_hint_json(&w.check_hints.dx_sub),
            "dy_sub": addsub_hint_json(&w.check_hints.dy_sub),
        },
        "rcb_hints": w.rcb_hints.iter().map(rcb_hint_json).collect::<Vec<_>>(),
    })
}

/// Convenience: scalar bytes → inputs.json in one call (the
/// hashbind-inputs-wasm entry point).
pub fn generate_inputs_json(scalar_be: &[u8; 32]) -> Result<String> {
    Ok(witness_to_inputs_json(&generate_witness(scalar_be)?))
}

/// noirc_abi `format_field_string` semantics: trimmed lowercase hex,
/// even-length, zero = "0x00".
fn field_str(value: &BigUint) -> String {
    if value.is_zero() {
        return "0x00".to_owned();
    }
    let mut s = format!("{value:x}");
    if s.len() % 2 != 0 {
        s.insert(0, '0');
    }
    format!("0x{s}")
}

fn limb_str(limb: u128) -> String {
    field_str(&BigUint::from(limb))
}

fn limbs_json(limbs: &Limbs) -> serde_json::Value {
    serde_json::Value::Array(limbs.iter().map(|l| limb_str(*l).into()).collect())
}

fn mul_hint_json(hint: &MulHint) -> serde_json::Value {
    serde_json::json!({ "z": limbs_json(&hint.z), "k": limbs_json(&hint.k) })
}

fn addsub_hint_json(hint: &AddSubHint) -> serde_json::Value {
    serde_json::json!({ "z": limbs_json(&hint.z), "q": field_str(&hint.q) })
}

fn rcb_hint_json(hint: &RcbHint) -> serde_json::Value {
    serde_json::json!({
        "muls": hint.muls.iter().map(mul_hint_json).collect::<Vec<_>>(),
        "b3_muls": hint.b3_muls.iter().map(addsub_hint_json).collect::<Vec<_>>(),
        "triple": addsub_hint_json(&hint.triple),
        "adds": hint.adds.iter().map(addsub_hint_json).collect::<Vec<_>>(),
        "subs": hint.subs.iter().map(addsub_hint_json).collect::<Vec<_>>(),
    })
}

// ---------------------------------------------------------------------------
// Curve / comb / hint math (moved verbatim from solverd-v2
// proof/hashbind_witness.rs — behavior must never change without
// recompiling the circuit)
// ---------------------------------------------------------------------------

fn build_check_hints(
    acc: &ProjectiveLimbs,
    z_inv_limbs: &Limbs,
    px_limbs: &Limbs,
    py_limbs: &Limbs,
) -> CheckHints {
    let zinv_mul = mul_hint(&acc.z, z_inv_limbs);
    let px_z_mul = mul_hint(px_limbs, &acc.z);
    let py_z_mul = mul_hint(py_limbs, &acc.z);
    let dx_sub = addsub_hint_sub(&px_z_mul.z, &acc.x);
    let dy_sub = addsub_hint_sub(&py_z_mul.z, &acc.y);

    CheckHints {
        zinv_mul,
        px_z_mul,
        py_z_mul,
        dx_sub,
        dy_sub,
    }
}

/// Double-and-add over the affine representation; used for the PUBLIC
/// point only (the in-circuit comb path below recomputes it with hints).
pub fn scalar_mul_affine(scalar: &BigUint) -> Result<AffinePoint> {
    let mut k = scalar.clone();
    let mut acc: Option<AffinePoint> = None;
    let mut addend = generator();

    while !k.is_zero() {
        if k.bit(0) {
            acc = point_add(acc, Some(addend.clone()));
        }
        k >>= 1usize;
        if !k.is_zero() {
            addend = point_add(Some(addend.clone()), Some(addend))
                .context("doubling Pallas point unexpectedly reached infinity")?;
        }
    }

    acc.context("nonzero scalar unexpectedly produced the point at infinity")
}

fn comb_projective(scalar: &BigUint, rcb_hints: &mut Vec<RcbHint>) -> Result<ProjectiveLimbs> {
    let tables = comb_tables()?;
    let d0 = scalar_window_digit(scalar, 0);
    let mut acc = projective_limbs(&tables[0][d0]);

    for (window, row) in tables.iter().enumerate().skip(1) {
        let digit = scalar_window_digit(scalar, window);
        let selected = projective_limbs(&row[digit]);
        acc = rcb_add(&acc, &selected, rcb_hints);
    }

    Ok(acc)
}

fn comb_tables() -> Result<Vec<Vec<ProjectivePoint>>> {
    let mut tables = Vec::with_capacity(N_WINDOWS);
    let mut base = generator();

    for _ in 0..N_WINDOWS {
        let mut row = Vec::with_capacity(ENTRIES);
        row.push(ProjectivePoint {
            x: BigUint::zero(),
            y: BigUint::one(),
            z: BigUint::zero(),
        });

        let mut acc: Option<AffinePoint> = None;
        for _ in 1..ENTRIES {
            acc = point_add(acc, Some(base.clone()));
            let point = acc
                .as_ref()
                .context("comb table entry unexpectedly reached infinity")?;
            row.push(ProjectivePoint {
                x: point.x.clone(),
                y: point.y.clone(),
                z: BigUint::one(),
            });
        }
        tables.push(row);

        for _ in 0..WINDOW {
            base = point_add(Some(base.clone()), Some(base))
                .context("doubling Pallas comb base unexpectedly reached infinity")?;
        }
    }

    Ok(tables)
}

fn scalar_window_digit(scalar: &BigUint, window: usize) -> usize {
    let mut digit = 0usize;
    for bit in 0..WINDOW {
        if scalar.bit((WINDOW * window + bit) as u64) {
            digit |= 1usize << bit;
        }
    }
    digit
}

fn rcb_add(p: &ProjectiveLimbs, q: &ProjectiveLimbs, hints: &mut Vec<RcbHint>) -> ProjectiveLimbs {
    let mut muls = Vec::with_capacity(12);
    let mut b3_muls = Vec::with_capacity(2);
    let mut adds = Vec::with_capacity(12);
    let mut subs = Vec::with_capacity(5);

    let t0 = rcb_mul(&mut muls, &p.x, &q.x);
    let t1 = rcb_mul(&mut muls, &p.y, &q.y);
    let t2 = rcb_mul(&mut muls, &p.z, &q.z);

    let t3a = rcb_add_hint(&mut adds, &p.x, &p.y);
    let t4a = rcb_add_hint(&mut adds, &q.x, &q.y);
    let t3b = rcb_mul(&mut muls, &t3a, &t4a);
    let t4b = rcb_add_hint(&mut adds, &t0, &t1);
    let t3 = rcb_sub_hint(&mut subs, &t3b, &t4b);

    let t4c = rcb_add_hint(&mut adds, &p.y, &p.z);
    let x3a = rcb_add_hint(&mut adds, &q.y, &q.z);
    let t4d = rcb_mul(&mut muls, &t4c, &x3a);
    let x3b = rcb_add_hint(&mut adds, &t1, &t2);
    let t4 = rcb_sub_hint(&mut subs, &t4d, &x3b);

    let x3c = rcb_add_hint(&mut adds, &p.x, &p.z);
    let y3a = rcb_add_hint(&mut adds, &q.x, &q.z);
    let x3d = rcb_mul(&mut muls, &x3c, &y3a);
    let y3b = rcb_add_hint(&mut adds, &t0, &t2);
    let y3_s1 = rcb_sub_hint(&mut subs, &x3d, &y3b);

    let (t0_new, triple) = mul_by_const_hint(&t0, 3u32);
    let (t2_scaled, b3_0) = mul_by_const_hint(&t2, 15u32);
    b3_muls.push(b3_0);

    let z3_s1 = rcb_add_hint(&mut adds, &t1, &t2_scaled);
    let t1_new = rcb_sub_hint(&mut subs, &t1, &t2_scaled);

    let (y3_s2, b3_1) = mul_by_const_hint(&y3_s1, 15u32);
    b3_muls.push(b3_1);

    let x3_part = rcb_mul(&mut muls, &t4, &y3_s2);
    let t2_prod = rcb_mul(&mut muls, &t3, &t1_new);
    let x3_final = rcb_sub_hint(&mut subs, &t2_prod, &x3_part);

    let y3_part1 = rcb_mul(&mut muls, &y3_s2, &t0_new);
    let y3_part2 = rcb_mul(&mut muls, &t1_new, &z3_s1);
    let y3_final = rcb_add_hint(&mut adds, &y3_part2, &y3_part1);

    let t0_prod = rcb_mul(&mut muls, &t0_new, &t3);
    let z3_mul = rcb_mul(&mut muls, &z3_s1, &t4);
    let z3_final = rcb_add_hint(&mut adds, &z3_mul, &t0_prod);

    hints.push(RcbHint {
        muls,
        b3_muls,
        triple,
        adds,
        subs,
    });

    ProjectiveLimbs {
        x: x3_final,
        y: y3_final,
        z: z3_final,
    }
}

fn rcb_mul(muls: &mut Vec<MulHint>, a: &Limbs, b: &Limbs) -> Limbs {
    let hint = mul_hint(a, b);
    let z = hint.z;
    muls.push(hint);
    z
}

fn rcb_add_hint(adds: &mut Vec<AddSubHint>, a: &Limbs, b: &Limbs) -> Limbs {
    let hint = addsub_hint_add(a, b);
    let z = hint.z;
    adds.push(hint);
    z
}

fn rcb_sub_hint(subs: &mut Vec<AddSubHint>, a: &Limbs, b: &Limbs) -> Limbs {
    let hint = addsub_hint_sub(a, b);
    let z = hint.z;
    subs.push(hint);
    z
}

fn mul_hint(x_limbs: &Limbs, y_limbs: &Limbs) -> MulHint {
    let x = from_limbs(x_limbs);
    let y = from_limbs(y_limbs);
    let product = &x * &y;
    let z = &product % pallas_p();
    let k = (&product - &z) / pallas_p();
    MulHint {
        z: limbs(&z),
        k: limbs(&k),
    }
}

fn addsub_hint_add(x_limbs: &Limbs, y_limbs: &Limbs) -> AddSubHint {
    let x = from_limbs(x_limbs);
    let y = from_limbs(y_limbs);
    let sum = x + y;
    let (z, q) = if sum >= *pallas_p() {
        (sum - pallas_p(), BigUint::one())
    } else {
        (sum, BigUint::zero())
    };
    AddSubHint { z: limbs(&z), q }
}

fn addsub_hint_sub(x_limbs: &Limbs, y_limbs: &Limbs) -> AddSubHint {
    let x = from_limbs(x_limbs);
    let y = from_limbs(y_limbs);
    let (z, q) = if x < y {
        (x + pallas_p() - y, BigUint::one())
    } else {
        (x - y, BigUint::zero())
    };
    AddSubHint { z: limbs(&z), q }
}

fn mul_by_const_hint(x_limbs: &Limbs, multiplier: u32) -> (Limbs, AddSubHint) {
    let x = from_limbs(x_limbs);
    let value = BigUint::from(multiplier) * x;
    let z = &value % pallas_p();
    let q = (&value - &z) / pallas_p();
    let z_limbs = limbs(&z);
    (z_limbs, AddSubHint { z: z_limbs, q })
}

fn point_add(p: Option<AffinePoint>, q: Option<AffinePoint>) -> Option<AffinePoint> {
    let Some(p) = p else {
        return q;
    };
    let Some(q) = q else {
        return Some(p);
    };

    let y_sum = mod_add(&p.y, &q.y);
    if p.x == q.x && y_sum.is_zero() {
        return None;
    }

    let slope = if p.x == q.x {
        let numerator = mod_mul(&BigUint::from(3u32), &mod_mul(&p.x, &p.x));
        let denominator = mod_mul(&BigUint::from(2u32), &p.y);
        mod_mul(&numerator, &mod_inv(&denominator)?)
    } else {
        let numerator = mod_sub(&q.y, &p.y);
        let denominator = mod_sub(&q.x, &p.x);
        mod_mul(&numerator, &mod_inv(&denominator)?)
    };

    let rx = mod_sub(&mod_sub(&mod_mul(&slope, &slope), &p.x), &q.x);
    let ry = mod_sub(&mod_mul(&slope, &mod_sub(&p.x, &rx)), &p.y);
    Some(AffinePoint { x: rx, y: ry })
}

fn mod_add(a: &BigUint, b: &BigUint) -> BigUint {
    (a + b) % pallas_p()
}

fn mod_sub(a: &BigUint, b: &BigUint) -> BigUint {
    if a >= b {
        (a - b) % pallas_p()
    } else {
        (a + pallas_p() - b) % pallas_p()
    }
}

fn mod_mul(a: &BigUint, b: &BigUint) -> BigUint {
    (a * b) % pallas_p()
}

fn mod_inv(value: &BigUint) -> Option<BigUint> {
    if value.is_zero() {
        None
    } else {
        Some(value.modpow(&(pallas_p() - BigUint::from(2u32)), pallas_p()))
    }
}

fn projective_limbs(point: &ProjectivePoint) -> ProjectiveLimbs {
    ProjectiveLimbs {
        x: limbs(&point.x),
        y: limbs(&point.y),
        z: limbs(&point.z),
    }
}

pub fn limbs(value: &BigUint) -> Limbs {
    let reduced = value % pallas_p();
    let mask = limb_mask();
    [
        (&reduced & mask)
            .to_u128()
            .expect("85-bit limb fits into u128"),
        ((&reduced >> LIMB_BITS) & mask)
            .to_u128()
            .expect("85-bit limb fits into u128"),
        ((&reduced >> (2 * LIMB_BITS)) & mask)
            .to_u128()
            .expect("85-bit limb fits into u128"),
    ]
}

pub fn from_limbs(limbs: &Limbs) -> BigUint {
    BigUint::from(limbs[0])
        + (BigUint::from(limbs[1]) << LIMB_BITS)
        + (BigUint::from(limbs[2]) << (2 * LIMB_BITS))
}

fn generator() -> AffinePoint {
    AffinePoint {
        x: gen_x().clone(),
        y: gen_y().clone(),
    }
}

fn pallas_p() -> &'static BigUint {
    static VALUE: OnceLock<BigUint> = OnceLock::new();
    VALUE.get_or_init(|| parse_hex_biguint(PALLAS_P_HEX))
}

fn gen_x() -> &'static BigUint {
    static VALUE: OnceLock<BigUint> = OnceLock::new();
    VALUE.get_or_init(|| parse_hex_biguint(GEN_X_HEX))
}

fn gen_y() -> &'static BigUint {
    static VALUE: OnceLock<BigUint> = OnceLock::new();
    VALUE.get_or_init(|| parse_hex_biguint(GEN_Y_HEX))
}

fn limb_mask() -> &'static BigUint {
    static VALUE: OnceLock<BigUint> = OnceLock::new();
    VALUE.get_or_init(|| (BigUint::one() << LIMB_BITS) - BigUint::one())
}

fn parse_hex_biguint(value: &str) -> BigUint {
    BigUint::parse_bytes(value.as_bytes(), 16).expect("valid hex constant")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_zero_scalar() {
        let err = generate_witness(&[0u8; 32]).expect_err("zero scalar is invalid");
        assert!(err.to_string().contains("nonzero"));
    }

    #[test]
    fn rejects_scalars_wider_than_252_bits() {
        let mut scalar = [0u8; 32];
        scalar[0] = 0x10;
        let err = generate_witness(&scalar).expect_err("253-bit scalar is invalid");
        assert!(err.to_string().contains("expected at most 252"));
    }

    #[test]
    fn scalar_one_witness_exposes_generator_and_35_rcb_hints() {
        let mut scalar = [0u8; 32];
        scalar[31] = 1;
        let w = generate_witness(&scalar).unwrap();
        assert_eq!(w.scalar, BigUint::one());
        // Generator = Orchard SpendAuthG; scalar=1 → public key = G itself.
        let gen_x = num_bigint::BigUint::parse_bytes(GEN_X_HEX.as_bytes(), 16).unwrap();
        let gen_y = num_bigint::BigUint::parse_bytes(GEN_Y_HEX.as_bytes(), 16).unwrap();
        assert_eq!(w.px_limbs, limbs(&gen_x));
        assert_eq!(w.py_limbs, limbs(&gen_y));
        assert_eq!(w.rcb_hints.len(), 35);
    }

    #[test]
    fn field_str_matches_noirc_format_field_string() {
        assert_eq!(field_str(&BigUint::zero()), "0x00");
        assert_eq!(field_str(&BigUint::from(1u8)), "0x01");
        assert_eq!(field_str(&BigUint::from(0x1au8)), "0x1a");
        assert_eq!(field_str(&BigUint::from(0x1abu16)), "0x01ab");
        assert_eq!(field_str(&BigUint::from(0xffffu16)), "0xffff");
    }

    #[test]
    fn inputs_json_shape() {
        let mut scalar = [0u8; 32];
        scalar[31] = 7;
        let json = generate_inputs_json(&scalar).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["scalar"], "0x07");
        assert_eq!(v["z_inv_limbs"].as_array().unwrap().len(), 3);
        assert_eq!(v["px_limbs"].as_array().unwrap().len(), 3);
        assert_eq!(v["py_limbs"].as_array().unwrap().len(), 3);
        assert_eq!(v["rcb_hints"].as_array().unwrap().len(), 35);
        let rcb0 = &v["rcb_hints"][0];
        assert_eq!(rcb0["muls"].as_array().unwrap().len(), 12);
        assert_eq!(rcb0["b3_muls"].as_array().unwrap().len(), 2);
        assert_eq!(rcb0["adds"].as_array().unwrap().len(), 12);
        assert_eq!(rcb0["subs"].as_array().unwrap().len(), 5);
        for k in ["zinv_mul", "px_z_mul", "py_z_mul", "dx_sub", "dy_sub"] {
            assert!(v["check_hints"].get(k).is_some(), "missing check_hints.{k}");
        }
    }
}
