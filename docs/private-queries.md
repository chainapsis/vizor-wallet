# Private queries

Settings has one Private queries toggle for shielded transaction queries and
transparent recovery. Turning it off requires confirmation when public lookups
would disclose wallet addresses and transaction IDs.

The toggle stays On until the transparent policy allows public lookups. If that
change fails, shielded queries also remain private, and the user retries with the
same toggle. Desktop settings, the network settings panel, and mobile settings
use the same state and action. A durably private wallet keeps the toggle visible
on networks where the private service is unavailable, so it can still be turned
off.

The saved turn-off intent survives a crash and is retried at startup. If startup
cannot finish it, the toggle remains On and supported private query paths remain
private. A successful change clears the intent and shows Off. Turning the toggle
on keeps private queries enabled while startup and sync retry any unsuccessful
transparent policy raise.

A full wallet reset keeps the saved install preference, clears any unfinished
opt-out belonging to the deleted wallet, and reapplies that saved choice to the
foreground and native background runtime before onboarding resumes. If an
enable cannot be saved, native background recovery is restored to the previous
setting too. Overlapping turn-off confirmations each apply Off, so a later
confirmation cannot turn private queries back on.
