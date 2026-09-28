# Desktop Gift Card groups

Someone giving the same Gift Card to several people can fund separate claimable cards in one desktop action, then save their distinct links in one CSV file. Each recipient gets one link and claims it through the existing claim flow. One-card creation stays the default. The code calls a group a *batch*; users only see "group".

| Included | Outside this version |
| --- | --- |
| Desktop software, Keystone and Ledger accounts; one amount and optional message for every card; one shared design or a different design on each card; an account-specific count ceiling; one funding transaction and one hardware signing request; CSV export and later re-export; batch recovery and status; a ready reveal | Mobile creation UI; different amounts or messages per recipient; choosing a design per card; recipient assignment, mailing, print sheets or bulk QR export; marking cards as shared on export |

The selectable range is **2–50 cards for software accounts and 2–30 for Keystone and Ledger**. These are product ceilings, not guaranteed transaction capacities: every proposal still passes the signer-specific checks below. There is no bulk **Max** shortcut, because the amount is per card.

## Interaction contract

Desktop Gift Cards keeps the centred one-card entry and list. A compact **For a group** tile with a small card stack sits at the right and opens the group flow in one step. At narrow widths or 200% text it becomes a full-width row below the main content. The one-card amount, message and review screens have no quantity control. On mobile, group members appear as ordinary created cards.

1. **Configure.** Starts at two cards. The deck preview leads the form, with the count control and the design rail under it.
   - The count control steps one at a time, accepts a typed number (clamped on submit or blur), and offers 10, 20 and the account ceiling.
   - **Different design on each card** is a labelled checkbox under the rail. It deals the designs in a shuffled order that uses each design once per round and never repeats one on neighbouring cards. The order is drawn once when the box is checked, so the preview matches the created cards. Choosing a single design unchecks it. Each card carries its own design in its link, so recipients see nothing new.
   - The amount field shows the spendable balance beside its label. The message field is always visible, grows from one line to at most two, and keeps the existing 128-character and 512-byte limits.
   - The title stays at the top and content starts at a fixed offset below it, so anything added while typing grows downward without moving what is above.
   - **You will spend** shows **Per card** (amount plus the per-card redeem fee), **× N cards**, **Network fee** and the total. Card math shows immediately; only the network fee and total wait for the quote. While the wallet syncs they stay pending instead of showing an error. A shortfall row appears only when the balance is insufficient.
   - After a sync, the prepared quote is kept when the spendable balance is unchanged and requoted when it changed.
2. **Review.** One centred column like the one-card review: a larger deck, the cost rows, the message if set, a divider, **Total**, then **Create N cards**. The fee is estimated for the complete output set and is never the one-card fee multiplied. Review and Create are disabled while quoting, when the balance is insufficient, or when the account or quote is stale. Quantity, amount or account edits invalidate the quote; design and message edits keep it and prepare the final presentation on entering Review.
3. **Creating.** One batch operation, with no fabricated percentage. The transaction funds every output or none.
   - A fee change before submission requotes and says so. A failure before anything was proposed funds nothing and returns to Review.
   - If the broadcast result is unknown, the batch and its secrets are kept and no second Create is offered. The list row shows **Payment status pending**; the detail explains that the payment is unconfirmed and offers **Check status**.
   - If card details fail to save after a successful broadcast, the review stays on screen with **Try saving again**, whichever account is active.
4. **Ready.** Once every card has durable funded metadata and the funding transaction meets the share rule (broadcast accepted or one confirmation), the batch detail opens and plays the ready reveal. Its title stays **N gift cards** in every state, so becoming ready never moves the layout.
   - On a roomy pane the detail is split: a fixed summary (deck, title, creation date, **Save all links as CSV**) on the left and a **Cards in this group** list on the right that alone scrolls, so saving stays reachable with 50 cards. Narrow panes, large text and short windows stack the two and scroll the pane.
   - Cards are grouped like the created-card list: **Pending**, **Unused**, then **Used**, each with its count; empty groups are left out. A row shows the card's thumbnail (dimmed once used), **Card 04**, any status its group does not already state, and copy and QR actions.
   - Card-use checks run automatically (on open, every 30 seconds, on resume and after unlock). One status line beside the list heading reports them, and a check never shifts the layout.
   - A funded batch waiting for its confirmation shows **Confirming payment** and says the links become shareable once it confirms.
5. **Created-card list.** One row per batch, matching the single-card row: **0.1 ZEC × 20** over the creation date, and the status (**Ready to share**, **3 of 20 used**, **All used**, or a pending status) at the trailing edge beside a chevron. The status stays empty until funding progress has been read once, rather than guessing a pending state. The row opens the batch detail.

## Funding and persistence contract

For `N` cards of recipient amount `A` zatoshi:

