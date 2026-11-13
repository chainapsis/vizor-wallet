import CoreFoundation
import Flutter
import UIKit

/// Native assets are the only icon source for this bridge. The fixed mapping
/// keeps channel input from selecting arbitrary bundle resources.
final class NativeTabBarIconCatalog {
  static let shared = NativeTabBarIconCatalog()
  static let names = ["home", "swap_arrows", "history", "cog"]
  private static let assets = [
    "home": "VizorTab_home", "swap_arrows": "VizorTab_swap_arrows",
    "history": "VizorTab_history", "cog": "VizorTab_cog",
  ]
  private let load: (String) -> UIImage?
  private var images: [String: UIImage] = [:]

  init(load: @escaping (String) -> UIImage? = {
    UIImage(named: $0, in: .main, compatibleWith: nil)
  }) {
    self.load = load
  }

  var availableNames: [String] { Self.names.filter { image(named: $0) != nil } }

  func capabilities(supported: Bool) -> [String: Any] {
    ["supported": supported, "iconNames": availableNames]
  }

  func image(named name: String) -> UIImage? {
    guard let asset = Self.assets[name] else { return nil }
    if let image = images[name] { return image }
    guard let source = load(asset), source.size.width.isFinite, source.size.height.isFinite,
      source.size.width > 0, source.size.height > 0 else { return nil }
    // The canonical SVGs have 20pt or 24pt intrinsic sizes. Normalize once in
    // UIKit to the existing 25pt tab size; selection tint still uses the alpha.
    let size = CGSize(width: 25, height: 25)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
      source.draw(in: CGRect(origin: .zero, size: size))
    }.withRenderingMode(.alwaysTemplate)
    images[name] = image
    return image
  }
}

/// An app-owned bridge to the system tab bar. UIKit owns its material and motion;
/// Flutter remains the owner of destinations and navigation history.
final class NativeTabBarPlugin {
  static let channelName = "com.zcash.wallet/native_tab_bar"
  private let channel: FlutterMethodChannel

  init(registrar: FlutterPluginRegistrar, icons: NativeTabBarIconCatalog = .shared) {
    let messenger = registrar.messenger()
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "getCapabilities" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 26.0, *) {
        result(icons.capabilities(supported: true))
      } else {
        result(icons.capabilities(supported: false))
      }
    }
    registrar.register(
      NativeTabBarFactory(messenger: messenger, icons: icons), withId: Self.channelName
    )
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}

private final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let icons: NativeTabBarIconCatalog

  init(messenger: FlutterBinaryMessenger, icons: NativeTabBarIconCatalog) {
    self.messenger = messenger
    self.icons = icons
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    NativeTabBarPlatformView(
      frame: frame, viewId: viewId, args: args, messenger: messenger, icons: icons
    )
  }
}

struct NativeTabBarItemConfiguration: Equatable {
  let id: String
  let label: String
  let iconName: String
}

struct NativeTabBarSnapshot {
  let items: [NativeTabBarItemConfiguration]
  let selectedId: String
  let style: UIUserInterfaceStyle
  let direction: UIUserInterfaceLayoutDirection
  let hidden: Bool
  let hideImmediately: Bool
  let inputEnabled: Bool
  let layoutReady: Bool
  let visibilityEpoch: Int64
  let showRequestId: Int64
  let selectedTintColor: UInt32?

