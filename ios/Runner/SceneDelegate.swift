import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    IncomingUriChannelBridge.shared.handle(
      urlContexts: connectionOptions.urlContexts
    )
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    IncomingUriChannelBridge.shared.handle(urlContexts: URLContexts)
    let remaining = URLContexts.filter {
      !($0.url.scheme?.lowercased() == "vizor" &&
        $0.url.host?.lowercased() == "payment-link")
    }
    if !remaining.isEmpty {
      super.scene(scene, openURLContexts: Set(remaining))
    }
  }
}
