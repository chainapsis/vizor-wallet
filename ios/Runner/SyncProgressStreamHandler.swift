import Flutter

/// Bridges sync progress from Swift (C FFI callback) to Dart (FlutterEventChannel).
class SyncProgressStreamHandler: NSObject, FlutterStreamHandler {
    static let shared = SyncProgressStreamHandler()
    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    func sendProgress(_ progress: CSyncProgress) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?([
                "scannedHeight": progress.scanned_height,
                "chainTipHeight": progress.chain_tip_height,
                "percentage": progress.percentage,
                "isSyncing": progress.is_syncing,
                "isComplete": progress.is_complete,
                "hasNewTx": progress.has_new_tx,
            ] as [String: Any])
        }
    }
}
