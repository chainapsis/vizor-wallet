import Flutter
import Testing
import UIKit

@testable import Runner

@MainActor
struct KeyboardToolbarHandlerTests {
  @Test("A Flutter request cannot show a control without a docked keyboard")
  func requestWithoutKeyboard() {
    let fixture = KeyboardToolbarFixture(keyboardPresent: false)
    fixture.view.layoutIfNeeded()
    fixture.messenger.update(visible: true)
    #expect(fixture.button?.isHidden != false)
  }

  @Test("A stale Flutter request after native hide cannot restore a bottom checkmark")
  func staleRequestAfterHide() {
    let fixture = KeyboardToolbarFixture()
    fixture.messenger.update(visible: true)
    fixture.notifications.post(name: UIResponder.keyboardWillHideNotification, object: nil)
    fixture.messenger.update(visible: true, dark: true)
    #expect(fixture.button?.isHidden != false)
  }

  @Test("A late show or frame notification cannot display a keyboardless control")
  func staleShowAfterGeometryCollapses() throws {
    let fixture = KeyboardToolbarFixture()
    fixture.messenger.update(visible: true)
    let button = try #require(fixture.button)
    fixture.geometry.frame = .zero
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil)
    fixture.notifications.post(name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    #expect(button.isHidden)
  }

  @Test("Layout changes hide and restore the control without a notification or Flutter update")
  func guideLayoutChanges() async throws {
    let fixture = KeyboardToolbarFixture()
    fixture.messenger.update(visible: true)
    let button = try #require(fixture.button)
    fixture.geometry.frame = CGRect(x: 0, y: 852, width: 393, height: 0)
    fixture.layout()
    await fixture.drain()
    #expect(button.isHidden)
    fixture.geometry.frame = CGRect(x: 0, y: 552, width: 393, height: 300)
    fixture.layout()
    await fixture.drain()
    #expect(!button.isHidden)
  }

  @Test("Non-local keyboard notifications cannot restore a hidden control")
  func foreignKeyboard() throws {
    let fixture = KeyboardToolbarFixture()
    fixture.messenger.update(visible: true)
    let button = try #require(fixture.button)
    fixture.notifications.post(name: UIResponder.keyboardWillHideNotification, object: nil)
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil,
      userInfo: [UIResponder.keyboardIsLocalUserInfoKey: false])
    #expect(button.isHidden)
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil,
      userInfo: [UIResponder.keyboardIsLocalUserInfoKey: true])
    #expect(!button.isHidden)
  }

  @Test("Only a finite docked guide extending above the safe area represents a keyboard")
  func geometryPolicy() {
    let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
    let safe = CGRect(x: 0, y: 0, width: 867, height: 635)
    #expect(KeyboardToolbarHandler.hasDockedKeyboard(
      CGRect(x: 0, y: 405, width: 951, height: 264), bounds: bounds, safeArea: safe))
    for frame in [CGRect.zero, CGRect(x: 0, y: 635, width: 951, height: 34),
                  CGRect(x: 100, y: 300, width: 300, height: 200),
                  CGRect(x: 0, y: 700, width: 951, height: 200),
                  CGRect(x: 1000, y: 405, width: 300, height: 264), CGRect.infinite] {
      #expect(!KeyboardToolbarHandler.hasDockedKeyboard(frame, bounds: bounds, safeArea: safe))
    }
  }

  @Test("Keyboard replacement restores the control without another Flutter update")
  func keyboardReplacement() throws {
    let fixture = KeyboardToolbarFixture()
    fixture.messenger.update(visible: true, dark: true)
    let button = try #require(fixture.button)
    #expect(!button.isHidden)

    fixture.notifications.post(name: UIResponder.keyboardWillHideNotification, object: nil)
    #expect(button.isHidden)
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil)

    #expect(!button.isHidden)
    #expect(button.overrideUserInterfaceStyle == .dark)
    #expect(fixture.button === button)
  }

  @Test("Explicitly hidden controls stay hidden when a keyboard appears")
  func explicitHide() throws {
    let fixture = KeyboardToolbarFixture()
    fixture.messenger.update(visible: true)
    let button = try #require(fixture.button)
    fixture.messenger.update(visible: false)
    fixture.notifications.post(name: UIResponder.keyboardWillHideNotification, object: nil)
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil)
    #expect(button.isHidden)
  }

  @Test("A keyboard shown before Flutter's request does not create a control")
  func showBeforeRequest() throws {
    let fixture = KeyboardToolbarFixture()
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil)
    #expect(fixture.button == nil)
    fixture.messenger.update(visible: true)
    let button = try #require(fixture.button)
    #expect(!button.isHidden)
  }

  @Test("A delayed keyboard-show notification does not undo Done")
  func lateShowAfterDismissal() throws {
    let fixture = KeyboardToolbarFixture()
    fixture.messenger.update(visible: true)
    let button = try #require(fixture.button)
    button.sendActions(for: .touchUpInside)
    #expect(button.isHidden)
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil)
    #expect(button.isHidden)
    #expect(fixture.messenger.outgoingMethods == ["dismiss"])
  }

  @Test("An unavailable foreground host stays hidden until it returns")
  func unavailableHost() throws {
    var hostAvailable = true
    let fixture = KeyboardToolbarFixture(hostAvailable: { hostAvailable })
    fixture.messenger.update(visible: true)
    let button = try #require(fixture.button)
    hostAvailable = false
    fixture.notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil)
    #expect(button.isHidden)
    hostAvailable = true
    fixture.notifications.post(name: UIResponder.keyboardDidShowNotification, object: nil)
    #expect(!button.isHidden)
  }
}

@MainActor
private final class KeyboardToolbarFixture {
  let messenger = KeyboardToolbarMessenger()
  let notifications = NotificationCenter()
  let view = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
  private let handler: KeyboardToolbarHandler
  let geometry = KeyboardToolbarTestGeometry()

  init(keyboardPresent: Bool = true, hostAvailable: @escaping () -> Bool = { true }) {
    let view = self.view
    let geometry = self.geometry
    if !keyboardPresent { geometry.frame = .zero }
    handler = KeyboardToolbarHandler(
      messenger: messenger, notificationCenter: notifications,
      hostViewProvider: { hostAvailable() ? view : nil },
      keyboardFrame: { _ in geometry.frame }
    )
  }

  func layout() {
    view.subviews.filter { !($0 is UIButton) }.forEach { $0.setNeedsLayout(); $0.layoutIfNeeded() }
  }
  func drain() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  var button: UIButton? {
    view.subviews.compactMap { $0 as? UIButton }.first {
      $0.accessibilityIdentifier == "mobile_keyboard_toolbar"
    }
  }
}

private final class KeyboardToolbarTestGeometry {
  var frame = CGRect(x: 0, y: 552, width: 393, height: 300)
}

private final class KeyboardToolbarMessenger: NSObject, FlutterBinaryMessenger {
  private var handler: FlutterBinaryMessageHandler?
  private let codec = FlutterStandardMethodCodec.sharedInstance()
  var outgoingMethods: [String] = []

  func update(visible: Bool, dark: Bool = false) {
    let call = FlutterMethodCall(methodName: "update", arguments: ["visible": visible, "dark": dark])
    handler?(codec.encode(call), { _ in })
  }

  func send(onChannel channel: String, message: Data?) {
    if let message { outgoingMethods.append(codec.decodeMethodCall(message).method) }
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