  init(arguments: Any?) throws {
    guard let args = arguments as? [String: Any],
      let rawItems = args["items"] as? [[String: Any]], !rawItems.isEmpty,
      let selectedId = args["selectedId"] as? String,
      let brightness = args["brightness"] as? String,
      let direction = args["direction"] as? String,
      ["light", "dark"].contains(brightness), ["ltr", "rtl"].contains(direction)
    else { throw NativeTabBarError.invalidSnapshot }
    guard ["hidden", "hideImmediately", "inputEnabled", "layoutReady"].allSatisfy({
      args[$0] == nil || args[$0] is Bool
    }) else {
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
    if let rawRequest = args["showRequestId"] {
      guard let number = rawRequest as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(), number.int64Value >= 0,
        number.doubleValue == Double(number.int64Value)
      else { throw NativeTabBarError.invalidSnapshot }
      showRequestId = number.int64Value
    } else {
      showRequestId = 0
    }
    guard args["hideImmediately"] as? Bool != true || args["hidden"] as? Bool == true else {
      throw NativeTabBarError.invalidSnapshot
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
        let iconName = raw["iconName"] as? String, !iconName.isEmpty
      else { throw NativeTabBarError.invalidSnapshot }
      items.append(.init(id: id, label: label, iconName: iconName))
    }
    guard ids.contains(selectedId) else { throw NativeTabBarError.invalidSnapshot }
    self.items = items
    self.selectedId = selectedId
    style = brightness == "dark" ? .dark : .light
    self.direction = direction == "rtl" ? .rightToLeft : .leftToRight
    hidden = args["hidden"] as? Bool ?? false
    hideImmediately = args["hideImmediately"] as? Bool ?? false
    inputEnabled = args["inputEnabled"] as? Bool ?? true
    layoutReady = args["layoutReady"] as? Bool ?? false
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
  var onLayoutCompleted: (() -> Void)?
  private var lastHeight: CGFloat?
  private var lastSize: CGSize?
  private var lastInsets: UIEdgeInsets?
  private let fittingHeight: ((UITabBar, CGSize) -> CGFloat)?

  override convenience init(frame: CGRect) {
    self.init(frame: frame, fittingHeight: nil)
  }

  init(frame: CGRect, fittingHeight: ((UITabBar, CGSize) -> CGFloat)?) {
    self.fittingHeight = fittingHeight
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
    let size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
    let height = fittingHeight?(tabBar, size) ?? tabBar.sizeThatFits(size).height
    return height.isFinite && height > 0 ? height : tabBar.intrinsicContentSize.height
  }

  var hasLaidOutCurrentGeometry: Bool {
    lastSize == bounds.size && lastInsets == safeAreaInsets
      && tabBar.bounds.size == bounds.size && slidingView.bounds.size == bounds.size
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // The outer platform-view rectangle never moves or collapses. In particular
    // do not assign frame while the sliding view has a nonidentity transform.
    slidingView.bounds = CGRect(origin: .zero, size: bounds.size)
    slidingView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    tabBar.frame = slidingView.bounds
    tabBar.layoutIfNeeded()
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
    onLayoutCompleted?()
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
  UIView, CGAffineTransform, TimeInterval, UICubicTimingParameters, @escaping () -> Void
) -> NativeTabBarAnimation

private final class NativeTabBarUIKitAnimation: NativeTabBarAnimation {
  private let animator: UIViewPropertyAnimator
  private weak var view: UIView?
  private let startTransform: CGAffineTransform

  init(
    view: UIView, target: CGAffineTransform, duration: TimeInterval,
    timing: UICubicTimingParameters, completion: @escaping () -> Void
  ) {
    self.view = view
    startTransform = view.transform
    animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
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
  private enum Phase: String { case detached, hidden, preparing, entering, visible, exiting }
  private let channel: FlutterMethodChannel
  private let host: NativeTabBarHostView
  private let icons: NativeTabBarIconCatalog
  private let animate: NativeTabBarAnimator
  private let reduceMotion: () -> Bool
  private let attachmentProvider: (() -> Bool)?
  private let notificationCenter: NotificationCenter
  private let schedulePreparation: (@escaping () -> Void) -> Void
  private var motionObserver: NSObjectProtocol?
  private var animation: NativeTabBarAnimation?
  private var animationGeneration: UInt64 = 0
  private var phase: Phase = .detached
  private var targetHidden = true
  private var targetInputEnabled = true
  private var layoutReady = false
  private var hasStartedInitialReveal = false
  private var needsPreparedShow = false
  private var needsAttachmentRestore = false
  private var preparationGeneration: UInt64 = 0
  private var preparationScheduled = false
  private var lastPublishedInteractive = false
  private var visibilityEpoch: Int64 = 0
  private var showRequestId: Int64 = 0
  private var presentationRevision: Int64 = 0
  private var pendingSnapshot: NativeTabBarPreparedSnapshot?
  private var itemsById: [String: UITabBarItem] = [:]
  private var orderedIds: [String] = []
  private var selectedTintColor: UInt32?
  private var pendingHeight: CGFloat?
  private var lastAttachedHeight: CGFloat?
  private var heightDeliveryScheduled = false

  init(
    frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger,
    icons: NativeTabBarIconCatalog = .shared,
    animator: NativeTabBarAnimator? = nil,
    reduceMotion: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled },
    attachmentProvider: (() -> Bool)? = nil,
    notificationCenter: NotificationCenter = .default,
    fittingHeight: ((UITabBar, CGSize) -> CGFloat)? = nil,
    schedulePreparation: @escaping (@escaping () -> Void) -> Void = {
      DispatchQueue.main.async(execute: $0)
    }
  ) {
    channel = FlutterMethodChannel(
      name: "\(NativeTabBarPlugin.channelName)/\(viewId)", binaryMessenger: messenger
    )
    host = NativeTabBarHostView(frame: frame, fittingHeight: fittingHeight)
    self.icons = icons
    animate = animator ?? { view, transform, duration, timing, completion in
      NativeTabBarUIKitAnimation(
        view: view, target: transform, duration: duration, timing: timing, completion: completion
      )
    }
    self.reduceMotion = reduceMotion
    self.attachmentProvider = attachmentProvider
    self.notificationCenter = notificationCenter
    self.schedulePreparation = schedulePreparation
    super.init()
    host.tabBar.delegate = self
    host.onHeightChanged = { [weak self] height in self?.scheduleHeight(height) }
    host.onGeometryChanged = { [weak self] in self?.geometryChanged() }
    host.onAttachmentChanged = { [weak self] in self?.attachmentChanged() }
    host.onLayoutCompleted = { [weak self] in self?.layoutCompleted() }
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
        result(Double(self.reportedHeight))
      case "getPresentation":
        result(self.presentation)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    preparationGeneration &+= 1
    animationGeneration &+= 1
    animation?.cancel()
    if let motionObserver { notificationCenter.removeObserver(motionObserver) }
    host.tabBar.delegate = nil
    host.onHeightChanged = nil
    host.onGeometryChanged = nil
    host.onAttachmentChanged = nil
    host.onLayoutCompleted = nil
    host.slidingView.isHidden = true
    host.isUserInteractionEnabled = false
    host.accessibilityElementsHidden = true
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { host }

  private func apply(_ snapshot: NativeTabBarSnapshot) throws {
    guard snapshot.visibilityEpoch >= visibilityEpoch, snapshot.showRequestId >= showRequestId else {
      throw NativeTabBarError.invalidSnapshot
    }
    // Preparing is atomic even while hidden. Only one pending full snapshot is
    // retained, and none of its state reaches the exiting/hidden native items.
    var images: [String: UIImage] = [:]
    for config in snapshot.items {
      guard let image = icons.image(named: config.iconName) else {
        throw NativeTabBarError.invalidIcon
      }
      images[config.id] = image
    }
    let epochChanged = visibilityEpoch != snapshot.visibilityEpoch
    let inputChanged = targetInputEnabled != snapshot.inputEnabled
    let newShow = !snapshot.hidden && (targetHidden || snapshot.showRequestId > showRequestId)
    visibilityEpoch = snapshot.visibilityEpoch
    showRequestId = snapshot.showRequestId
    pendingSnapshot = .init(configuration: snapshot, images: images)
    targetHidden = snapshot.hidden
    targetInputEnabled = snapshot.inputEnabled
    layoutReady = snapshot.layoutReady
    if snapshot.hidden {
      needsPreparedShow = false
    } else if newShow && (host.slidingView.isHidden || phase == .detached || phase == .preparing) {
      // A logical show can arrive while Flutter still has the stable view
      // Offstage. Remember it across detachment and any coalesced snapshots.
      needsPreparedShow = true
      needsAttachmentRestore = false
    }
    if snapshot.hideImmediately {
      settleImmediatelyHidden()
      return
    }
    if requiresPreparedReveal {
      cancelPreparation()
      // Measurement and the first staged frame must already use the latest
      // labels, images, theme and direction, even before Flutter accepts height.
      applyPendingSnapshot()
    }
    reconcileVisibility(forcePresentation: epochChanged || inputChanged)
  }

  private func reconcileVisibility(forcePresentation: Bool = false) {
    if !isAttached {
      interruptAnimation()
      cancelPreparation()
      needsAttachmentRestore = hasStartedInitialReveal && !needsPreparedShow
      host.slidingView.isHidden = true
      setPhase(targetHidden ? .hidden : .detached, force: forcePresentation || targetHidden)
    } else if targetHidden {
      cancelPreparation()
      if phase == .visible || phase == .entering {
        transition(toHidden: true)
      } else if phase == .detached || phase == .preparing {
        host.slidingView.isHidden = true
        needsAttachmentRestore = false
        setPhase(.hidden, force: forcePresentation)
      } else {
        setPhase(phase, force: forcePresentation || phase == .hidden)
      }
    } else if requiresPreparedReveal {
      setPhase(.preparing, force: forcePresentation)
      prepareReveal()
    } else if needsAttachmentRestore {
      setPhase(.detached, force: forcePresentation)
      restoreAfterAttachment()
    } else if phase == .visible || phase == .entering {
      applyPendingSnapshot()
      setPhase(phase, force: forcePresentation)
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
  private var requiresPreparedReveal: Bool { !hasStartedInitialReveal || needsPreparedShow }
  private var reportedHeight: CGFloat {
    // Offstage removes the platform view from its window; UIKit then measures
    // the bar without the home-indicator inset. Keep the last attached height
    // until a real attached layout supplies the next authoritative value.
    if isAttached, host.bounds.width > 0, host.bounds.height > 0,
      host.hasLaidOutCurrentGeometry { return host.preferredHeight }
    return lastAttachedHeight ?? host.preferredHeight
  }
  private var hasUsableLayout: Bool {
    let size = host.bounds.size
    let height = host.preferredHeight
    return layoutReady && size.width.isFinite && size.height.isFinite
      && size.width > 0 && size.height > 0 && height.isFinite && height > 0
      && abs(size.height - height) <= 0.5 && host.hasLaidOutCurrentGeometry
  }
  private var isInteractive: Bool {
    phase == .visible && !targetHidden && targetInputEnabled && isAttached && hasUsableLayout
  }
  private var presentation: [String: Any] {
    [
      "visibilityEpoch": visibilityEpoch, "revision": presentationRevision,
      "interactive": isInteractive, "phase": phase.rawValue,
      "settledHidden": targetHidden && host.slidingView.isHidden
        && animation == nil && !preparationScheduled,
    ]
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
    let interactive = isInteractive
    let readinessChanged = interactive != lastPublishedInteractive
    setInputEnabled(interactive)
    if changed || force || readinessChanged {
      lastPublishedInteractive = interactive
      presentationRevision += 1
      channel.invokeMethod("presentation", arguments: presentation)
    }
  }

  private func cancelPreparation() {
    preparationGeneration &+= 1
    preparationScheduled = false
  }

  private func prepareReveal() {
    guard requiresPreparedReveal, !targetHidden, isAttached, hasUsableLayout else {
      host.slidingView.isHidden = true
      return
    }
    guard !preparationScheduled else { return }
    preparationScheduled = true
    UIView.performWithoutAnimation {
      host.slidingView.transform = hiddenTransform
      host.slidingView.isHidden = false
      host.slidingView.layoutIfNeeded()
      host.tabBar.layoutIfNeeded()
    }
    let generation = preparationGeneration
    // This is a preparation/layout boundary, not a time delay: UIKit sees a
    // laid-out offscreen starting state before the first property animation.
    schedulePreparation { [weak self] in
      guard let self, self.preparationGeneration == generation else { return }
      self.preparationScheduled = false
      guard self.requiresPreparedReveal, !self.targetHidden, self.isAttached,
        self.hasUsableLayout else {
        self.host.slidingView.isHidden = true
        return
      }
      self.hasStartedInitialReveal = true
      self.needsPreparedShow = false
      self.transition(toHidden: false)
    }
  }

  private func settleImmediatelyHidden() {
    cancelPreparation()
    interruptAnimation()
    needsPreparedShow = false
    needsAttachmentRestore = false
    pendingHeight = nil
    UIView.performWithoutAnimation {
      host.slidingView.transform = hiddenTransform
      host.slidingView.isHidden = true
    }
    // Security/logout can Offstage without waiting. Always acknowledge the
    // current request, even when another hidden update coalesced into it.
    setPhase(.hidden, force: true)
  }

  private func restoreAfterAttachment() {
    guard needsAttachmentRestore, isAttached, hasUsableLayout else { return }
    applyPendingSnapshot()
    UIView.performWithoutAnimation {
      host.slidingView.transform = targetHidden ? hiddenTransform : .identity
      host.slidingView.isHidden = targetHidden
      host.slidingView.layoutIfNeeded()
      host.tabBar.layoutIfNeeded()
    }
    needsAttachmentRestore = false
    setPhase(targetHidden ? .hidden : .visible)
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
    let remainingDistance = abs(target.ty - host.slidingView.transform.ty)
    let generation = animationGeneration
    let completion = { [weak self] in
      guard let self, self.animationGeneration == generation,
        self.targetHidden == hidden, self.isAttached else { return }
      self.animation = nil
      self.host.slidingView.isHidden = hidden
      self.setPhase(hidden ? .hidden : .visible)
    }
    if reduceMotion() || remainingDistance <= 0.5 {
      UIView.performWithoutAnimation { host.slidingView.transform = target }
      completion()
    } else {
      // A reversal/resize has only part of the original trip left. Use its
      // presented position (captured by cancel), rather than restarting a full
      // duration and making a nearly settled bar linger with input disabled.
      let fraction = min(remainingDistance / max(hiddenTransform.ty, 1), 1)
      let timing = UICubicTimingParameters(
        controlPoint1: hidden ? CGPoint(x: 0.3, y: 0) : CGPoint(x: 0.2, y: 0.8),
        controlPoint2: hidden ? CGPoint(x: 0.8, y: 0.7) : CGPoint(x: 0.2, y: 1)
      )
      animation = animate(
        host.slidingView, target, (hidden ? 0.140 : 0.180) * Double(fraction),
        timing, completion
      )
    }
  }

  private func geometryChanged() {
    if requiresPreparedReveal {
      prepareReveal()
      return
    }
    if needsAttachmentRestore {
      restoreAfterAttachment()
      return
    }
    switch phase {
    case .entering, .exiting:
      transition(toHidden: targetHidden)
    case .hidden, .detached, .preparing:
      UIView.performWithoutAnimation { host.slidingView.transform = hiddenTransform }
    case .visible:
      setPhase(.visible)
    }
  }

  private func layoutCompleted() {
    if requiresPreparedReveal {
      prepareReveal()
    } else if needsAttachmentRestore {
      restoreAfterAttachment()
    } else {
      setPhase(phase)
    }
  }

  private func attachmentChanged() {
    if !isAttached {
      interruptAnimation()
      cancelPreparation()
      needsAttachmentRestore = hasStartedInitialReveal && !needsPreparedShow
      host.slidingView.isHidden = true
      setPhase(targetHidden ? .hidden : .detached)
    } else if targetHidden {
      if phase == .exiting, animation != nil {
        setPhase(.exiting)
        return
      }
      host.slidingView.isHidden = true
      needsAttachmentRestore = false
      setPhase(.hidden)
    } else if requiresPreparedReveal {
      setPhase(.preparing)
      prepareReveal()
    } else if phase == .detached || needsAttachmentRestore {
      needsAttachmentRestore = true
      restoreAfterAttachment()
    } else {
      // Flutter can reparent its platform-view hierarchy without a new native
      // instance. Do not turn those notifications into another entrance.
      setPhase(phase)
    }
  }

  private func scheduleHeight(_ height: CGFloat) {
    guard isAttached, host.bounds.width > 0, host.bounds.height > 0,
      height.isFinite, height > 0 else { return }
    lastAttachedHeight = height
    pendingHeight = height
    guard !heightDeliveryScheduled else { return }
    heightDeliveryScheduled = true
    // Layout can occur inside a platform-view resize. Deliver after that pass
    // so Flutter can change its constraints without reentering UIKit layout.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.heightDeliveryScheduled = false
      guard let height = self.pendingHeight else { return }
      self.pendingHeight = nil
      guard self.isAttached else { return }
      self.channel.invokeMethod("layout", arguments: ["height": Double(height)])
    }
  }
}
