# Sync

How a wallet sync runs: the Rust engine that downloads and scans compact
blocks, and the Dart provider that starts it and keeps the wallet current.

## Sync Engine (Rust-only)

The entire sync loop runs in Rust (`rust/src/wallet/sync_engine/mod.rs`). A single call from Dart (`startFullSync()`) triggers the full pipeline:

1. tonic gRPC → lightwalletd (TLS via `tls-ring`)
2. Download subtree roots (sapling + orchard, incremental with start_index optimization)
3. Download compact blocks into memory (in-memory `MemoryBlockSource`, no file I/O),
   four batches ahead of the scan (`PREFETCH_DEPTH`), each on its own request
   and planned with the same byte budget as the scan, so up to five batches'
   worth of compact blocks are held at once. Blocks stay protobuf-encoded
   until the scan reads them (`MemoryBlockSource`), since decoded they take
   about 1.8 times their wire size; a tip batch that cuts in between
   history batches keeps the queued ones, and a Verify range a new tip puts at
   the scan frontier is scanned together with the queued batch it falls in.
   A queued batch whose download fails with a network error sooner than any
   lightwalletd timeout (a stream reset, a refused connection) is retried in
   the background after 1 s and again after 4 s
   (`retry_quick_prefetch_failures`); a timeout, or a failure left after the
   retries, is downloaded again inline when the scan reaches the batch.
   With Tor and Private queries on, a session whose estimated download
   reaches `DIRECT_BLOCK_DOWNLOAD_MIN_BYTES` fetches its main-scan batches of
   ChainTip, Historic and LatestPoolActivation ranges, and Verify batches
   above the blocks scanned before the session, directly (see Direct block
   connection below).
4. Scan from memory: trial decryption (`decrypt_cached_blocks`), then the
   scan and write (`scan_decrypted_blocks`). While a batch is written
   (`put_blocks`), the next queued batch, if its download has finished, is
   already being decrypted on the scan's pool (`start_next_decryption`, see
   Scan power), so its decryption overlaps the write. The next scan uses that
   decryption only if it covers the same blocks with the same viewing keys,
   and decrypts again otherwise; it holds one more batch's decryption results
   in memory. A tip batch scanned between history batches keeps that
   decryption for the queued batch, whose work cannot be stopped once started.
   A batch takes as many blocks as fit a
   compact-block byte budget (about 31 MB on desktop, 11 MB on mobile), up to
   10,000 blocks on desktop, 1,000 on mobile and 300 in background mode (each
   batch also pays a fixed serial cost after its scan, so sparse history wants
   long batches). Bytes
   are estimated from the compiled mainnet tree sizes and the downloaded subtree
   completion heights, so the dense spam window gets short batches without
   hardcoded heights and the estimate sends no request; past the compiled table
   and off mainnet, where nothing says how dense blocks are, a batch takes at
   most 2,000 blocks (`UNPLANNED_BATCH_BLOCKS`). The wallet backend's
   `put_blocks` skips work on history scanned after newer ranges: when no height
   in a batch is retained and each tree already holds `max_checkpoints` newer
   checkpoints, the batch adds none, and a
   note-free shard wholly inside it that is already stored as its downloaded
   subtree root is not rebuilt. Rebuilding never compared that root with the
   computed one, and the roots above the shards, which anchors and witnesses
   use, come from the downloaded roots cached in the tree's cap either way, so
   the trust is unchanged. Only the shard's own row differs: it keeps the
   downloaded root instead of the computed subtree, which is read only if a
   truncation drops the cached roots above it. With matching roots the tree rows
   come out the same as without the skip. About one in 16 such shards (random
   per process), and every shard with a wallet note, is rebuilt and its stored
   root compared; a mismatch is logged once per process
   (`stored_root_mismatches`), fails nothing, and turns the skip off for the
   rest of the process. The backend also keeps a tree that a batch inserts
   nothing into, as Ironwood's is before its activation, to `max_checkpoints`
   checkpoints. Without that, it gains one at every height another pool
   checkpoints and prunes only some of them once inserts begin: about 1.4
   million Ironwood rows after a full restore, or about 1,600 with the history
   skip above, against 784 with the pruning.
