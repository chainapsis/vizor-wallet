import Flutter
import UIKit

/// An app-owned bridge to the system tab bar. UIKit owns its material and motion;
/// Flutter remains the owner of destinations and navigation history.
final class NativeTabBarPlugin {
  static let channelName = "com.zcash.wallet/native_tab_bar"
  private let channel: FlutterMethodChannel

  init(registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "getCapabilities" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 26.0, *) {
        result(["supported": true])
      } else {
        result(["supported": false])
      }
    }
    registrar.register(
      NativeTabBarFactory(messenger: messenger), withId: Self.channelName
    )
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}

private final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    NativeTabBarPlatformView(frame: frame, viewId: viewId, args: args, messenger: messenger)
  }
}

struct NativeTabBarItemConfiguration: Equatable {
  let id: String
  let label: String
  let icon: Data
  let iconScale: Double
}

struct NativeTabBarSnapshot {
  let items: [NativeTabBarItemConfiguration]
  let selectedId: String
  let style: UIUserInterfaceStyle
  let direction: UIUserInterfaceLayoutDirection
  let hidden: Bool

  init(arguments: Any?) throws {
    guard let args = arguments as? [String: Any],
      let rawItems = args["items"] as? [[String: Any]], !rawItems.isEmpty,
      let selectedId = args["selectedId"] as? String,
      let brightness = args["brightness"] as? String,
      let direction = args["direction"] as? String,
      ["light", "dark"].contains(brightness), ["ltr", "rtl"].contains(direction)
    else { throw NativeTabBarError.invalidSnapshot }
    guard args["hidden"] == nil || args["hidden"] is Bool else {
      throw NativeTabBarError.invalidSnapshot
    }

    var ids = Set<String>()
    var items: [NativeTabBarItemConfiguration] = []
    for raw in rawItems {
      guard let id = raw["id"] as? String, !id.isEmpty, ids.insert(id).inserted,
        let label = raw["label"] as? String, !label.isEmpty,
        let icon = raw["icon"] as? FlutterStandardTypedData, !icon.data.isEmpty,
        let scale = raw["iconScale"] as? NSNumber,
        scale.doubleValue.isFinite, scale.doubleValue > 0
      else { throw NativeTabBarError.invalidSnapshot }
      items.append(.init(id: id, label: label, icon: icon.data, iconScale: scale.doubleValue))
    }
    guard ids.contains(selectedId) else { throw NativeTabBarError.invalidSnapshot }
    self.items = items
    self.selectedId = selectedId
    style = brightness == "dark" ? .dark : .light
    self.direction = direction == "rtl" ? .rightToLeft : .leftToRight
    hidden = args["hidden"] as? Bool ?? false
  }
}

enum NativeTabBarError: Error {
  case invalidSnapshot
  case invalidIcon
}

/// Transparent placement only. No tab-bar appearance, tint, clipping or gesture
/// customizations: the system is responsible for the glass and selection lens.
final class NativeTabBarHostView: UIView {
  let tabBar = UITabBar()
  var onHeightChanged: ((CGFloat) -> Void)?
  private var lastHeight: CGFloat?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    addSubview(tabBar)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var preferredHeight: CGFloat {
    let height = tabBar.sizeThatFits(
      CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
    ).height
    return height.isFinite && height > 0 ? height : tabBar.intrinsicContentSize.height
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    tabBar.frame = bounds
    let height = preferredHeight
    if height.isFinite, height > 0, lastHeight == nil || abs(height - lastHeight!) > 0.5 {
      lastHeight = height
      onHeightChanged?(height)
    }
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    setNeedsLayout()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    setNeedsLayout()
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
    // Do not make the transparent wrapper an additional interactive surface.
    return tabBar.hitTest(convert(point, to: tabBar), with: event)
  }
}

