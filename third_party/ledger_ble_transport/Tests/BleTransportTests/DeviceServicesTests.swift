import CoreBluetooth
import XCTest
@testable import BleTransport

final class DeviceServicesTests: XCTestCase {
    func testDefaultConfigurationIncludesEachSupportedBluetoothModel() {
        let configuration = BleTransportConfiguration.defaultConfig()
        let models = ["0004", "6004", "3004", "8004"] // Nano X, Stax, Flex, Nano Gen5.

        XCTAssertEqual(configuration.services.count, models.count)
        for model in models {
            let prefix = "13d63400-2c97-\(model)"
            let suffix = "4c6564676572"
            let serviceUUID = CBUUID(string: "\(prefix)-0000-\(suffix)")
            let service = configuration.serviceMatching(serviceUUID: serviceUUID)
            XCTAssertNotNil(service, "Missing scan service for \(model)")
            XCTAssertEqual(service?.notify.uuid, CBUUID(string: "\(prefix)-0001-\(suffix)"))
            XCTAssertEqual(service?.writeWithResponse.uuid, CBUUID(string: "\(prefix)-0002-\(suffix)"))
            XCTAssertEqual(service?.writeWithoutResponse.uuid, CBUUID(string: "\(prefix)-0003-\(suffix)"))
        }
    }
}
