import Flutter
import Testing
import UIKit

@testable import Runner

@MainActor
struct KeyboardToolbarHandlerTests {
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

  init(hostAvailable: @escaping () -> Bool = { true }) {
    let view = self.view
    handler = KeyboardToolbarHandler(
      messenger: messenger, notificationCenter: notifications,
      hostViewProvider: { hostAvailable() ? view : nil }
    )
  }

  var button: UIButton? {
    view.subviews.compactMap { $0 as? UIButton }.first {
      $0.accessibilityIdentifier == "mobile_keyboard_toolbar"
    }
  }
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
