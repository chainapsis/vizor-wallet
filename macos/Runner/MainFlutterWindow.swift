import Cocoa
import FlutterMacOS
import zcash_desktop_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let desktopWindowViewController = ZcashDesktopWindowBootstrap.start(
      mainFlutterWindow: self
    )
    RegisterGeneratedPlugins(registry: desktopWindowViewController.flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
