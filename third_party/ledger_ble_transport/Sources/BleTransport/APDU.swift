//
//  APDU.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/10/22.
//

import Foundation

public class APDU: Sendable, Receivable {

    public let data: Data                   /// The APDU data to send or receive.
    public var chunks: [Data] = []          /// The APDU data split into frames smaller than `mtuSize`

    static var mtuSize: Int = 153           /// The maximum number of bytes (including the tag and frame index) we can send. This should be updated every time we connect to a new device.

    public var isEmpty: Bool {
        chunks.isEmpty
    }

    public static let inferMTU = APDU(data: [0x08,0x00,0x00,0x00,0x00], preventChunking: true)

    public init(data: [UInt8], preventChunking: Bool = false) {
        let dataReceived = Data(data)
        self.data = dataReceived
        if preventChunking {
            self.chunks = [Data(data)]
        } else {
            self.chunks = self.chunkAPDU(data: dataReceived)
        }
    }

    // Overload to allow passing a String instead of UInt8 since that's what we get from live-common anyway
    public init(raw: String) {
        guard raw.isHexDigit else {
            self.data = Data()
            return
        }
        let dataReceived = Data(raw.UInt8Array())
        self.data = dataReceived
        self.chunks = self.chunkAPDU(data: dataReceived)
    }

    required public init(bluetoothData: Data) throws {
        self.data = bluetoothData
        self.chunks = self.chunkAPDU(data: bluetoothData)
    }

    // When called by BleTransport it will return the current frame to send
    public func toBluetoothData() -> Data {
        return self.chunks[0]
    }

    // Increase index to point to the next frame
    func next() -> Void {
        self.chunks.removeFirst()
    }

    internal func chunkAPDU(data: Data) -> [Data] {
        let apdu: [UInt8] = Array(data)
        var chunks = Array<Data>()
        let size = UInt16(apdu.count)

        let head: [UInt8] = [0x05]     // Tag/Head we need to send for the nano x
        var hi = 0                     // Our current index inside the data
        var ind = UInt16(0)            // Frame counter

        while(hi < size) {
            let maxDataForFrame = ind == 0 ? (APDU.mtuSize - 5) : (APDU.mtuSize - 3)
            var messageData = Data()
            messageData.append(Data(head))
            /// Index is 2 bytes
            messageData.append(withUnsafeBytes(of: ind.bigEndian, { Data($0) }))
            if ind == 0 {
                /// Size is 2 bytes and we only send it in the first frame
                messageData.append(withUnsafeBytes(of: size.bigEndian, { Data($0) }))
            }
            messageData.append(Data(apdu[hi..<min(hi+maxDataForFrame, apdu.count)]))

            // Move forward in the data
            hi += maxDataForFrame
            ind += 1

            // Append the newly created frame to the array representing the apdu.
            chunks.append(messageData)
        }
        return chunks
    }
}

class APDUs: NSObject {
    public static let openBitcoin: [APDU] = [APDU(raw: "e0d8000007426974636f696e")]
}

public extension String {
    func UInt8Array() -> [UInt8] {
        guard self.count % 2 == 0 else { return [] }
        var lo = 0
        let chars = Array(self)
        var out = Array<UInt8>()
        while (lo < self.count) {
            let pair = String(chars[lo])+String(chars[lo+1])
            out.append(UInt8(pair, radix: 16)!)
            lo += 2
        }
        return out
    }

    var isHexDigit: Bool {
        filter(\.isHexDigit).count == count
    }
}

public extension Array where Element == UInt8 {
    func bytesToHex(spacing: String) -> String {
        var hexString: String = ""
        var count = self.count
        for byte in self
        {
            hexString.append(String(format:"%02X", byte))
            count = count - 1
            if count > 0
            {
                hexString.append(spacing)
            }
        }
        return hexString
    }
}

public extension Data {
    func hexEncodedString(uppercase: Bool = false) -> String {
        let format = uppercase ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }
}
