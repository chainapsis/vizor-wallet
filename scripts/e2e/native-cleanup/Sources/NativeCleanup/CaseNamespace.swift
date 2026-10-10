import Foundation

package func validateCleanupNamespace(_ namespace: String) throws {
  let parts = namespace.split(separator: "_", omittingEmptySubsequences: false)
  func index(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
      let number = Int(value), (0...1_000_000).contains(number)
    else { return false }
    return String(number) == value
  }
  guard namespace.utf8.count <= 64, namespace.utf8.allSatisfy({ $0 < 128 }),
    parts.count == 4, parts[0] == "vizor", parts[1].count == 10,
    parts[1].allSatisfy({ "0123456789abcdef".contains($0) }),
    parts[2].first == "w", index(String(parts[2].dropFirst())), index(String(parts[3]))
  else { throw CleanupFailure("invalid_namespace") }
}
