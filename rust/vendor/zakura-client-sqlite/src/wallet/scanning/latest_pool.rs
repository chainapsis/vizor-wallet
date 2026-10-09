//! Scan ordering for the most recently activated shielded pool.
//!
//! A wallet recovering from a birthday below the latest pool's activation height is handed the
//! `Historic` coverage above that height first, labelled [`ScanPriority::LatestPoolActivation`].
//! The label is derived when ranges are read and never persisted; see
//! [`derive_latest_pool_activation`].

use zcash_client_backend::data_api::scanning::{ScanPriority, ScanRange};
use zcash_protocol::consensus::{self, BlockHeight};

use crate::error::SqliteClientError;

use super::super::scanning;
use ScanPriority::*;

/// The activation height of the most recently activated shielded pool, or `None` if this
/// wallet has no reason to prioritise the blocks above it.
///
/// Without the `orchard` feature the wallet has no Ironwood viewing keys and no Ironwood
/// commitment tree, so it cannot detect Ironwood notes at all. No value is then concentrated
/// above the activation height from its point of view, and recovery order is left alone.
fn latest_pool_activation<P: consensus::Parameters>(params: &P) -> Option<BlockHeight> {
    #[cfg(feature = "orchard")]
    {
        params.activation_height(consensus::NetworkUpgrade::Nu6_3)
    }
    #[cfg(not(feature = "orchard"))]
    {
        let _ = params;
        None
    }
}

/// Returns the scan queue's ranges at or above [`ScanPriority::Historic`] in descending
/// priority order.
///
/// When [`latest_pool_activation`] is `Some` and the queue still holds `Historic` coverage
/// below it, the `Historic` coverage at or above it is reported as
/// [`ScanPriority::LatestPoolActivation`] so that the caller scans the newest pool's history
/// first. See [`derive_latest_pool_activation`] for why this is derived here rather than
/// stored.
pub(crate) fn suggest_scan_ranges<P: consensus::Parameters>(
    conn: &rusqlite::Connection,
    params: &P,
) -> Result<Vec<ScanRange>, SqliteClientError> {
    let ranges = scanning::suggest_scan_ranges(conn, Historic)?;
    Ok(derive_latest_pool_activation(
        ranges,
        latest_pool_activation(params),
    ))
}

/// Reports the `Historic` coverage at or above `activation` as
/// [`ScanPriority::LatestPoolActivation`], re-sorting the result into descending priority
/// order.
///
/// This is a read-time relabelling: nothing is written back to `scan_queue`. Persisting the
/// priority instead would mean writing a code that older releases reject as database
/// corruption, and would require splicing ranges over the queue on every chain-tip update --
/// which risks raising the `Ignored` rows that `prune_scan_queue_below` writes to record
/// coverage the store deliberately skips. Deriving avoids both, and needs no bookkeeping to
/// retire itself once the window has been scanned.
fn derive_latest_pool_activation(
    ranges: Vec<ScanRange>,
    activation: Option<BlockHeight>,
) -> Vec<ScanRange> {
    let Some(activation) = activation else {
        return ranges;
    };

    // The policy exists to defer pre-activation history. Once none is left, every `Historic`
    // range is already post-activation and relabelling them would only reorder equals.
    if !ranges
        .iter()
        .any(|r| r.priority() == Historic && r.block_range().start < activation)
    {
        return ranges;
    }

    let promote =
        |r: ScanRange| ScanRange::from_parts(r.block_range().clone(), LatestPoolActivation);

    let mut out = Vec::with_capacity(ranges.len() + 1);
    for range in ranges {
        if range.priority() != Historic {
            out.push(range);
            continue;
        }
        match (
            range.truncate_end(activation),
            range.truncate_start(activation),
        ) {
            // Crosses the activation height: the older part stays `Historic`.
            (Some(below), Some(above)) => {
                out.push(below);
                out.push(promote(above));
            }
            // Entirely at or above it.
            (None, Some(above)) => out.push(promote(above)),
            // Entirely below it, or empty.
            _ => out.push(range),
        }
    }

    out.sort_by(|a, b| {
        b.priority()
            .cmp(&a.priority())
            .then_with(|| b.block_range().end.cmp(&a.block_range().end))
    });

    out
}

#[cfg(test)]
mod tests {
    use nonempty::NonEmpty;
    use rusqlite::Connection;

