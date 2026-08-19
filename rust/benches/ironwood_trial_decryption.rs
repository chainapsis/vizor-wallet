//! Benchmarks the production Ironwood compact trial-decryption seam.
//!
//! [`zcash_client_backend::data_api::chain::scan_cached_blocks`] collects
//! compact outputs using a 100-output flush threshold. It dispatches them via
//! [`zcash_note_encryption::batch::try_compact_note_decryption`]. Benchmarking
//! that function directly isolates the crypto work while preserving its batch
//! shape. The public per-block scanner is deliberately not measured here: it
//! uses an inline, per-transaction path and includes unrelated pool work.

use std::hint::black_box;

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use orchard::{
    keys::{FullViewingKey, PreparedIncomingViewingKey},
    note_encryption::{CompactAction, IronwoodDomain},
};
use rand_chacha::{rand_core::SeedableRng, ChaCha20Rng};
use zcash_client_backend::{
    data_api::testing::{AddressType, IronwoodFvk, TestFvk},
    proto::compact_formats::CompactTx,
};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_note_encryption::batch;
use zcash_protocol::{
    consensus::{BlockHeight, Network, NetworkUpgrade, Parameters},
    value::Zatoshis,
};
use zip32::{AccountId, Scope};

const ACTION_COUNT: usize = 100;
const BACKGROUND_ACCOUNT_COUNTS: [usize; 3] = [2, 4, 8];
const ACTIVE_ACCOUNT_SEED_TAG: u8 = 7;
const BACKGROUND_ACCOUNT_SEED_TAGS: [u8; 8] = [13, 17, 23, 29, 31, 37, 41, 43];
const RECIPIENT_SEED_TAG: u8 = 113;
const NOTE_VALUE: Zatoshis = Zatoshis::const_from_u64(1);
const RNG_SEED: [u8; 32] = [19; 32];

type CompactOutput = (IronwoodDomain, CompactAction);

fn ironwood_height() -> BlockHeight {
    Network::TestNetwork
        .activation_height(NetworkUpgrade::Nu6_3)
        .expect("testnet has an Ironwood activation height")
}

fn account(seed_tag: u8) -> FullViewingKey {
    UnifiedSpendingKey::from_seed(&Network::TestNetwork, &[seed_tag; 32], AccountId::ZERO)
        .expect("valid benchmark seed")
        .to_unified_full_viewing_key()
        .orchard()
        .expect("benchmark account has an Orchard component")
        .clone()
}

fn external_ivk(fvk: &FullViewingKey) -> PreparedIncomingViewingKey {
    PreparedIncomingViewingKey::new(&fvk.to_ivk(Scope::External))
}

fn unrelated_outputs(recipient: &FullViewingKey) -> Vec<CompactOutput> {
    let recipient = IronwoodFvk(recipient.clone());
    let mut tx = CompactTx::default();
    let mut rng = ChaCha20Rng::from_seed(RNG_SEED);

    for _ in 0..ACTION_COUNT {
        recipient.add_output(
            &mut tx,
            &Network::TestNetwork,
            ironwood_height(),
            None,
            AddressType::DefaultExternal,
            NOTE_VALUE,
            0,
            &mut rng,
        );
    }

    assert_eq!(tx.ironwood_actions.len(), ACTION_COUNT);
    tx.ironwood_actions
        .iter()
        .map(|action| {
            let action = CompactAction::try_from(action)
                .expect("generated Ironwood compact action is valid");
            (IronwoodDomain::for_compact_action(&action), action)
        })
        .collect()
}

fn trial_decrypt(ivks: &[PreparedIncomingViewingKey], outputs: &[CompactOutput]) -> usize {
    batch::try_compact_note_decryption(ivks, outputs)
        .into_iter()
        .filter(Option::is_some)
        .count()
}

fn validate_fixture(
    intended_recipient: &PreparedIncomingViewingKey,
    foreground_ivks: &[PreparedIncomingViewingKey],
    background_ivks: &[PreparedIncomingViewingKey],
    outputs: &[CompactOutput],
) {
    let intended_results =
        batch::try_compact_note_decryption(std::slice::from_ref(intended_recipient), outputs);
    assert_eq!(intended_results.len(), ACTION_COUNT);
    assert!(intended_results
        .iter()
        .all(|result| result.as_ref().map(|(_, index)| *index) == Some(0)));

    assert_eq!(trial_decrypt(foreground_ivks, outputs), 0);
    assert_eq!(trial_decrypt(background_ivks, outputs), 0);
}

fn benchmark_ironwood_trial_decryption(c: &mut Criterion) {
    let recipient = account(RECIPIENT_SEED_TAG);
    let outputs = unrelated_outputs(&recipient);
    let intended_recipient = external_ivk(&recipient);

    // Foreground sync prioritizes the active account and uses one scope. The
    // common unrelated-action case therefore performs one trial per action.
    let foreground_ivks = [external_ivk(&account(ACTIVE_ACCOUNT_SEED_TAG))];

    // Background sync handles the remaining accounts after the active account
    // result is available. Each key belongs to a distinct account and uses one
    // scope, so this measures account scaling without doubling every account
    // into external and internal keys.
    let background_ivks: Vec<_> = BACKGROUND_ACCOUNT_SEED_TAGS
        .iter()
        .map(|seed_tag| external_ivk(&account(*seed_tag)))
        .collect();

    validate_fixture(
        &intended_recipient,
        &foreground_ivks,
        &background_ivks,
        &outputs,
    );

    let mut foreground = c.benchmark_group("ironwood_unrelated_trial_decryption/foreground");
    foreground.throughput(Throughput::Elements(ACTION_COUNT as u64));
    foreground.bench_function("active_account_1_ivk_x_100_actions", |bencher| {
        bencher.iter(|| {
            black_box(trial_decrypt(
                black_box(&foreground_ivks),
                black_box(&outputs),
            ))
        });
    });
    foreground.finish();

    let mut background = c.benchmark_group("ironwood_unrelated_trial_decryption/background");
    for account_count in BACKGROUND_ACCOUNT_COUNTS {
        let ivks = &background_ivks[..account_count];
        // Criterion's element throughput is the number of (IVK, action)
        // trial pairs. All pairs are evaluated before note plaintext checks.
        background.throughput(Throughput::Elements((account_count * ACTION_COUNT) as u64));
        background.bench_with_input(
            BenchmarkId::new("other_accounts_x_100_actions", account_count),
            ivks,
            |bencher, ivks| {
                bencher.iter(|| black_box(trial_decrypt(black_box(ivks), black_box(&outputs))));
            },
        );
    }
    background.finish();
}

criterion_group! {
    name = benches;
    config = Criterion::default()
        .sample_size(30)
        .warm_up_time(core::time::Duration::from_secs(2))
        .measurement_time(core::time::Duration::from_secs(5));
    targets = benchmark_ironwood_trial_decryption
}
criterion_main!(benches);
