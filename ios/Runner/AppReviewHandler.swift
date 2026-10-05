import Flutter
import StoreKit
import UIKit

@MainActor
final class AppReviewHandler {
  private let viewController: () -> UIViewController?
  private var prepared = false

  init(viewController: @escaping () -> UIViewController?) {
    self.viewController = viewController
  }

  private var activeScene: UIWindowScene? {
    guard UIApplication.shared.applicationState == .active,
          let controller = viewController(),
          controller.presentedViewController == nil,
          let scene = controller.viewIfLoaded?.window?.windowScene,
          scene.activationState == .foregroundActive else { return nil }
    return scene
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepare":
      prepared = activeScene != nil
      result(prepared)
    case "request":
      guard prepared, let scene = activeScene else {
        prepared = false
        result(false)
        return
      }
      prepared = false
      if #available(iOS 16.0, *) {
        AppStore.requestReview(in: scene)
      } else {
        SKStoreReviewController.requestReview(in: scene)
      }
      // StoreKit provides no display, dismissal or rating result.
      result(true)
    case "cancel":
      prepared = false
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
