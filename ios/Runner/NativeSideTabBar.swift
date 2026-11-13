import Flutter
import UIKit

/// A real child controller is required for UIKit's scene-aware vertical bars.
/// Its transparent content stays over Flutter; only the native bar accepts hits.
final class NativeSideTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  private enum Phase: String { case detached, hidden, preparing, entering, visible, exiting }
  private let channel: FlutterMethodChannel
  private let host: NativeSideTabBarHostView
  private let controller = NativeSideTabController()
  private let icons: NativeTabBarIconCatalog
  private let owner: () -> UIViewController?
  private let feedback: NativeTabBarPressFeedback
  private let reduceMotion: () -> Bool
  private let notifications: NotificationCenter
  private var motionObserver: NSObjectProtocol?
  private var press: NativeTabBarPressObserver?
  private var snapshot: NativeTabBarSnapshot?
  private var pendingImages: [String: UIImage] = [:]
  private var pages: [String: UIViewController] = [:]
  private var ids: [String] = []
  private var phase = Phase.detached
  private var presentationRevision: Int64 = 0
  private var layoutRevision: Int64 = 0
  private var acknowledgedLayout: Int64 = -1
  private var lastSize = CGSize.zero
  private var barRect = CGRect.zero
  private var lastInteractive = false
  private var hasPresented = false
  private var needsShow = true
  private var preparationGeneration = 0
  private var preparationScheduled = false
  private var animationGeneration = 0
  private var animation: NativeSideTabLayerAnimation?
  private var layoutScheduled = false
  private var changingAttachment = false
  private var geometryValid = false

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger,
       icons: NativeTabBarIconCatalog = .shared, owner: @escaping () -> UIViewController?,
       feedback: NativeTabBarPressFeedback? = nil,
       reduceMotion: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled },
       notifications: NotificationCenter = .default) {
    self.channel = FlutterMethodChannel(name: "\(NativeTabBarPlugin.channelName)/\(viewId)", binaryMessenger: messenger)
    self.host = NativeSideTabBarHostView(frame: frame)
    self.icons = icons
    self.owner = owner
    self.feedback = feedback ?? NativeSideTabSoftFeedback()
    self.reduceMotion = reduceMotion
    self.notifications = notifications
    super.init()
    controller.delegate = self
    controller.loadViewIfNeeded()
    controller.view.backgroundColor = .clear
    controller.view.isOpaque = false
    controller.view.alpha = 0
    host.bar = controller.tabBar
    host.onWindow = { [weak self] in self?.attachmentChanged() }
    host.onLayout = { [weak self] in self?.layout() }
    controller.onLayout = { [weak self] in self?.scheduleLayout() }
    let press = NativeTabBarPressObserver(
      canPress: { [weak self] in self?.accepts($0) ?? false },
      onPress: { [weak self] in
        guard let self, self.interactive else { return }
        self.feedback.impactOccurred()
        self.feedback.prepare()
      })
    self.press = press
    controller.view.addGestureRecognizer(press)
    input(false)
    motionObserver = notifications.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
      object: nil, queue: .main) { [weak self] _ in
        guard let self, self.reduceMotion(), self.animation != nil else { return }
        self.transition(hidden: self.snapshot?.hidden ?? true)
      }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "update":
        do { try self.apply(NativeTabBarSnapshot(arguments: call.arguments)); result(nil) }
        catch { result(FlutterError(code: "invalid_snapshot", message: "Invalid native tab bar configuration.", details: nil)) }
      case "getPresentation": result(self.presentation)
      case "getLayout": result(self.layoutDescription)
      case "getHeight": result(Double(self.host.bounds.height))
      default: result(FlutterMethodNotImplemented)
      }
    }
    if let initial = try? NativeTabBarSnapshot(arguments: args) { try? apply(initial) }
  }

  deinit {
    animation?.cancel()
    if let motionObserver { notifications.removeObserver(motionObserver) }
    press?.isEnabled = false
    if let press { controller.view.removeGestureRecognizer(press) }
    controller.delegate = nil
    controller.onLayout = nil
    host.onWindow = nil
    host.onLayout = nil
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { host }

  private var attached: Bool { host.window != nil && controller.parent != nil }
  private var geometryReady: Bool {
    attached && geometryValid && layoutRevision > 0 && lastSize == host.bounds.size && !barRect.isEmpty
      && snapshot?.layoutReady == true && acknowledgedLayout == layoutRevision
  }
  private var interactive: Bool {
    phase == .visible && snapshot?.hidden == false && snapshot?.inputEnabled == true && geometryReady
  }
  private var hiddenX: CGFloat {
    let distance = barRect.width + 16 // Include the glass rim/shadow in the exit.
    return snapshot?.placement == "left" ? -distance : distance
  }
  private var layoutDescription: [String: Any] {
    ["height": Double(host.bounds.height), "layoutRevision": layoutRevision,
     "hitRect": ["x": Double(barRect.minX), "y": Double(barRect.minY),
                 "width": Double(barRect.width), "height": Double(barRect.height)]]
  }
  private var presentation: [String: Any] {
    ["visibilityEpoch": snapshot?.visibilityEpoch ?? 0, "revision": presentationRevision,
     "interactive": interactive, "phase": phase.rawValue,
     "settledHidden": snapshot?.hidden == true && controller.view.alpha == 0
       && animation == nil && !preparationScheduled]
  }

  private func apply(_ next: NativeTabBarSnapshot) throws {
    guard next.placement != "bottom",
      next.visibilityEpoch >= (snapshot?.visibilityEpoch ?? 0),
      next.showRequestId >= (snapshot?.showRequestId ?? 0),
      snapshot == nil || snapshot?.placement == next.placement
    else { throw NativeTabBarError.invalidSnapshot }
    var images: [String: UIImage] = [:]
    for item in next.items {
      guard let image = icons.image(named: item.iconName) else { throw NativeTabBarError.invalidIcon }
      images[item.id] = image
    }
    let old = snapshot
    let freshShow = !next.hidden && (old?.hidden != false || next.showRequestId > (old?.showRequestId ?? 0))
    snapshot = next
    pendingImages = images
    acknowledgedLayout = next.layoutRevision
    needsShow = needsShow || freshShow
    if next.hideImmediately { settleHidden(); return }
    if !hasPresented { render() }
    reconcile(force: old?.visibilityEpoch != next.visibilityEpoch || old?.inputEnabled != next.inputEnabled)
  }

  private func render() {
    guard let snapshot else { return }
    let nextIds = snapshot.items.map(\.id)
    var nextPages: [String: UIViewController] = [:]
    for item in snapshot.items {
      let page = pages[item.id] ?? UIViewController()
      page.view.backgroundColor = .clear
      page.view.isOpaque = false
      if page.tabBarItem.title != item.label { page.tabBarItem.title = item.label }
      page.tabBarItem.accessibilityIdentifier = item.id
      if page.tabBarItem.image !== pendingImages[item.id] {
        page.tabBarItem.image = pendingImages[item.id]
        page.tabBarItem.selectedImage = pendingImages[item.id]
      }
      nextPages[item.id] = page
    }
    pages = nextPages
    if nextIds != ids {
      ids = nextIds
      controller.setViewControllers(ids.compactMap { pages[$0] }, animated: false)
    }
    if let page = pages[snapshot.selectedId], controller.selectedViewController !== page {
      controller.selectedViewController = page
    }
    if let argb = snapshot.selectedTintColor {
      let color = UIColor(red: CGFloat((argb >> 16) & 255) / 255,
        green: CGFloat((argb >> 8) & 255) / 255, blue: CGFloat(argb & 255) / 255,
        alpha: CGFloat((argb >> 24) & 255) / 255)
      controller.tabBar.tintColor = color
      controller.view.tintColor = color
    } else { controller.tabBar.tintColor = nil; controller.view.tintColor = nil }
    controller.overrideUserInterfaceStyle = snapshot.style
    let direction: UISemanticContentAttribute = snapshot.direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
    controller.view.semanticContentAttribute = direction
    controller.tabBar.semanticContentAttribute = direction
    if #available(iOS 17.0, *) { controller.tabBar.traitOverrides.layoutDirection = snapshot.direction == .rightToLeft ? .rightToLeft : .leftToRight }
  }

  private func attachmentChanged() {
    guard !changingAttachment else { return }
    changingAttachment = true
    defer { changingAttachment = false }
    if host.window == nil {
      stopAnimation()
      preparationGeneration += 1
      preparationScheduled = false
      controller.view.alpha = 0
      controller.willMove(toParent: nil)
      controller.view.removeFromSuperview()
      controller.removeFromParent()
      lastSize = .zero
      geometryValid = false
      input(false)
      setPhase(snapshot?.hidden == true ? .hidden : .detached)
    } else if controller.parent == nil, let owner = owner() {
      owner.addChild(controller)
      controller.view.frame = host.bounds
      controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      host.addSubview(controller.view)
      controller.didMove(toParent: owner)
      host.setNeedsLayout()
      scheduleLayout()
    }
  }

  private func scheduleLayout() {
    guard !layoutScheduled else { return }
    layoutScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.layoutScheduled = false
      self.layout()
    }
  }

  private func layout() {
    guard attached, host.bounds.width > 0, host.bounds.height > 0 else { return }
    if controller.view.frame != host.bounds { controller.view.frame = host.bounds }
    controller.view.layoutIfNeeded()
    // UIView conversion includes our render-only translation. Remove it so
    // native geometry acknowledgements stay anchored during the slide.
    let rect = controller.tabBar.convert(controller.tabBar.bounds, to: host)
      .offsetBy(dx: -controller.view.layer.sublayerTransform.m41, dy: 0)
    let correctEdge = snapshot?.placement == "left"
      ? rect.maxX <= host.bounds.midX : rect.minX >= host.bounds.midX
    guard rect.width.isFinite, rect.height.isFinite, !rect.isEmpty,
      host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect), correctEdge
    else {
      if geometryValid {
        geometryValid = false
        layoutRevision += 1
        setPhase(phase, force: true)
      }
      input(false)
      return
    }
    if !geometryValid || lastSize != host.bounds.size || barRect != rect {
      let interrupted = phase == .entering || phase == .exiting
      stopAnimation()
      geometryValid = true
      lastSize = host.bounds.size
      barRect = rect
      layoutRevision += 1
      if interrupted {
        controller.view.alpha = 0
        hasPresented = false
        needsShow = true
        setPhase(.preparing)
      }
      if !hasPresented || snapshot?.hidden == true { setOffset(hiddenX) }
      setPhase(phase, force: true)
      channel.invokeMethod("layout", arguments: layoutDescription)
    }
    reconcile()
  }

  private func reconcile(force: Bool = false) {
    guard let snapshot else { return }
    if !attached { setPhase(snapshot.hidden ? .hidden : .detached, force: force); return }
    if snapshot.hidden {
      if phase == .visible || phase == .entering { transition(hidden: true) }
      else if phase == .exiting { setPhase(.exiting, force: force) }
      else { settleHidden() }
      return
    }
    guard geometryReady else {
      if !hasPresented || phase == .hidden || phase == .detached {
        controller.view.alpha = 0
        setPhase(.preparing, force: force)
      } else { setPhase(phase, force: force) }
      return
    }
    render()
    if phase == .visible && !needsShow { setPhase(.visible, force: force); return }
    if phase == .entering && !needsShow { setPhase(.entering, force: force); return }
    needsShow = false
    if phase == .exiting { transition(hidden: false); return }
    guard !preparationScheduled else { return }
    setOffset(hiddenX)
    controller.view.alpha = 1
    preparationScheduled = true
    preparationGeneration += 1
    let generation = preparationGeneration
    setPhase(.preparing, force: force)
    DispatchQueue.main.async { [weak self] in
      guard let self, self.preparationGeneration == generation else { return }
      self.preparationScheduled = false
      guard self.snapshot?.hidden == false, self.geometryReady else { return }
      self.hasPresented = true
      self.transition(hidden: false)
    }
  }

  private func input(_ enabled: Bool) {
    let wasEnabled = host.isUserInteractionEnabled
    host.isUserInteractionEnabled = enabled
    host.accessibilityElementsHidden = !enabled
    controller.tabBar.isUserInteractionEnabled = enabled
    if press?.isEnabled != enabled { press?.isEnabled = enabled }
    if enabled && !wasEnabled { feedback.prepare() }
  }

  private func setPhase(_ next: Phase, force: Bool = false) {
    let changed = phase != next
    phase = next
    let ready = interactive
    input(ready)
    if changed || force || ready != lastInteractive {
      lastInteractive = ready
      presentationRevision += 1
      channel.invokeMethod("presentation", arguments: presentation)
    }
  }

  private func setOffset(_ x: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    controller.view.layer.sublayerTransform = CATransform3DMakeTranslation(x, 0, 0)
    CATransaction.commit()
  }

  private func stopAnimation() {
    animationGeneration += 1
    animation?.cancel()
    animation = nil
  }

  private func settleHidden() {
    stopAnimation()
    preparationGeneration += 1
    preparationScheduled = false
    controller.view.alpha = 0
    setOffset(hiddenX)
    setPhase(.hidden, force: true)
  }

  private func transition(hidden: Bool) {
    stopAnimation()
    controller.view.alpha = 1
    let layer = controller.view.layer
    let from = layer.sublayerTransform.m41
    let target = hidden ? hiddenX : 0
    let fraction = min(abs(target - from) / max(abs(hiddenX), 1), 1)
    let generation = animationGeneration
    setPhase(hidden ? .exiting : .entering)
    let completion = { [weak self] in
      guard let self, self.animationGeneration == generation,
        self.snapshot?.hidden == hidden, self.attached else { return }
      self.animation = nil
      if hidden { self.controller.view.alpha = 0 }
      self.setPhase(hidden ? .hidden : .visible)
    }
    if reduceMotion() || abs(target - from) <= 0.5 {
      setOffset(target)
      completion()
    } else {
      let timing = hidden
        ? CAMediaTimingFunction(controlPoints: 0.3, 0, 0.8, 0.7)
        : CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
      animation = NativeSideTabLayerAnimation(layer: layer, from: from, to: target,
        duration: (hidden ? 0.140 : 0.180) * Double(fraction), timing: timing, completion: completion)
    }
  }

  private func accepts(_ touch: UITouch) -> Bool {
    guard interactive, touch.type == .direct, let view = touch.view,
      view.isDescendant(of: controller.view),
      barRect.contains(touch.location(in: host)),
      !pages.values.contains(where: { view.isDescendant(of: $0.view) }) else { return false }
    // Modern vertical bars can use a system-hosted glass surface outside the
    // public UITabBar proxy. Observe its actual native hit, not private classes.
    return true
  }

  func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
    return interactive
  }
  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    guard interactive, let id = ids.first(where: { pages[$0] === viewController }), let snapshot else { return }
    channel.invokeMethod("select", arguments: ["id": id, "visibilityEpoch": snapshot.visibilityEpoch,
      "revision": presentationRevision])
  }

  @available(iOS 18.0, *)
  func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
    return interactive
  }

  @available(iOS 18.0, *)
  func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
    guard let page = selectedTab.viewController else { return }
    self.tabBarController(tabBarController, didSelect: page)
  }
}

