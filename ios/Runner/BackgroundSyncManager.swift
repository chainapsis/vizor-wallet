import Foundation
import BackgroundTasks

@available(iOS 26.0, *)
class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.zcash.zcashWallet.sync"

    private var taskProgress: Progress?
    private var batchCount: Int64 = 0
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

        taskProgress = task.progress
        batchCount = 0

        // Wait for mode=background AND previous sync to finish
        var waitCount = 0
        let maxWait = 60 // 120 seconds
        while zcash_get_sync_mode() != 2 || zcash_is_sync_running() {
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

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsDir.appendingPathComponent("zcash_wallet.db").path

        // Heartbeat on global .utility queue — syncQueue is blocked by zcash_run_full_sync
        let hb = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        hb.schedule(deadline: .now() + 5.0, repeating: 5.0)
        hb.setEventHandler { [weak self] in
            guard let progress = self?.taskProgress else { return }
            progress.completedUnitCount += 1
            print("[BGSync] heartbeat: completedUnitCount=\(progress.completedUnitCount)")
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
                    mgr.batchCount += 1
                    let completed = mgr.batchCount * 100
                    let remaining = Int64(progress.chain_tip_height - progress.scanned_height)
                    mgr.taskProgress?.completedUnitCount = completed
                    mgr.taskProgress?.totalUnitCount = completed + remaining
                    print("[BGSync] batch \(mgr.batchCount): completed=\(completed), total=\(completed + remaining), scanned=\(progress.scanned_height)/\(progress.chain_tip_height)")
                }
                SyncProgressStreamHandler.shared.sendProgress(progress)
            }
        )

        heartbeat?.cancel()
        heartbeat = nil
        taskProgress = nil

        print("[BGSync] zcash_run_full_sync returned: \(result)")

        if result == 0 && zcash_get_sync_mode() == 2 {
            let resubmitted = startBackgroundSync()
            print("[BGSync] resubmit: \(resubmitted)")
        } else {
            print("[BGSync] no resubmit: result=\(result), mode=\(zcash_get_sync_mode())")
        }

        return result
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
}