    use zcash_client_backend::data_api::{
        WalletRead, WalletWrite,
        scanning::{ScanPriority, ScanRange, spanning_tree::testing::scan_range},
        testing::{TestBuilder, TestState},
    };
    use zcash_primitives::block::BlockHash;
    use zcash_protocol::{consensus::BlockHeight, local_consensus::LocalNetwork};

    use crate::{
        error::SqliteClientError,
        testing::db::{TestDb, TestDbFactory},
        wallet::scanning::{self, insert_queue_entries, parse_priority_code, priority_code},
    };

    use super::derive_latest_pool_activation;
    use ScanPriority::*;

    /// Sapling activates at 100_000 on `DEFAULT_NETWORK`; NU6.3 is placed well above it so an
    /// account created at Sapling activation has a birthday below the Ironwood pool.
    const NU6_3_ACTIVATION: u32 = 300_000;

    /// The earlier NU6 upgrades activate strictly below NU6.3, so a test that asserts where the
    /// promotion boundary falls pins it to NU6.3 specifically rather than to whichever recent
    /// upgrade happens to be consulted.
    const PRIOR_NU6_ACTIVATION: u32 = 200_000;

    fn nu6_3_active_network() -> LocalNetwork {
        let prior = Some(BlockHeight::from_u32(PRIOR_NU6_ACTIVATION));
        LocalNetwork {
            nu6: prior,
            nu6_1: prior,
            nu6_2: prior,
            nu6_3: Some(BlockHeight::from_u32(NU6_3_ACTIVATION)),
            ..TestBuilder::<(), ()>::DEFAULT_NETWORK
        }
    }

    /// A wallet on an NU6.3-active network whose single account was born at Sapling
    /// activation, i.e. well below the Ironwood pool.
    fn pre_nu6_3_birthday_wallet() -> TestState<(), TestDb, LocalNetwork> {
        TestBuilder::new()
            .with_data_store_factory(TestDbFactory::default())
            .with_network(nu6_3_active_network())
            .with_account_from_sapling_activation(BlockHash([0; 32]))
            .build()
    }

    /// The codes persisted in `scan_queue` must stay in the same order as the enum, because
    /// every query that reasons about priority compares the stored integers rather than
    /// parsing them (for example `v_*_shard_unscanned_ranges`, which filters
    /// `priority > Scanned`).
    ///
    /// `LatestPoolActivation` is never written by this crate, but it keeps a code so that a
    /// row carrying one -- from a bug, or a future release that does persist it -- parses
    /// rather than being reported as database corruption.
    #[test]
    fn priority_code_round_trips_in_enum_order() {
        let all = [
            Ignored,
            Scanned,
            Historic,
            LatestPoolActivation,
            OpenAdjacent,
            FoundNote,
            ChainTip,
            Verify,
        ];

        assert_eq!(
            all.iter().map(priority_code).collect::<Vec<_>>(),
            vec![0, 10, 20, 25, 30, 40, 50, 60],
        );

        for priority in all {
            assert_eq!(
                parse_priority_code(priority_code(&priority)),
                Some(priority)
            );
        }

        for pair in all.windows(2) {
            assert!(
                pair[0] < pair[1],
                "{:?} must order below {:?}",
                pair[0],
                pair[1],
            );
        }
    }

    /// `LatestPoolActivation` outranks `Historic` so the Ironwood era is suggested first, but
    /// stays below `FoundNote` so witness-completion work still preempts it.
    #[test]
    fn latest_pool_activation_orders_between_historic_and_open_adjacent() {
        assert!(Historic < LatestPoolActivation);
        assert!(LatestPoolActivation < OpenAdjacent);
        assert!(LatestPoolActivation < FoundNote);
        assert!(LatestPoolActivation < ChainTip);
    }

    /// Reads the queue at or above `min_priority` and applies the relabelling, as
    /// [`super::suggest_scan_ranges`] does at `Historic`.
    fn suggest(
        conn: &Connection,
        min_priority: ScanPriority,
        activation: Option<BlockHeight>,
    ) -> Result<Vec<ScanRange>, SqliteClientError> {
        scanning::suggest_scan_ranges(conn, min_priority)
            .map(|ranges| derive_latest_pool_activation(ranges, activation))
    }

