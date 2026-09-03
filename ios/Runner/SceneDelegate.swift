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
    for userActivity in connectionOptions.userActivities {
      _ = IncomingUriChannelBridge.shared.handle(userActivity: userActivity)
    }
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
