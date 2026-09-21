//
//  ConnectionResult.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

/// Indicates a successful, cancelled, or failed connection attempt, where the success case contains the peripheral connected to.
public enum ConnectionResult {
    /// The connection is successful, and the peripheral connected is captured in the associated value.
    case success(CBPeripheral)
    /// The connection has failed unexpectedly with an error.
    case failure(Error)
}
