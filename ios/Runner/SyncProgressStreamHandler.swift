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

    func sendEvent(_ event: CSyncEventV2) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?([
                "kind": event.kind,
                "runId": event.run_id,
                "sequence": event.sequence,
                "scannedHeight": event.scanned_height,
                "chainTipHeight": event.chain_tip_height,
                "percentage": event.percentage,
                "displayTargetPercentage": event.display_target_percentage,
                "displayTargetBlocks": event.display_target_blocks,
                "hasNewTx": event.has_new_tx,
                "phase": event.phase.map { String(cString: $0) } ?? "",
            ] as [String: Any])
        }
    }
}
