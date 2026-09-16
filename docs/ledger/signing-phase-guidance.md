# Ledger signing phase guidance analysis

2026-09-16. Four-stage guidance implemented after the inventory and proposal below.
The inventory records the pre-change UI; the implementation section records the new behavior.
Scope: transaction approval on desktop/mobile, plus the separate voting approval UI.
Account import/public viewing-key export is a separate onboarding flow.

## Current surfaces

Desktop send uses `AppPaneModalOverlay` in `send_review_screen.dart`. Mobile send
uses `MobileLedgerSendSignScreen` with top title `Confirm transaction`. Both render
`LedgerSigningModal`. Shielding, swap/payment, gift-card funding and immediate
migration also use that shared card, with desktop overlays/mobile page wrappers.
Mobile wrapper titles include `Shield with Ledger`, `Sign ZEC deposit`,
`Sign payment`, `Confirm Gift Card`, and `Migrate with Ledger`.
Voting uses `LedgerVotingSigningPanel`, not the shared card.

macOS supports USB/BLE; Windows/Linux USB; iOS/Android BLE in current product code.
Form factor controls presentation; active transport controls connection instructions.

## Pre-change shared card inventory

| Phase | Title | Status | Body |
| --- | --- | --- | --- |
| preparing | Preparing for Ledger | Preparing transaction | Vizor is preparing the transaction for secure device review. |
| awaitingDevice | Review on your Ledger | Waiting for approval | Review every transaction detail on the device, then approve or reject it. |
| saving | Saving signed transaction | Securing transaction | Keep Vizor open while the signed transaction is saved securely. |
| broadcasting | Sending transaction | Broadcasting to the network | Keep Vizor open while the transaction is sent. |
| failed | Caller-specific | Caller-specific, often Action needed | Caller-specific failure/recovery instructions. |

During awaitingDevice, readiness can override the card:

- `Checking your Ledger` / `Checking device`: `Vizor is checking whether the Zcash app is ready.`
- `Confirm opening Zcash` / `Opening Zcash`: `Confirm the request on your Ledger. Vizor will reconnect automatically.`
- idle/ready/failed readiness otherwise keeps the generic approval text.
- A failed card may use `Ledger needs attention` / `Action needed` and the readiness error.

Preparing and awaitingDevice both also show `Open the Zcash app` /
`Keep it open on your Ledger.` even after the app is known to be open.
Active cards have a spinner and a disabled `Waiting` button (`Saving` during save).
Cancellation availability depends on the flow; signed-operation recovery must be preserved.
Desktop failure UI can offer Auto/USB/Bluetooth on macOS, USB guidance on Windows/Linux;
mobile does not offer this connection picker.

TEX and consecutive shielding display transaction/round counts. Awaiting text is
`Review Transaction N of M on your Ledger`, `Waiting for approval · N of M`,
and `Approve this transaction on the device. Vizor will request the next transaction separately.`
Shielding additionally explains separate network fees per approval.
Normal send hands off after saving to the send-status flow rather than showing
the shared card's broadcasting phase.

Voting shows `Approve voting delegation`, `Bundle N of M`, and defaults to
`Waiting for Ledger approval` / `Approve bundle N on the device. Vizor will continue automatically.`
Readiness overrides are checking/opening/attention. Its enclosing status screen
can still say `Approve on your Ledger` while the panel is checking the device.
Keep the existing disclosure that the device may not display the voting memo verbatim.

## Gaps

1. Both send UIs set awaitingDevice before calling the signer, not upon device review.
   Validation, path/DB lookup, connection, cooldown, APDU planning, upload, device
   processing, signature retrieval and local validation are collapsed into approval.
2. Regular send/swap/shield proof generation happens under preparing, but this
   generic label does not explain the longer local calculation.
3. Connection/cooldown happens before readiness sets checkingDevice. Old idle/ready
   state can therefore display approval while no review is possible yet.
4. No transport progress or per-command activity reaches the card. A long device
   computation and a broken connection initially look identical.
5. After approval, response retrieval and verification still say waiting for approval.
6. Immediate migration has an additional issue: after signing, broadcasting includes
   waiting for background proofs, before actual network submission.
7. Cancellation can await SDK/proposal cleanup without a dedicated cancelling label.

## Revised proposal: four user-facing stages

User feedback on 2026-09-16 supersedes the earlier detailed stage proposal:
keep `Open the Zcash app` / `Keep it open on your Ledger.` unchanged, and group
internal work into a few stages. Do not expose a checklist of internal operations.

