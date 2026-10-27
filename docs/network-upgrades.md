# Network upgrades

A transaction commits to the consensus branch at its target height. One signed
before an upgrade can only be mined before it activates; from the activation
block the network rejects it. Vizor's rules for the blocks around an upgrade
follow from that, and they apply to any upgrade Common schedules. NU7 also
changes the block spacing, which only NU7 code handles.

## Where the rules live

`rust/src/wallet/network_upgrade.rs` holds the rules that do not read the
wallet:

- `TX_EXPIRING_SOON_BLOCKS` (3).
- `next_activation_after`, `crosses` and `cap_expiry_at_branch_end`, all
  derived from `BranchId::height_bounds`.
- `hold_heights`, the tip from which sends are refused before the next
  upgrade.
- `SEND_HOLD_MESSAGE`.

Dart reads these rules rather than restating them:

- `get_network_upgrade_window` exposes `hold_heights`.
  `networkUpgradeWindowProvider` applies it to the wallet's tip so swaps and
  Gift Cards stop before side effects Rust cannot undo.
- `networkUpgradeHoldMessage` in `lib/src/core/zcash/network_upgrade_hold.dart`
  turns the Rust message into user copy.
- `upgrade_hold_heights_match_the_send_refusal` checks `hold_heights` against
  the send refusal tip by tip.

## What happens at each tip

`A` is the activation height. Tips are the chain tip the wallet has seen.

| Tip | Effect |
| --- | --- |
| up to `A − 5` | Normal. |
| `A − 4` to `A − 2` | Sends, send-max, shielding, swap deposits and Gift Cards are refused: their expiry, capped at `A − 1`, is too close for nodes to accept. Swaps that send ZEC and Gift Card creation stop before they start. |
| `A − 1` | New transactions target the new branch and are accepted again. |

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
activation, after any Ironwood announcement. Wallets whose accounts all began
after activation skip it.

## When the next upgrade is scheduled

The expiry cap, the send refusal and their copy follow from Common's activation
heights and need no change. Check the rest:

- **Block spacing.** If it changes again, update `block_times.rs` and Dart
  `BlockSpacing`.
- **Hardware signing.** Check
  `orchard_circuit_version_for_consensus_branch` in `pczt.rs`: it keys on the
  branch's Orchard protocol revision. Also check whether Keystone and Ledger
  firmware accept the new branch.
- **Announcement.** `nu7AnnouncementProvider` keys on NU7; a new upgrade
  needs its own copy and seen key.
