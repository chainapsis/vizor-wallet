import Foundation
import BackgroundTasks

@available(iOS 26.0, *)
class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.zcash.zcashWallet.sync"

    /// Shared progress state updated by C callback, read by task monitor.
    private var latestProgress: CSyncProgress?
    private var syncRunning = false

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
        task.expirationHandler = {
            zcash_cancel_sync()
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsDir.appendingPathComponent("zcash_wallet.db").path

        // Start Dynamic Island
        LiveActivityManager.shared.start()

        // Start a timer to read progress and update task.progress
        syncRunning = true
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let p = self.latestProgress else { return }
            task.progress.totalUnitCount = Int64(p.chain_tip_height)
            task.progress.completedUnitCount = Int64(p.scanned_height)
        }

        // Run sync via C FFI (blocking) — C callback cannot capture context
        let result = zcash_run_full_sync(
            dbPath,
            "https://zec.rocks:443",
            "main",
            { progress in
                // Static-context-safe: update shared state + EventChannel
                if #available(iOS 26.0, *) {
                    BackgroundSyncManager.shared.latestProgress = progress
                }

                LiveActivityManager.shared.update(
                    percentage: progress.percentage,
                    scannedHeight: progress.scanned_height,
                    chainTipHeight: progress.chain_tip_height
                )

                SyncProgressStreamHandler.shared.sendProgress(progress)
            }
        )

        progressTimer.invalidate()
        syncRunning = false
        LiveActivityManager.shared.stop()
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
