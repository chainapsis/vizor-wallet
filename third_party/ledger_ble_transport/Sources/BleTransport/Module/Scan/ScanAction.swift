//
//  ScanAction.swift
//
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation

/// Indicates whether a scan should continue, continue but blacklist the current discovery, stop, or stop and connect.
public enum ScanAction {
    /// Continue scanning.
    case `continue`
    /// Continue scanning, but don't discover the same peripheral in the current callback again within the same scan session.
    case blacklist
    /// Stop scanning.
    case stop
}
