import Foundation
import XCTest

@testable import Runner

final class E2eRuntimeProfileTests: XCTestCase {
  private let namespace = "vizor_a1b2c3d4e5_w2_17"

  func testAbsentEnvironmentPreservesProductionNames() throws {
    let profile = try E2eRuntimeProfile.parse(
      environment: [:],
      supportsIsolation: false,
      isCohortBuild: false
    )
    let support = URL(fileURLWithPath: "/tmp/support", isDirectory: true)

    XCTAssertFalse(profile.isIsolated)
    XCTAssertNil(profile.namespace)
    XCTAssertNil(profile.runId)
    XCTAssertNil(profile.defaultsSuiteName)
    XCTAssertNil(profile.notificationPrefix)
    XCTAssertTrue(profile.defaults === UserDefaults.standard)
    XCTAssertEqual(profile.keychainService("service"), "service")
    XCTAssertEqual(profile.supportDirectory(support), support)
    XCTAssertEqual(profile.notificationIdentifier("notice"), "notice")
  }

  func testBuildMarkerMustBePresentAndBoolean() throws {
    XCTAssertThrowsError(
      try E2eRuntimeProfile.readCohortBuildMarker(infoDictionary: nil)
    ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .missingBuildMarker) }
    for invalidMarker in ["true" as Any, 1 as Any] {
      XCTAssertThrowsError(
        try E2eRuntimeProfile.readCohortBuildMarker(
          infoDictionary: [E2eRuntimeProfile.cohortBuildInfoKey: invalidMarker]
        )
      ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .invalidBuildMarker) }
    }
    let ordinaryMarker = try E2eRuntimeProfile.readCohortBuildMarker(
      infoDictionary: [E2eRuntimeProfile.cohortBuildInfoKey: false]
    )
    let cohortMarker = try E2eRuntimeProfile.readCohortBuildMarker(
      infoDictionary: [E2eRuntimeProfile.cohortBuildInfoKey: true]
    )
    XCTAssertFalse(ordinaryMarker)
    XCTAssertTrue(cohortMarker)
  }

  func testCohortBuildWithoutEnvironmentFailsClosed() {
    XCTAssertThrowsError(
      try E2eRuntimeProfile.parse(
        environment: [:],
        supportsIsolation: true,
        isCohortBuild: true
      )
    ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .missingEnvironment) }
  }

  func testNonCohortBuildRejectsAnyE2eEnvironment() throws {
    let encoded = try encodedManifest()
    for environment in [
      [E2eRuntimeProfile.manifestEnvironmentKey: encoded],
      [E2eRuntimeProfile.namespaceEnvironmentKey: namespace],
      [
        E2eRuntimeProfile.manifestEnvironmentKey: encoded,
        E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
      ],
    ] {
      XCTAssertThrowsError(
        try E2eRuntimeProfile.parse(
          environment: environment,
          supportsIsolation: true,
          isCohortBuild: false
        )
      ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .unexpectedEnvironment) }
    }
  }

  func testValidManifestDerivesAllNativeIsolationNames() throws {
    let profile = try parse()

    XCTAssertTrue(profile.isIsolated)
    XCTAssertEqual(profile.namespace, namespace)
    XCTAssertEqual(profile.runId, "a1b2c3d4e5")
    XCTAssertEqual(
      profile.keychainService("service"),
      "service.e2e.\(namespace)"
    )
    XCTAssertEqual(
      profile.defaultsSuiteName,
      "com.keplr.vizor.regtest.e2e.\(namespace)"
    )
    XCTAssertEqual(profile.notificationPrefix, "vizor_e2e_\(namespace).")
    XCTAssertEqual(
      profile.notificationIdentifier("notice"),
      "vizor_e2e_\(namespace).notice"
    )
    XCTAssertEqual(
      profile.supportDirectory(URL(fileURLWithPath: "/tmp/support")).path,
      "/tmp/support/e2e/\(namespace)"
    )
  }

  func testPartialEnvironmentFailsClosed() throws {
    let manifest = try encodedManifest()
    XCTAssertThrowsError(
      try E2eRuntimeProfile.parse(
        environment: [E2eRuntimeProfile.manifestEnvironmentKey: manifest],
        supportsIsolation: true,
        isCohortBuild: true
      )
    ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .partialEnvironment) }
    XCTAssertThrowsError(
      try E2eRuntimeProfile.parse(
        environment: [E2eRuntimeProfile.namespaceEnvironmentKey: namespace],
        supportsIsolation: true,
        isCohortBuild: true
      )
    ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .partialEnvironment) }
  }

  func testUnsupportedBuildFailsClosedBeforeParsingManifest() {
    for environment in [
      [:],
      [
        E2eRuntimeProfile.manifestEnvironmentKey: "not-json",
        E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
      ],
    ] {
      XCTAssertThrowsError(
        try E2eRuntimeProfile.parse(
          environment: environment,
          supportsIsolation: false,
          isCohortBuild: true
        )
      ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .unsupportedBuild) }
    }
  }

  func testNamespaceMismatchFailsClosed() throws {
    XCTAssertThrowsError(try parse(environmentNamespace: "vizor_0000000000_w0_0")) {
      XCTAssertEqual($0 as? E2eRuntimeProfileError, .namespaceMismatch)
    }
    XCTAssertThrowsError(try parse(overrides: ["namespace": "vizor_0000000000_w0_0"])) {
      XCTAssertEqual($0 as? E2eRuntimeProfileError, .namespaceMismatch)
    }
  }

  func testStrictManifestRejectsUnknownMissingAndInvalidFields() throws {
    let invalidOverrides: [[String: Any]] = [
      ["schema_version": 2],
      ["scenario_id": "flutter.ios.trailing-"],
      ["scenario_id": "flutter.macos.send"],
      ["run_id": "A1B2C3D4E5"],
      ["worker_id": -1],
      ["worker_id": 1_000_001],
      ["case_index": true],
      ["context_path": "/tmp/context.json"],
      ["lightwalletd_port": 0],
      ["primary_proxy_port": 18_232],
      ["regtest_ironwood_activation_height": 0],
      ["regtest_ironwood_activation_height": UInt64(UInt32.max) + 1],
    ]
    for overrides in invalidOverrides {
      XCTAssertThrowsError(try parse(overrides: overrides)) {
        XCTAssertEqual($0 as? E2eRuntimeProfileError, .invalidManifest)
      }
    }

    var withUnknown = manifest()
    withUnknown["unexpected"] = "value"
    XCTAssertThrowsError(try parse(manifest: withUnknown)) {
      XCTAssertEqual($0 as? E2eRuntimeProfileError, .invalidManifest)
    }

    var withMissing = manifest()
    withMissing.removeValue(forKey: "context_path")
    XCTAssertThrowsError(try parse(manifest: withMissing)) {
      XCTAssertEqual($0 as? E2eRuntimeProfileError, .invalidManifest)
    }

    let encoded = try encodedManifest()
    let fractional = encoded.replacingOccurrences(
      of: #"("case_index"\s*:\s*)17"#,
      with: "$117.0",
      options: .regularExpression
    )
    XCTAssertNotEqual(fractional, encoded)
    XCTAssertThrowsError(
      try E2eRuntimeProfile.parse(
        environment: [
          E2eRuntimeProfile.manifestEnvironmentKey: fractional,
          E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
        ],
        supportsIsolation: true,
        isCohortBuild: true
      )
    ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .invalidManifest) }
  }

  func testEnvironmentValuesMustBeAsciiAndBounded() throws {
    let encoded = try encodedManifest()
    for invalidManifest in [
      String(repeating: " ", count: 2_049) + encoded,
      encoded.replacingOccurrences(of: "send-shielded", with: "send-é"),
    ] {
      XCTAssertThrowsError(
        try E2eRuntimeProfile.parse(
          environment: [
            E2eRuntimeProfile.manifestEnvironmentKey: invalidManifest,
            E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
          ],
          supportsIsolation: true,
          isCohortBuild: true
        )
      ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .invalidManifest) }
    }
    for invalidNamespace in [
      String(repeating: "a", count: 65),
      "vizor_é",
    ] {
      XCTAssertThrowsError(
        try E2eRuntimeProfile.parse(
          environment: [
            E2eRuntimeProfile.manifestEnvironmentKey: encoded,
            E2eRuntimeProfile.namespaceEnvironmentKey: invalidNamespace,
          ],
          supportsIsolation: true,
          isCohortBuild: true
        )
      ) { XCTAssertEqual($0 as? E2eRuntimeProfileError, .invalidManifest) }
    }
  }

  private func parse(
    overrides: [String: Any] = [:],
    environmentNamespace: String? = nil
  ) throws -> E2eRuntimeProfile {
    var value = manifest()
    overrides.forEach { value[$0.key] = $0.value }
    return try parse(manifest: value, environmentNamespace: environmentNamespace)
  }

  private func parse(
    manifest: [String: Any],
    environmentNamespace: String? = nil
  ) throws -> E2eRuntimeProfile {
    try E2eRuntimeProfile.parse(
      environment: [
        E2eRuntimeProfile.manifestEnvironmentKey: try encodedManifest(manifest),
        E2eRuntimeProfile.namespaceEnvironmentKey: environmentNamespace ?? namespace,
      ],
      supportsIsolation: true,
      isCohortBuild: true
    )
  }

  private func manifest() -> [String: Any] {
    [
      "schema_version": 1,
      "scenario_id": "flutter.ios.send-shielded",
      "run_id": "a1b2c3d4e5",
      "worker_id": 2,
      "case_index": 17,
      "namespace": namespace,
      "context_path": "app-support",
      "lightwalletd_port": 18_232,
      "primary_proxy_port": 18_233,
      "zcashd_rpc_port": 18_234,
      "regtest_ironwood_activation_height": 1,
    ]
  }

  private func encodedManifest(_ value: [String: Any]? = nil) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value ?? manifest())
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }
}