| Stage | Suggested title | Short body | Work included |
| --- | --- | --- | --- |
| Prepare | Preparing transaction | Please wait while Vizor prepares your transaction. | PCZT/proofs, validation, connection readiness, cooldown and command planning. |
| Transfer | Processing with Ledger | Keep your Ledger connected. This may take a while. | Transaction command transfer and device processing interleaved with that transfer. |
| Review | Check your Ledger | Review and approve when prompted on your Ledger. | Processing around the review-triggering command and user review/approval. |
| Finish | Finishing transaction | Keep Vizor open. | Signature retrieval/validation, checkpoint, and any remaining proof work; network submission if this surface owns it. |

The first two stages mean wait, review means check the device, and finish means
Vizor is completing the approved request. Desktop/mobile use the same four-stage
model. No new screen per stage and no mandatory four-step checklist; update the
existing title/status area without repeating the same information three times.

- Keep the existing persistent Zcash-app prompt unchanged, as explicitly requested.
- The existing `Confirm opening Zcash` remains a contextual action prompt within
  preparation, not another numbered stage. Never hide a required device action
  behind a generic waiting message. Checking-device feedback can remain contextual.
- Do not expose proof generation, DB reads, cooldown, signature verification and
  saving as separate stages. Internal states remain available for correctness/logs.
- Normal send already navigates to its send-status screen for broadcasting; retain
  that handoff. Flows broadcasting within the Ledger surface can remain in Finish,
  rather than adding another approval-stage transition. Success/failure remain outcomes.
- Preserve round/bundle N-of-M and per-transaction fee explanations. Each new approval
  repeats the relevant stages; Finish alone must not imply the whole batch succeeded.
- Voting uses the same stage semantics with operation-appropriate nouns and keeps
  the existing memo disclosure. Synchronize its outer headline and inner panel.
- Cancellation/failure are exceptional states, not extra happy-path steps. A
  cancelling button label can explain cleanup without adding a stage to the sequence.

## Honest progress boundaries

- Enter Transfer immediately before transaction APDU exchange, after host preparation.
- Current APIs do not expose an exact device-screen-ready event. Enter Review at
  the protocol's review-capable request boundary, verified for each supported
  transaction format; do not switch merely because signing was requested.
- The final upload request may still perform device validation before showing review.
  `when prompted` deliberately avoids claiming that approval is already visible.
  Never wait for that request's response to first show Review if the response itself
  requires user approval. Do not infer progress from a timer or poll concurrently.
- Enter Finish only after the review/approval outcome is known; then retrieve and
  verify signatures. If that boundary cannot be observed by the host, remain in
  Review until a reliable response is available instead of fabricating approval.
- No percentages, estimated completion times, or command counts in the initial UI.
  Keep per-command timing/progress internally for diagnostics.
- Keep the processing helper fixed: `Keep your Ledger connected. This may take a while.`
  Do not replace it based on elapsed time; elapsed time alone does not establish
  device health or failure.

## Implementation

- `ledger_signing_progress.dart` owns the account-scoped stage and attempt generation.
  Late events after cancellation, disposal or a newer attempt are ignored; stages
  advance monotonically within an attempt, including review-busy transport retries.
- Shared signing cards and voting consume this model. Preparing includes host work;
  existing app-opening action prompts remain. Voting headings no longer ask for
  approval while preparing. Transaction/bundle counts remain independent of stage.
- USB uses an FRB stream with operation-local progress and one terminal result.
  The final packet of `CommandPackets.finishes_pczt` emits reviewing immediately
  before exchange; a successful exchange sequence emits finishing before signatures.
- Apple/Android BLE emit progress over a separate method channel, keyed to the
  existing batch request. The final Orchard V5 (`0x56`) or Ironwood V6 (`0x58`)
  bundle command with `p2 == 1` marks the review boundary; its successful response
  marks finishing. The existing sequential APDU batch, retries, validation and
  cancellation ownership remain intact. macOS BLE uses these same native events.
- Review is a protocol boundary, not an exact screen-ready signal. Device validation
  can still run before the prompt appears; the copy explicitly says “when prompted.”
- No additional device polling, split batches, percentages, timers or automatic
  signing retries were introduced. Physical Nano X timing/reboot verification is
  deferred in `nano-x-follow-up.md`; this UI change does not claim to fix that issue.
- Regression coverage includes live stage changes, account isolation, cancel/retry
  and late events, consecutive mobile rounds, and native review/response ordering.

Copy audit CSVs named by AGENTS.md were not present in this checkout. Draft copy
uses sentence case; consult those audits if restored before implementation.
