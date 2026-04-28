import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 26.0, *) {
      BackgroundSyncManager.shared.registerBackgroundTask()
      TxTrackManager.shared.registerTask()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    // MethodChannel for background sync control
    let methodChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/background_sync",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "isAvailable":
        #if targetEnvironment(simulator)
          result(false)
        #else
          if #available(iOS 26.0, *) {
            result(true)
          } else {
            result(false)
          }
        #endif
      case "startBackgroundSync":
        if #available(iOS 26.0, *) {
          let args = call.arguments as? [String: Any]
          let lightwalletdUrl = args?["lightwalletdUrl"] as? String
          let network = args?["network"] as? String
          let success = BackgroundSyncManager.shared.startBackgroundSync(
            lightwalletdUrl: lightwalletdUrl,
            network: network
          )
          result(success)
        } else {
          result(false)
        }
      case "stopBackgroundSync":
        if #available(iOS 26.0, *) {
          let success = BackgroundSyncManager.shared.stopBackgroundSync()
          result(success)
        } else {
          result(false)
        }
      case "updateEndpoint":
        let args = call.arguments as? [String: Any]
        let lightwalletdUrl = args?["lightwalletdUrl"] as? String
        let network = args?["network"] as? String
        RpcEndpointConfigStore.save(
          lightwalletdUrl: lightwalletdUrl,
          network: network
        )
        result(true)
      case "startTxTracking":
        if #available(iOS 26.0, *) {
          let args = call.arguments as? [String: Any]
          let lightwalletdUrl = args?["lightwalletdUrl"] as? String
          let success = TxTrackManager.shared.startTxTracking(
            lightwalletdUrl: lightwalletdUrl
          )
          result(success)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // EventChannel for sync progress (Swift → Dart)
    let eventChannel = FlutterEventChannel(
      name: "com.zcash.wallet/sync_progress",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(SyncProgressStreamHandler.shared)
  }
}