5. Enhancement: process each work queue separately. Status observations come
   from `transaction_status_work()`, which routes each obligation to public
   `GetTransaction` or private Status PIR. Payload recovery comes from
   `transaction_enhancement_work()`. `transaction_data_requests()` feeds only
   transparent-address history (`TransactionsInvolvingAddress`). librustzcash
   persistently requests `GetStatus` only when compact-block scanning cannot
   observe the transaction's mined state. During recovery, Vizor separately
   excludes previously mined transactions from resubmission while a pending
   scan range can still restore their mined heights. A public payload request
   that fails with anything but "not found", or returns an unusable reply,
   stays queued and does not fail the attempt: the session holds that
   transaction back from later checkpoints for 30 s, then 60 s, 120 s and
   300 s, and a sync that ends with it held completes and leaves it for the
   next sync, as private payload work is. A local database failure while
   storing a payload still fails the attempt.
6. Progress streamed to Dart via FRB `StreamSink` per batch. Each event has a
   `kind` (`SyncEventKind` in `sync_engine/mod.rs`, which replaced the old
   `is_complete` flag): `Progress`, `Completed`, or `FollowupUpdated`.
7. After `Completed`, two follow-up loops run under the same cancellation and
   never fail the sync: private transparent recovery over the transparent PIR
   service (`transparent_followup`,
   `sync_engine/transparent_ledger.rs`, a no-op unless Private queries selects
   it) and transparent txid details (`sync_engine/transparent_details.rs`, over
   txid display PIR under private policy or gated `GetTransaction` otherwise).
   Background preparation syncs (mode 2) skip both. When one changes wallet
   data it reports `FollowupUpdated`, and Dart re-reads balances, history and
   open receipts without counting a second completion. The stream and the
   `SYNC_RUNNING` guard end only after the follow-ups (and the deferred
   inactive-account UTXO refresh) finish.

Single DB connection reused across entire sync (opened once, passed to all operations).

In debug builds, every minute a session logs where its time went (`SyncTimingSummary`): batches and how many went direct, blocks and megabytes downloaded, time waiting for downloads and for tip checks, scan time and the scan power level. The direct block connection and its reconnects are described below.

Chain tip during a sync: fetched at the start, after every batch within 10,000 blocks of the tip (`HISTORY_TIP_CHECK_DISTANCE`) and at most once a minute after batches below that (`HISTORY_TIP_CHECK_EVERY`), every 10 minutes and before completion (skipped when a tip proved unchanged less than 5 seconds earlier). A restore over Tor otherwise waited on a round trip after every batch. Status lookups run only on batches that check the tip, so a recovered status is completed against the check that follows its lookup; between checks, resubmission and status lookups wait. The post-batch fetch is requested when the batch's scan starts (`TipPrefetch`), so its round trip overlaps the scan; it counts as validated when it was requested, it runs whatever the wallet holds, and resubmission judges expiry against it. It predates the batch's status lookups, so a batch whose lookups released a transaction (with resubmission allowed) fetches the tip again after them, as the completion path does for its own releases. That second request is the only wallet state the tip requests show: that a status was released. After an unchanged tip the rebroadcast shows the same; after an advanced tip the rebroadcast waits for a later check. The mempool observer also writes new tips to the DB during a sync, so a ChainTip range can start past the loop's tip: the loop takes the first pending range at or below its tip (`next_pending_scan_range`), and with nothing else pending refreshes the tip once per range start (`refresh_tip_for_queued_range`) before ending the attempt with a continuity error.

Scan power (`sync_engine/scan_power.rs`): each batch scans at the level `set_sync_scan_power` last set. Full uses rayon's global pool (every core, default priority); Efficient a pool of half the cores at utility QoS (nice 10 on Android), which moves Apple devices to the efficiency cores. Efficient runs a batch's decryption, the decryption of the next batch started ahead and the write (`decrypt_cached_blocks`, `start_next_decryption`, `scan_decrypted_blocks`) on a worker of its pool, so the decryption tasks they spawn land there; the scanning thread blocks on their results while holding one worker, so the pool keeps at least two threads. On iOS and Android `SyncNotifier` listens to `com.zcash.wallet/device_power` (thermal state and Low Power Mode / Battery Saver), logs each state in debug builds (`Device power: thermal …`) and feeds `syncScanSlowdownProvider`, which gives a reason (critical before power saving; nothing through serious) once the sync job has run three minutes, so a catch-up that finishes sooner stays at Full; the job's clock survives retries and stops when a sync completes. `SyncNotifier` sets the level from that reason, Efficient while there is one, and the keep-awake screen shows it under "Vizor is syncing". Android maps its thermal status onto the iOS scale; it does not read the thermal headroom, which has no level past severe. Desktop stays at Full.

