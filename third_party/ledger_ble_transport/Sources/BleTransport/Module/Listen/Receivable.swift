//
//  Receivable.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/5/22.
//

import Foundation

/// Protocol to indicate that a type can be received from the Bluetooth connection.
public protocol Receivable {

    /**
     A place to implement your deserialization logic.

     - Parameter bluetoothData: The data received over Bluetooth and needing to be deserialized.
     */
    init(bluetoothData: Data) throws

}