    /// Seeds `scan_queue` directly and reads it back through `suggest`, so that `Ignored` and
    /// `Scanned` coverage is visible alongside the relabelled ranges.
    fn suggested(entries: &[ScanRange], activation: Option<u32>) -> Vec<(ScanPriority, u32, u32)> {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(crate::wallet::db::TABLE_SCAN_QUEUE)
            .unwrap();
        insert_queue_entries(&conn, entries.iter()).unwrap();

        suggest(&conn, Ignored, activation.map(BlockHeight::from_u32))
            .unwrap()
            .into_iter()
            .map(|r| {
                (
                    r.priority(),
                    u32::from(r.block_range().start),
                    u32::from(r.block_range().end),
                )
            })
            .collect()
    }

    /// The motivating case: post-activation history is handed out before the older backfill,
    /// and a range crossing the activation height is split exactly at it.
    #[test]
    fn suggest_scan_ranges_prioritizes_post_activation_history() {
        assert_eq!(
            suggested(
                &[scan_range(100_000..400_001, ScanPriority::Historic)],
                Some(NU6_3_ACTIVATION),
            ),
            vec![
                (LatestPoolActivation, NU6_3_ACTIVATION, 400_001),
                (Historic, 100_000, NU6_3_ACTIVATION),
            ],
        );
    }

    /// Only `Historic` coverage is relabelled. In particular `Ignored` -- which
    /// `prune_scan_queue_below` writes to record coverage the store deliberately skips -- and
    /// `Scanned` must pass through untouched, and higher priorities keep precedence.
    #[test]
    fn suggest_scan_ranges_relabels_only_historic_coverage() {
        assert_eq!(
            suggested(
                &[
                    scan_range(100_000..310_000, ScanPriority::Historic), // crosses: split
                    scan_range(310_000..340_000, ScanPriority::Ignored),  // untouched
                    scan_range(340_000..360_000, ScanPriority::Scanned),  // untouched
                    scan_range(360_000..380_000, ScanPriority::FoundNote), // untouched
                    scan_range(380_000..400_001, ScanPriority::Historic), // wholly promoted
                ],
                Some(NU6_3_ACTIVATION),
            ),
            vec![
                (FoundNote, 360_000, 380_000),
                (LatestPoolActivation, 380_000, 400_001),
                (LatestPoolActivation, NU6_3_ACTIVATION, 310_000),
                (Historic, 100_000, NU6_3_ACTIVATION),
                (Scanned, 340_000, 360_000),
                (Ignored, 310_000, 340_000),
            ],
        );
    }

    /// `Verify` must stay first: the sync loop's continuity check depends on it preceding
    /// every other range.
    #[test]
    fn verify_still_precedes_latest_pool_activation() {
        let suggestions = suggested(
            &[
                scan_range(100_000..350_000, ScanPriority::Historic),
                scan_range(350_000..350_010, ScanPriority::Verify),
                scan_range(350_010..400_001, ScanPriority::Historic),
            ],
            Some(NU6_3_ACTIVATION),
        );
        assert_eq!(suggestions.first().map(|(p, _, _)| *p), Some(Verify));
    }

    /// Once the post-activation window has been scanned, the remaining pre-activation history
    /// is the highest-priority work left, so the backfill proceeds rather than stalling.
    #[test]
    fn pre_activation_backfill_resumes_once_the_window_is_scanned() {
        assert_eq!(
            suggested(
                &[
                    scan_range(100_000..NU6_3_ACTIVATION, ScanPriority::Historic),
                    scan_range(NU6_3_ACTIVATION..400_001, ScanPriority::Scanned),
                ],
                Some(NU6_3_ACTIVATION),
            ),
            vec![
                (Historic, 100_000, NU6_3_ACTIVATION),
                (Scanned, NU6_3_ACTIVATION, 400_001),
            ],
        );
    }

    /// With no pre-activation history left to defer, post-activation `Historic` coverage is
    /// reported as-is: relabelling it would only reorder ranges that are already equals.
    #[test]
    fn no_relabelling_without_pre_activation_history() {
        assert_eq!(
            suggested(
                &[scan_range(
                    NU6_3_ACTIVATION..400_001,
                    ScanPriority::Historic
                )],
                Some(NU6_3_ACTIVATION),
            ),
            vec![(Historic, NU6_3_ACTIVATION, 400_001)],
        );
    }

