import Flutter
import Testing
import UIKit

@testable import Runner

@MainActor
struct NativeTabBarTests {
  @Test("Invalid snapshots preserve all previously displayed items and selection")
  func atomicSnapshotValidation() throws {
    let fixture = NativeTabBarFixture()
    let originalItems = try #require(fixture.bar.items)
    let originalSelection = fixture.bar.selectedItem

    var duplicate = fixture.snapshot(ids: ["home", "home"], selected: "home")
    #expect(fixture.update(duplicate) is FlutterError)
    #expect(fixture.bar.items?.first === originalItems.first)
    #expect(fixture.bar.selectedItem === originalSelection)

    duplicate = fixture.snapshot(selected: "missing")
    #expect(fixture.update(duplicate) is FlutterError)
    #expect(fixture.bar.selectedItem === originalSelection)

    var corrupt = fixture.snapshot()
    var items = try #require(corrupt["items"] as? [[String: Any]])
    items[0]["label"] = "Changed before a corrupt icon"
    items[1]["icon"] = FlutterStandardTypedData(bytes: Data([0, 1, 2]))
    corrupt["items"] = items
    #expect(fixture.update(corrupt) is FlutterError)
    #expect(fixture.bar.items?.first?.title == "home")
    #expect(fixture.bar.selectedItem === originalSelection)
  }

  @Test("Tab identities and decoded images survive label updates, filtering and reordering")
  func stableItemsAndImages() throws {
    let fixture = NativeTabBarFixture()
    let original = try #require(fixture.bar.items)
    let originalImage = try #require(original[2].image)
    #expect(fixture.update(fixture.snapshot(ids: ["settings", "home"], selected: "settings")) == nil)
    #expect(fixture.bar.items?[0] === original[2])
    #expect(fixture.bar.items?[1] === original[0])
    #expect(fixture.bar.selectedItem === original[2])
    #expect(fixture.bar.items?[0].image === originalImage)

    var translated = fixture.snapshot(ids: ["settings", "home"], selected: "settings")
    var items = try #require(translated["items"] as? [[String: Any]])
    items[0]["label"] = "설정"
    translated["items"] = items
    #expect(fixture.update(translated) == nil)
    #expect(fixture.bar.items?[0] === original[2])
    #expect(fixture.bar.items?[0].image === originalImage)
    #expect(fixture.bar.items?[0].title == "설정")
  }

