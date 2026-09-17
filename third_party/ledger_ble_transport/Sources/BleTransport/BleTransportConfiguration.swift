//
//  BleTransportConfiguration.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/10/22.
//

import Foundation
import CoreBluetooth

@objc
public class BleTransportConfiguration: NSObject {
    let services: [BleService]

    var connectedService: BleService?

    public init(services: [BleService]) {
        self.services = services
    }

    static func defaultConfig() -> BleTransportConfiguration {
        let nanoXServiceUUID = "13D63400-2C97-0004-0000-4C6564676572"
        let nanoXNotifyCharacteristicUUID = "13d63400-2c97-0004-0001-4c6564676572"
        let nanoXWriteWithResponseCharacteristicUUID = "13d63400-2c97-0004-0002-4c6564676572"
        let nanoXWriteWithoutResponseCharacteristicUUID = "13d63400-2c97-0004-0003-4c6564676572"

        let nanoFTSServiceUUID = "13d63400-2c97-6004-0000-4c6564676572"
        let nanoFTSNotifyCharacteristicUUID = "13d63400-2c97-6004-0001-4c6564676572"
        let nanoFTSWriteWithResponseCharacteristicUUID = "13d63400-2c97-6004-0002-4c6564676572"
        let nanoFTSWriteWithoutResponseCharacteristicUUID = "13d63400-2c97-6004-0003-4c6564676572"

        let nanoXService = BleService(serviceUUID: nanoXServiceUUID, notifyUUID: nanoXNotifyCharacteristicUUID, writeWithResponseUUID: nanoXWriteWithResponseCharacteristicUUID, writeWithoutResponseUUID: nanoXWriteWithoutResponseCharacteristicUUID)
        let nanoFTSService = BleService(serviceUUID: nanoFTSServiceUUID, notifyUUID: nanoFTSNotifyCharacteristicUUID, writeWithResponseUUID: nanoFTSWriteWithResponseCharacteristicUUID, writeWithoutResponseUUID: nanoFTSWriteWithoutResponseCharacteristicUUID)

        return BleTransportConfiguration(services: [nanoXService, nanoFTSService])
    }

    public func serviceMatching(serviceUUID: CBUUID) -> BleService? {
        return services.first(where: { configService in serviceUUID == configService.service.uuid })
    }
}

@objc
public class BleService: NSObject {
    let service: ServiceIdentifier

    let notify: CharacteristicIdentifier
    let writeWithResponse: CharacteristicIdentifier
    let writeWithoutResponse: CharacteristicIdentifier

    public init(serviceUUID: String, notifyUUID: String, writeWithResponseUUID: String, writeWithoutResponseUUID: String) {
        let service = ServiceIdentifier(uuid: serviceUUID)
        self.notify = CharacteristicIdentifier(uuid: notifyUUID, service: service)
        self.writeWithResponse = CharacteristicIdentifier(uuid: writeWithResponseUUID, service: service)
        self.writeWithoutResponse = CharacteristicIdentifier(uuid: writeWithoutResponseUUID, service: service)
        self.service = service
    }

    func writeCharacteristic(canWriteWithoutResponse: Bool) -> CharacteristicIdentifier {
        return canWriteWithoutResponse ? writeWithoutResponse : writeWithResponse
    }

    static func == (lhs: BleService, rhs: BleService) -> Bool {
        return lhs.service.uuid == rhs.service.uuid
    }
}
