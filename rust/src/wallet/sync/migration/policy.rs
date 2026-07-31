pub(crate) const ZATOSHIS_PER_ZEC: u64 = 100_000_000;
pub(crate) const ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI: u64 = ZATOSHIS_PER_ZEC / 100;
pub(crate) const ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI: u64 = 10_000 * ZATOSHIS_PER_ZEC;
pub(crate) const ZIP318_ANCHOR_BUCKET_MODULUS: u32 = 144;
pub(crate) const REGTEST_ANCHOR_BUCKET_MODULUS: u32 = 1;
pub(crate) const ZIP318_ANCHOR_AGE_CAP: u32 = 4;
pub(crate) const ZIP318_EXPIRY_MODULUS: u32 = 34_560;
// Keep the original value readable for runs created before the shorter policy.
pub(crate) const ZIP318_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 144;
pub(crate) const ZIP318_TRANSFER_MAX_DELAY_BLOCKS: u32 = 576;
pub(crate) const NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 66;
pub(crate) const REGTEST_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 1;
pub(crate) const REGTEST_TRANSFER_MAX_DELAY_BLOCKS: u32 = 4;
pub(crate) const FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 12;
pub(crate) const FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS: u32 = 48;
pub(crate) const FAST_TESTNET_ANCHOR_BUCKET_MODULUS: u32 = 12;
pub(crate) const MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI: u64 = 1;
pub(crate) const DENSE_MIGRATION_PART_THRESHOLD: usize = 10;
// Mirrors the per-child ZIP-317 migration fee estimate used by send planning:
// 3 logical actions (a 2-action padded Orchard bundle and a 1-action
// unpadded Ironwood bundle).
const MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 15_000;
// Every migration needs at least one 16-action padded Orchard transaction
// before its first Ironwood output can be created.
const DENOMINATION_SPLIT_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 80_000;

static FAST_TESTNET_MIGRATION_ENABLED: AtomicBool = AtomicBool::new(false);

/// Persisted migration cadence.
///
/// Dense variants are separate durable values so an app update cannot retime
/// an already-staged native outbox by reinterpreting its part count.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationTimingPolicy {
    Standard,
    StandardDense,
    Standard90Minutes,
    Standard90MinutesDense,
    Standard90MinutesLatestAnchor,
    Standard90MinutesLatestAnchorDense,
    FastTestnet,
    FastTestnetDense,
}

impl MigrationTimingPolicy {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::StandardDense => "standard_dense",
            Self::Standard90Minutes => "standard_90m",
            Self::Standard90MinutesDense => "standard_90m_dense",
            Self::Standard90MinutesLatestAnchor => "standard_90m_latest_anchor",
            Self::Standard90MinutesLatestAnchorDense => "standard_90m_latest_anchor_dense",
            Self::FastTestnet => "fast_testnet",
            Self::FastTestnetDense => "fast_testnet_dense",
        }
    }

    fn from_str(value: &str) -> Result<Self, String> {
        match value {
            "standard" => Ok(Self::Standard),
            "standard_dense" => Ok(Self::StandardDense),
            "standard_90m" => Ok(Self::Standard90Minutes),
            "standard_90m_dense" => Ok(Self::Standard90MinutesDense),
            "standard_90m_latest_anchor" => Ok(Self::Standard90MinutesLatestAnchor),
            "standard_90m_latest_anchor_dense" => Ok(Self::Standard90MinutesLatestAnchorDense),
            "fast_testnet" => Ok(Self::FastTestnet),
            "fast_testnet_dense" => Ok(Self::FastTestnetDense),
            _ => Err(format!("Unsupported migration timing policy: {value}")),
        }
    }

    const fn is_dense(self) -> bool {
        matches!(
            self,
            Self::StandardDense
                | Self::Standard90MinutesDense
                | Self::Standard90MinutesLatestAnchorDense
                | Self::FastTestnetDense
        )
    }

    const fn is_fast_testnet(self) -> bool {
        matches!(self, Self::FastTestnet | Self::FastTestnetDense)
    }

    const fn uses_ninety_minute_mean(self) -> bool {
        matches!(
            self,
            Self::Standard90Minutes
                | Self::Standard90MinutesDense
                | Self::Standard90MinutesLatestAnchor
                | Self::Standard90MinutesLatestAnchorDense
        )
    }

    const fn uses_latest_anchor(self) -> bool {
        matches!(
            self,
            Self::Standard90MinutesLatestAnchor | Self::Standard90MinutesLatestAnchorDense
        )
    }

    const fn with_dense_schedule(self, dense: bool) -> Self {
        match (self, dense) {
            (Self::Standard | Self::StandardDense, false) => Self::Standard,
            (Self::Standard | Self::StandardDense, true) => Self::StandardDense,
            (Self::Standard90Minutes | Self::Standard90MinutesDense, false) => {
                Self::Standard90Minutes
            }
            (Self::Standard90Minutes | Self::Standard90MinutesDense, true) => {
                Self::Standard90MinutesDense
            }
            (
                Self::Standard90MinutesLatestAnchor | Self::Standard90MinutesLatestAnchorDense,
                false,
            ) => Self::Standard90MinutesLatestAnchor,
            (
                Self::Standard90MinutesLatestAnchor | Self::Standard90MinutesLatestAnchorDense,
                true,
            ) => Self::Standard90MinutesLatestAnchorDense,
            (Self::FastTestnet | Self::FastTestnetDense, false) => Self::FastTestnet,
            (Self::FastTestnet | Self::FastTestnetDense, true) => Self::FastTestnetDense,
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
        MigrationTimingPolicy::Standard90Minutes
    }
}

pub(crate) fn schedule_parameters(network: WalletNetwork) -> (u32, u32) {
    schedule_parameters_with_policy(network, configured_timing_policy(network))
}

pub(crate) fn schedule_parameters_for_part_count(
    network: WalletNetwork,
    part_count: usize,
) -> (u32, u32) {
    schedule_parameters_with_policy_for_part_count(
        network,
        configured_timing_policy(network),
        part_count,
    )
}

fn schedule_parameters_with_policy_for_part_count(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    part_count: usize,
) -> (u32, u32) {
    schedule_parameters_with_policy(
        network,
        timing_policy
            .with_dense_schedule(part_count > DENSE_MIGRATION_PART_THRESHOLD),
    )
}

fn schedule_parameters_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> (u32, u32) {
    let (mean_delay_blocks, max_delay_blocks) = match network {
        WalletNetwork::Regtest if timing_policy.is_fast_testnet() => (
            FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Regtest => (
            REGTEST_TRANSFER_MEAN_DELAY_BLOCKS,
            REGTEST_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Test if timing_policy.is_fast_testnet() => (
            FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Main | WalletNetwork::Test if timing_policy.uses_ninety_minute_mean() => {
            (
                NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
                ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
            )
        }
        WalletNetwork::Main | WalletNetwork::Test => (
            ZIP318_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
        ),
    };
    (
        if timing_policy.is_dense() {
            (mean_delay_blocks / 2).max(1)
        } else {
            mean_delay_blocks
        },
        max_delay_blocks,
    )
}
