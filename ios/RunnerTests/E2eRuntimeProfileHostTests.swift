import Foundation

@main
enum E2eRuntimeProfileHostTests {
  static func main() throws {
    let namespace = "vizor_a1b2c3d4e5_w2_17"
    var manifest: [String: Any] = [
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
    let data = try JSONSerialization.data(withJSONObject: manifest)
    let encoded = String(decoding: data, as: UTF8.self)
    let profile = try E2eRuntimeProfile.parse(
      environment: [
        E2eRuntimeProfile.manifestEnvironmentKey: encoded,
        E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
      ],
      supportsIsolation: true
    )

    precondition(profile.namespace == namespace)
    precondition(profile.keychainService("service") == "service.e2e.\(namespace)")
    precondition(
      profile.defaultsSuiteName == "com.keplr.vizor.regtest.e2e.\(namespace)"
    )
    precondition(profile.notificationPrefix == "vizor_e2e_\(namespace).")
    precondition(
      profile.supportDirectory(URL(fileURLWithPath: "/tmp/support")).path
        == "/tmp/support/e2e/\(namespace)"
    )
    let production = try E2eRuntimeProfile.parse(
      environment: [:],
      supportsIsolation: false
    )
    precondition(!production.isIsolated)
    precondition(production.keychainService("service") == "service")

    try expectError(.partialEnvironment) {
      _ = try E2eRuntimeProfile.parse(
        environment: [E2eRuntimeProfile.manifestEnvironmentKey: encoded],
        supportsIsolation: true
      )
    }
    try expectError(.unsupportedBuild) {
      _ = try E2eRuntimeProfile.parse(
        environment: [
          E2eRuntimeProfile.manifestEnvironmentKey: encoded,
          E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
        ],
        supportsIsolation: false
      )
    }
    try expectError(.namespaceMismatch) {
      _ = try E2eRuntimeProfile.parse(
        environment: [
          E2eRuntimeProfile.manifestEnvironmentKey: encoded,
          E2eRuntimeProfile.namespaceEnvironmentKey: "vizor_0000000000_w0_0",
        ],
        supportsIsolation: true
      )
    }

    for invalid in [
      ("scenario_id", "flutter.ios.trailing-" as Any),
      ("case_index", true as Any),
      ("primary_proxy_port", 18_232 as Any),
      ("regtest_ironwood_activation_height", 0 as Any),
    ] {
      let original = manifest[invalid.0]
      manifest[invalid.0] = invalid.1
      let invalidEncoded = String(
        decoding: try JSONSerialization.data(withJSONObject: manifest),
        as: UTF8.self
      )
      try expectError(.invalidManifest, label: "\(invalid.0)=\(invalid.1)") {
        _ = try E2eRuntimeProfile.parse(
          environment: [
            E2eRuntimeProfile.manifestEnvironmentKey: invalidEncoded,
            E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
          ],
          supportsIsolation: true
        )
      }
      manifest[invalid.0] = original
    }
    let fractional = encoded.replacingOccurrences(
      of: #"("case_index"\s*:\s*)17"#,
      with: "$117.0",
      options: .regularExpression
    )
    precondition(fractional != encoded)
    try expectError(.invalidManifest, label: "fractional case_index") {
      _ = try E2eRuntimeProfile.parse(
        environment: [
          E2eRuntimeProfile.manifestEnvironmentKey: fractional,
          E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
        ],
        supportsIsolation: true
      )
    }
    for invalidManifest in [
      String(repeating: " ", count: 2_049) + encoded,
      encoded.replacingOccurrences(of: "send-shielded", with: "send-é"),
    ] {
      try expectError(.invalidManifest, label: "manifest encoding") {
        _ = try E2eRuntimeProfile.parse(
          environment: [
            E2eRuntimeProfile.manifestEnvironmentKey: invalidManifest,
            E2eRuntimeProfile.namespaceEnvironmentKey: namespace,
          ],
          supportsIsolation: true
        )
      }
    }
    for invalidNamespace in [
      String(repeating: "a", count: 65),
      "vizor_é",
    ] {
      try expectError(.invalidManifest, label: "namespace encoding") {
        _ = try E2eRuntimeProfile.parse(
          environment: [
            E2eRuntimeProfile.manifestEnvironmentKey: encoded,
            E2eRuntimeProfile.namespaceEnvironmentKey: invalidNamespace,
          ],
          supportsIsolation: true
        )
      }
    }

    print("E2eRuntimeProfile host tests passed")
  }

  private static func expectError(
    _ expected: E2eRuntimeProfileError,
    label: String = "runtime profile",
    operation: () throws -> Void
  ) throws {
    do {
      try operation()
      preconditionFailure("expected \(expected) for \(label)")
    } catch let error as E2eRuntimeProfileError {
      precondition(error == expected, "unexpected error: \(error)")
    }
  }
}