final class NativeTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let channel: FlutterMethodChannel
  private let host: NativeTabBarHostView
  private var configurations: [String: NativeTabBarItemConfiguration] = [:]
  private var itemsById: [String: UITabBarItem] = [:]
  private var orderedIds: [String] = []
  private var pendingHeight: CGFloat?
  private var heightDeliveryScheduled = false

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "\(NativeTabBarPlugin.channelName)/\(viewId)", binaryMessenger: messenger
    )
    host = NativeTabBarHostView(frame: frame)
    super.init()
    host.tabBar.delegate = self
    host.onHeightChanged = { [weak self] height in self?.scheduleHeight(height) }
    // The view factory cannot return a FlutterError. An invalid creation stays
    // empty; subsequent updates use the same strict, atomic validation below.
    if let snapshot = try? NativeTabBarSnapshot(arguments: args) {
      try? apply(snapshot)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "update":
        do {
          try self.apply(NativeTabBarSnapshot(arguments: call.arguments))
          result(nil)
        } catch {
          result(FlutterError(
            code: "invalid_snapshot", message: "Invalid native tab bar configuration.", details: nil
          ))
        }
      case "getHeight":
        result(Double(self.host.preferredHeight))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    host.tabBar.delegate = nil
    host.onHeightChanged = nil
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { host }

  private func apply(_ snapshot: NativeTabBarSnapshot) throws {
    // Decode all new images before touching the displayed state. A bad image
    // must not partially update the labels or invalidate the selected item.
    var nextItems: [String: UITabBarItem] = [:]
    var newImages: [String: UIImage] = [:]
    for config in snapshot.items {
      nextItems[config.id] = itemsById[config.id] ?? UITabBarItem()
      let previous = configurations[config.id]
      if previous?.icon != config.icon || previous?.iconScale != config.iconScale {
        guard let image = UIImage(data: config.icon, scale: config.iconScale) else {
          throw NativeTabBarError.invalidIcon
        }
        newImages[config.id] = image.withRenderingMode(.alwaysTemplate)
      }
    }

    let nextIds = snapshot.items.map(\.id)
    let itemsChanged = nextIds != orderedIds
    for config in snapshot.items {
      let item = nextItems[config.id]!
      if item.title != config.label { item.title = config.label }
      item.accessibilityIdentifier = config.id
      if let image = newImages[config.id] {
        item.image = image
        item.selectedImage = image
      }
    }
    configurations = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
    itemsById = nextItems
    orderedIds = nextIds
    if itemsChanged {
      host.tabBar.setItems(nextIds.compactMap { nextItems[$0] }, animated: false)
    }
    // Assigning selectedItem does not invoke the user-selection delegate.
    if host.tabBar.selectedItem !== nextItems[snapshot.selectedId] {
      host.tabBar.selectedItem = nextItems[snapshot.selectedId]
    }
    host.overrideUserInterfaceStyle = snapshot.style
    host.isHidden = snapshot.hidden
    host.isUserInteractionEnabled = !snapshot.hidden
    let semantic: UISemanticContentAttribute = snapshot.direction == .rightToLeft
      ? .forceRightToLeft : .forceLeftToRight
    host.semanticContentAttribute = semantic
    host.tabBar.semanticContentAttribute = semantic
    if #available(iOS 17.0, *) {
      host.tabBar.traitOverrides.layoutDirection = snapshot.direction == .rightToLeft
        ? .rightToLeft : .leftToRight
    }
    host.setNeedsLayout()
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard tabBar === host.tabBar,
      let id = orderedIds.first(where: { itemsById[$0] === item })
    else { return }
    // Re-selection is intentional: Flutter may return the branch to its root.
    channel.invokeMethod("select", arguments: ["id": id])
  }

  private func scheduleHeight(_ height: CGFloat) {
    pendingHeight = height
    guard !heightDeliveryScheduled else { return }
    heightDeliveryScheduled = true
    // Layout can occur inside a platform-view resize. Deliver after that pass
    // so Flutter can change its constraints without reentering UIKit layout.
    DispatchQueue.main.async { [weak self] in
      guard let self, let height = self.pendingHeight else { return }
      self.heightDeliveryScheduled = false
      self.pendingHeight = nil
      self.channel.invokeMethod("layout", arguments: ["height": Double(height)])
    }
  }
}
