import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // A zcash: link that cold-starts Vizor arrives in the connection options'
    // URL contexts. FlutterDeepLinkingEnabled is false, so super does not also
    // route it; the payment-URI channel is the sole handler.
    PaymentUriChannelBridge.shared.handle(urlContexts: connectionOptions.urlContexts)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    PaymentUriChannelBridge.shared.handle(urlContexts: URLContexts)
    // Forward anything we did not consume (non-zcash) to Flutter and plugins.
    let remaining = URLContexts.filter { $0.url.scheme?.lowercased() != "zcash" }
    if !remaining.isEmpty {
      super.scene(scene, openURLContexts: Set(remaining))
    }
  }
}
