import Foundation
import BackgroundTasks

@available(iOS 26.0, *)
class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.zcash.zcashWallet.sync"

    /// Stored reference to task's NSProgress — updated from C callback thread (thread-safe).
    private var taskProgress: Progress?
    private var batchCount: Int64 = 0
    private var heartbeat: DispatchSourceTimer?

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

    private func handleBackgroundTask(_ task: BGContinuedProcessingTask) {
        print("[BGSync] handleBackgroundTask: started")
        print("[BGSync]   mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")

        taskProgress = task.progress
        batchCount = 0

        task.expirationHandler = { [weak self] in
            print("[BGSync] EXPIRATION HANDLER CALLED")
            print("[BGSync]   mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")
            self?.heartbeat?.cancel()
            self?.heartbeat = nil
            self?.taskProgress = nil
            zcash_set_sync_mode(0)
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

        // Heartbeat timer: increment completedUnitCount every 5s to prevent OS stalled detection.
        // Actual batch callbacks jump by 100, heartbeats fill in between with +1.
        let hb = DispatchSource.makeTimerSource(queue: .global())
        hb.schedule(deadline: .now() + 5.0, repeating: 5.0)
        hb.setEventHandler { [weak self] in
            guard let self, let progress = self.taskProgress else { return }
            progress.completedUnitCount += 1
            print("[BGSync] heartbeat: completedUnitCount=\(progress.completedUnitCount)")
        }
        hb.resume()
        heartbeat = hb

        // Run sync via C FFI (blocking call on background queue)
        let result = zcash_run_full_sync(
            dbPath,
            "https://zec.rocks:443",
            "main",
            { progress in
                if #available(iOS 26.0, *) {
                    let mgr = BackgroundSyncManager.shared
                    mgr.batchCount += 1

                    // Jump completedUnitCount to batchCount * 100 (actual blocks processed)
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

        print("[BGSync] zcash_run_full_sync returned: \(result)")
        print("[BGSync]   mode=\(zcash_get_sync_mode()), is_running=\(zcash_is_sync_running())")

        taskProgress = nil

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
