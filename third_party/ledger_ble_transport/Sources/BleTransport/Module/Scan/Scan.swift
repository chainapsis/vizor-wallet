//
//  Scan.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

// Only the radio boundary is substituted by tests; timers and queue are real.
protocol ScanRadio: AnyObject {
    var state: CBManagerState { get }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
}

extension CBCentralManager: ScanRadio {}

public class Scan: TaskOperation {

    var finished: EmptyResponse?
    private var isStarted = false
    private var isFinished = false

    /// The manager responsible for this operation.
    private let manager: ScanRadio

    /// The duration of the scan.
    private let duration: TimeInterval

    /// The timer that completes when timeout equal to `duration` occurs.
    private var timeoutTimer: Timer?

    /// Throttle discoveries by ignoring discovery if the change in RSSI is insignificant. 0 will never throttle discoveries, default is 5 dBm.
    private let throttleRSSIDelta: Int

    /// The scan will only look for peripherals broadcasting the specified services.
    private let serviceIdentifiers: [ServiceIdentifier]

    /// The discovery callback.
    private var discovery: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)?

    /// The expired callback.
    private var expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)?

    /// The stopped callback. Called when stopped normally as well, not just when there is an error.
    private var stopped: (([ScanDiscovery], Error?, Bool) -> Void)?

    /// The discoveries made so far in a given scan session.
    private var discoveries = [ScanDiscovery]()

    /// The timers used to estimate an expiry callback, indicating that the peripheral is potentially no longer accessible.
    private var timers = [(UUID, Timer?)]()

    deinit {
        //print("Deinited Scan")
    }

    init(duration: TimeInterval,
         throttleRSSIDelta: Int,
         serviceIdentifiers: [ServiceIdentifier],
         discovery: @escaping (ScanDiscovery, [ScanDiscovery]) -> ScanAction,
         expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)?,
         stopped: @escaping ([ScanDiscovery], Error?, Bool) -> Void,
         manager: ScanRadio) {

        self.duration = duration
        self.throttleRSSIDelta = throttleRSSIDelta
        self.serviceIdentifiers = serviceIdentifiers
        self.discovery = discovery
        self.expired = expired
        self.stopped = stopped
        self.manager = manager

        if serviceIdentifiers.isEmpty != false {
            print("""
                Warning: Setting `serviceIdentifiers` to `nil` is not recommended by Apple. \
                It may cause battery and cpu issues on prolonged scanning, and **it also doesn't work in the background**. \
                If you need to scan for all Bluetooth devices, we recommend making use of the `duration` parameter to stop the scan \
                after 5 ~ 10 seconds to avoid scanning indefinitely and overloading the hardware.
                """)
        }
    }

    func start() {
        guard !isStarted, !isFinished else { return }
        isStarted = true
        let timeoutTimer = Timer(
            timeInterval: duration,
            target: self,
            selector: #selector(timeoutTimerAction(_:)),
            userInfo: nil,
            repeats: false)
        let runLoop: RunLoop = .current
        runLoop.add(timeoutTimer, forMode: RunLoop.Mode.default)
        self.timeoutTimer = timeoutTimer

        let services = serviceIdentifiers.map { service -> CBUUID in
            service.uuid
        }

        manager.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        stopScan(with: discoveries, error: nil, timedOut: false)
    }

    func discoveredPeripheral(cbPeripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        discovered(ScanDiscovery(
            peripheralIdentifier: PeripheralIdentifier(uuid: cbPeripheral.identifier, name: cbPeripheral.name),
            advertisementPacket: advertisementData, rssi: rssi.intValue))
    }

    func discovered(_ newDiscovery: ScanDiscovery) {
        guard isStarted, !isFinished else { return }
        clearTimeoutTimer()
        let peripheralIdentifier = newDiscovery.peripheralIdentifier
        let rssi = newDiscovery.rssi

        refreshTimer(identifier: newDiscovery.peripheralIdentifier.uuid)

        if let indexOfExistingDiscovery = discoveries.firstIndex(where: { existingDiscovery -> Bool in
            existingDiscovery.peripheralIdentifier == peripheralIdentifier
        }) {
            let existingDiscovery = discoveries[indexOfExistingDiscovery]

            // Throttle discovery by ignoring discovery if the change of RSSI is insignificant.
            if abs(existingDiscovery.rssi - rssi) < throttleRSSIDelta {
                return
            }

            // Update existing discovery.
            discoveries.remove(at: indexOfExistingDiscovery)
            discoveries.insert(newDiscovery, at: indexOfExistingDiscovery)
        } else {
            discoveries.append(newDiscovery)
        }

        if case .stop? = discovery?(newDiscovery, discoveries) {
            stopScan(with: discoveries, error: nil, timedOut: false)
        }
    }

    // Queue invalidation is silent: Bluetooth state already supplies the error.
    // Mark terminal before stopping radio or releasing callbacks for reentrancy.
    func discard() {
        guard !isFinished else { finished = nil; return }
        isFinished = true
        finished = nil
        clearTimers()
        discovery = nil
        expired = nil
        stopped = nil
        discoveries.removeAll()
        if isStarted, manager.state == .poweredOn { manager.stopScan() }
    }

    private func stopScan(with discoveries: [ScanDiscovery], error: Error?, timedOut: Bool) {
        guard !isFinished else { return }
        let completion = stopped
        let drained = finished
        discard()
        completion?(discoveries, error, timedOut)
        drained?()
    }

    private func refreshTimer(identifier: UUID) {
        if let indexOfExistingTimer = timers.firstIndex(where: { uuid, _ -> Bool in
            uuid == identifier
        }) {
            timers[indexOfExistingTimer].1?.invalidate()
            timers[indexOfExistingTimer].1 = nil
            timers.remove(at: indexOfExistingTimer)
        }

        var timer: Timer?

        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let weakSelf = self else {
                return
            }
            weakSelf.refresh(identifier: identifier)
        }

        timers.append((identifier, timer!))
    }

    private func refresh(identifier: UUID) {
        guard isStarted, !isFinished else { return }
        if let indexOfExpiredDiscovery = discoveries.firstIndex(where: { discovery -> Bool in
            discovery.peripheralIdentifier.uuid == identifier
        }) {
            let expiredDiscovery = discoveries[indexOfExpiredDiscovery]
            discoveries.remove(at: indexOfExpiredDiscovery)

            if let expired = expired {
                if case .stop = expired(expiredDiscovery, discoveries) {
                    DispatchQueue.main.async {
                        self.stopScan(with: self.discoveries, error: nil, timedOut: false)
                    }
                }
            }
        }
    }

    @objc func refresh(timer: Timer) {
        if let identifier = timer.userInfo as? UUID {
            refresh(identifier: identifier)
        }
    }

    private func clearTimers() {
        for timerIndex in 0..<timers.count {
            timers[timerIndex].1?.invalidate()
            timers[timerIndex].1 = nil
        }

        timers = []

        clearTimeoutTimer()
    }

    private func clearTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    @objc func timeoutTimerAction(_ timer: Timer) {
        self.timeoutTimer = nil

        //print("Finished scanning on timeout.")

        stopScan(with: discoveries, error: nil, timedOut: true)
    }
}
