# Payment request card and handoff

Read when changing precheck, request context, or the card-to-Review/Edit proposal handoff.

- Card ownership: [`payment_request_flow_provider.dart`](../../../../lib/src/providers/payment_request_flow_provider.dart),
  [`payment_request_precheck.dart`](../../../../lib/src/features/send/services/payment_request_precheck.dart),
  and [`payment_request_host.dart`](../../../../lib/src/features/send/widgets/payment_request_host.dart).

- The requester's `label` is unverified; `message` is off-chain context, never
  the transaction memo. Keep both distinct from verified recipient identity.
- Preserve incoming memo whitespace through the card, direct Review, and Edit.
  [`SendPrefillArgs.outgoingMemoText`](../../../../lib/src/features/send/models/send_prefill_args.dart)
  owns the displayed/proposed memo bytes, including a whitespace-only memo.

- No amount, or `amount=0`, produces a ready card without a proposal; its primary
  action opens the composer to collect an amount. A positive amount creates a
  real proposal, retaining account UUID, flow ID, fee, and request framing.
- Only settled, account-scoped spendable state can justify insufficient funds.
  Re-read authority and balance after asynchronous work; stale or non-authoritative
  balances cannot establish a final shortfall. Rust proposal creation remains
  authoritative. Syncing cards recheck on settlement; bounded immediate
  rechecks become `syncStalled`, where the user can choose Check again.
- Replacement checks wait for preceding releases and displaced prechecks.
  Generation changes suppress stale publication and discard any late proposal.
  Dismissal, replacement, account switch, lock, reset, and disposal relinquish
  card-owned proposals. Lock re-parks the request alone unless a newer one is
  already parked; an account switch invalidates the old request's handoff.
- Desktop Review transfers the existing proposal without discarding it. Mobile
  Review returns it and passes a draft to the mobile review step, which creates
  its own proposal on confirmation. Edit on both form factors returns the
  proposal before loading the prefill into a newly keyed composer.
- Mobile Review and Edit clear the card immediately, then await release. An
  unconfirmed release gets one additional attempt after a three-second grace;
  the handoff proceeds after that attempt even if release remains unconfirmed.
  This exception preserves the request; it does not establish successful release.
- A newer request, lock, account switch, or intervening route navigation must
  prevent the old asynchronous handoff from opening a screen. Clear a retained
  completed Send receipt before navigating to the chosen request.

## Verification

- [`payment_request_flow_provider_test.dart`](../../../../test/providers/payment_request_flow_provider_test.dart)
  and [`payment_request_precheck_test.dart`](../../../../test/features/send/payment_request_precheck_test.dart): proposal ownership, release exceptions, races, and affordability.
- [`payment_request_host_test.dart`](../../../../test/features/send/payment_request_host_test.dart)
  and [`mobile_payment_request_host_test.dart`](../../../../test/features/send/mobile_payment_request_host_test.dart): route and Review/Edit handoffs.

## Related changes

- When changing common cleanup success, read [proposal release](../../references/transactions/proposal-release.md).
- When changing spendable authority, read [account balances](../../references/sync/account-balances.md).
- When changing parking after lock or replacement, read [request intake](intake.md).