- Generate `N` independent Gift Card mnemonics and shielded unified addresses. Save them with a batch manifest as an unsubmitted draft in the existing secure recovery storage, then quote the complete payment request against those addresses. Each output receives `A + 10,000` zatoshi, keeping the existing per-card claim fee reserve.
- The request has exactly `N` shielded payments and must produce one transaction. A proposal needing more than one transaction is rejected before broadcast; a subset is never sent. Fee and spendable funds are confirmed again immediately before submission.
- Editing the amount or count, or leaving before submission, removes only a provably unsubmitted batch. Before the broadcast boundary, the submission marker is recorded for every member atomically. A successful response records the shared txid and promotes every member together.
- A lost response or interrupted metadata write leaves a durable batch that recovery settles by txid, or by the cards' own wallets, on the next launch. An ambiguous batch is never sent again. A batch with fewer than `N` funded members is **Some cards aren’t ready**, never ready or exportable.
- Keystone and Ledger accounts put the same outputs into one PCZT. Keystone uses one signatures-only batch QR request; Ledger signs once and checkpoints one outbox entry keyed by batch ID. Cancelling before submission removes every member; definitive Ledger rejection or expiry removes the unfunded batch.
- Batch metadata is optional on recovery records, so old single-card records read unchanged. Claim links carry no batch data. Activity and card-use tracking handle many records sharing one funding txid. Account deletion and reset warnings count every unshared funded member.

### Signer limits

Proposals are checked against the real selected inputs, outputs and consensus action counts before Review:

- **Keystone:** at most 96 Orchard or Ironwood spend signatures per request, and no Sapling inputs.
- **Ledger:** at most 32 shielded actions per pool in the Zcash app's serializer, and no Sapling inputs. At NU6.3 a legacy Orchard action cannot combine a spend with a cross-address output, so 30 card outputs plus one change output and one spend can already fill all 32 Orchard actions.

A rejected proposal says what to try instead, fewer cards or a smaller amount per card, and does not enable Review. It is never split into several transactions.

### Export contract

- Prepare every share URI through the existing validation path first; if any fails, write nothing.
- Save through the native panel as `vizor-gift-cards-YYYY-MM-DD.csv`: UTF-8, header `card_number,amount_zec,link`, one quoted row per card in card order.
- The confirmation before choosing a location says **Anyone with this file can claim these cards. Save it somewhere private.** Cancelling is silent and leaves re-export available.
- Never log links, mnemonics or CSV contents. Export is not proof of delivery, so it does not mark cards shared.

## Motion contract

In Configure, changing the count animates the deck's thickness and `×N` badge over 140 ms; reduced motion shows the target immediately. The first transition of a batch to ready plays a one-shot stacking reveal: cards drop onto the stack from the back (90 ms apart, 320 ms each) and the `×N` badge appears last (160 ms). There is no confetti. Reopening the batch, returning from the list, exporting and restarting show the settled deck. Screen readers get one batch with its exact count and state, not the decorative layers.

## Measurements

Local macOS regtest, software account, 2026-09-24. Figures are measurements, not requirements.

| Cards | Orchard actions | Fee (zat) | Transaction size | Proof and broadcast | Peak RSS (profile build) |
| --- | --- | --- | --- | --- | --- |
| 2 | 6 | 30,000 | 21,789 B | 0.46 s | 0.47 GB |
| 10 | 11 | 55,000 | 37,569 B | 0.54 s | 0.57 GB |
| 50 | 51 | 255,000 | 163,811 B | 1.65 s | 1.28 GB |

- Keystone batch QR requests took 42–61, 218–246, 321–349 and 526–554 parts for 2, 20, 30 and 50 cards; the count depends on which notes are spent. Thirty cards is at most about 44 KB, within the protocol's 80 KB limit.
- Keystone signing QRs now show 5 frames per second (#754), so one 30-card cycle takes about 64–70 seconds. The 30-card Keystone cap was set when that cycle took about 35 seconds at 10 fps. Scan time on a real device is still unmeasured.
- A restart after a lost broadcast response recovered all 50 cards with the same txid and no second funding transaction.

## Release gates

1. Compare the 50-card peak RSS and proof time with the minimum desktop specification before fixing the software ceiling.
2. Sign, broadcast and confirm 2 and 30 cards on a real Keystone and a real Ledger, including rejection, cancellation, restart after a checkpoint, and inputs that reach each signer limit.
3. Save and reopen a CSV on every desktop platform being shipped, and claim two of its links.

## Code map

- Screen routing: `lib/src/features/payment_links/screens/payment_links_screen.dart`. The group flow's form, quote and funding state live in its part file `payment_links_batch_creation.dart`, as one quote state and one submission state.
- Configure and review: `lib/src/features/payment_links/widgets/payment_link_bulk_desktop_flow.dart`, with the cost panel in `payment_link_batch_cost_summary.dart` and the count and message fields in `payment_link_batch_inputs.dart`. Detail: `payment_link_batch_detail_desktop_view.dart`. Deck and motion: `payment_link_batch_deck.dart`.
- Quote and funding: `PaymentLinkService.prepareBatch` and `fundBatch` in `lib/src/features/payment_links/services/payment_link_service.dart`. Limits: `payment_link_batch_limits.dart`. Export: `payment_link_batch_export.dart`.
- Persistence and recovery: `payment_link_recovery_store.dart` and `payment_link_recovery_reconciler.dart`.
- Hardware: `payment_link_hardware_signing_service.dart` (Keystone) and `payment_link_ledger_funding_service.dart` (Ledger).
- Rust proposal and signer checks: `propose_payment_link_batch` and `estimate_payment_link_batch_fee` in `rust/src/wallet/sync/send.rs`, exposed through `rust/src/api/sync.rs`.
- Protocol background: [ZIP 321](https://zips.z.cash/zip-0321) allows several payments in one transaction; [ZIP 317](https://zips.z.cash/zip-0317) scales the conventional fee with logical actions.
