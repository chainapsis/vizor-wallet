pub mod action;
pub mod decompose;
pub mod elgamal;
pub mod governance;
pub mod hotkey;
#[cfg(any(feature = "client-pir", feature = "client-tree-sync"))]
mod http_transport;
pub mod note_bundling;
pub mod pir_snapshot;
pub mod share_policy;
pub mod share_tracking;
pub mod storage;
#[cfg(feature = "client-tree-sync")]
pub mod tree_sync;
pub mod types;
pub mod vote_commitment;
pub mod witness;
pub mod zkp1;
pub mod zkp2;

#[cfg(any(feature = "client-pir", feature = "client-tree-sync"))]
pub use http_transport::HyperTransport;
#[cfg(feature = "client-pir")]
pub use pir_client::{
    ImtProofData, PirClient, PirClientBlocking, Transport, TransportFuture, TransportResponse,
};

pub use governance::BALLOT_DIVISOR;
pub use types::*;

/// Warm process-lifetime proving-key caches used by on-device voting proofs.
///
/// This is intentionally best-effort at the cache layer: callers should invoke
/// it from a background task before the first proof is needed.
pub fn warm_proving_caches() {
    const KEYGEN_STACK_BYTES: usize = 64 * 1024 * 1024;

    let handles = [
        std::thread::Builder::new()
            .name("voting-delegation-cache-warmup".to_string())
            .stack_size(KEYGEN_STACK_BYTES)
            .spawn(|| {
                let _ = voting_circuits::delegation::warm_delegation_keys();
            })
            .expect("spawn delegation proving cache warm-up thread"),
        std::thread::Builder::new()
            .name("voting-vote-proof-cache-warmup".to_string())
            .stack_size(KEYGEN_STACK_BYTES)
            .spawn(|| {
                let _ = voting_circuits::vote_proof::warm_vote_proof_keys();
            })
            .expect("spawn vote proof cache warm-up thread"),
    ];

    for handle in handles {
        handle
            .join()
            .expect("proving cache warm-up thread panicked");
    }
}
