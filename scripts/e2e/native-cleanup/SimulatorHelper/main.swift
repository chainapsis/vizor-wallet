#if os(iOS) && targetEnvironment(simulator)
import Foundation
import UIKit

// Build only as the dedicated helper app; never add to the wallet target.
@MainActor final class CleanupAppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    Task { @MainActor in
      do {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 10, ["--mode", "--namespace", "--simulator", "--owner-nonce", "--team"]
          == stride(from: 0, to: 10, by: 2).map({ arguments[$0] }),
          let mode = CleanupMode(rawValue: arguments[1])
        else { throw CleanupFailure("invalid_arguments") }
        let scope = try IosCleanupScope(namespace: arguments[3], simulatorUdid: arguments[5],
          ownerNonce: arguments[7], expectedTeam: arguments[9])
        let receipt = await inspectOrCleanIos(scope, mode: mode, system: NativeIosCleanupSystem())
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(receipt) + Data([10]))
        exit(receipt.completed ? 0 : 1)
      } catch {
        FileHandle.standardError.write(Data("ios_cleanup_helper_refused\n".utf8))
        exit(2)
      }
    }
    return true
  }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(CleanupAppDelegate.self))
#else
#error("The cleanup helper only supports iOS Simulator")
#endif
