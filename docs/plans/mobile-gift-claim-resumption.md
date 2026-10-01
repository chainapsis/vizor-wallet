# Mobile gift claim submission and resumption

Based on umbrella PR #793 at `93ec9a412`, after #814 integrated #815. Branch:
`rowan/gift-claim-resumption`. Public Gift onboarding entry remains a later slice.

## Contract

- Finish wallet setup and save the Card with its `setupAccountUuid` first.
- Hand the existing inspection to `PaymentLinkClaimCoordinator.claimSetupCard`.
  Binding re-estimates for that receiving account without another scan. The
  screen can proceed to Face ID/Home; handle the returned future's error using
  the saved Card recovery path rather than retrying account creation.
- Concurrent handoffs and preparation share their work. Submission joins only
  when the Card and receiving account agree. Wallet deletion/reset drains
  preparation, handoff, submission, and retention before deleting account data.
- Confirmation waiting is saved as a ready Card with `checking` availability.
  Restart, unlock, foreground resume, and the existing retry timer can prepare
  it again for the saved account. Account switches do not redirect this claim.
- Automatic setup claim recovery waits until the setup journal and start marker
  are gone. Account metadata restored after unlock wakes otherwise idle recovery.
- Failed, rejected, spent-elsewhere, archived, and terminal empty Cards do not
  automatically submit. Existing **Settings > My gift cards > Received** provides
  inspection and manual retry. A missing receiving account is never replaced
  with the current account.
- Submitted claims use the existing received store and Home Activity index.
  The pending transaction and subsequently detected receipt retain one identity.
  Waiting before submission does not create a transaction row. No Gift banner
  or new recovery screen is added.

## Verification boundary

Focused tests exercise real Dart coordination, record persistence across fresh
containers, account pinning, journal gating, destructive-operation drain, and
the production Activity index. Service tests use mocked Rust APIs; resumption
tests use a fake broadcast adapter. Mobile widget tests cover the existing Card
retry screen and account changes. These are not live-chain or native
process-termination evidence. Full Gift onboarding activation, native walkthrough
recording, and live claim verification remain later work.
