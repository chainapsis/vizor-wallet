# Sync contracts

Choose the contract for the behavior being changed. Known contracts can be read
directly; follow additional links only when their stated condition applies.

| Change or question | Read |
| --- | --- |
| Foreground scanning, running/mode/cancel guards, polling, mempool observation, or surfaced termination and retry | [Foreground sync lifecycle](foreground-lifecycle.md) |
| Authoritative progress targets, denominator updates, UI smoothing, or the meaning of completed progress | [Sync progress and UI interpolation](progress.md) |
| Account-scoped display caches, restored spendable snapshots, or authoritative refresh after proposal release | [Account balances and authoritative refresh](account-balances.md) |
| User lock/unlock orchestration | [Lock and unlock](../../domains/wallet/lock-unlock.md) |
| Tor/Direct endpoint transport | [Network route policy](../network/route-policy.md) |
| Shared writer quiesce/drain/pause | [Mutation barrier](../wallet/mutation-barrier.md) |
