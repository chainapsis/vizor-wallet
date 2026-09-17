import Flutter
import UIKit

/// A UIKit control above the system keyboard; Flutter owns numeric-field focus.
final class NumericKeyboardHandler {
  private let channel: FlutterMethodChannel
  private weak var host: UIView?
  private var button: UIButton?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.zcash.wallet/numeric_keyboard", binaryMessenger: messenger
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
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        self?.button?.isHidden = true
      })
    }
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    button?.removeFromSuperview()
  }

  private func update(visible: Bool, dark: Bool) {
    guard visible else {
      button?.isHidden = true
      return
    }
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .filter({ $0.activationState == .foregroundActive })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
      let view = window.rootViewController?.view
    else { return }

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
      // Figma 7819:24603: SF Pro Semibold checkmark, 19pt.
      configuration.image = UIImage(
        systemName: "checkmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
      )
      configuration.baseForegroundColor = UIColor(red: 0, green: 136.0 / 255.0, blue: 1, alpha: 1)
      control.configuration = configuration
      control.accessibilityLabel = "Done"
      control.accessibilityIdentifier = "mobile_numeric_keyboard_toolbar"
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
    button?.overrideUserInterfaceStyle = dark ? .dark : .light
    button?.isHidden = false
    if let button { view.bringSubviewToFront(button) }
  }

  @objc private func dismissKeyboard() {
    button?.isHidden = true
    host?.endEditing(true)
    channel.invokeMethod("dismiss", arguments: nil)
  }
}
