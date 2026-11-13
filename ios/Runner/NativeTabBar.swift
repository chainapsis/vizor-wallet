import CoreFoundation
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
  let visibilityEpoch: Int64
  let selectedTintColor: UInt32?

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
    if let rawEpoch = args["visibilityEpoch"] {
      guard let number = rawEpoch as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(), number.int64Value >= 0,
        number.doubleValue == Double(number.int64Value)
      else { throw NativeTabBarError.invalidSnapshot }
      visibilityEpoch = number.int64Value
    } else {
      visibilityEpoch = 0
    }
    if let rawColor = args["selectedTintColor"] {
      guard let number = rawColor as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(),
        let argb = UInt32(exactly: number.int64Value),
        number.doubleValue == Double(argb)
      else { throw NativeTabBarError.invalidSnapshot }
      selectedTintColor = argb
    } else {
      selectedTintColor = nil
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

/// Transparent placement only. Item tint comes from the app; UIKit remains
/// responsible for the material, clipping and selection-lens interaction.
final class NativeTabBarHostView: UIView {
  let tabBar = NativeSlidingTabBar()
  let slidingView = UIView()
  var onHeightChanged: ((CGFloat) -> Void)?
  var onGeometryChanged: (() -> Void)?
  var onAttachmentChanged: (() -> Void)?
  private var lastHeight: CGFloat?
  private var lastSize: CGSize?
  private var lastInsets: UIEdgeInsets?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    slidingView.backgroundColor = .clear
    slidingView.isHidden = true
    addSubview(slidingView)
    slidingView.addSubview(tabBar)
    tabBar.host = self
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
    // The outer platform-view rectangle never moves or collapses. In particular
    // do not assign frame while the sliding view has a nonidentity transform.
    slidingView.bounds = CGRect(origin: .zero, size: bounds.size)
    slidingView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    tabBar.frame = slidingView.bounds
    let height = preferredHeight
    if height.isFinite, height > 0, lastHeight == nil || abs(height - lastHeight!) > 0.5 {
      lastHeight = height
      onHeightChanged?(height)
    }
    if lastSize != bounds.size || lastInsets != safeAreaInsets {
      lastSize = bounds.size
      lastInsets = safeAreaInsets
      onGeometryChanged?()
    }
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    setNeedsLayout()
    onAttachmentChanged?()
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

/// UIKit otherwise recomputes a moving bar's safe area from its animated screen
/// position, which changes sizeThatFits and can feed back into Flutter's height.
/// Anchor that geometry to the stationary host while leaving the material alone.
final class NativeSlidingTabBar: UITabBar {
  weak var host: NativeTabBarHostView?
  override var safeAreaInsets: UIEdgeInsets { host?.safeAreaInsets ?? super.safeAreaInsets }
}

protocol NativeTabBarAnimation: AnyObject {
  func cancel()
}

typealias NativeTabBarAnimator = (
  UIView, CGAffineTransform, TimeInterval, UIView.AnimationCurve, @escaping () -> Void
) -> NativeTabBarAnimation

private final class NativeTabBarUIKitAnimation: NativeTabBarAnimation {
  private let animator: UIViewPropertyAnimator
  private weak var view: UIView?
  private let startTransform: CGAffineTransform

  init(
    view: UIView, target: CGAffineTransform, duration: TimeInterval,
    curve: UIView.AnimationCurve, completion: @escaping () -> Void
  ) {
    self.view = view
    startTransform = view.transform
    animator = UIViewPropertyAnimator(duration: duration, curve: curve)
    animator.addAnimations { [weak view] in view?.transform = target }
    animator.addCompletion { position in if position == .end { completion() } }
    animator.startAnimation()
  }

  func cancel() {
    let current = view?.layer.presentation()?.affineTransform()
      ?? (animator.state == .active ? startTransform : view?.transform ?? startTransform)
    animator.stopAnimation(true)
    if let view { UIView.performWithoutAnimation { view.transform = current } }
  }
}

private struct NativeTabBarPreparedSnapshot {
  let configuration: NativeTabBarSnapshot
  let images: [String: UIImage]
}

final class NativeTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private enum Phase { case detached, hidden, entering, visible, exiting }
  private let channel: FlutterMethodChannel
  private let host: NativeTabBarHostView
  private let animate: NativeTabBarAnimator
  private let reduceMotion: () -> Bool
  private let attachmentProvider: (() -> Bool)?
  private let notificationCenter: NotificationCenter
  private var motionObserver: NSObjectProtocol?
  private var animation: NativeTabBarAnimation?
  private var animationGeneration: UInt64 = 0
  private var phase: Phase = .detached
  private var targetHidden = true
  private var visibilityEpoch: Int64 = 0
  private var presentationRevision: Int64 = 0
  private var pendingSnapshot: NativeTabBarPreparedSnapshot?
  private var configurations: [String: NativeTabBarItemConfiguration] = [:]
  private var itemsById: [String: UITabBarItem] = [:]
  private var orderedIds: [String] = []
  private var selectedTintColor: UInt32?
  private var pendingHeight: CGFloat?
  private var heightDeliveryScheduled = false

  init(
    frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger,
    animator: NativeTabBarAnimator? = nil,
    reduceMotion: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled },
    attachmentProvider: (() -> Bool)? = nil,
    notificationCenter: NotificationCenter = .default
  ) {
    channel = FlutterMethodChannel(
      name: "\(NativeTabBarPlugin.channelName)/\(viewId)", binaryMessenger: messenger
    )
    host = NativeTabBarHostView(frame: frame)
    animate = animator ?? { view, transform, duration, curve, completion in
      NativeTabBarUIKitAnimation(
        view: view, target: transform, duration: duration, curve: curve, completion: completion
      )
    }
    self.reduceMotion = reduceMotion
    self.attachmentProvider = attachmentProvider
    self.notificationCenter = notificationCenter
    super.init()
    host.tabBar.delegate = self
    host.onHeightChanged = { [weak self] height in self?.scheduleHeight(height) }
    host.onGeometryChanged = { [weak self] in self?.geometryChanged() }
    host.onAttachmentChanged = { [weak self] in self?.attachmentChanged() }
    setInputEnabled(false)
    motionObserver = notificationCenter.addObserver(
      forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self, self.reduceMotion(), self.phase == .entering || self.phase == .exiting else {
        return
      }
      self.transition(toHidden: self.targetHidden)
    }
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
      case "getPresentation":
        result(self.presentation)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    animationGeneration &+= 1
    animation?.cancel()
    if let motionObserver { notificationCenter.removeObserver(motionObserver) }
    host.tabBar.delegate = nil
    host.onHeightChanged = nil
    host.onGeometryChanged = nil
    host.onAttachmentChanged = nil
    host.slidingView.isHidden = true
    host.isUserInteractionEnabled = false
    host.accessibilityElementsHidden = true
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { host }

  private func apply(_ snapshot: NativeTabBarSnapshot) throws {
    guard snapshot.visibilityEpoch >= visibilityEpoch else {
      throw NativeTabBarError.invalidSnapshot
    }
    // Preparing is atomic even while hidden. Only one pending full snapshot is
    // retained, and none of its state reaches the exiting/hidden native items.
    var images: [String: UIImage] = [:]
    for config in snapshot.items {
      let previous = configurations[config.id]
      let pending = pendingSnapshot?.configuration.items.first { $0.id == config.id }
      if pending?.icon == config.icon, pending?.iconScale == config.iconScale,
        let image = pendingSnapshot?.images[config.id]
      {
        images[config.id] = image
      } else if previous?.icon == config.icon, previous?.iconScale == config.iconScale,
        let image = itemsById[config.id]?.image
      {
        images[config.id] = image
      } else {
        guard let image = UIImage(data: config.icon, scale: config.iconScale) else {
          throw NativeTabBarError.invalidIcon
        }
        images[config.id] = image.withRenderingMode(.alwaysTemplate)
      }
    }
    let epochChanged = visibilityEpoch != snapshot.visibilityEpoch
    visibilityEpoch = snapshot.visibilityEpoch
    pendingSnapshot = .init(configuration: snapshot, images: images)
    targetHidden = snapshot.hidden
    if !isAttached {
      interruptAnimation()
      host.slidingView.isHidden = true
      setPhase(.detached, force: epochChanged)
    } else if snapshot.hidden {
      if phase == .visible || phase == .entering {
        transition(toHidden: true)
      } else if phase == .detached {
        host.slidingView.isHidden = true
        setPhase(.hidden, force: epochChanged)
      } else {
        setPhase(phase, force: epochChanged)
      }
    } else if phase == .visible || phase == .entering {
      applyPendingSnapshot()
      setPhase(phase, force: epochChanged)
    } else {
      transition(toHidden: false)
    }
  }

  private func applyPendingSnapshot() {
    guard let prepared = pendingSnapshot else { return }
    let snapshot = prepared.configuration
    var nextItems: [String: UITabBarItem] = [:]
    for config in snapshot.items {
      nextItems[config.id] = itemsById[config.id] ?? UITabBarItem()
    }

    let nextIds = snapshot.items.map(\.id)
    let itemsChanged = nextIds != orderedIds
    for config in snapshot.items {
      let item = nextItems[config.id]!
      if item.title != config.label { item.title = config.label }
      item.accessibilityIdentifier = config.id
      if let image = prepared.images[config.id], item.image !== image {
        item.image = image
        item.selectedImage = image
      }
    }
    configurations = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
    itemsById = nextItems
    orderedIds = nextIds
    if selectedTintColor != snapshot.selectedTintColor {
      if let argb = snapshot.selectedTintColor {
        host.tabBar.tintColor = UIColor(
          red: CGFloat((argb >> 16) & 0xFF) / 255,
          green: CGFloat((argb >> 8) & 0xFF) / 255,
          blue: CGFloat(argb & 0xFF) / 255,
          alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
      } else {
        host.tabBar.tintColor = nil
      }
      selectedTintColor = snapshot.selectedTintColor
    }
    if itemsChanged {
      host.tabBar.setItems(nextIds.compactMap { nextItems[$0] }, animated: false)
    }
    // Assigning selectedItem does not invoke the user-selection delegate.
    if host.tabBar.selectedItem !== nextItems[snapshot.selectedId] {
      host.tabBar.selectedItem = nextItems[snapshot.selectedId]
    }
    host.overrideUserInterfaceStyle = snapshot.style
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
    guard isInteractive, tabBar === host.tabBar,
      let id = orderedIds.first(where: { itemsById[$0] === item })
    else { return }
    // Re-selection is intentional: Flutter may return the branch to its root.
    channel.invokeMethod("select", arguments: [
      "id": id, "visibilityEpoch": visibilityEpoch, "revision": presentationRevision,
    ])
  }

  private var isAttached: Bool { attachmentProvider?() ?? (host.window != nil) }
  private var isInteractive: Bool { phase == .visible && !targetHidden && isAttached }
  private var presentation: [String: Any] {
    ["visibilityEpoch": visibilityEpoch, "revision": presentationRevision, "interactive": isInteractive]
  }

  private var hiddenTransform: CGAffineTransform {
    let distance = max(host.bounds.height, host.preferredHeight)
    return CGAffineTransform(translationX: 0, y: distance)
  }

  private func setInputEnabled(_ enabled: Bool) {
    host.isUserInteractionEnabled = enabled
    host.tabBar.isUserInteractionEnabled = enabled
    host.accessibilityElementsHidden = !enabled
  }

  private func setPhase(_ next: Phase, force: Bool = false) {
    let changed = next != phase
    phase = next
    setInputEnabled(isInteractive)
    if changed || force {
      presentationRevision += 1
      channel.invokeMethod("presentation", arguments: presentation)
    }
  }

  private func interruptAnimation() {
    animationGeneration &+= 1
    animation?.cancel()
    animation = nil
  }

  private func transition(toHidden hidden: Bool) {
    interruptAnimation()
    guard isAttached else {
      host.slidingView.isHidden = true
      setPhase(.detached)
      return
    }
    if !hidden {
      applyPendingSnapshot()
      if host.slidingView.isHidden {
        UIView.performWithoutAnimation { host.slidingView.transform = hiddenTransform }
      }
      host.slidingView.isHidden = false
    }
    setPhase(hidden ? .exiting : .entering)
    let target = hidden ? hiddenTransform : .identity
    let generation = animationGeneration
    let completion = { [weak self] in
      guard let self, self.animationGeneration == generation,
        self.targetHidden == hidden, self.isAttached else { return }
      self.animation = nil
      self.host.slidingView.isHidden = hidden
      self.setPhase(hidden ? .hidden : .visible)
    }
    if reduceMotion() {
      UIView.performWithoutAnimation { host.slidingView.transform = target }
      completion()
    } else {
      animation = animate(
        host.slidingView, target, hidden ? 0.200 : 0.240,
        hidden ? .easeIn : .easeOut, completion
      )
    }
  }

  private func geometryChanged() {
    switch phase {
    case .entering, .exiting:
      transition(toHidden: targetHidden)
    case .hidden, .detached:
      UIView.performWithoutAnimation { host.slidingView.transform = hiddenTransform }
    case .visible:
      break
    }
  }

  private func attachmentChanged() {
    if !isAttached {
      interruptAnimation()
      host.slidingView.isHidden = true
      setPhase(.detached)
    } else if targetHidden {
      host.slidingView.isHidden = true
      setPhase(.hidden)
    } else {
      transition(toHidden: false)
    }
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
