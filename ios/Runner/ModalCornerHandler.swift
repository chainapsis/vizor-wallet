import Flutter
import UIKit

/// Geometry only: this view is never inserted into Flutter's view hierarchy.
/// Unavailable or ambiguous host geometry returns nil so Dart keeps its radius.
final class ModalCornerHandler {
  private let probe = UIView()

  func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    guard call.method == "resolve" else { result(FlutterMethodNotImplemented); return }
    guard #available(iOS 26.0, *), Thread.isMainThread,
      UIApplication.shared.applicationState == .active,
      let args = call.arguments as? [String: Any]
    else { result(nil); return }

    func number(_ key: String) -> CGFloat? {
      guard let value = args[key] as? NSNumber, value.doubleValue.isFinite else { return nil }
      return CGFloat(value.doubleValue)
    }
    guard let x = number("x"), let y = number("y"),
      let width = number("width"), let height = number("height"),
      let viewWidth = number("viewWidth"), let viewHeight = number("viewHeight"),
      let scale = number("scale"), width > 0, height > 0, scale > 0
    else { result(nil); return }

    // A detached UIView has no explicit scene binding. Limit this optimization
    // to the single foreground, full-screen iPhone host verified by the probe.
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    guard scenes.count == 1, let scene = scenes.first,
      scene.session.role == .windowApplication,
      let window = scene.windows.first(where: { $0.isKeyWindow }),
      let controller = window.rootViewController as? FlutterViewController,
      controller.traitCollection.userInterfaceIdiom == .phone,
      let root = controller.viewIfLoaded,
      abs(root.bounds.width - viewWidth) < 0.5,
      abs(root.bounds.height - viewHeight) < 0.5,
      abs(window.bounds.width - viewWidth) < 0.5,
      abs(window.bounds.height - viewHeight) < 0.5,
      abs(window.screen.scale - scale) < 0.01,
      window.convert(window.bounds, to: scene.coordinateSpace) == scene.coordinateSpace.bounds
    else { result(nil); return }

    let rect = root.convert(CGRect(x: x, y: y, width: width, height: height), to: window)
    guard window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect) else { result(nil); return }
    probe.frame = rect
    probe.cornerConfiguration = .corners(
      topLeftRadius: .fixed(32), topRightRadius: .fixed(32),
      bottomLeftRadius: .containerConcentric(minimum: 32),
      bottomRightRadius: .containerConcentric(minimum: 32))
    probe.setNeedsLayout()
    probe.layoutIfNeeded()
    let left = probe.effectiveRadius(corner: .bottomLeft)
    let right = probe.effectiveRadius(corner: .bottomRight)
    guard left.isFinite, right.isFinite, left >= 0, right >= 0 else { result(nil); return }
    result(["bottomLeft": left, "bottomRight": right])
  }
}
