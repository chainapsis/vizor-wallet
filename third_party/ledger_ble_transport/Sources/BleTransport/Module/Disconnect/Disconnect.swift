//
//  Disconnect.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/9/22.
//

import CoreBluetooth
import Foundation

/// A disconnection operation.
class Disconnect: TaskOperation {

    var finished: EmptyResponse?

    /// The peripheral this operation is for.
    let peripheral: CBPeripheral

    /// The manager responsible for this operation.
    let manager: CBCentralManager

    /// Callback for the disconnection attempt.
    var callback: ((DisconnectionResult) -> Void)?

    init(peripheral: CBPeripheral, manager: CBCentralManager, callback: ((DisconnectionResult) -> Void)?) {
        self.peripheral = peripheral
        self.manager = manager

        self.callback = callback
    }

    func start() {
        manager.cancelPeripheralConnection(peripheral)
    }

    func didDisconnectPeripheral(peripheral: PeripheralIdentifier) {
        complete(.disconnected(peripheral))
    }

    func complete(_ result: DisconnectionResult) {
        callback?(result)
        callback = nil

        /// We don't call `finished?()` on `Disconnect` because we don't want the queue to advance to the next operation, as soon as the delegate received `didDisconnect` it clears the queue up to the next `Scan` or `Connect` (if there's any)
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }
}
