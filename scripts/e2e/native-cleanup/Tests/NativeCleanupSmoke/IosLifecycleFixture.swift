// MANUAL SDK lifecycle fixture, not a wallet or a financial scenario.
// Compile only as the dedicated fresh-Simulator test app. It declares synthetic
// context using the actual native profile; writes no Keychain/preference values.
// The fixture module defaults to MainActor: its sole profile owner/caller is
// UIApplicationDelegate's startup, with no background workers or shared callers.
#if os(iOS) && targetEnvironment(simulator) && DEBUG
import Foundation
import UIKit

@main enum IosLifecycleFixture {
  @MainActor static func main() {
    UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(LifecycleFixtureDelegate.self))
  }
}

@MainActor final class LifecycleFixtureDelegate: UIResponder, UIApplicationDelegate {
  func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    do {
      guard Bundle.main.object(forInfoDictionaryKey: "VizorE2eIosLifecycleFixture") as? Bool == true else {
        throw CleanupFailure("not_lifecycle_fixture")
      }
      let profile = try E2eRuntimeProfile.installFromEnvironment()
      guard let namespace = profile.namespace, let suite = profile.defaultsSuiteName,
        let prefix = profile.notificationPrefix, let executable = Bundle.main.executableURL,
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      else { throw CleanupFailure("fixture_scope_unavailable") }
      let identifier = try iosHelperApplicationIdentifier(iosSimulatedEntitlements(Data(contentsOf: executable)))
      // Scope derives names only; the dummy nonce grants no cleanup authority.
      let scope = try IosCleanupScope(namespace: namespace,
        simulatorUdid: ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "",
        ownerNonce: "0000000000000000", expectedTeam: String(identifier.prefix(10)))
      let directory = support.appendingPathComponent("e2e", isDirectory: true).appendingPathComponent(namespace, isDirectory: true)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw CleanupFailure("fixture_support_not_preallocated")
      }
      let context: [String: Any] = ["schema_version": 1, "namespace": namespace,
        "pid": ProcessInfo.processInfo.processIdentifier, "support_directory": directory.path,
        "secure_store_services": scope.services, "preferences_prefix": scope.preferencesPrefix,
        "native_preferences_suite": suite, "notification_identifier_prefix": prefix,
        "os_background_scheduling_enabled": false, "storage_cleanup_completed": false]
      let data = try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys])
      try data.write(to: directory.appendingPathComponent("native-context.json"), options: .atomic)
      print("lifecycle_fixture_ready")
      fflush(stdout)
      // Stay in UIApplication's loop until the exact owned SDK stop. No window,
      // wallet bootstrap, backend, background registration or authorization UI.
    } catch {
      FileHandle.standardError.write(Data("lifecycle_fixture_refused\n".utf8))
      exit(2)
    }
    return true
  }
}
#else
#error("The manual lifecycle fixture only supports Debug iOS Simulator")
#endif
