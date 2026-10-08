import CoreFoundation
import Foundation

// Xcode's Simulator rights live in the Mach-O __TEXT,__entitlements section;
// codesign's ad-hoc entitlements output alone does not establish these rights.
package func iosSimulatedEntitlements(_ data: Data) throws -> [String: Any] {
  func u32(_ offset: Int) throws -> UInt32 {
    guard offset >= 0, offset <= data.count - 4 else { throw CleanupFailure("ios_entitlements_invalid") }
    return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
  }
  func u64(_ offset: Int) throws -> UInt64 {
    guard offset >= 0, offset <= data.count - 8 else { throw CleanupFailure("ios_entitlements_invalid") }
    return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian }
  }
  func name(_ offset: Int) throws -> String {
    guard offset >= 0, offset <= data.count - 16 else { throw CleanupFailure("ios_entitlements_invalid") }
    return String(decoding: data[offset..<offset + 16].prefix(while: { $0 != 0 }), as: UTF8.self)
  }
  guard data.count >= 32, data.count <= 64 * 1024 * 1024,
    try u32(0) == 0xfeedfacf, try u32(12) == 2
  else { throw CleanupFailure("ios_entitlements_invalid") }
  let count = Int(try u32(16))
  let bytes = Int(try u32(20))
  guard count > 0, count <= 4096, bytes <= 1024 * 1024, bytes <= data.count - 32 else {
    throw CleanupFailure("ios_entitlements_invalid")
  }
  let end = 32 + bytes
  var offset = 32
  var payload: Data?
  for _ in 0..<count {
    guard offset <= end - 8 else { throw CleanupFailure("ios_entitlements_invalid") }
    let command = try u32(offset)
    let size = Int(try u32(offset + 4))
    guard size >= 8, size % 8 == 0, size <= end - offset else { throw CleanupFailure("ios_entitlements_invalid") }
    if command == 0x19 {  // LC_SEGMENT_64
      guard size >= 72 else { throw CleanupFailure("ios_entitlements_invalid") }
      let sections = Int(try u32(offset + 64))
      guard sections <= (size - 72) / 80 else { throw CleanupFailure("ios_entitlements_invalid") }
      for index in 0..<sections {
        let section = offset + 72 + 80 * index
        if try name(section) == "__entitlements", try name(section + 16) == "__TEXT", try name(offset + 8) == "__TEXT" {
          let length = try u64(section + 40)
          let start = Int(try u32(section + 48))
          guard payload == nil, length > 0, length <= 16_384,
            start >= end, start <= data.count, length <= UInt64(data.count - start)
          else { throw CleanupFailure("ios_entitlements_invalid") }
          payload = data.subdata(in: start..<start + Int(length))
        }
      }
    }
    offset += size
  }
  guard offset == end, let payload else { throw CleanupFailure("ios_entitlements_missing") }
  do {
    guard let object = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any] else {
      throw CleanupFailure("ios_entitlements_invalid")
    }
    return object
  } catch { throw CleanupFailure("ios_entitlements_invalid") }
}

package func iosHelperApplicationIdentifier(_ entitlements: [String: Any]) throws -> String {
  let allowed: Set<String> = ["application-identifier", "com.apple.developer.team-identifier",
    "keychain-access-groups", "get-task-allow", "com.apple.security.get-task-allow"]
  guard Set(entitlements.keys).isSubset(of: allowed),
    let identifier = entitlements["application-identifier"] as? String,
    identifier.hasSuffix(".com.keplr.vizor")
  else { throw CleanupFailure("ios_helper_access_rights_invalid") }
  let team = String(identifier.dropLast(".com.keplr.vizor".count))
  guard team.utf8.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
    throw CleanupFailure("ios_helper_access_rights_invalid")
  }
  if let value = entitlements["com.apple.developer.team-identifier"], value as? String != team {
    throw CleanupFailure("ios_helper_access_rights_invalid")
  }
  if let value = entitlements["keychain-access-groups"], value as? [String] != [identifier] {
    throw CleanupFailure("ios_helper_access_rights_invalid")
  }
  for name in ["get-task-allow", "com.apple.security.get-task-allow"] {
    if let value = entitlements[name] {
      guard let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() else {
        throw CleanupFailure("ios_helper_access_rights_invalid")
      }
    }
  }
  return identifier
}
