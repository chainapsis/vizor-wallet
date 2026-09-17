import XCTest
import CoreBluetooth
@testable import BleTransport

final class RecoveryTests: XCTestCase {
    @MainActor
    private func connected(_ radio: Radio, timeout: TimeInterval = 60) async -> BleTransport {
        let transport = BleTransport(configuration: nil, debugMode: false, module: radio, handshakeTimeout: timeout)
        let ready = expectation(description: "connected")
        transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in ready.fulfill() }, failure: { XCTFail("\($0)") })
        await fulfillment(of: [ready], timeout: 2)
        return transport
    }

    @MainActor
    func testDisconnectSettlesExchangeOnceAndDiscardsPartialBytes() async {
        let radio = Radio()
        let transport = await connected(radio)
        var results = 0
        let failed = expectation(description: "pending exchange failed")
        transport.exchange(apdu: APDU(data: [0xb0, 1, 0, 0])) { result in
            results += 1
            if case .success = result { XCTFail("disconnected exchange succeeded") }
            failed.fulfill()
        }
        await Task.yield()
        // Partial response then a real radio disconnect, without an APDU reply.
        radio.deliver([5, 0, 0, 0, 4, 0xaa])
        let oldListener = radio.listener!
        radio.loseConnection()
        await fulfillment(of: [failed], timeout: 2)
        let ready = expectation(description: "reconnected")
        transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in ready.fulfill() }, failure: { XCTFail("\($0)") })
        await fulfillment(of: [ready], timeout: 2)
        let response = expectation(description: "fresh response")
        transport.exchange(apdu: APDU(data: [0xb0, 1, 0, 0])) { result in
            XCTAssertEqual(try? result.get(), "9000")
            response.fulfill()
        }
        await Task.yield()
        oldListener(Data([5, 0, 1, 0xbb, 0x90, 0]))
        radio.deliver([5, 0, 0, 0, 2, 0x90, 0])
        await fulfillment(of: [response], timeout: 2)
        XCTAssertEqual(results, 1)
    }

    @MainActor
    func testAbortWaitsForPhysicalDisconnectAndIgnoresLateResponse() async {
        let radio = Radio()
        let transport = await connected(radio)
        radio.deferDisconnect = true
        var results = 0
        transport.exchange(apdu: APDU(data: [0xb0, 1, 0, 0])) { result in
            results += 1
            if case .success = result { XCTFail("aborted exchange succeeded") }
        }
        await Task.yield()
        transport.abortExchange()
        await Task.yield()
        XCTAssertEqual(radio.cancellations, 1)
        radio.deliver([5, 0, 0, 0, 2, 0x90, 0])
        XCTAssertEqual(results, 0)
        let busy = expectation(description: "exchange ownership retained")
        transport.exchange(apdu: APDU(data: [0xb0, 1, 0, 0])) { result in
            guard case .failure(.pendingActionOnDevice) = result else { XCTFail("not busy"); return }
            busy.fulfill()
        }
        await fulfillment(of: [busy], timeout: 2)
        radio.loseConnection()
        radio.loseConnection()
        XCTAssertEqual(results, 1)
    }

    @MainActor
    func testDisconnectCompletionWaitsForRadioTeardown() async {
        let radio = Radio()
        let transport = await connected(radio)
        radio.deferDisconnect = true
        var finished = false
        transport.disconnect { error in XCTAssertNil(error); finished = true }
        XCTAssertFalse(finished)
        transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in XCTFail("overlap") }, failure: { _ in })
        XCTAssertEqual(radio.connects, 1)
        radio.loseConnection()
        XCTAssertTrue(finished)
    }

    @MainActor
    func testMtuFailureAndTimeoutFinishConnectAndPermitRecovery() async {
        for failsWrite in [true, false] {
            let radio = Radio()
            radio.answerMtu = false
            radio.failWrite = failsWrite
            let transport = BleTransport(configuration: nil, debugMode: false, module: radio, handshakeTimeout: 0.01)
            let failed = expectation(description: "handshake failed")
            var failures = 0
            transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in XCTFail("handshake succeeded") }, failure: { _ in failures += 1; failed.fulfill() })
            await fulfillment(of: [failed], timeout: 2)
            XCTAssertFalse(transport.isConnected)
            radio.answerMtu = true
            radio.failWrite = false
            let ready = expectation(description: "recovered handshake")
            transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in ready.fulfill() }, failure: { XCTFail("\($0)") })
            await fulfillment(of: [ready], timeout: 2)
            XCTAssertEqual(failures, 1)
        }
    }

    @MainActor
    func testDisconnectAlsoFinishesQueuedDisconnectAndEmptyQueueDrain() async {
        let radio = Radio()
        let transport = await connected(radio)
        let failed = expectation(description: "exchange failed")
        transport.exchange(apdu: APDU(data: [0xb0, 1, 0, 0])) { result in
            if case .success = result { XCTFail("disconnected exchange succeeded") }
            failed.fulfill()
        }
        let disconnected = expectation(description: "queued disconnect")
        transport.disconnect { error in XCTAssertNil(error); disconnected.fulfill() }
        radio.loseConnection()
        await fulfillment(of: [failed, disconnected], timeout: 2)
        let queue = Queue()
        let drained = expectation(description: "empty queue drained")
        queue.removeAllUpToScanOrConnect { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
    }

    @MainActor
    func testConnectTimeoutKeepsQueueUntilRadioDrains() async {
        let timedOut = expectation(description: "timeout returned")
        var results = 0
        var cancellations = 0
        var drains = 0
        let attempt = Connect(timeout: .seconds(0.01), start: {}, cancel: { cancellations += 1 }) { result in
            results += 1
            if case .failure(let error) = result {
                guard case ConnectionError.timedOut = error else { XCTFail("unexpected error"); return }
            } else { XCTFail("timed out connect succeeded") }
            timedOut.fulfill()
        }
        attempt.finished = { drains += 1 }
        attempt.start()
        await fulfillment(of: [timedOut], timeout: 2)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(drains, 0)
        attempt.didConnectPeripheral() // late OS success must be cancelled
        XCTAssertEqual(cancellations, 2)
        XCTAssertEqual(results, 1)
        attempt.didDisconnectPeripheral(error: nil)
        attempt.didDisconnectPeripheral(error: nil)
        XCTAssertEqual(drains, 1)
        XCTAssertEqual(results, 1)
    }

    @MainActor
    func testTransportBlocksRetryUntilTimedOutConnectDrains() async {
        let radio = Radio()
        radio.connectError = ConnectionError.timedOut
        let transport = BleTransport(configuration: nil, debugMode: false, module: radio)
        let failed = expectation(description: "connect failed")
        transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in XCTFail("timeout succeeded") }, failure: { _ in failed.fulfill() })
        await fulfillment(of: [failed], timeout: 2)
        transport.disconnect { error in
            guard case .pendingActionOnDevice? = error else { XCTFail("cleanup not guarded"); return }
        }
        transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in XCTFail("overlap") }, failure: { error in
            guard case .pendingActionOnDevice = error else { XCTFail("retry not guarded"); return }
        })
        XCTAssertEqual(radio.connects, 1)
        radio.loseConnection()
        radio.connectError = nil
        let ready = expectation(description: "retry after drain")
        transport.connect(toPeripheralID: radio.device, disconnectedCallback: nil, success: { _ in ready.fulfill() }, failure: { XCTFail("\($0)") })
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(radio.connects, 2)
    }

    @MainActor
    func testConnectLookupFailureFinishesQueueWithoutStartingRadio() {
        var results = 0
        var drains = 0
        let attempt = Connect(timeout: .seconds(0.01), start: {
            throw ConnectionError.peripheralCantBeRetrievedFromCentralManager
        }, cancel: { XCTFail("nothing to cancel") }) { _ in results += 1 }
        attempt.finished = { drains += 1 }
        attempt.start()
        XCTAssertEqual(results, 1)
        XCTAssertEqual(drains, 1)
    }

    @MainActor
    func testQueuedOperationCannotStartAfterRadioGenerationChanges() async {
        let queue = Queue()
        var current = true
        let stale = TestOperation()
        let added = expectation(description: "queued add returned")
        queue.add(stale, isCurrent: { current }) { added.fulfill() }
        current = false
        queue.discardAll()
        await fulfillment(of: [added], timeout: 2)
        XCTAssertEqual(stale.starts, 0)
        XCTAssertTrue(queue.isEmpty)
        let fresh = TestOperation()
        let started = expectation(description: "new generation starts")
        queue.add(fresh) { started.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(fresh.starts, 1)
        queue.discardAll()
    }

    func testCompletionAndMalformedResponseAreBounded() {
        var callbacks = 0
        let pending = PendingBleExchange { _ in callbacks += 1 }
        XCTAssertNotNil(pending.receive(Data([5])))
        pending.finish(.failure(.readError(description: "bad frame")))
        pending.finish(.success("9000"))
        XCTAssertNil(pending.receive(Data([5,0,0,0,2,0x90,0])))
        XCTAssertEqual(callbacks, 1)
    }
}

