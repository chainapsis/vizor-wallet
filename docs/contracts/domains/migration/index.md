# Migration

Choose the contract for the behavior being changed. Known contracts can be read
directly; follow additional links only when their stated condition applies.

| Change or question | Read |
| --- | --- |
| Durable Ironwood runs, process operation ownership, user stop, or account deletion/reset preflight | [Migration run lifecycle](run-lifecycle.md) |
| Wallet-open epochs, overdue-transfer fallback, sleep/lock timing, or visibility-driven scheduling | [Desktop migration scheduling](desktop-scheduling.md) |
| The platform-neutral preparation operation API, its mode/cancel boundary, or restricted read-only entry points | [Migration preparation core](reference/preparation-core.md) |
| The watch-only iOS task, read-only DB access, per-wave notifications, or multi-account continuation handoff | [iOS migration confirmation](ios-confirmation.md) |
| Background submission of staged signed transaction bytes or reconciliation after transport/storage outcomes | [Migration signed outbox](signed-outbox.md) |
| Shared mutation preflight and recovery | [Mutation barrier](../../references/wallet/mutation-barrier.md) |
| iOS background Direct transport | [Background transport](../../platforms/ios/background-transport.md) |
