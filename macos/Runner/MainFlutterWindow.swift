import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Holds the stream handler for the lifetime of the window so the
  // registered NotificationCenter observers don't get ARC-released.
  private var fullscreenStreamHandler: FullscreenStreamHandler?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Observe NSWindow fullscreen notifications via NotificationCenter
    // (not the NSWindow.delegate slot — that's owned by window_manager).
    // The Dart side drives the visible effect change on each willEnter /
    // willExit event.
    let fullscreenChannel = FlutterEventChannel(
      name: "app.zcash/fullscreen_events",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let handler = FullscreenStreamHandler()
    fullscreenChannel.setStreamHandler(handler)
    fullscreenStreamHandler = handler

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

/// Pushes `"willEnter"` / `"willExit"` events into the
/// `app.zcash/fullscreen_events` Flutter event channel whenever an NSWindow
/// is about to enter or leave fullscreen. Uses NotificationCenter so the
/// NSWindow.delegate slot stays free for `window_manager`.
class FullscreenStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(willEnterFullScreen),
      name: NSWindow.willEnterFullScreenNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(willExitFullScreen),
      name: NSWindow.willExitFullScreenNotification,
      object: nil
    )
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    sink = nil
    return nil
  }

  @objc private func willEnterFullScreen() {
    sink?("willEnter")
  }

  @objc private func willExitFullScreen() {
    sink?("willExit")
  }
}
