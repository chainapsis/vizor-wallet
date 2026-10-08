import Foundation

private let cohortDefine = "VIZOR_E2E_IOS_COHORT"
private let plistKey = "VizorE2eIosCohort"

private enum StampError: Error, CustomStringConvertible {
  case usage
  case malformedBase64(Int)
  case malformedUTF8(Int)
  case malformedCohortDefinition
  case duplicateCohortDefinition
  case invalidCohortValue(String)
  case invalidPlist(String)

  var description: String {
    switch self {
    case .usage:
      return "usage: stamp-ios-runtime-profile.swift <processed-info-plist>"
    case let .malformedBase64(index):
      return "DART_DEFINES entry \(index) is not canonical base64"
    case let .malformedUTF8(index):
      return "DART_DEFINES entry \(index) is not valid UTF-8"
    case .malformedCohortDefinition:
      return "VIZOR_E2E_IOS_COHORT must be encoded as KEY=true or KEY=false"
    case .duplicateCohortDefinition:
      return "VIZOR_E2E_IOS_COHORT must be defined at most once"
    case let .invalidCohortValue(value):
      return "VIZOR_E2E_IOS_COHORT must be true or false, got \(value)"
    case let .invalidPlist(message):
      return "could not update processed Info.plist: \(message)"
    }
  }
}

private func cohortEnabled(from rawDefines: String?) throws -> Bool {
  guard let rawDefines, !rawDefines.isEmpty else { return false }

  var result: Bool?
  for (offset, encoded) in rawDefines.split(separator: ",", omittingEmptySubsequences: false)
    .enumerated()
  {
    let encodedString = String(encoded)
    guard
      !encodedString.isEmpty,
      let data = Data(base64Encoded: encodedString),
      data.base64EncodedString() == encodedString
    else {
      throw StampError.malformedBase64(offset)
    }
    guard let definition = String(data: data, encoding: .utf8) else {
      throw StampError.malformedUTF8(offset)
    }

    let separator = definition.firstIndex(of: "=")
    let key = separator.map { String(definition[..<$0]) } ?? definition
    guard key == cohortDefine else { continue }
    guard let separator else {
      throw StampError.malformedCohortDefinition
    }
    guard result == nil else {
      throw StampError.duplicateCohortDefinition
    }

    let value = String(definition[definition.index(after: separator)...])
    switch value {
    case "true":
      result = true
    case "false":
      result = false
    default:
      throw StampError.invalidCohortValue(value)
    }
  }
  return result ?? false
}

private func stamp(plistURL: URL, cohortEnabled: Bool) throws {
  let original: Data
  do {
    original = try Data(contentsOf: plistURL)
  } catch {
    throw StampError.invalidPlist(error.localizedDescription)
  }

  var format = PropertyListSerialization.PropertyListFormat.xml
  let decoded: Any
  do {
    decoded = try PropertyListSerialization.propertyList(
      from: original,
      options: [],
      format: &format
    )
  } catch {
    throw StampError.invalidPlist(error.localizedDescription)
  }
  guard var dictionary = decoded as? [String: Any] else {
    throw StampError.invalidPlist("root object is not a dictionary")
  }
  dictionary[plistKey] = cohortEnabled

  let updated: Data
  do {
    updated = try PropertyListSerialization.data(
      fromPropertyList: dictionary,
      format: format,
      options: 0
    )
  } catch {
    throw StampError.invalidPlist(error.localizedDescription)
  }
  do {
    try updated.write(to: plistURL, options: .atomic)
  } catch {
    throw StampError.invalidPlist(error.localizedDescription)
  }
}

do {
  guard CommandLine.arguments.count == 2 else { throw StampError.usage }
  let enabled = try cohortEnabled(
    from: ProcessInfo.processInfo.environment["DART_DEFINES"]
  )
  let plistURL = URL(fileURLWithPath: CommandLine.arguments[1])
  try stamp(plistURL: plistURL, cohortEnabled: enabled)
  print("Stamped \(plistKey)=\(enabled) in \(plistURL.path)")
} catch {
  fputs("stamp-ios-runtime-profile: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
