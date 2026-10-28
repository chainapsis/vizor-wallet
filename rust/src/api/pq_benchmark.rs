//! On-device benchmark of the post-quantum signature schemes considered for transparent
//! spends: WOTS+, standalone FORS in four shapes, and three SLH-DSA (SPHINCS+) parameter sets. Measures
//! the same three
//! operations as common's `pq_schemes` benchmark: deriving a key pair from a seed, signing
//! a transaction digest, and verifying the signature.

use std::time::{Duration, Instant};

use sha2::{Digest, Sha256, Sha512};
use slh_dsa::{ParameterSet, Signature, SigningKey, VerifyingKey};

/// Timings for one scheme, as the median of all iterations, in microseconds.
pub struct PqSchemeTiming {
    pub scheme: String,
    pub keygen_us: f64,
    pub sign_us: f64,
    pub verify_us: f64,
    pub signature_bytes: u32,
    pub public_key_bytes: u32,
    pub iterations: u32,
}

const DIGEST: [u8; 32] = [7; 32];
const CONTEXT: &[u8] = b"Zcash/PQ/spend/v1";

/// A distinct 32-byte secret per iteration and label, so no step is served from a cache.
fn seed(label: &[u8], iteration: u32) -> [u8; 32] {
    Sha256::new()
        .chain_update(label)
        .chain_update(iteration.to_le_bytes())
        .finalize()
        .into()
}

fn median(mut samples: Vec<Duration>) -> f64 {
    samples.sort();
    samples[samples.len() / 2].as_secs_f64() * 1e6
}

fn time<T>(samples: &mut Vec<Duration>, f: impl FnOnce() -> T) -> T {
    let start = Instant::now();
    let out = std::hint::black_box(f());
    samples.push(start.elapsed());
    out
}

fn bench_wots(iterations: u32) -> PqSchemeTiming {
    use pq_crypto::wots::{SIGNATURE_BYTES, SigningKey, VerifyingKey};
    use pq_crypto::{MessageDigest, PublicSeed, SecretSeed};

    let (mut keygen, mut sign, mut verify) = (Vec::new(), Vec::new(), Vec::new());
    let mut public_key_bytes = 0;
    for i in 0..iterations {
        let key = time(&mut keygen, || {
            let key = SigningKey::from_seeds(
                SecretSeed::from_bytes(seed(b"wots-sk", i)),
                PublicSeed::from_bytes(seed(b"wots-pk", i)),
            )
            .expect("valid seeds");
            let public = key.verifying_key();
            (key, public)
        });
        let (key, public) = key;
        public_key_bytes = public.to_bytes().len();
        let signature = time(&mut sign, || {
            key.sign_digest(&MessageDigest::from_bytes(DIGEST))
        });
        // WOTS+ verifies by recomputing the public key from the signature.
        let recovered = time(&mut verify, || {
            VerifyingKey::recover_from_signature(
                &MessageDigest::from_bytes(DIGEST),
                &signature,
                public.public_seed().clone(),
            )
        });
        assert!(recovered == public, "WOTS+ signature failed to verify");
    }
    PqSchemeTiming {
        scheme: "WOTS+ (n=32, w=16)".into(),
        keygen_us: median(keygen),
        sign_us: median(sign),
        verify_us: median(verify),
        signature_bytes: SIGNATURE_BYTES as u32,
        public_key_bytes: public_key_bytes as u32,
        iterations,
    }
}

/// Benchmarks standalone FORS with `$k` trees of height `$a` and `$n`-byte hashes. A
/// macro because the digest length is a compile-time function of the shape.
macro_rules! bench_fors {
    ($name:expr, $k:literal, $a:literal, $n:literal, $digest_bytes:literal, $iterations:expr) => {{
        use pq_crypto::fors::{IndexDigest, Signature, SigningKey, VerifyingKey};
        use pq_crypto::{PublicSeed, SecretSeed};

        // FORS signs K * A bits of tree indices; derive them from the transaction digest.
        let digest = IndexDigest::<$k, $a>::from_bytes::<$digest_bytes>(
            Sha512::digest(DIGEST)[..$digest_bytes]
                .try_into()
                .expect("SHA-512 output is longer than any FORS digest"),
        );
        let iterations: u32 = $iterations;
        let (mut keygen, mut sign, mut verify) = (Vec::new(), Vec::new(), Vec::new());
        for i in 0..iterations {
            let (key, public) = time(&mut keygen, || {
                let key = SigningKey::<$k, $a, $n>::from_seeds(
                    SecretSeed::from_bytes(seed(b"fors-sk", i)[..$n].try_into().unwrap()),
                    PublicSeed::from_bytes(seed(b"fors-pk", i)[..$n].try_into().unwrap()),
                )
                .expect("valid seeds");
                let public = key.verifying_key();
                (key, public)
            });
            let signature = time(&mut sign, || key.sign_digest(&digest));
            let verified = time(&mut verify, || public.verify_digest(&digest, &signature));
            assert!(verified.is_ok(), "FORS signature failed to verify");
        }
        PqSchemeTiming {
            scheme: format!("{} (k={}, a={}, n={})", $name, $k, $a, $n),
            keygen_us: median(keygen),
            sign_us: median(sign),
            verify_us: median(verify),
            signature_bytes: Signature::<$k, $a, $n>::BYTES as u32,
            public_key_bytes: VerifyingKey::<$k, $a, $n>::BYTES as u32,
            iterations,
        }
    }};
}

