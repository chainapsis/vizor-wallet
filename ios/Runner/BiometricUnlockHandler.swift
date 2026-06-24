import Flutter
import Foundation
import LocalAuthentication
import Security

/// Passcode escrow behind the current biometric set.
///
/// The wallet passcode is stored in a dedicated keychain item whose
/// access control requires the CURRENT Face ID / Touch ID enrollment
/// (`.biometryCurrentSet`): re-enrolling a face invalidates the item,
/// which Dart maps to "fall back to the passcode and re-enable".
/// Reads trigger the system biometric prompt via LAContext. The device
/// passcode is intentionally NOT accepted as a fallback — it is not
/// the wallet passcode.
final class BiometricUnlockHandler {
  static let shared = BiometricUnlockHandler()

  private static let service = "com.zcash.wallet.biometric-unlock"
  private static let account = "wallet-passcode-escrow"

  private init() {}

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      result(availability())
    case "enable":
      guard
        let args = call.arguments as? [String: Any],
        let passcode = args["passcode"] as? String,
        !passcode.isEmpty
      else {
        result(FlutterError(code: "failed", message: "passcode is required", details: nil))
        return
      }
      enable(passcode: passcode, result: result)
    case "disable":
      disable(result: result)
    case "read":
      let args = call.arguments as? [String: Any]
      let reason = (args?["reason"] as? String) ?? "Unlock your wallet"
      read(reason: reason, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func availability() -> [String: Any] {
    let context = LAContext()
    var error: NSError?
    let canEvaluate = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &error
    )

    let kind: String
    switch context.biometryType {
    case .faceID:
      kind = "face"
    case .touchID:
      kind = "fingerprint"
    default:
      kind = "none"
    }

    // canEvaluatePolicy == false with biometryNotEnrolled still reports
    // the hardware kind; expose both so the UI can distinguish "no
    // hardware" from "nothing enrolled yet".
    let notEnrolled = (error as? LAError)?.code == .biometryNotEnrolled
    let supported = canEvaluate || notEnrolled || kind != "none"
    return [
      "supported": supported,
      "enrolled": canEvaluate,
      "kind": kind,
    ]
  }

  private func accessControl() -> SecAccessControl? {
    SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      .biometryCurrentSet,
      nil
    )
  }

  private func enable(passcode: String, result: @escaping FlutterResult) {
    guard let access = accessControl() else {
      result(FlutterError(code: "failed", message: "access control unavailable", details: nil))
      return
    }
    guard let data = passcode.data(using: .utf8) else {
      result(FlutterError(code: "failed", message: "encoding failed", details: nil))
      return
    }

    // Keychain writes can block; keep them off the platform thread.
    DispatchQueue.global(qos: .userInitiated).async {
      let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.account,
      ]
      SecItemDelete(deleteQuery as CFDictionary)

      let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.account,
        kSecValueData as String: data,
        kSecAttrAccessControl as String: access,
      ]
      let status = SecItemAdd(addQuery as CFDictionary, nil)
      DispatchQueue.main.async {
        if status == errSecSuccess {
          result(nil)
        } else {
          result(FlutterError(
            code: "failed",
            message: "keychain write failed (\(status))",
            details: nil
          ))
        }
      }
    }
  }

  private func disable(result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.account,
      ]
      let status = SecItemDelete(query as CFDictionary)
      DispatchQueue.main.async {
        if status == errSecSuccess || status == errSecItemNotFound {
          result(nil)
        } else {
          result(FlutterError(
            code: "failed",
            message: "keychain delete failed (\(status))",
            details: nil
          ))
        }
      }
    }
  }

  private func read(reason: String, result: @escaping FlutterResult) {
    let context = LAContext()
    context.localizedReason = reason
    // No system fallback button: the in-app numpad is the fallback and
    // the device passcode must not stand in for the wallet passcode.
    context.localizedFallbackTitle = ""

    DispatchQueue.global(qos: .userInitiated).async {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: Self.account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecUseAuthenticationContext as String: context,
      ]

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)

      DispatchQueue.main.async {
        switch status {
        case errSecSuccess:
          guard
            let data = item as? Data,
            let passcode = String(data: data, encoding: .utf8),
            !passcode.isEmpty
          else {
            result(FlutterError(code: "failed", message: "escrow unreadable", details: nil))
            return
          }
          result(passcode)
        case errSecUserCanceled:
          result(FlutterError(code: "cancelled", message: nil, details: nil))
        case errSecItemNotFound:
          // Either never enabled or invalidated by re-enrollment — both
          // mean the passcode path must take over and the flag resets.
          result(FlutterError(code: "invalidated", message: nil, details: nil))
        case errSecAuthFailed:
          // Failed/locked-out biometry; Dart falls back to the numpad.
          result(FlutterError(code: "failed", message: "authentication failed", details: nil))
        default:
          result(FlutterError(
            code: "failed",
            message: "keychain read failed (\(status))",
            details: nil
          ))
        }
      }
    }
  }
}

/// Device-owner verification for destructive local actions.
///
/// This is separate from biometric unlock: it never reads the wallet passcode
/// escrow, and it intentionally requires the device passcode only — Face ID /
/// Touch ID are never offered for this destructive gate.
final class DeviceOwnerAuthHandler {
  static let shared = DeviceOwnerAuthHandler()

  private init() {}

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "verify":
      let args = call.arguments as? [String: Any]
      let reason = (args?["reason"] as? String) ?? "Confirm reset Vizor"
      verify(reason: reason, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func verify(reason: String, result: @escaping FlutterResult) {
    // Passcode-only by design: this destructive gate must never be satisfied
    // by a Face ID / Touch ID glance. There is no LAPolicy that accepts the
    // device passcode while skipping biometry, so instead of
    // `.deviceOwnerAuthentication` (biometry-first) we evaluate a
    // `.devicePasscode`-constrained access control, which only ever presents
    // the device passcode entry.
    //
    // NOTE: the iOS Simulator cannot present `.devicePasscode` UI, so this
    // path only completes on a real device. On the simulator the evaluation
    // fails fast (no prompt), which fails safe — the wallet is never wiped.
    var accessControlError: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      .devicePasscode,
      &accessControlError
    ) else {
      result(FlutterError(
        code: "unavailable",
        message: "Device passcode is not configured.",
        details: nil
      ))
      return
    }

    let context = LAContext()
    context.evaluateAccessControl(
      accessControl,
      operation: .useItem,
      localizedReason: reason
    ) { success, error in
      DispatchQueue.main.async {
        if success {
          result(true)
          return
        }

        guard let laError = error as? LAError else {
          result(FlutterError(code: "failed", message: error?.localizedDescription, details: nil))
          return
        }

        switch laError.code {
        case .userCancel, .systemCancel, .appCancel:
          result(false)
        case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled:
          result(FlutterError(code: "unavailable", message: laError.localizedDescription, details: nil))
        default:
          result(FlutterError(code: "failed", message: laError.localizedDescription, details: nil))
        }
      }
    }
  }
}
