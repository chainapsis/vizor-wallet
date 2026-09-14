# Wallet lifecycle

Choose the contract for the behavior being changed. Known contracts can be read
directly; follow additional links only when their stated condition applies.

| Change or question | Read |
| --- | --- |
| First-frame routes, account reconciliation, or startup hydration and blocking failures | [Wallet bootstrap](bootstrap.md) |
| Full wallet deletion, last-account reset, or recovery after partial reset failure | [Wallet reset](reset.md) |
| The complete user lock/unlock transition across security, accounts, sync, navigation, and parked intents | [Wallet lock and unlock](lock-unlock.md) |
| Wallet DB name, path ownership, writer serialization | [Wallet database](../../references/storage/wallet-database.md) |
| Account-specific cache and authoritative balance refresh | [Account balances](../../references/sync/account-balances.md) |
| Shared quiesce, drain, pause, and resume boundary | [Mutation barrier](../../references/wallet/mutation-barrier.md) |
