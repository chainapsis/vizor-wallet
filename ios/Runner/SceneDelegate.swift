import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyOverlay: AppPrivacyOverlay?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let windowScene = scene as? UIWindowScene {
      privacyOverlay = AppPrivacyOverlay(windows: { [weak windowScene] in
        windowScene?.windows ?? []
      })
      if scene.activationState != .foregroundActive {
        privacyOverlay?.show()
      }
    }
    IncomingUriChannelBridge.shared.handle(
      urlContexts: connectionOptions.urlContexts
    )
    for userActivity in connectionOptions.userActivities {
      _ = IncomingUriChannelBridge.shared.handle(userActivity: userActivity)
    }
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    privacyOverlay?.show()
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    // Re-enumerate windows: a sheet or keyboard window may have appeared
    // since willResignActive. UIKit takes its snapshot after this callback.
    privacyOverlay?.show()
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyOverlay?.hide()
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    privacyOverlay?.hide()
    privacyOverlay = nil
    super.sceneDidDisconnect(scene)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    IncomingUriChannelBridge.shared.handle(urlContexts: URLContexts)
    let remaining = URLContexts.filter {
      !IncomingUriChannelBridge.shared.handles($0.url)
    }
    if !remaining.isEmpty {
      super.scene(scene, openURLContexts: Set(remaining))
    }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if IncomingUriChannelBridge.shared.handle(userActivity: userActivity) {
      return
    }
    super.scene(scene, continue: userActivity)
  }
}

/// Shared with the method channel, independently of capture exclusion.
final class AppBackgroundPrivacyPolicy {
  static let shared = AppBackgroundPrivacyPolicy()
  static let changed = Notification.Name("VizorAppBackgroundPrivacyChanged")
  private var solidBackground = true
  private var captureSensitive = false
  var isSolid: Bool { solidBackground || captureSensitive }

  func setSolidBackground(_ solid: Bool) {
    solidBackground = solid
    NotificationCenter.default.post(name: Self.changed, object: self)
  }

  func setCaptureSensitive(_ visible: Bool) {
    captureSensitive = visible
    NotificationCenter.default.post(name: Self.changed, object: self)
  }
}

/// A native app-switcher cover. It never changes screenshot exclusion
/// (SecureScreenshotShield owns that policy for sensitive screens only).
/// Kept with SceneDelegate so every Runner build includes the lifecycle owner.
final class AppPrivacyOverlay {
  private let windows: () -> [UIWindow]
  private var covers: [ObjectIdentifier: UIView] = [:]
  private let isSolid: () -> Bool
  private var solidLatched = false
  private var policyObserver: NSObjectProtocol?

  init(
    windows: @escaping () -> [UIWindow],
    isSolid: @escaping () -> Bool = { AppBackgroundPrivacyPolicy.shared.isSolid }
  ) {
    self.windows = windows
    self.isSolid = isSolid
    policyObserver = NotificationCenter.default.addObserver(
      forName: AppBackgroundPrivacyPolicy.changed, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self, !self.covers.isEmpty, self.isSolid() else { return }
      self.show()
    }
  }

  deinit {
    if let policyObserver { NotificationCenter.default.removeObserver(policyObserver) }
    covers.values.forEach { $0.removeFromSuperview() }
  }

  func show() {
    solidLatched = solidLatched || isSolid()
    UIView.performWithoutAnimation {
      for window in windows() {
        let key = ObjectIdentifier(window)
        if let oldCover = covers[key],
          (oldCover.tag == 1) != solidLatched
        {
          oldCover.removeFromSuperview()
          covers.removeValue(forKey: key)
        }
        let cover = covers[key] ?? makeCover(solid: solidLatched)
        cover.frame = window.bounds
        if cover.superview !== window {
          window.addSubview(cover)
        }
        window.bringSubviewToFront(cover)
        cover.layoutIfNeeded()
        covers[key] = cover
      }
    }
  }

  func hide() {
    covers.values.forEach { $0.removeFromSuperview() }
    covers.removeAll()
    solidLatched = false
  }

  private func makeCover(solid: Bool) -> UIView {
    let cover = UIView()
    cover.tag = solid ? 1 : 0
    let fill = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 20 / 255, green: 24 / 255, blue: 24 / 255, alpha: 1)
        : .white
    }
    cover.backgroundColor = solid ? fill : .clear
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    if !solid {
      let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      blur.frame = cover.bounds
      blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.addSubview(blur)
      let tint = UIView(frame: cover.bounds)
      tint.backgroundColor = fill.withAlphaComponent(0.35)
      tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.addSubview(tint)
    }
    cover.isAccessibilityElement = true
    cover.accessibilityLabel = "Sensitive content hidden"
    cover.accessibilityViewIsModal = true
    let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
    lock.tintColor = .label
    lock.contentMode = .scaleAspectFit
    lock.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(lock)
    NSLayoutConstraint.activate([
      lock.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      lock.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      lock.widthAnchor.constraint(equalToConstant: 50),
      lock.heightAnchor.constraint(equalToConstant: 50),
    ])
    return cover
  }
}
