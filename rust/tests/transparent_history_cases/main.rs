//! Transparent history qualification suite, Vizor layer (H01-H13), public and
//! private profiles. See README.md in this directory and
//! `scripts/e2e/transparent-history-cases.sh`.
//!
//! One isolated Docker regtest chain hosts every case. Alice's two accounts
//! (A0, A1 from separate seeds) live in the Vizor wallet under test; B, C and
//! D are runtime keys held only by this harness; Z is zcashd. Expected values
//! come from `scripts/e2e/transparent_history_oracle.py`, never from Vizor.
//!
//! The private profile's switches are process-wide, so run one profile per
//! process: `--exact <profile>_profile_h01_to_h13`.

mod cases;
mod chain;
mod faucet;
mod keys;
mod provers;
mod proxy;
mod publication;
mod report;
mod signer;
mod vizor;

use rust_lib_zcash_wallet::api::{simple as simple_api, sync as sync_api};

fn run(profile: &'static str) {
    report::set_profile(profile);
    // Every ephemeral (TEX) returned-funds check is due on each sync, so H10's
    // return is observable without waiting a day (debug builds only).
    std::env::set_var("ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW", "1");
    if profile == "private" {
        // Debug builds only: regtest may select private transparent recovery
        // and reach the harness's loopback service over plain HTTP.
        std::env::set_var("ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT", "1");
        // The development flag, the private-queries preference, and that the
        // preference was read from storage: what a flagged build with private
        // queries on has at startup.
        simple_api::configure_private_transparent_recovery(true);
        sync_api::set_enhance_pir_enabled(true);
        sync_api::set_enhance_pir_preference_confirmed(true);
    }
    let _ = rustls::crypto::ring::default_provider().install_default();
    let mut ctx = cases::Ctx::new();
    ctx.run();
    let status = ctx.finish();
    assert_eq!(
        status,
        0,
        "transparent history qualification ({profile}) failed; see {}/results.json",
        ctx.suite.out.display()
    );
}

#[test]
#[ignore = "requires Docker; builds an isolated regtest chain; run scripts/e2e/transparent-history-cases.sh"]
fn public_profile_h01_to_h13() {
    run("public");
}

#[test]
#[ignore = "requires Docker and a debug build; builds an isolated regtest chain and transparent PIR service; run scripts/e2e/transparent-history-cases.sh --profile private"]
fn private_profile_h01_to_h13() {
    assert!(
        cfg!(debug_assertions),
        "the private profile needs a debug build: release builds never select private recovery on regtest"
    );
    run("private");
}
