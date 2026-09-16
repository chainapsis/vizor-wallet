//
//  Sendable.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/3/22.
//

import Foundation

/// Protocol to indicate that a type can be sent via the Bluetooth connection.
public protocol Sendable {

    /**
     A place to implement your serialization logic.
     */
    func toBluetoothData() -> Data
}
