//
//  File.swift
//
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

/// A model capturing what is found from a scan callback.
public struct ScanDiscovery {
    /// The unique, persistent identifier associated with the peer.
    public let peripheralIdentifier: PeripheralIdentifier

    /// The advertisement packet the discovered peripheral is sending.
    public let advertisementPacket: [String: Any]

    /// The signal strength of the peripheral discovered.
    public let rssi: Int
}
