# Desktop onboarding design improvements

## Scope

Independent follow-up based on `main` at
`4bff2e7c64ce8f87404f3e0c5b5d80db1201a5e5`.
This preserves the reviewed desktop design work from #794, #795, and #797
while the onboarding umbrella prioritizes mobile delivery.

- Welcome video/poster assets, loop crossfade, gradient overlay, and button effects.
- Import method and hardware wallet selectors, including Back/Cancel destinations
  for first-wallet setup and additional accounts.
- Introduction text wrapping, heading weight, and sidebar spacing.
- The testnet import summary advertises Keystone only, matching the existing
  Ledger mainnet capability gate. Ledger support policy is unchanged.
- Deterministic captures and focused routing, interaction, and playback tests.

Shared button/video components and their pinned dependencies are included so
this branch compiles without depending on the mobile umbrella. Mobile screen
implementations, assets, routing, and progress are unchanged from this base.

## Deferred behavior

Gift activation stays disabled with a TODO and appears only on the initial
walletless Welcome. Gift Claim/Home and mobile progress are outside this PR.
Desktop Link Vizor Desktop and placeholder legal links remain excluded.

Keep this PR draft while mobile work proceeds. Do not merge into or modify
local or remote `main` as part of preparing the draft.
