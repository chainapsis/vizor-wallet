import Foundation
import NativeCleanup

// The worker must wrap/sign this executable as a sandboxed com.keplr.vizor app
// with the stopped cohort's identity. An unsigned CLI fails before native I/O.
let arguments = Array(CommandLine.arguments.dropFirst())
let verify = arguments.first == "--verify"
let supportLocation = arguments.first == "--support-location"
let fields = verify || supportLocation ? Array(arguments.dropFirst()) : arguments
do {
  guard fields.count == 4, fields[0] == "--namespace", fields[2] == "--team" else {
    throw CleanupFailure("invalid_arguments")
  }
  let scope = try MacCleanupScope(namespace: fields[1], expectedTeam: fields[3])
  let encoder = JSONEncoder()
  encoder.keyEncodingStrategy = .convertToSnakeCase
  encoder.outputFormatting = [.sortedKeys]
  if supportLocation {
    let receipt = observeMacSupportLocation(scope, system: MacCleanupSystem())
    let data = try encoder.encode(receipt)
    FileHandle.standardOutput.write(data + Data([10]))
    exit(receipt.completed ? 0 : 1)
  }
  let receipt = inspectOrClean(scope, mode: verify ? .verify : .delete, system: MacCleanupSystem())
  let data = try encoder.encode(receipt)
  FileHandle.standardOutput.write(data + Data([10]))
  exit(receipt.completed ? 0 : 1)
} catch let failure as CleanupFailure {
  // Invalid, untrusted arguments (possibly secrets) are never echoed.
  let receipt: [String: Any] = ["schema_version": 1, "platform": "macos", "completed": false, "error_code": failure.code]
  let data = try JSONSerialization.data(withJSONObject: receipt, options: .sortedKeys)
  FileHandle.standardOutput.write(data + Data([10]))
  exit(1)
} catch {
  FileHandle.standardError.write(Data("{\"completed\":false,\"error_code\":\"receipt_encoding_failed\",\"schema_version\":1}\n".utf8))
  exit(1)
}
