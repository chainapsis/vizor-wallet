pub(crate) const ZATOSHIS_PER_ZEC: u64 = 100_000_000;
pub(crate) const ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI: u64 = ZATOSHIS_PER_ZEC / 100;
pub(crate) const ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI: u64 = 10_000 * ZATOSHIS_PER_ZEC;
pub(crate) const ZIP318_ANCHOR_BUCKET_MODULUS: u32 = 144;
pub(crate) const REGTEST_ANCHOR_BUCKET_MODULUS: u32 = 1;
pub(crate) const ZIP318_ANCHOR_AGE_CAP: u32 = 16;
pub(crate) const ZIP318_EXPIRY_MODULUS: u32 = 34_560;
// Keep the original value readable for runs created before the shorter policy.
pub(crate) const ZIP318_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 144;
pub(crate) const ZIP318_TRANSFER_MAX_DELAY_BLOCKS: u32 = 576;
pub(crate) const NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 72;
pub(crate) const REGTEST_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 1;
pub(crate) const REGTEST_TRANSFER_MAX_DELAY_BLOCKS: u32 = 4;
pub(crate) const FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 12;
pub(crate) const FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS: u32 = 48;
pub(crate) const FAST_TESTNET_ANCHOR_BUCKET_MODULUS: u32 = 12;
pub(crate) const MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI: u64 = 1;
// Mirrors the per-child ZIP-317 migration fee estimate used by send planning:
// 3 logical actions (a 2-action padded Orchard bundle and a 1-action
// unpadded Ironwood bundle).
const MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 15_000;
// Every migration needs at least one 16-action padded Orchard transaction
// before its first Ironwood output can be created.
const DENOMINATION_SPLIT_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 80_000;

static FAST_TESTNET_MIGRATION_ENABLED: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationTimingPolicy {
    Standard,
    Standard90Minutes,
    Standard90MinutesLatestAnchor,
    FastTestnet,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationStrategy {
    Balanced,
    Zip318Canonical,
}

impl MigrationTimingPolicy {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::Standard90Minutes => "standard_90m",
            Self::Standard90MinutesLatestAnchor => "standard_90m_latest_anchor",
            Self::FastTestnet => "fast_testnet",
        }
    }

    fn from_str(value: &str) -> Result<Self, String> {
        match value {
            "standard" => Ok(Self::Standard),
            "standard_90m" => Ok(Self::Standard90Minutes),
            "standard_90m_latest_anchor" => Ok(Self::Standard90MinutesLatestAnchor),
            "fast_testnet" => Ok(Self::FastTestnet),
            _ => Err(format!("Unsupported migration timing policy: {value}")),
        }
    }

}

pub(crate) fn configure_fast_testnet_migration(enabled: bool) {
    FAST_TESTNET_MIGRATION_ENABLED.store(enabled, Ordering::Relaxed);
}

pub(crate) fn configured_timing_policy(network: WalletNetwork) -> MigrationTimingPolicy {
    if matches!(network, WalletNetwork::Test | WalletNetwork::Regtest)
        && FAST_TESTNET_MIGRATION_ENABLED.load(Ordering::Relaxed)
    {
        MigrationTimingPolicy::FastTestnet
    } else if network == WalletNetwork::Regtest {
        MigrationTimingPolicy::Standard
    } else {
        MigrationTimingPolicy::Standard90MinutesLatestAnchor
    }
}

pub(crate) fn timing_policy_for_strategy(
    network: WalletNetwork,
    strategy: MigrationStrategy,
) -> MigrationTimingPolicy {
    let configured = configured_timing_policy(network);
    if configured == MigrationTimingPolicy::FastTestnet || network == WalletNetwork::Regtest {
        return configured;
    }

    match strategy {
        MigrationStrategy::Balanced => MigrationTimingPolicy::Standard90MinutesLatestAnchor,
        MigrationStrategy::Zip318Canonical => MigrationTimingPolicy::Standard,
    }
}

pub(crate) fn schedule_parameters(network: WalletNetwork) -> (u32, u32) {
    schedule_parameters_with_policy(network, configured_timing_policy(network))
}

pub(crate) fn schedule_parameters_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> (u32, u32) {
    match network {
        WalletNetwork::Regtest if timing_policy == MigrationTimingPolicy::FastTestnet => (
            FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Regtest => (
            REGTEST_TRANSFER_MEAN_DELAY_BLOCKS,
            REGTEST_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => (
            FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Main | WalletNetwork::Test
            if matches!(
                timing_policy,
                MigrationTimingPolicy::Standard90Minutes
                    | MigrationTimingPolicy::Standard90MinutesLatestAnchor
            ) =>
        {
            (
                NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
                ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
            )
        }
        WalletNetwork::Main | WalletNetwork::Test => (
            ZIP318_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
        ),
    }
}