fn bench_slh_dsa<P: ParameterSet>(name: &str, n: usize, iterations: u32) -> PqSchemeTiming {
    let (mut keygen, mut sign, mut verify) = (Vec::new(), Vec::new(), Vec::new());
    let (mut signature_bytes, mut public_key_bytes) = (0, 0);
    for i in 0..iterations {
        let key: SigningKey<P> = time(&mut keygen, || {
            SigningKey::slh_keygen_internal(
                &seed(b"slh-sk-seed", i)[..n],
                &seed(b"slh-sk-prf", i)[..n],
                &seed(b"slh-pk-seed", i)[..n],
            )
        });
        let signature: Signature<P> = time(&mut sign, || {
            key.try_sign_with_context(&DIGEST, CONTEXT, None)
                .expect("short context")
        });
        let public: &VerifyingKey<P> = key.as_ref();
        signature_bytes = signature.to_vec().len();
        public_key_bytes = public.to_vec().len();
        let verified = time(&mut verify, || {
            public.try_verify_with_context(&DIGEST, CONTEXT, &signature)
        });
        assert!(verified.is_ok(), "SLH-DSA signature failed to verify");
    }
    PqSchemeTiming {
        scheme: name.into(),
        keygen_us: median(keygen),
        sign_us: median(sign),
        verify_us: median(verify),
        signature_bytes: signature_bytes as u32,
        public_key_bytes: public_key_bytes as u32,
        iterations,
    }
}

/// Runs every scheme `iterations` times (at least once) and returns their median timings.
pub fn run_pq_signature_benchmark(iterations: u32) -> Vec<PqSchemeTiming> {
    let iterations = iterations.max(1);
    let timings = vec![
        bench_wots(iterations),
        bench_fors!("FORS 256f", 35, 9, 32, 40, iterations),
        bench_fors!("FORS 256s", 22, 14, 32, 39, iterations),
        bench_fors!("FORS 192f", 33, 8, 24, 33, iterations),
        bench_fors!("FORS 192s", 17, 14, 24, 30, iterations),
        bench_fors!("FORS 16x16", 16, 16, 32, 32, iterations),
        bench_fors!("FORS 128s", 14, 12, 16, 21, iterations),
        bench_slh_dsa::<slh_dsa::Sha2_128s>("SLH-DSA-SHA2-128s", 16, iterations),
        bench_slh_dsa::<slh_dsa::Sha2_128f>("SLH-DSA-SHA2-128f", 16, iterations),
        bench_slh_dsa::<slh_dsa::Sha2_192s>("SLH-DSA-SHA2-192s", 24, iterations),
        bench_slh_dsa::<slh_dsa::Sha2_192f>("SLH-DSA-SHA2-192f", 24, iterations),
        bench_slh_dsa::<slh_dsa::Sha2_256s>("SLH-DSA-SHA2-256s", 32, iterations),
    ];
    // One line per scheme so results can be read from the device log. Logged at warn
    // level because iOS does not relay info-level os_log messages to the device syslog.
    for t in &timings {
        log::warn!(
            "PQBENCH scheme={:?} keygen_us={:.1} sign_us={:.1} verify_us={:.1} signature_bytes={} public_key_bytes={} iterations={}",
            t.scheme,
            t.keygen_us,
            t.sign_us,
            t.verify_us,
            t.signature_bytes,
            t.public_key_bytes,
            t.iterations
        );
    }
    timings
}

#[cfg(test)]
mod tests {
    #[test]
    fn every_scheme_signs_and_verifies() {
        let timings = super::run_pq_signature_benchmark(1);
        assert_eq!(timings.len(), 8);
        let sizes: Vec<_> = timings[1..5].iter().map(|t| t.signature_bytes).collect();
        assert_eq!(sizes, [11_200, 10_560, 8_704, 2_912]);
        assert_eq!(timings[5].signature_bytes, 7856);
        assert_eq!(timings[5].public_key_bytes, 32);
    }
}