  @Test("Only UIKit selection emits navigation, including re-selection")
  func selectionEvents() throws {
    let fixture = NativeTabBarFixture()
    #expect(fixture.update(fixture.snapshot(selected: "settings")) == nil)
    #expect(fixture.messenger.outgoing.isEmpty)
    let selected = try #require(fixture.bar.selectedItem)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    fixture.platformView?.tabBar(fixture.bar, didSelect: selected)
    #expect(fixture.messenger.outgoing.map(\.method) == ["select", "select"])
    #expect(fixture.messenger.outgoing.allSatisfy {
      ($0.arguments as? [String: String])?["id"] == "settings"
    })
    fixture.platformView?.tabBar(UITabBar(), didSelect: selected)
    fixture.platformView?.tabBar(fixture.bar, didSelect: UITabBarItem())
    #expect(fixture.messenger.outgoing.count == 2)
  }

  @Test("App theme, direction and hidden state update without replacing the bar")
  func environmentAndVisibility() throws {
    let fixture = NativeTabBarFixture()
    let originalItem = fixture.bar.items?.first
    var args = fixture.snapshot()
    args["brightness"] = "dark"
    args["direction"] = "rtl"
    args["hidden"] = true
    #expect(fixture.update(args) == nil)
    #expect(fixture.host.overrideUserInterfaceStyle == .dark)
    #expect(fixture.bar.effectiveUserInterfaceLayoutDirection == .rightToLeft)
    #expect(fixture.host.isHidden)
    #expect(!fixture.host.isUserInteractionEnabled)
    #expect(fixture.bar.items?.first === originalItem)
    #expect(fixture.host.preferredHeight > 0)
    args["hidden"] = false
    #expect(fixture.update(args) == nil)
    #expect(!fixture.host.isHidden)
    #expect(fixture.host.isUserInteractionEnabled)
  }

  @Test("Native appearance and template image rendering stay under UIKit control")
  func systemAppearance() throws {
    let fixture = NativeTabBarFixture()
    #expect(fixture.bar.backgroundImage == nil)
    #expect(fixture.bar.shadowImage == nil)
    #expect(fixture.bar.barTintColor == nil)
    let image = try #require(fixture.bar.items?.first?.image)
    #expect(image.renderingMode == .alwaysTemplate)
    #expect(image.size == CGSize(width: 25, height: 25))
    #expect(!fixture.host.clipsToBounds)
    #expect(fixture.host.hitTest(CGPoint(x: -1, y: -1), with: nil) == nil)
  }

  @Test("Layout notifications do not loop when Flutter accepts the native height")
  func heightNegotiation() async throws {
    let fixture = NativeTabBarFixture()
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    await drainMainQueue()
    let heightEvents = fixture.messenger.outgoing.filter { $0.method == "layout" }
    #expect(heightEvents.count == 1)
    let reported = try #require((heightEvents.first?.arguments as? [String: Double])?["height"])
    #expect(reported > 0)
    fixture.host.frame.size.height = reported
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    await drainMainQueue()
    #expect(fixture.messenger.outgoing.filter { $0.method == "layout" }.count == 1)
    #expect(fixture.messenger.call("getHeight") as? Double == reported)
  }

  @Test("Selected icons and titles share the app tint without changing native material")
  func selectedItemTint() throws {
    let fixture = NativeTabBarFixture()
    let item = try #require(fixture.bar.items?.first)
    let originalImage = try #require(item.image)
    let originalTint = fixture.bar.tintColor
    var args = fixture.snapshot()
    args["selectedTintColor"] = 0xFFA83861
    #expect(fixture.update(args) == nil)
    #expect(fixture.bar.tintColor == UIColor(
      red: 168.0 / 255, green: 56.0 / 255, blue: 97.0 / 255, alpha: 1
    ))
    #expect(item.image === originalImage)
    #expect(item.selectedImage?.renderingMode == .alwaysTemplate)
    #expect(item.image?.renderingMode == .alwaysTemplate)
    #expect(fixture.bar.unselectedItemTintColor == nil)
    #expect(fixture.bar.backgroundImage == nil)
    #expect(fixture.bar.shadowImage == nil)
    #expect(fixture.bar.barTintColor == nil)

    args["selectedId"] = "settings"
    #expect(fixture.update(args) == nil)
    #expect(item.image === originalImage)
    args["selectedTintColor"] = 0xFF123456
    #expect(fixture.update(args) == nil)
    #expect(fixture.bar.tintColor == UIColor(
      red: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1
    ))
    args.removeValue(forKey: "selectedTintColor")
    #expect(fixture.update(args) == nil)
    #expect(fixture.bar.tintColor == originalTint)
  }

  @Test("Malformed selected tints preserve the existing native color")
  func invalidSelectedTint() throws {
    let fixture = NativeTabBarFixture()
    var args = fixture.snapshot()
    args["selectedTintColor"] = 0xFFA83861
    #expect(fixture.update(args) == nil)
    let tint = fixture.bar.tintColor
    for invalid: Any in [-1, 0x1_0000_0000, 1.5, true, "red"] {
      args["selectedTintColor"] = invalid
      #expect(fixture.update(args) is FlutterError)
      #expect(fixture.bar.tintColor == tint)
    }
  }

  @Test("Platform-view destruction removes the channel and pending callback owner")
  func disposal() {
    let fixture = NativeTabBarFixture()
    #expect(fixture.messenger.hasHandler)
    fixture.host.setNeedsLayout()
    fixture.host.layoutIfNeeded()
    fixture.platformView = nil
    #expect(!fixture.messenger.hasHandler)
    #expect(fixture.host.tabBar.delegate == nil)
    #expect(fixture.host.onHeightChanged == nil)
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}

@MainActor
private final class NativeTabBarFixture {
  let messenger = NativeTabBarMessenger()
  private let png: Data
  var platformView: NativeTabBarPlatformView?
  let host: NativeTabBarHostView
  var bar: UITabBar { host.tabBar }

  init() {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    png = UIGraphicsImageRenderer(size: CGSize(width: 25, height: 25), format: format)
      .pngData { context in
        UIColor.black.setFill()
        context.fill(CGRect(x: 2, y: 2, width: 21, height: 21))
      }
    let args = Self.snapshot(png: png, ids: ["home", "activity", "settings"], selected: "home")
    let platformView = NativeTabBarPlatformView(
      frame: CGRect(x: 0, y: 0, width: 393, height: 100),
      viewId: 1, args: args, messenger: messenger
    )
    self.platformView = platformView
    host = platformView.view() as! NativeTabBarHostView
  }

  func snapshot(ids: [String] = ["home", "activity", "settings"], selected: String = "home")
    -> [String: Any]
  {
    Self.snapshot(png: png, ids: ids, selected: selected)
  }

  func update(_ args: [String: Any]) -> Any? {
    messenger.call("update", arguments: args)
  }

  private static func snapshot(png: Data, ids: [String], selected: String) -> [String: Any] {
    [
      "items": ids.map {
        ["id": $0, "label": $0, "icon": FlutterStandardTypedData(bytes: png), "iconScale": 3]
      },
      "selectedId": selected,
      "brightness": "light",
      "direction": "ltr",
    ]
  }
}

private final class NativeTabBarMessenger: NSObject, FlutterBinaryMessenger {
  private let codec = FlutterStandardMethodCodec.sharedInstance()
  private var handler: FlutterBinaryMessageHandler?
  var outgoing: [FlutterMethodCall] = []
  var hasHandler: Bool { handler != nil }

  func call(_ method: String, arguments: Any? = nil) -> Any? {
    var result: Any?
    handler?(codec.encode(FlutterMethodCall(methodName: method, arguments: arguments))) { reply in
      if let reply { result = self.codec.decodeEnvelope(reply) }
    }
    return result
  }

  func send(onChannel channel: String, message: Data?) {
    if let message { outgoing.append(codec.decodeMethodCall(message)) }
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    self.handler = handler
    return 1
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    handler = nil
  }
}
