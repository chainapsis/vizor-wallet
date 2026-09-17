//
//  ReadResult.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/5/22.
//

import Foundation

public enum ReadError: LocalizedError {
    case missingData

    public var errorDescription: String? {
        switch self {
        case .missingData:
            return "Missing data."
        }
    }
}

/// Indicates a successful, cancelled, or failed read attempt, where the success case contains the value read.
public enum ReadResult<R> {
    /// The read is successful and the value read is captured in the associated value.
    case success(R)
    /// The read has failed unexpectedly with an error.
    case failure(Error)
}

extension ReadResult where R: Receivable {

    /// Create a typed read result from raw data.
    init(dataResult: ReadResult<Data?>) {
        switch dataResult {
        case .success(let data):
            if let data = data {
                do {
                    self = .success(try R(bluetoothData: data))
                } catch {
                    self = .failure(error)
                }
            } else {
                self = .failure(ReadError.missingData)
            }
        case .failure(let error):
            self = .failure(error)
        }
    }

}
