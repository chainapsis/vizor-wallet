import Flutter
import UIKit

/// A UIKit control above the system keyboard; Flutter owns editable-field focus.
final class KeyboardToolbarHandler {
  private let channel: FlutterMethodChannel
  private let notificationCenter: NotificationCenter
  private let hostViewProvider: () -> UIView?
  private weak var host: UIView?
  private var button: UIButton?
  private var observers: [NSObjectProtocol] = []
  private var requestedVisible = false
  private var requestedDark = false

  init(
    messenger: FlutterBinaryMessenger,
    notificationCenter: NotificationCenter = .default,
    hostViewProvider: (() -> UIView?)? = nil
  ) {
    self.notificationCenter = notificationCenter
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
                 UIApplication.willResignActiveNotification] {
      observers.append(notificationCenter.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        self?.button?.isHidden = true
      })
    }
    observers.append(notificationCenter.addObserver(
      forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main
    ) { [weak self] _ in
      // Keyboard replacement can hide the control while Flutter's insets and
      // cached visibility stay unchanged. Restore its last requested state.
      self?.applyRequestedState()
    })
  }

  deinit {
    observers.forEach(notificationCenter.removeObserver)
    button?.removeFromSuperview()
  }

  private func update(visible: Bool, dark: Bool) {
    requestedVisible = visible
    requestedDark = dark
    applyRequestedState()
  }

  private func applyRequestedState() {
    guard requestedVisible else {
      button?.isHidden = true
      return
    }
    guard let view = hostViewProvider() else { return }

    if host !== view {
      button?.removeFromSuperview()
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
    }
    button?.overrideUserInterfaceStyle = requestedDark ? .dark : .light
    button?.isHidden = false
    if let button { view.bringSubviewToFront(button) }
  }

  @objc private func dismissKeyboard() {
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
