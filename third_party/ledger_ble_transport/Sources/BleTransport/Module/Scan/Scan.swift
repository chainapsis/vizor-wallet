//
//  Scan.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

public class Scan: TaskOperation {

    var finished: EmptyResponse?

    /// The manager responsible for this operation.
    private let manager: CBCentralManager

    /// The duration of the scan.
    private let duration: TimeInterval

    /// The timer that completes when timeout equal to `duration` occurs.
    private var timeoutTimer: Timer?

    /// Throttle discoveries by ignoring discovery if the change in RSSI is insignificant. 0 will never throttle discoveries, default is 5 dBm.
    private let throttleRSSIDelta: Int

    /// The scan will only look for peripherals broadcasting the specified services.
    private let serviceIdentifiers: [ServiceIdentifier]

    /// The discovery callback.
    private let discovery: (ScanDiscovery, [ScanDiscovery]) -> ScanAction

    /// The expired callback.
    private let expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)?

    /// The stopped callback. Called when stopped normally as well, not just when there is an error.
    private let stopped: ([ScanDiscovery], Error?, Bool) -> Void

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
         manager: CBCentralManager) {

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
        clearTimeoutTimer()

        let peripheralIdentifier = PeripheralIdentifier(uuid: cbPeripheral.identifier, name: cbPeripheral.name)

        let newDiscovery = ScanDiscovery(peripheralIdentifier: peripheralIdentifier, advertisementPacket: advertisementData, rssi: rssi.intValue)

        refreshTimer(identifier: newDiscovery.peripheralIdentifier.uuid)

        if let indexOfExistingDiscovery = discoveries.firstIndex(where: { existingDiscovery -> Bool in
            existingDiscovery.peripheralIdentifier == peripheralIdentifier
        }) {
            let existingDiscovery = discoveries[indexOfExistingDiscovery]

            // Throttle discovery by ignoring discovery if the change of RSSI is insignificant.
            if abs(existingDiscovery.rssi - rssi.intValue) < throttleRSSIDelta {
                return
            }

            // Update existing discovery.
            discoveries.remove(at: indexOfExistingDiscovery)
            discoveries.insert(newDiscovery, at: indexOfExistingDiscovery)
        } else {
            discoveries.append(newDiscovery)
        }

        if case .stop = discovery(newDiscovery, discoveries) {
            stopScan(with: discoveries, error: nil, timedOut: false)
        }
    }

    private func stopScan(with discoveries: [ScanDiscovery], error: Error?, timedOut: Bool) {
        clearTimers()

        // There is no point trying to stop the scan if Bluetooth is off, as trying to do so has no effect and will also cause CoreBluetooth to log an "API MISUSE" warning.
        if manager.state == .poweredOn {
            manager.stopScan()
        }

        /*if let error = error {
            print("Scanning stopped with error: \(error.localizedDescription)")
        } else {
            print("Scanning stopped.")
        }*/

        complete(discoveries, error, timedOut)
    }

    func complete(_ discoveries: [ScanDiscovery], _ error: Error?, _ timedOut: Bool) {
        stopped(discoveries, error, timedOut)
        finished?()
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
        if let indexOfExpiredDiscovery = discoveries.firstIndex(where: { discovery -> Bool in
            discovery.peripheralIdentifier.uuid == identifier
        }) {
            let expiredDiscovery = discoveries[indexOfExpiredDiscovery]
            discoveries.remove(at: indexOfExpiredDiscovery)

            if let expired = expired {
                if case .stop = expired(expiredDiscovery, discoveries) {
                    DispatchQueue.main.async {
                        self.clearTimers()

                        if self.manager.state == .poweredOn {
                            self.manager.stopScan()
                        }

                        self.complete(self.discoveries, nil, false)
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