private final class Radio: BleTransportIO {
    let device = PeripheralIdentifier(uuid: UUID(), name: "Ledger")
    var isBluetoothAvailable = true
    var bluetoothState: CBManagerState = .poweredOn
    weak var delegate: BleModuleDelegate?
    var listener: ((Data) -> Void)?
    var connects = 0
    var connectError: Error?
    var answerMtu = true
    var failWrite = false
    var deferDisconnect = false
    func start(delegate: BleModuleDelegate) { self.delegate = delegate }
    func stopScanning() {}
    func scanLedger(duration: TimeInterval, serviceIdentifiers: [ServiceIdentifier], discovery: @escaping (ScanDiscovery, [ScanDiscovery]) -> ScanAction, expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)?, stopped: @escaping ([ScanDiscovery], Error?, Bool) -> Void) {
        let found = ScanDiscovery(peripheralIdentifier: device, advertisementPacket: ["kCBAdvDataServiceUUIDs": [CBUUID(string: "13d63400-2c97-0004-0000-4c6564676572")]], rssi: -40)
        _ = discovery(found, [found])
        _ = discovery(found, [found]) // repeated advertisements must not reconnect
    }
    func connectLedger(_ id: PeripheralIdentifier, timeout: Timeout, callback: @escaping (Result<PeripheralIdentifier, Error>) -> Void) { connects += 1; if let connectError { callback(.failure(connectError)) } else { callback(.success(device)) } }
    func write<S: Sendable>(to: CharacteristicIdentifier, value: S, type: CBCharacteristicWriteType, completion: @escaping (WriteResult) -> Void) {
        if failWrite { completion(.failure(BleModuleError.notConnected)); return }
        completion(.success)
        if let apdu = value as? APDU, apdu.data.first == 8, answerMtu { deliver([8,0,0,0,0,153]) }
    }
    func listen<R: Receivable>(to: CharacteristicIdentifier, completion: @escaping (ReadResult<R>) -> Void, setupFinished: EmptyResponse?) {
        listener = { completion(ReadResult<R>(dataResult: .success($0))) }
        setupFinished?()
    }
    func disconnect(completion: ((DisconnectionResult) -> Void)?) {
        completion?(.disconnected(device))
        if !deferDisconnect { loseConnection() }
    }
    var cancellations = 0
    func cancelConnection() { cancellations += 1; if !deferDisconnect { loseConnection() } }
    func loseConnection() { delegate?.disconnected(from: device) }
    func deliver(_ bytes: [UInt8]) { listener?(Data(bytes)) }
}

private final class TestOperation: TaskOperation {
    var finished: EmptyResponse?
    var starts = 0
    func start() { starts += 1 }
}
