import Foundation
import BackgroundTasks

@available(iOS 26.0, *)
class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.zcash.zcashWallet.sync"

    /// Stored reference to task's NSProgress — updated from C callback thread (thread-safe).
    private var taskProgress: Progress?

    private init() {}

    func registerBackgroundTask() {
        print("[BGSync] registerBackgroundTask: registering \(Self.taskIdentifier)")
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            print("[BGSync] handler invoked, task type: \(type(of: task))")
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                print("[BGSync] ERROR: task is not BGContinuedProcessingTask, completing as failure")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(continuedTask)
        }
        print("[BGSync] registerBackgroundTask: done")
    }

    private var batchCount: Int64 = 0

    private func handleBackgroundTask(_ task: BGContinuedProcessingTask) {
        print("[BGSync] handleBackgroundTask: started")
        print("[BGSync]   mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")

        // Store progress reference for C callback to update (NSProgress is thread-safe)
        taskProgress = task.progress
        batchCount = 0
        print("[BGSync]   taskProgress stored, totalUnitCount=\(task.progress.totalUnitCount), completedUnitCount=\(task.progress.completedUnitCount)")

        task.expirationHandler = { [weak self] in
            print("[BGSync] EXPIRATION HANDLER CALLED")
            print("[BGSync]   mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")
            self?.taskProgress = nil
            zcash_set_sync_mode(0)  // none → prevents resubmit
            zcash_cancel_sync()
            print("[BGSync]   mode set to 0, cancel sent")
        }

        // Wait for mode=background AND previous sync to finish
        var waitCount = 0
        while zcash_get_sync_mode() != 2 || zcash_is_sync_running() {
            waitCount += 1
            print("[BGSync] waiting... (\(waitCount)) mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")
            Thread.sleep(forTimeInterval: 2.0)
        }
        print("[BGSync] wait complete after \(waitCount) iterations, starting C FFI sync")

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsDir.appendingPathComponent("zcash_wallet.db").path
        print("[BGSync] dbPath=\(dbPath)")

        // Run sync via C FFI (blocking call on background queue)
        let result = zcash_run_full_sync(
            dbPath,
            "https://zec.rocks:443",
            "main",
            { progress in
                // Called from tokio thread — NSProgress is thread-safe
                if #available(iOS 26.0, *) {
                    let mgr = BackgroundSyncManager.shared
                    // Use batch count for completedUnitCount so it always increases.
                    // fully_scanned_height may not advance until contiguous ranges complete,
                    // which makes the system think the task is stalled.
                    mgr.batchCount += 1
                    let estimatedTotalBatches = max(
                        Int64(progress.chain_tip_height - progress.scanned_height) / 100 + mgr.batchCount,
                        mgr.batchCount + 1
                    )
                    mgr.taskProgress?.totalUnitCount = estimatedTotalBatches
                    mgr.taskProgress?.completedUnitCount = mgr.batchCount
                    print("[BGSync] progress: batch=\(mgr.batchCount)/~\(estimatedTotalBatches), scanned=\(progress.scanned_height)/\(progress.chain_tip_height)")
                }

                // Send to Dart via EventChannel (if app is in foreground)
                SyncProgressStreamHandler.shared.sendProgress(progress)
            }
        )

        print("[BGSync] zcash_run_full_sync returned: \(result)")
        print("[BGSync]   mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")

        taskProgress = nil

        // If mode is still background and sync ended normally (not cancelled),
        // resubmit to continue syncing
        if result == 0 && zcash_get_sync_mode() == 2 {
            let resubmitted = startBackgroundSync()
            print("[BGSync] resubmit: \(resubmitted)")
        } else {
            print("[BGSync] no resubmit: result=\(result), mode=\(zcash_get_sync_mode())")
        }

        task.setTaskCompleted(success: result == 0)
        print("[BGSync] task completed, success=\(result == 0)")
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
