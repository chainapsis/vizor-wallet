import Foundation

enum E2eRuntimeProfileError: Error, Equatable {
  case missingBuildMarker
  case invalidBuildMarker
  case missingEnvironment
  case partialEnvironment
  case unexpectedEnvironment
  case unsupportedBuild
  case invalidManifest
  case namespaceMismatch
}

struct E2eRuntimeProfile: Equatable {
  static let cohortBuildInfoKey = "VizorE2eIosCohort"
  static let manifestEnvironmentKey = "VIZOR_E2E_CASE_MANIFEST"
  static let namespaceEnvironmentKey = "VIZOR_E2E_NAMESPACE"

  private static var installedProfile: E2eRuntimeProfile?

  static var current: E2eRuntimeProfile {
    guard let installedProfile else {
      preconditionFailure("E2eRuntimeProfile must be installed before native state is used")
    }
    return installedProfile
  }

  static let production = E2eRuntimeProfile(namespace: nil, runId: nil)

  let namespace: String?
  let runId: String?

  var isIsolated: Bool { namespace != nil }

  var defaultsSuiteName: String? {
    namespace.map { "com.keplr.vizor.regtest.e2e.\($0)" }
  }

  var notificationPrefix: String? {
    namespace.map { "vizor_e2e_\($0)." }
  }

  var defaults: UserDefaults {
    guard let defaultsSuiteName else { return .standard }
    guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
      preconditionFailure("Unable to open E2E UserDefaults suite")
    }
    return defaults
  }

  static func installFromEnvironment() throws -> E2eRuntimeProfile {
    let isCohortBuild = try readCohortBuildMarker(
      infoDictionary: Bundle.main.infoDictionary
    )
    #if DEBUG && targetEnvironment(simulator)
      let supportsIsolation = true
    #else
      let supportsIsolation = false
    #endif
    let profile = try parse(
      environment: ProcessInfo.processInfo.environment,
      supportsIsolation: supportsIsolation,
      isCohortBuild: isCohortBuild
    )
    if let installedProfile, installedProfile != profile {
      throw E2eRuntimeProfileError.invalidManifest
    }
    installedProfile = profile
    return profile
  }

  static func parse(
    environment: [String: String],
    supportsIsolation: Bool,
    isCohortBuild: Bool
  ) throws -> E2eRuntimeProfile {
    let encoded = environment[manifestEnvironmentKey]
    let runtimeNamespace = environment[namespaceEnvironmentKey]

    guard isCohortBuild else {
      guard encoded == nil, runtimeNamespace == nil else {
        throw E2eRuntimeProfileError.unexpectedEnvironment
      }
      return .production
    }
    guard supportsIsolation else {
      throw E2eRuntimeProfileError.unsupportedBuild
    }
    guard encoded != nil || runtimeNamespace != nil else {
      throw E2eRuntimeProfileError.missingEnvironment
    }
    guard let encoded, let runtimeNamespace else {
      throw E2eRuntimeProfileError.partialEnvironment
    }
    guard encoded.utf8.count <= 2_048,
      encoded.utf8.allSatisfy({ $0 < 0x80 }),
      runtimeNamespace.utf8.count <= 64,
      runtimeNamespace.utf8.allSatisfy({ $0 < 0x80 })
    else {
      throw E2eRuntimeProfileError.invalidManifest
    }
    guard let data = encoded.data(using: .utf8) else {
      throw E2eRuntimeProfileError.invalidManifest
    }
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw E2eRuntimeProfileError.invalidManifest
    }
    guard let manifest = object as? [String: Any] else {
      throw E2eRuntimeProfileError.invalidManifest
    }
    let expectedKeys: Set<String> = [
      "schema_version", "scenario_id", "run_id", "worker_id", "case_index",
      "namespace", "context_path", "lightwalletd_port", "primary_proxy_port",
      "zcashd_rpc_port", "regtest_ironwood_activation_height",
    ]
    guard Set(manifest.keys) == expectedKeys,
      integer(manifest["schema_version"], minimum: 1, maximum: 1) != nil,
      let scenarioId = manifest["scenario_id"] as? String,
      scenarioId.range(
        of: #"^flutter\.ios\.[a-z0-9]+(?:-[a-z0-9]+)*$"#,
        options: .regularExpression
      ) == scenarioId.startIndex..<scenarioId.endIndex,
      let runId = manifest["run_id"] as? String,
      runId.range(of: #"^[0-9a-f]{10}$"#, options: .regularExpression)
        == runId.startIndex..<runId.endIndex,
      let workerId = integer(manifest["worker_id"], minimum: 0, maximum: 1_000_000),
      let caseIndex = integer(manifest["case_index"], minimum: 0, maximum: 1_000_000),
      let manifestNamespace = manifest["namespace"] as? String,
      manifest["context_path"] as? String == "app-support",
      let lightwalletdPort = port(manifest["lightwalletd_port"]),
      let primaryProxyPort = port(manifest["primary_proxy_port"]),
      let zcashdRpcPort = port(manifest["zcashd_rpc_port"]),
      integer(
        manifest["regtest_ironwood_activation_height"],
        minimum: 1,
        maximum: Int(UInt32.max)
      ) != nil,
      Set([lightwalletdPort, primaryProxyPort, zcashdRpcPort]).count == 3
    else {
      throw E2eRuntimeProfileError.invalidManifest
    }
    let expectedNamespace = "vizor_\(runId)_w\(workerId)_\(caseIndex)"
    guard manifestNamespace == expectedNamespace,
      runtimeNamespace == expectedNamespace
    else {
      throw E2eRuntimeProfileError.namespaceMismatch
    }
    return E2eRuntimeProfile(namespace: expectedNamespace, runId: runId)
  }

  static func readCohortBuildMarker(
    infoDictionary: [String: Any]?
  ) throws -> Bool {
    guard let value = infoDictionary?[cohortBuildInfoKey] else {
      throw E2eRuntimeProfileError.missingBuildMarker
    }
    guard let marker = value as? NSNumber,
      CFGetTypeID(marker) == CFBooleanGetTypeID()
    else {
      throw E2eRuntimeProfileError.invalidBuildMarker
    }
    return marker.boolValue
  }

  func keychainService(_ base: String) -> String {
    guard let namespace else { return base }
    return "\(base).e2e.\(namespace)"
  }

  func supportDirectory(_ base: URL) -> URL {
    guard let namespace else { return base }
    return base
      .appendingPathComponent("e2e", isDirectory: true)
      .appendingPathComponent(namespace, isDirectory: true)
  }

  func notificationIdentifier(_ base: String) -> String {
    guard let notificationPrefix else { return base }
    return notificationPrefix + base
  }

  private static func integer(
    _ value: Any?,
    minimum: Int,
    maximum: Int
  ) -> Int? {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      !CFNumberIsFloatType(number)
    else { return nil }
    let integer = number.int64Value
    guard NSNumber(value: integer) == number,
      integer >= minimum,
      integer <= maximum
    else { return nil }
    return Int(integer)
  }

  private static func port(_ value: Any?) -> Int? {
    integer(value, minimum: 1, maximum: 65_535)
  }
}
