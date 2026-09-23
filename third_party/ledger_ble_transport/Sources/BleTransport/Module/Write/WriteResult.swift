//
//  WriteResult.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/3/22.
//

import Foundation
import CoreBluetooth

/// Indicates a successful, cancelled, or failed write attempt.
public enum WriteResult {
    /// The write is successful.
    case success
    /// The write has failed unexpectedly with an error.
    case failure(Error)
}
