# Product domains

Choose the contract for the behavior being changed. Known contracts can be read
directly; follow additional links only when their stated condition applies.

| Change or question | Read |
| --- | --- |
| Account creation, import, switch, or deletion | [Accounts](accounts/index.md) |
| Startup, lock/unlock, or whole-wallet reset | [Wallet lifecycle](wallet/index.md) |
| Credential setup, validation, or password rotation | [Security](security/index.md) |
| Ordinary ZEC transfer and its navigation | [Send](send/index.md) |
| Support Vizor availability, entry, Review, or status | [Donation](donation/index.md) |
| Shield Balance eligibility and execution | [Shielding](shielding/flow.md) |
| Create/edit a Receive request; amount and address snapshots | [Receive](receive/request-draft.md) |
| Incoming ZIP-321 request, parking, card, or handoff | [Payment requests](payment-requests/index.md) |
| Swap composition, quote, or deposit | [Swap](swap/index.md) |
| Pay exact-output composition, retry, quote, or deposit | [Pay](pay/index.md) |
| Gift Card payload, funding, claim, or recovery | [Gift Cards](gift-cards/index.md) |
| Desktop-to-mobile encrypted wallet transfer | [Wallet Link](wallet-link/index.md) |
| Voting discovery, participation, signing, or execution | [Voting](voting/index.md) |
| Ironwood run, preparation, scheduling, or native tracking | [Migration](migration/index.md) |

## Source-only areas

These areas do not yet have standalone behavior contracts. Begin with their
implementation; the routes above cover only the documented behaviors they use.

- [Activity](../../../lib/src/features/activity/screens/activity_screen.dart)
- [Address book](../../../lib/src/features/address_book/providers/address_book_provider.dart)
- [Address scan](../../../lib/src/features/address_scan/domain/address_scan_payload.dart)