Progress percentage (`sync_engine/progress_work.rs`): the share of estimated scan work finished for one sync job. Work for a range is a weighted sum of its blocks, Sapling outputs, Orchard and Ironwood actions, and planned batches (counted with the engine's byte budget and foreground block cap); output counts come from the compiled mainnet tree sizes and downloaded subtree completion heights, so the estimate sends no request. Blocks alone stall for most of a full-history sync (the 2022 sandblasting window holds nearly all outputs), and outputs alone stall on the long sparse stretch before it. `mark_sync_started` claims the job (the stored one, including one whose scan finished before the attempt could complete, or a new id) in `ext_vizor_sync_meta`, where its id, total work and fraction stay until `mark_sync_completed` clears them, so retries, endpoint fallbacks and relaunches resume the same fraction (`get_sync_status` exposes it; the bootstrap carries only a cached balance, so an unlock and the first sync after a launch read it before starting). Within an attempt, new pending work (tip growth, rewinds, repairs, new ranges) raises the total; it never restarts the denominator. Work found after the main scan drains (witness and anchor repairs, blocks a final tip refresh adds) shows as Checking instead: events carry `checking` with that queue's own block fraction while `percentage` stays at 1.0, and `retry_progress.rs` keeps the Checking stage across `run_sync_inner` retries (the job already carries the main scan's fraction). A relaunch does not keep it: the work Checking found raised the job's total, so a process killed in that stage resumes at the lower fraction as a main scan. The job is saved every 15 seconds while an attempt scans, at once for the batch that finishes the scan, and once more, marked closed, when the attempt ends however it ends (completion clears it instead). Work that appeared between attempts (blocks mined meanwhile) keeps the stored fraction and rescales the rest; so does less work after a closed attempt, which went away unscanned (a deleted account). Less work after a killed process is scanning done since the last save and counts as progress. Only new work larger than what the job finished (and than one reference batch), or any real catch-up after a job that had scanned everything, replaces the job under a new id. The job also saves the work model it was counted in (every constant of the estimate, its code revision and the newest compiled checkpoint); a job saved under another model, as after an app update, keeps its fraction and rescales the rest whichever way the new measurement differs, unless its scan had finished. Every event carries `sync_job_id`; Dart restarts the display only for a new job. Each progress event also includes `has_new_tx` (from `ScanSummary` received/spent note counts) to trigger transaction history refresh only when needed.

Direct block connection (`open_block_download_lwd_transport` in `sync_engine/lwd.rs`, `DirectBlockRoute` in `sync_engine/mod.rs`): with Tor and Private queries on, a session whose estimated compact-block download, counting only the ranges it may fetch directly (`direct_download_bytes`), reaches `DIRECT_BLOCK_DOWNLOAD_MIN_BYTES` fetches its main-scan batches (`GetBlockRange`, the batch-start `GetTreeState`, and `GetBlock` for the predecessor's hash when the first block carries none) over a direct connection. Compact blocks are public, and one Tor circuit would take hours for a restore. The threshold is per platform, like the batch sizes: 256 MiB on desktop, which keeps syncing in the background (about 13 minutes on one circuit, roughly seven months of recent blocks), and 8 MiB on mobile, where sync runs only on screen (about 25 seconds, roughly five days). It applies only under Private queries: the direct connection opens alongside the session's Tor one, so the server can tie the two together by timing, and Private queries keep address and txid lookups off that Tor connection. Without them every block download stays on Tor. The opener skips the direct-route lease and never dials an onion server (`block_download_can_go_direct`): only Tor reaches one, and a direct dial would send its name to the system resolver. The connection opens with the session, before the Checking stage, only if Tor was already on when the session opened its route, and its opens stop with the session. The session still opens its Tor route first and fails closed with it.

Only main-scan batches of ChainTip, Historic and LatestPoolActivation ranges, and Verify batches above the blocks scanned before the session (the frontier continuity check, often merged into a full queued batch), use the direct connection (`batch_uses_direct_connection`). Checking-stage batches, Verify batches over already-scanned blocks (witness repairs a stopped session left), FoundNote and OpenAdjacent ranges, and every request that carries an address, txid or transaction stay on Tor.

If the direct connection cannot open, the session downloads over Tor. A direct batch that fails, queued or not, is downloaded again over Tor, and three failures in a row (`DIRECT_BLOCK_FAILURES_BEFORE_TOR`) move the session to Tor. After `DIRECT_BLOCK_RETRY_AFTER` (a minute, doubling with each demotion up to `DIRECT_BLOCK_RETRY_MAX`, ten minutes) the session opens a fresh direct connection at the next batch that would download directly, and restarts its queue. A connection that could not open within `DIRECT_BLOCK_OPEN_TIMEOUT` (20 seconds; the TCP connect timeout does not cover name resolution or the TLS handshake), or a reopened one whose first batch fails, waits again. A connection that stops answering fails every request on it while a fresh one to the same server works, as on a phone restore where three queued batches timed out together. HTTP/2 pings close such a connection about 35 seconds after its last frame, so requests sent after that reconnect instead of waiting out their deadlines; requests already in flight still end at their own. Only a multi-threaded runtime pings (`keep_alive_fits_runtime`): background migration preparation scans on its single runtime thread, and hyper checks the ping deadline before it reads the reply, so a long scan there would close a healthy connection.

A direct session shows the server the device's IP address with the birthday bucket or resume height, and a reconnect after the device changes networks shows the new one, which the continuing block range ties to the first. Timing can still tie the session's Tor requests to it. The ranges left on Tor still show: a FoundNote range scanned out of order ends a direct batch, or leaves a gap, at a public subtree boundary, so the server can infer which shards hold the wallet's notes. The connected settings copy therefore says Vizor uses Tor to protect the IP address rather than promising that every request goes through Tor, and does not list this exception.

Automatic retry: `run_sync_inner` wraps `run_sync_impl` with exponential backoff (3 retries, 2s/4s/8s). Cancel and mode-change are checked during retry wait. Both FRB and C FFI paths benefit. With Tor on, a retry opens its connection on a fresh isolated circuit, so a bad exit does not fail every attempt; a first attempt uses the client's shared circuit.

All sync log messages include `[Xs]` elapsed time from sync start (set once in `run_sync_inner`, consistent across retries). Errors are logged via `log` crate (forwarded to os_log subsystem `frb_user` by FRB `setup_default_user_utils()`). Log level set to `Info` to filter verbose rustls TLS logs. Rust logs are NOT visible in `flutter run` terminal — use `log stream --predicate 'subsystem == "frb_user"' --level info` in a separate terminal.

## Dart Sync Provider

`lib/src/providers/sync_provider.dart` — Riverpod `AsyncNotifier`.

**Auto-sync lifecycle:**
- `build()` watches `accountProvider` via `ref.listen` (not `ref.watch` — avoids rebuild on switch/rename)
- Account count increase triggers `startSync()` + `_startPolling()` (both first account and additional accounts)
- `_checkAndSync()`: polls `getLatestBlockHeight` every 10s, re-syncs if tip > last synced height or previous sync incomplete (`!isSyncComplete`)
- The mempool observer's `newBlock` event (the server ended the stream, which lightwalletd does when a block is mined) runs `_checkAndSync()` at once, marked pending (`_newBlockCheckPending`, cleared when a check starts, and by `stopSync()`, the lock and app exit) so a check or sync already running is followed by another, even one that read the tip before the block; at most one such check per 5 s. The 10 s poll stays, since its tick also refreshes the upgrade status, pending-activity evidence and recovery restarts
- `_checkAndSync()`, `_refreshBalance()`, and `_onSyncProgress()` all bail out while
  locked and discard late async completions via `_sensitiveStateEpoch`
- Polling stops during `_checkAndSync` execution to prevent concurrent overlap, restarts after
- Duplicate sync guard: `_isSyncing` (Dart-side bool) + `isSyncRunning()` (Rust AtomicBool)
- `startSync()` / `startSyncAnyway()` called while this notifier's own stream is
  still open (the Rust guard is held through post-sync follow-ups) queue one
  start (`_queueSyncStart`) instead of being dropped. Repeats coalesce: a
  forced request upgrades a plain one and the highest tip carries over. The
  queued start runs when the stream ends, unless the app is now in the
  background.

**startSync() is fire-and-forget:**
- Sets up FRB stream listener and returns immediately (no Completer, no await)
- `_syncGen` generation counter: incremented by `stopSync()`, checked in `.then()` callbacks to invalidate pending operations after user-initiated stop
- Stream `onDone` (handled inline in `startSync()`): balance refresh + start polling, then any queued start
- `FollowupUpdated` event → `_onSyncFollowupUpdated()` (re-read balances and open receipts; not a new completion)
- Stream `onError` → sets error state + starts polling for auto-retry

**Sync control:**
- `stopSync()`: increments `_syncGen` + `cancelFullSync()` + `_stopPolling()`. Polling does not restart until next `onResume`
- `clearSensitiveStateForLock()`: increments `_syncGen`/`_sensitiveStateEpoch`,
  clears in-memory sync state, sends `setSyncMode(0)` + `cancelFullSync()`,
  and waits briefly for stale Rust sync / mempool work to stop
- `startSyncAnyway()`: unlock recovery path. If Rust is still running but already
  cancelling, waits for teardown before starting foreground sync; if teardown
  times out, it at least restores polling so a later retry can recover

**Lifecycle:**
- `onResume`: refreshes balance → `_checkAndSync()` (which starts polling)
- `onHide`: stops polling where the app does no work in the background (`canRunAppProcessWork`; mobile), so no network is wasted there
- `SyncState.recentTransactions`: latest 10 transactions, updated on `hasNewTx`, sync completion, and app resume
- `hasCachedBalance` permits Home to display the persisted snapshot without setting
  `hasBalanceData`, current pool balances, sync completion, or spendability. An
  accepted live read updates current balances independently of history. Persisted
  display snapshots follow the same release conditions as in-memory completed-sync
  snapshots: a valid balance at sync completion, or an explicit send, proposal-release,
  or account-switch refresh. Intermediate reads preserve spendable, pending, and
  holdings displays. `hasRecentTransactionsData` and `hasRecentTransactionsError`
  own the activity loading state.
- Only completed-sync or explicit-release balance reads enqueue display-only
  snapshots through `walletBalanceCacheProvider`; intermediate reads leave the
  saved snapshot intact. Deletion/reset suspend and drain its writes.
  `ext_vizor_balance_cache` is in the wallet DB and removed with its account;
  writes open existing DB files only and do not invalidate the wallet-summary cache.
- All balance/history queries pass `activeAccountUuid` from `AccountProvider`

**Progress of a new sync job:** a new job shows 0% through its preparation phases (preflight, setup, active UTXO, chain prepare). Once scanning reports progress, the percentage is the job's share of scan work shown as 1-99% (`syncDisplayPercentageProvider`): a scanning job shows at least 1%, since the whole-percent label would round about the first minute of a full restore's scan to 0%. Checking keeps its own fraction, and only a completion shows 100%. A resumed job (relaunch, retry, endpoint fallback, unlock) keeps showing its stored percentage through preparation, including a job whose scan finished before the attempt could complete. After a wallet reset the next wallet's first sync is a new job. The status reads "N% Syncing…"; screen readers announce the same words without the ellipsis.

**Status during a catch-up:** a sync that starts from a completed one (`SyncState.startedFromCompletedSync`; unlock, and a launch with no bootstrap snapshot, restore a completed wallet from the stored status; a catch-up that a failure, a stop or a lock interrupted continues as one, and so does one the app was killed during, since its stored job records that it started from a completed sync (`progress_job_from_completed_sync`, reported by `get_sync_status`) unless its pending work reaches more than 100 blocks below that sync, as an added account's history does (checked when the job is measured and whenever the loop reads new ranges, so an account added during the catch-up counts too); a sync after an account was added is a rescan, not a catch-up) shows the sync status as "Syncing…" without a percentage on Home, the migration status and the desktop sidebar, with the synced look kept (the synced color and bar, no shimmer, and the sidebar's block height following the scan), keeps neither the screen awake nor the keep-awake privacy lock up, and leaves a keep-awake screen already showing "Sync Complete" on it, while it has at most 1,000 blocks to scan (about 21 hours of 75-second blocks) and has run under 10 seconds (`syncShortCatchUpProvider`). Past either limit the percentage shows with the syncing look, and it stays for the rest of that sync job, including its restarts after a failure, an endpoint fallback or a lock, which resume the job with fewer blocks left; a keep-awake screen that showed "Sync Complete" through the catch-up keeps showing it until the attempt ends. The mobile top nav reserves the width of "Vizor is synced" for its label, and percentages use tabular figures, so the label changes without moving the nav. Checking, failures, a failed Tor route and a Tor route still coming up keep their own labels; over a connected Tor route, the catch-up's wait for its first answer does not read as "Connecting to Tor…".
