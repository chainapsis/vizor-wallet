import Cocoa
import FlutterMacOS

public final class ZcashDesktopWindowPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zcash_desktop_window/methods",
      binaryMessenger: registrar.messenger
    )
    let instance = ZcashDesktopWindowPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(true)
    case "getTitlebarInset":
      result(ZcashDesktopWindowBootstrap.titlebarInset())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
