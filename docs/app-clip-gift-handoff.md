# iOS App Clip gift handoff

A person who receives a Gift Card link but has not installed Vizor can tap the
link, see the gift in an App Clip, and install Vizor from the system install
sheet. When they open Vizor for the first time, the same gift opens without
returning to the link.

## Flow

1. The person taps `https://link.vizor.cash/payment-links/open#v3=...` on an
   iPhone without Vizor. iOS shows the App Clip card (Messages, Safari, or the
   gateway page's Smart App Banner card).
2. `VizorClip` receives the invocation URL through
   `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`.
3. `AppClipGiftHandoff.isGiftLink` checks the shape (host, path, no query,
   `#v1=`/`#v2=`/`#v3=` fragment, at most 16 KiB). The App Clip saves the link
   in the keychain and shows the amount, USD snapshot, and message decoded by
   `GiftLinkPreview`. It makes no network requests.
4. "Get Vizor to claim" presents `SKOverlay.AppClipConfiguration`, the system
   install sheet.
5. On Vizor's first user-visible launch, `SceneDelegate` calls
   `IncomingUriChannelBridge.handlePendingAppClipGift()`. It reads and deletes
   the keychain item once per install and queues the link exactly like an
   incoming universal link.
6. Dart's existing intake routes it: no wallet on Welcome opens `/gift` after
   the network sheet; every other state follows `payment_link_entry_policy`.

If Vizor is already installed, the universal link opens Vizor directly and the
App Clip is not involved.

## Components

| Path | Role |
| --- | --- |
| `ios/VizorClip/` | App Clip sources, `Info.plist`, and icon (synchronized folder) |
| `ios/VizorClip.entitlements` | `appclips:` domain, parent app identifier, on-demand install |
| `ios/Shared/AppClipGiftHandoff.swift` | Link shape check and keychain save/consume, compiled into both targets |
| `ios/Shared/GiftLinkPreview.swift` | Display-only amount and message decoding, compiled into both targets |
| `ios/Flutter/DeeplinkHost.xcconfig` | The one `VIZOR_DEEPLINK_HOST` value for both targets |
| `ios/Flutter/VizorClip.xcconfig` | App Clip base config; takes the version from `Generated.xcconfig` |
| `ios/Runner/Runner.entitlements` | Adds `associated-appclip-app-identifiers` for keychain access |
| `ios/RunnerTests/AppClipGiftHandoffTests.swift` | Shape, keychain, once-per-install, and preview tests |

The gateway (`vizor-deeplink-server`) publishes the `appclips` section of the
apple-app-site-association file and the `apple-itunes-app` meta tag with
`app-clip-bundle-id` and `app-clip-display=card` on the Gift Card page.

## Security

- The link is a bearer secret. It lives only in the URL fragment, the App
  Clip's memory, and one keychain item
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronized). It is
  never logged, written to the app group, or sent anywhere.
- App Clips cannot use `keychain-access-groups`, so the item uses the default
  access group. On iOS 15.4 and later the full app can read keychain items its
  App Clip created, granted by `parent-application-identifiers` and
  `associated-appclip-app-identifiers`.
- The full app deletes the item when it reads it, and checks only once per
  install (`vizor.appClipGiftHandoffChecked` in `UserDefaults`), so a failed
  delete cannot reopen the same gift on every launch. Keychain items outlive an
  uninstall, so if that delete ever failed, a later reinstall would open the
  gift once more; Dart then shows its normal claimed or unclaimed state.
- The App Clip's preview is not a validator. Dart's `VizorPaymentLink.parse`
  and the claim wallet decide whether a gift can be claimed.

## Release setup

These steps happen outside the repository and must be done before a release
build containing the App Clip:

1. In Certificates, Identifiers & Profiles, register the App ID
   `com.keplr.vizor.Clip` as an App Clip of `com.keplr.vizor`, with Associated
   Domains enabled.
2. Run fastlane `match` once without `MATCH_READONLY` so the App Store profile
   for `com.keplr.vizor.Clip` is created and the `com.keplr.vizor` profile is
   regenerated with the App Clip association. `fastlane/ios/Fastfile` already
   lists the new bundle identifier and the `VizorClip` target.
3. Deploy the gateway change so the AASA file lists the App Clip under
   `appclips` and the Gift Card page carries the App Clip meta tag.
4. In App Store Connect, after uploading a build with the App Clip, configure
   the default App Clip experience (header image, subtitle, "Open" action) and
   an advanced experience for `https://link.vizor.cash/payment-links/open`.
   Reuse the gateway's Gift Card share image for the card.

## Testing

- Unit tests: `RunnerTests/AppClipGiftHandoffTests.swift` runs with the
  existing RunnerTests target in Xcode.
- App Clip UI: run the shared `VizorClip` scheme. It sets `_XCAppClipURL` to
  the unfunded synthetic link from `docs/compact-gift-links.md`, so the App
  Clip launches as if invoked from that link.
- Handoff: run the `VizorClip` scheme on a device or simulator without Vizor,
  then run the `Runner` scheme. Vizor's first launch should open the same gift
  on `/gift`.
- Real invocations: on a device, use Settings > Developer > App Clips Testing >
  Local Experiences with the `link-dev.vizor.cash` prefix, or TestFlight App
  Clip invocations after upload.

## Open questions to verify on device

- Whether the invocation URL keeps the `#v3=` fragment when the App Clip is
  launched from the Smart App Banner card in Safari and from Messages. If iOS
  drops it, the App Clip shows "This gift link can't be opened", and the link
  cannot move to the query or path because the gateway would then see the
  secret.
- In-app browsers (Telegram, WhatsApp, and others) usually show the web page
  instead of the App Clip card. The page's "Get Vizor" and "Copy gift link"
  fallback remains the path there.
