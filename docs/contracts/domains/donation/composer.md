# Donation composer

Read when changing Support Vizor availability, amount entry, or Review preparation.

Donation is the desktop **Support Vizor** domain at `/donation`. It sends to the
fixed public mainnet `kVizorDonationAddress` from `donation_config.dart`, with no
recipient or memo editor. Keep that address aligned with the README. Settings
enables entry only for mainnet; the route redirects non-desktop or non-mainnet
requests to `/settings`.

Donation uses shared transaction operations with `SendFlowKind.donation`; it
does not define a separate transaction pipeline.

[`DonationScreen`](../../../../lib/src/features/donation/screens/donation_screen.dart)
owns the amount text, unit mode, preset selection, and validation sequence.

- ZEC is the initial mode. USD mode uses the live ZEC price and shared Send
  conversion helpers; entering USD mode requires an available price. Continue
  captures the currently converted zatoshi amount, not a fiat amount to convert
  again at broadcast. Input allows eight decimal places in ZEC and two in USD.
- Validation uses balances scoped to the active account. During Ironwood resume
  it uses `displayIronwoodBalance`; otherwise it uses `displaySpendableBalance`.
  Account, relevant balance/freshness, and migration-mode changes revalidate;
  live-price changes also revalidate an amount entered in USD.
- Typing debounces validation by 300 ms; preset selection validates immediately.
  Advancing the validation sequence invalidates older fee results, including
  after dependency changes. An unmounted screen cannot publish their errors.
- Fee estimation targets the fixed recipient with no memo. It skips a completed
  spendable snapshot; otherwise it uses the authoritative-spendable gate.
  Insufficient amount-plus-fee blocks Continue. Other estimation errors are
  non-blocking, leaving proposal creation to establish whether the send can run.
- Continue requires a positive amount within the displayed balance, an active
  account, no validation error, and no submission in progress. It captures that
  account and a new `sendFlowId`, creates donation-tagged review args for the
  fixed unified address, and pushes `/send/review`. If it obtains a proposal but
  cannot hand it to Review because the screen was unmounted, it invokes shared
  proposal release rather than leaving the proposal owned by a dead composer.

## Verification

- Network availability and README recipient agreement:
  [`donation_config_test.dart`](../../../../test/features/donation/donation_config_test.dart)
- Balance and USD-price changes revalidate existing input:
  [`donation_screen_test.dart`](../../../../test/features/donation/donation_screen_test.dart)

## Related changes

- When changing proposal creation, read [proposal ownership](../../references/transactions/proposal-ownership.md).
- When changing failed Review handoff cleanup, read [proposal release](../../references/transactions/proposal-release.md).
