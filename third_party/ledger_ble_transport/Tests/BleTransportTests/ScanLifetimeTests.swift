import XCTest
import CoreBluetooth
@testable import BleTransport

final class ScanLifetimeTests: XCTestCase {
    @MainActor
    private func enqueue(_ scan: Scan, in queue: Queue, isCurrent: @escaping () -> Bool = { true }) async {
        let added = expectation(description: "scan enqueued")
        queue.add(scan, isCurrent: isCurrent) { added.fulfill() }
        await fulfillment(of: [added], timeout: 2)
    }

    @MainActor
    func testRadioOffDiscardCannotStopReplacementScan() async {
        let radio = ScanTestRadio()
        let queue = Queue()
        let old = makeScan(radio, duration: 0.1) { XCTFail("discarded scan callback") }
        await enqueue(old, in: queue)
        radio.state = .poweredOff
        queue.discardAll()
        radio.state = .poweredOn
        let fresh = makeScan(radio, duration: 10)
        await enqueue(fresh, in: queue)
        let elapsed = expectation(description: "original timeout has elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { elapsed.fulfill() }
        await fulfillment(of: [elapsed], timeout: 2)
        XCTAssertTrue(radio.scanning)
        XCTAssertEqual(radio.stops, 0)
        // An already delivered timeout or explicit stale stop must be inert too.
        old.timeoutTimerAction(Timer())
        old.stopScanning()
        old.start()
        XCTAssertTrue(radio.scanning)
        XCTAssertEqual(radio.starts, 2)
        XCTAssertEqual(radio.stops, 0)
        fresh.stopScanning()
    }

    @MainActor
    func testDiscardReleasesScanAndCapturedCallbacksImmediately() async {
        let radio = ScanTestRadio()
        let queue = Queue()
        weak var releasedScan: Scan?
        weak var releasedCapture: NSObject?
        do {
            let capture = NSObject()
            let scan = makeScan(radio, duration: 60) { _ = capture.description }
            releasedScan = scan
            releasedCapture = capture
            await enqueue(scan, in: queue)
        }
        queue.discardAll()
        XCTAssertNil(releasedScan)
        XCTAssertNil(releasedCapture)
        XCTAssertFalse(radio.scanning)
    }

    @MainActor
    func testQueuedExpiryAndLateDiscoveryAreIgnoredAfterDiscard() async {
        let radio = ScanTestRadio()
        let queue = Queue()
        var discoveries = 0
        let old = Scan(duration: 10, throttleRSSIDelta: 5,
            serviceIdentifiers: [ServiceIdentifier(uuid: "1800")],
            discovery: { _, _ in discoveries += 1; return .continue },
            expired: { _, _ in .stop },
            stopped: { _, _, _ in XCTFail("discarded expiry callback") }, manager: radio)
        await enqueue(old, in: queue)
        let device = ScanDiscovery(peripheralIdentifier: PeripheralIdentifier(uuid: UUID(), name: "Ledger"), advertisementPacket: [:], rssi: -40)
        old.discovered(device)
        let expiry = Timer(timeInterval: 1, target: NSObject(), selector: Selector(("unused")), userInfo: device.peripheralIdentifier.uuid, repeats: false)
        old.refresh(timer: expiry) // Enqueues asynchronous stop from expiry callback.
        radio.state = .poweredOff
        queue.discardAll()
        radio.state = .poweredOn
        let fresh = makeScan(radio, duration: 10)
        await enqueue(fresh, in: queue)
        old.discovered(device)
        old.refresh(timer: expiry)
        XCTAssertEqual(discoveries, 1)
        XCTAssertTrue(radio.scanning)
        XCTAssertEqual(radio.stops, 0)
        fresh.stopScanning()
    }

    @MainActor
    func testNormalStopNotifiesAndDrainsOnlyOnce() async {
        let radio = ScanTestRadio()
        let queue = Queue()
        var completions = 0
        var drains = 0
        let scan = makeScan(radio, duration: 10) { completions += 1 }
        scan.finished = { drains += 1 }
        await enqueue(scan, in: queue)
        scan.stopScanning()
        scan.timeoutTimerAction(Timer())
        scan.stopScanning()
        queue.discardAll()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(drains, 1)
        XCTAssertEqual(radio.stops, 1)
    }

    @MainActor
    func testRejectedQueuedScanReleasesCallbacksWithoutStoppingActiveScan() async {
        let radio = ScanTestRadio()
        let queue = Queue()
        let active = makeScan(radio, duration: 10)
        await enqueue(active, in: queue)
        weak var capture: NSObject?
        let rejected: Scan
        do {
            let owner = NSObject()
            capture = owner
            rejected = makeScan(radio, duration: 10) { _ = owner.description }
        }
        await enqueue(rejected, in: queue, isCurrent: { false })
        XCTAssertNil(capture)
        rejected.stopScanning()
        rejected.start()
        XCTAssertTrue(radio.scanning)
        XCTAssertEqual(radio.starts, 1)
        XCTAssertEqual(radio.stops, 0)
        active.stopScanning()
    }
}

private func makeScan(_ radio: ScanTestRadio, duration: TimeInterval, stopped: @escaping () -> Void = {}) -> Scan {
    Scan(duration: duration, throttleRSSIDelta: 5,
         serviceIdentifiers: [ServiceIdentifier(uuid: "1800")],
         discovery: { _, _ in .continue }, expired: nil,
         stopped: { _, _, _ in stopped() }, manager: radio)
}

private final class ScanTestRadio: ScanRadio {
    var state: CBManagerState = .poweredOn
    var scanning = false
    var starts = 0
    var stops = 0
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        scanning = true
        starts += 1
    }
    func stopScan() { scanning = false; stops += 1 }
}
