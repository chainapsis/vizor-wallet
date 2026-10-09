# SQLite sparse-checkpoint backport

`zakura-client-sqlite/` is the published `0.1.0-rc7` package with the single
upstream source fix from
[wallet-libraries #87](https://github.com/zakura-core/wallet-libraries/pull/87),
commit `e1cf20a25b3b43dd49463a804a82a5d6248b16bb`.

When no retained checkpoint exists at or above a requested rewind height, the
old fallback used the pruning floor instead of the requested height. The fix
uses the requested truncation target, avoiding a rewind below an account's
birthday. The upstream regression test is included unchanged; checkpoint
safety guards and database schemas are unchanged.

The root Cargo patch applies to **production builds as well as tests**, including
transitive SDK consumers. This is not an E2E-only workaround. All SDK package
versions and dependency requirements remain unchanged; it is not a dependency
family upgrade.

`zakura-client-sqlite/PATCHES.json` records the published archive checksum,
source revision, upstream fix, all original package-file hashes and the modified
file hash. Two packaging-only newline normalizations and license-text provenance
are recorded separately. All other package source files retain their published
bytes, including existing whitespace. The source copy is about 2.9 MB.

Offline provenance checks:

```bash
python3 -B -m unittest scripts/e2e/test_sqlite_backport.py
```

Those checks establish package provenance, not wallet behavior. The isolated
multi-account E2Es retain the existing balance, transaction-history, account
separation and repeated-sync assertions. The two orphaned/deleted scan-range
regressions deliberately inject historical scan-queue state because the short
regtest chain cannot naturally reproduce a mainnet partial scan.

Remove this override when a published SDK release contains the fix, after
verifying the affected multi-account cases against that release. Do not apply
formatting or unrelated fixes to the vendored package.