private final class NativeSideTabController: UITabBarController {
  var onLayout: (() -> Void)?
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onLayout?() }
}

private final class NativeSideTabBarHostView: UIView {
  weak var bar: UITabBar?
  var onWindow: (() -> Void)?
  var onLayout: (() -> Void)?
  override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
  required init?(coder: NSCoder) { fatalError() }
  override func didMoveToWindow() { super.didMoveToWindow(); onWindow?() }
  override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, alpha > 0.01, isUserInteractionEnabled, let bar else { return nil }
    guard bar.convert(bar.bounds, to: self).contains(point), let root = subviews.first else { return nil }
    let hit = root.hitTest(convert(point, to: root), with: event)
    return hit === root ? nil : hit
  }
}

private final class NativeSideTabSoftFeedback: NativeTabBarPressFeedback {
  let generator = UIImpactFeedbackGenerator(style: .soft)
  func prepare() { generator.prepare() }
  func impactOccurred() { generator.impactOccurred() }
}

/// Move the transparent controller's rendered contents, leaving its geometry and
/// safe-area registration stationary throughout the horizontal transition.
private final class NativeSideTabLayerAnimation: NSObject, CAAnimationDelegate {
  private weak var layer: CALayer?
  private let completion: () -> Void
  private let key = "vizor.sideTabSlide"
  init(layer: CALayer, from: CGFloat, to: CGFloat, duration: TimeInterval,
       timing: CAMediaTimingFunction, completion: @escaping () -> Void) {
    self.layer = layer
    self.completion = completion
    super.init()
    let movement = CABasicAnimation(keyPath: "sublayerTransform")
    movement.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(from, 0, 0))
    movement.toValue = NSValue(caTransform3D: CATransform3DMakeTranslation(to, 0, 0))
    movement.duration = duration
    movement.timingFunction = timing
    movement.delegate = self
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.sublayerTransform = CATransform3DMakeTranslation(to, 0, 0)
    layer.add(movement, forKey: key)
    CATransaction.commit()
  }
  func cancel() {
    guard let layer else { return }
    let current = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.sublayerTransform = current
    layer.removeAnimation(forKey: key)
    CATransaction.commit()
  }
  func animationDidStop(_ anim: CAAnimation, finished flag: Bool) { if flag { completion() } }
}
