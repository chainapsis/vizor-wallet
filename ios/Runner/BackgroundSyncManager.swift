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
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(continuedTask)
        }
    }

    private func handleBackgroundTask(_ task: BGContinuedProcessingTask) {
        // Store progress reference for C callback to update (NSProgress is thread-safe)
        taskProgress = task.progress

        task.expirationHandler = { [weak self] in
            self?.taskProgress = nil
            zcash_set_sync_mode(0)  // none → prevents resubmit
            zcash_cancel_sync()
        }

        // Wait for mode=background AND previous sync to finish
        while zcash_get_sync_mode() != 2 || zcash_is_sync_running() {
            Thread.sleep(forTimeInterval: 2.0)
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsDir.appendingPathComponent("zcash_wallet.db").path

        // Run sync via C FFI (blocking call on background queue)
        let result = zcash_run_full_sync(
            dbPath,
            "https://zec.rocks:443",
            "main",
            { progress in
                // Called from tokio thread — NSProgress is thread-safe
                if #available(iOS 26.0, *) {
                    let mgr = BackgroundSyncManager.shared
                    mgr.taskProgress?.totalUnitCount = Int64(progress.chain_tip_height)
                    mgr.taskProgress?.completedUnitCount = Int64(progress.scanned_height)
                }

                // Send to Dart via EventChannel (if app is in foreground)
                SyncProgressStreamHandler.shared.sendProgress(progress)
            }
        )

        taskProgress = nil

        // If mode is still background and sync ended normally (not cancelled),
        // resubmit to continue syncing
        if result == 0 && zcash_get_sync_mode() == 2 {
            _ = startBackgroundSync()
        }

        task.setTaskCompleted(success: result == 0)
    }

    func startBackgroundSync() -> Bool {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "Syncing Zcash Wallet",
            subtitle: "Scanning blockchain blocks"
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            print("BackgroundSync: failed to submit: \(error)")
            return false
        }
    }
}
