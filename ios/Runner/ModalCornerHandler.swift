import Flutter
import UIKit

/// Geometry only: this view is never inserted into Flutter's view hierarchy.
/// Unavailable or ambiguous host geometry returns nil so Dart keeps its radius.
final class ModalCornerHandler {
  private let probe = UIView()
  private let cache = ModalCornerCache()

  private var hardware: String {
    if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
      return simulated
    }
    var info = utsname()
    uname(&info)
    return withUnsafeBytes(of: &info.machine) { bytes in
      String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
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
    // Validate the current host above even on a cache hit. Geometry includes
    // actual height: UIKit may constrain radii for unusually short cards.
    let numbers = [rect.minX, rect.minY, rect.width, rect.height,
      viewWidth, viewHeight, scale, window.screen.nativeBounds.width,
      window.screen.nativeBounds.height, window.screen.nativeScale]
    let key = ([hardware, ProcessInfo.processInfo.operatingSystemVersionString,
      String(scene.interfaceOrientation.rawValue), "minimum32"] +
      numbers.map { String(Double($0)) }).joined(separator: "|")
    let limit = min(viewWidth, viewHeight) / 2
    if let saved = cache.radii(for: key, limit: Double(limit)) {
      result(["bottomLeft": saved[0], "bottomRight": saved[1], "cacheHit": true])
      return
    }
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
    guard left >= 32, right >= 32, left <= limit, right <= limit else { result(nil); return }
    cache.store([Double(left), Double(right)], for: key, limit: Double(limit))
    result(["bottomLeft": left, "bottomRight": right, "cacheHit": false])
  }
}

/// App-wide geometry memoization, independent of modal lifetime. Includes a
/// bounded persisted LRU; misses/errors never become successful cache entries.
final class ModalCornerCache {
  static let storageKey = "vizor.modalCorners.v2"
  private let defaults: UserDefaults
  private var entries: [String: [Double]]
  private var order: [String]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let stored = defaults.dictionary(forKey: Self.storageKey) ?? [:]
    let values = stored["entries"] as? [String: [Double]] ?? [:]
    entries = values.count <= 64 ? values : [:]
    order = (stored["order"] as? [String] ?? []).filter { values[$0] != nil && values.count <= 64 }
    // Recover gracefully from a truncated/malformed persisted order.
    order = Array(NSOrderedSet(array: order)) as? [String] ?? []
    for key in entries.keys.sorted() where !order.contains(key) { order.append(key) }
  }

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
    defaults.set(["entries": entries, "order": order], forKey: Self.storageKey)
  }

  private func valid(_ value: [Double], limit: Double) -> Bool {
    value.count == 2 && limit.isFinite &&
      value.allSatisfy { $0.isFinite && $0 >= 32 && $0 <= limit }
  }
}
