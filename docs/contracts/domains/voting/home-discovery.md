# Voting Home discovery

Use when changing candidate discovery, card visibility, lazy loading, or refresh/failure behavior.

Implementation: [`VotingHomeRefresh`](../../../../lib/src/providers/voting/voting_home_entry_provider.dart)
and the [Home cache](../../../../lib/src/providers/voting/voting_home_cache_provider.dart).
Verify refresh, failure, and stale-response behavior with
[`voting_home_refresh_test.dart`](../../../../test/providers/voting/voting_home_refresh_test.dart).

Home renders the last confirmed account-scoped display decision. Unknown rounds
start hidden. A verified remaining eligible note set or an actionable local
recovery plan confirms visibility; an active round alone does not. Decisions
survive restart and do not depend on the current sync progress height.

App bootstrap does not load voting state. Home renders first, then its post-frame
refresh loads the local summary; source and test-round preferences load through
their asynchronous providers. The card stays hidden until the saved decision is
available, then a confirmed show restores without waiting for sync or RPC.
Loaded decisions stay in memory across Home reentry.
The persisted round list contains only IDs, titles, statuses, snapshot heights
and normalized vote deadlines, alongside source/discovery metadata. Full round
payloads and proposal bodies are not serialized with Home decisions; voting
details continue to use their existing live data path.
On entry or foreground resume, mainnet with the bundled prod voting source and
testnet with the bundled stage voting source query their public discovery
endpoint once. Network or selected source changes trigger the same check. Concurrent triggers share
one request; a source/network/endpoint switch queues a refresh for the new context.
The one-minute Home timer only reevaluates in-memory deadlines. It does not read
snapshot files, schedule participation checks or poll discovery. Participation
checks use route, lifecycle, sync and relevant provider-change events; unresolved
checks still respect the participation backoff.

## Refresh and failure behavior

- A valid response has `schemaVersion: 1`, the requested `scope` (`prod` or `stage`), a SHA-256 revision,
  and a UTC `checkedAt`. Reject observations at least ten minutes old and those
  more than one minute ahead of the device clock.
- An unchanged, previously applied revision reuses the list. A missing/changed
  revision runs existing config authentication and authenticated round listing.
  These operations never check Home eligibility or load account recovery/PIR.
- Store the applied revision and endpoint with the successfully refreshed list.
  A probe alone never changes the list's six-hour success timestamp. Existing
  caches without discovery metadata remain readable. Explicit voting-screen
  refreshes preserve the previous applied hint within the same source fingerprint.
- Reconcile via a full refresh at the next Home entry after six hours, even if
  the revision is unchanged. Backend and upstream lists are not an atomic snapshot.
- Probe failures (including 503, stale/invalid responses or URL configuration)
  keep fresh local data and back off for one minute. Missing or expired local
  data still attempts direct discovery. Failed full refreshes back off for five
  minutes and do not save the new revision. No failure means “no votes.”
- Discovery participates in the destructive-operation drain. Discard results
  after lock, source/network/endpoint changes or provider disposal; account
  deletion/reset retain the existing cache cleanup invariants.

Settings keeps its permanent Coinholder voting entry. Actual voting still uses
live config authentication and eligibility checks, irrespective of Home hints.

- Unknown Home rounds start hidden. Only verified remaining eligibility or
  actionable local recovery confirms visibility; an active round alone does not.
  Preserve the last confirmed decision while checking, syncing, or failing. Settings stays
  available regardless of Home visibility.

- Bootstrap never waits for voting storage. Home renders before loading summaries;
  its minute timer checks deadlines in memory without polling discovery/participation.
