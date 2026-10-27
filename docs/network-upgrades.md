# Network upgrades

A transaction commits to the consensus branch at its target height. One signed
before an upgrade can only be mined before it activates; from the activation
block the network rejects it. Vizor's rules for the blocks around an upgrade
follow from that, and they apply to any upgrade Common schedules. NU7 also
changes the block spacing, which only NU7 code handles.

## Where the rules live

`rust/src/wallet/network_upgrade.rs` holds the rules that do not read the
wallet:

- `BROADCAST_HOLD_BLOCKS` (10) and `TX_EXPIRING_SOON_BLOCKS` (3).
- `next_activation_after`, `crosses` and `cap_expiry_at_branch_end`, all
  derived from `BranchId::height_bounds`.
- `holds_transaction` and `ensure_migration_can_start` for migrations.
- `hold_heights`, the tips from which migrations and transactions are refused
  before the next upgrade.
- `START_HOLD_MESSAGE` and `SEND_HOLD_MESSAGE`.

Dart reads these rules rather than restating them:

- `get_network_upgrade_window` exposes `hold_heights`.
  `networkUpgradeWindowProvider` applies it to the wallet's tip so swaps and
  Gift Cards stop before side effects Rust cannot undo.
- `networkUpgradeHoldMessage` in `lib/src/core/zcash/network_upgrade_hold.dart`
  turns the Rust message into user copy.
- `upgrade_hold_heights_match_the_send_and_migration_refusals` checks
  `hold_heights` against the refusals tip by tip.

## What happens at each tip

`A` is the activation height. Tips are the chain tip the wallet has seen.

| Tip | Effect |
| --- | --- |
| up to `A − 12` | Normal. |
| `A − 11` to `A − 2` | Migration parts and preparation stages are not broadcast. New Private and Immediate migrations and Keystone prepares are refused. |
| `A − 4` to `A − 2` | Sends, send-max, shielding, swap deposits and Gift Cards are also refused: their expiry, capped at `A − 1`, is too close for nodes to accept. Swaps that send ZEC and Gift Card creation stop before they start. |
| `A − 1` | New transactions target the new branch and are accepted again. Old-branch migration parts stay held: a node that missed the upgrade stops here and would still accept them. |
| once `A − 1` is scanned | Runs whose transactions are still unmined on the old branch end as `stopped_by_upgrade`. |

## Sends

Send expiry follows Common's `default_tx_expiry_delta`: 40 blocks before NU7,
120 from it. `send_expiry_height_for_target` caps it at the last block of the
target's branch.

`ensure_send_outside_upgrade_edge` refuses a proposal or execution whose capped
expiry falls inside the expiring-soon window. Without it the wallet would store
a transaction that nodes refuse, and tell the user it keeps retrying. A
proposal reviewed before the window and sent inside it gets the same refusal
rather than a generic expiry error.

Shielding takes its expiry and this check from the live target. It is refused
when the live tip has already passed the proposal's branch, which happens when
the wallet trails the tip by a block at activation.

Rust refuses a hardware PCZT the same way before the device is asked to sign.
Device approval, and the authority and wallet waits before submission, can
outlast the margin. `pczt_broadcast_expiry_error` checks again after signing
and once more against a freshly read tip as the first request leaves. A capped expiry inside the
expiring-soon window returns the refusal; from `A − 1` the transaction is
plainly expired and the payment can be rebuilt on the new branch.
`networkUpgradeHoldMessage` maps the refusal to one copy on the send,
shielding, swap, Pay and Gift Card screens, including signing screens that
receive it as an `expired` result.

## Swaps and Gift Cards

Both have side effects before Rust builds the transaction, so they check
`networkUpgradeWindowProvider` first:

- A swap that sends ZEC stops before the swap provider starts it. Its fee
  preflight does not apply the refusal, so the swap would otherwise wait for a
  deposit Rust then refuses.
- Gift Card creation, single and batch, stops before funding starts.

A refusal that still comes from Rust, because the tip moved after the check,
shows the same copy. Rust raises it before building the funding transaction,
so a Gift Card whose submission marker was already written is not locked as
possibly sent, and a held claim stays ready to claim.

