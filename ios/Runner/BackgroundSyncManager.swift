import Foundation
import BackgroundTasks

class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.zcash.zcashWallet.sync"

    private init() {}

    func registerBackgroundTask() {
        if #available(iOS 17.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.taskIdentifier,
                using: nil
            ) { task in
                self.handleBackgroundTask(task)
            }
        }
    }

    private func handleBackgroundTask(_ task: BGTask) {
        task.expirationHandler = {
            zcash_cancel_sync()
        }

        // Get paths
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsDir.appendingPathComponent("zcash_wallet.db").path
        let cachePath = documentsDir.appendingPathComponent("zcash_cache").path

        // Create cache dir if needed
        try? FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true)

        // Start Dynamic Island
        if #available(iOS 16.1, *) {
            LiveActivityManager.shared.start()
        }

        // Run sync via C FFI (blocking)
        let result = zcash_run_full_sync(
            dbPath,
            cachePath,
            "https://zec.rocks:443",
            "main",
            { progress in
                // Update Dynamic Island
                if #available(iOS 16.1, *) {
                    LiveActivityManager.shared.update(
                        percentage: progress.percentage,
                        scannedHeight: progress.scanned_height,
                        chainTipHeight: progress.chain_tip_height
                    )
                }

                // Send to Dart via EventChannel (if app is in foreground)
                SyncProgressStreamHandler.shared.sendProgress(progress)
            }
        )

        // Stop Dynamic Island
        if #available(iOS 16.1, *) {
            LiveActivityManager.shared.stop()
        }

        task.setTaskCompleted(success: result == 0)
    }

    func startBackgroundSync() -> Bool {
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false

            do {
                try BGTaskScheduler.shared.submit(request)
                return true
            } catch {
                print("BackgroundSync: failed to submit: \(error)")
                return false
            }
        }
        return false
    }

    func isAvailable() -> Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
}