    /// A network with no assigned activation height (and any build without the `orchard`
    /// feature, via `latest_pool_activation`) keeps the previous behaviour exactly.
    #[test]
    fn no_relabelling_without_an_activation_height() {
        let entries = [
            scan_range(100_000..350_000, ScanPriority::Historic),
            scan_range(350_000..400_001, ScanPriority::Historic),
        ];
        assert_eq!(
            suggested(&entries, None),
            vec![(Historic, 350_000, 400_001), (Historic, 100_000, 350_000),],
        );
    }

    /// Newly queued post-activation work preempts an in-progress pre-activation backfill on
    /// the very next suggestion, which is what lets `sync.rs` abort its current pass.
    #[test]
    fn new_post_activation_work_preempts_an_in_progress_backfill() {
        let suggestions = suggested(
            &[
                scan_range(100_000..200_000, ScanPriority::Historic),
                scan_range(200_000..NU6_3_ACTIVATION, ScanPriority::Scanned),
                scan_range(NU6_3_ACTIVATION..400_001, ScanPriority::Historic),
            ],
            Some(NU6_3_ACTIVATION),
        );
        assert_eq!(
            suggestions.first(),
            Some(&(LatestPoolActivation, NU6_3_ACTIVATION, 400_001)),
        );
    }

    /// Reading suggestions must never write to `scan_queue`: the whole point of deriving the
    /// priority is that no release-incompatible code reaches the database.
    #[test]
    fn suggest_scan_ranges_does_not_mutate_the_queue() {
        let mut st = pre_nu6_3_birthday_wallet();
        st.wallet_mut()
            .update_chain_tip(BlockHeight::from_u32(400_000))
            .unwrap();

        let before = queue_contents(&st);
        let suggestions = suggest(
            st.wallet().conn(),
            Historic,
            Some(BlockHeight::from_u32(NU6_3_ACTIVATION)),
        )
        .unwrap();

        assert_eq!(queue_contents(&st), before);
        assert!(
            !queue_contents(&st)
                .iter()
                .any(|(_, _, code)| *code == priority_code(&LatestPoolActivation)),
            "priority 25 must never be persisted: {:?}",
            queue_contents(&st),
        );
        // ...even though the derived suggestion does use it.
        assert_eq!(
            suggestions.first().map(|r| r.priority()),
            Some(LatestPoolActivation),
        );
    }

    /// The public rescan API accepts every `ScanPriority`, but the activation priority is a
    /// read-time label only. Normalize it at the storage boundary so that releases whose parser
    /// only accepts the pre-existing codes can still read the wallet after a downgrade.
    #[test]
    fn queue_rescans_does_not_persist_latest_pool_activation() {
        let mut st = pre_nu6_3_birthday_wallet();
        st.wallet_mut()
            .update_chain_tip(BlockHeight::from_u32(400_000))
            .unwrap();

        let rescan_start = BlockHeight::from_u32(310_000);
        let rescan_end = BlockHeight::from_u32(320_000);
        st.wallet_mut()
            .db_mut()
            .queue_rescans(
                NonEmpty {
                    head: rescan_start..rescan_end,
                    tail: vec![],
                },
                LatestPoolActivation,
            )
            .unwrap();

        let contents = queue_contents(&st);
        assert!(
            contents.iter().any(|&(start, end, code)| {
                start == u32::from(rescan_start)
                    && end == u32::from(rescan_end)
                    && code == priority_code(&Historic)
            }),
            "the derived priority should be stored as Historic: {contents:?}",
        );
        assert!(
            contents
                .iter()
                .all(|&(_, _, code)| [0, 10, 20, 30, 40, 50, 60].contains(&code)),
            "the queue contains a priority code rejected by the previous release: {contents:?}",
        );
    }