## Migrations

**Unmined transactions.** The hold and the stop both look at a run's
transactions that are not mined yet:

- scheduled, `needs_resign` and broadcast parts;
- signed children not yet promoted to parts;
- stages awaiting inputs or broadcast;
- parts a later Keystone batch will sign for the run's schedule origin.

**Hold.** `network_upgrade_holds_broadcasts` keeps parts and stages unsent
from `A − 11`. Parts and stages are judged at the later of the wallet's tip
and the server's, since a desktop that wakes near the upgrade can broadcast
before sync catches up, and wait while the server's tip cannot be read; starts
read the wallet's tip. While a run is held, the
foreground does not mark its parts for new signatures, so a wallet catching
up after activation leaves them for the stop.

**Stop.** `stopped_by_upgrade` is terminal. A run stops at either of two
points:

- when a broadcast is rejected after activation
  (`stop_run_if_network_upgrade_invalidated`);
- after a sync whose fully scanned height reaches `A − 1`
  (`network_upgrade_stops_run`). Waiting for that scan lets parts mined before
  the upgrade confirm first, so the receipt reports them as moved.

Stopping releases the run's note locks. Migration status keeps the run as a
receipt while Orchard funds remain, so the rest can move in a new run under
the new branch.

**Start.** Software starts, Keystone prepares, draft creation and Immediate
builds call `ensure_migration_can_start`. A new run also refuses a schedule
drawn before the upgrade (`ensure_schedule_drawn_for_height`): a plan reviewed
before NU7 and started after it would pass its delays in a third of the time.
A schedule drawn in the running app is judged by the spacing it was drawn at,
one from before a restart by its offsets. A saved draft resumed after the upgrade takes the schedule approved then. A
wallet without a scanned tip is not held: it has no target yet. An Immediate
migration checks again just before broadcasting, at the later of the wallet's
and the server's tip: the build reads only the wallet's tip, and hardware
signing can outlast it.

**ZIP 318 durations.** ZIP 318 states delays, the anchor bucket interval and
the expiry modulus in 75-second reference blocks. From NU7 each one spans three
blocks:

- The expiry modulus becomes 103,680 and anchor boundaries fall every 432
  blocks. Vizor takes these from Common's `zip318` helpers.
- `schedule_delays_in_blocks` reports schedule gaps in blocks at the wallet's
  next height.

A schedule drawn before activation keeps one block per reference block. Its
parts past activation are held and stopped, so ZIP 318's rule to sign them
for both branches is not implemented.

## NU7 block spacing

Block spacing drops from 75 to 25 seconds at NU7. Every estimate splits each
span at activation:

- `block_times.rs` for birthday and date conversion. The mainnet table updater
  accepts 25-second averages, so it keeps running after activation.
- `BlockSpacing` and `blockSpacingProvider` in Dart for wait-time text. They
  read `get_block_spacing_schedule`, which takes the 25-second value from
  Common's spacing ratio.

If the schedule cannot be read, Dart falls back to 75-second spacing, which
only affects estimates.

## NU7 announcement

Home shows the NU7 announcement once per network after the tip reaches
activation. From then on the Ironwood announcement no longer shows. Wallets
with no account born before activation skip it.

## When the next upgrade is scheduled

The hold, stop, expiry cap and copy follow from Common's activation heights
and need no change. Check the rest:

- **Block spacing or ZIP 318 parameters.** If they change again, update
  `block_times.rs` and Dart `BlockSpacing`.
- **Hardware signing.** Check
  `orchard_circuit_version_for_consensus_branch` in `pczt.rs`: it keys on the
  branch's Orchard protocol revision. Also check whether Keystone and Ledger
  firmware accept the new branch. Ledger apps before 3.10.0 reject NU7, so
  the serializer refuses an NU7 PCZT unless `LedgerAppSupport.nu7_branch`
  says the connected app accepts it; a new branch needs its own flag and
  minimum version in `ledger_capability.dart`.
- **Announcement.** `nu7AnnouncementProvider` keys on NU7; a new upgrade
  needs its own copy and seen key.
