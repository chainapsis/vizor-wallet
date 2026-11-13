import Flutter
import Testing
import UIKit

@testable import Runner

@MainActor
struct NativeSideTabBarTests {
  @Test("Placement and layout acknowledgements are strictly validated")
  func snapshotValidation() throws {
    for value in ["diagonal", 1, NSNull()] as [Any] {
      var args = sideSnapshot()
      args["placement"] = value
      #expect(throws: NativeTabBarError.self) { try NativeTabBarSnapshot(arguments: args) }
    }
    for value in [-1, 1.5, true, "1"] as [Any] {
      var args = sideSnapshot()
      args["layoutRevision"] = value
      #expect(throws: NativeTabBarError.self) { try NativeTabBarSnapshot(arguments: args) }
    }
    #expect(try NativeTabBarSnapshot(arguments: sideSnapshot()).placement == "right")
  }

  @Test("Invalid side updates preserve the last selection and epoch")
  func atomicUpdate() throws {
    let messages = SideTabMessenger()
    let view = NativeSideTabBarPlatformView(frame: .zero, viewId: 1,
      args: sideSnapshot(), messenger: messages, owner: { nil })
    let initial = messages.call("getPresentation") as? [String: Any]
    var invalid = sideSnapshot()
    invalid["items"] = [["id": "/settings", "label": "Settings", "iconName": "missing"]]
    invalid["selectedId"] = "/settings"
    invalid["visibilityEpoch"] = 10
    #expect(messages.call("update", arguments: invalid) is FlutterError)
    #expect((messages.call("getPresentation") as? [String: Any])?["visibilityEpoch"] as? Int == initial?["visibilityEpoch"] as? Int)
    #expect(view.view().isUserInteractionEnabled == false)
    #expect(messages.outgoing.allSatisfy { $0.method != "select" })
  }

  @Test("A side view without an attached owner never becomes interactive")
  func missingOwnerAndStaleUpdate() {
    let messages = SideTabMessenger()
    let view = NativeSideTabBarPlatformView(frame: CGRect(x: 0, y: 0, width: 466, height: 678),
      viewId: 1, args: sideSnapshot(), messenger: messages, owner: { nil })
    var next = sideSnapshot()
    next["hidden"] = false
    next["inputEnabled"] = true
    next["layoutReady"] = true
    next["visibilityEpoch"] = 2
    #expect(messages.call("update", arguments: next) == nil)
    #expect(messages.call("update", arguments: sideSnapshot()) is FlutterError)
    let status = messages.call("getPresentation") as? [String: Any]
    #expect(status?["interactive"] as? Bool == false)
    #expect(status?["visibilityEpoch"] as? Int == 2)
    #expect(view.view().isUserInteractionEnabled == false)
  }
}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.contains("Duo") == true))
struct NativeSideTabBarDuoTests {
  @Test("A real vertical controller requires the current layout acknowledgement and detaches on disposal")
  func layoutAndLifetime() async throws {
    let fixture = try SideTabFixture()
    defer { fixture.close() }
    await fixture.drain()
    let layout = try #require(fixture.layout)
    let revision = try #require(layout["layoutRevision"] as? Int)
    #expect(revision > 0)
    #expect(fixture.root.children.count == 1)
    var args = fixture.args
    args["hidden"] = false
    args["inputEnabled"] = true
    args["layoutReady"] = true
    args["visibilityEpoch"] = 1
    args["layoutRevision"] = revision - 1
    #expect(fixture.messages.call("update", arguments: args) == nil)
    await fixture.drain()
    #expect(fixture.status["interactive"] as? Bool == false)
    args["visibilityEpoch"] = 2
    args["layoutRevision"] = revision
    #expect(fixture.messages.call("update", arguments: args) == nil)
    await fixture.drain()
    #expect(fixture.status["interactive"] as? Bool == true)
    let rect = try #require(layout["hitRect"] as? [String: Double])
    #expect(try #require(rect["x"]) >= fixture.window.bounds.midX)
    fixture.platform = nil
    #expect(fixture.root.children.isEmpty)
    #expect(!fixture.messages.hasHandler)
  }

