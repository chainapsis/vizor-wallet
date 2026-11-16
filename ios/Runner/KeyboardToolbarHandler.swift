import Flutter
import UIKit

/// A UIKit control above the system keyboard; Flutter owns editable-field focus.
final class KeyboardToolbarHandler {
  private let channel: FlutterMethodChannel
  private let notificationCenter: NotificationCenter
  private let hostViewProvider: () -> UIView?
  private weak var host: UIView?
  private var button: UIButton?
  private var layoutProbe: KeyboardToolbarLayoutProbe?
  private let keyboardFrame: (UIView) -> CGRect
  private var keyboardHiding = false
  private var layoutUpdateScheduled = false
  private var observers: [NSObjectProtocol] = []
  private var requestedVisible = false
  private var requestedDark = false

  init(
    messenger: FlutterBinaryMessenger,
    notificationCenter: NotificationCenter = .default,
    hostViewProvider: (() -> UIView?)? = nil,
    keyboardFrame: @escaping (UIView) -> CGRect = { $0.keyboardLayoutGuide.layoutFrame }
  ) {
    self.notificationCenter = notificationCenter
    self.keyboardFrame = keyboardFrame
    self.hostViewProvider = hostViewProvider ?? Self.foregroundHostView
    channel = FlutterMethodChannel(
      name: "com.zcash.wallet/keyboard_toolbar", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update",
        let arguments = call.arguments as? [String: Any]
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(
        visible: arguments["visible"] as? Bool ?? false,
        dark: arguments["dark"] as? Bool ?? false
      )
      result(nil)
    }
    for name in [UIResponder.keyboardWillHideNotification,
                 UIResponder.keyboardDidHideNotification,
                 UIApplication.willResignActiveNotification] {
      observe(name) { handler, _ in
        handler.keyboardHiding = true
        handler.button?.isHidden = true
      }
    }
    for name in [UIResponder.keyboardWillShowNotification,
                 UIResponder.keyboardDidShowNotification,
                 UIResponder.keyboardDidChangeFrameNotification] {
      observe(name) { handler, notification in
        guard handler.belongsToHost(notification) else { return }
        handler.keyboardHiding = false
        handler.applyRequestedState()
      }
    }
    observe(UIResponder.keyboardWillChangeFrameNotification) { handler, notification in
      guard handler.belongsToHost(notification) else { return }
      handler.scheduleLayoutUpdate()
    }
    observe(UIApplication.didBecomeActiveNotification) { handler, _ in
      handler.keyboardHiding = false
      handler.applyRequestedState()
    }
  }

  private func observe(_ name: Notification.Name,
                       action: @escaping (KeyboardToolbarHandler, Notification) -> Void) {
    observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
      [weak self] notification in
      guard let self else { return }
      action(self, notification)
    })
  }

  private func belongsToHost(_ notification: Notification) -> Bool {
    if let local = notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool,
       !local { return false }
    if let screen = notification.object as? UIScreen,
       hostViewProvider()?.window?.screen !== screen { return false }
    return true
  }

  private func scheduleLayoutUpdate() {
    guard !layoutUpdateScheduled else { return }
    layoutUpdateScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.layoutUpdateScheduled = false
      self.applyRequestedState()
    }
  }

  deinit {
    observers.forEach(notificationCenter.removeObserver)
    button?.removeFromSuperview()
    layoutProbe?.removeFromSuperview()
  }

  private func update(visible: Bool, dark: Bool) {
    requestedVisible = visible
    requestedDark = dark
    applyRequestedState()
  }

  private func applyRequestedState() {
    guard requestedVisible, let view = hostViewProvider() else {
      button?.isHidden = true
      return
    }

    if host !== view {
      button?.removeFromSuperview()
      layoutProbe?.removeFromSuperview()
      // Its height follows the keyboard edge, so keyboard movement and window
      // resizing both re-evaluate visibility even without a Flutter update.
      let probe = KeyboardToolbarLayoutProbe()
      probe.onLayout = { [weak self] in self?.scheduleLayoutUpdate() }
      probe.translatesAutoresizingMaskIntoConstraints = false
      probe.isUserInteractionEnabled = false
      probe.accessibilityElementsHidden = true
      probe.isHidden = true
      view.addSubview(probe)
      NSLayoutConstraint.activate([
        probe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        probe.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        probe.topAnchor.constraint(equalTo: view.topAnchor),
        probe.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      ])
      layoutProbe = probe
      let control = UIButton(type: .system)
      var configuration: UIButton.Configuration
      if #available(iOS 26.0, *) {
        configuration = .glass()
      } else {
        configuration = .plain()
        configuration.background.visualEffect = UIBlurEffect(style: .systemMaterial)
      }
      configuration.cornerStyle = .capsule
      // Glass renders template symbols monochromatically, even with a
      // foreground transformer. Preserve the Figma blue in the image itself.
      let checkColor = UIColor(red: 0, green: 136.0 / 255.0, blue: 1, alpha: 1)
      configuration.image = UIImage(
        systemName: "checkmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
      )?.withTintColor(checkColor, renderingMode: .alwaysOriginal)
      control.configuration = configuration
      control.accessibilityLabel = "Done"
      control.accessibilityIdentifier = "mobile_keyboard_toolbar"
      control.translatesAutoresizingMaskIntoConstraints = false
      control.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
      view.addSubview(control)
      NSLayoutConstraint.activate([
        control.widthAnchor.constraint(equalToConstant: 48),
        control.heightAnchor.constraint(equalToConstant: 48),
        control.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -11),
        control.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
      ])
      host = view
      button = control
      view.layoutIfNeeded()
    }
    button?.overrideUserInterfaceStyle = requestedDark ? .dark : .light
    // The guide collapses to the bottom safe area when the keyboard is absent
    // or undocked. A cached Flutter inset/show request must not resurrect it.
    button?.isHidden = keyboardHiding || !Self.hasDockedKeyboard(
      keyboardFrame(view), bounds: view.bounds, safeArea: view.bounds.inset(by: view.safeAreaInsets)
    )
    if let button { view.bringSubviewToFront(button) }
  }

  static func hasDockedKeyboard(_ frame: CGRect, bounds: CGRect, safeArea: CGRect) -> Bool {
    guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }),
      !frame.isEmpty, !frame.isInfinite, !bounds.isEmpty else { return false }
    let intersection = frame.intersection(bounds)
    return !intersection.isNull && !intersection.isEmpty
      && intersection.minY < safeArea.maxY - 0.5
      && frame.maxY >= bounds.maxY - 0.5
  }

  @objc private func dismissKeyboard() {
    keyboardHiding = true
    requestedVisible = false
    button?.isHidden = true
    host?.endEditing(true)
    channel.invokeMethod("dismiss", arguments: nil)
  }

  private static func foregroundHostView() -> UIView? {
    UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .filter({ $0.activationState == .foregroundActive })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?
      .rootViewController?.view
  }
}

/// A zero-input layout observer, kept in the same host as the control.
private final class KeyboardToolbarLayoutProbe: UIView {
  var onLayout: (() -> Void)?
  override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
  override func didMoveToWindow() { super.didMoveToWindow(); onLayout?() }
}
