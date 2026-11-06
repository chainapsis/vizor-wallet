# Initial Home presentation

Newly created accounts stay on normal Home while their first local reads load.
One-block scan work does not replace Home with an importing screen. Amounts and
Activity still depend on real accepted reads; creation never seeds a zero
balance or an empty transaction history.

New software, Keystone, Ledger and Wallet Link imports enter the restore
presentation before account publication. A zero partial summary, a discovered
transaction, or a temporarily empty scan queue does not finish restoration.
The first accepted native completion and successful balance/history reads are
required. The local Gift Card and enabled swap indexes load while mobile's
normal Home is unmounted, so completing restoration does not mount a second
set of Activity skeletons. Local failures are terminal presentation outcomes:
Home can display unavailable Activity and recover on a later accepted read.
Network failures keep the existing actionable Home error and can resume the
restore presentation on retry.

The registry is session-only and keyed by account UUID, with an identity token
per entry. Successful creation/import registers before publishing the account.
A sync captures pending tokens before preflight; its completion cannot finish
an account added later or an entry replaced by deletion/reset. Existing
account/read/session generation checks still reject stale local responses.
Wallet-wide completion can finish the scan requirement for inactive imports;
their account-specific reads finish when selected and refreshed.

Unknown sessions without a restored display balance register conservatively at
sync start. They enter importing only after real pending work is observed and
remain there through scan-queue zero until completion reads finish. A restart
restores no creation/import hint. Existing display caches keep the normal Home
path. A Home presentation that has resolved local sources does not reenter
importing for later sync or local-index refreshes.

Switching accounts, locking and backgrounding preserve the non-secret intent.
Lock still clears sensitive sync data and rejects late reads through the
existing epoch checks. Deletion removes the entry; a successful reset clears
all entries. No account JSON, database schema, Rust API, RPC budget, periodic
timer, scan range or birthday changes. Desktop, mobile and sidebar labels use
the same presentation. Sidebar navigation retains its original operational
importing restrictions and also stays blocked while showing restoration.
Mobile keep-awake and authoritative spendability continue to use sync truth.
