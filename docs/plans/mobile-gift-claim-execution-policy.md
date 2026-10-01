# Mobile gift card claim execution policy

Decision: 2026-10-01, agreed while reviewing PR #814.

## Inspection and binding

- Inspect the card before wallet setup, using its temporary claim wallet.
- Treat the result as a snapshot at inspection time. It is not a promise that
  the funds will remain available or that a later claim will succeed.
- When binding the receiving account, reuse the inspected database and
  re-estimate the amount and fee for that account's address.
- Do not add a sync during binding or add a background scan merely to refresh
  this snapshot. Readiness and confirmation counts can remain unchanged until
  the existing claim/recovery path updates them.
- Attempt the claim when the prepared session permits it. Confirmation waiting
  remains waiting; submission rejection is a failure; an uncertain submission
  remains recoverable rather than being treated as a definite failure.

## Onboarding integration contract

This section specifies the follow-up UI integration. PR #814 provides card
inspection and restart-safe account setup but does not activate the new
onboarding routes or claim handoff.

- Finish account creation and durably save the card and its receiving account
  UUID before handing off the claim work.
- Keep the configured account and passcode if the claim fails.
- Continue through optional Face ID setup into Home without waiting for the
  claim to finish. Claim work belongs to the existing coordinator, independently
  of the onboarding screen's lifetime.
- Do not add a Gift Card status banner to Home.

## Existing failure and recovery surface

- Use **Settings > My gift cards > Received** to find the saved card, inspect its
  status, and retry through the existing card flow.
- The service saves the card before submission. A failure before submission
  starts returns it to an actionable Received record; once submission may have
  started, retain the card wallet and submission state for existing recovery.
- Received is the tab for saved incoming cards, including unsuccessful and
  pending claims; it does not mean every listed card has been successfully
  received on chain.
- Inspection/binding failures before claim submission do not themselves save a
  card. The onboarding handoff must preserve it before starting the claim work.
- Existing claim/recovery scans remain unchanged. This policy adds no extra scan
  to account binding.
