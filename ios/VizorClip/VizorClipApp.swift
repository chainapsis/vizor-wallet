import SwiftUI

@main
struct VizorClipApp: App {
  @StateObject private var model = GiftClipModel()

  var body: some Scene {
    WindowGroup {
      GiftClipView(model: model)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          model.receive(activity.webpageURL)
        }
    }
  }
}
