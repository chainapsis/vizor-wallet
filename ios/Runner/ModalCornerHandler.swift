import Flutter
import UIKit

/// Geometry only: this view is never inserted into Flutter's view hierarchy.
/// Unavailable or ambiguous host geometry returns nil so Dart keeps its radius.
final class ModalCornerHandler {
  private let probe = UIView()
  private let cache = ModalCornerCache()

  init(defaults: UserDefaults = .standard) {
    // One-way cleanup of the previous persistent cache; geometry stays in RAM.
    defaults.removeObject(forKey: "vizor.modalCorners.v2")
  }

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
    // Normalize only the top edge. Content height must not affect the probe
    // or cache identity; preserve the actual left/right/bottom screen insets.
    let reference = ModalCornerGeometry.referenceRect(for: rect, in: window.bounds)
    let numbers = [reference.minX, reference.width, reference.maxY,
      viewWidth, viewHeight, scale, window.screen.nativeBounds.width,
      window.screen.nativeBounds.height, window.screen.nativeScale]
    let key = ([String(scene.interfaceOrientation.rawValue)] +
      numbers.map { String(Double($0)) }).joined(separator: "|")
    let limit = min(viewWidth, viewHeight) / 2
    if let saved = cache.radii(for: key, limit: Double(limit)) {
      guard ModalCornerGeometry.supports(rect, radii: saved) else { result(nil); return }
      result(["bottomLeft": saved[0], "bottomRight": saved[1], "cacheHit": true])
      return
    }
    // Even the minimum radius needs enough room. Avoid calculating tiny cards.
    guard ModalCornerGeometry.supports(rect, radii: [32, 32]) else { result(nil); return }
    probe.frame = reference
    probe.cornerConfiguration = .corners(
      topLeftRadius: .fixed(32), topRightRadius: .fixed(32),
      bottomLeftRadius: .containerConcentric(minimum: 32),
      bottomRightRadius: .containerConcentric(minimum: 32))
    probe.setNeedsLayout()
    probe.layoutIfNeeded()
    let left = probe.effectiveRadius(corner: .bottomLeft)
    let right = probe.effectiveRadius(corner: .bottomRight)
    guard left.isFinite, right.isFinite, left >= 0, right >= 0 else { result(nil); return }
    guard left >= 32, right >= 32, left <= limit, right <= limit else { result(nil); return }
    let radii = [Double(left), Double(right)]
    guard ModalCornerGeometry.supports(rect, radii: radii) else { result(nil); return }
    cache.store(radii, for: key, limit: Double(limit))
    result(["bottomLeft": left, "bottomRight": right, "cacheHit": false])
  }
}

/// Conservative app policy, not a UIKit formula. Keep generous separation
/// between top/bottom corners and between the two bottom corners.
enum ModalCornerGeometry {
  static func referenceRect(for rect: CGRect, in bounds: CGRect) -> CGRect {
    CGRect(x: rect.minX, y: bounds.minY, width: rect.width,
      height: rect.maxY - bounds.minY)
  }

  static func supports(_ rect: CGRect, radii: [Double]) -> Bool {
    guard radii.count == 2, radii.allSatisfy({ $0.isFinite && $0 >= 32 }) else { return false }
    let bottom = max(radii[0], radii[1])
    return Double(rect.height) >= 2 * (32 + bottom) && Double(rect.width) >= 4 * bottom
  }
}

/// Engine-owned, bounded memory LRU. No disk reads/writes and no modal lifetime
/// coupling. A new engine/process starts empty; failed queries are never stored.
final class ModalCornerCache {
  private var entries: [String: [Double]] = [:]
  private var order: [String] = []

  func radii(for key: String, limit: Double) -> [Double]? {
    guard let value = entries[key], valid(value, limit: limit) else { return nil }
    order.removeAll { $0 == key }
    order.append(key)
    return value
  }

  func store(_ value: [Double], for key: String, limit: Double) {
    guard valid(value, limit: limit) else { return }
    order.removeAll { $0 == key }
    while order.count >= 64 { entries.removeValue(forKey: order.removeFirst()) }
    entries[key] = value
    order.append(key)
  }

  private func valid(_ value: [Double], limit: Double) -> Bool {
    value.count == 2 && limit.isFinite &&
      value.allSatisfy { $0.isFinite && $0 >= 32 && $0 <= limit }
  }
}
