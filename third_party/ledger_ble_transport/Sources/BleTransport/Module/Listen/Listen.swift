//
//  Listen.swift
//
//
//  Created by Dante Puglisi on 8/5/22.
//

import Foundation
import CoreBluetooth

class Listen: TaskOperation {

    var finished: EmptyResponse?

    /// The peripheral this operation is for.
    let peripheral: CBPeripheral

    /// The characteristic to listen to.
    let characteristicIdentifier: CharacteristicIdentifier

    /// Whether to start listening or to stop listening.
    let value: Bool

    /// Callback for the attempt to start or stop listening, not the values received from the characteristic.
    private var callback: ((WriteResult) -> Void)?

    /// Internal reference to the CBCharacteristic.
    private var characteristic: CBCharacteristic?

    deinit {
        //print("Deinited Listen")
    }

    init(characteristicIdentifier: CharacteristicIdentifier, peripheral: CBPeripheral, value: Bool, callback: @escaping (WriteResult) -> Void) {

        self.characteristicIdentifier = characteristicIdentifier
        self.peripheral = peripheral
        self.value = value
        self.callback = callback
    }

    func start() {
        guard
            let service = peripheral.service(with: characteristicIdentifier.service.uuid),
            let characteristic = service.characteristic(with: characteristicIdentifier.uuid)
        else {
            complete(withError: DiscoverCharacteristicError.missingCharacteristic(characteristicIdentifier))
            return
        }

        peripheral.setNotifyValue(value, for: characteristic)

        self.characteristic = characteristic

        /*if value {
            print("Will start listening to \(characteristicIdentifier.description) on \(peripheral.name ?? peripheral.identifier.uuidString).")
        } else {
            print("Will stop listening to \(characteristicIdentifier.description) on \(peripheral.name ?? peripheral.identifier.uuidString).")
        }*/
    }

    func complete(withError error: Error?) {
        if let error = error {
            callback?(.failure(error))
        } else {
            callback?(.success)
        }
        callback = nil
        finished?()
    }

    func didUpdateCharacteristicNotificationState(error: Error?) {
        /*if value {
            print("Listening to \(characteristicIdentifier.description) on \(peripheral.name ?? peripheral.identifier.uuidString).")
        } else {
            print("Stopped listening to \(characteristicIdentifier.description) on \(peripheral.name ?? peripheral.identifier.uuidString).")
        }*/

        complete(withError: error)
    }
}
