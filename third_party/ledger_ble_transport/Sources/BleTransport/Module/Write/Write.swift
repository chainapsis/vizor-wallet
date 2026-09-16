//
//  Write.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/3/22.
//

import Foundation
import CoreBluetooth

class Write<T: Sendable>: TaskOperation {

    var finished: EmptyResponse?

    /// The peripheral this operation is for.
    let peripheral: CBPeripheral

    /// The characteristic to write to.
    let characteristicIdentifier: CharacteristicIdentifier

    /// The value to write.
    let value: T

    // Type of write
    let writeType: CBCharacteristicWriteType

    /// Callback for the write attempt.
    private var callback: ((WriteResult) -> Void)?

    init(characteristicIdentifier: CharacteristicIdentifier, peripheral: CBPeripheral, value: T, writeType: CBCharacteristicWriteType = .withResponse, callback: @escaping (WriteResult) -> Void) {
        self.characteristicIdentifier = characteristicIdentifier
        self.peripheral = peripheral
        self.value = value
        self.writeType = writeType
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

        let property: CBCharacteristicProperties = writeType == .withoutResponse ? .writeWithoutResponse : .write
        guard characteristic.properties.contains(property) else {
            complete(withError: DiscoverCharacteristicError.missingCharacteristicProperty(property))
            return
        }

        peripheral.writeValue(value.toBluetoothData(), for: characteristic, type: writeType)

        //print("Started write to \(characteristicIdentifier.description) on \(peripheral.identifier).")

        if writeType == .withoutResponse {
            didWriteValue(toCharacteristic: characteristic)
        }
    }

    func didWriteValue(toCharacteristic: CBCharacteristic) {
        if toCharacteristic.uuid != characteristicIdentifier.uuid {
            preconditionFailure("Expecting write to \(characteristicIdentifier.description), but actually wrote to \(toCharacteristic.uuid)")
        }

        //print("Write to \(characteristicIdentifier.description) on \(peripheral.identifier) is successful.")

        complete(withError: nil)
    }

    func didWriteError(_ error: Error) {
        //print("Failed writing to \(characteristicIdentifier.description) on \(peripheral.identifier) with error: \(error.localizedDescription)")

        complete(withError: error)
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
}
