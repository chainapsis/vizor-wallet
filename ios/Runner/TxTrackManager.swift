import BackgroundTasks
import Foundation

/// Manages TX tracking via BGContinuedProcessingTask.
/// Polls lightwalletd to detect when pending transactions are mined or expired.
@available(iOS 26.0, *)
class TxTrackManager {
    static let shared = TxTrackManager()
    static let taskIdentifier = "com.zcash.zcashWallet.txtrack"

    private let trackQueue = DispatchQueue(label: "com.zcash.txtrack", qos: .utility)
    private let pollInterval: TimeInterval = 5.0
    private let resultDisplayDelay: TimeInterval = 5.0
    private let lightwalletdUrl = "https://zec.rocks:443"
    private var cancelled = false

    private init() {}

    func registerTask() {
        print("[TxTrack] registering \(Self.taskIdentifier)")
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            print("[TxTrack] handler invoked")
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                print("[TxTrack] ERROR: not BGContinuedProcessingTask")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleTask(continuedTask)
        }
        print("[TxTrack] registered")
    }

    func startTxTracking() -> Bool {
        print("[TxTrack] submitting task request")
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "Tracking Transaction",
            subtitle: "Waiting for confirmation"
        )
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[TxTrack] submitted OK")
            return true
        } catch {
            print("[TxTrack] submit FAILED: \(error)")
            return false
        }
    }

    private func handleTask(_ task: BGContinuedProcessingTask) {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        cancelled = false

        task.expirationHandler = { [weak self] in
            print("[TxTrack] EXPIRATION")
            self?.cancelled = true
            semaphore.signal()
        }

        trackQueue.async { [weak self] in
            guard let self else { semaphore.signal(); return }
            success = self.runTracking()
            semaphore.signal()
        }

        semaphore.wait()
        task.setTaskCompleted(success: success)
        print("[TxTrack] task completed, success=\(success)")
    }

    private func runTracking() -> Bool {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsDir.appendingPathComponent("zcash_wallet.db").path

        // Get initial pending TXs
        var pendingBuf = [CPendingTx](repeating: CPendingTx(), count: 16)
        let count = zcash_get_pending_txs(dbPath, &pendingBuf, 16)

        if count <= 0 {
            print("[TxTrack] no pending TXs, exiting")
            return true
        }

        var pending: [(txid: String, expiryHeight: UInt64)] = []
        for i in 0..<Int(count) {
            let tx = pendingBuf[i]
            let txid = withUnsafePointer(to: tx.txid_hex) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 65) {
                    String(cString: $0)
                }
            }
            pending.append((txid: txid, expiryHeight: tx.expiry_height))
        }

        print("[TxTrack] tracking \(pending.count) transaction(s)")
        DynamicIslandManager.shared.showTxTracking(pendingCount: pending.count)

        var confirmed = 0
        var expired = 0

        // Poll loop
        while !pending.isEmpty && !cancelled {
            Thread.sleep(forTimeInterval: pollInterval)
            if cancelled { break }

            var stillPending: [(txid: String, expiryHeight: UInt64)] = []

            for tx in pending {
                let status = zcash_check_tx_status(lightwalletdUrl, tx.txid)
                print("[TxTrack] \(tx.txid.prefix(16))...: status=\(status)")

                if status > 0 {
                    // Mined
                    confirmed += 1
                    print("[TxTrack] \(tx.txid.prefix(16))... confirmed at height \(status)")
                } else if status == 0 {
                    // Still pending — check expiry
                    // We can't easily get chain tip here without another gRPC call,
                    // so we rely on the wallet DB's expired_unmined flag on next check
                    let currentCount = zcash_get_pending_tx_count(dbPath)
                    if currentCount >= 0 && currentCount < Int32(pending.count) {
                        // Something changed — a TX may have expired via DB update
                        // Re-fetch pending list
                        let refreshCount = zcash_get_pending_txs(dbPath, &pendingBuf, 16)
                        if refreshCount >= 0 {
                            let refreshSet = Set((0..<Int(refreshCount)).map { i -> String in
                                withUnsafePointer(to: pendingBuf[i].txid_hex) { ptr in
                                    ptr.withMemoryRebound(to: CChar.self, capacity: 65) {
                                        String(cString: $0)
                                    }
                                }
                            })
                            if !refreshSet.contains(tx.txid) {
                                expired += 1
                                print("[TxTrack] \(tx.txid.prefix(16))... expired")
                                continue
                            }
                        }
                    }
                    stillPending.append(tx)
                } else {
                    // Error — keep tracking
                    stillPending.append(tx)
                }
            }

            pending = stillPending

            DynamicIslandManager.shared.updateTxStatus(
                confirmed: confirmed,
                expired: expired,
                remaining: pending.count
            )
        }

        print("[TxTrack] all TXs resolved: \(confirmed) confirmed, \(expired) expired")

        // Show result briefly before ending
        Thread.sleep(forTimeInterval: resultDisplayDelay)
        DynamicIslandManager.shared.restoreSyncDisplay()

        return true
    }
}
