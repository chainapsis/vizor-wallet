//
//  DisconnectionResult.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/9/22.
//

import Foundation

/// Indicates a successful, cancelled, or failed disconnection attempt, where the success case contains the peripheral disconnected from.
public enum DisconnectionResult {
    /// The disconnection is successful, and the disconnected peripheral is captured in the associated value.
    case disconnected(PeripheralIdentifier)
    /// The disconnection has failed unexpectedly with an error.
    case failure(Error)
}