  @Test("Side tabs keep touch-down feedback and preserve selection while hidden")
  func selectionFeedbackAndHiddenState() async throws {
    let fixture = try SideTabFixture()
    defer { fixture.close() }
    await fixture.show()
    let controller = try #require(fixture.root.children.first as? UITabBarController)
    let bar = controller.tabBar
    let observer = try #require(controller.view.gestureRecognizers?.compactMap { $0 as? NativeTabBarPressObserver }.first)
    let rect = try #require(fixture.layout?["hitRect"] as? [String: Double])
    let point = CGPoint(x: try #require(rect["x"]) + 20, y: fixture.window.bounds.height - 50)
    let target = try #require(fixture.platform?.view().hitTest(point, with: nil))
    let touch = SideTabTouch(target: target, point: point, host: try #require(fixture.platform?.view()))
    observer.touchesBegan([touch], with: UIEvent())
    #expect(fixture.feedback.impacts == 1)
    observer.touchesEnded([touch], with: UIEvent())
    let settings = try #require(controller.viewControllers?.last)
    controller.selectedViewController = settings
    controller.delegate?.tabBarController?(controller, didSelect: settings)
    #expect(fixture.messages.outgoing.filter { $0.method == "select" }.count == 1)
    #expect(fixture.feedback.impacts == 1)
    var hidden = fixture.readyArgs
    hidden["visibilityEpoch"] = 3
    hidden["hidden"] = true
    hidden["selectedId"] = "/home"
    #expect(fixture.messages.call("update", arguments: hidden) == nil)
    #expect(controller.selectedViewController === settings)
    #expect(fixture.status["settledHidden"] as? Bool == true)
    #expect(!observer.isEnabled)
    var shown = hidden
    shown["visibilityEpoch"] = 4
    shown["showRequestId"] = 1
    shown["hidden"] = false
    #expect(fixture.messages.call("update", arguments: shown) == nil)
    await fixture.drain()
    #expect(controller.selectedViewController === controller.viewControllers?.first)
    #expect(fixture.status["interactive"] as? Bool == true)
  }

  @Test("Right-side enter and exit move rendered contents horizontally without moving the native bar frame")
  func horizontalAnimation() async throws {
    let fixture = try SideTabFixture(reducedMotion: false)
    defer { fixture.close() }
    await fixture.show()
    let controller = try #require(fixture.root.children.first as? UITabBarController)
    let bar = controller.tabBar
    let frame = bar.frame
    let entrance = try #require(controller.view.layer.animation(forKey: "vizor.sideTabSlide") as? CABasicAnimation)
    #expect(try #require(entrance.fromValue as? NSValue).caTransform3DValue.m41 > 0)
    #expect(try #require(entrance.toValue as? NSValue).caTransform3DValue.m41 == 0)
    #expect(fixture.status["interactive"] as? Bool == false)
    try await Task.sleep(nanoseconds: 250_000_000)
    #expect(fixture.status["interactive"] as? Bool == true)
    var hidden = fixture.readyArgs
    hidden["visibilityEpoch"] = 3
    hidden["hidden"] = true
    #expect(fixture.messages.call("update", arguments: hidden) == nil)
    let exit = try #require(controller.view.layer.animation(forKey: "vizor.sideTabSlide") as? CABasicAnimation)
    #expect(try #require(exit.toValue as? NSValue).caTransform3DValue.m41 > 0)
    #expect(try #require(exit.toValue as? NSValue).caTransform3DValue.m42 == 0)
    #expect(bar.frame == frame)
    #expect(fixture.status["interactive"] as? Bool == false)
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(fixture.status["settledHidden"] as? Bool == true)
  }
}

private func sideSnapshot() -> [String: Any] {
  ["items": [["id": "/home", "label": "Home", "iconName": "home"],
             ["id": "/settings", "label": "Settings", "iconName": "cog"]],
   "selectedId": "/home", "brightness": "light", "direction": "ltr",
   "placement": "right", "hidden": true, "inputEnabled": false,
   "layoutReady": false, "visibilityEpoch": 0, "showRequestId": 0, "layoutRevision": 0]
}

@MainActor
private final class SideTabFixture {
  let messages = SideTabMessenger()
  let feedback = SideTabFeedback()
  let window: UIWindow
  let root = UIViewController()
  weak var previous: UIWindow?
  var platform: NativeSideTabBarPlatformView?
  var args = sideSnapshot()
  var layout: [String: Any]? { messages.call("getLayout") as? [String: Any] }
  var status: [String: Any] { messages.call("getPresentation") as? [String: Any] ?? [:] }
  var readyArgs: [String: Any] {
    var next = args
    next["hidden"] = false; next["inputEnabled"] = true; next["layoutReady"] = true
    next["layoutRevision"] = layout?["layoutRevision"]
    next["visibilityEpoch"] = 2
    return next
  }
  init(reducedMotion: Bool = true) throws {
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    previous = scene.windows.first { $0.isKeyWindow }
    window = UIWindow(windowScene: scene)
    window.rootViewController = root
    window.makeKeyAndVisible()
    root.view.layoutIfNeeded()
    platform = NativeSideTabBarPlatformView(frame: root.view.bounds, viewId: 1,
      args: args, messenger: messages, owner: { [weak root] in root },
      feedback: feedback, reduceMotion: { reducedMotion })
    root.view.addSubview(try #require(platform).view())
    root.view.layoutIfNeeded()
  }
  func drain() async {
    for _ in 0..<8 {
      await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
  }
  func show() async {
    await drain()
    _ = messages.call("update", arguments: readyArgs)
    await drain()
  }
  func close() {
    platform = nil
    window.isHidden = true
    previous?.makeKeyAndVisible()
  }
}

private final class SideTabFeedback: NativeTabBarPressFeedback {
  var impacts = 0
  func prepare() {}
  func impactOccurred() { impacts += 1 }
}
private final class SideTabTouch: UITouch {
  let target: UIView
  let point: CGPoint
  let host: UIView
  init(target: UIView, point: CGPoint, host: UIView) {
    self.target = target; self.point = point; self.host = host; super.init()
  }
  override func location(in view: UIView?) -> CGPoint { host.convert(point, to: view) }
  override var view: UIView? { target }
  override var type: UITouch.TouchType { .direct }
}
private final class SideTabMessenger: NSObject, FlutterBinaryMessenger {
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
    send(onChannel: channel, message: message); callback?(nil)
  }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    self.handler = handler; return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler = nil }
}
