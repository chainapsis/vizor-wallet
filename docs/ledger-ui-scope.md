# Ledger UI collection scope

This is the UI collection for the Ledger review series. The initial commit is
documentation only. It adds no routes, screens, assets, or runtime behavior.

## Review baseline

- Source implementation: `fbe51859972213eb0c70dc80bda67c7ef7f249e8` on
  `rowan/ledger-advanced`.
- Starting main: `7339fa94a62339d89bcbbb3f14916d7be931a26a`.
- UI collection: `rowan/ledger-ui-collection`, targeting
  `rowan/ledger-core-collection`.
- Core collection PR: [#693](https://github.com/chainapsis/vizor-wallet/pull/693).
- Core plan: [ledger-pr-plan.md](ledger-pr-plan.md).
- Source ownership: [ledger-change-inventory.md](ledger-change-inventory.md).
- The original implementation and the older `rowan/ledger-core` branch remain
  intact. This collection does not replace either one.

## What belongs here

| Surface | Expected UI behavior | Core contract consumed |
| --- | --- | --- |
| Onboarding and accounts | Choose Ledger, connect, enter an advanced account index, retain input on failure, set birthday/name/password or passcode | C02 account import, C03 connection state, relevant OS adapter |
| Account management | Display independent Ledger accounts, account details and connection preferences, no secret-phrase action | C02 account metadata, C03 connection/enrollment state |
| Shared connection and signing surfaces | Show device selection, app readiness, pairing confirmation, review/signing progress, reconnect and invalid-pairing recovery | C03-C08 typed state and action contracts |
| Send and TEX | Desktop/mobile review, approval rounds, cancel/retry/status presentation | C09 limits, C10 recovery, C11 send execution |
| Shielding | Remaining-input notice, round count, approval and paused/completed presentation | C09 limits, C12 shielding execution |
| Swap and pay | Deposit approval, pending broadcast, queued/recovered result and disabled actions | C10 recovery, C13 order/deposit state |
| Voting | Bundle progress, device approval, reconnect/cancel/retry presentation | C14 voting session/job state |
| Wallet Link | Imported Ledger identity and first-mobile-signature device enrollment screens | C15 transfer/enrollment contract |
| Unsupported operations | Explain unavailable migration and other current capability limits | Existing support guards, C03 capability, C09 proposal checks |
| Visual support | Icons/assets, Widgetbook fixtures and deterministic comparison scenarios | The same view state contracts used by product screens |

Account grouping and wallet fingerprints removed in the source snapshot must not
return during extraction. Advanced displays account-level shielded and
transparent paths; it does not introduce manual receive-address-index entry.

## Boundary with core

UI renders state and sends explicit user intents. Account validation, transport
fallback, cancellation, retry eligibility, signing, checkpointing, broadcasting,
expiry, and recovery decisions stay in core. A widget file containing those
decisions is a mixed source file, not an automatic UI assignment.

The core collection owns the minimal app lifecycle trigger needed to recover
stored operations; this collection owns its visible notices. Existing widget
orchestration is extracted only as far as needed to preserve this boundary.
This series is not a redesign or a general architecture migration.

Error classification is core; wording, recovery instructions and settings-button
presentation are UI. Connecting or pairing must not itself approve, sign or
broadcast. Retry controls must consume the specific action allowed by core.

## Sequential review policy

- These two collection drafts are containers, not active feature reviews.
- Open one feature PR, obtain review, address feedback, and merge into its
  collection before opening the next one.
- If a second review is independent, propose its dependency and file-overlap
  evidence to the user first. Open it only after explicit approval.
- Sub-agent analysis does not authorize concurrent feature PRs.
- This seed does not create feature PRs, request reviewers, merge anything into
  main, or authorize a release.

## Acceptance for future UI PRs

- Verify visible success, failure, cancellation and retry states with
  deterministic fixtures; preserve existing software and Keystone surfaces.
- Run targeted desktop and mobile tests in their respective form-factor lanes.
  Mobile tests use `--tags mobile --run-skipped
  --dart-define=VIZOR_FORM_FACTOR=mobile` in a single invocation.
- Use widget captures for app content. Verify native permissions, pairing and
  actual Ledger prompts on the relevant platform, recording unverified cases.
- Update literal-string tests and Widgetbook fixtures with copy changes.
- Keep existing sentence-case and design-token conventions. Do not introduce
  new feature policy through button handlers or route guards.
- State whether evidence is a fixture test, native adapter test or physical
  device run. Do not reuse old full-branch results as proof for an extracted PR.

## Collection completion

The UI collection is complete when its source inventory is reconciled, the
corresponding core contracts have been integrated, the combined result preserves
the source behavior except for documented review changes, and visual/runtime
verification gaps are explicitly recorded. Turning the collection ready for
review or merging it into main is outside this documentation-seed step.
