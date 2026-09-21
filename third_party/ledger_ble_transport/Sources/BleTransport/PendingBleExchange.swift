import Foundation

/// State belonging to exactly one APDU. The transport serializes access on main.
/// Dropping this object discards partial bytes; completion is consumed once.
final class PendingBleExchange {
    private var completion: ((Result<String, BleTransportError>) -> Void)?
    private var bytes = Data()
    private var expectedLength: Int?
    private var sequence = 0

    init(completion: @escaping (Result<String, BleTransportError>) -> Void) {
        self.completion = completion
    }

    func receive(_ frame: Data) -> Result<String, BleTransportError>? {
        guard completion != nil else { return nil }
        let header = sequence == 0 ? 5 : 3
        guard frame.count >= header, frame[0] == 0x05,
              (Int(frame[1]) << 8 | Int(frame[2])) == sequence else {
            return .failure(.readError(description: "Invalid Ledger response frame"))
        }
        if sequence == 0 { expectedLength = Int(frame[3]) << 8 | Int(frame[4]) }
        bytes.append(frame.dropFirst(header))
        sequence += 1
        guard let expectedLength, bytes.count <= expectedLength else {
            return .failure(.readError(description: "Invalid Ledger response length"))
        }
        return bytes.count == expectedLength ? .success(bytes.hexEncodedString()) : nil
    }

    func finish(_ result: Result<String, BleTransportError>) {
        let callback = completion
        completion = nil
        bytes.removeAll()
        expectedLength = nil
        sequence = 0
        callback?(result)
    }
}
