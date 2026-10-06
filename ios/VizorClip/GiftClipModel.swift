import Foundation

/// Receives the App Clip invocation URL and hands a Gift Card link to the
/// full app through `AppClipGiftHandoff`. Never logs the URL: it is a bearer
/// secret. SwiftUI delivers the invocation on the main thread.
final class GiftClipModel: ObservableObject {
  enum State: Equatable {
    /// Launched without an invocation URL, for example from the App Library.
    case waiting
    /// A Gift Card link. `saved` is false when the keychain write failed, so
    /// the full app will not open the gift on its own.
    case gift(GiftLinkPreview, saved: Bool)
    /// The invocation URL is not a Gift Card link Vizor can open.
    case invalid
  }

  @Published private(set) var state: State = .waiting

  static let deeplinkHost =
    (Bundle.main.object(forInfoDictionaryKey: "VizorDeeplinkHost") as? String)?
    .lowercased() ?? "link.vizor.cash"

  func receive(_ url: URL?) {
    guard let url else { return }
    guard AppClipGiftHandoff.isGiftLink(url, host: Self.deeplinkHost) else {
      state = .invalid
      return
    }
    let saved = AppClipGiftHandoff.save(url)
    state = .gift(GiftLinkPreview(url: url), saved: saved)
  }
}
