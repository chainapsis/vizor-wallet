import Foundation
import BackgroundTasks

@available(iOS 26.0, *)
class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.zcash.zcashWallet.sync"

    private var taskProgress: Progress?
    private var heartbeat: DispatchSourceTimer?

    /// Sync work runs on this .utility queue so Rust inherits the QoS.
    private let syncQueue = DispatchQueue(label: "com.zcash.sync", qos: .utility)

    private init() {}

    func registerBackgroundTask() {
        print("[BGSync] registerBackgroundTask: registering \(Self.taskIdentifier)")
        // using: nil — so expirationHandler can run on a different queue
        // (if using: syncQueue, Thread.sleep blocks the queue and expirationHandler deadlocks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            print("[BGSync] handler invoked, task type: \(type(of: task))")
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                print("[BGSync] ERROR: task is not BGContinuedProcessingTask")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(continuedTask)
        }
        print("[BGSync] registerBackgroundTask: done")
    }

    private func handleBackgroundTask(_ task: BGContinuedProcessingTask) {
        print("[BGSync] handleBackgroundTask: started")

        let semaphore = DispatchSemaphore(value: 0)
        var syncResult: Int32 = 1

        task.expirationHandler = { [weak self] in
            print("[BGSync] EXPIRATION HANDLER CALLED")
            self?.heartbeat?.cancel()
            self?.heartbeat = nil
            self?.taskProgress = nil
            zcash_set_sync_mode(0)
            zcash_cancel_sync()
            print("[BGSync]   mode set to 0, cancel sent")
        }

        // Run sync on .utility queue — Rust tokio current_thread inherits this QoS
        syncQueue.async { [weak self] in
            guard let self else { semaphore.signal(); return }
            syncResult = self.runSync(task: task)
            semaphore.signal()
        }

        // Handler thread waits here — does NOT block syncQueue
        semaphore.wait()

        task.setTaskCompleted(success: syncResult == 0)
        print("[BGSync] task completed, success=\(syncResult == 0)")
    }

    private func runSync(task: BGContinuedProcessingTask) -> Int32 {
        print("[BGSync] runSync: mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")

        if zcash_get_sync_mode() != 2 {
            print("[BGSync] runSync: background mode no longer requested, exiting without work")
            return 0
        }

        taskProgress = task.progress

        // Wait for any previous sync to finish. If background mode is
        // no longer requested while waiting, exit immediately rather
        // than burning the BG task budget on a doomed handoff.
        var waitCount = 0
        let maxWait = 60 // 120 seconds
        while zcash_is_sync_running() {
            if zcash_get_sync_mode() != 2 {
                print("[BGSync] runSync: mode changed while waiting, exiting without work")
                taskProgress = nil
                return 0
            }
            waitCount += 1
            if waitCount > maxWait {
                print("[BGSync] ERROR: timed out waiting for sync conditions")
                taskProgress = nil
                return 1
            }
            print("[BGSync] waiting... (\(waitCount)/\(maxWait)) mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")
            Thread.sleep(forTimeInterval: 2.0)
        }
        print("[BGSync] wait complete after \(waitCount) iterations")

        let dbPath: String
        do {
            dbPath = try walletDbPath()
        } catch {
            print("[BGSync] ERROR: failed to resolve db path: \(error)")
            taskProgress = nil
            return 1
        }

        // Heartbeat: nudge completedUnitCount every 5s to signal "alive" to OS.
        // Uses percentage * 10000 as base, heartbeat adds small increments between batches.
        let hb = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        hb.schedule(deadline: .now() + 5.0, repeating: 5.0)
        hb.setEventHandler { [weak self] in
            guard let tp = self?.taskProgress else { return }
            // Small nudge — must be less than a batch jump to avoid overtaking
            if tp.completedUnitCount < tp.totalUnitCount {
                tp.completedUnitCount += 1
            }
            print("[BGSync] heartbeat: \(tp.completedUnitCount)/\(tp.totalUnitCount)")
        }
        hb.resume()
        heartbeat = hb

        // C FFI sync — blocks this thread (.utility QoS)
        let result = zcash_run_full_sync(
            dbPath,
            "https://zec.rocks:443",
            "main",
            { progress in
                if #available(iOS 26.0, *) {
                    let mgr = BackgroundSyncManager.shared
                    // Scale to 10000 for fine-grained NSProgress reporting
                    let completed = Int64(progress.percentage * 10000)
                    mgr.taskProgress?.totalUnitCount = 10000
                    mgr.taskProgress?.completedUnitCount = completed
                    print("[BGSync] batch: \(String(format: "%.1f", progress.percentage * 100))% (\(progress.scanned_height)/\(progress.chain_tip_height))")

                    // Update Dynamic Island via DynamicIslandManager
                    DynamicIslandManager.shared.showSyncProgress(
                        percentage: progress.percentage
                    )
                }
                SyncProgressStreamHandler.shared.sendProgress(progress)
            }
        )

        heartbeat?.cancel()
        heartbeat = nil
        taskProgress = nil

        print("[BGSync] zcash_run_full_sync returned: \(result)")

        // End Dynamic Island if sync is fully done (not resubmitting)
        if !(result == 0 && zcash_get_sync_mode() == 2) {
            DynamicIslandManager.shared.endActivity()
        }

        if result == 0 && zcash_get_sync_mode() == 2 {
            let resubmitted = startBackgroundSync()
            print("[BGSync] resubmit: \(resubmitted)")
        } else {
            print("[BGSync] no resubmit: result=\(result), mode=\(zcash_get_sync_mode())")
        }

        return result
    }

    private func walletDbPath() throws -> String {
        try resolveWalletDbPath()
    }

    func startBackgroundSync() -> Bool {
        print("[BGSync] startBackgroundSync: submitting BGContinuedProcessingTaskRequest")
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "Syncing Zcash Wallet",
            subtitle: "Scanning blockchain blocks"
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGSync] startBackgroundSync: submitted OK")
            return true
        } catch {
            print("[BGSync] startBackgroundSync: FAILED: \(error)")
            return false
        }
    }

    func stopBackgroundSync() -> Bool {
        print("[BGSync] stopBackgroundSync: cancelling pending task requests")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        return true
    }
}