    /// Exercises the production wiring: `WalletRead::suggest_scan_ranges` must reach
    /// `latest_pool_activation`, which must consult NU6.3 specifically. Every other test here
    /// injects the activation height by hand, so without this one the whole feature could be
    /// dead -- or anchored to the wrong network upgrade -- in every shipped build.
    ///
    /// The boundary assertion is what pins the upgrade: the earlier NU6 upgrades activate at
    /// `PRIOR_NU6_ACTIVATION`, so consulting any of them would split the range there instead.
    #[cfg(feature = "orchard")]
    #[test]
    fn wallet_read_suggest_scan_ranges_derives_from_the_nu6_3_activation_height() {
        let mut st = pre_nu6_3_birthday_wallet();
        let birthday = u32::from(st.wallet().get_wallet_birthday().unwrap().unwrap());
        assert!(birthday < PRIOR_NU6_ACTIVATION);

        st.wallet_mut()
            .update_chain_tip(BlockHeight::from_u32(400_000))
            .unwrap();

        let suggestions = st
            .wallet()
            .suggest_scan_ranges()
            .unwrap()
            .into_iter()
            .map(|r| {
                (
                    r.priority(),
                    u32::from(r.block_range().start),
                    u32::from(r.block_range().end),
                )
            })
            .collect::<Vec<_>>();

        assert_eq!(
            suggestions,
            vec![
                (LatestPoolActivation, NU6_3_ACTIVATION, 400_001),
                (Historic, birthday, NU6_3_ACTIVATION),
            ],
        );
    }

    /// The counterpart: without the `orchard` feature the wallet cannot detect Ironwood notes,
    /// so `latest_pool_activation` yields `None` and the production query is unchanged.
    #[cfg(not(feature = "orchard"))]
    #[test]
    fn wallet_read_suggest_scan_ranges_does_not_derive_without_orchard() {
        let mut st = pre_nu6_3_birthday_wallet();
        let birthday = u32::from(st.wallet().get_wallet_birthday().unwrap().unwrap());

        st.wallet_mut()
            .update_chain_tip(BlockHeight::from_u32(400_000))
            .unwrap();

        assert_eq!(
            st.wallet()
                .suggest_scan_ranges()
                .unwrap()
                .into_iter()
                .map(|r| (
                    r.priority(),
                    u32::from(r.block_range().start),
                    u32::from(r.block_range().end)
                ))
                .collect::<Vec<_>>(),
            vec![(Historic, birthday, 400_001)],
        );
    }

    /// End-to-end: a wallet recovering from a birthday below NU6.3 is handed the Ironwood era
    /// before its older history, without `update_chain_tip` having touched the queue's
    /// priorities.
    #[test]
    fn pre_nu6_3_birthday_wallet_scans_the_ironwood_era_first() {
        let mut st = pre_nu6_3_birthday_wallet();
        let birthday = u32::from(st.wallet().get_wallet_birthday().unwrap().unwrap());
        assert!(birthday < NU6_3_ACTIVATION);

        st.wallet_mut()
            .update_chain_tip(BlockHeight::from_u32(400_000))
            .unwrap();

        // The queue itself is exactly what it was before this feature existed.
        assert_eq!(
            queue_contents(&st),
            vec![(birthday, 400_001, priority_code(&Historic))],
        );
        assert_queue_contiguous(&st);

        // The scheduling appears only in the suggestion.
        assert_eq!(
            suggest(
                st.wallet().conn(),
                Historic,
                Some(BlockHeight::from_u32(NU6_3_ACTIVATION)),
            )
            .unwrap()
            .into_iter()
            .map(|r| (
                r.priority(),
                u32::from(r.block_range().start),
                u32::from(r.block_range().end)
            ))
            .collect::<Vec<_>>(),
            vec![
                (LatestPoolActivation, NU6_3_ACTIVATION, 400_001),
                (Historic, birthday, NU6_3_ACTIVATION),
            ],
        );
    }

    fn queue_contents(st: &TestState<(), TestDb, LocalNetwork>) -> Vec<(u32, u32, i64)> {
        let mut stmt = st
            .wallet()
            .conn()
            .prepare(
                "SELECT block_range_start, block_range_end, priority FROM scan_queue
                 ORDER BY block_range_start",
            )
            .unwrap();

        stmt.query_map([], |r| {
            Ok((
                r.get::<_, u32>(0)?,
                r.get::<_, u32>(1)?,
                r.get::<_, i64>(2)?,
            ))
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
    }

    fn assert_queue_contiguous(st: &TestState<(), TestDb, LocalNetwork>) {
        let entries = queue_contents(st);
        for pair in entries.windows(2) {
            assert_eq!(
                pair[0].1, pair[1].0,
                "gap in scan queue between {:?} and {:?}",
                pair[0], pair[1]
            );
        }
    }
}
