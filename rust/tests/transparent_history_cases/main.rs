//! Transparent history qualification suite, Vizor layer (H01-H13), public
//! profile. See README.md in this directory and
//! `scripts/e2e/transparent-history-cases.sh`.
//!
//! One isolated Docker regtest chain hosts every case. Alice's two accounts
//! (A0, A1 from separate seeds) live in the Vizor wallet under test; B, C and
//! D are runtime keys held only by this harness; Z is zcashd. Expected values
//! come from `scripts/e2e/transparent_history_oracle.py`, never from Vizor.

mod cases;
mod chain;
mod faucet;
mod keys;
mod provers;
mod proxy;
mod report;
mod signer;
mod vizor;

#[test]
#[ignore = "requires Docker; builds an isolated regtest chain; run scripts/e2e/transparent-history-cases.sh"]
fn public_profile_h01_to_h13() {
    // Every ephemeral (TEX) returned-funds check is due on each sync, so H10's
    // return is observable without waiting a day (debug builds only).
    std::env::set_var("ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW", "1");
    let _ = rustls::crypto::ring::default_provider().install_default();
    let mut ctx = cases::Ctx::new();
    ctx.run();
    let status = ctx.finish();
    assert_eq!(
        status,
        0,
        "transparent history qualification failed; see {}/results.json",
        ctx.suite.out.display()
    );
}
