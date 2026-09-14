# Contract compression review — 2026-09-12

Completed on `rowan/agent-contract-docs`, based on `5b2783bb2`.
All changes remain uncommitted in the documentation worktree.

## Result and measurement boundary

The 11 contracts decreased from **72,753 to 67,434 UTF-8 bytes**:
**5,319 bytes saved (7.31%)**. The baseline was captured immediately before
this prose pass, after the Migration and Voting contract additions. Comparing
only with Git HEAD would mix those additions with this compression.

This measures file size, not tokenizer output, model input, quota consumption,
or task quality. No new A/B or model benchmark was run. The user's latest
instruction lifted the earlier quota reserve; an account-limit reset was not
verified.

| Contract | Before bytes | After bytes | Reduction |
| --- | ---: | ---: | ---: |
| [account-storage.md](../contracts/account-storage.md) | 6,442 | 5,893 | 8.5% |
| [hardware-signing.md](../contracts/hardware-signing.md) | 5,270 | 4,969 | 5.7% |
| [lock-sync.md](../contracts/lock-sync.md) | 5,747 | 5,490 | 4.5% |
| [migration.md](../contracts/migration.md) | 9,178 | 8,261 | 10.0% |
| [payment-links.md](../contracts/payment-links.md) | 7,715 | 7,304 | 5.3% |
| [security-lifecycle.md](../contracts/security-lifecycle.md) | 4,762 | 4,505 | 5.4% |
| [send.md](../contracts/send.md) | 5,649 | 5,293 | 6.3% |
| [swap-pay.md](../contracts/swap-pay.md) | 5,558 | 5,301 | 4.6% |
| [sync-network.md](../contracts/sync-network.md) | 5,785 | 5,153 | 10.9% |
| [ui-platform.md](../contracts/ui-platform.md) | 7,932 | 7,344 | 7.4% |
| [voting.md](../contracts/voting.md) | 8,715 | 7,921 | 9.1% |

## What changed

Two workers handled the account/security/lock and payment/signing groups;
the parent handled Migration, Voting, sync/network, and UI/platform, then
reviewed the combined wording and ownership boundaries.

The edits remove repeated subjects, redundant explanations, and verbose
transitions. They retain explicit conditions, exceptions, ordering, ownership,
units, numeric limits, failure outcomes, source symbols, and verification links.
Examples retained include proposal consumption versus input-lock release,
authoritative balance refresh before retry, ambiguous-broadcast recovery,
account/session generations, account-scoped migration handoff, serialized vote
broadcasts, and the mobile build/test define.

Two wording corrections were checked against current source:

- Hardware signing now says **Vizor** owns proof work, rather than limiting the
  statement to a phone. Both
  [desktop review](../../lib/src/features/send/screens/send_review_screen.dart)
  and [mobile signing](../../lib/src/features/send/screens/mobile/mobile_keystone_sign_screen.dart)
  invoke the proof pipeline.
- Migration now states that **any required** notification submission succeeds
  before continuation recording. The condition matters: submission is not
  required when there are no notification events or notifications are disabled.
  See `applyTrackingBatch` in the
  [native manager](../../ios/Runner/BackgroundMigrationPreparationManager.swift)
  and the failed/successful-submission cases in
  [RunnerTests.swift](../../ios/RunnerTests/RunnerTests.swift).

The prerequisite phase also clarified docs-only verification in
[CONTRIBUTING.md](../../CONTRIBUTING.md#testing), added Migration/Voting behavior
and focused test anchors, and shortened ordinary/API comment narratives in
three source files. Those source diffs remove a net 92 comment lines; their
changed lines contain only comments or whitespace.

## Verification

- All 90 contract headings retain their text and order.
- Markdown link targets and their order are unchanged in each contract.
- All prior inline-code contents remain, comparing normalized whitespace.
- All 176 local link occurrences in root AGENTS, CONTRIBUTING, and the contracts
  resolve; Markdown fragments were checked against destination headings.
- CONTRIBUTING's existing fenced command blocks and root AGENTS are unchanged.
- Changed contract conditions were compared with their baseline wording;
  targeted code and existing test cases support the clarified claims.
- `git diff --check` passed. Source diff inspection found only comments and
  whitespace in the three files already touched by the prerequisite phase.

These structural checks support the manual review; preserved headings and
symbols alone do not prove semantic equivalence. No Flutter/Rust build, runtime
test, regtest, or new test was needed or executed for these documentation and
ordinary comment changes. Linked tests were inspected, not run.

## Recommended stopping point

Keep this compression without imposing a further percentage target. Further
cuts would increasingly remove useful qualifiers, turn readable sentences into
abbreviations, or force extra lookups. Observe the documents during the next
real domain task; correct ambiguity or redundant reads where they occur.

Vizor local and remote `main` were not modified. No commit, push, installation,
or new paid experiment was performed in this pass.
