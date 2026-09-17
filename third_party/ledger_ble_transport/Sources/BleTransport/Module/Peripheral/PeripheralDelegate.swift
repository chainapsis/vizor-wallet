//
//  PeripheralDelegate.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/4/22.
//

import Foundation
import CoreBluetooth

protocol PeripheralDelegate: AnyObject {
    func requestStartOperation(_ operation: TaskOperation)
    func didDiscoverServices()
    func didDiscoverCharacteristics()
    func didUpdateCharacteristicNotificationState(error: Error?)
    func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?)
}
